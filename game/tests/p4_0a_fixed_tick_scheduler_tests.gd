extends SceneTree

const SchedulerScript := preload("res://scripts/simulation/fixed_tick_scheduler.gd")
const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_configuration_contract()
	_test_exact_fixed_tick_cadence()
	_test_bounded_catchup_and_frame_slicing_equivalence()
	_test_pause_and_manual_step_semantics()
	_test_snapshot_restore_and_validation()
	_test_runtime_adapter()
	_test_playable_scene_mount()

	if failures == 0:
		print("P4_0A_FIXED_TICK_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error(
			"P4_0A_FIXED_TICK_FAIL: assertions=%d failures=%d"
			% [assertions, failures]
		)
	quit(0 if failures == 0 else 1)


func _test_configuration_contract() -> void:
	var zero_tick: FixedTickScheduler = SchedulerScript.new()
	_check(
		zero_tick.initialize(0, 4).get("reason", "") == "tick_usec_invalid",
		"zero tick duration fails closed"
	)

	var oversized_tick: FixedTickScheduler = SchedulerScript.new()
	_check(
		oversized_tick.initialize(
			FixedTickScheduler.MAX_TICK_USEC + 1, 4
		).get("reason", "") == "tick_usec_invalid",
		"tick duration has an explicit upper bound"
	)

	var zero_budget: FixedTickScheduler = SchedulerScript.new()
	_check(
		zero_budget.initialize(1000, 0).get("reason", "")
			== "max_ticks_per_frame_invalid",
		"zero per-frame admission budget is rejected"
	)

	var oversized_budget: FixedTickScheduler = SchedulerScript.new()
	_check(
		oversized_budget.initialize(
			1000, FixedTickScheduler.MAX_TICKS_PER_FRAME_HARD + 1
		).get("reason", "") == "max_ticks_per_frame_invalid",
		"per-frame admission budget has a hard engine bound"
	)

	var negative_start: FixedTickScheduler = SchedulerScript.new()
	_check(
		negative_start.initialize(1000, 4, -1).get("reason", "")
			== "start_tick_invalid",
		"negative logical tick identity is rejected"
	)

	var scheduler: FixedTickScheduler = SchedulerScript.new()
	var initialized: Dictionary = scheduler.initialize(1000, 4, 7, true)
	_check(
		initialized.get("ok", false)
			and scheduler.get_current_tick() == 7
			and scheduler.is_paused(),
		"valid scheduler configuration initializes exact logical identity"
	)
	_check(
		scheduler.initialize(1000, 4).get("reason", "")
			== "scheduler_already_initialized",
		"scheduler initialization is single-commit"
	)


func _test_exact_fixed_tick_cadence() -> void:
	var scheduler: FixedTickScheduler = _new_scheduler(100_000, 4)

	var before_boundary: Dictionary = scheduler.process_elapsed_usec(99_999)
	_check(
		before_boundary.get("ok", false)
			and int(before_boundary.get("admitted_ticks", -1)) == 0
			and int(before_boundary.get("accumulator_usec", -1)) == 99_999,
		"sub-tick elapsed time accumulates without advancing logical time"
	)

	var boundary: Dictionary = scheduler.process_elapsed_usec(1)
	_check(
		int(boundary.get("admitted_ticks", -1)) == 1
			and int(boundary.get("first_tick", -1)) == 1
			and int(boundary.get("last_tick", -1)) == 1
			and int(boundary.get("accumulator_usec", -1)) == 0,
		"exact tick boundary advances one deterministic logical tick"
	)

	var three_ticks: Dictionary = scheduler.process_elapsed_usec(300_000)
	_check(
		int(three_ticks.get("admitted_ticks", -1)) == 3
			and int(three_ticks.get("current_tick", -1)) == 4
			and int(three_ticks.get("backlog_ticks", -1)) == 0,
		"multiple due ticks are admitted in deterministic ascending order"
	)

	var snapshot: Dictionary = scheduler.get_authoritative_snapshot()
	_check(
		int(snapshot.get("current_tick", -1)) == 4
			and int(snapshot.get("accumulator_usec", -1)) == 0,
		"authoritative scheduler snapshot records exact logical time"
	)

	var prior: Dictionary = snapshot.duplicate(true)
	_check(
		scheduler.process_elapsed_usec(-1).get("reason", "") == "elapsed_usec_negative"
			and scheduler.get_authoritative_snapshot() == prior,
		"negative elapsed input fails without mutating scheduler state"
	)
	_check(
		scheduler.process_elapsed_usec(
			FixedTickScheduler.MAX_ELAPSED_USEC_PER_CALL + 1
		).get("reason", "") == "elapsed_usec_exceeds_bound"
			and scheduler.get_authoritative_snapshot() == prior,
		"single-call elapsed input is explicitly bounded and atomic on rejection"
	)

	var backlog_guard: FixedTickScheduler = _new_scheduler(1, 1)
	var backlog_guard_prior: Dictionary = backlog_guard.get_authoritative_snapshot()
	_check(
		backlog_guard.process_elapsed_usec(
			FixedTickScheduler.MAX_BACKLOG_TICKS_HARD + 1
		).get("reason", "") == "backlog_limit_exceeded"
			and backlog_guard.get_authoritative_snapshot() == backlog_guard_prior,
		"deferred backlog has a hard scalar bound and overflow rejection is atomic"
	)


func _test_bounded_catchup_and_frame_slicing_equivalence() -> void:
	var sliced: FixedTickScheduler = _new_scheduler(1000, 4)
	for _index in range(10):
		var result: Dictionary = sliced.process_elapsed_usec(1000)
		_check(
			int(result.get("admitted_ticks", -1)) == 1,
			"one-tick frame slice admits exactly one tick"
		)

	var burst: FixedTickScheduler = _new_scheduler(1000, 4)
	var first_burst: Dictionary = burst.process_elapsed_usec(10_000)
	_check(
		int(first_burst.get("admitted_ticks", -1)) == 4
			and int(first_burst.get("newly_due_ticks", -1)) == 10
			and int(first_burst.get("backlog_ticks", -1)) == 6,
		"catch-up admits only the configured per-frame budget"
	)
	var second_burst: Dictionary = burst.process_elapsed_usec(0)
	_check(
		int(second_burst.get("admitted_ticks", -1)) == 4
			and int(second_burst.get("backlog_ticks", -1)) == 2,
		"deferred catch-up backlog drains incrementally without new elapsed time"
	)
	var third_burst: Dictionary = burst.process_elapsed_usec(0)
	_check(
		int(third_burst.get("admitted_ticks", -1)) == 2
			and int(third_burst.get("backlog_ticks", -1)) == 0,
		"final deferred backlog drains without dropping due ticks"
	)
	_check(
		burst.get_authoritative_snapshot() == sliced.get_authoritative_snapshot(),
		"equivalent elapsed time converges to the same authoritative scheduler state regardless of frame slicing"
	)

	var burst_metrics: Dictionary = burst.get_metrics()
	_check(
		int(burst_metrics.get("peak_backlog_ticks", -1)) == 10
			and int(burst_metrics.get("peak_ticks_admitted_per_frame", -1)) == 4,
		"telemetry records backlog pressure and the enforced admission ceiling"
	)

	var large_backlog: FixedTickScheduler = _new_scheduler(1000, 3)
	var large_result: Dictionary = large_backlog.process_elapsed_usec(1_000_000)
	_check(
		int(large_result.get("newly_due_ticks", -1)) == 1000
			and int(large_result.get("admitted_ticks", -1)) == 3
			and int(large_result.get("backlog_ticks", -1)) == 997,
		"large catch-up is represented as scalar backlog instead of unbounded same-frame work"
	)
	var drain_once: Dictionary = large_backlog.process_elapsed_usec(0)
	_check(
		int(drain_once.get("admitted_ticks", -1)) == 3
			and int(drain_once.get("backlog_ticks", -1)) == 994,
		"each later frame remains bounded while backlog is deferred deterministically"
	)


func _test_pause_and_manual_step_semantics() -> void:
	var scheduler: FixedTickScheduler = _new_scheduler(100, 2)

	var partial: Dictionary = scheduler.process_elapsed_usec(50)
	_check(
		int(partial.get("accumulator_usec", -1)) == 50
			and int(partial.get("current_tick", -1)) == 0,
		"pause fixture retains a sub-tick accumulator"
	)
	_check(
		scheduler.set_paused(true).get("ok", false),
		"simulation can enter paused state explicitly"
	)

	var ignored_elapsed: Dictionary = scheduler.process_elapsed_usec(10_000)
	_check(
		int(ignored_elapsed.get("admitted_ticks", -1)) == 0
			and int(ignored_elapsed.get("accumulator_usec", -1)) == 50
			and int(ignored_elapsed.get("current_tick", -1)) == 0,
		"paused scheduler ignores wall elapsed time and preserves fractional logical progress"
	)
	_check(
		scheduler.request_steps(3).get("ok", false),
		"paused scheduler accepts an explicit bounded manual-step request"
	)

	var first_manual: Dictionary = scheduler.process_elapsed_usec(0)
	_check(
		int(first_manual.get("admitted_ticks", -1)) == 2
			and int(first_manual.get("manual_step_ticks", -1)) == 1
			and String(first_manual.get("source", "")) == "manual_step",
		"manual steps obey the same per-frame admission budget"
	)
	_check(
		scheduler.set_paused(false).get("reason", "") == "manual_steps_pending",
		"resume fails closed while requested manual steps remain pending"
	)

	var second_manual: Dictionary = scheduler.process_elapsed_usec(0)
	_check(
		int(second_manual.get("admitted_ticks", -1)) == 1
			and int(second_manual.get("current_tick", -1)) == 3,
		"remaining manual step advances exactly one logical tick"
	)
	_check(
		scheduler.set_paused(false).get("ok", false),
		"simulation resumes once the manual-step queue is empty"
	)

	var resumed: Dictionary = scheduler.process_elapsed_usec(50)
	_check(
		int(resumed.get("admitted_ticks", -1)) == 1
			and int(resumed.get("current_tick", -1)) == 4
			and int(resumed.get("accumulator_usec", -1)) == 0,
		"resume continues from the preserved pre-pause accumulator"
	)
	_check(
		scheduler.request_steps(1).get("reason", "")
			== "manual_step_requires_pause",
		"manual stepping is unavailable while normal simulation is running"
	)

	_check(
		scheduler.set_paused(true).get("ok", false),
		"scheduler can pause again after resumed progress"
	)
	_check(
		scheduler.request_steps(
			FixedTickScheduler.MAX_MANUAL_STEP_QUEUE
		).get("ok", false),
		"manual-step queue accepts its exact bounded capacity"
	)
	_check(
		scheduler.request_steps(1).get("reason", "")
			== "manual_step_queue_limit",
		"manual-step queue rejects overflow without expanding its bound"
	)


func _test_snapshot_restore_and_validation() -> void:
	var original: FixedTickScheduler = _new_scheduler(100, 3)
	var first: Dictionary = original.process_elapsed_usec(550)
	_check(
		int(first.get("current_tick", -1)) == 3
			and int(first.get("backlog_ticks", -1)) == 2
			and int(first.get("accumulator_usec", -1)) == 50,
		"snapshot fixture contains backlog and fractional time"
	)
	_check(original.set_paused(true).get("ok", false), "snapshot fixture pauses")
	_check(original.request_steps(2).get("ok", false), "snapshot fixture queues steps")

	var snapshot: Dictionary = original.get_authoritative_snapshot()
	var restored: FixedTickScheduler = SchedulerScript.new()
	var restore_result: Dictionary = restored.restore_snapshot(snapshot)
	_check(
		restore_result.get("ok", false)
			and restored.get_authoritative_snapshot() == snapshot,
		"authoritative scheduler snapshot restores byte-equivalent logical state"
	)

	var original_step: Dictionary = original.process_elapsed_usec(0)
	var restored_step: Dictionary = restored.process_elapsed_usec(0)
	_check(
		int(original_step.get("admitted_ticks", -1))
				== int(restored_step.get("admitted_ticks", -1))
			and int(original_step.get("first_tick", -1))
				== int(restored_step.get("first_tick", -1))
			and int(original_step.get("last_tick", -1))
				== int(restored_step.get("last_tick", -1))
			and original.get_authoritative_snapshot()
				== restored.get_authoritative_snapshot(),
		"restored scheduler replays the same next admitted tick batch independent of telemetry counters"
	)
	_check(
		original.set_paused(false).get("ok", false)
			and restored.set_paused(false).get("ok", false),
		"original and restored schedulers resume after equal step drain"
	)

	var original_resume: Dictionary = original.process_elapsed_usec(50)
	var restored_resume: Dictionary = restored.process_elapsed_usec(50)
	_check(
		int(original_resume.get("admitted_ticks", -1))
				== int(restored_resume.get("admitted_ticks", -1))
			and int(original_resume.get("current_tick", -1))
				== int(restored_resume.get("current_tick", -1))
			and original.get_authoritative_snapshot()
				== restored.get_authoritative_snapshot(),
		"restored scheduler preserves deterministic post-resume evolution independent of telemetry counters"
	)

	var unknown_field: Dictionary = snapshot.duplicate(true)
	unknown_field["unexpected"] = true
	var validator: FixedTickScheduler = SchedulerScript.new()
	_check(
		validator.validate_snapshot(unknown_field).get("reason", "")
			== "scheduler_snapshot_fields_invalid",
		"snapshot contract rejects unknown fields"
	)

	var negative_backlog: Dictionary = snapshot.duplicate(true)
	negative_backlog["backlog_ticks"] = -1
	_check(
		validator.validate_snapshot(negative_backlog).get("reason", "")
			== "scheduler_snapshot_backlog_invalid",
		"snapshot contract rejects negative deferred backlog"
	)

	var running_steps: Dictionary = snapshot.duplicate(true)
	running_steps["paused"] = false
	_check(
		validator.validate_snapshot(running_steps).get("reason", "")
			== "scheduler_snapshot_running_manual_steps_invalid",
		"snapshot contract rejects manual-step backlog in running state"
	)

	var invalid_accumulator: Dictionary = snapshot.duplicate(true)
	invalid_accumulator["accumulator_usec"] = int(snapshot["tick_usec"])
	_check(
		validator.validate_snapshot(invalid_accumulator).get("reason", "")
			== "scheduler_snapshot_accumulator_invalid",
		"snapshot contract enforces sub-tick accumulator range"
	)


func _test_runtime_adapter() -> void:
	var runtime: SimulationRuntime = RuntimeScript.new()
	var initialized: Dictionary = runtime.initialize_runtime(100, 2)
	_check(
		initialized.get("ok", false),
		"runtime adapter initializes the pure fixed-tick core"
	)

	var first: Dictionary = runtime.process_delta_seconds(0.00025)
	_check(
		int(first.get("admitted_ticks", -1)) == 2
			and int(first.get("current_tick", -1)) == 2
			and int(first.get("accumulator_usec", -1)) == 50,
		"runtime adapter converts frame delta into bounded integer-microsecond admission"
	)

	_check(
		runtime.set_simulation_paused(true).get("ok", false),
		"runtime adapter exposes explicit pause control"
	)
	_check(
		runtime.request_simulation_steps(1).get("ok", false),
		"runtime adapter exposes explicit manual stepping"
	)
	var paused_frame: Dictionary = runtime.process_delta_seconds(5.0)
	_check(
		int(paused_frame.get("admitted_ticks", -1)) == 1
			and int(paused_frame.get("current_tick", -1)) == 3
			and int(paused_frame.get("accumulator_usec", -1)) == 50,
		"runtime pause discards real elapsed time while still executing requested logical steps"
	)

	_check(
		runtime.set_simulation_paused(false).get("ok", false),
		"runtime adapter resumes after manual step consumption"
	)
	var resumed: Dictionary = runtime.process_delta_seconds(0.00005)
	_check(
		int(resumed.get("current_tick", -1)) == 4
			and int(resumed.get("accumulator_usec", -1)) == 0,
		"runtime fractional carry resumes without pause-time leakage"
	)

	var metrics: Dictionary = runtime.get_scheduler_metrics()
	_check(
		int(metrics.get("max_ticks_per_frame", -1)) == 2
			and int(metrics.get("current_tick", -1)) == 4,
		"runtime exposes bounded scheduler telemetry without exposing mutable state"
	)
	_check(
		not runtime.consume_last_scheduler_result().is_empty()
			and runtime.consume_last_scheduler_result().is_empty(),
		"runtime scheduler result consumption is one-shot and bounded"
	)
	runtime.free()


func _test_playable_scene_mount() -> void:
	var packed: PackedScene = load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "playable terrain scene loads with P4.0A runtime dependency")
	if packed == null:
		return
	var scene: Node = packed.instantiate()
	_check(
		scene.has_node("SimulationRuntime"),
		"playable terrain scene mounts one engine-owned SimulationRuntime"
	)
	if scene.has_node("SimulationRuntime"):
		var runtime_node: Node = scene.get_node("SimulationRuntime")
		_check(
			runtime_node.has_method("get_scheduler_snapshot")
				and runtime_node.has_method("set_simulation_paused")
				and runtime_node.has_method("request_simulation_steps"),
			"playable runtime exposes scheduler control surface without gameplay-specific simulation code"
		)
	scene.free()


func _new_scheduler(
	tick_usec: int,
	max_ticks_per_frame: int,
	start_tick: int = 0,
	start_paused: bool = false
) -> FixedTickScheduler:
	var scheduler: FixedTickScheduler = SchedulerScript.new()
	var result: Dictionary = scheduler.initialize(
		tick_usec, max_ticks_per_frame, start_tick, start_paused
	)
	_check(
		result.get("ok", false),
		"scheduler test fixture initializes (%s)" % result.get("reason", "ok")
	)
	return scheduler


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)
