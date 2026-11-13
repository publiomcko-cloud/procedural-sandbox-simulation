extends SceneTree

const Policy := preload("res://scripts/terrain/dm10_motion_aware_visual_policy.gd")

var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var idle := Policy.plan(4, "balanced", 0.0, true, 0, 0, 16.6, 4.0, 1000000)
	_check(idle["state"] == "idle" and idle["limit"] == 4 and idle["may_submit"],
		"stationary and canonical-ready: four workers")
	var idle_loading := Policy.plan(4, "balanced", 0.0, false, 8, 4, 16.6, 4.0, 1000000)
	_check(not idle_loading["may_submit"], "stationary missing core yields to canonical")
	var slow := Policy.plan(4, "balanced", 2.0, true, 0, 0, 16.6, 4.0, 1000000)
	_check(slow["state"] == "slow" and slow["limit"] == 4 and slow["may_submit"],
		"2m/s motion retains high visual throughput")
	var slow_cooldown := Policy.plan(4, "balanced", 2.0, true, 0, 0, 16.6, 4.0, 100000)
	_check(not slow_cooldown["may_submit"], "slow motion short cooldown")
	var slow_loading := Policy.plan(4, "balanced", 2.0, true, 2, 6, 16.6, 4.0, 600000)
	_check(slow_loading["limit"] == 1 and not slow_loading["may_submit"],
		"slow but canonical busy yields CPU")
	var slow_missing := Policy.plan(4, "balanced", 2.0, false, 2, 6, 16.6, 4.0, 1000000)
	_check(not slow_missing["may_submit"], "slow motion cannot starve missing core")
	var moving_missing := Policy.plan(4, "balanced", 18.0, false, 4, 7, 16.6, 4.0, 950000)
	_check(moving_missing["state"] == "directional" and not moving_missing["may_submit"],
		"normal-speed canonical pressure throttles visual dispatch")
	var moving_admitted := Policy.plan(4, "balanced", 18.0, false, 4, 7, 16.6, 4.0, 1100000)
	_check(moving_admitted["may_submit"] and moving_admitted["limit"] == 1,
		"balanced normal speed permits occasional non-starving visual progress")
	var guarded := Policy.plan(4, "guarded", 18.0, false, 4, 7, 16.6, 4.0, 4000000)
	_check(not guarded["may_submit"] and guarded["reason"] == "guarded_missing_core",
		"guarded profile protects missing canonical core")
	var moving_ready := Policy.plan(4, "balanced", 18.0, true, 0, 0, 16.6, 4.0, 350000)
	_check(moving_ready["may_submit"] and moving_ready["limit"] == 1,
		"normal speed, canonical ready schedules one visual task")
	var moving_busy := Policy.plan(4, "balanced", 18.0, true, 1, 5, 16.6, 4.0, 650000)
	_check(not moving_busy["may_submit"], "in-flight canonical work imposes cooldown")
	var moving_busy_admit := Policy.plan(4, "balanced", 18.0, true, 1, 5, 16.6, 4.0, 720000)
	_check(moving_busy_admit["may_submit"], "bounded visual progress after cooldown")
	var spike := Policy.plan(4, "balanced", 18.0, true, 0, 0, 24.0, 15.0, 500000)
	_check(not spike["may_submit"], "mild frame pressure extends cooldown")
	var overload := Policy.plan(4, "balanced", 0.0, true, 0, 0, 37.0, 15.0, 5000000)
	_check(not overload["may_submit"], "high frame pressure stops new submissions")
	var bad := Policy.plan(4, "balanced", NAN, true, 0, 0, 16.6, 4.0, 5000000)
	_check(not bad["may_submit"], "invalid velocity fails closed")
	var one_worker := Policy.plan(1, "balanced", 0.0, true, 0, 0, 16.6, 4.0, 1000000)
	_check(one_worker["limit"] == 1, "bounded configured max")
	var original: Array[Vector2i] = [
		Vector2i(-2, 0), Vector2i(0, 2), Vector2i(2, 0), Vector2i(0, -2)
	]
	var ordered := Policy.prioritize_direction(original, Vector3(8, 0, 6), Vector3(18, 0, 0))
	_check(ordered[0] == Vector2i(2,0), "actual eastward velocity prioritizes forward shell")
	_check(ordered[-1] == Vector2i(-2,0), "backward shell ranks last")
	_check(ordered.size() == original.size(), "no region added/dropped")
	for key in original:
		_check(ordered.has(key), "preserve exact existing region set")
	var reversed := Policy.prioritize_direction(original, Vector3(8, 0, 6), Vector3(-18, 0, 0))
	_check(reversed[0] == Vector2i(-2,0), "direction reversal changes priority")
	var unmoved := Policy.prioritize_direction(original, Vector3(8,0,6), Vector3.ZERO)
	_check(unmoved == original, "stationary keeps original exact distance order")
	_check(original[0] == Vector2i(-2,0), "ranking cannot mutate input order")
	print("DM10_MOTION_QOS_RESULT=" + JSON.stringify({
		"assertions": assertions, "failures": failures,
		"modes": ["stationary", "slow", "directional"],
		"policies": ["balanced", "guarded"],
		"canonical_authority_unchanged": true,
		"geometry_unchanged": true,
	}))
	print("DM10_MOTION_QOS_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("DM10_MOTION_QOS_FAIL: " + message)
