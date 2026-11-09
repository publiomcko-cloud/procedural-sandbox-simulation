extends RefCounted

## P5.0A authoritative environmental state store.
##
## One record is keyed by the existing P4 simulation scope id (region:x,z).
## The store owns only deterministic integer authority. Terrain/surface samples,
## worker products and rendering are derived elsewhere and are never persisted.
##
## Reservoir cells model rivers/oceans as infinite fixed-level boundaries:
## they never carry finite surface/soil volume. Exchange with those cells is
## accounted through cumulative inflow/outflow counters without changing the
## reservoir level or finite stored volume.

const SNAPSHOT_SCHEMA_VERSION := 1

const DEFAULT_GRID_WIDTH := 8
const DEFAULT_GRID_HEIGHT := 6
const MIN_GRID_AXIS := 1
const MAX_GRID_AXIS := 64
const MAX_CELL_COUNT := 4096

const DEFAULT_MAX_SCOPES := 65_536
const MAX_SCOPES_HARD := 1_000_000
const MAX_SCOPE_ID_LENGTH := 256

const RESERVOIR_FINITE := 0
const RESERVOIR_RIVER := 1
const RESERVOIR_OCEAN := 2
const VALID_RESERVOIR_KINDS := [
	RESERVOIR_FINITE,
	RESERVOIR_RIVER,
	RESERVOIR_OCEAN,
]

const MAX_ABS_RESERVOIR_LEVEL_MM := 1_000_000_000
const MAX_WATER_UL_PER_CELL := 1_000_000_000_000_000
const MAX_EXCHANGE_TOTAL_UL := 8_000_000_000_000_000_000

const SNAPSHOT_FIELDS := [
	"schema_version",
	"grid_width",
	"grid_height",
	"max_scopes",
	"scopes",
]
const RECORD_FIELDS := [
	"scope_id",
	"state_revision",
	"profile_id",
	"profile_sha256",
	"last_environment_tick",
	"surface_water_ul",
	"soil_water_ul",
	"reservoir_kind",
	"reservoir_level_mm",
	"reservoir_inflow_ul_total",
	"reservoir_outflow_ul_total",
]
const UPDATE_FIELDS := [
	"scope_id",
	"expected_state_revision",
	"last_environment_tick",
	"surface_water_ul",
	"soil_water_ul",
	"reservoir_kind",
	"reservoir_level_mm",
	"reservoir_inflow_ul_delta",
	"reservoir_outflow_ul_delta",
]

var _initialized := false
var _grid_width := DEFAULT_GRID_WIDTH
var _grid_height := DEFAULT_GRID_HEIGHT
var _cell_count := DEFAULT_GRID_WIDTH * DEFAULT_GRID_HEIGHT
var _max_scopes := DEFAULT_MAX_SCOPES
var _scopes: Dictionary = {}

var _registrations_total := 0
var _commit_batches_total := 0
var _committed_scopes_total := 0
var _commit_rejections_total := 0
var _snapshot_restores_total := 0


func initialize(
	grid_width: int = DEFAULT_GRID_WIDTH,
	grid_height: int = DEFAULT_GRID_HEIGHT,
	max_scopes: int = DEFAULT_MAX_SCOPES
) -> Dictionary:
	if _initialized:
		return _failure("environment_store_already_initialized")
	var config := _validate_config(grid_width, grid_height, max_scopes)
	if not config.get("ok", false):
		return config
	_grid_width = grid_width
	_grid_height = grid_height
	_cell_count = grid_width * grid_height
	_max_scopes = max_scopes
	_scopes.clear()
	_reset_metrics()
	_initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": get_authoritative_snapshot(),
	}


func is_initialized() -> bool:
	return _initialized


func get_grid_width() -> int:
	return _grid_width


func get_grid_height() -> int:
	return _grid_height


func get_cell_count() -> int:
	return _cell_count


func register_scope(
	scope_id: String,
	profile_id: String = "",
	profile_sha256: String = "",
	last_environment_tick: int = 0
) -> Dictionary:
	if not _initialized:
		return _failure("environment_store_not_initialized")
	if not _valid_scope_id(scope_id):
		return _failure("environment_scope_id_invalid")
	if _scopes.has(scope_id):
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"record": _public_record(_scopes[scope_id]),
		}
	if _scopes.size() >= _max_scopes:
		return _failure("environment_scope_limit_reached")
	if last_environment_tick < 0:
		return _failure("environment_tick_invalid")
	if not _valid_profile_pin(profile_id, profile_sha256):
		return _failure("environment_profile_pin_invalid")

	var record := {
		"scope_id": scope_id,
		"state_revision": 0,
		"profile_id": profile_id,
		"profile_sha256": profile_sha256,
		"last_environment_tick": last_environment_tick,
		"surface_water_ul": _zero_i64(),
		"soil_water_ul": _zero_i64(),
		"reservoir_kind": _zero_u8(),
		"reservoir_level_mm": _zero_i64(),
		"reservoir_inflow_ul_total": 0,
		"reservoir_outflow_ul_total": 0,
	}
	_scopes[scope_id] = record
	_registrations_total += 1
	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"record": _public_record(record),
	}


func has_scope(scope_id: String) -> bool:
	return _scopes.has(scope_id)


func get_scope(scope_id: String) -> Dictionary:
	if not _initialized or not _scopes.has(scope_id):
		return {}
	return _public_record(_scopes[scope_id])


func get_scope_count() -> int:
	return _scopes.size()


func commit_batch(updates: Array) -> Dictionary:
	if not _initialized:
		return _failure("environment_store_not_initialized")
	if updates.is_empty():
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"committed_scope_count": 0,
		}
	if updates.size() > _max_scopes:
		return _reject_commit("environment_commit_batch_too_large")

	var staged: Dictionary = {}
	for update_value in updates:
		if typeof(update_value) != TYPE_DICTIONARY:
			return _reject_commit("environment_update_invalid")
		var update: Dictionary = update_value
		if not _has_exact_fields(update, UPDATE_FIELDS):
			return _reject_commit("environment_update_fields_invalid")

		var scope_id_value: Variant = update.get("scope_id")
		if typeof(scope_id_value) != TYPE_STRING:
			return _reject_commit("environment_scope_id_invalid")
		var scope_id := String(scope_id_value)
		if not _scopes.has(scope_id):
			return _reject_commit("environment_scope_not_found")
		if staged.has(scope_id):
			return _reject_commit("environment_commit_duplicate_scope")
		if typeof(update.get("expected_state_revision")) != TYPE_INT:
			return _reject_commit("environment_expected_revision_invalid")
		if typeof(update.get("last_environment_tick")) != TYPE_INT:
			return _reject_commit("environment_tick_invalid")
		if typeof(update.get("reservoir_inflow_ul_delta")) != TYPE_INT:
			return _reject_commit("environment_reservoir_exchange_invalid")
		if typeof(update.get("reservoir_outflow_ul_delta")) != TYPE_INT:
			return _reject_commit("environment_reservoir_exchange_invalid")

		var current: Dictionary = _scopes[scope_id]
		if int(update["expected_state_revision"]) != int(current["state_revision"]):
			return _reject_commit("environment_state_revision_conflict")
		var next_tick := int(update["last_environment_tick"])
		if next_tick < int(current["last_environment_tick"]):
			return _reject_commit("environment_tick_not_monotonic")

		var arrays := _validate_state_arrays(
			update.get("surface_water_ul"),
			update.get("soil_water_ul"),
			update.get("reservoir_kind"),
			update.get("reservoir_level_mm")
		)
		if not arrays.get("ok", false):
			return _reject_commit(String(arrays.get("reason", "environment_state_invalid")))

		var inflow_delta := int(update["reservoir_inflow_ul_delta"])
		var outflow_delta := int(update["reservoir_outflow_ul_delta"])
		if inflow_delta < 0 or outflow_delta < 0:
			return _reject_commit("environment_reservoir_exchange_invalid")
		var current_inflow := int(current["reservoir_inflow_ul_total"])
		var current_outflow := int(current["reservoir_outflow_ul_total"])
		if (
			inflow_delta > MAX_EXCHANGE_TOTAL_UL - current_inflow
			or outflow_delta > MAX_EXCHANGE_TOTAL_UL - current_outflow
		):
			return _reject_commit("environment_reservoir_exchange_overflow")

		var next_record: Dictionary = current.duplicate(true)
		next_record["last_environment_tick"] = next_tick
		next_record["surface_water_ul"] = (update["surface_water_ul"] as PackedInt64Array).duplicate()
		next_record["soil_water_ul"] = (update["soil_water_ul"] as PackedInt64Array).duplicate()
		next_record["reservoir_kind"] = (update["reservoir_kind"] as PackedByteArray).duplicate()
		next_record["reservoir_level_mm"] = (update["reservoir_level_mm"] as PackedInt64Array).duplicate()
		next_record["reservoir_inflow_ul_total"] = current_inflow + inflow_delta
		next_record["reservoir_outflow_ul_total"] = current_outflow + outflow_delta
		if _same_mutable_state(current, next_record):
			next_record["state_revision"] = int(current["state_revision"])
		else:
			next_record["state_revision"] = int(current["state_revision"]) + 1
		staged[scope_id] = next_record

	var committed := 0
	var changed := 0
	var ids: Array = staged.keys()
	ids.sort()
	for scope_id_value in ids:
		var scope_id := String(scope_id_value)
		var before_revision := int(_scopes[scope_id]["state_revision"])
		var next_record: Dictionary = staged[scope_id]
		_scopes[scope_id] = next_record
		committed += 1
		if int(next_record["state_revision"]) != before_revision:
			changed += 1
	_commit_batches_total += 1
	_committed_scopes_total += committed
	return {
		"ok": true,
		"reason": "ok",
		"noop": changed == 0,
		"committed_scope_count": committed,
		"changed_scope_count": changed,
	}


func get_authoritative_snapshot() -> Dictionary:
	if not _initialized:
		return {}
	var ids: Array = _scopes.keys()
	ids.sort()
	var scopes: Array = []
	for scope_id_value in ids:
		scopes.append(_public_record(_scopes[String(scope_id_value)]))
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"grid_width": _grid_width,
		"grid_height": _grid_height,
		"max_scopes": _max_scopes,
		"scopes": scopes,
	}


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_fields(snapshot, SNAPSHOT_FIELDS):
		return _failure("environment_snapshot_fields_invalid")
	for field in ["schema_version", "grid_width", "grid_height", "max_scopes"]:
		if typeof(snapshot.get(field)) != TYPE_INT:
			return _failure("environment_snapshot_integer_invalid")
	if int(snapshot["schema_version"]) != SNAPSHOT_SCHEMA_VERSION:
		return _failure("environment_snapshot_schema_unsupported")
	var config := _validate_config(
		int(snapshot["grid_width"]),
		int(snapshot["grid_height"]),
		int(snapshot["max_scopes"])
	)
	if not config.get("ok", false):
		return config
	if typeof(snapshot.get("scopes")) != TYPE_ARRAY:
		return _failure("environment_snapshot_scopes_invalid")
	var scopes: Array = snapshot["scopes"]
	if scopes.size() > int(snapshot["max_scopes"]):
		return _failure("environment_snapshot_scope_limit")
	var expected_cells := int(snapshot["grid_width"]) * int(snapshot["grid_height"])
	var seen: Dictionary = {}
	var prior_scope_id := ""
	for record_value in scopes:
		if typeof(record_value) != TYPE_DICTIONARY:
			return _failure("environment_snapshot_record_invalid")
		var record: Dictionary = record_value
		var record_result := _validate_record(record, expected_cells)
		if not record_result.get("ok", false):
			return record_result
		var scope_id := String(record["scope_id"])
		if seen.has(scope_id):
			return _failure("environment_snapshot_duplicate_scope")
		if not prior_scope_id.is_empty() and scope_id < prior_scope_id:
			return _failure("environment_snapshot_scope_order_invalid")
		seen[scope_id] = true
		prior_scope_id = scope_id
	return {"ok": true, "reason": "ok"}


func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation := validate_snapshot(snapshot)
	if not validation.get("ok", false):
		return validation
	_grid_width = int(snapshot["grid_width"])
	_grid_height = int(snapshot["grid_height"])
	_cell_count = _grid_width * _grid_height
	_max_scopes = int(snapshot["max_scopes"])
	_scopes.clear()
	for record_value in snapshot["scopes"]:
		var record: Dictionary = record_value
		_scopes[String(record["scope_id"])] = _copy_record(record)
	_initialized = true
	_reset_metrics()
	_snapshot_restores_total = 1
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": get_authoritative_snapshot(),
	}


func get_metrics() -> Dictionary:
	if not _initialized:
		return {}
	var reservoir_cells := 0
	var river_cells := 0
	var ocean_cells := 0
	var finite_surface_water_ul := 0
	var finite_soil_water_ul := 0
	var reservoir_inflow_ul_total := 0
	var reservoir_outflow_ul_total := 0
	for record_value in _scopes.values():
		var record: Dictionary = record_value
		var kinds: PackedByteArray = record["reservoir_kind"]
		var surface: PackedInt64Array = record["surface_water_ul"]
		var soil: PackedInt64Array = record["soil_water_ul"]
		for index in range(_cell_count):
			var kind := int(kinds[index])
			if kind == RESERVOIR_RIVER:
				reservoir_cells += 1
				river_cells += 1
			elif kind == RESERVOIR_OCEAN:
				reservoir_cells += 1
				ocean_cells += 1
			else:
				finite_surface_water_ul += int(surface[index])
				finite_soil_water_ul += int(soil[index])
		reservoir_inflow_ul_total += int(record["reservoir_inflow_ul_total"])
		reservoir_outflow_ul_total += int(record["reservoir_outflow_ul_total"])
	return {
		"grid_width": _grid_width,
		"grid_height": _grid_height,
		"cell_count": _cell_count,
		"max_scopes": _max_scopes,
		"scope_count": _scopes.size(),
		"reservoir_cells": reservoir_cells,
		"river_cells": river_cells,
		"ocean_cells": ocean_cells,
		"finite_surface_water_ul": finite_surface_water_ul,
		"finite_soil_water_ul": finite_soil_water_ul,
		"reservoir_inflow_ul_total": reservoir_inflow_ul_total,
		"reservoir_outflow_ul_total": reservoir_outflow_ul_total,
		"registrations_total": _registrations_total,
		"commit_batches_total": _commit_batches_total,
		"committed_scopes_total": _committed_scopes_total,
		"commit_rejections_total": _commit_rejections_total,
		"snapshot_restores_total": _snapshot_restores_total,
	}


func _validate_config(grid_width: int, grid_height: int, max_scopes: int) -> Dictionary:
	if (
		grid_width < MIN_GRID_AXIS
		or grid_width > MAX_GRID_AXIS
		or grid_height < MIN_GRID_AXIS
		or grid_height > MAX_GRID_AXIS
		or grid_width * grid_height > MAX_CELL_COUNT
	):
		return _failure("environment_grid_invalid")
	if max_scopes <= 0 or max_scopes > MAX_SCOPES_HARD:
		return _failure("environment_scope_capacity_invalid")
	return {"ok": true, "reason": "ok"}


func _validate_record(record: Dictionary, expected_cells: int) -> Dictionary:
	if not _has_exact_fields(record, RECORD_FIELDS):
		return _failure("environment_record_fields_invalid")
	if typeof(record.get("scope_id")) != TYPE_STRING or not _valid_scope_id(String(record["scope_id"])):
		return _failure("environment_scope_id_invalid")
	if (
		typeof(record.get("state_revision")) != TYPE_INT
		or int(record["state_revision"]) < 0
		or typeof(record.get("last_environment_tick")) != TYPE_INT
		or int(record["last_environment_tick"]) < 0
		or typeof(record.get("reservoir_inflow_ul_total")) != TYPE_INT
		or typeof(record.get("reservoir_outflow_ul_total")) != TYPE_INT
	):
		return _failure("environment_record_integer_invalid")
	if (
		int(record["reservoir_inflow_ul_total"]) < 0
		or int(record["reservoir_inflow_ul_total"]) > MAX_EXCHANGE_TOTAL_UL
		or int(record["reservoir_outflow_ul_total"]) < 0
		or int(record["reservoir_outflow_ul_total"]) > MAX_EXCHANGE_TOTAL_UL
	):
		return _failure("environment_reservoir_exchange_invalid")
	if not _valid_profile_pin(String(record.get("profile_id", "")), String(record.get("profile_sha256", ""))):
		return _failure("environment_profile_pin_invalid")
	return _validate_state_arrays(
		record.get("surface_water_ul"),
		record.get("soil_water_ul"),
		record.get("reservoir_kind"),
		record.get("reservoir_level_mm"),
		expected_cells
	)


func _validate_state_arrays(
	surface_value: Variant,
	soil_value: Variant,
	kind_value: Variant,
	level_value: Variant,
	expected_cells: int = -1
) -> Dictionary:
	var count := _cell_count if expected_cells < 0 else expected_cells
	if (
		typeof(surface_value) != TYPE_PACKED_INT64_ARRAY
		or typeof(soil_value) != TYPE_PACKED_INT64_ARRAY
		or typeof(kind_value) != TYPE_PACKED_BYTE_ARRAY
		or typeof(level_value) != TYPE_PACKED_INT64_ARRAY
	):
		return _failure("environment_state_array_type_invalid")
	var surface: PackedInt64Array = surface_value
	var soil: PackedInt64Array = soil_value
	var kinds: PackedByteArray = kind_value
	var levels: PackedInt64Array = level_value
	if (
		surface.size() != count
		or soil.size() != count
		or kinds.size() != count
		or levels.size() != count
	):
		return _failure("environment_state_array_size_invalid")
	for index in range(count):
		var kind := int(kinds[index])
		var surface_ul := int(surface[index])
		var soil_ul := int(soil[index])
		var level_mm := int(levels[index])
		if not VALID_RESERVOIR_KINDS.has(kind):
			return _failure("environment_reservoir_kind_invalid")
		if surface_ul < 0 or surface_ul > MAX_WATER_UL_PER_CELL:
			return _failure("environment_surface_water_invalid")
		if soil_ul < 0 or soil_ul > MAX_WATER_UL_PER_CELL:
			return _failure("environment_soil_water_invalid")
		if kind == RESERVOIR_FINITE:
			if level_mm != 0:
				return _failure("environment_finite_reservoir_level_invalid")
		else:
			if surface_ul != 0 or soil_ul != 0:
				return _failure("environment_infinite_reservoir_stores_finite_water")
			if absi(level_mm) > MAX_ABS_RESERVOIR_LEVEL_MM:
				return _failure("environment_reservoir_level_invalid")
	return {"ok": true, "reason": "ok"}


func _valid_profile_pin(profile_id: String, profile_sha256: String) -> bool:
	if profile_id.is_empty() and profile_sha256.is_empty():
		return true
	if profile_id.is_empty() or profile_sha256.length() != 64:
		return false
	return profile_id == profile_id.strip_edges()


func _valid_scope_id(scope_id: String) -> bool:
	return (
		not scope_id.is_empty()
		and scope_id == scope_id.strip_edges()
		and scope_id.length() <= MAX_SCOPE_ID_LENGTH
	)


func _public_record(record: Dictionary) -> Dictionary:
	return _copy_record(record)


func _copy_record(record: Dictionary) -> Dictionary:
	return {
		"scope_id": String(record["scope_id"]),
		"state_revision": int(record["state_revision"]),
		"profile_id": String(record["profile_id"]),
		"profile_sha256": String(record["profile_sha256"]),
		"last_environment_tick": int(record["last_environment_tick"]),
		"surface_water_ul": (record["surface_water_ul"] as PackedInt64Array).duplicate(),
		"soil_water_ul": (record["soil_water_ul"] as PackedInt64Array).duplicate(),
		"reservoir_kind": (record["reservoir_kind"] as PackedByteArray).duplicate(),
		"reservoir_level_mm": (record["reservoir_level_mm"] as PackedInt64Array).duplicate(),
		"reservoir_inflow_ul_total": int(record["reservoir_inflow_ul_total"]),
		"reservoir_outflow_ul_total": int(record["reservoir_outflow_ul_total"]),
	}


func _same_mutable_state(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a["last_environment_tick"]) == int(b["last_environment_tick"])
		and a["surface_water_ul"] == b["surface_water_ul"]
		and a["soil_water_ul"] == b["soil_water_ul"]
		and a["reservoir_kind"] == b["reservoir_kind"]
		and a["reservoir_level_mm"] == b["reservoir_level_mm"]
		and int(a["reservoir_inflow_ul_total"]) == int(b["reservoir_inflow_ul_total"])
		and int(a["reservoir_outflow_ul_total"]) == int(b["reservoir_outflow_ul_total"])
	)


func _zero_i64() -> PackedInt64Array:
	var result := PackedInt64Array()
	result.resize(_cell_count)
	return result


func _zero_u8() -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(_cell_count)
	return result


func _reset_metrics() -> void:
	_registrations_total = 0
	_commit_batches_total = 0
	_committed_scopes_total = 0
	_commit_rejections_total = 0
	_snapshot_restores_total = 0


func _reject_commit(reason: String) -> Dictionary:
	_commit_rejections_total += 1
	return _failure(reason)


func _has_exact_fields(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for field in expected:
		if not value.has(field):
			return false
	return true


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
