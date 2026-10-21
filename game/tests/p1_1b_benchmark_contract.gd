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
	if not _canonical_value_supported(parsed):
		return {"ok": false, "reason": "manifest_contains_noncanonical_value"}
	var canonical := canonical_json(parsed).to_utf8_buffer()
	if raw != canonical:
		return {"ok": false, "reason": "manifest_bytes_not_canonical_utf8_json"}
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
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return false
		TYPE_ARRAY:
			for item in value:
				if not _canonical_value_supported(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING or not _canonical_value_supported(value[key]):
					return false
			return true
		_:
			return false


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
