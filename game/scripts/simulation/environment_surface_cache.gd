extends RefCounted
class_name EnvironmentSurfaceCache

## P5.0C transient derived terrain-surface cache.
## Canonical terrain remains the SDF/edit authority. Records here are disposable
## and are never part of the runtime persistence snapshot.

const DEFAULT_GRID_WIDTH := 8
const DEFAULT_GRID_HEIGHT := 6
const DEFAULT_CELL_SIZE_X_MM := 2000
const DEFAULT_CELL_SIZE_Z_MM := 2000
const MAX_SCOPES_HARD := 1_000_000
const MAX_ABS_HEIGHT_MM := 1_000_000_000
const MAX_SLOPE_MILLI := 10_000_000
const NEIGHBOR_COUNT := 4

const RECORD_FIELDS := [
	"scope_id",
	"region_key",
	"world_seed",
	"generator_version",
	"terrain_revision",
	"terrain_cache_scope_id",
	"terrain_effect_revision",
	"grid_width",
	"grid_height",
	"cell_size_x_mm",
	"cell_size_z_mm",
	"surface_valid",
	"surface_height_mm",
	"slope_milli",
	"neighbor_mask",
	"neighbor_delta_mm",
	"downhill_neighbor",
	"downhill_drop_mm",
]

var _initialized := false
var _max_scopes := 0
var _expected: Dictionary = {}
var _records: Dictionary = {}

var _expectations_total := 0
var _invalidations_total := 0
var _publications_total := 0
var _publication_noops_total := 0
var _stale_rejections_total := 0
var _discard_total := 0
var _peak_records := 0


func initialize(max_scopes: int) -> Dictionary:
	if _initialized:
		return _failure("surface_cache_already_initialized")
	if max_scopes < 1 or max_scopes > MAX_SCOPES_HARD:
		return _failure("surface_cache_scope_limit_invalid")
	_max_scopes = max_scopes
	_expected.clear()
	_records.clear()
	_reset_metrics()
	_initialized = true
	return {"ok": true, "reason": "ok"}


func is_initialized() -> bool:
	return _initialized


func expect_scope(
	scope_id: String,
	region_key: Vector2i,
	world_seed: int,
	generator_version: int,
	terrain_revision: int,
	terrain_cache_scope_id: int,
	terrain_effect_revision: int
) -> Dictionary:
	if not _initialized:
		return _failure("surface_cache_not_initialized")
	if not _valid_scope_id(scope_id):
		return _failure("surface_cache_scope_id_invalid")
	if generator_version < 0 or terrain_revision < 0 or terrain_cache_scope_id <= 0 		or terrain_effect_revision < 0:
		return _failure("surface_cache_provenance_invalid")
	if not _expected.has(scope_id) and _expected.size() >= _max_scopes:
		return _failure("surface_cache_scope_limit_reached")
	var token := _token(
		scope_id,
		region_key,
		world_seed,
		generator_version,
		terrain_revision,
		terrain_cache_scope_id,
		terrain_effect_revision
	)
	var previous: Dictionary = _expected.get(scope_id, {})
	_expectations_total += 1
	if previous == token:
		return {"ok": true, "reason": "ok", "noop": true, "token": token.duplicate(true)}
	if _records.has(scope_id):
		_records.erase(scope_id)
		_invalidations_total += 1
	_expected[scope_id] = token
	return {"ok": true, "reason": "ok", "noop": false, "token": token.duplicate(true)}


func publish(record: Dictionary) -> Dictionary:
	if not _initialized:
		return _failure("surface_cache_not_initialized")
	var validation := _validate_record(record)
	if not validation.get("ok", false):
		return validation
	var scope_id := String(record["scope_id"])
	if not _expected.has(scope_id):
		_stale_rejections_total += 1
		return _failure("surface_cache_scope_not_expected")
	var expected: Dictionary = _expected[scope_id]
	var actual := _token(
		scope_id,
		record["region_key"],
		int(record["world_seed"]),
		int(record["generator_version"]),
		int(record["terrain_revision"]),
		int(record["terrain_cache_scope_id"]),
		int(record["terrain_effect_revision"])
	)
	if actual != expected:
		_stale_rejections_total += 1
		return _failure("surface_cache_result_stale")
	var prepared := _copy_record(record)
	if _records.has(scope_id) and _records[scope_id] == prepared:
		_publication_noops_total += 1
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"record": _copy_record(_records[scope_id]),
		}
	_records[scope_id] = prepared
	_publications_total += 1
	_peak_records = maxi(_peak_records, _records.size())
	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"record": _copy_record(prepared),
	}


func discard_scope(scope_id: String) -> Dictionary:
	if not _initialized:
		return _failure("surface_cache_not_initialized")
	if not _valid_scope_id(scope_id):
		return _failure("surface_cache_scope_id_invalid")
	var changed := _expected.erase(scope_id)
	changed = _records.erase(scope_id) or changed
	if changed:
		_discard_total += 1
	return {"ok": true, "reason": "ok", "noop": not changed}


func get_scope(scope_id: String) -> Dictionary:
	if not _initialized or not _records.has(scope_id):
		return {}
	return _copy_record(_records[scope_id])


func has_scope(scope_id: String) -> bool:
	return _initialized and _records.has(scope_id)


func get_expected_token(scope_id: String) -> Dictionary:
	if not _initialized or not _expected.has(scope_id):
		return {}
	return (_expected[scope_id] as Dictionary).duplicate(true)


func get_scope_count() -> int:
	return _records.size() if _initialized else 0


func clear_transient() -> void:
	_expected.clear()
	_records.clear()


func get_metrics() -> Dictionary:
	return {
		"initialized": _initialized,
		"record_count": _records.size(),
		"expected_scope_count": _expected.size(),
		"max_scopes": _max_scopes,
		"expectations_total": _expectations_total,
		"invalidations_total": _invalidations_total,
		"publications_total": _publications_total,
		"publication_noops_total": _publication_noops_total,
		"stale_rejections_total": _stale_rejections_total,
		"discard_total": _discard_total,
		"peak_records": _peak_records,
	}


func _validate_record(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, RECORD_FIELDS):
		return _failure("surface_cache_record_fields_invalid")
	if typeof(record["scope_id"]) != TYPE_STRING or not _valid_scope_id(String(record["scope_id"])):
		return _failure("surface_cache_scope_id_invalid")
	if typeof(record["region_key"]) != TYPE_VECTOR2I:
		return _failure("surface_cache_region_key_invalid")
	for field in [
		"world_seed",
		"generator_version",
		"terrain_revision",
		"terrain_cache_scope_id",
		"terrain_effect_revision",
		"grid_width",
		"grid_height",
		"cell_size_x_mm",
		"cell_size_z_mm",
	]:
		if typeof(record[field]) != TYPE_INT:
			return _failure("surface_cache_record_integer_invalid")
	if int(record["generator_version"]) < 0 or int(record["terrain_revision"]) < 0 		or int(record["terrain_cache_scope_id"]) <= 0 or int(record["terrain_effect_revision"]) < 0:
		return _failure("surface_cache_provenance_invalid")
	if int(record["grid_width"]) != DEFAULT_GRID_WIDTH 		or int(record["grid_height"]) != DEFAULT_GRID_HEIGHT 		or int(record["cell_size_x_mm"]) != DEFAULT_CELL_SIZE_X_MM 		or int(record["cell_size_z_mm"]) != DEFAULT_CELL_SIZE_Z_MM:
		return _failure("surface_cache_grid_invalid")

	if typeof(record["surface_valid"]) != TYPE_PACKED_BYTE_ARRAY 		or typeof(record["surface_height_mm"]) != TYPE_PACKED_INT64_ARRAY 		or typeof(record["slope_milli"]) != TYPE_PACKED_INT32_ARRAY 		or typeof(record["neighbor_mask"]) != TYPE_PACKED_BYTE_ARRAY 		or typeof(record["neighbor_delta_mm"]) != TYPE_PACKED_INT64_ARRAY 		or typeof(record["downhill_neighbor"]) != TYPE_PACKED_INT32_ARRAY 		or typeof(record["downhill_drop_mm"]) != TYPE_PACKED_INT64_ARRAY:
		return _failure("surface_cache_array_type_invalid")

	var cell_count := DEFAULT_GRID_WIDTH * DEFAULT_GRID_HEIGHT
	if record["surface_valid"].size() != cell_count 		or record["surface_height_mm"].size() != cell_count 		or record["slope_milli"].size() != cell_count 		or record["neighbor_mask"].size() != cell_count 		or record["neighbor_delta_mm"].size() != cell_count * NEIGHBOR_COUNT 		or record["downhill_neighbor"].size() != cell_count 		or record["downhill_drop_mm"].size() != cell_count:
		return _failure("surface_cache_array_size_invalid")

	for index in range(cell_count):
		var valid := int(record["surface_valid"][index])
		if valid != 0 and valid != 1:
			return _failure("surface_cache_validity_invalid")
		if absi(int(record["surface_height_mm"][index])) > MAX_ABS_HEIGHT_MM:
			return _failure("surface_cache_height_invalid")
		var slope := int(record["slope_milli"][index])
		if slope < 0 or slope > MAX_SLOPE_MILLI:
			return _failure("surface_cache_slope_invalid")
		var mask := int(record["neighbor_mask"][index])
		if mask < 0 or mask > 15:
			return _failure("surface_cache_neighbor_mask_invalid")
		var downhill := int(record["downhill_neighbor"][index])
		if downhill < -1 or downhill >= cell_count:
			return _failure("surface_cache_downhill_neighbor_invalid")
		if int(record["downhill_drop_mm"][index]) < 0:
			return _failure("surface_cache_downhill_drop_invalid")
	return {"ok": true, "reason": "ok"}


func _token(
	scope_id: String,
	region_key: Vector2i,
	world_seed: int,
	generator_version: int,
	terrain_revision: int,
	terrain_cache_scope_id: int,
	terrain_effect_revision: int
) -> Dictionary:
	return {
		"scope_id": scope_id,
		"region_key": region_key,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"terrain_revision": terrain_revision,
		"terrain_cache_scope_id": terrain_cache_scope_id,
		"terrain_effect_revision": terrain_effect_revision,
	}


func _copy_record(record: Dictionary) -> Dictionary:
	return {
		"scope_id": String(record["scope_id"]),
		"region_key": record["region_key"],
		"world_seed": int(record["world_seed"]),
		"generator_version": int(record["generator_version"]),
		"terrain_revision": int(record["terrain_revision"]),
		"terrain_cache_scope_id": int(record["terrain_cache_scope_id"]),
		"terrain_effect_revision": int(record["terrain_effect_revision"]),
		"grid_width": int(record["grid_width"]),
		"grid_height": int(record["grid_height"]),
		"cell_size_x_mm": int(record["cell_size_x_mm"]),
		"cell_size_z_mm": int(record["cell_size_z_mm"]),
		"surface_valid": (record["surface_valid"] as PackedByteArray).duplicate(),
		"surface_height_mm": (record["surface_height_mm"] as PackedInt64Array).duplicate(),
		"slope_milli": (record["slope_milli"] as PackedInt32Array).duplicate(),
		"neighbor_mask": (record["neighbor_mask"] as PackedByteArray).duplicate(),
		"neighbor_delta_mm": (record["neighbor_delta_mm"] as PackedInt64Array).duplicate(),
		"downhill_neighbor": (record["downhill_neighbor"] as PackedInt32Array).duplicate(),
		"downhill_drop_mm": (record["downhill_drop_mm"] as PackedInt64Array).duplicate(),
	}


func _valid_scope_id(scope_id: String) -> bool:
	if not scope_id.begins_with("region:"):
		return false
	var coordinates := scope_id.trim_prefix("region:").split(",")
	if coordinates.size() != 2:
		return false
	return coordinates[0].is_valid_int() and coordinates[1].is_valid_int()


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field in fields:
		if not value.has(field):
			return false
	return true


func _reset_metrics() -> void:
	_expectations_total = 0
	_invalidations_total = 0
	_publications_total = 0
	_publication_noops_total = 0
	_stale_rejections_total = 0
	_discard_total = 0
	_peak_records = 0


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
