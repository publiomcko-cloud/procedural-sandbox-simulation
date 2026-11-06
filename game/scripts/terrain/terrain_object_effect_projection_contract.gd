class_name TerrainObjectEffectProjectionContract
extends RefCounted

## Validation contract for the persistent terrain-object effect projection.
## Entity/object state remains authoritative; this snapshot is a rebuildable,
## revisioned projection only.
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")

const SCHEMA_VERSION := 1
const MAX_EFFECTS := 20000
const MAX_SCOPES := 20000
const MAX_EFFECTS_PER_SCOPE := 64
const MAX_SOURCES_PER_SCOPE := 64
const MAX_REVISION := 9007199254740991

const SNAPSHOT_KEYS := [
	"schema_version", "world_id", "world_seed", "generator_version",
	"projection_revision", "source_world_revision", "scopes", "effects"
]
const SCOPE_KEYS := [
	"scope_id", "region_key", "source_world_revision", "source_digest_sha256",
	"source_instance_ids", "effect_ids"
]


static func empty_snapshot(world_id: String, world_seed: int, generator_version: int) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"projection_revision": 0,
		"source_world_revision": 0,
		"scopes": {},
		"effects": {},
	}


static func validate_snapshot(
	value: Variant,
	world_id: String,
	world_seed: int,
	generator_version: int
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("effect_projection_snapshot_not_dictionary")
	var snapshot: Dictionary = value
	if not _exact_keys(snapshot, SNAPSHOT_KEYS):
		return _failure("effect_projection_snapshot_fields_invalid")
	if not _is_integer(snapshot["schema_version"]) or int(snapshot["schema_version"]) != SCHEMA_VERSION:
		return _failure("effect_projection_schema_invalid")
	if String(snapshot["world_id"]) != world_id 		or int(snapshot["world_seed"]) != world_seed 		or int(snapshot["generator_version"]) != generator_version:
		return _failure("effect_projection_world_identity_mismatch")
	if not _valid_world_id(world_id) or world_seed < 0 or world_seed > 2147483646 or generator_version < 1:
		return _failure("effect_projection_world_identity_invalid")
	if not _valid_revision(snapshot["projection_revision"]) 		or not _valid_revision(snapshot["source_world_revision"]):
		return _failure("effect_projection_revision_invalid")
	var scopes_value: Variant = snapshot["scopes"]
	var effects_value: Variant = snapshot["effects"]
	if typeof(scopes_value) != TYPE_DICTIONARY or typeof(effects_value) != TYPE_DICTIONARY:
		return _failure("effect_projection_maps_invalid")
	var scopes: Dictionary = scopes_value
	var effects: Dictionary = effects_value
	if scopes.size() > MAX_SCOPES or effects.size() > MAX_EFFECTS:
		return _failure("effect_projection_capacity_exceeded")

	var normalized_effects: Dictionary = {}
	var effect_source_ids: Dictionary = {}
	for effect_id_value in effects:
		var effect_id := String(effect_id_value)
		if effect_id.is_empty() or typeof(effects[effect_id_value]) != TYPE_DICTIONARY:
			return _failure("effect_projection_effect_entry_invalid")
		var checked_effect := Effect.validate_effect(effects[effect_id_value])
		if not checked_effect.get("ok", false):
			return _failure("effect_projection_effect_invalid:%s" % checked_effect.get("reason", "unknown"))
		var effect: Dictionary = checked_effect["effect"]
		if String(effect["effect_id"]) != effect_id:
			return _failure("effect_projection_effect_key_mismatch")
		if String(effect["world_id"]) != world_id 			or int(effect["world_seed"]) != world_seed 			or int(effect["generator_version"]) != generator_version:
			return _failure("effect_projection_effect_world_mismatch")
		var source_id := String(effect["source_instance_id"])
		if effect_source_ids.has(source_id):
			return _failure("effect_projection_duplicate_source_effect")
		effect_source_ids[source_id] = effect_id
		normalized_effects[effect_id] = effect

	var normalized_scopes: Dictionary = {}
	var referenced_effects: Dictionary = {}
	var referenced_sources: Dictionary = {}
	var maximum_scope_revision := 0
	for scope_id_value in scopes:
		var scope_id := String(scope_id_value)
		if typeof(scopes[scope_id_value]) != TYPE_DICTIONARY:
			return _failure("effect_projection_scope_invalid")
		var scope_check := validate_scope(scopes[scope_id_value], scope_id)
		if not scope_check.get("ok", false):
			return scope_check
		var scope: Dictionary = scope_check["scope"]
		if int(scope["source_world_revision"]) > int(snapshot["source_world_revision"]):
			return _failure("effect_projection_scope_revision_ahead")
		maximum_scope_revision = maxi(maximum_scope_revision, int(scope["source_world_revision"]))
		for source_id in scope["source_instance_ids"]:
			if referenced_sources.has(source_id):
				return _failure("effect_projection_source_in_multiple_scopes")
			referenced_sources[source_id] = scope_id
		for effect_id in scope["effect_ids"]:
			if not normalized_effects.has(effect_id):
				return _failure("effect_projection_scope_effect_missing")
			if referenced_effects.has(effect_id):
				return _failure("effect_projection_effect_in_multiple_scopes")
			var effect: Dictionary = normalized_effects[effect_id]
			if not (scope["source_instance_ids"] as Array).has(String(effect["source_instance_id"])):
				return _failure("effect_projection_effect_source_not_in_scope")
			referenced_effects[effect_id] = scope_id
		normalized_scopes[scope_id] = scope
	if scopes.is_empty():
		if int(snapshot["source_world_revision"]) != 0:
			return _failure("effect_projection_empty_scope_revision_invalid")
	elif maximum_scope_revision > int(snapshot["source_world_revision"]):
		return _failure("effect_projection_revision_order_invalid")
	if referenced_effects.size() != normalized_effects.size():
		return _failure("effect_projection_unreferenced_effect")

	var normalized := snapshot.duplicate(true)
	normalized["schema_version"] = SCHEMA_VERSION
	normalized["world_seed"] = world_seed
	normalized["generator_version"] = generator_version
	normalized["projection_revision"] = int(snapshot["projection_revision"])
	normalized["source_world_revision"] = int(snapshot["source_world_revision"])
	normalized["scopes"] = normalized_scopes
	normalized["effects"] = normalized_effects
	return {"ok": true, "snapshot": normalized}


static func validate_scope(value: Variant, expected_scope_id: String = "") -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("effect_projection_scope_not_dictionary")
	var scope: Dictionary = value
	if not _exact_keys(scope, SCOPE_KEYS):
		return _failure("effect_projection_scope_fields_invalid")
	var scope_id := String(scope["scope_id"])
	if scope_id.is_empty() or (not expected_scope_id.is_empty() and scope_id != expected_scope_id):
		return _failure("effect_projection_scope_id_invalid")
	var region := _read_int2(scope["region_key"])
	if not region.get("ok", false):
		return _failure("effect_projection_scope_region_invalid")
	var expected_region_scope := scope_id_for_region(Vector2i(region["x"], region["y"]))
	if scope_id != expected_region_scope:
		return _failure("effect_projection_scope_region_mismatch")
	if not _valid_revision(scope["source_world_revision"]):
		return _failure("effect_projection_scope_revision_invalid")
	var digest := String(scope["source_digest_sha256"])
	if digest.length() != 64 or not _is_hex(digest):
		return _failure("effect_projection_scope_digest_invalid")
	var source_ids := _read_sorted_unique_strings(scope["source_instance_ids"], MAX_SOURCES_PER_SCOPE)
	if not source_ids.get("ok", false):
		return _failure("effect_projection_scope_sources_invalid")
	var effect_ids := _read_sorted_unique_strings(scope["effect_ids"], MAX_EFFECTS_PER_SCOPE)
	if not effect_ids.get("ok", false):
		return _failure("effect_projection_scope_effect_ids_invalid")
	return {
		"ok": true,
		"scope": {
			"scope_id": scope_id,
			"region_key": [region["x"], region["y"]],
			"source_world_revision": int(scope["source_world_revision"]),
			"source_digest_sha256": digest,
			"source_instance_ids": source_ids["values"],
			"effect_ids": effect_ids["values"],
		},
	}


static func scope_id_for_region(region_key: Vector2i) -> String:
	return "region:%d,%d" % [region_key.x, region_key.y]


static func canonical_sha256(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()


static func _read_sorted_unique_strings(value: Variant, maximum: int) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() > maximum:
		return {"ok": false}
	var values: Array[String] = []
	var seen: Dictionary = {}
	for item in value:
		if typeof(item) != TYPE_STRING or String(item).is_empty() or seen.has(String(item)):
			return {"ok": false}
		seen[String(item)] = true
		values.append(String(item))
	var sorted := values.duplicate()
	sorted.sort()
	if sorted != values:
		return {"ok": false}
	return {"ok": true, "values": values}


static func _read_int2(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return {"ok": false}
	if not _is_integer(value[0]) or not _is_integer(value[1]):
		return {"ok": false}
	var x := int(value[0])
	var y := int(value[1])
	if x < -2147483648 or x > 2147483647 or y < -2147483648 or y > 2147483647:
		return {"ok": false}
	return {"ok": true, "x": x, "y": y}


static func _valid_world_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_-]*$")
	return regex.search(value) != null


static func _valid_revision(value: Variant) -> bool:
	return _is_integer(value) and int(value) >= 0 and int(value) <= MAX_REVISION


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
