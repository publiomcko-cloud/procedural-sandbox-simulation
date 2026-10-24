class_name ProceduralObjectWorld
extends RefCounted

## Pure deterministic placement records for data-defined static procedural objects.
## Scene nodes and meshes are created by ProceduralObjectStream, never stored here.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const SLOT_DEFINITIONS := [
	"firstparty.core_rocks:granite",
	"official.example.procedural_rock:basalt_stack",
]
const MAX_SURFACE_ATTEMPTS := 12
const SURFACE_SCAN_TOP := 8.0
const SURFACE_SCAN_BOTTOM := -0.9
const SURFACE_SCAN_STEP := 0.1
const SURFACE_REFINEMENT_STEPS := 16
const RANDOM_MODULUS := 2147483647


static func build_region_instances(
	world_seed: int,
	world_id: String,
	region_key: Vector2i,
	registry: ContentDefinitionRegistry
) -> Dictionary:
	if world_seed < 0 or world_seed >= RANDOM_MODULUS:
		return _failure("invalid_world_seed")
	if world_id.is_empty() or registry == null:
		return _failure("invalid_world_identity_or_registry")
	var definition_ids: Array[String] = []
	for definition_id in SLOT_DEFINITIONS:
		definition_ids.append(String(definition_id))
	var pins_result: Dictionary = registry.pin_definitions(definition_ids)
	if not pins_result.get("ok", false):
		return _failure("required_object_content_unavailable")
	var pins_by_id: Dictionary = {}
	for pin in pins_result["pins"]:
		pins_by_id[String(pin["content_id"])] = pin
	var instances: Array[Dictionary] = []
	for slot_index in range(SLOT_DEFINITIONS.size()):
		var definition_id: String = SLOT_DEFINITIONS[slot_index]
		var placement_seed := _mix_seed(world_seed, region_key, slot_index)
		var position_result := _find_placement(world_seed, region_key, placement_seed, slot_index)
		if not position_result.get("ok", false):
			return _failure("no_valid_terrain_anchor")
		var recipe_seed := _mix_seed(placement_seed, region_key, 97 + slot_index)
		var recipe: Dictionary = registry.evaluate_rock_recipe(definition_id, recipe_seed)
		if not recipe.get("ok", false):
			return _failure("required_object_recipe_failed")
		if recipe.get("algorithm", "") != ContentDefinitionRegistry.GEOLOGICAL_ALGORITHM or not recipe.get("geometry", null) is Dictionary or not recipe.get("geometry_seeds", null) is Dictionary:
			return _failure("required_object_geometry_version_unavailable")
		instances.append({
			"instance_id": _instance_id(world_id, world_seed, definition_id, region_key, slot_index),
			"definition_id": definition_id,
			"content_pin": pins_by_id[definition_id].duplicate(true),
			"world_id": world_id,
			"world_seed": world_seed,
			"generator_version": FIELD.GENERATOR_VERSION,
			"region_key": region_key,
			"slot": slot_index,
			"placement_seed": placement_seed,
			"recipe_seed": recipe_seed,
			"recipe_algorithm": recipe.get("algorithm", ""),
			"geometry_profile": recipe.get("profile", ""),
			"geometry": recipe["geometry"].duplicate(true),
			"geometry_seeds": recipe["geometry_seeds"].duplicate(true),
			"instance_state": {},
			"position_mm": position_result["position_mm"],
		})
	return {"ok": true, "reason": "ok", "region_key": region_key, "instances": instances}


static func _find_placement(world_seed: int, region_key: Vector2i, seed: int, slot: int) -> Dictionary:
	var state := seed
	for _attempt in range(MAX_SURFACE_ATTEMPTS):
		state = _next_random(state)
		var x_min := 1800 if slot == 0 else 9800
		var x_max := 6200 if slot == 0 else 14200
		var local_x_mm := x_min + state % (x_max - x_min + 1)
		state = _next_random(state)
		var local_z_mm := 1300 + state % 9401
		var surface_y := _find_top_surface(world_seed, region_key, float(local_x_mm) / 1000.0, float(local_z_mm) / 1000.0)
		if is_finite(surface_y):
			return {"ok": true, "position_mm": Vector3i(local_x_mm, roundi(surface_y * 1000.0), local_z_mm)}
	return _failure("surface_anchor_unavailable")


static func _find_top_surface(world_seed: int, region_key: Vector2i, local_x: float, local_z: float) -> float:
	var previous_y := SURFACE_SCAN_TOP
	var previous_density := FIELD.sample_density(world_seed, region_key, Vector3(local_x, previous_y, local_z))
	if not is_finite(previous_density) or previous_density > 0.0:
		return NAN
	var scan_steps := ceili((SURFACE_SCAN_TOP - SURFACE_SCAN_BOTTOM) / SURFACE_SCAN_STEP)
	for index in range(1, scan_steps + 1):
		var sample_y := SURFACE_SCAN_TOP - float(index) * SURFACE_SCAN_STEP
		var density := FIELD.sample_density(world_seed, region_key, Vector3(local_x, sample_y, local_z))
		if not is_finite(density):
			return NAN
		if density > 0.0:
			var inside_y := sample_y
			var outside_y := previous_y
			for _refine in range(SURFACE_REFINEMENT_STEPS):
				var middle_y := (inside_y + outside_y) * 0.5
				var middle_density := FIELD.sample_density(world_seed, region_key, Vector3(local_x, middle_y, local_z))
				if not is_finite(middle_density):
					return NAN
				if middle_density > 0.0:
					inside_y = middle_y
				else:
					outside_y = middle_y
			return (inside_y + outside_y) * 0.5
		previous_y = sample_y
		previous_density = density
	return NAN


static func _mix_seed(world_seed: int, region_key: Vector2i, discriminator: int) -> int:
	var value := world_seed * 48271 + region_key.x * 69621 + region_key.y * 104729 + discriminator * 130363
	return posmod(value, RANDOM_MODULUS - 1) + 1


static func _next_random(value: int) -> int:
	return (value * 16807) % RANDOM_MODULUS


static func _instance_id(world_id: String, world_seed: int, definition_id: String, region_key: Vector2i, slot: int) -> String:
	return "%s/seed-%d/object/%s/region/%d,%d/slot/%d" % [world_id, world_seed, definition_id, region_key.x, region_key.y, slot]


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
