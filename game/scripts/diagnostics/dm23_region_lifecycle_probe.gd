class_name DM23RegionLifecycleProbe
extends RefCounted

## Bounded region-centric observer, enabled IN BOTH baseline and treatment.
## Tracks a LOAD stage from neighbor creation through first chunk dispatch,
## source readiness, focus entry, cancellation and canonical publication.
const MAX_STAGES := 320
const MAX_RECENT_PUBLISHED := 320
const MAX_LATENCY_SAMPLES := 2048

var _stages: Dictionary = {}
var _order: Array[String] = []
var _published: Dictionary = {}
var _published_order: Array[String] = []
var _counts: Dictionary = {}
var _latency: Dictionary = {}
var _critical_phase: Dictionary = {}
var _last_critical_scopes: Dictionary = {}


static func identity(id: String, token: int) -> String:
	return id + ":" + str(token)


func begin(id: String, token: int, now_usec: int,
		initially_focal: bool, cache_restored: bool) -> void:
	var key := identity(id, token)
	_stages[key] = {
		"region": id,
		"token": token,
		"created_usec": now_usec,
		"focus_usec": now_usec if initially_focal else 0,
		"first_attempt_usec": 0, "first_submit_usec": 0,
		"last_source_published_usec": 0, "last_source_id": "",
		"last_source_phases": {}, "all_ready_usec": 0,
		"pending_count": 0, "attempt_count": 0,
		"missing": {}, "observed_missing": {},
		"cached": cache_restored,
		"initially_focal": initially_focal
	}
	_order.append(key)
	while _order.size() > MAX_STAGES:
		_stages.erase(_order.pop_front())
		_inc("stage_probe_evictions")
	_inc("load_stages_started")
	if initially_focal:
		_inc("started_as_focus")
	else:
		_inc("started_as_neighbor")
	if cache_restored:
		_inc("dm18_cache_stages")


func focus_enter(id: String, token: int, now_usec: int) -> void:
	var key := identity(id, token)
	if _stages.has(key):
		var rec: Dictionary = _stages[key]
		if int(rec["focus_usec"]) == 0:
			rec["focus_usec"] = now_usec
			_inc("neighbor_became_focus")
			_measure("stage_age_at_focus_ms", now_usec - int(rec["created_usec"]))
			if int(rec["first_submit_usec"]) > 0:
				_inc("neighbor_first_chunk_already_submitted_before_focus")
			else:
				_inc("neighbor_first_chunk_still_pending_at_focus")
		return
	if _published.has(id):
		var pub: Dictionary = _published[id]
		_inc("published_before_focus")
		_measure("published_lead_before_focus_ms", now_usec - int(pub["published_usec"]))
		_published.erase(id)
		_published_order.erase(id)
		return
	_inc("focus_enter_without_active_load_stage")


func first_prepare(id: String, token: int, now_usec: int,
		missing_regions: Array, is_pending: bool) -> void:
	var key := identity(id, token)
	if not _stages.has(key):
		_inc("prepare_untracked_stage")
		return
	var rec: Dictionary = _stages[key]
	if int(rec["first_attempt_usec"]) == 0:
		rec["first_attempt_usec"] = now_usec
		_inc("first_chunk_prepare_stages")
	rec["attempt_count"] = int(rec["attempt_count"]) + 1
	if is_pending:
		rec["pending_count"] = int(rec["pending_count"]) + 1
		_inc("first_chunk_pending_attempts")
	var unresolved: Dictionary = rec["missing"]
	var observed: Dictionary = rec["observed_missing"]
	for region_value in missing_regions:
		if not region_value is Vector2i:
			continue
		var region: Vector2i = region_value
		var scope_id := "region:%d,%d" % [region.x, region.y]
		if not observed.has(scope_id):
			observed[scope_id] = true
			unresolved[scope_id] = true
	_inc("first_chunk_prepare_calls")


func source_published(scope_id: String, now_usec: int,
		phase_usec: Dictionary) -> void:
	for key_value in _stages.keys():
		var rec: Dictionary = _stages[key_value]
		var unresolved: Dictionary = rec["missing"]
		if not unresolved.has(scope_id):
			continue
		unresolved.erase(scope_id)
		rec["last_source_id"] = scope_id
		rec["last_source_published_usec"] = now_usec
		rec["last_source_phases"] = phase_usec.duplicate()
		_inc("stage_dependency_scope_resolved")
		if unresolved.is_empty():
			rec["all_ready_usec"] = now_usec
			_inc("stage_dependency_rendezvous")


func first_submitted(id: String, token: int, now_usec: int) -> void:
	var key := identity(id, token)
	if not _stages.has(key):
		_inc("first_submit_untracked_stage")
		return
	var rec: Dictionary = _stages[key]
	if int(rec["first_submit_usec"]) > 0:
		_inc("duplicate_first_submit")
		return
	rec["first_submit_usec"] = now_usec
	_inc("first_chunks_dispatched")
	if int(rec["first_attempt_usec"]) > 0:
		_measure("created_to_first_chunk_ms", now_usec - int(rec["created_usec"]))
		_measure("first_attempt_to_dispatch_ms",
			now_usec - int(rec["first_attempt_usec"]))
		_measure("first_chunk_prepare_attempts",
			int(rec["attempt_count"]) * 1000)
	if int(rec["focus_usec"]) > 0:
		_inc("first_chunk_dispatched_while_focal")
		_measure("focus_entry_to_first_dispatch_ms",
			maxi(0, now_usec - int(rec["focus_usec"])))
	else:
		_inc("first_chunk_dispatched_as_neighbor")
	if int(rec["all_ready_usec"]) > 0:
		_measure("last_source_to_first_dispatch_ms",
			maxi(0, now_usec - int(rec["all_ready_usec"])))
	var critical_scope := String(rec["last_source_id"])
	if not critical_scope.is_empty():
		_last_critical_scopes[critical_scope] = int(
			_last_critical_scopes.get(critical_scope, 0)) + 1
		var phases: Dictionary = rec["last_source_phases"]
		var dominant := "unknown"
		var largest := -1
		for phase_name_value in phases:
			var phase_name := String(phase_name_value)
			var usec := int(phases[phase_name])
			_measure("last_source_" + phase_name + "_ms", usec)
			if usec > largest:
				largest = usec
				dominant = phase_name
		_critical_phase[dominant] = int(
			_critical_phase.get(dominant, 0)) + 1


func published(id: String, token: int, now_usec: int) -> void:
	var key := identity(id, token)
	if not _stages.has(key):
		_inc("published_stage_not_tracked")
		return
	var rec: Dictionary = _stages[key]
	_inc("canonical_loads_published")
	_measure("stage_created_to_publish_ms",
		now_usec - int(rec["created_usec"]))
	if int(rec["focus_usec"]) == 0:
		_inc("neighbor_published_before_focus")
		_published[id] = {
			"published_usec": now_usec, "token": token,
			"created_usec": int(rec["created_usec"]),
			"first_submit_usec": int(rec["first_submit_usec"])
		}
		_published_order.erase(id)
		_published_order.append(id)
		while _published_order.size() > MAX_RECENT_PUBLISHED:
			_published.erase(_published_order.pop_front())
	else:
		_inc("focal_stage_published")
		_measure("focus_entry_to_publish_ms",
			maxi(0, now_usec - int(rec["focus_usec"])))
	_stages.erase(key)
	_order.erase(key)


func cancelled(id: String, token: int, reason: String) -> void:
	var key := identity(id, token)
	if not _stages.has(key):
		return
	var rec: Dictionary = _stages[key]
	_inc("cancelled_" + reason)
	if int(rec["first_submit_usec"]) > 0:
		_inc("cancelled_after_first_chunk")
	else:
		_inc("cancelled_before_first_chunk")
	if int(rec["focus_usec"]) > 0:
		_inc("cancelled_after_focus_entry")
	_measure("cancelled_stage_age_ms",
		Time.get_ticks_usec() - int(rec["created_usec"]))
	_stages.erase(key)
	_order.erase(key)


func reset_counters_preserving_active() -> void:
	_counts.clear()
	_latency.clear()
	_critical_phase.clear()
	_last_critical_scopes.clear()


func summary() -> Dictionary:
	var stats: Dictionary = {}
	for name_value in _latency:
		var name := String(name_value)
		var values: Array = (_latency[name] as Array).duplicate()
		values.sort()
		if values.is_empty():
			continue
		var total := 0
		for value in values:
			total += int(value)
		var count := values.size()
		stats[name] = {
			"n": count,
			"mean_ms": snappedf(float(total) / float(count) / 1000.0, 0.001),
			"p50_ms": snappedf(float(int(values[clampi(ceili(count * 0.50) - 1, 0, count - 1)])) / 1000.0, 0.001),
			"p95_ms": snappedf(float(int(values[clampi(ceili(count * 0.95) - 1, 0, count - 1)])) / 1000.0, 0.001)
		}
	var ranking: Array = []
	for key_value in _last_critical_scopes.keys():
		ranking.append({
			"scope": String(key_value),
			"blocking_stages": int(_last_critical_scopes[key_value])
		})
	ranking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["blocking_stages"]) > int(b["blocking_stages"])
	)
	if ranking.size() > 12:
		ranking.resize(12)
	return {
		"counts": _counts.duplicate(),
		"latency": stats,
		"last_dependency_dominant_phase": _critical_phase.duplicate(),
		"last_dependency_scopes": ranking,
		"active_stages": _stages.size(),
		"recent_published_stages": _published.size()
	}


func _inc(name: String) -> void:
	_counts[name] = int(_counts.get(name, 0)) + 1


func _measure(name: String, usec: int) -> void:
	if not _latency.has(name):
		_latency[name] = []
	var values: Array = _latency[name]
	if values.size() < MAX_LATENCY_SAMPLES:
		values.append(maxi(0, usec))
