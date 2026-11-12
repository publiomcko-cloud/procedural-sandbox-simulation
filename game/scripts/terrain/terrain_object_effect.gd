class_name TerrainObjectEffect
extends RefCounted

## Pure terrain-object effect normalization and SDF evaluation.
##
## This Phase-B domain type is intentionally disconnected from terrain runtime,
## persistence and entity lifecycle. It accepts already-resolved object records
## and produces deterministic world-space convex cutter planes.
const ShapeDescriptor := preload("res://scripts/objects/procedural_rock_shape_descriptor.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

const SCHEMA_VERSION := 1
const EFFECT_TYPE := "terrain_object_effect"
const EFFECT_ALGORITHM := "sdf_ground_imprint_v1"
const SHAPE_SOURCE := "recipe_envelope_v1"
const OPERATION := "subtract_solid_v1"
const EDIT_ORDER := "terrain_edits_then_imprint_v1"
const BLEND_MODE := "interior_eased_subtract_v1"
const MAX_WORLD_SEED := 2147483646
const MAX_SOURCE_REVISION := 9007199254740991
const MAX_PLANES := 64
const EFFECT_KEYS := [
	"schema_version", "type", "effect_id", "source_instance_id", "source_revision",
	"source_fingerprint_sha256", "world_id", "world_seed", "generator_version",
	"definition_id", "content_pin", "terrain_interaction_pin",
	"shape_descriptor_version", "shape_descriptor_sha256", "algorithm",
	"shape_source", "operation", "edit_order", "blend_mode",
	"embed_depth_mm", "blend_radius_mm", "anchor_world_mm", "translation_mm",
	"rotation_mdeg", "scale_milli", "world_planes", "bounds_min", "bounds_max",
	"interior_point_world"
]


static func build_from_instance(instance: Dictionary, source_revision: int = 0, cached_pair_cross: bool = false) -> Dictionary:
	var input_check := _validate_instance_input(instance, source_revision)
	if not input_check.get("ok", false):
		return input_check
	var content_pin: Dictionary = instance["content_pin"]
	if not _exact_keys(content_pin, [
		"content_id", "mod_id", "mod_version", "definition_schema_version"
	]) \
		or String(content_pin.get("content_id", "")) != String(instance["definition_id"]) \
		or String(content_pin.get("mod_id", "")).is_empty() \
		or String(content_pin.get("mod_version", "")).is_empty() \
		or not _is_integer(content_pin.get("definition_schema_version")):
		return _failure("terrain_effect_content_pin_invalid")
	var interaction: Dictionary = instance["terrain_interaction"]
	var interaction_pin: Dictionary = instance["terrain_interaction_pin"]
	var descriptor := ShapeDescriptor.build(instance["geometry"], instance["geometry_seeds"], cached_pair_cross)
	if not descriptor.get("ok", false):
		return _failure("terrain_effect_shape_descriptor_failed:%s" % descriptor.get("reason", "unknown"))

	var transform_result := _resolve_transform(instance)
	if not transform_result.get("ok", false):
		return transform_result
	var anchor_world_mm: Vector3i = transform_result["anchor_world_mm"]
	var translation_mm: Vector3i = transform_result["translation_mm"]
	var rotation_mdeg: Vector3i = transform_result["rotation_mdeg"]
	var scale_milli: Vector3i = transform_result["scale_milli"]
	var embed_depth_mm := int(interaction["embed_depth_mm"])
	var effect_origin := (
		Vector3(anchor_world_mm + translation_mm) / 1000.0
		+ Vector3(0.0, -float(embed_depth_mm) / 1000.0, 0.0)
	)
	var rotation_radians := Vector3(rotation_mdeg) * (PI / 180000.0)
	var basis := Basis.from_euler(rotation_radians)
	var scale := Vector3(scale_milli) / 1000.0
	if scale.x <= 0.0 or scale.y <= 0.0 or scale.z <= 0.0:
		return _failure("terrain_effect_scale_invalid")

	var local_guard := float(descriptor["roughness_guard_m"])
	var world_planes: Array[Dictionary] = []
	for plane_value in descriptor["planes"]:
		var plane: Dictionary = plane_value
		var local_normal: Vector3 = plane["normal"]
		var scaled_normal := Vector3(
			local_normal.x / scale.x,
			local_normal.y / scale.y,
			local_normal.z / scale.z
		)
		var world_unnormalized: Vector3 = basis * scaled_normal
		var normal_length := world_unnormalized.length()
		if not is_finite(normal_length) or normal_length <= 0.000000001:
			return _failure("terrain_effect_plane_transform_invalid")
		var world_normal := world_unnormalized / normal_length
		var local_distance := float(plane["distance"]) + local_guard
		var world_distance := local_distance / normal_length + world_normal.dot(effect_origin)
		world_planes.append({
			"normal": [world_normal.x, world_normal.y, world_normal.z],
			"distance_m": world_distance,
		})
	if world_planes.is_empty() or world_planes.size() > MAX_PLANES:
		return _failure("terrain_effect_plane_budget_invalid")

	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var interior := Vector3.ZERO
	var guarded_vertices: Array[Vector3] = descriptor["guarded_vertices"]
	for local_vertex in guarded_vertices:
		var world_vertex := effect_origin + basis * (local_vertex * scale)
		minimum = minimum.min(world_vertex)
		maximum = maximum.max(world_vertex)
		interior += world_vertex
	if guarded_vertices.is_empty() or not minimum.is_finite() or not maximum.is_finite():
		return _failure("terrain_effect_bounds_invalid")
	interior /= float(guarded_vertices.size())

	var world_id := String(instance["world_id"])
	var source_id := String(instance["instance_id"])
	var effect_identity_source := JSON.stringify({
		"schema_version": SCHEMA_VERSION,
		"world_id": world_id,
		"source_instance_id": source_id,
	}, "", true, true)
	var effect_id := "%s/terrain-effect-v1/%s" % [
		world_id,
		effect_identity_source.sha256_text().substr(0, 32),
	]
	var source_fingerprint := JSON.stringify({
		"schema_version": SCHEMA_VERSION,
		"source_instance_id": source_id,
		"source_revision": source_revision,
		"content_pin": instance["content_pin"],
		"terrain_interaction_pin": interaction_pin,
		"shape_descriptor_sha256": descriptor["descriptor_sha256"],
		"anchor_world_mm": _vector3i_array(anchor_world_mm),
		"translation_mm": _vector3i_array(translation_mm),
		"rotation_mdeg": _vector3i_array(rotation_mdeg),
		"scale_milli": _vector3i_array(scale_milli),
		"embed_depth_mm": embed_depth_mm,
		"blend_radius_mm": int(interaction["blend_radius_mm"]),
	}, "", true, true).sha256_text()

	var effect := {
		"schema_version": SCHEMA_VERSION,
		"type": EFFECT_TYPE,
		"effect_id": effect_id,
		"source_instance_id": source_id,
		"source_revision": source_revision,
		"source_fingerprint_sha256": source_fingerprint,
		"world_id": world_id,
		"world_seed": int(instance["world_seed"]),
		"generator_version": int(instance["generator_version"]),
		"definition_id": String(instance["definition_id"]),
		"content_pin": instance["content_pin"].duplicate(true),
		"terrain_interaction_pin": interaction_pin.duplicate(true),
		"shape_descriptor_version": int(descriptor["schema_version"]),
		"shape_descriptor_sha256": String(descriptor["descriptor_sha256"]),
		"algorithm": String(interaction["algorithm"]),
		"shape_source": String(interaction["shape_source"]),
		"operation": String(interaction["operation"]),
		"edit_order": String(interaction["edit_order"]),
		"blend_mode": BLEND_MODE,
		"embed_depth_mm": embed_depth_mm,
		"blend_radius_mm": int(interaction["blend_radius_mm"]),
		"anchor_world_mm": _vector3i_array(anchor_world_mm),
		"translation_mm": _vector3i_array(translation_mm),
		"rotation_mdeg": _vector3i_array(rotation_mdeg),
		"scale_milli": _vector3i_array(scale_milli),
		"world_planes": world_planes,
		"bounds_min": _vector3_array(minimum),
		"bounds_max": _vector3_array(maximum),
		"interior_point_world": _vector3_array(interior),
	}
	var checked := validate_effect(effect)
	if not checked.get("ok", false):
		return checked
	return {"ok": true, "effect": checked["effect"], "shape_descriptor": descriptor}


static func validate_effect(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("terrain_effect_not_dictionary")
	var effect: Dictionary = value
	if not _exact_keys(effect, EFFECT_KEYS):
		return _failure("terrain_effect_fields_invalid")
	if not _is_integer(effect["schema_version"]) or int(effect["schema_version"]) != SCHEMA_VERSION 		or effect["type"] != EFFECT_TYPE:
		return _failure("terrain_effect_schema_invalid")
	for key in [
		"effect_id", "source_instance_id", "source_fingerprint_sha256", "world_id",
		"definition_id", "shape_descriptor_sha256", "algorithm", "shape_source",
		"operation", "edit_order", "blend_mode"
	]:
		if typeof(effect[key]) != TYPE_STRING or String(effect[key]).is_empty():
			return _failure("terrain_effect_string_field_invalid")
	if String(effect["source_fingerprint_sha256"]).length() != 64 		or String(effect["shape_descriptor_sha256"]).length() != 64 		or not _is_hex(String(effect["source_fingerprint_sha256"])) 		or not _is_hex(String(effect["shape_descriptor_sha256"])):
		return _failure("terrain_effect_hash_invalid")
	if effect["algorithm"] != EFFECT_ALGORITHM or effect["shape_source"] != SHAPE_SOURCE 		or effect["operation"] != OPERATION or effect["edit_order"] != EDIT_ORDER 		or effect["blend_mode"] != BLEND_MODE:
		return _failure("terrain_effect_contract_invalid")
	if not _is_integer(effect["source_revision"]) or int(effect["source_revision"]) < 0 		or int(effect["source_revision"]) > MAX_SOURCE_REVISION:
		return _failure("terrain_effect_source_revision_invalid")
	if not _is_integer(effect["world_seed"]) or int(effect["world_seed"]) < 0 		or int(effect["world_seed"]) > MAX_WORLD_SEED 		or not _is_integer(effect["generator_version"]) or int(effect["generator_version"]) < 1:
		return _failure("terrain_effect_world_identity_invalid")
	if not _is_integer(effect["shape_descriptor_version"]) 		or int(effect["shape_descriptor_version"]) != ShapeDescriptor.DESCRIPTOR_VERSION:
		return _failure("terrain_effect_shape_version_invalid")
	if not _is_integer(effect["embed_depth_mm"]) or int(effect["embed_depth_mm"]) < 0 		or int(effect["embed_depth_mm"]) > 3000 		or not _is_integer(effect["blend_radius_mm"]) or int(effect["blend_radius_mm"]) < 0 		or int(effect["blend_radius_mm"]) > 2000:
		return _failure("terrain_effect_interaction_range_invalid")
	if typeof(effect["content_pin"]) != TYPE_DICTIONARY \
		or typeof(effect["terrain_interaction_pin"]) != TYPE_DICTIONARY:
		return _failure("terrain_effect_pin_invalid")
	var content_pin: Dictionary = effect["content_pin"]
	if not _exact_keys(content_pin, [
		"content_id", "mod_id", "mod_version", "definition_schema_version"
	]):
		return _failure("terrain_effect_content_pin_invalid")
	if String(content_pin["content_id"]) != String(effect["definition_id"]) \
		or typeof(content_pin["mod_id"]) != TYPE_STRING \
		or String(content_pin["mod_id"]).is_empty() \
		or typeof(content_pin["mod_version"]) != TYPE_STRING \
		or String(content_pin["mod_version"]).is_empty() \
		or not _is_integer(content_pin["definition_schema_version"]):
		return _failure("terrain_effect_content_pin_invalid")
	var interaction_pin: Dictionary = effect["terrain_interaction_pin"]
	if not _exact_keys(interaction_pin, [
		"rule_id", "definition_id", "mod_id", "mod_version", "rule_schema_version",
		"algorithm", "rule_sha256"
	]):
		return _failure("terrain_effect_interaction_pin_invalid")
	if String(interaction_pin["definition_id"]) != String(effect["definition_id"]) \
		or String(interaction_pin["algorithm"]) != EFFECT_ALGORITHM \
		or typeof(interaction_pin["rule_id"]) != TYPE_STRING \
		or String(interaction_pin["rule_id"]).is_empty() \
		or typeof(interaction_pin["mod_id"]) != TYPE_STRING \
		or String(interaction_pin["mod_id"]).is_empty() \
		or typeof(interaction_pin["mod_version"]) != TYPE_STRING \
		or String(interaction_pin["mod_version"]).is_empty() \
		or not _is_integer(interaction_pin["rule_schema_version"]) \
		or typeof(interaction_pin["rule_sha256"]) != TYPE_STRING \
		or String(interaction_pin["rule_sha256"]).length() != 64 \
		or not _is_hex(String(interaction_pin["rule_sha256"])):
		return _failure("terrain_effect_interaction_pin_invalid")
	var anchor := _read_int3(effect["anchor_world_mm"])
	var translation := _read_int3(effect["translation_mm"])
	var rotation := _read_int3(effect["rotation_mdeg"])
	var scale := _read_int3(effect["scale_milli"])
	if not anchor.get("ok", false) or not translation.get("ok", false) 		or not rotation.get("ok", false) or not scale.get("ok", false):
		return _failure("terrain_effect_transform_invalid")
	for component in scale["value"]:
		if int(component) <= 0 or int(component) > 5000:
			return _failure("terrain_effect_scale_invalid")
	var minimum := _read_float3(effect["bounds_min"])
	var maximum := _read_float3(effect["bounds_max"])
	var interior := _read_float3(effect["interior_point_world"])
	if not minimum.get("ok", false) or not maximum.get("ok", false) or not interior.get("ok", false):
		return _failure("terrain_effect_bounds_invalid")
	var min_v: Vector3 = minimum["value"]
	var max_v: Vector3 = maximum["value"]
	if min_v.x > max_v.x or min_v.y > max_v.y or min_v.z > max_v.z:
		return _failure("terrain_effect_bounds_invalid")
	var interior_v: Vector3 = interior["value"]
	if interior_v.x < min_v.x - 0.000001 or interior_v.x > max_v.x + 0.000001 \
		or interior_v.y < min_v.y - 0.000001 or interior_v.y > max_v.y + 0.000001 \
		or interior_v.z < min_v.z - 0.000001 or interior_v.z > max_v.z + 0.000001:
		return _failure("terrain_effect_interior_outside_bounds")
	if typeof(effect["world_planes"]) != TYPE_ARRAY 		or effect["world_planes"].is_empty() or effect["world_planes"].size() > MAX_PLANES:
		return _failure("terrain_effect_planes_invalid")
	for plane_value in effect["world_planes"]:
		if typeof(plane_value) != TYPE_DICTIONARY:
			return _failure("terrain_effect_plane_invalid")
		var plane: Dictionary = plane_value
		if not _exact_keys(plane, ["normal", "distance_m"]):
			return _failure("terrain_effect_plane_invalid")
		var normal_result := _read_float3(plane["normal"])
		if not normal_result.get("ok", false) \
			or not _is_number(plane["distance_m"]) \
			or not is_finite(float(plane["distance_m"])):
			return _failure("terrain_effect_plane_invalid")
		var normal: Vector3 = normal_result["value"]
		if absf(normal.length() - 1.0) > 0.00001:
			return _failure("terrain_effect_plane_normal_invalid")
	var normalized: Dictionary = effect.duplicate(true)
	normalized["schema_version"] = SCHEMA_VERSION
	normalized["source_revision"] = int(effect["source_revision"])
	normalized["world_seed"] = int(effect["world_seed"])
	normalized["generator_version"] = int(effect["generator_version"])
	normalized["shape_descriptor_version"] = int(effect["shape_descriptor_version"])
	normalized["embed_depth_mm"] = int(effect["embed_depth_mm"])
	normalized["blend_radius_mm"] = int(effect["blend_radius_mm"])
	normalized["anchor_world_mm"] = anchor["value"].duplicate()
	normalized["translation_mm"] = translation["value"].duplicate()
	normalized["rotation_mdeg"] = rotation["value"].duplicate()
	normalized["scale_milli"] = scale["value"].duplicate()

	var normalized_content_pin: Dictionary = content_pin.duplicate(true)
	normalized_content_pin["definition_schema_version"] = int(
		content_pin["definition_schema_version"]
	)
	normalized["content_pin"] = normalized_content_pin

	var normalized_interaction_pin: Dictionary = interaction_pin.duplicate(true)
	normalized_interaction_pin["rule_schema_version"] = int(
		interaction_pin["rule_schema_version"]
	)
	normalized["terrain_interaction_pin"] = normalized_interaction_pin

	normalized["bounds_min"] = _vector3_array(min_v)
	normalized["bounds_max"] = _vector3_array(max_v)
	normalized["interior_point_world"] = _vector3_array(interior_v)
	var normalized_planes: Array[Dictionary] = []
	for plane_value in effect["world_planes"]:
		var plane: Dictionary = plane_value
		var normal_result := _read_float3(plane["normal"])
		var normal: Vector3 = normal_result["value"]
		normalized_planes.append({
			"normal": _vector3_array(normal),
			"distance_m": _canonical_float(float(plane["distance_m"])),
		})
	normalized["world_planes"] = normalized_planes
	return {"ok": true, "effect": normalized}


static func sample_cutter(effect: Dictionary, world_point: Vector3) -> float:
	if not world_point.is_finite():
		return INF
	var checked := validate_effect(effect)
	if not checked.get("ok", false):
		return INF
	return sample_cutter_prevalidated(effect, world_point)


## Hot-path evaluator for effects already validated by a snapshot/index boundary.
## Phase D must never feed unvalidated external dictionaries into this method.
static func sample_cutter_prevalidated(
	effect: Dictionary,
	world_point: Vector3
) -> float:
	if not world_point.is_finite():
		return INF
	var maximum_plane_delta := -INF
	for plane_value in effect["world_planes"]:
		var plane: Dictionary = plane_value
		var n := _array_to_vector3(plane["normal"])
		maximum_plane_delta = maxf(
			maximum_plane_delta,
			n.dot(world_point) - float(plane["distance_m"])
		)
	return maximum_plane_delta


static func compose_density(
	terrain_density: float,
	effect: Dictionary,
	world_point: Vector3
) -> float:
	if not is_finite(terrain_density):
		return terrain_density
	var checked := validate_effect(effect)
	if not checked.get("ok", false):
		return terrain_density
	return compose_density_prevalidated(terrain_density, effect, world_point)


static func compose_density_prevalidated(
	terrain_density: float,
	effect: Dictionary,
	world_point: Vector3
) -> float:
	if not is_finite(terrain_density):
		return terrain_density
	var cutter := sample_cutter_prevalidated(effect, world_point)
	if not is_finite(cutter) or cutter >= 0.0:
		return terrain_density
	var hard := minf(terrain_density, cutter)
	var radius := float(effect["blend_radius_mm"]) / 1000.0
	if radius <= 0.0 or -cutter >= radius:
		return hard
	var u := clampf((-cutter) / radius, 0.0, 1.0)
	var weight := u * u * (3.0 - 2.0 * u)
	return lerpf(terrain_density, hard, weight)


static func compose_effects(
	terrain_density: float,
	effects: Array[Dictionary],
	world_point: Vector3
) -> float:
	if not is_finite(terrain_density):
		return terrain_density
	for effect in effects:
		if not validate_effect(effect).get("ok", false):
			return terrain_density
	return compose_effects_prevalidated(terrain_density, effects, world_point)


## Multiple imprints are ordered by stable effect_id. This makes overlap replay
## independent of discovery/visit order while avoiding validation inside every
## lattice sample after the snapshot boundary has qualified its records.
static func compose_effects_prevalidated(
	terrain_density: float,
	effects: Array[Dictionary],
	world_point: Vector3
) -> float:
	if not is_finite(terrain_density):
		return terrain_density
	var ordered := effects.duplicate(false)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["effect_id"]) < String(b["effect_id"])
	)
	var density := terrain_density
	for effect in ordered:
		density = compose_density_prevalidated(density, effect, world_point)
	return density


static func bounds(effect: Dictionary) -> Dictionary:
	var checked := validate_effect(effect)
	if not checked.get("ok", false):
		return checked
	return {
		"ok": true,
		"min": _array_to_vector3(effect["bounds_min"]),
		"max": _array_to_vector3(effect["bounds_max"]),
	}


static func _validate_instance_input(instance: Dictionary, source_revision: int) -> Dictionary:
	for key in [
		"instance_id", "definition_id", "content_pin", "world_id", "world_seed",
		"generator_version", "region_key", "position_mm", "default_scale_milli",
		"default_yaw_mdeg", "geometry", "geometry_seeds", "terrain_interaction",
		"terrain_interaction_pin"
	]:
		if not instance.has(key):
			return _failure("terrain_effect_instance_field_missing:%s" % key)
	if String(instance["instance_id"]).is_empty() or String(instance["definition_id"]).is_empty() 		or String(instance["world_id"]).is_empty():
		return _failure("terrain_effect_instance_identity_invalid")
	if not _is_integer(source_revision) or source_revision < 0 or source_revision > MAX_SOURCE_REVISION:
		return _failure("terrain_effect_source_revision_invalid")
	if not _is_integer(instance["world_seed"]) or int(instance["world_seed"]) < 0 		or int(instance["world_seed"]) > MAX_WORLD_SEED 		or not _is_integer(instance["generator_version"]) or int(instance["generator_version"]) < 1:
		return _failure("terrain_effect_instance_world_invalid")
	if not instance["region_key"] is Vector2i or not instance["position_mm"] is Vector3i 		or not instance["default_scale_milli"] is Vector3i 		or not _is_integer(instance["default_yaw_mdeg"]):
		return _failure("terrain_effect_instance_transform_invalid")
	if typeof(instance["geometry"]) != TYPE_DICTIONARY 		or typeof(instance["geometry_seeds"]) != TYPE_DICTIONARY 		or typeof(instance["content_pin"]) != TYPE_DICTIONARY 		or typeof(instance["terrain_interaction"]) != TYPE_DICTIONARY 		or typeof(instance["terrain_interaction_pin"]) != TYPE_DICTIONARY:
		return _failure("terrain_effect_instance_payload_invalid")
	var interaction: Dictionary = instance["terrain_interaction"]
	if interaction.is_empty():
		return _failure("terrain_effect_interaction_missing")
	for key in [
		"schema_version", "type", "id", "definition_id", "algorithm", "shape_source",
		"operation", "embed_depth_mm", "blend_radius_mm", "edit_order"
	]:
		if not interaction.has(key):
			return _failure("terrain_effect_interaction_invalid")
	if String(interaction["definition_id"]) != String(instance["definition_id"]) 		or interaction["algorithm"] != EFFECT_ALGORITHM 		or interaction["shape_source"] != SHAPE_SOURCE 		or interaction["operation"] != OPERATION 		or interaction["edit_order"] != EDIT_ORDER:
		return _failure("terrain_effect_interaction_contract_invalid")
	var pin: Dictionary = instance["terrain_interaction_pin"]
	for key in [
		"rule_id", "definition_id", "mod_id", "mod_version", "rule_schema_version",
		"algorithm", "rule_sha256"
	]:
		if not pin.has(key):
			return _failure("terrain_effect_interaction_pin_invalid")
	var interaction_sha := JSON.stringify(interaction, "", true, true).sha256_text()
	if String(pin["definition_id"]) != String(instance["definition_id"]) 		or String(pin["rule_id"]) != String(interaction["id"]) 		or String(pin["algorithm"]) != EFFECT_ALGORITHM 		or String(pin["rule_sha256"]) != interaction_sha:
		return _failure("terrain_effect_interaction_pin_mismatch")
	return {"ok": true}


static func _resolve_transform(instance: Dictionary) -> Dictionary:
	var region_key: Vector2i = instance["region_key"]
	var local_position_mm: Vector3i = instance["position_mm"]
	var region_size_x_mm := roundi(Spatial.REGION_SIZE_X * 1000.0)
	var region_size_z_mm := roundi(Spatial.REGION_SIZE_Z * 1000.0)
	var anchor_world_mm := Vector3i(
		region_key.x * region_size_x_mm + local_position_mm.x,
		local_position_mm.y,
		region_key.y * region_size_z_mm + local_position_mm.z
	)
	var anchor_world := Vector3(anchor_world_mm) / 1000.0
	if instance.has("world_position_mm"):
		if not instance["world_position_mm"] is Vector3i 			or Vector3i(instance["world_position_mm"]) != anchor_world_mm:
			return _failure("terrain_effect_world_anchor_mismatch")
	var translation_mm := Vector3i.ZERO
	var rotation_mdeg := Vector3i(0, int(instance["default_yaw_mdeg"]), 0)
	var scale_milli: Vector3i = instance["default_scale_milli"]
	var components: Dictionary = instance.get("instance_components", {})
	var transform_component: Dictionary = components.get("core.transform", {})
	if not transform_component.is_empty():
		var properties: Dictionary = transform_component.get("properties", {})
		var translation_result := _read_int3(properties.get("translation_mm"))
		var rotation_result := _read_int3(properties.get("rotation_mdeg"))
		var scale_result := _read_int3(properties.get("scale_milli"))
		if not translation_result.get("ok", false) 			or not rotation_result.get("ok", false) 			or not scale_result.get("ok", false):
			return _failure("terrain_effect_component_transform_invalid")
		translation_mm = translation_result["vector3i"]
		rotation_mdeg = rotation_result["vector3i"]
		scale_milli = scale_result["vector3i"]
	for component in [scale_milli.x, scale_milli.y, scale_milli.z]:
		if component < 100 or component > 5000:
			return _failure("terrain_effect_scale_invalid")
	return {
		"ok": true,
		"anchor_world_mm": anchor_world_mm,
		"translation_mm": translation_mm,
		"rotation_mdeg": rotation_mdeg,
		"scale_milli": scale_milli,
	}


static func _read_int3(value: Variant) -> Dictionary:
	if value is Vector3i:
		var vector: Vector3i = value
		return {
			"ok": true,
			"value": [vector.x, vector.y, vector.z],
			"vector3i": vector,
		}
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"ok": false}
	var parsed: Array[int] = []
	for component in value:
		if not _is_integer(component) or abs(float(component)) > 2147483647.0:
			return {"ok": false}
		parsed.append(int(component))
	return {
		"ok": true,
		"value": parsed,
		"vector3i": Vector3i(parsed[0], parsed[1], parsed[2]),
	}


static func _read_float3(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"ok": false}
	var parsed: Array[float] = []
	for component in value:
		if not (typeof(component) == TYPE_FLOAT or typeof(component) == TYPE_INT) 			or not is_finite(float(component)):
			return {"ok": false}
		parsed.append(float(component))
	return {
		"ok": true,
		"value": Vector3(parsed[0], parsed[1], parsed[2]),
	}


static func _vector3i_array(value: Vector3i) -> Array[int]:
	return [value.x, value.y, value.z]


static func _vector3_array(value: Vector3) -> Array[float]:
	return [
		_canonical_float(value.x),
		_canonical_float(value.y),
		_canonical_float(value.z),
	]


static func _canonical_float(value: float) -> float:
	# Godot's JSON parser/stringifier may shift the final binary digit of a
	# double across a round-trip. Twelve decimal places are far below terrain
	# sampling resolution while making validate->serialize->parse->validate
	# idempotent.
	return String.num(value, 12).to_float()


static func _array_to_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and floor(float(value)) == float(value)
		and abs(float(value)) <= 9007199254740991.0
	)


static func _is_hex(value: String) -> bool:
	if value.is_empty():
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
