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
		"issue108-d5-1-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	scene.set("world_save_store", WorldSaveStore.new(store_path))
	scene.set("object_state_directory_override", store_path.path_join("objects"))
	scene.set("terrain_effect_directory_override", store_path.path_join("effects"))
	scene.set("object_package_roots_override", ["res://mods/first-party"])
	root.add_child(scene)

	var focused_profile := await _wait_for_publish_profile(scene, Vector2i.ZERO)
	_check(not focused_profile.is_empty(), "focused region publication emits a decomposition profile")
	if focused_profile.is_empty():
		scene.queue_free()
		await process_frame
		_remove_tree(store_path)
		_finish()
		return

	var focused_timings: Dictionary = focused_profile.get("timings_usec", {})
	var focused_chunk_timings: Dictionary = focused_profile.get("chunk_timings_usec", {})
	_check(bool(focused_profile.get("focused_region", false)), "focused publication is labeled explicitly")
	_check(int(focused_profile.get("mesh_count", 0)) == 16, "focused publication retains all sixteen chunk meshes")
	_check(
		int(focused_profile.get("created_node_count", 0))
			+ int(focused_profile.get("reused_node_count", 0)) == 16,
		"focused profile accounts for every published chunk node"
	)
	_check(
		focused_timings.has("chunk_commit")
			and focused_timings.has("object_enqueue")
			and focused_timings.has("focus_refresh")
			and focused_timings.has("top_level_unaccounted"),
		"top-level publication phases are exposed"
	)
	_check(
		focused_chunk_timings.has("node_resolve")
			and focused_chunk_timings.has("mesh_replace")
			and focused_chunk_timings.has("metadata")
			and focused_chunk_timings.has("lod_state")
			and focused_chunk_timings.has("index_commit"),
		"chunk publication phases are exposed"
	)
	_check(
		int(focused_profile.get("duration_usec", 0))
			>= int(focused_timings.get("focus_refresh", 0)),
		"focused refresh timing is bounded by total publication time"
	)

	var neighbor_profile := await _wait_for_nonfocused_publish_profile(scene)
	_check(not neighbor_profile.is_empty(), "non-focused region publication emits a decomposition profile")
	if not neighbor_profile.is_empty():
		var neighbor_timings: Dictionary = neighbor_profile.get("timings_usec", {})
		_check(not bool(neighbor_profile.get("focused_region", true)), "neighbor publication is labeled non-focused")
		_check(
			int(neighbor_timings.get("focus_refresh", -1)) == 0,
			"non-focused publication performs no placement-target refresh"
		)
		_check(
			int(neighbor_profile.get("created_node_count", 0))
				+ int(neighbor_profile.get("reused_node_count", 0)) == 16,
			"neighbor profile accounts for every published chunk node"
		)

	_check(
		scene.get("active_regions").has("0,0")
			and (scene.get("active_regions")["0,0"]["chunk_nodes"] as Dictionary).size() == 16,
		"instrumentation preserves atomic focused-region publication"
	)

	evidence = {
		"focused_duration_usec": int(focused_profile.get("duration_usec", -1)),
		"focused_timings_usec": focused_timings,
		"focused_chunk_timings_usec": focused_chunk_timings,
		"focused_created_nodes": int(focused_profile.get("created_node_count", -1)),
		"focused_reused_nodes": int(focused_profile.get("reused_node_count", -1)),
		"neighbor_region": neighbor_profile.get("region", []),
		"neighbor_duration_usec": int(neighbor_profile.get("duration_usec", -1)),
		"neighbor_timings_usec": neighbor_profile.get("timings_usec", {}),
	}
	scene.queue_free()
	await process_frame
	_remove_tree(store_path)
	_finish()


func _wait_for_publish_profile(scene: Node, expected_region: Vector2i) -> Dictionary:
	for _frame in range(5000):
		var profile: Dictionary = scene.get("_last_region_publish_profile")
		var region: Array = profile.get("region", [])
		if region.size() == 2 			and int(region[0]) == expected_region.x 			and int(region[1]) == expected_region.y:
			return profile.duplicate(true)
		await process_frame
	return {}


func _wait_for_nonfocused_publish_profile(scene: Node) -> Dictionary:
	for _frame in range(5000):
		var profile: Dictionary = scene.get("_last_region_publish_profile")
		var region: Array = profile.get("region", [])
		if region.size() == 2 			and not (int(region[0]) == 0 and int(region[1]) == 0):
			return profile.duplicate(true)
		await process_frame
	return {}


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
	print("ISSUE108_D5_1_REGION_PUBLISH_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D5_1_REGION_PUBLISH_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	quit(0 if failures == 0 else 1)
