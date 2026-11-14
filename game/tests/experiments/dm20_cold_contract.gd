extends SceneTree

const Priority := preload("res://scripts/terrain/dm20_canonical_focus_priority.gd")
const Guard := preload("res://scripts/terrain/dm20_snapshot_guard.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_test")


func _stage(region: Vector2i, purpose: String = "load", i: int = 0) -> Dictionary:
	return {
		"region_key": region,
		"purpose": purpose,
		"submit_index": i,
		"chunk_coordinates": Grid.all_coordinates(),
		"stage_token": 51,
		"edit_revision": 3,
		"terrain_effect_authority_revision": 7,
	}


func _test() -> void:
	var focus := Vector2i(2, 2)
	var world := Vector3(39.5, 0.0, 29.0)
	var stages := {
		"far": _stage(Vector2i(0, 0)),
		"focus": _stage(focus),
		"near": _stage(Vector2i(2, 3))
	}
	var r: Dictionary = Priority.choose(stages, {}, focus, world)
	_check(r.get("id") == "focus", "focus-first overrides older far stage")
	_check(r.get("index") == 0, "original within-region order")
	_check(r.get("coordinate") == (stages["focus"]["chunk_coordinates"] as Array)[0],
		"first chunk unchanged")
	r = Priority.choose(stages, {"focus": true}, focus, world)
	_check(r.get("id") == "near", "nearest region after focus exclusion")
	stages["edit"] = _stage(Vector2i(7, 7), "edit_transaction")
	_check(Priority.choose(stages, {}, focus, world).get("id") == "edit", "edit has priority")
	stages.erase("edit")
	stages["partial"] = _stage(Vector2i(-5, -5), "partial")
	_check(Priority.choose(stages, {}, focus, world).get("id") == "partial", "partial higher priority")
	stages.erase("partial")
	stages["full"] = _stage(Vector2i(-5, -5), "full")
	_check(Priority.choose(stages, {}, focus, world).get("id") == "full", "full higher priority")
	stages.erase("full")
	stages["focus"]["submit_index"] = 16
	_check(Priority.choose(stages, {}, focus, world).get("id") == "near", "completed stages skipped")
	stages["near"]["dm9_speculative"] = true
	_check(Priority.choose(stages, {}, focus, world).get("id") == "far",
		"speculative not promoted above ordinary loads")
	_check(Priority.choose({}, {}, focus, world).is_empty(), "empty queue")

	var target := Vector2i(1, 1)
	var status := {
		"stage_token": 51,
		"edit_revision": 3,
		"terrain_effect_authority_revision": 7
	}
	var snapshot := {
		"terrain_effect_authority_revision": 7,
		"terrain_object_effect_frames": []
	}
	var entry := {
		"snapshot": snapshot,
		"coordinate": target, "token": 51,
		"brush_revision": 3, "brush_scope_id": 555,
		"effect_revision": 7
	}
	_check(Guard.valid(entry, status, target, 555, 3, 7), "valid snapshot")
	_check(not Guard.valid(entry, status, Vector2i.ZERO, 555, 3, 7), "coordinate exact")
	_check(not Guard.valid(entry, status, target, 555, 4, 7), "brush revision")
	_check(not Guard.valid(entry, status, target, 556, 3, 7), "scope identity")
	_check(not Guard.valid(entry, status, target, 555, 3, 8), "world effect revision")
	for key in ["token", "brush_revision", "brush_scope_id", "effect_revision"]:
		var stale := entry.duplicate(true)
		stale[key] = int(stale[key]) + 1
		_check(not Guard.valid(stale, status, target, 555, 3, 7),
			"reject primed stale " + key)
	var changed_stage := status.duplicate(true)
	changed_stage["stage_token"] = 52
	_check(not Guard.valid(entry, changed_stage, target, 555, 3, 7), "stage token")
	changed_stage = status.duplicate(true)
	changed_stage["edit_revision"] = 4
	_check(not Guard.valid(entry, changed_stage, target, 555, 3, 7), "stage brush")
	changed_stage = status.duplicate(true)
	changed_stage["terrain_effect_authority_revision"] = 8
	_check(not Guard.valid(entry, changed_stage, target, 555, 3, 7), "stage effect")
	var altered := entry.duplicate(true)
	altered["snapshot"]["terrain_effect_authority_revision"] = 6
	_check(not Guard.valid(altered, status, target, 555, 3, 7), "snapshot authority")
	altered = entry.duplicate(true)
	altered["snapshot"] = {}
	_check(not Guard.valid(altered, status, target, 555, 3, 7), "empty snapshot")
	_check(not Guard.valid({}, status, target, 555, 3, 7), "empty primed")
	print("DM20_EXACT_CONTRACT=" + JSON.stringify({"checks": checks, "failures": failures}))
	print("DM20_EXACT_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("DM20_CONTRACT_FAIL: " + reason)
