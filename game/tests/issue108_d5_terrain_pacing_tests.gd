extends SceneTree

const WorldSaveStore := preload("res://scripts/terrain/terrain_world_save_store_v2.gd")

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "terrain demo scene loads")
	if packed == null:
		_finish()
		return
	var scene: Node = packed.instantiate()
	var store_path := OS.get_temp_dir().path_join(
		"issue108-d5-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	scene.set("world_save_store", WorldSaveStore.new(store_path))
	root.add_child(scene)

	var ready := await _wait_for_window(scene)
	_check(ready, "initial 3x3 terrain window completes")
	if not ready:
		scene.queue_free()
		await process_frame
		_finish()
		return
	for _i in range(20):
		await process_frame
	var diagnostics: Dictionary = scene.get("last_mesh_diagnostics")
	_check(
		int(diagnostics.get("peak_mesh_dispatches_per_frame", 99)) <= 1,
		"terrain snapshot dispatch is capped at one job per process frame"
	)
	_check(
		int(diagnostics.get("mesh_job_limit", 99)) <= 8,
		"terrain worker pressure is capped at eight in-flight jobs"
	)
	_check(
		scene.get("active_regions").size() == 9
			and scene.get("chunk_nodes").size() == 144,
		"pacing preserves complete 3x3 publication"
	)

	var metadata_complete := true
	var triangle_sum := 0
	var vertex_sum := 0
	for node_value in (scene.get("chunk_nodes") as Dictionary).values():
		var node := node_value as MeshInstance3D
		if node == null 			or not node.has_meta("mesh_triangle_count") 			or not node.has_meta("mesh_vertex_count"):
			metadata_complete = false
			continue
		triangle_sum += int(node.get_meta("mesh_triangle_count", 0))
		vertex_sum += int(node.get_meta("mesh_vertex_count", 0))
	_check(
		metadata_complete,
		"published terrain nodes retain worker-derived mesh counts"
	)
	_check(
		triangle_sum == int(scene.get("_active_triangle_count"))
			and vertex_sum == int(scene.get("_active_vertex_count")),
		"cached mesh-count accounting matches active terrain totals"
	)

	evidence = {
		"peak_mesh_dispatches_per_frame": int(
			diagnostics.get("peak_mesh_dispatches_per_frame", -1)
		),
		"mesh_job_limit": int(diagnostics.get("mesh_job_limit", -1)),
		"peak_mesh_jobs_in_flight": int(
			diagnostics.get("peak_mesh_jobs_in_flight", -1)
		),
		"active_regions": scene.get("active_regions").size(),
		"active_chunks": scene.get("chunk_nodes").size(),
		"triangle_sum": triangle_sum,
		"vertex_sum": vertex_sum,
		"active_triangle_count": int(scene.get("_active_triangle_count")),
		"active_vertex_count": int(scene.get("_active_vertex_count")),
	}
	scene.queue_free()
	await process_frame
	_remove_tree(store_path)
	_finish()


func _wait_for_window(scene: Node) -> bool:
	for _frame in range(5000):
		var active: Dictionary = scene.get("active_regions")
		if active.size() == 9 and scene.get("loading_regions").is_empty():
			return true
		await process_frame
	return false


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("ISSUE108_D5_TERRAIN_PACING_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D5_TERRAIN_PACING_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	quit(0 if failures == 0 else 1)
