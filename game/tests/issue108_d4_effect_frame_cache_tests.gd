extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-d4-effect-cache"
const WORLD_SEED := 424242
const ROOT := "user://issue108-d4-effect-cache-tests"
const TIMEOUT_MSEC := 20000

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


class FakeGenerationJob:
	extends RefCounted

	var region_key := Vector2i.ZERO
	var result: Dictionary = {}
	var worker_started_usec := 0
	var worker_finished_usec := 0

	func _init(key: Vector2i) -> void:
		region_key = key

	func run() -> void:
		worker_started_usec = Time.get_ticks_usec()
		result = {
			"ok": true,
			"region_key": region_key,
			"timings_usec": {"total": 0},
		}
		worker_finished_usec = Time.get_ticks_usec()
		result["worker_usec"] = worker_finished_usec - worker_started_usec


class FakeObjectStream:
	extends Node

	var source_region := Vector2i.ZERO
	var instance: Dictionary = {}
	var active := true
	var world_revision := 0
	var entity_revision := 0

	func get_command_world_revision() -> int:
		return world_revision

	func get_authoritative_region_projection_source(region_key: Vector2i) -> Dictionary:
		var instances: Array[Dictionary] = []
		var revisions: Dictionary = {}
		if active and region_key == source_region and not instance.is_empty():
			instances.append(instance.duplicate(true))
			revisions[String(instance["instance_id"])] = entity_revision
		return {
			"ok": true,
			"region_key": region_key,
			"world_revision": world_revision,
			"instances": instances,
			"source_revisions": revisions,
		}

	func create_projection_source_generation_job(region_key: Vector2i) -> RefCounted:
		return FakeGenerationJob.new(region_key)

	func finalize_authoritative_region_projection_source(
		region_key: Vector2i,
		generated: Dictionary
	) -> Dictionary:
		if not generated.get("ok", false):
			return {"ok": false, "reason": "fake_generation_failed"}
		return get_authoritative_region_projection_source(region_key)

	func transform_translation(value: Vector3i) -> void:
		if instance.is_empty():
			return
		var components: Dictionary = instance.get(
			"instance_components", {}
		).duplicate(true)
		var default_scale: Vector3i = instance.get(
			"default_scale_milli", Vector3i(1000, 1000, 1000)
		)
		components["core.transform"] = {
			"schema_version": 1,
			"properties": {
				"translation_mm": [value.x, value.y, value.z],
				"rotation_mdeg": [
					0, int(instance.get("default_yaw_mdeg", 0)), 0
				],
				"scale_milli": [
					default_scale.x, default_scale.y, default_scale.z
				],
			},
		}
		instance["instance_components"] = components
		entity_revision += 1
		world_revision += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register([
		"res://mods/first-party"
	])
	_check(registered.get("ok", false), "first-party registry initializes")
	if not registered.get("ok", false):
		_finish()
		return

	var generated: Dictionary = ObjectWorld.build_region_instances(
		WORLD_SEED, WORLD_ID, Vector2i.ZERO, registry
	)
	_check(generated.get("ok", false), "reference procedural region generates")
	var interacting := _first_interacting(generated.get("instances", []))
	_check(not interacting.is_empty(), "reference interacting source exists")
	if interacting.is_empty():
		_finish()
		return

	var fake := FakeObjectStream.new()
	fake.instance = interacting
	var runtime := Runtime.new()
	var initialized: Dictionary = runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		fake,
		ROOT + "/projection"
	)
	_check(initialized.get("ok", false), "D4 runtime initializes")
	if not initialized.get("ok", false):
		_finish()
		return
	runtime.set_incremental_prefetch_enabled(true)

	var window: Dictionary = runtime.update_resident_target_regions([
		Vector2i.ZERO
	])
	_check(window.get("ok", false), "cold source window queues")
	var cold_drained := await _drain(runtime)
	_check(cold_drained, "cold source window drains")
	var cold_perf: Dictionary = runtime.get_performance_snapshot()
	var cold_misses := int(cold_perf.get(
		"projection_build_cache_miss_count", 0
	))
	var cold_dispatches := int(cold_perf.get(
		"prefetch_projection_worker_dispatch_count", 0
	))
	_check(
		cold_misses > 0 and cold_dispatches == cold_misses,
		"cold scopes build through projection workers exactly once"
	)
	_check(
		int(cold_perf.get("projection_build_cache_hit_count", -1)) == 0,
		"cold pass has no false cache hits"
	)
	_check(
		int(cold_perf.get("projection_build_cache_entry_count", 0))
			== cold_misses,
		"successful cold builds populate bounded derived cache"
	)
	var cold_scope: Dictionary = runtime.projection.get_scope_snapshot(
		Vector2i.ZERO
	)
	var cold_frame_hash := _first_frame_hash(cold_scope)
	_check(
		not cold_frame_hash.is_empty(),
		"cold center scope publishes an effect frame"
	)

	runtime.release_all_scopes()
	runtime.reset_performance_metrics()
	var warm_window: Dictionary = runtime.update_resident_target_regions([
		Vector2i.ZERO
	])
	_check(warm_window.get("ok", false), "warm revisit window queues")
	var warm_drained := await _drain(runtime)
	_check(warm_drained, "warm revisit window drains from cache")
	var warm_perf: Dictionary = runtime.get_performance_snapshot()
	var warm_hits := int(warm_perf.get(
		"projection_build_cache_hit_count", 0
	))
	_check(
		warm_hits == cold_misses,
		"unchanged revisited scopes reuse every cached projection build"
	)
	_check(
		int(warm_perf.get("projection_build_cache_miss_count", -1)) == 0
			and int(warm_perf.get(
				"prefetch_projection_worker_dispatch_count", -1
			)) == 0,
		"warm revisit dispatches no Effect/LocalFrame worker rebuilds"
	)
	_check(
		int(warm_perf.get("projection_build_cache_reused_effect_count", 0)) > 0,
		"warm revisit reuses at least one terrain effect frame"
	)
	var warm_scope: Dictionary = runtime.projection.get_scope_snapshot(
		Vector2i.ZERO
	)
	_check(
		_first_frame_hash(warm_scope) == cold_frame_hash,
		"cache reuse preserves canonical frame identity"
	)

	runtime.release_all_scopes()
	fake.transform_translation(Vector3i(350, 0, 0))
	runtime.reset_performance_metrics()
	var mutated_window: Dictionary = runtime.update_resident_target_regions([
		Vector2i.ZERO
	])
	_check(mutated_window.get("ok", false), "mutated source window queues")
	var mutated_drained := await _drain(runtime)
	_check(mutated_drained, "mutated source window drains")
	var mutated_perf: Dictionary = runtime.get_performance_snapshot()
	_check(
		int(mutated_perf.get("projection_build_cache_miss_count", 0)) == 1
			and int(mutated_perf.get(
				"prefetch_projection_worker_dispatch_count", 0
			)) == 1,
		"one changed source scope invalidates only its content-addressed cache entry"
	)
	_check(
		int(mutated_perf.get("projection_build_cache_hit_count", 0))
			== cold_misses - 1,
		"unchanged neighboring scopes still reuse cached builds after global revision advance"
	)
	var mutated_scope: Dictionary = runtime.projection.get_scope_snapshot(
		Vector2i.ZERO
	)
	_check(
		_first_frame_hash(mutated_scope) != cold_frame_hash,
		"source transform mutation produces a new canonical frame"
	)
	_check(
		int(mutated_scope.get("source_world_revision", -1))
			== fake.world_revision,
		"cached and rebuilt scopes rebase to current authoritative world revision"
	)

	evidence = {
		"cold_misses": cold_misses,
		"cold_projection_dispatches": cold_dispatches,
		"warm_cache_hits": warm_hits,
		"warm_projection_dispatches": int(warm_perf.get(
			"prefetch_projection_worker_dispatch_count", -1
		)),
		"warm_reused_effects": int(warm_perf.get(
			"projection_build_cache_reused_effect_count", 0
		)),
		"mutation_cache_hits": int(mutated_perf.get(
			"projection_build_cache_hit_count", 0
		)),
		"mutation_cache_misses": int(mutated_perf.get(
			"projection_build_cache_miss_count", 0
		)),
		"cache_entries": int(mutated_perf.get(
			"projection_build_cache_entry_count", 0
		)),
		"cache_capacity": int(mutated_perf.get(
			"projection_build_cache_capacity", 0
		)),
	}
	runtime.release_all_scopes()
	_finish()


func _drain(runtime: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		var step: Dictionary = runtime.process_prefetch_step(1)
		if not step.get("ok", false):
			push_error("D4_PREFETCH_FAIL: %s" % step.get("reason", "unknown"))
			return false
		if runtime.get_prefetch_pending_count() == 0:
			return true
		await process_frame
		OS.delay_msec(1)
	return false


func _first_interacting(instances_value: Variant) -> Dictionary:
	if typeof(instances_value) != TYPE_ARRAY:
		return {}
	for value in instances_value:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var instance: Dictionary = value
		if not (instance.get("terrain_interaction", {}) as Dictionary).is_empty():
			return instance.duplicate(true)
	return {}


func _first_frame_hash(scope: Dictionary) -> String:
	var frames: Dictionary = scope.get("local_frames", {})
	if frames.is_empty():
		return ""
	var ids: Array[String] = []
	for effect_id_value in frames:
		ids.append(String(effect_id_value))
	ids.sort()
	return String((frames[ids[0]] as Dictionary).get("frame_sha256", ""))


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
	print("ISSUE108_D4_EFFECT_CACHE_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D4_EFFECT_CACHE_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
