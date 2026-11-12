extends SceneTree

const Cache := preload("res://scripts/terrain/terrain_stream_ready_cache_policy.gd")
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
	var focus := Vector2i(8, 8)
	var stage := {
		"purpose": "load", "region_key": focus, "stage_token": 4,
		"submit_index": 0, "chunk_coordinates": [Vector2i.ZERO, Vector2i(1, 0)],
		"edit_revision": 5, "terrain_effect_authority_revision": 10,
	}
	var ticket: Dictionary = Cache.pending_ticket(stage, 12, 100)
	_check(Cache.still_pending(ticket, stage, 12, 100), "snapshot-pending stage is cached")
	_check(Cache.still_pending(ticket, stage, 12, 129), "bounded cache prevents repeated snapshots")
	_check(not Cache.still_pending(ticket, stage, 12, 130), "TTL forces a liveness retry")
	_check(not Cache.still_pending(ticket, stage, 13, 101), "projection publication invalidates epoch")
	for key in ["stage_token", "submit_index", "edit_revision", "terrain_effect_authority_revision"]:
		var changed := stage.duplicate()
		changed[key] = int(changed[key]) + 1
		_check(not Cache.still_pending(ticket, changed, 12, 101), "stage revision/index invalidates " + key)
	var neighbors := {
		"blocked": stage,
		"ready": {
			"purpose": "load", "region_key": focus + Vector2i.RIGHT,
			"stage_token": 7, "submit_index": 0,
			"chunk_coordinates": [Vector2i.ZERO], "edit_revision": 5,
			"terrain_effect_authority_revision": 10,
		},
		"edit": {
			"purpose": "edit_transaction", "region_key": focus + Vector2i(2, 0),
			"stage_token": 9, "submit_index": 0,
			"chunk_coordinates": [Vector2i.ZERO], "edit_revision": 5,
			"terrain_effect_authority_revision": 10,
		},
	}
	var tickets := {"blocked": ticket, "edit": Cache.pending_ticket(neighbors["edit"], 12, 100)}
	var excluded := Cache.excluded(neighbors, tickets, 12, 101)
	_check(excluded.has("blocked"), "known blocked load is excluded")
	_check(not excluded.has("edit"), "edit transactions cannot be blocked by negative cache")
	_check(Selector.next(neighbors, excluded, focus).get("id") == "edit", "edit wins all scheduling")
	neighbors.erase("edit")
	_check(Selector.next(neighbors, excluded, focus).get("id") == "ready", "ready neighboring load outranks pending load")
	_check(Selector.next(neighbors, {}, focus).get("id") == "blocked", "baseline unchanged")
	var replacement: Dictionary = neighbors["blocked"].duplicate()
	replacement["stage_token"] = 5
	neighbors["blocked"] = replacement
	_check(Cache.excluded(neighbors, tickets, 12, 101).is_empty(), "stage replacement invalidates cached block")
	_check(Cache.excluded(neighbors, tickets, 13, 101).is_empty(), "epoch invalidates all cached blocks")
	_check(Cache.excluded({}, tickets, 12, 101).is_empty(), "unloaded stages never retained as candidates")
	_check(Cache.MAX_TRACKED_STAGES <= 64, "negative cache is bounded")
	if failures == 0:
		print("P5_STREAM_READY_CACHE_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P5_STREAM_READY_CACHE_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)
