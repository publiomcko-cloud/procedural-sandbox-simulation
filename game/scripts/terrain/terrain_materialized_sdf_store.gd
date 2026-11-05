class_name TerrainMaterializedSdfStore
extends RefCounted

## Experimental v3-style hot storage for long-lived editable terrain.
##
## Hot world load reads only head.json. Materialized chunk tiles are fetched
## lazily through spatially-computable pointer paths. The append-only journal is
## retained for audit/rebuild but is deliberately absent from the gameplay load
## path.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const State := preload("res://scripts/terrain/terrain_scalable_sdf_state.gd")

const FORMAT_ID := "procedural-sandbox-materialized-sdf-world"
const SCHEMA_VERSION := 1
const WORLD_ID := "sandbox-default"
const HEAD_FILE := "head.json"

var _world_directory: String
var _head_metadata: Dictionary = {}
var _pointer_cache: Dictionary = {}
var _tile_cache: Dictionary = {}

var head_read_count := 0
var head_read_bytes := 0
var pointer_read_count := 0
var pointer_read_bytes := 0
var tile_blob_read_count := 0
var tile_blob_read_bytes := 0
var tile_cache_hit_count := 0
var journal_read_count := 0
var journal_read_bytes := 0
var last_error := ""


func _init(directory_override: String = "") -> void:
	_world_directory = directory_override if not directory_override.is_empty() 		else ProjectSettings.globalize_path("user://worlds-v3/" + WORLD_ID)


func load_world(world_id: String = WORLD_ID) -> Dictionary:
	reset_hot_stats()
	last_error = ""
	if world_id != WORLD_ID:
		return {"ok": false, "found": false, "reason": "unsupported_world_identity"}
	var head_result := _read_head(true)
	if not head_result.get("ok", false):
		return head_result
	if not head_result.get("found", false):
		return {"ok": true, "found": false, "reason": "no_saved_world"}
	var head: Dictionary = head_result["metadata"]
	if not _validate_head(head):
		return {"ok": false, "found": true, "reason": "head_metadata_invalid"}
	_head_metadata = head.duplicate(true)
	_pointer_cache.clear()
	_tile_cache.clear()
	var state := State.new(int(head["world_seed"]), int(head["generator_version"]))
	if not state.restore_hot_reference(self, head):
		return {
			"ok": false,
			"found": true,
			"reason": "state_restore_failed_" + String(state.last_storage_error),
		}
	return {
		"ok": true,
		"found": true,
		"generation": int(head["generation"]),
		"payload": head.duplicate(true),
		"state": state,
	}


func checkpoint_state(world_id: String, state: RefCounted) -> Dictionary:
	last_error = ""
	if world_id != WORLD_ID or state == null:
		return {"ok": false, "reason": "unsupported_world_identity"}
	if int(state.generator_version) != Field.GENERATOR_VERSION:
		return {"ok": false, "reason": "unsupported_generator_version"}
	if _head_metadata.is_empty():
		var existing := _read_head(false)
		if existing.get("ok", false) and existing.get("found", false):
			_head_metadata = (existing["metadata"] as Dictionary).duplicate(true)
	var current_generation := int(_head_metadata.get("generation", 0))
	var plan: Dictionary = state.build_checkpoint_plan()
	if not plan.get("valid", false):
		return {
			"ok": false,
			"reason": String(plan.get("reason", "checkpoint_plan_failed")),
			"detail": plan,
		}
	var generation := current_generation + 1
	var directory_result := _ensure_layout()
	if directory_result != OK and directory_result != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "save_directory_unavailable_%d" % directory_result}

	var journal_records: Array = plan.get("journal_records", [])
	var journal_entry: Dictionary = {}
	if not journal_records.is_empty():
		var first_sequence := int((journal_records[0] as Dictionary)["sequence"])
		var last_sequence := int((journal_records[-1] as Dictionary)["sequence"])
		var journal_payload := {
			"format": FORMAT_ID,
			"schema_version": SCHEMA_VERSION,
			"generation": generation,
			"world_seed": int(state.world_seed),
			"generator_version": int(state.generator_version),
			"first_sequence": first_sequence,
			"last_sequence": last_sequence,
			"records": journal_records,
		}
		var journal_bytes := _canonical_json_bytes(journal_payload)
		var journal_sha := _sha256(journal_bytes)
		var journal_name := "segment-%016d-%016d-%s.json" % [
			first_sequence, last_sequence, journal_sha
		]
		var journal_path := _world_directory.path_join("journal").path_join(journal_name)
		var journal_write := _write_immutable(journal_path, journal_bytes)
		if not journal_write.get("ok", false):
			return journal_write
		journal_entry = {
			"file": "journal/" + journal_name,
			"sha256": journal_sha,
			"first_sequence": first_sequence,
			"last_sequence": last_sequence,
			"count": journal_records.size(),
		}

	var replacements: Dictionary = plan.get("tile_replacements", {})
	var ordered_tile_ids: Array[String] = []
	for id_value in replacements.keys():
		ordered_tile_ids.append(String(id_value))
	ordered_tile_ids.sort()
	var written_tiles := 0
	var reused_blobs := 0
	for tile_id in ordered_tile_ids:
		var tile: Dictionary = replacements[tile_id]
		var tile_bytes := var_to_bytes(tile, false)
		if tile_bytes.is_empty():
			return {"ok": false, "reason": "tile_serialization_failed", "tile_id": tile_id}
		var tile_sha := _sha256(tile_bytes)
		var blob_name := "tile-%s.bin" % tile_sha
		var blob_path := _world_directory.path_join("blobs").path_join(blob_name)
		var existed := FileAccess.file_exists(blob_path)
		var blob_write := _write_immutable(blob_path, tile_bytes)
		if not blob_write.get("ok", false):
			return blob_write
		if existed:
			reused_blobs += 1
		var region_key: Vector2i = tile["region_key"]
		var coordinate: Vector2i = tile["coordinate"]
		var pointer_path := _pointer_path(region_key, coordinate)
		var previous_result := _read_effective_pointer(
			pointer_path, current_generation, false
		)
		if not previous_result.get("ok", false):
			return previous_result
		var current_entry := {
			"generation": generation,
			"tile_id": tile_id,
			"region": [region_key.x, region_key.y],
			"coordinate": [coordinate.x, coordinate.y],
			"blob_file": "blobs/" + blob_name,
			"sha256": tile_sha,
			"base_revision": int(tile.get("base_revision", -1)),
			"base_sequence": int(tile.get("base_sequence", -1)),
			"step": float(tile.get("step", 0.0)),
		}
		var pointer_payload := {
			"format": FORMAT_ID,
			"schema_version": SCHEMA_VERSION,
			"current": current_entry,
			"previous": previous_result.get("entry", {}) if previous_result.get("found", false) else {},
		}
		var pointer_dir_error := DirAccess.make_dir_recursive_absolute(pointer_path.get_base_dir())
		if pointer_dir_error != OK and pointer_dir_error != ERR_ALREADY_EXISTS:
			return {"ok": false, "reason": "pointer_directory_unavailable_%d" % pointer_dir_error}
		var pointer_write := _write_replace(pointer_path, _canonical_json_bytes(pointer_payload))
		if not pointer_write.get("ok", false):
			return pointer_write
		written_tiles += 1

	var previous_archived := int(_head_metadata.get("archived_operation_count", 0))
	var archived_count := int(plan.get("lifetime_operation_count", 0))
	if archived_count != previous_archived + journal_records.size():
		# A fresh world has previous_archived=0. A loaded state always resumes from
		# the committed archived count; this catches omitted or duplicated tails.
		return {"ok": false, "reason": "journal_accounting_mismatch"}

	var head := {
		"format": FORMAT_ID,
		"schema_version": SCHEMA_VERSION,
		"world_id": WORLD_ID,
		"world_seed": int(plan["world_seed"]),
		"generator_version": int(plan["generator_version"]),
		"generation": generation,
		"revision": int(plan["revision"]),
		"next_sequence": int(plan["next_sequence"]),
		"lifetime_operation_count": int(plan["lifetime_operation_count"]),
		"archived_operation_count": archived_count,
		"last_journal": journal_entry,
		"materialized_step": State.MATERIALIZED_STEP,
	}
	var head_write := _write_replace(
		_world_directory.path_join(HEAD_FILE), _canonical_json_bytes(head)
	)
	if not head_write.get("ok", false):
		return head_write
	_head_metadata = head.duplicate(true)
	_pointer_cache.clear()
	_tile_cache.clear()
	if not state.commit_checkpoint(plan, self, head):
		return {
			"ok": false,
			"reason": "state_checkpoint_commit_failed_" + String(state.last_storage_error),
		}
	return {
		"ok": true,
		"generation": generation,
		"archived_operation_count": archived_count,
		"written_tiles": written_tiles,
		"reused_tile_blobs": reused_blobs,
		"journal_entry": journal_entry,
	}


func get_materialized_tile(region_key: Vector2i, coordinate: Vector2i) -> Dictionary:
	last_error = ""
	if not Grid.is_valid_coordinate(coordinate):
		return {"ok": false, "found": false, "reason": "invalid_chunk_coordinate"}
	var tile_id := Grid.stable_id(region_key, coordinate)
	if _tile_cache.has(tile_id):
		tile_cache_hit_count += 1
		return {"ok": true, "found": true, "tile": _tile_cache[tile_id]}
	var generation := int(_head_metadata.get("generation", 0))
	if generation <= 0:
		return {"ok": true, "found": false}
	var pointer_result: Dictionary
	if _pointer_cache.has(tile_id):
		pointer_result = _pointer_cache[tile_id]
	else:
		pointer_result = _read_effective_pointer(
			_pointer_path(region_key, coordinate), generation, true
		)
		_pointer_cache[tile_id] = pointer_result
	if not pointer_result.get("ok", false):
		last_error = String(pointer_result.get("reason", "pointer_read_failed"))
		return pointer_result
	if not pointer_result.get("found", false):
		return {"ok": true, "found": false}
	var entry: Dictionary = pointer_result["entry"]
	var blob_path := _world_directory.path_join(String(entry["blob_file"]))
	if not FileAccess.file_exists(blob_path):
		return {"ok": false, "found": false, "reason": "tile_blob_missing"}
	var bytes := FileAccess.get_file_as_bytes(blob_path)
	tile_blob_read_count += 1
	tile_blob_read_bytes += bytes.size()
	if bytes.is_empty() or _sha256(bytes) != String(entry.get("sha256", "")):
		return {"ok": false, "found": false, "reason": "tile_blob_integrity_failure"}
	var decoded: Variant = bytes_to_var(bytes, false)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {"ok": false, "found": false, "reason": "tile_blob_decode_failure"}
	var tile: Dictionary = decoded
	if not _validate_tile(tile, region_key, coordinate, tile_id):
		return {"ok": false, "found": false, "reason": "tile_blob_semantics_failure"}
	_tile_cache[tile_id] = tile
	return {"ok": true, "found": true, "tile": tile}


func audit_archive() -> Dictionary:
	last_error = ""
	var journal_dir := _world_directory.path_join("journal")
	if not DirAccess.dir_exists_absolute(journal_dir):
		return {
			"ok": int(_head_metadata.get("archived_operation_count", 0)) == 0,
			"record_count": 0,
			"segment_count": 0,
		}
	var directory := DirAccess.open(journal_dir)
	if directory == null:
		return {"ok": false, "reason": "journal_directory_unreadable"}
	var names: Array[String] = []
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if not directory.current_is_dir() and name.begins_with("segment-") and name.ends_with(".json"):
			names.append(name)
	directory.list_dir_end()
	names.sort()
	var expected_sequence := 0
	var count := 0
	for name in names:
		var path := journal_dir.path_join(name)
		var bytes := FileAccess.get_file_as_bytes(path)
		journal_read_count += 1
		journal_read_bytes += bytes.size()
		if bytes.is_empty():
			return {"ok": false, "reason": "journal_segment_empty", "file": name}
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "journal_segment_decode_failure", "file": name}
		var payload: Dictionary = parsed
		var records_value: Variant = payload.get("records", null)
		if typeof(records_value) != TYPE_ARRAY:
			return {"ok": false, "reason": "journal_records_invalid", "file": name}
		for record_value in records_value:
			if typeof(record_value) != TYPE_DICTIONARY:
				return {"ok": false, "reason": "journal_record_invalid", "file": name}
			var record: Dictionary = record_value
			if int(record.get("sequence", -1)) != expected_sequence:
				return {
					"ok": false,
					"reason": "journal_sequence_gap",
					"expected": expected_sequence,
					"actual": int(record.get("sequence", -1)),
				}
			expected_sequence += 1
			count += 1
	var expected_count := int(_head_metadata.get("archived_operation_count", 0))
	return {
		"ok": count == expected_count,
		"record_count": count,
		"segment_count": names.size(),
		"expected_count": expected_count,
	}


func get_head_metadata() -> Dictionary:
	return _head_metadata.duplicate(true)


func get_hot_stats() -> Dictionary:
	return {
		"head_read_count": head_read_count,
		"head_read_bytes": head_read_bytes,
		"pointer_read_count": pointer_read_count,
		"pointer_read_bytes": pointer_read_bytes,
		"tile_blob_read_count": tile_blob_read_count,
		"tile_blob_read_bytes": tile_blob_read_bytes,
		"tile_cache_hit_count": tile_cache_hit_count,
		"journal_read_count": journal_read_count,
		"journal_read_bytes": journal_read_bytes,
	}


func reset_hot_stats() -> void:
	head_read_count = 0
	head_read_bytes = 0
	pointer_read_count = 0
	pointer_read_bytes = 0
	tile_blob_read_count = 0
	tile_blob_read_bytes = 0
	tile_cache_hit_count = 0
	journal_read_count = 0
	journal_read_bytes = 0


func clear_tile_cache() -> void:
	_pointer_cache.clear()
	_tile_cache.clear()


func _read_head(count_metrics: bool) -> Dictionary:
	var path := _world_directory.path_join(HEAD_FILE)
	if not FileAccess.file_exists(path):
		return {"ok": true, "found": false}
	var bytes := FileAccess.get_file_as_bytes(path)
	if count_metrics:
		head_read_count += 1
		head_read_bytes += bytes.size()
	if bytes.is_empty():
		return {"ok": false, "found": true, "reason": "head_empty"}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "found": true, "reason": "head_decode_failure"}
	return {"ok": true, "found": true, "metadata": parsed}


func _read_effective_pointer(
	path: String,
	committed_generation: int,
	count_metrics: bool
) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "found": false}
	var bytes := FileAccess.get_file_as_bytes(path)
	if count_metrics:
		pointer_read_count += 1
		pointer_read_bytes += bytes.size()
	if bytes.is_empty():
		return {"ok": false, "found": false, "reason": "pointer_empty"}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "found": false, "reason": "pointer_decode_failure"}
	var payload: Dictionary = parsed
	for key in ["current", "previous"]:
		var value: Variant = payload.get(key, {})
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		if entry.is_empty():
			continue
		if int(entry.get("generation", -1)) <= committed_generation:
			return {"ok": true, "found": true, "entry": entry}
	return {"ok": true, "found": false}


func _validate_head(head: Dictionary) -> bool:
	return String(head.get("format", "")) == FORMAT_ID 		and int(head.get("schema_version", -1)) == SCHEMA_VERSION 		and String(head.get("world_id", "")) == WORLD_ID 		and int(head.get("generator_version", -1)) == Field.GENERATOR_VERSION 		and int(head.get("generation", -1)) >= 1 		and int(head.get("revision", -1)) >= 0 		and int(head.get("next_sequence", -1)) >= 0 		and int(head.get("lifetime_operation_count", -1)) >= 0 		and int(head.get("archived_operation_count", -1)) >= 0 		and int(head.get("archived_operation_count", -1)) 			<= int(head.get("lifetime_operation_count", -1))


func _validate_tile(
	tile: Dictionary,
	region_key: Vector2i,
	coordinate: Vector2i,
	tile_id: String
) -> bool:
	if String(tile.get("format", "")) != "materialized-sdf-tile" 		or int(tile.get("format_version", -1)) != 1 		or String(tile.get("tile_id", "")) != tile_id:
		return false
	if tile.get("region_key", Vector2i(999999, 999999)) != region_key 		or tile.get("coordinate", Vector2i(-1, -1)) != coordinate:
		return false
	var dims: Vector3i = tile.get("dims", Vector3i.ZERO)
	var values: PackedFloat32Array = tile.get("values", PackedFloat32Array())
	return dims == Vector3i(
		Grid.CELLS_PER_CHUNK_X + 1,
		Grid.CELL_COUNT_Y + 1,
		Grid.CELLS_PER_CHUNK_Z + 1
	) and is_equal_approx(float(tile.get("step", 0.0)), State.MATERIALIZED_STEP) 		and values.size() == dims.x * dims.y * dims.z


func _ensure_layout() -> int:
	var result := DirAccess.make_dir_recursive_absolute(_world_directory)
	if result != OK and result != ERR_ALREADY_EXISTS:
		return result
	for child in ["journal", "blobs", "pointers"]:
		result = DirAccess.make_dir_recursive_absolute(_world_directory.path_join(child))
		if result != OK and result != ERR_ALREADY_EXISTS:
			return result
	return OK


func _pointer_path(region_key: Vector2i, coordinate: Vector2i) -> String:
	var region_dir := "r_%d_%d" % [region_key.x, region_key.y]
	var filename := "c_%d_%d.json" % [coordinate.x, coordinate.y]
	return _world_directory.path_join("pointers").path_join(region_dir).path_join(filename)


func _write_immutable(path: String, bytes: PackedByteArray) -> Dictionary:
	if FileAccess.file_exists(path):
		var existing := FileAccess.get_file_as_bytes(path)
		if existing == bytes:
			return {"ok": true, "reused": true}
		return {"ok": false, "reason": "immutable_content_collision"}
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "immutable_directory_unavailable_%d" % directory_error}
	var temporary := "%s.tmp-%d-%d" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "immutable_write_open_failed_%d" % FileAccess.get_open_error()}
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(temporary) != bytes:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "reason": "immutable_write_readback_failed_%d" % error}
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "reason": "immutable_rename_failed_%d" % rename_error}
	return {"ok": true, "reused": false}


func _write_replace(path: String, bytes: PackedByteArray) -> Dictionary:
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "replace_directory_unavailable_%d" % directory_error}
	var temporary := "%s.tmp-%d-%d" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "replace_write_open_failed_%d" % FileAccess.get_open_error()}
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(temporary) != bytes:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "reason": "replace_write_readback_failed_%d" % error}
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(path)
		if remove_error != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "reason": "replace_remove_failed_%d" % remove_error}
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "reason": "replace_rename_failed_%d" % rename_error}
	return {"ok": true}


func _canonical_json_bytes(value: Variant) -> PackedByteArray:
	return JSON.stringify(value, "", true, true).to_utf8_buffer()


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
