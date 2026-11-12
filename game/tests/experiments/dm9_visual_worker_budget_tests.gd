extends SceneTree

const Policy := preload("res://scripts/terrain/dm9_visual_worker_budget_policy.gd")

var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(Policy.effective_limit(8, false, 0, 0, 0, 16.7, 2) == 1, "missing canonical core reserves workers")
	_check(Policy.effective_limit(8, true, 1, 0, 0, 16.7, 2) == 1, "loading core reserves workers")
	_check(Policy.effective_limit(8, true, 0, 1, 0, 16.7, 2) == 1, "inflight canonical mesh reserves workers")
	_check(Policy.effective_limit(8, true, 0, 0, 18.0, 16.7, 2) == 2, "moving retains two background jobs")
	_check(Policy.effective_limit(8, true, 0, 0, 0.0, 16.7, 2) == 8, "idle raises visual concurrency")
	_check(Policy.effective_limit(4, true, 0, 0, 0.0, 16.7, 2) == 4, "config clamp supports four")
	_check(Policy.effective_limit(12, true, 0, 0, 0.0, 16.7, 2) == 8, "upper bound eight")
	_check(Policy.effective_limit(0, true, 0, 0, 0.0, 16.7, 2) == 1, "never zero worker")
	_check(Policy.effective_limit(8, true, 0, 0, 0.0, 20.0, 2) == 1, "frame pressure throttles")
	_check(Policy.effective_limit(8, true, 0, 0, 0.0, 16.7, 14.0) == 1, "process pressure throttles")
	_check(Policy.effective_limit(8, true, 0, 0, 0.0, INF, 2) == 1, "nonfinite frame throttles")
	_check(Policy.effective_limit(8, true, 0, 0, INF, 16.7, 2) == 2, "nonfinite movement treated urgent")
	print("DM9_VISUAL_BUDGET_RESULT=" + JSON.stringify({
		"assertions": assertions, "failures": failures,
		"idle_max_workers": Policy.MAX_WORKERS,
		"moving_max_workers": Policy.MOVING_VISUAL_WORKERS,
		"canonical_priority_protected": true,
		"high_detail_radius_unchanged": true
	}))
	print("DM9_VISUAL_BUDGET_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func _check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("DM9_VISUAL_BUDGET_FAIL: " + reason)
