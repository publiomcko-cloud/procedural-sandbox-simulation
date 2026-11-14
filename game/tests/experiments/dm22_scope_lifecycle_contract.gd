extends SceneTree

const Probe := preload("res://scripts/diagnostics/dm22_scope_lifecycle_probe.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var p := Probe.new()
	var one := "region:1,1"
	var two := "region:2,1"
	p.queued(one, 1_000_000, 10, false)
	p.queued(two, 1_000_100, 11, false)
	p.queued(two, 1_000_150, 11, true)
	p.reprioritized(two)
	p.focus_prepare(
		"region:0,0", 22, 1_000_500,
		[Vector2i(1, 1), Vector2i(2, 1)], true
	)
	p.generation_dispatched(one, 1_001_000)
	p.generation_completed(one, 1_001_000, 1_007_000, 500, 5000, 400)
	p.projection_dispatched(one, 1_008_000, false)
	p.projection_completed(one, 1_017_000, 500, 8000)
	p.published(one, 1_020_000, 2000)
	p.generation_dispatched(two, 1_021_000)
	p.generation_completed(two, 1_021_000, 1_025_000, 300, 3400, 100)
	p.projection_dispatched(two, 1_025_300, true)
	p.published(two, 1_040_000, 1000)
	p.focus_prepare("region:0,0", 22, 1_041_000, [], false)
	p.focus_first_submitted("region:0,0", 22, 1_043_000)
	var r := p.summary()
	_check(int(r["counts"]["scope_publications"]) == 2, "publication count")
	_check(int(r["counts"]["generation_dispatches"]) == 2, "generation count")
	_check(int(r["counts"]["projection_dispatches"]) == 1, "projection queue")
	_check(int(r["counts"]["projection_cache_hits"]) == 1, "projection cache")
	_check(int(r["counts"]["focus_first_chunk_pending_attempts"]) == 1, "focus pending")
	_check(int(r["counts"]["focus_first_chunk_ready_calls"]) == 1, "focus ready")
	_check(int(r["counts"]["focus_first_chunk_submitted"]) == 1, "focal submit")
	_check(int(r["counts"]["scope_duplicate_queue_attempt"]) == 1, "dedup original queues")
	_check(int(r["counts"]["focus_all_sources_ready_events"]) == 1, "source rendezvous")
	_check(int(r["critical_scope_top"][0]["hits"]) == 1, "critical last scope count")
	_check(String(r["critical_scope_top"][0]["scope"]) == two, "critical source ID")
	_check(int(r["latency"]["focus_first_chunk_wait_ms"]["mean_ms"]) == 42, "focus wall wait")
	_check(int(r["latency"]["focus_dependency_last_publish_wait_ms"]["mean_ms"]) == 39, "last dependency wait")
	_check(int(r["latency"]["focus_ready_to_first_submit_ms"]["mean_ms"]) == 3, "ready to submit")
	_check(int(r["latency"]["scope_total_ms"]["n"]) == 2, "complete scopes")
	_check(int(r["latency"]["critical_scope_total_ms"]["n"]) == 1, "critical scope linked")
	_check(int(r["critical_dominant_phases"]["queue"]) == 1, "critical phase queue")
	_check(int(r["scopes_in_trace"]) == 0, "completed scopes released")
	_check(int(r["focus_requests_unfinished"]) == 0, "finished focus released")

	p.queued("region:3,3", 1_050_000, 13, false)
	p.cancelled("region:3,3", "left_protected_queue")
	_check(int(p.summary()["counts"]["cancel_left_protected_queue"]) == 1, "bounded cancellation")
	_check(int(p.summary()["scopes_in_trace"]) == 0, "cancel removes trace")
	p.focus_prepare("region:9,9", 24, 2_000_000, [Vector2i(4, 4)], true)
	p.focus_cancel("region:9,9", 24)
	_check(int(p.summary()["counts"]["focus_first_chunk_cancelled_waiting"]) == 1, "focal cancel")
	print("DM22_SCOPE_PROBE_RESULT=" + JSON.stringify({
		"checks": checks, "failures": failures
	}))
	print("DM22_SCOPE_PROBE_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DM22_SCOPE_PROBE_FAILURE: " + reason)
