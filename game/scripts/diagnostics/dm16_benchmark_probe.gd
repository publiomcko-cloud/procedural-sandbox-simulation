extends RefCounted

## DM16: benchmark-only in-memory timing receipt, independent from PERF_TRACE.
## No JSON, file I/O, Engine/SceneTree operations, or stdout per frame.
## record_frame() is called at the end of each deterministic benchmark frame.
## frame_ms is the previous frame delta; previous_stages describes the
## preceding _process. Never attribute the current stage to prior delta.

var _frame_ms: Array[float] = []
var _process_ms: Array[float] = []
var _missing_focus := 0
var _frames_over_20 := 0
var _frames_over_33 := 0
var _frames_over_50 := 0
var _prior_process_over_14 := 0
var _high_elapsed_ms := -1.0
var _stage_current: Dictionary = {}
var _stage_previous: Dictionary = {}
var _spike_stage_counts: Dictionary = {}
var _stage_usec_sum: Dictionary = {}
var _stage_usec_max: Dictionary = {}
var _spike_exemplars: Array[Dictionary] = []


func record_stage(name: String, elapsed_usec: int) -> void:
	_stage_current[name] = int(_stage_current.get(name, 0)) + maxi(0, elapsed_usec)


func record_frame(
	frame_delta_ms: float, process_usec: int,
	focus_missing: bool, high_complete: bool, elapsed_wall_ms: float
) -> void:
	var frame_ms := maxf(0.0, frame_delta_ms)
	_frame_ms.append(frame_ms)
	_process_ms.append(float(maxi(0, process_usec)) / 1000.0)
	if focus_missing:
		_missing_focus += 1
	if frame_ms > 20.0:
		_frames_over_20 += 1
	if frame_ms > 33.0:
		_frames_over_33 += 1
	if frame_ms > 50.0:
		_frames_over_50 += 1
	if high_complete and _high_elapsed_ms < 0.0:
		_high_elapsed_ms = elapsed_wall_ms

	# Godot delta is elapsed since the previous frame. Inspect the *previous*
	# frame's stage durations and full _process time, never current stages.
	if frame_ms > 33.0:
		var dominant := "unattributed"
		var maximum := 0
		for stage in _stage_previous:
			var usec := int(_stage_previous[stage])
			if usec > maximum:
				maximum = usec
				dominant = String(stage)
		_spike_stage_counts[dominant] = int(
			_spike_stage_counts.get(dominant, 0)
		) + 1
		if not _process_ms.is_empty() and _process_ms.size() > 1 \
		and _process_ms[-2] >= 14.0:
			_prior_process_over_14 += 1
		if _spike_exemplars.size() < 32:
			_spike_exemplars.append({
				"frame": _frame_ms.size(),
				"delta_previous_ms": snappedf(frame_ms, 0.001),
				"prior_process_ms": _process_ms[-2] if _process_ms.size() > 1 else -1.0,
				"prior_dominant_stage": dominant,
				"prior_stage_ms": snappedf(float(maximum) / 1000.0, 0.001)
			})

	for stage in _stage_current:
		var usec := int(_stage_current[stage])
		_stage_usec_sum[stage] = int(_stage_usec_sum.get(stage, 0)) + usec
		_stage_usec_max[stage] = maxi(int(_stage_usec_max.get(stage, 0)), usec)
	_stage_previous = _stage_current.duplicate()
	_stage_current.clear()


func summary(
	route: String, profile: String, seed_value: int, expected_frames: int,
	trace_enabled: bool, light_stages: bool,
	visual_completed: int, visual_visible: int, canonical_active: int,
	world_revision: int
) -> Dictionary:
	var n := _frame_ms.size()
	var sum_frame := 0.0
	var sum_process := 0.0
	for value in _frame_ms:
		sum_frame += value
	for value in _process_ms:
		sum_process += value
	var stages := {}
	for stage in _stage_usec_sum:
		stages[stage] = {
			"sum_ms": snappedf(float(_stage_usec_sum[stage]) / 1000.0, 0.001),
			"peak_ms": snappedf(float(_stage_usec_max[stage]) / 1000.0, 0.001)
		}
	return {
		"ok": n == expected_frames,
		"source": "dm16_benchmark_in_memory",
		"route": route,
		"profile": profile,
		"seed": seed_value,
		"expected_frames": expected_frames,
		"measured_frames": n,
		"perf_trace": trace_enabled,
		"light_stages": light_stages,
		"frame_avg_ms": snappedf(sum_frame / maxf(1.0, float(n)), 0.001),
		"frame_p95_ms": _percentile(_frame_ms, 0.95),
		"frame_p99_ms": _percentile(_frame_ms, 0.99),
		"frame_max_ms": _percentile(_frame_ms, 1.0),
		"frame_over20_count": _frames_over_20,
		"frame_over33_count": _frames_over_33,
		"frame_over50_count": _frames_over_50,
		"frame_over20_pct": snappedf(100.0 * float(_frames_over_20) / maxf(1.0, float(n)), 0.001),
		"frame_over33_pct": snappedf(100.0 * float(_frames_over_33) / maxf(1.0, float(n)), 0.001),
		"process_avg_ms": snappedf(sum_process / maxf(1.0, float(n)), 0.001),
		"process_p95_ms": _percentile(_process_ms, 0.95),
		"process_p99_ms": _percentile(_process_ms, 0.99),
		"process_max_ms": _percentile(_process_ms, 1.0),
		"spikes_with_prior_process_over14": _prior_process_over_14,
		"spike_prior_dominant_stage_counts": _spike_stage_counts.duplicate(),
		"stage_work": stages,
		"spike_exemplars": _spike_exemplars.duplicate(true),
		"focus_missing_frames": _missing_focus,
		"focus_missing_pct": (
			snappedf(100.0 * float(_missing_focus) / float(n), 0.001)
			if route != "idle" and n > 0 else null
		),
		"visual_high_completed": visual_completed,
		"visual_high_visible": visual_visible,
		"canonical_regions_active": canonical_active,
		"full_high_elapsed_ms": _high_elapsed_ms if route == "idle" else null,
		"world_revision": world_revision
	}


func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(ceil(float(sorted.size()) * percentile)) - 1, 0, sorted.size() - 1)
	return snappedf(sorted[index], 0.001)
