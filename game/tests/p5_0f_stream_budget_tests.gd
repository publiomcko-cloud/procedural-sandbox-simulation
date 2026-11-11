extends SceneTree

const Policy := preload("res://scripts/terrain/terrain_stream_budget_policy.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var baseline: Dictionary = {}
	for _frame in range(100):
		baseline = Policy.next(baseline, 8.0, 3.0, false)
		_check(int(baseline["dispatch_limit"]) == 1, "baseline is always one dispatch/frame")
	var adaptive := Policy.next({}, 16.67, 7.0, true)
	_check(int(adaptive["dispatch_limit"]) == 1, "adaptive begins at conservative baseline")
	for _frame in range(11):
		adaptive = Policy.next(adaptive, 16.67, 7.0, true)
	_check(int(adaptive["dispatch_limit"]) == 2, "adaptive enables second dispatch after stable headroom")
	adaptive = Policy.next(adaptive, 24.0, 8.0, true)
	_check(int(adaptive["dispatch_limit"]) == 1, "slow frame immediately removes bonus dispatch")
	_check(int(adaptive["cooldown_frames"]) == Policy.SPIKE_COOLDOWN_FRAMES, "spike starts cooldown")
	for _frame in range(Policy.SPIKE_COOLDOWN_FRAMES):
		adaptive = Policy.next(adaptive, 8.0, 3.0, true)
		_check(int(adaptive["dispatch_limit"]) == 1, "cooldown protects subsequent frames")
	for _frame in range(Policy.STABLE_FRAMES_REQUIRED):
		adaptive = Policy.next(adaptive, 8.0, 3.0, true)
	_check(int(adaptive["dispatch_limit"]) == 2, "headroom re-enables after cooldown")
	adaptive = Policy.next(adaptive, 16.0, 14.1, true)
	_check(int(adaptive["dispatch_limit"]) == 1, "expensive previous process triggers cooldown")
	adaptive = Policy.next(adaptive, 8.0, 3.0, false)
	_check(int(adaptive["dispatch_limit"]) == 1 and int(adaptive["cooldown_frames"]) == 0,
		"switching back to baseline resets all experimental state")
	if failures == 0:
		print("P5_0F_STREAM_BUDGET_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P5_0F_STREAM_BUDGET_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)
