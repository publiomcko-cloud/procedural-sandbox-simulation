extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateScript := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const CANDIDATE_ID := "D"
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
		var scope: Dictionary = Core.candidate_scope(row, CANDIDATE_ID)
		if not scope.get("valid", false):
			_emit_result(row, variant, case_id, start_event, case_start, "FAIL", "FAILED_INVALID_CANDIDATE_SCOPE", "NOT_ASSESSED", "PARTIAL",
				{"reason": scope.get("reason", "candidate_scope_invalid")}, [])
			continue
		if not scope.get("in_scope", false):
			_emit_result(row, variant, case_id, start_event, case_start, "NOT_RUN", "NOT_APPLICABLE_OTHER_CANDIDATES", "NOT_ASSESSED", "NONE",
				{"reason": "manifest_candidate_scope_excludes_candidate", "candidate_scope": row.get("candidate_scope", [])}, [])
			continue
		var counts: Dictionary = Core.iteration_counts(row, variant)
		if not counts.get("valid", false):
			_emit_result(row, variant, case_id, start_event, case_start, "FAIL", "FAILED_INVALID_REPETITION_CONTRACT", "NOT_ASSESSED", "PARTIAL",
				{"reason": counts.get("reason", "iteration_contract_invalid")}, [])
			continue
		var hooks: Array = Core.diagnostic_hooks(String(row.get("kind", "")))
		if hooks.is_empty():
			_emit_result(row, variant, case_id, start_event, case_start, "FAIL", "FAILED_UNSUPPORTED_SCENARIO_KIND", "NOT_ASSESSED", "PARTIAL",
				{"reason": "scenario_kind_has_no_registered_diagnostic_hooks", "kind": row.get("kind", "")}, [])
			continue
		if "canonical_sampled_cave_connectivity" in hooks:
			var cave_times: Array[int] = []
			var cave_values: Array[Dictionary] = []
			var cave_failed := false
			for sample_index in range(counts.repeats):
				if Time.get_ticks_usec() - _campaign_started_usec >= Core.MAX_CANDIDATE_USEC:
					cave_failed = true; _hard_stop = true; break
				var sample_start := Time.get_ticks_usec()
				var cave_setup: Dictionary = Core.make_snapshot(row)
				if not cave_setup.get("valid", false):
					cave_values.append({"valid": false, "reason": cave_setup.get("reason", "snapshot_invalid")})
				else:
					cave_values.append(Core.sampled_cave_connectivity(variant.get("roi", row.get("roi", {})), cave_setup.snapshot, int(row.seed)))
				var cave_elapsed := Time.get_ticks_usec() - sample_start
				cave_times.append(cave_elapsed)
				if cave_elapsed > Core.MAX_SCENARIO_USEC:
					cave_failed = true; break
			var cave_valid := not cave_values.is_empty()
			for cave_value in cave_values:
				cave_valid = cave_valid and bool(cave_value.get("valid", false))
			var cave_summary: Array[Dictionary] = []
			for cave_value in cave_values:
				cave_summary.append(_connectivity_summary(cave_value))
			var cave_status := "CENSORED" if cave_failed else ("COMPLETE" if cave_valid else "FAIL")
			_emit_result(row, variant, case_id, start_event, case_start, cave_status,
				"SHARED_CANONICAL_REFERENCE_ONLY", "DIAGNOSTIC_ONLY", "COMPLETE" if cave_valid and not cave_failed else "PARTIAL",
				{"sampled_connectivity": cave_summary, "requested_warmups": counts.warmups, "requested_repeats": counts.repeats,
				"warmup_samples_usec": [], "repeat_attempt_count": cave_times.size(), "successful_repeat_count": cave_values.size()}, cave_times)
			continue
		var setup: Dictionary = Core.make_snapshot(row)
		if not setup.get("valid", false):
			_emit_result(row, variant, case_id, start_event, case_start, "FAIL", "FAILED", "NOT_ASSESSED", "PARTIAL",
				{"reason": setup.get("reason", "snapshot_invalid"), "requested_warmups": counts.warmups, "requested_repeats": counts.repeats}, [])
			continue
		var roi: Dictionary = variant.get("roi", {})
		if not Core.validate_roi(roi).get("valid", false):
			_emit_result(row, variant, case_id, start_event, case_start, "FAIL", "FAILED", "NOT_ASSESSED", "PARTIAL",
				{"reason": "roi_rejected_by_shared_contract", "requested_warmups": counts.warmups, "requested_repeats": counts.repeats}, [])
			continue
		_candidate.call("configure_roi", roi)
		var warmup_samples: Array[int] = []
		var sample_times: Array[int] = []
		var sample_hashes: Array[String] = []
		var build_metrics: Array[Dictionary] = []
		var successful_repeat_count := 0
		var mesh: Dictionary = {}
		var mesh_available := false
		var primary_metrics: Dictionary = {}
		var failed := false
		var failure_reason := ""
		var failure_status := "FAIL"
		for warmup_index in range(counts.warmups):
			if Time.get_ticks_usec() - _campaign_started_usec >= Core.MAX_CANDIDATE_USEC:
				failed = true; failure_reason = "candidate_aggregate_runtime_stop_loss"; failure_status = "CENSORED"; _hard_stop = true; break
			var warm_start := Time.get_ticks_usec()
			var warm_value: Variant = _candidate.call("build", setup.snapshot, row, variant)
			var warm_usec := Time.get_ticks_usec() - warm_start
			warmup_samples.append(warm_usec)
			if typeof(warm_value) != TYPE_DICTIONARY or not warm_value.get("valid", false):
				failure_reason = String(warm_value.get("reason", "candidate_warmup_failed")) if typeof(warm_value) == TYPE_DICTIONARY else "candidate_warmup_result_not_dictionary"
				failure_status = "CENSORED" if _is_stop_loss(failure_reason) or warm_usec > Core.MAX_SCENARIO_USEC else "FAIL"
				failed = true; break
			var warm_result: Dictionary = warm_value
			if typeof(warm_result.get("mesh", null)) == TYPE_DICTIONARY and not mesh_available:
				mesh = warm_result.mesh; primary_metrics = warm_result.get("metrics", {}); mesh_available = true
			if warm_usec > Core.MAX_SCENARIO_USEC:
				failure_reason = "per_scenario_warmup_time_stop_loss"; failure_status = "CENSORED"; failed = true; break
		var repeat_index := 0
		while repeat_index < counts.repeats and not failed:
			if Time.get_ticks_usec() - _campaign_started_usec >= Core.MAX_CANDIDATE_USEC:
				failed = true; failure_reason = "candidate_aggregate_runtime_stop_loss"; failure_status = "CENSORED"; _hard_stop = true; break
			var repeat_start := Time.get_ticks_usec()
			var repeat_value: Variant = _candidate.call("build", setup.snapshot, row, variant)
			var elapsed := Time.get_ticks_usec() - repeat_start
			if typeof(repeat_value) != TYPE_DICTIONARY or not repeat_value.get("valid", false):
				sample_times.append(elapsed); sample_hashes.append("")
				failure_reason = String(repeat_value.get("reason", "candidate_repeat_failed")) if typeof(repeat_value) == TYPE_DICTIONARY else "candidate_repeat_result_not_dictionary"
				failure_status = "CENSORED" if _is_stop_loss(failure_reason) or elapsed > Core.MAX_SCENARIO_USEC else "FAIL"
				failed = true; break
			var repeat_build: Dictionary = repeat_value
			sample_times.append(elapsed); sample_hashes.append(String(repeat_build.get("mesh_sha256", "")))
			successful_repeat_count += 1
			build_metrics.append(repeat_build.get("metrics", {}))
			if not mesh_available and typeof(repeat_build.get("mesh", null)) == TYPE_DICTIONARY:
				mesh = repeat_build.mesh; primary_metrics = repeat_build.get("metrics", {}); mesh_available = true
			if elapsed > Core.MAX_SCENARIO_USEC:
				failure_reason = "per_scenario_repetition_time_stop_loss"; failure_status = "CENSORED"; failed = true; break
			repeat_index += 1
		if not mesh_available:
			_emit_result(row, variant, case_id, start_event, case_start, failure_status if failed else "FAIL",
				"EXECUTED_BUT_NO_MESH", "NOT_ASSESSED", "PARTIAL",
				{"reason": failure_reason if not failure_reason.is_empty() else "candidate_returned_no_mesh",
				"requested_warmups": counts.warmups, "requested_repeats": counts.repeats,
				"warmup_samples_usec": warmup_samples, "build_samples_usec": sample_times,
				"repeat_attempt_count": sample_times.size(), "successful_repeat_count": successful_repeat_count}, sample_times)
			continue
		var topo: Dictionary = Core.topology(mesh, Core.world_min(roi), Core.world_min(roi) + Vector3(Core.cell_counts(roi)) * Core.step(roi))
		var residual: Dictionary = Core.surface_residual(mesh, setup.snapshot, int(row.seed))
		var normals: Dictionary = Core.normal_deviation(mesh, setup.snapshot, int(row.seed))
		var components: Dictionary = Core.mesh_components(mesh)
		var diagnostics: Dictionary = {"topology": _topology_summary(topo), "surface_residual": residual,
			"normal_deviation": normals, "mesh_components": components, "candidate_metrics": primary_metrics,
			"requested_warmups": counts.warmups, "requested_repeats": counts.repeats,
			"warmup_samples_usec": warmup_samples, "warmup_usec_total": _sum_ints(warmup_samples),
			"build_samples_usec": sample_times, "repeat_attempt_count": sample_times.size(),
			"successful_repeat_count": successful_repeat_count,
			"build_sample_sha256": sample_hashes, "deterministic_hash_match": _all_hashes_match(sample_hashes),
			"determinism_scope": "same process and identical input; not independent process reconstruction",
			"candidate_metric_samples": build_metrics, "memory_scope": "external process-tree peak only; not per-scenario RSS"}
		var kind := String(row.get("kind", ""))
		var capability := _capability_status(row, variant)
		if "single_roi_contour_proxy_not_chunk_join" in hooks:
			diagnostics["seam_contour"] = _seam_diagnostic(mesh, setup.snapshot, roi, row, variant)
			diagnostics["seam_scope"] = "single ROI contour proxy; independent neighboring chunk join not performed"
		if "canonical_cpu_mesh_ray_proxy_not_production_picker" in hooks:
			var rays: Array[Dictionary] = Core.ray_grid(roi, row.ray_grid)
			diagnostics["ray_picker"] = _ray_summary(Core.compare_mesh_rays(rays, mesh, setup.snapshot, int(row.seed)))
		if "canonical_and_mesh_ray_proxy" in hooks:
			diagnostics["historical_mesh_ray"] = _historical_ray_diagnostic(mesh, setup.snapshot, row)
		if "offline_cpu_two_sided_triangle_proxy" in hooks:
			var proxy_rays: Array[Dictionary] = _proxy_rays(row)
			diagnostics["two_sided_cpu_proxy"] = _ray_summary(Core.compare_mesh_rays(proxy_rays, mesh, setup.snapshot, int(row.seed)))
			diagnostics["physics_server"] = "NOT_RUN"
		if "local_cell_corner_probe_only" in hooks:
			diagnostics["triangle_root_observation"] = _triangle_root_observation(mesh, setup.snapshot, roi, row)
		if "same_process_repeats_only" in hooks:
			diagnostics["rebuild_hashes"] = sample_hashes
		if "full_snapshot_rebuild_only_no_per_edit_update" in hooks:
			diagnostics["edit_to_candidate_mesh_usec"] = sample_times
			diagnostics["edit_path_scope"] = "one full frozen four-command snapshot build per measured repetition; no per-edit acceptance or incremental mesh publication"
		if "single_roi_build_only_no_independent_chunk_pair" in hooks:
			diagnostics["independent_chunk_pair"] = "NOT_IMPLEMENTED_SINGLE_ROI_BUILD"
		if "mesh_components_only_cave_connectivity_unimplemented" in hooks:
			diagnostics["extracted_mesh_cave_connectivity"] = "NOT_IMPLEMENTED; triangle connectivity does not establish empty-space cave connectivity"
		if "candidate_reported_serialization_only_process_memory_external" in hooks:
			diagnostics["serialization_observation"] = {"candidate_metrics": primary_metrics,
				"serialized_bytes": _find_metric(primary_metrics, "serialized_bytes"),
				"process_memory": "available only as campaign process-tree peak in external evidence"}
		if CANDIDATE_ID == "D" and "actual_fresh_reader_corruption_reload" in hooks:
			var corruption: Dictionary = _candidate.call("corruption_reload_probe", setup.snapshot)
			diagnostics["corruption_reload"] = corruption
			if not corruption.get("valid", false) or not corruption.get("rejected", false):
				failed = true; failure_status = "FAIL"; failure_reason = "materialized_volume_corruption_not_rejected_by_fresh_reader"
		if CANDIDATE_ID == "A" and kind == "mixed_lod_boundary":
			diagnostics["candidate_a_mixed_lod"] = {"local_face_probe": _candidate.call("_xplus_shared_face_probe", setup.snapshot),
				"complete_chunk_pair": _candidate.call("_build_xplus_chunk_pair", setup.snapshot)}
		var quality := _quality_status(topo)
		if kind == "memory_disk_serialization" and CANDIDATE_ID != "D":
			capability = "NOT_IMPLEMENTED_SERIALIZED_CACHE_OR_VOLUME"
		var partial_capabilities := ["SINGLE_ROI_CONTOUR_PROXY_NOT_CHUNK_JOIN", "NOT_IMPLEMENTED_INDEPENDENT_CHUNK_PAIR",
			"FULL_SNAPSHOT_REBUILD_ONLY_NO_PER_EDIT_UPDATE", "SAME_PROCESS_REPEATS_ONLY", "LOCAL_CELL_CORNER_PROBE_ONLY",
			"MESH_COMPONENTS_ONLY_CAVE_CONNECTIVITY_NOT_IMPLEMENTED", "CANONICAL_CPU_MESH_RAY_PROXY_NOT_PRODUCTION_PICKER",
			"OFFLINE_CPU_TWO_SIDED_TRIANGLE_PROXY", "NOT_IMPLEMENTED_SERIALIZED_CACHE_OR_VOLUME",
			"CANDIDATE_REPORTED_SERIALIZATION_ONLY_PROCESS_MEMORY_EXTERNAL"]
		var evidence := "PARTIAL" if failed or not residual.get("valid", false) or not normals.get("valid", false) or partial_capabilities.has(capability) else "COMPLETE"
		var execution := failure_status if failed else "COMPLETE"
		if failed:
			diagnostics["failure_reason"] = failure_reason
		_emit_result(row, variant, case_id, start_event, case_start, execution, capability, quality, evidence, diagnostics, sample_times)

func _sum_ints(values: Array[int]) -> int:
	var total := 0
	for value in values: total += value
	return total

func _find_metric(metrics: Variant, key: String) -> Variant:
	if typeof(metrics) != TYPE_DICTIONARY:
		return null
	if metrics.has(key): return metrics[key]
	for child in metrics.values():
		var found: Variant = _find_metric(child, key)
		if found != null: return found
	return null

func _historical_ray_diagnostic(mesh: Dictionary, snapshot: Dictionary, row: Dictionary) -> Dictionary:
	var ray: Dictionary = row.get("ray", {})
	var origin_values: Array = ray.get("origin", [])
	var direction_values: Array = ray.get("direction", [])
	if origin_values.size() != 3 or direction_values.size() != 3:
		return {"valid": false, "reason": "historical_ray_definition_invalid"}
	var rays: Array[Dictionary] = [{"origin": Vector3(origin_values[0], origin_values[1], origin_values[2]),
		"direction": Vector3(direction_values[0], direction_values[1], direction_values[2]), "length": float(ray.get("length", 12.0))}]
	return _ray_summary(Core.compare_mesh_rays(rays, mesh, snapshot, int(row.seed)))

func _emit_result(row: Dictionary, variant: Dictionary, case_id: String, start_event: String, started_usec: int,
		execution_status: String, capability_status: String, geometry_status: String, evidence_status: String,
		diagnostics: Dictionary, samples_usec: Array) -> void:
	var completed_usec := Time.get_ticks_usec()
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
		"scenario_end_usec": completed_usec, "monotonic_usec": completed_usec, "duration_usec": completed_usec - started_usec,
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
	if kind == "neighboring_chunks": return "NOT_IMPLEMENTED_INDEPENDENT_CHUNK_PAIR"
	if kind in ["equal_resolution_boundary", "mixed_lod_boundary", "negative_coordinate_region_boundaries", "historical_xplus_interface"]:
		return "SINGLE_ROI_CONTOUR_PROXY_NOT_CHUNK_JOIN"
	if kind == "historical_xminus_displacement": return "CANONICAL_CPU_MESH_RAY_PROXY_NOT_PRODUCTION_PICKER"
	if kind == "historical_triangle_root": return "LOCAL_CELL_CORNER_PROBE_ONLY"
	if kind == "sampled_cave_connectivity": return "SHARED_CANONICAL_REFERENCE_ONLY"
	if kind == "extracted_mesh_cave_connectivity": return "MESH_COMPONENTS_ONLY_CAVE_CONNECTIVITY_NOT_IMPLEMENTED"
	if kind == "ray_picker_parity": return "CANONICAL_CPU_MESH_RAY_PROXY_NOT_PRODUCTION_PICKER"
	if kind == "cpu_two_sided_triangle_proxy": return "OFFLINE_CPU_TWO_SIDED_TRIANGLE_PROXY"
	if kind == "local_edit_to_mesh_rebuild": return "FULL_SNAPSHOT_REBUILD_ONLY_NO_PER_EDIT_UPDATE"
	if kind == "deterministic_mesh_reconstruction": return "SAME_PROCESS_REPEATS_ONLY"
	if kind == "memory_disk_serialization": return "CANDIDATE_REPORTED_SERIALIZATION_ONLY_PROCESS_MEMORY_EXTERNAL"
	if kind == "materialized_volume_corrupt_reload": return "ACTUAL_FRESH_READER_CORRUPTION_RELOAD" if CANDIDATE_ID == "D" else "NOT_APPLICABLE_OTHER_CANDIDATES"
	return "EXECUTED_CANDIDATE_PATH"

func _quality_status(topology: Dictionary) -> String:
	if int(topology.get("internal_open_edges", 0)) > 0 or int(topology.get("nonmanifold_edges", 0)) > 0 or \
		int(topology.get("degenerate_triangles", 0)) > 0 or int(topology.get("winding_inconsistencies", 0)) > 0:
		return "TOPOLOGY_DEFECT_RECORDED"
	return "NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE"

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
