extends Node3D

const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const SpatialGrid := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const BrushEditState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const BrushPicker := preload("res://scripts/terrain/terrain_brush_picker.gd")

const BRUSH_RADIUS := 1.25
const REQUEST_RADIUS := 1
const UNLOAD_RADIUS := 2
const MAX_ACTIVE_REGIONS := 25
const MAX_MESH_SLICES_PER_FRAME := 1
const MESH_SLICE_COUNT := ceili(float(ChunkGrid.CELL_COUNT_Y) / float(TerrainMesher.CELLS_PER_MESH_SLICE))
const MAX_EDITED_REGION_STATES := 16
const FOCUS_MOVE_STEP := 4.0

@onready var terrain_chunks_root: Node3D = $TerrainChunks
@onready var terrain_mesh_template: MeshInstance3D = $TerrainChunks/Terrain
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $CanvasLayer/Status

var cave_section_enabled := false
var orbit_target := Vector3(8.0, 3.1, 6.0)
var orbit_offset := Vector3(34.0, 24.0, 40.0)
var orbit_dragging := false
var focus_region_key := Vector2i.ZERO
var _last_reconciled_focus := Vector2i(2147483647, 2147483647)

# Rendering residency is transient. WorldState remains separate from these nodes.
var active_regions: Dictionary = {} # region id -> {region_key, world_state, chunk_nodes}
var loading_regions: Dictionary = {} # region id -> bounded incremental mesh staging state
var edited_region_states: Dictionary = {} # unloaded regions with accepted transient edits
var world_states: Dictionary = {} # active and currently staged domain states
var world_state: RefCounted # focused region compatibility alias for the demo/tests
var chunk_nodes: Dictionary = {} # stable chunk id -> active MeshInstance3D

var selected_brush_mode: int = BrushEditState.Mode.CARVE
var last_brush_result := "Ready"
var last_mesh_diagnostics: Dictionary = {}
var last_stream_error := ""

var global_rebuild_pending := false
var global_rebuild_reason := ""
var _full_rebuild_target_ids: Array[String] = []
var _rendered_cave_section_enabled := false
var _operation_name := "initial_load"
var _operation_chunk_ids: Array[String] = []
var _operation_sample_count := 0
var _operation_started_usec := 0
var _operation_total_mesh_work_ms := 0.0
var _last_mesh_slice_ms := 0.0
var _peak_mesh_slice_ms := 0.0
var _last_process_work_ms := 0.0
var _peak_process_work_ms := 0.0
var _last_frame_ms := 0.0
var _peak_frame_ms := 0.0
var _mesh_slices_this_frame := 0
var _peak_mesh_slices_per_frame := 0
var _peak_active_region_count := 0
var _peak_queue_depth := 0
var _peak_mesh_slice_queue_depth := 0
var _streamed_region_loads := 0
var _streamed_region_unloads := 0
var _active_triangle_count := 0
var _active_vertex_count := 0


func _ready() -> void:
	terrain_mesh_template.mesh = null
	terrain_mesh_template.visible = false
	_begin_operation("initial_load")
	_update_camera()
	_reconcile_region_window(true)
	_update_status()


func _process(delta: float) -> void:
	var process_started_usec := Time.get_ticks_usec()
	_mesh_slices_this_frame = 0
	_last_frame_ms = maxf(delta * 1000.0, 0.0)
	_peak_frame_ms = maxf(_peak_frame_ms, _last_frame_ms)
	_update_focus_key()
	_reconcile_region_window()
	_process_one_chunk_job()
	_peak_mesh_slices_per_frame = maxi(_peak_mesh_slices_per_frame, _mesh_slices_this_frame)
	_last_process_work_ms = float(Time.get_ticks_usec() - process_started_usec) / 1000.0
	_peak_process_work_ms = maxf(_peak_process_work_ms, _last_process_work_ms)
	_update_runtime_diagnostics()
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
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			cave_section_enabled = not cave_section_enabled
			_start_global_rebuild("cave_section")
		elif event.keycode == KEY_R:
			_start_global_rebuild("regenerate")
		elif event.keycode == KEY_X:
			var focused_state := _state_for_region(focus_region_key)
			if focused_state != null:
				focused_state.clear_edits()
				if focused_state.brush_edits.get_edit_count() == 0:
					edited_region_states.erase(_region_id(focus_region_key))
			last_brush_result = "Transient edits cleared for focused region %s" % focus_region_key
			_start_global_rebuild("reset")
		elif event.keycode in [KEY_A, KEY_LEFT]:
			_move_focus(Vector3(-FOCUS_MOVE_STEP, 0.0, 0.0))
		elif event.keycode in [KEY_D, KEY_RIGHT]:
			_move_focus(Vector3(FOCUS_MOVE_STEP, 0.0, 0.0))
		elif event.keycode in [KEY_W, KEY_UP]:
			_move_focus(Vector3(0.0, 0.0, -FOCUS_MOVE_STEP))
		elif event.keycode in [KEY_S, KEY_DOWN]:
			_move_focus(Vector3(0.0, 0.0, FOCUS_MOVE_STEP))
		_update_status()


func _move_focus(delta: Vector3) -> void:
	orbit_target += delta
	_update_camera()
	_update_focus_key()
	_reconcile_region_window()


func _update_focus_key() -> void:
	var mapped: Dictionary = SpatialGrid.world_to_region_local(orbit_target)
	if mapped.get("valid", false):
		focus_region_key = mapped["region_key"]
		world_state = _state_for_region(focus_region_key)


func _reconcile_region_window(force: bool = false) -> void:
	_update_focus_key()
	if not force and focus_region_key == _last_reconciled_focus:
		return
	_last_reconciled_focus = focus_region_key
	var desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
	var retained_ids: Dictionary = {}
	for key in _region_keys_within_radius(focus_region_key, UNLOAD_RADIUS):
		retained_ids[_region_id(key)] = true
	for id_value in active_regions.keys().duplicate():
		var id: String = id_value
		if not retained_ids.has(id):
			_unload_region(id)

	if global_rebuild_pending:
		_ensure_full_rebuild_targets(desired, retained_ids)
	else:
		for id_value in loading_regions.keys().duplicate():
			var id: String = id_value
			var stage: Dictionary = loading_regions[id]
			var key: Vector2i = stage["region_key"]
			if not retained_ids.has(id) or (stage["purpose"] == "load" and not _contains_region(desired, key)):
				loading_regions.erase(id)
		for key in desired:
			var id := _region_id(key)
			if not active_regions.has(id) and not loading_regions.has(id):
				if loading_regions.is_empty():
					_begin_operation("region_stream_load")
				_begin_region_stage(key, "load", ChunkGrid.all_coordinates())
	_sync_world_state_index()
	_update_runtime_diagnostics()


func _region_keys_within_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			result.append(Vector2i(x, z))
	return result


func _contains_region(keys: Array[Vector2i], target: Vector2i) -> bool:
	return keys.has(target)


func _ensure_full_rebuild_targets(desired: Array[Vector2i], retained_ids: Dictionary) -> void:
	var target_keys: Array[Vector2i] = []
	for key in desired:
		target_keys.append(key)
	for entry in active_regions.values():
		var key: Vector2i = entry["region_key"]
		if retained_ids.has(_region_id(key)) and not target_keys.has(key):
			target_keys.append(key)
	target_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x - focus_region_key.x), absi(a.y - focus_region_key.y))
		var db := maxi(absi(b.x - focus_region_key.x), absi(b.y - focus_region_key.y))
		if da == db:
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		return da < db
	)
	var target_ids: Array[String] = []
	for key in target_keys:
		target_ids.append(_region_id(key))
	if target_ids == _full_rebuild_target_ids:
		return
	_full_rebuild_target_ids = target_ids
	loading_regions.clear()
	for key in target_keys:
		_begin_region_stage(key, "full", ChunkGrid.all_coordinates())


func _begin_region_stage(region_key: Vector2i, purpose: String, chunk_coordinates: Array[Vector2i]) -> void:
	var id := _region_id(region_key)
	var state := _state_for_region(region_key)
	if state == null:
		state = WorldState.new(WorldState.DEMO_SEED, region_key)
	var coordinates: Array[Vector2i] = chunk_coordinates.duplicate()
	var empty_slice_results: Array[Dictionary] = []
	loading_regions[id] = {
		"region_key": region_key,
		"world_state": state,
		"purpose": purpose,
		"chunk_coordinates": coordinates,
		"next_index": 0,
		"slice_index": 0,
		"slice_results": empty_slice_results,
		"meshes": {},
		"cave_section_enabled": cave_section_enabled,
		"edit_revision": state.brush_edits.revision,
	}
	world_states[id] = state
	if region_key == focus_region_key:
		world_state = state


func _process_one_chunk_job() -> void:
	if loading_regions.is_empty():
		if global_rebuild_pending:
			_try_commit_global_rebuild()
		return
	var ids: Array[String] = []
	for value in loading_regions.keys():
		ids.append(String(value))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ka: Vector2i = loading_regions[a]["region_key"]
		var kb: Vector2i = loading_regions[b]["region_key"]
		var da := maxi(absi(ka.x - focus_region_key.x), absi(ka.y - focus_region_key.y))
		var db := maxi(absi(kb.x - focus_region_key.x), absi(kb.y - focus_region_key.y))
		if da == db:
			if ka.y == kb.y:
				return ka.x < kb.x
			return ka.y < kb.y
		return da < db
	)
	var id := ""
	for candidate in ids:
		var candidate_stage: Dictionary = loading_regions[candidate]
		if int(candidate_stage["next_index"]) < (candidate_stage["chunk_coordinates"] as Array).size():
			id = candidate
			break
	if id.is_empty():
		_try_commit_global_rebuild()
		return
	var stage: Dictionary = loading_regions[id]
	var next_index: int = stage["next_index"]
	var coordinates: Array[Vector2i] = stage["chunk_coordinates"]
	var coordinate: Vector2i = coordinates[next_index]
	var state: RefCounted = stage["world_state"]
	var brush_state: RefCounted = state.brush_edits if state.brush_edits.get_edit_count() > 0 else null
	var slice_index: int = stage["slice_index"]
	var cell_start_y := slice_index * TerrainMesher.CELLS_PER_MESH_SLICE
	var cell_end_y := mini(cell_start_y + TerrainMesher.CELLS_PER_MESH_SLICE, ChunkGrid.CELL_COUNT_Y)
	var build_started_usec := Time.get_ticks_usec()
	_mesh_slices_this_frame += 1
	var result: Dictionary = TerrainMesher.build_chunk_mesh_slice(
		state.world_seed,
		stage["region_key"],
		coordinate,
		stage["cave_section_enabled"],
		brush_state,
		cell_start_y,
		cell_end_y
	)
	_last_mesh_slice_ms = float(Time.get_ticks_usec() - build_started_usec) / 1000.0
	_peak_mesh_slice_ms = maxf(_peak_mesh_slice_ms, _last_mesh_slice_ms)
	_operation_total_mesh_work_ms += _last_mesh_slice_ms
	if not result.get("valid", false) or not result.get("mesh") is ArrayMesh:
		_fail_region_stage(id, "Chunk mesh-slice generation failed; old visible terrain retained")
		return
	var slice_results: Array[Dictionary] = stage["slice_results"]
	slice_results.append(result)
	stage["slice_results"] = slice_results
	stage["slice_index"] = slice_index + 1
	if int(stage["slice_index"]) >= MESH_SLICE_COUNT:
		var combined: Dictionary = TerrainMesher.combine_chunk_mesh_slices(slice_results)
		if not combined.get("valid", false):
			_fail_region_stage(id, "Chunk mesh-slice combination failed; old visible terrain retained")
			return
		stage["meshes"][coordinate] = combined["mesh"]
		stage["next_index"] = next_index + 1
		stage["slice_index"] = 0
		var next_slice_results: Array[Dictionary] = []
		stage["slice_results"] = next_slice_results
		var unique_samples := (ChunkGrid.CELLS_PER_CHUNK_X + 1) * (ChunkGrid.CELL_COUNT_Y + 1) * (ChunkGrid.CELLS_PER_CHUNK_Z + 1)
		stage["sample_count"] = int(stage.get("sample_count", 0)) + unique_samples
		stage["triangle_count"] = int(stage.get("triangle_count", 0)) + int(combined["triangle_count"])
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		if not _operation_chunk_ids.has(chunk_id):
			_operation_chunk_ids.append(chunk_id)
		_operation_sample_count += unique_samples
	loading_regions[id] = stage
	if int(stage["next_index"]) >= coordinates.size():
		_complete_region_stage(id)


func _complete_region_stage(id: String) -> void:
	if not loading_regions.has(id):
		return
	var stage: Dictionary = loading_regions[id]
	if int(stage["next_index"]) < (stage["chunk_coordinates"] as Array).size():
		return
	if global_rebuild_pending or stage["purpose"] == "full":
		_try_commit_global_rebuild()
		return
	loading_regions.erase(id)
	if stage["purpose"] == "partial":
		_publish_partial_stage(id, stage)
	else:
		_publish_region(stage["region_key"], stage["world_state"], stage["meshes"])
		_streamed_region_loads += 1
		if _operation_name == "initial_load" and loading_regions.is_empty():
			print("TERRAIN_STREAM_WINDOW_READY: focus=%s active_regions=%d active_chunks=%d queued_chunks=0 peak_queue=%d peak_mesh_slice_ms=%.3f" % [
				focus_region_key, active_regions.size(), chunk_nodes.size(), _peak_queue_depth, _peak_mesh_slice_ms,
			])
	_sync_world_state_index()
	_record_completed_operation(stage)
	_update_runtime_diagnostics()


func _publish_partial_stage(id: String, stage: Dictionary) -> void:
	if not active_regions.has(id):
		return
	var entry: Dictionary = active_regions[id]
	var region_nodes: Dictionary = entry["chunk_nodes"]
	for coordinate in stage["chunk_coordinates"]:
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		if not region_nodes.has(chunk_id) or not stage["meshes"].has(coordinate):
			_fail_region_stage(id, "Partial remesh was incomplete; old visible meshes retained")
			return
	for coordinate in stage["chunk_coordinates"]:
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		var node: MeshInstance3D = region_nodes[chunk_id]
		_replace_node_mesh(node, stage["meshes"][coordinate])
	_record_completed_operation(stage)
	_update_runtime_diagnostics()


func _try_commit_global_rebuild() -> void:
	if not global_rebuild_pending:
		return
	for id in _full_rebuild_target_ids:
		if not loading_regions.has(id):
			return
		var stage: Dictionary = loading_regions[id]
		if int(stage["next_index"]) < (stage["chunk_coordinates"] as Array).size():
			return
	var all_stages: Array[Dictionary] = []
	for id in _full_rebuild_target_ids:
		all_stages.append(loading_regions[id])
	global_rebuild_pending = false
	global_rebuild_reason = ""
	_full_rebuild_target_ids.clear()
	loading_regions.clear()
	for stage in all_stages:
		_publish_region(stage["region_key"], stage["world_state"], stage["meshes"])
	_rendered_cave_section_enabled = cave_section_enabled
	_streamed_region_loads += all_stages.size()
	_sync_world_state_index()
	_record_completed_operation({
		"region_key": focus_region_key,
		"world_state": world_state,
		"purpose": "full",
		"sample_count": _operation_sample_count,
		"triangle_count": 0,
	})
	_update_runtime_diagnostics()


func _publish_region(region_key: Vector2i, state: RefCounted, meshes: Dictionary) -> void:
	var id := _region_id(region_key)
	var region_nodes: Dictionary = {}
	var region_origin: Vector3 = SpatialGrid.region_origin_world(region_key)
	for coordinate in ChunkGrid.all_coordinates():
		if not meshes.has(coordinate):
			continue
		var chunk_id: String = state.chunk_id(coordinate)
		var node: MeshInstance3D
		if active_regions.has(id) and active_regions[id]["chunk_nodes"].has(chunk_id):
			node = active_regions[id]["chunk_nodes"][chunk_id]
		else:
			node = _create_chunk_node(region_key, coordinate, chunk_id)
		node.position = region_origin + ChunkGrid.origin_for(coordinate)
		_replace_node_mesh(node, meshes[coordinate])
		node.visible = true
		node.set_meta("stable_chunk_id", chunk_id)
		node.set_meta("region_key", region_key)
		node.set_meta("chunk_coordinate", coordinate)
		region_nodes[chunk_id] = node
		chunk_nodes[chunk_id] = node
	var previous: Dictionary = active_regions.get(id, {})
	for old_id in previous.get("chunk_nodes", {}):
		if not region_nodes.has(old_id):
			_release_chunk_node(old_id, previous["chunk_nodes"][old_id])
	active_regions[id] = {"region_key": region_key, "world_state": state, "chunk_nodes": region_nodes}
	world_states[id] = state
	if region_key == focus_region_key:
		world_state = state


func _create_chunk_node(region_key: Vector2i, coordinate: Vector2i, chunk_id: String) -> MeshInstance3D:
	if region_key == Vector2i.ZERO and coordinate == Vector2i.ZERO:
		return terrain_mesh_template
	var node := MeshInstance3D.new()
	node.name = "Region_%d_%d_Chunk_%d_%d" % [region_key.x, region_key.y, coordinate.x, coordinate.y]
	node.material_override = terrain_mesh_template.material_override
	terrain_chunks_root.add_child(node)
	return node


func _release_chunk_node(chunk_id: String, node: MeshInstance3D) -> void:
	chunk_nodes.erase(chunk_id)
	_replace_node_mesh(node, null)
	if node == terrain_mesh_template:
		node.visible = false
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _replace_node_mesh(node: MeshInstance3D, replacement: Mesh) -> void:
	var previous := node.mesh
	_active_triangle_count -= _mesh_triangle_count(previous)
	_active_vertex_count -= _mesh_vertex_count(previous)
	node.mesh = replacement
	_active_triangle_count += _mesh_triangle_count(replacement)
	_active_vertex_count += _mesh_vertex_count(replacement)


func _mesh_triangle_count(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return vertices.size() / 3


func _mesh_vertex_count(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return vertices.size()


func _unload_region(id: String) -> void:
	if not active_regions.has(id):
		return
	var entry: Dictionary = active_regions[id]
	var state: RefCounted = entry["world_state"]
	if state.brush_edits.get_edit_count() > 0:
		edited_region_states[id] = state
	else:
		edited_region_states.erase(id)
	for chunk_id in entry["chunk_nodes"]:
		_release_chunk_node(chunk_id, entry["chunk_nodes"][chunk_id])
	active_regions.erase(id)
	world_states.erase(id)
	_streamed_region_unloads += 1


func _fail_region_stage(id: String, message: String) -> void:
	last_stream_error = message
	loading_regions.erase(id)
	if global_rebuild_pending:
		loading_regions.clear()
		global_rebuild_pending = false
		global_rebuild_reason = ""
		_full_rebuild_target_ids.clear()
		cave_section_enabled = _rendered_cave_section_enabled
		last_mesh_diagnostics["operation"] = "failed"
		last_brush_result = message
	_sync_world_state_index()
	_update_status()


func _record_completed_operation(stage: Dictionary) -> void:
	last_mesh_diagnostics = {
		"operation": _operation_name,
		"focus_region_key": focus_region_key,
		"active_region_count": active_regions.size(),
		"preview_region_count": active_regions.size(),
		"active_chunk_count": chunk_nodes.size(),
		"remeshed_chunk_count": _operation_chunk_ids.size(),
		"remeshed_chunk_ids": _operation_chunk_ids.duplicate(),
		"sample_count": _operation_sample_count,
		"triangle_count": _active_triangle_count,
		"total_triangle_count": _active_triangle_count,
		"mesh_vertex_attribute_bytes_estimate": _get_mesh_attribute_bytes_estimate(),
		"elapsed_ms": float(Time.get_ticks_usec() - _operation_started_usec) / 1000.0 if _operation_started_usec > 0 else 0.0,
		"total_mesh_work_ms": _operation_total_mesh_work_ms,
		"peak_mesh_slice_ms": _peak_mesh_slice_ms,
		"max_active_region_count": _peak_active_region_count,
		"max_queue_depth": _peak_queue_depth,
		"operation_region_key": stage.get("region_key", focus_region_key),
	}


func _start_global_rebuild(operation_name: String) -> void:
	_begin_operation(operation_name)
	last_stream_error = ""
	global_rebuild_pending = true
	global_rebuild_reason = operation_name
	loading_regions.clear()
	_full_rebuild_target_ids.clear()
	var desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
	var targets: Array[Vector2i] = []
	for entry in active_regions.values():
		var key: Vector2i = entry["region_key"]
		if not targets.has(key):
			targets.append(key)
	for key in desired:
		if not targets.has(key):
			targets.append(key)
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x - focus_region_key.x), absi(a.y - focus_region_key.y))
		var db := maxi(absi(b.x - focus_region_key.x), absi(b.y - focus_region_key.y))
		if da == db:
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		return da < db
	)
	for key in targets:
		var id := _region_id(key)
		_full_rebuild_target_ids.append(id)
		_begin_region_stage(key, "full", ChunkGrid.all_coordinates())
	_sync_world_state_index()
	_update_runtime_diagnostics()


func _schedule_partial_rebuild(region_key: Vector2i, chunks: Array[Vector2i], operation_name: String) -> void:
	var id := _region_id(region_key)
	_begin_operation(operation_name)
	_begin_region_stage(region_key, "partial", chunks)
	_update_runtime_diagnostics()


func _begin_operation(operation_name: String) -> void:
	_operation_name = operation_name
	_operation_chunk_ids.clear()
	_operation_sample_count = 0
	_operation_total_mesh_work_ms = 0.0
	_operation_started_usec = Time.get_ticks_usec()


func _sync_world_state_index() -> void:
	world_states.clear()
	for id_value in active_regions:
		var id: String = id_value
		world_states[id] = active_regions[id]["world_state"]
	for id_value in loading_regions:
		var id: String = id_value
		world_states[id] = loading_regions[id]["world_state"]
	for id_value in edited_region_states:
		var id: String = id_value
		if not world_states.has(id):
			world_states[id] = edited_region_states[id]
	world_state = _state_for_region(focus_region_key)


func _state_for_region(region_key: Vector2i) -> RefCounted:
	var id := _region_id(region_key)
	if active_regions.has(id):
		return active_regions[id]["world_state"]
	if loading_regions.has(id):
		return loading_regions[id]["world_state"]
	if edited_region_states.has(id):
		return edited_region_states[id]
	return null


func _can_accept_edit(state: RefCounted, region_key: Vector2i) -> bool:
	if state.brush_edits.get_edit_count() > 0:
		return true
	var edited_ids: Dictionary = {}
	for entry in active_regions.values():
		var candidate: RefCounted = entry["world_state"]
		if candidate.brush_edits.get_edit_count() > 0:
			edited_ids[_region_id(candidate.region_key)] = true
	for candidate in edited_region_states.values():
		if candidate.brush_edits.get_edit_count() > 0:
			edited_ids[_region_id(candidate.region_key)] = true
	return edited_ids.has(_region_id(region_key)) or edited_ids.size() < MAX_EDITED_REGION_STATES


func _sample_world_density(world_position: Vector3) -> float:
	var mapped: Dictionary = SpatialGrid.world_to_region_local(world_position)
	if not mapped.get("valid", false):
		return -INF
	var key: Vector2i = mapped["region_key"]
	var state := _state_for_region(key)
	if state != null:
		return state.sample_density(mapped["local_position"], cave_section_enabled)
	return Field.sample_density(WorldState.DEMO_SEED, key, mapped["local_position"], cave_section_enabled)


func _apply_brush_at(screen_position: Vector2) -> void:
	if global_rebuild_pending or not active_regions.has(_region_id(focus_region_key)):
		last_brush_result = "Focused region is not ready for edits; no edit added"
		_update_status()
		return
	if loading_regions.has(_region_id(focus_region_key)):
		last_brush_result = "Focused region is rebuilding; no edit added"
		_update_status()
		return
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var density_sampler := func(point: Vector3) -> float:
		return _sample_world_density(point)
	var pick: Dictionary = BrushPicker.pick_surface(ray_origin, ray_direction, density_sampler)
	if not pick.get("hit", false):
		last_brush_result = "No terrain surface hit; no edit added"
		_update_status()
		return
	var world_hit: Vector3 = pick["position"]
	var mapped: Dictionary = SpatialGrid.world_to_region_local(world_hit)
	if not mapped.get("valid", false):
		last_brush_result = "Invalid world position; no edit added"
		_update_status()
		return
	var hit_region: Vector2i = mapped["region_key"]
	var local_hit: Vector3 = mapped["local_position"]
	if hit_region != focus_region_key:
		last_brush_result = "Region %s is outside the focused edit region" % hit_region
		_update_status()
		return
	if not _is_region_edit_safe(local_hit):
		last_brush_result = "Brush reaches a region or mesh boundary; no edit added"
		_update_status()
		return
	var state := _state_for_region(focus_region_key)
	if state == null or not _can_accept_edit(state, focus_region_key):
		last_brush_result = "Transient edited-region limit reached; terrain unchanged"
		_update_status()
		return
	var dirty_chunks: Array[Vector2i] = ChunkGrid.affected_chunks_for_sphere(local_hit, BRUSH_RADIUS)
	if dirty_chunks.is_empty():
		last_brush_result = "Brush does not intersect the focused region mesh; no edit added"
		_update_status()
		return
	if not state.apply_sphere(selected_brush_mode, local_hit, BRUSH_RADIUS):
		last_brush_result = "Edit limit reached or brush rejected; terrain unchanged"
		_update_status()
		return
	var mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	last_brush_result = "%s sphere applied to focused region %s only" % [mode_name, focus_region_key]
	if state.brush_edits.get_edit_count() > 0:
		edited_region_states[_region_id(focus_region_key)] = state
	_schedule_partial_rebuild(focus_region_key, dirty_chunks, "focused_region_brush_edit")
	_update_status()


func _is_region_edit_safe(local_hit: Vector3) -> bool:
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


func _get_total_triangle_count() -> int:
	return _active_triangle_count


func _get_mesh_attribute_bytes_estimate() -> int:
	return _active_vertex_count * 24


func _queued_chunk_count() -> int:
	var total := 0
	for stage_value in loading_regions.values():
		var stage: Dictionary = stage_value
		total += (stage["chunk_coordinates"] as Array).size() - int(stage["next_index"])
	return total


func _queued_mesh_slice_count() -> int:
	var total := 0
	for stage_value in loading_regions.values():
		var stage: Dictionary = stage_value
		var remaining_chunks: int = (stage["chunk_coordinates"] as Array).size() - int(stage["next_index"])
		if remaining_chunks <= 0:
			continue
		total += (remaining_chunks - 1) * MESH_SLICE_COUNT + (MESH_SLICE_COUNT - int(stage["slice_index"]))
	return total


func _update_runtime_diagnostics() -> void:
	_peak_active_region_count = maxi(_peak_active_region_count, active_regions.size())
	_peak_queue_depth = maxi(_peak_queue_depth, _queued_chunk_count())
	_peak_mesh_slice_queue_depth = maxi(_peak_mesh_slice_queue_depth, _queued_mesh_slice_count())
	if last_mesh_diagnostics.is_empty():
		last_mesh_diagnostics = {}
	last_mesh_diagnostics["active_region_count"] = active_regions.size()
	last_mesh_diagnostics["preview_region_count"] = active_regions.size()
	last_mesh_diagnostics["active_chunk_count"] = chunk_nodes.size()
	last_mesh_diagnostics["requested_region_count"] = (REQUEST_RADIUS * 2 + 1) * (REQUEST_RADIUS * 2 + 1)
	last_mesh_diagnostics["loading_region_count"] = loading_regions.size()
	last_mesh_diagnostics["queued_chunk_count"] = _queued_chunk_count()
	last_mesh_diagnostics["queued_mesh_slice_count"] = _queued_mesh_slice_count()
	last_mesh_diagnostics["peak_active_region_count"] = _peak_active_region_count
	last_mesh_diagnostics["peak_queue_depth"] = _peak_queue_depth
	last_mesh_diagnostics["peak_mesh_slice_queue_depth"] = _peak_mesh_slice_queue_depth
	last_mesh_diagnostics["last_mesh_slice_ms"] = _last_mesh_slice_ms
	last_mesh_diagnostics["peak_mesh_slice_ms"] = _peak_mesh_slice_ms
	last_mesh_diagnostics["last_process_work_ms"] = _last_process_work_ms
	last_mesh_diagnostics["peak_process_work_ms"] = _peak_process_work_ms
	last_mesh_diagnostics["last_frame_ms"] = _last_frame_ms
	last_mesh_diagnostics["peak_frame_ms"] = _peak_frame_ms
	last_mesh_diagnostics["streamed_region_loads"] = _streamed_region_loads
	last_mesh_diagnostics["streamed_region_unloads"] = _streamed_region_unloads
	last_mesh_diagnostics["global_rebuild_pending"] = global_rebuild_pending
	last_mesh_diagnostics["max_active_region_count"] = MAX_ACTIVE_REGIONS
	last_mesh_diagnostics["max_mesh_slices_per_frame"] = MAX_MESH_SLICES_PER_FRAME
	last_mesh_diagnostics["peak_mesh_slices_per_frame"] = _peak_mesh_slices_per_frame


func _update_status() -> void:
	var state := _state_for_region(focus_region_key)
	var edit_count: int = state.brush_edits.get_edit_count() if state != null else 0
	var seed: int = state.world_seed if state != null else WorldState.DEMO_SEED
	var generator_version: int = state.generator_version if state != null else Field.GENERATOR_VERSION
	var selected_mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	var queue_depth := _queued_chunk_count()
	var status := "P1.0B dynamic SDF regions  |  seed %d  |  generator v%d\nFocus region: %s  |  active: %d/%d  |  loading: %d  |  queued chunks/slices: %d/%d\nWASD/arrows: move focus    Right-drag: orbit    Wheel: zoom    Left: carve    Shift+left: fill\nC: global cave section    R: regenerate    X: reset focused edits\nSelected: %s    Edits: %d/%d in focus region    Radius: %.2f\nBuild budget: %d mesh slice/frame  |  last/peak slice: %.1f/%.1f ms  |  peak frame: %.1f ms\n" % [
		seed,
		generator_version,
		focus_region_key,
		active_regions.size(),
		MAX_ACTIVE_REGIONS,
		loading_regions.size(),
		queue_depth,
		_queued_mesh_slice_count(),
		selected_mode_name,
		edit_count,
		BrushEditState.MAX_EDITS,
		BRUSH_RADIUS,
		MAX_MESH_SLICES_PER_FRAME,
		_last_mesh_slice_ms,
		_peak_mesh_slice_ms,
		_peak_frame_ms,
	]
	if global_rebuild_pending:
		status += "Rebuilding visible set: %d regions staged\n" % loading_regions.size()
	if cave_section_enabled:
		status += "Global cave section: ON (world Z=6)\n"
	if last_stream_error != "":
		status += "STREAM ERROR: " + last_stream_error + "\n"
	status += last_brush_result
	status_label.text = status
