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
	var has_budget := used < limit
	var has_worker := worker_count < worker_limit
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


func effect_pending(id: String, token: int) -> void:
	var k := key(id, token)
	if not _active.has(k):
		return
	_active[k]["pending_effect"] += 1
	_inc("first_chunk_effect_pending")


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


func reset_measurements_preserving_active() -> void:
	_counts.clear()
	_samples.clear()


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
		"active_stages": _active.size()}


func _inc(name: String) -> void:
	_counts[name] = int(_counts.get(name, 0)) + 1


func _measure(name: String, duration_usec: int) -> void:
	if not _samples.has(name):
		_samples[name] = []
	var values: Array = _samples[name]
	if values.size() < MAX_SAMPLES:
		values.append(maxi(0, duration_usec))
