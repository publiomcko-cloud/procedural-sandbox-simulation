extends RefCounted
class_name SimulationRuntimeStore

## Durable immutable-generation sidecar for authoritative P4 runtime snapshots.
## Transient queues, profile bindings and resident lifecycle indices are never
## serialized here; SimulationRuntime.get_runtime_snapshot() is the sole payload.

const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")

const FORMAT_ID := "procedural-sandbox-simulation-runtime"
const SCHEMA_VERSION := 1
const GENERATIONS_TO_KEEP := 4
const MAX_GENERATION := 99_999_999
const MAX_PAYLOAD_BYTES := 32 * 1024 * 1024
const MAX_DOCUMENT_BYTES := 48 * 1024 * 1024

var _directory: String
var _last_generation := 0


func _init(directory_override: String = "") -> void:
	if directory_override.is_empty():
		_directory = ProjectSettings.globalize_path(
			"user://simulation-state/sandbox-default"
		)
	elif directory_override.begins_with("user://") or directory_override.begins_with("res://"):
		_directory = ProjectSettings.globalize_path(directory_override)
	else:
		_directory = directory_override


func get_directory() -> String:
	return _directory


func save_snapshot(
	world_id: String,
	world_seed: int,
	generator_version: int,
	terrain_generation: int,
	runtime_snapshot: Dictionary
) -> Dictionary:
	if not _valid_identity(world_id, world_seed, generator_version, terrain_generation):
		return _failure("simulation_store_identity_invalid")
	var validation := _validate_runtime_snapshot(runtime_snapshot)
	if not validation.get("ok", false):
		return _failure(
			"simulation_store_runtime_snapshot_invalid:%s"
			% validation.get("reason", "invalid")
		)

	var directory_error := DirAccess.make_dir_recursive_absolute(_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _failure("simulation_store_directory_unavailable")

	var generation := _next_generation()
	if generation < 1 or generation > MAX_GENERATION:
		return _failure("simulation_store_generation_limit_reached")

	# Godot Variant serialization preserves integer/float/vector distinctions that
	# JSON cannot preserve. The authoritative snapshot is already canonicalized.
	var payload_bytes: PackedByteArray = var_to_bytes(runtime_snapshot, false)
	if payload_bytes.is_empty() or payload_bytes.size() > MAX_PAYLOAD_BYTES:
		return _failure("simulation_store_payload_size_invalid")
	var payload_sha := _sha256(payload_bytes)
	if payload_sha.is_empty():
		return _failure("simulation_store_hash_failed")
	var envelope := {
		"format": FORMAT_ID,
		"schema_version": SCHEMA_VERSION,
		"generation": generation,
		"world_id": world_id,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"terrain_generation": terrain_generation,
		"runtime_schema_version": int(runtime_snapshot["schema_version"]),
		"payload_base64": Marshalls.raw_to_base64(payload_bytes),
		"payload_sha256": payload_sha,
	}
	var bytes := JSON.stringify(envelope, "", true, true).to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > MAX_DOCUMENT_BYTES:
		return _failure("simulation_store_document_size_invalid")

	var temporary_path := _generation_path(generation, ".tmp")
	var final_path := _generation_path(generation, ".json")
	if FileAccess.file_exists(temporary_path) or FileAccess.file_exists(final_path):
		return _failure("simulation_store_generation_collision")
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("simulation_store_temporary_open_failed")
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _failure("simulation_store_temporary_write_failed")
	if FileAccess.get_file_as_bytes(temporary_path) != bytes:
		return _failure("simulation_store_temporary_readback_mismatch")
	var rename_error := DirAccess.rename_absolute(temporary_path, final_path)
	if rename_error != OK:
		return _failure("simulation_store_commit_rename_failed")
	if FileAccess.get_file_as_bytes(final_path) != bytes:
		return _failure("simulation_store_committed_readback_mismatch")

	_last_generation = generation
	_prune(generation)
	return {
		"ok": true,
		"reason": "ok",
		"generation": generation,
		"terrain_generation": terrain_generation,
		"payload_sha256": payload_sha,
	}


func load_snapshot(
	world_id: String,
	world_seed: int,
	generator_version: int,
	terrain_generation: int = -1
) -> Dictionary:
	if not _valid_identity(
		world_id, world_seed, generator_version, maxi(0, terrain_generation)
	):
		return _failure("simulation_store_identity_invalid")
	if terrain_generation < -1:
		return _failure("simulation_store_terrain_generation_invalid")
	if not DirAccess.dir_exists_absolute(_directory):
		return {
			"ok": true,
			"reason": "no_saved_simulation",
			"found": false,
			"generation": 0,
		}
	var directory := DirAccess.open(_directory)
	if directory == null:
		return _failure("simulation_store_directory_unreadable")

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
		var generation := _generation(filename)
		highest_generation_seen = maxi(highest_generation_seen, generation)
		var decoded := _decode_document(
			FileAccess.get_file_as_bytes(_directory.path_join(filename))
		)
		if not decoded.get("ok", false):
			if filename.ends_with(".tmp"):
				continue
			directory.list_dir_end()
			return _failure(
				"simulation_store_corrupt_generation:%s"
				% decoded.get("reason", "invalid")
			)
		if (
			String(decoded["world_id"]) != world_id
			or int(decoded["world_seed"]) != world_seed
			or int(decoded["generator_version"]) != generator_version
		):
			directory.list_dir_end()
			return _failure("simulation_store_identity_mismatch")
		if terrain_generation >= 0 and int(decoded["terrain_generation"]) != terrain_generation:
			continue
		candidates.append({
			"generation": int(decoded["generation"]),
			"terrain_generation": int(decoded["terrain_generation"]),
			"snapshot": decoded["snapshot"],
			"payload_sha256": String(decoded["payload_sha256"]),
			"temporary": filename.ends_with(".tmp"),
		})
	directory.list_dir_end()
	_last_generation = highest_generation_seen

	if candidates.is_empty():
		return {
			"ok": true,
			"reason": (
				"simulation_generation_not_found"
				if recognized > 0 and terrain_generation >= 0
				else "no_saved_simulation"
			),
			"found": false,
			"generation": 0,
			"recognized_generation_count": recognized,
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
		if (
			not FileAccess.file_exists(final_path)
			and DirAccess.rename_absolute(temporary_path, final_path) == OK
		):
			recovered_temporary = true
	return {
		"ok": true,
		"reason": "ok",
		"found": true,
		"generation": int(selected["generation"]),
		"terrain_generation": int(selected["terrain_generation"]),
		"snapshot": (selected["snapshot"] as Dictionary).duplicate(true),
		"payload_sha256": String(selected["payload_sha256"]),
		"recovered_temporary": recovered_temporary,
		"recognized_generation_count": recognized,
	}


func _decode_document(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_DOCUMENT_BYTES:
		return _failure("simulation_store_document_size_invalid")
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return _failure("simulation_store_json_invalid")
	if typeof(parser.data) != TYPE_DICTIONARY:
		return _failure("simulation_store_document_invalid")
	var document: Dictionary = parser.data
	var fields := [
		"format", "schema_version", "generation", "world_id", "world_seed",
		"generator_version", "terrain_generation", "runtime_schema_version",
		"payload_base64", "payload_sha256",
	]
	if not _has_exact_fields(document, fields):
		return _failure("simulation_store_document_fields_invalid")
	if String(document.get("format", "")) != FORMAT_ID:
		return _failure("simulation_store_format_invalid")
	var version := _read_integer(document.get("schema_version"))
	var generation := _read_integer(document.get("generation"))
	var world_seed := _read_integer(document.get("world_seed"))
	var generator_version := _read_integer(document.get("generator_version"))
	var terrain_generation := _read_integer(document.get("terrain_generation"))
	var runtime_schema_version := _read_integer(document.get("runtime_schema_version"))
	if (
		not version.get("ok", false)
		or int(version["value"]) != SCHEMA_VERSION
		or not generation.get("ok", false)
		or int(generation["value"]) < 1
		or int(generation["value"]) > MAX_GENERATION
		or not world_seed.get("ok", false)
		or not generator_version.get("ok", false)
		or not terrain_generation.get("ok", false)
		or int(terrain_generation["value"]) < 0
		or not runtime_schema_version.get("ok", false)
	):
		return _failure("simulation_store_document_integer_invalid")
	if typeof(document.get("world_id")) != TYPE_STRING or String(document["world_id"]).is_empty():
		return _failure("simulation_store_world_id_invalid")
	if typeof(document.get("payload_base64")) != TYPE_STRING:
		return _failure("simulation_store_payload_invalid")
	if typeof(document.get("payload_sha256")) != TYPE_STRING:
		return _failure("simulation_store_hash_invalid")

	var payload_bytes := Marshalls.base64_to_raw(String(document["payload_base64"]))
	if payload_bytes.is_empty() or payload_bytes.size() > MAX_PAYLOAD_BYTES:
		return _failure("simulation_store_payload_size_invalid")
	var payload_sha := _sha256(payload_bytes)
	if payload_sha != String(document["payload_sha256"]):
		return _failure("simulation_store_hash_mismatch")
	var value: Variant = bytes_to_var(payload_bytes, false)
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("simulation_store_payload_variant_invalid")
	var snapshot: Dictionary = value
	if int(snapshot.get("schema_version", -1)) != int(runtime_schema_version["value"]):
		return _failure("simulation_store_runtime_schema_mismatch")
	var validation := _validate_runtime_snapshot(snapshot)
	if not validation.get("ok", false):
		return _failure(
			"simulation_store_runtime_snapshot_invalid:%s"
			% validation.get("reason", "invalid")
	)

	return {
		"ok": true,
		"reason": "ok",
		"generation": int(generation["value"]),
		"world_id": String(document["world_id"]),
		"world_seed": int(world_seed["value"]),
		"generator_version": int(generator_version["value"]),
		"terrain_generation": int(terrain_generation["value"]),
		"snapshot": snapshot,
		"payload_sha256": payload_sha,
	}


func _validate_runtime_snapshot(snapshot: Dictionary) -> Dictionary:
	var validator: Node = RuntimeScript.new()
	var result: Dictionary = validator.validate_runtime_snapshot(snapshot)
	validator.free()
	return result


func _valid_identity(
	world_id: String,
	world_seed: int,
	generator_version: int,
	terrain_generation: int
) -> bool:
	return (
		not world_id.is_empty()
		and world_id == world_id.strip_edges()
		and world_seed >= 0
		and generator_version >= 0
		and terrain_generation >= 0
	)


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
	if (
		not filename.begins_with("simulation-")
		or not (filename.ends_with(".json") or filename.ends_with(".tmp"))
	):
		return false
	var extension_size := 5 if filename.ends_with(".json") else 4
	var digit_count := filename.length() - 11 - extension_size
	if digit_count != 8:
		return false
	for character in filename.substr(11, 8):
		if not "0123456789".contains(character):
			return false
	return true


func _generation(filename: String) -> int:
	return int(filename.substr(11, 8))


func _generation_path(generation: int, extension: String) -> String:
	return _directory.path_join("simulation-%08d%s" % [generation, extension])


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
	if (
		typeof(value) == TYPE_FLOAT
		and is_finite(value)
		and floor(value) == value
		and abs(value) <= 9_007_199_254_740_991.0
	):
		return {"ok": true, "value": int(value)}
	return {"ok": false}


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_value in fields:
		if not value.has(String(field_value)):
			return false
	return true


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
