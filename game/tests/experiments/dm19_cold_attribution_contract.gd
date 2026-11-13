extends SceneTree

const Probe := preload("res://scripts/diagnostics/dm19_cold_attribution.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var probe := Probe.new()
	probe.begin("a", "load", 1_000_000, false, 1)
	probe.effect_result({"ok": false, "pending": true}, 120, 2)
	probe.blocked("effect_pending_chunk")
	probe.submit("a", 1_010_000, 100)
	probe.submit("a", 1_030_000, 200)
	probe.completed_job("a", 1_035_000, 5000, 7000, 800)
	probe.completed_job("a", 1_040_000, 2000, 5000, 600)
	probe.sample_frame("a", false, {"submit_index": 2, "chunk_coordinates": [1, 2, 3]}, 2, 3, 8)
	probe.published("a", 1_055_000)
	probe.begin("a", "load", 1_060_000, true, 1)
	probe.sample_frame("a", false, {"dm18_cache_ready": true}, 1, 8, 8)
	probe.published("a", 1_061_000)
	probe.begin("b", "load", 1_065_000, false, 1)
	probe.cancel("b", "left_window")
	probe.stale_job()
	probe.sample_frame("z", false, {}, 1, 0, 8)
	var result := probe.summary()
	_check(int(result["stage_groups"]["first_visit"]["published"]) == 1, "first visit")
	_check(int(result["stage_groups"]["cached"]["published"]) == 1, "cache")
	_check(int(result["stage_groups"]["first_visit"]["chunks_submitted"]) == 2, "submission count")
	_check(int(result["stage_groups"]["first_visit"]["chunks_completed"]) == 2, "job count")
	_check(int(result["stage_groups"]["first_visit"]["worker_queue_usec"]) == 7000, "queue totals")
	_check(int(result["stage_groups"]["first_visit"]["worker_run_usec"]) == 12000, "worker totals")
	_check(int(result["stage_groups"]["first_visit"]["upload_usec"]) == 1400, "upload totals")
	_check(int(result["stage_latency"]["first_visit.total"]["p50_ms"]) == 55.0, "total wall latency")
	_check(int(result["stage_latency"]["first_visit.before_first_submit"]["p50_ms"]) == 10, "first dispatch delay")
	_check(int(result["stage_latency"]["first_visit.submit_span"]["p50_ms"]) == 20, "submit window")
	_check(int(result["stage_latency"]["first_visit.drain_after_last_submit"]["p50_ms"]) == 25, "drain")
	_check(int(result["stage_latency"]["cached.total"]["p50_ms"]) == 1, "cached latency")
	_check(int(result["effect"]["pending"]) == 1, "pending effect")
	_check(int(result["dispatch_blockers"]["effect_pending_chunk"]) == 1, "blocker")
	_check(int(result["missing_focus_frames_by_state"]["submitting"]) == 1, "missing during submit")
	_check(int(result["missing_focus_frames_by_state"]["cached_waiting_publish"]) == 1, "missing cache queue")
	_check(int(result["missing_focus_frames_by_state"]["not_requested"]) == 1, "not requested")
	_check(int(result["dispatch_frames"]["max_inflight"]) == 1, "worker saturation")
	_check(int(result["cancelled_by_reason"]["first_visit.left_window"]) == 1, "cancelled")
	_check(int(result["stale_ignored_jobs"]) == 1, "orphan jobs")
	_check(int(result["ever_published_regions"]) == 1, "published unique region")
	_check(int(result["unfinished_stages"]) == 0, "no live stages")
	print("DM19_COLD_PROFILE_RESULT: " + JSON.stringify({"checks": checks, "failures": failures}))
	print("DM19_COLD_PROFILE_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DM19_COLD_PROFILE_FAILURE: " + reason)
