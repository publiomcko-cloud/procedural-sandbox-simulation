extends SceneTree

const SaveStore := preload("res://scripts/terrain/terrain_world_save_store_v2.gd")

const TIMEOUT_MSEC := 60000
const YIELD_MSEC := 1

var assertions := 0
var failures := 0
var fixture_root := ""
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	fixture_root = "user://issue108_d3_visual_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(fixture_root)
	)

	var scene: Node3D = load("res://scenes/terrain_demo.tscn").instantiate()
	scene.set(
		"world_save_store",
		SaveStore.new(fixture_root.path_join("terrain"))
	)
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

	root.add_child(scene)
	var ready := await _wait_stream_idle(scene)
	_check(ready, "cold real scene reaches stable object publication")
	if ready:
		var stream: Node = scene.get_node("ProceduralObjects")
		var perf: Dictionary = stream.get_performance_snapshot()
		var last_region: Dictionary = perf.get("last_region", {})
		evidence = {
			"visual_mesh_commit_budget_per_frame":
				int(perf.get("visual_mesh_commit_budget_per_frame", -1)),
			"peak_visual_mesh_commits_per_tick":
				int(perf.get("peak_visual_mesh_commits_per_tick", -1)),
			"visual_mesh_commit_count":
				int(perf.get("visual_mesh_commit_count", 0)),
			"visual_mesh_commit_peak_usec":
				int(perf.get("visual_mesh_commit_peak_usec", 0)),
			"visual_mesh_commit_total_usec":
				int(perf.get("visual_mesh_commit_total_usec", 0)),
			"visual_prewarm_completed_count":
				int(perf.get("visual_prewarm_completed_count", 0)),
			"geometry_cache_miss_count":
				int(perf.get("geometry_cache_miss_count", 0)),
			"peak_geometry_build_usec":
				int(perf.get("peak_geometry_build_usec", 0)),
			"last_region_mesh_build_usec":
				int(last_region.get("mesh_build_usec", 0)),
			"last_region_geometry_cache_misses":
				int(last_region.get("geometry_cache_misses", -1)),
			"active_region_count": stream.get_active_region_count(),
			"visible_instance_count": stream.get_visible_instance_count(),
		}
		_check(
			int(perf.get("visual_mesh_commit_budget_per_frame", -1)) == 1,
			"D.3 exposes one expensive ArrayMesh commit per frame"
		)
		_check(
			int(perf.get("peak_visual_mesh_commits_per_tick", 99)) <= 1,
			"runtime never commits more than one cold ArrayMesh variant in one tick"
		)
		_check(
			int(perf.get("visual_mesh_commit_count", 0)) > 0,
			"cold scene exercises incremental visual mesh commits"
		)
		_check(
			int(perf.get("visual_prewarm_completed_count", 0)) > 0,
			"at least one region completes visual prewarm before publication"
		)
		_check(
			int(perf.get("geometry_cache_miss_count", -1))
				== int(perf.get("visual_mesh_commit_count", -2)),
			"cold geometry cache misses are paid by the paced prewarm path"
		)
		_check(
			int(last_region.get("geometry_cache_misses", -1)) == 0,
			"atomic region publication performs no cold mesh commits"
		)
		_check(
			int(perf.get("peak_geometry_build_usec", 999999999)) < 100000,
			"published-region mesh phase stays below 100 ms after prewarm"
		)
		_check(
			stream.get_active_region_count() > 0
				and stream.get_visible_instance_count() > 0,
			"incremental prewarm preserves visible object publication"
		)

	await _finish_scene(scene)
	_finish()


func _wait_stream_idle(scene: Node) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	var stream: Node = scene.get_node("ProceduralObjects")
	var stable_frames := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(YIELD_MSEC)
		var active: Dictionary = scene.get("active_regions")
		var loading: Dictionary = scene.get("loading_regions")
		var mesh_jobs: Dictionary = scene.get("_mesh_jobs")
		var perf: Dictionary = stream.get_performance_snapshot()
		var stable: bool = active.has("0,0") 			and stream.has_published_region(Vector2i.ZERO) 			and loading.is_empty() 			and mesh_jobs.is_empty() 			and int(perf.get("pending_region_publication_count", 0)) == 0 			and not bool(scene.get("global_rebuild_pending"))
		if stable:
			stable_frames += 1
			if stable_frames >= 3:
				return true
		else:
			stable_frames = 0
	print("D3_VISUAL_TIMEOUT perf=%s stream_error=%s" % [
		str(stream.get_performance_snapshot()),
		String(stream.get_error_summary()),
	])
	return false


func _finish_scene(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		OS.delay_msec(10)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var child := directory.get_next()
		if child.is_empty():
			break
		if child == "." or child == "..":
			continue
		var child_path := path.path_join(child)
		if directory.current_is_dir():
			_remove_tree(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("ISSUE108_D3_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D3_%s: assertions=%d failures=%d" % [
		"VISUAL_COMMIT_PASS" if failures == 0 else "VISUAL_COMMIT_FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(fixture_root))
	quit(0 if failures == 0 else 1)
