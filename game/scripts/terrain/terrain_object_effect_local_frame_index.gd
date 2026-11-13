class_name TerrainObjectEffectLocalFrameIndex
extends RefCounted

## Bounded chunk index over source-region-local effect frames.
## Absolute world-space floating-point coordinates are never constructed.
const Frame := preload("res://scripts/terrain/terrain_object_effect_local_frame.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

const MAX_FRAMES := 20064
const MAX_CHUNKS_PER_FRAME := 256
const CHUNK_WIDTH := float(Grid.CELLS_PER_CHUNK_X) * Grid.SAMPLE_STEP
const CHUNK_DEPTH := float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
const INDEX_HALO := Grid.SAMPLE_STEP

var _frames: Dictionary = {}
var _chunks_by_frame: Dictionary = {}
var _frame_ids_by_chunk: Dictionary = {}


func replace_frame(frame_value: Dictionary) -> Dictionary:
	var checked := Frame.validate_frame(frame_value)
	if not checked.get("ok", false):
		return checked
	var frame: Dictionary = checked["frame"]
	var effect_id := String(frame["effect_id"])
	if not _frames.has(effect_id) and _frames.size() >= MAX_FRAMES:
		return _failure("terrain_effect_frame_index_capacity_exceeded")
	var keys_result := _chunk_keys_for_frame(frame)
	if not keys_result.get("ok", false):
		return keys_result
	_remove_membership(effect_id)
	_frames[effect_id] = frame
	_chunks_by_frame[effect_id] = keys_result["keys"].duplicate()
	for key_value in keys_result["keys"]:
		var key := String(key_value)
		var ids: Array = _frame_ids_by_chunk.get(key, [])
		if not ids.has(effect_id):
			ids.append(effect_id)
			ids.sort()
		_frame_ids_by_chunk[key] = ids
	return {
		"ok": true,
		"effect_id": effect_id,
		"indexed_chunk_count": keys_result["keys"].size(),
	}


func replace_frame_prevalidated(frame: Dictionary) -> Dictionary:
	var effect_id := String(frame.get("effect_id", ""))
	if effect_id.is_empty():
		return _failure("terrain_effect_frame_index_identity_invalid")
	if not _frames.has(effect_id) and _frames.size() >= MAX_FRAMES:
		return _failure("terrain_effect_frame_index_capacity_exceeded")
	var keys_result := _chunk_keys_for_frame_prevalidated(frame)
	if not keys_result.get("ok", false):
		return keys_result
	_remove_membership(effect_id)
	_frames[effect_id] = frame.duplicate(true)
	_chunks_by_frame[effect_id] = keys_result["keys"].duplicate()
	for key_value in keys_result["keys"]:
		var key := String(key_value)
		var ids: Array = _frame_ids_by_chunk.get(key, [])
		if not ids.has(effect_id):
			ids.append(effect_id)
			ids.sort()
		_frame_ids_by_chunk[key] = ids
	return {
		"ok": true,
		"effect_id": effect_id,
		"indexed_chunk_count": keys_result["keys"].size(),
	}


func get_frames_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not Grid.is_valid_coordinate(chunk_coordinate):
		return result
	var key := Grid.stable_id(region_key, chunk_coordinate)
	for id_value in _frame_ids_by_chunk.get(key, []):
		var effect_id := String(id_value)
		if _frames.has(effect_id):
			result.append((_frames[effect_id] as Dictionary).duplicate(true))
	return result


func get_frame_ids_for_chunk(
	region_key: Vector2i,
	chunk_coordinate: Vector2i
) -> Array[String]:
	var ids: Array[String] = []
	if not Grid.is_valid_coordinate(chunk_coordinate):
		return ids
	var key := Grid.stable_id(region_key, chunk_coordinate)
	for id_value in _frame_ids_by_chunk.get(key, []):
		ids.append(String(id_value))
	return ids


func get_indexed_chunk_ids(effect_id: String) -> Array[String]:
	var result: Array[String] = []
	for value in _chunks_by_frame.get(effect_id, []):
		result.append(String(value))
	return result


func get_all_indexed_chunk_ids() -> Array[String]:
	var ids: Array[String] = []
	for chunk_id in _frame_ids_by_chunk:
		ids.append(String(chunk_id))
	ids.sort()
	return ids


## DM14: cleanup order is not semantically observable. Avoid sorting all
## source chunk keys when detaching inactive derived reverse routes.
func get_all_indexed_chunk_ids_unsorted() -> Array[String]:
	var ids: Array[String] = []
	for chunk_id in _frame_ids_by_chunk:
		ids.append(String(chunk_id))
	return ids


func get_frame_count() -> int:
	return _frames.size()


func clear() -> void:
	_frames.clear()
	_chunks_by_frame.clear()
	_frame_ids_by_chunk.clear()


func _chunk_keys_for_frame(frame: Dictionary) -> Dictionary:
	var bounds := Frame.bounds_local(frame)
	if not bounds.get("ok", false):
		return bounds
	return _chunk_keys_for_bounds(
		bounds["source_region_key"], bounds["min"], bounds["max"]
	)


func _chunk_keys_for_frame_prevalidated(frame: Dictionary) -> Dictionary:
	var source_values: Array = frame["source_region_key"]
	return _chunk_keys_for_bounds(
		Vector2i(int(source_values[0]), int(source_values[1])),
		_array_to_vector3(frame["bounds_min_local"]),
		_array_to_vector3(frame["bounds_max_local"])
	)


func _chunk_keys_for_bounds(
	source_region: Vector2i,
	minimum: Vector3,
	maximum: Vector3
) -> Dictionary:
	if not minimum.is_finite() or not maximum.is_finite() 		or minimum.x > maximum.x 		or minimum.y > maximum.y 		or minimum.z > maximum.z:
		return _failure("terrain_effect_frame_bounds_invalid")
	if maximum.y < Grid.MIN_BOUND.y - INDEX_HALO 		or minimum.y > Grid.MAX_BOUND.y + INDEX_HALO:
		return {"ok": true, "keys": []}

	var min_local_chunk_x := floori((minimum.x - INDEX_HALO) / CHUNK_WIDTH)
	var max_local_chunk_x := floori((maximum.x + INDEX_HALO) / CHUNK_WIDTH)
	var min_local_chunk_z := floori((minimum.z - INDEX_HALO) / CHUNK_DEPTH)
	var max_local_chunk_z := floori((maximum.z + INDEX_HALO) / CHUNK_DEPTH)
	var estimated := (max_local_chunk_x - min_local_chunk_x + 1) 		* (max_local_chunk_z - min_local_chunk_z + 1)
	if estimated < 0 or estimated > MAX_CHUNKS_PER_FRAME:
		return _failure("terrain_effect_frame_spatial_budget_exceeded")

	var source_world_chunk_x: int = source_region.x * Grid.CHUNK_COUNT_X
	var source_world_chunk_z: int = source_region.y * Grid.CHUNK_COUNT_Z
	var keys: Array[String] = []
	for local_chunk_z in range(min_local_chunk_z, max_local_chunk_z + 1):
		var world_chunk_z := source_world_chunk_z + local_chunk_z
		var target_region_z := _floor_divide(world_chunk_z, Grid.CHUNK_COUNT_Z)
		var target_local_z := world_chunk_z - target_region_z * Grid.CHUNK_COUNT_Z
		for local_chunk_x in range(min_local_chunk_x, max_local_chunk_x + 1):
			var world_chunk_x := source_world_chunk_x + local_chunk_x
			var target_region_x := _floor_divide(world_chunk_x, Grid.CHUNK_COUNT_X)
			var target_local_x := world_chunk_x - target_region_x * Grid.CHUNK_COUNT_X
			var coordinate := Vector2i(target_local_x, target_local_z)
			if not Grid.is_valid_coordinate(coordinate):
				return _failure("terrain_effect_frame_chunk_mapping_invalid")
			keys.append(Grid.stable_id(
				Vector2i(target_region_x, target_region_z), coordinate
			))
	keys.sort()
	return {"ok": true, "keys": keys}


func _array_to_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _remove_membership(effect_id: String) -> void:
	for key_value in _chunks_by_frame.get(effect_id, []):
		var key := String(key_value)
		var ids: Array = _frame_ids_by_chunk.get(key, [])
		ids.erase(effect_id)
		if ids.is_empty():
			_frame_ids_by_chunk.erase(key)
		else:
			_frame_ids_by_chunk[key] = ids
	_chunks_by_frame.erase(effect_id)


func _floor_divide(value: int, divisor: int) -> int:
	var quotient: int = value / divisor
	if value < 0 and value % divisor != 0:
		quotient -= 1
	return quotient


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
