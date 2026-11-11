extends SceneTree

const Policy := preload("res://scripts/terrain/terrain_stream_budget_policy.gd")
const Selector := preload("res://scripts/terrain/terrain_stream_dispatch_selector.gd")

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
	_test_runtime_profile_resolution()
	_test_stage_skip_selection()
	if failures == 0:
		print("P5_0F_STREAM_BUDGET_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P5_0F_STREAM_BUDGET_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)


## Exact, deterministic stage priority is preserved. A blocked LOAD stage is
## excluded from this call only; a ready neighbor may be processed next.
## Returning to the next frame starts with the original blocked stage again.
func _test_stage_skip_selection() -> void:
	var origin := Vector2i(5, 13)
	var stages := {
		"home": {
			"region_key": origin,
			"purpose": "load",
			"chunk_coordinates": [Vector2i(0, 0), Vector2i(1, 0)],
			"submit_index": 0,
		},
		"near": {
			"region_key": Vector2i(6, 13),
			"purpose": "load",
			"chunk_coordinates": [Vector2i(0, 0), Vector2i(1, 0)],
			"submit_index": 0,
		},
		"far": {
			"region_key": Vector2i(7, 13),
			"purpose": "load",
			"chunk_coordinates": [Vector2i(0, 0)],
			"submit_index": 0,
		},
	}
	var initial := Selector.next(stages, {}, origin)
	_check(initial.get("id", "") == "home",
		"skip policy starts with focused region, preserving original region priority")
	var excluded := {"home": true}
	var next_ready := Selector.next(stages, excluded, origin)
	_check(next_ready.get("id", "") == "near",
		"skip policy passes an effect-pending focused region to next-ready neighbor")
	_check(int(stages["home"]["submit_index"]) == 0,
		"skipping a region never consumes or changes its next chunk")
	_check(next_ready.get("coordinate") == Vector2i(0, 0),
		"new region begins at its own first queued chunk")
	var near: Dictionary = stages["near"]
	near["submit_index"] = 1
	stages["near"] = near
	_check(Selector.next(stages, excluded, origin).get("coordinate") == Vector2i(1, 0),
		"next chunk within the selected region follows strict original order")
	_check(Selector.next(stages, {"home": true, "near": true}, origin).get("id") == "far",
		"multiple blocked regions are excluded for this invocation only")
	_check(Selector.next(stages, {"home": true, "near": true, "far": true}, origin).is_empty(),
		"no candidate terminates immediately, preventing endless spinning")
	_check(Selector.next(stages, {}, origin).get("id") == "home",
		"blocked region becomes eligible again on next frame")
	var edit := {
		"region_key": Vector2i(7, 13),
		"purpose": "edit_transaction",
		"chunk_coordinates": [Vector2i(2, 1)],
		"submit_index": 0,
	}
	stages["edit"] = edit
	_check(Selector.next(stages, {}, origin).get("id") == "edit",
		"edit transaction priority remains higher than regular load stages")
	_check(Selector.next(stages, {"edit": true}, origin).get("id") == "home",
		"explicit exclusion does not mutate edit transaction queue")
	var policy_cases := [
		["adaptive-skip", "load", 0, 1500, 3500, true, true],
		["adaptive-skip-lookahead", "load", 0, 1500, 3500, true, true],
		["adaptive-skip-dependency", "load", 0, 1500, 3500, true, true],
		["adaptive-skip-lookahead", "load", 3, 1500, 3500, true, false],
		["adaptive-skip-lookahead", "edit_transaction", 0, 1500, 3500, true, false],
		["adaptive-skip", "load", 2, 3499, 3500, true, true],
		["adaptive-skip", "load", 3, 500, 3500, true, false],
		["adaptive-skip", "load", 0, 3500, 3500, true, false],
		["adaptive-skip", "load", 0, 500, 3500, false, false],
		["baseline", "load", 0, 500, 3500, true, false],
		["adaptive", "load", 0, 500, 3500, true, false],
		["adaptive-skip", "edit_transaction", 0, 500, 3500, true, false],
		["adaptive-skip", "partial", 0, 500, 3500, true, false],
		["adaptive-skip", "full", 0, 500, 3500, true, false],
	]
	for entry in policy_cases:
		var accepted: bool = Selector.can_skip_pending(
			String(entry[0]), String(entry[1]), int(entry[2]),
			int(entry[3]), int(entry[4]), bool(entry[5])
		)
		_check(accepted == bool(entry[6]),
			"skip eligibility enforces profile, load-only, 3-stage cap, 3.5ms cap, headroom")
	var near_full := stages.duplicate(true)
	near_full.erase("edit")
	var complete: Dictionary = near_full["near"]
	complete["submit_index"] = 2
	near_full["near"] = complete
	_check(Selector.next(near_full, {"home": true}, origin).get("id") == "far",
		"completed region is ignored rather than restarting its chunk index")


## R2 retest blocker: the actual Godot runtime previously coerced any
## environment mode other than "adaptive" to baseline, so the A/B script
## reported adaptive-skip even as PERF_TRACE said baseline.
func _test_runtime_profile_resolution() -> void:
	var empty := PackedStringArray()
	_check(Policy.resolve_profile("", empty) == "baseline",
		"unset environment retains default baseline")
	_check(Policy.resolve_profile("baseline", empty) == "baseline",
		"explicit baseline is supported")
	_check(Policy.resolve_profile("adaptive", empty) == "adaptive",
		"adaptive environment is preserved")
	_check(Policy.resolve_profile("adaptive-skip", empty) == "adaptive-skip",
		"adaptive-skip environment reaches actual runtime without being reset")
	_check(Policy.resolve_profile("adaptive-skip-lookahead", empty) == "adaptive-skip-lookahead",
		"lookahead profile uses same runtime resolver without coercion")
	_check(Policy.resolve_profile("adaptive-skip-dependency", empty) == "adaptive-skip-dependency",
		"dependency profile remains strictly opt-in")
	_check(Policy.resolve_profile("adaptive-skip",
		PackedStringArray(["--stream-profile=adaptive-skip-lookahead"])) == "adaptive-skip-lookahead",
		"CLI opt-in to lookahead overrides ordinary adaptive-skip")
	_check(Policy.resolve_profile(" ADAPTIVE-SKIP ", empty) == "adaptive-skip",
		"case and whitespace do not disable adaptive-skip")
	_check(Policy.resolve_profile("unknown", empty) == "baseline",
		"invalid environment fails closed to baseline")
	_check(Policy.resolve_profile("adaptive-skip",
		PackedStringArray(["--stream-profile=baseline"])) == "baseline",
		"explicit CLI baseline overrides environment")
	_check(Policy.resolve_profile("baseline",
		PackedStringArray(["--stream-profile=adaptive-skip"])) == "adaptive-skip",
		"CLI can opt in to adaptive-skip without environment")
	_check(Policy.resolve_profile("adaptive",
		PackedStringArray(["--unused", "--stream-profile=adaptive-skip"])) == "adaptive-skip",
		"CLI args scan selects requested adaptive-skip profile")
	_check(Policy.resolve_profile("adaptive-skip",
		PackedStringArray(["--stream-profile=unknown"])) == "baseline",
		"invalid CLI override fails closed")
