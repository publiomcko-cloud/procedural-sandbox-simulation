class_name TerrainObjectEffectProjectionStore
extends RefCounted

## Crash-consistent immutable-generation store for the derived terrain-object
## effect projection. Object/entity state is never opened or rewritten here.
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")

const FORMAT_ID := "procedural-sandbox-terrain-object-effect-projection"
const SCHEMA_VERSION := 1
const MAX_DOCUMENT_BYTES := 64 * 1024 * 1024
const GENERATIONS_TO_KEEP := 2

var _directory: String
var _world_id := ""
var _world_seed := -1
var _generator_version := -1
var _last_generation := 0


func _init(directory_override: String = "") -> void:
	if directory_override.is_empty():
		_directory = ProjectSettings.globalize_path("user://worlds/sandbox-default/terrain-object-effects")
	else:
		_directory = ProjectSettings.globalize_path(directory_override) 			if directory_override.begins_with("user://") or directory_override.begins_with("res://") 			else directory_override


func get_directory() -> String:
	return _directory


func load_snapshot(world_id: String, world_seed: int, generator_version: int) -> Dictionary:
	_world_id = world_id
	_world_seed = world_seed
	_generator_version = generator_version
	_last_generation = 0
	if not DirAccess.dir_exists_absolute(_directory):
		return {
			"ok": true,
			"found": false,
			"generation": 0,
			"snapshot": Contract.empty_snapshot(world_id, world_seed, generator_version),
			"recovered_temporary": false,
			"ignored_incomplete_generations": 0,
		}
	var directory := DirAccess.open(_directory)
	if directory == null:
		return _failure("effect_projection_directory_unreadable")
	var candidates: Array[Dictionary] = []
	var recognized := 0
	var ignored := 0
	var highest_generation_seen := 0
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if directory.current_is_dir() or not _is_generation_filename(filename):
			continue
		recognized += 1
		var generation := _generation(filename)
		highest_generation_seen = maxi(highest_generation_seen, generation)
		var decoded := _decode_document(
			FileAccess.get_file_as_bytes(_directory.path_join(filename))
		)
		if not decoded.get("ok", false) or int(decoded.get("generation", -1)) != generation:
			if filename.ends_with(".tmp"):
				ignored += 1
				continue
			directory.list_dir_end()
			return _failure("effect_projection_corrupt_generation")
		candidates.append({
			"generation": generation,
			"snapshot": decoded["snapshot"],
			"temporary": filename.ends_with(".tmp"),
		})
	directory.list_dir_end()
	_last_generation = highest_generation_seen
	if candidates.is_empty():
		return {
			"ok": true,
			"found": false,
			"generation": 0,
			"snapshot": Contract.empty_snapshot(world_id, world_seed, generator_version),
			"recovered_temporary": false,
			"ignored_incomplete_generations": ignored if recognized > 0 else 0,
		}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["generation"]) != int(b["generation"]):
			return int(a["generation"]) > int(b["generation"])
		return not bool(a["temporary"]) and bool(b["temporary"])
	)
	var selected: Dictionary = candidates[0]
	var recovered_temporary := false
	if bool(selected["temporary"]):
		var temporary_path := _generation_path(int(selected["generation"]), ".tmp")
		var final_path := _generation_path(int(selected["generation"]), ".json")
		if not FileAccess.file_exists(final_path):
			recovered_temporary = DirAccess.rename_absolute(temporary_path, final_path) == OK
	return {
		"ok": true,
		"found": true,
		"generation": int(selected["generation"]),
		"snapshot": selected["snapshot"],
		"recovered_temporary": recovered_temporary,
		"ignored_incomplete_generations": ignored,
	}


func save_snapshot(snapshot: Dictionary) -> Dictionary:
	var checked := Contract.validate_snapshot(
		snapshot, _world_id, _world_seed, _generator_version
	)
	if not checked.get("ok", false):
		return _failure(String(checked.get("reason", "effect_projection_snapshot_invalid")))
	return save_validated_snapshot(checked["snapshot"])


func save_validated_snapshot(snapshot: Dictionary) -> Dictionary:
	if String(snapshot.get("world_id", "")) != _world_id 		or int(snapshot.get("world_seed", -1)) != _world_seed 		or int(snapshot.get("generator_version", -1)) != _generator_version:
		return _failure("effect_projection_snapshot_identity_mismatch")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_directory)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return _failure("effect_projection_directory_unavailable")
	var generation := _next_generation()
	if generation < 1 or generation > 99999999:
		return _failure("effect_projection_generation_limit_reached")
	var payload_json := _canonical_json(snapshot)
	var payload_bytes := payload_json.to_utf8_buffer()
	var envelope := {
		"format": FORMAT_ID,
		"schema_version": SCHEMA_VERSION,
		"generation": generation,
		"payload_json": payload_json,
		"payload_sha256": _sha256(payload_bytes),
	}
	var bytes := _canonical_json(envelope).to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > MAX_DOCUMENT_BYTES:
		return _failure("effect_projection_document_too_large")
	var temporary_path := _generation_path(generation, ".tmp")
	var final_path := _generation_path(generation, ".json")
	if FileAccess.file_exists(temporary_path) or FileAccess.file_exists(final_path):
		return _failure("effect_projection_generation_collision")
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("effect_projection_temporary_open_failed")
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _failure("effect_projection_temporary_write_failed")
	if FileAccess.get_file_as_bytes(temporary_path) != bytes:
		return _failure("effect_projection_temporary_readback_mismatch")
	var rename_error := DirAccess.rename_absolute(temporary_path, final_path)
	if rename_error != OK:
		return _failure("effect_projection_commit_rename_failed")
	if FileAccess.get_file_as_bytes(final_path) != bytes:
		return _failure("effect_projection_committed_readback_mismatch")
	_last_generation = generation
	_prune(generation)
	return {
		"ok": true,
		"generation": generation,
		"projection_revision": int(snapshot.get("projection_revision", 0)),
		"source_world_revision": int(snapshot.get("source_world_revision", 0)),
	}


func _decode_document(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_DOCUMENT_BYTES:
		return _failure("effect_projection_document_size_invalid")
	var parsed := _parse_json(bytes.get_string_from_utf8())
	if not parsed.get("ok", false) or typeof(parsed.get("value")) != TYPE_DICTIONARY:
		return _failure("effect_projection_json_invalid")
	var document: Dictionary = parsed["value"]
	if document.size() != 5 or document.get("format") != FORMAT_ID:
		return _failure("effect_projection_format_invalid")
	var version := _read_integer(document.get("schema_version"))
	var generation := _read_integer(document.get("generation"))
	if not version.get("ok", false) or int(version["value"]) != SCHEMA_VERSION 		or not generation.get("ok", false) or int(generation["value"]) < 1:
		return _failure("effect_projection_version_invalid")
	if typeof(document.get("payload_json")) != TYPE_STRING 		or typeof(document.get("payload_sha256")) != TYPE_STRING:
		return _failure("effect_projection_envelope_invalid")
	var payload_json := String(document["payload_json"])
	var payload_bytes := payload_json.to_utf8_buffer()
	if _sha256(payload_bytes) != String(document["payload_sha256"]):
		return _failure("effect_projection_hash_mismatch")
	var payload_parse := _parse_json(payload_json)
	if not payload_parse.get("ok", false):
		return _failure("effect_projection_payload_invalid")
	var normalized := Contract.validate_snapshot(
		payload_parse.get("value"), _world_id, _world_seed, _generator_version
	)
	if not normalized.get("ok", false):
		return _failure(String(normalized.get("reason", "effect_projection_payload_rejected")))
	document["schema_version"] = int(version["value"])
	document["generation"] = int(generation["value"])
	if _canonical_json(document).to_utf8_buffer() != bytes:
		return _failure("effect_projection_envelope_noncanonical")
	if _canonical_json(normalized["snapshot"]).to_utf8_buffer() != payload_bytes:
		return _failure("effect_projection_payload_noncanonical")
	return {
		"ok": true,
		"generation": int(generation["value"]),
		"snapshot": normalized["snapshot"],
	}


func _next_generation() -> int:
	if _last_generation > 0:
		return _last_generation + 1
	var maximum := 0
	var directory := DirAccess.open(_directory)
	if directory == null:
		return 1
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if _is_generation_filename(filename):
			maximum = maxi(maximum, _generation(filename))
	directory.list_dir_end()
	_last_generation = maximum
	return maximum + 1


func _is_generation_filename(filename: String) -> bool:
	if not filename.begins_with("projection-"):
		return false
	var extension := ".json" if filename.ends_with(".json") else ".tmp" if filename.ends_with(".tmp") else ""
	if extension.is_empty():
		return false
	var stem := filename.trim_suffix(extension)
	if stem.length() != 19:
		return false
	var digits := stem.substr(11, 8)
	if digits.length() != 8:
		return false
	for character in digits:
		if not "0123456789".contains(character):
			return false
	return true


func _generation(filename: String) -> int:
	return int(filename.substr(11, 8))


func _generation_path(generation: int, extension: String) -> String:
	return _directory.path_join("projection-%08d%s" % [generation, extension])


func _prune(current: int) -> void:
	var directory := DirAccess.open(_directory)
	if directory == null:
		return
	var generations: Array[int] = []
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if _is_generation_filename(filename) and filename.ends_with(".json"):
			generations.append(_generation(filename))
	directory.list_dir_end()
	generations.sort()
	generations.reverse()
	var retained := 0
	for generation in generations:
		if generation == current:
			retained += 1
		elif retained < GENERATIONS_TO_KEEP:
			retained += 1
		else:
			DirAccess.remove_absolute(_generation_path(generation, ".json"))


func _read_integer(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": int(value)}
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) 		and floor(float(value)) == float(value) 		and abs(float(value)) <= 9007199254740991.0:
		return {"ok": true, "value": int(value)}
	return {"ok": false}


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _parse_json(value: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(value) != OK:
		return {"ok": false}
	return {"ok": true, "value": parser.data}


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
