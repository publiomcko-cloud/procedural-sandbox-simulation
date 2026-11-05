extends SceneTree

const DemoScene := preload("res://scenes/terrain_demo.tscn")
const Store := preload("res://scripts/terrain/terrain_materialized_sdf_store.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Picker := preload("res://scripts/terrain/terrain_brush_picker.gd")

const SETTLE_TIMEOUT_MSEC := 90000
const EXCURSION := Vector3(64.0, 0.0, 48.0)
const PREEDIT_COUNT := 128

var assertions := 0
var failures := 0
var evidence: Dictionary = {}
var _root := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_root = ProjectSettings.globalize_path(
		"user://runtime-performance-baseline-%d" % Time.get_ticks_usec()
	)
	var demo = DemoScene.instantiate()
	demo.world_save_store = Store.new(_root.path_join("terrain"))
	demo.object_state_directory_override = _root.path_join("objects")
	demo._preedit_count = PREEDIT_COUNT

	var initial_started := Time.get_ticks_usec()
	get_root().add_child(demo)
	var initial_ready := await _wait_idle(demo)
	var initial_usec := Time.get_ticks_usec() - initial_started
	_check(initial_ready, "initial 3x3 streaming window settles")
	if not initial_ready:
		await _shutdown(demo)
		return
	evidence["initial_window_ms"] = float(initial_usec) / 1000.0

	var unedited_reload := await _measure_excursion(demo, "unedited")
	evidence["unedited_reload"] = unedited_reload
	_check(unedited_reload.get("ok", false), "unedited diagonal unload/reload completes")

	# Produce a committed materialized base before timing interactive edits.
	demo._apply_preedit_fixture()
	var materialized_ready := await _wait_until(func() -> bool:
		return demo._checkpoint_task_id < 0 			and demo._edit_transaction.is_empty() 			and not demo.global_rebuild_pending 			and demo.loading_regions.is_empty() 			and demo.edit_ledger.get_archived_edit_count() >= PREEDIT_COUNT 			and demo.edit_ledger.get_tail_edit_count() == 0
	)
	_check(materialized_ready, "128-edit materialized base settles")
	if not materialized_ready:
		await _shutdown(demo)
		return

	var edited_reload := await _measure_excursion(demo, "edited")
	evidence["edited_reload"] = edited_reload
	_check(edited_reload.get("ok", false), "edited diagonal unload/reload completes")

	var scenarios := [
		{"name": "interior", "point": _surface_point(demo, Vector2(8.0, 5.0))},
		{"name": "x_seam", "point": _surface_point(demo, Vector2(16.0, 5.0))},
		{"name": "z_seam", "point": _surface_point(demo, Vector2(8.0, 12.0))},
		{"name": "xz_corner", "point": _surface_point(demo, Vector2(16.0, 12.0))},
	]

	var edit_results: Dictionary = {}
	for scenario_value in scenarios:
		var scenario: Dictionary = scenario_value
		var point: Vector3 = scenario["point"]
		var name := String(scenario["name"])
		var result := await _measure_direct_edit(demo, name, point)
		edit_results[name] = result
		_check(result.get("ok", false), "%s direct edit becomes visible" % name)
	evidence["edits"] = edit_results

	var burst_result := await _measure_same_area_burst(demo, _surface_point(demo, Vector2(8.0, 5.0)))
	evidence["same_area_burst"] = burst_result
	_check(burst_result.get("ok", false), "rapid same-area edit burst coalesces without losing input")
	_check(
		int(burst_result.get("pruned_candidate_count", 0)) >= 10,
		"same-mode dominated hot-tail operations are pruned before meshing"
	)

	var picker_result := _measure_picker(demo)
	evidence["picker"] = picker_result
	_check(picker_result.get("ok", false), "picker benchmark completes")

	print("RUNTIME_PERFORMANCE_BASELINE=" + JSON.stringify(evidence))
	await _shutdown(demo)


func _measure_excursion(demo: Node, label: String) -> Dictionary:
	var origin_id: String = demo._region_id(Vector2i.ZERO)
	demo._move_focus(EXCURSION)
	var unloaded := await _wait_until(func() -> bool:
		return not demo.active_regions.has(origin_id) 			and demo.focus_region_key.x >= 4 			and demo.focus_region_key.y >= 4
	)
	if not unloaded:
		return {"ok": false, "reason": label + "_origin_not_unloaded"}
	if not await _wait_idle(demo):
		return {"ok": false, "reason": label + "_away_window_timeout"}
	var started := Time.get_ticks_usec()
	demo._move_focus(-EXCURSION)
	var focus_ready := await _wait_until(func() -> bool:
		return demo.focus_region_key == Vector2i.ZERO and demo.active_regions.has(origin_id)
	)
	var focus_usec := Time.get_ticks_usec() - started
	var full_ready := await _wait_idle(demo)
	var full_usec := Time.get_ticks_usec() - started
	return {
		"ok": focus_ready and full_ready,
		"focus_ms": float(focus_usec) / 1000.0,
		"full_window_ms": float(full_usec) / 1000.0,
	}


func _measure_direct_edit(demo: Node, label: String, point: Vector3) -> Dictionary:
	if not await _wait_idle(demo):
		return {"ok": false, "reason": "pre_edit_not_idle"}
	var before_revision := int(demo.edit_ledger.revision)
	var before_count := int(demo.edit_ledger.get_edit_count())
	demo.selected_brush_mode = Brush.Mode.CARVE
	var started := Time.get_ticks_usec()
	var accepted: bool = demo._accept_brush_at_world(point)
	var accept_usec := Time.get_ticks_usec() - started
	if not accepted:
		return {
			"ok": false,
			"reason": "edit_rejected",
			"message": demo.last_brush_result,
		}
	var visible := await _wait_until(func() -> bool:
		return demo._edit_transaction.is_empty() 			and demo.loading_regions.is_empty() 			and int(demo.edit_ledger.revision) == before_revision + 1
	)
	var visible_usec := Time.get_ticks_usec() - started
	var metrics: Dictionary = demo.last_mesh_diagnostics.duplicate(true)
	return {
		"ok": visible 			and demo.edit_ledger.get_edit_count() == before_count + 1,
		"point": point,
		"accept_ms": float(accept_usec) / 1000.0,
		"visible_ms": float(visible_usec) / 1000.0,
		"remeshed_chunks": int(metrics.get("remeshed_chunk_count", -1)),
		"mesh_jobs": int(metrics.get("last_dirty_mesh_job_count", -1)),
		"mesh_queue_p95_ms": float(metrics.get("mesh_queue_wait_p95_ms", -1.0)),
		"worker_queue_p95_ms": float(metrics.get("worker_queue_wait_p95_ms", -1.0)),
		"upload_p50_ms": float(metrics.get("array_mesh_upload_p50_ms", -1.0)),
		"publish_p95_ms": float(metrics.get("mesh_publish_p95_ms", -1.0)),
		"total_mesh_work_ms": float(metrics.get("total_mesh_work_ms", -1.0)),
		"stage_timings_ms": metrics.get("stage_timings_ms", {}),
		"peak_workers": int(metrics.get("peak_mesh_jobs_in_flight", -1)),
		"peak_uploads_per_frame": int(metrics.get("peak_mesh_uploads_per_frame", -1)),
	}


func _measure_same_area_burst(demo: Node, point: Vector3) -> Dictionary:
	if not await _wait_idle(demo):
		return {"ok": false, "reason": "burst_precondition_not_idle"}
	var before_count := int(demo.edit_ledger.get_edit_count())
	demo.selected_brush_mode = Brush.Mode.CARVE
	var accepted := 0
	var started := Time.get_ticks_usec()
	for _index in range(12):
		if demo._accept_brush_at_world(point):
			accepted += 1
	var settled := await _wait_until(func() -> bool:
		return demo._edit_transaction.is_empty() \
			and demo._buffered_brush_requests.is_empty() \
			and int(demo.edit_ledger.get_edit_count()) == before_count + 12
	)
	var elapsed_usec := Time.get_ticks_usec() - started
	var mapped: Dictionary = Spatial.world_to_region_local(point)
	if not mapped.get("valid", false):
		return {"ok": false, "reason": "burst_point_mapping_failed"}
	var local: Vector3 = mapped["local_position"]
	var chunk_width := float(Grid.CELLS_PER_CHUNK_X) * Grid.SAMPLE_STEP
	var chunk_depth := float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
	var coordinate := Vector2i(
		clampi(floori(local.x / chunk_width), 0, Grid.CHUNK_COUNT_X - 1),
		clampi(floori(local.z / chunk_depth), 0, Grid.CHUNK_COUNT_Z - 1)
	)
	var state: RefCounted = demo._state_for_region(mapped["region_key"])
	var snapshot: Dictionary = state.brush_edits.get_meshing_snapshot_for_chunk(
		mapped["region_key"], coordinate
	)
	var raw_candidates := int(snapshot.get("raw_candidate_operation_count", snapshot.get("candidate_operation_count", 0)))
	var reduced_candidates := int(snapshot.get("candidate_operation_count", 0))
	return {
		"ok": settled and accepted == 12,
		"accepted": accepted,
		"elapsed_ms": float(elapsed_usec) / 1000.0,
		"raw_candidate_count": raw_candidates,
		"reduced_candidate_count": reduced_candidates,
		"pruned_candidate_count": raw_candidates - reduced_candidates,
		"final_edit_count": int(demo.edit_ledger.get_edit_count()),
	}


func _measure_picker(demo: Node) -> Dictionary:
	var viewport: Viewport = demo.get_viewport()
	var screen := viewport.get_visible_rect().size * 0.5
	var ray_origin: Vector3 = demo.camera.project_ray_origin(screen)
	var ray_direction: Vector3 = demo.camera.project_ray_normal(screen)
	var state: RefCounted = demo._state_for_region(demo.focus_region_key)
	var snapshot_started := Time.get_ticks_usec()
	var snapshot: Dictionary = state.brush_edits.get_ray_snapshot(
		ray_origin, ray_direction, Picker.MAX_DISTANCE
	)
	var snapshot_usec := Time.get_ticks_usec() - snapshot_started
	if not snapshot.get("valid", false):
		return {"ok": false, "reason": "snapshot_failed"}
	var samples := 0
	var sampler := func(point: Vector3) -> float:
		samples += 1
		return demo._sample_world_density_from_snapshot(point, snapshot)
	var pick_started := Time.get_ticks_usec()
	var pick: Dictionary = Picker.pick_sdf_v1_surface(ray_origin, ray_direction, sampler)
	var pick_usec := Time.get_ticks_usec() - pick_started
	return {
		"ok": true,
		"hit": bool(pick.get("hit", false)),
		"snapshot_ms": float(snapshot_usec) / 1000.0,
		"march_ms": float(pick_usec) / 1000.0,
		"total_ms": float(snapshot_usec + pick_usec) / 1000.0,
		"samples": samples,
		"candidate_operations": int(snapshot.get("candidate_operation_count", -1)),
		"materialized_tiles": (snapshot.get("materialized_tiles", []) as Array).size(),
	}


func _surface_point(demo: Node, xz: Vector2) -> Vector3:
	var mapped := Spatial.world_to_region_local(Vector3(xz.x, 0.0, xz.y))
	var region_key: Vector2i = mapped["region_key"]
	var local_x := float(mapped["local_position"].x)
	var local_z := float(mapped["local_position"].z)
	# Find the upper terrain crossing, away from the floor/cave crossing.
	var prior_y := 7.95
	var prior := Field.sample_density(demo.world_seed, region_key, Vector3(local_x, prior_y, local_z), false)
	for i in range(1, 181):
		var y := 7.95 - float(i) * 0.05
		var d := Field.sample_density(demo.world_seed, region_key, Vector3(local_x, y, local_z), false)
		if prior < 0.0 and d >= 0.0:
			var lo := y
			var hi := prior_y
			for _j in range(14):
				var mid := (lo + hi) * 0.5
				var md := Field.sample_density(demo.world_seed, region_key, Vector3(local_x, mid, local_z), false)
				if md >= 0.0:
					lo = mid
				else:
					hi = mid
			return Vector3(xz.x, (lo + hi) * 0.5, xz.y)
		prior_y = y
		prior = d
	return Vector3(xz.x, 3.0, xz.y)


func _wait_idle(demo: Node) -> bool:
	return await _wait_until(func() -> bool:
		return demo.loading_regions.is_empty() 			and not demo.global_rebuild_pending 			and demo._edit_transaction.is_empty()
	)


func _wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + SETTLE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false


func _shutdown(demo: Node) -> void:
	if demo != null and is_instance_valid(demo):
		demo.queue_free()
		await process_frame
	var cleaned := _cleanup_tree(_root)
	_check(cleaned, "performance benchmark storage cleaned")
	_finish()


func _cleanup_tree(path: String) -> bool:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return true
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if directory.current_is_dir():
			if not _cleanup_tree(child):
				directory.list_dir_end()
				return false
		else:
			if DirAccess.remove_absolute(child) != OK:
				directory.list_dir_end()
				return false
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("RUNTIME_PERFORMANCE_BASELINE_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
