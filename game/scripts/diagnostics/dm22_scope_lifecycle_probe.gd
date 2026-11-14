class_name DM22ScopeLifecycleProbe
extends RefCounted

## BENCHMARK ONLY. Identical source and focus-stage instrumentation in every
## measured arm. No queue/worker/publication decisions are changed here.
## Bounded state; no per-frame stdout, disk writes or heavyweight trace.
const MAX_SCOPES := 640
const MAX_FOCUS_REQUESTS := 192
const MAX_SAMPLES := 2048

var _scopes: Dictionary = {}
var _scope_order: Array[String] = []
var _focus: Dictionary = {}
var _focus_order: Array[String] = []
var _samples: Dictionary = {}
var _counts: Dictionary = {}
var _critical_scopes: Dictionary = {}
var _recent_published: Dictionary = {}
var _published_order: Array[String] = []
var _critical_phase_counts: Dictionary = {}


func queued(id: String, now: int, queue_depth: int, urgent: bool) -> void:
	if not _scopes.has(id):
		_scopes[id] = {
			"queued": now, "generation_submitted": 0,
			"generation_finished": 0, "generation_worker_usec": 0,
			"generation_queue_usec": 0, "source_finalize_usec": 0,
			"projection_submitted": 0, "projection_finished": 0,
			"projection_worker_usec": 0, "projection_queue_usec": 0,
			"projection_publish_usec": 0, "source_cache": false,
			"projection_cache": false, "queue_depth": queue_depth,
			"urgent": urgent
		}
		_scope_order.append(id)
		while _scope_order.size() > MAX_SCOPES:
			_scopes.erase(_scope_order.pop_front())
			_increment("scope_evicted_from_probe")
	else:
		_increment("scope_duplicate_queue_attempt")
	if urgent:
		_increment("scope_urgent_queues")
	_increment("scope_queue_events")


func reprioritized(id: String) -> void:
	if _scopes.has(id):
		_scopes[id]["urgent"] = true
	_increment("scope_reprioritizations")


func generation_dispatched(id: String, now: int) -> void:
	if _scopes.has(id):
		_scopes[id]["generation_submitted"] = now
	_increment("generation_dispatches")


func generation_completed(id: String, start: int, finish: int,
		worker_queue_usec: int, worker_usec: int, finalize_usec: int) -> void:
	if _scopes.has(id):
		var d: Dictionary = _scopes[id]
		d["generation_finished"] = finish
		d["generation_queue_usec"] = worker_queue_usec
		d["generation_worker_usec"] = worker_usec
		d["source_finalize_usec"] = finalize_usec
		_measure("generation_queue_ms", worker_queue_usec)
		_measure("generation_worker_ms", worker_usec)
		_measure("source_finalize_ms", finalize_usec)
		var queued_at := int(d.get("queued", start))
		_measure("scope_queue_to_generation_done_ms", maxi(0, finish - queued_at))
	_increment("generation_completed")


func source_cache_hit(id: String, now: int) -> void:
	if _scopes.has(id):
		_scopes[id]["source_cache"] = true
		_scopes[id]["generation_finished"] = now
	_increment("source_cache_hits")


func projection_dispatched(id: String, now: int, cache_hit: bool) -> void:
	if _scopes.has(id):
		_scopes[id]["projection_submitted"] = now
		_scopes[id]["projection_cache"] = cache_hit
	_increment("projection_cache_hits" if cache_hit else "projection_dispatches")


func projection_completed(id: String, now: int, queue_usec: int, run_usec: int) -> void:
	if _scopes.has(id):
		_scopes[id]["projection_finished"] = now
		_scopes[id]["projection_queue_usec"] = queue_usec
		_scopes[id]["projection_worker_usec"] = run_usec
	_measure("projection_worker_queue_ms", queue_usec)
	_measure("projection_worker_run_ms", run_usec)
	_increment("projection_completed")


func published(id: String, now: int, publish_usec: int) -> void:
	var d: Dictionary = _scopes.get(id, {})
	if not d.is_empty():
		var enqueued := int(d.get("queued", now))
		var gen_start := int(d.get("generation_submitted", 0))
		var gen_finish := int(d.get("generation_finished", 0))
		var proj_start := int(d.get("projection_submitted", 0))
		var proj_finish := int(d.get("projection_finished", 0))
		_measure("scope_total_ms", maxi(0, now - enqueued))
		_measure("scope_queue_ms", maxi(0, (gen_start if gen_start > 0 else proj_start) - enqueued))
		if proj_start > 0:
			_measure("source_to_projection_ms", maxi(0, proj_start - (gen_finish if gen_finish > 0 else enqueued)))
			_measure("projection_to_publish_ms", maxi(0, now - proj_start))
		if proj_finish > 0:
			_measure("projection_finish_to_publish_ms", maxi(0, now - proj_finish))
		_measure("scope_publish_cpu_ms", publish_usec)
		var phases := {
			"queue": maxi(0, (gen_start if gen_start > 0 else proj_start) - enqueued),
			"generation": int(d.get("generation_worker_usec", 0)),
			"source_finalize": int(d.get("source_finalize_usec", 0)),
			"projection": int(d.get("projection_worker_usec", 0)),
			"projection_publish": publish_usec
		}
		_recent_published[id] = {
			"total_usec": maxi(0, now - enqueued),
			"phases": phases
		}
		_published_order.erase(id)
		_published_order.append(id)
		while _published_order.size() > MAX_SCOPES:
			_recent_published.erase(_published_order.pop_front())
		_scopes.erase(id)
		_scope_order.erase(id)
	else:
		_increment("publication_without_scope_trace")
	for key_value in _focus.keys():
		var key := String(key_value)
		var req: Dictionary = _focus[key]
		var unresolved: Dictionary = req["unresolved"]
		if unresolved.has(id):
			unresolved.erase(id)
			req["last_scope"] = id
			req["last_scope_published_usec"] = now
			req["resolved"] = int(req["resolved"]) + 1
			if unresolved.is_empty():
				req["all_ready_usec"] = now
				_increment("focus_all_sources_ready_events")
	_increment("scope_publications")


func cancelled(id: String, reason: String) -> void:
	if _scopes.has(id):
		var d: Dictionary = _scopes[id]
		if int(d.get("generation_submitted", 0)) > 0:
			_increment("cancelled_after_generation_dispatch")
		elif int(d.get("projection_submitted", 0)) > 0:
			_increment("cancelled_after_projection_dispatch")
		else:
			_increment("cancelled_queued")
		_scopes.erase(id)
		_scope_order.erase(id)
	_increment("cancel_" + reason)


func focus_prepare(key: String, stage_token: int, now: int,
		missing: Array, was_pending: bool) -> void:
	var identity := key + ":" + str(stage_token)
	if not _focus.has(identity):
		_focus[identity] = {
			"first_attempt_usec": now, "attempts": 0,
			"initial_missing_count": missing.size(), "unresolved": {},
			"last_scope": "", "last_scope_published_usec": 0,
			"resolved": 0, "all_ready_usec": 0
		}
		_focus_order.append(identity)
		while _focus_order.size() > MAX_FOCUS_REQUESTS:
			_focus.erase(_focus_order.pop_front())
			_increment("focus_probe_evictions")
	var d: Dictionary = _focus[identity]
	d["attempts"] = int(d["attempts"]) + 1
	if was_pending:
		_increment("focus_first_chunk_pending_attempts")
	for region_value in missing:
		if region_value is Vector2i:
			var region: Vector2i = region_value
			var scope_id := "region:%d,%d" % [region.x, region.y]
			var unresolved: Dictionary = d["unresolved"]
			if not unresolved.has(scope_id):
				unresolved[scope_id] = true
	if not was_pending:
		_increment("focus_first_chunk_ready_calls")


func focus_first_submitted(key: String, stage_token: int, now: int) -> void:
	var identity := key + ":" + str(stage_token)
	if not _focus.has(identity):
		_increment("focus_first_submitted_without_pending")
		return
	var d: Dictionary = _focus[identity]
	var begin := int(d["first_attempt_usec"])
	_measure("focus_first_chunk_wait_ms", maxi(0, now - begin))
	_measure("focus_first_chunk_attempt_count", int(d["attempts"]) * 1000)
	_measure("focus_first_chunk_initial_missing", int(d["initial_missing_count"]) * 1000)
	var ready_usec := int(d.get("all_ready_usec", 0))
	if ready_usec > 0:
		_measure("focus_dependency_last_publish_wait_ms", maxi(0, ready_usec - begin))
		_measure("focus_ready_to_first_submit_ms", maxi(0, now - ready_usec))
	var critical_id := String(d.get("last_scope", ""))
	if not critical_id.is_empty():
		_critical_scopes[critical_id] = int(_critical_scopes.get(critical_id, 0)) + 1
		var record: Dictionary = _recent_published.get(critical_id, {})
		if not record.is_empty():
			_measure("critical_scope_total_ms", int(record["total_usec"]))
			var phases: Dictionary = record["phases"]
			var dominant := "unknown"
			var max_phase_usec := -1
			for phase_value in phases:
				var phase := String(phase_value)
				var duration := int(phases[phase])
				_measure("critical_" + phase + "_ms", duration)
				if duration > max_phase_usec:
					max_phase_usec = duration
					dominant = phase
			_critical_phase_counts[dominant] = int(
				_critical_phase_counts.get(dominant, 0)
			) + 1
	_increment("focus_first_chunk_submitted")
	_focus.erase(identity)
	_focus_order.erase(identity)


func focus_cancel(key: String, stage_token: int) -> void:
	var identity := key + ":" + str(stage_token)
	if _focus.has(identity):
		_increment("focus_first_chunk_cancelled_waiting")
		_focus.erase(identity)
		_focus_order.erase(identity)


## Clear measurement counters at the end of stationary prewarm, but keep
## in-flight scopes and their enqueue timestamps (real critical-path age).
func reset_measurements() -> void:
	_samples.clear()
	_counts.clear()
	_critical_scopes.clear()
	_critical_phase_counts.clear()
	_focus.clear()
	_focus_order.clear()


func summary() -> Dictionary:
	var stats: Dictionary = {}
	for name_value in _samples:
		var name := String(name_value)
		var a: Array = (_samples[name] as Array).duplicate()
		a.sort()
		if a.is_empty():
			continue
		var total := 0
		for x in a:
			total += int(x)
		stats[name] = {
			"n": a.size(),
			"mean_ms": snappedf(float(total) / float(a.size()) / 1000.0, 0.001),
			"p50_ms": _pct_ms(a, 0.50),
			"p95_ms": _pct_ms(a, 0.95),
			"p99_ms": _pct_ms(a, 0.99),
			"max_ms": float(int(a[-1])) / 1000.0
		}
	var critical: Array = []
	for scope_value in _critical_scopes:
		critical.append({"scope": String(scope_value), "hits": int(_critical_scopes[scope_value])})
	critical.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["hits"]) > int(b["hits"])
	)
	if critical.size() > 12:
		critical.resize(12)
	return {
		"counts": _counts.duplicate(),
		"latency": stats,
		"critical_scope_top": critical,
		"critical_dominant_phases": _critical_phase_counts.duplicate(),
		"scopes_in_trace": _scopes.size(),
		"focus_requests_unfinished": _focus.size()
	}


func _increment(name: String) -> void:
	_counts[name] = int(_counts.get(name, 0)) + 1


func _measure(name: String, elapsed_usec: int) -> void:
	if not _samples.has(name):
		_samples[name] = []
	var a: Array = _samples[name]
	if a.size() < MAX_SAMPLES:
		a.append(maxi(0, elapsed_usec))


func _pct_ms(sorted_samples: Array, q: float) -> float:
	var index := clampi(ceili(float(sorted_samples.size()) * q) - 1, 0, sorted_samples.size()-1)
	return snappedf(float(int(sorted_samples[index])) / 1000.0, 0.001)
