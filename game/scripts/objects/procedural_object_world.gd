class_name ProceduralObjectWorld
extends RefCounted

## Pure, bounded placement records. No scene nodes, mesh resources or mutable state.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const LEGACY_ALGORITHM := "p2a_compatibility_slot_v1"
const REGION_GRID_ALGORITHM := "region_grid_density_v1"
const LEGACY_SLOT_DEFINITIONS := [
	"firstparty.core_rocks:granite",
	"official.example.procedural_rock:basalt_stack",
]
const SLOT_DEFINITIONS := LEGACY_SLOT_DEFINITIONS # P2.0A compatibility API; new population uses registry rules.
const MAX_SURFACE_ATTEMPTS := 12
const MAX_SURFACE_ANCHORS_PER_REGION := 64
const MAX_RULES_PER_REGION := 16
const MAX_CANDIDATE_CELLS_PER_REGION := 256
const MAX_OBJECTS_PER_REGION := 64
const SURFACE_SCAN_TOP := 8.0
const SURFACE_SCAN_BOTTOM := -0.9
const SURFACE_SCAN_STEP := 0.1
const SURFACE_REFINEMENT_STEPS := 16
const SURFACE_NORMAL_PROBE := 0.25
const RANDOM_MODULUS := 2147483647
const SAFE_REGION_COORD_MIN := -2147483648
const SAFE_REGION_COORD_MAX := 2147483647


static func build_region_instances(
	world_seed: int,
	world_id: String,
	region_key: Vector2i,
	registry: ContentDefinitionRegistry
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if world_seed < 0 or world_seed >= RANDOM_MODULUS:
		return _failure("invalid_world_seed")
	if world_id.is_empty() or registry == null or region_key.x < SAFE_REGION_COORD_MIN or region_key.x > SAFE_REGION_COORD_MAX or region_key.y < SAFE_REGION_COORD_MIN or region_key.y > SAFE_REGION_COORD_MAX:
		return _failure("invalid_world_identity_or_registry")
	var all_rule_ids: Array[String] = registry.get_population_rule_ids()
	if all_rule_ids.size() > MAX_RULES_PER_REGION:
		return _failure("population_rule_region_budget_exceeded")
	var rules: Array[Dictionary] = []
	var legacy_by_slot: Dictionary = {}
	var used_definition_ids: Array[String] = []
	var candidate_cells_total := 0
	for rule_id in all_rule_ids:
		var rule: Dictionary = registry.get_population_rule(rule_id)
		if rule.is_empty():
			return _failure("population_rule_disappeared")
		if rule.get("algorithm", "") == LEGACY_ALGORITHM:
			var slot := int(rule.get("legacy_slot", -1))
			if slot < 0 or slot >= LEGACY_SLOT_DEFINITIONS.size() or legacy_by_slot.has(slot) or String(rule.get("definition_id", "")) != String(LEGACY_SLOT_DEFINITIONS[slot]):
				return _failure("legacy_population_contract_mismatch")
			legacy_by_slot[slot] = rule
		else:
			candidate_cells_total += _candidate_cell_count(rule.get("distribution", {}))
			rules.append(rule)
		var definition_id := String(rule.get("definition_id", ""))
		if not used_definition_ids.has(definition_id):
			used_definition_ids.append(definition_id)
	if legacy_by_slot.size() != LEGACY_SLOT_DEFINITIONS.size():
		return _failure("legacy_population_rules_missing")
	if candidate_cells_total > MAX_CANDIDATE_CELLS_PER_REGION:
		return _failure("population_candidate_region_budget_exceeded")
	var pins_result: Dictionary = registry.pin_definitions(used_definition_ids)
	if not pins_result.get("ok", false):
		return _failure("population_definition_content_unavailable")
	var pins_by_id: Dictionary = {}
	for pin in pins_result["pins"]:
		pins_by_id[String(pin["content_id"])] = pin
	var rules_by_id: Dictionary = {}
	for rule in rules:
		var rule_id := String(rule["id"])
		var pin_result := registry.pin_population_rule(rule_id)
		if not pin_result.get("ok", false):
			return _failure("population_rule_pin_failed")
		rules_by_id[rule_id] = pin_result["pin"]
	rules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))

	var instances: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	var surface_anchor_count := 0
	# These two compatibility records preserve every P2.0A/P2.0B identity and
	# placement seed exactly. Their rules now live in the same data registry.
	for slot in range(LEGACY_SLOT_DEFINITIONS.size()):
		var rule: Dictionary = legacy_by_slot[slot]
		var definition_id := String(rule["definition_id"])
		var placement_seed := _mix_seed(world_seed, region_key, slot)
		var position_result := _find_placement(world_seed, region_key, placement_seed, slot)
		surface_anchor_count += int(position_result.get("attempts", MAX_SURFACE_ATTEMPTS))
		if not position_result.get("ok", false):
			return _failure("legacy_surface_anchor_unavailable")
		var recipe_seed := _mix_seed(placement_seed, region_key, 97 + slot)
		var instance_result := _build_instance(world_seed, world_id, region_key, registry, rule, pins_by_id[definition_id], {}, slot, -1, placement_seed, recipe_seed, position_result["position_mm"], Vector3i(1000, 1000, 1000), 0)
		if not instance_result.get("ok", false):
			return instance_result
		var legacy_instance: Dictionary = instance_result["instance"]
		if seen_ids.has(legacy_instance["instance_id"]):
			return _failure("population_instance_identity_collision")
		seen_ids[legacy_instance["instance_id"]] = true
		instances.append(legacy_instance)
	if surface_anchor_count > MAX_SURFACE_ANCHORS_PER_REGION:
		return _failure("population_surface_anchor_budget_exceeded")

	for rule in rules:
		var rule_id := String(rule["id"])
		var definition_id := String(rule["definition_id"])
		var definition: Dictionary = registry.get_definition(definition_id)
		var generated: Dictionary = _build_rule_instances(
			world_seed, world_id, region_key, registry, rule, definition,
			pins_by_id[definition_id], rules_by_id[rule_id], instances, seen_ids,
			surface_anchor_count
		)
		if not generated.get("ok", false):
			return generated
		instances = generated["instances"]
		seen_ids = generated["seen_ids"]
		surface_anchor_count = int(generated["surface_anchor_count"])
		if instances.size() > MAX_OBJECTS_PER_REGION:
			return _failure("population_instance_region_budget_exceeded")

	return {
		"ok": true,
		"reason": "ok",
		"region_key": region_key,
		"instances": instances,
		"timings_usec": {"total": Time.get_ticks_usec() - started_usec},
		"candidate_cell_count": candidate_cells_total,
		"surface_anchor_count": surface_anchor_count,
	}


static func _build_rule_instances(
	world_seed: int,
	world_id: String,
	region_key: Vector2i,
	registry: ContentDefinitionRegistry,
	rule: Dictionary,
	definition: Dictionary,
	content_pin: Dictionary,
	rule_pin: Dictionary,
	prior_instances: Array[Dictionary],
	prior_ids: Dictionary,
	prior_surface_anchor_count: int
) -> Dictionary:
	var distribution: Dictionary = rule["distribution"]
	var transform_rule: Dictionary = rule["transform"]
	var surface_rule: Dictionary = rule["surface"]
	var cells := _candidate_cells(distribution)
	if cells.is_empty():
		return _failure("population_lattice_empty")
	var density := int(rule["density_milli_per_region"])
	# Density is in milli-instances per region; divide by 1000 before turning
	# the expected count into a per-cell ticket in the [0, 1_000_000) domain.
	var threshold := int(floor(float(density) * 1000.0 / float(cells.size())))
	var rule_hash := _stable_hash(String(rule["id"]))
	var accepted: Array[Dictionary] = []
	var next_state := 1
	var surface_anchor_count := prior_surface_anchor_count
	var recipe: Dictionary = definition["recipe"]
	var radius_mm := sqrt(pow(float(recipe["half_extent_x_mm"]), 2.0) + pow(float(recipe["half_extent_z_mm"]), 2.0))
	for cell in cells:
		var candidate_index := int(cell["candidate_index"])
		var candidate_discriminator := posmod(rule_hash + candidate_index * 104729, RANDOM_MODULUS - 1) + 1
		var placement_seed := _mix_seed(world_seed, region_key, candidate_discriminator)
		next_state = _next_random(placement_seed)
		var density_ticket := next_state % 1000000
		if density_ticket >= threshold:
			continue
		if surface_anchor_count >= MAX_SURFACE_ANCHORS_PER_REGION:
			return _failure("population_surface_anchor_budget_exceeded")
		var spacing := int(distribution["grid_spacing_mm"])
		var jitter_limit := int(floor(float(spacing) * float(distribution["jitter_milli"]) / 1000.0))
		next_state = _next_random(next_state)
		var jitter_x := _signed_offset(next_state, jitter_limit)
		next_state = _next_random(next_state)
		var jitter_z := _signed_offset(next_state, jitter_limit)
		var local_x_mm := clampi(int(cell["x_mm"]) + jitter_x, int(distribution["edge_margin_mm"]), 16000 - int(distribution["edge_margin_mm"]))
		var local_z_mm := clampi(int(cell["z_mm"]) + jitter_z, int(distribution["edge_margin_mm"]), 12000 - int(distribution["edge_margin_mm"]))
		var local_x := float(local_x_mm) / 1000.0
		var local_z := float(local_z_mm) / 1000.0
		var surface_y := _find_top_surface(world_seed, region_key, local_x, local_z)
		surface_anchor_count += 1
		if not is_finite(surface_y):
			continue
		var position_y_mm := roundi(surface_y * 1000.0)
		if position_y_mm < int(surface_rule["minimum_height_mm"]) or position_y_mm > int(surface_rule["maximum_height_mm"]):
			continue
		if not _surface_slope_allowed(world_seed, region_key, local_x, local_z, surface_y, int(surface_rule["maximum_slope_mdeg"])):
			continue
		var position_mm := Vector3i(local_x_mm, position_y_mm, local_z_mm)
		if _overlaps_prior(position_mm, int(distribution["minimum_separation_mm"]), radius_mm, prior_instances, accepted):
			continue
		var transform_seed := _mix_seed(placement_seed, region_key, candidate_discriminator + 130363)
		var scale_values: Array = []
		var scale_min: Array = transform_rule["scale_min_milli"]
		var scale_max: Array = transform_rule["scale_max_milli"]
		for axis in range(3):
			transform_seed = _next_random(transform_seed)
			var scale_range := int(scale_max[axis]) - int(scale_min[axis])
			scale_values.append(int(scale_min[axis]) + (transform_seed % (scale_range + 1)))
		transform_seed = _next_random(transform_seed)
		var yaw_range := int(transform_rule["yaw_max_mdeg"]) - int(transform_rule["yaw_min_mdeg"])
		var yaw := int(transform_rule["yaw_min_mdeg"]) + (transform_seed % (yaw_range + 1))
		var variants := int(distribution["geometry_variant_count"])
		var recipe_seed := posmod(_mix_seed(placement_seed, region_key, candidate_discriminator + 3579), variants) + 1
		var candidate_id := _population_instance_id(world_id, world_seed, String(rule["definition_id"]), region_key, String(rule["id"]), candidate_index)
		if prior_ids.has(candidate_id):
			return _failure("population_instance_identity_collision")
		var built := _build_instance(world_seed, world_id, region_key, registry, rule, content_pin, rule_pin, -1, candidate_index, placement_seed, recipe_seed, position_mm, Vector3i(scale_values[0], scale_values[1], scale_values[2]), yaw)
		if not built.get("ok", false):
			return built
		var instance: Dictionary = built["instance"]
		instance["clearance_radius_mm"] = ceil(radius_mm * maxf(float(scale_values[0]), maxf(float(scale_values[1]), float(scale_values[2]))) / 1000.0)
		instance["minimum_separation_mm"] = int(distribution["minimum_separation_mm"])
		instance["population_candidate_key"] = Vector2i(int(cell["grid_x"]), int(cell["grid_z"]))
		accepted.append(instance)
		prior_ids[candidate_id] = true
		if prior_instances.size() + accepted.size() + 1 > MAX_OBJECTS_PER_REGION:
			return _failure("population_instance_region_budget_exceeded")
	for instance in accepted:
		prior_instances.append(instance)
	return {"ok": true, "instances": prior_instances, "seen_ids": prior_ids, "surface_anchor_count": surface_anchor_count}


static func _build_instance(
	world_seed: int,
	world_id: String,
	region_key: Vector2i,
	registry: ContentDefinitionRegistry,
	rule: Dictionary,
	content_pin: Dictionary,
	rule_pin: Dictionary,
	slot: int,
	candidate_index: int,
	placement_seed: int,
	recipe_seed: int,
	position_mm: Vector3i,
	scale_milli: Vector3i,
	yaw_mdeg: int
) -> Dictionary:
	var definition_id := String(rule["definition_id"])
	var recipe_result: Dictionary = registry.evaluate_rock_recipe(definition_id, recipe_seed)
	if not recipe_result.get("ok", false) or recipe_result.get("algorithm", "") != ContentDefinitionRegistry.GEOLOGICAL_ALGORITHM or not recipe_result.get("geometry", null) is Dictionary or not recipe_result.get("geometry_seeds", null) is Dictionary:
		return _failure("population_object_recipe_failed")
	var is_legacy: bool = rule.get("algorithm", "") == LEGACY_ALGORITHM
	var instance_id := _legacy_instance_id(world_id, world_seed, definition_id, region_key, slot) if is_legacy else _population_instance_id(world_id, world_seed, definition_id, region_key, String(rule["id"]), candidate_index)
	var instance := {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"content_pin": content_pin.duplicate(true),
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": FIELD.GENERATOR_VERSION,
		"region_key": region_key,
		"slot": slot,
		"placement_seed": placement_seed,
		"recipe_seed": recipe_seed,
		"recipe_algorithm": recipe_result.get("algorithm", ""),
		"geometry_profile": recipe_result.get("profile", ""),
		"geometry": recipe_result["geometry"].duplicate(true),
		"geometry_seeds": recipe_result["geometry_seeds"].duplicate(true),
		"instance_state": {},
		"component_contract_version": 1,
		"components": ["core.transform@1", "core.appearance@1", "core.logical@1"],
		"position_mm": position_mm,
		"default_scale_milli": scale_milli,
		"default_yaw_mdeg": yaw_mdeg,
		"population_rule_id": "" if is_legacy else String(rule["id"]),
		"population_rule_pin": {} if is_legacy else rule_pin.duplicate(true),
		"population_rule_schema_version": int(rule["schema_version"]),
		"population_candidate_index": candidate_index,
		"population_algorithm": String(rule["algorithm"]),
		"population_batched": not is_legacy,
	}
	var recipe: Dictionary = instance["geometry"]
	var base_radius := sqrt(pow(float(recipe["half_extent_x_mm"]), 2.0) + pow(float(recipe["half_extent_z_mm"]), 2.0))
	var maximum_scale := maxf(float(scale_milli.x), maxf(float(scale_milli.y), float(scale_milli.z)))
	instance["clearance_radius_mm"] = ceil(base_radius * maximum_scale / 1000.0)
	instance["minimum_separation_mm"] = int(rule.get("distribution", {}).get("minimum_separation_mm", 0))
	if not is_legacy:
		var id_contract := String(instance["instance_id"])
		if id_contract.length() > 256:
			return _failure("population_instance_id_too_long")
	return {"ok": true, "instance": instance}


static func _candidate_cells(distribution: Dictionary) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	var spacing := int(distribution.get("grid_spacing_mm", 0))
	var margin := int(distribution.get("edge_margin_mm", 0))
	if spacing <= 0:
		return cells
	var index := 0
	var grid_z := 0
	var z_mm := margin
	while z_mm <= 12000 - margin:
		var grid_x := 0
		var x_mm := margin
		while x_mm <= 16000 - margin:
			cells.append({"candidate_index": index, "grid_x": grid_x, "grid_z": grid_z, "x_mm": x_mm, "z_mm": z_mm})
			index += 1
			grid_x += 1
			x_mm += spacing
		grid_z += 1
		z_mm += spacing
	return cells


static func _candidate_cell_count(distribution: Dictionary) -> int:
	return _candidate_cells(distribution).size()


static func _overlaps_prior(position_mm: Vector3i, minimum_separation_mm: int, clearance_radius_mm: float, prior_instances: Array[Dictionary], accepted: Array[Dictionary]) -> bool:
	for candidate in prior_instances + accepted:
		var previous: Vector3i = candidate["position_mm"]
		var distance := Vector2(float(previous.x - position_mm.x), float(previous.z - position_mm.z)).length()
		var required := maxf(float(minimum_separation_mm), maxf(float(candidate.get("minimum_separation_mm", 0)), clearance_radius_mm + float(candidate.get("clearance_radius_mm", 0)) + 100.0))
		if distance < required:
			return true
	return false


static func _surface_slope_allowed(world_seed: int, region_key: Vector2i, local_x: float, local_z: float, center_y: float, maximum_slope_mdeg: int) -> bool:
	var x_before := _find_top_surface(world_seed, region_key, local_x - SURFACE_NORMAL_PROBE, local_z)
	var x_after := _find_top_surface(world_seed, region_key, local_x + SURFACE_NORMAL_PROBE, local_z)
	var z_before := _find_top_surface(world_seed, region_key, local_x, local_z - SURFACE_NORMAL_PROBE)
	var z_after := _find_top_surface(world_seed, region_key, local_x, local_z + SURFACE_NORMAL_PROBE)
	if not is_finite(x_before) or not is_finite(x_after) or not is_finite(z_before) or not is_finite(z_after):
		return false
	var inverse_probe := 1.0 / (2.0 * SURFACE_NORMAL_PROBE)
	var slope_x := (x_after - x_before) * inverse_probe
	var slope_z := (z_after - z_before) * inverse_probe
	var slope_degrees := atan(sqrt(slope_x * slope_x + slope_z * slope_z)) * 180000.0 / PI
	return is_finite(slope_degrees) and slope_degrees <= float(maximum_slope_mdeg) + 0.5 and is_finite(center_y)


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
			return {"ok": true, "attempts": _attempt + 1, "position_mm": Vector3i(local_x_mm, roundi(surface_y * 1000.0), local_z_mm)}
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


static func _stable_hash(value: String) -> int:
	var hash_value: int = 2166136261
	for byte_value in value.to_utf8_buffer():
		hash_value = (hash_value ^ int(byte_value)) * 16777619
		hash_value = hash_value & 0xffffffff
	return hash_value


static func _next_random(value: int) -> int:
	return (value * 16807) % RANDOM_MODULUS


static func _signed_offset(value: int, magnitude: int) -> int:
	if magnitude == 0:
		return 0
	return value % (magnitude * 2 + 1) - magnitude


static func _legacy_instance_id(world_id: String, world_seed: int, definition_id: String, region_key: Vector2i, slot: int) -> String:
	return "%s/seed-%d/object/%s/region/%d,%d/slot/%d" % [world_id, world_seed, definition_id, region_key.x, region_key.y, slot]


static func _population_instance_id(world_id: String, world_seed: int, definition_id: String, region_key: Vector2i, rule_id: String, candidate_index: int) -> String:
	return "%s/seed-%d/object/%s/region/%d,%d/population/%s/candidate/%d" % [world_id, world_seed, definition_id, region_key.x, region_key.y, rule_id, candidate_index]


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
