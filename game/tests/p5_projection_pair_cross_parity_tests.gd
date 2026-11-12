extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const Shape := preload("res://scripts/objects/procedural_rock_shape_descriptor.gd")
const Job := preload("res://scripts/terrain/terrain_object_effect_projection_build_job.gd")
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "p5-projection-pair-cross-parity"
const SEED := 424242
var assertions := 0
var failures := 0
var legacy_usec := 0
var fast_usec := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register([
		"res://mods/first-party"
	])
	_check(bool(registered.get("ok", false)), "authoritative first-party mod registration")
	if not registered.get("ok", false):
		_finish()
		return
	for seed in [1, 17, 101, 31337, 424242, 700100, 700101, 700102,
			700103, 700104, 700105, 2147483646]:
		var recipe: Dictionary = registry.evaluate_rock_recipe(
			"firstparty.core_rocks:granite", seed
		)
		_check(bool(recipe.get("ok", false)), "mod-derived geometry recipe")
		if not recipe.get("ok", false):
			continue
		var started := Time.get_ticks_usec()
		var baseline: Dictionary = Shape.build(recipe["geometry"], recipe["geometry_seeds"])
		legacy_usec += Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		var optimized: Dictionary = Shape.build(recipe["geometry"], recipe["geometry_seeds"], true)
		fast_usec += Time.get_ticks_usec() - started
		_check(bool(baseline.get("ok", false)), "baseline descriptor builds")
		_check(bool(optimized.get("ok", false)), "E5 descriptor builds")
		if not baseline.get("ok", false) or not optimized.get("ok", false):
			continue
		_check(baseline == optimized, "E5 descriptor EXACT bytes/values/parity including guarded vertices")
		_check(
			baseline["guarded_vertices"] == optimized["guarded_vertices"],
			"ordered intersection vertices identical"
		)
		_check(
			baseline["descriptor_sha256"] == optimized["descriptor_sha256"],
			"source geometry fingerprint unchanged"
		)
	for region in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-5, 7)]:
		var generated: Dictionary = ObjectWorld.build_region_instances(
			SEED, WORLD_ID, region, registry
		)
		_check(bool(generated.get("ok", false)), "mod-first procedural region generated")
		if not generated.get("ok", false):
			continue
		var interacting: Dictionary = {}
		for instance_value in generated.get("instances", []):
			if not (instance_value as Dictionary).get("terrain_interaction", {}).is_empty():
				interacting = instance_value
				break
		_check(not interacting.is_empty(), "terrain interaction source selected")
		if interacting.is_empty():
			continue
		var revision := 0
		var source := {
			"world_revision": revision,
			"instances": [interacting.duplicate(true)],
			"source_revisions": {String(interacting["instance_id"]): revision}
		}
		var standard := Job.new(WORLD_ID, SEED, Field.GENERATOR_VERSION, region, source)
		standard.run()
		var accelerated := Job.new(WORLD_ID, SEED, Field.GENERATOR_VERSION, region, source, true)
		accelerated.run()
		_check(bool(standard.result.get("ok", false)), "original worker projection builds")
		_check(bool(accelerated.result.get("ok", false)), "accelerated worker projection builds")
		if not standard.result.get("ok", false) or not accelerated.result.get("ok", false):
			continue
		var original_snapshot: Dictionary = standard.result["prevalidated_snapshot"]
		var fast_snapshot: Dictionary = accelerated.result["prevalidated_snapshot"]
		_check(original_snapshot == fast_snapshot, "full authoritative projection snapshots EXACT identical")
		_check(
			String(standard.result["source_digest_sha256"])
				== String(accelerated.result["source_digest_sha256"]),
			"canonical effect source digest identical"
		)
		var verified := Contract.validate_snapshot(
			fast_snapshot, WORLD_ID, SEED, Field.GENERATOR_VERSION, region
		)
		_check(bool(verified.get("ok", false)), "opt-in worker stays canonically valid")
	_finish()


func _finish() -> void:
	if failures == 0:
		print("P5_PROJECTION_PAIR_PARITY_PASS: assertions=%d failures=%d descriptor_baseline_ms=%.3f descriptor_fast_ms=%.3f" % [
			assertions, failures, float(legacy_usec) / 1000.0, float(fast_usec) / 1000.0,
		])
		quit(0)
	else:
		push_error("P5_PROJECTION_PAIR_PARITY_FAIL: assertions=%d failures=%d" % [
			assertions, failures
		])
		quit(1)
