extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const Frame := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")
const LocalIndex := preload("res://scripts/terrain/terrain_object_effect_local_index.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const WORLD_ID := "issue108-pre-d"
const WORLD_SEED := 424242
const FAR_POSITIVE := Vector2i(100000000, 100000000)
const FAR_NEGATIVE := Vector2i(-100000000, -100000000)

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := Registry.new()
	var registration := registry.discover_and_register(["res://mods/first-party"])
	_check(registration.get("ok", false), "first-party registry initializes")
	if not registration.get("ok", false):
		_finish()
		return

	_test_far_region_invariance(registry)
	_test_frame_region_normalization(registry)
	_test_cross_region_indexing(registry)
	_test_sampling_boundary(registry)
	_test_json_idempotence(registry)
	_finish()


func _test_far_region_invariance(registry: RefCounted) -> void:
	var origin := _fixture(
		registry,
		Vector2i.ZERO,
		Vector3i(8200, 3800, 6100),
		"precision-invariant"
	)
	var far_positive := origin.duplicate(true)
	far_positive["region_key"] = FAR_POSITIVE
	var far_negative := origin.duplicate(true)
	far_negative["region_key"] = FAR_NEGATIVE

	var built_origin := Frame.build_from_instance(origin, 7)
	var built_positive := Frame.build_from_instance(far_positive, 7)
	var built_negative := Frame.build_from_instance(far_negative, 7)
	_check(
		built_origin.get("ok", false)
			and built_positive.get("ok", false)
			and built_negative.get("ok", false),
		"local frames build at origin and +/-100M regions"
	)
	if not built_origin.get("ok", false) 		or not built_positive.get("ok", false) 		or not built_negative.get("ok", false):
		return
	var a: Dictionary = built_origin["frame"]
	var b: Dictionary = built_positive["frame"]
	var c: Dictionary = built_negative["frame"]

	for field in [
		"frame_origin_local_mm", "rotation_mdeg", "scale_milli",
		"local_planes", "bounds_min_local", "bounds_max_local",
		"interior_point_local", "shape_descriptor_sha256",
	]:
		_check(
			a[field] == b[field] and a[field] == c[field],
			"far-region translation leaves local geometry invariant: %s" % field
		)
	_check(
		a["frame_region_key"] == [0, 0]
			and b["frame_region_key"] == [FAR_POSITIVE.x, FAR_POSITIVE.y]
			and c["frame_region_key"] == [FAR_NEGATIVE.x, FAR_NEGATIVE.y],
		"only integer frame region identity changes across huge world offsets"
	)
	var local_interior := _v3(a["interior_point_local"])
	var sample_a := Frame.sample_cutter_prevalidated(
		a, Vector2i.ZERO, local_interior
	)
	var sample_b := Frame.sample_cutter_prevalidated(
		b, FAR_POSITIVE, local_interior
	)
	var sample_c := Frame.sample_cutter_prevalidated(
		c, FAR_NEGATIVE, local_interior
	)
	_check(
		sample_a == sample_b and sample_a == sample_c and sample_a < 0.0,
		"sampling is bit-stable at equivalent local points across +/-100M regions"
	)
	evidence["far_region_interior_cutter"] = sample_a


func _test_frame_region_normalization(registry: RefCounted) -> void:
	var instance := _fixture(
		registry,
		Vector2i(17, -23),
		Vector3i(15800, 3800, 11800),
		"normalized-crossing"
	)
	instance["instance_components"] = {
		"core.transform": {
			"schema_version": 1,
			"properties": {
				"translation_mm": [700, 50, 500],
				"rotation_mdeg": [0, 23000, 0],
				"scale_milli": [1000, 1000, 1000],
			},
		},
	}
	var built := Frame.build_from_instance(instance, 9)
	_check(built.get("ok", false), "translation crossing +X/+Z region boundaries builds")
	if built.get("ok", false):
		var frame: Dictionary = built["frame"]
		_check(
			frame["frame_region_key"] == [18, -22]
				and frame["frame_origin_local_mm"] == [500, 3850, 300],
			"effective origin is normalized by integer region carry"
		)
		_check(
			int(frame["frame_origin_local_mm"][0]) >= 0
				and int(frame["frame_origin_local_mm"][0]) < Frame.REGION_SIZE_X_MM
				and int(frame["frame_origin_local_mm"][2]) >= 0
				and int(frame["frame_origin_local_mm"][2]) < Frame.REGION_SIZE_Z_MM,
			"normalized local origin remains bounded"
		)

	var negative := _fixture(
		registry,
		Vector2i(-17, 23),
		Vector3i(100, 3800, 100),
		"normalized-negative"
	)
	negative["instance_components"] = {
		"core.transform": {
			"schema_version": 1,
			"properties": {
				"translation_mm": [-500, 0, -300],
				"rotation_mdeg": [0, 0, 0],
				"scale_milli": [1000, 1000, 1000],
			},
		},
	}
	var negative_built := Frame.build_from_instance(negative, 3)
	_check(negative_built.get("ok", false), "negative crossing transform builds")
	if negative_built.get("ok", false):
		_check(
			negative_built["frame"]["frame_region_key"] == [-18, 22]
				and negative_built["frame"]["frame_origin_local_mm"]
					== [15600, 3800, 11800],
			"negative crossings use floor ownership rather than truncation"
		)


func _test_cross_region_indexing(registry: RefCounted) -> void:
	var seam := _fixture(
		registry,
		FAR_POSITIVE,
		Vector3i(15850, 3800, 6000),
		"far-seam-positive"
	)
	var built := Frame.build_from_instance(seam, 1)
	_check(built.get("ok", false), "far +X seam frame builds")
	if not built.get("ok", false):
		return
	var frame: Dictionary = built["frame"]
	var index := LocalIndex.new()
	var indexed := index.replace_frame(frame)
	_check(indexed.get("ok", false), "far seam frame indexes without global float coordinates")
	_check(
		index.get_effect_ids_for_chunk(FAR_POSITIVE, Vector2i(3, 2))
			.has(frame["effect_id"]),
		"far seam frame indexes owning edge chunk"
	)
	_check(
		index.get_effect_ids_for_chunk(FAR_POSITIVE + Vector2i.RIGHT, Vector2i(0, 2))
			.has(frame["effect_id"]),
		"far seam frame indexes +X neighbor with integer chunk mapping"
	)

	var negative := _fixture(
		registry,
		FAR_NEGATIVE,
		Vector3i(150, 3800, 6000),
		"far-seam-negative"
	)
	var negative_built := Frame.build_from_instance(negative, 2)
	_check(negative_built.get("ok", false), "far negative seam frame builds")
	if negative_built.get("ok", false):
		var negative_frame: Dictionary = negative_built["frame"]
		_check(index.replace_frame(negative_frame).get("ok", false), "far negative seam indexes")
		_check(
			index.get_effect_ids_for_chunk(
				FAR_NEGATIVE - Vector2i.RIGHT, Vector2i(3, 2)
			).has(negative_frame["effect_id"]),
			"far negative seam uses signed floor ownership"
		)


func _test_sampling_boundary(registry: RefCounted) -> void:
	var seam := _fixture(
		registry,
		Vector2i(31, -41),
		Vector3i(15900, 3800, 6000),
		"sampling-seam"
	)
	var built := Frame.build_from_instance(seam, 5)
	_check(built.get("ok", false), "sampling seam frame builds")
	if not built.get("ok", false):
		return
	var frame: Dictionary = built["frame"]
	var frame_region := Vector2i(
		int(frame["frame_region_key"][0]),
		int(frame["frame_region_key"][1])
	)
	var y := float(frame["interior_point_local"][1])
	var z := float(frame["interior_point_local"][2])
	var source_side := Frame.sample_cutter_prevalidated(
		frame, frame_region, Vector3(16.1, y, z)
	)
	var neighbor_side := Frame.sample_cutter_prevalidated(
		frame, frame_region + Vector2i.RIGHT, Vector3(0.1, y, z)
	)
	_check(
		source_side == neighbor_side,
		"same physical point has identical cutter value across region-local seam representation"
	)
	var too_far := Frame.sample_cutter_prevalidated(
		frame,
		frame_region + Vector2i(Frame.MAX_QUERY_REGION_DELTA + 1, 0),
		Vector3.ZERO
	)
	_check(too_far == INF, "sampling fails closed outside bounded indexed region delta")


func _test_json_idempotence(registry: RefCounted) -> void:
	var instance := _fixture(
		registry,
		Vector2i(-321, 654),
		Vector3i(14321, 3777, 11234),
		"json-roundtrip"
	)
	instance["instance_components"] = {
		"core.transform": {
			"schema_version": 1,
			"properties": {
				"translation_mm": [-811, 73, 1222],
				"rotation_mdeg": [11000, -37000, 8000],
				"scale_milli": [901, 1234, 1111],
			},
		},
	}
	var built := Frame.build_from_instance(instance, 11)
	_check(built.get("ok", false), "round-trip frame builds")
	if not built.get("ok", false):
		return
	var frame: Dictionary = built["frame"]
	var encoded := JSON.stringify(frame, "", true, true)
	var decoded: Variant = JSON.parse_string(encoded)
	var validated := Frame.validate_frame(decoded)
	_check(validated.get("ok", false), "serialized local frame validates after JSON parse")
	if validated.get("ok", false):
		var reencoded := JSON.stringify(validated["frame"], "", true, true)
		_check(encoded == reencoded, "local frame JSON representation is idempotent")
		_check(
			validated["frame"]["content_pin"] == frame["content_pin"]
				and validated["frame"]["terrain_interaction_pin"]
					== frame["terrain_interaction_pin"],
			"local frame round-trip preserves exact content and interaction pins"
		)
	_check(
		not frame.has("world_planes")
			and not frame.has("bounds_min")
			and not frame.has("bounds_max")
			and not frame.has("anchor_world_mm"),
		"precision-safe frame contains no global geometric float/anchor fields"
	)


func _fixture(
	registry: RefCounted,
	region_key: Vector2i,
	position_mm: Vector3i,
	instance_id: String
) -> Dictionary:
	var definition_id := "firstparty.core_rocks:granite"
	var definition_ids: Array[String] = [definition_id]
	var pin_result: Dictionary = registry.pin_definitions(definition_ids)
	var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, 31337)
	var interaction: Dictionary = registry.resolve_terrain_interaction(definition_id)
	if not pin_result.get("ok", false) 		or (pin_result.get("pins", []) as Array).is_empty() 		or not recipe.get("ok", false) 		or not interaction.get("ok", false):
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
		"default_scale_milli": Vector3i(1000, 1000, 1000),
		"default_yaw_mdeg": 0,
		"geometry": recipe["geometry"].duplicate(true),
		"geometry_seeds": recipe["geometry_seeds"].duplicate(true),
		"terrain_interaction": interaction["rule"].duplicate(true),
		"terrain_interaction_pin": interaction["pin"].duplicate(true),
		"terrain_interaction_applied": false,
		"instance_components": {},
	}


func _v3(value: Array) -> Vector3:
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
