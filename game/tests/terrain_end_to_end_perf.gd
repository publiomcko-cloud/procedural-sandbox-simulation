extends SceneTree

const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const MAX_FRAMES := 3000
const CLICK_REPEATS := 5

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "end-to-end benchmark scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	var cold_started := Time.get_ticks_usec()
	root.add_child(scene)
	await _wait_for_window(scene)
	var cold_elapsed := float(Time.get_ticks_usec() - cold_started) / 1000.0
	print("TERRAIN_PERF_SCENE: initial_window_regions=%d chunks=%d cold_start_ms=%.3f cpu_threads=%d" % [
		scene.get("active_regions").size(), scene.get("chunk_nodes").size(), cold_elapsed, OS.get_processor_count(),
	])

	var crossing_samples := PackedInt64Array()
	for delta_x in [16.0, 16.0, 16.0, 16.0, 16.0]:
		var started := Time.get_ticks_usec()
		scene.call("_move_focus", Vector3(delta_x, 0.0, 0.0))
		await _wait_for_window(scene)
		crossing_samples.append(Time.get_ticks_usec() - started)
	var crossing_metrics: Dictionary = scene.get("last_mesh_diagnostics")
	print("TERRAIN_PERF_REGION_CROSSING: samples=%d p50/p95_ms=%.3f/%.3f values_ms=%s frame_p95/p99_ms=%.3f/%.3f process_peak_ms=%.3f" % [
		crossing_samples.size(), _percentile(crossing_samples, 0.50) / 1000.0,
		_percentile(crossing_samples, 0.95) / 1000.0, _format_samples(crossing_samples),
		crossing_metrics.get("frame_time_p95_ms", 0.0), crossing_metrics.get("frame_time_p99_ms", 0.0),
		crossing_metrics.get("peak_process_work_ms", 0.0),
	])
	# Return to region zero; click samples begin with an empty global command log.
	var current_key: Vector2i = scene.get("focus_region_key")
	scene.call("_move_focus", Vector3(-float(current_key.x) * Spatial.REGION_SIZE_X, 0.0, -float(current_key.y) * Spatial.REGION_SIZE_Z))
	await _wait_for_window(scene)
	var click_samples := PackedInt64Array()
	for index in range(CLICK_REPEATS):
		var world_x := 7.2 + float(index) * 0.22
		var target := Vector3(world_x, _surface_height(scene, world_x, 3.0), 3.0)
		click_samples.append(await _dispatch_click_to_visible(scene, target))
	print("TERRAIN_PERF_CLICK_VISIBLE: scenario=single_region ledger_before=0..4 samples=%d p50/p95_ms=%.3f/%.3f values_ms=%s" % [
		click_samples.size(), _percentile(click_samples, 0.50) / 1000.0,
		_percentile(click_samples, 0.95) / 1000.0, _format_samples(click_samples),
	])
	_check(click_samples.size() == CLICK_REPEATS and scene.get("edit_ledger").get_edit_count() == CLICK_REPEATS, "real viewport input events accept and commit five visible edits")

	var seam_samples := PackedInt64Array()
	var seam_support_counts := PackedInt32Array()
	var seam_target := Vector3.ZERO
	for index in range(CLICK_REPEATS):
		var seam_x := 15.82
		var seam_z := 0.5 + float(index) * 2.5
		seam_target = Vector3(seam_x, _surface_height(scene, seam_x, seam_z), seam_z)
		seam_samples.append(await _dispatch_click_to_visible(scene, seam_target, Vector3(0.0, 24.0, 0.01)))
		seam_support_counts.append(int(scene.get("last_mesh_diagnostics").get("last_support_region_count", 0)))
	var seam_metrics: Dictionary = scene.get("last_mesh_diagnostics").duplicate(true)
	print("TERRAIN_PERF_CLICK_VISIBLE: scenario=two_region_seam ledger_before=5..9 samples=%d p50/p95_ms=%.3f/%.3f values_ms=%s support=%d rebuild_regions=%d chunks=%d queue/pool_p95_ms=%.3f/%.3f upload_p50/publish_p95_ms=%.3f/%.3f stage_ms=%s frame_p95/p99_ms=%.3f/%.3f" % [
		seam_samples.size(), _percentile(seam_samples, 0.50) / 1000.0, _percentile(seam_samples, 0.95) / 1000.0,
		_format_samples(seam_samples), seam_metrics.get("last_support_region_count", 0), seam_metrics.get("last_rebuild_region_count", 0),
		seam_metrics.get("last_rebuild_chunk_count", 0), seam_metrics.get("mesh_queue_wait_p95_ms", 0.0),
		seam_metrics.get("worker_queue_wait_p95_ms", 0.0), seam_metrics.get("array_mesh_upload_p50_ms", 0.0),
		seam_metrics.get("mesh_publish_p95_ms", 0.0), JSON.stringify(seam_metrics.get("stage_timings_ms", {})),
		seam_metrics.get("frame_time_p95_ms", 0.0), seam_metrics.get("frame_time_p99_ms", 0.0),
	])
	var every_seam_crosses := true
	for support_count in seam_support_counts:
		every_seam_crosses = every_seam_crosses and support_count >= 2
	_check(every_seam_crosses, "all near-seam viewport events exercise multi-region support operations")

	var ledger: RefCounted = scene.get("edit_ledger")
	while ledger.get_edit_count() < BrushState.MAX_EDITS - 1:
		var sequence: int = ledger.get_edit_count()
		var mode := BrushState.Mode.CARVE if sequence % 2 == 0 else BrushState.Mode.FILL
		var offset := float(sequence % 3) * 0.04
		_check(ledger.add_sphere(mode, Vector3(8.0 + offset, 3.0, 3.0 + offset), 0.58), "32-command benchmark ledger setup accepts bounded command %d" % sequence)
	scene.call("_start_global_rebuild", "performance_ledger_prep")
	await _wait_for_window(scene)
	var full_ledger_started := Time.get_ticks_usec()
	var full_ledger_accepted: bool = scene.call("_accept_brush_at_world", Vector3(15.8, 4.0, 3.0))
	_check(full_ledger_accepted, "256th command is accepted through the canonical world-space edit path")
	await _wait_for_transaction(scene)
	var full_ledger_latency := Time.get_ticks_usec() - full_ledger_started
	var full_ledger_metrics: Dictionary = scene.get("last_mesh_diagnostics").duplicate(true)
	var ledger_before_final: int = ledger.get_edit_count()
	print("TERRAIN_PERF_ACCEPTED_TO_VISIBLE: scenario=two_region_seam ledger_before=%d latency_ms=%.3f support=%d rebuild_regions=%d chunks=%d queue/pool_p95_ms=%.3f/%.3f upload_p50/publish_p95_ms=%.3f/%.3f stage_ms=%s frame_p95/p99_ms=%.3f/%.3f" % [
		ledger_before_final,
		float(full_ledger_latency) / 1000.0, full_ledger_metrics.get("last_support_region_count", 0),
		full_ledger_metrics.get("last_rebuild_region_count", 0), full_ledger_metrics.get("last_rebuild_chunk_count", 0),
		full_ledger_metrics.get("mesh_queue_wait_p95_ms", 0.0), full_ledger_metrics.get("worker_queue_wait_p95_ms", 0.0),
		full_ledger_metrics.get("array_mesh_upload_p50_ms", 0.0), full_ledger_metrics.get("mesh_publish_p95_ms", 0.0),
		JSON.stringify(full_ledger_metrics.get("stage_timings_ms", {})),
		full_ledger_metrics.get("frame_time_p95_ms", 0.0), full_ledger_metrics.get("frame_time_p99_ms", 0.0),
	])
	_check(ledger.get_edit_count() == BrushState.MAX_EDITS and full_ledger_metrics.get("last_rebuild_chunk_count", 0) > 0, "256th global operation commits through the same coherent rebuild path")

	var old_region_start := Time.get_ticks_usec()
	scene.call("_move_focus", Vector3(64.0, 0.0, 0.0))
	await _wait_for_window(scene)
	var edited_region_return_start := Time.get_ticks_usec()
	scene.call("_move_focus", Vector3(-64.0, 0.0, 0.0))
	await _wait_for_window(scene)
	print("TERRAIN_PERF_EDITED_REGION_RETURN: unload_travel_ms=%.3f return_to_edited_3x3_ms=%.3f replayed_operations=%d" % [
		float(edited_region_return_start - old_region_start) / 1000.0,
		float(Time.get_ticks_usec() - edited_region_return_start) / 1000.0,
		ledger.get_edit_count(),
	])
	_check(scene.get("active_regions").has("0,0") and scene.get("active_regions").has("1,0"), "edited regions re-enter residency with their canonical global ledger")
	scene.queue_free()
	await process_frame
	_finish()


func _dispatch_click_to_visible(scene: Node, target: Vector3, camera_offset: Vector3 = Vector3(34.0, 24.0, 40.0)) -> int:
	var camera: Camera3D = scene.get_node("Camera3D")
	scene.set("orbit_target", target)
	scene.set("orbit_offset", camera_offset)
	scene.call("_update_camera")
	var viewport: Viewport = scene.get_viewport()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = viewport.get_visible_rect().size * 0.5
	var before_revision: int = scene.get("edit_ledger").revision
	var started := Time.get_ticks_usec()
	viewport.push_input(event, true)
	for _frame in range(MAX_FRAMES):
		if scene.get("edit_ledger").revision > before_revision:
			break
		await process_frame
	if scene.get("edit_ledger").revision == before_revision:
		_check(false, "viewport left-click reaches terrain picker at %s" % target)
		return -1
	for _frame in range(MAX_FRAMES):
		if scene.get("_edit_transaction").is_empty() and not scene.get("global_rebuild_pending"):
			return Time.get_ticks_usec() - started
		await process_frame
	_check(false, "accepted viewport edit becomes visible before timeout")
	return -1


func _surface_height(scene: Node, world_x: float, world_z: float) -> float:
	var low := Field.MIN_Y
	var high := 7.0
	for _iteration in range(30):
		var middle := (low + high) * 0.5
		var density: float = scene.call("_sample_world_density", Vector3(world_x, middle, world_z))
		if density >= 0.0:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


func _wait_for_window(scene: Node) -> void:
	for _frame in range(MAX_FRAMES):
		if not scene.get("global_rebuild_pending") and scene.get("loading_regions").is_empty():
			var ready := true
			for key in scene.call("_region_keys_within_radius", scene.get("focus_region_key"), 1):
				if not scene.get("active_regions").has(scene.call("_region_id", key)):
					ready = false
					break
			if ready:
				return
		await process_frame
	_check(false, "requested region window completes before timeout")


func _wait_for_transaction(scene: Node) -> void:
	for _frame in range(MAX_FRAMES):
		if scene.get("_edit_transaction").is_empty():
			return
		await process_frame
	_check(false, "accepted world-space edit becomes visible before timeout")


func _percentile(values: PackedInt64Array, fraction: float) -> int:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)] if not sorted.is_empty() else 0


func _format_samples(values: PackedInt64Array) -> String:
	var formatted := PackedStringArray()
	for value in values:
		formatted.append("%.3f" % (float(value) / 1000.0))
	return ",".join(formatted)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("TERRAIN_E2E_PERF_ASSERTION_FAILED: " + message)


func _finish() -> void:
	if failures == 0:
		print("TERRAIN_E2E_PERF_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("TERRAIN_E2E_PERF_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)
