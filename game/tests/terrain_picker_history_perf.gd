extends SceneTree

const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const BrushPicker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const Scene := preload("res://scenes/terrain_demo.tscn")
const MAX_FRAMES := 6000
const REPEATS := 5
const HISTORY_LEVELS := [0, 32, 128, 255, 256]
const LOCAL_LAYOUTS := [
	{"name": "local_interior", "xz": Vector2(8.0, 6.0)},
	{"name": "local_positive_edge", "xz": Vector2(14.55, 6.0)},
	{"name": "local_positive_corner", "xz": Vector2(14.55, 10.55)},
	{"name": "local_negative_corner", "xz": Vector2(-1.45, -1.45)},
]

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("TERRAIN_PICK_HISTORY: Godot=%s levels=0,32,128,255,256 repeats=%d path=Viewport.InputEvent->BrushPicker->SDF->mesh->publication" % [Engine.get_version_info().string, REPEATS])
	var diagnostic_mode := OS.get_environment("PICKER_PARITY_DIAGNOSTIC") == "1"
	var scene: Node = Scene.instantiate()
	root.add_child(scene)
	await _wait_for_window(scene)
	var remote_levels := HISTORY_LEVELS if not diagnostic_mode else [0]
	for history_size in remote_levels:
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
		var snapshot_usec := PackedInt64Array()
		var picker_total_usec := PackedInt64Array()
		var candidate_counts := PackedInt64Array()
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
			snapshot_usec.append(int(scene.get("_last_brush_pick_snapshot_elapsed_usec")))
			picker_total_usec.append(int(scene.get("_last_brush_pick_total_elapsed_usec")))
			candidate_counts.append(int(scene.get("_last_brush_pick_candidate_count")))
			sample_counts.append(sample_count)
			_check(hit == expect_hit, "mouse picking outcome %s equals expected hit=%s at history=%d actual=%s (samples=%d)" % [scenario, expect_hit, history_size, hit, sample_count])
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
		print("TERRAIN_PICK_PROFILE: history_start=%d history_before=%s candidates_p50/p95=%d/%d snapshot_p50/p95_ms=%.3f/%.3f picker_loop_p50/p95_ms=%.3f/%.3f picker_e2e_p50/p95_ms=%.3f/%.3f event_terminal_p50/p95_ms=%.3f/%.3f visible_p50/p95_ms=%.3f/%.3f samples_p50/p95=%d/%d frames_n=%d p95/p99/peak_ms=%.3f/%.3f/%.3f mesh_queue_wait_p50/p95_ms=%.3f/%.3f worker_wait_p50/p95_ms=%.3f/%.3f publish_p50/p95_ms=%.3f/%.3f queue_peak=%d workers_peak=%d" % [
			history_size, _format_ints(before_counts), _percentile(candidate_counts, 0.50), _percentile(candidate_counts, 0.95),
			_percentile(snapshot_usec, 0.50) / 1000.0, _percentile(snapshot_usec, 0.95) / 1000.0,
			_percentile(picker_usec, 0.50) / 1000.0, _percentile(picker_usec, 0.95) / 1000.0,
			_percentile(picker_total_usec, 0.50) / 1000.0, _percentile(picker_total_usec, 0.95) / 1000.0,
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
	await _run_concentrated_profiles(scene, diagnostic_mode)
	if not diagnostic_mode:
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


func _run_concentrated_profiles(scene: Node, diagnostic_mode: bool = false) -> void:
	print("TERRAIN_PICK_LOCAL_HISTORY: layouts=interior,positive_edge,positive_corner,negative_corner levels=0,32,128,255,256 repeats=%d clustered_same_region=true" % REPEATS)
	var ledger: RefCounted = scene.get("edit_ledger")
	var layouts := LOCAL_LAYOUTS
	var levels := HISTORY_LEVELS
	var repeat_count := REPEATS if not diagnostic_mode else 1
	for layout_value in layouts:
		var layout: Dictionary = layout_value
		for history_size in levels:
			var snapshot_usec := PackedInt64Array()
			var picker_usec := PackedInt64Array()
			var picker_total_usec := PackedInt64Array()
			var dispatch_usec := PackedInt64Array()
			var accept_usec := PackedInt64Array()
			var transaction_usec := PackedInt64Array()
			var visible_usec := PackedInt64Array()
			var frame_usec := PackedInt64Array()
			var candidate_counts := PackedInt64Array()
			var sample_counts := PackedInt64Array()
			var mesh_queue_wait_usec := PackedInt64Array()
			var worker_wait_usec := PackedInt64Array()
			var publish_usec := PackedInt64Array()
			var array_mesh_upload_usec := PackedInt64Array()
			var expected_counts := PackedInt32Array()
			var comparison_serial := 0
			for repeat_index in range(repeat_count):
				var xz: Vector2 = layout["xz"]
				ledger.clear()
				var base_surface_y := _surface_height(scene, xz.x, xz.y)
				var anchor := Vector3(xz.x, base_surface_y, xz.y)
				if not _seed_history_near_ray(ledger, history_size, anchor):
					_check(false, "%s concentrated history setup count=%d repeat=%d" % [layout["name"], history_size, repeat_index])
					continue
				_check(ledger.get_edit_count() == history_size, "%s exact concentrated operation count=%d repeat=%d" % [layout["name"], history_size, repeat_index])
				var target := Vector3(xz.x, _surface_height(scene, xz.x, xz.y), xz.y)
				var scenario: String = ["near_hit", "far_hit", "far_no_intersection", "near_hit", "far_hit"][repeat_index]
				var camera_offset := Vector3(12.0, 8.0, 15.0) if scenario == "near_hit" else Vector3(65.0, 53.0, 40.0)
				if scenario == "far_no_intersection":
					target = Vector3(xz.x, 100.0, xz.y)
					scene.set("orbit_target", target)
					scene.set("orbit_offset", Vector3(4.0, 95.0, 10.0))
				else:
					scene.set("orbit_target", target)
					scene.set("orbit_offset", camera_offset)
				scene.call("_update_camera")
				scene.call("_update_focus_key")
				scene.call("_reconcile_region_window")
				# Materialize the exact preseeded history before timing the actual click.
				scene.call("_start_global_rebuild", "picker_local_history_profile_setup")
				await _wait_for_window(scene)
				var viewport: Viewport = scene.get_viewport()
				var center_screen := viewport.get_visible_rect().size * 0.5
				var profile_camera: Camera3D = scene.get("camera")
				var ray_origin: Vector3 = profile_camera.project_ray_origin(center_screen)
				var ray_direction: Vector3 = profile_camera.project_ray_normal(center_screen)
				var compare_legacy_picker: bool = repeat_index == 0 and history_size in [0, 255]
				var oracle: Dictionary = _compare_full_and_filtered_picker(
					scene, ray_origin, ray_direction, compare_legacy_picker
				)
				if not oracle.get("equivalent", false):
					print("TERRAIN_PICK_ORACLE_MISMATCH: layout=%s history=%d scenario=%s details=%s" % [layout["name"], history_size, scenario, oracle])
				_check(oracle.get("equivalent", false), "%s full-replay ray-march/bisection parity history=%d scenario=%s" % [layout["name"], history_size, scenario])
				if compare_legacy_picker:
					if not oracle.get("legacy_equivalent", false):
						print("TERRAIN_PICK_LEGACY_MISMATCH: layout=%s history=%d details=%s" % [layout["name"], history_size, oracle])
					_check(oracle.get("legacy_equivalent", false), "%s adaptive march selects the same fixed-step surface history=%d" % [layout["name"], history_size])
				comparison_serial += 1
				var input_event := InputEventMouseButton.new()
				input_event.button_index = MOUSE_BUTTON_LEFT
				input_event.pressed = true
				input_event.position = center_screen
				var before_serial: int = scene.get("_brush_pick_serial")
				var before_revision: int = ledger.revision
				var before_count: int = ledger.get_edit_count()
				expected_counts.append(before_count)
				var started_usec := Time.get_ticks_usec()
				viewport.push_input(input_event, true)
				var immediate_dispatch_usec := Time.get_ticks_usec() - started_usec
				for _frame in range(4):
					if int(scene.get("_brush_pick_serial")) > before_serial:
						break
					await process_frame
					frame_usec.append(int(round(float(scene.get("_last_frame_ms")) * 1000.0)))
				_check(int(scene.get("_brush_pick_serial")) == before_serial + 1, "%s real Viewport mouse click reaches picker history=%d repeat=%d" % [layout["name"], history_size, repeat_index])
				if int(scene.get("_brush_pick_serial")) != before_serial + 1:
					continue
				var hit: bool = scene.get("_last_brush_pick_hit")
				var expect_hit: bool = scenario != "far_no_intersection"
				_check(hit == expect_hit and bool(oracle.get("hit", false)) == expect_hit, "%s concentrated real/full-replay hit classification history=%d scenario=%s" % [layout["name"], history_size, scenario])
				if expect_hit:
					_check(scene.get("_last_brush_pick_position") == oracle.get("position", Vector3.ZERO), "%s selected surface position matches full ordered replay history=%d scenario=%s" % [layout["name"], history_size, scenario])
				snapshot_usec.append(int(scene.get("_last_brush_pick_snapshot_elapsed_usec")))
				picker_usec.append(int(scene.get("_last_brush_pick_elapsed_usec")))
				picker_total_usec.append(int(scene.get("_last_brush_pick_total_elapsed_usec")))
				dispatch_usec.append(immediate_dispatch_usec)
				candidate_counts.append(int(scene.get("_last_brush_pick_candidate_count")))
				sample_counts.append(int(scene.get("_last_brush_pick_sample_count")))
				if expect_hit and before_count < BrushState.MAX_EDITS:
					_check(ledger.get_edit_count() == before_count + 1 and ledger.revision == before_revision + 1, "%s valid concentrated click accepted once history=%d" % [layout["name"], before_count])
					var accepted_usec := Time.get_ticks_usec()
					accept_usec.append(accepted_usec - started_usec)
					var transaction_started := Time.get_ticks_usec()
					await _wait_for_transaction(scene, frame_usec)
					var completed_usec := Time.get_ticks_usec()
					transaction_usec.append(completed_usec - transaction_started)
					visible_usec.append(completed_usec - started_usec)
					var diagnostics: Dictionary = scene.get("last_mesh_diagnostics")
					mesh_queue_wait_usec.append(int(round(float(diagnostics.get("mesh_queue_wait_p95_ms", 0.0)) * 1000.0)))
					worker_wait_usec.append(int(round(float(diagnostics.get("worker_queue_wait_p95_ms", 0.0)) * 1000.0)))
					publish_usec.append(int(round(float(diagnostics.get("mesh_publish_p95_ms", 0.0)) * 1000.0)))
					array_mesh_upload_usec.append(int(round(float(diagnostics.get("array_mesh_upload_p50_ms", 0.0)) * 1000.0)))
				elif expect_hit:
					_check(ledger.revision == before_revision and scene.get("_last_edit_rejection") == "ledger_capacity_exceeded", "%s 256-operation hit is rejected only for capacity" % layout["name"])
				else:
					_check(ledger.revision == before_revision and String(scene.get("last_brush_result")).contains("No terrain surface hit"), "%s miss leaves concentrated ledger unchanged" % layout["name"])
				var release_event := InputEventMouseButton.new()
				release_event.button_index = MOUSE_BUTTON_LEFT
				release_event.pressed = false
				release_event.position = center_screen
				viewport.push_input(release_event, true)
				frame_usec.append(int(round(float(scene.get("_last_frame_ms")) * 1000.0)))
				if failures > 0:
					# Continue all cases to retain complete failure evidence.
					pass
			print("TERRAIN_PICK_LOCAL_PROFILE: layout=%s history_requested=%d counts_before=%s repeats=%d candidates_p50/p95=%d/%d snapshot_p50/p95_ms=%.3f/%.3f picker_loop_p50/p95_ms=%.3f/%.3f picker_e2e_p50/p95_ms=%.3f/%.3f event_dispatch_p50/p95_ms=%.3f/%.3f accept_p50/p95_ms=%.3f/%.3f transaction_p50/p95_ms=%.3f/%.3f visible_p50/p95_ms=%.3f/%.3f frames_n=%d p95/p99/peak_ms=%.3f/%.3f/%.3f samples_p50/p95=%d/%d mesh_queue_wait_p95_ms=%.3f worker_wait_p95_ms=%.3f array_mesh_upload_p50/p95_ms=%.3f/%.3f publish_p95_ms=%.3f candidates_full_replay_checks=%d" % [
			layout["name"], history_size, _format_ints(expected_counts), dispatch_usec.size(), _percentile(candidate_counts, 0.50), _percentile(candidate_counts, 0.95),
				_percentile(snapshot_usec, 0.50) / 1000.0, _percentile(snapshot_usec, 0.95) / 1000.0,
				_percentile(picker_usec, 0.50) / 1000.0, _percentile(picker_usec, 0.95) / 1000.0,
				_percentile(picker_total_usec, 0.50) / 1000.0, _percentile(picker_total_usec, 0.95) / 1000.0,
				_percentile(dispatch_usec, 0.50) / 1000.0, _percentile(dispatch_usec, 0.95) / 1000.0,
				_percentile(accept_usec, 0.50) / 1000.0, _percentile(accept_usec, 0.95) / 1000.0,
				_percentile(transaction_usec, 0.50) / 1000.0, _percentile(transaction_usec, 0.95) / 1000.0,
				_percentile(visible_usec, 0.50) / 1000.0, _percentile(visible_usec, 0.95) / 1000.0,
				frame_usec.size(), _percentile(frame_usec, 0.95) / 1000.0, _percentile(frame_usec, 0.99) / 1000.0, _max(frame_usec) / 1000.0,
				_percentile(sample_counts, 0.50), _percentile(sample_counts, 0.95), _percentile(mesh_queue_wait_usec, 0.95) / 1000.0,
				_percentile(worker_wait_usec, 0.95) / 1000.0,
				_percentile(array_mesh_upload_usec, 0.50) / 1000.0, _percentile(array_mesh_upload_usec, 0.95) / 1000.0,
				_percentile(publish_usec, 0.95) / 1000.0, comparison_serial,
			])


func _seed_history_near_ray(ledger: RefCounted, count: int, surface_point: Vector3) -> bool:
	var camera_offset := Vector3(12.0, 8.0, 15.0)
	var ray_direction := -camera_offset.normalized()
	var mapped: Dictionary = Spatial.world_to_region_local(surface_point)
	var local_position: Vector3 = mapped["local_position"]
	var local_xz := Vector2(local_position.x, local_position.z)
	var region_center := Vector2(Spatial.REGION_SIZE_X * 0.5, Spatial.REGION_SIZE_Z * 0.5)
	var inward := Vector3(
		-1.0 if local_xz.x > region_center.x else 1.0,
		0.0,
		-1.0 if local_xz.y > region_center.y else 1.0
	)
	if absf(local_xz.x - region_center.x) < 1.0:
		inward.x = 1.0
	if absf(local_xz.y - region_center.y) < 1.0:
		inward.z = 1.0
	var perpendicular := (inward - ray_direction * inward.dot(ray_direction)).normalized()
	var second_perpendicular := ray_direction.cross(perpendicular).normalized()
	var cluster_center := surface_point + perpendicular * 1.43
	if not surface_point.is_finite() or perpendicular.length_squared() < 0.5:
		return false
	for index in range(count):
		var phase := float(index % 7) * 0.011
		var center := cluster_center + perpendicular * phase + second_perpendicular * (float(index % 5) - 2.0) * 0.008
		var mode := BrushState.Mode.CARVE if index % 2 == 0 else BrushState.Mode.FILL
		if not ledger.add_sphere(mode, center, 1.25):
			return false
		var operation: Dictionary = ledger.get_last_operation_snapshot()
		var support_regions: Array[Vector2i] = operation["support_regions"]
		if support_regions.size() != 1 or support_regions[0] != mapped["region_key"]:
			return false
	return true


func _compare_full_and_filtered_picker(
	scene: Node,
	origin: Vector3,
	direction: Vector3,
	compare_legacy_picker: bool = false
) -> Dictionary:
	var ledger: RefCounted = scene.get("edit_ledger")
	var full_operations: Array[Dictionary] = ledger.get_operations_snapshot()
	var focused_state: RefCounted = scene.call("_state_for_region", scene.get("focus_region_key"))
	var snapshot: Dictionary = focused_state.brush_edits.get_ray_snapshot(origin, direction, 120.0)
	var full_trace := PackedVector3Array()
	var filtered_trace := PackedVector3Array()
	var full_values := PackedFloat64Array()
	var filtered_values := PackedFloat64Array()
	var full_sampler := func(point: Vector3) -> float:
		full_trace.append(point)
		var mapped: Dictionary = Spatial.world_to_region_local(point)
		var value: float = _sample_density_full_replay(
			WorldState.DEMO_SEED,
			mapped["region_key"],
			mapped["local_position"],
			bool(scene.get("cave_section_enabled")),
			full_operations
		)
		full_values.append(value)
		return value
	var filtered_sampler := func(point: Vector3) -> float:
		filtered_trace.append(point)
		var value: float = scene.call("_sample_world_density_from_snapshot", point, snapshot)
		filtered_values.append(value)
		return value
	var full_pick: Dictionary = BrushPicker.pick_sdf_v1_surface(origin, direction, full_sampler)
	var filtered_pick: Dictionary = BrushPicker.pick_sdf_v1_surface(origin, direction, filtered_sampler)
	var legacy_pick: Dictionary = {}
	if compare_legacy_picker:
		var legacy_sampler := func(point: Vector3) -> float:
			var mapped: Dictionary = Spatial.world_to_region_local(point)
			return _sample_density_full_replay(
				WorldState.DEMO_SEED,
				mapped["region_key"],
				mapped["local_position"],
				bool(scene.get("cave_section_enabled")),
				full_operations
			)
		legacy_pick = _pick_surface_fixed_reference(origin, direction, legacy_sampler)
	var same_trace := full_trace == filtered_trace
	var same_values := full_values == filtered_values
	var first_value_mismatch := -1
	for index in range(mini(full_values.size(), filtered_values.size())):
		if full_values[index] != filtered_values[index]:
			first_value_mismatch = index
			break
	var same_surface := bool(full_pick.get("hit", false)) == bool(filtered_pick.get("hit", false))
	if same_surface and full_pick.get("hit", false):
		same_surface = full_pick["position"] == filtered_pick["position"]
	var legacy_equivalent := true
	if compare_legacy_picker:
		legacy_equivalent = bool(full_pick.get("hit", false)) == bool(legacy_pick.get("hit", false))
		if legacy_equivalent and full_pick.get("hit", false):
			legacy_equivalent = full_pick["position"].distance_to(legacy_pick["position"]) <= 0.0001
	return {
		"equivalent": same_trace and same_surface and same_values,
		"same_trace": same_trace,
		"same_values": same_values,
		"same_surface": same_surface,
		"full_trace_count": full_trace.size(),
		"filtered_trace_count": filtered_trace.size(),
		"first_value_mismatch": first_value_mismatch,
		"full_value_at_mismatch": full_values[first_value_mismatch] if first_value_mismatch >= 0 else 0.0,
		"filtered_value_at_mismatch": filtered_values[first_value_mismatch] if first_value_mismatch >= 0 else 0.0,
		"hit": bool(full_pick.get("hit", false)),
		"position": full_pick.get("position", Vector3.ZERO),
		"samples": full_trace.size(),
		"candidate_count": int(snapshot.get("candidate_operation_count", 0)),
		"legacy_equivalent": legacy_equivalent,
		"legacy_hit": legacy_pick.get("hit", false),
		"legacy_position": legacy_pick.get("position", Vector3.ZERO),
		"legacy_position_delta": full_pick["position"].distance_to(legacy_pick["position"]) \
			if compare_legacy_picker and full_pick.get("hit", false) and legacy_pick.get("hit", false) else -1.0,
	}


func _pick_surface_fixed_reference(
	origin: Vector3,
	direction: Vector3,
	sample_field: Callable
) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() <= 0.000001:
		return {"hit": false}
	var normalized_direction := direction.normalized()
	var previous_distance := 0.0
	var previous_density: float = sample_field.call(origin)
	if not is_finite(previous_density) or previous_density >= 0.0:
		return {"hit": false}
	for step_index in range(1, BrushPicker.MAX_STEPS + 1):
		var distance := float(step_index) * BrushPicker.SAMPLE_STEP
		var density: float = sample_field.call(origin + normalized_direction * distance)
		if not is_finite(density):
			return {"hit": false}
		if density >= 0.0:
			var empty_distance := previous_distance
			var solid_distance := distance
			for _iteration in range(BrushPicker.BISECTION_STEPS):
				var middle_distance := (empty_distance + solid_distance) * 0.5
				var middle_density: float = sample_field.call(
					origin + normalized_direction * middle_distance
				)
				if not is_finite(middle_density):
					return {"hit": false}
				if middle_density >= 0.0:
					solid_distance = middle_distance
				else:
					empty_distance = middle_distance
			return {"hit": true, "position": origin + normalized_direction * solid_distance}
		previous_distance = distance
	return {"hit": false}


func _sample_density_full_replay(
	seed: int,
	region_key: Vector2i,
	local_position: Vector3,
	show_cave_section: bool,
	operations: Array[Dictionary]
) -> float:
	var density: float = Field.sample_density(seed, region_key, local_position)
	var world_position := Spatial.region_local_to_world(region_key, local_position)
	for operation in operations:
		var distance_to_surface := world_position.distance_to(operation["center_world"]) - float(operation["radius"])
		if int(operation["mode"]) == BrushState.Mode.CARVE:
			density = minf(density, distance_to_surface)
		else:
			density = maxf(density, -distance_to_surface)
	if show_cave_section:
		density = minf(density, 6.0 - world_position.z)
	return density


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
