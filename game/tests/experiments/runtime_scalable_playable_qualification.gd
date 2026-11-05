extends SceneTree

const DemoScene := preload("res://scenes/terrain_demo.tscn")
const Store := preload("res://scripts/terrain/terrain_materialized_sdf_store.gd")

const PREEDIT_COUNT := 256
const SETTLE_TIMEOUT_MSEC := 90000
const STREAM_DELTA := Vector3(64.0, 0.0, 48.0)

var assertions := 0
var failures := 0
var evidence: Dictionary = {}
var _root := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_root = ProjectSettings.globalize_path(
		"user://runtime-scalable-playable-%d" % Time.get_ticks_usec()
	)
	var demo = DemoScene.instantiate()
	demo.world_save_store = Store.new(_root.path_join("terrain"))
	demo.object_state_directory_override = _root.path_join("objects")
	demo._preedit_count = PREEDIT_COUNT
	demo.debug_shared_runtime_diagnostics = true
	get_root().add_child(demo)

	var initial_ready := await _wait_until(func() -> bool:
		return demo.loading_regions.is_empty() 			and not demo.global_rebuild_pending 			and demo.active_regions.size() >= 9
	)
	_check(initial_ready, "initial playable streaming window settles")
	if not initial_ready:
		await _shutdown(demo)
		return

	_check(demo._scalable_runtime_enabled, "terrain demo uses scalable materialized runtime")
	_check(demo._shared_boundary_runtime_enabled, "shared X boundary runtime is enabled")
	_check(demo.edit_ledger.get_edit_count() == 0, "isolated runtime starts without edits")

	var preedit_started := Time.get_ticks_usec()
	demo._apply_preedit_fixture()
	var preedit_ready := await _wait_until(func() -> bool:
		return demo._checkpoint_task_id < 0 \
			and not demo.global_rebuild_pending \
			and demo.loading_regions.is_empty() \
			and demo.edit_ledger.get_archived_edit_count() == PREEDIT_COUNT \
			and demo.edit_ledger.get_tail_edit_count() == 0
	)
	var preedit_elapsed_usec := Time.get_ticks_usec() - preedit_started
	_check(preedit_ready, "pre-edits rebuild and async checkpoint settle")
	_check(demo._checkpoint_overlap_observed, "checkpoint overlaps terrain rebuild instead of blocking the frame lifecycle")
	_check(demo.edit_ledger.get_edit_count() == PREEDIT_COUNT, "all pre-edits remain in lifetime count")
	_check(demo._checkpoint_generation >= 1, "pre-edits produce a committed materialized generation")
	if not preedit_ready:
		await _shutdown(demo)
		return

	var origin_id: String = demo._region_id(Vector2i.ZERO)
	_check(demo.active_regions.has(origin_id), "edited origin region is resident before excursion")
	var before_stats: Dictionary = demo.world_save_store.get_hot_stats()

	demo._move_focus(STREAM_DELTA)
	var unloaded := await _wait_until(func() -> bool:
		return not demo.active_regions.has(origin_id) \
			and demo.focus_region_key.x >= 4 \
			and demo.focus_region_key.y >= 4
	)
	_check(unloaded, "edited origin region unloads after moving beyond retention radius")

	var away_settled := await _wait_until(func() -> bool:
		return demo.loading_regions.is_empty() and not demo.global_rebuild_pending
	)
	_check(away_settled, "distant streaming window settles")

	var reload_started := Time.get_ticks_usec()
	demo._move_focus(-STREAM_DELTA)
	var focus_reloaded := await _wait_until(func() -> bool:
		return demo.focus_region_key == Vector2i.ZERO and demo.active_regions.has(origin_id)
	)
	var focus_reload_usec := Time.get_ticks_usec() - reload_started
	_check(focus_reloaded, "edited focus region becomes visible again after returning")

	var settle_started := Time.get_ticks_usec()
	var reloaded := await _wait_until(func() -> bool:
		return demo.focus_region_key == Vector2i.ZERO \
			and demo.active_regions.has(origin_id) \
			and demo.loading_regions.is_empty() \
			and not demo.global_rebuild_pending
	)
	var full_settle_usec := Time.get_ticks_usec() - reload_started
	var post_focus_settle_usec := Time.get_ticks_usec() - settle_started
	_check(reloaded, "complete 3x3 streaming window settles after returning")
	_check(demo.edit_ledger.get_edit_count() == PREEDIT_COUNT, "reload preserves lifetime edit count")
	_check(demo.edit_ledger.get_tail_edit_count() == 0, "reload uses materialized state with empty hot tail")

	var after_stats: Dictionary = demo.world_save_store.get_hot_stats()
	_check(
		int(after_stats.get("journal_read_count", -1)) == int(before_stats.get("journal_read_count", -2)),
		"stream unload/reload performs zero archived journal reads"
	)
	var x_diag: Dictionary = demo._last_shared_x_boundary_diagnostics
	var z_diag: Dictionary = demo._last_shared_z_boundary_diagnostics
	var corner_diag: Dictionary = demo._last_shared_corner_diagnostics
	_check(not x_diag.is_empty(), "runtime publishes X-boundary diagnostics")
	_check(not z_diag.is_empty(), "runtime publishes Z-boundary diagnostics")
	_check(not corner_diag.is_empty(), "runtime publishes four-region corner diagnostics")
	if not x_diag.is_empty():
		_check(int(x_diag.get("seam_bad_incidence_count", -1)) == 0, "runtime X seam has no bad incidence")
		_check(int(x_diag.get("t_junction_count", -1)) == 0, "runtime X seam has no T-junctions")
		_check(
			int(x_diag.get("seam_cross_owner_count", -1))
				== int(x_diag.get("seam_crossing_edge_count", -2)),
			"runtime X crossing seam edges remain cross-owned"
		)
	if not z_diag.is_empty():
		_check(int(z_diag.get("seam_bad_incidence_count", -1)) == 0, "runtime Z seam has no bad incidence")
		_check(int(z_diag.get("t_junction_count", -1)) == 0, "runtime Z seam has no T-junctions")
		_check(
			int(z_diag.get("seam_cross_owner_count", -1))
				== int(z_diag.get("seam_crossing_edge_count", -2)),
			"runtime Z crossing seam edges remain cross-owned"
		)
	if not corner_diag.is_empty():
		_check(int(corner_diag.get("x_seam_bad_incidence_count", -1)) == 0, "runtime corner X plane has no bad incidence")
		_check(int(corner_diag.get("z_seam_bad_incidence_count", -1)) == 0, "runtime corner Z plane has no bad incidence")
		_check(int(corner_diag.get("junction_bad_incidence_count", -1)) == 0, "runtime four-region junction has no bad incidence")
		_check(int(corner_diag.get("x_t_junction_count", -1)) == 0, "runtime corner X plane has no T-junctions")
		_check(int(corner_diag.get("z_t_junction_count", -1)) == 0, "runtime corner Z plane has no T-junctions")
		_check(int(corner_diag.get("junction_t_junction_count", -1)) == 0, "runtime four-region junction has no T-junctions")

	demo._update_runtime_diagnostics()
	evidence = {
		"preedit_count": PREEDIT_COUNT,
		"preedit_elapsed_ms": float(preedit_elapsed_usec) / 1000.0,
		"checkpoint_generation": demo._checkpoint_generation,
		"checkpoint_worker_ms": demo._checkpoint_last_worker_ms,
		"focus_reload_elapsed_ms": float(focus_reload_usec) / 1000.0,
		"full_window_settle_elapsed_ms": float(full_settle_usec) / 1000.0,
		"post_focus_window_settle_ms": float(post_focus_settle_usec) / 1000.0,
		"frame_p50_ms": float(demo.last_mesh_diagnostics.get("frame_time_p50_ms", 0.0)),
		"frame_p95_ms": float(demo.last_mesh_diagnostics.get("frame_time_p95_ms", 0.0)),
		"frame_p99_ms": float(demo.last_mesh_diagnostics.get("frame_time_p99_ms", 0.0)),
		"peak_frame_ms": float(demo.last_mesh_diagnostics.get("peak_frame_ms", 0.0)),
		"peak_process_work_ms": float(demo.last_mesh_diagnostics.get("peak_process_work_ms", 0.0)),
		"streamed_region_loads": int(demo.last_mesh_diagnostics.get("streamed_region_loads", 0)),
		"streamed_region_unloads": int(demo.last_mesh_diagnostics.get("streamed_region_unloads", 0)),
		"store_stats": after_stats,
		"shared_x_boundary": x_diag,
		"shared_z_boundary": z_diag,
		"shared_corner": corner_diag,
	}
	# Hosted headless timing is evidence, not a product FPS threshold. This only
	# catches a pathological reload stall; target-machine frame budgets are manual.
	_check(focus_reload_usec < 5000000, "headless edited focus region becomes visible within 5 seconds")

	await _shutdown(demo)


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
	var cleanup_ok := _cleanup_tree(_root)
	_check(cleanup_ok, "runtime qualification storage is cleaned")
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
	var payload := {
		"status": "PASS" if failures == 0 else "FAIL",
		"assertions": assertions,
		"failures": failures,
		"evidence": evidence,
	}
	print("RUNTIME_SCALABLE_PLAYABLE_RESULT=" + JSON.stringify(payload))
	print("RUNTIME_SCALABLE_PLAYABLE_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
