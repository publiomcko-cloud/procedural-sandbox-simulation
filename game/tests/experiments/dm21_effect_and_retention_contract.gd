extends SceneTree

const WaitGate := preload("res://scripts/terrain/dm21_effect_wait_gate.gd")
const Retention := preload("res://scripts/terrain/dm21_stage_retention.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := {
		"stage_token": 12, "edit_revision": 3,
		"terrain_effect_authority_revision": 7
	}
	var coord := Vector2i(1, 2)
	var missing: Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 4)]
	var record := WaitGate.register(original, coord, missing, 5, 1000000, 42)
	_check(WaitGate.still_same_request(record, original, coord, 3, 42, 7), "exact registered request")
	_check(WaitGate.should_wait_without_event(record, 5, 1100000), "event-gated suppression")
	_check(not WaitGate.should_wait_without_event(record, 6, 1100000), "notification wakes")
	_check(WaitGate.should_wait_after_event(record, false, 1100000), "unrelated wake still blocks")
	_check(not WaitGate.should_wait_after_event(record, true, 1100000), "all sources ready wakes")
	_check(not WaitGate.should_wait_without_event(record, 5, 1500001), "watchdog expiry")
	_check(not WaitGate.still_same_request(record, original, Vector2i(0, 0), 3, 42, 7), "chunk invalidated")
	_check(not WaitGate.still_same_request(record, original, coord, 4, 42, 7), "brush revision invalidated")
	_check(not WaitGate.still_same_request(record, original, coord, 3, 43, 7), "brush identity invalidated")
	_check(not WaitGate.still_same_request(record, original, coord, 3, 42, 8), "effect revision invalidated")
	var changed := original.duplicate(true)
	changed["stage_token"] = 13
	_check(not WaitGate.still_same_request(record, changed, coord, 3, 42, 7), "stage token invalidated")
	changed = original.duplicate(true)
	changed["edit_revision"] = 4
	_check(not WaitGate.still_same_request(record, changed, coord, 3, 42, 7), "stage edit invalidated")
	changed = original.duplicate(true)
	changed["terrain_effect_authority_revision"] = 8
	_check(not WaitGate.still_same_request(record, changed, coord, 3, 42, 7), "stage effect invalidated")
	_check(not WaitGate.still_same_request({}, original, coord, 3, 42, 7), "empty wait never accepted")
	missing.clear()
	_check((record["missing_regions"] as Array).size() == 2, "detached dependency list")

	var stage := {
		"purpose": "load", "chunk_coordinates": range(16),
		"submit_index": 10, "next_index": 6, "pending_count": 4,
		"dm9_speculative": false, "dm18_cache_ready": false
	}
	_check(Retention.eligible(stage, true, false, 0), "partly completed stage reused within residence")
	_check(Retention.eligible(stage, true, false, 1), "second retained stage allowed")
	_check(not Retention.eligible(stage, true, false, 2), "strict retained cap")
	_check(not Retention.eligible(stage, false, false, 0), "no expansion outside retained")
	_check(not Retention.eligible(stage, true, true, 0), "no retention needed while desired")
	for purpose in ["edit_transaction", "partial", "full"]:
		var edited := stage.duplicate(true)
		edited["purpose"] = purpose
		_check(not Retention.eligible(edited, true, false, 0), "do not retain " + purpose)
	var spec := stage.duplicate(true)
	spec["dm9_speculative"] = true
	_check(not Retention.eligible(spec, true, false, 0), "do not retain speculation")
	spec = stage.duplicate(true)
	spec["dm18_cache_ready"] = true
	_check(not Retention.eligible(spec, true, false, 0), "do not retain already cached")
	spec = stage.duplicate(true)
	spec["submit_index"] = 7
	_check(not Retention.eligible(spec, true, false, 0), "insufficient submitted work")
	spec = stage.duplicate(true)
	spec["next_index"] = 3
	_check(not Retention.eligible(spec, true, false, 0), "insufficient completed work")
	spec = stage.duplicate(true)
	spec["next_index"] = 16
	_check(not Retention.eligible(spec, true, false, 0), "already complete handled elsewhere")

	print("DM21_CONTRACT_RESULT=" + JSON.stringify({"checks": checks, "failures": failures}))
	print("DM21_CONTRACT_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DM21_CONTRACT_FAILURE: " + reason)
