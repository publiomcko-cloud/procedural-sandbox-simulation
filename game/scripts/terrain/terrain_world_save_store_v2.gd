class_name TerrainWorldSaveStoreV2
extends RefCounted

## Clean-start v2 terrain storage. Schema-1 files live in a separate namespace
## and are only detected for a user-facing notice; they are never imported,
## rewritten or deleted by this store.
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

const FORMAT_ID := "procedural-sandbox-terrain-world"
const SCHEMA_VERSION := 2
const WORLD_ID := "sandbox-default"
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_OPERATIONS := Brush.MAX_OPERATION_COUNT
const MAX_SEGMENT_OPERATIONS := 128
const MAX_SEGMENT_BYTES := 2 * 1024 * 1024
const MAX_TOTAL_BYTES := 268435456
const MAX_INDEX_REFERENCES := 2000000
const MAX_GENERATION := 99999999
const QUERY_INFLUENCE_RADIUS := Brush.MESHING_NOOP_DISTANCE

var _world_directory: String
var _legacy_directory: String
var _loaded_metadata: Dictionary = {}
var _loaded_segments: Array[Dictionary] = []
var _loaded_index: Dictionary = {}
var _sequence_to_segment: Dictionary = {}
var _max_operations := MAX_OPERATIONS
var _max_segment_operations := MAX_SEGMENT_OPERATIONS
var _max_segment_bytes := MAX_SEGMENT_BYTES
var _max_total_bytes := MAX_TOTAL_BYTES
var _max_index_references := MAX_INDEX_REFERENCES
var last_read_error := ""


func _init(directory_override: String = "", legacy_directory_override: String = "", limits_override: Dictionary = {}) -> void:
	_world_directory = directory_override if not directory_override.is_empty() else ProjectSettings.globalize_path("user://worlds-v2/" + WORLD_ID)
	_legacy_directory = legacy_directory_override if not legacy_directory_override.is_empty() else ProjectSettings.globalize_path("user://worlds/" + WORLD_ID)
	_max_operations = mini(MAX_OPERATIONS, maxi(1, int(limits_override.get("max_operations", MAX_OPERATIONS))))
	_max_segment_operations = mini(MAX_SEGMENT_OPERATIONS, maxi(1, int(limits_override.get("max_segment_operations", MAX_SEGMENT_OPERATIONS))))
	_max_segment_bytes = mini(MAX_SEGMENT_BYTES, maxi(1024, int(limits_override.get("max_segment_bytes", MAX_SEGMENT_BYTES))))
	_max_total_bytes = mini(MAX_TOTAL_BYTES, maxi(1024, int(limits_override.get("max_total_bytes", MAX_TOTAL_BYTES))))
	_max_index_references = mini(MAX_INDEX_REFERENCES, maxi(1, int(limits_override.get("max_index_references", MAX_INDEX_REFERENCES))))


func save_ledger(world_id: String, ledger: RefCounted) -> Dictionary:
	if world_id != WORLD_ID or ledger == null:
		return {"ok": false, "reason": "unsupported_world_identity"}
	if int(ledger.generator_version) != Field.GENERATOR_VERSION:
		return {"ok": false, "reason": "unsupported_generator_version"}
	var metadata: Dictionary = ledger.get_persistence_metadata()
	var operation_count := int(metadata.get("operation_count", -1))
	if operation_count < 0 or operation_count > _max_operations:
		return {"ok": false, "reason": "operation_quota_exceeded"}
	var directory_error := DirAccess.make_dir_recursive_absolute(_world_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "save_directory_unavailable_%d" % directory_error}
	# Scan file lengths once. Repeatedly reopening every immutable segment for each
	# subsequent segment write made dense saves scale quadratically with segment count.
	var write_accounting := {"bytes": _directory_bytes()}
	var generation := _next_generation()
	if generation < 1 or generation > MAX_GENERATION:
		return {"ok": false, "reason": "save_generation_limit_reached"}
	var segments: Array[Dictionary] = []
	var support_index: Dictionary = {}
	var query_index: Dictionary = {}
	var records_buffer: Array[Dictionary] = []
	var export_state := {"written_operation_count": 0, "error": ""}
	var indexed_references := 0
	var consume_operation := func(operation: Dictionary) -> void:
		if not String(export_state["error"]).is_empty():
			return
		var record := _record_from_operation(operation)
		if record.is_empty():
			export_state["error"] = "operation_record_invalid"
			return
		records_buffer.append(record)
		export_state["written_operation_count"] = int(export_state["written_operation_count"]) + 1
		var sequence := int(record["sequence"])
		for region_key in operation["support_regions"]:
			_append_index(support_index, _region_id(region_key), sequence)
			indexed_references += 1
		for query_key in _query_regions_for_operation(operation):
			_append_index(query_index, _region_id(query_key), sequence)
			indexed_references += 1
		if indexed_references > _max_index_references:
			export_state["error"] = "spatial_index_quota_exceeded"
			return
		if records_buffer.size() >= _max_segment_operations:
			var segment_result := _write_segment(records_buffer, write_accounting)
			if not segment_result.get("ok", false):
				export_state["error"] = String(segment_result.get("reason", "segment_write_failed"))
			else:
				segments.append(segment_result["entry"])
				records_buffer.clear()
	ledger.for_each_persistence_operation(consume_operation)
	if not String(ledger.last_storage_error).is_empty():
		return {"ok": false, "reason": "source_read_failed_%s" % String(ledger.last_storage_error)}
	if not String(export_state["error"]).is_empty():
		return {"ok": false, "reason": String(export_state["error"])}
	if not records_buffer.is_empty():
		var final_segment := _write_segment(records_buffer, write_accounting)
		if not final_segment.get("ok", false):
			return final_segment
		segments.append(final_segment["entry"])
	if int(export_state["written_operation_count"]) != operation_count:
		return {"ok": false, "reason": "operation_count_changed_during_save"}
	var index_payload := {
		"format": FORMAT_ID,
		"schema_version": SCHEMA_VERSION,
		"support_regions": support_index,
		"query_regions": query_index,
	}
	var index_bytes := _canonical_bytes(index_payload)
	if index_bytes.size() > _max_total_bytes:
		return {"ok": false, "reason": "spatial_index_byte_quota_exceeded"}
	var index_hash := _sha256(index_bytes)
	var index_filename := "index-%s.json" % index_hash
	var index_write := _write_immutable(_world_directory.path_join(index_filename), index_bytes, write_accounting)
	if not index_write.get("ok", false):
		return index_write
	var manifest_payload := {
		"world_id": world_id,
		"world_seed": int(metadata["world_seed"]),
		"generator_version": int(metadata["generator_version"]),
		"ledger_revision": int(metadata["revision"]),
		"next_sequence": int(metadata["next_sequence"]),
		"operation_count": operation_count,
		"segment_count": segments.size(),
		"segments": segments,
		"index_file": index_filename,
		"index_sha256": index_hash,
	}
	var payload_json := JSON.stringify(manifest_payload, "", true, true)
	var envelope := {
		"format": FORMAT_ID,
		"schema_version": SCHEMA_VERSION,
		"generation": generation,
		"payload_json": payload_json,
		"payload_sha256": _sha256(payload_json.to_utf8_buffer()),
	}
	var bytes := _canonical_bytes(envelope)
	if bytes.size() > _max_segment_bytes:
		return {"ok": false, "reason": "manifest_byte_quota_exceeded"}
	if int(write_accounting["bytes"]) + bytes.size() > _max_total_bytes:
		return {"ok": false, "reason": "world_storage_quota_exceeded"}
	var temporary_path := _manifest_path(generation, ".tmp")
	var final_path := _manifest_path(generation, ".json")
	if FileAccess.file_exists(temporary_path) or FileAccess.file_exists(final_path):
		return {"ok": false, "reason": "manifest_generation_collision"}
	var write_result := _write_new_file(temporary_path, bytes)
	if not write_result.get("ok", false):
		return write_result
	if FileAccess.get_file_as_bytes(temporary_path) != bytes or not _decode_manifest(bytes, generation).get("valid", false):
		return {"ok": false, "reason": "manifest_readback_validation_failed"}
	var rename_error := DirAccess.rename_absolute(temporary_path, final_path)
	if rename_error != OK:
		return {"ok": false, "reason": "manifest_commit_rename_failed_%d" % rename_error}
	write_accounting["bytes"] = int(write_accounting["bytes"]) + bytes.size()
	var committed := _decode_manifest(FileAccess.get_file_as_bytes(final_path), generation)
	if not committed.get("valid", false):
		return {"ok": false, "reason": "committed_manifest_verification_failed"}
	return {"ok": true, "generation": generation, "operation_count": operation_count, "revision": int(metadata["revision"]), "segment_count": segments.size(), "index_references": indexed_references, "storage_bytes": _directory_bytes()}


func load_world(world_id: String = WORLD_ID) -> Dictionary:
	if world_id != WORLD_ID:
		return {"ok": false, "found": false, "reason": "unsupported_world_identity"}
	if not DirAccess.dir_exists_absolute(_world_directory):
		var legacy_exists := DirAccess.dir_exists_absolute(_legacy_directory)
		return {"ok": true, "found": false, "legacy_available": legacy_exists, "reason": "legacy_schema1_present_choose_new_world" if legacy_exists else "no_saved_world"}
	var directory := DirAccess.open(_world_directory)
	if directory == null:
		return {"ok": false, "found": true, "reason": "save_directory_unreadable"}
	var candidates: Array[Dictionary] = []
	var invalid_count := 0
	var invalid_reasons: Array[String] = []
	var newest_invalid_committed_generation := 0
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if directory.current_is_dir() or not _is_manifest_filename(filename):
			continue
		var generation := int(filename.substr(9, 8))
		var decoded := _decode_manifest(FileAccess.get_file_as_bytes(_world_directory.path_join(filename)), generation)
		if not decoded.get("valid", false):
			invalid_count += 1
			invalid_reasons.append("%s:%s" % [filename, String(decoded.get("reason", "manifest_invalid"))])
			if filename.ends_with(".json"):
				newest_invalid_committed_generation = maxi(newest_invalid_committed_generation, generation)
			continue
		var verified := _verify_generation(decoded["payload"])
		if not verified.get("valid", false):
			invalid_count += 1
			invalid_reasons.append("%s:%s" % [filename, String(verified.get("reason", "generation_invalid"))])
			if filename.ends_with(".json"):
				newest_invalid_committed_generation = maxi(newest_invalid_committed_generation, generation)
			continue
		candidates.append({"generation": generation, "extension": ".tmp" if filename.ends_with(".tmp") else ".json", "path": _world_directory.path_join(filename), "payload": decoded["payload"], "verified": verified})
	directory.list_dir_end()
	if candidates.is_empty():
		return {"ok": false, "found": true, "reason": "no_valid_v2_generation", "invalid_candidates": invalid_count, "diagnostics": invalid_reasons}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["generation"]) != int(b["generation"]):
			return int(a["generation"]) > int(b["generation"])
		return String(a["extension"]) == ".json" and String(b["extension"]) == ".tmp"
	)
	var selected: Dictionary = candidates[0]
	var generation := int(selected["generation"])
	# A final .json manifest denotes a committed generation. Falling back past a
	# corrupt newer committed generation would silently roll back accepted edits.
	# Incomplete .tmp files remain recoverable by selecting the prior commit.
	var selected_is_temporary := String(selected["extension"]) == ".tmp"
	if newest_invalid_committed_generation > generation \
		or (selected_is_temporary and newest_invalid_committed_generation == generation):
		return {
			"ok": false,
			"found": true,
			"reason": "newest_committed_v2_generation_corrupt",
			"generation": newest_invalid_committed_generation,
			"invalid_candidates": invalid_count,
			"diagnostics": invalid_reasons,
		}
	if String(selected["extension"]) == ".tmp":
		var final_path := _manifest_path(generation, ".json")
		if not FileAccess.file_exists(final_path) and DirAccess.rename_absolute(String(selected["path"]), final_path) == OK:
			selected["path"] = final_path
	var payload: Dictionary = selected["payload"]
	var verified: Dictionary = selected["verified"]
	_loaded_metadata = payload.duplicate(true)
	_loaded_metadata["generation"] = generation
	_loaded_segments = verified["segments"]
	_loaded_index = verified["index"]
	_sequence_to_segment = verified["sequence_to_segment"]
	var storage_metadata := {
		"generation": generation,
		"world_id": String(payload["world_id"]),
		"world_seed": int(payload["world_seed"]),
		"generator_version": int(payload["generator_version"]),
		"ledger_revision": int(payload["ledger_revision"]),
		"next_sequence": int(payload["next_sequence"]),
		"operation_count": int(payload["operation_count"]),
	}
	return {
		"ok": true,
		"found": true,
		"payload": {
			"world_id": String(payload["world_id"]),
			"world_seed": int(payload["world_seed"]),
			"generator_version": int(payload["generator_version"]),
			"ledger_revision": int(payload["ledger_revision"]),
			"next_sequence": int(payload["next_sequence"]),
			"operation_count": int(payload["operation_count"]),
			"storage_reference": {"source": self, "metadata": storage_metadata},
		},
		"generation": generation,
		"segment_count": _loaded_segments.size(),
		"recovered_temporary": String(selected["extension"]) == ".tmp",
		"ignored_invalid_candidates": invalid_count,
	}


func validate_storage_reference(metadata: Dictionary) -> bool:
	return not _loaded_metadata.is_empty() \
		and String(metadata.get("world_id", "")) == String(_loaded_metadata.get("world_id", "")) \
		and int(metadata.get("world_seed", -1)) == int(_loaded_metadata.get("world_seed", -2)) \
		and int(metadata.get("generator_version", -1)) == int(_loaded_metadata.get("generator_version", -2)) \
		and int(metadata.get("generation", -1)) == int(_loaded_metadata.get("generation", -2)) \
		and int(metadata.get("operation_count", -1)) == int(_loaded_metadata.get("operation_count", -2)) \
		and int(metadata.get("ledger_revision", -1)) == int(_loaded_metadata.get("ledger_revision", -2)) \
		and int(metadata.get("next_sequence", -1)) == int(_loaded_metadata.get("next_sequence", -2))


func for_each_operation(callback: Callable) -> void:
	last_read_error = ""
	for segment_index in range(_loaded_segments.size()):
		var operations := _read_segment_operations(segment_index)
		if not last_read_error.is_empty():
			return
		for operation in operations:
			callback.call(operation)


func get_operations_for_support_region(region_key: Vector2i) -> Array[Dictionary]:
	return _operations_for_index("support_regions", _region_id(region_key), {})


func get_operations_for_query_region(region_key: Vector2i, excluded: Dictionary = {}) -> Array[Dictionary]:
	return _operations_for_index("query_regions", _region_id(region_key), excluded)


func _operations_for_index(index_name: String, key: String, excluded: Dictionary) -> Array[Dictionary]:
	last_read_error = ""
	var result: Array[Dictionary] = []
	var entries: Dictionary = _loaded_index.get(index_name, {})
	var sequences_by_segment: Dictionary = {}
	for sequence_value in entries.get(key, []):
		var sequence := int(sequence_value)
		if excluded.has(sequence):
			continue
		var segment_index := int(_sequence_to_segment.get(sequence, -1))
		if segment_index < 0:
			last_read_error = "spatial_index_reference_unmapped"
			return []
		if not sequences_by_segment.has(segment_index):
			sequences_by_segment[segment_index] = []
		(sequences_by_segment[segment_index] as Array).append(sequence)
	var segment_indices: Array = sequences_by_segment.keys()
	segment_indices.sort()
	for segment_index_value in segment_indices:
		var segment_index := int(segment_index_value)
		var wanted: Dictionary = {}
		for sequence_value in sequences_by_segment[segment_index]:
			wanted[int(sequence_value)] = true
		var matched := 0
		for operation in _read_segment_operations(segment_index):
			var sequence := int(operation["sequence"])
			if wanted.has(sequence):
				result.append(operation)
				matched += 1
		if not last_read_error.is_empty():
			return []
		if matched != wanted.size():
			last_read_error = "spatial_index_reference_missing"
			return []
	return result


func _read_segment_operations(segment_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if segment_index < 0 or segment_index >= _loaded_segments.size():
		last_read_error = "segment_index_out_of_range"
		return result
	var entry: Dictionary = _loaded_segments[segment_index]
	var bytes := FileAccess.get_file_as_bytes(_world_directory.path_join(String(entry["file"])))
	var decoded := _decode_segment(bytes)
	if not decoded.get("valid", false) or _sha256(bytes) != String(entry["sha256"]):
		last_read_error = "segment_integrity_failure"
		return result
	var ledger: RefCounted = Brush.new(int(_loaded_metadata["world_seed"]), int(_loaded_metadata["generator_version"]))
	for record in decoded["records"]:
		var operation_result: Dictionary = ledger._build_operation(int(record["mode"]), Vector3(float(record["center"][0]), float(record["center"][1]), float(record["center"][2])), float(record["radius"]), int(record["sequence"]), int(record["revision"]))
		if not operation_result.get("valid", false):
			last_read_error = "segment_semantics_failure"
			return []
		result.append(operation_result["operation"])
	return result


func _verify_generation(payload: Dictionary) -> Dictionary:
	if payload.get("world_id", null) != WORLD_ID:
		return {"valid": false, "reason": "world_id_invalid"}
	for field in ["world_seed", "generator_version", "ledger_revision", "next_sequence", "operation_count", "segment_count"]:
		if not _is_integer(payload.get(field, null)):
			return {"valid": false, "reason": "manifest_metadata_invalid"}
	if int(payload["generator_version"]) != Field.GENERATOR_VERSION or int(payload["operation_count"]) > _max_operations:
		return {"valid": false, "reason": "manifest_version_or_quota_invalid"}
	var segment_values: Variant = payload.get("segments", null)
	if typeof(segment_values) != TYPE_ARRAY or (segment_values as Array).size() != int(payload["segment_count"]):
		return {"valid": false, "reason": "segment_table_invalid"}
	var segments: Array[Dictionary] = []
	var sequence_to_segment: Dictionary = {}
	var expected_support_index: Dictionary = {}
	var expected_query_index: Dictionary = {}
	var index_reference_count := 0
	var operation_count := 0
	var previous_sequence := -1
	var previous_revision := 0
	for segment_value in segment_values:
		if typeof(segment_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "segment_entry_invalid"}
		var entry: Dictionary = segment_value
		var filename := String(entry.get("file", ""))
		var expected_hash := String(entry.get("sha256", ""))
		if not filename.begins_with("segment-") or not filename.ends_with(".json") or not _is_sha256(expected_hash) or filename != "segment-%s.json" % expected_hash:
			return {"valid": false, "reason": "segment_identity_invalid"}
		var bytes := FileAccess.get_file_as_bytes(_world_directory.path_join(filename))
		if bytes.is_empty() or bytes.size() > _max_segment_bytes or _sha256(bytes) != expected_hash:
			return {"valid": false, "reason": "segment_hash_or_size_invalid"}
		var decoded := _decode_segment(bytes)
		if not decoded.get("valid", false):
			return {"valid": false, "reason": "segment_payload_invalid_%s" % String(decoded.get("reason", "unknown"))}
		var records: Array = decoded["records"]
		if int(entry.get("count", -1)) != records.size() or records.is_empty() \
			or int(entry.get("first_sequence", -1)) != int(records[0]["sequence"]) \
			or int(entry.get("last_sequence", -1)) != int(records[-1]["sequence"]):
			return {"valid": false, "reason": "segment_range_metadata_invalid"}
		for record in records:
			var sequence := int(record["sequence"])
			var revision_value := int(record["revision"])
			if sequence <= previous_sequence or sequence >= int(payload["next_sequence"]) or revision_value <= previous_revision or revision_value > int(payload["ledger_revision"]):
				return {"valid": false, "reason": "global_operation_order_invalid"}
			var validator: RefCounted = Brush.new(int(payload["world_seed"]), int(payload["generator_version"]))
			var operation_result: Dictionary = validator._build_operation(int(record["mode"]), Vector3(float(record["center"][0]), float(record["center"][1]), float(record["center"][2])), float(record["radius"]), sequence, revision_value)
			if not operation_result.get("valid", false):
				return {"valid": false, "reason": "operation_semantics_invalid"}
			var operation: Dictionary = operation_result["operation"]
			for region_key in operation["support_regions"]:
				_append_index(expected_support_index, _region_id(region_key), sequence)
				index_reference_count += 1
			for query_key in _query_regions_for_operation(operation):
				_append_index(expected_query_index, _region_id(query_key), sequence)
				index_reference_count += 1
			if index_reference_count > _max_index_references:
				return {"valid": false, "reason": "index_reference_quota_exceeded"}
			sequence_to_segment[sequence] = segments.size()
			previous_sequence = sequence
			previous_revision = revision_value
			operation_count += 1
		segments.append(entry)
	if operation_count != int(payload["operation_count"]) or int(payload["ledger_revision"]) < operation_count or int(payload["next_sequence"]) < operation_count:
		return {"valid": false, "reason": "operation_count_or_revision_invalid"}
	var index_file := String(payload.get("index_file", ""))
	var index_hash := String(payload.get("index_sha256", ""))
	if not index_file.begins_with("index-") or not index_file.ends_with(".json") or not _is_sha256(index_hash) or index_file != "index-%s.json" % index_hash:
		return {"valid": false, "reason": "index_identity_invalid"}
	var index_bytes := FileAccess.get_file_as_bytes(_world_directory.path_join(index_file))
	if index_bytes.is_empty() or index_bytes.size() > _max_total_bytes or _sha256(index_bytes) != index_hash:
		return {"valid": false, "reason": "index_hash_or_size_invalid"}
	var index_parse := _parse_json(index_bytes.get_string_from_utf8())
	if not index_parse.get("ok", false) or typeof(index_parse.get("data", null)) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "index_json_invalid"}
	var index: Dictionary = index_parse["data"]
	if index.get("format", null) != FORMAT_ID or int(index.get("schema_version", -1)) != SCHEMA_VERSION:
		return {"valid": false, "reason": "index_schema_invalid"}
	var normalized_index: Dictionary = index.duplicate(true)
	normalized_index["schema_version"] = SCHEMA_VERSION
	for index_name in ["support_regions", "query_regions"]:
		var map_value: Variant = index.get(index_name, null)
		if typeof(map_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "index_map_invalid"}
		for key in (map_value as Dictionary).keys():
			var sequences: Variant = (map_value as Dictionary)[key]
			if typeof(sequences) != TYPE_ARRAY:
				return {"valid": false, "reason": "index_entries_invalid"}
			var last_sequence := -1
			var normalized_sequences: Array[int] = []
			for sequence_value in sequences:
				if not _is_integer(sequence_value) or int(sequence_value) <= last_sequence or not sequence_to_segment.has(int(sequence_value)):
					return {"valid": false, "reason": "index_reference_invalid"}
				last_sequence = int(sequence_value)
				normalized_sequences.append(int(sequence_value))
			(normalized_index[index_name] as Dictionary)[key] = normalized_sequences
	if _canonical_bytes(normalized_index) != index_bytes:
		return {"valid": false, "reason": "index_noncanonical"}
	if normalized_index["support_regions"] != expected_support_index or normalized_index["query_regions"] != expected_query_index:
		return {"valid": false, "reason": "spatial_index_semantic_mismatch"}
	return {"valid": true, "segments": segments, "index": normalized_index, "sequence_to_segment": sequence_to_segment}


func _decode_manifest(bytes: PackedByteArray, expected_generation: int) -> Dictionary:
	if bytes.is_empty() or bytes.size() > _max_segment_bytes:
		return {"valid": false, "reason": "manifest_empty_or_oversized"}
	var parse_result := _parse_json(bytes.get_string_from_utf8())
	if not parse_result.get("ok", false) or typeof(parse_result.get("data", null)) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "manifest_json_invalid"}
	var envelope: Dictionary = parse_result["data"]
	if envelope.get("format", null) != FORMAT_ID or int(envelope.get("schema_version", -1)) != SCHEMA_VERSION or int(envelope.get("generation", -1)) != expected_generation:
		return {"valid": false, "reason": "manifest_header_invalid"}
	var payload_json := String(envelope.get("payload_json", ""))
	var payload_bytes := payload_json.to_utf8_buffer()
	if _sha256(payload_bytes) != String(envelope.get("payload_sha256", "")):
		return {"valid": false, "reason": "manifest_payload_hash_mismatch"}
	var payload_parse := _parse_json(payload_json)
	if not payload_parse.get("ok", false) or typeof(payload_parse.get("data", null)) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "manifest_payload_not_object"}
	var payload_value: Variant = payload_parse["data"]
	var normalized_payload: Dictionary = payload_value
	for field in ["world_seed", "generator_version", "ledger_revision", "next_sequence", "operation_count", "segment_count"]:
		if not _is_integer(normalized_payload.get(field, null)):
			return {"valid": false, "reason": "manifest_integer_field_invalid_%s" % field}
		normalized_payload[field] = int(normalized_payload[field])
	var segment_records: Variant = normalized_payload.get("segments", null)
	if typeof(segment_records) != TYPE_ARRAY:
		return {"valid": false, "reason": "manifest_segment_table_invalid"}
	for segment_value in segment_records:
		if typeof(segment_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "manifest_segment_entry_not_object"}
		for integer_field in ["count", "first_sequence", "last_sequence"]:
			if not _is_integer(segment_value.get(integer_field, null)):
				return {"valid": false, "reason": "manifest_segment_integer_invalid_%s" % integer_field}
			segment_value[integer_field] = int(segment_value[integer_field])
	if JSON.stringify(normalized_payload, "", true, true) != payload_json:
		return {"valid": false, "reason": "manifest_payload_noncanonical"}
	var normalized: Dictionary = envelope.duplicate(true)
	normalized["schema_version"] = SCHEMA_VERSION
	normalized["generation"] = expected_generation
	if _canonical_bytes(normalized) != bytes:
		return {"valid": false, "reason": "manifest_envelope_noncanonical"}
	return {"valid": true, "payload": payload_value}


func _decode_segment(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > _max_segment_bytes:
		return {"valid": false, "reason": "empty_or_oversized"}
	var parse_result := _parse_json(bytes.get_string_from_utf8())
	if not parse_result.get("ok", false) or typeof(parse_result.get("data", null)) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "envelope_not_object"}
	var envelope: Dictionary = parse_result["data"]
	if envelope.get("format", null) != FORMAT_ID or int(envelope.get("schema_version", -1)) != SCHEMA_VERSION:
		return {"valid": false, "reason": "header_invalid"}
	var payload_json := String(envelope.get("payload_json", ""))
	if _sha256(payload_json.to_utf8_buffer()) != String(envelope.get("payload_sha256", "")):
		return {"valid": false, "reason": "payload_hash_mismatch"}
	var payload_parse := _parse_json(payload_json)
	if not payload_parse.get("ok", false) or typeof(payload_parse.get("data", null)) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "payload_not_object"}
	var payload_value: Variant = payload_parse["data"]
	var payload: Dictionary = payload_value
	if payload.get("format", null) != FORMAT_ID or int(payload.get("schema_version", -1)) != SCHEMA_VERSION or typeof(payload.get("records", null)) != TYPE_ARRAY:
		return {"valid": false, "reason": "payload_schema_invalid"}
	var records: Array = payload["records"]
	if records.is_empty() or records.size() > _max_segment_operations:
		return {"valid": false, "reason": "record_count_invalid"}
	var last_sequence := -1
	for value in records:
		if typeof(value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "record_not_object"}
		var record: Dictionary = value
		if not _is_integer(record.get("sequence", null)) or not _is_integer(record.get("revision", null)) or not _is_integer(record.get("mode", null)) \
			or typeof(record.get("center", null)) != TYPE_ARRAY or (record["center"] as Array).size() != 3 \
			or not _is_finite_number(record.get("radius", null)):
			return {"valid": false, "reason": "record_fields_invalid"}
		if int(record["sequence"]) <= last_sequence or int(record["mode"]) not in [Brush.Mode.CARVE, Brush.Mode.FILL]:
			return {"valid": false, "reason": "sequence_or_mode_invalid"}
		for component in record["center"]:
			if not _is_finite_number(component):
				return {"valid": false, "reason": "center_nonfinite"}
		record["sequence"] = int(record["sequence"])
		record["revision"] = int(record["revision"])
		record["mode"] = int(record["mode"])
		record["radius"] = float(record["radius"])
		var normalized_center: Array = []
		for component in record["center"]:
			normalized_center.append(float(component))
		record["center"] = normalized_center
		last_sequence = int(record["sequence"])
	var canonical_payload := JSON.stringify(payload, "", true, true).to_utf8_buffer()
	var normalized_envelope: Dictionary = envelope.duplicate(true)
	normalized_envelope["schema_version"] = SCHEMA_VERSION
	if _canonical_bytes(normalized_envelope) != bytes:
		return {"valid": false, "reason": "envelope_noncanonical"}
	return {"valid": true, "records": records, "canonical_payload_bytes": canonical_payload}


func _write_segment(records: Array[Dictionary], write_accounting: Dictionary) -> Dictionary:
	var payload := {"format": FORMAT_ID, "schema_version": SCHEMA_VERSION, "records": records}
	var payload_json := JSON.stringify(payload, "", true, true)
	var envelope := {"format": FORMAT_ID, "schema_version": SCHEMA_VERSION, "payload_json": payload_json, "payload_sha256": _sha256(payload_json.to_utf8_buffer())}
	var bytes := _canonical_bytes(envelope)
	if bytes.size() > _max_segment_bytes:
		return {"ok": false, "reason": "segment_byte_quota_exceeded"}
	var digest := _sha256(bytes)
	var filename := "segment-%s.json" % digest
	var result := _write_immutable(_world_directory.path_join(filename), bytes, write_accounting)
	if not result.get("ok", false):
		return result
	return {"ok": true, "entry": {"file": filename, "sha256": digest, "count": records.size(), "first_sequence": int(records[0]["sequence"]), "last_sequence": int(records[-1]["sequence"])}}


func _write_immutable(path: String, bytes: PackedByteArray, write_accounting: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path):
		return {"ok": true} if FileAccess.get_file_as_bytes(path) == bytes else {"ok": false, "reason": "immutable_content_address_collision"}
	if int(write_accounting.get("bytes", _max_total_bytes)) + bytes.size() > _max_total_bytes:
		return {"ok": false, "reason": "world_storage_quota_exceeded"}
	var temporary_path := "%s.tmp-%d-%d" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	while FileAccess.file_exists(temporary_path):
		temporary_path += "x"
	var write_result := _write_new_file(temporary_path, bytes)
	if not write_result.get("ok", false):
		return write_result
	if FileAccess.get_file_as_bytes(temporary_path) != bytes:
		return {"ok": false, "reason": "immutable_temporary_readback_mismatch"}
	if FileAccess.file_exists(path):
		var existing_matches := FileAccess.get_file_as_bytes(path) == bytes
		DirAccess.remove_absolute(temporary_path)
		return {"ok": true} if existing_matches else {"ok": false, "reason": "immutable_content_address_collision"}
	var rename_error := DirAccess.rename_absolute(temporary_path, path)
	if rename_error != OK:
		return {"ok": false, "reason": "immutable_commit_rename_failed_%d" % rename_error}
	if FileAccess.get_file_as_bytes(path) != bytes:
		return {"ok": false, "reason": "immutable_committed_readback_mismatch"}
	write_accounting["bytes"] = int(write_accounting["bytes"]) + bytes.size()
	return {"ok": true}


func _write_new_file(path: String, bytes: PackedByteArray) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "storage_write_open_failed_%d" % FileAccess.get_open_error()}
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(path) != bytes:
		return {"ok": false, "reason": "storage_write_or_readback_failed_%d" % error}
	return {"ok": true}


func _record_from_operation(operation: Dictionary) -> Dictionary:
	if not operation.has("sequence") or not operation.has("revision") or not operation.has("mode") or not operation.has("center_world") or not operation.has("radius"):
		return {}
	var center: Vector3 = operation["center_world"]
	if not center.is_finite():
		return {}
	return {"sequence": int(operation["sequence"]), "revision": int(operation["revision"]), "mode": int(operation["mode"]), "center": [center.x, center.y, center.z], "radius": float(operation["radius"])}


func _query_regions_for_operation(operation: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var center: Vector3 = operation["center_world"]
	var radius := QUERY_INFLUENCE_RADIUS
	for rz in range(floori((center.z - radius) / Spatial.REGION_SIZE_Z), floori((center.z + radius) / Spatial.REGION_SIZE_Z) + 1):
		for rx in range(floori((center.x - radius) / Spatial.REGION_SIZE_X), floori((center.x + radius) / Spatial.REGION_SIZE_X) + 1):
			var minimum := Vector3(float(rx) * Spatial.REGION_SIZE_X, Grid.MIN_BOUND.y - Brush.MESHING_QUERY_MARGIN, float(rz) * Spatial.REGION_SIZE_Z)
			var maximum := Vector3(minimum.x + Spatial.REGION_SIZE_X, Grid.MAX_BOUND.y + Brush.MESHING_QUERY_MARGIN, minimum.z + Spatial.REGION_SIZE_Z)
			var nearest := Vector3(clampf(center.x, minimum.x, maximum.x), clampf(center.y, minimum.y, maximum.y), clampf(center.z, minimum.z, maximum.z))
			if center.distance_squared_to(nearest) <= radius * radius:
				result.append(Vector2i(rx, rz))
	return result


func _append_index(index: Dictionary, key: String, sequence: int) -> void:
	if not index.has(key):
		index[key] = []
	(index[key] as Array).append(sequence)


func _next_generation() -> int:
	var maximum := 0
	if not DirAccess.dir_exists_absolute(_world_directory):
		return 1
	var directory := DirAccess.open(_world_directory)
	if directory == null:
		return 1
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if _is_manifest_filename(filename):
			maximum = maxi(maximum, int(filename.substr(9, 8)))
	directory.list_dir_end()
	return maximum + 1


func _directory_bytes() -> int:
	if not DirAccess.dir_exists_absolute(_world_directory):
		return 0
	var total := 0
	var directory := DirAccess.open(_world_directory)
	if directory == null:
		return _max_total_bytes
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if not directory.current_is_dir():
			var file := FileAccess.open(_world_directory.path_join(filename), FileAccess.READ)
			if file == null:
				directory.list_dir_end()
				return _max_total_bytes
			total += int(file.get_length())
			file.close()
	directory.list_dir_end()
	return total


func _is_manifest_filename(filename: String) -> bool:
	return filename.begins_with("manifest-") and (filename.length() == 21 or filename.length() == 22) and (filename.ends_with(".json") or filename.ends_with(".tmp")) and filename.substr(9, 8).is_valid_int()


func _manifest_path(generation: int, extension: String) -> String:
	return _world_directory.path_join("manifest-%08d%s" % [generation, extension])


func _region_id(region_key: Vector2i) -> String:
	return "%d,%d" % [region_key.x, region_key.y]


func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return absf(float(value)) <= float(MAX_SAFE_INTEGER)
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		return is_finite(number) and floorf(number) == number and absf(number) <= float(MAX_SAFE_INTEGER)
	return false


func _is_finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _is_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _canonical_bytes(value: Variant) -> PackedByteArray:
	return JSON.stringify(value, "", true, true).to_utf8_buffer()


func _parse_json(text: String) -> Dictionary:
	var parser := JSON.new()
	var error := parser.parse(text)
	if error != OK:
		return {"ok": false, "reason": parser.get_error_message()}
	return {"ok": true, "data": parser.data}


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()
