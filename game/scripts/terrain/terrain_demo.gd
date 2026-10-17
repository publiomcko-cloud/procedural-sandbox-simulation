extends Node3D

const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const SpatialGrid := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const BrushEditState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const BrushPicker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const BRUSH_RADIUS := 1.25
const CENTER_REGION := Vector2i.ZERO

@onready var terrain_chunks_root: Node3D = $TerrainChunks
@onready var terrain_mesh_template: MeshInstance3D = $TerrainChunks/Terrain
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $CanvasLayer/Status

var cave_section_enabled := false
var orbit_target := Vector3(8.0, 3.1, 6.0)
var orbit_offset := Vector3(34.0, 24.0, 40.0)
var orbit_dragging := false
var world_states: Dictionary = {}
var world_state: RefCounted
var chunk_nodes: Dictionary = {}
var selected_brush_mode: int = BrushEditState.Mode.CARVE
var last_brush_result := "Ready"
var last_mesh_diagnostics: Dictionary = {}


func _ready() -> void:
	_initialize_region_states()
	_create_chunk_nodes()
	_update_camera()
	_rebuild_all_chunks("initial")
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbit_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			selected_brush_mode = BrushEditState.Mode.FILL if event.shift_pressed else BrushEditState.Mode.CARVE
			_apply_brush_at(event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_orbit_distance(orbit_offset.length() * 0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_orbit_distance(orbit_offset.length() * 1.1)
	elif event is InputEventMouseMotion and orbit_dragging:
		orbit_offset = orbit_offset.rotated(Vector3.UP, -event.relative.x * 0.006)
		orbit_offset.y = clampf(orbit_offset.y - event.relative.y * 0.05, 2.0, 36.0)
		_update_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			cave_section_enabled = not cave_section_enabled
			_rebuild_all_chunks("cave_section")
			_update_status()
		elif event.keycode == KEY_R:
			_rebuild_all_chunks("regenerate")
			_update_status()
		elif event.keycode == KEY_X:
			world_state.clear_edits()
			last_brush_result = "Transient center-region edits cleared"
			_rebuild_all_chunks("reset")
			_update_status()


func _initialize_region_states() -> void:
	for region_key in SpatialGrid.preview_region_keys():
		var state: RefCounted = WorldState.new(WorldState.DEMO_SEED, region_key)
		world_states[_region_id(region_key)] = state
		if region_key == CENTER_REGION:
			world_state = state


func _create_chunk_nodes() -> void:
	for region_key in SpatialGrid.preview_region_keys():
		var region_state: RefCounted = world_states[_region_id(region_key)]
		var region_origin: Vector3 = SpatialGrid.region_origin_world(region_key)
		for chunk_coordinate in ChunkGrid.all_coordinates():
			var chunk_id: String = region_state.chunk_id(chunk_coordinate)
			var chunk_node: MeshInstance3D
			if region_key == CENTER_REGION and chunk_coordinate == Vector2i.ZERO:
				chunk_node = terrain_mesh_template
			else:
				chunk_node = MeshInstance3D.new()
				chunk_node.name = "Region_%d_%d_Chunk_%d_%d" % [region_key.x, region_key.y, chunk_coordinate.x, chunk_coordinate.y]
				chunk_node.material_override = terrain_mesh_template.material_override
				terrain_chunks_root.add_child(chunk_node)
			chunk_node.position = region_origin + ChunkGrid.origin_for(chunk_coordinate)
			chunk_node.set_meta("stable_chunk_id", chunk_id)
			chunk_node.set_meta("region_key", region_key)
			chunk_node.set_meta("chunk_coordinate", chunk_coordinate)
			chunk_nodes[chunk_id] = chunk_node


func _rebuild_all_chunks(operation_name: String) -> void:
	var all_regions: Array[Vector2i] = SpatialGrid.preview_region_keys()
	var all_chunks: Array[Dictionary] = []
	for region_key in all_regions:
		for chunk_coordinate in ChunkGrid.all_coordinates():
			all_chunks.append({"region_key": region_key, "chunk_coordinate": chunk_coordinate})
	_rebuild_chunk_set(all_chunks, operation_name)


func _rebuild_chunk_set(chunks: Array[Dictionary], operation_name: String) -> void:
	var started_usec := Time.get_ticks_usec()
	var remeshed_ids: Array[String] = []
	var sample_count := 0
	for entry in chunks:
		var region_key: Vector2i = entry["region_key"]
		var chunk_coordinate: Vector2i = entry["chunk_coordinate"]
		if not ChunkGrid.is_valid_coordinate(chunk_coordinate):
			continue
		var region_state: RefCounted = world_states[_region_id(region_key)]
		var chunk_id: String = region_state.chunk_id(chunk_coordinate)
		if remeshed_ids.has(chunk_id):
			continue
		var brush_state: RefCounted = region_state.brush_edits if region_key == CENTER_REGION else null
		var result: Dictionary = TerrainMesher.build_chunk_mesh(
			region_state.world_seed,
			region_key,
			chunk_coordinate,
			cave_section_enabled,
			brush_state
		)
		if not result["valid"]:
			continue
		var chunk_node: MeshInstance3D = chunk_nodes[chunk_id]
		chunk_node.mesh = result["mesh"]
		remeshed_ids.append(chunk_id)
		sample_count += result["sample_count"]
	var total_triangles := _get_total_triangle_count()
	var mesh_attribute_bytes_estimate := _get_mesh_attribute_bytes_estimate()
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	var remeshed_coordinates: Array[Dictionary] = []
	for entry in chunks:
		var chunk_id: String = ChunkGrid.stable_id(entry["region_key"], entry["chunk_coordinate"])
		if remeshed_ids.has(chunk_id) and not remeshed_coordinates.has(entry):
			remeshed_coordinates.append(entry.duplicate())
	last_mesh_diagnostics = {
		"preview_region_count": world_states.size(),
		"active_chunk_count": chunk_nodes.size(),
		"remeshed_chunk_count": remeshed_ids.size(),
		"remeshed_chunk_ids": remeshed_ids.duplicate(),
		"remeshed_chunks": remeshed_coordinates,
		"sample_count": sample_count,
		"triangle_count": total_triangles,
		"total_triangle_count": total_triangles,
		"mesh_vertex_attribute_bytes_estimate": mesh_attribute_bytes_estimate,
		"elapsed_ms": elapsed_ms,
		"operation": operation_name,
	}
	print("TERRAIN_MULTI_REGION_READY: seed=%d generator=%d center_region=%s preview_regions=%d active_chunks=%d remeshed_chunks=%d total_triangles=%d vertex_attribute_bytes_estimate=%d elapsed_ms=%.3f edits=%d cave_section=%s operation=%s" % [
		world_state.world_seed,
		world_state.generator_version,
		CENTER_REGION,
		world_states.size(),
		chunk_nodes.size(),
		remeshed_ids.size(),
		total_triangles,
		mesh_attribute_bytes_estimate,
		elapsed_ms,
		world_state.brush_edits.get_edit_count(),
		cave_section_enabled,
		operation_name,
	])


func _get_total_triangle_count() -> int:
	var total := 0
	for chunk_node_value in chunk_nodes.values():
		var chunk_node: MeshInstance3D = chunk_node_value
		if chunk_node.mesh == null or chunk_node.mesh.get_surface_count() == 0:
			continue
		var vertices: PackedVector3Array = chunk_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		total += vertices.size() / 3
	return total


func _get_mesh_attribute_bytes_estimate() -> int:
	# Position and normal arrays are two float32 Vector3 attributes (24 bytes/vertex).
	# This excludes mesh, allocator and renderer-side overhead; it is a lower-bound estimate.
	var total_vertices := 0
	for chunk_node_value in chunk_nodes.values():
		var chunk_node: MeshInstance3D = chunk_node_value
		if chunk_node.mesh == null or chunk_node.mesh.get_surface_count() == 0:
			continue
		var vertices: PackedVector3Array = chunk_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		total_vertices += vertices.size()
	return total_vertices * 24


func _update_status() -> void:
	var selected_mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	var diagnostics_line := "Mesh: pending"
	if not last_mesh_diagnostics.is_empty():
		diagnostics_line = "Chunks: %d active, %d rebuilt | %d triangles | %.2f ms | ~%d vertex bytes" % [
			last_mesh_diagnostics["active_chunk_count"],
			last_mesh_diagnostics["remeshed_chunk_count"],
			last_mesh_diagnostics["triangle_count"],
			last_mesh_diagnostics["elapsed_ms"],
			last_mesh_diagnostics["mesh_vertex_attribute_bytes_estimate"],
		]
	status_label.text = "P1.0A fixed 3x3 SDF preview  |  seed %d  |  generator v%d\nRegions X/Z: -1..1 (center editable)  |  Center ID: %s\nRight-drag: orbit    Wheel: zoom    Left: carve    Shift+left: fill\nC: global cave section    R: regenerate    X: reset center edits\nSelected: %s    Edits: %d/%d    Radius: %.2f\n%s\n%s" % [
		world_state.world_seed,
		world_state.generator_version,
		world_state.region_key,
		selected_mode_name,
		world_state.brush_edits.get_edit_count(),
		BrushEditState.MAX_EDITS,
		BRUSH_RADIUS,
		diagnostics_line,
		last_brush_result,
	]
	if cave_section_enabled:
		status_label.text += "\nGlobal cave section: ON (world Z=6)"


func _apply_brush_at(screen_position: Vector2) -> void:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var density_sampler := func(point: Vector3) -> float:
		# The center region's local coordinates coincide with world coordinates.
		# Its canonical SDF remains continuous beyond that region for ray rejection.
		return world_state.sample_density(point)
	var pick: Dictionary = BrushPicker.pick_surface(ray_origin, ray_direction, density_sampler)
	if not pick.get("hit", false):
		last_brush_result = "No terrain surface hit; no edit added"
		_update_status()
		return
	var world_hit: Vector3 = pick["position"]
	var mapped: Dictionary = SpatialGrid.world_to_region_local(world_hit)
	if not mapped["valid"]:
		last_brush_result = "Invalid world position; no edit added"
		_update_status()
		return
	var hit_region: Vector2i = mapped["region_key"]
	var local_hit: Vector3 = mapped["local_position"]
	if hit_region != CENTER_REGION:
		last_brush_result = "Preview region %s is read-only in P1.0A" % hit_region
		_update_status()
		return
	if not _is_center_edit_safe(local_hit):
		last_brush_result = "Brush reaches a region or mesh boundary; no edit added"
		_update_status()
		return
	var dirty_chunks: Array[Dictionary] = []
	for chunk_coordinate in ChunkGrid.affected_chunks_for_sphere(local_hit, BRUSH_RADIUS):
		dirty_chunks.append({"region_key": CENTER_REGION, "chunk_coordinate": chunk_coordinate})
	if dirty_chunks.is_empty():
		last_brush_result = "Brush does not intersect the center region mesh; no edit added"
		_update_status()
		return
	if not world_state.apply_sphere(selected_brush_mode, local_hit, BRUSH_RADIUS):
		last_brush_result = "Edit limit reached or brush rejected; terrain unchanged"
		_update_status()
		return
	var mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	last_brush_result = "%s sphere applied to center region only" % mode_name
	_rebuild_chunk_set(dirty_chunks, "center_brush_edit")
	_update_status()


func _is_center_edit_safe(local_hit: Vector3) -> bool:
	return local_hit.x - BRUSH_RADIUS >= ChunkGrid.MIN_BOUND.x \
		and local_hit.x + BRUSH_RADIUS <= ChunkGrid.MAX_BOUND.x \
		and local_hit.z - BRUSH_RADIUS >= ChunkGrid.MIN_BOUND.z \
		and local_hit.z + BRUSH_RADIUS <= ChunkGrid.MAX_BOUND.z \
		and local_hit.y - BRUSH_RADIUS >= ChunkGrid.MIN_BOUND.y \
		and local_hit.y + BRUSH_RADIUS <= ChunkGrid.MAX_BOUND.y


func _region_id(region_key: Vector2i) -> String:
	return "%d,%d" % [region_key.x, region_key.y]


func _update_camera() -> void:
	camera.position = orbit_target + orbit_offset
	camera.look_at(orbit_target, Vector3.UP)


func _set_orbit_distance(distance: float) -> void:
	orbit_offset = orbit_offset.normalized() * clampf(distance, 20.0, 96.0)
	_update_camera()
