extends Node3D

const TerrainField := preload("res://scripts/terrain/sdf_world.gd")
const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const BrushEditState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const BrushPicker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const BRUSH_RADIUS := 1.25

@onready var terrain_chunks_root: Node3D = $TerrainChunks
@onready var terrain_mesh_template: MeshInstance3D = $TerrainChunks/Terrain
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $CanvasLayer/Status

var cave_section_enabled := false
var orbit_target := Vector3(8.0, 3.1, 6.0)
var orbit_offset := Vector3(14.0, 10.0, 18.0)
var orbit_dragging := false
var world_state: RefCounted = WorldState.new()
var chunk_nodes: Dictionary = {}
var selected_brush_mode: int = BrushEditState.Mode.CARVE
var last_brush_result := "Ready"
var last_mesh_diagnostics: Dictionary = {}


func _ready() -> void:
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
		orbit_offset.y = clampf(orbit_offset.y - event.relative.y * 0.05, 2.0, 22.0)
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
			last_brush_result = "Transient edits cleared"
			_rebuild_all_chunks("reset")
			_update_status()


func _create_chunk_nodes() -> void:
	for chunk_coordinate in ChunkGrid.all_coordinates():
		var chunk_id: String = world_state.chunk_id(chunk_coordinate)
		var chunk_node: MeshInstance3D
		if chunk_coordinate == Vector2i.ZERO:
			chunk_node = terrain_mesh_template
		else:
			chunk_node = MeshInstance3D.new()
			chunk_node.name = "Chunk_%02d_%02d" % [chunk_coordinate.x, chunk_coordinate.y]
			chunk_node.material_override = terrain_mesh_template.material_override
			terrain_chunks_root.add_child(chunk_node)
		chunk_node.position = ChunkGrid.origin_for(chunk_coordinate)
		chunk_node.set_meta("stable_chunk_id", chunk_id)
		chunk_node.set_meta("chunk_coordinate", chunk_coordinate)
		chunk_nodes[chunk_id] = chunk_node


func _rebuild_all_chunks(operation_name: String) -> void:
	_rebuild_chunk_set(ChunkGrid.all_coordinates(), operation_name)


func _rebuild_chunk_set(chunk_coordinates: Array[Vector2i], operation_name: String) -> void:
	var started_usec := Time.get_ticks_usec()
	var remeshed_ids: Array[String] = []
	var sample_count := 0
	for chunk_coordinate in chunk_coordinates:
		if not ChunkGrid.is_valid_coordinate(chunk_coordinate):
			continue
		var chunk_id: String = world_state.chunk_id(chunk_coordinate)
		if remeshed_ids.has(chunk_id):
			continue
		var result: Dictionary = TerrainMesher.build_chunk_mesh(
			world_state.world_seed,
			world_state.region_key,
			chunk_coordinate,
			cave_section_enabled,
			world_state.brush_edits
		)
		if not result["valid"]:
			continue
		var chunk_node: MeshInstance3D = chunk_nodes[chunk_id]
		chunk_node.mesh = result["mesh"]
		remeshed_ids.append(chunk_id)
		sample_count += result["sample_count"]
	var total_triangles := _get_total_triangle_count()
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	var remeshed_coordinates: Array[Vector2i] = []
	for coordinate in chunk_coordinates:
		if remeshed_ids.has(world_state.chunk_id(coordinate)) and not remeshed_coordinates.has(coordinate):
			remeshed_coordinates.append(coordinate)
	last_mesh_diagnostics = {
		"active_chunk_count": chunk_nodes.size(),
		"remeshed_chunk_count": remeshed_ids.size(),
		"remeshed_chunk_ids": remeshed_ids.duplicate(),
		"remeshed_chunk_coordinates": remeshed_coordinates,
		"sample_count": sample_count,
		"triangle_count": total_triangles,
		"total_triangle_count": total_triangles,
		"elapsed_ms": elapsed_ms,
		"operation": operation_name,
	}
	print("TERRAIN_CHUNKS_READY: seed=%d generator=%d region=%s active_chunks=%d remeshed_chunks=%d total_triangles=%d elapsed_ms=%.3f edits=%d cave_section=%s operation=%s" % [
		world_state.world_seed,
		world_state.generator_version,
		world_state.region_key,
		chunk_nodes.size(),
		remeshed_ids.size(),
		total_triangles,
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


func _update_status() -> void:
	var selected_mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	var diagnostics_line := "Chunks: pending"
	if not last_mesh_diagnostics.is_empty():
		diagnostics_line = "Chunks: %d active, %d rebuilt | %d triangles | %.2f ms" % [
			last_mesh_diagnostics["active_chunk_count"],
			last_mesh_diagnostics["remeshed_chunk_count"],
			last_mesh_diagnostics["triangle_count"],
			last_mesh_diagnostics["elapsed_ms"],
		]
	status_label.text = "P0.1 SDF terrain  |  seed %d  |  generator v%d  |  region %s\nRight-drag: orbit    Wheel: zoom    Left: carve    Shift+left: fill\nC: cave section    R: regenerate    X: reset edits\nSelected: %s    Edits: %d/%d    Radius: %.2f\n%s\n%s" % [
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
		status_label.text += "\nCave section: ON"


func _apply_brush_at(screen_position: Vector2) -> void:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var density_sampler := func(point: Vector3) -> float:
		return world_state.sample_density(point)
	var pick: Dictionary = BrushPicker.pick_surface(ray_origin, ray_direction, density_sampler)
	if not pick.get("hit", false) or not TerrainMesher.contains_mesh_point(pick["position"]):
		last_brush_result = "No visible terrain hit; no edit added"
		_update_status()
		return
	var dirty_chunks: Array[Vector2i] = ChunkGrid.affected_chunks_for_sphere(pick["position"], BRUSH_RADIUS)
	if dirty_chunks.is_empty():
		last_brush_result = "Brush does not intersect rendered chunks; no edit added"
		_update_status()
		return
	if not world_state.apply_sphere(selected_brush_mode, pick["position"], BRUSH_RADIUS):
		last_brush_result = "Edit limit reached or brush rejected; terrain unchanged"
		_update_status()
		return
	var mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	last_brush_result = "%s sphere applied" % mode_name
	_rebuild_chunk_set(dirty_chunks, "brush_edit")
	_update_status()


func _update_camera() -> void:
	camera.position = orbit_target + orbit_offset
	camera.look_at(orbit_target, Vector3.UP)


func _set_orbit_distance(distance: float) -> void:
	orbit_offset = orbit_offset.normalized() * clampf(distance, 10.0, 42.0)
	_update_camera()
