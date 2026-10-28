extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateScript := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const CANDIDATE_ID := "A"
const REPEATS := 5
var _candidate: Object
var _manifest: Dictionary = {}
var _source_sha := ""
var _run_id := ""
var _campaign_event := ""
var _campaign_started_usec := 0
var _case_counter := 0
var _hard_stop := false

func _initialize() -> void:
	_campaign_started_usec = Time.get_ticks_usec()
	_source_sha = OS.get_environment("R9_SOURCE_SHA")
	_run_id = OS.get_environment("R9_RUN_ID")
	if _run_id.is_empty():
		_run_id = "R9.2." + CANDIDATE_ID + "." + str(Time.get_ticks_usec())
	_campaign_event = _run_id + ".campaign.started"
	_candidate = CandidateScript.new()
	call_deferred("_run")

func _run() -> void:
	_manifest = Core.load_manifest()
	if not _manifest.get("valid", false):
		_emit({"schema": "P3.1.R9.2.Event.v1", "event_type": "campaign_blocked", "run_id": _run_id,
			"source_sha": _source_sha, "reason": _manifest.get("reason", "manifest_invalid"),
			"monotonic_usec": Time.get_ticks_usec()})
		quit(2)
		return
	if _source_sha.length() != 40 or not _source_sha.is_valid_hex_number():
		_emit({"schema": "P3.1.R9.2.Event.v1", "event_type": "campaign_blocked", "run_id": _run_id,
			"source_sha": _source_sha, "reason": "source_sha_env_missing_or_invalid", "monotonic_usec": Time.get_ticks_usec()})
		quit(2)
		return
	_emit({"schema": "P3.1.R9.2.Event.v1", "event_type": "campaign_started", "event_id": _campaign_event,
		"run_id": _run_id, "source_sha": _source_sha, "candidate": CANDIDATE_ID,
		"manifest_sha256": Core.EXPECTED_MANIFEST_SHA, "scenario_rows": _manifest.rows.size(),
		"process_monotonic_origin_usec": _campaign_started_usec, "monotonic_usec": Time.get_ticks_usec()})
	for row_value in _manifest.rows:
		var row: Dictionary = row_value
		if _hard_stop:
			_emit_not_run(row, "candidate_aggregate_runtime_stop_loss")
			continue
		if Time.get_ticks_usec() - _campaign_started_usec >= Core.MAX_CANDIDATE_USEC:
			_hard_stop = true
			_emit_not_run(row, "candidate_aggregate_runtime_stop_loss")
			continue
		_run_row(row)
	var status := "COMPLETE" if not _hard_stop else "CENSORED"
	_emit({"schema": "P3.1.R9.2.Event.v1", "event_type": "campaign_complete", "event_id": _run_id + ".campaign.complete",
		"parent_event_id": _campaign_event, "run_id": _run_id, "source_sha": _source_sha, "candidate": CANDIDATE_ID,
		"status": status, "scenario_variant_count": _case_counter, "duration_usec": Time.get_ticks_usec() - _campaign_started_usec,
		"monotonic_usec": Time.get_ticks_usec()})
	print("P3_1_R9_2_CAMPAIGN_RESULT " + JSON.stringify({"candidate": CANDIDATE_ID, "source_sha": _source_sha,
		"manifest_sha256": Core.EXPECTED_MANIFEST_SHA, "status": status, "scenario_variant_count": _case_counter,
		"duration_usec": Time.get_ticks_usec() - _campaign_started_usec, "production_eligibility": "NOT_ELIGIBLE_EXPERIMENT_ONLY"}))
	quit(0)

func _run_row(row: Dictionary) -> void:
	var setup: Dictionary = Core.make_snapshot(row)
	var variants: Array = []
	if row.has("roi"):
		variants.append({"id": "default", "roi": row.roi})
	else:
		variants = row.get("variants", [])
	for variant_value in variants:
		var variant: Dictionary = variant_value
		_case_counter += 1
		var case_id := String(row.scenario_id) + "." + String(variant.get("id", "default"))
		var start_event := _run_id + ".case." + str(_case_counter) + ".started"
		var case_start := Time.get_ticks_usec()
		_emit({"schema": "P3.1.R9.2.Event.v1", "event_type": "scenario_started", "event_id": start_event,
			"parent_event_id": _campaign_event, "run_id": _run_id, "source_sha": _source_sha,
			"candidate": CANDIDATE_ID, "scenario_id": row.scenario_id, "variant_id": variant.get("id", "default"),
			"case_id": case_id, "manifest_case_sha256": _manifest.case_digests[row.scenario_id],
			"command_sha256": _manifest.command_digests[row.scenario_id], "command_count": row.commands.size(),
			"monotonic_usec": case_start})
		if not setup.get("valid", false):
			_emit_result(row, variant, case_id, start_event, case_start, "FAIL", "FAILED", "NOT_ASSESSED", "PARTIAL",
				{"reason": setup.get("reason", "snapshot_invalid")}, [])
			continue
		var roi: Dictionary = variant.get("roi", {})
		if not Core.validate_roi(roi).get("valid", false):
			_emit_result(row, variant, case_id, start_event, case_start, "FAIL", "FAILED", "NOT_ASSESSED", "PARTIAL",
				{"reason": "roi_rejected_by_shared_contract"}, [])
			continue
		if String(row.get("kind", "")) == "sampled_cave_connectivity":
			var connectivity: Dictionary = Core.sampled_cave_connectivity(roi, setup.snapshot, int(row.seed))
			_emit_result(row, variant, case_id, start_event, case_start, "COMPLETE",
				"SHARED_CANONICAL_REFERENCE_ONLY", "DIAGNOSTIC_ONLY", "COMPLETE",
				{"sampled_connectivity": _connectivity_summary(connectivity)}, [])
			continue
		_candidate.call("configure_roi", roi)
		var warm_start := Time.get_ticks_usec()
		var warm_value: Variant = _candidate.call("build", setup.snapshot, row, variant)
		var warm_usec := Time.get_ticks_usec() - warm_start
		if typeof(warm_value) != TYPE_DICTIONARY or not warm_value.get("valid", false):
			var warm_reason := String(warm_value.get("reason", "candidate_build_failed")) if typeof(warm_value) == TYPE_DICTIONARY else "candidate_build_result_not_dictionary"
			var warm_status := "CENSORED" if _is_stop_loss(warm_reason) or warm_usec >= Core.MAX_SCENARIO_USEC else "FAIL"
			_emit_result(row, variant, case_id, start_event, case_start, warm_status, "EXECUTED_BUT_NO_MESH",
				"NOT_ASSESSED", "PARTIAL", {"reason": warm_reason, "warmup_usec": warm_usec}, [])
			continue
		var warm: Dictionary = warm_value
		var mesh: Dictionary = warm.mesh
		var sample_times: Array[int] = []
		var sample_hashes: Array[String] = []
		var build_metrics: Array[Dictionary] = []
		var failed_repeat := false
		var repeat_reason := ""
		for repeat_index in range(REPEATS):
			if Time.get_ticks_usec() - _campaign_started_usec >= Core.MAX_CANDIDATE_USEC:
				failed_repeat = true
				repeat_reason = "candidate_aggregate_runtime_stop_loss"
				_hard_stop = true
				break
			var repeat_start := Time.get_ticks_usec()
			var repeat_value: Variant = _candidate.call("build", setup.snapshot, row, variant)
			var elapsed := Time.get_ticks_usec() - repeat_start
			if typeof(repeat_value) != TYPE_DICTIONARY or not repeat_value.get("valid", false):
				failed_repeat = true
				repeat_reason = String(repeat_value.get("reason", "repeat_build_failed")) if typeof(repeat_value) == TYPE_DICTIONARY else "repeat_build_result_not_dictionary"
				break
			var repeat_build: Dictionary = repeat_value
			sample_times.append(elapsed)
			sample_hashes.append(String(repeat_build.get("mesh_sha256", "")))
			build_metrics.append(repeat_build.get("metrics", {}))
			if elapsed > Core.MAX_SCENARIO_USEC:
				failed_repeat = true
				repeat_reason = "per_scenario_repetition_time_stop_loss"
				break
		var topo: Dictionary = Core.topology(mesh, Core.world_min(roi), Core.world_min(roi) + Vector3(Core.cell_counts(roi)) * Core.step(roi))
		var residual: Dictionary = Core.surface_residual(mesh, setup.snapshot, int(row.seed))
		var normals: Dictionary = Core.normal_deviation(mesh, setup.snapshot, int(row.seed))
		var components: Dictionary = Core.mesh_components(mesh)
		var diagnostics: Dictionary = {"topology": _topology_summary(topo), "surface_residual": residual,
			"normal_deviation": normals, "mesh_components": components, "candidate_metrics": warm.get("metrics", {}),
			"warmup_usec": warm_usec, "build_samples_usec": sample_times, "build_sample_sha256": sample_hashes,
			"deterministic_hash_match": _all_hashes_match(sample_hashes), "candidate_metric_samples": build_metrics}
		var capability := _capability_status(row, variant)
		if String(row.get("kind", "")) in ["same_resolution_boundary", "mixed_lod_boundary", "negative_region_boundary", "historical_interface_defect"]:
			diagnostics["seam_contour"] = _seam_diagnostic(mesh, setup.snapshot, roi, row, variant)
		if String(row.get("kind", "")) == "ray_picker_parity":
			var rays: Array[Dictionary] = Core.ray_grid(roi, row.ray_grid)
			var ray_result: Dictionary = Core.compare_mesh_rays(rays, mesh, setup.snapshot, int(row.seed))
			diagnostics["ray_picker"] = _ray_summary(ray_result)
		if String(row.get("kind", "")) == "cpu_two_sided_triangle_proxy":
			var proxy_rays: Array[Dictionary] = _proxy_rays(row)
			var proxy_result: Dictionary = Core.compare_mesh_rays(proxy_rays, mesh, setup.snapshot, int(row.seed))
			diagnostics["two_sided_cpu_proxy"] = _ray_summary(proxy_result)
			diagnostics["physics_server"] = "NOT_RUN"
		if String(row.get("kind", "")) == "historical_triangle_root":
			diagnostics["triangle_root_observation"] = _triangle_root_observation(mesh, setup.snapshot, roi, row)
		if String(row.get("kind", "")) == "deterministic_rebuild":
			diagnostics["rebuild_hashes"] = sample_hashes
		if String(row.get("kind", "")) == "local_edit_rebuild":
			diagnostics["edit_to_candidate_mesh_usec"] = sample_times
		if CANDIDATE_ID == "D" and String(row.get("kind", "")) == "corrupt_reload_recovery":
			var corruption: Dictionary = _candidate.call("corruption_reload_probe", setup.snapshot)
			diagnostics["corruption_reload"] = corruption
		if CANDIDATE_ID == "A" and String(row.get("kind", "")) == "mixed_lod_boundary":
			var local_probe: Dictionary = _candidate.call("_xplus_shared_face_probe", setup.snapshot)
			var full_pair: Dictionary = _candidate.call("_build_xplus_chunk_pair", setup.snapshot)
			diagnostics["candidate_a_mixed_lod"] = {"local_face_probe": local_probe, "complete_chunk_pair": full_pair}
		var quality := _quality_status(topo)
		var evidence := "COMPLETE"
		if failed_repeat or not residual.get("valid", false) or not normals.get("valid", false):
			evidence = "PARTIAL"
		var execution := "COMPLETE" if not failed_repeat else ("CENSORED" if _is_stop_loss(repeat_reason) else "PARTIAL")
		if failed_repeat:
			diagnostics["repeat_failure"] = repeat_reason
		if _has_unimplemented_capability(row, variant):
			capability = "NOT_IMPLEMENTED_OR_PARTIAL_AS_REPORTED"
		_emit_result(row, variant, case_id, start_event, case_start, execution, capability, quality, evidence, diagnostics, sample_times)

func _emit_result(row: Dictionary, variant: Dictionary, case_id: String, start_event: String, started_usec: int,
		execution_status: String, capability_status: String, geometry_status: String, evidence_status: String,
		diagnostics: Dictionary, samples_usec: Array) -> void:
	var record: Dictionary = {"schema": "P3.1.R9.2.Result.v1", "event_type": "scenario_complete",
		"event_id": start_event.trim_suffix(".started") + ".complete", "parent_event_id": start_event,
		"run_id": _run_id, "source_sha": _source_sha, "candidate": CANDIDATE_ID,
		"scenario_id": row.scenario_id, "variant_id": variant.get("id", "default"), "case_id": case_id,
		"manifest_sha256": Core.EXPECTED_MANIFEST_SHA, "manifest_case_sha256": _manifest.case_digests[row.scenario_id],
		"command_sha256": _manifest.command_digests[row.scenario_id], "command_count": row.commands.size(),
		"revision": row.commands.size(), "seed": row.seed, "generator_version": row.generator_version,
		"execution_status": execution_status, "capability_status": capability_status,
		"geometry_quality_status": geometry_status, "evidence_completeness": evidence_status,
		"production_eligibility": "NOT_ELIGIBLE_EXPERIMENT_ONLY", "scenario_start_usec": started_usec,
		"scenario_end_usec": Time.get_ticks_usec(), "duration_usec": Time.get_ticks_usec() - started_usec,
		"build_samples_usec": samples_usec, "diagnostics": diagnostics}
	_emit(record)

func _emit_not_run(row: Dictionary, reason: String) -> void:
	var variants: Array = row.get("variants", [])
	if row.has("roi"):
		variants = [{"id": "default", "roi": row.roi}]
	for variant_value in variants:
		var variant: Dictionary = variant_value
		_case_counter += 1
		var event_id := _run_id + ".case." + str(_case_counter) + ".notrun"
		_emit({"schema": "P3.1.R9.2.Result.v1", "event_type": "scenario_complete", "event_id": event_id,
			"parent_event_id": _campaign_event, "run_id": _run_id, "source_sha": _source_sha,
			"candidate": CANDIDATE_ID, "scenario_id": row.scenario_id, "variant_id": variant.get("id", "default"),
			"execution_status": "NOT_RUN", "capability_status": "NOT_ASSESSED", "geometry_quality_status": "NOT_ASSESSED",
			"evidence_completeness": "NONE", "production_eligibility": "NOT_ELIGIBLE_EXPERIMENT_ONLY",
			"reason": reason, "monotonic_usec": Time.get_ticks_usec()})

func _capability_status(row: Dictionary, variant: Dictionary) -> String:
	var kind := String(row.get("kind", ""))
	if kind == "mixed_lod_boundary":
		return "PARTIAL_LOCAL_TEMPLATE_ONLY" if CANDIDATE_ID == "A" else "NOT_IMPLEMENTED"
	if variant.has("lod_pairs") and _has_mixed_lod(variant.lod_pairs):
		return "NOT_IMPLEMENTED_MIXED_LOD_ORIENTATION"
	if kind == "corrupt_reload_recovery":
		return "IMPLEMENTED" if CANDIDATE_ID == "D" else "NOT_IMPLEMENTED_D_STORAGE_SCENARIO"
	if kind == "sampled_cave_connectivity":
		return "SHARED_CANONICAL_REFERENCE_ONLY"
	if kind == "cpu_two_sided_triangle_proxy":
		return "OFFLINE_CPU_TWO_SIDED_TRIANGLE_PROXY"
	return "EXECUTED_CANDIDATE_PATH"

func _has_unimplemented_capability(row: Dictionary, variant: Dictionary) -> bool:
	return String(row.get("kind", "")) == "mixed_lod_boundary" and CANDIDATE_ID != "A" or \
		variant.has("lod_pairs") and _has_mixed_lod(variant.lod_pairs) or \
		String(row.get("kind", "")) == "corrupt_reload_recovery" and CANDIDATE_ID != "D"

func _has_mixed_lod(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for pair_value in value:
		var pair: Array = pair_value
		if pair.size() == 2 and int(pair[0]) != int(pair[1]):
			return true
	return false

func _quality_status(topology: Dictionary) -> String:
	if int(topology.get("internal_open_edges", 0)) > 0 or int(topology.get("nonmanifold_edges", 0)) > 0 or \
		int(topology.get("degenerate_triangles", 0)) > 0 or int(topology.get("winding_inconsistencies", 0)) > 0:
		return "DEFECT_RECORDED"
	return "NO_DEFECT_OBSERVED_IN_RECORDED_CHECKS_NOT_ACCEPTANCE"

func _is_stop_loss(reason: String) -> bool:
	return reason.contains("stop_loss") or reason.contains("timeout") or reason.contains("resource")

func _all_hashes_match(hashes: Array[String]) -> bool:
	if hashes.is_empty() or hashes[0].is_empty():
		return false
	for digest in hashes:
		if digest != hashes[0]:
			return false
	return true

func _topology_summary(topology: Dictionary) -> Dictionary:
	return {"triangles": topology.get("triangle_count", 0), "internal_open_edges": topology.get("internal_open_edges", 0),
		"roi_boundary_open_edges": topology.get("roi_boundary_open_edges", 0), "nonmanifold_edges": topology.get("nonmanifold_edges", 0),
		"degenerate_triangles": topology.get("degenerate_triangles", 0), "winding_inconsistencies": topology.get("winding_inconsistencies", 0)}

func _connectivity_summary(value: Dictionary) -> Dictionary:
	return {"valid": value.get("valid", false), "reason": value.get("reason", ""),
		"sample_count": value.get("sample_count", 0), "centerline_slice_count": value.get("centerline_slice_count", 0),
		"centerline_slices_continuous": value.get("centerline_slices_continuous", false),
		"centerline_component_reaches_negative_x_opening": value.get("centerline_component_reaches_negative_x_opening", false),
		"centerline_component_reaches_positive_x_opening": value.get("centerline_component_reaches_positive_x_opening", false),
		"empty_component_count": value.get("empty_component_count", 0), "top_bottom_exterior_component_count": value.get("top_bottom_exterior_component_count", 0)}

func _ray_summary(value: Dictionary) -> Dictionary:
	return {"valid": value.get("valid", false), "ray_count": value.get("ray_count", 0),
		"hit_miss_disagreements": value.get("hit_miss_disagreements", -1), "position_error_count": value.get("position_error_count", 0),
		"position_error_abs_p50": value.get("position_error_abs_p50", null), "position_error_abs_p95": value.get("position_error_abs_p95", null),
		"position_error_abs_max": value.get("position_error_abs_max", null), "root_scan_completeness": value.get("root_scan_completeness", ""),
		"rays": value.get("rays", [])}

func _proxy_rays(row: Dictionary) -> Array[Dictionary]:
	var rays: Array[Dictionary] = []
	for ray_value in row.get("rays", []):
		var ray: Dictionary = ray_value
		var origin: Array = ray.o
		var direction: Array = ray.d
		rays.append({"origin": Vector3(origin[0], origin[1], origin[2]),
			"direction": Vector3(direction[0], direction[1], direction[2]), "length": float(row.get("ray_length", 12.0))})
	return rays

func _triangle_root_observation(mesh: Dictionary, snapshot: Dictionary, roi: Dictionary, row: Dictionary) -> Dictionary:
	var origin := Core.world_min(roi)
	var corners: Array[Dictionary] = []
	var values: Array[float] = []
	for corner_value in Core.GRID_CORNERS:
		var point := origin + Vector3(corner_value) * Core.step(roi)
		var density := Core.sample(point, snapshot, int(row.seed))
		values.append(density)
		var packed := PackedFloat32Array([density]).to_byte_array()
		corners.append({"point": [point.x, point.y, point.z], "density": density, "binary32_hex": packed.hex_encode()})
	return {"frozen_source_triangle_index": row.triangle_index, "local_roi_triangle_count": mesh.positions.size() / 3,
		"local_roi_corner_samples": corners, "local_rebuild_is_not_historical_full_roi_triangle_index_equivalence": true,
		"squared_cross_cutoff": row.squared_cross_cutoff}

func _seam_diagnostic(mesh: Dictionary, snapshot: Dictionary, roi: Dictionary, row: Dictionary, variant: Dictionary) -> Dictionary:
	var axis_name := String(variant.get("axis", row.get("axis", "X")))
	var axis := 0 if axis_name == "X" else (1 if axis_name == "Y" else 2)
	var plane := float(variant.get("plane", row.get("plane", 0.0)))
	var actual := _mesh_plane_segments(mesh, axis, plane)
	var expected := _canonical_plane_segments(snapshot, roi, axis, plane, int(row.seed))
	var missing: Array[String] = []
	var extra: Array[String] = []
	for key in expected.keys():
		if not actual.has(key): missing.append(String(key))
	for key in actual.keys():
		if not expected.has(key): extra.append(String(key))
	return {"axis": axis_name, "plane": plane, "variant": variant.get("id", "default"),
		"candidate_segment_count": actual.size(), "sampled_field_reference_segment_count": expected.size(),
		"missing_segment_count": missing.size(), "extra_segment_count": extra.size(),
		"missing_segments_first_16": missing.slice(0, 16), "extra_segments_first_16": extra.slice(0, 16),
		"reference": "independent piecewise-linear contour on the frozen canonical sampled field; not a product tolerance"}

func _mesh_plane_segments(mesh: Dictionary, axis: int, plane: float) -> Dictionary:
	var output: Dictionary = {}
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	for i in range(0, positions.size(), 3):
		var triangle: Array[Vector3] = [positions[i], positions[i + 1], positions[i + 2]]
		var hits: Array[Vector3] = []
		for edge in [Vector2i(0,1), Vector2i(1,2), Vector2i(2,0)]:
			var a: Vector3 = triangle[edge.x]
			var b: Vector3 = triangle[edge.y]
			var da := a[axis] - plane
			var db := b[axis] - plane
			if absf(da) < 1.0e-6: hits.append(a)
			if da * db < -1.0e-12: hits.append(a.lerp(b, da / (da - db)))
		var unique: Array[Vector3] = []
		for point in hits:
			var duplicate := false
			for old in unique:
				if point.distance_squared_to(old) < 1.0e-10: duplicate = true; break
			if not duplicate: unique.append(point)
		if unique.size() >= 2 and unique[0].distance_squared_to(unique[1]) > 1.0e-12:
			var ka := Core._point_key(unique[0])
			var kb := Core._point_key(unique[1])
			output[ka + "|" + kb if ka < kb else kb + "|" + ka] = true
	return output

func _canonical_plane_segments(snapshot: Dictionary, roi: Dictionary, axis: int, plane: float, seed: int) -> Dictionary:
	var origin := Core.world_min(roi)
	var cells := Core.cell_counts(roi)
	var h := Core.step(roi)
	var plane_index := roundi((plane - origin[axis]) / h)
	if plane_index < 0 or plane_index > cells[axis] or absf(origin[axis] + float(plane_index) * h - plane) > 1.0e-5:
		return {}
	var other_axes: Array[int] = [0, 1, 2]
	other_axes.erase(axis)
	var counts := Vector2i(cells[other_axes[0]], cells[other_axes[1]])
	var output: Dictionary = {}
	for u in range(counts.x):
		for v in range(counts.y):
			var points: Array[Vector3] = []
			for corner in [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(0,1)]:
				var grid := Vector3i.ZERO
				grid[axis] = plane_index
				grid[other_axes[0]] = u + corner.x
				grid[other_axes[1]] = v + corner.y
				points.append(origin + Vector3(grid) * h)
			for tri in [[0,1,2], [0,2,3]]:
				var hits: Array[Vector3] = []
				for edge in [Vector2i(0,1), Vector2i(1,2), Vector2i(2,0)]:
					var pa: Vector3 = points[int(tri[edge.x])]
					var pb: Vector3 = points[int(tri[edge.y])]
					var da := Core.sample(pa, snapshot, seed)
					var db := Core.sample(pb, snapshot, seed)
					if da == 0.0:
						hits.append(pa)
					elif db == 0.0:
						hits.append(pb)
					elif (da < 0.0) != (db < 0.0):
						hits.append(pa.lerp(pb, da / (da - db)))
				var unique: Array[Vector3] = []
				for point in hits:
					var duplicate := false
					for old in unique:
						if point.distance_squared_to(old) < 1.0e-10: duplicate = true; break
					if not duplicate: unique.append(point)
				if unique.size() == 2:
					var ka := Core._point_key(unique[0])
					var kb := Core._point_key(unique[1])
					output[ka + "|" + kb if ka < kb else kb + "|" + ka] = true
	return output

func _emit(event: Dictionary) -> void:
	print("P3_1_R9_2_JSONL " + JSON.stringify(event))
