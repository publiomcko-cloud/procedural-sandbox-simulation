extends Node3D

const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const SpatialGrid := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const BrushEditState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const BrushPicker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const TerrainMeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")

const BRUSH_RADIUS := 1.25
const REQUEST_RADIUS := 1
const UNLOAD_RADIUS := 2
const MAX_ACTIVE_REGIONS := 25
const MAX_MESH_JOBS_IN_FLIGHT := 4
const MAX_MESH_UPLOADS_PER_FRAME := 2
const DIAGNOSTICS_REFRESH_INTERVAL := 0.25
const FOCUS_MOVE_STEP := 4.0
const MAX_STAGE_RETRIES := 2

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
var world_states: Dictionary = {} # active and currently staged domain states
var world_state: RefCounted # focused region compatibility alias for the demo/tests
var edit_ledger: RefCounted
var chunk_nodes: Dictionary = {} # stable chunk id -> active MeshInstance3D

var selected_brush_mode: int = BrushEditState.Mode.CARVE
var last_brush_result := "Ready"
var last_mesh_diagnostics: Dictionary = {}
var last_stream_error := ""

var global_rebuild_pending := false
var global_rebuild_reason := ""
var _full_rebuild_target_ids: Array[String] = []
var _edit_transaction: Dictionary = {}
var _stage_retry_counts: Dictionary = {}
var _stream_errors_by_region: Dictionary = {}
var _superseded_stage_total := 0
var _next_stage_token := 1
var _mesh_jobs: Dictionary = {} # WorkerThreadPool task id -> immutable job/stage token
var _mesh_queue_wait_usec_samples: Array[int] = []
var _pool_queue_wait_usec_samples: Array[int] = []
var _mesh_upload_usec_samples: Array[int] = []
var _mesh_publish_usec_samples: Array[int] = []
var _global_rebuild_retry_count := 0
var debug_fail_next_mesh_stage := false
var debug_fail_next_load_stage := false
var _mesh_stage_retry_total := 0
var _rendered_cave_section_enabled := false
var _operation_name := "initial_load"
var _operation_chunk_ids: Array[String] = []
var _operation_sample_count := 0
var _operation_started_usec := 0
var _operation_total_mesh_work_ms := 0.0
var _operation_stage_timings_usec: Dictionary = {}
var _last_mesh_upload_ms := 0.0
var _peak_mesh_upload_ms := 0.0
var _last_process_work_ms := 0.0
var _peak_process_work_ms := 0.0
var _last_frame_ms := 0.0
var _peak_frame_ms := 0.0
var _mesh_uploads_this_frame := 0
var _peak_mesh_uploads_per_frame := 0
var _peak_mesh_jobs_in_flight := 0
var _frame_time_samples: Array[float] = []
var _frame_sample_write_index := 0
var _frame_sample_count := 0
var _diagnostics_refresh_elapsed := 0.0
var _peak_active_region_count := 0
var _peak_queue_depth := 0
var _peak_mesh_job_queue_depth := 0
var _streamed_region_loads := 0
var _streamed_region_unloads := 0
var _active_triangle_count := 0
var _active_vertex_count := 0
var _last_edit_support_region_count := 0
var _last_edit_rebuild_region_count := 0
var _last_edit_rebuild_chunk_count := 0
var _last_edit_mesh_jobs := 0
var _last_edit_rejection := ""


func _ready() -> void:
	_frame_time_samples.resize(512)
	edit_ledger = BrushEditState.new(WorldState.DEMO_SEED, Field.GENERATOR_VERSION)
	terrain_mesh_template.mesh = null
	terrain_mesh_template.visible = false
	_begin_operation("initial_load")
	_update_camera()
	_reconcile_region_window(true)
	_update_status()


func _exit_tree() -> void:
	# Worker callbacks own only immutable input and CPU packed arrays, but complete
	# them before the scene and their result holders are released.
	for task_id_value in _mesh_jobs.keys().duplicate():
		WorkerThreadPool.wait_for_task_completion(int(task_id_value))
	_mesh_jobs.clear()


func _process(delta: float) -> void:
	var process_started_usec := Time.get_ticks_usec()
	_mesh_uploads_this_frame = 0
	_last_frame_ms = maxf(delta * 1000.0, 0.0)
	if _frame_time_samples.size() == 512:
		_frame_time_samples[_frame_sample_write_index] = _last_frame_ms
		_frame_sample_write_index = (_frame_sample_write_index + 1) % 512
		_frame_sample_count = mini(_frame_sample_count + 1, 512)
	_peak_frame_ms = maxf(_peak_frame_ms, _last_frame_ms)
	_update_focus_key()
	_reconcile_region_window()
	_process_one_chunk_job()
	_peak_mesh_uploads_per_frame = maxi(_peak_mesh_uploads_per_frame, _mesh_uploads_this_frame)
	_last_process_work_ms = float(Time.get_ticks_usec() - process_started_usec) / 1000.0
	_peak_process_work_ms = maxf(_peak_process_work_ms, _last_process_work_ms)
	_diagnostics_refresh_elapsed += delta
	if _diagnostics_refresh_elapsed >= DIAGNOSTICS_REFRESH_INTERVAL:
		_diagnostics_refresh_elapsed = 0.0
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
			var cleared: Dictionary = edit_ledger.clear_for_region(focus_region_key)
			last_brush_result = "Reset focused edits for %s: removed %d command(s); rebuilding %d dependent region(s)" % [
				focus_region_key, cleared["removed_count"], cleared["rebuild_regions"].size(),
			]
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
				if not _edit_transaction.is_empty() and (_edit_transaction["target_ids"] as Array).has(id):
					_edit_transaction["target_ids"].erase(id)
		if not _edit_transaction.is_empty() and (_edit_transaction["target_ids"] as Array).is_empty():
			_finish_edit_transaction("accepted; rebuild dependencies left residency and will apply it on load")
		for key in desired:
			var id := _region_id(key)
			if not active_regions.has(id) and not loading_regions.has(id):
				if loading_regions.is_empty():
					_begin_operation("region_stream_load")
				if _edit_transaction_affects_region(key):
					_add_edit_transaction_region(key)
				else:
					_begin_region_stage(key, "load", ChunkGrid.all_coordinates())
		for id_value in loading_regions.keys().duplicate():
			var id: String = id_value
			var stage: Dictionary = loading_regions[id]
			var key: Vector2i = stage["region_key"]
			if stage["purpose"] == "load" and _edit_transaction_affects_region(key):
				_add_edit_transaction_region(key)
	_sync_world_state_index()
	_update_runtime_diagnostics()


func _edit_transaction_affects_region(region_key: Vector2i) -> bool:
	return not _edit_transaction.is_empty() \
		and (_edit_transaction.get("rebuild_regions", []) as Array).has(region_key)


func _add_edit_transaction_region(region_key: Vector2i) -> void:
	if not _edit_transaction_affects_region(region_key):
		return
	var id := _region_id(region_key)
	var already_targeted := false
	for target in _edit_transaction["targets"]:
		if target["id"] == id:
			already_targeted = true
			break
	if not already_targeted:
		_edit_transaction["targets"].append({
			"region_key": region_key,
			"id": id,
			"chunks": ChunkGrid.all_coordinates(),
			"full": true,
		})
	if _edit_transaction.get("stage_state", "") == "failed_pending_retry":
		_edit_transaction["stage_state"] = "staging"
		_edit_transaction["retries"] = 0
		_start_edit_transaction_attempt()
		return
	if not (_edit_transaction["target_ids"] as Array).has(id):
		loading_regions.erase(id)
		_begin_region_stage(region_key, "edit_transaction", ChunkGrid.all_coordinates())
		_edit_transaction["target_ids"].append(id)
		_edit_transaction["rebuild_chunk_count"] += ChunkGrid.CHUNK_COUNT_X * ChunkGrid.CHUNK_COUNT_Z
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
		state = WorldState.new(WorldState.DEMO_SEED, region_key, edit_ledger)
	var coordinates: Array[Vector2i] = chunk_coordinates.duplicate()
	var token := _next_stage_token
	_next_stage_token += 1
	var queued_times: Array[int] = []
	var queued_now := Time.get_ticks_usec()
	for _coordinate in coordinates:
		queued_times.append(queued_now)
	loading_regions[id] = {
		"region_key": region_key,
		"world_state": state,
		"purpose": purpose,
		"chunk_coordinates": coordinates,
		"next_index": 0,
		"stage_token": token,
		"submit_index": 0,
		"pending_count": 0,
		"chunk_queued_usec": queued_times,
		"meshes": {},
		"cave_section_enabled": cave_section_enabled,
		"edit_revision": state.brush_edits.revision,
		"chunk_enqueued_usec": Time.get_ticks_usec(),
		"retry_count": 0,
	}
	world_states[id] = state
	if region_key == focus_region_key:
		world_state = state


func _process_one_chunk_job() -> void:
	_process_completed_mesh_jobs()
	_dispatch_mesh_jobs()
	if loading_regions.is_empty() and global_rebuild_pending:
		_try_commit_global_rebuild()


func _process_completed_mesh_jobs() -> void:
	var completed_task_ids: Array[int] = []
	for task_id_value in _mesh_jobs.keys():
		var task_id := int(task_id_value)
		if WorkerThreadPool.is_task_completed(task_id):
			completed_task_ids.append(task_id)
	var uploads_this_frame := 0
	for task_id in completed_task_ids:
		if uploads_this_frame >= MAX_MESH_UPLOADS_PER_FRAME:
			break
		WorkerThreadPool.wait_for_task_completion(task_id)
		var record: Dictionary = _mesh_jobs[task_id]
		_mesh_jobs.erase(task_id)
		var job = record["job"]
		var id: String = record["stage_id"]
		_pool_queue_wait_usec_samples.append(maxi(0, int(job.worker_started_usec) - int(record["submitted_usec"])))
		if not loading_regions.has(id):
			continue
		var stage: Dictionary = loading_regions[id]
		if int(stage["stage_token"]) != int(record["stage_token"]):
			continue
		var state: RefCounted = stage["world_state"]
		if state.brush_edits.revision != int(stage["edit_revision"]):
			_supersede_region_stage(id)
			continue
		var cpu_result: Dictionary = job.result
		if not cpu_result.get("valid", false) or not cpu_result.has("positions"):
			_fail_region_stage(id, "Chunk CPU mesh job failed; previous visible meshes retained")
			continue
		var upload_started_usec := Time.get_ticks_usec()
		var result: Dictionary = TerrainMesher.mesh_from_cpu_data(cpu_result)
		var upload_elapsed_usec := Time.get_ticks_usec() - upload_started_usec
		_mesh_upload_usec_samples.append(upload_elapsed_usec)
		_last_mesh_upload_ms = float(upload_elapsed_usec) / 1000.0
		_peak_mesh_upload_ms = maxf(_peak_mesh_upload_ms, _last_mesh_upload_ms)
		_mesh_uploads_this_frame += 1
		var cpu_timings: Dictionary = result.get("timings_usec", {})
		var cpu_work_usec := int(cpu_timings.get("sdf_and_ledger", 0)) \
			+ int(cpu_timings.get("triangulation_and_face_normals", 0)) \
			+ int(cpu_timings.get("shared_gradient_normals", 0))
		_operation_total_mesh_work_ms += float(cpu_work_usec + upload_elapsed_usec) / 1000.0
		_add_stage_timings(result.get("timings_usec", {}))
		if not result.get("mesh") is ArrayMesh:
			_fail_region_stage(id, "Chunk main-thread mesh creation failed; previous meshes retained")
			continue
		var coordinate: Vector2i = record["coordinate"]
		stage["meshes"][coordinate] = result["mesh"]
		stage["next_index"] = int(stage["next_index"]) + 1
		stage["pending_count"] = maxi(0, int(stage["pending_count"]) - 1)
		stage["sample_count"] = int(stage.get("sample_count", 0)) + int(result["sample_count"])
		stage["triangle_count"] = int(stage.get("triangle_count", 0)) + int(result["triangle_count"])
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		_operation_chunk_ids.append(chunk_id)
		_operation_sample_count += int(result["sample_count"])
		if stage["purpose"] == "edit_transaction" and not _edit_transaction.is_empty():
			_edit_transaction["mesh_job_count"] = int(_edit_transaction.get("mesh_job_count", 0)) + 1
		loading_regions[id] = stage
		uploads_this_frame += 1
		if int(stage["next_index"]) >= (stage["chunk_coordinates"] as Array).size() \
			and int(stage["submit_index"]) >= (stage["chunk_coordinates"] as Array).size() \
			and int(stage["pending_count"]) == 0:
			_complete_region_stage(id)


func _dispatch_mesh_jobs() -> void:
	while _mesh_jobs.size() < MAX_MESH_JOBS_IN_FLIGHT:
		var request := _next_mesh_job_request()
		if request.is_empty():
			return
		var id: String = request["id"]
		var stage: Dictionary = loading_regions[id]
		var state: RefCounted = stage["world_state"]
		if state.brush_edits.revision != int(stage["edit_revision"]):
			_supersede_region_stage(id)
			continue
		var inject_edit_failure: bool = debug_fail_next_mesh_stage and String(stage["purpose"]) == "edit_transaction"
		var inject_load_failure: bool = debug_fail_next_load_stage and String(stage["purpose"]) == "load"
		if inject_edit_failure or inject_load_failure:
			debug_fail_next_mesh_stage = false
			debug_fail_next_load_stage = false
			_fail_region_stage(id, "Injected mesh-stage failure; prior meshes retained")
			continue
		var coordinate: Vector2i = request["coordinate"]
		var queue_index: int = int(stage["submit_index"])
		var enqueued_usec := int(stage["chunk_queued_usec"][queue_index])
		var submitted_usec := Time.get_ticks_usec()
		_mesh_queue_wait_usec_samples.append(maxi(0, submitted_usec - enqueued_usec))
		var job := TerrainMeshJob.new(
			state.world_seed, stage["region_key"], coordinate,
			stage["cave_section_enabled"],
			state.brush_edits.get_meshing_snapshot_for_chunk(stage["region_key"], coordinate),
			submitted_usec
		)
		var high_priority: bool = String(stage["purpose"]) in ["edit_transaction", "partial"]
		var task_id := WorkerThreadPool.add_task(Callable(job, "run"), high_priority, "P1.0C terrain chunk")
		if task_id < 0:
			_fail_region_stage(id, "Worker pool rejected a mesh job; previous visible meshes retained")
			continue
		stage["submit_index"] = int(stage["submit_index"]) + 1
		stage["pending_count"] = int(stage["pending_count"]) + 1
		loading_regions[id] = stage
		_mesh_jobs[task_id] = {
			"job": job,
			"stage_id": id,
			"stage_token": stage["stage_token"],
			"coordinate": coordinate,
			"submitted_usec": submitted_usec,
		}
		_peak_mesh_jobs_in_flight = maxi(_peak_mesh_jobs_in_flight, _mesh_jobs.size())


func _next_mesh_job_request() -> Dictionary:
	var candidates: Array[String] = []
	for key_value in loading_regions.keys():
		candidates.append(String(key_value))
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var stage_a: Dictionary = loading_regions[a]
		var stage_b: Dictionary = loading_regions[b]
		var pa := _stage_priority(String(stage_a["purpose"]))
		var pb := _stage_priority(String(stage_b["purpose"]))
		if pa != pb:
			return pa < pb
		var ka: Vector2i = stage_a["region_key"]
		var kb: Vector2i = stage_b["region_key"]
		var da := maxi(absi(ka.x - focus_region_key.x), absi(ka.y - focus_region_key.y))
		var db := maxi(absi(kb.x - focus_region_key.x), absi(kb.y - focus_region_key.y))
		if da == db:
			return ka.y < kb.y if ka.y != kb.y else ka.x < kb.x
		return da < db
	)
	for id in candidates:
		var stage: Dictionary = loading_regions[id]
		var submit_index: int = int(stage.get("submit_index", 0))
		var coordinates: Array[Vector2i] = stage["chunk_coordinates"]
		if submit_index < coordinates.size():
			return {"id": id, "coordinate": coordinates[submit_index], "index": submit_index}
	return {}


func _stage_priority(purpose: String) -> int:
	if purpose == "edit_transaction":
		return 0
	if purpose == "partial":
		return 1
	if purpose == "full":
		return 2
	return 3


func _complete_region_stage(id: String) -> void:
	if not loading_regions.has(id):
		return
	var stage: Dictionary = loading_regions[id]
	if int(stage["next_index"]) < (stage["chunk_coordinates"] as Array).size():
		return
	if global_rebuild_pending or stage["purpose"] == "full":
		_try_commit_global_rebuild()
		return
	if stage["purpose"] == "edit_transaction":
		_try_commit_edit_transaction()
		return
	loading_regions.erase(id)
	if stage["purpose"] == "partial":
		if _publish_partial_stage(id, stage):
			_clear_stream_error(id)
	else:
		_publish_region(stage["region_key"], stage["world_state"], stage["meshes"])
		_streamed_region_loads += 1
		_stage_retry_counts.erase(id)
		_clear_stream_error(id)
		if _operation_name == "initial_load" and loading_regions.is_empty():
			print("TERRAIN_STREAM_WINDOW_READY: focus=%s active_regions=%d active_chunks=%d queued_chunks=0 peak_queue=%d peak_mesh_upload_ms=%.3f" % [
				focus_region_key, active_regions.size(), chunk_nodes.size(), _peak_queue_depth, _peak_mesh_upload_ms,
			])
	_sync_world_state_index()
	_record_completed_operation(stage)
	_update_runtime_diagnostics()


func _publish_partial_stage(id: String, stage: Dictionary) -> bool:
	if not active_regions.has(id):
		return false
	var entry: Dictionary = active_regions[id]
	var region_nodes: Dictionary = entry["chunk_nodes"]
	for coordinate in stage["chunk_coordinates"]:
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		if not region_nodes.has(chunk_id) or not stage["meshes"].has(coordinate):
			_fail_region_stage(id, "Partial remesh was incomplete; old visible meshes retained")
			return false
	for coordinate in stage["chunk_coordinates"]:
		var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
		var node: MeshInstance3D = region_nodes[chunk_id]
		_replace_node_mesh(node, stage["meshes"][coordinate])
	_record_completed_operation(stage)
	_update_runtime_diagnostics()
	return true


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
	_global_rebuild_retry_count = 0
	for id in _full_rebuild_target_ids:
		_clear_stream_error(id)
	_full_rebuild_target_ids.clear()
	loading_regions.clear()
	_edit_transaction = {}
	var publish_started_usec := Time.get_ticks_usec()
	for stage in all_stages:
		_publish_region(stage["region_key"], stage["world_state"], stage["meshes"])
	_mesh_publish_usec_samples.append(Time.get_ticks_usec() - publish_started_usec)
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
	if _edit_transaction.has("target_ids") and (_edit_transaction["target_ids"] as Array).has(id):
		_edit_transaction["target_ids"].erase(id)
		loading_regions.erase(id)
	for chunk_id in entry["chunk_nodes"]:
		_release_chunk_node(chunk_id, entry["chunk_nodes"][chunk_id])
	active_regions.erase(id)
	world_states.erase(id)
	_streamed_region_unloads += 1


func _supersede_region_stage(id: String) -> void:
	if not loading_regions.has(id):
		return
	var stale_stage: Dictionary = loading_regions[id]
	loading_regions.erase(id)
	_superseded_stage_total += 1
	var region_key: Vector2i = stale_stage["region_key"]
	var purpose: String = stale_stage["purpose"]
	if not _edit_transaction.is_empty() \
		and int(_edit_transaction.get("revision", -1)) == edit_ledger.revision \
		and (_edit_transaction.get("target_ids", []) as Array).has(id):
		_start_edit_transaction_attempt()
	elif global_rebuild_pending:
		# Every full-rebuild snapshot is revision-pinned. Replace the complete staged
		# set together so no mixture of revisions can be published.
		loading_regions.clear()
		_full_rebuild_target_ids.clear()
		var desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
		var retained: Dictionary = {}
		for key in _region_keys_within_radius(focus_region_key, UNLOAD_RADIUS):
			retained[_region_id(key)] = true
		_ensure_full_rebuild_targets(desired, retained)
	elif purpose == "load":
		var desired := _region_keys_within_radius(focus_region_key, REQUEST_RADIUS)
		if not active_regions.has(id) and _contains_region(desired, region_key):
			_begin_region_stage(region_key, "load", ChunkGrid.all_coordinates())
	elif purpose == "partial":
		if active_regions.has(id):
			_begin_region_stage(region_key, "partial", stale_stage["chunk_coordinates"])
	_sync_world_state_index()
	_update_runtime_diagnostics()
	_update_status()


func _record_stream_error(id: String, message: String) -> void:
	var error_key := id if id != "" else "_global"
	_stream_errors_by_region[error_key] = message
	last_stream_error = message


func _clear_stream_error(id: String) -> void:
	_stream_errors_by_region.erase(id)
	if _stream_errors_by_region.is_empty():
		last_stream_error = ""
	else:
		var keys: Array = _stream_errors_by_region.keys()
		keys.sort()
		last_stream_error = String(_stream_errors_by_region[keys[-1]])


func _fail_region_stage(id: String, message: String) -> void:
	_record_stream_error(id, message)
	var failed_stage: Dictionary = loading_regions.get(id, {})
	loading_regions.erase(id)
	if not _edit_transaction.is_empty() and (_edit_transaction["target_ids"] as Array).has(id):
		_retry_edit_transaction(message)
		_sync_world_state_index()
		_update_runtime_diagnostics()
		_update_status()
		return
	if global_rebuild_pending:
		_global_rebuild_retry_count += 1
		if _global_rebuild_retry_count <= MAX_STAGE_RETRIES:
			last_stream_error = "%s; full rebuild retry %d/%d" % [message, _global_rebuild_retry_count, MAX_STAGE_RETRIES]
			_stream_errors_by_region[id if id != "" else "_global"] = last_stream_error
			loading_regions.clear()
			for target_id in _full_rebuild_target_ids:
				_begin_region_stage(_region_key_from_id(target_id), "full", ChunkGrid.all_coordinates())
		else:
			loading_regions.clear()
			global_rebuild_pending = false
			global_rebuild_reason = ""
			_full_rebuild_target_ids.clear()
			cave_section_enabled = _rendered_cave_section_enabled
			last_mesh_diagnostics["operation"] = "failed_pending_retry"
			last_brush_result = "%s; visible mesh set retained, press R to retry" % message
	elif id != "" and not active_regions.has(id) and failed_stage.get("purpose", "") == "load":
		var retries := int(_stage_retry_counts.get(id, 0)) + 1
		_stage_retry_counts[id] = retries
		_mesh_stage_retry_total += 1
		var key: Vector2i = failed_stage.get("region_key", Vector2i.ZERO)
		if retries <= MAX_STAGE_RETRIES and _contains_region(_region_keys_within_radius(focus_region_key, REQUEST_RADIUS), key):
			_begin_region_stage(key, "load", ChunkGrid.all_coordinates())
		else:
			last_stream_error = "%s; load retry limit reached, move focus away and back or press R" % message
			_stream_errors_by_region[id] = last_stream_error
	_sync_world_state_index()
	_update_runtime_diagnostics()
	_update_status()


func _record_completed_operation(stage: Dictionary) -> void:
	var queue_waits := _queue_wait_percentiles_ms()
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
		"mesh_queue_wait_p50_ms": queue_waits.x,
		"mesh_queue_wait_p95_ms": queue_waits.y,
		"mesh_queue_wait_total_ms": _sum_usec(_mesh_queue_wait_usec_samples) / 1000.0,
		"worker_queue_wait_p50_ms": _percentile_usec(_pool_queue_wait_usec_samples, 0.50),
		"worker_queue_wait_p95_ms": _percentile_usec(_pool_queue_wait_usec_samples, 0.95),
		"array_mesh_upload_p50_ms": _percentile_usec(_mesh_upload_usec_samples, 0.50),
		"mesh_publish_p95_ms": _percentile_usec(_mesh_publish_usec_samples, 0.95),
		"stage_timings_ms": _stage_timings_ms(),
		"peak_mesh_upload_ms": _peak_mesh_upload_ms,
		"max_active_region_count": _peak_active_region_count,
		"max_queue_depth": _peak_queue_depth,
		"operation_region_key": stage.get("region_key", focus_region_key),
		"global_edit_count": edit_ledger.get_edit_count(),
		"peak_mesh_jobs_in_flight": _peak_mesh_jobs_in_flight,
		"global_edit_last_sequence": edit_ledger.get_last_sequence(),
		"global_edit_revision": edit_ledger.revision,
		"last_support_region_count": _last_edit_support_region_count,
		"last_rebuild_region_count": _last_edit_rebuild_region_count,
		"last_rebuild_chunk_count": _last_edit_rebuild_chunk_count,
		"last_dirty_mesh_job_count": _last_edit_mesh_jobs,
		"edit_stage_state": "idle" if _edit_transaction.is_empty() else _edit_transaction.get("stage_state", "staging"),
		"last_edit_rejection": _last_edit_rejection,
	}


func _start_global_rebuild(operation_name: String) -> void:
	_begin_operation(operation_name)
	_global_rebuild_retry_count = 0
	_edit_transaction = {}
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


func _schedule_edit_transaction(operation: Dictionary) -> void:
	_begin_operation("global_brush_edit")
	var targets: Array[Dictionary] = []
	_last_edit_support_region_count = operation["support_regions"].size()
	_last_edit_rebuild_region_count = operation["rebuild_regions"].size()
	_last_edit_rebuild_chunk_count = 0
	_last_edit_rejection = ""
	for region_key in operation["rebuild_regions"]:
		var id := _region_id(region_key)
		if not active_regions.has(id) and not loading_regions.has(id):
			continue # Canonical ledger replays this command on the next load.
		var local_center := Vector3(
			operation["center_world"].x - float(region_key.x) * SpatialGrid.REGION_SIZE_X,
			operation["center_world"].y,
			operation["center_world"].z - float(region_key.y) * SpatialGrid.REGION_SIZE_Z
		)
		var chunks: Array[Vector2i] = ChunkGrid.affected_chunks_for_sphere(local_center, float(operation["radius"]))
		var needs_full_stage := not active_regions.has(id)
		if needs_full_stage:
			chunks = ChunkGrid.all_coordinates()
		if chunks.is_empty():
			continue
		targets.append({"region_key": region_key, "id": id, "chunks": chunks, "full": needs_full_stage})
		_last_edit_rebuild_chunk_count += chunks.size()
	if targets.is_empty():
		_edit_transaction = {}
		last_brush_result += "; no rebuild-dependent region is resident, future loads will replay it"
		_record_completed_operation({"region_key": focus_region_key, "purpose": "global_brush_edit"})
		return
	_edit_transaction = {
		"revision": edit_ledger.revision,
		"operation_sequence": operation["sequence"],
		"rebuild_regions": operation["rebuild_regions"],
		"target_ids": [],
		"targets": targets,
		"retries": 0,
		"stage_state": "staging",
		"support_region_count": operation["support_regions"].size(),
		"rebuild_region_count": operation["rebuild_regions"].size(),
		"rebuild_chunk_count": 0,
		"mesh_job_count": 0,
	}
	_start_edit_transaction_attempt()
	_update_runtime_diagnostics()


func _start_edit_transaction_attempt() -> void:
	if _edit_transaction.is_empty():
		return
	var target_ids: Array[String] = []
	for target in _edit_transaction["targets"]:
		var id: String = target["id"]
		if not active_regions.has(id) and not loading_regions.has(id):
			continue
		var region_key: Vector2i = target["region_key"]
		var chunks: Array[Vector2i] = target["chunks"]
		if not active_regions.has(id):
			chunks = ChunkGrid.all_coordinates()
		loading_regions.erase(id)
		_begin_region_stage(region_key, "edit_transaction", chunks)
		target_ids.append(id)
	_edit_transaction["target_ids"] = target_ids
	_edit_transaction["stage_state"] = "staging"
	_edit_transaction["rebuild_chunk_count"] = 0
	_edit_transaction["mesh_job_count"] = 0
	for target in _edit_transaction["targets"]:
		if target_ids.has(target["id"]):
			_edit_transaction["rebuild_chunk_count"] += target["chunks"].size()
	if target_ids.is_empty():
		_finish_edit_transaction("accepted; unloaded rebuild dependencies will apply it on load")


func _try_commit_edit_transaction() -> void:
	if _edit_transaction.is_empty() or int(_edit_transaction["revision"]) != edit_ledger.revision:
		return
	var target_ids: Array[String] = _edit_transaction["target_ids"]
	for id in target_ids:
		if not loading_regions.has(id):
			return
		var stage: Dictionary = loading_regions[id]
		if stage["purpose"] != "edit_transaction" \
			or int(stage["edit_revision"]) != edit_ledger.revision \
			or int(stage["next_index"]) < (stage["chunk_coordinates"] as Array).size():
			return
		for coordinate in stage["chunk_coordinates"]:
			if not stage["meshes"].has(coordinate):
				_fail_region_stage(id, "Edit transaction mesh set is incomplete; previous meshes retained")
				return
		if active_regions.has(id):
			var nodes: Dictionary = active_regions[id]["chunk_nodes"]
			for coordinate in stage["chunk_coordinates"]:
				if not nodes.has(ChunkGrid.stable_id(stage["region_key"], coordinate)):
					_fail_region_stage(id, "Edit transaction lost a visible chunk target; previous meshes retained")
					return
	# All targets and meshes validate before the first visible assignment.
	_edit_transaction["stage_state"] = "committing"
	var publish_started_usec := Time.get_ticks_usec()
	for id in target_ids:
		var stage: Dictionary = loading_regions[id]
		if active_regions.has(id):
			var nodes: Dictionary = active_regions[id]["chunk_nodes"]
			for coordinate in stage["chunk_coordinates"]:
				var chunk_id: String = ChunkGrid.stable_id(stage["region_key"], coordinate)
				_replace_node_mesh(nodes[chunk_id], stage["meshes"][coordinate])
		else:
			_publish_region(stage["region_key"], stage["world_state"], stage["meshes"])
		loading_regions.erase(id)
	_mesh_publish_usec_samples.append(Time.get_ticks_usec() - publish_started_usec)
	var committed_sequence: int = _edit_transaction["operation_sequence"]
	var committed_regions: int = target_ids.size()
	for id in target_ids:
		_clear_stream_error(id)
	_last_edit_mesh_jobs = int(_edit_transaction.get("mesh_job_count", 0))
	_edit_transaction = {}
	last_brush_result = "Global edit #%d mesh commit complete across %d resident region(s)" % [committed_sequence, committed_regions]
	_record_completed_operation({"region_key": focus_region_key, "purpose": "global_brush_edit"})
	_sync_world_state_index()
	_update_runtime_diagnostics()


func _finish_edit_transaction(message: String) -> void:
	if _edit_transaction.is_empty():
		return
	var sequence: int = _edit_transaction["operation_sequence"]
	_edit_transaction = {}
	last_brush_result = "Global edit #%d %s" % [sequence, message]
	_record_completed_operation({"region_key": focus_region_key, "purpose": "global_brush_edit"})
	_sync_world_state_index()
	_update_runtime_diagnostics()


func _retry_edit_transaction(failure_message: String) -> void:
	if _edit_transaction.is_empty():
		return
	_edit_transaction["retries"] = int(_edit_transaction["retries"]) + 1
	_mesh_stage_retry_total += 1
	if int(_edit_transaction["retries"]) <= MAX_STAGE_RETRIES:
		last_stream_error = "%s; retry %d/%d" % [failure_message, _edit_transaction["retries"], MAX_STAGE_RETRIES]
		for id in _edit_transaction["target_ids"]:
			_stream_errors_by_region[id] = last_stream_error
		_start_edit_transaction_attempt()
		return
	for id_value in (_edit_transaction["target_ids"] as Array).duplicate():
		var id: String = id_value
		if loading_regions.has(id) and loading_regions[id]["purpose"] == "edit_transaction":
			loading_regions.erase(id)
	_edit_transaction["stage_state"] = "failed_pending_retry"
	_edit_transaction["target_ids"] = []
	last_stream_error = "%s; accepted edit retained, press R to retry mesh build" % failure_message
	for id in _edit_transaction["target_ids"]:
		_stream_errors_by_region[id] = last_stream_error
	last_brush_result = "Accepted edit remains in the global ledger; visible meshes retained until retry succeeds"
	_update_runtime_diagnostics()


func _begin_operation(operation_name: String) -> void:
	_operation_name = operation_name
	_operation_chunk_ids.clear()
	_operation_sample_count = 0
	_operation_total_mesh_work_ms = 0.0
	_operation_stage_timings_usec.clear()
	_mesh_queue_wait_usec_samples.clear()
	_pool_queue_wait_usec_samples.clear()
	_mesh_upload_usec_samples.clear()
	_mesh_publish_usec_samples.clear()
	_operation_started_usec = Time.get_ticks_usec()


func _add_stage_timings(timings_usec: Dictionary) -> void:
	for key in timings_usec:
		_operation_stage_timings_usec[key] = int(_operation_stage_timings_usec.get(key, 0)) + int(timings_usec[key])


func _stage_timings_ms() -> Dictionary:
	var result: Dictionary = {}
	for key in _operation_stage_timings_usec:
		result[key] = float(_operation_stage_timings_usec[key]) / 1000.0
	return result


func _queue_wait_percentiles_ms() -> Vector2:
	if _mesh_queue_wait_usec_samples.is_empty():
		return Vector2.ZERO
	var samples := _mesh_queue_wait_usec_samples.duplicate()
	samples.sort()
	return Vector2(
		float(samples[maxi(0, ceili(float(samples.size()) * 0.50) - 1)]) / 1000.0,
		float(samples[maxi(0, ceili(float(samples.size()) * 0.95) - 1)]) / 1000.0
	)


func _percentile_usec(samples: Array[int], fraction: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var index := clampi(ceili(float(sorted_samples.size()) * fraction) - 1, 0, sorted_samples.size() - 1)
	return float(sorted_samples[index]) / 1000.0


func _sum_usec(samples: Array[int]) -> int:
	var total := 0
	for sample in samples:
		total += sample
	return total


func _sync_world_state_index() -> void:
	world_states.clear()
	for id_value in active_regions:
		var id: String = id_value
		world_states[id] = active_regions[id]["world_state"]
	for id_value in loading_regions:
		var id: String = id_value
		world_states[id] = loading_regions[id]["world_state"]
	world_state = _state_for_region(focus_region_key)


func _state_for_region(region_key: Vector2i) -> RefCounted:
	var id := _region_id(region_key)
	if active_regions.has(id):
		return active_regions[id]["world_state"]
	if loading_regions.has(id):
		return loading_regions[id]["world_state"]
	return WorldState.new(WorldState.DEMO_SEED, region_key, edit_ledger)


func _sample_world_density(world_position: Vector3) -> float:
	var mapped: Dictionary = SpatialGrid.world_to_region_local(world_position)
	if not mapped.get("valid", false):
		return -INF
	var key: Vector2i = mapped["region_key"]
	var state := _state_for_region(key)
	return state.sample_density(mapped["local_position"], cave_section_enabled)


func _apply_brush_at(screen_position: Vector2) -> void:
	if global_rebuild_pending or not active_regions.has(_region_id(focus_region_key)):
		last_brush_result = "Focused region is not ready for edits; no edit added"
		_update_status()
		return
	if not _edit_transaction.is_empty():
		last_brush_result = "Previous accepted edit is waiting for a coherent mesh commit; no new edit added"
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
	_accept_brush_at_world(world_hit)


func _accept_brush_at_world(world_hit: Vector3) -> bool:
	if global_rebuild_pending or not _edit_transaction.is_empty():
		last_brush_result = "Mesh publication is busy; no edit added"
		_update_status()
		return false
	if not edit_ledger.add_sphere(selected_brush_mode, world_hit, BRUSH_RADIUS):
		_last_edit_rejection = edit_ledger.last_rejection_reason
		last_brush_result = "Edit rejected (%s); terrain unchanged" % _last_edit_rejection
		_update_status()
		return false
	var operation: Dictionary = edit_ledger.get_last_operation_snapshot()
	var support_regions: Array[Vector2i] = operation["support_regions"]
	var dependency_regions: Array[Vector2i] = operation["dependency_regions"]
	var rebuild_regions: Array[Vector2i] = operation["rebuild_regions"]
	_last_edit_rejection = ""
	var mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	last_brush_result = "%s #%d accepted globally at %s; %d support + %d dependent rebuild region(s)" % [
		mode_name, operation["sequence"], world_hit, support_regions.size(), dependency_regions.size(),
	]
	_schedule_edit_transaction(operation)
	_update_status()
	return true


func _region_id(region_key: Vector2i) -> String:
	return "%d,%d" % [region_key.x, region_key.y]


func _region_key_from_id(region_id: String) -> Vector2i:
	var parts := region_id.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


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


func _frame_time_percentiles() -> Vector3:
	if _frame_sample_count == 0:
		return Vector3.ZERO
	var sorted: Array[float] = []
	for index in range(_frame_sample_count):
		sorted.append(_frame_time_samples[index])
	sorted.sort()
	return Vector3(
		sorted[maxi(0, ceili(float(sorted.size()) * 0.50) - 1)],
		sorted[maxi(0, ceili(float(sorted.size()) * 0.95) - 1)],
		sorted[maxi(0, ceili(float(sorted.size()) * 0.99) - 1)]
	)


func _queued_chunk_count() -> int:
	var total := 0
	for stage_value in loading_regions.values():
		var stage: Dictionary = stage_value
		total += (stage["chunk_coordinates"] as Array).size() - int(stage["next_index"])
	return total


func _queued_mesh_job_count() -> int:
	return _queued_chunk_count()


func _update_runtime_diagnostics() -> void:
	_peak_active_region_count = maxi(_peak_active_region_count, active_regions.size())
	_peak_queue_depth = maxi(_peak_queue_depth, _queued_chunk_count())
	_peak_mesh_job_queue_depth = maxi(_peak_mesh_job_queue_depth, _queued_mesh_job_count())
	if last_mesh_diagnostics.is_empty():
		last_mesh_diagnostics = {}
	last_mesh_diagnostics["active_region_count"] = active_regions.size()
	last_mesh_diagnostics["preview_region_count"] = active_regions.size()
	last_mesh_diagnostics["active_chunk_count"] = chunk_nodes.size()
	last_mesh_diagnostics["requested_region_count"] = (REQUEST_RADIUS * 2 + 1) * (REQUEST_RADIUS * 2 + 1)
	last_mesh_diagnostics["loading_region_count"] = loading_regions.size()
	last_mesh_diagnostics["queued_chunk_count"] = _queued_chunk_count()
	last_mesh_diagnostics["queued_mesh_job_count"] = _queued_mesh_job_count()
	last_mesh_diagnostics["peak_active_region_count"] = _peak_active_region_count
	last_mesh_diagnostics["peak_queue_depth"] = _peak_queue_depth
	last_mesh_diagnostics["peak_mesh_job_queue_depth"] = _peak_mesh_job_queue_depth
	last_mesh_diagnostics["last_mesh_upload_ms"] = _last_mesh_upload_ms
	last_mesh_diagnostics["peak_mesh_upload_ms"] = _peak_mesh_upload_ms
	last_mesh_diagnostics["last_process_work_ms"] = _last_process_work_ms
	last_mesh_diagnostics["peak_process_work_ms"] = _peak_process_work_ms
	last_mesh_diagnostics["last_frame_ms"] = _last_frame_ms
	last_mesh_diagnostics["peak_frame_ms"] = _peak_frame_ms
	last_mesh_diagnostics["streamed_region_loads"] = _streamed_region_loads
	last_mesh_diagnostics["streamed_region_unloads"] = _streamed_region_unloads
	last_mesh_diagnostics["global_rebuild_pending"] = global_rebuild_pending
	last_mesh_diagnostics["max_active_region_count"] = MAX_ACTIVE_REGIONS
	last_mesh_diagnostics["max_mesh_uploads_per_frame"] = MAX_MESH_UPLOADS_PER_FRAME
	last_mesh_diagnostics["peak_mesh_uploads_per_frame"] = _peak_mesh_uploads_per_frame
	last_mesh_diagnostics["mesh_jobs_in_flight"] = _mesh_jobs.size()
	last_mesh_diagnostics["peak_mesh_jobs_in_flight"] = _peak_mesh_jobs_in_flight
	last_mesh_diagnostics["global_edit_count"] = edit_ledger.get_edit_count()
	last_mesh_diagnostics["global_edit_limit"] = BrushEditState.MAX_EDITS
	last_mesh_diagnostics["global_edit_last_sequence"] = edit_ledger.get_last_sequence()
	last_mesh_diagnostics["global_edit_revision"] = edit_ledger.revision
	last_mesh_diagnostics["last_support_region_count"] = _last_edit_support_region_count
	last_mesh_diagnostics["last_rebuild_region_count"] = _last_edit_rebuild_region_count
	last_mesh_diagnostics["last_rebuild_chunk_count"] = _last_edit_rebuild_chunk_count
	last_mesh_diagnostics["last_dirty_mesh_job_count"] = _last_edit_mesh_jobs
	last_mesh_diagnostics["edit_stage_state"] = "idle" if _edit_transaction.is_empty() else _edit_transaction.get("stage_state", "staging")
	last_mesh_diagnostics["last_edit_rejection"] = _last_edit_rejection
	last_mesh_diagnostics["mesh_stage_retry_total"] = _mesh_stage_retry_total
	last_mesh_diagnostics["superseded_stage_total"] = _superseded_stage_total
	last_mesh_diagnostics["resident_region_count"] = active_regions.size()
	last_mesh_diagnostics["queued_region_count"] = loading_regions.size()
	var frame_percentiles := _frame_time_percentiles()
	last_mesh_diagnostics["frame_time_p50_ms"] = frame_percentiles.x
	last_mesh_diagnostics["frame_time_p95_ms"] = frame_percentiles.y
	last_mesh_diagnostics["frame_time_p99_ms"] = frame_percentiles.z


func _update_status() -> void:
	var state := _state_for_region(focus_region_key)
	var seed: int = state.world_seed if state != null else WorldState.DEMO_SEED
	var generator_version: int = state.generator_version if state != null else Field.GENERATOR_VERSION
	var selected_mode_name := "FILL" if selected_brush_mode == BrushEditState.Mode.FILL else "CARVE"
	var queue_depth := _queued_chunk_count()
	var transaction_state := "idle" if _edit_transaction.is_empty() else String(_edit_transaction.get("stage_state", "staging"))
	var status := "P1.0C global SDF edits  |  seed %d  |  generator v%d\nFocus region: %s  |  resident/active: %d/%d  |  queued regions: %d  |  queued chunks/jobs: %d/%d\nWASD/arrows: move focus    Right-drag: orbit    Wheel: zoom    Left: carve    Shift+left: fill\nC: global cave section    R: regenerate    X: reset commands supported by focused region\nSelected: %s    Global edits: %d/%d  |  seq/rev: %d/%d  |  Radius: %.2f\nLast edit: %d support / %d rebuild regions, %d chunks, %d uploads  |  commit: %s\nWorker jobs: %d/%d  |  max uploads/frame: %d  |  last/peak upload: %.1f/%.1f ms  |  peak frame: %.1f ms\n" % [
		seed,
		generator_version,
		focus_region_key,
		active_regions.size(),
		MAX_ACTIVE_REGIONS,
		loading_regions.size(),
		queue_depth,
		_queued_mesh_job_count(),
		selected_mode_name,
		edit_ledger.get_edit_count(),
		BrushEditState.MAX_EDITS,
		edit_ledger.get_last_sequence(),
		edit_ledger.revision,
		BRUSH_RADIUS,
		_last_edit_support_region_count,
		_last_edit_rebuild_region_count,
		_last_edit_rebuild_chunk_count,
		_last_edit_mesh_jobs,
		transaction_state,
		_mesh_jobs.size(),
		MAX_MESH_JOBS_IN_FLIGHT,
		MAX_MESH_UPLOADS_PER_FRAME,
		_last_mesh_upload_ms,
		_peak_mesh_upload_ms,
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
