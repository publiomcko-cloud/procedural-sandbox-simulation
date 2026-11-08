extends RefCounted
class_name SimulationTierRouter

## Engine-owned bounded automatic tier routing policy.
##
## Callers explicitly submit already-routed scope observations. This class does
## not inspect SceneTree, terrain, chunks, entities or world history. Dirty
## observations are deduplicated and processed under a hard per-call budget.

const SNAPSHOT_SCHEMA_VERSION := 1

const DEFAULT_ACTIVE_ENTER_MM := 32_000
const DEFAULT_ACTIVE_EXIT_MM := 40_000
const DEFAULT_AGGREGATE_ENTER_MM := 96_000
const DEFAULT_AGGREGATE_EXIT_MM := 112_000
const DEFAULT_MAX_DECISIONS_PER_CALL := 32
const DEFAULT_MAX_TRACKED_OBSERVATIONS := 65_536

const MAX_DISTANCE_MM := 9_000_000_000_000_000
const MAX_DECISIONS_PER_CALL_HARD := 4096
const MAX_TRACKED_OBSERVATIONS_HARD := 1_000_000
const MAX_SCOPE_ID_LENGTH := 256

const SNAPSHOT_FIELDS := [
	"schema_version",
	"active_enter_mm",
	"active_exit_mm",
	"aggregate_enter_mm",
	"aggregate_exit_mm",
	"max_decisions_per_call",
	"max_tracked_observations",
	"observations",
	"pending_scope_ids",
]
const OBSERVATION_FIELDS := [
	"scope_id",
	"distance_mm",
	"observation_revision",
]

var _initialized := false
var _active_enter_mm := DEFAULT_ACTIVE_ENTER_MM
var _active_exit_mm := DEFAULT_ACTIVE_EXIT_MM
var _aggregate_enter_mm := DEFAULT_AGGREGATE_ENTER_MM
var _aggregate_exit_mm := DEFAULT_AGGREGATE_EXIT_MM
var _max_decisions_per_call := DEFAULT_MAX_DECISIONS_PER_CALL
var _max_tracked_observations := DEFAULT_MAX_TRACKED_OBSERVATIONS

var _observations: Dictionary = {}
var _pending_scope_ids: Array[String] = []
var _pending_set: Dictionary = {}

# Telemetry only.
var _observation_submissions_total := 0
var _observation_changes_total := 0
var _observation_noops_total := 0
var _observation_rejections_total := 0
var _process_calls_total := 0
var _decisions_total := 0
var _transition_commits_total := 0
var _transition_noops_total := 0
var _peak_pending_count := 0
var _snapshot_restores_total := 0


func initialize(
	active_enter_mm: int = DEFAULT_ACTIVE_ENTER_MM,
	active_exit_mm: int = DEFAULT_ACTIVE_EXIT_MM,
	aggregate_enter_mm: int = DEFAULT_AGGREGATE_ENTER_MM,
	aggregate_exit_mm: int = DEFAULT_AGGREGATE_EXIT_MM,
	max_decisions_per_call: int = DEFAULT_MAX_DECISIONS_PER_CALL,
	max_tracked_observations: int = DEFAULT_MAX_TRACKED_OBSERVATIONS
) -> Dictionary:
	if _initialized:
		return {"ok": false, "reason": "simulation_tier_router_already_initialized"}

	var config_validation := _validate_config(
		active_enter_mm,
		active_exit_mm,
		aggregate_enter_mm,
		aggregate_exit_mm,
		max_decisions_per_call,
		max_tracked_observations
	)
	if not config_validation.get("ok", false):
		return config_validation

	_active_enter_mm = active_enter_mm
	_active_exit_mm = active_exit_mm
	_aggregate_enter_mm = aggregate_enter_mm
	_aggregate_exit_mm = aggregate_exit_mm
	_max_decisions_per_call = max_decisions_per_call
	_max_tracked_observations = max_tracked_observations
	_observations.clear()
	_pending_scope_ids.clear()
	_pending_set.clear()
	_reset_metrics()
	_initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"config": get_config(),
	}


func is_initialized() -> bool:
	return _initialized


func get_config() -> Dictionary:
	if not _initialized:
		return {}
	return {
		"active_enter_mm": _active_enter_mm,
		"active_exit_mm": _active_exit_mm,
		"aggregate_enter_mm": _aggregate_enter_mm,
		"aggregate_exit_mm": _aggregate_exit_mm,
		"max_decisions_per_call": _max_decisions_per_call,
		"max_tracked_observations": _max_tracked_observations,
	}


func submit_observation(
	scope_id: String,
	distance_mm: int,
	tier_state: SimulationTierState
) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "simulation_tier_router_not_initialized"}

	_observation_submissions_total += 1

	if not _is_valid_scope_id(scope_id):
		return _reject_observation("simulation_router_scope_id_invalid")
	if distance_mm < 0 or distance_mm > MAX_DISTANCE_MM:
		return _reject_observation("simulation_router_distance_invalid")
	if tier_state == null or not tier_state.is_initialized():
		return _reject_observation("simulation_tier_state_not_initialized")
	if tier_state.get_scope(scope_id).is_empty():
		return _reject_observation("simulation_scope_not_found")

	if _observations.has(scope_id):
		var existing: Dictionary = _observations[scope_id]
		if int(existing["distance_mm"]) == distance_mm:
			_observation_noops_total += 1
			return {
				"ok": true,
				"reason": "ok",
				"noop": true,
				"queued": _pending_set.has(scope_id),
				"observation": _public_observation(existing),
				"pending_count": _pending_scope_ids.size(),
			}

		existing["distance_mm"] = distance_mm
		existing["observation_revision"] = int(existing["observation_revision"]) + 1
		_observations[scope_id] = existing
		_observation_changes_total += 1
		_enqueue_if_needed(scope_id)
		return {
			"ok": true,
			"reason": "ok",
			"noop": false,
			"queued": true,
			"observation": _public_observation(existing),
			"pending_count": _pending_scope_ids.size(),
		}

	if _observations.size() >= _max_tracked_observations:
		return _reject_observation("simulation_router_observation_limit_reached")

	var record := {
		"scope_id": scope_id,
		"distance_mm": distance_mm,
		"observation_revision": 0,
	}
	_observations[scope_id] = record
	_observation_changes_total += 1
	_enqueue_if_needed(scope_id)
	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"queued": true,
		"observation": _public_observation(record),
		"pending_count": _pending_scope_ids.size(),
	}


func get_observation(scope_id: String) -> Dictionary:
	if not _initialized or not _observations.has(scope_id):
		return {}
	return _public_observation(_observations[scope_id])


func get_pending_count() -> int:
	return _pending_scope_ids.size() if _initialized else 0


func process_pending(
	tier_state: SimulationTierState,
	logical_tick: int,
	requested_budget: int = -1
) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "simulation_tier_router_not_initialized"}
	if tier_state == null or not tier_state.is_initialized():
		return {"ok": false, "reason": "simulation_tier_state_not_initialized"}
	if logical_tick < 0:
		return {"ok": false, "reason": "simulation_router_tick_invalid"}
	if requested_budget == 0 or requested_budget < -1:
		return {"ok": false, "reason": "simulation_router_budget_invalid"}
	if requested_budget > _max_decisions_per_call:
		return {"ok": false, "reason": "simulation_router_budget_exceeds_configured_max"}

	var budget := _max_decisions_per_call
	if requested_budget > 0:
		budget = requested_budget

	_process_calls_total += 1
	var processed: Array = []
	var processed_count := mini(budget, _pending_scope_ids.size())
	for _index in range(processed_count):
		var scope_id := _pending_scope_ids.pop_front()
		_pending_set.erase(scope_id)

		if not _observations.has(scope_id):
			return {
				"ok": false,
				"reason": "simulation_router_pending_observation_missing",
				"processed": processed,
			}

		var observation: Dictionary = _observations[scope_id]
		var scope_record: Dictionary = tier_state.get_scope(scope_id)
		if scope_record.is_empty():
			return {
				"ok": false,
				"reason": "simulation_scope_not_found",
				"processed": processed,
			}

		var source_tier := String(scope_record["tier"])
		var target_tier := _target_tier(
			source_tier,
			int(observation["distance_mm"])
		)
		var transition: Dictionary = tier_state.transition_scope(
			scope_id,
			target_tier,
			logical_tick,
			int(scope_record["tier_revision"])
		)
		if not transition.get("ok", false):
			return {
				"ok": false,
				"reason": "simulation_router_transition_failed",
				"detail": String(transition.get("reason", "")),
				"processed": processed,
			}

		var changed := not bool(transition.get("noop", false))
		_decisions_total += 1
		if changed:
			_transition_commits_total += 1
		else:
			_transition_noops_total += 1

		var final_record: Dictionary = transition.get("record", {})
		processed.append({
			"scope_id": scope_id,
			"distance_mm": int(observation["distance_mm"]),
			"observation_revision": int(observation["observation_revision"]),
			"source_tier": source_tier,
			"target_tier": target_tier,
			"changed": changed,
			"tier_revision": int(final_record.get("tier_revision", -1)),
			"state_revision": int(final_record.get("state_revision", -1)),
		})

	return {
		"ok": true,
		"reason": "ok",
		"processed": processed,
		"processed_count": processed.size(),
		"pending_count": _pending_scope_ids.size(),
		"budget": budget,
	}


func get_authoritative_snapshot() -> Dictionary:
	if not _initialized:
		return {}

	var scope_ids: Array = _observations.keys()
	scope_ids.sort()
	var serialized_observations: Array = []
	for scope_id_value in scope_ids:
		var scope_id := String(scope_id_value)
		serialized_observations.append(_public_observation(_observations[scope_id]))

	var pending: Array = []
	for scope_id in _pending_scope_ids:
		pending.append(scope_id)

	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"active_enter_mm": _active_enter_mm,
		"active_exit_mm": _active_exit_mm,
		"aggregate_enter_mm": _aggregate_enter_mm,
		"aggregate_exit_mm": _aggregate_exit_mm,
		"max_decisions_per_call": _max_decisions_per_call,
		"max_tracked_observations": _max_tracked_observations,
		"observations": serialized_observations,
		"pending_scope_ids": pending,
	}


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_fields(snapshot, SNAPSHOT_FIELDS):
		return {"ok": false, "reason": "simulation_router_snapshot_fields_invalid"}
	if typeof(snapshot.get("schema_version")) != TYPE_INT:
		return {"ok": false, "reason": "simulation_router_snapshot_schema_invalid"}
	if int(snapshot["schema_version"]) != SNAPSHOT_SCHEMA_VERSION:
		return {"ok": false, "reason": "simulation_router_snapshot_schema_invalid"}

	for field_name in [
		"active_enter_mm",
		"active_exit_mm",
		"aggregate_enter_mm",
		"aggregate_exit_mm",
		"max_decisions_per_call",
		"max_tracked_observations",
	]:
		if typeof(snapshot.get(field_name)) != TYPE_INT:
			return {"ok": false, "reason": "simulation_router_snapshot_config_invalid"}

	var config_validation := _validate_config(
		int(snapshot["active_enter_mm"]),
		int(snapshot["active_exit_mm"]),
		int(snapshot["aggregate_enter_mm"]),
		int(snapshot["aggregate_exit_mm"]),
		int(snapshot["max_decisions_per_call"]),
		int(snapshot["max_tracked_observations"])
	)
	if not config_validation.get("ok", false):
		return {"ok": false, "reason": "simulation_router_snapshot_config_invalid"}

	if typeof(snapshot.get("observations")) != TYPE_ARRAY:
		return {"ok": false, "reason": "simulation_router_snapshot_observations_invalid"}
	if typeof(snapshot.get("pending_scope_ids")) != TYPE_ARRAY:
		return {"ok": false, "reason": "simulation_router_snapshot_pending_invalid"}

	var observations_value: Array = snapshot["observations"]
	if observations_value.size() > int(snapshot["max_tracked_observations"]):
		return {"ok": false, "reason": "simulation_router_snapshot_observation_limit_exceeded"}

	var seen := {}
	for observation_value in observations_value:
		if typeof(observation_value) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "simulation_router_snapshot_observation_invalid"}
		var observation: Dictionary = observation_value
		if not _has_exact_fields(observation, OBSERVATION_FIELDS):
			return {"ok": false, "reason": "simulation_router_snapshot_observation_fields_invalid"}
		if typeof(observation.get("scope_id")) != TYPE_STRING:
			return {"ok": false, "reason": "simulation_router_snapshot_scope_id_invalid"}
		var scope_id := String(observation["scope_id"])
		if not _is_valid_scope_id(scope_id):
			return {"ok": false, "reason": "simulation_router_snapshot_scope_id_invalid"}
		if seen.has(scope_id):
			return {"ok": false, "reason": "simulation_router_snapshot_duplicate_observation"}
		seen[scope_id] = true
		if typeof(observation.get("distance_mm")) != TYPE_INT:
			return {"ok": false, "reason": "simulation_router_snapshot_distance_invalid"}
		var distance_mm := int(observation["distance_mm"])
		if distance_mm < 0 or distance_mm > MAX_DISTANCE_MM:
			return {"ok": false, "reason": "simulation_router_snapshot_distance_invalid"}
		if (
			typeof(observation.get("observation_revision")) != TYPE_INT
			or int(observation["observation_revision"]) < 0
		):
			return {"ok": false, "reason": "simulation_router_snapshot_revision_invalid"}

	var pending_seen := {}
	var pending_value: Array = snapshot["pending_scope_ids"]
	if pending_value.size() > observations_value.size():
		return {"ok": false, "reason": "simulation_router_snapshot_pending_invalid"}
	for pending_scope_value in pending_value:
		if typeof(pending_scope_value) != TYPE_STRING:
			return {"ok": false, "reason": "simulation_router_snapshot_pending_invalid"}
		var pending_scope_id := String(pending_scope_value)
		if not seen.has(pending_scope_id):
			return {"ok": false, "reason": "simulation_router_snapshot_pending_unknown_scope"}
		if pending_seen.has(pending_scope_id):
			return {"ok": false, "reason": "simulation_router_snapshot_pending_duplicate"}
		pending_seen[pending_scope_id] = true

	return {"ok": true, "reason": "ok"}


func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if _initialized:
		return {"ok": false, "reason": "simulation_tier_router_already_initialized"}
	var validation := validate_snapshot(snapshot)
	if not validation.get("ok", false):
		return validation

	var next_observations := {}
	for observation_value in snapshot["observations"]:
		var observation: Dictionary = observation_value
		var scope_id := String(observation["scope_id"])
		next_observations[scope_id] = {
			"scope_id": scope_id,
			"distance_mm": int(observation["distance_mm"]),
			"observation_revision": int(observation["observation_revision"]),
		}

	var next_pending: Array[String] = []
	var next_pending_set := {}
	for pending_scope_value in snapshot["pending_scope_ids"]:
		var pending_scope_id := String(pending_scope_value)
		next_pending.append(pending_scope_id)
		next_pending_set[pending_scope_id] = true

	_active_enter_mm = int(snapshot["active_enter_mm"])
	_active_exit_mm = int(snapshot["active_exit_mm"])
	_aggregate_enter_mm = int(snapshot["aggregate_enter_mm"])
	_aggregate_exit_mm = int(snapshot["aggregate_exit_mm"])
	_max_decisions_per_call = int(snapshot["max_decisions_per_call"])
	_max_tracked_observations = int(snapshot["max_tracked_observations"])
	_observations = next_observations
	_pending_scope_ids = next_pending
	_pending_set = next_pending_set
	_reset_metrics()
	_snapshot_restores_total = 1
	_peak_pending_count = _pending_scope_ids.size()
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
		"tracked_observation_count": _observations.size(),
		"pending_count": _pending_scope_ids.size(),
		"max_decisions_per_call": _max_decisions_per_call,
		"max_tracked_observations": _max_tracked_observations,
		"observation_submissions_total": _observation_submissions_total,
		"observation_changes_total": _observation_changes_total,
		"observation_noops_total": _observation_noops_total,
		"observation_rejections_total": _observation_rejections_total,
		"process_calls_total": _process_calls_total,
		"decisions_total": _decisions_total,
		"transition_commits_total": _transition_commits_total,
		"transition_noops_total": _transition_noops_total,
		"peak_pending_count": _peak_pending_count,
		"snapshot_restores_total": _snapshot_restores_total,
	}


func _target_tier(current_tier: String, distance_mm: int) -> String:
	match current_tier:
		SimulationTierState.TIER_ACTIVE:
			if distance_mm <= _active_exit_mm:
				return SimulationTierState.TIER_ACTIVE
			if distance_mm <= _aggregate_exit_mm:
				return SimulationTierState.TIER_AGGREGATE
			return SimulationTierState.TIER_DORMANT
		SimulationTierState.TIER_AGGREGATE:
			if distance_mm <= _active_enter_mm:
				return SimulationTierState.TIER_ACTIVE
			if distance_mm <= _aggregate_exit_mm:
				return SimulationTierState.TIER_AGGREGATE
			return SimulationTierState.TIER_DORMANT
		SimulationTierState.TIER_DORMANT:
			if distance_mm <= _active_enter_mm:
				return SimulationTierState.TIER_ACTIVE
			if distance_mm <= _aggregate_enter_mm:
				return SimulationTierState.TIER_AGGREGATE
			return SimulationTierState.TIER_DORMANT
		_:
			return current_tier


func _enqueue_if_needed(scope_id: String) -> void:
	if _pending_set.has(scope_id):
		return
	_pending_scope_ids.append(scope_id)
	_pending_set[scope_id] = true
	_peak_pending_count = maxi(_peak_pending_count, _pending_scope_ids.size())


func _public_observation(record: Dictionary) -> Dictionary:
	return {
		"scope_id": String(record["scope_id"]),
		"distance_mm": int(record["distance_mm"]),
		"observation_revision": int(record["observation_revision"]),
	}


func _reject_observation(reason: String) -> Dictionary:
	_observation_rejections_total += 1
	return {"ok": false, "reason": reason}


func _validate_config(
	active_enter_mm: int,
	active_exit_mm: int,
	aggregate_enter_mm: int,
	aggregate_exit_mm: int,
	max_decisions_per_call: int,
	max_tracked_observations: int
) -> Dictionary:
	if (
		active_enter_mm < 0
		or active_exit_mm < active_enter_mm
		or aggregate_enter_mm < active_exit_mm
		or aggregate_exit_mm < aggregate_enter_mm
		or aggregate_exit_mm > MAX_DISTANCE_MM
	):
		return {"ok": false, "reason": "simulation_router_thresholds_invalid"}
	if (
		max_decisions_per_call <= 0
		or max_decisions_per_call > MAX_DECISIONS_PER_CALL_HARD
	):
		return {"ok": false, "reason": "simulation_router_decision_budget_invalid"}
	if (
		max_tracked_observations <= 0
		or max_tracked_observations > MAX_TRACKED_OBSERVATIONS_HARD
	):
		return {"ok": false, "reason": "simulation_router_observation_limit_invalid"}
	return {"ok": true, "reason": "ok"}


func _is_valid_scope_id(scope_id: String) -> bool:
	return (
		not scope_id.is_empty()
		and scope_id.length() <= MAX_SCOPE_ID_LENGTH
		and scope_id == scope_id.strip_edges()
	)


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_value in fields:
		if not value.has(String(field_value)):
			return false
	return true


func _reset_metrics() -> void:
	_observation_submissions_total = 0
	_observation_changes_total = 0
	_observation_noops_total = 0
	_observation_rejections_total = 0
	_process_calls_total = 0
	_decisions_total = 0
	_transition_commits_total = 0
	_transition_noops_total = 0
	_peak_pending_count = 0
	_snapshot_restores_total = 0
