extends SceneTree

const Priority := preload("res://scripts/terrain/dm24_canonical_stage_priority.gd")
const Probe := preload("res://scripts/diagnostics/dm24_canonical_stage_funnel_probe.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _stage(region: Vector2i, age_usec: int, purpose: String = "load",
		submitted: int = 0) -> Dictionary:
	return {
		"region_key": region, "purpose": purpose,
		"chunk_enqueued_usec": age_usec, "submit_index": submitted,
		"chunk_coordinates": range(16), "stage_token": 31,
		"dm9_speculative": false, "dm18_cache_ready": false
	}


func _run() -> void:
	var focus := Vector2i(1, 1)
	var stages := {
		"far": _stage(Vector2i(0, 0), 100_000, "load", 5),
		"focus": _stage(focus, 800_000),
		"old_neighbor": _stage(Vector2i(2, 1), 200_000),
		"fresh_neighbor": _stage(Vector2i(1, 2), 950_000)
	}
	var original := {"id": "far", "index": 5, "coordinate": 5}
	var chosen: Dictionary = Priority.candidate(stages, {}, focus, 1_000_000, 0, original)
	_check(chosen.get("id") == "focus", "new focal first chunk gets priority")
	_check(int(chosen.get("index", -1)) == 0, "original per-region chunk order")
	chosen = Priority.candidate(stages, {"focus": true}, focus, 1_000_000, 2, original)
	_check(chosen.get("id") == "old_neighbor", "aged neighbor wins one-third slot")
	chosen = Priority.candidate(stages, {"focus": true}, focus, 1_000_000, 1, original)
	_check(chosen.get("id") == "far", "two of three slots keep baseline order")
	chosen = Priority.candidate(stages, {"focus": true, "old_neighbor": true},
		focus, 1_000_000, 2, original)
	_check(chosen.get("id") == "far", "fresh neighbor below age threshold")
	chosen = Priority.candidate(stages, {}, focus, 1_000_000, 2,
		{"id": "edit", "index": 0, "coordinate": 0})
	# Edit/full/partial lookups must be actual stage keys to exercise authority.
	stages["edit"] = _stage(Vector2i(10, 10), 0, "edit_transaction")
	chosen = Priority.candidate(stages, {}, focus, 1_000_000, 2,
		{"id": "edit", "index": 0, "coordinate": 0})
	_check(chosen.get("id") == "edit", "edit transaction strict precedence")
	stages.erase("edit")
	for operation in ["partial", "full"]:
		stages[operation] = _stage(Vector2i(10, 10), 0, operation)
		chosen = Priority.candidate(stages, {}, focus, 1_000_000, 2,
			{"id": operation, "index": 0, "coordinate": 0})
		_check(chosen.get("id") == operation, "non-load precedence " + operation)
		stages.erase(operation)
	stages["focus"]["submit_index"] = 16
	chosen = Priority.candidate(stages, {}, focus, 1_000_000, 0, original)
	_check(chosen.get("id") == "far", "completed focus not retried")
	stages["focus"]["submit_index"] = 0
	stages["focus"]["dm18_cache_ready"] = true
	chosen = Priority.candidate(stages, {}, focus, 1_000_000, 0, original)
	_check(chosen.get("id") == "far", "DM18 cache-ready stage never preempted")
	stages["focus"]["dm18_cache_ready"] = false
	stages["focus"]["dm9_speculative"] = true
	chosen = Priority.candidate(stages, {}, focus, 1_000_000, 0, original)
	_check(chosen.get("id") == "far", "speculative excluded")
	_check(Priority.candidate(stages, {}, focus, 1_000_000, 0, {}).is_empty(),
		"empty selection remains empty")

	var p := Probe.new()
	var observed := _stage(focus, 1_000_000)
	p.begin("focus", 31, 1_000_000, true)
	p.frame({"focus": observed}, focus, 1, 1, 0, 8)
	p.frame({"focus": observed}, focus, 1, 0, 8, 8)
	p.frame({"focus": observed}, focus, 1, 0, 0, 8)
	p.selected(original, {"id": "focus", "coordinate": 0, "index": 0},
		{"id": "focus", "coordinate": 0, "index": 0},
		{"focus": observed}, 1_005_000, true)
	p.first_snapshot("focus", 31, 1_006_000)
	p.effect_pending("focus", 31)
	p.first_dispatched("focus", 31, 1_008_000)
	p.finish("focus", 31, 1_020_000, "published")
	var a: Dictionary = p.summary()
	var c: Dictionary = a["counts"]
	_check(int(c.get("instrumented_frames", 0)) == 3, "frame parity")
	_check(int(c.get("focal_wait_dispatch_budget", 0)) == 1, "dispatch cap")
	_check(int(c.get("focal_wait_worker_capacity", 0)) == 1, "worker capacity")
	_check(int(c.get("focal_eligible_not_yet_submitted", 0)) == 1,
		"eligible stage waiting for scheduler")
	_check(int(c.get("shadow_priority_overrides", 0)) == 1, "shadow evaluated")
	_check(int(c.get("applied_priority_overrides", 0)) == 1, "shadow applied")
	_check(int(c.get("first_chunk_selected_once", 0)) == 1, "first selected")
	_check(int(c.get("first_snapshot_attempted", 0)) == 1, "first prepared")
	_check(int(c.get("first_chunk_effect_pending", 0)) == 1, "blocked on effects")
	_check(int(c.get("first_chunks_dispatched", 0)) == 1, "first dispatched")
	_check(int(c.get("published", 0)) == 1, "final publication")
	_check(int(a["latency"]["creation_to_first_selection_ms"]["mean_ms"]) == 5,
		"created to eligibility selection latency")
	_check(int(a["latency"]["first_selection_to_snapshot_ms"]["mean_ms"]) == 1,
		"selection to snapshot latency")
	_check(int(a["latency"]["first_snapshot_to_dispatch_ms"]["mean_ms"]) == 2,
		"effect wait before dispatch")
	_check(int(a["active_stages"]) == 0, "no leaked completed stage")

	p.begin("neighbor", 32, 2_000_000, false)
	p.focus_enter("neighbor", 32, 2_010_000)
	p.finish("neighbor", 32, 2_020_000, "left_window")
	c = p.summary()["counts"]
	_check(int(c.get("ended_never_selected", 0)) == 1,
		"unselected focus-stage cancellation")
	_check(int(c.get("ended_after_focus_without_first_dispatch", 0)) == 1,
		"cancel after entering focus before first chunk")
	p.begin("neighbor", 33, 3_000_000, false)
	var next_stage := _stage(Vector2i(2, 1), 3_000_000)
	next_stage["stage_token"] = 33
	p.selected({"id": "neighbor", "index": 0, "coordinate": 0},
		{"id": "neighbor", "index": 0, "coordinate": 0},
		{"id": "neighbor", "index": 0, "coordinate": 0},
		{"neighbor": next_stage}, 3_010_000, false)
	p.first_snapshot("neighbor", 33, 3_011_000)
	p.effect_pending("neighbor", 33)
	p.finish("neighbor", 33, 3_100_000, "left_window")
	c = p.summary()["counts"]
	_check(int(c.get("ended_blocked_by_effects", 0)) == 1,
		"distinguish selected effect-blocked cancellation")
	_check(int(p.summary()["active_stages"]) == 0, "all cancelled stages released")

	print("DM24_STAGE_CONTRACT_RESULT=" + JSON.stringify({
		"checks": assertions, "failures": failures
	}))
	print("DM24_STAGE_CONTRACT_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("DM24_STAGE_CONTRACT_FAIL: " + reason)
