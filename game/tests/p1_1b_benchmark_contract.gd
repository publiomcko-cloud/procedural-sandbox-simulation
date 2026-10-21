class_name P11B1BenchmarkContract
extends RefCounted

## Pure input-contract helpers for the opt-in B1-1 harness. This file is not
## preloaded by the playable scene or by scripts/validate.ps1.
const MANIFEST_PATH := "res://tests/fixtures/p1_1b_b0_manifest.json"
const MANIFEST_SHA_PATH := "res://tests/fixtures/p1_1b_b0_manifest.sha256"
const MANIFEST_SHA256 := "bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd"
const CONTRACT_ID := "P1.1B-B0-R4-R4A-OWNER-APPROVED-EXPERIMENTAL-INPUTS"
const SEED := 424242
const GENERATOR_VERSION := 1
const REPLAY_RADIUS_MM := 580
## Match the exact-integer range that IEEE-754 binary64 can represent without ambiguity.
const MAX_SAFE_JSON_INTEGER := 9007199254740991
const MIN_SAFE_JSON_INTEGER := -9007199254740991
const BOUNDARY_T_JUNCTION_DISTANCE_TOLERANCE := 0.00001
const BOUNDARY_T_JUNCTION_ENDPOINT_PARAMETER_TOLERANCE := 0.000001
const DISTRIBUTED_KEYS := [
	Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
	Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-2, -1),
	Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-2, 1),
]
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")


static func verify_manifest(path: String = MANIFEST_PATH, pin_path: String = MANIFEST_SHA_PATH) -> Dictionary:
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(pin_path):
		return {"ok": false, "reason": "manifest_or_digest_file_missing"}
	var raw := FileAccess.get_file_as_bytes(path)
	var text_value := raw.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text_value)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "manifest_json_not_object"}
	var canonical_check := validate_canonical_json_bytes(raw, parsed)
	if not canonical_check.get("ok", false):
		return {"ok": false, "reason": String(canonical_check.get("reason", "manifest_canonical_validation_failed"))}
	parsed = canonical_check["value"]
	var expected := FileAccess.get_file_as_string(pin_path).strip_edges().to_lower()
	if expected.length() != 64 or not _is_lower_hex_sha256(expected):
		return {"ok": false, "reason": "manifest_sha256_pin_malformed"}
	if expected != MANIFEST_SHA256:
		return {"ok": false, "reason": "manifest_sha256_pin_does_not_match_reviewed_source"}
	var actual := FileAccess.get_sha256(path).to_lower()
	if actual != expected:
		return {"ok": false, "reason": "manifest_sha256_mismatch", "expected_sha256": expected, "actual_sha256": actual}
	if String(parsed.get("contract_id", "")) != CONTRACT_ID \
		or int(parsed.get("schema_version", -1)) != 1 \
		or String(parsed.get("contract_main_sha", "")) != "ea4422d90726d3f2fe6d5cef097126268f93685a" \
		or int(parsed.get("global_seed", -1)) != SEED \
		or int(parsed.get("generator_version", -1)) != GENERATOR_VERSION:
		return {"ok": false, "reason": "manifest_contract_identity_mismatch"}
	return {"ok": true, "manifest": parsed, "sha256": actual, "byte_count": raw.size()}


static func validate_canonical_json_bytes(raw: PackedByteArray, parsed: Variant) -> Dictionary:
	var normalized := normalize_json_value(parsed)
	if not normalized.get("ok", false):
		return {"ok": false, "reason": String(normalized.get("reason", "manifest_contains_noncanonical_value"))}
	var canonical := canonical_json(normalized["value"]).to_utf8_buffer()
	if raw != canonical:
		return {"ok": false, "reason": "manifest_bytes_not_canonical_utf8_json"}
	return {"ok": true, "reason": "", "value": normalized["value"]}


static func normalize_json_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return {"ok": true, "value": value}
		TYPE_INT:
			var integer_value := int(value)
			if integer_value < MIN_SAFE_JSON_INTEGER or integer_value > MAX_SAFE_JSON_INTEGER:
				return {"ok": false, "reason": "manifest_json_integer_outside_safe_range"}
			return {"ok": true, "value": integer_value}
		TYPE_FLOAT:
			var numeric_value := float(value)
			if not is_finite(numeric_value):
				return {"ok": false, "reason": "manifest_json_number_not_finite"}
			if numeric_value != floor(numeric_value):
				return {"ok": false, "reason": "manifest_json_number_not_integral"}
			if numeric_value < float(MIN_SAFE_JSON_INTEGER) or numeric_value > float(MAX_SAFE_JSON_INTEGER):
				return {"ok": false, "reason": "manifest_json_integer_outside_safe_range"}
			var normalized_integer := int(numeric_value)
			if float(normalized_integer) != numeric_value:
				return {"ok": false, "reason": "manifest_json_integer_not_exactly_representable"}
			return {"ok": true, "value": normalized_integer}
		TYPE_ARRAY:
			var normalized_array: Array = []
			for item in value:
				var normalized_item := normalize_json_value(item)
				if not normalized_item.get("ok", false):
					return normalized_item
				normalized_array.append(normalized_item["value"])
			return {"ok": true, "value": normalized_array}
		TYPE_DICTIONARY:
			var normalized_dictionary: Dictionary = {}
			for key in value:
				if typeof(key) != TYPE_STRING:
					return {"ok": false, "reason": "manifest_json_object_key_not_string"}
				var normalized_child := normalize_json_value(value[key])
				if not normalized_child.get("ok", false):
					return normalized_child
				normalized_dictionary[key] = normalized_child["value"]
			return {"ok": true, "value": normalized_dictionary}
		_:
			return {"ok": false, "reason": "manifest_contains_noncanonical_value"}


static func contract_suite_plan(verification: Dictionary) -> Dictionary:
	if not bool(verification.get("ok", false)):
		return {
			"ok": false,
			"status": "FAIL",
			"reason": String(verification.get("reason", "manifest_preflight_failed")),
			"dependent_groups": [],
		}
	var manifest_value: Variant = verification.get("manifest", null)
	if typeof(manifest_value) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"status": "FAIL",
			"reason": "manifest_preflight_valid_result_missing_manifest",
			"dependent_groups": [],
		}
	return {
		"ok": true,
		"status": "RUN",
		"reason": "",
		"manifest": manifest_value,
		"dependent_groups": [
			"manifest_identity",
			"canonical_replay",
			"support_rebuild_dependency",
			"streaming_contract",
			"lod_registry",
			"tunnel_registry",
			"fixed_edits_reload",
			"review_correction_gates",
			"manifest_normalization",
			"manifest_file_failures",
			"preflight_fail_closed",
		],
	}


static func canonical_json(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(value)
		TYPE_STRING:
			return JSON.stringify(String(value))
		TYPE_ARRAY:
			var pieces: PackedStringArray = []
			for item in value:
				pieces.append(canonical_json(item))
			return "[" + ",".join(pieces) + "]"
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort()
			var pairs: PackedStringArray = []
			for key in keys:
				pairs.append(JSON.stringify(String(key)) + ":" + canonical_json(value[key]))
			return "{" + ",".join(pairs) + "}"
		_:
			return ""


static func command_list_sha256(commands: Array) -> String:
	return _sha256_bytes(canonical_json(commands).to_utf8_buffer())


static func build_commands(scenario: Dictionary, manifest: Dictionary) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var count := int(scenario.get("operation_count", 0))
	var recipe := String(scenario.get("recipe", ""))
	var recipe_keys: Array = []
	if recipe == "INTERIOR":
		recipe_keys = [Vector2i.ZERO]
	elif recipe == "EDGE_POS_X":
		recipe_keys = [Vector2i.ZERO, Vector2i(1, 0)]
	elif recipe == "CORNER_POS_XZ":
		recipe_keys = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	elif recipe == "CORNER_NEG_XZ":
		recipe_keys = [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i.ZERO]
	elif recipe == "DISTRIBUTED_16_REGION":
		recipe_keys = DISTRIBUTED_KEYS
	else:
		return _commands_from_manifest(scenario)

	for index in range(count):
		var center_mm := Vector3i.ZERO
		match recipe:
			"INTERIOR":
				center_mm = Vector3i(8000 + (index % 4) * 100, 3200, 6000 + (int(index / 4) % 4) * 100)
			"EDGE_POS_X":
				center_mm = Vector3i(15700 + (index % 3) * 20, 3200, 6000 + (int(index / 3) % 3) * 20)
			"CORNER_POS_XZ":
				center_mm = Vector3i(15800 + (index % 2) * 10, 3200, 11800 + (int(index / 2) % 2) * 10)
			"CORNER_NEG_XZ":
				center_mm = Vector3i(-200 + (index % 2) * 10, 3200, -200 + (int(index / 2) % 2) * 10)
			"DISTRIBUTED_16_REGION":
				var region_key: Vector2i = recipe_keys[index % recipe_keys.size()]
				center_mm = Vector3i(region_key.x * 16000 + 8000, 3200, region_key.y * 12000 + 6000)
		commands.append(_command(index, "CARVE" if index % 2 == 0 else "FILL", center_mm, REPLAY_RADIUS_MM))
	return commands


static func commands_from_scenario(scenario: Dictionary) -> Array[Dictionary]:
	return _commands_from_manifest(scenario)


static func expected_support_for_command(scenario: Dictionary, command: Dictionary) -> Array[String]:
	var expected: Array[String] = []
	var definition: Variant = scenario.get("expected_support_keys", [])
	if typeof(definition) == TYPE_ARRAY:
		for key_value in definition:
			expected.append(String(key_value))
	elif definition == "CENTER_REGION":
		var center_mm: Array = command["center_mm"]
		var world := Vector3(float(center_mm[0]) / 1000.0, float(center_mm[1]) / 1000.0, float(center_mm[2]) / 1000.0)
		var mapped: Dictionary = Spatial.world_to_region_local(world)
		expected.append(_region_id(mapped["region_key"]))
	expected.sort()
	return expected


static func command_from_operation(operation: Dictionary) -> Dictionary:
	var center: Vector3 = operation["center_world"]
	return _command(
		int(operation["sequence"]),
		"CARVE" if int(operation["mode"]) == 0 else "FILL",
		Vector3i(roundi(center.x * 1000.0), roundi(center.y * 1000.0), roundi(center.z * 1000.0)),
		roundi(float(operation["radius"]) * 1000.0)
	)


static func operation_region_keys(operation: Dictionary, field_name: String) -> Array[String]:
	var result: Array[String] = []
	for key_value in operation.get(field_name, []):
		result.append(_region_id(key_value))
	result.sort()
	return result


static func region_id(key: Vector2i) -> String:
	return _region_id(key)


static func movement_result_gate(current_status: String, move_result: Dictionary) -> Dictionary:
	if bool(move_result.get("ok", false)):
		return {"abort": false, "terminal_status": current_status, "reason_code": ""}
	var reason := String(move_result.get("reason_code", "movement_failed_without_reason"))
	return {
		"abort": true,
		"terminal_status": "TIMEOUT" if current_status == "TIMEOUT" else "FAIL",
		"reason_code": reason if not reason.is_empty() else "movement_failed_without_reason",
	}


static func last_successful_movement_base_keys(move_result: Dictionary) -> Dictionary:
	if move_result.is_empty():
		return {"ok": false, "reason_code": "nonsettled_route_has_no_successful_movement_record"}
	var raw_keys: Variant = move_result.get("active_before_last_crossing", null)
	if typeof(raw_keys) != TYPE_ARRAY or (raw_keys as Array).is_empty():
		return {"ok": false, "reason_code": "successful_movement_record_missing_crossing_residency"}
	var keys: Array[String] = []
	for key in raw_keys:
		if typeof(key) != TYPE_STRING:
			return {"ok": false, "reason_code": "successful_movement_record_has_invalid_crossing_residency"}
		keys.append(key)
	return {"ok": true, "keys": keys}


static func compare_boundary_contours(actual: Dictionary, expected: Dictionary) -> Dictionary:
	if not bool(actual.get("valid", false)):
		return {
			"ok": false,
			"reason_code": "transition_boundary_contour_invalid",
			"contour_reason": String(actual.get("reason_code", "unspecified")),
		}
	if not bool(expected.get("valid", false)):
		return {
			"ok": false,
			"reason_code": "reference_boundary_contour_invalid",
			"contour_reason": String(expected.get("reason_code", "unspecified")),
		}
	var actual_segments: Dictionary = actual.get("segments", {})
	var expected_segments: Dictionary = expected.get("segments", {})
	if actual_segments.is_empty() or expected_segments.is_empty():
		return {"ok": false, "reason_code": "empty_interface_contour"}
	if actual_segments != expected_segments:
		return {
			"ok": false,
			"reason_code": "interface_segment_mismatch",
			"actual_segment_count": actual_segments.size(),
			"expected_segment_count": expected_segments.size(),
		}
	return {"ok": true, "segment_count": actual_segments.size()}


static func boundary_contour(mesh: Dictionary, axis: int, plane: float, position_tolerance: float, normal_tolerance: float) -> Dictionary:
	var vertices: PackedVector3Array = mesh.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh.get("normals", PackedVector3Array())
	if axis < 0 or axis > 2 or vertices.is_empty() or vertices.size() != normals.size() or vertices.size() % 3 != 0:
		return {"segments": {}, "normals": {}, "valid": false, "reason_code": "malformed_boundary_mesh_arrays"}
	var segments: Dictionary = {}
	var point_normals: Dictionary = {}
	for start in range(0, vertices.size(), 3):
		for edge in range(3):
			var ai := start + edge
			var bi := start + (edge + 1) % 3
			var a: Vector3 = vertices[ai]
			var b: Vector3 = vertices[bi]
			if not a.is_finite() or not b.is_finite() or not normals[ai].is_finite() or not normals[bi].is_finite():
				return {"segments": segments, "normals": point_normals, "valid": false, "reason_code": "nonfinite_boundary_geometry"}
			if absf(a[axis] - plane) > position_tolerance or absf(b[axis] - plane) > position_tolerance:
				continue
			if a.distance_squared_to(b) <= position_tolerance * position_tolerance:
				return {"segments": segments, "normals": point_normals, "valid": false, "reason_code": "degenerate_boundary_segment"}
			var a_key := _boundary_point_key(a)
			var b_key := _boundary_point_key(b)
			var segment_key := a_key + "|" + b_key if a_key < b_key else b_key + "|" + a_key
			if segments.has(segment_key):
				return {"segments": segments, "normals": point_normals, "valid": false, "reason_code": "duplicate_boundary_segment"}
			segments[segment_key] = true
			if point_normals.has(a_key) and (point_normals[a_key] as Vector3).distance_to(normals[ai]) > normal_tolerance:
				return {"segments": segments, "normals": point_normals, "valid": false, "reason_code": "conflicting_boundary_normals"}
			if point_normals.has(b_key) and (point_normals[b_key] as Vector3).distance_to(normals[bi]) > normal_tolerance:
				return {"segments": segments, "normals": point_normals, "valid": false, "reason_code": "conflicting_boundary_normals"}
			point_normals[a_key] = normals[ai]
			point_normals[b_key] = normals[bi]
	var t_junction := _find_boundary_t_junction(segments, point_normals)
	if not t_junction.is_empty():
		return {
			"segments": segments,
			"normals": point_normals,
			"valid": false,
			"reason_code": "t_junction_boundary_vertex",
			"t_junction": t_junction,
			"t_junction_distance_tolerance": BOUNDARY_T_JUNCTION_DISTANCE_TOLERANCE,
			"endpoint_parameter_tolerance": BOUNDARY_T_JUNCTION_ENDPOINT_PARAMETER_TOLERANCE,
		}
	return {"segments": segments, "normals": point_normals, "valid": true}


static func _boundary_point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * 1000000.0),
		roundi(point.y * 1000000.0),
		roundi(point.z * 1000000.0),
	]


static func _find_boundary_t_junction(segments: Dictionary, point_normals: Dictionary) -> Dictionary:
	for segment_value: Variant in segments.keys():
		var endpoints := String(segment_value).split("|")
		if endpoints.size() != 2:
			return {"reason_code": "malformed_boundary_segment_key"}
		var a := _boundary_point_from_key(endpoints[0])
		var b := _boundary_point_from_key(endpoints[1])
		var ab := b - a
		var length_squared := ab.length_squared()
		if length_squared <= BOUNDARY_T_JUNCTION_DISTANCE_TOLERANCE * BOUNDARY_T_JUNCTION_DISTANCE_TOLERANCE:
			return {"reason_code": "degenerate_boundary_segment_key", "segment": String(segment_value)}
		for point_value: Variant in point_normals.keys():
			var point_key := String(point_value)
			if point_key == endpoints[0] or point_key == endpoints[1]:
				continue
			var point := _boundary_point_from_key(point_key)
			var t := (point - a).dot(ab) / length_squared
			if t <= BOUNDARY_T_JUNCTION_ENDPOINT_PARAMETER_TOLERANCE \
				or t >= 1.0 - BOUNDARY_T_JUNCTION_ENDPOINT_PARAMETER_TOLERANCE:
				continue
			var closest := a + ab * t
			if point.distance_to(closest) <= BOUNDARY_T_JUNCTION_DISTANCE_TOLERANCE:
				return {
					"segment": String(segment_value),
					"interior_vertex": point_key,
					"segment_parameter": t,
					"distance_tolerance": BOUNDARY_T_JUNCTION_DISTANCE_TOLERANCE,
					"endpoint_parameter_tolerance": BOUNDARY_T_JUNCTION_ENDPOINT_PARAMETER_TOLERANCE,
				}
	return {}


static func _boundary_point_from_key(key: String) -> Vector3:
	var coordinates := key.split(",")
	if coordinates.size() != 3:
		return Vector3(INF, INF, INF)
	return Vector3(
		float(coordinates[0].to_int()) / 1000000.0,
		float(coordinates[1].to_int()) / 1000000.0,
		float(coordinates[2].to_int()) / 1000000.0
	)


static func connected_required_samples(mask: PackedByteArray, dimensions: Vector3i, required_indices: PackedInt32Array) -> Dictionary:
	var total := dimensions.x * dimensions.y * dimensions.z
	if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.z <= 0 \
		or total != mask.size() or required_indices.is_empty():
		return {"ok": false, "reason_code": "invalid_connectivity_dimensions_or_seeds"}
	for index in required_indices:
		if index < 0 or index >= total or mask[index] == 0:
			return {"ok": false, "reason_code": "required_sample_not_in_component_mask", "sample_index": index}
	var visited := PackedByteArray()
	visited.resize(total)
	var queue := PackedInt32Array([required_indices[0]])
	visited[required_indices[0]] = 1
	var head := 0
	var ny_nz := dimensions.y * dimensions.z
	while head < queue.size():
		var current := queue[head]
		head += 1
		var x := int(current / ny_nz)
		var remainder := current % ny_nz
		var y := int(remainder / dimensions.z)
		var z := remainder % dimensions.z
		if x > 0:
			var neighbor_x_low := current - ny_nz
			if mask[neighbor_x_low] != 0 and visited[neighbor_x_low] == 0:
				visited[neighbor_x_low] = 1
				queue.append(neighbor_x_low)
		if x + 1 < dimensions.x:
			var neighbor_x_high := current + ny_nz
			if mask[neighbor_x_high] != 0 and visited[neighbor_x_high] == 0:
				visited[neighbor_x_high] = 1
				queue.append(neighbor_x_high)
		if y > 0:
			var neighbor_y_low := current - dimensions.z
			if mask[neighbor_y_low] != 0 and visited[neighbor_y_low] == 0:
				visited[neighbor_y_low] = 1
				queue.append(neighbor_y_low)
		if y + 1 < dimensions.y:
			var neighbor_y_high := current + dimensions.z
			if mask[neighbor_y_high] != 0 and visited[neighbor_y_high] == 0:
				visited[neighbor_y_high] = 1
				queue.append(neighbor_y_high)
		if z > 0:
			var neighbor_z_low := current - 1
			if mask[neighbor_z_low] != 0 and visited[neighbor_z_low] == 0:
				visited[neighbor_z_low] = 1
				queue.append(neighbor_z_low)
		if z + 1 < dimensions.z:
			var neighbor_z_high := current + 1
			if mask[neighbor_z_high] != 0 and visited[neighbor_z_high] == 0:
				visited[neighbor_z_high] = 1
				queue.append(neighbor_z_high)
	var missing: Array[int] = []
	for index in required_indices:
		if visited[index] == 0:
			missing.append(index)
	return {
		"ok": missing.is_empty(),
		"reason_code": "required_samples_disconnected" if not missing.is_empty() else "",
		"visited_sample_count": queue.size(),
		"missing_required_indices": missing,
	}


static func validate_publication_evidence(evidence: Dictionary) -> Dictionary:
	if not bool(evidence.get("transaction_clear", false)):
		return {"ok": false, "reason_code": "publication_transaction_not_clear"}
	if bool(evidence.get("pending_stage", true)):
		return {"ok": false, "reason_code": "publication_stage_still_pending"}
	if not (evidence.get("stream_errors", []) as Array).is_empty():
		return {"ok": false, "reason_code": "publication_has_stream_errors"}
	var expected_revision := int(evidence.get("expected_revision", -1))
	if expected_revision < 0 or int(evidence.get("observed_revision", -2)) != expected_revision:
		return {"ok": false, "reason_code": "publication_revision_mismatch"}
	var expected_chunks := int(evidence.get("expected_chunk_count", -1))
	if expected_chunks <= 0 or int(evidence.get("active_chunk_count", -1)) != expected_chunks \
		or int(evidence.get("array_mesh_count", -1)) != expected_chunks:
		return {"ok": false, "reason_code": "publication_mesh_set_incomplete"}
	match String(evidence.get("kind", "")):
		"EDIT_TRANSACTION":
			if String(evidence.get("edit_commit_status", "")) != "COHERENT_COMMIT" \
				or int(evidence.get("edit_commit_sequence", -1)) != int(evidence.get("expected_sequence", -2)) \
				or int(evidence.get("mesh_job_count", 0)) <= 0:
				return {"ok": false, "reason_code": "edit_mesh_commit_receipt_missing_or_mismatched"}
		"REGION_LOAD":
			if int(evidence.get("successful_publication_delta", 0)) <= 0:
				return {"ok": false, "reason_code": "region_load_publication_not_observed"}
		_:
			return {"ok": false, "reason_code": "unsupported_publication_evidence_kind"}
	var expected_stage_purpose := "edit_transaction" if String(evidence["kind"]) == "EDIT_TRANSACTION" else "load"
	var matching_stage_observed := false
	for stage_value in evidence.get("stage_observations", []):
		var stage: Dictionary = stage_value
		if String(stage.get("region_id", "")) == String(evidence.get("target_region_id", "")) \
			and String(stage.get("purpose", "")) == expected_stage_purpose \
			and int(stage.get("edit_revision", -1)) == expected_revision \
			and int(stage.get("chunk_count", 0)) > 0 \
			and (expected_stage_purpose != "load" or int(stage.get("chunk_count", 0)) == expected_chunks):
			matching_stage_observed = true
	if not matching_stage_observed:
		return {"ok": false, "reason_code": "revision_pinned_production_stage_not_observed"}
	return {"ok": true, "reason_code": "", "revision": expected_revision, "kind": String(evidence["kind"])}


static func key_array(key: Vector2i) -> Array[int]:
	return [key.x, key.y]


static func _commands_from_manifest(scenario: Dictionary) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	for raw_command in scenario.get("commands", []):
		commands.append(_command(
			int(raw_command["sequence"]),
			String(raw_command["mode"]),
			Vector3i(raw_command["center_mm"][0], raw_command["center_mm"][1], raw_command["center_mm"][2]),
			int(raw_command["radius_mm"])
		))
	return commands


static func _command(sequence: int, mode: String, center_mm: Vector3i, radius_mm: int) -> Dictionary:
	return {
		"sequence": sequence,
		"mode": mode,
		"center_mm": [center_mm.x, center_mm.y, center_mm.z],
		"radius_mm": radius_mm,
	}


static func _canonical_value_supported(value: Variant) -> bool:
	return bool(normalize_json_value(value).get("ok", false))


static func _is_lower_hex_sha256(value: String) -> bool:
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode().to_lower()


static func _region_id(key: Vector2i) -> String:
	return "%d,%d" % [key.x, key.y]
