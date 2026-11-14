class_name DM24CanonicalStageFunnelProbe
extends RefCounted

## Identical instrumentation in control and treatment, inclusive of the
## shadow selector. Per-stage timer and reason ledger, bounded in RAM.
const MAX_ACTIVE := 320
const MAX_SAMPLES := 2048

var _active: Dictionary = {}
var _order: Array[String] = []
var _counts: Dictionary = {}
var _samples: Dictionary = {}

# DM25 observer-only focal stall classification. Never influences dispatch.
var _dm25_focus_key := ""
var _dm25_frame_selected_focal := false
var _dm25_frame_effect_pending := false
var _dm25_frame_selected_other_load := false
var _dm25_frame_selected_protected := false
var _dm25_frame_budget := false
var _dm25_frame_worker := false
var _dm25_missing_source_hits: Dictionary = {}
var _dm26_sources: Dictionary = {}


static func key(id: String, token: int) -> String:
	return id + ":" + str(token)


func begin(id: String, token: int, now_usec: int, focal: bool) -> void:
	var k := key(id, token)
	_active[k] = {
		"created": now_usec, "first_selected": 0, "first_snapshot": 0,
		"first_dispatch": 0, "focus_entered": now_usec if focal else 0,
		"pending_effect": 0, "eligible_frames": 0, "budget_frames": 0,
		"worker_frames": 0, "selected_attempts": 0, "skipped_frames": 0
	}
	_order.append(k)
	while _order.size() > MAX_ACTIVE:
		_active.erase(_order.pop_front())
		_inc("probe_evicted")
	_inc("started")


func focus_enter(id: String, token: int, now_usec: int) -> void:
	var k := key(id, token)
	if not _active.has(k):
		return
	var s: Dictionary = _active[k]
	if int(s["focus_entered"]) == 0:
		s["focus_entered"] = now_usec
		_inc("neighbor_entered_focus")
		if int(s["first_dispatch"]) == 0:
			_inc("focus_enter_without_first_dispatch")


func frame(stages: Dictionary, focus: Vector2i, limit: int,
		used: int, worker_count: int, worker_limit: int) -> void:
	_inc("instrumented_frames")
	_dm25_focus_key = ""
	_dm25_frame_selected_focal = false
	_dm25_frame_effect_pending = false
	_dm25_frame_selected_other_load = false
	_dm25_frame_selected_protected = false
	var has_budget := used < limit
	var has_worker := worker_count < worker_limit
	_dm25_frame_budget = has_budget
	_dm25_frame_worker = has_worker
	for id_value in stages:
		var id := String(id_value)
		var stage: Dictionary = stages[id]
		if String(stage.get("purpose", "")) != "load" \
		or bool(stage.get("dm9_speculative", false)) \
		or bool(stage.get("dm18_cache_ready", false)) \
		or int(stage.get("submit_index", 0)) != 0:
			continue
		var k := key(id, int(stage.get("stage_token", -1)))
		if not _active.has(k):
			continue
		var s: Dictionary = _active[k]
		var focal: bool = stage.get("region_key") == focus
		if focal:
			_dm25_focus_key = k
		_inc("unsubmitted_stage_frames")
		if focal:
			_inc("unsubmitted_focal_frames")
		if not has_budget:
			s["budget_frames"] += 1
			_inc("stage_wait_dispatch_budget")
			if focal:
				_inc("focal_wait_dispatch_budget")
		elif not has_worker:
			s["worker_frames"] += 1
			_inc("stage_wait_worker_capacity")
			if focal:
				_inc("focal_wait_worker_capacity")
		else:
			s["eligible_frames"] += 1
			_inc("stage_eligible_not_yet_submitted")
			if focal:
				_inc("focal_eligible_not_yet_submitted")


func selected(original: Dictionary, shadow: Dictionary,
		used: Dictionary, stages: Dictionary, now_usec: int,
		treatment: bool) -> void:
	_inc("selector_calls")
	var oid := String(original.get("id", ""))
	var sid := String(shadow.get("id", ""))
	var uid := String(used.get("id", ""))
	if not oid.is_empty() and sid != oid:
		_inc("shadow_priority_overrides")
	if treatment and sid != oid and uid == sid:
		_inc("applied_priority_overrides")
	if uid.is_empty():
		_inc("selector_empty")
		return
	var stage: Dictionary = stages.get(uid, {})
	if not _dm25_focus_key.is_empty():
		if key(uid, int(stage.get("stage_token", -1))) == _dm25_focus_key:
			_dm25_frame_selected_focal = true
		elif String(stage.get("purpose", "")) != "load":
			_dm25_frame_selected_protected = true
		else:
			_dm25_frame_selected_other_load = true
	if String(stage.get("purpose", "")) != "load" \
	or int(stage.get("submit_index", -1)) != 0:
		return
	var k := key(uid, int(stage.get("stage_token", -1)))
	if not _active.has(k):
		return
	var s: Dictionary = _active[k]
	s["selected_attempts"] += 1
	_inc("first_chunk_selection_calls")
	if int(s["first_selected"]) == 0:
		s["first_selected"] = now_usec
		_inc("first_chunk_selected_once")
		_measure("creation_to_first_selection_ms", now_usec - int(s["created"]))
		if int(s["focus_entered"]) > 0:
			_measure("focus_to_first_selection_ms",
				maxi(0, now_usec - int(s["focus_entered"])))


func first_snapshot(id: String, token: int, now_usec: int) -> void:
	var k := key(id, token)
	if not _active.has(k):
		return
	var s: Dictionary = _active[k]
	if int(s["first_snapshot"]) == 0:
		s["first_snapshot"] = now_usec
		_inc("first_snapshot_attempted")
		_measure("creation_to_first_snapshot_ms", now_usec - int(s["created"]))
		if int(s["first_selected"]) > 0:
			_measure("first_selection_to_snapshot_ms",
				maxi(0, now_usec - int(s["first_selected"])))


func effect_pending(id: String, token: int,
		missing_source_regions: Array = []) -> void:
	var k := key(id, token)
	if not _active.has(k):
		return
	_active[k]["pending_effect"] += 1
	_inc("first_chunk_effect_pending")
	if k == _dm25_focus_key:
		_dm25_frame_effect_pending = true
		for source_value in missing_source_regions:
			if not source_value is Vector2i:
				continue
			var source: Vector2i = source_value
			var scope := "region:%d,%d" % [source.x, source.y]
			if not _dm25_missing_source_hits.has(scope) \
			and _dm25_missing_source_hits.size() >= 128:
				_inc("dm25_missing_scope_overflow")
				continue
			_dm25_missing_source_hits[scope] = int(_dm25_missing_source_hits.get(scope, 0)) + 1


## Called only for the pending first-chunk snapshot of a tracked focal stage.
## Full observer cost is identical in both A/A arms. No scheduling effects.
func dm26_observe_sources(id: String, token: int, states: Array) -> void:
	var focal_key := key(id, token)
	if not _active.has(focal_key) or focal_key != _dm25_focus_key:
		return
	for value in states:
		if not value is Dictionary:
			continue
		var record: Dictionary = value
		var scope_id := String(record.get("id", ""))
		if scope_id.is_empty():
			continue
		var state := String(record.get("state", "unknown"))
		_inc("dm26_state_" + state)
		var source: Dictionary = _dm26_sources.get(scope_id, {
			"states": {}, "transitions": 0, "last_state": "",
			"last_queue_index": -1, "last_protected": false,
			"last_tracked": false, "last_queue_length": 0,
			"prefetch_errors": 0
		})
		var counts: Dictionary = source["states"]
		counts[state] = int(counts.get(state, 0)) + 1
		if not String(source["last_state"]).is_empty() \
		and String(source["last_state"]) != state:
			source["transitions"] = int(source["transitions"]) + 1
		source["last_state"] = state
		source["last_queue_index"] = int(record.get("queued_index", -1))
		source["last_protected"] = bool(record.get("protected", false))
		source["last_tracked"] = bool(record.get("tracked", false))
		source["last_queue_length"] = int(record.get("queue_length", 0))
		if bool(record.get("prefetch_error", false)):
			source["prefetch_errors"] = int(source["prefetch_errors"]) + 1
		if not _dm26_sources.has(scope_id) and _dm26_sources.size() >= 128:
			_inc("dm26_overflow")
			continue
		_dm26_sources[scope_id] = source


func first_dispatched(id: String, token: int, now_usec: int) -> void:
	var k := key(id, token)
	if not _active.has(k):
		return
	var s: Dictionary = _active[k]
	if int(s["first_dispatch"]) != 0:
		return
	s["first_dispatch"] = now_usec
	_inc("first_chunks_dispatched")
	_measure("creation_to_first_dispatch_ms", now_usec - int(s["created"]))
	if int(s["first_selected"]) > 0:
		_measure("first_selection_to_dispatch_ms", now_usec - int(s["first_selected"]))
	if int(s["first_snapshot"]) > 0:
		_measure("first_snapshot_to_dispatch_ms", now_usec - int(s["first_snapshot"]))
	if int(s["focus_entered"]) > 0:
		_measure("focus_to_first_dispatch_ms",
			maxi(0, now_usec - int(s["focus_entered"])))
	_measure("eligible_frames_before_dispatch",
		int(s["eligible_frames"]) * 1000)
	_measure("budget_frames_before_dispatch",
		int(s["budget_frames"]) * 1000)
	_measure("worker_frames_before_dispatch",
		int(s["worker_frames"]) * 1000)
	_measure("pending_effect_checks_before_dispatch",
		int(s["pending_effect"]) * 1000)


func finish(id: String, token: int, now_usec: int, reason: String) -> void:
	var k := key(id, token)
	if not _active.has(k):
		return
	var s: Dictionary = _active[k]
	var published := reason == "published"
	_inc("published" if published else "cancelled_" + reason)
	if int(s["first_dispatch"]) == 0:
		_inc("ended_before_first_dispatch")
		if int(s["first_selected"]) == 0:
			_inc("ended_never_selected")
		elif int(s["first_snapshot"]) == 0:
			_inc("ended_selected_without_snapshot")
		elif int(s["pending_effect"]) > 0:
			_inc("ended_blocked_by_effects")
		else:
			_inc("ended_snapshot_without_dispatch")
	if int(s["focus_entered"]) > 0:
		_inc("ended_after_focus")
		if int(s["first_dispatch"]) == 0:
			_inc("ended_after_focus_without_first_dispatch")
	_measure("stage_end_age_ms", maxi(0, now_usec - int(s["created"])))
	if not published:
		_measure("cancelled_eligible_frames", int(s["eligible_frames"]) * 1000)
		_measure("cancelled_budget_frames", int(s["budget_frames"]) * 1000)
		_measure("cancelled_worker_frames", int(s["worker_frames"]) * 1000)
	_active.erase(k)
	_order.erase(k)


func focal_frame_outcome(id: String, is_active: bool,
		stage: Dictionary) -> void:
	# Same post-dispatch sampling boundary as DM19; covers ONLY actual
	# missing focal LOADs with submit_index==0. Counters are disjoint.
	if is_active or stage.is_empty() \
	or bool(stage.get("dm18_cache_ready", false)) \
	or int(stage.get("submit_index", -1)) != 0 \
	or String(stage.get("purpose", "")) != "load":
		return
	_inc("dm25_focal_missing_awaiting_first")
	if _dm25_focus_key != key(id, int(stage.get("stage_token", -1))):
		_inc("dm25_reason_untracked_or_changed_stage")
	elif _dm25_frame_selected_focal:
		_inc("dm25_reason_selected_effect_pending" if _dm25_frame_effect_pending \
			else "dm25_reason_selected_without_pending_or_dispatch")
	elif not _dm25_frame_budget:
		_inc("dm25_reason_no_budget_at_dispatch_entry")
	elif not _dm25_frame_worker:
		_inc("dm25_reason_no_worker_at_dispatch_entry")
	elif _dm25_frame_selected_protected:
		_inc("dm25_reason_protected_stage_selected")
	elif _dm25_frame_selected_other_load:
		_inc("dm25_reason_other_load_selected")
	else:
		_inc("dm25_reason_no_selection_with_global_capacity")


func reset_measurements_preserving_active() -> void:
	_counts.clear()
	_samples.clear()
	_dm25_missing_source_hits.clear()
	_dm26_sources.clear()


func summary() -> Dictionary:
	var stats := {}
	for key_value in _samples:
		var name := String(key_value)
		var values: Array = (_samples[name] as Array).duplicate()
		values.sort()
		var n := values.size()
		if n == 0:
			continue
		var sum: int = 0
		for value in values:
			sum += int(value)
		var percentile_index := clampi(ceili(float(n) * 0.95) - 1, 0, n - 1)
		stats[name] = {
			"n": n,
			"mean_ms": snappedf(float(sum) / float(n) / 1000.0, 0.001),
			"p95_ms": snappedf(float(int(values[percentile_index])) / 1000.0, 0.001)
		}
	return {"counts": _counts.duplicate(), "latency": stats,
		"active_stages": _active.size(),
		"dm25_missing_source_hits": _dm25_missing_source_hits.duplicate(),
		"dm26_source_states": _dm26_sources.duplicate(true)}


func _inc(name: String) -> void:
	_counts[name] = int(_counts.get(name, 0)) + 1


func _measure(name: String, duration_usec: int) -> void:
	if not _samples.has(name):
		_samples[name] = []
	var values: Array = _samples[name]
	if values.size() < MAX_SAMPLES:
		values.append(maxi(0, duration_usec))
