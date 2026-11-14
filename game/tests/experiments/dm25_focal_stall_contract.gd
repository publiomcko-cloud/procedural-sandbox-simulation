extends SceneTree

const Probe := preload("res://scripts/diagnostics/dm24_canonical_stage_funnel_probe.gd")

var checks := 0
var errors := 0


func _initialize() -> void:
	call_deferred("_run")


func _stage(region: Vector2i, purpose: String = "load", token: int = 41) -> Dictionary:
	return {
		"region_key": region, "purpose": purpose,
		"submit_index": 0, "stage_token": token,
		"chunk_coordinates": range(16),
		"dm9_speculative": false, "dm18_cache_ready": false
	}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors += 1
		push_error("DM25_CAUSE_CONTRACT_FAIL: " + message)


func _run() -> void:
	var probe := Probe.new()
	var focus := Vector2i(1, 1)
	var f := _stage(focus)
	var stages := {"focus": f, "other": _stage(Vector2i(1, 2))}
	var focus_request := {"id": "focus", "index": 0, "coordinate": 0}
	var other_request := {"id": "other", "index": 0, "coordinate": 0}
	probe.begin("focus", 41, 1_000_000, true)

	# Frame 1: globally free slot, no candidate selection.
	probe.frame(stages, focus, 1, 0, 0, 8)
	probe.focal_frame_outcome("focus", false, f)
	# Frame 2: all dispatch budget consumed.
	probe.frame(stages, focus, 1, 1, 0, 8)
	probe.focal_frame_outcome("focus", false, f)
	# Frame 3: worker capacity exhausted.
	probe.frame(stages, focus, 1, 0, 8, 8)
	probe.focal_frame_outcome("focus", false, f)
	# Frame 4: another load gets the selection.
	probe.frame(stages, focus, 1, 0, 0, 8)
	probe.selected(other_request, other_request, other_request, stages, 1_010_000, false)
	probe.focal_frame_outcome("focus", false, f)
	# Frame 5: protected stage gets selection.
	stages["edit"] = _stage(Vector2i(2, 2), "edit_transaction")
	var edit_request := {"id": "edit", "index": 0, "coordinate": 0}
	probe.frame(stages, focus, 1, 0, 0, 8)
	probe.selected(edit_request, edit_request, edit_request, stages, 1_011_000, false)
	probe.focal_frame_outcome("focus", false, f)
	stages.erase("edit")
	# Frame 6: selected focus but required source is pending.
	probe.frame(stages, focus, 1, 0, 0, 8)
	probe.selected(focus_request, focus_request, focus_request, stages, 1_012_000, false)
	probe.first_snapshot("focus", 41, 1_012_100)
	probe.effect_pending("focus", 41, [Vector2i(4, 5)])
	probe.focal_frame_outcome("focus", false, f)
	# Frame 7: focal selected but not dispatched for another reason.
	probe.frame(stages, focus, 1, 0, 0, 8)
	probe.selected(focus_request, focus_request, focus_request, stages, 1_013_000, false)
	probe.focal_frame_outcome("focus", false, f)
	# Frame 8: no matching stage token; never misattribute another generation.
	probe.frame(stages, focus, 1, 0, 0, 8)
	probe.focal_frame_outcome("focus", false, _stage(focus, "load", 42))
	# An active canonical region never contributes to missing-frame buckets.
	probe.focal_frame_outcome("focus", true, f)

	var result: Dictionary = probe.summary()
	var counts: Dictionary = result["counts"]
	_check(int(counts.get("dm25_focal_missing_awaiting_first", 0)) == 8, "eight missing frames")
	for reason in [
		"dm25_reason_no_selection_with_global_capacity",
		"dm25_reason_no_budget_at_dispatch_entry",
		"dm25_reason_no_worker_at_dispatch_entry",
		"dm25_reason_other_load_selected",
		"dm25_reason_protected_stage_selected",
		"dm25_reason_selected_effect_pending",
		"dm25_reason_selected_without_pending_or_dispatch",
		"dm25_reason_untracked_or_changed_stage"
	]:
		_check(int(counts.get(reason, 0)) == 1, reason)
	var total := 0
	for name in counts.keys():
		if String(name).begins_with("dm25_reason_"):
			total += int(counts[name])
	_check(total == 8, "exclusive bucket sum equals observed frames")
	_check(int(result.get("dm25_missing_source_hits", {}).get("region:4,5", 0)) == 1,
		"focal pending source identity captured")
	_check(int(counts.get("instrumented_frames", 0)) == 8,
		"all frames carry the same observer cost")
	probe.reset_measurements_preserving_active()
	_check(probe.summary().get("dm25_missing_source_hits", {}).is_empty(),
		"warm-up reset clears source samples")
	print("DM25_CAUSE_CONTRACT_RESULT=" + JSON.stringify({"checks": checks, "errors": errors}))
	print("DM25_CAUSE_CONTRACT_%s" % ("PASS" if errors == 0 else "FAIL"))
	quit(0 if errors == 0 else 1)
