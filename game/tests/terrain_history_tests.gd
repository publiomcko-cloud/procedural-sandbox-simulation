extends SceneTree

const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const Scene := preload("res://scenes/terrain_demo.tscn")
const SEED := 424242
const REGION_KEYS := [
	Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
	Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-2, -1),
	Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-2, 1),
]
var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("TERRAIN_HISTORY_TEST: Godot=%s target_edits=256 distributed_regions=%d" % [Engine.get_version_info().string, REGION_KEYS.size()])
	var ledger := _make_full_ledger()
	_test_capacity_and_exact_spatial_filter(ledger)
	await _test_256_sequential_scene_edits()
	await _test_revision_supersession_and_rapid_movement()
	if failures == 0:
		print("TERRAIN_HISTORY_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("TERRAIN_HISTORY_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)


func _make_full_ledger() -> RefCounted:
	var ledger: RefCounted = BrushState.new(SEED, Field.GENERATOR_VERSION)
	for index in range(BrushState.MAX_EDITS):
		var key: Vector2i = REGION_KEYS[index % REGION_KEYS.size()]
		var origin := Spatial.region_origin_world(key)
		var center: Vector3
		var radius := 1.25
		if index % 8 == 0:
			# Exercise four-region support without sacrificing the per-region spread.
			center = origin + Vector3(15.35, 3.2, 11.35)
		else:
			var lane := float((index / REGION_KEYS.size()) % 4) * 0.22
			center = origin + Vector3(7.2 + lane, 3.2, 5.2 + lane)
		var mode := BrushState.Mode.CARVE if index % 2 == 0 else BrushState.Mode.FILL
		var accepted: bool = ledger.add_sphere(mode, center, radius)
		_check(accepted, "distributed command %d is accepted" % index)
	return ledger


func _test_capacity_and_exact_spatial_filter(ledger: RefCounted) -> void:
	_check(BrushState.MAX_EDITS >= 256 and ledger.get_edit_count() == 256, "bounded history accepts all 256 sequential commands")
	_check(ledger.get_last_sequence() == 255 and ledger.revision == 256, "global sequence and revision remain monotonic through command 256")
	var touched_regions: Dictionary = {}
	for operation in ledger.get_operations_snapshot():
		for key in operation["support_regions"]:
			touched_regions["%d,%d" % [key.x, key.y]] = true
	_check(touched_regions.size() >= 10, "256 commands cover at least ten signed regions")
	var before_count: int = ledger.get_edit_count()
	var before_revision: int = ledger.revision
	var before_sequence: int = ledger.get_last_sequence()
	_check(not ledger.add_sphere(BrushState.Mode.CARVE, Vector3(8.0, 3.0, 6.0), 1.25), "257th valid command is rejected at the documented finite cap")
	_check(ledger.last_rejection_reason == "ledger_capacity_exceeded", "257th rejection identifies capacity rather than invalid brush data")
	_check(ledger.get_edit_count() == before_count and ledger.revision == before_revision and ledger.get_last_sequence() == before_sequence, "capacity rejection cannot silently evict or consume sequence/revision")
	_check(not ledger.add_sphere(BrushState.Mode.CARVE, Vector3(NAN, 3.0, 6.0), 1.25), "invalid input remains rejected when ledger is full")
	_check(ledger.last_rejection_reason == "non_finite_input", "invalid input reason takes precedence over full-capacity status")

	var full_snapshot: Dictionary = ledger.get_meshing_snapshot()
	var compare_keys: Array[Vector2i] = [Vector2i(-2, -2), Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 1)]
	var compare_chunks: Array[Vector2i] = [Vector2i.ZERO, Vector2i(3, 3)]
	var max_candidates := 0
	for key in compare_keys:
		for coordinate in compare_chunks:
			var filtered: Dictionary = ledger.get_meshing_snapshot_for_chunk(key, coordinate)
			max_candidates = maxi(max_candidates, int(filtered["candidate_operation_count"]))
			var bounds: Vector4i = Grid.cell_bounds(coordinate)
			for y in range(Grid.CELL_COUNT_Y + 1):
				for z in range(bounds.z, bounds.w + 1):
					for x in range(bounds.x, bounds.y + 1):
						var local := Grid.MIN_BOUND + Vector3(x, y, z) * Grid.SAMPLE_STEP
						var expected := BrushState.sample_density_snapshot(SEED, key, local, false, full_snapshot)
						var actual := BrushState.sample_density_snapshot(SEED, key, local, false, filtered)
						if expected != actual:
							_check(false, "spatial subset exactly preserves full ordered SDF at %s %s" % [key, local])
							return
			_check(true, "all lattice samples match full replay for signed region %s chunk %s" % [key, coordinate])
	_check(max_candidates < 256, "conservative chunk filter removes only provably dominated distant operations (max candidates=%d)" % max_candidates)

	for key in [Vector2i(-2, -2), Vector2i.ZERO, Vector2i(1, 1)]:
		for coordinate in [Vector2i.ZERO, Vector2i(3, 3)]:
			var expected_mesh: Dictionary = Mesher.build_chunk_mesh(SEED, key, coordinate, false, ledger)
			var filtered_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(key, coordinate)
			var actual_data: Dictionary = Mesher.build_chunk_cpu_data(SEED, key, coordinate, false, filtered_snapshot)
			var actual_mesh: Dictionary = Mesher.mesh_from_cpu_data(actual_data)
			_check(_meshes_equal(expected_mesh["mesh"], actual_mesh["mesh"]), "filtered 256-operation mesh and normals equal full replay at %s/%s" % [key, coordinate])

	var count_before_x: int = ledger.get_edit_count()
	var sequence_before_x: int = ledger.get_last_sequence()
	var reset: Dictionary = ledger.clear_for_region(Vector2i(-2, -2))
	_check(int(reset["removed_count"]) > 0 and ledger.get_edit_count() < count_before_x, "focused X removes every command whose geometric support touches its region")
	_check(ledger.get_last_sequence() == sequence_before_x and ledger.get_edit_count() > 0, "focused reset preserves unrelated history and never rewinds sequence")
	_check(ledger.add_sphere(BrushState.Mode.CARVE, Vector3(-24.0, 3.2, -18.0), 1.25), "reset frees capacity for a later edit")
	_check(ledger.get_last_sequence() == sequence_before_x + 1, "post-reset command receives a fresh monotonic sequence")
	print("TERRAIN_HISTORY_FILTER: total_ops=256 max_chunk_candidates=%d process_static_bytes=%d" % [
		max_candidates, int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	])


func _test_256_sequential_scene_edits() -> void:
	var scene: Node = Scene.instantiate()
	root.add_child(scene)
	await _wait_for_window(scene)
	var latencies := PackedInt64Array()
	var mesh_queue_waits := PackedInt64Array()
	var worker_queue_waits := PackedInt64Array()
	var publish_times := PackedInt64Array()
	var previous_key := Vector2i.ZERO
	for key in REGION_KEYS:
		if key != previous_key:
			var delta := Vector3(
				float(key.x - previous_key.x) * Spatial.REGION_SIZE_X,
				0.0,
				float(key.y - previous_key.y) * Spatial.REGION_SIZE_Z
			)
			scene.call("_move_focus", delta)
			await _wait_for_window(scene)
			previous_key = key
		for local_index in range(BrushState.MAX_EDITS / REGION_KEYS.size()):
			var index := key_index(key) * (BrushState.MAX_EDITS / REGION_KEYS.size()) + local_index
			var origin := Spatial.region_origin_world(key)
			var center := origin + Vector3(7.4 + float(local_index % 4) * 0.15, 3.2, 5.4 + float(local_index % 4) * 0.15)
			if local_index == 0:
				center = origin + Vector3(15.35, 3.2, 11.35)
			scene.set("selected_brush_mode", BrushState.Mode.CARVE if index % 2 == 0 else BrushState.Mode.FILL)
			var started := Time.get_ticks_usec()
			var accepted: bool = scene.call("_accept_brush_at_world", center)
			_check(accepted, "scene accepts sequential global edit %d across region %s" % [index, key])
			if accepted:
				await _wait_for_transaction(scene)
				latencies.append(Time.get_ticks_usec() - started)
				var operation_metrics: Dictionary = scene.get("last_mesh_diagnostics")
				mesh_queue_waits.append(int(round(float(operation_metrics.get("mesh_queue_wait_p95_ms", 0.0)) * 1000.0)))
				worker_queue_waits.append(int(round(float(operation_metrics.get("worker_queue_wait_p95_ms", 0.0)) * 1000.0)))
				publish_times.append(int(round(float(operation_metrics.get("mesh_publish_p95_ms", 0.0)) * 1000.0)))
	var ledger: RefCounted = scene.get("edit_ledger")
	var diagnostics: Dictionary = scene.get("last_mesh_diagnostics")
	_check(ledger.get_edit_count() == 256 and ledger.get_last_sequence() == 255, "all 256 sequential scene commands remain in the global ledger")
	_check(diagnostics.get("peak_mesh_jobs_in_flight", 0) <= 4 and diagnostics.get("max_active_region_count", 25) <= 25, "scene stress preserves four-worker and 25-region bounds")
	_check(diagnostics.get("peak_queue_depth", 400) <= 400 and diagnostics.get("peak_mesh_uploads_per_frame", 2) <= 2, "scene stress preserves queued-chunk and per-frame ArrayMesh bounds")
	print("TERRAIN_HISTORY_E2E: accepted=256 regions=%d latency_p50/p95_ms=%.3f/%.3f samples=%d memory_static_bytes=%d mesh_bytes_estimate=%d queue_peak=%d peak_workers=%d mesh_queue_p95_max_ms=%.3f worker_queue_p95_max_ms=%.3f publish_p95_max_ms=%.3f retries=%d frame_p95/p99_ms=%.3f/%.3f" % [
		REGION_KEYS.size(), _percentile(latencies, 0.50) / 1000.0, _percentile(latencies, 0.95) / 1000.0,
		latencies.size(), int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		scene.call("_get_mesh_attribute_bytes_estimate"), diagnostics.get("peak_queue_depth", 0),
		diagnostics.get("peak_mesh_jobs_in_flight", 0), _max_usec(mesh_queue_waits) / 1000.0,
		_max_usec(worker_queue_waits) / 1000.0, _max_usec(publish_times) / 1000.0, diagnostics.get("mesh_stage_retry_total", 0),
		diagnostics.get("frame_time_p95_ms", 0.0), diagnostics.get("frame_time_p99_ms", 0.0),
	])

	var first_key := REGION_KEYS[0]
	var far_target := Vector3(4 * Spatial.REGION_SIZE_X + 8.0, 3.2, 4 * Spatial.REGION_SIZE_Z + 6.0)
	scene.set("orbit_target", far_target)
	scene.call("_update_camera")
	scene.call("_update_focus_key")
	scene.call("_reconcile_region_window")
	await _wait_for_window(scene)
	var return_target := Spatial.region_origin_world(first_key) + Vector3(8.0, 3.2, 6.0)
	scene.set("orbit_target", return_target)
	scene.call("_update_camera")
	scene.call("_update_focus_key")
	scene.call("_reconcile_region_window")
	await _wait_for_window(scene)
	var returned_entry: Dictionary = scene.get("active_regions")["%d,%d" % [first_key.x, first_key.y]]
	var corner_id: String = Grid.stable_id(first_key, Vector2i(3, 3))
	var expected: Dictionary = Mesher.build_chunk_mesh(SEED, first_key, Vector2i(3, 3), false, ledger)
	_check(_meshes_equal(returned_entry["chunk_nodes"][corner_id].mesh, expected["mesh"]), "edited negative corner region reconstructs exactly after unload and reentry")

	var sequence_before_x: int = ledger.get_last_sequence()
	var before_x_count: int = ledger.get_edit_count()
	var reset_event := InputEventKey.new()
	reset_event.keycode = KEY_X
	reset_event.pressed = true
	scene.call("_unhandled_input", reset_event)
	await _wait_for_global_rebuild(scene)
	_check(ledger.get_edit_count() < before_x_count and ledger.get_last_sequence() == sequence_before_x, "X removes focused-support edits without rewinding global history")
	var next_center: Vector3 = return_target
	var next_accepted: bool = scene.call("_accept_brush_at_world", next_center)
	_check(next_accepted, "X-freed capacity admits a later scene operation")
	if next_accepted:
		await _wait_for_transaction(scene)
		_check(ledger.get_last_sequence() == sequence_before_x + 1, "post-X scene operation has a new global sequence")
	scene.queue_free()
	await process_frame


func _test_revision_supersession_and_rapid_movement() -> void:
	var scene: Node = Scene.instantiate()
	root.add_child(scene)
	await _wait_for_window(scene)
	var retry_before: int = scene.get("last_mesh_diagnostics").get("mesh_stage_retry_total", 0)
	scene.call("_move_focus", Vector3(64.0, 0.0, 0.0))
	var accepted: bool = scene.call("_accept_brush_at_world", Vector3(72.0, 3.2, 6.0))
	_check(accepted, "edit revision changes while the newly requested region window is loading")
	if accepted:
		await _wait_for_transaction(scene)
		await _wait_for_window(scene)
	var metrics: Dictionary = scene.get("last_mesh_diagnostics")
	_check(metrics.get("superseded_stage_total", 0) > 0, "obsolete load stages are classified as expected supersessions")
	_check(metrics.get("mesh_stage_retry_total", 0) == retry_before, "expected revision supersession does not spend real-failure retry budget")
	_check(scene.get("last_stream_error") == "", "successful current-revision work clears no stale supersession banner because none was recorded")
	for target in [Vector3(-64.0, 0.0, 0.0), Vector3(96.0, 0.0, 0.0), Vector3.ZERO]:
		var current: Vector2i = scene.get("focus_region_key")
		var destination: Vector2i = Spatial.world_to_region_local(scene.get("orbit_target") + target).get("region_key", Vector2i.ZERO)
		scene.call("_move_focus", target)
		await process_frame
		_check(scene.get("active_regions").size() <= 25 and scene.get("chunk_nodes").size() <= 400 and scene.get("_mesh_jobs").size() <= 4, "rapid focus movement preserves 25-region/400-chunk/four-worker bounds from %s to %s" % [current, destination])
	await _wait_for_window(scene)
	_check(scene.get("last_stream_error") == "" and scene.get("loading_regions").is_empty(), "rapid movement settles without a stale stream error or stranded stage")
	scene.queue_free()
	await process_frame


func _wait_for_window(scene: Node) -> void:
	for _frame in range(6000):
		if not scene.get("global_rebuild_pending") and scene.get("loading_regions").is_empty():
			var focus: Vector2i = scene.get("focus_region_key")
			var ready := true
			for z in range(focus.y - 1, focus.y + 2):
				for x in range(focus.x - 1, focus.x + 2):
					if not scene.get("active_regions").has("%d,%d" % [x, z]):
						ready = false
			if ready:
				return
		await process_frame
	_check(false, "requested 3x3 region window settles within bounded frames")


func _wait_for_transaction(scene: Node) -> void:
	for _frame in range(1200):
		if scene.get("_edit_transaction").is_empty():
			return
		await process_frame
	_check(false, "accepted edit transaction settles without dropping its command")


func _wait_for_global_rebuild(scene: Node) -> void:
	for _frame in range(6000):
		if not scene.get("global_rebuild_pending") and scene.get("loading_regions").is_empty():
			return
		await process_frame
	_check(false, "global rebuild completes after X")


func _meshes_equal(left: ArrayMesh, right: ArrayMesh) -> bool:
	if left.get_surface_count() != right.get_surface_count():
		return false
	if left.get_surface_count() == 0:
		return true
	var left_arrays: Array = left.surface_get_arrays(0)
	var right_arrays: Array = right.surface_get_arrays(0)
	return left_arrays[Mesh.ARRAY_VERTEX] == right_arrays[Mesh.ARRAY_VERTEX] \
		and left_arrays[Mesh.ARRAY_NORMAL] == right_arrays[Mesh.ARRAY_NORMAL]


func _percentile(values: PackedInt64Array, fraction: float) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)]


func _max_usec(values: PackedInt64Array) -> int:
	var result := 0
	for value in values:
		result = maxi(result, value)
	return result


func key_index(key: Vector2i) -> int:
	return REGION_KEYS.find(key)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("TERRAIN_HISTORY_ASSERTION_FAILED: " + message)
