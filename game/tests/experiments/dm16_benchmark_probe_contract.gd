extends SceneTree

const Probe := preload("res://scripts/diagnostics/dm16_benchmark_probe.gd")

var assertions := 0
var fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var p := Probe.new()
	p.record_stage("sdf_cache", 19000)
	p.record_stage("water_visual", 900)
	p.record_frame(16.0, 20000, true, false, 100.0)
	p.record_stage("mesh_dispatch_and_upload", 100)
	p.record_frame(42.0, 3000, false, false, 120.0)
	p.record_stage("water_visual", 22000)
	p.record_frame(55.0, 22000, false, true, 130.0)
	p.record_stage("coarse_preview", 150)
	p.record_frame(18.0, 1000, false, true, 145.0)
	var s: Dictionary = p.summary("outback-18", "adaptive-skip-progressive",
		424242, 4, false, true, 7, 5, 9, 0)
	_check(bool(s.get("ok", false)), "four samples accepted")
	_check(int(s["measured_frames"]) == 4, "exact sample count")
	_check(int(s["frame_over33_count"]) == 2, "two previous-frame delta spikes")
	_check(int(s["frame_over50_count"]) == 1, "one 50 ms tail")
	_check(int(s["focus_missing_frames"]) == 1, "focus absent on one frame")
	_check(is_equal_approx(float(s["focus_missing_pct"]), 25.0), "focus missing percentage")
	_check(int(s["spikes_with_prior_process_over14"]) == 1,
		"only first spike follows a previous process above 14ms")
	_check(int(s["spike_prior_dominant_stage_counts"].get("sdf_cache", 0)) == 1,
		"42ms frame attributed to preceding 19ms SDF")
	_check(int(s["spike_prior_dominant_stage_counts"].get("mesh_dispatch_and_upload", 0)) == 1,
		"55ms frame attributed to preceding mesh stage, not current water")
	_check(is_equal_approx(float(s["frame_p95_ms"]), 55.0), "deterministic p95")
	_check(is_equal_approx(float(s["frame_p99_ms"]), 55.0), "deterministic p99")
	_check(int(s["visual_high_completed"]) == 7, "visual HIGH receipt preserved")
	_check(s["light_stages"] and not s["perf_trace"], "trace off but lightweight stages on")
	_check(not p.summary("outback-18", "adaptive-skip-progressive",
		424242, 5, false, true, 7, 5, 9, 0).get("ok", true),
		"short benchmark cannot claim complete data")
	var off := Probe.new()
	off.record_frame(34.0, 1000, false, false, 40.0)
	var no_trace: Dictionary = off.summary("outback-18", "baseline",
		424242, 1, false, false, 0, 0, 0, 0)
	_check(no_trace["stage_work"].is_empty(), "trace-off has no stage capture")
	_check(int(no_trace["spike_prior_dominant_stage_counts"].get("unattributed", 0)) == 1,
		"trace-off never invents causal attribution")
	var idle := Probe.new()
	idle.record_frame(16.0, 3000, false, false, 15.0)
	idle.record_frame(16.0, 3000, false, true, 13000.0)
	var idle_summary: Dictionary = idle.summary("idle", "baseline", 424242,
		2, false, false, 268, 268, 9, 0)
	_check(idle_summary["focus_missing_pct"] == null, "idle excludes movement gap percentage")
	_check(is_equal_approx(float(idle_summary["full_high_elapsed_ms"]), 13000.0),
		"first HIGH fill elapsed retained")
	print("DM16_BENCH_PROBE_RESULT=" + JSON.stringify({
		"assertions": assertions, "failures": fails,
		"prior_frame_attribution": fails == 0,
		"trace_off_receipt": fails == 0
	}))
	print("DM16_BENCH_PROBE_%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		fails += 1
		push_error("DM16_BENCH_PROBE_FAIL: " + label)
