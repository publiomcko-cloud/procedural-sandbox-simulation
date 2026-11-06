extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")
const EffectIndex := preload("res://scripts/terrain/terrain_object_effect_index.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-pre-d"
const WORLD_SEED := 424242
const DEFINITION_ID := "firstparty.core_rocks:granite"
const FAR_POSITIVE := Vector2i(100000000, 100000000)
const FAR_NEGATIVE := Vector2i(-100000000, -100000000)

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register(
		["res://mods/first-party"]
	)
	_check(registered.get("ok", false), "first-party registry initializes")
	if not registered.get("ok", false):
		_finish()
		return

	var near_instance := _fixture(
		registry,
		Vector2i.ZERO,
		Vector3i(15850, 3800, 6000),
		"precision-stable-source"
	)
	var far_instance := near_instance.duplicate(true)
	far_instance["region_key"] = FAR_POSITIVE
	var far_negative_instance := near_instance.duplicate(true)
	far_negative_instance["region_key"] = FAR_NEGATIVE

	var near_result := Effect.build_from_instance(near_instance, 11)
	var far_result := Effect.build_from_instance(far_instance, 11)
	var far_negative_result := Effect.build_from_instance(
		far_negative_instance, 11
	)
	_check(
		near_result.get("ok", false)
			and far_result.get("ok", false)
			and far_negative_result.get("ok", false),
		"same local source builds at origin and extreme signed regions"
	)
	if not near_result.get("ok", false) 		or not far_result.get("ok", false) 		or not far_negative_result.get("ok", false):
		_finish()
		return

	var near: Dictionary = near_result["effect"]
	var far: Dictionary = far_result["effect"]
	var far_negative: Dictionary = far_negative_result["effect"]

	_check(
		int(near["schema_version"]) == 2
			and near["frame"] == "source_region_local_v1",
		"effect schema explicitly declares region-local precision frame"
	)
	for forbidden in [
		"anchor_world_mm",
		"world_planes",
		"bounds_min",
		"bounds_max",
		"interior_point_world",
	]:
		_check(
			not near.has(forbidden),
			"effect record omits global float field %s" % forbidden
		)

	_check(
		near["anchor_local_mm"] == far["anchor_local_mm"]
			and near["region_planes"] == far["region_planes"]
			and near["bounds_min_local"] == far["bounds_min_local"]
			and near["bounds_max_local"] == far["bounds_max_local"]
			and near["interior_point_local"] == far["interior_point_local"],
		"positive extreme region does not perturb normalized local geometry"
	)
	_check(
		near["region_planes"] == far_negative["region_planes"]
			and near["bounds_min_local"] == far_negative["bounds_min_local"]
			and near["bounds_max_local"] == far_negative["bounds_max_local"]
			and near["interior_point_local"] == far_negative["interior_point_local"],
		"negative extreme region does not perturb normalized local geometry"
	)
	_check(
		near["effect_id"] == far["effect_id"]
			and far["effect_id"] == far_negative["effect_id"],
		"stable effect identity is independent of region frame"
	)
	_check(
		near["source_fingerprint_sha256"] != far["source_fingerprint_sha256"]
			and far["source_fingerprint_sha256"]
				!= far_negative["source_fingerprint_sha256"],
		"source fingerprint includes signed source-region identity"
	)

	var interior := _vector3(near["interior_point_local"])
	var near_cutter := Effect.sample_cutter(
		near, Vector2i.ZERO, interior
	)
	var far_cutter := Effect.sample_cutter(
		far, FAR_POSITIVE, interior
	)
	var far_negative_cutter := Effect.sample_cutter(
		far_negative, FAR_NEGATIVE, interior
	)
	_check(
		is_equal_approx(near_cutter, far_cutter)
			and is_equal_approx(near_cutter, far_negative_cutter)
			and near_cutter < 0.0,
		"local cutter evaluation is invariant at extreme signed regions"
	)

	var terrain_density := 0.25
	var near_composed := Effect.compose_density(
		terrain_density, near, Vector2i.ZERO, interior
	)
	var far_composed := Effect.compose_density(
		terrain_density, far, FAR_POSITIVE, interior
	)
	_check(
		is_equal_approx(near_composed, far_composed),
		"terrain composition is region-translation invariant"
	)

	var near_index := EffectIndex.new()
	var far_index := EffectIndex.new()
	var far_negative_index := EffectIndex.new()
	_check(
		near_index.replace_effect(near).get("ok", false)
			and far_index.replace_effect(far).get("ok", false)
			and far_negative_index.replace_effect(far_negative).get("ok", false),
		"integer chunk index accepts extreme signed regions"
	)
	_check(
		far_index.get_effect_ids_for_chunk(
			FAR_POSITIVE, Vector2i(3, 2)
		).has(far["effect_id"]),
		"far positive source indexes owning edge chunk"
	)
	_check(
		far_index.get_effect_ids_for_chunk(
			FAR_POSITIVE + Vector2i(1, 0), Vector2i(0, 2)
		).has(far["effect_id"]),
		"far positive seam crosses to adjacent region without global floats"
	)
	_check(
		far_negative_index.get_effect_ids_for_chunk(
			FAR_NEGATIVE, Vector2i(3, 2)
		).has(far_negative["effect_id"]),
		"far negative source indexes owning edge chunk"
	)
	_check(
		far_negative_index.get_effect_ids_for_chunk(
			FAR_NEGATIVE + Vector2i(1, 0), Vector2i(0, 2)
		).has(far_negative["effect_id"]),
		"far negative seam maps adjacent signed region deterministically"
	)

	# The same physical point expressed through the neighboring region must map
	# into the source frame by a bounded delta of exactly one region.
	var neighbor_local := interior - Vector3(
		Effect.REGION_SIZE_X, 0.0, 0.0
	)
	var same_point_far := Effect.sample_cutter(
		far,
		FAR_POSITIVE + Vector2i(1, 0),
		neighbor_local
	)
	_check(
		is_equal_approx(same_point_far, far_cutter),
		"cross-region sample conversion preserves the same physical point"
	)

	var rejected_far_delta := Effect.sample_cutter_prevalidated(
		far,
		FAR_POSITIVE + Vector2i(
			Effect.MAX_SAMPLE_REGION_DELTA + 1, 0
		),
		interior
	)
	_check(
		is_inf(rejected_far_delta),
		"hot evaluator fails closed when region delta exceeds bounded frame"
	)

	# Optional legacy world_position_mm is compatibility-only and never required
	# for region-local generated sources.
	_check(
		not far_instance.has("world_position_mm"),
		"extreme-region source requires no global millimeter anchor"
	)

	evidence = {
		"schema_version": int(far["schema_version"]),
		"frame": String(far["frame"]),
		"far_positive_region": [FAR_POSITIVE.x, FAR_POSITIVE.y],
		"far_negative_region": [FAR_NEGATIVE.x, FAR_NEGATIVE.y],
		"near_cutter": near_cutter,
		"far_cutter": far_cutter,
		"far_negative_cutter": far_negative_cutter,
		"max_sample_region_delta": Effect.MAX_SAMPLE_REGION_DELTA,
		"far_indexed_chunk_count": far_index.get_indexed_chunk_ids(
			far["effect_id"]
		).size(),
	}
	_finish()


func _fixture(
	registry: RefCounted,
	region_key: Vector2i,
	position_mm: Vector3i,
	instance_id: String
) -> Dictionary:
	var pins: Dictionary = registry.pin_definitions([DEFINITION_ID])
	var recipe: Dictionary = registry.evaluate_rock_recipe(
		DEFINITION_ID, 31337
	)
	var interaction: Dictionary = registry.resolve_terrain_interaction(
		DEFINITION_ID
	)
	if not pins.get("ok", false) 		or pins.get("pins", []).is_empty() 		or not recipe.get("ok", false) 		or not interaction.get("ok", false):
		return {}
	return {
		"instance_id": instance_id,
		"definition_id": DEFINITION_ID,
		"content_pin": pins["pins"][0].duplicate(true),
		"world_id": WORLD_ID,
		"world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"region_key": region_key,
		"position_mm": position_mm,
		"default_scale_milli": Vector3i(1000, 1000, 1000),
		"default_yaw_mdeg": 0,
		"geometry": recipe["geometry"].duplicate(true),
		"geometry_seeds": recipe["geometry_seeds"].duplicate(true),
		"terrain_interaction": interaction["rule"].duplicate(true),
		"terrain_interaction_pin": interaction["pin"].duplicate(true),
		"terrain_interaction_applied": false,
		"instance_components": {},
	}


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("ISSUE108_PRE_D_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_PRE_D_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	quit(0 if failures == 0 else 1)
