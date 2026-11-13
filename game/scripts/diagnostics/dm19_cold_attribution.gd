class_name DM19ColdAttribution
extends RefCounted

## Benchmark-only, low-overhead cold canonical stage ledger.
## No console/file output in the frame loop. Does not modify scheduler, world,
## terrain, mesh, effect authority or the DM18 revisit cache.
const MAX_LATENCY_SAMPLES := 2048

var _stages: Dictionary = {}
var _published_region_ids: Dictionary = {}
var _metrics: Dictionary = {}
var _latencies: Dictionary = {}
var _effect: Dictionary = {
	"calls": 0, "success": 0, "pending": 0, "failed": 0,
	"all_usec": 0, "success_usec": 0, "pending_usec": 0,
	"peak_usec": 0, "target_count": 0, "pending_max_usec": 0
}
var _blockers: Dictionary = {}
var _frame_phases: Dictionary = {}

var _missing_focus: Dictionary = {
	"not_requested": 0, "awaiting_first_dispatch": 0,
	"submitting": 0, "awaiting_jobs_or_upload": 0,
	"cached_waiting_publish": 0
}
var _dispatch_frames: Dictionary = {"budget_one": 0, "budget_two": 0, "max_inflight": 0}
var _cancelled: Dictionary = {}
var _ignored_stale_jobs := 0


func begin(id: String, purpose: String, now_usec: int,
	restored_cache: bool, focus_distance: int) -> void:
	if purpose != "load":
		return
	_stages[id] = {
		"start": now_usec,
		"first_submit": 0,
		"last_submit": 0,
		"last_completed": 0,
		"submissions": 0,
		"completions": 0,
		"snapshot_usec": 0,
		"queue_usec": 0,
		"worker_usec": 0,
		"upload_usec": 0,
		"cached": restored_cache,
		"first_visit": not _published_region_ids.has(id),
		"focus_distance": focus_distance
	}
	var group := _group(_stages[id])
	_add(group, "started", 1)


func submit(id: String, now_usec: int, snapshot_usec: int) -> void:
	if not _stages.has(id):
		return
	var record: Dictionary = _stages[id]
	if int(record["first_submit"]) == 0:
		record["first_submit"] = now_usec
	record["last_submit"] = now_usec
	record["submissions"] = int(record["submissions"]) + 1
	record["snapshot_usec"] = int(record["snapshot_usec"]) + maxi(0, snapshot_usec)


func completed_job(id: String, accepted_usec: int,
	queue_usec: int, worker_usec: int, upload_usec: int) -> void:
	if not _stages.has(id):
		return
	var record: Dictionary = _stages[id]
	record["completions"] = int(record["completions"]) + 1
	record["last_completed"] = maxi(int(record["last_completed"]), accepted_usec)
	record["queue_usec"] = int(record["queue_usec"]) + maxi(0, queue_usec)
	record["worker_usec"] = int(record["worker_usec"]) + maxi(0, worker_usec)
	record["upload_usec"] = int(record["upload_usec"]) + maxi(0, upload_usec)


func stale_job() -> void:
	_ignored_stale_jobs += 1


func published(id: String, now_usec: int) -> void:
	if not _stages.has(id):
		_published_region_ids[id] = true
		return
	var record: Dictionary = _stages[id]
	_stages.erase(id)
	_published_region_ids[id] = true
	var group := _group(record)
	_add(group, "published", 1)
	var total := maxi(0, now_usec - int(record["start"]))
	_measure(group + ".total", total)
	_add(group, "total_usec", total)
	_add(group, "chunks_submitted", int(record["submissions"]))
	_add(group, "chunks_completed", int(record["completions"]))
	_add(group, "snapshot_usec", int(record["snapshot_usec"]))
	_add(group, "worker_queue_usec", int(record["queue_usec"]))
	_add(group, "worker_run_usec", int(record["worker_usec"]))
	_add(group, "upload_usec", int(record["upload_usec"]))
	if not bool(record["cached"]):
		if int(record["first_submit"]) > 0:
			var pre := maxi(0, int(record["first_submit"]) - int(record["start"]))
			var submit := maxi(0, int(record["last_submit"]) - int(record["first_submit"]))
			var drain := maxi(0, now_usec - int(record["last_submit"]))
			_measure(group + ".before_first_submit", pre)
			_measure(group + ".submit_span", submit)
			_measure(group + ".drain_after_last_submit", drain)
			_add(group, "before_first_submit_usec", pre)
			_add(group, "submit_span_usec", submit)
			_add(group, "drain_after_last_submit_usec", drain)
	else:
		_measure(group + ".cache_restore", total)
	_add(group, "start_distance_sum", int(record["focus_distance"]))


func cancel(id: String, reason: String) -> void:
	if not _stages.has(id):
		return
	var record: Dictionary = _stages[id]
	_stages.erase(id)
	var key := _group(record) + "." + reason
	_cancelled[key] = int(_cancelled.get(key, 0)) + 1
	_add(_group(record), "wasted_submissions", int(record["submissions"]))
	_add(_group(record), "wasted_completions", int(record["completions"]))


func effect_result(prepared: Dictionary, elapsed_usec: int, target_count: int) -> void:
	_effect["calls"] = int(_effect["calls"]) + 1
	_effect["target_count"] = int(_effect["target_count"]) + target_count
	_effect["all_usec"] = int(_effect["all_usec"]) + maxi(0, elapsed_usec)
	_effect["peak_usec"] = maxi(int(_effect["peak_usec"]), elapsed_usec)
	if bool(prepared.get("ok", false)):
		_effect["success"] = int(_effect["success"]) + 1
		_effect["success_usec"] = int(_effect["success_usec"]) + maxi(0, elapsed_usec)
	elif bool(prepared.get("pending", false)):
		_effect["pending"] = int(_effect["pending"]) + 1
		_effect["pending_usec"] = int(_effect["pending_usec"]) + maxi(0, elapsed_usec)
		_effect["pending_max_usec"] = maxi(int(_effect["pending_max_usec"]), elapsed_usec)
	else:
		_effect["failed"] = int(_effect["failed"]) + 1


func frame_phase(name: String, elapsed_usec: int) -> void:
	if not _frame_phases.has(name):
		_frame_phases[name] = {
			"calls": 0, "total_usec": 0, "peak_usec": 0, "over8ms": 0
		}
	var entry: Dictionary = _frame_phases[name]
	var cost := maxi(0, elapsed_usec)
	entry["calls"] = int(entry["calls"]) + 1
	entry["total_usec"] = int(entry["total_usec"]) + cost
	entry["peak_usec"] = maxi(int(entry["peak_usec"]), cost)
	if cost >= 8000:
		entry["over8ms"] = int(entry["over8ms"]) + 1


func blocked(reason: String) -> void:
	_blockers[reason] = int(_blockers.get(reason, 0)) + 1


func sample_frame(focus_id: String, is_active: bool, stage: Dictionary,
	dispatch_budget: int, inflight: int, inflight_max: int) -> void:
	if dispatch_budget > 1:
		_dispatch_frames["budget_two"] = int(_dispatch_frames["budget_two"]) + 1
	else:
		_dispatch_frames["budget_one"] = int(_dispatch_frames["budget_one"]) + 1
	if inflight >= inflight_max:
		_dispatch_frames["max_inflight"] = int(_dispatch_frames["max_inflight"]) + 1
	if is_active:
		return
	if stage.is_empty():
		_missing_focus["not_requested"] = int(_missing_focus["not_requested"]) + 1
	elif bool(stage.get("dm18_cache_ready", false)):
		_missing_focus["cached_waiting_publish"] = int(_missing_focus["cached_waiting_publish"]) + 1
	elif int(stage.get("submit_index", 0)) == 0:
		_missing_focus["awaiting_first_dispatch"] = int(_missing_focus["awaiting_first_dispatch"]) + 1
	elif int(stage.get("submit_index", 0)) < (stage.get("chunk_coordinates", []) as Array).size():
		_missing_focus["submitting"] = int(_missing_focus["submitting"]) + 1
	else:
		_missing_focus["awaiting_jobs_or_upload"] = int(_missing_focus["awaiting_jobs_or_upload"]) + 1


func summary() -> Dictionary:
	var percentiles: Dictionary = {}
	for name_value in _latencies.keys():
		var name := String(name_value)
		var values: Array = _latencies[name]
		var ordered := values.duplicate()
		ordered.sort()
		var count := ordered.size()
		if count == 0:
			continue
		var sum_usec := 0
		for value in ordered:
			sum_usec += int(value)
		percentiles[name] = {
			"n": count,
			"avg_ms": snappedf(float(sum_usec) / float(count) / 1000.0, 0.001),
			"p50_ms": _percentile_ms(ordered, 0.50),
			"p95_ms": _percentile_ms(ordered, 0.95),
			"max_ms": float(int(ordered[-1])) / 1000.0
		}
	return {
		"stage_groups": _metrics.duplicate(true),
		"stage_latency": percentiles,
		"effect": _effect.duplicate(),
		"dispatch_blockers": _blockers.duplicate(),
		"frame_phases": _frame_phases.duplicate(true),
		"missing_focus_frames_by_state": _missing_focus.duplicate(),
		"dispatch_frames": _dispatch_frames.duplicate(),
		"cancelled_by_reason": _cancelled.duplicate(),
		"stale_ignored_jobs": _ignored_stale_jobs,
		"unfinished_stages": _stages.size(),
		"ever_published_regions": _published_region_ids.size()
	}


func _group(record: Dictionary) -> String:
	if bool(record.get("cached", false)):
		return "cached"
	if bool(record.get("first_visit", false)):
		return "first_visit"
	return "uncached_revisit"


func _add(group: String, key: String, delta: int) -> void:
	if not _metrics.has(group):
		_metrics[group] = {}
	var values: Dictionary = _metrics[group]
	values[key] = int(values.get(key, 0)) + delta


func _measure(name: String, usec: int) -> void:
	if not _latencies.has(name):
		_latencies[name] = []
	var values: Array = _latencies[name]
	if values.size() < MAX_LATENCY_SAMPLES:
		values.append(maxi(0, usec))


func _percentile_ms(ordered: Array, fraction: float) -> float:
	if ordered.is_empty():
		return 0.0
	var index := clampi(ceili(float(ordered.size()) * fraction) - 1, 0, ordered.size() - 1)
	return snappedf(float(int(ordered[index])) / 1000.0, 0.001)
