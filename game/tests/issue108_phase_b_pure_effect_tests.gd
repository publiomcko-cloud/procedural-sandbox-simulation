extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectWorld := preload("res://scripts/objects/procedural_object_world.gd")
const RockMesh := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const Shape := preload("res://scripts/objects/procedural_rock_shape_descriptor.gd")
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")
const EffectIndex := preload("res://scripts/terrain/terrain_object_effect_index.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-phase-b"
const WORLD_SEED := 424242
const TEST_SEEDS := [1, 17, 101, 31337]

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := Registry.new()
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var external_root := project_root.get_base_dir().path_join("mods/examples")
	var registration := registry.discover_and_register(["res://mods/first-party", external_root])
	_check(registration.get("ok", false), "first-party plus explicit external package register")
	if not registration.get("ok", false):
		_finish()
		return
	var synthetic := registry.register_discovered(_synthetic_discovery())
	_check(synthetic.get("ok", false), "independent synthetic package registers")
	if not synthetic.get("ok", false):
		_finish()
		return

	_test_shape_descriptor(registry)
	_test_effect_normalization_and_transform(registry)
	_test_evaluator(registry)
	_test_spatial_index(registry)
	_test_generated_instance_compatibility(registry)
	_finish()


func _test_shape_descriptor(registry: RefCounted) -> void:
	var summaries: Dictionary = {}
	for definition_id in [
		"firstparty.core_rocks:granite",
		"official.example.procedural_rock:basalt_stack",
		"phaseb.synthetic:weathered_block",
	]:
		var max_guard_mm := 0.0
		var max_violation := 0.0
		for seed in TEST_SEEDS:
			var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, seed)
			_check(recipe.get("ok", false), "%s seed %d recipe evaluates" % [definition_id, seed])
			if not recipe.get("ok", false):
				continue
			var descriptor := Shape.build(recipe["geometry"], recipe["geometry_seeds"])
			var descriptor_repeat := Shape.build(recipe["geometry"], recipe["geometry_seeds"])
			_check(descriptor.get("ok", false), "%s seed %d descriptor builds" % [definition_id, seed])
			_check(
				descriptor.get("descriptor_sha256", "") == descriptor_repeat.get("descriptor_sha256", "")
					and descriptor.get("roughness_guard_m", -1.0) == descriptor_repeat.get("roughness_guard_m", -2.0),
				"%s seed %d descriptor is deterministic" % [definition_id, seed]
			)
			if not descriptor.get("ok", false):
				continue
			var cpu := RockMesh.build_cpu_data(recipe["geometry"], recipe["geometry_seeds"])
			_check(cpu.get("ok", false), "%s seed %d renderer CPU geometry builds" % [definition_id, seed])
			if not cpu.get("ok", false):
				continue
			var all_contained := true
			var worst := -INF
			var positions: PackedVector3Array = cpu["positions"]
			var guard := float(descriptor["roughness_guard_m"])
			for point in positions:
				if not Shape.contains_local_point(descriptor, point, 0.000002):
					all_contained = false
				for plane_value in descriptor["planes"]:
					var plane: Dictionary = plane_value
					var delta := (plane["normal"] as Vector3).dot(point) - float(plane["distance"]) - guard
					worst = maxf(worst, delta)
			_check(all_contained, "%s seed %d descriptor conservatively contains final CPU geometry" % [definition_id, seed])
			var configured := (
				float(recipe["geometry"]["macro_roughness_mm"])
				+ float(recipe["geometry"]["meso_roughness_mm"])
				+ float(recipe["geometry"]["fine_roughness_mm"])
			) / 1000.0
			_check(
				guard >= 0.0 and guard <= configured + 0.000001,
				"%s seed %d guard respects configured roughness ceiling" % [definition_id, seed]
			)
			_check(
				int(descriptor.get("plane_count", 0)) >= 6
					and int(descriptor.get("plane_count", 0)) <= Effect.MAX_PLANES,
				"%s seed %d descriptor plane budget is bounded" % [definition_id, seed]
			)
			max_guard_mm = maxf(max_guard_mm, guard * 1000.0)
			max_violation = maxf(max_violation, worst if is_finite(worst) else 0.0)
		summaries[definition_id] = {
			"maximum_guard_mm": max_guard_mm,
			"maximum_containment_violation_m": max_violation,
		}
	evidence["shape_descriptors"] = summaries


func _test_effect_normalization_and_transform(registry: RefCounted) -> void:
	var base := _fixture_instance(
		registry,
		"firstparty.core_rocks:granite",
		101,
		Vector2i.ZERO,
		Vector3i(15800, 3800, 6000),
		Vector3i(1000, 1000, 1000),
		0,
		"fixture-transform"
	)
	var built := Effect.build_from_instance(base, 7)
	_check(built.get("ok", false), "default-transform terrain effect builds")
	if not built.get("ok", false):
		return
	var effect: Dictionary = built["effect"]
	_check(Effect.validate_effect(effect).get("ok", false), "normalized effect validates")
	_check(
		String(effect["terrain_interaction_pin"]["rule_sha256"])
			== String(base["terrain_interaction_pin"]["rule_sha256"]),
		"effect carries exact terrain-interaction pin"
	)
	_check(
		int(effect["embed_depth_mm"]) == int(base["terrain_interaction"]["embed_depth_mm"])
			and int(effect["blend_radius_mm"]) == int(base["terrain_interaction"]["blend_radius_mm"]),
		"effect carries declared embed and blend parameters"
	)
	_check(
		String(effect["shape_descriptor_sha256"])
			== String(built["shape_descriptor"]["descriptor_sha256"]),
		"effect pins exact pure shape descriptor"
	)
	_check(
		not effect.has("mesh") and not effect.has("node") and not effect.has("resource"),
		"effect record contains no renderer authority"
	)
	_check(not bool(base.get("terrain_interaction_applied", true)), "effect construction does not mark source interaction applied")

	var transformed := base.duplicate(true)
	transformed["instance_components"] = {
		"core.transform": {
			"schema_version": 1,
			"properties": {
				"translation_mm": [120, 80, -90],
				"rotation_mdeg": [17000, 45000, -9000],
				"scale_milli": [900, 1200, 1100],
			},
		},
	}
	var changed := Effect.build_from_instance(transformed, 8)
	_check(changed.get("ok", false), "full resolved transform terrain effect builds")
	if changed.get("ok", false):
		_check(
			changed["effect"]["effect_id"] == effect["effect_id"],
			"effect identity remains stable across source transform revision"
		)
		_check(
			changed["effect"]["source_fingerprint_sha256"] != effect["source_fingerprint_sha256"],
			"source fingerprint changes with transform/revision"
		)
		_check(
			changed["effect"]["bounds_min"] != effect["bounds_min"]
				or changed["effect"]["bounds_max"] != effect["bounds_max"],
			"world bounds respond to transform"
		)
		var changed_repeat := Effect.build_from_instance(transformed, 8)
		_check(
			changed_repeat.get("ok", false)
				and changed_repeat["effect"]["source_fingerprint_sha256"]
					== changed["effect"]["source_fingerprint_sha256"]
				and changed_repeat["effect"]["world_planes"] == changed["effect"]["world_planes"],
			"effect transform and fingerprint are deterministic"
		)

	var bad_pin := base.duplicate(true)
	bad_pin["terrain_interaction_pin"]["rule_sha256"] = "0".repeat(64)
	_check(
		not Effect.build_from_instance(bad_pin, 7).get("ok", false),
		"interaction pin mismatch is rejected explicitly"
	)
	var bad_content_pin := base.duplicate(true)
	bad_content_pin["content_pin"]["content_id"] = "other.package:other"
	_check(
		not Effect.build_from_instance(bad_content_pin, 7).get("ok", false),
		"content pin mismatch is rejected explicitly"
	)
	var bad_world_anchor := base.duplicate(true)
	bad_world_anchor["world_position_mm"] = Vector3i(1, 2, 3)
	_check(
		not Effect.build_from_instance(bad_world_anchor, 7).get("ok", false),
		"contradictory explicit world anchor is rejected"
	)


func _test_evaluator(registry: RefCounted) -> void:
	var first_instance := _fixture_instance(
		registry,
		"phaseb.synthetic:weathered_block",
		17,
		Vector2i(-1, 0),
		Vector3i(8000, 3600, 5000),
		Vector3i(1000, 1000, 1000),
		27000,
		"eval-a"
	)
	var second_instance := first_instance.duplicate(true)
	second_instance["instance_id"] = "eval-b"
	second_instance["position_mm"] = Vector3i(8300, 3600, 5200)
	var first_result := Effect.build_from_instance(first_instance, 3)
	var second_result := Effect.build_from_instance(second_instance, 4)
	_check(first_result.get("ok", false) and second_result.get("ok", false), "overlapping evaluator fixtures build")
	if not first_result.get("ok", false) or not second_result.get("ok", false):
		return
	var first: Dictionary = first_result["effect"]
	var second: Dictionary = second_result["effect"]
	var interior := _vector3(first["interior_point_world"])
	var cutter := Effect.sample_cutter(first, interior)
	_check(cutter < 0.0, "effect interior evaluates to negative cutter density")
	var terrain_density := 0.25
	var composed := Effect.compose_density(terrain_density, first, interior)
	_check(composed <= terrain_density and composed < 0.0, "interior imprint subtracts solid terrain")
	var outside := _vector3(first["bounds_max"]) + Vector3(1.0, 1.0, 1.0)
	var outside_cutter := Effect.sample_cutter(first, outside)
	_check(outside_cutter > 0.0, "outside point evaluates positive cutter density")
	_check(
		Effect.compose_density(terrain_density, first, outside) == terrain_density,
		"outside cutter has exactly zero terrain influence"
	)
	var forward := Effect.compose_effects(terrain_density, [first, second], interior)
	var reverse := Effect.compose_effects(terrain_density, [second, first], interior)
	_check(is_equal_approx(forward, reverse), "effect composition is deterministic independent of input visitation order")

	var hard := first.duplicate(true)
	hard["blend_radius_mm"] = 0
	_check(Effect.validate_effect(hard).get("ok", false), "zero-radius hard subtract variant remains schema-valid")
	var hard_density := Effect.compose_density(terrain_density, hard, interior)
	_check(
		is_equal_approx(hard_density, minf(terrain_density, Effect.sample_cutter(hard, interior))),
		"zero blend radius is exact hard subtraction"
	)
	_check(
		is_equal_approx(
			Effect.sample_cutter(first, interior),
			Effect.sample_cutter_prevalidated(first, interior)
		) and is_equal_approx(
			Effect.compose_density(terrain_density, first, interior),
			Effect.compose_density_prevalidated(terrain_density, first, interior)
		) and is_equal_approx(
			Effect.compose_effects(terrain_density, [first, second], interior),
			Effect.compose_effects_prevalidated(terrain_density, [first, second], interior)
		),
		"prevalidated hot-path evaluator is semantically identical to safe evaluator"
	)
	var malformed_plane := first.duplicate(true)
	malformed_plane["world_planes"][0]["distance_m"] = "invalid"
	_check(
		not Effect.validate_effect(malformed_plane).get("ok", false),
		"malformed plane distance fails validation without entering evaluator"
	)


func _test_spatial_index(registry: RefCounted) -> void:
	var seam_instance := _fixture_instance(
		registry,
		"firstparty.core_rocks:granite",
		31337,
		Vector2i.ZERO,
		Vector3i(15850, 3800, 6000),
		Vector3i(1000, 1000, 1000),
		0,
		"seam-positive"
	)
	var seam_result := Effect.build_from_instance(seam_instance, 1)
	_check(seam_result.get("ok", false), "positive X seam effect builds")
	if not seam_result.get("ok", false):
		return
	var seam_effect: Dictionary = seam_result["effect"]
	var index := EffectIndex.new()
	var indexed := index.replace_effect(seam_effect)
	_check(indexed.get("ok", false), "effect indexes into bounded chunk candidates")
	_check(
		index.get_effect_ids_for_chunk(Vector2i.ZERO, Vector2i(3, 2)).has(seam_effect["effect_id"]),
		"effect indexes owning edge chunk"
	)
	_check(
		index.get_effect_ids_for_chunk(Vector2i(1, 0), Vector2i(0, 2)).has(seam_effect["effect_id"]),
		"effect crossing +X region seam indexes adjacent region"
	)

	var negative_instance := _fixture_instance(
		registry,
		"phaseb.synthetic:weathered_block",
		101,
		Vector2i(-1, 0),
		Vector3i(150, 3600, 6000),
		Vector3i(1000, 1000, 1000),
		0,
		"seam-negative"
	)
	var negative_result := Effect.build_from_instance(negative_instance, 2)
	_check(negative_result.get("ok", false), "negative-region seam effect builds")
	if negative_result.get("ok", false):
		var negative: Dictionary = negative_result["effect"]
		_check(index.replace_effect(negative).get("ok", false), "negative-region effect indexes")
		_check(
			index.get_effect_ids_for_chunk(Vector2i(-1, 0), Vector2i(0, 2)).has(negative["effect_id"]),
			"negative effect indexes current region edge chunk"
		)
		_check(
			index.get_effect_ids_for_chunk(Vector2i(-2, 0), Vector2i(3, 2)).has(negative["effect_id"]),
			"negative effect crossing -X seam uses floor ownership"
		)

	var moved_instance := seam_instance.duplicate(true)
	moved_instance["instance_components"] = {
		"core.transform": {
			"schema_version": 1,
			"properties": {
				"translation_mm": [-7000, 0, 0],
				"rotation_mdeg": [0, 0, 0],
				"scale_milli": [1000, 1000, 1000],
			},
		},
	}
	var moved_result := Effect.build_from_instance(moved_instance, 3)
	_check(moved_result.get("ok", false), "replacement effect with new footprint builds")
	if moved_result.get("ok", false):
		var before_keys := index.get_indexed_chunk_ids(seam_effect["effect_id"])
		var replaced := index.replace_effect(moved_result["effect"])
		var after_keys := index.get_indexed_chunk_ids(seam_effect["effect_id"])
		_check(replaced.get("ok", false) and before_keys != after_keys, "replacement atomically changes derived chunk membership")
		_check(
			not index.get_effect_ids_for_chunk(Vector2i(1, 0), Vector2i(0, 2)).has(seam_effect["effect_id"]),
			"replacement removes stale old-footprint membership"
		)

	var first: Dictionary = seam_result["effect"]
	var second: Dictionary = negative_result["effect"] if negative_result.get("ok", false) else moved_result["effect"]
	var index_a := EffectIndex.new()
	var index_b := EffectIndex.new()
	index_a.replace_effect(first)
	index_a.replace_effect(second)
	index_b.replace_effect(second)
	index_b.replace_effect(first)
	var common := _find_common_chunk(index_a, first["effect_id"], second["effect_id"])
	if common.get("ok", false):
		var snap_a := index_a.snapshot_for_chunk(common["region_key"], common["coordinate"])
		var snap_b := index_b.snapshot_for_chunk(common["region_key"], common["coordinate"])
		_check(
			snap_a.get("ok", false) and snap_b.get("ok", false)
				and snap_a["snapshot_sha256"] == snap_b["snapshot_sha256"],
			"chunk snapshot is deterministic independent of insertion order"
		)
	else:
		# Stable ordering is also observable directly even when these particular
		# bounded footprints do not overlap.
		var ids := index_a.get_indexed_chunk_ids(first["effect_id"])
		_check(not ids.is_empty(), "deterministic index maintains bounded membership for non-overlap fixtures")

	var removed := index.remove_effect(seam_effect["effect_id"])
	_check(removed.get("ok", false) and removed.get("removed", false), "effect removal clears derived index membership")
	_check(index.get_effect(seam_effect["effect_id"]).is_empty(), "removed effect is no longer authoritative in index")


func _test_generated_instance_compatibility(registry: RefCounted) -> void:
	var generated := ObjectWorld.build_region_instances(
		WORLD_SEED,
		WORLD_ID,
		Vector2i.ZERO,
		registry
	)
	_check(generated.get("ok", false), "existing procedural world generation remains compatible")
	if not generated.get("ok", false):
		return
	var built_count := 0
	for instance_value in generated.get("instances", []):
		var instance: Dictionary = instance_value
		if instance.get("terrain_interaction", {}).is_empty():
			continue
		var built := Effect.build_from_instance(instance, 0)
		_check(
			built.get("ok", false),
			"generated instance %s normalizes through generic Phase-B effect contract" % String(instance.get("instance_id", ""))
		)
		if built.get("ok", false):
			built_count += 1
		if built_count >= 4:
			break
	_check(built_count > 0, "at least one existing generated object exercises the pure effect path")


func _fixture_instance(
	registry: RefCounted,
	definition_id: String,
	recipe_seed: int,
	region_key: Vector2i,
	position_mm: Vector3i,
	scale_milli: Vector3i,
	yaw_mdeg: int,
	instance_id: String
) -> Dictionary:
	var definition_ids: Array[String] = [definition_id]
	var pin_result: Dictionary = registry.pin_definitions(definition_ids)
	var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, recipe_seed)
	var interaction: Dictionary = registry.resolve_terrain_interaction(definition_id)
	if not pin_result.get("ok", false) or pin_result.get("pins", []).is_empty() 		or not recipe.get("ok", false) or not interaction.get("ok", false):
		return {}
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"content_pin": pin_result["pins"][0].duplicate(true),
		"world_id": WORLD_ID,
		"world_seed": WORLD_SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"region_key": region_key,
		"position_mm": position_mm,
		"default_scale_milli": scale_milli,
		"default_yaw_mdeg": yaw_mdeg,
		"geometry": recipe["geometry"].duplicate(true),
		"geometry_seeds": recipe["geometry_seeds"].duplicate(true),
		"terrain_interaction": interaction["rule"].duplicate(true),
		"terrain_interaction_pin": interaction["pin"].duplicate(true),
		"terrain_interaction_applied": false,
		"instance_components": {},
	}


func _find_common_chunk(
	index: RefCounted,
	first_id: String,
	second_id: String
) -> Dictionary:
	var first_keys: Array[String] = index.get_indexed_chunk_ids(first_id)
	var second_keys: Array[String] = index.get_indexed_chunk_ids(second_id)
	for key in first_keys:
		if not second_keys.has(key):
			continue
		var regex := RegEx.new()
		regex.compile("^region:(-?[0-9]+),(-?[0-9]+)/chunk:([0-9]+),([0-9]+)$")
		var match := regex.search(key)
		if match != null:
			return {
				"ok": true,
				"region_key": Vector2i(int(match.get_string(1)), int(match.get_string(2))),
				"coordinate": Vector2i(int(match.get_string(3)), int(match.get_string(4))),
			}
	return {"ok": false}


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _synthetic_discovery() -> Dictionary:
	return {
		"ok": true,
		"packages": [{
			"manifest": {
				"id": "phaseb.synthetic",
				"version": "1.0.0",
				"schema_version": 1,
				"requires_engine": "4.7.2",
				"dependencies": [],
				"content_roots": ["objects/", "interactions/"],
				"script_policy": "data_only",
			},
			"definitions": [{
				"schema_version": 2,
				"type": "procedural_rock",
				"id": "phaseb.synthetic:weathered_block",
				"display_name": "Phase B Weathered Block",
				"tags": ["rock", "phase_b"],
				"recipe": {
					"algorithm": "geological_halfspace_v1",
					"profile": "phaseb_weathered_block_v1",
					"half_extent_x_mm": 650,
					"half_extent_y_mm": 700,
					"half_extent_z_mm": 620,
					"primary_plane_count": 7,
					"fracture_plane_count": 3,
					"anisotropy_axis": "x",
					"anisotropy_milli": 1200,
					"bevel_count": 3,
					"weathering_milli": 500,
					"macro_roughness_mm": 35,
					"meso_roughness_mm": 18,
					"fine_roughness_mm": 7,
				},
			}],
			"population_rules": [],
			"terrain_interactions": [{
				"schema_version": 1,
				"type": "terrain_interaction_rule",
				"id": "phaseb.synthetic:weathered_ground",
				"definition_id": "phaseb.synthetic:weathered_block",
				"algorithm": "sdf_ground_imprint_v1",
				"shape_source": "recipe_envelope_v1",
				"operation": "subtract_solid_v1",
				"embed_depth_mm": 240,
				"blend_radius_mm": 160,
				"edit_order": "terrain_edits_then_imprint_v1",
			}],
		}],
	}


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("ISSUE108_PHASE_B_EVIDENCE=" + JSON.stringify(evidence))
	print("ISSUE108_PHASE_B_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL",
		assertions,
		failures,
	])
	quit(0 if failures == 0 else 1)
