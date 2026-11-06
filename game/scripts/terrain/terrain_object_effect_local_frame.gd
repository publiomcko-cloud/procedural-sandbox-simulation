class_name TerrainObjectEffectLocalFrame
extends RefCounted

## Precision-safe sampling frame for terrain-object effects.
##
## Every continuous coordinate is expressed relative to the source region.
## Query conversion uses integer region-key deltas before multiplying by the
## fixed region dimensions; no absolute world-space float is required.
const ShapeDescriptor := preload("res://scripts/objects/procedural_rock_shape_descriptor.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

const SCHEMA_VERSION := 1
const FRAME_TYPE := "terrain_object_effect_local_frame"
const MAX_PLANES := 128
const MAX_QUERY_REGION_DELTA := 64

const FRAME_KEYS := [
	"schema_version", "type", "effect_id", "source_instance_id",
	"source_revision", "source_fingerprint_sha256", "source_region_key",
	"blend_radius_mm", "local_planes", "bounds_min_local", "bounds_max_local",
	"interior_point_local", "frame_sha256"
]


static func build_from_instance(
	instance: Dictionary,
	effect: Dictionary,
	source_revision: int
) -> Dictionary:
	if not instance.get("region_key") is Vector2i 		or not instance.get("position_mm") is Vector3i:
		return _failure("terrain_effect_frame_source_transform_invalid")
	if String(effect.get("source_instance_id", "")) != String(instance.get("instance_id", "")) 		or int(effect.get("source_revision", -1)) != source_revision:
		return _failure("terrain_effect_frame_source_identity_mismatch")
	var descriptor := ShapeDescriptor.build(
		instance.get("geometry", {}), instance.get("geometry_seeds", {})
	)
	if not descriptor.get("ok", false):
		return _failure(
			"terrain_effect_frame_descriptor_failed:%s" 				% descriptor.get("reason", "unknown")
		)
	var interaction: Dictionary = instance.get("terrain_interaction", {})
	if interaction.is_empty():
		return _failure("terrain_effect_frame_interaction_missing")
	var transform := _resolve_local_transform(instance)
	if not transform.get("ok", false):
		return transform

	var anchor_local_mm: Vector3i = instance["position_mm"]
	var translation_mm: Vector3i = transform["translation_mm"]
	var rotation_mdeg: Vector3i = transform["rotation_mdeg"]
	var scale_milli: Vector3i = transform["scale_milli"]
	var embed_depth_mm := int(interaction.get("embed_depth_mm", -1))
	if embed_depth_mm < 0 or embed_depth_mm > 3000:
		return _failure("terrain_effect_frame_embed_depth_invalid")
	var effect_origin_local := (
		Vector3(anchor_local_mm + translation_mm) / 1000.0
		+ Vector3(0.0, -float(embed_depth_mm) / 1000.0, 0.0)
	)
	var rotation_radians := Vector3(rotation_mdeg) * (PI / 180000.0)
	var basis := Basis.from_euler(rotation_radians)
	var scale := Vector3(scale_milli) / 1000.0
	if scale.x <= 0.0 or scale.y <= 0.0 or scale.z <= 0.0:
		return _failure("terrain_effect_frame_scale_invalid")

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
		var rotated := basis * scaled_normal
		var normal_length := rotated.length()
		if not is_finite(normal_length) or normal_length <= 0.000000001:
			return _failure("terrain_effect_frame_plane_transform_invalid")
		var normal := rotated / normal_length
		var source_distance := float(plane["distance"]) + local_guard
		var distance_local := source_distance / normal_length 			+ normal.dot(effect_origin_local)
		local_planes.append({
			"normal": _vector3_array(normal),
			"distance_m": _canonical_float(distance_local),
		})
	if local_planes.is_empty() or local_planes.size() > MAX_PLANES:
		return _failure("terrain_effect_frame_plane_budget_invalid")

	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var interior := Vector3.ZERO
	var guarded_vertices: Array[Vector3] = descriptor["guarded_vertices"]
	for local_vertex in guarded_vertices:
		var point := effect_origin_local + basis * (local_vertex * scale)
		minimum = minimum.min(point)
		maximum = maximum.max(point)
		interior += point
	if guarded_vertices.is_empty() or not minimum.is_finite() or not maximum.is_finite():
		return _failure("terrain_effect_frame_bounds_invalid")
	interior /= float(guarded_vertices.size())

	var frame := {
		"schema_version": SCHEMA_VERSION,
		"type": FRAME_TYPE,
		"effect_id": String(effect["effect_id"]),
		"source_instance_id": String(effect["source_instance_id"]),
		"source_revision": source_revision,
		"source_fingerprint_sha256": String(effect["source_fingerprint_sha256"]),
		"source_region_key": [
			int((instance["region_key"] as Vector2i).x),
			int((instance["region_key"] as Vector2i).y),
		],
		"blend_radius_mm": int(effect["blend_radius_mm"]),
		"local_planes": local_planes,
		"bounds_min_local": _vector3_array(minimum),
		"bounds_max_local": _vector3_array(maximum),
		"interior_point_local": _vector3_array(interior),
		"frame_sha256": "",
	}
	frame["frame_sha256"] = _frame_sha256(frame)
	return validate_frame(frame)


static func validate_frame(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("terrain_effect_frame_not_dictionary")
	var frame: Dictionary = value
	if not _exact_keys(frame, FRAME_KEYS):
		return _failure("terrain_effect_frame_fields_invalid")
	if not _is_integer(frame["schema_version"]) 		or int(frame["schema_version"]) != SCHEMA_VERSION 		or String(frame["type"]) != FRAME_TYPE:
		return _failure("terrain_effect_frame_schema_invalid")
	for key in [
		"effect_id", "source_instance_id", "source_fingerprint_sha256", "frame_sha256"
	]:
		if typeof(frame[key]) != TYPE_STRING or String(frame[key]).is_empty():
			return _failure("terrain_effect_frame_string_invalid")
	if String(frame["source_fingerprint_sha256"]).length() != 64 		or not _is_hex(String(frame["source_fingerprint_sha256"])) 		or String(frame["frame_sha256"]).length() != 64 		or not _is_hex(String(frame["frame_sha256"])):
		return _failure("terrain_effect_frame_hash_invalid")
	if not _is_integer(frame["source_revision"]) 		or int(frame["source_revision"]) < 0 		or not _is_integer(frame["blend_radius_mm"]) 		or int(frame["blend_radius_mm"]) < 0 		or int(frame["blend_radius_mm"]) > 2000:
		return _failure("terrain_effect_frame_revision_or_blend_invalid")
	var region := _read_int2(frame["source_region_key"])
	if not region.get("ok", false):
		return _failure("terrain_effect_frame_region_invalid")
	var min_result := _read_float3(frame["bounds_min_local"])
	var max_result := _read_float3(frame["bounds_max_local"])
	var interior_result := _read_float3(frame["interior_point_local"])
	if not min_result.get("ok", false) 		or not max_result.get("ok", false) 		or not interior_result.get("ok", false):
		return _failure("terrain_effect_frame_bounds_invalid")
	var minimum: Vector3 = min_result["value"]
	var maximum: Vector3 = max_result["value"]
	if minimum.x > maximum.x or minimum.y > maximum.y or minimum.z > maximum.z:
		return _failure("terrain_effect_frame_bounds_order_invalid")
	if typeof(frame["local_planes"]) != TYPE_ARRAY 		or frame["local_planes"].is_empty() 		or frame["local_planes"].size() > MAX_PLANES:
		return _failure("terrain_effect_frame_planes_invalid")
	var planes: Array[Dictionary] = []
	for plane_value in frame["local_planes"]:
		if typeof(plane_value) != TYPE_DICTIONARY:
			return _failure("terrain_effect_frame_plane_invalid")
		var plane: Dictionary = plane_value
		if plane.size() != 2 or not plane.has("normal") or not plane.has("distance_m"):
			return _failure("terrain_effect_frame_plane_fields_invalid")
		var normal_result := _read_float3(plane["normal"])
		if not normal_result.get("ok", false) 			or not _is_number(plane["distance_m"]) 			or not is_finite(float(plane["distance_m"])):
			return _failure("terrain_effect_frame_plane_value_invalid")
		var normal: Vector3 = normal_result["value"]
		if absf(normal.length() - 1.0) > 0.00001:
			return _failure("terrain_effect_frame_plane_normal_invalid")
		planes.append({
			"normal": _vector3_array(normal),
			"distance_m": _canonical_float(float(plane["distance_m"])),
		})
	var normalized := {
		"schema_version": SCHEMA_VERSION,
		"type": FRAME_TYPE,
		"effect_id": String(frame["effect_id"]),
		"source_instance_id": String(frame["source_instance_id"]),
		"source_revision": int(frame["source_revision"]),
		"source_fingerprint_sha256": String(frame["source_fingerprint_sha256"]),
		"source_region_key": [region["x"], region["y"]],
		"blend_radius_mm": int(frame["blend_radius_mm"]),
		"local_planes": planes,
		"bounds_min_local": _vector3_array(minimum),
		"bounds_max_local": _vector3_array(maximum),
		"interior_point_local": _vector3_array(interior_result["value"]),
		"frame_sha256": String(frame["frame_sha256"]),
	}
	if String(frame["frame_sha256"]) != _frame_sha256(normalized):
		return _failure("terrain_effect_frame_digest_mismatch")
	return {"ok": true, "frame": normalized}


static func sample_cutter_prevalidated(
	frame: Dictionary,
	query_region_key: Vector2i,
	query_local_position: Vector3
) -> float:
	if not query_local_position.is_finite():
		return INF
	var source_values: Array = frame["source_region_key"]
	var source_region := Vector2i(int(source_values[0]), int(source_values[1]))
	var delta := query_region_key - source_region
	if absi(delta.x) > MAX_QUERY_REGION_DELTA 		or absi(delta.y) > MAX_QUERY_REGION_DELTA:
		return INF
	var source_local_point := Vector3(
		query_local_position.x + float(delta.x) * Spatial.REGION_SIZE_X,
		query_local_position.y,
		query_local_position.z + float(delta.y) * Spatial.REGION_SIZE_Z
	)
	var maximum_plane_delta := -INF
	for plane_value in frame["local_planes"]:
		var plane: Dictionary = plane_value
		var normal := _array_to_vector3(plane["normal"])
		maximum_plane_delta = maxf(
			maximum_plane_delta,
			normal.dot(source_local_point) - float(plane["distance_m"])
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
	var density := terrain_density
	for frame_value in frames:
		if typeof(frame_value) != TYPE_DICTIONARY:
			continue
		density = compose_density_prevalidated(
			density, frame_value, query_region_key, query_local_position
		)
	return density


static func bounds_local(frame: Dictionary) -> Dictionary:
	var checked := validate_frame(frame)
	if not checked.get("ok", false):
		return checked
	var normalized: Dictionary = checked["frame"]
	return {
		"ok": true,
		"source_region_key": Vector2i(
			int(normalized["source_region_key"][0]),
			int(normalized["source_region_key"][1])
		),
		"min": _array_to_vector3(normalized["bounds_min_local"]),
		"max": _array_to_vector3(normalized["bounds_max_local"]),
	}


static func _resolve_local_transform(instance: Dictionary) -> Dictionary:
	var translation_mm := Vector3i.ZERO
	var rotation_mdeg := Vector3i(0, int(instance.get("default_yaw_mdeg", 0)), 0)
	var scale_value: Variant = instance.get("default_scale_milli")
	if not scale_value is Vector3i:
		return _failure("terrain_effect_frame_default_scale_invalid")
	var scale_milli: Vector3i = scale_value
	var components: Dictionary = instance.get("instance_components", {})
	var transform_component: Dictionary = components.get("core.transform", {})
	if not transform_component.is_empty():
		var properties: Dictionary = transform_component.get("properties", {})
		var translation := _read_int3(properties.get("translation_mm"))
		var rotation := _read_int3(properties.get("rotation_mdeg"))
		var scale := _read_int3(properties.get("scale_milli"))
		if not translation.get("ok", false) 			or not rotation.get("ok", false) 			or not scale.get("ok", false):
			return _failure("terrain_effect_frame_component_transform_invalid")
		translation_mm = translation["vector3i"]
		rotation_mdeg = rotation["vector3i"]
		scale_milli = scale["vector3i"]
	for component in [scale_milli.x, scale_milli.y, scale_milli.z]:
		if component < 100 or component > 5000:
			return _failure("terrain_effect_frame_scale_invalid")
	return {
		"ok": true,
		"translation_mm": translation_mm,
		"rotation_mdeg": rotation_mdeg,
		"scale_milli": scale_milli,
	}


static func _frame_sha256(frame: Dictionary) -> String:
	var payload := frame.duplicate(true)
	payload["frame_sha256"] = ""
	return JSON.stringify(payload, "", true, true).sha256_text()


static func _read_int2(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return {"ok": false}
	if not _is_integer(value[0]) or not _is_integer(value[1]):
		return {"ok": false}
	return {"ok": true, "x": int(value[0]), "y": int(value[1])}


static func _read_int3(value: Variant) -> Dictionary:
	if value is Vector3i:
		return {"ok": true, "vector3i": Vector3i(value)}
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"ok": false}
	for component in value:
		if not _is_integer(component) or abs(float(component)) > 2147483647.0:
			return {"ok": false}
	return {
		"ok": true,
		"vector3i": Vector3i(int(value[0]), int(value[1]), int(value[2])),
	}


static func _read_float3(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"ok": false}
	var parsed: Array[float] = []
	for component in value:
		if not _is_number(component) or not is_finite(float(component)):
			return {"ok": false}
		parsed.append(float(component))
	return {"ok": true, "value": Vector3(parsed[0], parsed[1], parsed[2])}


static func _vector3_array(value: Vector3) -> Array[float]:
	return [
		_canonical_float(value.x),
		_canonical_float(value.y),
		_canonical_float(value.z),
	]


static func _canonical_float(value: float) -> float:
	return String.num(value, 12).to_float()


static func _array_to_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and floor(float(value)) == float(value)
		and abs(float(value)) <= 9007199254740991.0
	)


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _is_hex(value: String) -> bool:
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
