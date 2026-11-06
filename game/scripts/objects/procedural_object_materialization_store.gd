class_name ProceduralObjectMaterializationStore
extends RefCounted

## Derived, non-authoritative per-region cache for deterministic procedural object
## records and worker-built CPU geometry. Logical object state remains owned by
## ProceduralObjectStateService; cache corruption or invalidation is always a miss.
const FORMAT_ID := "procedural-sandbox-object-materialization"
const SCHEMA_VERSION := 1
const MATERIALIZATION_ALGORITHM_VERSION := 1
const MAX_REGION_BYTES := 64 * 1024 * 1024

var _directory := ""
var _world_id := ""
var _world_seed := -1
var _generator_version := -1
var _content_signature := ""


func _init(
	directory: String,
	world_identifier: String,
	seed_value: int,
	generator_version: int,
	content_signature: String
) -> void:
	_directory = ProjectSettings.globalize_path(directory) 		if directory.begins_with("user://") or directory.begins_with("res://") 		else directory
	_world_id = world_identifier
	_world_seed = seed_value
	_generator_version = generator_version
	_content_signature = content_signature


static func build_content_signature(registry: RefCounted) -> String:
	if registry == null:
		return ""
	var payload := {
		"materialization_algorithm_version": MATERIALIZATION_ALGORITHM_VERSION,
		"definitions": [],
		"population_rules": [],
		"terrain_interactions": [],
	}
	if not registry.has_method("get_definition_ids") 		or not registry.has_method("get_population_rule_ids") 		or not registry.has_method("get_terrain_interaction_rule_ids"):
		return ""
	for definition_id in registry.get_definition_ids():
		payload["definitions"].append({
			"id": String(definition_id),
			"value": registry.get_definition(String(definition_id)),
		})
	for rule_id in registry.get_population_rule_ids():
		payload["population_rules"].append({
			"id": String(rule_id),
			"value": registry.get_population_rule(String(rule_id)),
		})
	for interaction_id in registry.get_terrain_interaction_rule_ids():
		payload["terrain_interactions"].append({
			"id": String(interaction_id),
			"value": registry.get_terrain_interaction_rule(String(interaction_id)),
		})
	return JSON.stringify(payload, "", true, true).sha256_text()


func load_region(region_key: Vector2i) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not _identity_valid():
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_identity_unavailable",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	var path := _region_path(region_key)
	if not FileAccess.file_exists(path):
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_miss",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or bytes.size() > MAX_REGION_BYTES:
		_discard(path)
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_size_invalid",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	var envelope_value := bytes_to_var(bytes, false)
	if typeof(envelope_value) != TYPE_DICTIONARY:
		_discard(path)
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_envelope_invalid",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	var envelope: Dictionary = envelope_value
	if envelope.get("format", "") != FORMAT_ID 		or int(envelope.get("schema_version", -1)) != SCHEMA_VERSION 		or envelope.get("world_id", "") != _world_id 		or int(envelope.get("world_seed", -1)) != _world_seed 		or int(envelope.get("generator_version", -1)) != _generator_version 		or envelope.get("content_signature", "") != _content_signature:
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_identity_mismatch",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	var stored_region := envelope.get("region_key", [])
	if typeof(stored_region) != TYPE_ARRAY or stored_region.size() != 2 		or Vector2i(int(stored_region[0]), int(stored_region[1])) != region_key:
		_discard(path)
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_region_mismatch",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	var payload_value := envelope.get("payload", PackedByteArray())
	if typeof(payload_value) != TYPE_PACKED_BYTE_ARRAY:
		_discard(path)
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_payload_invalid",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	var payload_bytes: PackedByteArray = payload_value
	if payload_bytes.is_empty() 		or String(envelope.get("payload_sha256", "")) != _sha256(payload_bytes):
		_discard(path)
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_hash_mismatch",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	var generated_value := bytes_to_var(payload_bytes, false)
	if typeof(generated_value) != TYPE_DICTIONARY:
		_discard(path)
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_generated_invalid",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	var generated: Dictionary = generated_value
	if not generated.get("ok", false) 		or Vector2i(generated.get("region_key", Vector2i(2147483647, 2147483647))) != region_key 		or typeof(generated.get("instances", [])) != TYPE_ARRAY 		or typeof(generated.get("geometry_cpu_by_instance", {})) != TYPE_DICTIONARY:
		_discard(path)
		return {
			"ok": true,
			"hit": false,
			"reason": "materialization_generated_contract_invalid",
			"load_usec": Time.get_ticks_usec() - started_usec,
		}
	return {
		"ok": true,
		"hit": true,
		"reason": "materialization_hit",
		"generated": generated,
		"load_usec": Time.get_ticks_usec() - started_usec,
		"byte_count": bytes.size(),
	}


func save_region(region_key: Vector2i, generated: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not _identity_valid() or not generated.get("ok", false):
		return {
			"ok": false,
			"reason": "materialization_save_input_invalid",
			"save_usec": Time.get_ticks_usec() - started_usec,
		}
	if Vector2i(generated.get("region_key", Vector2i(2147483647, 2147483647))) != region_key:
		return {
			"ok": false,
			"reason": "materialization_save_region_mismatch",
			"save_usec": Time.get_ticks_usec() - started_usec,
		}
	var payload: Dictionary = generated.duplicate(true)
	for transient_key in [
		"worker_usec",
		"worker_thread_id",
		"materialization_hit",
		"materialization_load_usec",
		"materialization_save_usec",
		"materialization_reason",
	]:
		payload.erase(transient_key)
	var payload_bytes := var_to_bytes(payload, false)
	if payload_bytes.is_empty() or payload_bytes.size() > MAX_REGION_BYTES:
		return {
			"ok": false,
			"reason": "materialization_payload_size_invalid",
			"save_usec": Time.get_ticks_usec() - started_usec,
		}
	var envelope := {
		"format": FORMAT_ID,
		"schema_version": SCHEMA_VERSION,
		"world_id": _world_id,
		"world_seed": _world_seed,
		"generator_version": _generator_version,
		"content_signature": _content_signature,
		"region_key": [region_key.x, region_key.y],
		"payload_sha256": _sha256(payload_bytes),
		"payload": payload_bytes,
	}
	var bytes := var_to_bytes(envelope, false)
	if bytes.is_empty() or bytes.size() > MAX_REGION_BYTES:
		return {
			"ok": false,
			"reason": "materialization_envelope_size_invalid",
			"save_usec": Time.get_ticks_usec() - started_usec,
		}
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_directory)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return {
			"ok": false,
			"reason": "materialization_directory_unavailable",
			"save_usec": Time.get_ticks_usec() - started_usec,
		}
	var final_path := _region_path(region_key)
	var temporary_path := final_path + ".tmp"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"reason": "materialization_temporary_open_failed",
			"save_usec": Time.get_ticks_usec() - started_usec,
		}
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_bytes(temporary_path) != bytes:
		_discard(temporary_path)
		return {
			"ok": false,
			"reason": "materialization_temporary_write_failed",
			"save_usec": Time.get_ticks_usec() - started_usec,
		}
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var rename_error := DirAccess.rename_absolute(temporary_path, final_path)
	if rename_error != OK or FileAccess.get_file_as_bytes(final_path) != bytes:
		_discard(temporary_path)
		_discard(final_path)
		return {
			"ok": false,
			"reason": "materialization_commit_failed",
			"save_usec": Time.get_ticks_usec() - started_usec,
		}
	return {
		"ok": true,
		"reason": "materialization_saved",
		"save_usec": Time.get_ticks_usec() - started_usec,
		"byte_count": bytes.size(),
	}


func _identity_valid() -> bool:
	return not _directory.is_empty() and not _world_id.is_empty() 		and _world_seed >= 0 and _generator_version >= 0 		and _content_signature.length() == 64


func _region_path(region_key: Vector2i) -> String:
	return _directory.path_join("region_%d_%d.bin" % [region_key.x, region_key.y])


func _discard(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK 		or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()
