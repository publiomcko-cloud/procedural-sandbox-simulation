extends SceneTree

const SaveStore := preload("res://scripts/terrain/terrain_world_save_store_v2.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

const ASYNC_WAIT_TIMEOUT_MSEC := 60000
const ASYNC_WORKER_YIELD_MSEC := 1
const TRAVERSAL_STEPS := 8

var assertions := 0
var failures := 0
var fixture_root := ""
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_root = "user://issue108_d1_scene_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_root))

	var scene: Node3D = load("res://scenes/terrain_demo.tscn").instantiate()
	scene.set("world_save_store", SaveStore.new(fixture_root.path_join("terrain")))
	scene.set(
		"object_state_directory_override",
		ProjectSettings.globalize_path(fixture_root.path_join("entities"))
	)
	scene.set(
		"terrain_effect_directory_override",
		ProjectSettings.globalize_path(
			fixture_root.path_join("terrain-object-effects")
		)
	)
	var package_roots: Array[String] = ["res://mods/first-party"]
	scene.set("object_package_roots_override", package_roots)

	var initial_started := Time.get_ticks_usec()
	root.add_child(scene)
	var initial_ok := await _wait_stream_idle(scene, Vector2i.ZERO)
	var initial_usec := Time.get_ticks_usec() - initial_started
	_check(initial_ok, "initial real scene reaches stable published focus")
	if not initial_ok:
		await _finish_scene(scene)
		_finish()
		return

	var forward_usec: Array[int] = []
	for x in range(1, TRAVERSAL_STEPS + 1):
		var started := Time.get_ticks_usec()
		scene.call("_move_focus", Vector3(Spatial.REGION_SIZE_X, 0.0, 0.0))
		var ok := await _wait_stream_idle(scene, Vector2i(x, 0))
		forward_usec.append(Time.get_ticks_usec() - started)
		_check(ok, "forward streaming step %d stabilizes" % x)
		if not ok:
			await _finish_scene(scene)
			_finish()
			return

	var return_usec: Array[int] = []
	for x in range(TRAVERSAL_STEPS - 1, -1, -1):
		var started := Time.get_ticks_usec()
		scene.call("_move_focus", Vector3(-Spatial.REGION_SIZE_X, 0.0, 0.0))
		var ok := await _wait_stream_idle(scene, Vector2i(x, 0))
		return_usec.append(Time.get_ticks_usec() - started)
		_check(ok, "return streaming step %d stabilizes" % x)
		if not ok:
			await _finish_scene(scene)
			_finish()
			return

	var all_steps: Array[int] = []
	all_steps.append_array(forward_usec)
	all_steps.append_array(return_usec)
	var effect_perf: Dictionary = {}
	var runtime: Variant = scene.get("terrain_effect_runtime")
	if runtime != null and runtime.has_method("get_performance_snapshot"):
		effect_perf = runtime.call("get_performance_snapshot")

	var stream: Node = scene.get_node("ProceduralObjects")
	var stream_perf: Dictionary = stream.get_performance_snapshot()
	evidence = {
		"initial_usec": initial_usec,
		"forward_step_usec": forward_usec,
		"return_step_usec": return_usec,
		"step_p50_usec": _percentile(all_steps, 0.50),
		"step_p95_usec": _percentile(all_steps, 0.95),
		"step_max_usec": _max_value(all_steps),
		"final_active_region_count": (scene.get("active_regions") as Dictionary).size(),
		"final_chunk_count": (scene.get("chunk_nodes") as Dictionary).size(),
		"lod_fallback_chunk_count": (scene.get("_lod_fallback_chunks") as Dictionary).size(),
		"visible_object_count": stream.get_visible_instance_count(),
		"object_active_region_count": stream.get_active_region_count(),
		"object_peak_generation_usec": int(stream_perf.get("peak_generation_usec", 0)),
		"last_stream_error": String(scene.get("last_stream_error")),
	}
	if not effect_perf.is_empty():
		evidence["effect_runtime"] = effect_perf

	_check(
		String(scene.get("last_stream_error")).is_empty(),
		"real scene traversal ends without terrain stream error"
	)
	_check(
		stream.get_active_region_count() > 0
			and stream.get_visible_instance_count() > 0,
		"real scene traversal keeps procedural objects published"
	)

	await _finish_scene(scene)
	_finish()


func _wait_stream_idle(scene: Node, expected_focus: Vector2i) -> bool:
	var deadline := Time.get_ticks_msec() + ASYNC_WAIT_TIMEOUT_MSEC
	var stream: Node = scene.get_node("ProceduralObjects")
	var expected_id := "%d,%d" % [expected_focus.x, expected_focus.y]
	var stable_frames := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(ASYNC_WORKER_YIELD_MSEC)
		var active: Dictionary = scene.get("active_regions")
		var loading: Dictionary = scene.get("loading_regions")
		var mesh_jobs: Dictionary = scene.get("_mesh_jobs")
		var stream_perf: Dictionary = stream.get_performance_snapshot()
		var stable := active.has(expected_id) 			and stream.has_published_region(expected_focus) 			and loading.is_empty() 			and mesh_jobs.is_empty() 			and int(stream_perf.get("pending_region_publication_count", 0)) == 0 			and not bool(scene.get("global_rebuild_pending"))
		if stable:
			stable_frames += 1
			if stable_frames >= 3:
				return true
		else:
			stable_frames = 0
	print("D1_SCENE_TIMEOUT: expected=%s focus=%s active=%s loading=%s mesh_jobs=%d stream_perf=%s stream_error=%s effect_status=%s" % [
		expected_focus,
		scene.get("focus_region_key"),
		str(scene.get("active_regions")),
		str(scene.get("loading_regions")),
		(scene.get("_mesh_jobs") as Dictionary).size(),
		str(stream.get_performance_snapshot()),
		String(stream.get_error_summary()),
		String(scene.get("_terrain_effect_status")),
	])
	return false


func _percentile(values: Array[int], fraction: float) -> int:
	if values.is_empty():
		return 0
	var ordered := values.duplicate()
	ordered.sort()
	var index := clampi(
		ceili(float(ordered.size()) * fraction) - 1,
		0,
		ordered.size() - 1
	)
	return int(ordered[index])


func _max_value(values: Array[int]) -> int:
	var result := 0
	for value in values:
		result = maxi(result, int(value))
	return result


func _finish_scene(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		OS.delay_msec(10)


func _remove_fixture() -> void:
	_remove_tree(ProjectSettings.globalize_path(fixture_root))


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var child := dir.get_next()
		if child.is_empty():
			break
		if child == "." or child == "..":
			continue
		var child_path := path.path_join(child)
		if dir.current_is_dir():
			_remove_tree(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	dir.list_dir_end()
	dir = null
	DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("ISSUE108_D1_SCENE_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D1_SCENE_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_fixture()
	quit(0 if failures == 0 else 1)
