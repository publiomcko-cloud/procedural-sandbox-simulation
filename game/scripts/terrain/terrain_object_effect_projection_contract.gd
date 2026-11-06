class_name TerrainObjectEffectProjectionContract
extends RefCounted

## Region-sharded validation contract for the persistent terrain-object effect
## projection. Entity/object state remains authoritative; each regional snapshot
## is independently rebuildable and independently recoverable.
const Effect := preload("res://scripts/terrain/terrain_object_effect.gd")

const SCHEMA_VERSION := 1
const MAX_EFFECTS_PER_SCOPE := 20064
const MAX_SOURCES_PER_SCOPE := 20064
const MAX_REVISION := 9007199254740991

const SNAPSHOT_KEYS := [
	"schema_version", "world_id", "world_seed", "generator_version",
	"scope_id", "region_key", "projection_revision", "source_world_revision",
	"source_digest_sha256", "source_instance_ids", "effects"
]


static func empty_snapshot(
	world_id: String,
	world_seed: int,
	generator_version: int,
	region_key: Vector2i
) -> Dictionary:
	var scope_id := scope_id_for_region(region_key)
	return {
		"schema_version": SCHEMA_VERSION,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"scope_id": scope_id,
		"region_key": [region_key.x, region_key.y],
		"projection_revision": 0,
		"source_world_revision": 0,
		"source_digest_sha256": source_digest(scope_id, region_key, 0, []),
		"source_instance_ids": [],
		"effects": {},
	}


static func validate_snapshot(
	value: Variant,
	world_id: String,
	world_seed: int,
	generator_version: int,
	expected_region_key: Vector2i
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
	var region := _read_int2(snapshot["region_key"])
	if not region.get("ok", false):
		return _failure("effect_projection_region_invalid")
	var region_key := Vector2i(region["x"], region["y"])
	if region_key != expected_region_key:
		return _failure("effect_projection_region_mismatch")
	var scope_id := String(snapshot["scope_id"])
	if scope_id != scope_id_for_region(region_key):
		return _failure("effect_projection_scope_id_invalid")
	if not _valid_revision(snapshot["projection_revision"]) 		or not _valid_revision(snapshot["source_world_revision"]):
		return _failure("effect_projection_revision_invalid")
	var digest := String(snapshot["source_digest_sha256"])
	if digest.length() != 64 or not _is_hex(digest):
		return _failure("effect_projection_source_digest_invalid")
	var source_ids := _read_sorted_unique_strings(
		snapshot["source_instance_ids"], MAX_SOURCES_PER_SCOPE
	)
	if not source_ids.get("ok", false):
		return _failure("effect_projection_source_ids_invalid")
	if typeof(snapshot["effects"]) != TYPE_DICTIONARY:
		return _failure("effect_projection_effect_map_invalid")
	var effects: Dictionary = snapshot["effects"]
	if effects.size() > MAX_EFFECTS_PER_SCOPE:
		return _failure("effect_projection_scope_capacity_exceeded")

	var normalized_effects: Dictionary = {}
	var seen_effect_sources: Dictionary = {}
	for effect_id_value in effects:
		var effect_id := String(effect_id_value)
		if effect_id.is_empty() or typeof(effects[effect_id_value]) != TYPE_DICTIONARY:
			return _failure("effect_projection_effect_entry_invalid")
		var checked_effect := Effect.validate_effect(effects[effect_id_value])
		if not checked_effect.get("ok", false):
			return _failure(
				"effect_projection_effect_invalid:%s" % checked_effect.get("reason", "unknown")
			)
		var effect: Dictionary = checked_effect["effect"]
		if String(effect["effect_id"]) != effect_id:
			return _failure("effect_projection_effect_key_mismatch")
		if String(effect["world_id"]) != world_id 			or int(effect["world_seed"]) != world_seed 			or int(effect["generator_version"]) != generator_version:
			return _failure("effect_projection_effect_world_mismatch")
		var source_id := String(effect["source_instance_id"])
		if not (source_ids["values"] as Array).has(source_id):
			return _failure("effect_projection_effect_source_not_in_scope")
		if seen_effect_sources.has(source_id):
			return _failure("effect_projection_duplicate_source_effect")
		if int(effect["source_revision"]) > int(snapshot["source_world_revision"]):
			return _failure("effect_projection_effect_revision_ahead")
		seen_effect_sources[source_id] = effect_id
		normalized_effects[effect_id] = effect

	var normalized := {
		"schema_version": SCHEMA_VERSION,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"scope_id": scope_id,
		"region_key": [region_key.x, region_key.y],
		"projection_revision": int(snapshot["projection_revision"]),
		"source_world_revision": int(snapshot["source_world_revision"]),
		"source_digest_sha256": digest,
		"source_instance_ids": source_ids["values"],
		"effects": normalized_effects,
	}
	return {"ok": true, "snapshot": normalized}


static func scope_id_for_region(region_key: Vector2i) -> String:
	return "region:%d,%d" % [region_key.x, region_key.y]


static func source_digest(
	scope_id: String,
	region_key: Vector2i,
	source_world_revision: int,
	source_entries: Array
) -> String:
	return canonical_sha256({
		"scope_id": scope_id,
		"region_key": [region_key.x, region_key.y],
		"source_world_revision": source_world_revision,
		"sources": source_entries,
	})


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
