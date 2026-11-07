extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-d6-cold-effect-transient-publish"
const WORLD_SEED := 424242
const ROOT := "user://issue108-d6-tests"
const TIMEOUT_MSEC := 30000

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

	# Seed an actual persisted derived projection so the second runtime proves
	# that D.6 bypasses disk on a genuine cold process-local miss.
	var seed_runtime := Runtime.new()
	var seed_initialized: Dictionary = seed_runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		fake,
		ROOT + "/projection"
	)
	_check(seed_initialized.get("ok", false), "seed runtime initializes")
	var persisted: Dictionary = seed_runtime.call(
		"_reconcile_source_region", Vector2i.ZERO, true
	)
	_check(persisted.get("ok", false), "seed runtime persists center projection")
	var persisted_scope: Dictionary = seed_runtime.projection.get_scope_snapshot(
		Vector2i.ZERO
	)
	var persisted_frame_hash := _first_frame_hash(persisted_scope)
	_check(
		not persisted_frame_hash.is_empty(),
		"persisted center projection has a canonical frame"
	)
	seed_runtime.release_all_scopes()
	var confirmed_disk: Dictionary = seed_runtime.projection.load_scope(
		Vector2i.ZERO
	)
	_check(
		confirmed_disk.get("ok", false)
			and confirmed_disk.get("found", false)
			and int(confirmed_disk.get("generation", 0)) >= 1,
		"persisted projection generation is present on disk"
	)
	seed_runtime.release_all_scopes()

	# A new runtime has no resident or dormant memory. Incremental prefetch must
	# publish from the current authoritative prebuilt result without loading the
	# persisted derived projection.
	var runtime := Runtime.new()
	var initialized: Dictionary = runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		fake,
		ROOT + "/projection"
	)
	_check(initialized.get("ok", false), "D6 runtime initializes")
	if not initialized.get("ok", false):
		_finish()
		return
	runtime.set_incremental_prefetch_enabled(true)
	runtime.reset_performance_metrics()

	var window: Dictionary = runtime.update_resident_target_regions([
		Vector2i.ZERO
	])
	_check(window.get("ok", false), "cold source window queues")
	var drained := await _drain(runtime)
	_check(drained, "cold source window drains")

	var perf: Dictionary = runtime.get_performance_snapshot()
	var projection_perf: Dictionary = perf.get("projection", {})
	var protected_scope_count := int(perf.get("protected_scope_count", 0))
	var storage_loads := int(projection_perf.get("scope_load_count", -1))
	var bypasses := int(projection_perf.get(
		"transient_storage_load_bypass_count", -1
	))
	var direct_installs := int(projection_perf.get(
		"transient_direct_install_count", -1
	))
	_check(
		protected_scope_count == 25,
		"single target region protects the expected 25 source scopes"
	)
	_check(
		storage_loads == 0,
		"cold incremental prefetch performs zero projection-store scope loads"
	)
	_check(
		bypasses == protected_scope_count,
		"every process-local cold scope bypasses persisted derived-state loading"
	)
	_check(
		direct_installs == protected_scope_count,
		"every bypassed cold scope installs its validated prebuilt projection directly"
	)

	var cold_scope: Dictionary = runtime.projection.get_scope_snapshot(
		Vector2i.ZERO
	)
	var cold_frame_hash := _first_frame_hash(cold_scope)
	_check(
		cold_frame_hash == persisted_frame_hash,
		"direct transient install preserves canonical frame identity"
	)

	# Prove that bypassing the old derived cache does not disable later durable
	# publication after an authoritative mutation.
	fake.transform_translation(Vector3i(350, 0, 0))
	var durable_after_mutation: Dictionary = runtime.call(
		"_reconcile_source_region", Vector2i.ZERO, true
	)
	_check(
		durable_after_mutation.get("ok", false)
			and durable_after_mutation.get("persisted", false),
		"authoritative mutation still persists through the normal durable path"
	)
	var mutated_frame_hash := _first_frame_hash(
		runtime.projection.get_scope_snapshot(Vector2i.ZERO)
	)
	_check(
		not mutated_frame_hash.is_empty()
			and mutated_frame_hash != cold_frame_hash,
		"authoritative mutation produces a new canonical frame"
	)

	runtime.release_all_scopes()
	var reloaded: Dictionary = runtime.projection.load_scope(Vector2i.ZERO)
	_check(
		reloaded.get("ok", false)
			and reloaded.get("found", false)
			and int(reloaded.get("generation", 0))
				> int(confirmed_disk.get("generation", 0)),
		"later durable mutation advances the persisted projection generation"
	)

	evidence = {
		"protected_scope_count": protected_scope_count,
		"storage_loads_on_cold_prefetch": storage_loads,
		"transient_storage_load_bypasses": bypasses,
		"transient_direct_installs": direct_installs,
		"prefetch_publish_peak_usec": int(perf.get(
			"prefetch_projection_publish_peak_usec", -1
		)),
		"persisted_generation_before": int(confirmed_disk.get(
			"generation", -1
		)),
		"persisted_generation_after": int(reloaded.get("generation", -1)),
		"frame_identity_preserved": cold_frame_hash == persisted_frame_hash,
	}

	runtime.release_all_scopes()
	_finish()


func _drain(runtime: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		var step: Dictionary = runtime.process_prefetch_step(1)
		if not step.get("ok", false):
			push_error(
				"D6_PREFETCH_FAIL: %s" % step.get("reason", "unknown")
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
	print("ISSUE108_D6_COLD_EFFECT_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D6_COLD_EFFECT_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
