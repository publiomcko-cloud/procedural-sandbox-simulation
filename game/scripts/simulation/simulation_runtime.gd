extends Node
class_name SimulationRuntime

## SceneTree adapter for P4 simulation authority.
##
## P4.0A owns deterministic fixed logical time. P4.0B adds engine-owned
## active/aggregate/dormant scope authority and due decisions. Domain-specific
## simulation systems remain outside this node.

const SchedulerScript := preload("res://scripts/simulation/fixed_tick_scheduler.gd")
const TierStateScript := preload("res://scripts/simulation/simulation_tier_state.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")

const RUNTIME_SNAPSHOT_SCHEMA_VERSION := 1

const DEFAULT_TICK_USEC := SchedulerScript.DEFAULT_TICK_USEC
const DEFAULT_MAX_TICKS_PER_FRAME := SchedulerScript.DEFAULT_MAX_TICKS_PER_FRAME
const DEFAULT_AGGREGATE_INTERVAL_TICKS := TierStateScript.DEFAULT_AGGREGATE_INTERVAL_TICKS
const DEFAULT_MAX_SIMULATION_SCOPES := TierStateScript.DEFAULT_MAX_SCOPES

const RUNTIME_SNAPSHOT_FIELDS := [
	"schema_version",
	"fractional_usec",
	"scheduler",
	"tier_state",
]

var scheduler: FixedTickScheduler
var tier_state: SimulationTierState
var initialized := false
var initialization_error := ""

var _fractional_usec := 0.0
var _last_result: Dictionary = {}
var _perf_trace_enabled := false


func _ready() -> void:
	_perf_trace_enabled = PerformanceTrace.is_enabled()
	if not initialized:
		var result: Dictionary = initialize_runtime()
		if not result.get("ok", false):
			push_error("Simulation runtime initialization failed: %s" % result.get("reason", "unknown"))


func _process(delta: float) -> void:
	if not initialized:
		return
	var result: Dictionary = process_delta_seconds(delta)
	if not result.get("ok", false):
		initialization_error = String(result.get("reason", "scheduler_frame_failed"))
		push_error("Simulation scheduler frame failed: %s" % initialization_error)


func initialize_runtime(
	tick_usec: int = DEFAULT_TICK_USEC,
	max_ticks_per_frame: int = DEFAULT_MAX_TICKS_PER_FRAME,
	start_tick: int = 0,
	start_paused: bool = false,
	aggregate_interval_ticks: int = DEFAULT_AGGREGATE_INTERVAL_TICKS,
	max_simulation_scopes: int = DEFAULT_MAX_SIMULATION_SCOPES
) -> Dictionary:
	if initialized:
		return {"ok": false, "reason": "simulation_runtime_already_initialized"}

	var next_scheduler: FixedTickScheduler = SchedulerScript.new()
	var scheduler_result: Dictionary = next_scheduler.initialize(
		tick_usec, max_ticks_per_frame, start_tick, start_paused
	)
	if not scheduler_result.get("ok", false):
		initialization_error = String(
			scheduler_result.get("reason", "scheduler_initialization_failed")
		)
		return scheduler_result

	var next_tier_state: SimulationTierState = TierStateScript.new()
	var tier_result: Dictionary = next_tier_state.initialize(
		aggregate_interval_ticks, max_simulation_scopes
	)
	if not tier_result.get("ok", false):
		initialization_error = String(
			tier_result.get("reason", "simulation_tier_initialization_failed")
		)
		return tier_result

	scheduler = next_scheduler
	tier_state = next_tier_state
	_fractional_usec = 0.0
	_last_result = {}
	initialization_error = ""
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": get_runtime_snapshot(),
	}


func process_delta_seconds(delta: float) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if not is_finite(delta) or delta < 0.0:
		return {"ok": false, "reason": "simulation_delta_invalid"}

	if scheduler.is_paused():
		return process_elapsed_usec(0)

	var total_usec: float = delta * 1_000_000.0 + _fractional_usec
	var elapsed_usec: int = floori(total_usec)
	var next_fractional_usec: float = total_usec - float(elapsed_usec)
	var result: Dictionary = process_elapsed_usec(elapsed_usec)
	if result.get("ok", false):
		_fractional_usec = next_fractional_usec
	return result


func process_elapsed_usec(elapsed_usec: int) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}

	var started_usec: int = Time.get_ticks_usec() if _perf_trace_enabled else 0
	var result: Dictionary = scheduler.process_elapsed_usec(elapsed_usec)
	_last_result = result.duplicate(true)

	if _perf_trace_enabled and result.get("ok", false):
		var admitted_ticks: int = int(result.get("admitted_ticks", 0))
		var backlog_ticks: int = int(result.get("backlog_ticks", 0))
		var manual_step_ticks: int = int(result.get("manual_step_ticks", 0))
		if admitted_ticks > 0 or backlog_ticks > 0 or manual_step_ticks > 0:
			PerformanceTrace.emit_duration(
				"simulation_scheduler_frame",
				started_usec,
				{
					"elapsed_usec": elapsed_usec,
					"frame_index": int(result.get("frame_index", 0)),
					"source": String(result.get("source", "")),
					"first_tick": int(result.get("first_tick", -1)),
					"last_tick": int(result.get("last_tick", -1)),
					"admitted_ticks": admitted_ticks,
					"newly_due_ticks": int(result.get("newly_due_ticks", 0)),
					"backlog_ticks": backlog_ticks,
					"manual_step_ticks": manual_step_ticks,
					"paused": bool(result.get("paused", false)),
				},
				true
			)
	return result


func set_simulation_paused(value: bool) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return scheduler.set_paused(value)


func request_simulation_steps(count: int = 1) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return scheduler.request_steps(count)


func register_simulation_scope(
	scope_id: String,
	initial_tier: String = TierStateScript.TIER_DORMANT,
	state: Dictionary = {}
) -> Dictionary:
	if not initialized or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return tier_state.register_scope(scope_id, initial_tier, state)


func transition_simulation_scope(
	scope_id: String,
	target_tier: String,
	expected_tier_revision: int = -1
) -> Dictionary:
	if not initialized or scheduler == null or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}

	var started_usec: int = Time.get_ticks_usec() if _perf_trace_enabled else 0
	var logical_tick := scheduler.get_current_tick()
	var result: Dictionary = tier_state.transition_scope(
		scope_id, target_tier, logical_tick, expected_tier_revision
	)
	if (
		_perf_trace_enabled
		and result.get("ok", false)
		and not result.get("noop", false)
	):
		var record: Dictionary = result.get("record", {})
		PerformanceTrace.emit_duration(
			"simulation_tier_transition",
			started_usec,
			{
				"scope_id": scope_id,
				"logical_tick": logical_tick,
				"source_tier": String(result.get("source_tier", "")),
				"target_tier": String(result.get("target_tier", "")),
				"tier_revision": int(record.get("tier_revision", -1)),
				"state_revision": int(record.get("state_revision", -1)),
			},
			true
		)
	return result


func replace_simulation_scope_state(
	scope_id: String,
	state: Dictionary,
	expected_state_revision: int = -1
) -> Dictionary:
	if not initialized or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return tier_state.replace_scope_state(
		scope_id, state, expected_state_revision
	)


func get_simulation_scope(scope_id: String) -> Dictionary:
	if not initialized or tier_state == null:
		return {}
	return tier_state.get_scope(scope_id)


func get_simulation_due_decision(
	scope_id: String,
	logical_tick: int = -1
) -> Dictionary:
	if not initialized or scheduler == null or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	var query_tick := logical_tick
	if query_tick < 0:
		query_tick = scheduler.get_current_tick()
	return tier_state.get_due_decision(scope_id, query_tick)


func get_scheduler_snapshot() -> Dictionary:
	if not initialized or scheduler == null:
		return {}
	return scheduler.get_authoritative_snapshot()


func get_scheduler_metrics() -> Dictionary:
	if not initialized or scheduler == null:
		return {}
	return scheduler.get_metrics()


func get_simulation_tier_snapshot() -> Dictionary:
	if not initialized or tier_state == null:
		return {}
	return tier_state.get_authoritative_snapshot()


func get_simulation_tier_metrics() -> Dictionary:
	if not initialized or tier_state == null:
		return {}
	return tier_state.get_metrics()


func get_runtime_snapshot() -> Dictionary:
	if not initialized or scheduler == null or tier_state == null:
		return {}
	return {
		"schema_version": RUNTIME_SNAPSHOT_SCHEMA_VERSION,
		"fractional_usec": _fractional_usec,
		"scheduler": scheduler.get_authoritative_snapshot(),
		"tier_state": tier_state.get_authoritative_snapshot(),
	}


func consume_last_scheduler_result() -> Dictionary:
	var result: Dictionary = _last_result.duplicate(true)
	_last_result.clear()
	return result


func restore_scheduler_snapshot(snapshot: Dictionary) -> Dictionary:
	var next_scheduler: FixedTickScheduler = SchedulerScript.new()
	var result: Dictionary = next_scheduler.restore_snapshot(snapshot)
	if not result.get("ok", false):
		initialization_error = String(result.get("reason", "scheduler_restore_failed"))
		return result

	var next_tier_state: SimulationTierState = tier_state
	if next_tier_state == null or not next_tier_state.is_initialized():
		next_tier_state = TierStateScript.new()
		var tier_result: Dictionary = next_tier_state.initialize()
		if not tier_result.get("ok", false):
			initialization_error = String(
				tier_result.get("reason", "simulation_tier_initialization_failed")
			)
			return tier_result

	scheduler = next_scheduler
	tier_state = next_tier_state
	_fractional_usec = 0.0
	_last_result = {}
	initialization_error = ""
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": scheduler.get_authoritative_snapshot(),
	}


func restore_simulation_tier_snapshot(snapshot: Dictionary) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}

	var next_tier_state: SimulationTierState = TierStateScript.new()
	var result: Dictionary = next_tier_state.restore_snapshot(snapshot)
	if not result.get("ok", false):
		return result
	tier_state = next_tier_state
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": tier_state.get_authoritative_snapshot(),
	}


func validate_runtime_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_fields(snapshot, RUNTIME_SNAPSHOT_FIELDS):
		return {"ok": false, "reason": "simulation_runtime_snapshot_fields_invalid"}
	if typeof(snapshot.get("schema_version")) != TYPE_INT:
		return {"ok": false, "reason": "simulation_runtime_snapshot_schema_invalid"}
	if int(snapshot["schema_version"]) != RUNTIME_SNAPSHOT_SCHEMA_VERSION:
		return {"ok": false, "reason": "simulation_runtime_snapshot_schema_invalid"}
	if typeof(snapshot.get("fractional_usec")) != TYPE_FLOAT:
		return {"ok": false, "reason": "simulation_runtime_snapshot_fractional_usec_invalid"}
	var fractional_usec := float(snapshot["fractional_usec"])
	if not is_finite(fractional_usec) or fractional_usec < 0.0 or fractional_usec >= 1.0:
		return {"ok": false, "reason": "simulation_runtime_snapshot_fractional_usec_invalid"}
	if typeof(snapshot.get("scheduler")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "simulation_runtime_snapshot_scheduler_invalid"}
	if typeof(snapshot.get("tier_state")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "simulation_runtime_snapshot_tier_state_invalid"}

	var scheduler_candidate: FixedTickScheduler = SchedulerScript.new()
	var scheduler_result: Dictionary = scheduler_candidate.restore_snapshot(
		snapshot["scheduler"]
	)
	if not scheduler_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_scheduler_invalid",
			"detail": String(scheduler_result.get("reason", "")),
		}

	var tier_candidate: SimulationTierState = TierStateScript.new()
	var tier_result: Dictionary = tier_candidate.restore_snapshot(
		snapshot["tier_state"]
	)
	if not tier_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_tier_state_invalid",
			"detail": String(tier_result.get("reason", "")),
		}

	return {"ok": true, "reason": "ok"}


func restore_runtime_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_runtime_snapshot(snapshot)
	if not validation.get("ok", false):
		return validation

	var next_scheduler: FixedTickScheduler = SchedulerScript.new()
	var scheduler_result: Dictionary = next_scheduler.restore_snapshot(
		snapshot["scheduler"]
	)
	if not scheduler_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_scheduler_invalid",
		}

	var next_tier_state: SimulationTierState = TierStateScript.new()
	var tier_result: Dictionary = next_tier_state.restore_snapshot(
		snapshot["tier_state"]
	)
	if not tier_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_tier_state_invalid",
		}

	scheduler = next_scheduler
	tier_state = next_tier_state
	_fractional_usec = float(snapshot["fractional_usec"])
	_last_result = {}
	initialization_error = ""
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": get_runtime_snapshot(),
	}


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_value in fields:
		if not value.has(String(field_value)):
			return false
	return true
