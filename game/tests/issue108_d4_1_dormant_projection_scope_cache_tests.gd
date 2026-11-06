extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-d4-1-dormant-scope-cache"
const WORLD_SEED := 424242
const ROOT := "user://issue108-d4-1-tests"
const TIMEOUT_MSEC := 20000
const FAR_REGION := Vector2i(20, 0)

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
	var world_revision := 0
	var entity_revision := 0

	func get_command_world_revision() -> int:
		return world_revision

	func get_authoritative_region_projection_source(region_key: Vector2i) -> Dictionary:
		var instances: Array[Dictionary] = []
		var revisions: Dictionary = {}
		if region_key == source_region and not instance.is_empty():
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
	_check(initialized.get("ok", false), "D4.1 runtime initializes")
	if not initialized.get("ok", false):
		_finish()
		return
	runtime.set_incremental_prefetch_enabled(true)

	var cold_window: Dictionary = runtime.update_resident_target_regions([
		Vector2i.ZERO
	])
	_check(cold_window.get("ok", false), "cold center window queues")
	var cold_drained: bool = await _drain(runtime)
	_check(cold_drained, "cold center window drains")
	var cold_scope: Dictionary = runtime.projection.get_scope_snapshot(
		Vector2i.ZERO
	)
	var cold_frame_hash := _first_frame_hash(cold_scope)
	_check(
		not cold_frame_hash.is_empty(),
		"cold center scope publishes an effect frame"
	)
	var cold_perf: Dictionary = runtime.get_performance_snapshot()
	var expected_scope_count := int(cold_perf.get(
		"protected_scope_count", 0
	))
	_check(
		expected_scope_count == 25,
		"single target region protects the expected 25 source scopes"
	)

	var far_window: Dictionary = runtime.update_resident_target_regions([
		FAR_REGION
	])
	_check(far_window.get("ok", false), "far window queues and evicts center scopes")
	var far_drained: bool = await _drain(runtime)
	_check(far_drained, "far window drains")
	var after_far: Dictionary = runtime.get_performance_snapshot()
	var projection_after_far: Dictionary = after_far.get("projection", {})
	_check(
		int(projection_after_far.get("dormant_scope_count", 0))
			>= expected_scope_count,
		"center scopes remain as non-routed dormant derived entries after eviction"
	)
	_check(
		int(projection_after_far.get("dormant_scope_store_count", 0))
			>= expected_scope_count,
		"window eviction stores validated snapshots and indexes in dormant cache"
	)
	_check(
		not runtime.projection.has_scope(Vector2i.ZERO),
		"dormant center scope is not active or routable while far away"
	)

	runtime.reset_performance_metrics()
	var revisit_window: Dictionary = runtime.update_resident_target_regions([
		Vector2i.ZERO
	])
	_check(revisit_window.get("ok", false), "center revisit window queues")
	var revisit_drained: bool = await _drain(runtime)
	_check(revisit_drained, "center revisit drains")
	var revisit_perf: Dictionary = runtime.get_performance_snapshot()
	var projection_revisit: Dictionary = revisit_perf.get("projection", {})
	var dormant_hits := int(projection_revisit.get(
		"dormant_scope_hit_count", 0
	))
	var dormant_misses := int(projection_revisit.get(
		"dormant_scope_miss_count", 0
	))
	var storage_loads := int(projection_revisit.get(
		"scope_load_count", 0
	))
	_check(
		dormant_hits == expected_scope_count,
		"every revisited source scope reactivates from dormant memory"
	)
	_check(
		dormant_misses == 0 and storage_loads == 0,
		"revisit performs no projection-store load or index rebuild path"
	)
	_check(
		int(revisit_perf.get("projection_build_cache_hit_count", 0))
			== expected_scope_count
			and int(revisit_perf.get(
				"prefetch_projection_worker_dispatch_count", 0
			)) == 0,
		"D4 projection-build cache composes with D4.1 dormant scope reactivation"
	)
	var revisit_scope: Dictionary = runtime.projection.get_scope_snapshot(
		Vector2i.ZERO
	)
	_check(
		_first_frame_hash(revisit_scope) == cold_frame_hash,
		"dormant reactivation preserves canonical local-frame identity"
	)
	_check(
		int(projection_revisit.get("dormant_scope_activate_peak_usec", -1)) >= 0,
		"dormant activation timing is exposed for owner-hardware qualification"
	)

	evidence = {
		"expected_scope_count": expected_scope_count,
		"dormant_hits": dormant_hits,
		"dormant_misses": dormant_misses,
		"storage_loads_on_revisit": storage_loads,
		"projection_build_cache_hits": int(revisit_perf.get(
			"projection_build_cache_hit_count", 0
		)),
		"projection_worker_dispatches": int(revisit_perf.get(
			"prefetch_projection_worker_dispatch_count", 0
		)),
		"dormant_activate_peak_usec": int(projection_revisit.get(
			"dormant_scope_activate_peak_usec", -1
		)),
		"dormant_scope_count_after_revisit": int(projection_revisit.get(
			"dormant_scope_count", 0
		)),
		"dormant_cache_capacity": int(projection_revisit.get(
			"max_dormant_scope_count", 0
		)),
	}
	runtime.release_all_scopes()
	var after_release_all: Dictionary = runtime.get_performance_snapshot()
	var projection_after_release_all: Dictionary = after_release_all.get(
		"projection", {}
	)
	_check(
		int(projection_after_release_all.get("resident_scope_count", -1)) == 0
			and int(projection_after_release_all.get(
				"dormant_scope_count", -1
			)) == 0,
		"release_all_scopes purges active and dormant projection state"
	)
	_finish()


func _drain(runtime: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		var step: Dictionary = runtime.process_prefetch_step(1)
		if not step.get("ok", false):
			push_error(
				"D4_1_PREFETCH_FAIL: %s" % step.get("reason", "unknown")
			)
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
	return String(
		(frames[ids[0]] as Dictionary).get("frame_sha256", "")
	)


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
	print("ISSUE108_D4_1_DORMANT_SCOPE_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D4_1_DORMANT_SCOPE_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
