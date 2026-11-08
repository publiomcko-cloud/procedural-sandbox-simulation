extends Node
class_name SimulationRuntime

## SceneTree adapter for the pure FixedTickScheduler.
##
## This node owns no simulation content yet. P4.0A only establishes deterministic
## logical time, bounded admission, pause/step controls and observability.

const SchedulerScript := preload("res://scripts/simulation/fixed_tick_scheduler.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")

const DEFAULT_TICK_USEC := FixedTickScheduler.DEFAULT_TICK_USEC
const DEFAULT_MAX_TICKS_PER_FRAME := FixedTickScheduler.DEFAULT_MAX_TICKS_PER_FRAME

var scheduler: FixedTickScheduler
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
	start_paused: bool = false
) -> Dictionary:
	if initialized:
		return {"ok": false, "reason": "simulation_runtime_already_initialized"}

	scheduler = SchedulerScript.new()
	var result: Dictionary = scheduler.initialize(
		tick_usec, max_ticks_per_frame, start_tick, start_paused
	)
	if not result.get("ok", false):
		initialization_error = String(result.get("reason", "scheduler_initialization_failed"))
		return result

	_fractional_usec = 0.0
	_last_result = {}
	initialization_error = ""
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": scheduler.get_authoritative_snapshot(),
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
	_fractional_usec = total_usec - float(elapsed_usec)
	return process_elapsed_usec(elapsed_usec)


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


func get_scheduler_snapshot() -> Dictionary:
	if not initialized or scheduler == null:
		return {}
	return scheduler.get_authoritative_snapshot()


func get_scheduler_metrics() -> Dictionary:
	if not initialized or scheduler == null:
		return {}
	return scheduler.get_metrics()


func consume_last_scheduler_result() -> Dictionary:
	var result: Dictionary = _last_result.duplicate(true)
	_last_result.clear()
	return result


func restore_scheduler_snapshot(snapshot: Dictionary) -> Dictionary:
	if scheduler == null:
		scheduler = SchedulerScript.new()
	var result: Dictionary = scheduler.restore_snapshot(snapshot)
	if not result.get("ok", false):
		initialization_error = String(result.get("reason", "scheduler_restore_failed"))
		return result
	_fractional_usec = 0.0
	_last_result = {}
	initialization_error = ""
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": scheduler.get_authoritative_snapshot(),
	}
