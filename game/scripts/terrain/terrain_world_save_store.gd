class_name TerrainWorldSaveStore
extends RefCounted

## One deterministic local world slot. Each save is an immutable generation file;
## a flushed temporary is committed by same-directory rename and older valid
## generations are retained until the new generation has been reread and verified.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")

const FORMAT_ID := "procedural-sandbox-world"
const SCHEMA_VERSION := 1
const WORLD_ID := "sandbox-default"
const MAX_SAFE_INTEGER := 9007199254740991
const VALID_GENERATIONS_TO_KEEP := 2

var _world_directory: String


func _init(directory_override: String = "") -> void:
	_world_directory = directory_override if not directory_override.is_empty() else ProjectSettings.globalize_path("user://worlds/" + WORLD_ID)


func save_ledger(world_id: String, ledger: RefCounted) -> Dictionary:
	if world_id != WORLD_ID or ledger == null:
		return {"ok": false, "reason": "unsupported_world_identity"}
	if int(ledger.generator_version) != Field.GENERATOR_VERSION:
		return {"ok": false, "reason": "unsupported_generator_version"}
	var directory_error := DirAccess.make_dir_recursive_absolute(_world_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "save_directory_unavailable_%d" % directory_error}
	var generation := _next_generation()
	if generation < 1 or generation > 99999999:
		return {"ok": false, "reason": "save_generation_limit_reached"}
	var ledger_snapshot: Dictionary = ledger.get_persistence_snapshot()
	var operations: Array = []
	for operation in ledger_snapshot.get("operations", []):
		operations.append({
			"sequence": int(operation["sequence"]),
			"revision": int(operation["revision"]),
			"mode": int(operation["mode"]),
			"center": operation["center"],
			"radius": float(operation["radius"]),
		})
	var payload := {
		"world_id": world_id,
		"world_seed": int(ledger_snapshot["world_seed"]),
		"generator_version": int(ledger_snapshot["generator_version"]),
		"ledger_revision": int(ledger_snapshot["revision"]),
		"next_sequence": int(ledger_snapshot["next_sequence"]),
		"operation_count": operations.size(),
		"operations": operations,
	}
	var payload_json := _canonical_json(payload)
	var payload_bytes := payload_json.to_utf8_buffer()
	var envelope := {
		"format": FORMAT_ID,
		"schema_version": SCHEMA_VERSION,
		"generation": generation,
		"payload_json": payload_json,
		"payload_sha256": _sha256(payload_bytes),
	}
	var bytes := _canonical_json(envelope).to_utf8_buffer()
	var temporary_path := _generation_path(generation, ".tmp")
	var final_path := _generation_path(generation, ".json")
	if FileAccess.file_exists(temporary_path) or FileAccess.file_exists(final_path):
		return {"ok": false, "reason": "save_generation_path_collision"}
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "temporary_save_open_failed_%d" % FileAccess.get_open_error()}
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "reason": "temporary_save_write_failed_%d" % write_error}
	if FileAccess.get_file_as_bytes(temporary_path) != bytes:
		return {"ok": false, "reason": "temporary_save_readback_mismatch"}
	var temporary_validation := _decode_document(FileAccess.get_file_as_bytes(temporary_path))
	if not temporary_validation.get("valid", false) or int(temporary_validation.get("generation", -1)) != generation:
		return {"ok": false, "reason": "temporary_save_validation_failed_%s" % temporary_validation.get("reason", "generation_mismatch")}
	var rename_error := DirAccess.rename_absolute(temporary_path, final_path)
	if rename_error != OK:
		return {"ok": false, "reason": "save_commit_rename_failed_%d" % rename_error}
	var committed_validation := _decode_document(FileAccess.get_file_as_bytes(final_path))
	if not committed_validation.get("valid", false) or int(committed_validation.get("generation", -1)) != generation:
		return {"ok": false, "reason": "committed_save_verification_failed"}
	_prune_old_valid_generations(generation)
	return {"ok": true, "generation": generation, "operation_count": operations.size(), "revision": int(ledger_snapshot["revision"])}


func load_world(world_id: String = WORLD_ID) -> Dictionary:
	if world_id != WORLD_ID:
		return {"ok": false, "found": false, "reason": "unsupported_world_identity"}
	if not DirAccess.dir_exists_absolute(_world_directory):
		return {"ok": true, "found": false, "reason": "no_saved_world"}
	var directory := DirAccess.open(_world_directory)
	if directory == null:
		return {"ok": false, "found": true, "reason": "save_directory_unreadable"}
	var candidates: Array[Dictionary] = []
	var recognized_count := 0
	var invalid_count := 0
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if directory.current_is_dir() or not _is_save_filename(filename):
			continue
		recognized_count += 1
		var extension := ".tmp" if filename.ends_with(".tmp") else ".json"
		var generation := _generation_from_filename(filename)
		var path := _world_directory.path_join(filename)
		var decoded := _decode_document(FileAccess.get_file_as_bytes(path))
		if not decoded.get("valid", false) or int(decoded.get("generation", -1)) != generation:
			invalid_count += 1
			continue
		candidates.append({
			"generation": generation,
			"extension": extension,
			"path": path,
			"payload": decoded["payload"],
		})
	directory.list_dir_end()
	if candidates.is_empty():
		if recognized_count == 0:
			return {"ok": true, "found": false, "reason": "no_saved_world"}
		return {"ok": false, "found": true, "reason": "no_valid_save_generation", "invalid_candidates": invalid_count}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["generation"]) != int(b["generation"]):
			return int(a["generation"]) > int(b["generation"])
		return String(a["extension"]) == ".json" and String(b["extension"]) == ".tmp"
	)
	var selected: Dictionary = candidates[0]
	var recovered_temporary := String(selected["extension"]) == ".tmp"
	if recovered_temporary:
		var final_path := _generation_path(int(selected["generation"]), ".json")
		if not FileAccess.file_exists(final_path):
			var recovery_error := DirAccess.rename_absolute(String(selected["path"]), final_path)
			if recovery_error == OK:
				selected["path"] = final_path
				selected["extension"] = ".json"
	return {
		"ok": true,
		"found": true,
		"payload": selected["payload"],
		"generation": int(selected["generation"]),
		"recovered_temporary": recovered_temporary,
		"ignored_invalid_candidates": invalid_count,
	}


func _decode_document(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {"valid": false, "reason": "empty_save"}
	var text := bytes.get_string_from_utf8()
	var parsed_result := _parse_json(text)
	if not parsed_result.get("valid", false):
		return {"valid": false, "reason": "save_json_invalid"}
	var parsed: Variant = parsed_result["data"]
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "save_json_invalid"}
	var document: Dictionary = parsed
	if document.get("format", null) != FORMAT_ID:
		return {"valid": false, "reason": "save_format_unsupported"}
	var schema_result := _read_integer(document.get("schema_version", null))
	var generation_result := _read_integer(document.get("generation", null))
	if not schema_result.get("valid", false) or int(schema_result["value"]) != SCHEMA_VERSION \
		or not generation_result.get("valid", false) or int(generation_result["value"]) < 1:
		return {"valid": false, "reason": "save_version_or_generation_unsupported"}
	var payload_json_value: Variant = document.get("payload_json", null)
	if typeof(payload_json_value) != TYPE_STRING:
		return {"valid": false, "reason": "save_payload_invalid"}
	var payload_json := String(payload_json_value)
	var payload_bytes := payload_json.to_utf8_buffer()
	var hash_value: Variant = document.get("payload_sha256", null)
	if typeof(hash_value) != TYPE_STRING or not _is_sha256(String(hash_value)):
		return {"valid": false, "reason": "save_payload_hash_invalid"}
	var computed_hash := _sha256(payload_bytes)
	if not computed_hash == String(hash_value):
		return {"valid": false, "reason": "save_payload_hash_mismatch"}
	var payload_parse_result := _parse_json(payload_json)
	if not payload_parse_result.get("valid", false):
		return {"valid": false, "reason": "save_payload_invalid"}
	var payload_value: Variant = payload_parse_result["data"]
	if typeof(payload_value) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "save_payload_invalid"}
	var payload: Dictionary = payload_value
	var normalized_result := _validate_payload(payload)
	if not normalized_result.get("valid", false):
		return {"valid": false, "reason": String(normalized_result.get("reason", "save_payload_rejected"))}
	# Godot 4.7 parses JSON integer tokens as floating-point Variants. Normalize
	# the fixed outer integer fields before exact physical canonical-byte checking.
	document["schema_version"] = int(schema_result["value"])
	document["generation"] = int(generation_result["value"])
	if _canonical_json(document).to_utf8_buffer() != bytes:
		return {"valid": false, "reason": "save_json_noncanonical"}
	return {
		"valid": true,
		"generation": int(generation_result["value"]),
		"payload": normalized_result["payload"],
	}


func _validate_payload(payload: Dictionary) -> Dictionary:
	if payload.get("world_id", null) != WORLD_ID:
		return {"valid": false, "reason": "save_world_id_mismatch"}
	var seed_result := _read_integer(payload.get("world_seed", null))
	var generator_result := _read_integer(payload.get("generator_version", null))
	var revision_result := _read_integer(payload.get("ledger_revision", null))
	var next_sequence_result := _read_integer(payload.get("next_sequence", null))
	var count_result := _read_integer(payload.get("operation_count", null))
	var operations_value: Variant = payload.get("operations", null)
	if not seed_result.get("valid", false) or not generator_result.get("valid", false) \
		or not revision_result.get("valid", false) or not next_sequence_result.get("valid", false) \
		or not count_result.get("valid", false) or typeof(operations_value) != TYPE_ARRAY:
		return {"valid": false, "reason": "save_metadata_invalid"}
	var seed := int(seed_result["value"])
	var generator_version := int(generator_result["value"])
	var revision := int(revision_result["value"])
	var next_sequence := int(next_sequence_result["value"])
	var operation_count := int(count_result["value"])
	var source_operations: Array = operations_value
	if generator_version != Field.GENERATOR_VERSION:
		return {"valid": false, "reason": "save_generator_version_unsupported"}
	if operation_count != source_operations.size() or operation_count < 0 or operation_count > BrushState.MAX_EDITS \
		or revision < operation_count or next_sequence < operation_count:
		return {"valid": false, "reason": "save_operation_count_or_ledger_bounds_invalid"}
	var normalized_operations: Array[Dictionary] = []
	var previous_sequence := -1
	var previous_revision := 0
	for source_value in source_operations:
		if typeof(source_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "save_operation_not_object"}
		var source: Dictionary = source_value
		var sequence_result := _read_integer(source.get("sequence", null))
		var operation_revision_result := _read_integer(source.get("revision", null))
		var mode_result := _read_integer(source.get("mode", null))
		var radius_result := _read_finite_number(source.get("radius", null))
		var center_value: Variant = source.get("center", null)
		if not sequence_result.get("valid", false) or not operation_revision_result.get("valid", false) \
			or not mode_result.get("valid", false) or not radius_result.get("valid", false) \
			or typeof(center_value) != TYPE_ARRAY:
			return {"valid": false, "reason": "save_operation_fields_invalid"}
		var center_array: Array = center_value
		if center_array.size() != 3:
			return {"valid": false, "reason": "save_operation_center_invalid"}
		var center: Array[float] = []
		for component in center_array:
			var component_result := _read_finite_number(component)
			if not component_result.get("valid", false):
				return {"valid": false, "reason": "save_operation_center_invalid"}
			center.append(float(component_result["value"]))
		var sequence := int(sequence_result["value"])
		var operation_revision := int(operation_revision_result["value"])
		var mode := int(mode_result["value"])
		var radius := float(radius_result["value"])
		if sequence <= previous_sequence or sequence >= next_sequence \
			or operation_revision <= previous_revision or operation_revision > revision \
			or (mode != BrushState.Mode.CARVE and mode != BrushState.Mode.FILL) \
			or radius < BrushState.MIN_RADIUS or radius > BrushState.MAX_RADIUS \
			or maxf(absf(center[0]), maxf(absf(center[1]), absf(center[2]))) > BrushState.MAX_ABS_WORLD_COORDINATE:
			return {"valid": false, "reason": "save_operation_semantics_invalid"}
		normalized_operations.append({
			"sequence": sequence,
			"revision": operation_revision,
			"mode": mode,
			"center": center,
			"radius": radius,
		})
		previous_sequence = sequence
		previous_revision = operation_revision
	var normalized := {
		"world_id": WORLD_ID,
		"world_seed": seed,
		"generator_version": generator_version,
		"ledger_revision": revision,
		"next_sequence": next_sequence,
		"operation_count": operation_count,
		"operations": normalized_operations,
	}
	return {"valid": true, "payload": normalized}


func _read_integer(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		var integer_value := int(value)
		return {"valid": absf(float(integer_value)) <= float(MAX_SAFE_INTEGER), "value": integer_value}
	if typeof(value) == TYPE_FLOAT:
		var numeric := float(value)
		if is_finite(numeric) and floorf(numeric) == numeric and absf(numeric) <= float(MAX_SAFE_INTEGER):
			return {"valid": true, "value": int(numeric)}
	return {"valid": false}


func _read_finite_number(value: Variant) -> Dictionary:
	if (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)):
		return {"valid": true, "value": float(value)}
	return {"valid": false}


func _next_generation() -> int:
	var maximum := 0
	var directory := DirAccess.open(_world_directory)
	if directory == null:
		return 1
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if _is_save_filename(filename):
			maximum = maxi(maximum, _generation_from_filename(filename))
	directory.list_dir_end()
	return maximum + 1


func _is_save_filename(filename: String) -> bool:
	if not filename.begins_with("save-") or not (filename.ends_with(".json") or filename.ends_with(".tmp")):
		return false
	if filename.length() != 17 and filename.length() != 18:
		return false
	for character in filename.substr(5, 8):
		if not "0123456789".contains(character):
			return false
	return true


func _generation_from_filename(filename: String) -> int:
	return int(filename.substr(5, 8))


func _generation_path(generation: int, extension: String) -> String:
	return _world_directory.path_join("save-%08d%s" % [generation, extension])


func _prune_old_valid_generations(current_generation: int) -> void:
	var directory := DirAccess.open(_world_directory)
	if directory == null:
		return
	var valid_generations: Array[int] = []
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if not filename.ends_with(".json") or not _is_save_filename(filename):
			continue
		var decoded := _decode_document(FileAccess.get_file_as_bytes(_world_directory.path_join(filename)))
		if decoded.get("valid", false) and int(decoded.get("generation", -1)) == _generation_from_filename(filename):
			valid_generations.append(int(decoded["generation"]))
	directory.list_dir_end()
	valid_generations.sort()
	valid_generations.reverse()
	var retained := 0
	for generation in valid_generations:
		if generation == current_generation:
			retained += 1
		elif retained < VALID_GENERATIONS_TO_KEEP:
			retained += 1
		else:
			DirAccess.remove_absolute(_generation_path(generation, ".json"))


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _parse_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"valid": false}
	return {"valid": true, "data": parser.data}


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()


func _is_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true
