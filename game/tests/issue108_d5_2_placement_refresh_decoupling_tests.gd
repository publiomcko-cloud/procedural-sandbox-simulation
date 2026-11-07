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
		"issue108-d5-2-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	scene.set("world_save_store", WorldSaveStore.new(store_path))
	scene.set("object_state_directory_override", store_path.path_join("objects"))
	scene.set("terrain_effect_directory_override", store_path.path_join("effects"))
	scene.set("object_package_roots_override", ["res://mods/first-party"])
	root.add_child(scene)

	var focused_profile := await _wait_for_publish_profile(scene, Vector2i.ZERO)
	_check(not focused_profile.is_empty(), "focused terrain publication emits a profile")
	if focused_profile.is_empty():
		scene.queue_free()
		await process_frame
		_remove_tree(store_path)
		_finish()
		return

	var timings: Dictionary = focused_profile.get("timings_usec", {})
	_check(bool(focused_profile.get("focused_region", false)), "profile identifies focused publication")
	_check(int(focused_profile.get("mesh_count", 0)) == 16, "focused publication remains atomic at sixteen chunks")
	_check(
		int(timings.get("focus_refresh", -1)) == 0,
		"focused terrain publication performs no synchronous placement refresh"
	)
	_check(
		timings.has("placement_invalidate"),
		"focused terrain publication exposes cheap placement invalidation timing"
	)
	_check(
		bool(focused_profile.get("placement_target_dirty_after_publish", false)),
		"focused terrain publication marks placement preview dirty"
	)
	_check(
		int(focused_profile.get("placement_target_invalidation_count", 0)) >= 1,
		"focused terrain publication records placement invalidation"
	)
	_check(
		scene.get("active_regions").has("0,0")
			and (scene.get("active_regions")["0,0"]["chunk_nodes"] as Dictionary).size() == 16,
		"decoupling preserves focused-region publication"
	)

	scene.call("_refresh_placement_target_indicator")
	_check(
		not bool(scene.get("_placement_target_dirty")),
		"explicit placement refresh clears the dirty flag"
	)

	scene.call("_invalidate_placement_target_after_terrain_change")
	_check(
		bool(scene.get("_placement_target_dirty")),
		"terrain invalidation marks the preview dirty"
	)
	_check(
		not bool(scene.get("_placement_target_valid")),
		"terrain invalidation prevents stale placement preview use"
	)

	evidence = {
		"focused_duration_usec": int(focused_profile.get("duration_usec", -1)),
		"focus_refresh_usec": int(timings.get("focus_refresh", -1)),
		"placement_invalidate_usec": int(timings.get("placement_invalidate", -1)),
		"chunk_commit_usec": int(timings.get("chunk_commit", -1)),
		"placement_target_dirty_after_publish": bool(
			focused_profile.get("placement_target_dirty_after_publish", false)
		),
		"placement_target_invalidation_count": int(
			focused_profile.get("placement_target_invalidation_count", -1)
		),
	}

	scene.queue_free()
	await process_frame
	_remove_tree(store_path)
	_finish()


func _wait_for_publish_profile(scene: Node, expected_region: Vector2i) -> Dictionary:
	for _frame in range(5000):
		var profile: Dictionary = scene.get("_last_region_publish_profile")
		var region: Array = profile.get("region", [])
		if (
			region.size() == 2
			and int(region[0]) == expected_region.x
			and int(region[1]) == expected_region.y
		):
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
	print("ISSUE108_D5_2_PLACEMENT_DECOUPLING_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D5_2_PLACEMENT_DECOUPLING_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	quit(0 if failures == 0 else 1)
