extends SceneTree

const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Scene := preload("res://scenes/terrain_demo.tscn")
const MAX_FRAMES := 6000
const REPEATS := 5

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("TERRAIN_PICK_HISTORY: Godot=%s levels=0,32,128,256 repeats=%d path=Viewport.InputEvent->BrushPicker->SDF->mesh->publication" % [Engine.get_version_info().string, REPEATS])
	var scene: Node = Scene.instantiate()
	root.add_child(scene)
	await _wait_for_window(scene)
	for history_size in [0, 32, 128, 256]:
		var ledger: RefCounted = scene.get("edit_ledger")
		ledger.clear()
		var setup_ok := true
		var far_origin := Spatial.region_origin_world(Vector2i(64, 64))
		for index in range(history_size):
			var mode := BrushState.Mode.CARVE if index % 2 == 0 else BrushState.Mode.FILL
			if not ledger.add_sphere(mode, far_origin + Vector3(8.0, 3.2, 6.0), 1.25):
				setup_ok = false
				break
		_check(setup_ok and ledger.get_edit_count() == history_size, "synthetic concentrated picker history setup count=%d" % history_size)
		scene.call("_start_global_rebuild", "picker_history_profile_setup")
		await _wait_for_window(scene)
		var picker_usec := PackedInt64Array()
		var terminal_usec := PackedInt64Array()
		var visible_usec := PackedInt64Array()
		var frame_usec := PackedInt64Array()
		var mesh_queue_wait_usec := PackedInt64Array()
		var worker_queue_wait_usec := PackedInt64Array()
		var publish_usec := PackedInt64Array()
		var before_counts := PackedInt32Array()
		var sample_counts := PackedInt64Array()
		var expected_names := ["near_interior", "far_interior", "near_positive_corner", "near_negative_corner", "far_no_intersection"]
		for repeat_index in range(REPEATS):
			var scenario := String(expected_names[repeat_index])
			var target: Vector3
			var camera_offset: Vector3
			var world_x := 0.0
			var world_z := 0.0
			var expect_hit := scenario != "far_no_intersection"
			match scenario:
				"near_interior":
					world_x = 8.0
					world_z = 6.0
					target = Vector3(world_x, _surface_height(scene, world_x, world_z), world_z)
					camera_offset = Vector3(12.0, 8.0, 15.0)
				"far_interior":
					world_x = 8.6
					world_z = 4.8
					target = Vector3(world_x, _surface_height(scene, world_x, world_z), world_z)
					camera_offset = Vector3(65.0, 53.0, 40.0)
				"near_positive_corner":
					world_x = 15.82
					world_z = 11.82
					target = Vector3(world_x, _surface_height(scene, world_x, world_z), world_z)
					camera_offset = Vector3(12.0, 8.0, 15.0)
				"near_negative_corner":
					world_x = -0.18
					world_z = -0.18
					target = Vector3(world_x, _surface_height(scene, world_x, world_z), world_z)
					camera_offset = Vector3(12.0, 8.0, 15.0)
				"far_no_intersection":
					target = Vector3(8.0, 100.0, 6.0)
					camera_offset = Vector3(4.0, 95.0, 10.0)
			# Move to the target focus and settle streaming before starting the timer.
			scene.set("orbit_target", target)
			scene.set("orbit_offset", camera_offset)
			scene.call("_update_camera")
			scene.call("_update_focus_key")
			scene.call("_reconcile_region_window")
			await _wait_for_window(scene)
			var viewport: Viewport = scene.get_viewport()
			var input_event := InputEventMouseButton.new()
			input_event.button_index = MOUSE_BUTTON_LEFT
			input_event.pressed = true
			input_event.position = viewport.get_visible_rect().size * 0.5
			var before_serial: int = scene.get("_brush_pick_serial")
			var before_revision: int = ledger.revision
			var before_count: int = ledger.get_edit_count()
			before_counts.append(before_count)
			var started_usec := Time.get_ticks_usec()
			viewport.push_input(input_event, true)
			for _frame in range(4):
				if int(scene.get("_brush_pick_serial")) > before_serial:
					break
				await process_frame
				frame_usec.append(int(round(float(scene.get("_last_frame_ms")) * 1000.0)))
			_check(int(scene.get("_brush_pick_serial")) == before_serial + 1, "real viewport mouse event reaches BrushPicker for %s at history=%d" % [scenario, history_size])
			if int(scene.get("_brush_pick_serial")) != before_serial + 1:
				continue
			var hit: bool = scene.get("_last_brush_pick_hit")
			var pick_duration: int = scene.get("_last_brush_pick_elapsed_usec")
			var sample_count: int = scene.get("_last_brush_pick_sample_count")
			picker_usec.append(pick_duration)
			sample_counts.append(sample_count)
			_check(hit == expect_hit, "mouse picking outcome %s equals expected hit=%s at history=%d (samples=%d)" % [scenario, expect_hit, history_size, sample_count])
			_check(sample_count > 0 and sample_count <= 1 + 1200 + 12, "picker sample count stays inside fixed ray/bisection bound")
			if expect_hit and before_count < BrushState.MAX_EDITS:
				_check(ledger.revision == before_revision + 1 and ledger.get_edit_count() == before_count + 1, "actual hit event is admitted exactly once at history=%d" % before_count)
				await _wait_for_transaction(scene, frame_usec)
				visible_usec.append(Time.get_ticks_usec() - started_usec)
				var operation_metrics: Dictionary = scene.get("last_mesh_diagnostics")
				mesh_queue_wait_usec.append(int(round(float(operation_metrics.get("mesh_queue_wait_p95_ms", 0.0)) * 1000.0)))
				worker_queue_wait_usec.append(int(round(float(operation_metrics.get("worker_queue_wait_p95_ms", 0.0)) * 1000.0)))
				publish_usec.append(int(round(float(operation_metrics.get("mesh_publish_p95_ms", 0.0)) * 1000.0)))
			elif expect_hit:
				_check(ledger.revision == before_revision and scene.get("_last_edit_rejection") == "ledger_capacity_exceeded", "actual hit at 256 reports capacity rejection without ledger mutation")
			else:
				_check(ledger.revision == before_revision and String(scene.get("last_brush_result")).contains("No terrain surface hit"), "no-intersection mouse event leaves the ledger unchanged")
			terminal_usec.append(Time.get_ticks_usec() - started_usec)
			await process_frame
			frame_usec.append(int(round(float(scene.get("_last_frame_ms")) * 1000.0)))
		var diagnostics: Dictionary = scene.get("last_mesh_diagnostics")
		print("TERRAIN_PICK_PROFILE: history_start=%d history_before=%s picker_p50/p95_ms=%.3f/%.3f event_terminal_p50/p95_ms=%.3f/%.3f visible_p50/p95_ms=%.3f/%.3f samples_p50/p95=%d/%d frames_n=%d p95/p99/peak_ms=%.3f/%.3f/%.3f mesh_queue_wait_p50/p95_ms=%.3f/%.3f worker_wait_p50/p95_ms=%.3f/%.3f publish_p50/p95_ms=%.3f/%.3f queue_peak=%d workers_peak=%d" % [
			history_size, _format_ints(before_counts), _percentile(picker_usec, 0.50) / 1000.0, _percentile(picker_usec, 0.95) / 1000.0,
			_percentile(terminal_usec, 0.50) / 1000.0, _percentile(terminal_usec, 0.95) / 1000.0,
			_percentile(visible_usec, 0.50) / 1000.0, _percentile(visible_usec, 0.95) / 1000.0,
			_percentile(sample_counts, 0.50), _percentile(sample_counts, 0.95),
			frame_usec.size(),
			_percentile(frame_usec, 0.95) / 1000.0, _percentile(frame_usec, 0.99) / 1000.0, _max(frame_usec) / 1000.0,
			_percentile(mesh_queue_wait_usec, 0.50) / 1000.0, _percentile(mesh_queue_wait_usec, 0.95) / 1000.0,
			_percentile(worker_queue_wait_usec, 0.50) / 1000.0, _percentile(worker_queue_wait_usec, 0.95) / 1000.0,
			_percentile(publish_usec, 0.50) / 1000.0, _percentile(publish_usec, 0.95) / 1000.0,
			diagnostics.get("peak_queue_depth", 0), diagnostics.get("peak_mesh_jobs_in_flight", 0),
		])
	await _profile_256th_mouse_commit(scene)
	# Leave the shared scene in a clean transient state for any callers/reuse.
	var ledger_after: RefCounted = scene.get("edit_ledger")
	ledger_after.clear()
	scene.call("_start_global_rebuild", "picker_history_cleanup")
	await _wait_for_window(scene)
	scene.queue_free()
	await process_frame
	if failures == 0:
		print("TERRAIN_PICK_HISTORY_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("TERRAIN_PICK_HISTORY_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)


func _profile_256th_mouse_commit(scene: Node) -> void:
	var ledger: RefCounted = scene.get("edit_ledger")
	var far_origin := Spatial.region_origin_world(Vector2i(64, 64))
	var pick_times := PackedInt64Array()
	var visible_times := PackedInt64Array()
	var frame_times := PackedInt64Array()
	for repetition in range(REPEATS):
		ledger.clear()
		for index in range(255):
			var mode := BrushState.Mode.CARVE if index % 2 == 0 else BrushState.Mode.FILL
			ledger.add_sphere(mode, far_origin + Vector3(8.0, 3.2, 6.0), 1.25)
		scene.call("_start_global_rebuild", "picker_255_operation_setup")
		await _wait_for_window(scene)
		var world_x := 15.82
		var world_z := 11.82
		var target := Vector3(world_x, _surface_height(scene, world_x, world_z), world_z)
		scene.set("orbit_target", target)
		scene.set("orbit_offset", Vector3(12.0, 8.0, 15.0))
		scene.call("_update_camera")
		scene.call("_update_focus_key")
		scene.call("_reconcile_region_window")
		await _wait_for_window(scene)
		var viewport: Viewport = scene.get_viewport()
		var input_event := InputEventMouseButton.new()
		input_event.button_index = MOUSE_BUTTON_LEFT
		input_event.pressed = true
		input_event.position = viewport.get_visible_rect().size * 0.5
		var serial_before: int = scene.get("_brush_pick_serial")
		var revision_before: int = ledger.revision
		var started := Time.get_ticks_usec()
		viewport.push_input(input_event, true)
		for _frame in range(4):
			if int(scene.get("_brush_pick_serial")) > serial_before:
				break
			await process_frame
			frame_times.append(int(round(float(scene.get("_last_frame_ms")) * 1000.0)))
		_check(int(scene.get("_brush_pick_serial")) == serial_before + 1 and scene.get("_last_brush_pick_hit"), "real viewport event at ledger=255 reaches a surface through the accelerated picker")
		pick_times.append(int(scene.get("_last_brush_pick_elapsed_usec")))
		_check(ledger.get_edit_count() == 256 and ledger.revision == revision_before + 1, "actual 256th mouse edit is admitted atomically")
		await _wait_for_transaction(scene, frame_times)
		visible_times.append(Time.get_ticks_usec() - started)
		var metrics: Dictionary = scene.get("last_mesh_diagnostics")
		_check(metrics.get("peak_mesh_jobs_in_flight", 0) <= 4 and metrics.get("peak_mesh_uploads_per_frame", 2) <= 2, "256th mouse edit preserves worker and ArrayMesh caps")
		var reset: Dictionary = ledger.clear_for_region(scene.get("focus_region_key"))
		_check(reset.get("removed_count", 0) == 1 and ledger.get_edit_count() == 255, "focused X semantics can remove only the added corner support command in disposable benchmark history")
		scene.call("_start_global_rebuild", "picker_255_operation_restore")
		await _wait_for_window(scene)
	print("TERRAIN_PICK_256TH_COMMIT: repeats=%d history_before=255 picker_p50/p95_ms=%.3f/%.3f visible_p50/p95_ms=%.3f/%.3f frame_p95/p99/peak_ms=%.3f/%.3f/%.3f queue_peak=%d workers_peak=%d" % [
		REPEATS, _percentile(pick_times, 0.50) / 1000.0, _percentile(pick_times, 0.95) / 1000.0,
		_percentile(visible_times, 0.50) / 1000.0, _percentile(visible_times, 0.95) / 1000.0,
		_percentile(frame_times, 0.95) / 1000.0, _percentile(frame_times, 0.99) / 1000.0, _max(frame_times) / 1000.0,
		scene.get("last_mesh_diagnostics").get("peak_queue_depth", 0), scene.get("last_mesh_diagnostics").get("peak_mesh_jobs_in_flight", 0),
	])


func _surface_height(scene: Node, world_x: float, world_z: float) -> float:
	var low := -1.0
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
			var focus: Vector2i = scene.get("focus_region_key")
			var ready := true
			for z in range(focus.y - 1, focus.y + 2):
				for x in range(focus.x - 1, focus.x + 2):
					if not scene.get("active_regions").has("%d,%d" % [x, z]):
						ready = false
			if ready:
				return
		await process_frame
	_check(false, "requested 3x3 region window settles")


func _wait_for_transaction(scene: Node, frames: PackedInt64Array) -> void:
	for _frame in range(MAX_FRAMES):
		if scene.get("_edit_transaction").is_empty():
			return
		await process_frame
		frames.append(int(round(float(scene.get("_last_frame_ms")) * 1000.0)))
	_check(false, "mouse edit transaction reaches coherent publication")


func _percentile(values: PackedInt64Array, fraction: float) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)]


func _max(values: PackedInt64Array) -> int:
	var result := 0
	for value in values:
		result = maxi(result, value)
	return result


func _format_ints(values: PackedInt32Array) -> String:
	var strings := PackedStringArray()
	for value in values:
		strings.append(str(value))
	return ",".join(strings)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("TERRAIN_PICK_HISTORY_ASSERTION_FAILED: " + message)
