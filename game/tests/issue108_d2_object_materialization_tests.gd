extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const RegionGenerationJob := preload("res://scripts/objects/procedural_object_region_generation_job.gd")
const MaterializationStore := preload("res://scripts/objects/procedural_object_materialization_store.gd")
const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")

const WORLD_ID := "issue108-d2-materialization"
const WORLD_SEED := 424242
const ROOT := "user://issue108-d2-materialization"

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_absolute := ProjectSettings.globalize_path(ROOT)
	_remove_tree(root_absolute)

	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register(["res://mods/first-party"])
	_check(registered.get("ok", false), "first-party registry initializes")
	if not registered.get("ok", false):
		_finish()
		return

	var signature := MaterializationStore.build_content_signature(registry)
	_check(signature.length() == 64, "content materialization signature is sha256")
	_check(
		signature == MaterializationStore.build_content_signature(registry),
		"content materialization signature is deterministic"
	)

	var materialization_directory := ROOT + "/regions"
	var first_job := RegionGenerationJob.new(
		WORLD_SEED,
		WORLD_ID,
		Vector2i.ZERO,
		registry,
		signature,
		materialization_directory
	)
	first_job.run()
	var first: Dictionary = first_job.result
	_check(first.get("ok", false), "cold region generation succeeds")
	_check(
		not bool(first.get("materialization_hit", true)),
		"cold region generation is a materialization miss"
	)
	_check(
		(first.get("geometry_cpu_by_instance", {}) as Dictionary).size()
			== (first.get("instances", []) as Array).size(),
		"cold generation materializes CPU geometry for every instance"
	)

	var second_job := RegionGenerationJob.new(
		WORLD_SEED,
		WORLD_ID,
		Vector2i.ZERO,
		registry,
		signature,
		materialization_directory
	)
	second_job.run()
	var second: Dictionary = second_job.result
	_check(second.get("ok", false), "warm region generation succeeds")
	_check(
		bool(second.get("materialization_hit", false)),
		"warm region generation hydrates the persistent materialization"
	)
	_check(
		_instance_ids(first) == _instance_ids(second),
		"materialized region preserves deterministic object identities"
	)
	_check(
		(second.get("geometry_cpu_by_instance", {}) as Dictionary).size()
			== (second.get("instances", []) as Array).size(),
		"warm materialization restores CPU geometry"
	)

	var changed_signature := "0".repeat(64)
	if changed_signature == signature:
		changed_signature = "1".repeat(64)
	var invalidated_job := RegionGenerationJob.new(
		WORLD_SEED,
		WORLD_ID,
		Vector2i.ZERO,
		registry,
		changed_signature,
		materialization_directory
	)
	invalidated_job.run()
	_check(
		not bool(invalidated_job.result.get("materialization_hit", true)),
		"content signature change invalidates the derived snapshot"
	)

	var instances: Array = second.get("instances", [])
	if instances.is_empty():
		_check(false, "generated region contains at least one object")
	else:
		var instance: Dictionary = instances[0]
		var instance_id := String(instance.get("instance_id", ""))
		var cpu_by_instance: Dictionary = second.get("geometry_cpu_by_instance", {})
		var stream := ObjectStream.new()
		var first_mesh: Dictionary = stream._get_or_build_geometry_mesh(
			instance, cpu_by_instance.get(instance_id, {})
		)
		var second_mesh: Dictionary = stream._get_or_build_geometry_mesh(
			instance, cpu_by_instance.get(instance_id, {})
		)
		_check(first_mesh.get("ok", false), "first main-thread mesh commit succeeds")
		_check(second_mesh.get("ok", false), "second mesh request succeeds")
		_check(
			first_mesh.get("mesh") == second_mesh.get("mesh"),
			"second mesh request reuses the same ArrayMesh resource"
		)
		var perf: Dictionary = stream.get_performance_snapshot()
		_check(
			int(perf.get("geometry_cache_miss_count", -1)) == 1
				and int(perf.get("geometry_cache_hit_count", -1)) == 1,
			"geometry cache records one miss followed by one hit"
		)
		_check(
			int(perf.get("geometry_cache_capacity", 0)) >= 512,
			"D.2 geometry cache retains a traversal-scale working set"
		)
		stream.free()

	evidence = {
		"cold_worker_usec": int(first.get("worker_usec", 0)),
		"cold_materialization_save_usec": int(first.get("materialization_save_usec", 0)),
		"warm_worker_usec": int(second.get("worker_usec", 0)),
		"warm_materialization_load_usec": int(second.get("materialization_load_usec", 0)),
		"instance_count": (second.get("instances", []) as Array).size(),
		"content_signature": signature,
	}
	_finish()


func _instance_ids(generated: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for value in generated.get("instances", []):
		if typeof(value) == TYPE_DICTIONARY:
			ids.append(String((value as Dictionary).get("instance_id", "")))
	ids.sort()
	return ids


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
	print("ISSUE108_D2_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D2_%s: assertions=%d failures=%d" % [
		"MATERIALIZATION_PASS" if failures == 0 else "MATERIALIZATION_FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
