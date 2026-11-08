extends RefCounted
class_name FixedTickScheduler

## Engine-owned deterministic fixed-tick admission core.
##
## The scheduler owns only logical time and bounded tick admission. It does not
## execute gameplay callbacks, mutate SceneTree state, or inspect world content.
## Callers provide integer elapsed microseconds so replay tests can avoid
## frame-rate-dependent floating-point accumulation.

const SNAPSHOT_SCHEMA_VERSION := 1
const DEFAULT_TICK_USEC := 100_000
const DEFAULT_MAX_TICKS_PER_FRAME := 4
const MAX_TICK_USEC := 60_000_000
const MAX_TICKS_PER_FRAME_HARD := 64
const MAX_MANUAL_STEP_QUEUE := 1024
const MAX_ELAPSED_USEC_PER_CALL := 86_400_000_000

const SNAPSHOT_KEYS: Array[String] = [
	"schema_version",
	"tick_usec",
	"max_ticks_per_frame",
	"current_tick",
	"accumulator_usec",
	"backlog_ticks",
	"manual_step_ticks",
	"paused",
]

var initialized := false

var _tick_usec := DEFAULT_TICK_USEC
var _max_ticks_per_frame := DEFAULT_MAX_TICKS_PER_FRAME
var _current_tick := 0
var _accumulator_usec := 0
var _backlog_ticks := 0
var _manual_step_ticks := 0
var _paused := false

var _frames_processed := 0
var _total_ticks_admitted := 0
var _frames_with_backlog := 0
var _peak_backlog_ticks := 0
var _peak_ticks_admitted_per_frame := 0
var _last_admitted_ticks := 0
var _last_newly_due_ticks := 0


func initialize(
	tick_usec: int = DEFAULT_TICK_USEC,
	max_ticks_per_frame: int = DEFAULT_MAX_TICKS_PER_FRAME,
	start_tick: int = 0,
	start_paused: bool = false
) -> Dictionary:
	if initialized:
		return _failure("scheduler_already_initialized")
	var config_validation: Dictionary = _validate_config(
		tick_usec, max_ticks_per_frame, start_tick
	)
	if not config_validation.get("ok", false):
		return config_validation

	_tick_usec = tick_usec
	_max_ticks_per_frame = max_ticks_per_frame
	_current_tick = start_tick
	_accumulator_usec = 0
	_backlog_ticks = 0
	_manual_step_ticks = 0
	_paused = start_paused
	_reset_telemetry()
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": get_authoritative_snapshot(),
	}


func process_elapsed_usec(elapsed_usec: int) -> Dictionary:
	if not initialized:
		return _failure("scheduler_not_initialized")
	if elapsed_usec < 0:
		return _failure("elapsed_usec_negative")
	if elapsed_usec > MAX_ELAPSED_USEC_PER_CALL:
		return _failure("elapsed_usec_exceeds_bound")

	_frames_processed += 1
	var newly_due_ticks: int = 0
	var admitted_ticks: int = 0
	var source: String = "paused"

	if _paused:
		if _manual_step_ticks > 0:
			source = "manual_step"
			admitted_ticks = mini(_manual_step_ticks, _max_ticks_per_frame)
			var consumed_backlog_ticks: int = mini(admitted_ticks, _backlog_ticks)
			_backlog_ticks -= consumed_backlog_ticks
			_manual_step_ticks -= admitted_ticks
	else:
		source = "elapsed"
		var total_usec: int = _accumulator_usec + elapsed_usec
		newly_due_ticks = int(total_usec / _tick_usec)
		_accumulator_usec = total_usec % _tick_usec
		_backlog_ticks += newly_due_ticks
		_peak_backlog_ticks = maxi(_peak_backlog_ticks, _backlog_ticks)
		admitted_ticks = mini(_backlog_ticks, _max_ticks_per_frame)
		_backlog_ticks -= admitted_ticks

	var first_tick: int = -1
	var last_tick: int = -1
	if admitted_ticks > 0:
		first_tick = _current_tick + 1
		_current_tick += admitted_ticks
		last_tick = _current_tick
		_total_ticks_admitted += admitted_ticks
		_peak_ticks_admitted_per_frame = maxi(
			_peak_ticks_admitted_per_frame, admitted_ticks
		)
	if _backlog_ticks > 0:
		_frames_with_backlog += 1

	_last_admitted_ticks = admitted_ticks
	_last_newly_due_ticks = newly_due_ticks
	return {
		"ok": true,
		"reason": "ok",
		"frame_index": _frames_processed,
		"source": source,
		"first_tick": first_tick,
		"last_tick": last_tick,
		"admitted_ticks": admitted_ticks,
		"newly_due_ticks": newly_due_ticks,
		"current_tick": _current_tick,
		"logical_time_usec": _current_tick * _tick_usec,
		"accumulator_usec": _accumulator_usec,
		"backlog_ticks": _backlog_ticks,
		"manual_step_ticks": _manual_step_ticks,
		"paused": _paused,
	}


func set_paused(value: bool) -> Dictionary:
	if not initialized:
		return _failure("scheduler_not_initialized")
	if not value and _manual_step_ticks > 0:
		return _failure("manual_steps_pending")
	_paused = value
	return {
		"ok": true,
		"reason": "ok",
		"paused": _paused,
		"backlog_ticks": _backlog_ticks,
		"manual_step_ticks": _manual_step_ticks,
	}


func request_steps(count: int = 1) -> Dictionary:
	if not initialized:
		return _failure("scheduler_not_initialized")
	if not _paused:
		return _failure("manual_step_requires_pause")
	if count <= 0:
		return _failure("manual_step_count_invalid")
	if count > MAX_MANUAL_STEP_QUEUE - _manual_step_ticks:
		return _failure("manual_step_queue_limit")
	_manual_step_ticks += count
	return {
		"ok": true,
		"reason": "ok",
		"manual_step_ticks": _manual_step_ticks,
	}


func get_authoritative_snapshot() -> Dictionary:
	if not initialized:
		return {}
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"tick_usec": _tick_usec,
		"max_ticks_per_frame": _max_ticks_per_frame,
		"current_tick": _current_tick,
		"accumulator_usec": _accumulator_usec,
		"backlog_ticks": _backlog_ticks,
		"manual_step_ticks": _manual_step_ticks,
		"paused": _paused,
	}


func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_snapshot(snapshot)
	if not validation.get("ok", false):
		return validation

	_tick_usec = int(snapshot["tick_usec"])
	_max_ticks_per_frame = int(snapshot["max_ticks_per_frame"])
	_current_tick = int(snapshot["current_tick"])
	_accumulator_usec = int(snapshot["accumulator_usec"])
	_backlog_ticks = int(snapshot["backlog_ticks"])
	_manual_step_ticks = int(snapshot["manual_step_ticks"])
	_paused = bool(snapshot["paused"])
	_reset_telemetry()
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": get_authoritative_snapshot(),
	}


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_keys(snapshot, SNAPSHOT_KEYS):
		return _failure("scheduler_snapshot_fields_invalid")
	if not _is_int(snapshot.get("schema_version")) 		or int(snapshot["schema_version"]) != SNAPSHOT_SCHEMA_VERSION:
		return _failure("scheduler_snapshot_schema_unsupported")
	if not _is_int(snapshot.get("tick_usec")) 		or not _is_int(snapshot.get("max_ticks_per_frame")) 		or not _is_int(snapshot.get("current_tick")) 		or not _is_int(snapshot.get("accumulator_usec")) 		or not _is_int(snapshot.get("backlog_ticks")) 		or not _is_int(snapshot.get("manual_step_ticks")):
		return _failure("scheduler_snapshot_integer_invalid")
	if typeof(snapshot.get("paused")) != TYPE_BOOL:
		return _failure("scheduler_snapshot_pause_invalid")

	var tick_usec: int = int(snapshot["tick_usec"])
	var max_ticks_per_frame: int = int(snapshot["max_ticks_per_frame"])
	var current_tick: int = int(snapshot["current_tick"])
	var config_validation: Dictionary = _validate_config(
		tick_usec, max_ticks_per_frame, current_tick
	)
	if not config_validation.get("ok", false):
		return config_validation

	var accumulator_usec: int = int(snapshot["accumulator_usec"])
	var backlog_ticks: int = int(snapshot["backlog_ticks"])
	var manual_step_ticks: int = int(snapshot["manual_step_ticks"])
	var paused: bool = bool(snapshot["paused"])

	if accumulator_usec < 0 or accumulator_usec >= tick_usec:
		return _failure("scheduler_snapshot_accumulator_invalid")
	if backlog_ticks < 0:
		return _failure("scheduler_snapshot_backlog_invalid")
	if manual_step_ticks < 0 or manual_step_ticks > MAX_MANUAL_STEP_QUEUE:
		return _failure("scheduler_snapshot_manual_steps_invalid")
	if not paused and manual_step_ticks != 0:
		return _failure("scheduler_snapshot_running_manual_steps_invalid")
	return {"ok": true, "reason": "ok"}


func get_metrics() -> Dictionary:
	if not initialized:
		return {}
	return {
		"tick_usec": _tick_usec,
		"max_ticks_per_frame": _max_ticks_per_frame,
		"current_tick": _current_tick,
		"logical_time_usec": _current_tick * _tick_usec,
		"accumulator_usec": _accumulator_usec,
		"backlog_ticks": _backlog_ticks,
		"manual_step_ticks": _manual_step_ticks,
		"paused": _paused,
		"frames_processed": _frames_processed,
		"total_ticks_admitted": _total_ticks_admitted,
		"frames_with_backlog": _frames_with_backlog,
		"peak_backlog_ticks": _peak_backlog_ticks,
		"peak_ticks_admitted_per_frame": _peak_ticks_admitted_per_frame,
		"last_admitted_ticks": _last_admitted_ticks,
		"last_newly_due_ticks": _last_newly_due_ticks,
	}


func is_paused() -> bool:
	return _paused


func get_current_tick() -> int:
	return _current_tick


func get_tick_usec() -> int:
	return _tick_usec


func get_max_ticks_per_frame() -> int:
	return _max_ticks_per_frame


func _validate_config(
	tick_usec: int,
	max_ticks_per_frame: int,
	start_tick: int
) -> Dictionary:
	if tick_usec <= 0 or tick_usec > MAX_TICK_USEC:
		return _failure("tick_usec_invalid")
	if max_ticks_per_frame <= 0 or max_ticks_per_frame > MAX_TICKS_PER_FRAME_HARD:
		return _failure("max_ticks_per_frame_invalid")
	if start_tick < 0:
		return _failure("start_tick_invalid")
	return {"ok": true, "reason": "ok"}


func _reset_telemetry() -> void:
	_frames_processed = 0
	_total_ticks_admitted = 0
	_frames_with_backlog = 0
	_peak_backlog_ticks = _backlog_ticks
	_peak_ticks_admitted_per_frame = 0
	_last_admitted_ticks = 0
	_last_newly_due_ticks = 0


func _has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true


func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
