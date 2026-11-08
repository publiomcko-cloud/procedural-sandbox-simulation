extends RefCounted
class_name SimulationTierState

## Engine-owned simulation fidelity registry.
##
## P4.0B defines only fidelity/tier authority and a bounded data-only state
## envelope. Domain simulation systems remain separate and may query due
## decisions by stable scope ID without scanning unrelated world state.

const SNAPSHOT_SCHEMA_VERSION := 1

const TIER_ACTIVE := "active"
const TIER_AGGREGATE := "aggregate"
const TIER_DORMANT := "dormant"
const VALID_TIERS := [TIER_ACTIVE, TIER_AGGREGATE, TIER_DORMANT]

const DEFAULT_AGGREGATE_INTERVAL_TICKS := 10
const MIN_AGGREGATE_INTERVAL_TICKS := 2
const MAX_AGGREGATE_INTERVAL_TICKS := 1_000_000

const DEFAULT_MAX_SCOPES := 65_536
const MAX_SCOPES_HARD := 1_000_000
const MAX_SCOPE_ID_LENGTH := 256

const MAX_STATE_DEPTH := 16
const MAX_STATE_NODES := 4096

const SNAPSHOT_FIELDS := [
	"schema_version",
	"aggregate_interval_ticks",
	"max_scopes",
	"scopes",
]
const RECORD_FIELDS := [
	"scope_id",
	"tier",
	"tier_revision",
	"state_revision",
	"last_transition_tick",
	"state",
]

var _initialized := false
var _aggregate_interval_ticks := DEFAULT_AGGREGATE_INTERVAL_TICKS
var _max_scopes := DEFAULT_MAX_SCOPES
var _scopes: Dictionary = {}
var _tier_counts := {
	TIER_ACTIVE: 0,
	TIER_AGGREGATE: 0,
	TIER_DORMANT: 0,
}

# Telemetry only. None of these counters are authoritative.
var _registrations_total := 0
var _transition_requests_total := 0
var _transition_commits_total := 0
var _transition_noops_total := 0
var _transition_rejections_total := 0
var _state_replacements_total := 0
var _state_replacement_noops_total := 0
var _due_checks_total := 0
var _snapshot_restores_total := 0


func initialize(
	aggregate_interval_ticks: int = DEFAULT_AGGREGATE_INTERVAL_TICKS,
	max_scopes: int = DEFAULT_MAX_SCOPES
) -> Dictionary:
	if _initialized:
		return {"ok": false, "reason": "simulation_tier_state_already_initialized"}
	if not _is_valid_aggregate_interval(aggregate_interval_ticks):
		return {"ok": false, "reason": "aggregate_interval_ticks_invalid"}
	if max_scopes <= 0 or max_scopes > MAX_SCOPES_HARD:
		return {"ok": false, "reason": "max_simulation_scopes_invalid"}

	_aggregate_interval_ticks = aggregate_interval_ticks
	_max_scopes = max_scopes
	_scopes.clear()
	_reset_tier_counts()
	_reset_metrics()
	_initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"aggregate_interval_ticks": _aggregate_interval_ticks,
		"max_scopes": _max_scopes,
	}


func is_initialized() -> bool:
	return _initialized


func register_scope(
	scope_id: String,
	initial_tier: String = TIER_DORMANT,
	state: Dictionary = {}
) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "simulation_tier_state_not_initialized"}
	if not _is_valid_scope_id(scope_id):
		return {"ok": false, "reason": "simulation_scope_id_invalid"}
	if not _is_valid_tier(initial_tier):
		return {"ok": false, "reason": "simulation_tier_invalid"}
	if _scopes.has(scope_id):
		return {"ok": false, "reason": "simulation_scope_already_registered"}
	if _scopes.size() >= _max_scopes:
		return {"ok": false, "reason": "simulation_scope_limit_reached"}

	var state_result: Dictionary = _prepare_state_payload(state)
	if not state_result.get("ok", false):
		return state_result

	var record := {
		"scope_id": scope_id,
		"tier": initial_tier,
		"tier_revision": 0,
		"state_revision": 0,
		"last_transition_tick": -1,
		"state": state_result["state"],
	}
	_scopes[scope_id] = record
	_tier_counts[initial_tier] = int(_tier_counts[initial_tier]) + 1
	_registrations_total += 1
	return {
		"ok": true,
		"reason": "ok",
		"record": _public_record(record),
	}


func transition_scope(
	scope_id: String,
	target_tier: String,
	logical_tick: int,
	expected_tier_revision: int = -1
) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "simulation_tier_state_not_initialized"}
	_transition_requests_total += 1

	if not _is_valid_scope_id(scope_id):
		return _reject_transition("simulation_scope_id_invalid")
	if not _is_valid_tier(target_tier):
		return _reject_transition("simulation_tier_invalid")
	if logical_tick < 0:
		return _reject_transition("simulation_transition_tick_invalid")
	if expected_tier_revision < -1:
		return _reject_transition("expected_tier_revision_invalid")
	if not _scopes.has(scope_id):
		return _reject_transition("simulation_scope_not_found")

	var record: Dictionary = _scopes[scope_id]
	var current_revision := int(record["tier_revision"])
	if expected_tier_revision >= 0 and expected_tier_revision != current_revision:
		return _reject_transition("simulation_tier_revision_conflict")

	var source_tier := String(record["tier"])
	if source_tier == target_tier:
		_transition_noops_total += 1
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"source_tier": source_tier,
			"target_tier": target_tier,
			"record": _public_record(record),
		}

	_tier_counts[source_tier] = int(_tier_counts[source_tier]) - 1
	_tier_counts[target_tier] = int(_tier_counts[target_tier]) + 1
	record["tier"] = target_tier
	record["tier_revision"] = current_revision + 1
	record["last_transition_tick"] = logical_tick
	_scopes[scope_id] = record
	_transition_commits_total += 1

	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"source_tier": source_tier,
		"target_tier": target_tier,
		"record": _public_record(record),
	}


func replace_scope_state(
	scope_id: String,
	state: Dictionary,
	expected_state_revision: int = -1
) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "simulation_tier_state_not_initialized"}
	if not _is_valid_scope_id(scope_id):
		return {"ok": false, "reason": "simulation_scope_id_invalid"}
	if expected_state_revision < -1:
		return {"ok": false, "reason": "expected_state_revision_invalid"}
	if not _scopes.has(scope_id):
		return {"ok": false, "reason": "simulation_scope_not_found"}

	var state_result: Dictionary = _prepare_state_payload(state)
	if not state_result.get("ok", false):
		return state_result

	var record: Dictionary = _scopes[scope_id]
	var current_revision := int(record["state_revision"])
	if expected_state_revision >= 0 and expected_state_revision != current_revision:
		return {"ok": false, "reason": "simulation_state_revision_conflict"}

	var prepared_state: Dictionary = state_result["state"]
	if record["state"] == prepared_state:
		_state_replacement_noops_total += 1
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"record": _public_record(record),
		}

	record["state"] = prepared_state
	record["state_revision"] = current_revision + 1
	_scopes[scope_id] = record
	_state_replacements_total += 1
	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"record": _public_record(record),
	}


func has_scope(scope_id: String) -> bool:
	return _initialized and _scopes.has(scope_id)


func get_scope(scope_id: String) -> Dictionary:
	if not _initialized or not _scopes.has(scope_id):
		return {}
	return _public_record(_scopes[scope_id])


func get_scope_count() -> int:
	return _scopes.size() if _initialized else 0


func get_tier_counts() -> Dictionary:
	return _tier_counts.duplicate(true) if _initialized else {}


func get_due_decision(scope_id: String, logical_tick: int) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "simulation_tier_state_not_initialized"}
	if logical_tick < 0:
		return {"ok": false, "reason": "simulation_due_tick_invalid"}
	if not _is_valid_scope_id(scope_id):
		return {"ok": false, "reason": "simulation_scope_id_invalid"}
	if not _scopes.has(scope_id):
		return {"ok": false, "reason": "simulation_scope_not_found"}

	_due_checks_total += 1
	var record: Dictionary = _scopes[scope_id]
	var tier := String(record["tier"])
	var phase := _aggregate_phase(scope_id)
	var due := false
	match tier:
		TIER_ACTIVE:
			due = true
		TIER_AGGREGATE:
			due = logical_tick % _aggregate_interval_ticks == phase
		TIER_DORMANT:
			due = false

	return {
		"ok": true,
		"reason": "ok",
		"scope_id": scope_id,
		"tier": tier,
		"logical_tick": logical_tick,
		"due": due,
		"aggregate_interval_ticks": _aggregate_interval_ticks,
		"aggregate_phase": phase,
	}


func get_authoritative_snapshot() -> Dictionary:
	if not _initialized:
		return {}

	var scope_ids: Array = _scopes.keys()
	scope_ids.sort()
	var serialized_scopes: Array = []
	for scope_id_value in scope_ids:
		var scope_id := String(scope_id_value)
		var record: Dictionary = _scopes[scope_id]
		serialized_scopes.append({
			"scope_id": scope_id,
			"tier": String(record["tier"]),
			"tier_revision": int(record["tier_revision"]),
			"state_revision": int(record["state_revision"]),
			"last_transition_tick": int(record["last_transition_tick"]),
			"state": _canonicalize_data(record["state"]),
		})

	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"aggregate_interval_ticks": _aggregate_interval_ticks,
		"max_scopes": _max_scopes,
		"scopes": serialized_scopes,
	}


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_fields(snapshot, SNAPSHOT_FIELDS):
		return {"ok": false, "reason": "simulation_tier_snapshot_fields_invalid"}
	if typeof(snapshot.get("schema_version")) != TYPE_INT:
		return {"ok": false, "reason": "simulation_tier_snapshot_schema_invalid"}
	if int(snapshot["schema_version"]) != SNAPSHOT_SCHEMA_VERSION:
		return {"ok": false, "reason": "simulation_tier_snapshot_schema_invalid"}
	if typeof(snapshot.get("aggregate_interval_ticks")) != TYPE_INT:
		return {"ok": false, "reason": "simulation_tier_snapshot_interval_invalid"}
	var interval := int(snapshot["aggregate_interval_ticks"])
	if not _is_valid_aggregate_interval(interval):
		return {"ok": false, "reason": "simulation_tier_snapshot_interval_invalid"}
	if typeof(snapshot.get("max_scopes")) != TYPE_INT:
		return {"ok": false, "reason": "simulation_tier_snapshot_scope_limit_invalid"}
	var scope_limit := int(snapshot["max_scopes"])
	if scope_limit <= 0 or scope_limit > MAX_SCOPES_HARD:
		return {"ok": false, "reason": "simulation_tier_snapshot_scope_limit_invalid"}
	if typeof(snapshot.get("scopes")) != TYPE_ARRAY:
		return {"ok": false, "reason": "simulation_tier_snapshot_scopes_invalid"}

	var scopes_value: Array = snapshot["scopes"]
	if scopes_value.size() > scope_limit:
		return {"ok": false, "reason": "simulation_tier_snapshot_scope_limit_exceeded"}

	var seen := {}
	for record_value in scopes_value:
		if typeof(record_value) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "simulation_tier_snapshot_record_invalid"}
		var record: Dictionary = record_value
		if not _has_exact_fields(record, RECORD_FIELDS):
			return {"ok": false, "reason": "simulation_tier_snapshot_record_fields_invalid"}

		if typeof(record.get("scope_id")) != TYPE_STRING:
			return {"ok": false, "reason": "simulation_tier_snapshot_scope_id_invalid"}
		var scope_id := String(record["scope_id"])
		if not _is_valid_scope_id(scope_id):
			return {"ok": false, "reason": "simulation_tier_snapshot_scope_id_invalid"}
		if seen.has(scope_id):
			return {"ok": false, "reason": "simulation_tier_snapshot_duplicate_scope"}
		seen[scope_id] = true

		if typeof(record.get("tier")) != TYPE_STRING or not _is_valid_tier(String(record["tier"])):
			return {"ok": false, "reason": "simulation_tier_snapshot_tier_invalid"}
		if typeof(record.get("tier_revision")) != TYPE_INT or int(record["tier_revision"]) < 0:
			return {"ok": false, "reason": "simulation_tier_snapshot_tier_revision_invalid"}
		if typeof(record.get("state_revision")) != TYPE_INT or int(record["state_revision"]) < 0:
			return {"ok": false, "reason": "simulation_tier_snapshot_state_revision_invalid"}
		if (
			typeof(record.get("last_transition_tick")) != TYPE_INT
			or int(record["last_transition_tick"]) < -1
		):
			return {"ok": false, "reason": "simulation_tier_snapshot_transition_tick_invalid"}
		if typeof(record.get("state")) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "simulation_tier_snapshot_state_invalid"}
		var state_result: Dictionary = _prepare_state_payload(record["state"])
		if not state_result.get("ok", false):
			return {"ok": false, "reason": "simulation_tier_snapshot_state_invalid"}

	return {"ok": true, "reason": "ok"}


func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if _initialized:
		return {"ok": false, "reason": "simulation_tier_state_already_initialized"}
	var validation: Dictionary = validate_snapshot(snapshot)
	if not validation.get("ok", false):
		return validation

	var next_scopes := {}
	var next_counts := {
		TIER_ACTIVE: 0,
		TIER_AGGREGATE: 0,
		TIER_DORMANT: 0,
	}
	var scopes_value: Array = snapshot["scopes"]
	for record_value in scopes_value:
		var record: Dictionary = record_value
		var scope_id := String(record["scope_id"])
		var tier := String(record["tier"])
		next_scopes[scope_id] = {
			"scope_id": scope_id,
			"tier": tier,
			"tier_revision": int(record["tier_revision"]),
			"state_revision": int(record["state_revision"]),
			"last_transition_tick": int(record["last_transition_tick"]),
			"state": _canonicalize_data(record["state"]),
		}
		next_counts[tier] = int(next_counts[tier]) + 1

	_aggregate_interval_ticks = int(snapshot["aggregate_interval_ticks"])
	_max_scopes = int(snapshot["max_scopes"])
	_scopes = next_scopes
	_tier_counts = next_counts
	_reset_metrics()
	_snapshot_restores_total = 1
	_initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": get_authoritative_snapshot(),
	}


func get_metrics() -> Dictionary:
	if not _initialized:
		return {}
	return {
		"scope_count": _scopes.size(),
		"max_scopes": _max_scopes,
		"aggregate_interval_ticks": _aggregate_interval_ticks,
		"tier_counts": _tier_counts.duplicate(true),
		"registrations_total": _registrations_total,
		"transition_requests_total": _transition_requests_total,
		"transition_commits_total": _transition_commits_total,
		"transition_noops_total": _transition_noops_total,
		"transition_rejections_total": _transition_rejections_total,
		"state_replacements_total": _state_replacements_total,
		"state_replacement_noops_total": _state_replacement_noops_total,
		"due_checks_total": _due_checks_total,
		"snapshot_restores_total": _snapshot_restores_total,
	}


func _public_record(record: Dictionary) -> Dictionary:
	var scope_id := String(record["scope_id"])
	return {
		"scope_id": scope_id,
		"tier": String(record["tier"]),
		"tier_revision": int(record["tier_revision"]),
		"state_revision": int(record["state_revision"]),
		"last_transition_tick": int(record["last_transition_tick"]),
		"aggregate_phase": _aggregate_phase(scope_id),
		"state": _canonicalize_data(record["state"]),
	}


func _reject_transition(reason: String) -> Dictionary:
	_transition_rejections_total += 1
	return {"ok": false, "reason": reason}


func _is_valid_tier(tier: String) -> bool:
	return tier in VALID_TIERS


func _is_valid_scope_id(scope_id: String) -> bool:
	return (
		not scope_id.is_empty()
		and scope_id.length() <= MAX_SCOPE_ID_LENGTH
		and scope_id == scope_id.strip_edges()
	)


func _is_valid_aggregate_interval(value: int) -> bool:
	return (
		value >= MIN_AGGREGATE_INTERVAL_TICKS
		and value <= MAX_AGGREGATE_INTERVAL_TICKS
	)


func _aggregate_phase(scope_id: String) -> int:
	var hash_value: int = 2_166_136_261
	var bytes: PackedByteArray = scope_id.to_utf8_buffer()
	for byte_value in bytes:
		hash_value = ((hash_value ^ int(byte_value)) * 16_777_619) & 0xFFFFFFFF
	return int(hash_value % _aggregate_interval_ticks)


func _prepare_state_payload(state: Dictionary) -> Dictionary:
	var counter := [0]
	if not _validate_data_value(state, 0, counter):
		return {"ok": false, "reason": "simulation_state_payload_invalid"}
	return {
		"ok": true,
		"reason": "ok",
		"state": _canonicalize_data(state),
	}


func _validate_data_value(value: Variant, depth: int, counter: Array) -> bool:
	if depth > MAX_STATE_DEPTH:
		return false
	counter[0] = int(counter[0]) + 1
	if int(counter[0]) > MAX_STATE_NODES:
		return false

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I:
			return true
		TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I:
			return true
		TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_PLANE, TYPE_QUATERNION:
			return true
		TYPE_AABB, TYPE_BASIS, TYPE_COLOR, TYPE_PROJECTION:
			return true
		TYPE_ARRAY:
			for item in value:
				if not _validate_data_value(item, depth + 1, counter):
					return false
			return true
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			for key in dictionary.keys():
				if typeof(key) != TYPE_STRING:
					return false
				if not _validate_data_value(dictionary[key], depth + 1, counter):
					return false
			return true
		_:
			return false


func _canonicalize_data(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var keys: Array = source.keys()
			keys.sort()
			var result := {}
			for key_value in keys:
				var key := String(key_value)
				result[key] = _canonicalize_data(source[key_value])
			return result
		TYPE_ARRAY:
			var result_array: Array = []
			for item in value:
				result_array.append(_canonicalize_data(item))
			return result_array
		_:
			return value


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_value in fields:
		if not value.has(String(field_value)):
			return false
	return true


func _reset_tier_counts() -> void:
	_tier_counts = {
		TIER_ACTIVE: 0,
		TIER_AGGREGATE: 0,
		TIER_DORMANT: 0,
	}


func _reset_metrics() -> void:
	_registrations_total = 0
	_transition_requests_total = 0
	_transition_commits_total = 0
	_transition_noops_total = 0
	_transition_rejections_total = 0
	_state_replacements_total = 0
	_state_replacement_noops_total = 0
	_due_checks_total = 0
	_snapshot_restores_total = 0
