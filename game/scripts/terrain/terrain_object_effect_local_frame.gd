class_name TerrainObjectEffectLocalFrame
extends RefCounted

## Precision-safe terrain-object effect frame.
##
## This record never stores or reconstructs a global floating-point position.
## Horizontal position is represented as an integer region key plus bounded
## region-local metric coordinates. Query conversion uses only a bounded integer
## region delta after spatial indexing has established locality.
const ShapeDescriptor := preload("res://scripts/objects/procedural_rock_shape_descriptor.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

const SCHEMA_VERSION := 1
const FRAME_TYPE := "terrain_object_effect_local_frame_v1"
const EFFECT_ALGORITHM := "sdf_ground_imprint_v1"
const SHAPE_SOURCE := "recipe_envelope_v1"
const OPERATION := "subtract_solid_v1"
const EDIT_ORDER := "terrain_edits_then_imprint_v1"
const BLEND_MODE := "interior_smooth_subtract_v1"
const MAX_SOURCE_REVISION := 9007199254740991
const MAX_WORLD_SEED := 2147483646
const MAX_PLANES := 64
const MAX_QUERY_REGION_DELTA := 128
const REGION_SIZE_X_MM := 16000
const REGION_SIZE_Z_MM := 12000
const REGION_SIZE_X_M := 16.0
const REGION_SIZE_Z_M := 12.0

const FRAME_KEYS := [
	"schema_version", "type", "effect_id", "source_instance_id", "source_revision",
	"source_fingerprint_sha256", "world_id", "world_seed", "generator_version",
	"definition_id", "content_pin", "terrain_interaction_pin",
	"shape_descriptor_version", "shape_descriptor_sha256", "algorithm",
	"shape_source", "operation", "edit_order", "blend_mode",
	"embed_depth_mm", "blend_radius_mm", "source_region_key", "frame_region_key",
	"frame_origin_local_mm", "translation_mm", "rotation_mdeg", "scale_milli",
	"local_planes", "bounds_min_local", "bounds_max_local", "interior_point_local"
]


static func build_from_instance(instance: Dictionary, source_revision: int = 0) -> Dictionary:
	var input := _validate_instance_input(instance, source_revision)
	if not input.get("ok", false):
		return input
	var descriptor := ShapeDescriptor.build(instance["geometry"], instance["geometry_seeds"])
	if not descriptor.get("ok", false):
		return _failure(
			"terrain_effect_local_frame_shape_failed:%s" % descriptor.get("reason", "unknown")
		)
	var transform := _resolve_local_transform(instance)
	if not transform.get("ok", false):
		return transform

	var frame_region_key: Vector2i = transform["frame_region_key"]
	var frame_origin_local_mm: Array = transform["frame_origin_local_mm"]
	var rotation_mdeg: Array = transform["rotation_mdeg"]
	var scale_milli: Array = transform["scale_milli"]
	var embed_depth_mm := int(instance["terrain_interaction"]["embed_depth_mm"])
	var effect_origin_local := Vector3(
		float(frame_origin_local_mm[0]) / 1000.0,
		float(frame_origin_local_mm[1] - embed_depth_mm) / 1000.0,
		float(frame_origin_local_mm[2]) / 1000.0
	)
	var rotation_radians := Vector3(
		float(rotation_mdeg[0]), float(rotation_mdeg[1]), float(rotation_mdeg[2])
	) * (PI / 180000.0)
	var basis := Basis.from_euler(rotation_radians)
	var scale := Vector3(
		float(scale_milli[0]), float(scale_milli[1]), float(scale_milli[2])
	) / 1000.0
	if scale.x <= 0.0 or scale.y <= 0.0 or scale.z <= 0.0:
		return _failure("terrain_effect_local_frame_scale_invalid")

	var local_guard := float(descriptor["roughness_guard_m"])
	var local_planes: Array[Dictionary] = []
	for plane_value in descriptor["planes"]:
		var plane: Dictionary = plane_value
		var local_normal: Vector3 = plane["normal"]
		var scaled_normal := Vector3(
			local_normal.x / scale.x,
			local_normal.y / scale.y,
			local_normal.z / scale.z
		)
		var frame_unnormalized: Vector3 = basis * scaled_normal
		var normal_length := frame_unnormalized.length()
		if not is_finite(normal_length) or normal_length <= 0.000000001:
			return _failure("terrain_effect_local_frame_plane_transform_invalid")
		var frame_normal := frame_unnormalized / normal_length
		var local_distance := float(plane["distance"]) + local_guard
		var frame_distance := (
			local_distance / normal_length
			+ frame_normal.dot(effect_origin_local)
		)
		local_planes.append({
			"normal": _vector3_array(frame_normal),
			"distance_m": _canonical_float(frame_distance),
		})
	if local_planes.is_empty() or local_planes.size() > MAX_PLANES:
		return _failure("terrain_effect_local_frame_plane_budget_invalid")

	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var interior := Vector3.ZERO
	var guarded_vertices: Array[Vector3] = descriptor["guarded_vertices"]
	for local_vertex in guarded_vertices:
		var frame_vertex := effect_origin_local + basis * (local_vertex * scale)
		minimum = minimum.min(frame_vertex)
		maximum = maximum.max(frame_vertex)
		interior += frame_vertex
	if guarded_vertices.is_empty() or not minimum.is_finite() or not maximum.is_finite():
		return _failure("terrain_effect_local_frame_bounds_invalid")
	interior /= float(guarded_vertices.size())

	var world_id := String(instance["world_id"])
	var source_id := String(instance["instance_id"])
	var effect_identity_source := JSON.stringify({
		"schema_version": 1,
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
		"source_region_key": _int2(instance["region_key"]),
		"content_pin": instance["content_pin"],
		"terrain_interaction_pin": instance["terrain_interaction_pin"],
		"shape_descriptor_sha256": descriptor["descriptor_sha256"],
		"frame_region_key": _int2(frame_region_key),
		"frame_origin_local_mm": frame_origin_local_mm,
		"translation_mm": transform["translation_mm"],
		"rotation_mdeg": rotation_mdeg,
		"scale_milli": scale_milli,
		"embed_depth_mm": embed_depth_mm,
		"blend_radius_mm": int(instance["terrain_interaction"]["blend_radius_mm"]),
	}, "", true, true).sha256_text()

	var frame := {
		"schema_version": SCHEMA_VERSION,
		"type": FRAME_TYPE,
		"effect_id": effect_id,
		"source_instance_id": source_id,
		"source_revision": source_revision,
		"source_fingerprint_sha256": source_fingerprint,
		"world_id": world_id,
		"world_seed": int(instance["world_seed"]),
		"generator_version": int(instance["generator_version"]),
		"definition_id": String(instance["definition_id"]),
		"content_pin": instance["content_pin"].duplicate(true),
		"terrain_interaction_pin": instance["terrain_interaction_pin"].duplicate(true),
		"shape_descriptor_version": int(descriptor["schema_version"]),
		"shape_descriptor_sha256": String(descriptor["descriptor_sha256"]),
		"algorithm": String(instance["terrain_interaction"]["algorithm"]),
		"shape_source": String(instance["terrain_interaction"]["shape_source"]),
		"operation": String(instance["terrain_interaction"]["operation"]),
		"edit_order": String(instance["terrain_interaction"]["edit_order"]),
		"blend_mode": BLEND_MODE,
		"embed_depth_mm": embed_depth_mm,
		"blend_radius_mm": int(instance["terrain_interaction"]["blend_radius_mm"]),
		"source_region_key": _int2(instance["region_key"]),
		"frame_region_key": _int2(frame_region_key),
		"frame_origin_local_mm": frame_origin_local_mm,
		"translation_mm": transform["translation_mm"],
		"rotation_mdeg": rotation_mdeg,
		"scale_milli": scale_milli,
		"local_planes": local_planes,
		"bounds_min_local": _vector3_array(minimum),
		"bounds_max_local": _vector3_array(maximum),
		"interior_point_local": _vector3_array(interior),
	}
	var checked := validate_frame(frame)
	if not checked.get("ok", false):
		return checked
	return {
		"ok": true,
		"frame": checked["frame"],
		"shape_descriptor": descriptor,
	}


static func validate_frame(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("terrain_effect_local_frame_not_dictionary")
	var frame: Dictionary = value
	if not _exact_keys(frame, FRAME_KEYS):
		return _failure("terrain_effect_local_frame_fields_invalid")
	if not _is_integer(frame["schema_version"]) 		or int(frame["schema_version"]) != SCHEMA_VERSION 		or frame["type"] != FRAME_TYPE:
		return _failure("terrain_effect_local_frame_schema_invalid")
	for key in [
		"effect_id", "source_instance_id", "source_fingerprint_sha256", "world_id",
		"definition_id", "shape_descriptor_sha256", "algorithm", "shape_source",
		"operation", "edit_order", "blend_mode"
	]:
		if typeof(frame[key]) != TYPE_STRING or String(frame[key]).is_empty():
			return _failure("terrain_effect_local_frame_string_invalid")
	if String(frame["source_fingerprint_sha256"]).length() != 64 		or String(frame["shape_descriptor_sha256"]).length() != 64 		or not _is_hex(String(frame["source_fingerprint_sha256"])) 		or not _is_hex(String(frame["shape_descriptor_sha256"])):
		return _failure("terrain_effect_local_frame_hash_invalid")
	if frame["algorithm"] != EFFECT_ALGORITHM 		or frame["shape_source"] != SHAPE_SOURCE 		or frame["operation"] != OPERATION 		or frame["edit_order"] != EDIT_ORDER 		or frame["blend_mode"] != BLEND_MODE:
		return _failure("terrain_effect_local_frame_contract_invalid")
	if not _is_integer(frame["source_revision"]) 		or int(frame["source_revision"]) < 0 		or int(frame["source_revision"]) > MAX_SOURCE_REVISION:
		return _failure("terrain_effect_local_frame_revision_invalid")
	if not _is_integer(frame["world_seed"]) 		or int(frame["world_seed"]) < 0 		or int(frame["world_seed"]) > MAX_WORLD_SEED 		or not _is_integer(frame["generator_version"]) 		or int(frame["generator_version"]) < 1:
		return _failure("terrain_effect_local_frame_world_invalid")
	if not _is_integer(frame["shape_descriptor_version"]) 		or int(frame["shape_descriptor_version"]) != ShapeDescriptor.DESCRIPTOR_VERSION:
		return _failure("terrain_effect_local_frame_shape_version_invalid")
	if not _is_integer(frame["embed_depth_mm"]) 		or int(frame["embed_depth_mm"]) < 0 		or int(frame["embed_depth_mm"]) > 3000 		or not _is_integer(frame["blend_radius_mm"]) 		or int(frame["blend_radius_mm"]) < 0 		or int(frame["blend_radius_mm"]) > 2000:
		return _failure("terrain_effect_local_frame_interaction_range_invalid")

	var source_region := _read_int2(frame["source_region_key"])
	var frame_region := _read_int2(frame["frame_region_key"])
	var origin := _read_int3(frame["frame_origin_local_mm"])
	var translation := _read_int3(frame["translation_mm"])
	var rotation := _read_int3(frame["rotation_mdeg"])
	var scale := _read_int3(frame["scale_milli"])
	if not source_region.get("ok", false) or not frame_region.get("ok", false) 		or not origin.get("ok", false) or not translation.get("ok", false) 		or not rotation.get("ok", false) or not scale.get("ok", false):
		return _failure("terrain_effect_local_frame_transform_invalid")
	var origin_values: Array = origin["value"]
	if int(origin_values[0]) < 0 or int(origin_values[0]) >= REGION_SIZE_X_MM 		or int(origin_values[2]) < 0 or int(origin_values[2]) >= REGION_SIZE_Z_MM:
		return _failure("terrain_effect_local_frame_origin_not_normalized")
	for component in scale["value"]:
		if int(component) <= 0 or int(component) > 5000:
			return _failure("terrain_effect_local_frame_scale_invalid")

	if typeof(frame["content_pin"]) != TYPE_DICTIONARY 		or typeof(frame["terrain_interaction_pin"]) != TYPE_DICTIONARY:
		return _failure("terrain_effect_local_frame_pin_invalid")
	var content_pin: Dictionary = frame["content_pin"]
	var interaction_pin: Dictionary = frame["terrain_interaction_pin"]
	if not _exact_keys(content_pin, [
		"content_id", "mod_id", "mod_version", "definition_schema_version"
	]) or not _exact_keys(interaction_pin, [
		"rule_id", "definition_id", "mod_id", "mod_version", "rule_schema_version",
		"algorithm", "rule_sha256"
	]):
		return _failure("terrain_effect_local_frame_pin_invalid")
	if String(content_pin["content_id"]) != String(frame["definition_id"]) 		or String(interaction_pin["definition_id"]) != String(frame["definition_id"]) 		or String(interaction_pin["algorithm"]) != EFFECT_ALGORITHM:
		return _failure("terrain_effect_local_frame_pin_mismatch")

	var minimum := _read_float3(frame["bounds_min_local"])
	var maximum := _read_float3(frame["bounds_max_local"])
	var interior := _read_float3(frame["interior_point_local"])
	if not minimum.get("ok", false) or not maximum.get("ok", false) 		or not interior.get("ok", false):
		return _failure("terrain_effect_local_frame_bounds_invalid")
	var min_v: Vector3 = minimum["vector"]
	var max_v: Vector3 = maximum["vector"]
	var interior_v: Vector3 = interior["vector"]
	if min_v.x > max_v.x or min_v.y > max_v.y or min_v.z > max_v.z:
		return _failure("terrain_effect_local_frame_bounds_invalid")
	if interior_v.x < min_v.x - 0.000001 or interior_v.x > max_v.x + 0.000001 		or interior_v.y < min_v.y - 0.000001 or interior_v.y > max_v.y + 0.000001 		or interior_v.z < min_v.z - 0.000001 or interior_v.z > max_v.z + 0.000001:
		return _failure("terrain_effect_local_frame_interior_invalid")
	if typeof(frame["local_planes"]) != TYPE_ARRAY 		or frame["local_planes"].is_empty() 		or frame["local_planes"].size() > MAX_PLANES:
		return _failure("terrain_effect_local_frame_planes_invalid")
	var normalized_planes: Array[Dictionary] = []
	for plane_value in frame["local_planes"]:
		if typeof(plane_value) != TYPE_DICTIONARY:
			return _failure("terrain_effect_local_frame_plane_invalid")
		var plane: Dictionary = plane_value
		if not _exact_keys(plane, ["normal", "distance_m"]):
			return _failure("terrain_effect_local_frame_plane_invalid")
		var normal_result := _read_float3(plane["normal"])
		if not normal_result.get("ok", false) 			or not _is_number(plane["distance_m"]) 			or not is_finite(float(plane["distance_m"])):
			return _failure("terrain_effect_local_frame_plane_invalid")
		var normal: Vector3 = normal_result["vector"]
		if absf(normal.length() - 1.0) > 0.00001:
			return _failure("terrain_effect_local_frame_plane_normal_invalid")
		normalized_planes.append({
			"normal": _vector3_array(normal),
			"distance_m": _canonical_float(float(plane["distance_m"])),
		})

	var normalized := frame.duplicate(true)
	normalized["schema_version"] = SCHEMA_VERSION
	normalized["source_revision"] = int(frame["source_revision"])
	normalized["world_seed"] = int(frame["world_seed"])
	normalized["generator_version"] = int(frame["generator_version"])
	normalized["shape_descriptor_version"] = int(frame["shape_descriptor_version"])
	normalized["embed_depth_mm"] = int(frame["embed_depth_mm"])
	normalized["blend_radius_mm"] = int(frame["blend_radius_mm"])
	normalized["source_region_key"] = source_region["value"]
	normalized["frame_region_key"] = frame_region["value"]
	normalized["frame_origin_local_mm"] = origin["value"]
	normalized["translation_mm"] = translation["value"]
	normalized["rotation_mdeg"] = rotation["value"]
	normalized["scale_milli"] = scale["value"]
	normalized["bounds_min_local"] = _vector3_array(min_v)
	normalized["bounds_max_local"] = _vector3_array(max_v)
	normalized["interior_point_local"] = _vector3_array(interior_v)
	normalized["local_planes"] = normalized_planes
	var normalized_content_pin := content_pin.duplicate(true)
	normalized_content_pin["definition_schema_version"] = int(
		content_pin["definition_schema_version"]
	)
	normalized["content_pin"] = normalized_content_pin
	var normalized_interaction_pin := interaction_pin.duplicate(true)
	normalized_interaction_pin["rule_schema_version"] = int(
		interaction_pin["rule_schema_version"]
	)
	normalized["terrain_interaction_pin"] = normalized_interaction_pin
	return {"ok": true, "frame": normalized}


static func sample_cutter(
	frame: Dictionary,
	query_region_key: Vector2i,
	query_local_position: Vector3
) -> float:
	var checked := validate_frame(frame)
	if not checked.get("ok", false):
		return INF
	return sample_cutter_prevalidated(
		checked["frame"], query_region_key, query_local_position
	)


static func sample_cutter_prevalidated(
	frame: Dictionary,
	query_region_key: Vector2i,
	query_local_position: Vector3
) -> float:
	if not query_local_position.is_finite():
		return INF
	var frame_region_values: Array = frame["frame_region_key"]
	var frame_region := Vector2i(
		int(frame_region_values[0]), int(frame_region_values[1])
	)
	var delta := query_region_key - frame_region
	if absi(delta.x) > MAX_QUERY_REGION_DELTA 		or absi(delta.y) > MAX_QUERY_REGION_DELTA:
		return INF
	var point_in_frame := Vector3(
		float(delta.x) * REGION_SIZE_X_M + query_local_position.x,
		query_local_position.y,
		float(delta.y) * REGION_SIZE_Z_M + query_local_position.z
	)
	var maximum_plane_delta := -INF
	for plane_value in frame["local_planes"]:
		var plane: Dictionary = plane_value
		var normal := _array_to_vector3(plane["normal"])
		maximum_plane_delta = maxf(
			maximum_plane_delta,
			normal.dot(point_in_frame) - float(plane["distance_m"])
		)
	return maximum_plane_delta


static func compose_density_prevalidated(
	terrain_density: float,
	frame: Dictionary,
	query_region_key: Vector2i,
	query_local_position: Vector3
) -> float:
	if not is_finite(terrain_density):
		return terrain_density
	var cutter := sample_cutter_prevalidated(
		frame, query_region_key, query_local_position
	)
	if not is_finite(cutter) or cutter >= 0.0:
		return terrain_density
	var hard := minf(terrain_density, cutter)
	var radius := float(frame["blend_radius_mm"]) / 1000.0
	if radius <= 0.0 or -cutter >= radius:
		return hard
	var u := clampf((-cutter) / radius, 0.0, 1.0)
	var weight := u * u * (3.0 - 2.0 * u)
	return lerpf(terrain_density, hard, weight)


static func compose_frames_prevalidated(
	terrain_density: float,
	frames: Array,
	query_region_key: Vector2i,
	query_local_position: Vector3
) -> float:
	if not is_finite(terrain_density):
		return terrain_density
	# Projection/local-index snapshots already emit frames in stable effect_id
	# order. Re-sorting here would execute once per SDF sample and dominate mesh
	# generation cost.
	var density := terrain_density
	for frame_value in frames:
		if typeof(frame_value) != TYPE_DICTIONARY:
			continue
		density = compose_density_prevalidated(
			density,
			frame_value,
			query_region_key,
			query_local_position
		)
	return density


static func bounds_local(frame: Dictionary) -> Dictionary:
	var checked := validate_frame(frame)
	if not checked.get("ok", false):
		return checked
	return {
		"ok": true,
		"frame_region_key": Vector2i(
			int(frame["frame_region_key"][0]),
			int(frame["frame_region_key"][1])
		),
		"min": _array_to_vector3(frame["bounds_min_local"]),
		"max": _array_to_vector3(frame["bounds_max_local"]),
	}


static func _resolve_local_transform(instance: Dictionary) -> Dictionary:
	var source_region: Vector2i = instance["region_key"]
	var position_mm: Vector3i = instance["position_mm"]
	var translation := Vector3i.ZERO
	var rotation := Vector3i(0, int(instance["default_yaw_mdeg"]), 0)
	var scale: Vector3i = instance["default_scale_milli"]
	var components: Dictionary = instance.get("instance_components", {})
	var transform_component: Dictionary = components.get("core.transform", {})
	if not transform_component.is_empty():
		var properties: Dictionary = transform_component.get("properties", {})
		var translation_result := _read_int3(properties.get("translation_mm"))
		var rotation_result := _read_int3(properties.get("rotation_mdeg"))
		var scale_result := _read_int3(properties.get("scale_milli"))
		if not translation_result.get("ok", false) 			or not rotation_result.get("ok", false) 			or not scale_result.get("ok", false):
			return _failure("terrain_effect_local_frame_component_transform_invalid")
		translation = Vector3i(
			int(translation_result["value"][0]),
			int(translation_result["value"][1]),
			int(translation_result["value"][2])
		)
		rotation = Vector3i(
			int(rotation_result["value"][0]),
			int(rotation_result["value"][1]),
			int(rotation_result["value"][2])
		)
		scale = Vector3i(
			int(scale_result["value"][0]),
			int(scale_result["value"][1]),
			int(scale_result["value"][2])
		)
	for component in [scale.x, scale.y, scale.z]:
		if component < 100 or component > 5000:
			return _failure("terrain_effect_local_frame_scale_invalid")

	var total_x_mm: int = int(position_mm.x) + int(translation.x)
	var total_z_mm: int = int(position_mm.z) + int(translation.z)
	var region_dx := _floor_divide(total_x_mm, REGION_SIZE_X_MM)
	var region_dz := _floor_divide(total_z_mm, REGION_SIZE_Z_MM)
	var frame_region := Vector2i(
		source_region.x + region_dx,
		source_region.y + region_dz
	)
	var local_x_mm := total_x_mm - region_dx * REGION_SIZE_X_MM
	var local_z_mm := total_z_mm - region_dz * REGION_SIZE_Z_MM
	return {
		"ok": true,
		"frame_region_key": frame_region,
		"frame_origin_local_mm": [
			local_x_mm,
			int(position_mm.y) + int(translation.y),
			local_z_mm,
		],
		"translation_mm": [translation.x, translation.y, translation.z],
		"rotation_mdeg": [rotation.x, rotation.y, rotation.z],
		"scale_milli": [scale.x, scale.y, scale.z],
	}


static func _validate_instance_input(
	instance: Dictionary,
	source_revision: int
) -> Dictionary:
	for key in [
		"instance_id", "definition_id", "content_pin", "world_id", "world_seed",
		"generator_version", "region_key", "position_mm", "default_scale_milli",
		"default_yaw_mdeg", "geometry", "geometry_seeds", "terrain_interaction",
		"terrain_interaction_pin"
	]:
		if not instance.has(key):
			return _failure(
				"terrain_effect_local_frame_instance_field_missing:%s" % key
			)
	if String(instance["instance_id"]).is_empty() 		or String(instance["definition_id"]).is_empty() 		or String(instance["world_id"]).is_empty():
		return _failure("terrain_effect_local_frame_instance_identity_invalid")
	if not _is_integer(source_revision) or source_revision < 0 		or source_revision > MAX_SOURCE_REVISION:
		return _failure("terrain_effect_local_frame_revision_invalid")
	if not instance["region_key"] is Vector2i 		or not instance["position_mm"] is Vector3i 		or not instance["default_scale_milli"] is Vector3i 		or not _is_integer(instance["default_yaw_mdeg"]):
		return _failure("terrain_effect_local_frame_instance_transform_invalid")
	if typeof(instance["geometry"]) != TYPE_DICTIONARY 		or typeof(instance["geometry_seeds"]) != TYPE_DICTIONARY 		or typeof(instance["content_pin"]) != TYPE_DICTIONARY 		or typeof(instance["terrain_interaction"]) != TYPE_DICTIONARY 		or typeof(instance["terrain_interaction_pin"]) != TYPE_DICTIONARY:
		return _failure("terrain_effect_local_frame_instance_payload_invalid")
	var interaction: Dictionary = instance["terrain_interaction"]
	if interaction.is_empty() 		or interaction.get("algorithm") != EFFECT_ALGORITHM 		or interaction.get("shape_source") != SHAPE_SOURCE 		or interaction.get("operation") != OPERATION 		or interaction.get("edit_order") != EDIT_ORDER 		or String(interaction.get("definition_id", "")) 			!= String(instance["definition_id"]):
		return _failure("terrain_effect_local_frame_interaction_invalid")
	var pin: Dictionary = instance["terrain_interaction_pin"]
	var interaction_sha := JSON.stringify(interaction, "", true, true).sha256_text()
	if String(pin.get("definition_id", "")) != String(instance["definition_id"]) 		or String(pin.get("rule_id", "")) != String(interaction.get("id", "")) 		or String(pin.get("algorithm", "")) != EFFECT_ALGORITHM 		or String(pin.get("rule_sha256", "")) != interaction_sha:
		return _failure("terrain_effect_local_frame_interaction_pin_mismatch")
	return {"ok": true}


static func _read_int2(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return {"ok": false}
	var parsed: Array[int] = []
	for component in value:
		if not _is_integer(component) 			or abs(float(component)) > 2147483647.0:
			return {"ok": false}
		parsed.append(int(component))
	return {"ok": true, "value": parsed}


static func _read_int3(value: Variant) -> Dictionary:
	if value is Vector3i:
		return {
			"ok": true,
			"value": [value.x, value.y, value.z],
		}
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"ok": false}
	var parsed: Array[int] = []
	for component in value:
		if not _is_integer(component) 			or abs(float(component)) > 2147483647.0:
			return {"ok": false}
		parsed.append(int(component))
	return {"ok": true, "value": parsed}


static func _read_float3(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"ok": false}
	var parsed: Array[float] = []
	for component in value:
		if not _is_number(component) or not is_finite(float(component)):
			return {"ok": false}
		parsed.append(float(component))
	return {
		"ok": true,
		"vector": Vector3(parsed[0], parsed[1], parsed[2]),
	}


static func _int2(value: Vector2i) -> Array[int]:
	return [value.x, value.y]


static func _vector3_array(value: Vector3) -> Array[float]:
	return [
		_canonical_float(value.x),
		_canonical_float(value.y),
		_canonical_float(value.z),
	]


static func _array_to_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _canonical_float(value: float) -> float:
	return String.num(value, 12).to_float()


static func _floor_divide(value: int, divisor: int) -> int:
	var quotient: int = value / divisor
	if value < 0 and value % divisor != 0:
		quotient -= 1
	return quotient


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
