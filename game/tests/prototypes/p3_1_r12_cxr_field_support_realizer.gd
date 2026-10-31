extends "res://tests/prototypes/p3_1_r12_cx_micropatch_realizer.gd"

const CXR_CUTOFF_SQUARED: float = 1.0e-12
const CXR_MAX_CAVITY_LEVEL: int = 3
const CXR_MAX_CAVITIES: int = 3
const CXR_MAX_PATCH_TRIANGLES: int = 64
const CXR_MAX_CANDIDATE_ATTEMPTS_PER_CAVITY: int = 8192
const CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY: int = 256
const CXR_MAX_SELECTED_SUPPORTS: int = 4
const CXR_MAX_CANDIDATE_TRIANGLES_PER_CAVITY: int = 2048
const CXR_MAX_SEARCH_STATES_PER_CAVITY: int = 16384
const CXR_MAX_SEARCH_STATES_TOTAL: int = 32768
const CXR_MAX_RETAINED_SOLUTIONS: int = 32
const CXR_MAX_SEARCH_USEC_PER_CAVITY: int = 10000000
const CXR_MAX_SEARCH_USEC_TOTAL: int = 20000000
const CXR_MAX_REALIZE_USEC: int = 30000000
const CXR_BARYCENTRIC_EPSILON: float = 1.0e-7
const CXR_FIELD_RESIDUAL_EPSILON: float = 1.0e-7
const CXR_MAX_SUPPORT_DISTANCE: float = 0.5

var _cxr_search_started_usec: int = 0
var _cxr_cavity_started_usec: int = 0
var _cxr_search_nodes_total: int = 0
var _cxr_candidate_attempts_total: int = 0
var _cxr_candidate_triangles_total: int = 0
var _cxr_candidate_triangles_cavity: int = 0
var _cxr_branch_counts: Dictionary = {}
var _cxr_prune_counts: Dictionary = {}
var _cxr_active_cavity_branches: Dictionary = {}
var _cxr_active_cavity_prunes: Dictionary = {}
var _cxr_local_search_marker_emitted: bool = false
var _cxr_allowed_support_ids: Dictionary = {}

func realize_cxr(graph: Dictionary, values: PackedFloat32Array, roi: Dictionary, expected_topology_sha: String, expected_graph_fingerprint_sha: String, residual_fixture: Dictionary, snapshot: Dictionary) -> Dictionary:
	var began_usec: int = Time.get_ticks_usec()
	_cxr_local_search_marker_emitted = false
	_cxr_allowed_support_ids.clear()
	var base: Dictionary = super.realize(graph, values, roi, expected_topology_sha, expected_graph_fingerprint_sha)
	if not bool(base.get("valid", false)):
		return {"valid": false, "cx_algorithm_started": false, "reason": "cxr_c6_base_realizer_invalid", "details": base}
	var fixture_error: String = _validate_residual_fixture(residual_fixture, base)
	if not fixture_error.is_empty():
		return {"valid": false, "cx_algorithm_started": false, "reason": fixture_error, "details": {"expected_fixture_sha256": EXPECTED_RESIDUAL_FIXTURE_SHA}}
	var built: Dictionary = _build_triangles(base, residual_fixture)
	if not bool(built.get("valid", false)):
		return {"valid": false, "cx_algorithm_started": false, "reason": "cxr_c6_triangle_reconstruction_failed", "details": built}
	var triangles: Array[Dictionary] = built.triangles
	_root_positions = built.root_positions
	var accepted_c6: Array[Dictionary] = _accepted_triangle_rows(triangles)
	if _mesh_sha(_mesh_from_triangles(accepted_c6)) != EXPECTED_C6_MESH_SHA or String(base.get("mesh_sha256", "")) != EXPECTED_C6_MESH_SHA:
		return {"valid": false, "cx_algorithm_started": false, "reason": "cxr_reconstructed_c6_mesh_hash_mismatch", "expected": EXPECTED_C6_MESH_SHA, "reconstructed": _mesh_sha(_mesh_from_triangles(accepted_c6)), "realizer": base.get("mesh_sha256", "")}
	var residual_rows: Array = residual_fixture.get("residuals", [])
	if residual_rows.size() != 3 or base.get("cutoff_rejections", []).size() != 3:
		return {"valid": false, "cx_algorithm_started": false, "reason": "cxr_residual_count_mismatch", "fixture_count": residual_rows.size(), "c6_count": base.get("cutoff_rejections", []).size()}
	_required_arc_keys.clear()
	for arc_value in base.get("arc_map", []):
		var arc: Dictionary = arc_value
		var arc_ids: Array = arc.get("root_ids", [])
		if arc_ids.size() == 2:
			_required_arc_keys[_edge_key(String(arc_ids[0]), String(arc_ids[1]))] = true
	_locked_triplets = _derive_locked_triplets(base.get("applied_flips", []), _root_positions)
	var adjacency: Dictionary = _adjacency(triangles)
	_orient_rejected_triangles(triangles, adjacency)
	var original_triangles: Array[Dictionary] = triangles.duplicate(true)
	var groups: Array[Array] = _overlapping_defect_groups(residual_rows, adjacency)
	if groups.is_empty() or groups.size() > CXR_MAX_CAVITIES:
		return {"valid": false, "cx_algorithm_started": false, "reason": "cxr_cavity_set_invalid", "cavity_count": groups.size(), "cap": CXR_MAX_CAVITIES}
	_cxr_search_started_usec = Time.get_ticks_usec()
	_cxr_search_nodes_total = 0
	_cxr_candidate_attempts_total = 0
	_cxr_candidate_triangles_total = 0
	_cxr_branch_counts.clear()
	_cxr_prune_counts.clear()
	var cavity_results: Array[Dictionary] = []
	var patch_records: Array[Dictionary] = []
	var used_patch_ids: Dictionary = {}
	var search_started: bool = false
	for cavity_index in range(groups.size()):
		var cavity_ids: Array = groups[cavity_index]
		var cavity_result: Dictionary = _search_cxr_cavity(cavity_ids, triangles, adjacency, residual_fixture, values, roi)
		cavity_results.append(cavity_result)
		if not bool(cavity_result.get("valid", false)):
			var partial: bool = not bool(cavity_result.get("search_complete", false)) or String(cavity_result.get("terminal_reason", "")).contains("limit")
			var failure_reason: String = "cxr_search_partial" if partial else "cxr_no_valid_field_support_solution"
			return {"valid": false, "cx_algorithm_started": search_started or bool(cavity_result.get("search_started", false)), "reason": "cx_bounded_patch_search_failed", "details": {"search": {"reason": failure_reason, "complete": bool(cavity_result.get("search_complete", false)), "search_exhaustive": bool(cavity_result.get("search_exhaustive", false)), "nodes": _cxr_search_nodes_total, "candidate_attempts": _cxr_candidate_attempts_total, "candidate_triangles": _cxr_candidate_triangles_total, "cavity_nodes": cavity_result.get("search_nodes", "UNKNOWN_NOT_CAPTURED"), "terminal_reason": cavity_result.get("terminal_reason", "UNKNOWN_NOT_CAPTURED")}, "cxr_cavity_results": cavity_results, "cxr_limits": _cxr_limits(), "cxr_search_counters": _cxr_counters()}}
		search_started = search_started or bool(cavity_result.get("search_started", false))
		for triangle_id in cavity_result.get("patch_triangle_ids", []):
			if used_patch_ids.has(String(triangle_id)):
				return {"valid": false, "cx_algorithm_started": true, "reason": "cx_bounded_patch_search_failed", "details": {"search": {"reason": "cxr_patch_overlap", "complete": true}, "cxr_cavity_results": cavity_results, "overlap_triangle_id": triangle_id, "cxr_limits": _cxr_limits()}}
			used_patch_ids[String(triangle_id)] = true
		patch_records.append(cavity_result.get("patch_record", {}))
		var replacement: Array[Dictionary] = cavity_result.get("replacement_triangles", [])
		var patch_id_map: Dictionary = {}
		for triangle_id in cavity_result.get("patch_triangle_ids", []): patch_id_map[String(triangle_id)] = true
		var updated: Array[Dictionary] = []
		for triangle in triangles:
			if not patch_id_map.has(String(triangle.get("triangle_id", ""))): updated.append(triangle)
		updated.append_array(replacement)
		triangles = updated
	var validation: Dictionary = _validate_final_mesh(triangles, original_triangles, patch_records, base, roi, snapshot)
	if not bool(validation.get("valid", false)):
		return {"valid": false, "cx_algorithm_started": true, "reason": "cx_bounded_patch_search_failed", "details": {"search": {"reason": "cxr_final_mesh_validation_failed", "complete": true}, "validation": validation, "cxr_cavity_results": cavity_results, "cxr_limits": _cxr_limits(), "cxr_search_counters": _cxr_counters()}}
	var rebuilt_mesh: Dictionary = _mesh_from_triangles(triangles)
	var bounds_min: Vector3 = Core.world_min(roi)
	var bounds_max: Vector3 = bounds_min + Vector3(Core.cell_counts(roi)) * Core.step(roi)
	var topology: Dictionary = Core.topology(rebuilt_mesh, bounds_min, bounds_max)
	var c6_paths: Dictionary = _validate_c6_paths(triangles, base.get("applied_flips", []))
	var obligations: Dictionary = _validate_required_arcs(triangles, base.get("arc_map", []), base.get("applied_flips", []))
	var root_integrity: bool = _root_coordinates_unchanged(original_triangles, triangles, _root_positions)
	var cutoff_rows: Array[Dictionary] = _cutoff_rows(triangles)
	var topology_roundtrip: bool = bool(base.get("topology_signature_match", false)) and bool(base.get("topology_roundtrip_sha256", "") != "")
	var topology_complete: bool = topology_roundtrip and cutoff_rows.is_empty() and int(obligations.get("missing", -1)) == 0 and int(obligations.get("nonmanifold", -1)) == 0 and bool(c6_paths.get("valid", false))
	var mesh_complete: bool = topology_complete and int(topology.get("internal_open_edges", -1)) == 0 and int(topology.get("nonmanifold_edges", -1)) == 0 and int(topology.get("winding_inconsistencies", -1)) == 0 and int(topology.get("degenerate_triangles", -1)) == 0 and float(_minimum_cross_squared(triangles)) > CXR_CUTOFF_SQUARED
	var selected_supports: Array[Dictionary] = []
	for cavity in cavity_results:
		for support_value in cavity.get("selected_supports", []):
			var support: Dictionary = support_value
			selected_supports.append(support)
			_cxr_allowed_support_ids[String(support.get("support_id", ""))] = true
	var support_json: String = JSON.stringify(selected_supports)
	base["hypothesis"] = "R12_CXR_FIELD_CONSTRAINED_SUPPORT_MICRO_PATCH"
	base["mesh"] = rebuilt_mesh
	base["mesh_sha256"] = _mesh_sha(rebuilt_mesh)
	base["mesh_topology"] = topology
	base["emitted_triangles"] = _emitted_rows(triangles)
	base["cutoff_rejections"] = cutoff_rows
	base["required_adjacency_missing_count"] = int(obligations.get("missing", -1))
	base["required_adjacency_nonmanifold_count"] = int(obligations.get("nonmanifold", -1))
	base["required_adjacency_obligations"] = obligations.get("rows", [])
	base["required_topology_complete"] = topology_complete
	base["geometry_realization_complete"] = mesh_complete
	base["winding_valid"] = int(topology.get("winding_inconsistencies", -1)) == 0
	base["cx_patch_records"] = patch_records
	base["cxr_residual_fixture_sha256"] = EXPECTED_RESIDUAL_FIXTURE_SHA
	base["cxr_local_search_limits"] = _cxr_limits()
	base["cxr_local_search_nodes"] = _cxr_search_nodes_total
	base["cxr_local_search_complete"] = true
	base["cxr_local_search_exhaustive"] = false
	base["cxr_search_counters"] = _cxr_counters()
	base["cxr_candidate_attempt_count"] = _cxr_candidate_attempts_total
	base["cxr_candidate_triangle_count"] = _cxr_candidate_triangles_total
	base["cxr_cavity_results"] = cavity_results
	base["cx_support_vertex_count"] = selected_supports.size()
	base["cx_support_candidate_count"] = _total_candidate_count(cavity_results)
	base["cx_support_provenance"] = selected_supports
	base["cx_support_provenance_sha256"] = Core.sha256(support_json.to_utf8_buffer())
	base["cx_changed_triangle_ids"] = _changed_triangle_ids(original_triangles, triangles)
	base["cx_triangle_count"] = triangles.size()
	base["geometry_triangle_count"] = triangles.size()
	base["geometry_vertex_count"] = _unique_vertex_count(triangles)
	base["cx_field_diagnostics"] = _field_diagnostics(patch_records, snapshot)
	base["cx_preserved_c6_paths"] = c6_paths
	base["cx_preserved_topology_arcs"] = obligations
	base["cx_root_coordinates_unchanged"] = root_integrity
	base["cx_build_usec"] = Time.get_ticks_usec() - began_usec
	base["geometry_complete"] = mesh_complete and root_integrity and base.cx_build_usec <= CXR_MAX_REALIZE_USEC
	base["topology_signature_match"] = topology_complete
	base["minimum_cross_squared"] = _minimum_cross_squared(triangles)
	if base.cx_build_usec > CXR_MAX_REALIZE_USEC:
		base["geometry_complete"] = false
		base["realizer_failure_reason"] = "cxr_realize_time_limit"
	return base

func _search_cxr_cavity(cavity_ids: Array, all_triangles: Array[Dictionary], adjacency: Dictionary, residual_fixture: Dictionary, values: PackedFloat32Array, roi: Dictionary) -> Dictionary:
	_cxr_cavity_started_usec = Time.get_ticks_usec()
	_cxr_candidate_triangles_cavity = 0
	_cxr_active_cavity_branches = {}
	_cxr_active_cavity_prunes = {}
	var sorted_cavity_ids: Array = cavity_ids.duplicate()
	sorted_cavity_ids.sort()
	var residual_by_id: Dictionary = {}
	for row_value in residual_fixture.get("residuals", []):
		var row: Dictionary = row_value
		residual_by_id[String(row.get("triangle_id", ""))] = row
	var residual_triangles: Array[Dictionary] = []
	for triangle in all_triangles:
		if sorted_cavity_ids.has(String(triangle.get("triangle_id", ""))):
			residual_triangles.append(triangle)
	residual_triangles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.triangle_id) < String(b.triangle_id))
	if residual_triangles.is_empty():
		return {"valid": false, "search_started": false, "terminal_reason": "residual_cavity_faces_missing", "search_complete": true, "search_exhaustive": true}
	if residual_triangles.size() > CXR_MAX_SELECTED_SUPPORTS:
		return {"valid": false, "search_started": false, "terminal_reason": "selected_support_cap_insufficient", "search_complete": true, "search_exhaustive": true}
	var cavity_id: String = Core.sha256(JSON.stringify(sorted_cavity_ids).to_utf8_buffer()).substr(0, 16)
	var cavity_report: Dictionary = {"cavity_id": cavity_id, "residual_triangle_ids": sorted_cavity_ids.duplicate(), "levels": [], "candidate_attempts": [], "support_candidates": [], "support_candidates_retained": [], "fan_evaluations": [], "candidate_triangles": [], "selected_supports": [], "search_nodes": 0, "branches": _cxr_active_cavity_branches, "prunes": _cxr_active_cavity_prunes, "limits_hit": [], "search_complete": false, "search_exhaustive": false, "terminal_reason": "UNKNOWN_NOT_CAPTURED"}
	var search_started: bool = false
	var candidates_per_residual: Dictionary = {}
	var max_candidates_per_face: int = maxi(1, int(floor(float(CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY) / float(residual_triangles.size()))))
	for level in range(CXR_MAX_CAVITY_LEVEL + 1):
		var patch_id_map: Dictionary = {}
		for seed_id in sorted_cavity_ids:
			for triangle_id in _radius_ids(String(seed_id), adjacency, level):
				patch_id_map[String(triangle_id)] = true
		if patch_id_map.size() > CXR_MAX_PATCH_TRIANGLES:
			cavity_report.levels.append({"level": level, "source_triangle_count": patch_id_map.size(), "terminal_reason": "source_triangle_cap"})
			cavity_report.limits_hit.append("MAX_PATCH_TRIANGLES")
			cavity_report.terminal_reason = "limit_max_patch_triangles"
			return {"valid": false, "search_started": search_started, "search_complete": false, "search_exhaustive": false, "terminal_reason": cavity_report.terminal_reason, "cavity_report": cavity_report}
		var patch: Array[Dictionary] = []
		var patch_ids: Array = _sorted_keys(patch_id_map)
		for triangle in all_triangles:
			if patch_id_map.has(String(triangle.get("triangle_id", ""))):
				patch.append(triangle)
		var boundary_before: Dictionary = _boundary_state(patch)
		if not bool(boundary_before.get("valid", false)):
			cavity_report.levels.append({"level": level, "source_triangle_count": patch.size(), "terminal_reason": "patch_boundary_invalid", "boundary": boundary_before})
			cavity_report.terminal_reason = "patch_boundary_invalid"
			return {"valid": false, "search_started": search_started, "search_complete": false, "search_exhaustive": false, "terminal_reason": cavity_report.terminal_reason, "cavity_report": cavity_report}
		var residual_patch: Array[Dictionary] = []
		for triangle in residual_triangles:
			if patch_id_map.has(String(triangle.get("triangle_id", ""))):
				residual_patch.append(triangle)
		var options_by_residual: Array[Array] = []
		var level_report: Dictionary = {"level": level, "patch_triangle_ids": patch_ids, "source_triangle_count": patch.size(), "candidate_count_by_residual": {}, "candidate_attempt_count": 0, "candidate_triangle_count": 0, "search_nodes": 0, "branches": 0, "solutions": 0, "terminal_reason": "UNKNOWN_NOT_CAPTURED"}
		var generation_limited: bool = false
		for residual_triangle in residual_patch:
			var residual_id: String = String(residual_triangle.get("triangle_id", ""))
			var residual_fixture_row: Dictionary = residual_by_id.get(residual_id, {})
			var attempts_remaining: int = CXR_MAX_CANDIDATE_ATTEMPTS_PER_CAVITY - cavity_report.candidate_attempts.size()
			var remaining_for_face: int = maxi(0, max_candidates_per_face - int(candidates_per_residual.get(residual_id, 0)))
			search_started = true
			if not _cxr_local_search_marker_emitted:
				print("R12CXR_LOCAL_PATCH_SEARCH_BEGIN " + JSON.stringify({"attempt_id": OS.get_environment("R12CXR_ATTEMPT_ID"), "source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "scenario_id": "R9.2.SEAM.XPLUS_EQUAL.v1", "cavity_id": cavity_id, "level": level, "preregistered_limits": _cxr_limits()}))
				_cxr_local_search_marker_emitted = true
			var candidate_data: Dictionary = _generate_field_candidates(residual_triangle, patch, values, roi, level, remaining_for_face, attempts_remaining, cavity_id, residual_fixture_row)
			level_report["candidate_generation_usec"] = int(level_report.get("candidate_generation_usec", 0)) + int(candidate_data.get("candidate_generation_usec", 0))
			var attempt_rows: Array = candidate_data.get("attempts", [])
			cavity_report.candidate_attempts.append_array(attempt_rows)
			level_report.candidate_attempt_count = int(level_report.candidate_attempt_count) + attempt_rows.size()
			cavity_report.support_candidates.append_array(candidate_data.get("candidate_pool", []))
			if not bool(candidate_data.get("source_valid", false)):
				cavity_report.levels.append(level_report)
				cavity_report.terminal_reason = String(candidate_data.get("source_failure_reason", "source_tetrahedron_invalid"))
				return {"valid": false, "search_started": search_started, "search_complete": false, "search_exhaustive": false, "terminal_reason": cavity_report.terminal_reason, "cavity_report": cavity_report}
			if bool(candidate_data.get("limit_hit", false)):
				generation_limited = true
				cavity_report.limits_hit.append_array(candidate_data.get("limits_hit", []))
			var options: Array[Dictionary] = []
			for candidate_value in candidate_data.get("candidates", []):
				var candidate: Dictionary = candidate_value
				if int(candidates_per_residual.get(residual_id, 0)) >= max_candidates_per_face:
					generation_limited = true
					cavity_report.limits_hit.append("MAX_SUPPORT_CANDIDATES_PER_CAVITY")
					break
				candidates_per_residual[residual_id] = int(candidates_per_residual.get(residual_id, 0)) + 1
				cavity_report.support_candidates_retained.append(candidate)
				var fan: Dictionary = _candidate_support_fan(residual_triangle, candidate)
				var fan_rows: Array = fan.get("triangle_rows", [])
				cavity_report.fan_evaluations.append({"candidate_id": candidate.get("candidate_id", ""), "valid": bool(fan.get("valid", false)), "reason": fan.get("reason", ""), "triangle_rows": fan_rows, "minimum_cross_squared": fan.get("minimum_cross_squared", "UNKNOWN_NOT_CAPTURED")})
				if _cxr_candidate_triangles_cavity + fan_rows.size() > CXR_MAX_CANDIDATE_TRIANGLES_PER_CAVITY:
					generation_limited = true
					cavity_report.limits_hit.append("MAX_CANDIDATE_TRIANGLES_PER_CAVITY")
					break
				_cxr_candidate_triangles_cavity += fan_rows.size()
				_cxr_candidate_triangles_total += fan_rows.size()
				cavity_report.candidate_triangles.append_array(fan_rows)
				level_report.candidate_triangle_count = int(level_report.candidate_triangle_count) + fan_rows.size()
				if bool(fan.get("valid", false)):
					candidate["fan_triangles"] = fan.get("triangles", [])
					candidate["fan_minimum_cross_squared"] = fan.get("minimum_cross_squared", 0.0)
					options.append(candidate)
				else:
					candidate["fan_rejection"] = fan.get("reason", "candidate_fan_invalid")
					_cxr_count_prune(String(candidate.get("fan_rejection", "candidate_fan_invalid")))
			options_by_residual.append(options)
			level_report.candidate_count_by_residual[residual_id] = options.size()
			if generation_limited:
				break
		if generation_limited:
			level_report.terminal_reason = "candidate_generation_limit"
			cavity_report.levels.append(level_report)
			cavity_report.terminal_reason = "limit_candidate_generation"
			return {"valid": false, "search_started": search_started, "search_complete": false, "search_exhaustive": false, "terminal_reason": cavity_report.terminal_reason, "cavity_report": cavity_report}
		var no_options: bool = false
		for options in options_by_residual:
			if options.is_empty():
				no_options = true
		if no_options:
			level_report.terminal_reason = "no_valid_fan_options"
			_cxr_count_prune("no_valid_fan_options")
			cavity_report.levels.append(level_report)
			continue
		var selected: Array[Dictionary] = []
		search_started = true
		var search_state: Dictionary = {"best": {}, "solutions": 0, "nodes": 0, "branches": 0, "complete": true, "limit_reason": "", "patch": patch, "patch_ids": patch_ids, "residual_triangles": residual_patch, "all_triangles": all_triangles, "arc_map": residual_fixture.get("arc_map", []), "applied_flips": residual_fixture.get("applied_flips", []), "boundary_signature": boundary_before.get("signature", "")}
		_search_cxr_combinations(0, options_by_residual, selected, search_state)
		level_report.search_nodes = int(search_state.get("nodes", 0))
		level_report.branches = int(search_state.get("branches", 0))
		level_report.solutions = int(search_state.get("solutions", 0))
		var best_for_level: Dictionary = search_state.get("best", {})
		level_report.terminal_reason = String(search_state.get("limit_reason", "")) if not bool(search_state.get("complete", false)) else ("solution_found" if not best_for_level.is_empty() else "no_valid_solution")
		cavity_report.search_nodes = int(cavity_report.search_nodes) + int(search_state.get("nodes", 0))
		cavity_report.levels.append(level_report)
		if not bool(search_state.get("complete", false)):
			cavity_report.terminal_reason = "limit_" + String(search_state.get("limit_reason", "unknown"))
			return {"valid": false, "search_started": search_started, "search_complete": false, "search_exhaustive": false, "terminal_reason": cavity_report.terminal_reason, "cavity_report": cavity_report}
		var best: Dictionary = best_for_level
		if not best.is_empty():
			var residual_ids_map: Dictionary = {}
			for residual in residual_patch:
				residual_ids_map[String(residual.triangle_id)] = true
			var replacement: Array[Dictionary] = []
			for triangle in patch:
				if not residual_ids_map.has(String(triangle.triangle_id)):
					replacement.append(triangle)
			replacement.append_array(best.get("fan_triangles", []))
			var patch_record: Dictionary = {"patch_triangle_ids": patch_ids, "replacement_triangles": replacement, "residual_triangle_ids": sorted_cavity_ids.duplicate(), "selected_supports": best.get("selected_supports", []), "level": level}
			cavity_report.selected_supports = best.get("selected_supports", [])
			cavity_report.selected_solution = best.duplicate(true)
			cavity_report.search_complete = true
			cavity_report.search_exhaustive = false
			cavity_report.terminal_reason = "solution_found"
			return {"valid": true, "search_started": search_started, "search_complete": true, "search_exhaustive": false, "terminal_reason": "solution_found", "cavity_report": cavity_report, "patch_triangle_ids": patch_ids, "patch_record": patch_record, "replacement_triangles": replacement, "selected_supports": best.get("selected_supports", [])}
	cavity_report.search_complete = true
	cavity_report.search_exhaustive = true
	cavity_report.terminal_reason = "finite_domain_exhausted_no_solution"
	return {"valid": false, "search_started": search_started, "search_complete": true, "search_exhaustive": true, "terminal_reason": cavity_report.terminal_reason, "cavity_report": cavity_report}
func _search_cxr_combinations(index: int, options_by_residual: Array[Array], selected: Array[Dictionary], state: Dictionary) -> void:
	if not bool(state.get("complete", false)):
		return
	var now_usec: int = Time.get_ticks_usec()
	if now_usec - _cxr_search_started_usec >= CXR_MAX_SEARCH_USEC_TOTAL:
		state["complete"] = false
		state["limit_reason"] = "MAX_SEARCH_USEC_TOTAL"
		return
	if now_usec - _cxr_cavity_started_usec >= CXR_MAX_SEARCH_USEC_PER_CAVITY:
		state["complete"] = false
		state["limit_reason"] = "MAX_SEARCH_USEC_PER_CAVITY"
		return
	if _cxr_search_nodes_total >= CXR_MAX_SEARCH_STATES_TOTAL or int(state.get("nodes", 0)) >= CXR_MAX_SEARCH_STATES_PER_CAVITY:
		state["complete"] = false
		state["limit_reason"] = "MAX_SEARCH_STATES"
		return
	state["nodes"] = int(state.get("nodes", 0)) + 1
	_cxr_search_nodes_total += 1
	if index < options_by_residual.size():
		for option_value in options_by_residual[index]:
			if selected.size() >= CXR_MAX_SELECTED_SUPPORTS:
				_cxr_count_prune("selected_support_cap")
				continue
			var duplicate_support: bool = false
			var option_position: Vector3 = option_value.get("world_position", Vector3.ZERO)
			for existing in selected:
				var existing_position: Vector3 = existing.get("world_position", Vector3.ZERO)
				if option_position == existing_position:
					duplicate_support = true
					break
			if duplicate_support:
				_cxr_count_prune("duplicate_support_position")
				continue
			state["branches"] = int(state.get("branches", 0)) + 1
			_cxr_count_branch("support_choice")
			selected.append(option_value)
			_search_cxr_combinations(index + 1, options_by_residual, selected, state)
			selected.pop_back()
			if not bool(state.get("complete", false)):
				return
		return
	var fan_triangles: Array[Dictionary] = []
	var supports: Array[Dictionary] = []
	for option in selected:
		fan_triangles.append_array(option.get("fan_triangles", []))
		supports.append(_support_provenance(option))
	var replace_map: Dictionary = {}
	for triangle in state.get("residual_triangles", []):
		replace_map[String(triangle.get("triangle_id", ""))] = true
	var replacement: Array[Dictionary] = []
	for triangle in state.get("patch", []):
		if not replace_map.has(String(triangle.get("triangle_id", ""))):
			replacement.append(triangle)
	replacement.append_array(fan_triangles)
	var boundary_after: Dictionary = _boundary_state(replacement)
	if not bool(boundary_after.get("valid", false)) or String(boundary_after.get("signature", "")) != String(state.get("boundary_signature", "")):
		_cxr_count_prune("replacement_boundary_mismatch")
		return
	var edge_counts: Dictionary = _edge_incidence(replacement)
	for edge_key in edge_counts:
		if int(edge_counts[edge_key]) > 2:
			_cxr_count_prune("replacement_nonmanifold_edge")
			return
	if _minimum_cross_squared(fan_triangles) <= CXR_CUTOFF_SQUARED:
		_cxr_count_prune("replacement_cutoff")
		return
	var candidate_global: Array[Dictionary] = []
	for triangle in state.get("all_triangles", []):
		if not replace_map.has(String(triangle.get("triangle_id", ""))):
			candidate_global.append(triangle)
	candidate_global.append_array(fan_triangles)
	if not _self_intersections_clear(fan_triangles, candidate_global):
		_cxr_count_prune("self_intersection")
		return
	if _new_t_junction_count(fan_triangles, candidate_global) > 0:
		_cxr_count_prune("t_junction")
		return
	var obligations: Dictionary = _validate_required_arcs(candidate_global, state.get("arc_map", []), state.get("applied_flips", []))
	if not bool(obligations.get("valid", false)):
		_cxr_count_prune("topology_arc_obligation")
		return
	var min_cross: float = _minimum_cross_squared(fan_triangles)
	var max_displacement: float = 0.0
	for support in selected:
		max_displacement = maxf(max_displacement, float(support.get("distance_to_face_centroid", INF)))
	var ids: Array[String] = []
	for support in selected:
		ids.append(String(support.get("support_id", "")))
	ids.sort()
	var score_key: String = "%024.16f|%024.16f|%s" % [-min_cross, max_displacement, "|".join(ids)]
	state["solutions"] = int(state.get("solutions", 0)) + 1
	_cxr_count_branch("valid_solution")
	var best: Dictionary = state.get("best", {})
	if best.is_empty() or score_key < String(best.get("stable_score_key", "")):
		state["best"] = {"fan_triangles": fan_triangles, "selected_supports": supports, "support_ids": ids, "minimum_cross_squared": min_cross, "maximum_support_displacement": max_displacement, "stable_score_key": score_key}
	if int(state.get("solutions", 0)) >= CXR_MAX_RETAINED_SOLUTIONS:
		state["complete"] = false
		state["limit_reason"] = "MAX_RETAINED_SOLUTIONS"
func _generate_field_candidates(residual: Dictionary, patch: Array[Dictionary], values: PackedFloat32Array, roi: Dictionary, level: int, max_candidates: int, max_attempts: int, cavity_id: String, fixture_row: Dictionary) -> Dictionary:
	var generation_started_usec: int = Time.get_ticks_usec()
	if not _cxr_local_search_marker_emitted:
		print("R12CXR_LOCAL_PATCH_SEARCH_BEGIN " + JSON.stringify({"attempt_id": OS.get_environment("R12CXR_ATTEMPT_ID"), "source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "scenario_id": "R9.2.SEAM.XPLUS_EQUAL.v1", "cavity_id": cavity_id, "level": level, "preregistered_limits": _cxr_limits()}))
		_cxr_local_search_marker_emitted = true
	var attempts: Array[Dictionary] = []
	var candidates_by_identity: Dictionary = {}
	var triangle_points: Array = residual.get("points", [])
	if triangle_points.size() != 3:
		return {"attempts": [{"candidate_id": "", "accepted": false, "rejection_reason": "residual_point_arity_invalid"}], "candidates": [], "limit_hit": false, "source_valid": false}
	var face_centroid: Vector3 = (Vector3(triangle_points[0]) + Vector3(triangle_points[1]) + Vector3(triangle_points[2])) / 3.0
	if not face_centroid.is_finite():
		return {"attempts": [{"candidate_id": "", "accepted": false, "rejection_reason": "residual_centroid_nonfinite"}], "candidates": [], "limit_hit": false, "source_valid": false}
	var patch_bounds: Dictionary = _patch_world_bounds(patch)
	var roi_min: Vector3 = Core.world_min(roi)
	var step: float = Core.step(roi)
	var cell_counts: Vector3i = Core.cell_counts(roi)
	var dims: Vector3i = cell_counts + Vector3i.ONE
	var min_local: Vector3 = (patch_bounds.get("min", Vector3.ZERO) - roi_min) / step
	var max_local: Vector3 = (patch_bounds.get("max", Vector3.ZERO) - roi_min) / step
	var margin: int = level
	var cell_min: Vector3i = Vector3i(maxi(0, floori(min_local.x) - margin), maxi(0, floori(min_local.y) - margin), maxi(0, floori(min_local.z) - margin))
	var cell_max: Vector3i = Vector3i(mini(cell_counts.x - 1, floori(max_local.x) + margin), mini(cell_counts.y - 1, floori(max_local.y) + margin), mini(cell_counts.z - 1, floori(max_local.z) + margin))
	if cell_min.x > cell_max.x or cell_min.y > cell_max.y or cell_min.z > cell_max.z:
		return {"attempts": [], "candidate_pool": [], "candidates": [], "limit_hit": false, "source_valid": false, "source_failure_reason": "patch_support_domain_outside_roi"}
	var seed_rows: Array[Dictionary] = _projection_seeds(residual)
	var attempt_cap_hit: bool = max_attempts <= 0
	var time_cap_reason: String = ""
	var source_valid: bool = true
	var invalid_tetrahedra: int = 0
	var source_tet_count: int = 0
	for y in range(cell_min.y, cell_max.y + 1):
		for z in range(cell_min.z, cell_max.z + 1):
			for x in range(cell_min.x, cell_max.x + 1):
				var cell: Vector3i = Vector3i(x, y, z)
				for tet_index in range(Core.TETS.size()):
					time_cap_reason = _cxr_time_limit_reason()
					if not time_cap_reason.is_empty():
						break
					if attempts.size() >= max_attempts:
						attempt_cap_hit = true
						break
					var tet_data: Dictionary = _tetra_data(cell, tet_index, values, dims, roi_min, step)
					if not bool(tet_data.get("valid", false)):
						source_valid = false
						invalid_tetrahedra += 1
						_cxr_record_attempt(attempts, "", false, String(tet_data.get("reason", "tetrahedron_invalid")), cavity_id, residual, level, cell, tet_index, "tetra_data", -1, Vector3.ZERO, tet_data, roi_min, step, max_attempts)
						continue
					source_tet_count += 1
					var zero_points: Array[Vector3] = _tetra_zero_points(tet_data)
					for pair_i in range(zero_points.size()):
						for pair_j in range(pair_i + 1, zero_points.size()):
							time_cap_reason = _cxr_time_limit_reason()
							if not time_cap_reason.is_empty():
								break
							if attempts.size() >= max_attempts:
								attempt_cap_hit = true
								break
							var pair_midpoint: Vector3 = (zero_points[pair_i] + zero_points[pair_j]) * 0.5
							_add_cxr_candidate(pair_midpoint, residual, face_centroid, cavity_id, level, cell, tet_index, "zero_polygon_pair_midpoint", pair_i * zero_points.size() + pair_j, 0.5, tet_data, attempts, candidates_by_identity, max_candidates, {}, max_attempts)
						if attempt_cap_hit: break
					if attempt_cap_hit: break
					for seed in seed_rows:
						time_cap_reason = _cxr_time_limit_reason()
						if not time_cap_reason.is_empty():
							break
						if attempts.size() >= max_attempts:
							attempt_cap_hit = true
							break
						var projection: Dictionary = _project_to_tetra_zero_plane(seed.position, tet_data)
						_add_cxr_candidate(projection.get("point", Vector3.ZERO), residual, face_centroid, cavity_id, level, cell, tet_index, "bounded_projection_to_frozen_tetra_zero_plane", int(seed.seed_index), float(projection.get("projection_factor", 0.0)), tet_data, attempts, candidates_by_identity, max_candidates, projection, max_attempts)
					if attempt_cap_hit: break
				if attempt_cap_hit: break
			if attempt_cap_hit: break
			if not time_cap_reason.is_empty(): break
		if attempt_cap_hit: break
		if not time_cap_reason.is_empty(): break
	var candidates: Array[Dictionary] = []
	for candidate_value in candidates_by_identity.values():
		candidates.append(candidate_value)
	candidates.sort_custom(_candidate_less)
	var candidate_pool: Array[Dictionary] = candidates.duplicate(true)
	var candidate_cap_hit: bool = candidates.size() > max_candidates
	if candidate_cap_hit:
		candidates.resize(max_candidates)
	for index in range(candidates.size()):
		var candidate: Dictionary = candidates[index]
		candidate["stable_rank"] = index
		candidates[index] = candidate
	var limits_hit: Array[String] = []
	if attempt_cap_hit: limits_hit.append("MAX_CANDIDATE_ATTEMPTS_PER_CAVITY")
	if candidate_cap_hit: limits_hit.append("MAX_SUPPORT_CANDIDATES_PER_CAVITY")
	if not time_cap_reason.is_empty(): limits_hit.append(time_cap_reason)
	return {"attempts": attempts, "candidate_pool": candidate_pool, "candidates": candidates, "candidate_attempt_count": attempts.size(), "candidate_count": candidates.size(), "candidate_cap_hit": candidate_cap_hit, "attempt_cap_hit": attempt_cap_hit, "time_cap_reason": time_cap_reason, "limit_hit": attempt_cap_hit or candidate_cap_hit or not time_cap_reason.is_empty(), "limits_hit": limits_hit, "source_valid": source_valid, "invalid_tetrahedron_count": invalid_tetrahedra, "source_tetrahedron_count": source_tet_count, "candidate_generation_usec": Time.get_ticks_usec() - generation_started_usec, "cell_bounds": {"min": cell_min, "max": cell_max}}
func _add_cxr_candidate(point: Vector3, residual: Dictionary, face_centroid: Vector3, cavity_id: String, level: int, cell: Vector3i, tet_index: int, method: String, seed_index: int, projection_factor: float, tet_data: Dictionary, attempts: Array[Dictionary], candidates: Dictionary, max_candidates: int, projection: Dictionary = {}, max_attempts: int = CXR_MAX_CANDIDATE_ATTEMPTS_PER_CAVITY) -> void:
	if attempts.size() >= max_attempts: return
	var residual_id: String = String(residual.get("triangle_id", ""))
	var candidate_id: String = "CXR|" + cavity_id + "|" + residual_id + "|L" + str(level) + "|" + str(cell.x) + "," + str(cell.y) + "," + str(cell.z) + "|T" + str(tet_index) + "|" + method + "|S" + str(seed_index)
	var rejection: String = ""
	if not point.is_finite(): rejection = "support_nonfinite"
	if rejection.is_empty() and not projection.is_empty() and not bool(projection.get("valid", false)): rejection = String(projection.get("reason", "support_projection_invalid"))
	var distance: float = point.distance_to(face_centroid) if rejection.is_empty() else INF
	if rejection.is_empty() and distance > CXR_MAX_SUPPORT_DISTANCE: rejection = "support_outside_local_distance"
	var bary: Array[float] = []
	var field_residual: float = INF
	if rejection.is_empty():
		var bary_result: Dictionary = _tetra_barycentric(point, tet_data.positions)
		if not bool(bary_result.get("valid", false)):
			rejection = String(bary_result.get("reason", "support_barycentric_invalid"))
		else:
			bary = bary_result.weights
			for weight in bary:
				if float(weight) < -CXR_BARYCENTRIC_EPSILON or float(weight) > 1.0 + CXR_BARYCENTRIC_EPSILON:
					rejection = "support_outside_tetrahedron"
					break
			if rejection.is_empty():
				field_residual = 0.0
				for index in range(4): field_residual += float(bary[index]) * float(tet_data.samples[index])
				if not is_finite(field_residual) or absf(field_residual) > CXR_FIELD_RESIDUAL_EPSILON: rejection = "support_frozen_field_residual_exceeded"
	if rejection.is_empty():
		for root_position in _root_positions.values():
			if point.distance_squared_to(root_position) <= 1.0e-16:
				rejection = "support_coincides_with_topology_root"
				break
	if rejection.is_empty():
		for root_point in residual.get("points", []):
			if point.distance_squared_to(root_point) <= 1.0e-16:
				rejection = "support_coincides_with_residual_root"
				break
	var identity: String = var_to_bytes(point).hex_encode() if point.is_finite() else candidate_id
	var accepted: bool = rejection.is_empty()
	var row: Dictionary = {"candidate_id": candidate_id, "support_id": "SUPPORT|" + Core.sha256(candidate_id.to_utf8_buffer()).substr(0, 24), "cavity_id": cavity_id, "residual_triangle_id": residual_id, "accepted": accepted, "rejection_reason": rejection, "method": method, "level": level, "source_cell_local": cell, "source_cell_global_lattice": tet_data.global_cell, "source_tetrahedron": tet_index, "tetrahedron_sample_values": tet_data.samples.duplicate(), "tetrahedron_corner_world": tet_data.positions.duplicate(), "seed_index": seed_index, "projection_factor": projection_factor, "barycentric_weights": bary, "frozen_field_interpolated_residual": field_residual, "world_position": point, "distance_to_face_centroid": distance, "binary32_position_identity": identity}
	if not projection.is_empty(): row["projection_diagnostics"] = projection.duplicate(true)
	_cxr_record_attempt(attempts, candidate_id, accepted, rejection, cavity_id, residual, level, cell, tet_index, method, seed_index, point, row, tet_data.roi_min, tet_data.step, max_attempts)
	if not accepted: return
	if not candidates.has(identity) or candidate_id < String(candidates[identity].get("candidate_id", "")):
		candidates[identity] = row

func _candidate_support_fan(residual: Dictionary, candidate: Dictionary) -> Dictionary:
	var ids: Array = residual.get("root_ids", [])
	var points: Array = residual.get("points", [])
	if ids.size() != 3 or points.size() != 3: return {"valid": false, "reason": "residual_triangle_arity_invalid", "triangle_rows": []}
	var support_id: String = String(candidate.get("support_id", ""))
	var support_point: Vector3 = candidate.get("world_position", Vector3.ZERO)
	var parent_normal: Vector3 = residual.get("normal", Vector3.ZERO)
	if support_id.is_empty() or not support_point.is_finite() or not parent_normal.is_finite() or parent_normal.length_squared() <= 0.0:
		return {"valid": false, "reason": "support_or_parent_normal_invalid", "triangle_rows": []}
	var triangles: Array[Dictionary] = []
	var triangle_rows: Array[Dictionary] = []
	var minimum_cross: float = INF
	for edge_index in range(3):
		var next_index: int = (edge_index + 1) % 3
		var child_ids: Array = [String(ids[edge_index]), String(ids[next_index]), support_id]
		var child_points: Array = [points[edge_index], points[next_index], support_point]
		var child: Dictionary = _triangle("CXR|" + String(residual.triangle_id) + "|" + str(edge_index) + "|" + support_id, String(residual.get("polygon_id", "")), child_ids, child_points, "R12CXR_FIELD_SUPPORT_FAN", false)
		var cross_squared: float = float(child.get("cross_squared", NAN))
		var reason: String = ""
		if not is_finite(cross_squared): reason = "candidate_triangle_cross_nonfinite"
		elif cross_squared <= CXR_CUTOFF_SQUARED: reason = "candidate_triangle_fixed_cutoff"
		if reason.is_empty() and Vector3(child.normal).dot(parent_normal) <= 0.0: reason = "candidate_triangle_winding"
		triangle_rows.append({"triangle_id": child.triangle_id, "support_id": support_id, "root_edge_ids": [child_ids[0], child_ids[1]], "points": child_points, "cross_squared": cross_squared, "cutoff_squared": CXR_CUTOFF_SQUARED, "accepted": reason.is_empty(), "rejection_reason": reason, "normal": child.get("normal", Vector3.ZERO)})
		if not reason.is_empty(): return {"valid": false, "reason": reason, "triangle_rows": triangle_rows}
		minimum_cross = minf(minimum_cross, cross_squared)
		triangles.append(child)
	return {"valid": triangles.size() == 3, "reason": "" if triangles.size() == 3 else "fan_triangle_count_invalid", "triangles": triangles, "triangle_rows": triangle_rows, "minimum_cross_squared": minimum_cross}

func _tetra_data(cell: Vector3i, tet_index: int, values: PackedFloat32Array, dims: Vector3i, roi_min: Vector3, step: float) -> Dictionary:
	if tet_index < 0 or tet_index >= Core.TETS.size(): return {"valid": false, "reason": "tetrahedron_index_invalid"}
	var positions: Array[Vector3] = []
	var samples: Array[float] = []
	for corner_value in Core.TETS[tet_index]:
		var corner: Vector3i = Core.GRID_CORNERS[int(corner_value)]
		var grid: Vector3i = cell + corner
		if grid.x < 0 or grid.y < 0 or grid.z < 0 or grid.x >= dims.x or grid.y >= dims.y or grid.z >= dims.z: return {"valid": false, "reason": "tetrahedron_sample_out_of_range"}
		var sample_index: int = (grid.y * dims.z + grid.z) * dims.x + grid.x
		if sample_index < 0 or sample_index >= values.size(): return {"valid": false, "reason": "tetrahedron_sample_index_out_of_range"}
		var sample_value: float = float(values[sample_index])
		if not is_finite(sample_value): return {"valid": false, "reason": "tetrahedron_sample_nonfinite"}
		positions.append(roi_min + Vector3(grid) * step)
		samples.append(sample_value)
	if positions.size() != 4 or samples.size() != 4: return {"valid": false, "reason": "tetrahedron_sample_arity_invalid"}
	return {"valid": true, "cell": cell, "global_cell": _global_lattice_cell(cell, roi_min, step), "tet_index": tet_index, "positions": positions, "samples": samples, "roi_min": roi_min, "step": step}

func _tetra_zero_points(tet_data: Dictionary) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var positions: Array = tet_data.positions
	var samples: Array = tet_data.samples
	var edges: Array = [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]
	for edge_value in edges:
		var edge: Array = edge_value
		var ia: int = int(edge[0]); var ib: int = int(edge[1])
		var va: float = float(samples[ia]); var vb: float = float(samples[ib])
		var point: Vector3
		var include: bool = false
		if va == 0.0:
			point = positions[ia]; include = true
		elif vb == 0.0:
			point = positions[ib]; include = true
		elif (va < 0.0 and vb > 0.0) or (va > 0.0 and vb < 0.0):
			var t: float = va / (va - vb)
			point = positions[ia].lerp(positions[ib], t); include = true
		if include:
			var duplicate: bool = false
			for existing in points:
				if existing == point: duplicate = true; break
			if not duplicate: points.append(point)
	return points

func _project_to_tetra_zero_plane(seed: Vector3, tet_data: Dictionary) -> Dictionary:
	var p: Array = tet_data.positions
	var s: Array = tet_data.samples
	var e1: Vector3 = p[1] - p[0]; var e2: Vector3 = p[2] - p[0]; var e3: Vector3 = p[3] - p[0]
	var determinant: float = e1.dot(e2.cross(e3))
	if not is_finite(determinant) or absf(determinant) <= 1.0e-20: return {"valid": false, "reason": "tetrahedron_determinant_invalid", "point": Vector3.ZERO}
	var d1: float = float(s[1]) - float(s[0]); var d2: float = float(s[2]) - float(s[0]); var d3: float = float(s[3]) - float(s[0])
	var gradient: Vector3 = (d1 * e2.cross(e3) + d2 * e3.cross(e1) + d3 * e1.cross(e2)) / determinant
	var gradient2: float = gradient.length_squared()
	if not gradient.is_finite() or not is_finite(gradient2) or gradient2 <= 1.0e-20: return {"valid": false, "reason": "tetrahedron_zero_plane_gradient_invalid", "point": Vector3.ZERO}
	var seed_value: float = float(s[0]) + gradient.dot(seed - p[0])
	var factor: float = seed_value / gradient2
	var point: Vector3 = seed - gradient * factor
	var barycentric: Dictionary = _tetra_barycentric(point, p)
	if not bool(barycentric.get("valid", false)): return {"valid": false, "reason": String(barycentric.get("reason", "projected_barycentric_invalid")), "point": point, "projection_factor": factor}
	var residual: float = 0.0
	for index in range(4): residual += float(barycentric.weights[index]) * float(s[index])
	return {"valid": is_finite(residual), "reason": "" if is_finite(residual) else "projection_residual_nonfinite", "point": point, "projection_factor": factor, "gradient": gradient, "seed_value": seed_value, "barycentric_weights": barycentric.weights, "frozen_field_residual": residual}

func _tetra_barycentric(point: Vector3, positions: Array) -> Dictionary:
	if positions.size() != 4 or not point.is_finite(): return {"valid": false, "reason": "tetrahedron_barycentric_input_invalid"}
	for position_value in positions:
		if not (position_value is Vector3) or not Vector3(position_value).is_finite(): return {"valid": false, "reason": "tetrahedron_barycentric_position_nonfinite"}
	var a: Vector3 = positions[1] - positions[0]; var b: Vector3 = positions[2] - positions[0]; var c: Vector3 = positions[3] - positions[0]
	var q: Vector3 = point - positions[0]
	var determinant: float = a.dot(b.cross(c))
	if not is_finite(determinant) or absf(determinant) <= 1.0e-20: return {"valid": false, "reason": "tetrahedron_barycentric_singular"}
	var w1: float = q.dot(b.cross(c)) / determinant
	var w2: float = a.dot(q.cross(c)) / determinant
	var w3: float = a.dot(b.cross(q)) / determinant
	var weights: Array[float] = [1.0 - w1 - w2 - w3, w1, w2, w3]
	for weight in weights:
		if not is_finite(weight): return {"valid": false, "reason": "tetrahedron_barycentric_weight_nonfinite", "weights": weights}
	return {"valid": true, "weights": weights}

func _projection_seeds(residual: Dictionary) -> Array[Dictionary]:
	var p: Array = residual.get("points", [])
	var result: Array[Dictionary] = []
	if p.size() != 3: return result
	for index in range(3): result.append({"seed_index": index, "position": p[index]})
	for index in range(3): result.append({"seed_index": 3 + index, "position": (p[index] + p[(index + 1) % 3]) * 0.5})
	result.append({"seed_index": 6, "position": (p[0] + p[1] + p[2]) / 3.0})
	return result

func _patch_world_bounds(patch: Array[Dictionary]) -> Dictionary:
	var min_v: Vector3 = Vector3(INF, INF, INF); var max_v: Vector3 = Vector3(-INF, -INF, -INF)
	for triangle in patch:
		for point_value in triangle.get("points", []):
			var point: Vector3 = point_value
			min_v.x = minf(min_v.x, point.x); min_v.y = minf(min_v.y, point.y); min_v.z = minf(min_v.z, point.z)
			max_v.x = maxf(max_v.x, point.x); max_v.y = maxf(max_v.y, point.y); max_v.z = maxf(max_v.z, point.z)
	return {"min": min_v, "max": max_v}

func _global_lattice_cell(local_cell: Vector3i, roi_min: Vector3, step: float) -> Vector3i:
	var origin: Vector3i = Vector3i(roundi(roi_min.x / step), roundi(roi_min.y / step), roundi(roi_min.z / step))
	return origin + local_cell

func _candidate_less(a: Dictionary, b: Dictionary) -> bool:
	var da: float = float(a.get("distance_to_face_centroid", INF)); var db: float = float(b.get("distance_to_face_centroid", INF))
	if da != db: return da < db
	var ca: Vector3i = a.get("source_cell_global_lattice", Vector3i.ZERO); var cb: Vector3i = b.get("source_cell_global_lattice", Vector3i.ZERO)
	if ca.x != cb.x: return ca.x < cb.x
	if ca.y != cb.y: return ca.y < cb.y
	if ca.z != cb.z: return ca.z < cb.z
	if int(a.get("source_tetrahedron", -1)) != int(b.get("source_tetrahedron", -1)): return int(a.source_tetrahedron) < int(b.source_tetrahedron)
	if String(a.get("method", "")) != String(b.get("method", "")): return String(a.method) < String(b.method)
	if int(a.get("seed_index", -1)) != int(b.get("seed_index", -1)): return int(a.seed_index) < int(b.seed_index)
	return String(a.candidate_id) < String(b.candidate_id)

func _cxr_record_attempt(attempts: Array[Dictionary], candidate_id: String, accepted: bool, reason: String, cavity_id: String, residual: Dictionary, level: int, cell: Vector3i, tet_index: int, method: String, seed_index: int, point: Vector3, diagnostics: Dictionary, roi_min: Vector3, step: float, max_attempts: int) -> void:
	if attempts.size() >= max_attempts:
		return
	_cxr_candidate_attempts_total += 1
	attempts.append({"candidate_id": candidate_id, "cavity_id": cavity_id, "residual_triangle_id": residual.get("triangle_id", ""), "level": level, "source_cell_local": cell, "source_cell_global_lattice": _global_lattice_cell(cell, roi_min, step), "source_tetrahedron": tet_index, "method": method, "seed_index": seed_index, "world_position": point, "accepted": accepted, "rejection_reason": reason, "diagnostics": diagnostics})

func _cxr_limits() -> Dictionary:
	return {"max_cavity_level": CXR_MAX_CAVITY_LEVEL, "max_cavities": CXR_MAX_CAVITIES, "max_patch_triangles": CXR_MAX_PATCH_TRIANGLES, "max_candidate_attempts_per_cavity": CXR_MAX_CANDIDATE_ATTEMPTS_PER_CAVITY, "max_support_candidates_per_cavity": CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY, "max_selected_supports": CXR_MAX_SELECTED_SUPPORTS, "max_candidate_triangles_per_cavity": CXR_MAX_CANDIDATE_TRIANGLES_PER_CAVITY, "max_search_states_per_cavity": CXR_MAX_SEARCH_STATES_PER_CAVITY, "max_search_states_total": CXR_MAX_SEARCH_STATES_TOTAL, "max_retained_solutions_per_cavity": CXR_MAX_RETAINED_SOLUTIONS, "max_search_usec_per_cavity": CXR_MAX_SEARCH_USEC_PER_CAVITY, "max_search_usec_total": CXR_MAX_SEARCH_USEC_TOTAL, "max_realize_usec": CXR_MAX_REALIZE_USEC, "max_support_distance": CXR_MAX_SUPPORT_DISTANCE, "barycentric_epsilon": CXR_BARYCENTRIC_EPSILON, "field_residual_epsilon": CXR_FIELD_RESIDUAL_EPSILON, "cross_squared_cutoff": CXR_CUTOFF_SQUARED}

func _cxr_counters() -> Dictionary:
	return {"search_nodes": _cxr_search_nodes_total, "candidate_attempts": _cxr_candidate_attempts_total, "candidate_triangles": _cxr_candidate_triangles_total, "branches": _cxr_branch_counts.duplicate(true), "prunes": _cxr_prune_counts.duplicate(true)}

func _cxr_count(target: Dictionary, key: String) -> void:
	target[key] = int(target.get(key, 0)) + 1

func _cxr_count_branch(key: String) -> void:
	_cxr_count(_cxr_branch_counts, key)
	_cxr_count(_cxr_active_cavity_branches, key)

func _cxr_count_prune(key: String) -> void:
	_cxr_count(_cxr_prune_counts, key)
	_cxr_count(_cxr_active_cavity_prunes, key)

func _cxr_time_limit_reason() -> String:
	var now_usec: int = Time.get_ticks_usec()
	if now_usec - _cxr_search_started_usec >= CXR_MAX_SEARCH_USEC_TOTAL: return "MAX_SEARCH_USEC_TOTAL"
	if now_usec - _cxr_cavity_started_usec >= CXR_MAX_SEARCH_USEC_PER_CAVITY: return "MAX_SEARCH_USEC_PER_CAVITY"
	return ""

func _total_candidate_count(cavities: Array[Dictionary]) -> int:
	var total: int = 0
	for cavity in cavities:
		var report: Dictionary = cavity.get("cavity_report", {})
		total += report.get("support_candidates", []).size()
	return total

func _unique_vertex_count(triangles: Array[Dictionary]) -> int:
	var vertices: Dictionary = {}
	for triangle in triangles:
		for point in triangle.get("points", []): vertices[var_to_bytes(point).hex_encode()] = true
	return vertices.size()

func _support_provenance(candidate: Dictionary) -> Dictionary:
	var row: Dictionary = candidate.duplicate(true)
	row.erase("fan_triangles")
	return row

func _validate_final_mesh(final_triangles: Array[Dictionary], original_triangles: Array[Dictionary], patches: Array[Dictionary], geometry: Dictionary, roi: Dictionary, snapshot: Dictionary) -> Dictionary:
	var counts: Dictionary = _edge_incidence(final_triangles)
	for edge_key in counts:
		if int(counts[edge_key]) > 2:
			return {"valid": false, "reason": "cxr_final_nonmanifold_edge", "edge": edge_key, "count": counts[edge_key]}
	for patch_value in patches:
		var patch: Dictionary = patch_value
		var patch_ids: Array = patch.get("patch_triangle_ids", [])
		var before: Array[Dictionary] = []
		for triangle in original_triangles:
			if patch_ids.has(String(triangle.get("triangle_id", ""))): before.append(triangle)
		var after: Array[Dictionary] = patch.get("replacement_triangles", [])
		var before_boundary: Dictionary = _boundary_state(before)
		var after_boundary: Dictionary = _boundary_state(after)
		if not bool(before_boundary.get("valid", false)) or not bool(after_boundary.get("valid", false)) or String(before_boundary.get("signature", "")) != String(after_boundary.get("signature", "")):
			return {"valid": false, "reason": "cxr_patch_boundary_changed", "before": before_boundary, "after": after_boundary}
		if not _self_intersections_clear(after, final_triangles):
			return {"valid": false, "reason": "cxr_patch_self_intersection"}
		if _new_t_junction_count(after, final_triangles) > 0:
			return {"valid": false, "reason": "cxr_patch_t_junction"}
		var changed_ids: Array = []
		for old_triangle in before: changed_ids.append(String(old_triangle.get("triangle_id", "")))
		patch["changed_source_triangle_ids"] = changed_ids
		patch["surface_diagnostics"] = _surface_diagnostics(after, snapshot)
	var original_root_ids: Dictionary = {}
	for triangle in original_triangles:
		for root_id in triangle.get("root_ids", []): original_root_ids[String(root_id)] = true
	for triangle in final_triangles:
		for root_id_value in triangle.get("root_ids", []):
			var root_id: String = String(root_id_value)
			if not original_root_ids.has(root_id) and not _cxr_allowed_support_ids.has(root_id):
				return {"valid": false, "reason": "cxr_unregistered_derived_support_vertex", "root_id": root_id}
	return {"valid": true, "triangle_count": final_triangles.size(), "edge_incidence": counts, "source_root_count": original_root_ids.size(), "derived_support_vertex_count": _cxr_allowed_support_ids.size(), "topology_obligation_count": geometry.get("arc_map", []).size(), "surface_diagnostics": _surface_diagnostics(final_triangles, snapshot), "roi": roi}
