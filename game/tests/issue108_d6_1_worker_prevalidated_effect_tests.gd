extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")
const ProjectionBuildJob := preload("res://scripts/terrain/terrain_object_effect_projection_build_job.gd")
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-d6-1-worker-prevalidated"
const WORLD_SEED := 424242
const ROOT := "user://issue108-d6-1-tests"

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


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
	var source: Dictionary = fake.get_authoritative_region_projection_source(
		Vector2i.ZERO
	)

	var build_job := ProjectionBuildJob.new(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		Vector2i.ZERO,
		source
	)
	build_job.run()
	var prebuilt: Dictionary = build_job.result
	_check(prebuilt.get("ok", false), "projection build job succeeds")
	_check(
		bool(prebuilt.get("worker_prevalidated", false)),
		"projection build job marks canonical worker prevalidation"
	)
	var worker_timings: Dictionary = prebuilt.get("timings_usec", {})
	_check(
		int(worker_timings.get("validate_snapshot", -1)) >= 0,
		"worker exposes snapshot validation timing"
	)
	var worker_checked := Contract.validate_snapshot(
		prebuilt.get("prevalidated_snapshot"),
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		Vector2i.ZERO
	)
	_check(
		worker_checked.get("ok", false),
		"worker prevalidated snapshot remains canonically valid"
	)

	var runtime := Runtime.new()
	var initialized: Dictionary = runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		fake,
		ROOT + "/transient"
	)
	_check(initialized.get("ok", false), "transient runtime initializes")
	if not initialized.get("ok", false):
		_finish()
		return

	var transient: Dictionary = runtime.projection.reconcile_prebuilt_scope(
		Vector2i.ZERO,
		prebuilt,
		true,
		false,
		false,
		true
	)
	_check(transient.get("ok", false), "worker-prevalidated transient publish succeeds")
	var transient_metrics: Dictionary = runtime.projection.last_reconcile_metrics
	_check(
		bool(transient.get("worker_prevalidated", false))
			and bool(transient.get("main_validation_skipped", false)),
		"transient publish reports the worker-prevalidated fast path"
	)
	_check(
		int(transient_metrics.get("validate_usec", -1)) == 0,
		"transient publish performs zero main-thread snapshot validation"
	)
	_check(
		int(transient_metrics.get("index_usec", -1)) >= 0
			and int(transient_metrics.get("publish_routes_usec", -1)) >= 0,
		"main thread retains index and route publication responsibilities"
	)
	var installed_snapshot := runtime.projection.get_scope_snapshot(Vector2i.ZERO)
	var installed_checked := Contract.validate_snapshot(
		installed_snapshot,
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		Vector2i.ZERO
	)
	_check(
		installed_checked.get("ok", false),
		"fast-path installed snapshot remains canonically valid"
	)

	var malformed := prebuilt.duplicate(true)
	var malformed_snapshot: Dictionary = (
		malformed["prevalidated_snapshot"] as Dictionary
	).duplicate(true)
	malformed_snapshot["world_id"] = "wrong-world"
	malformed["prevalidated_snapshot"] = malformed_snapshot

	var malformed_runtime := Runtime.new()
	var malformed_initialized: Dictionary = malformed_runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		fake,
		ROOT + "/malformed"
	)
	_check(malformed_initialized.get("ok", false), "malformed-check runtime initializes")
	var rejected: Dictionary = malformed_runtime.projection.reconcile_prebuilt_scope(
		Vector2i.ZERO,
		malformed,
		true,
		false,
		false,
		true
	)
	_check(
		not rejected.get("ok", true)
			and String(rejected.get("reason", ""))
				== "effect_projection_worker_prevalidation_envelope_mismatch",
		"main thread rejects a tampered worker-prevalidation envelope"
	)

	var durable_runtime := Runtime.new()
	var durable_initialized: Dictionary = durable_runtime.initialize(
		WORLD_ID,
		WORLD_SEED,
		Field.GENERATOR_VERSION,
		fake,
		ROOT + "/durable"
	)
	_check(durable_initialized.get("ok", false), "durable runtime initializes")
	var durable: Dictionary = durable_runtime.projection.reconcile_prebuilt_scope(
		Vector2i.ZERO,
		prebuilt,
		true,
		true,
		true,
		true
	)
	_check(
		durable.get("ok", false) and durable.get("persisted", false),
		"durable publication still succeeds"
	)
	var durable_metrics: Dictionary = durable_runtime.projection.last_reconcile_metrics
	_check(
		not bool(durable_metrics.get("worker_prevalidated", false))
			and not bool(durable_metrics.get("main_validation_skipped", false)),
		"durable path does not trust the worker-prevalidated shortcut"
	)
	_check(
		int(durable_metrics.get("validate_usec", 0)) > 0,
		"durable path still performs canonical main-thread validation"
	)

	evidence = {
		"worker_validate_usec": int(worker_timings.get(
			"validate_snapshot", -1
		)),
		"transient_main_validate_usec": int(transient_metrics.get(
			"validate_usec", -1
		)),
		"transient_index_usec": int(transient_metrics.get(
			"index_usec", -1
		)),
		"transient_publish_routes_usec": int(transient_metrics.get(
			"publish_routes_usec", -1
		)),
		"transient_duration_usec": int(transient_metrics.get(
			"duration_usec", -1
		)),
		"durable_main_validate_usec": int(durable_metrics.get(
			"validate_usec", -1
		)),
		"tampered_envelope_rejected": not rejected.get("ok", true),
	}

	runtime.release_all_scopes()
	malformed_runtime.release_all_scopes()
	durable_runtime.release_all_scopes()
	_finish()


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
	print("ISSUE108_D6_1_WORKER_PREVALIDATED_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_D6_1_WORKER_PREVALIDATED_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	quit(0 if failures == 0 else 1)
