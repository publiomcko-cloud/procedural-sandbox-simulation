class_name TerrainObjectEffectLocalIndex
extends RefCounted

## Precision-safe spatial index for region-local terrain-object effect frames.
## No global floating-point coordinates are constructed.
const Frame := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

const INDEX_VERSION := 1
const MAX_EFFECTS := 20064
const MAX_CHUNKS_PER_EFFECT := 256
const CHUNK_WIDTH := float(Grid.CELLS_PER_CHUNK_X) * Grid.SAMPLE_STEP
const CHUNK_DEPTH := float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
const INDEX_HALO := Grid.SAMPLE_STEP

var _frames: Dictionary = {}
var _chunks_by_effect: Dictionary = {}
var _effect_ids_by_chunk: Dictionary = {}


func replace_frame(frame: Dictionary) -> Dictionary:
	var checked := Frame.validate_frame(frame)
	if not checked.get("ok", false):
		return checked
	var normalized: Dictionary = checked["frame"]
	var effect_id := String(normalized["effect_id"])
	if not _frames.has(effect_id) and _frames.size() >= MAX_EFFECTS:
		return _failure("terrain_effect_local_index_capacity_exceeded")
	var chunk_keys := _chunk_keys_for_frame(normalized)
	if not chunk_keys.get("ok", false):
		return chunk_keys
	_remove_membership(effect_id)
	_frames[effect_id] = normalized.duplicate(true)
	_chunks_by_effect[effect_id] = chunk_keys["keys"].duplicate()
	for key_value in chunk_keys["keys"]:
		var key := String(key_value)
		var ids: Array = _effect_ids_by_chunk.get(key, [])
		if not ids.has(effect_id):
			ids.append(effect_id)
			ids.sort()
		_effect_ids_by_chunk[key] = ids
	return {
		"ok": true,
		"effect_id": effect_id,
		"indexed_chunk_count": (chunk_keys["keys"] as Array).size(),
	}


func remove_frame(effect_id: String) -> Dictionary:
	if not _frames.has(effect_id):
		return {"ok": true, "removed": false, "effect_id": effect_id}
	_remove_membership(effect_id)
	_frames.erase(effect_id)
	return {"ok": true, "removed": true, "effect_id": effect_id}


func get_frames_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not Grid.is_valid_coordinate(chunk_coordinate):
		return result
	var key := Grid.stable_id(region_key, chunk_coordinate)
	for id_value in _effect_ids_by_chunk.get(key, []):
		var effect_id := String(id_value)
		if _frames.has(effect_id):
			result.append((_frames[effect_id] as Dictionary).duplicate(true))
	return result


func get_effect_ids_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Array[String]:
	var result: Array[String] = []
	if not Grid.is_valid_coordinate(chunk_coordinate):
		return result
	var key := Grid.stable_id(region_key, chunk_coordinate)
	for id_value in _effect_ids_by_chunk.get(key, []):
		result.append(String(id_value))
	return result


func get_indexed_chunk_ids(effect_id: String) -> Array[String]:
	var result: Array[String] = []
	for value in _chunks_by_effect.get(effect_id, []):
		result.append(String(value))
	return result


func get_frame(effect_id: String) -> Dictionary:
	return (_frames.get(effect_id, {}) as Dictionary).duplicate(true)


func get_frame_count() -> int:
	return _frames.size()


func snapshot_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Dictionary:
	if not Grid.is_valid_coordinate(chunk_coordinate):
		return _failure("terrain_effect_local_snapshot_chunk_invalid")
	var frames := get_frames_for_chunk(region_key, chunk_coordinate)
	var fingerprints: Array[String] = []
	for frame in frames:
		fingerprints.append(String(frame["source_fingerprint_sha256"]))
	return {
		"ok": true,
		"index_version": INDEX_VERSION,
		"region_key": region_key,
		"chunk_coordinate": chunk_coordinate,
		"frames": frames,
		"frame_count": frames.size(),
		"snapshot_sha256": JSON.stringify({
			"index_version": INDEX_VERSION,
			"chunk_id": Grid.stable_id(region_key, chunk_coordinate),
			"effect_ids": get_effect_ids_for_chunk(region_key, chunk_coordinate),
			"fingerprints": fingerprints,
		}, "", true, true).sha256_text(),
	}


func clear() -> void:
	_frames.clear()
	_chunks_by_effect.clear()
	_effect_ids_by_chunk.clear()


func _chunk_keys_for_frame(frame: Dictionary) -> Dictionary:
	var bounds_result := Frame.bounds_local(frame)
	if not bounds_result.get("ok", false):
		return bounds_result
	var frame_region: Vector2i = bounds_result["frame_region_key"]
	var minimum: Vector3 = bounds_result["min"]
	var maximum: Vector3 = bounds_result["max"]
	if maximum.y < Grid.MIN_BOUND.y - INDEX_HALO 		or minimum.y > Grid.MAX_BOUND.y + INDEX_HALO:
		return {"ok": true, "keys": []}

	var min_local_chunk_x := floori((minimum.x - INDEX_HALO) / CHUNK_WIDTH)
	var max_local_chunk_x := floori((maximum.x + INDEX_HALO) / CHUNK_WIDTH)
	var min_local_chunk_z := floori((minimum.z - INDEX_HALO) / CHUNK_DEPTH)
	var max_local_chunk_z := floori((maximum.z + INDEX_HALO) / CHUNK_DEPTH)
	var estimated := (
		(max_local_chunk_x - min_local_chunk_x + 1)
		* (max_local_chunk_z - min_local_chunk_z + 1)
	)
	if estimated < 0 or estimated > MAX_CHUNKS_PER_EFFECT:
		return _failure("terrain_effect_local_spatial_budget_exceeded")

	var keys: Array[String] = []
	var frame_global_chunk_x: int = frame_region.x * Grid.CHUNK_COUNT_X
	var frame_global_chunk_z: int = frame_region.y * Grid.CHUNK_COUNT_Z
	for local_chunk_z in range(min_local_chunk_z, max_local_chunk_z + 1):
		var global_chunk_z := frame_global_chunk_z + local_chunk_z
		var region_z := _floor_divide(global_chunk_z, Grid.CHUNK_COUNT_Z)
		var local_z := global_chunk_z - region_z * Grid.CHUNK_COUNT_Z
		for local_chunk_x in range(min_local_chunk_x, max_local_chunk_x + 1):
			var global_chunk_x := frame_global_chunk_x + local_chunk_x
			var region_x := _floor_divide(global_chunk_x, Grid.CHUNK_COUNT_X)
			var local_x := global_chunk_x - region_x * Grid.CHUNK_COUNT_X
			var coordinate := Vector2i(local_x, local_z)
			if not Grid.is_valid_coordinate(coordinate):
				return _failure("terrain_effect_local_chunk_mapping_invalid")
			keys.append(
				Grid.stable_id(Vector2i(region_x, region_z), coordinate)
			)
	keys.sort()
	return {"ok": true, "keys": keys}


func _remove_membership(effect_id: String) -> void:
	for key_value in _chunks_by_effect.get(effect_id, []):
		var key := String(key_value)
		var ids: Array = _effect_ids_by_chunk.get(key, [])
		ids.erase(effect_id)
		if ids.is_empty():
			_effect_ids_by_chunk.erase(key)
		else:
			_effect_ids_by_chunk[key] = ids
	_chunks_by_effect.erase(effect_id)


func _floor_divide(value: int, divisor: int) -> int:
	var quotient: int = value / divisor
	if value < 0 and value % divisor != 0:
		quotient -= 1
	return quotient


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
