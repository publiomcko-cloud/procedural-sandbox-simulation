class_name ProceduralObjectStateStore
extends RefCounted

## Separate immutable-generation store for object overlays; terrain schema-1 files
## are never opened or rewritten here.
const Contract := preload("res://scripts/objects/procedural_object_state_contract.gd")
const FORMAT_ID := "procedural-sandbox-object-state"
const SCHEMA_VERSION := 1
const MAX_DOCUMENT_BYTES := Contract.MAX_DOCUMENT_BYTES
const GENERATIONS_TO_KEEP := 2

var _directory: String
var _world_id := ""
var _world_seed := -1
var _generator_version := -1
var _last_generation := 0


func _init(directory_override: String = "") -> void:
	if directory_override.is_empty():
		_directory = ProjectSettings.globalize_path("user://worlds/sandbox-default/object-state")
	else:
		_directory = ProjectSettings.globalize_path(directory_override) if directory_override.begins_with("user://") or directory_override.begins_with("res://") else directory_override


func load_snapshot(world_id: String, world_seed: int, generator_version: int) -> Dictionary:
	_world_id = world_id
	_world_seed = world_seed
	_generator_version = generator_version
	if not DirAccess.dir_exists_absolute(_directory):
		return {"ok": true, "found": false, "generation": 0, "snapshot": _empty_snapshot()}
	var directory := DirAccess.open(_directory)
	if directory == null:
		return _failure("object_state_directory_unreadable")
	var candidates: Array[Dictionary] = []
	var recognized := 0
	var highest_generation_seen := 0
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if directory.current_is_dir() or not _is_generation_filename(filename):
			continue
		recognized += 1
		highest_generation_seen = maxi(highest_generation_seen, _generation(filename))
		var decoded := _decode_document(FileAccess.get_file_as_bytes(_directory.path_join(filename)))
		if not decoded.get("ok", false) or int(decoded.get("generation", -1)) != _generation(filename):
			if filename.ends_with(".tmp"):
				continue
			directory.list_dir_end()
			return _failure("object_state_corrupt_generation")
		candidates.append({"generation": int(decoded.generation), "snapshot": decoded.snapshot, "temporary": filename.ends_with(".tmp")})
	directory.list_dir_end()
	_last_generation = highest_generation_seen
	if candidates.is_empty():
		if recognized > 0:
			return {"ok": true, "found": false, "generation": 0, "snapshot": _empty_snapshot(), "ignored_incomplete_generations": recognized}
		return {"ok": true, "found": false, "generation": 0, "snapshot": _empty_snapshot()}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.generation) != int(b.generation):
			return int(a.generation) > int(b.generation)
		return not bool(a.temporary) and bool(b.temporary)
	)
	var selected: Dictionary = candidates[0]
	var recovered_temporary := false
	if bool(selected.temporary):
		var temporary_path := _generation_path(int(selected.generation), ".tmp")
		var final_path := _generation_path(int(selected.generation), ".json")
		if not FileAccess.file_exists(final_path) and DirAccess.rename_absolute(temporary_path, final_path) == OK:
			recovered_temporary = true
	return {"ok": true, "found": true, "generation": int(selected.generation), "snapshot": selected.snapshot, "recovered_temporary": recovered_temporary, "ignored_incomplete_generations": recognized - candidates.size()}


func save_snapshot(snapshot: Dictionary) -> Dictionary:
	var checked := Contract.validate_snapshot(snapshot, _world_id, _world_seed, _generator_version)
	if not checked.get("ok", false):
		return _failure(String(checked.get("reason", "object_state_snapshot_invalid")))
	return save_validated_snapshot(checked.snapshot)


## Fast durable path for callers that already ran Contract.validate_snapshot.
## It preserves write->flush->readback->atomic rename->final readback, but avoids
## validating/canonicalizing the same snapshot repeatedly in one command commit.
func save_validated_snapshot(snapshot: Dictionary) -> Dictionary:
	if snapshot.get("world_id", "") != _world_id \
		or int(snapshot.get("world_seed", -1)) != _world_seed \
		or int(snapshot.get("generator_version", -1)) != _generator_version:
		return _failure("object_state_validated_snapshot_identity_mismatch")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_directory)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return _failure("object_state_directory_unavailable")
	var generation := _next_generation()
	if generation < 1 or generation > 99999999:
		return _failure("object_state_generation_limit_reached")
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
	if bytes.size() > MAX_DOCUMENT_BYTES:
		return _failure("object_state_document_too_large")
	var temporary_path := _generation_path(generation, ".tmp")
	var final_path := _generation_path(generation, ".json")
	if FileAccess.file_exists(temporary_path) or FileAccess.file_exists(final_path):
		return _failure("object_state_generation_collision")
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("object_state_temporary_open_failed")
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _failure("object_state_temporary_write_failed")
	# Byte equality proves the flushed temporary file is exactly the already
	# validated canonical envelope; reparsing it here would duplicate all work.
	var readback := FileAccess.get_file_as_bytes(temporary_path)
	if readback != bytes:
		return _failure("object_state_readback_mismatch")
	var rename_error := DirAccess.rename_absolute(temporary_path, final_path)
	if rename_error != OK:
		return _failure("object_state_commit_rename_failed")
	# Final-path byte equality catches rename/readback failures without a second
	# JSON parse + full snapshot validation.
	if FileAccess.get_file_as_bytes(final_path) != bytes:
		return _failure("object_state_committed_verification_failed")
	_last_generation = generation
	_prune(generation)
	return {"ok": true, "generation": generation, "revision": int(snapshot.get("revision", 0))}


func _decode_document(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_DOCUMENT_BYTES:
		return _failure("object_state_document_size_invalid")
	var parsed := _parse_json(bytes.get_string_from_utf8())
	if not parsed.get("ok", false) or typeof(parsed.get("value")) != TYPE_DICTIONARY:
		return _failure("object_state_json_invalid")
	var document: Dictionary = parsed.value
	if document.size() != 5 or document.get("format") != FORMAT_ID:
		return _failure("object_state_format_invalid")
	var version := _read_integer(document.get("schema_version"))
	var generation := _read_integer(document.get("generation"))
	if not version.ok or int(version.value) != SCHEMA_VERSION or not generation.ok or int(generation.value) < 1:
		return _failure("object_state_version_invalid")
	if typeof(document.get("payload_json")) != TYPE_STRING or typeof(document.get("payload_sha256")) != TYPE_STRING:
		return _failure("object_state_envelope_invalid")
	var payload_json := String(document.payload_json)
	var payload_bytes := payload_json.to_utf8_buffer()
	if _sha256(payload_bytes) != String(document.payload_sha256):
		return _failure("object_state_hash_mismatch")
	var payload_parse := _parse_json(payload_json)
	if not payload_parse.get("ok", false):
		return _failure("object_state_payload_invalid")
	var normalized := Contract.validate_snapshot(payload_parse.get("value"), _world_id, _world_seed, _generator_version)
	if not normalized.get("ok", false):
		return _failure(String(normalized.get("reason", "object_state_payload_rejected")))
	document.schema_version = int(version.value)
	document.generation = int(generation.value)
	if _canonical_json(document).to_utf8_buffer() != bytes:
		return _failure("object_state_envelope_noncanonical")
	if _canonical_json(normalized.snapshot).to_utf8_buffer() != payload_bytes:
		return _failure("object_state_payload_noncanonical")
	return {"ok": true, "generation": int(generation.value), "snapshot": normalized.snapshot}


func _empty_snapshot() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "world_id": _world_id, "world_seed": _world_seed, "generator_version": _generator_version, "revision": 0, "overrides": {}, "deleted": {}}


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
	if not filename.begins_with("objects-") or not (filename.ends_with(".json") or filename.ends_with(".tmp")):
		return false
	if filename.length() != 21 and filename.length() != 20:
		return false
	for character in filename.substr(8, 8):
		if not "0123456789".contains(character):
			return false
	return true


func _generation(filename: String) -> int:
	return int(filename.substr(8, 8))


func _generation_path(generation: int, extension: String) -> String:
	return _directory.path_join("objects-%08d%s" % [generation, extension])


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
	for value in generations:
		if value == current:
			retained += 1
		elif retained < GENERATIONS_TO_KEEP:
			retained += 1
		else:
			DirAccess.remove_absolute(_generation_path(value, ".json"))


func _read_integer(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": int(value)}
	if typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value and abs(value) <= 9007199254740991.0:
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
