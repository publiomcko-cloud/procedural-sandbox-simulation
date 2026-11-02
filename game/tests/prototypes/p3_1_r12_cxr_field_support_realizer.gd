extends "res://tests/prototypes/p3_1_r12_cx_micropatch_realizer.gd"

const CXR_CUTOFF_SQUARED: float = 1.0e-12
const CXR_MAX_CAVITY_LEVEL: int = 3
const CXR_R3_MAX_CAVITY_LEVEL: int = 4
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
const CXR_R2_MAX_CANDIDATE_TRIANGLES_PER_CAVITY: int = 65536
const CXR_R2_MAX_CANDIDATE_TRIANGLES_TOTAL: int = 131072
const CXR_R2_MAX_SEARCH_STATES_PER_CAVITY: int = 32768
const CXR_R2_MAX_SEARCH_STATES_TOTAL: int = 65536
const CXR_R4_MAX_REMOVED_FACES: int = 64
const CXR_R4_MAX_BOUNDARY_STATES: int = 20000
const CXR_R4_MAX_QUEUE_SIZE: int = 4096
const CXR_R4_MAX_BOUNDARY_COMPONENTS: int = 8
const CXR_R4_MAX_BOUNDARY_USEC: int = 10000000

var _cxr_search_started_usec: int = 0
var _cxr_cavity_started_usec: int = 0
var _cxr_search_nodes_total: int = 0
var _cxr_search_nodes_cavity: int = 0
var _cxr_patch_selection_nodes_total: int = 0
var _cxr_candidate_attempts_total: int = 0
var _cxr_candidate_triangles_total: int = 0
var _cxr_candidate_triangles_cavity: int = 0
## R6 finite-domain audit switch. It removes only the legacy implementation
## counter cap; the caller must still stop on an explicit resource limit and
## report the unvisited triplet frontier as PARTIAL_LIMIT.
var _cxr_full_finite_graph_mode: bool = false
var _cxr_branch_counts: Dictionary = {}
var _cxr_prune_counts: Dictionary = {}
var _cxr_active_cavity_branches: Dictionary = {}
var _cxr_active_cavity_prunes: Dictionary = {}
var _cxr_local_search_marker_emitted: bool = false
var _cxr_allowed_support_ids: Dictionary = {}
var _cxr_active_phase: String = "r1"
var _cxr_active_snapshot: Dictionary = {}

func realize_cxr(graph: Dictionary, values: PackedFloat32Array, roi: Dictionary, expected_topology_sha: String, expected_graph_fingerprint_sha: String, residual_fixture: Dictionary, snapshot: Dictionary) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var result: Dictionary = _realize_cxr_impl(graph, values, roi, expected_topology_sha, expected_graph_fingerprint_sha, residual_fixture, snapshot)
	return _apply_realizer_deadline(result, Time.get_ticks_usec() - started_usec)

func _apply_realizer_deadline(result: Dictionary, elapsed_usec: int) -> Dictionary:
	if elapsed_usec <= CXR_MAX_REALIZE_USEC:
		if bool(result.get("valid", false)):
			var completed_geometry_value: Variant = result.get("geometry", null)
			if typeof(completed_geometry_value) == TYPE_DICTIONARY:
				var completed_geometry: Dictionary = completed_geometry_value
				completed_geometry["realizer_wall_usec"] = elapsed_usec
				result["geometry"] = completed_geometry
		result["realizer_wall_usec"] = elapsed_usec
		return result
	if bool(result.get("valid", false)):
		var successful_geometry_value: Variant = result.get("geometry", null)
		if typeof(successful_geometry_value) == TYPE_DICTIONARY:
			var successful_geometry: Dictionary = successful_geometry_value
			successful_geometry["geometry_complete"] = false
			successful_geometry["realizer_failure_reason"] = "cxr_realize_time_limit"
			successful_geometry["realizer_wall_usec"] = elapsed_usec
			result["geometry"] = successful_geometry
			result["realizer_wall_usec"] = elapsed_usec
			return result
	var prior_result: Dictionary = result.duplicate(true)
	var prior_details: Variant = result.get("details", null)
	var deadline_details: Dictionary = {"realizer_wall_usec": elapsed_usec, "max_realize_usec": CXR_MAX_REALIZE_USEC, "prior_result": prior_result}
	if typeof(prior_details) == TYPE_DICTIONARY:
		deadline_details["prior_details"] = prior_details
	return {"valid": false, "cx_algorithm_started": bool(result.get("cx_algorithm_started", false)), "reason": "cxr_realize_time_limit", "partial": true, "realizer_wall_usec": elapsed_usec, "details": deadline_details}
	result["realizer_wall_usec"] = elapsed_usec
	return result

func _realize_cxr_impl(graph: Dictionary, values: PackedFloat32Array, roi: Dictionary, expected_topology_sha: String, expected_graph_fingerprint_sha: String, residual_fixture: Dictionary, snapshot: Dictionary) -> Dictionary:
	var began_usec: int = Time.get_ticks_usec()
	_cxr_active_phase = OS.get_environment("R12CXR_PHASE")
	if _cxr_active_phase.is_empty():
		_cxr_active_phase = "r1"
	if not ["r1", "r2", "r3", "r4"].has(_cxr_active_phase):
		return {"valid": false, "cx_algorithm_started": false, "reason": "cxr_phase_invalid", "phase": _cxr_active_phase}
	_cxr_active_snapshot = snapshot
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
	# The fixture pins residual faces and support provenance, while the canonical
	# base realization owns topology arcs. Give R2 that authoritative arc map;
	# the local context below narrows it to obligations in each cavity.
	var search_residual_fixture: Dictionary = residual_fixture
	if ["r2", "r3", "r4"].has(_cxr_active_phase):
		search_residual_fixture = residual_fixture.duplicate(true)
		search_residual_fixture["arc_map"] = base.get("arc_map", []).duplicate(true)
		search_residual_fixture["applied_flips"] = base.get("applied_flips", []).duplicate(true)
	_locked_triplets = _derive_locked_triplets(base.get("applied_flips", []), _root_positions)
	var adjacency: Dictionary = _adjacency(triangles)
	_orient_rejected_triangles(triangles, adjacency)
	var original_triangles: Array[Dictionary] = triangles.duplicate(true)
	if _cxr_active_phase in ["r3", "r4"]:
		var residual_ids_seen: Dictionary = {}
		for residual_value in residual_rows:
			if typeof(residual_value) != TYPE_DICTIONARY:
				return {"valid": false, "cx_algorithm_started": false, "reason": "cxr_r3_residual_row_invalid"}
			var residual_row: Dictionary = residual_value
			var residual_id: String = String(residual_row.get("triangle_id", ""))
			if residual_id.is_empty() or residual_ids_seen.has(residual_id):
				return {"valid": false, "cx_algorithm_started": false, "reason": "cxr_r3_residual_identity_invalid", "triangle_id": residual_id, "duplicate": residual_ids_seen.has(residual_id)}
			residual_ids_seen[residual_id] = true
	var groups: Array[Array] = _overlapping_defect_groups(residual_rows, adjacency)
	if _cxr_active_phase in ["r3", "r4"]:
		groups = _canonicalize_defect_groups(groups)
	if groups.is_empty() or groups.size() > CXR_MAX_CAVITIES:
		return {"valid": false, "cx_algorithm_started": false, "reason": "cxr_cavity_set_invalid", "cavity_count": groups.size(), "cap": CXR_MAX_CAVITIES}
	_cxr_search_started_usec = Time.get_ticks_usec()
	_cxr_search_nodes_total = 0
	_cxr_patch_selection_nodes_total = 0
	_cxr_candidate_attempts_total = 0
	_cxr_candidate_triangles_total = 0
	_cxr_branch_counts.clear()
	_cxr_prune_counts.clear()
	var cavity_results: Array[Dictionary] = []
	var patch_records: Array[Dictionary] = []
	var used_patch_ids: Dictionary = {}
	var search_started: bool = false
	var cavity_search_complete: bool = true
	var cavity_search_exhaustive: bool = true
	var cavity_failure_reasons: Array[String] = []
	var global_limit_reason: String = ""
	var has_patch_overlap: bool = false
	var joint_cavity_attempts: Array[Dictionary] = []
	var joint_cavity_failure: Dictionary = {}
	var search_method: String = "_search_cxr_cavity_r3" if _cxr_active_phase in ["r3", "r4"] else "_search_cxr_cavity_r2" if _cxr_active_phase == "r2" else "_search_cxr_cavity"
	var search_callable: Callable = Callable(self, search_method).bind(triangles, adjacency, search_residual_fixture, values, roi)
	var cavity_sequence: Dictionary = _run_cxr_cavity_sequence(groups, search_callable)
	cavity_results = cavity_sequence.get("cavity_results", [])
	search_started = bool(cavity_sequence.get("search_started", false))
	cavity_search_complete = bool(cavity_sequence.get("search_complete", false))
	cavity_search_exhaustive = bool(cavity_sequence.get("search_exhaustive", false))
	cavity_failure_reasons = cavity_sequence.get("failure_reasons", [])
	global_limit_reason = String(cavity_sequence.get("global_limit_reason", ""))
	for cavity_result in cavity_results:
		if not bool(cavity_result.get("valid", false)):
			continue
		for triangle_id in cavity_result.get("patch_triangle_ids", []):
			if used_patch_ids.has(String(triangle_id)):
				cavity_failure_reasons.append("cxr_patch_overlap:" + String(triangle_id))
				has_patch_overlap = true
			used_patch_ids[String(triangle_id)] = true
		patch_records.append(cavity_result.get("patch_record", {}))
	if has_patch_overlap and _cxr_active_phase in ["r3", "r4"]:
		var joint_execution: Dictionary = _r3_execute_joint_cavity_plan(groups, cavity_results, search_callable)
		var raw_joint_attempts: Variant = joint_execution.get("joint_attempts", [])
		if raw_joint_attempts is Array:
			for attempt_value in raw_joint_attempts:
				if typeof(attempt_value) == TYPE_DICTIONARY: joint_cavity_attempts.append(attempt_value)
		if bool(joint_execution.get("valid", false)):
			var raw_joint_groups: Variant = joint_execution.get("groups", null)
			var raw_joint_results: Variant = joint_execution.get("cavity_results", null)
			var typed_joint_groups: Array[Array] = []
			var typed_joint_results: Array[Dictionary] = []
			var joint_shape_valid: bool = raw_joint_groups is Array and raw_joint_results is Array
			if joint_shape_valid:
				for group_value in raw_joint_groups:
					if not group_value is Array:
						joint_shape_valid = false
						break
					var typed_group: Array = group_value
					typed_joint_groups.append(typed_group)
				for result_value in raw_joint_results:
					if typeof(result_value) != TYPE_DICTIONARY:
						joint_shape_valid = false
						break
					typed_joint_results.append(result_value)
			joint_shape_valid = joint_shape_valid and typed_joint_groups.size() == typed_joint_results.size() and not typed_joint_groups.is_empty()
			if not joint_shape_valid:
				joint_cavity_failure = {"reason": "r3_joint_cavity_result_shape_invalid", "groups_type": type_string(typeof(raw_joint_groups)), "results_type": type_string(typeof(raw_joint_results)), "joint_attempts": joint_cavity_attempts.duplicate(true)}
			else:
				groups = typed_joint_groups
				cavity_results = typed_joint_results
				cavity_failure_reasons.clear()
				patch_records.clear()
				used_patch_ids.clear()
				has_patch_overlap = false
				cavity_search_complete = true
				cavity_search_exhaustive = true
				search_started = false
				for cavity_index in range(cavity_results.size()):
					var cavity_result: Dictionary = cavity_results[cavity_index]
					if not bool(cavity_result.get("valid", false)):
						cavity_failure_reasons.append(String(cavity_result.get("terminal_reason", cavity_result.get("reason", "joint_cavity_search_invalid"))))
					for triangle_id in cavity_result.get("patch_triangle_ids", []):
						if used_patch_ids.has(String(triangle_id)):
							cavity_failure_reasons.append("cxr_patch_overlap_after_joint_search:" + String(triangle_id))
							has_patch_overlap = true
						used_patch_ids[String(triangle_id)] = true
					var patch_record_value: Variant = cavity_result.get("patch_record", null)
					if typeof(patch_record_value) == TYPE_DICTIONARY: patch_records.append(patch_record_value)
					search_started = search_started or bool(cavity_result.get("search_started", false))
					cavity_search_complete = cavity_search_complete and bool(cavity_result.get("search_complete", false))
					cavity_search_exhaustive = cavity_search_exhaustive and bool(cavity_result.get("search_exhaustive", false))
				global_limit_reason = _cxr_global_limit_reason()
		else:
			joint_cavity_failure = joint_execution.duplicate(true)
	if not cavity_failure_reasons.is_empty() or cavity_results.size() != groups.size():
		var search_complete: bool = cavity_search_complete and cavity_results.size() == groups.size()
		var search_exhaustive: bool = cavity_search_exhaustive and search_complete and not has_patch_overlap
		var failure_reason: String = _cxr_failure_reason(_cxr_active_phase, search_complete, cavity_failure_reasons)
		if has_patch_overlap:
			failure_reason = "cxr_per_cavity_patch_overlap" if _cxr_active_phase in ["r3", "r4"] else "cxr_joint_patch_overlap"
			search_exhaustive = false
		var terminal_reason: String = _cxr_failure_terminal_reason(_cxr_active_phase, cavity_results, groups.size(), global_limit_reason, has_patch_overlap)
		var search_counters_observed: bool = search_started or _cxr_search_nodes_total > 0
		return {"valid": false, "cx_algorithm_started": search_started, "reason": "cx_bounded_patch_search_failed", "details": {"search": {"phase": _cxr_active_phase, "reason": failure_reason, "complete": search_complete, "search_exhaustive": search_exhaustive, "cavity_count_expected": groups.size(), "cavity_count_processed": cavity_results.size(), "cavity_failure_reasons": cavity_failure_reasons, "nodes": _cxr_search_nodes_total if search_counters_observed else "UNKNOWN_NOT_CAPTURED", "candidate_attempts": _cxr_candidate_attempts_total if search_counters_observed else "UNKNOWN_NOT_CAPTURED", "candidate_triangles": _cxr_candidate_triangles_total if search_counters_observed else "UNKNOWN_NOT_CAPTURED", "terminal_reason": terminal_reason}, "cxr_cavity_results": cavity_results, "cxr_joint_cavity_attempts": joint_cavity_attempts, "cxr_joint_cavity_failure": joint_cavity_failure, "cxr_limits": _cxr_limits(), "cxr_search_counters": _cxr_counters(search_counters_observed)}}
	var removed_patch_ids: Dictionary = used_patch_ids.duplicate()
	var updated_triangles: Array[Dictionary] = []
	for triangle in original_triangles:
		if not removed_patch_ids.has(String(triangle.get("triangle_id", ""))): updated_triangles.append(triangle)
	for cavity_result in cavity_results:
		updated_triangles.append_array(cavity_result.get("replacement_triangles", []))
	triangles = updated_triangles
	var validation: Dictionary = _validate_final_mesh(triangles, original_triangles, patch_records, base, roi, snapshot)
	if not bool(validation.get("valid", false)):
		return {"valid": false, "cx_algorithm_started": true, "reason": "cx_bounded_patch_search_failed", "details": {"search": {"reason": "cxr_final_mesh_validation_failed", "complete": true}, "validation": validation, "cxr_cavity_results": cavity_results, "cxr_joint_cavity_attempts": joint_cavity_attempts, "cxr_limits": _cxr_limits(), "cxr_search_counters": _cxr_counters(true)}}
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
	base["cxr_local_search_nodes"] = _cxr_search_nodes_total if search_started else "UNKNOWN_NOT_CAPTURED"
	base["cxr_local_search_complete"] = cavity_search_complete
	base["cxr_local_search_exhaustive"] = cavity_search_exhaustive and cavity_search_complete
	base["cxr_local_search_terminal_reason"] = "finite_domain_exhausted_with_candidate" if cavity_search_exhaustive and cavity_search_complete else global_limit_reason if not global_limit_reason.is_empty() else "candidate_geometry_available_but_search_incomplete"
	base["cxr_search_counters"] = _cxr_counters(search_started)
	base["cxr_candidate_attempt_count"] = _cxr_candidate_attempts_total if search_started else "UNKNOWN_NOT_CAPTURED"
	base["cxr_candidate_triangle_count"] = _cxr_candidate_triangles_total if search_started else "UNKNOWN_NOT_CAPTURED"
	base["cxr_cavity_results"] = cavity_results
	base["cxr_joint_cavity_used"] = not joint_cavity_attempts.is_empty()
	base["cxr_joint_cavity_attempts"] = joint_cavity_attempts
	base["cx_support_vertex_count"] = selected_supports.size() if search_started else "UNKNOWN_NOT_CAPTURED"
	base["cx_support_candidate_count"] = _total_candidate_count(cavity_results) if search_started else "UNKNOWN_NOT_CAPTURED"
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

func _canonicalize_defect_groups(groups: Array[Array]) -> Array[Array]:
	var result: Array[Array] = []
	for group_value in groups:
		var group: Array = group_value.duplicate()
		group.sort()
		result.append(group)
	result.sort_custom(func(a: Array, b: Array) -> bool: return JSON.stringify(a) < JSON.stringify(b))
	return result

func _r3_joint_find_root(parent: Array[int], index: int) -> int:
	var root: int = index
	while parent[root] != root:
		root = parent[root]
	while parent[index] != index:
		var next_index: int = parent[index]
		parent[index] = root
		index = next_index
	return root

func _r3_joint_union(parent: Array[int], first: int, second: int) -> void:
	var first_root: int = _r3_joint_find_root(parent, first)
	var second_root: int = _r3_joint_find_root(parent, second)
	if first_root == second_root: return
	if first_root < second_root:
		parent[second_root] = first_root
	else:
		parent[first_root] = second_root

func _r3_joint_cavity_plan(groups: Array, cavity_results: Array[Dictionary]) -> Dictionary:
	if groups.size() < 2 or groups.size() != cavity_results.size():
		return {"valid": false, "reason": "r3_joint_cavity_input_cardinality_invalid"}
	var parent: Array[int] = []
	for index in range(groups.size()): parent.append(index)
	var patch_owners: Dictionary = {}
	for group_index in range(cavity_results.size()):
		var result: Dictionary = cavity_results[group_index]
		if not bool(result.get("valid", false)): continue
		var local_patch_ids: Dictionary = {}
		for patch_id_value in result.get("patch_triangle_ids", []):
			var patch_id: String = String(patch_id_value)
			if patch_id.is_empty() or local_patch_ids.has(patch_id):
				return {"valid": false, "reason": "r3_joint_cavity_patch_identity_invalid", "group_index": group_index, "patch_id": patch_id}
			local_patch_ids[patch_id] = true
			if not patch_owners.has(patch_id): patch_owners[patch_id] = []
			var owners: Array = patch_owners[patch_id]
			for owner_value in owners:
				_r3_joint_union(parent, group_index, int(owner_value))
			owners.append(group_index)
			patch_owners[patch_id] = owners
	var components_by_root: Dictionary = {}
	for index in range(groups.size()):
		var root: int = _r3_joint_find_root(parent, index)
		if not components_by_root.has(root): components_by_root[root] = []
		components_by_root[root].append(index)
	var component_roots: Array = components_by_root.keys()
	component_roots.sort()
	var components: Array[Dictionary] = []
	var planned_groups: Array[Array] = []
	var any_joint: bool = false
	for root_value in component_roots:
		var group_indices: Array = components_by_root[root_value]
		group_indices.sort()
		var seed_set: Dictionary = {}
		for group_index_value in group_indices:
			for seed_value in groups[int(group_index_value)]: seed_set[String(seed_value)] = true
		var seed_ids: Array[String] = []
		for seed_value in seed_set.keys(): seed_ids.append(String(seed_value))
		seed_ids.sort()
		var shared_patch_ids: Dictionary = {}
		if group_indices.size() > 1:
			any_joint = true
			for patch_id_value in patch_owners.keys():
				var owners: Array = patch_owners[patch_id_value]
				var owners_in_component: int = 0
				for owner_value in owners:
					if group_indices.has(int(owner_value)): owners_in_component += 1
				if owners_in_component > 1: shared_patch_ids[String(patch_id_value)] = true
		var shared_ids: Array[String] = []
		for patch_id_value in shared_patch_ids.keys(): shared_ids.append(String(patch_id_value))
		shared_ids.sort()
		components.append({"group_indices": group_indices.duplicate(), "seed_ids": seed_ids.duplicate(), "joint": group_indices.size() > 1, "intersection_patch_ids": shared_ids})
		planned_groups.append(seed_ids)
	if not any_joint:
		return {"valid": false, "reason": "r3_joint_cavity_no_selected_patch_intersection", "groups": planned_groups, "components": components}
	return {"valid": true, "reason": "r3_minimal_manifold_expansion_patches_intersected", "groups": planned_groups, "components": components}

func _r3_execute_joint_cavity_plan(groups: Array, cavity_results: Array[Dictionary], searcher: Callable) -> Dictionary:
	var plan: Dictionary = _r3_joint_cavity_plan(groups, cavity_results)
	if not bool(plan.get("valid", false)): return plan
	var resolved_results: Array[Dictionary] = []
	var joint_attempts: Array[Dictionary] = []
	var final_groups: Array[Array] = plan.get("groups", [])
	var components: Array = plan.get("components", [])
	for component_index in range(components.size()):
		var component: Dictionary = components[component_index]
		var group_indices: Array = component.get("group_indices", [])
		var seed_ids: Array = component.get("seed_ids", [])
		var result: Dictionary = {}
		if bool(component.get("joint", false)):
			var search_value: Variant = searcher.call(seed_ids)
			if typeof(search_value) != TYPE_DICTIONARY:
				return {"valid": false, "reason": "r3_joint_cavity_search_result_invalid", "joint_attempts": joint_attempts, "failed_component": component.duplicate(true)}
			result = search_value
			var merge_record: Dictionary = {"merge_reason": "independently selected minimum-cardinality manifold patches intersected; rerun one minimum-manifold search from the union of frozen residual seeds", "intersection_patch_ids": component.get("intersection_patch_ids", []).duplicate(), "original_group_indices": group_indices.duplicate(), "merged_frozen_residual_ids": seed_ids.duplicate(), "boundary_source": "remaining_C6_edge_incidence_after_cavity_patch_removal"}
			result["joint_cavity_merge"] = merge_record
			result["cavity_policy"] = "joint_minimal_manifold_expansion_after_selected_patch_intersection"
			var report: Dictionary = result.get("cavity_report", {})
			report["cavity_policy"] = result.cavity_policy
			report["joint_cavity_merge"] = merge_record.duplicate(true)
			result["cavity_report"] = report
			var patch_record_value: Variant = result.get("patch_record", null)
			if typeof(patch_record_value) == TYPE_DICTIONARY:
				var patch_record: Dictionary = patch_record_value
				patch_record["joint_cavity_merge"] = merge_record.duplicate(true)
				result["patch_record"] = patch_record
			joint_attempts.append({"component_index": component_index, "merge_record": merge_record, "valid": bool(result.get("valid", false)), "search_started": bool(result.get("search_started", false)), "search_complete": bool(result.get("search_complete", false)), "search_exhaustive": bool(result.get("search_exhaustive", false)), "terminal_reason": String(result.get("terminal_reason", "UNKNOWN_NOT_CAPTURED"))})
		else:
			var original_index: int = int(group_indices[0])
			result = cavity_results[original_index].duplicate(true)
		result["cavity_index"] = component_index
		resolved_results.append(result)
	return {"valid": true, "reason": String(plan.get("reason", "")), "groups": final_groups, "components": components, "cavity_results": resolved_results, "joint_attempts": joint_attempts}

func _search_cxr_cavity(cavity_ids: Array, all_triangles: Array[Dictionary], adjacency: Dictionary, residual_fixture: Dictionary, values: PackedFloat32Array, roi: Dictionary) -> Dictionary:
	_cxr_cavity_started_usec = Time.get_ticks_usec()
	_cxr_candidate_triangles_cavity = 0
	_cxr_active_cavity_branches = {}
	_cxr_active_cavity_prunes = {}
	var sorted_cavity_ids: Array = cavity_ids.duplicate()
	sorted_cavity_ids.sort()
	var cavity_id: String = Core.sha256(JSON.stringify(sorted_cavity_ids).to_utf8_buffer()).substr(0, 16)
	var cavity_report: Dictionary = {"cavity_id": cavity_id, "residual_triangle_ids": sorted_cavity_ids.duplicate(), "levels": [], "candidate_attempts": [], "support_candidates": [], "support_candidates_retained": [], "fan_evaluations": [], "candidate_triangles": [], "retained_solutions": [], "selected_supports": [], "solution_found_levels": [], "search_nodes": 0, "branches": _cxr_active_cavity_branches, "prunes": _cxr_active_cavity_prunes, "limits_hit": [], "search_complete": false, "search_exhaustive": false, "terminal_reason": "UNKNOWN_NOT_CAPTURED"}
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
		_append_unrun_cxr_levels(cavity_report, 0, "NOT_RUN_INVALID_CAVITY", "residual_cavity_faces_missing")
		cavity_report.terminal_reason = "residual_cavity_faces_missing"
		return _finish_cxr_cavity_search(cavity_report, {}, false, false, cavity_report.terminal_reason)
	if residual_triangles.size() > CXR_MAX_SELECTED_SUPPORTS:
		cavity_report.limits_hit.append("MAX_SELECTED_SUPPORTS")
		_append_unrun_cxr_levels(cavity_report, 0, "NOT_RUN_CAVITY_LIMIT", "selected_support_cap_insufficient")
		cavity_report.terminal_reason = "limit_selected_support_cap_insufficient"
		return _finish_cxr_cavity_search(cavity_report, {}, false, false, cavity_report.terminal_reason)
	var search_started: bool = true
	var candidates_per_residual: Dictionary = {}
	var best_solution: Dictionary = {}
	var max_candidates_per_face: int = maxi(1, int(floor(float(CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY) / float(residual_triangles.size()))))
	for level in range(CXR_MAX_CAVITY_LEVEL + 1):
		var patch_id_map: Dictionary = {}
		for seed_id in sorted_cavity_ids:
			for triangle_id in _radius_ids(String(seed_id), adjacency, level):
				patch_id_map[String(triangle_id)] = true
		var patch_ids: Array = _sorted_keys(patch_id_map)
		var patch: Array[Dictionary] = []
		for triangle in all_triangles:
			if patch_id_map.has(String(triangle.get("triangle_id", ""))):
				patch.append(triangle)
		var level_report: Dictionary = _new_cxr_level_report(level, patch_ids, patch.size())
		if patch_id_map.size() > CXR_MAX_PATCH_TRIANGLES:
			level_report.terminal_reason = "limit_source_triangle_cap"
			level_report.candidate_generation_usec = "NOT_RUN_CAVITY_LIMIT"
			level_report.candidate_generation_status = "NOT_RUN_CAVITY_LIMIT"
			level_report.search_status = "NOT_RUN_CAVITY_LIMIT"
			cavity_report.levels.append(level_report)
			cavity_report.limits_hit.append("MAX_PATCH_TRIANGLES")
			cavity_report.terminal_reason = "limit_max_patch_triangles"
			_append_unrun_cxr_levels(cavity_report, level + 1, "NOT_RUN_CAVITY_LIMIT", cavity_report.terminal_reason)
			return _finish_cxr_cavity_search(cavity_report, best_solution, false, false, cavity_report.terminal_reason)
		var boundary_before: Dictionary = _boundary_state(patch)
		if not bool(boundary_before.get("valid", false)):
			_record_invalid_cxr_boundary_level(cavity_report, level_report, boundary_before)
			cavity_report.terminal_reason = "patch_boundary_invalid_level_%d" % level
			continue
		level_report["boundary_before"] = boundary_before
		level_report["boundary_signature"] = String(boundary_before.get("signature", ""))
		level_report["candidate_generation_usec"] = 0
		level_report["candidate_generation_status"] = "RUNNING"
		level_report["search_status"] = "NOT_RUN_NO_VALID_OPTIONS"
		var residual_patch: Array[Dictionary] = []
		for triangle in residual_triangles:
			if patch_id_map.has(String(triangle.get("triangle_id", ""))):
				residual_patch.append(triangle)
		var options_by_residual: Array[Array] = []
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
			var evidence_check: Dictionary = _validate_candidate_generation_evidence(candidate_data)
			if not bool(evidence_check.get("valid", false)):
				_preserve_incomplete_candidate_generation(candidate_data, evidence_check, cavity_report, level_report, residual_patch, residual_triangle, residual_id, level)
				return _finish_cxr_cavity_search(cavity_report, best_solution, false, false, cavity_report.terminal_reason)
			var elapsed_generation_value: Variant = candidate_data.get("candidate_generation_usec", "UNKNOWN_NOT_CAPTURED")
			var accumulated_generation_value: Variant = level_report.get("candidate_generation_usec", 0)
			if typeof(elapsed_generation_value) == TYPE_INT and typeof(accumulated_generation_value) == TYPE_INT:
				level_report["candidate_generation_usec"] = int(accumulated_generation_value) + int(elapsed_generation_value)
			else:
				level_report["candidate_generation_usec"] = "UNKNOWN_NOT_CAPTURED"
			var attempt_rows: Array = candidate_data.get("attempts", [])
			cavity_report.candidate_attempts.append_array(attempt_rows)
			level_report.candidate_attempt_count = int(level_report.candidate_attempt_count) + attempt_rows.size()
			level_report.candidate_unique_count_by_residual[residual_id] = int(candidate_data.candidate_unique_count)
			level_report.candidate_pool_retained_count_by_residual[residual_id] = candidate_data.candidate_pool.size()
			for attempt_value in attempt_rows:
				if attempt_value is Dictionary:
					level_report.candidate_attempt_ids.append(String(attempt_value.get("attempt_id", attempt_value.get("candidate_id", "UNKNOWN_NOT_CAPTURED"))))
			cavity_report.support_candidates.append_array(candidate_data.get("candidate_pool", []))
			if not bool(candidate_data.get("source_valid", false)):
				level_report.candidate_generation_status = "FAILED_SOURCE_VALIDATION"
				level_report.search_status = "NOT_RUN_SOURCE_INVALID"
				level_report.terminal_reason = String(candidate_data.get("source_failure_reason", "source_tetrahedron_invalid"))
				level_report.candidate_count_by_residual[residual_id] = int(candidate_data.get("candidate_count", -1))
				level_report.candidate_fan_status_by_residual[residual_id] = "NOT_RUN_SOURCE_INVALID"
				_mark_unrun_cxr_residuals(level_report, residual_patch, residual_patch.find(residual_triangle) + 1, "NOT_RUN_SOURCE_FAILURE")
				cavity_report.levels.append(level_report)
				cavity_report.terminal_reason = String(candidate_data.get("source_failure_reason", "source_tetrahedron_invalid"))
				_append_unrun_cxr_levels(cavity_report, level + 1, "NOT_RUN_SOURCE_FAILURE", cavity_report.terminal_reason)
				return _finish_cxr_cavity_search(cavity_report, best_solution, false, false, cavity_report.terminal_reason)
			if bool(candidate_data.get("limit_hit", false)):
				generation_limited = true
				cavity_report.limits_hit.append_array(candidate_data.get("limits_hit", []))
			var options: Array[Dictionary] = []
			var fan_limit_reached: bool = false
			for candidate_index in range(candidate_data.candidates.size()):
				var candidate_value: Variant = candidate_data.candidates[candidate_index]
				var candidate: Dictionary = candidate_value
				if int(candidates_per_residual.get(residual_id, 0)) >= max_candidates_per_face:
					generation_limited = true
					fan_limit_reached = true
					cavity_report.limits_hit.append("MAX_SUPPORT_CANDIDATES_PER_CAVITY")
					for untested_index in range(candidate_index, candidate_data.candidates.size()):
						var untested_support: Dictionary = candidate_data.candidates[untested_index]
						cavity_report.fan_evaluations.append({"candidate_id": untested_support.get("candidate_id", "UNKNOWN_NOT_CAPTURED"), "valid": false, "status": "NOT_RUN_RETAINED_SUPPORT_LIMIT", "reason": "MAX_SUPPORT_CANDIDATES_PER_CAVITY", "triangle_rows": "NOT_RUN_RETAINED_SUPPORT_LIMIT", "minimum_cross_squared": "NOT_RUN_RETAINED_SUPPORT_LIMIT"})
					break
				candidates_per_residual[residual_id] = int(candidates_per_residual.get(residual_id, 0)) + 1
				cavity_report.support_candidates_retained.append(candidate)
				var fixed_fan_triangle_count: int = 3
				if _cxr_candidate_triangles_cavity + fixed_fan_triangle_count > CXR_MAX_CANDIDATE_TRIANGLES_PER_CAVITY:
					generation_limited = true
					fan_limit_reached = true
					cavity_report.limits_hit.append("MAX_CANDIDATE_TRIANGLES_PER_CAVITY")
					cavity_report.fan_evaluations.append({"candidate_id": candidate.get("candidate_id", "UNKNOWN_NOT_CAPTURED"), "valid": false, "status": "NOT_RUN_CANDIDATE_TRIANGLE_LIMIT", "reason": "MAX_CANDIDATE_TRIANGLES_PER_CAVITY", "triangle_rows": "NOT_RUN_CANDIDATE_TRIANGLE_LIMIT", "minimum_cross_squared": "NOT_RUN_CANDIDATE_TRIANGLE_LIMIT"})
					for untested_index in range(candidate_index + 1, candidate_data.candidates.size()):
						var untested_support: Dictionary = candidate_data.candidates[untested_index]
						cavity_report.fan_evaluations.append({"candidate_id": untested_support.get("candidate_id", "UNKNOWN_NOT_CAPTURED"), "valid": false, "status": "NOT_RUN_CANDIDATE_TRIANGLE_LIMIT", "reason": "MAX_CANDIDATE_TRIANGLES_PER_CAVITY", "triangle_rows": "NOT_RUN_CANDIDATE_TRIANGLE_LIMIT", "minimum_cross_squared": "NOT_RUN_CANDIDATE_TRIANGLE_LIMIT"})
					break
				var fan: Dictionary = _candidate_support_fan(residual_triangle, candidate)
				var fan_rows: Array = fan.get("triangle_rows", [])
				cavity_report.fan_evaluations.append({"candidate_id": candidate.get("candidate_id", ""), "valid": bool(fan.get("valid", false)), "status": "TESTED", "reason": fan.get("reason", ""), "triangle_rows": fan_rows, "minimum_cross_squared": fan.get("minimum_cross_squared", "UNKNOWN_NOT_CAPTURED")})
				if fan_rows.size() > fixed_fan_triangle_count:
					cavity_report["fixed_fan_triangle_count_violation"] = {"candidate_id": candidate.get("candidate_id", "UNKNOWN_NOT_CAPTURED"), "expected_maximum": fixed_fan_triangle_count, "observed": fan_rows.size(), "triangle_rows": fan_rows}
					cavity_report.candidate_triangles.append_array(fan_rows)
					_cxr_candidate_triangles_cavity += fan_rows.size()
					_cxr_candidate_triangles_total += fan_rows.size()
					level_report["candidate_triangle_count"] = fan_rows.size()
					level_report["candidate_generation_status"] = "FAILED_FAN_TRIANGLE_COUNT_INVARIANT"
					level_report["search_status"] = "NOT_RUN_SOURCE_INVARIANT_FAILURE"
					level_report["terminal_reason"] = "fixed_fan_triangle_count_exceeded"
					_mark_unrun_cxr_residuals(level_report, residual_patch, residual_patch.find(residual_triangle) + 1, "NOT_RUN_SOURCE_INVARIANT_FAILURE")
					cavity_report.levels.append(level_report)
					cavity_report.terminal_reason = "fixed_fan_triangle_count_exceeded"
					_append_unrun_cxr_levels(cavity_report, level + 1, "NOT_RUN_SOURCE_INVARIANT_FAILURE", cavity_report.terminal_reason)
					return _finish_cxr_cavity_search(cavity_report, best_solution, false, false, cavity_report.terminal_reason)
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
			level_report.candidate_fan_status_by_residual[residual_id] = "PARTIAL_FAN_EVALUATION_LIMIT" if fan_limit_reached else "AVAILABLE_SET_TESTED_GENERATION_LIMIT_REACHED" if generation_limited else "COMPLETE"
			if generation_limited:
				_mark_unrun_cxr_residuals(level_report, residual_patch, residual_patch.find(residual_triangle) + 1, "NOT_RUN_CANDIDATE_LIMIT")
				break
		if generation_limited:
			level_report.candidate_generation_status = "LIMIT_REACHED"
			level_report.search_status = "NOT_RUN_CANDIDATE_LIMIT"
			level_report.terminal_reason = "candidate_generation_limit"
			cavity_report.levels.append(level_report)
			cavity_report.terminal_reason = "limit_candidate_generation"
			_append_unrun_cxr_levels(cavity_report, level + 1, "NOT_RUN_CAVITY_LIMIT", cavity_report.terminal_reason)
			return _finish_cxr_cavity_search(cavity_report, best_solution, false, false, cavity_report.terminal_reason)
		var no_options: bool = false
		for options in options_by_residual:
			if options.is_empty():
				no_options = true
		if no_options:
			level_report.terminal_reason = "no_valid_fan_options"
			level_report.candidate_generation_status = "COMPLETE"
			level_report.search_status = "COMPLETE_NO_OPTIONS"
			_cxr_count_prune("no_valid_fan_options")
			cavity_report.levels.append(level_report)
			continue
		var selected: Array[Dictionary] = []
		search_started = true
		var search_state: Dictionary = {"best": {}, "solutions": 0, "nodes": 0, "branches": 0, "complete": true, "limit_reason": "", "patch": patch, "patch_ids": patch_ids, "residual_triangles": residual_patch, "all_triangles": all_triangles, "arc_map": residual_fixture.get("arc_map", []), "applied_flips": residual_fixture.get("applied_flips", []), "boundary_signature": boundary_before.get("signature", "")}
		search_state["retained_solutions"] = []
		search_state["retained_solution_limit"] = CXR_MAX_RETAINED_SOLUTIONS - cavity_report.retained_solutions.size()
		if int(search_state.retained_solution_limit) <= 0:
			level_report.candidate_generation_status = "COMPLETE"
			level_report.search_status = "NOT_RUN_CAVITY_SOLUTION_CAP"
			level_report.terminal_reason = "MAX_RETAINED_SOLUTIONS"
			cavity_report.levels.append(level_report)
			cavity_report.limits_hit.append("MAX_RETAINED_SOLUTIONS")
			cavity_report.terminal_reason = "limit_MAX_RETAINED_SOLUTIONS"
			_append_unrun_cxr_levels(cavity_report, level + 1, "NOT_RUN_CAVITY_LIMIT", cavity_report.terminal_reason)
			return {"valid": false, "search_started": search_started, "search_complete": false, "search_exhaustive": false, "terminal_reason": cavity_report.terminal_reason, "cavity_report": cavity_report}
		_search_cxr_combinations(0, options_by_residual, selected, search_state)
		level_report.search_nodes = int(search_state.get("nodes", 0))
		level_report.branches = int(search_state.get("branches", 0))
		level_report.solutions = int(search_state.get("solutions", 0))
		level_report.retained_solutions = search_state.get("retained_solutions", [])
		for retained_value in level_report.retained_solutions:
			var retained_row: Dictionary = retained_value.duplicate(true)
			retained_row["level"] = level
			retained_row["patch_triangle_ids"] = patch_ids.duplicate()
			retained_row["boundary_signature"] = String(boundary_before.get("signature", ""))
			cavity_report.retained_solutions.append(retained_row)
		level_report.candidate_generation_status = "COMPLETE"
		var best_for_level: Dictionary = search_state.get("best", {})
		level_report.terminal_reason = String(search_state.get("limit_reason", "")) if not bool(search_state.get("complete", false)) else ("solution_found" if not best_for_level.is_empty() else "no_valid_solution")
		level_report.search_status = "COMPLETE" if bool(search_state.get("complete", false)) else "LIMIT_REACHED"
		cavity_report.search_nodes = int(cavity_report.search_nodes) + int(search_state.get("nodes", 0))
		cavity_report.levels.append(level_report)
		var best: Dictionary = search_state.get("best", {})
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
			cavity_report.solution_found_levels.append(level)
			if best_solution.is_empty() or String(best.get("stable_score_key", "")) < String(best_solution.get("solution", {}).get("stable_score_key", "")):
				best_solution = {"solution": best.duplicate(true), "patch_ids": patch_ids.duplicate(), "patch_record": patch_record, "replacement_triangles": replacement.duplicate(true), "level": level}
		if not bool(search_state.get("complete", false)):
			cavity_report.terminal_reason = "limit_" + String(search_state.get("limit_reason", "unknown"))
			cavity_report.limits_hit.append(String(search_state.get("limit_reason", "UNKNOWN_NOT_CAPTURED")))
			_append_unrun_cxr_levels(cavity_report, level + 1, "NOT_RUN_CAVITY_LIMIT", cavity_report.terminal_reason)
			return _finish_cxr_cavity_search(cavity_report, best_solution, false, false, cavity_report.terminal_reason)
	return _finish_cxr_cavity_search(cavity_report, best_solution, true, true, "all_levels_exhausted")

func _search_cxr_cavity_r3(cavity_ids: Array, all_triangles: Array[Dictionary], adjacency: Dictionary, residual_fixture: Dictionary, values: PackedFloat32Array, roi: Dictionary) -> Dictionary:
	_cxr_cavity_started_usec = Time.get_ticks_usec()
	_cxr_search_nodes_cavity = 0
	_cxr_candidate_triangles_cavity = 0
	_cxr_active_cavity_branches = {}
	_cxr_active_cavity_prunes = {}
	var seed_ids: Array = cavity_ids.duplicate()
	seed_ids.sort()
	var cavity_id: String = Core.sha256(JSON.stringify(seed_ids).to_utf8_buffer()).substr(0, 16)
	var report: Dictionary = {"phase": "r3" if _cxr_active_phase != "r4" else "r4", "cavity_id": cavity_id, "residual_triangle_ids": seed_ids, "cavity_policy": "original_overlapping_defect_group", "seed_face_count": seed_ids.size(), "levels": [], "candidate_attempts": [], "candidate_attempt_count": "NOT_RUN", "support_candidates": [], "support_candidate_count": "NOT_RUN", "support_candidates_unique_count": "NOT_RUN", "support_candidates_retained": [], "candidate_triangles": [], "candidate_triangle_count": "NOT_RUN", "candidate_edges": [], "retained_solutions": [], "selected_supports": [], "selected_solution": {}, "selected_level": -1, "solution_found_levels": [], "boundary_provenance": "derived_from_remaining_c6_edge_incidence", "search_nodes": "NOT_RUN", "branches": "NOT_RUN", "prunes": "NOT_RUN", "limits_hit": [], "search_started": false, "search_complete": false, "search_exhaustive": false, "terminal_reason": "UNKNOWN_NOT_CAPTURED"}
	var residual_by_id: Dictionary = {}
	var residual_all_by_id: Dictionary = {}
	var residual_rows_value: Variant = residual_fixture.get("residuals", null)
	if typeof(residual_rows_value) != TYPE_ARRAY:
		_append_unrun_cxr_levels(report, 0, "NOT_RUN_INVALID_CAVITY_SEEDS", "r3_residual_rows_not_array")
		return _finish_cxr_cavity_search(report, {}, false, false, "r3_cavity_seed_identity_invalid")
	var residual_rows: Array = residual_rows_value
	for residual_value in residual_rows:
		if typeof(residual_value) != TYPE_DICTIONARY:
			residual_all_by_id.clear()
			break
		var residual_row: Dictionary = residual_value
		var residual_id: String = String(residual_row.get("triangle_id", ""))
		if residual_id.is_empty() or residual_all_by_id.has(residual_id):
			residual_all_by_id.clear()
			break
		residual_all_by_id[residual_id] = residual_row
	for seed_id in seed_ids:
		if residual_all_by_id.has(String(seed_id)):
			residual_by_id[String(seed_id)] = residual_all_by_id[String(seed_id)]
	var seed_triangles: Array[Dictionary] = []
	for triangle in all_triangles:
		if seed_ids.has(String(triangle.get("triangle_id", ""))):
			seed_triangles.append(triangle)
	seed_triangles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.triangle_id) < String(b.triangle_id))
	if seed_ids.is_empty() or seed_ids.size() > residual_rows.size() or seed_triangles.size() != seed_ids.size() or residual_by_id.size() != seed_ids.size():
		_append_unrun_cxr_levels(report, 0, "NOT_RUN_INVALID_CAVITY_SEEDS", "r3_group_must_match_unique_frozen_residual_faces")
		return _finish_cxr_cavity_search(report, {}, false, false, "r3_cavity_seed_identity_invalid")
	var support_by_position: Dictionary = {}
	var any_valid_boundary_search: bool = false
	var support_generation_exhaustive: bool = true
	var patch_selection_node_total: int = 0
	var boundary_first: bool = _cxr_active_phase == "r4"
	var levels: Array = [0] if boundary_first else []
	if not boundary_first:
		for level_index in range(CXR_R3_MAX_CAVITY_LEVEL + 1): levels.append(level_index)
	for level in levels:
		var patch_map: Dictionary = {}
		if boundary_first:
			for seed_id_value in seed_ids: patch_map[String(seed_id_value)] = true
		else:
			for seed_id_value in seed_ids:
				for triangle_id in _radius_ids(String(seed_id_value), adjacency, level):
					patch_map[String(triangle_id)] = true
		var allowed_ids: Array = _sorted_keys(patch_map)
		var search_allowed_ids: Array = allowed_ids
		if boundary_first:
			search_allowed_ids = []
			for triangle in all_triangles: search_allowed_ids.append(String(triangle.get("triangle_id", "")))
			search_allowed_ids.sort()
		var union_patch: Array[Dictionary] = _r3_patch_rows_for_ids(all_triangles, allowed_ids)
		var union_connectivity: Dictionary = _r3_patch_connectivity(union_patch)
		var union_boundary: Dictionary = _r3_derive_remaining_boundary(all_triangles, allowed_ids)
		var level_report: Dictionary = _new_cxr_level_report(level, allowed_ids, allowed_ids.size())
		level_report["cavity_seed_ids"] = seed_ids.duplicate()
		var patch_selection: Dictionary = _r4_select_boundary_first_patch(seed_ids, search_allowed_ids, all_triangles, adjacency, seed_triangles, [], residual_fixture, level) if boundary_first else _r3_select_boundary_patch(seed_ids, allowed_ids, all_triangles, adjacency, level, seed_triangles, residual_fixture)
		patch_selection_node_total += int(patch_selection.get("search_nodes", 0))
		report["patch_selection_nodes"] = patch_selection_node_total
		level_report["patch_selection"] = {"policy": "minimum_cardinality_connected_subsets_with_manifold_boundary_and_r2_domain_preflight_within_original_defect_group_radius_neighborhood", "radius": level, "max_radius": CXR_R3_MAX_CAVITY_LEVEL, "max_patch_triangles": CXR_MAX_PATCH_TRIANGLES, "search_nodes": patch_selection.get("search_nodes", 0), "candidate_subsets_examined": patch_selection.get("candidate_subsets_examined", 0), "rejection_counts": patch_selection.get("rejection_counts", {}), "context_rejection_count": patch_selection.get("context_rejection_count", 0), "context_rejections": patch_selection.get("context_rejections", []), "selected_patch_triangle_ids": patch_selection.get("patch_triangle_ids", []), "context_preflight_valid": patch_selection.get("context_preflight_valid", false), "neighborhood_triangle_ids": allowed_ids.duplicate(), "complete": patch_selection.get("complete", false), "limit_reason": patch_selection.get("limit_reason", "")}
		level_report["patch_selection"]["offending_expansion_candidate_ids"] = patch_selection.get("offending_expansion_candidate_ids", [])
		level_report["patch_selection"]["boundary_screen_policy"] = "compact_diagnostics_for_invalid_subsets_full_c6_incidence_diagnostics_for_valid_boundaries"
		if not bool(patch_selection.get("complete", false)):
			var selection_limit: String = String(patch_selection.get("limit_reason", "R3_PATCH_SELECTION_INCOMPLETE"))
			level_report["patch_triangle_ids"] = "NOT_RUN_PATCH_SELECTION_LIMIT"
			level_report["source_triangle_count"] = "NOT_RUN_PATCH_SELECTION_LIMIT"
			level_report["patch_connectivity"] = union_connectivity
			level_report["boundary_before"] = union_boundary.duplicate(true)
			level_report["boundary_diagnostics"] = union_boundary.get("incidence_diagnostics", [])
			level_report.candidate_generation_status = "NOT_RUN_PATCH_SELECTION_LIMIT"
			level_report.search_status = "NOT_RUN_PATCH_SELECTION_LIMIT"
			level_report.terminal_reason = selection_limit
			report.levels.append(level_report)
			report.limits_hit.append(selection_limit)
			_append_unrun_cxr_levels(report, level + 1, "NOT_RUN_PATCH_SELECTION_LIMIT", selection_limit)
			return _finish_cxr_cavity_search(report, {}, false, false, selection_limit)
		if not bool(patch_selection.get("valid", false)):
			var invalid_reason: String = String(patch_selection.get("reason", "r3_no_boundary_valid_patch_subset"))
			var context_blocked: bool = invalid_reason == "r3_no_context_valid_patch_subset"
			level_report["patch_triangle_ids"] = "NO_CONTEXT_VALID_SUBSET" if context_blocked else "NO_BOUNDARY_VALID_SUBSET"
			level_report["source_triangle_count"] = allowed_ids.size()
			level_report["patch_connectivity"] = union_connectivity
			level_report["boundary_before"] = union_boundary.duplicate(true)
			level_report["boundary_signature"] = String(union_boundary.get("observed_boundary_signature", "UNKNOWN_NOT_CAPTURED"))
			level_report["boundary_provenance"] = "remaining_C6_edge_incidence_after_candidate_patch_subset_removal"
			level_report["boundary_diagnostics"] = union_boundary.get("incidence_diagnostics", [])
			var unrun_reason: String = "NOT_RUN_CONTEXT_PREFLIGHT_REJECT" if context_blocked else "NOT_RUN_NO_BOUNDARY_VALID_SUBSET"
			level_report.candidate_count_by_residual = _r3_unrun_seed_metrics(seed_ids, unrun_reason)
			level_report.candidate_unique_count_by_residual = level_report.candidate_count_by_residual.duplicate()
			level_report.candidate_pool_retained_count_by_residual = level_report.candidate_count_by_residual.duplicate()
			level_report.candidate_fan_status_by_residual = level_report.candidate_count_by_residual.duplicate()
			level_report.candidate_attempt_count = "NOT_RUN_NO_BOUNDARY_VALID_SUBSET"
			level_report.candidate_attempt_ids = "NOT_RUN_NO_BOUNDARY_VALID_SUBSET"
			level_report.candidate_triangle_count = "NOT_RUN_NO_BOUNDARY_VALID_SUBSET"
			level_report.candidate_generation_usec = "NOT_RUN_NO_BOUNDARY_VALID_SUBSET"
			level_report.candidate_generation_status = "NOT_RUN_NO_BOUNDARY_VALID_SUBSET"
			level_report.search_nodes = "NOT_RUN_NO_BOUNDARY_VALID_SUBSET"
			level_report.search_status = "NOT_RUN_NO_BOUNDARY_VALID_SUBSET"
			level_report.terminal_reason = invalid_reason
			level_report["boundary_invalid_reason"] = invalid_reason
			report.levels.append(level_report)
			continue
		var patch_ids: Array = patch_selection.get("patch_triangle_ids", []).duplicate()
		var patch: Array[Dictionary] = patch_selection.get("patch_triangles", []).duplicate(true)
		var connectivity: Dictionary = patch_selection.get("connectivity", {}).duplicate(true)
		var boundary: Dictionary = patch_selection.get("boundary", {}).duplicate(true)
		level_report["patch_triangle_ids"] = patch_ids.duplicate()
		level_report["source_triangle_count"] = patch.size()
		level_report["patch_connectivity"] = connectivity
		level_report["boundary_before"] = boundary.duplicate(true)
		level_report["boundary_signature"] = String(boundary.get("signature", boundary.get("observed_boundary_signature", "UNKNOWN_NOT_CAPTURED")))
		level_report["boundary_provenance"] = "C6_all_triangles_minus_selected_connected_patch_subset"
		level_report["boundary_diagnostics"] = boundary.get("incidence_diagnostics", [])
		any_valid_boundary_search = true
		report["search_started"] = true
		if typeof(report.get("candidate_attempt_count", null)) != TYPE_INT:
			report["candidate_attempt_count"] = 0
			report["support_candidate_count"] = 0
			report["candidate_triangle_count"] = 0
			report["search_nodes"] = 0
			report["branches"] = 0
			report["prunes"] = {}
		var candidate_triangles_before_level: int = _cxr_candidate_triangles_total
		var generation_started: int = Time.get_ticks_usec()
		var level_candidate_counts: Dictionary = {}
		var level_candidate_unique: Dictionary = {}
		var level_candidate_retained: Dictionary = {}
		var remaining_global_attempts: int = CXR_MAX_CANDIDATE_ATTEMPTS_PER_CAVITY - report.candidate_attempts.size()
		var max_per_seed: int = maxi(1, int(floor(float(CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY) / float(seed_triangles.size()))))
		var generation_failed: bool = false
		var generation_reason: String = ""
		var generation_limited: bool = false
		var generation_limit_reasons: Array[String] = []
		for seed_index in range(seed_triangles.size()):
			var seed_triangle: Dictionary = seed_triangles[seed_index]
			var seed_id: String = String(seed_triangle.get("triangle_id", ""))
			var fixture_row: Dictionary = residual_by_id.get(seed_id, {})
			var attempts_remaining: int = CXR_MAX_CANDIDATE_ATTEMPTS_PER_CAVITY - report.candidate_attempts.size()
			if attempts_remaining <= 0:
				generation_limited = true
				generation_limit_reasons.append("MAX_CANDIDATE_ATTEMPTS_PER_CAVITY")
				break
			var candidate_data: Dictionary = _generate_field_candidates(seed_triangle, patch, values, roi, level, max_per_seed, mini(remaining_global_attempts, attempts_remaining), cavity_id, fixture_row)
			var evidence_check: Dictionary = _validate_candidate_generation_evidence(candidate_data)
			if not bool(evidence_check.get("valid", false)):
				generation_failed = true
				generation_reason = "candidate_generation_evidence_incomplete"
				level_report["candidate_generation_evidence_failure"] = evidence_check
				break
			var attempts: Array = candidate_data.get("attempts", [])
			report.candidate_attempts.append_array(attempts)
			report["candidate_attempt_count"] = report.candidate_attempts.size()
			for attempt_value in attempts:
				level_report.candidate_attempt_ids.append(String(attempt_value.get("attempt_id", attempt_value.get("candidate_id", "UNKNOWN_NOT_CAPTURED"))) if typeof(attempt_value) == TYPE_DICTIONARY else "UNKNOWN_NOT_CAPTURED")
			level_report.candidate_attempt_count = int(level_report.candidate_attempt_count) + attempts.size()
			level_candidate_counts[seed_id] = candidate_data.get("candidate_count", "UNKNOWN_NOT_CAPTURED")
			level_candidate_unique[seed_id] = candidate_data.get("candidate_unique_count", "UNKNOWN_NOT_CAPTURED")
			level_candidate_retained[seed_id] = candidate_data.get("candidate_pool", []).size()
			for candidate_value in candidate_data.get("candidate_pool", []):
				report.support_candidates.append(candidate_value.duplicate(true))
			report["support_candidate_count"] = report.support_candidates.size()
			if not bool(candidate_data.get("source_valid", false)):
				generation_failed = true
				generation_reason = String(candidate_data.get("source_failure_reason", "candidate_source_invalid"))
				break
			for candidate_value in candidate_data.get("candidate_pool", []):
				var candidate: Dictionary = candidate_value
				var identity: String = String(candidate.get("binary32_position_identity", ""))
				if identity.is_empty() or String(candidate.get("support_id", "")).is_empty():
					generation_failed = true
					generation_reason = "support_candidate_identity_invalid"
					break
				var prior: Dictionary = support_by_position.get(identity, {})
				if prior.is_empty():
					if support_by_position.size() >= CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY:
						generation_failed = true
						generation_reason = "MAX_SUPPORT_CANDIDATES_PER_CAVITY"
						break
					support_by_position[identity] = candidate.duplicate(true)
				else:
					var provenance: Array = prior.get("coalesced_candidate_ids", [])
					var candidate_id: String = String(candidate.get("candidate_id", ""))
					if not provenance.has(candidate_id): provenance.append(candidate_id)
					provenance.sort()
					if _candidate_less(candidate, prior):
						candidate["coalesced_candidate_ids"] = provenance
						support_by_position[identity] = candidate.duplicate(true)
					else:
						prior["coalesced_candidate_ids"] = provenance
						support_by_position[identity] = prior
			if generation_failed:
				break
			report["support_candidates_unique_count"] = support_by_position.size()
			if bool(candidate_data.get("limit_hit", false)):
				generation_limited = true
				for limit_value in candidate_data.get("limits_hit", []):
					var limit_reason: String = String(limit_value)
					if not limit_reason.is_empty() and not generation_limit_reasons.has(limit_reason):
						generation_limit_reasons.append(limit_reason)
				break
		var stop_for_generation: bool = _r3_generation_requires_partial_stop(generation_failed, generation_limited, support_by_position.size())
		if stop_for_generation:
			level_report.candidate_triangle_count = _cxr_candidate_triangles_total - candidate_triangles_before_level
			report["candidate_triangle_count"] = int(report.get("candidate_triangle_count", 0)) + int(level_report.candidate_triangle_count)
			level_report.candidate_count_by_residual = level_candidate_counts
			level_report.candidate_unique_count_by_residual = level_candidate_unique
			level_report.candidate_pool_retained_count_by_residual = level_candidate_retained
			_mark_unrun_cxr_residuals(level_report, seed_triangles, level_candidate_counts.size(), "NOT_RUN_GENERATION_FAILURE")
			level_report.candidate_generation_usec = Time.get_ticks_usec() - generation_started
			level_report.candidate_generation_status = "FAILED_SOURCE_EVIDENCE" if generation_failed else "LIMIT_REACHED_EMPTY_SUPPORT_POOL"
			level_report["candidate_generation_complete"] = false
			level_report["candidate_generation_exhaustive"] = false
			level_report["generation_limit_reasons"] = generation_limit_reasons.duplicate()
			level_report.search_status = "NOT_RUN_SOURCE_FAILURE" if generation_failed else "NOT_RUN_LIMIT_WITHOUT_SUPPORTS"
			level_report.terminal_reason = generation_reason if generation_failed else "candidate_generation_limit_without_valid_supports:" + ",".join(generation_limit_reasons)
			report.levels.append(level_report)
			var stop_reason: String = String(level_report.terminal_reason)
			if generation_failed and not generation_reason.is_empty():
				report.limits_hit.append(generation_reason)
			else:
				for limit_reason in generation_limit_reasons:
					if not report.limits_hit.has(limit_reason): report.limits_hit.append(limit_reason)
			_append_unrun_cxr_levels(report, level + 1, "NOT_RUN_CAVITY_LIMIT", stop_reason)
			return _finish_cxr_cavity_search(report, {}, false, false, stop_reason)
		level_report.candidate_count_by_residual = level_candidate_counts
		level_report.candidate_unique_count_by_residual = level_candidate_unique
		level_report.candidate_pool_retained_count_by_residual = level_candidate_retained
		for seed_id_value in seed_ids:
			level_report.candidate_fan_status_by_residual[String(seed_id_value)] = "NOT_RUN_R3_CAVITY_TRIANGULATION"
		level_report.candidate_generation_usec = Time.get_ticks_usec() - generation_started
		level_report.candidate_generation_status = "LIMITED_POOL_RETAINED_FOR_TRIANGULATION" if generation_limited else "COMPLETE_R3_FROZEN_RESIDUAL_SUPPORT_SET"
		level_report["candidate_generation_complete"] = not generation_limited
		level_report["candidate_generation_exhaustive"] = not generation_limited
		level_report["generation_limit_reasons"] = generation_limit_reasons.duplicate()
		if generation_limited:
			support_generation_exhaustive = false
			for limit_reason in generation_limit_reasons:
				if not report.limits_hit.has(limit_reason): report.limits_hit.append(limit_reason)
		var support_ids: Array = support_by_position.keys()
		support_ids.sort()
		var support_rows: Array[Dictionary] = []
		for identity_value in support_ids:
			support_rows.append(support_by_position[identity_value].duplicate(true))
		support_rows.sort_custom(Callable(self, "_candidate_less"))
		report.support_candidates_retained = []
		for support_row in support_rows:
			report.support_candidates_retained.append(support_row.duplicate(true))
		# The selected patch is the complete removal/replacement domain. Owner
		# provenance, however, comes only from the original cutoff residual seed
		# faces; adjacent C6 faces may not carry polygon ownership metadata.
		var context_result: Dictionary = _r3_make_expanded_patch_context(patch, patch_ids, seed_triangles, support_rows, boundary, all_triangles, residual_fixture, level)
		if not bool(context_result.get("valid", false)):
			level_report.candidate_triangle_count = _cxr_candidate_triangles_total - candidate_triangles_before_level
			report["candidate_triangle_count"] = int(report.get("candidate_triangle_count", 0)) + int(level_report.candidate_triangle_count)
			level_report.search_status = "NOT_RUN_R3_CONTEXT_INVALID"
			level_report.terminal_reason = String(context_result.get("reason", "r3_context_invalid"))
			level_report["context_failure"] = context_result
			report.levels.append(level_report)
			_append_unrun_cxr_levels(report, level + 1, "NOT_RUN_CONTEXT_FAILURE", level_report.terminal_reason)
			return _finish_cxr_cavity_search(report, {}, false, false, level_report.terminal_reason)
		var context: Dictionary = context_result.context
		context["phase"] = "r3"
		context["r3_cavity_boundary"] = boundary.duplicate(true)
		context["support_generation_usec"] = level_report.candidate_generation_usec
		print("R12CXR_R3_CAVITY_SEARCH_BEGIN " + JSON.stringify({"attempt_id": OS.get_environment("R12CXR_ATTEMPT_ID"), "source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "scenario_id": "R9.2.SEAM.XPLUS_EQUAL.v1", "cavity_id": cavity_id, "level": level, "cavity_seed_ids": seed_ids, "patch_triangle_count": patch.size(), "boundary_signature": boundary.get("signature", ""), "candidate_supports": support_rows.size(), "limits": _cxr_limits()}))
		var search_result: Dictionary = _r2_search_level(context)
		var search_disposition: Dictionary = _r3_search_disposition(search_result, support_generation_exhaustive)
		level_report.candidate_triangle_count = _cxr_candidate_triangles_total - candidate_triangles_before_level
		report["candidate_triangle_count"] = int(report.get("candidate_triangle_count", 0)) + int(level_report.candidate_triangle_count)
		level_report.search_nodes = int(search_result.get("search_nodes", context.get("search_nodes", 0)))
		level_report.branches = int(context.get("branches", 0))
		level_report.solutions = int(search_result.get("solution_count", 0))
		level_report.retained_solutions = search_result.get("retained_solutions", [])
		level_report.search_status = "COMPLETE_SOLUTION" if bool(search_result.get("valid", false)) else "COMPLETE_NO_SOLUTION" if bool(search_result.get("search_complete", false)) else "PARTIAL_LIMIT"
		level_report.terminal_reason = String(search_result.get("terminal_reason", "UNKNOWN_NOT_CAPTURED"))
		report.candidate_triangles.append_array(context.get("candidate_triangle_rows", []))
		var candidate_edge_keys: Array = context.get("candidate_edges", {}).keys()
		candidate_edge_keys.sort()
		for edge_key_value in candidate_edge_keys:
			report.candidate_edges.append(context.candidate_edges[edge_key_value])
		if bool(search_result.get("valid", false)):
			var selected: Dictionary = search_result.get("best_solution", {})
			var selected_supports: Array = selected.get("selected_supports", [])
			var replacement: Array[Dictionary] = selected.get("final_replacement_triangles", [])
			var patch_record: Dictionary = {"group_index": -1, "cavity_id": cavity_id, "level": level, "patch_triangle_ids": patch_ids.duplicate(), "cavity_seed_triangle_ids": seed_ids.duplicate(), "replacement_triangles": replacement.duplicate(true), "selected_supports": selected_supports.duplicate(true), "search_nodes": level_report.search_nodes, "search_usec": search_result.get("search_usec", "UNKNOWN_NOT_CAPTURED"), "search_phase": "r3", "boundary_signature": String(boundary.get("signature", "")), "boundary_provenance": "remaining_c6_edge_incidence", "boundary_diagnostics": boundary.get("incidence_diagnostics", []), "surface_diagnostics": selected.get("surface_diagnostics", "UNKNOWN_NOT_CAPTURED"), "candidate_triangle_count": level_report.candidate_triangle_count}
			var best: Dictionary = {"solution": {"selected_supports": selected_supports, "support_ids": selected.get("support_ids", []), "minimum_cross_squared": selected.get("minimum_cross_squared", "UNKNOWN_NOT_CAPTURED"), "surface_diagnostics": selected.get("surface_diagnostics", "UNKNOWN_NOT_CAPTURED"), "stable_score_key": selected.get("stable_score_key", "")}, "patch_ids": patch_ids.duplicate(), "patch_record": patch_record, "replacement_triangles": replacement.duplicate(true), "level": level}
			report.levels.append(level_report)
			report.solution_found_levels.append(level)
			report.search_nodes = _cxr_search_nodes_cavity
			report.branches = _cxr_active_cavity_branches
			report.prunes = _cxr_active_cavity_prunes
			report["search_nodes"] = _cxr_search_nodes_cavity
			report["branches"] = _cxr_active_cavity_branches.duplicate(true)
			report["prunes"] = _cxr_active_cavity_prunes.duplicate(true)
			report.retained_solutions.append_array(search_result.get("retained_solutions", []))
			return _finish_cxr_cavity_search(report, best, bool(search_disposition.get("complete", false)), bool(search_disposition.get("exhaustive", false)), String(search_disposition.get("terminal_reason", "valid_geometry_from_non_exhaustive_support_pool")))
		report.search_nodes = _cxr_search_nodes_cavity
		report.branches = _cxr_active_cavity_branches
		report.prunes = _cxr_active_cavity_prunes
		report["search_nodes"] = _cxr_search_nodes_cavity
		report["branches"] = _cxr_active_cavity_branches.duplicate(true)
		report["prunes"] = _cxr_active_cavity_prunes.duplicate(true)
		report.levels.append(level_report)
		if not bool(search_result.get("search_complete", false)):
			report.limits_hit.append(String(search_result.get("terminal_reason", "R3_SEARCH_PARTIAL")))
			_append_unrun_cxr_levels(report, level + 1, "NOT_RUN_SEARCH_LIMIT", String(search_result.get("terminal_reason", "r3_search_partial")))
			return _finish_cxr_cavity_search(report, {}, false, false, String(search_result.get("terminal_reason", "r3_search_partial")))
	if not any_valid_boundary_search:
		return _finish_cxr_cavity_search(report, {}, false, false, "r3_no_valid_cavity_boundary_level", false)
	if not support_generation_exhaustive:
		return _finish_cxr_cavity_search(report, {}, false, false, "r3_no_solution_with_non_exhaustive_support_generation")
	return _finish_cxr_cavity_search(report, {}, true, true, "r3_all_valid_cavity_levels_exhausted_no_solution")

func _r3_generation_requires_partial_stop(source_failed: bool, generation_limited: bool, retained_support_count: int) -> bool:
	return source_failed or (generation_limited and retained_support_count <= 0)

func _r3_search_disposition(search_result: Dictionary, support_generation_exhaustive: bool) -> Dictionary:
	var valid_geometry: bool = bool(search_result.get("valid", false))
	var complete: bool = bool(search_result.get("search_complete", false)) and support_generation_exhaustive
	var exhaustive: bool = bool(search_result.get("search_exhaustive", false)) and complete
	var reason: String = "minimum_valid_cavity_solution" if complete else "valid_geometry_from_non_exhaustive_support_pool" if valid_geometry else String(search_result.get("terminal_reason", "r3_search_partial"))
	return {"valid_geometry": valid_geometry, "complete": complete, "exhaustive": exhaustive, "terminal_reason": reason}

func _r3_invalid_level_reason(connectivity: Dictionary, boundary: Dictionary) -> String:
	if not bool(connectivity.get("valid", false)):
		var connectivity_reason: String = String(connectivity.get("reason", ""))
		if not connectivity_reason.is_empty():
			return connectivity_reason
	var boundary_reason: String = String(boundary.get("reason", ""))
	return boundary_reason if not boundary_reason.is_empty() else "r3_cavity_boundary_invalid"

func _cxr_failure_terminal_reason(phase: String, cavity_results: Array, expected_cavity_count: int, global_limit_reason: String, patch_overlap: bool = false) -> String:
	if not global_limit_reason.is_empty():
		return global_limit_reason
	if phase in ["r3", "r4"]:
		var phase_prefix: String = "r4" if phase == "r4" else "r3"
		if cavity_results.size() != expected_cavity_count or cavity_results.is_empty():
			return "UNKNOWN_NOT_CAPTURED"
		if patch_overlap:
			return phase_prefix + "_selected_patch_overlap_requires_alternative_solution_search"
		var invalid_boundary_count: int = 0
		var all_finite_exhausted: bool = true
		var all_results_complete: bool = true
		var valid_solution_count: int = 0
		var first_nonfinite_reason: String = ""
		for cavity_result in cavity_results:
			var cavity_reason: String = String(cavity_result.get("terminal_reason", "UNKNOWN_NOT_CAPTURED"))
			all_results_complete = all_results_complete and bool(cavity_result.get("search_complete", false)) and bool(cavity_result.get("search_exhaustive", false))
			if cavity_reason in ["r3_no_valid_cavity_boundary_level", "r4_boundary_domain_exhausted_within_declared_caps"]:
				invalid_boundary_count += 1
				all_finite_exhausted = false
			elif cavity_reason == "r3_all_valid_cavity_levels_exhausted_no_solution":
				pass
			elif bool(cavity_result.get("valid", false)) and cavity_reason == "minimum_valid_cavity_solution":
				valid_solution_count += 1
				all_finite_exhausted = false
			else:
				all_finite_exhausted = false
				if first_nonfinite_reason.is_empty(): first_nonfinite_reason = cavity_reason
		if invalid_boundary_count > 0:
			return "%s_cavity_boundary_domains_invalid:%d/%d" % [phase_prefix, invalid_boundary_count, expected_cavity_count]
		if all_finite_exhausted and all_results_complete:
			return phase_prefix + "_all_cavity_domains_finitely_exhausted_no_solution"
		if valid_solution_count > 0 and all_results_complete and first_nonfinite_reason.is_empty():
			return phase_prefix + "_unsolved_cavity_domain_exhausted_after_other_cavity_solution"
		return first_nonfinite_reason if not first_nonfinite_reason.is_empty() else "UNKNOWN_NOT_CAPTURED"
	return "finite_domain_exhausted_no_joint_solution"

func _cxr_failure_reason(phase: String, search_complete: bool, cavity_failure_reasons: Array[String]) -> String:
	if phase in ["r3", "r4"] and (cavity_failure_reasons.has("r3_no_valid_cavity_boundary_level") or cavity_failure_reasons.has("r4_boundary_domain_exhausted_within_declared_caps")):
		return "cxr_r4_cavity_boundary_domain_invalid" if phase == "r4" else "cxr_r3_cavity_boundary_domain_invalid"
	if not search_complete:
		return "cxr_search_partial"
	if phase in ["r3", "r4"]:
		return "cxr_r4_no_valid_constrained_triangulation" if phase == "r4" else "cxr_r3_no_valid_constrained_triangulation"
	if phase == "r2":
		return "cxr_r2_no_valid_constrained_triangulation"
	return "cxr_no_valid_field_support_solution"

func _r3_unrun_seed_metrics(seed_ids: Array, status: String) -> Dictionary:
	var result: Dictionary = {}
	for seed_id in seed_ids:
		result[String(seed_id)] = status
	return result

func _r3_patch_rows_for_ids(all_triangles: Array[Dictionary], patch_ids: Array, triangles_by_id: Dictionary = {}) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not triangles_by_id.is_empty():
		for triangle_id_value in patch_ids:
			var triangle: Dictionary = triangles_by_id.get(String(triangle_id_value), {})
			if not triangle.is_empty(): rows.append(triangle)
	else:
		var selected: Dictionary = {}
		for triangle_id_value in patch_ids: selected[String(triangle_id_value)] = true
		for triangle in all_triangles:
			if selected.has(String(triangle.get("triangle_id", ""))):
				rows.append(triangle)
	var already_sorted: bool = true
	for row_index in range(1, rows.size()):
		if String(rows[row_index - 1].get("triangle_id", "")) > String(rows[row_index].get("triangle_id", "")):
			already_sorted = false
			break
	if not already_sorted:
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("triangle_id", "")) < String(b.get("triangle_id", "")))
	return rows

func _r3_build_boundary_index(all_triangles: Array[Dictionary]) -> Dictionary:
	var triangles_by_id: Dictionary = {}
	var edge_rows_by_key: Dictionary = {}
	for triangle in all_triangles:
		var triangle_id: String = String(triangle.get("triangle_id", ""))
		if triangle_id.is_empty() or triangles_by_id.has(triangle_id):
			return {"valid": false, "reason": "r3_c6_triangle_identity_invalid", "triangle_id": triangle_id, "duplicate": triangles_by_id.has(triangle_id)}
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3:
			return {"valid": false, "reason": "r3_c6_triangle_arity_invalid", "triangle_id": triangle_id}
		triangles_by_id[triangle_id] = triangle
		for edge_index in range(3):
			var a_id: String = String(ids[edge_index])
			var b_id: String = String(ids[(edge_index + 1) % 3])
			if a_id.is_empty() or b_id.is_empty() or a_id == b_id:
				return {"valid": false, "reason": "r3_c6_edge_identity_invalid", "triangle_id": triangle_id}
			var edge_key: String = _edge_key(a_id, b_id)
			if not edge_rows_by_key.has(edge_key): edge_rows_by_key[edge_key] = []
			edge_rows_by_key[edge_key].append({"triangle_id": triangle_id, "a": a_id, "b": b_id})
	return {"valid": true, "triangles_by_id": triangles_by_id, "edge_rows_by_key": edge_rows_by_key, "triangle_count": all_triangles.size()}

func _r3_patch_rows_for_ids_indexed_for_test(all_triangles: Array[Dictionary], patch_ids: Array) -> Array[Dictionary]:
	var index: Dictionary = _r3_build_boundary_index(all_triangles)
	if not bool(index.get("valid", false)): return []
	return _r3_patch_rows_for_ids(all_triangles, patch_ids, index.get("triangles_by_id", {}))

func _r3_select_boundary_patch(seed_ids: Array, allowed_ids: Array, all_triangles: Array[Dictionary], adjacency: Dictionary, radius: int, residual_triangles: Array[Dictionary] = [], residual_fixture: Dictionary = {}) -> Dictionary:
	var allowed: Dictionary = {}
	var boundary_index: Dictionary = _r3_build_boundary_index(all_triangles)
	if not bool(boundary_index.get("valid", false)):
		return {"valid": false, "complete": false, "reason": String(boundary_index.get("reason", "r3_c6_boundary_index_invalid")), "search_nodes": 0, "candidate_subsets_examined": 0, "rejection_counts": {}}
	var triangles_by_id: Dictionary = boundary_index.get("triangles_by_id", {})
	for triangle_id_value in allowed_ids:
		allowed[String(triangle_id_value)] = true
	var sorted_seeds: Array[String] = []
	for seed_id_value in seed_ids:
		var seed_id: String = String(seed_id_value)
		if not allowed.has(seed_id) or not triangles_by_id.has(seed_id):
			return {"valid": false, "complete": true, "reason": "r3_cavity_seed_outside_radius_neighborhood", "radius": radius, "seed_id": seed_id, "search_nodes": 0, "candidate_subsets_examined": 0, "rejection_counts": {}}
		sorted_seeds.append(seed_id)
	sorted_seeds.sort()
	if sorted_seeds.is_empty():
		return {"valid": false, "complete": true, "reason": "r3_cavity_seed_set_empty", "radius": radius, "search_nodes": 0, "candidate_subsets_examined": 0, "rejection_counts": {}}
	var root_id: String = sorted_seeds[0]
	var layer: Array = [[root_id]]
	var seen: Dictionary = {_r3_patch_subset_key([root_id]): true}
	var generated_nodes: int = 1
	var observed_offending_expansion_ids: Dictionary = {}
	var initial_limit: String = _cxr_time_limit_reason()
	if initial_limit.is_empty():
		initial_limit = _cxr_global_limit_reason()
	if initial_limit.is_empty() and (_cxr_search_nodes_cavity >= CXR_R2_MAX_SEARCH_STATES_PER_CAVITY or _cxr_search_nodes_total >= CXR_R2_MAX_SEARCH_STATES_TOTAL):
		initial_limit = "R2_MAX_SEARCH_STATES"
	if not initial_limit.is_empty():
		return {"valid": false, "complete": false, "limit_reason": initial_limit, "radius": radius, "search_nodes": 0, "candidate_subsets_examined": 0, "rejection_counts": {}, "states_generated": 0}
	_cxr_search_nodes_total += 1
	_cxr_search_nodes_cavity += 1
	_cxr_patch_selection_nodes_total += 1
	var candidate_subsets_examined: int = 0
	var rejection_counts: Dictionary = {}
	var context_rejection_count: int = 0
	var context_rejections: Array[Dictionary] = []
	while not layer.is_empty():
		var next_layer: Array = []
		for subset_value in layer:
			var limit_reason: String = _cxr_time_limit_reason()
			if limit_reason.is_empty():
				limit_reason = _cxr_global_limit_reason()
			if limit_reason.is_empty() and (_cxr_search_nodes_cavity >= CXR_R2_MAX_SEARCH_STATES_PER_CAVITY or _cxr_search_nodes_total >= CXR_R2_MAX_SEARCH_STATES_TOTAL):
				limit_reason = "R2_MAX_SEARCH_STATES"
			if not limit_reason.is_empty():
				return {"valid": false, "complete": false, "limit_reason": limit_reason, "radius": radius, "search_nodes": generated_nodes, "candidate_subsets_examined": candidate_subsets_examined, "rejection_counts": rejection_counts, "context_rejection_count": context_rejection_count, "context_rejections": context_rejections, "states_generated": generated_nodes}
			var subset: Array = subset_value.duplicate()
			var boundary_for_expansion: Dictionary = {}
			var contains_all_seeds: bool = true
			for seed_id in sorted_seeds:
				if not subset.has(seed_id):
					contains_all_seeds = false
					break
			if contains_all_seeds:
				candidate_subsets_examined += 1
				var patch: Array[Dictionary] = _r3_patch_rows_for_ids(all_triangles, subset, triangles_by_id)
				var boundary_screen: Dictionary = _r3_derive_remaining_boundary(all_triangles, subset, boundary_index, false)
				boundary_for_expansion = boundary_screen
				if bool(boundary_screen.get("valid", false)):
					var boundary: Dictionary = _r3_derive_remaining_boundary(all_triangles, subset, boundary_index, true)
					if not bool(boundary.get("valid", false)) or String(boundary.get("reason", "")) != String(boundary_screen.get("reason", "")) or boundary.get("directed_edges", []) != boundary_screen.get("directed_edges", []) or String(boundary.get("signature", "")) != String(boundary_screen.get("signature", "")):
						return {"valid": false, "complete": false, "limit_reason": "r3_boundary_screen_full_diagnostic_mismatch", "reason": "r3_boundary_screen_full_diagnostic_mismatch", "radius": radius, "search_nodes": generated_nodes, "candidate_subsets_examined": candidate_subsets_examined, "rejection_counts": rejection_counts, "context_rejection_count": context_rejection_count, "context_rejections": context_rejections, "states_generated": generated_nodes, "offending_expansion_candidate_ids": _sorted_keys(observed_offending_expansion_ids)}
					var connectivity: Dictionary = _r3_patch_connectivity(patch)
					if bool(connectivity.get("valid", false)):
						if residual_triangles.is_empty():
							return {"valid": true, "complete": true, "radius": radius, "patch_triangle_ids": subset.duplicate(), "patch_triangles": patch, "connectivity": connectivity, "boundary": boundary, "context_preflight_valid": false, "context_rejection_count": context_rejection_count, "context_rejections": context_rejections, "search_nodes": generated_nodes, "candidate_subsets_examined": candidate_subsets_examined, "rejection_counts": rejection_counts, "states_generated": generated_nodes, "offending_expansion_candidate_ids": _sorted_keys(observed_offending_expansion_ids)}
						# A manifold boundary can still be unusable by R2's planar domain.
						# Reject only that candidate subset and continue bounded connected
						# expansion; source/provenance defects remain fatal below.
						var preflight: Dictionary = _r3_make_expanded_patch_context(patch, subset, residual_triangles, [], boundary, all_triangles, residual_fixture, radius, true)
						if bool(preflight.get("valid", false)):
							return {"valid": true, "complete": true, "radius": radius, "patch_triangle_ids": subset.duplicate(), "patch_triangles": patch, "connectivity": connectivity, "boundary": boundary, "context_preflight_valid": true, "context_rejection_count": context_rejection_count, "context_rejections": context_rejections, "search_nodes": generated_nodes, "candidate_subsets_examined": candidate_subsets_examined, "rejection_counts": rejection_counts, "states_generated": generated_nodes, "offending_expansion_candidate_ids": _sorted_keys(observed_offending_expansion_ids)}
						var preflight_reason: String = String(preflight.get("reason", "r3_context_preflight_invalid"))
						if not _r3_context_failure_is_patch_domain_limited(preflight_reason):
							return {"valid": false, "complete": false, "limit_reason": "r3_context_preflight_source_invalid:" + preflight_reason, "reason": preflight_reason, "radius": radius, "search_nodes": generated_nodes, "candidate_subsets_examined": candidate_subsets_examined, "rejection_counts": rejection_counts, "context_rejection_count": context_rejection_count, "context_rejections": context_rejections, "states_generated": generated_nodes}
						context_rejection_count += 1
						_cxr_count(rejection_counts, preflight_reason)
						if context_rejections.size() < 64:
							var context_diagnostic: Dictionary = {"patch_triangle_ids": subset.duplicate(), "reason": preflight_reason}
							if preflight.has("arc_diagnostics"):
								var arc_diagnostic: Dictionary = preflight.get("arc_diagnostics", {})
								for key in ["arc_id", "root_ids"]:
									if arc_diagnostic.has(key): context_diagnostic[key] = arc_diagnostic[key]
							context_rejections.append(context_diagnostic)
						var context_limit: String = _cxr_time_limit_reason()
						if context_limit.is_empty(): context_limit = _cxr_global_limit_reason()
						if not context_limit.is_empty():
							return {"valid": false, "complete": false, "limit_reason": context_limit, "radius": radius, "search_nodes": generated_nodes, "candidate_subsets_examined": candidate_subsets_examined, "rejection_counts": rejection_counts, "context_rejection_count": context_rejection_count, "context_rejections": context_rejections, "states_generated": generated_nodes}
					else:
						_cxr_count(rejection_counts, String(connectivity.get("reason", "r3_cavity_patch_disconnected")))
				else:
					_cxr_count(rejection_counts, String(boundary_screen.get("reason", "r3_cavity_boundary_invalid")))
			var subset_ids: Array[String] = []
			for triangle_id_value in subset:
				subset_ids.append(String(triangle_id_value))
			var subset_id_set: Dictionary = {}
			for triangle_id in subset_ids: subset_id_set[triangle_id] = true
			var priority_neighbors: Array[String] = []
			if contains_all_seeds and not bool(boundary_for_expansion.get("valid", true)):
				priority_neighbors = _r3_boundary_expansion_candidate_ids(boundary_for_expansion, subset_ids, adjacency, allowed_ids)
				for priority_id in priority_neighbors: observed_offending_expansion_ids[priority_id] = true
			var ordered_neighbors: Array[String] = []
			var ordered_neighbor_set: Dictionary = {}
			for priority_id in priority_neighbors:
				if not ordered_neighbor_set.has(priority_id):
					ordered_neighbors.append(priority_id)
					ordered_neighbor_set[priority_id] = true
			var fallback_neighbors: Dictionary = {}
			for triangle_id in subset_ids:
				var neighbor_row_value: Variant = adjacency.get(triangle_id, {})
				if not (neighbor_row_value is Dictionary):
					return {"valid": false, "complete": true, "reason": "r3_patch_adjacency_row_invalid", "radius": radius, "search_nodes": generated_nodes, "candidate_subsets_examined": candidate_subsets_examined, "rejection_counts": rejection_counts, "states_generated": generated_nodes, "offending_expansion_candidate_ids": _sorted_keys(observed_offending_expansion_ids)}
				var neighbor_map: Dictionary = neighbor_row_value
				var neighbors: Array = neighbor_map.keys()
				neighbors.sort()
				for neighbor_value in neighbors:
					var neighbor_id: String = String(neighbor_value)
					if allowed.has(neighbor_id) and not subset_id_set.has(neighbor_id) and not ordered_neighbor_set.has(neighbor_id):
						fallback_neighbors[neighbor_id] = true
			var fallback_ids: Array = fallback_neighbors.keys()
			fallback_ids.sort()
			for fallback_id_value in fallback_ids:
				ordered_neighbors.append(String(fallback_id_value))
			for neighbor_id in ordered_neighbors:
				var expanded: Array[String] = subset_ids.duplicate()
				expanded.append(neighbor_id)
				expanded.sort()
				if expanded.size() > CXR_MAX_PATCH_TRIANGLES:
					continue
				var expanded_key: String = _r3_patch_subset_key(expanded)
				if seen.has(expanded_key):
					continue
				limit_reason = _cxr_time_limit_reason()
				if limit_reason.is_empty():
					limit_reason = _cxr_global_limit_reason()
				if limit_reason.is_empty() and (_cxr_search_nodes_cavity >= CXR_R2_MAX_SEARCH_STATES_PER_CAVITY or _cxr_search_nodes_total >= CXR_R2_MAX_SEARCH_STATES_TOTAL):
					limit_reason = "R2_MAX_SEARCH_STATES"
				if not limit_reason.is_empty():
					return {"valid": false, "complete": false, "limit_reason": limit_reason, "radius": radius, "search_nodes": generated_nodes, "candidate_subsets_examined": candidate_subsets_examined, "rejection_counts": rejection_counts, "context_rejection_count": context_rejection_count, "context_rejections": context_rejections, "states_generated": generated_nodes, "offending_expansion_candidate_ids": _sorted_keys(observed_offending_expansion_ids)}
				seen[expanded_key] = true
				generated_nodes += 1
				_cxr_search_nodes_total += 1
				_cxr_search_nodes_cavity += 1
				_cxr_patch_selection_nodes_total += 1
				next_layer.append(expanded)
		layer = next_layer
	var terminal_reason: String = "r3_no_context_valid_patch_subset" if context_rejection_count > 0 else "r3_no_boundary_valid_patch_subset"
	return {"valid": false, "complete": true, "reason": terminal_reason, "radius": radius, "search_nodes": generated_nodes, "candidate_subsets_examined": candidate_subsets_examined, "rejection_counts": rejection_counts, "context_rejection_count": context_rejection_count, "context_rejections": context_rejections, "states_generated": generated_nodes, "offending_expansion_candidate_ids": _sorted_keys(observed_offending_expansion_ids)}

func select_boundary_first_patch_for_test(seed_ids: Array, all_triangles: Array[Dictionary], adjacency: Dictionary, residual_triangles: Array[Dictionary], support_rows: Array[Dictionary], residual_fixture: Dictionary, level: int = 2) -> Dictionary:
	return _r4_select_boundary_first_patch(seed_ids, _r3_sorted_triangle_ids(all_triangles), all_triangles, adjacency, residual_triangles, support_rows, residual_fixture, level)

func _r3_sorted_triangle_ids(all_triangles: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for triangle in all_triangles:
		ids.append(String(triangle.get("triangle_id", "")))
	ids.sort()
	return ids

func _r4_select_boundary_first_patch(seed_ids: Array, allowed_ids: Array, all_triangles: Array[Dictionary], adjacency: Dictionary, residual_triangles: Array[Dictionary], support_rows: Array[Dictionary], residual_fixture: Dictionary, level: int) -> Dictionary:
	var index: Dictionary = _r3_build_boundary_index(all_triangles)
	if not bool(index.get("valid", false)):
		return {"valid": false, "complete": true, "reason": String(index.get("reason", "r4_boundary_index_invalid")), "search_nodes": 0}
	var allowed: Dictionary = {}
	for id_value in allowed_ids: allowed[String(id_value)] = true
	var normalized_seeds: Array[String] = []
	for id_value in seed_ids:
		var seed_id: String = String(id_value)
		if seed_id.is_empty() or not allowed.has(seed_id) or normalized_seeds.has(seed_id):
			return {"valid": false, "complete": true, "reason": "r4_boundary_seed_identity_invalid", "seed_id": seed_id, "search_nodes": 0}
		normalized_seeds.append(seed_id)
	normalized_seeds.sort()
	if normalized_seeds.is_empty() or normalized_seeds.size() > CXR_R4_MAX_REMOVED_FACES:
		return {"valid": false, "complete": true, "reason": "r4_boundary_seed_count_invalid", "search_nodes": 0}
	var queue: Array[Dictionary] = [{"patch_ids": normalized_seeds, "expansion_causes": []}]
	var visited: Dictionary = {JSON.stringify(normalized_seeds): true}
	var rejection_counts: Dictionary = {}
	var expansion_log: Array[Dictionary] = []
	var states: int = 0
	var queue_peak: int = 1
	var began_usec: int = Time.get_ticks_usec()
	var best_multi_loop: Dictionary = {}
	while not queue.is_empty():
		if Time.get_ticks_usec() - began_usec >= CXR_R4_MAX_BOUNDARY_USEC:
			return {"valid": false, "complete": false, "reason": "r4_boundary_wall_time_limit", "search_nodes": states, "queue_peak": queue_peak, "rejection_counts": rejection_counts, "expansion_log": expansion_log}
		if states >= CXR_R4_MAX_BOUNDARY_STATES:
			return {"valid": false, "complete": false, "reason": "r4_boundary_state_limit", "search_nodes": states, "queue_peak": queue_peak, "rejection_counts": rejection_counts, "expansion_log": expansion_log}
		queue.sort_custom(Callable(self, "_r4_boundary_state_less"))
		var state: Dictionary = queue.pop_front()
		var patch_ids: Array[String] = state.get("patch_ids", []).duplicate()
		states += 1
		_cxr_search_nodes_total += 1
		_cxr_search_nodes_cavity += 1
		if patch_ids.size() > CXR_R4_MAX_REMOVED_FACES:
			_r4_count(rejection_counts, "max_removed_faces")
			continue
		var patch: Array[Dictionary] = _r3_patch_rows_for_ids(all_triangles, patch_ids)
		if patch.size() != patch_ids.size():
			return {"valid": false, "complete": true, "reason": "r4_patch_face_missing", "patch_ids": patch_ids, "search_nodes": states}
		var boundary: Dictionary = _r3_derive_remaining_boundary(all_triangles, patch_ids, index, true)
		if not bool(boundary.get("valid", false)) and typeof(boundary.get("invalid_reasons", [])) == TYPE_ARRAY and not boundary.get("invalid_reasons", []).is_empty():
			var invalid_edges: Array[String] = _r4_boundary_invalid_edges(boundary)
			_r4_count(rejection_counts, "boundary_incidence_invalid")
			var candidates: Array[String] = _r4_boundary_candidate_faces(boundary, patch_ids, adjacency, allowed, invalid_edges)
			var expansion: Dictionary = {"cause": "boundary_incidence_defect", "patch_ids": patch_ids, "offending_edges": invalid_edges, "candidate_face_ids": candidates}
			if expansion_log.size() < 512: expansion_log.append(expansion)
			_r4_enqueue_boundary_candidates(candidates, patch_ids, state, queue, visited)
		else:
			var cycles: Dictionary = _r4_boundary_cycle_set(boundary)
			if not bool(cycles.get("valid", false)):
				_r4_count(rejection_counts, String(cycles.get("reason", "boundary_cycle_invalid")))
				var cycle_candidates: Array[String] = _r4_cycle_defect_candidate_faces(cycles, boundary, patch_ids, adjacency, allowed)
				if expansion_log.size() < 512: expansion_log.append({"cause": "boundary_cycle_defect", "patch_ids": patch_ids, "cycle_diagnostics": cycles, "candidate_face_ids": cycle_candidates})
				_r4_enqueue_boundary_candidates(cycle_candidates, patch_ids, state, queue, visited)
			elif int(cycles.get("component_count", 0)) > CXR_R4_MAX_BOUNDARY_COMPONENTS:
				return {"valid": false, "complete": false, "reason": "r4_boundary_component_limit", "search_nodes": states, "queue_peak": queue_peak, "boundary_components": cycles.get("component_count", 0), "expansion_log": expansion_log}
			else:
				var projected_cycles: Dictionary = _r4_project_boundary_cycles(cycles.get("cycles", []), patch)
				var nesting: Dictionary = {"valid": false, "reason": String(projected_cycles.get("reason", "r4_boundary_projection_invalid"))}
				if bool(projected_cycles.get("valid", false)):
					nesting = _r4_classify_boundary_cycle_nesting(cycles.get("cycles", []), projected_cycles.get("projected_positions", {}))
				if not bool(nesting.get("valid", false)):
					var nesting_reason: String = String(nesting.get("reason", "r4_boundary_nesting_invalid"))
					_r4_count(rejection_counts, nesting_reason)
					var nesting_edges: Array[String] = []
					for cycle_value in cycles.get("cycles", []):
						var cycle_row: Dictionary = cycle_value
						var cycle_ids: Array = cycle_row.get("root_ids", [])
						for cycle_index in range(cycle_ids.size()):
							nesting_edges.append(_edge_key(String(cycle_ids[cycle_index]), String(cycle_ids[(cycle_index + 1) % cycle_ids.size()])))
					nesting_edges.sort()
					var nesting_candidates: Array[String] = _r4_boundary_candidate_faces(boundary, patch_ids, adjacency, allowed, nesting_edges)
					if expansion_log.size() < 512:
						expansion_log.append({"cause": "boundary_projected_cycle_invalid:" + nesting_reason, "patch_ids": patch_ids, "cycle_diagnostics": nesting, "candidate_face_ids": nesting_candidates})
					_r4_enqueue_boundary_candidates(nesting_candidates, patch_ids, state, queue, visited)
					if queue.size() > queue_peak: queue_peak = queue.size()
					continue
				cycles["cycles"] = nesting.get("cycles", [])
				cycles["nesting"] = nesting.get("nesting", "UNKNOWN_NOT_CAPTURED")
				boundary["valid"] = true
				boundary["reason"] = ""
				boundary["cycle_set"] = cycles.get("cycles", [])
				boundary["boundary_component_count"] = cycles.get("component_count", 0)
				if String(boundary.get("signature", "")).is_empty(): boundary["signature"] = String(cycles.get("signature", ""))
				if int(cycles.get("component_count", 0)) > 1:
					if best_multi_loop.is_empty():
						best_multi_loop = {"patch_ids": patch_ids.duplicate(), "patch": patch.duplicate(true), "boundary": boundary.duplicate(true), "cycles": cycles.duplicate(true), "expansion_causes": state.get("expansion_causes", []).duplicate(true)}
					_r4_count(rejection_counts, "valid_multi_loop_boundary_requires_hole_aware_triangulator")
				else:
					var context: Dictionary = _r3_make_expanded_patch_context(patch, patch_ids, residual_triangles, support_rows, boundary, all_triangles, residual_fixture, level, true)
					if bool(context.get("valid", false)):
						return {"valid": true, "complete": true, "reason": "", "patch_triangle_ids": patch_ids, "patch_triangles": patch, "connectivity": _r3_patch_connectivity(patch), "boundary": boundary, "context_preflight": context, "search_nodes": states, "queue_peak": queue_peak, "rejection_counts": rejection_counts, "expansion_log": expansion_log, "expansion_causes": state.get("expansion_causes", []).duplicate(true), "boundary_cycles": cycles.get("cycles", [])}
					var context_reason: String = String(context.get("reason", "r4_context_preflight_invalid"))
					_r4_count(rejection_counts, context_reason)
					var context_candidates: Array[String] = []
					var arc_expansion: Dictionary = {}
					if context_reason == "r2_topology_arc_crosses_cavity_boundary":
						arc_expansion = _r4_arc_crossing_boundary_candidates(context, patch, boundary, patch_ids, adjacency, allowed)
						context_candidates = arc_expansion.get("candidate_face_ids", [])
					if expansion_log.size() < 512: expansion_log.append({"cause": "context_preflight:" + context_reason, "patch_ids": patch_ids, "context": context, "arc_expansion": arc_expansion, "candidate_face_ids": context_candidates})
					_r4_enqueue_boundary_candidates(context_candidates, patch_ids, state, queue, visited)
			if queue.size() > queue_peak: queue_peak = queue.size()
		if queue.size() > CXR_R4_MAX_QUEUE_SIZE:
			return {"valid": false, "complete": false, "reason": "r4_boundary_queue_limit", "search_nodes": states, "queue_peak": queue_peak, "rejection_counts": rejection_counts, "expansion_log": expansion_log}
	if not best_multi_loop.is_empty():
		return {"valid": true, "complete": true, "reason": "r4_valid_multi_loop_boundary_d3_hole_support_required", "patch_triangle_ids": best_multi_loop.patch_ids, "patch_triangles": best_multi_loop.patch, "connectivity": _r3_patch_connectivity(best_multi_loop.patch), "boundary": best_multi_loop.boundary, "boundary_cycles": best_multi_loop.cycles, "search_nodes": states, "queue_peak": queue_peak, "rejection_counts": rejection_counts, "expansion_log": expansion_log, "expansion_causes": best_multi_loop.expansion_causes, "triangulation_supported": false}
	return {"valid": false, "complete": true, "reason": "r4_boundary_domain_exhausted_within_declared_caps", "search_nodes": states, "queue_peak": queue_peak, "rejection_counts": rejection_counts, "expansion_log": expansion_log, "domain_face_cap": CXR_R4_MAX_REMOVED_FACES}

func _r4_boundary_state_less(a: Dictionary, b: Dictionary) -> bool:
	var a_ids: Array = a.get("patch_ids", [])
	var b_ids: Array = b.get("patch_ids", [])
	if a_ids.size() != b_ids.size(): return a_ids.size() < b_ids.size()
	var a_defects: int = int(a.get("defect_count", 0))
	var b_defects: int = int(b.get("defect_count", 0))
	if a_defects != b_defects: return a_defects < b_defects
	var a_components: int = int(a.get("component_count", 0))
	var b_components: int = int(b.get("component_count", 0))
	if a_components != b_components: return a_components < b_components
	return JSON.stringify(a_ids) < JSON.stringify(b_ids)

func _r4_count(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1

func _r4_enqueue_boundary_candidates(candidates: Array[String], patch_ids: Array[String], state: Dictionary, queue: Array[Dictionary], visited: Dictionary) -> void:
	for candidate_id in candidates:
		var next_ids: Array[String] = patch_ids.duplicate()
		if next_ids.has(candidate_id): continue
		next_ids.append(candidate_id)
		next_ids.sort()
		if next_ids.size() > CXR_R4_MAX_REMOVED_FACES: continue
		var key: String = JSON.stringify(next_ids)
		if visited.has(key): continue
		visited[key] = true
		var causes: Array = state.get("expansion_causes", []).duplicate(true)
		causes.append(candidate_id)
		queue.append({"patch_ids": next_ids, "expansion_causes": causes, "defect_count": maxi(0, candidates.size() - 1)})

func _r4_boundary_invalid_edges(boundary: Dictionary) -> Array[String]:
	var edges: Dictionary = {}
	for value in boundary.get("invalid_reasons", []):
		if value is Dictionary and not String(value.get("edge_key", "")).is_empty(): edges[String(value.edge_key)] = true
		if value is Dictionary and not String(value.get("vertex", "")).is_empty():
			var vertex: String = String(value.vertex)
			for incidence_value in boundary.get("incidence_diagnostics", []):
				var incidence: Dictionary = incidence_value
				for row_value in incidence.get("removed_rows", []) + incidence.get("remaining_rows", []):
					var row: Dictionary = row_value
					if String(row.get("a", "")) == vertex or String(row.get("b", "")) == vertex: edges[String(incidence.get("edge_key", ""))] = true
	var result: Array[String] = []
	for edge in edges.keys(): result.append(String(edge))
	result.sort()
	return result

func _r4_boundary_cycle_set(boundary: Dictionary) -> Dictionary:
	var directed_edges: Array = boundary.get("directed_edges", [])
	if directed_edges.is_empty(): return {"valid": false, "reason": "r4_boundary_empty", "offending_edges": []}
	var successors: Dictionary = {}
	var incoming: Dictionary = {}
	var outgoing_edges_by_vertex: Dictionary = {}
	var incoming_edges_by_vertex: Dictionary = {}
	for edge_value in directed_edges:
		var split: PackedStringArray = String(edge_value).split("->")
		if split.size() != 2 or split[0].is_empty() or split[1].is_empty(): return {"valid": false, "reason": "r4_boundary_directed_edge_invalid", "offending_edges": [String(edge_value)]}
		var a: String = String(split[0]); var b: String = String(split[1])
		if successors.has(a) or incoming.has(b):
			var offending_edges: Array[String] = []
			if successors.has(a):
				for existing_outgoing_value in outgoing_edges_by_vertex.get(a, []): offending_edges.append(String(existing_outgoing_value))
			if incoming.has(b):
				for existing_incoming_value in incoming_edges_by_vertex.get(b, []): offending_edges.append(String(existing_incoming_value))
			offending_edges.append(String(edge_value))
			offending_edges.sort()
			return {"valid": false, "reason": "r4_boundary_vertex_degree_not_one_in_one_out", "vertex": a if successors.has(a) else b, "offending_edges": offending_edges}
		successors[a] = b; incoming[b] = a
		if not outgoing_edges_by_vertex.has(a): outgoing_edges_by_vertex[a] = []
		if not incoming_edges_by_vertex.has(b): incoming_edges_by_vertex[b] = []
		outgoing_edges_by_vertex[a].append(String(edge_value)); incoming_edges_by_vertex[b].append(String(edge_value))
	if successors.size() != incoming.size(): return {"valid": false, "reason": "r4_boundary_vertex_degree_mismatch", "offending_edges": directed_edges.duplicate()}
	var starts: Array = successors.keys(); starts.sort()
	var visited_vertices: Dictionary = {}
	var cycles: Array = []
	for start_value in starts:
		var start: String = String(start_value)
		if visited_vertices.has(start): continue
		var current: String = start
		var cycle: Array[String] = []
		while not visited_vertices.has(current):
			visited_vertices[current] = true; cycle.append(current)
			if not successors.has(current): return {"valid": false, "reason": "r4_boundary_open_chain", "vertex": current, "offending_edges": outgoing_edges_by_vertex.get(current, [])}
			current = String(successors[current])
		if current != start or cycle.size() < 3: return {"valid": false, "reason": "r4_boundary_cycle_invalid", "vertex": current, "offending_edges": directed_edges.duplicate()}
		var minimum_id: String = String(cycle[0]); var minimum_index: int = 0
		for index in range(1, cycle.size()):
			if String(cycle[index]) < minimum_id: minimum_id = String(cycle[index]); minimum_index = index
		var rotated: Array[String] = []
		for offset in range(cycle.size()): rotated.append(String(cycle[(minimum_index + offset) % cycle.size()]))
		cycles.append({"root_ids": rotated, "orientation": "remaining_face_directed_boundary", "nesting": "UNCLASSIFIED_NO_PROJECTED_GEOMETRY"})
	cycles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return JSON.stringify(a.root_ids) < JSON.stringify(b.root_ids))
	var normalized_edges: Array[String] = []
	for edge_value in directed_edges: normalized_edges.append(String(edge_value))
	normalized_edges.sort()
	return {"valid": true, "reason": "", "cycles": cycles, "component_count": cycles.size(), "signature": Core.sha256(JSON.stringify(normalized_edges).to_utf8_buffer()), "orientation_source": "remaining_C6_face_winding", "nesting": "UNCLASSIFIED_REQUIRES_PROJECTED_GEOMETRY"}

func _r4_project_boundary_cycles(cycles: Array, patch: Array[Dictionary]) -> Dictionary:
	if cycles.is_empty() or patch.is_empty(): return {"valid": false, "reason": "r4_boundary_projection_inputs_empty"}
	var normal: Vector3 = Vector3.ZERO
	for triangle in patch:
		var triangle_normal: Vector3 = Vector3(triangle.get("normal", Vector3.ZERO))
		if triangle_normal.length_squared() <= 1e-20:
			var points: Array = triangle.get("points", [])
			if points.size() != 3: return {"valid": false, "reason": "r4_boundary_projection_triangle_geometry_invalid", "triangle_id": triangle.get("triangle_id", "")}
			triangle_normal = (Vector3(points[1]) - Vector3(points[0])).cross(Vector3(points[2]) - Vector3(points[0]))
		if not triangle_normal.is_finite() or triangle_normal.length_squared() <= 1e-20: return {"valid": false, "reason": "r4_boundary_projection_triangle_normal_invalid", "triangle_id": triangle.get("triangle_id", "")}
		normal += triangle_normal.normalized()
	if not normal.is_finite() or normal.length_squared() <= 1e-20: return {"valid": false, "reason": "r4_boundary_projection_normal_ambiguous"}
	normal = normal.normalized()
	var first_cycle: Dictionary = cycles[0]
	var first_ids: Array = first_cycle.get("root_ids", [])
	if first_ids.size() < 3: return {"valid": false, "reason": "r4_boundary_projection_cycle_invalid"}
	var origin_id: String = String(first_ids[0])
	if not _root_positions.has(origin_id): return {"valid": false, "reason": "r4_boundary_projection_root_missing", "root_id": origin_id}
	var origin: Vector3 = Vector3(_root_positions[origin_id])
	var axis_u: Vector3 = Vector3.ZERO
	for cycle_index in range(first_ids.size()):
		var next_id: String = String(first_ids[(cycle_index + 1) % first_ids.size()])
		if not _root_positions.has(next_id): return {"valid": false, "reason": "r4_boundary_projection_root_missing", "root_id": next_id}
		var edge: Vector3 = Vector3(_root_positions[next_id]) - origin
		edge -= normal * edge.dot(normal)
		if edge.length_squared() > 1e-20:
			axis_u = edge.normalized()
			break
	if axis_u.length_squared() <= 1e-20: return {"valid": false, "reason": "r4_boundary_projection_axis_missing"}
	var axis_v: Vector3 = normal.cross(axis_u).normalized()
	if axis_v.length_squared() <= 1e-20: return {"valid": false, "reason": "r4_boundary_projection_second_axis_missing"}
	var projected_positions: Dictionary = {}
	for cycle_value in cycles:
		var cycle: Dictionary = cycle_value
		for root_id_value in cycle.get("root_ids", []):
			var root_id: String = String(root_id_value)
			if projected_positions.has(root_id): continue
			if not _root_positions.has(root_id): return {"valid": false, "reason": "r4_boundary_projection_root_missing", "root_id": root_id}
			var delta: Vector3 = Vector3(_root_positions[root_id]) - origin
			var projected: Vector2 = Vector2(delta.dot(axis_u), delta.dot(axis_v))
			if not projected.is_finite(): return {"valid": false, "reason": "r4_boundary_projection_nonfinite_root", "root_id": root_id}
			projected_positions[root_id] = projected
	return {"valid": true, "origin": origin, "normal": normal, "axis_u": axis_u, "axis_v": axis_v, "projected_positions": projected_positions, "projection": "patch_normal_orthonormal_plane"}

func _r4_classify_boundary_cycle_nesting(cycles: Array, projected_positions: Dictionary) -> Dictionary:
	if cycles.is_empty(): return {"valid": false, "reason": "r4_nesting_cycle_set_empty"}
	var polygons: Array[Array] = []
	var signed_areas: Array[float] = []
	for cycle_value in cycles:
		if typeof(cycle_value) != TYPE_DICTIONARY: return {"valid": false, "reason": "r4_nesting_cycle_record_invalid"}
		var cycle: Dictionary = cycle_value
		var root_ids: Array = cycle.get("root_ids", [])
		if root_ids.size() < 3: return {"valid": false, "reason": "r4_nesting_cycle_arity_invalid"}
		var polygon: Array[Vector2] = []
		for root_id_value in root_ids:
			var root_id: String = String(root_id_value)
			if not projected_positions.has(root_id): return {"valid": false, "reason": "r4_nesting_projected_root_missing", "root_id": root_id}
			var point_value: Variant = projected_positions[root_id]
			if typeof(point_value) != TYPE_VECTOR2 or not Vector2(point_value).is_finite(): return {"valid": false, "reason": "r4_nesting_projected_root_invalid", "root_id": root_id}
			polygon.append(Vector2(point_value))
		var area: float = _r2_polygon_signed_area(polygon)
		if not is_finite(area) or area == 0.0: return {"valid": false, "reason": "r4_nesting_cycle_area_zero_or_nonfinite", "root_ids": root_ids}
		for first_edge in range(polygon.size()):
			var first_next: int = (first_edge + 1) % polygon.size()
			if polygon[first_edge] == polygon[first_next]: return {"valid": false, "reason": "r4_nesting_zero_length_cycle_edge", "root_ids": root_ids, "edge_index": first_edge}
			for second_edge in range(first_edge + 1, polygon.size()):
				var second_next: int = (second_edge + 1) % polygon.size()
				if first_edge == second_edge or first_next == second_edge or second_next == first_edge: continue
				if _r4_segments_touch_or_cross(polygon[first_edge], polygon[first_next], polygon[second_edge], polygon[second_next]): return {"valid": false, "reason": "r4_nesting_cycle_self_intersection", "root_ids": root_ids, "edge_indices": [first_edge, second_edge]}
		polygons.append(polygon)
		signed_areas.append(area)
	for first_cycle_index in range(polygons.size()):
		for second_cycle_index in range(first_cycle_index + 1, polygons.size()):
			var first_polygon: Array[Vector2] = polygons[first_cycle_index]
			var second_polygon: Array[Vector2] = polygons[second_cycle_index]
			for first_edge in range(first_polygon.size()):
				for second_edge in range(second_polygon.size()):
					if _r4_segments_touch_or_cross(first_polygon[first_edge], first_polygon[(first_edge + 1) % first_polygon.size()], second_polygon[second_edge], second_polygon[(second_edge + 1) % second_polygon.size()]):
						return {"valid": false, "reason": "r4_nesting_cycles_touch_or_cross", "cycle_indices": [first_cycle_index, second_cycle_index], "edge_indices": [first_edge, second_edge]}
	var parent_indices: Array[int] = []
	for cycle_index in range(polygons.size()):
		var parent_index: int = -1
		var parent_area: float = INF
		for candidate_index in range(polygons.size()):
			if candidate_index == cycle_index: continue
			if not _r2_point_in_polygon(polygons[cycle_index][0], polygons[candidate_index], 0.0): continue
			var candidate_area: float = absf(signed_areas[candidate_index])
			if candidate_area <= absf(signed_areas[cycle_index]): return {"valid": false, "reason": "r4_nesting_containment_area_order_invalid", "cycle_indices": [cycle_index, candidate_index]}
			if candidate_area < parent_area:
				parent_area = candidate_area
				parent_index = candidate_index
		parent_indices.append(parent_index)
	var depths: Array[int] = []
	for cycle_index in range(polygons.size()):
		var depth: int = 0
		var parent: int = parent_indices[cycle_index]
		var walked: Dictionary = {cycle_index: true}
		while parent >= 0:
			if walked.has(parent): return {"valid": false, "reason": "r4_nesting_parent_cycle", "cycle_index": cycle_index}
			walked[parent] = true
			depth += 1
			parent = parent_indices[parent]
		depths.append(depth)
	var outer_sign: float = 0.0
	for cycle_index in range(depths.size()):
		if depths[cycle_index] == 0:
			outer_sign = signf(signed_areas[cycle_index])
			break
	if outer_sign == 0.0: return {"valid": false, "reason": "r4_nesting_no_outer_cycle"}
	var classified_cycles: Array[Dictionary] = []
	for cycle_index in range(cycles.size()):
		var cycle: Dictionary = cycles[cycle_index].duplicate(true)
		var depth: int = depths[cycle_index]
		var role: String = "OUTER" if depth == 0 else "HOLE" if depth % 2 == 1 else "ISLAND"
		var expected_sign: float = outer_sign if depth % 2 == 0 else -outer_sign
		if signf(signed_areas[cycle_index]) != expected_sign: return {"valid": false, "reason": "r4_nesting_orientation_conflicts_with_parity", "cycle_index": cycle_index, "role": role, "signed_area": signed_areas[cycle_index], "depth": depth}
		cycle["nesting"] = role
		cycle["nesting_depth"] = depth
		cycle["parent_cycle_index"] = parent_indices[cycle_index]
		cycle["signed_projected_area"] = signed_areas[cycle_index]
		cycle["projected_orientation"] = "CCW" if signed_areas[cycle_index] > 0.0 else "CW"
		classified_cycles.append(cycle)
	return {"valid": true, "reason": "", "cycles": classified_cycles, "component_count": cycles.size(), "nesting": "PROJECTED_CONTAINMENT_PARITY", "parent_indices": parent_indices, "depths": depths, "projection_basis": "caller_supplied_patch_plane"}

func _r4_segments_touch_or_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if _r2_proper_segments_intersect(a, b, c, d): return true
	if a == c or a == d or b == c or b == d: return true
	return _r2_endpoint_strictly_inside_segment_2d(a, c, d) or _r2_endpoint_strictly_inside_segment_2d(b, c, d) or _r2_endpoint_strictly_inside_segment_2d(c, a, b) or _r2_endpoint_strictly_inside_segment_2d(d, a, b)

func _r4_boundary_candidate_faces(boundary: Dictionary, patch_ids: Array[String], adjacency: Dictionary, allowed: Dictionary, edge_keys: Array[String]) -> Array[String]:
	var patch_set: Dictionary = {}
	for id in patch_ids: patch_set[id] = true
	var edge_set: Dictionary = {}
	for edge in edge_keys: edge_set[edge] = true
	var candidates: Dictionary = {}
	for incidence_value in boundary.get("incidence_diagnostics", []):
		var incidence: Dictionary = incidence_value
		if not edge_set.has(String(incidence.get("edge_key", ""))): continue
		for row_value in incidence.get("remaining_rows", []):
			var row: Dictionary = row_value
			var candidate_id: String = String(row.get("triangle_id", ""))
			if candidate_id.is_empty() or patch_set.has(candidate_id) or not allowed.has(candidate_id): continue
			for patch_id in patch_ids:
				var adjacent: Variant = adjacency.get(patch_id, {})
				if adjacent is Dictionary and adjacent.has(candidate_id): candidates[candidate_id] = true
	var result: Array[String] = []
	for id_value in candidates.keys(): result.append(String(id_value))
	result.sort()
	return result

func _r4_cycle_defect_candidate_faces(cycle_result: Dictionary, boundary: Dictionary, patch_ids: Array[String], adjacency: Dictionary, allowed: Dictionary) -> Array[String]:
	var edge_keys: Array[String] = []
	var seen_edges: Dictionary = {}
	var offending_value: Variant = cycle_result.get("offending_edges", [])
	if offending_value is Array:
		for edge_value in offending_value:
			var edge_text: String = String(edge_value)
			var split: PackedStringArray = edge_text.split("->")
			var edge_key: String = _edge_key(String(split[0]), String(split[1])) if split.size() == 2 else edge_text
			if not edge_key.is_empty() and not seen_edges.has(edge_key):
				seen_edges[edge_key] = true
				edge_keys.append(edge_key)
	edge_keys.sort()
	return _r4_boundary_candidate_faces(boundary, patch_ids, adjacency, allowed, edge_keys)

func _r4_probe_support_edge(a_id: String, b_id: String, context: Dictionary) -> Dictionary:
	var edge_key: String = _edge_key(a_id, b_id)
	if a_id == b_id: return {"valid": false, "edge_key": edge_key, "reason": "repeated_vertex"}
	if not context.vertex_positions.has(a_id) or not context.vertex_positions.has(b_id):
		return {"valid": false, "edge_key": edge_key, "reason": "vertex_position_missing"}
	if not context.projected_positions.has(a_id) or not context.projected_positions.has(b_id):
		return {"valid": false, "edge_key": edge_key, "reason": "vertex_projection_missing"}
	var a3: Vector3 = Vector3(context.vertex_positions[a_id])
	var b3: Vector3 = Vector3(context.vertex_positions[b_id])
	if not a3.is_finite() or not b3.is_finite(): return {"valid": false, "edge_key": edge_key, "reason": "nonfinite_geometry"}
	if var_to_bytes(a3) == var_to_bytes(b3): return {"valid": false, "edge_key": edge_key, "reason": "duplicate_geometry"}
	var a2: Vector2 = context.projected_positions[a_id]
	var b2: Vector2 = context.projected_positions[b_id]
	if not _r2_point_in_polygon(a2, context.polygon) or not _r2_point_in_polygon(b2, context.polygon):
		return {"valid": false, "edge_key": edge_key, "reason": "endpoint_outside_domain"}
	if not _r2_segment_inside_polygon(a_id, b_id, a2, b2, context):
		return {"valid": false, "edge_key": edge_key, "reason": "segment_outside_or_crosses_boundary"}
	var required_arcs: Array = context.residual_fixture.get("arc_map", [])
	for arc_value in required_arcs:
		if typeof(arc_value) != TYPE_DICTIONARY: return {"valid": false, "edge_key": edge_key, "reason": "required_arc_malformed"}
		var arc: Dictionary = arc_value
		var ids: Array = arc.get("root_ids", [])
		if ids.size() != 2: continue
		var arc_a_id: String = String(ids[0]); var arc_b_id: String = String(ids[1])
		if edge_key == _edge_key(arc_a_id, arc_b_id): continue
		if not context.projected_positions.has(arc_a_id) or not context.projected_positions.has(arc_b_id):
			return {"valid": false, "edge_key": edge_key, "reason": "required_arc_projection_missing", "arc_id": arc.get("arc_id", "")}
		var arc_a: Vector2 = context.projected_positions[arc_a_id]; var arc_b: Vector2 = context.projected_positions[arc_b_id]
		if a_id != arc_a_id and a_id != arc_b_id and b_id != arc_a_id and b_id != arc_b_id and _r2_proper_segments_intersect(a2, b2, arc_a, arc_b):
			return {"valid": false, "edge_key": edge_key, "reason": "crosses_required_topology_arc", "arc_id": arc.get("arc_id", "")}
		if _r2_endpoint_strictly_inside_segment_2d(a2, arc_a, arc_b) or _r2_endpoint_strictly_inside_segment_2d(b2, arc_a, arc_b) or _r2_endpoint_strictly_inside_segment_2d(arc_a, a2, b2) or _r2_endpoint_strictly_inside_segment_2d(arc_b, a2, b2):
			return {"valid": false, "edge_key": edge_key, "reason": "topology_edge_t_junction", "arc_id": arc.get("arc_id", "")}
	for vertex_id_value in context.vertex_ids:
		var vertex_id: String = String(vertex_id_value)
		if vertex_id == a_id or vertex_id == b_id or not context.projected_positions.has(vertex_id): continue
		if _r2_endpoint_strictly_inside_segment_2d(Vector2(context.projected_positions[vertex_id]), a2, b2):
			return {"valid": false, "edge_key": edge_key, "reason": "candidate_vertex_t_junction", "vertex_id": vertex_id}
	return {"valid": true, "edge_key": edge_key, "reason": "", "scope": "intrinsic_domain_topology_duplicate_and_t_junction_preflight"}

func _r4_arc_crossing_boundary_candidates(context: Dictionary, patch: Array[Dictionary], boundary: Dictionary, patch_ids: Array[String], adjacency: Dictionary, allowed: Dictionary) -> Dictionary:
	var diagnostics: Dictionary = context.get("arc_diagnostics", {})
	var root_ids: Array = diagnostics.get("root_ids", [])
	var cycle_result: Dictionary = _r4_boundary_cycle_set(boundary)
	if root_ids.size() != 2 or int(cycle_result.get("component_count", 0)) != 1: return {"valid": false, "reason": "r4_arc_expansion_requires_two_roots_and_one_boundary_cycle", "candidate_face_ids": []}
	var a_id: String = String(root_ids[0]); var b_id: String = String(root_ids[1])
	if not _root_positions.has(a_id) or not _root_positions.has(b_id): return {"valid": false, "reason": "r4_arc_expansion_root_position_missing", "candidate_face_ids": []}
	var normal: Vector3 = Vector3.ZERO
	for triangle in patch:
		var value: Variant = triangle.get("normal", null)
		if value is Vector3: normal += Vector3(value)
	if normal.length_squared() <= 1e-20: return {"valid": false, "reason": "r4_arc_expansion_normal_missing", "candidate_face_ids": []}
	normal = normal.normalized()
	var cycle: Array = cycle_result.cycles[0].root_ids
	var origin: Vector3 = Vector3(_root_positions[String(cycle[0])])
	var axis_u: Vector3 = Vector3.ZERO
	for index in range(1, cycle.size()):
		var candidate: Vector3 = Vector3(_root_positions[String(cycle[index])]) - origin
		candidate -= normal * candidate.dot(normal)
		if candidate.length_squared() > 1e-20: axis_u = candidate.normalized(); break
	if axis_u.length_squared() <= 1e-20: return {"valid": false, "reason": "r4_arc_expansion_projection_axis_missing", "candidate_face_ids": []}
	var axis_v: Vector3 = normal.cross(axis_u).normalized()
	var a3: Vector3 = Vector3(_root_positions[a_id]); var b3: Vector3 = Vector3(_root_positions[b_id])
	var a2: Vector2 = Vector2((a3 - origin).dot(axis_u), (a3 - origin).dot(axis_v))
	var b2: Vector2 = Vector2((b3 - origin).dot(axis_u), (b3 - origin).dot(axis_v))
	var crossed_edges: Array[String] = []
	for index in range(cycle.size()):
		var c3: Vector3 = Vector3(_root_positions[String(cycle[index])]); var d3: Vector3 = Vector3(_root_positions[String(cycle[(index + 1) % cycle.size()])])
		var c2: Vector2 = Vector2((c3 - origin).dot(axis_u), (c3 - origin).dot(axis_v)); var d2: Vector2 = Vector2((d3 - origin).dot(axis_u), (d3 - origin).dot(axis_v))
		if _r2_proper_segments_intersect(a2, b2, c2, d2): crossed_edges.append(_edge_key(String(cycle[index]), String(cycle[(index + 1) % cycle.size()])))
	crossed_edges.sort()
	var candidates: Array[String] = _r4_boundary_candidate_faces(boundary, patch_ids, adjacency, allowed, crossed_edges)
	return {"valid": not crossed_edges.is_empty() and not candidates.is_empty(), "reason": "" if not crossed_edges.is_empty() and not candidates.is_empty() else "r4_arc_boundary_crossing_not_expandable", "arc_id": diagnostics.get("arc_id", ""), "root_ids": root_ids, "crossed_boundary_edges": crossed_edges, "candidate_face_ids": candidates}

func _r3_boundary_expansion_candidate_ids(boundary: Dictionary, patch_ids: Array, adjacency: Dictionary, allowed_ids: Array) -> Array[String]:
	var patch_set: Dictionary = {}
	var allowed: Dictionary = {}
	for id_value in patch_ids: patch_set[String(id_value)] = true
	for id_value in allowed_ids: allowed[String(id_value)] = true
	var offending_edges: Dictionary = {}
	for invalid_value in boundary.get("invalid_reasons", []):
		if typeof(invalid_value) == TYPE_DICTIONARY and String(invalid_value.get("edge_key", "")) != "":
			offending_edges[String(invalid_value.edge_key)] = true
	var cycle: Dictionary = boundary.get("cycle_diagnostics", {})
	var cycle_edge: String = String(cycle.get("edge", ""))
	if cycle_edge.contains("->"):
		var split: PackedStringArray = cycle_edge.split("->")
		if split.size() == 2: offending_edges[_edge_key(split[0], split[1])] = true
	var offending_vertex: String = String(cycle.get("at", ""))
	var incidence_rows: Array = boundary.get("incidence_diagnostics", [])
	if not offending_vertex.is_empty():
		for incidence_value in incidence_rows:
			var incidence: Dictionary = incidence_value
			var touches_vertex: bool = false
			for row_value in incidence.get("removed_rows", []) + incidence.get("remaining_rows", []):
				var row: Dictionary = row_value
				if String(row.get("a", "")) == offending_vertex or String(row.get("b", "")) == offending_vertex:
					touches_vertex = true
					break
			if touches_vertex: offending_edges[String(incidence.get("edge_key", ""))] = true
	if offending_edges.is_empty() and String(boundary.get("reason", "")) in ["boundary_cycle_vertex_count_invalid", "boundary_cycle_multiple_loops"]:
		for incidence_value in incidence_rows:
			var incidence: Dictionary = incidence_value
			offending_edges[String(incidence.get("edge_key", ""))] = true
	var candidate_ids: Dictionary = {}
	for incidence_value in incidence_rows:
		var incidence: Dictionary = incidence_value
		if not offending_edges.has(String(incidence.get("edge_key", ""))): continue
		for row_value in incidence.get("remaining_rows", []):
			var row: Dictionary = row_value
			var candidate_id: String = String(row.get("triangle_id", ""))
			if candidate_id.is_empty() or patch_set.has(candidate_id) or not allowed.has(candidate_id): continue
			for patch_id_value in patch_set.keys():
				var neighbor_row_value: Variant = adjacency.get(String(patch_id_value), {})
				if neighbor_row_value is Dictionary and neighbor_row_value.has(candidate_id):
					candidate_ids[candidate_id] = true
					break
	var result: Array[String] = []
	for candidate_id_value in candidate_ids.keys(): result.append(String(candidate_id_value))
	result.sort()
	return result

func _r3_context_failure_is_patch_domain_limited(reason: String) -> bool:
	# These failures describe this subset's projected domain. The existing
	# radius, patch-size, search-state and wall-clock caps bound any expansion.
	return reason in ["r2_topology_arc_crosses_cavity_boundary", "r2_topology_arc_leaves_concave_cavity_domain", "r2_boundary_projection_self_intersects", "r2_boundary_polygon_degenerate", "r2_projection_axis_unavailable", "r2_projection_basis_invalid"]

func _r3_patch_subset_key(ids: Array) -> String:
	var normalized: Array[String] = []
	for id_value in ids:
		normalized.append(String(id_value))
	normalized.sort()
	return JSON.stringify(normalized)

func _r3_patch_connectivity(patch: Array[Dictionary]) -> Dictionary:
	if patch.is_empty():
		return {"valid": false, "reason": "r3_cavity_patch_empty", "component_count": 0}
	var edge_triangles: Dictionary = {}
	for triangle_index in range(patch.size()):
		var ids: Array = patch[triangle_index].get("root_ids", [])
		if ids.size() != 3:
			return {"valid": false, "reason": "r3_cavity_patch_triangle_arity_invalid", "triangle_id": patch[triangle_index].get("triangle_id", "")}
		for edge_index in range(3):
			var key: String = _edge_key(String(ids[edge_index]), String(ids[(edge_index + 1) % 3]))
			if not edge_triangles.has(key): edge_triangles[key] = []
			edge_triangles[key].append(triangle_index)
	var adjacency_rows: Array[Array] = []
	for triangle_index in range(patch.size()): adjacency_rows.append([])
	for rows_value in edge_triangles.values():
		var rows: Array = rows_value
		for first_index in range(rows.size()):
			for second_index in range(first_index + 1, rows.size()):
				var first_triangle: int = int(rows[first_index])
				var second_triangle: int = int(rows[second_index])
				if not adjacency_rows[first_triangle].has(second_triangle): adjacency_rows[first_triangle].append(second_triangle)
				if not adjacency_rows[second_triangle].has(first_triangle): adjacency_rows[second_triangle].append(first_triangle)
	var visited: Dictionary = {}
	var components: Array[Array] = []
	for triangle_index in range(patch.size()):
		if visited.has(triangle_index): continue
		var queue: Array[int] = [triangle_index]
		visited[triangle_index] = true
		var component: Array[int] = []
		while not queue.is_empty():
			var current: int = queue.pop_front()
			component.append(current)
			for neighbor_value in adjacency_rows[current]:
				var neighbor: int = int(neighbor_value)
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		component.sort()
		components.append(component)
	var component_ids: Array = []
	for component in components:
		var ids: Array[String] = []
		for index in component: ids.append(String(patch[int(index)].get("triangle_id", "")))
		ids.sort()
		component_ids.append(ids)
	return {"valid": components.size() == 1, "reason": "" if components.size() == 1 else "r3_cavity_patch_disconnected", "component_count": components.size(), "components": component_ids}

func _r3_derive_remaining_boundary(all_triangles: Array[Dictionary], patch_ids: Array, prebuilt_index: Dictionary = {}, include_full_diagnostics: bool = true) -> Dictionary:
	if patch_ids.is_empty():
		return {"valid": false, "reason": "r3_cavity_patch_empty"}
	var patch_set: Dictionary = {}
	for triangle_id in patch_ids: patch_set[String(triangle_id)] = true
	var edge_rows: Dictionary = {}
	var missing_patch_ids: Array[String] = []
	var found_patch_ids: Dictionary = {}
	if prebuilt_index.is_empty():
		var seen_triangle_ids: Dictionary = {}
		for triangle in all_triangles:
			var triangle_id: String = String(triangle.get("triangle_id", ""))
			if triangle_id.is_empty() or seen_triangle_ids.has(triangle_id):
				return {"valid": false, "reason": "r3_c6_triangle_identity_invalid", "triangle_id": triangle_id, "duplicate": seen_triangle_ids.has(triangle_id)}
			seen_triangle_ids[triangle_id] = true
			var ids: Array = triangle.get("root_ids", [])
			if ids.size() != 3:
				return {"valid": false, "reason": "r3_c6_triangle_arity_invalid", "triangle_id": triangle_id}
			var is_removed: bool = patch_set.has(triangle_id)
			if is_removed: found_patch_ids[triangle_id] = true
			for edge_index in range(3):
				var a_id: String = String(ids[edge_index])
				var b_id: String = String(ids[(edge_index + 1) % 3])
				if a_id.is_empty() or b_id.is_empty() or a_id == b_id:
					return {"valid": false, "reason": "r3_c6_edge_identity_invalid", "triangle_id": triangle_id}
				var edge_key: String = _edge_key(a_id, b_id)
				if not edge_rows.has(edge_key): edge_rows[edge_key] = {"removed": [], "remaining": []}
				var row: Dictionary = {"triangle_id": triangle_id, "a": a_id, "b": b_id}
				var owner: String = "removed" if is_removed else "remaining"
				edge_rows[edge_key][owner].append(row)
	else:
		if not bool(prebuilt_index.get("valid", false)):
			return {"valid": false, "reason": String(prebuilt_index.get("reason", "r3_c6_boundary_index_invalid"))}
		var triangles_by_id: Dictionary = prebuilt_index.get("triangles_by_id", {})
		var indexed_edges: Dictionary = prebuilt_index.get("edge_rows_by_key", {})
		var affected_edges: Dictionary = {}
		for triangle_id_value in patch_set.keys():
			var triangle_id: String = String(triangle_id_value)
			if not triangles_by_id.has(triangle_id):
				continue
			found_patch_ids[triangle_id] = true
			var triangle: Dictionary = triangles_by_id[triangle_id]
			var ids: Array = triangle.get("root_ids", [])
			for edge_index in range(3):
				affected_edges[_edge_key(String(ids[edge_index]), String(ids[(edge_index + 1) % 3]))] = true
		var affected_keys: Array = affected_edges.keys()
		affected_keys.sort()
		for edge_key_value in affected_keys:
			var edge_key: String = String(edge_key_value)
			var owners: Dictionary = {"removed": [], "remaining": []}
			for row_value in indexed_edges.get(edge_key, []):
				var row: Dictionary = row_value
				var owner: String = "removed" if patch_set.has(String(row.triangle_id)) else "remaining"
				owners[owner].append(row)
			edge_rows[edge_key] = owners
	for triangle_id_value in patch_set.keys():
		if not found_patch_ids.has(String(triangle_id_value)): missing_patch_ids.append(String(triangle_id_value))
	missing_patch_ids.sort()
	if not missing_patch_ids.is_empty():
		return {"valid": false, "reason": "r3_cavity_patch_triangles_missing", "missing_patch_triangle_ids": missing_patch_ids}
	var boundary_edges: Array[String] = []
	var incidence_diagnostics: Array[Dictionary] = []
	var invalid: Array[Dictionary] = []
	var removed_source_winding_mismatches: Array[Dictionary] = []
	var internal_removed_nonmanifold: Array[String] = []
	var closed_remaining_edges: Array[Dictionary] = []
	var removed_only_internal_edges: Array[Dictionary] = []
	var edge_keys: Array = edge_rows.keys()
	edge_keys.sort()
	for edge_key_value in edge_keys:
		var edge_key: String = String(edge_key_value)
		var owners: Dictionary = edge_rows[edge_key]
		var removed_rows: Array = owners.removed
		var remaining_rows: Array = owners.remaining
		if removed_rows.is_empty(): continue
		incidence_diagnostics.append({"edge_key": edge_key, "removed_incidence": removed_rows.size(), "remaining_incidence": remaining_rows.size(), "removed_rows": removed_rows.duplicate(true) if include_full_diagnostics else removed_rows, "remaining_rows": remaining_rows.duplicate(true) if include_full_diagnostics else remaining_rows})
		if remaining_rows.is_empty():
			if removed_rows.size() == 1:
				invalid.append({"reason": "r3_patch_open_edge_has_no_remaining_owner", "edge_key": edge_key, "removed_incidence": 1})
			else:
				removed_only_internal_edges.append({"edge_key": edge_key, "removed_incidence": removed_rows.size(), "resolution": "no_remaining_interface_owner"})
				if removed_rows.size() > 2:
					internal_removed_nonmanifold.append(edge_key)
			continue
		if remaining_rows.size() == 1:
			var remaining_row: Dictionary = remaining_rows[0]
			for removed_value in removed_rows:
				var removed_row: Dictionary = removed_value
				if String(removed_row.a) == String(remaining_row.a) and String(removed_row.b) == String(remaining_row.b):
					# The removed face is not an orientation authority. Preserve this
					# mismatch only as evidence; the surviving C6 owner orients the patch.
					if include_full_diagnostics: removed_source_winding_mismatches.append({"edge_key": edge_key, "removed": removed_row.duplicate(true), "remaining": remaining_row.duplicate(true), "resolution": "boundary_oriented_from_surviving_C6_owner"})
			boundary_edges.append(String(remaining_row.b) + "->" + String(remaining_row.a))
			continue
		if remaining_rows.size() == 2:
			var first_remaining: Dictionary = remaining_rows[0]
			var second_remaining: Dictionary = remaining_rows[1]
			if String(first_remaining.a) == String(second_remaining.b) and String(first_remaining.b) == String(second_remaining.a):
				# A pair of oppositely directed surviving owners is already closed.
				# It is not part of the replacement interface, even if the removed
				# patch also contained one or more coincident source faces.
				closed_remaining_edges.append({"edge_key": edge_key, "removed_incidence": removed_rows.size(), "remaining_rows": remaining_rows.duplicate(true) if include_full_diagnostics else remaining_rows, "resolution": "opposed_surviving_owners_form_closed_edge"})
			else:
				invalid.append({"reason": "r3_surviving_edge_winding_inconsistent", "edge_key": edge_key, "removed_incidence": removed_rows.size(), "remaining_rows": remaining_rows.duplicate(true) if include_full_diagnostics else remaining_rows})
			continue
		invalid.append({"reason": "r3_surviving_edge_nonmanifold", "edge_key": edge_key, "removed_incidence": removed_rows.size(), "remaining_incidence": remaining_rows.size(), "remaining_rows": remaining_rows.duplicate(true) if include_full_diagnostics else remaining_rows})
	boundary_edges.sort()
	var boundary: Dictionary = {"valid": invalid.is_empty(), "directed_edges": boundary_edges.duplicate(), "boundary_edge_count": boundary_edges.size(), "incidence_diagnostics": incidence_diagnostics, "removed_source_winding_mismatches": removed_source_winding_mismatches, "closed_remaining_edges": closed_remaining_edges, "removed_only_internal_edges": removed_only_internal_edges, "internal_removed_nonmanifold_edges": internal_removed_nonmanifold, "missing_patch_triangle_ids": missing_patch_ids, "boundary_source": "remaining_C6_edge_incidence_after_cavity_patch_removal", "invalid_reasons": invalid}
	if invalid.is_empty():
		var cycle: Dictionary = _r2_boundary_cycle(boundary)
		if not bool(cycle.get("valid", false)):
			boundary["valid"] = false
			boundary["reason"] = String(cycle.get("reason", "r3_cavity_boundary_cycle_invalid"))
			boundary["cycle_diagnostics"] = cycle
		else:
			boundary["cycle"] = cycle.get("cycle", [])
			boundary["signature"] = Core.sha256(JSON.stringify(boundary_edges).to_utf8_buffer())
			boundary["observed_boundary_signature"] = boundary.signature
			boundary["vertex_count"] = boundary.cycle.size()
	if not bool(boundary.get("valid", false)) and not boundary.has("reason"):
		boundary["reason"] = String(invalid[0].get("reason", "r3_cavity_boundary_invalid")) if not invalid.is_empty() else "r3_cavity_boundary_invalid"
	boundary["diagnostic_sha256"] = Core.sha256(JSON.stringify(boundary).to_utf8_buffer())
	return boundary

func derive_remaining_boundary_for_test(all_triangles: Array[Dictionary], patch_ids: Array) -> Dictionary:
	return _r3_derive_remaining_boundary(all_triangles, patch_ids)

func derive_remaining_boundary_indexed_for_test(all_triangles: Array[Dictionary], patch_ids: Array) -> Dictionary:
	var index: Dictionary = _r3_build_boundary_index(all_triangles)
	if not bool(index.get("valid", false)): return {"valid": false, "reason": String(index.get("reason", "r3_c6_boundary_index_invalid"))}
	return _r3_derive_remaining_boundary(all_triangles, patch_ids, index)

func _search_cxr_cavity_r2(cavity_ids: Array, all_triangles: Array[Dictionary], adjacency: Dictionary, residual_fixture: Dictionary, values: PackedFloat32Array, roi: Dictionary) -> Dictionary:
	_cxr_cavity_started_usec = Time.get_ticks_usec()
	_cxr_search_nodes_cavity = 0
	_cxr_candidate_triangles_cavity = 0
	_cxr_active_cavity_branches = {}
	_cxr_active_cavity_prunes = {}
	var sorted_ids: Array = cavity_ids.duplicate()
	sorted_ids.sort()
	var cavity_id: String = Core.sha256(JSON.stringify(sorted_ids).to_utf8_buffer()).substr(0, 16)
	var report: Dictionary = {"phase": "r2", "cavity_id": cavity_id, "residual_triangle_ids": sorted_ids, "levels": [], "candidate_attempts": [], "support_candidates": [], "support_candidates_retained": [], "candidate_edges": [], "candidate_triangles": [], "retained_solutions": [], "selected_supports": [], "solution_found_levels": [], "search_nodes": 0, "branches": _cxr_active_cavity_branches, "prunes": _cxr_active_cavity_prunes, "limits_hit": [], "search_complete": false, "search_exhaustive": false, "terminal_reason": "UNKNOWN_NOT_CAPTURED"}
	var residual_by_id: Dictionary = {}
	for row_value in residual_fixture.get("residuals", []):
		var row: Dictionary = row_value
		residual_by_id[String(row.get("triangle_id", ""))] = row
	var residual_triangles: Array[Dictionary] = []
	for triangle in all_triangles:
		if sorted_ids.has(String(triangle.get("triangle_id", ""))):
			residual_triangles.append(triangle)
	residual_triangles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.triangle_id) < String(b.triangle_id))
	if residual_triangles.is_empty():
		_append_unrun_cxr_levels(report, 0, "NOT_RUN_INVALID_CAVITY", "residual_cavity_faces_missing")
		return _finish_cxr_cavity_search(report, {}, false, false, "residual_cavity_faces_missing")
	var support_rows: Array[Dictionary] = []
	var support_by_id: Dictionary = {}
	var support_by_position_identity: Dictionary = {}
	var support_generation_failed: bool = false
	var best_solution: Dictionary = {}
	var any_search_started: bool = false
	for level in range(CXR_MAX_CAVITY_LEVEL + 1):
		var patch_map: Dictionary = {}
		for seed_id in sorted_ids:
			for triangle_id in _radius_ids(String(seed_id), adjacency, level):
				patch_map[String(triangle_id)] = true
		var patch_ids: Array = _sorted_keys(patch_map)
		var patch: Array[Dictionary] = []
		for triangle in all_triangles:
			if patch_map.has(String(triangle.get("triangle_id", ""))):
				patch.append(triangle)
		var level_report: Dictionary = _new_cxr_level_report(level, patch_ids, patch.size())
		if patch.size() > CXR_MAX_PATCH_TRIANGLES:
			level_report.terminal_reason = "limit_source_triangle_cap"
			level_report.candidate_generation_usec = "NOT_RUN_CAVITY_LIMIT"
			level_report.candidate_generation_status = "NOT_RUN_CAVITY_LIMIT"
			level_report.search_status = "NOT_RUN_CAVITY_LIMIT"
			report.levels.append(level_report)
			report.limits_hit.append("MAX_PATCH_TRIANGLES")
			_append_unrun_cxr_levels(report, level + 1, "NOT_RUN_CAVITY_LIMIT", "limit_max_patch_triangles")
			return _finish_cxr_cavity_search(report, best_solution, false, false, "limit_max_patch_triangles")
		var boundary: Dictionary = _boundary_state(patch)
		if not bool(boundary.get("valid", false)):
			_record_invalid_cxr_boundary_level(report, level_report, boundary)
			continue
		level_report["boundary_before"] = boundary.duplicate(true)
		level_report["boundary_signature"] = String(boundary.get("signature", ""))
		var generation_started: int = Time.get_ticks_usec()
		support_rows.clear()
		support_by_id.clear()
		support_generation_failed = false
		var max_per_residual: int = maxi(1, int(floor(float(CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY) / float(residual_triangles.size()))))
		for residual_index in range(residual_triangles.size()):
			var residual_triangle: Dictionary = residual_triangles[residual_index]
			var residual_id: String = String(residual_triangle.get("triangle_id", ""))
			var fixture_row: Dictionary = residual_by_id.get(residual_id, {})
			var remaining_attempts: int = CXR_MAX_CANDIDATE_ATTEMPTS_PER_CAVITY - report.candidate_attempts.size()
			var candidate_data: Dictionary = _generate_field_candidates(residual_triangle, patch, values, roi, level, max_per_residual, remaining_attempts, cavity_id, fixture_row)
			var evidence_check: Dictionary = _validate_candidate_generation_evidence(candidate_data)
			if not bool(evidence_check.get("valid", false)):
				level_report["candidate_generation_status"] = "FAILED_EVIDENCE_INCOMPLETE"
				level_report["candidate_generation_evidence"] = evidence_check
				report.levels.append(level_report)
				report["candidate_generation_evidence_failure"] = evidence_check
				return _finish_cxr_cavity_search(report, best_solution, false, false, "candidate_generation_evidence_incomplete")
			var attempts: Array = candidate_data.get("attempts", [])
			report.candidate_attempts.append_array(attempts)
			level_report.candidate_attempt_count = int(level_report.candidate_attempt_count) + attempts.size()
			level_report.candidate_attempt_ids.append_array(_r2_candidate_attempt_ids(attempts))
			level_report.candidate_count_by_residual[residual_id] = candidate_data.get("candidate_count", "UNKNOWN_NOT_CAPTURED")
			level_report.candidate_unique_count_by_residual[residual_id] = candidate_data.get("candidate_unique_count", "UNKNOWN_NOT_CAPTURED")
			level_report.candidate_pool_retained_count_by_residual[residual_id] = candidate_data.get("candidate_pool", []).size()
			level_report.candidate_fan_status_by_residual[residual_id] = "NOT_RUN_R2_GENERAL_TRIANGULATION"
			report.support_candidates.append_array(candidate_data.get("candidate_pool", []))
			if not bool(candidate_data.get("source_valid", false)) or bool(candidate_data.get("limit_hit", false)):
				support_generation_failed = true
				if bool(candidate_data.get("limit_hit", false)):
					report.limits_hit.append_array(candidate_data.get("limits_hit", []))
				level_report.candidate_generation_status = "FAILED_SOURCE_OR_CANDIDATE_LIMIT"
				level_report.search_status = "NOT_RUN_SOURCE_OR_CANDIDATE_LIMIT"
				level_report.terminal_reason = String(candidate_data.get("source_failure_reason", "candidate_generation_limit"))
				_mark_unrun_cxr_residuals(level_report, residual_triangles, residual_index + 1, "NOT_RUN_SOURCE_OR_CANDIDATE_LIMIT")
				report.levels.append(level_report)
				_append_unrun_cxr_levels(report, level + 1, "NOT_RUN_SOURCE_OR_CANDIDATE_LIMIT", level_report.terminal_reason)
				return _finish_cxr_cavity_search(report, best_solution, false, false, level_report.terminal_reason)
			for candidate_value in candidate_data.get("candidate_pool", []):
				var support: Dictionary = candidate_value
				var support_id: String = String(support.get("support_id", ""))
				if support_id.is_empty():
					support_generation_failed = true
					break
				var position_identity: String = String(support.get("binary32_position_identity", ""))
				if position_identity.is_empty():
					support_generation_failed = true
					break
				if not support_by_position_identity.has(position_identity):
					if support_by_position_identity.size() >= CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY:
						support_generation_failed = true
						report.limits_hit.append("MAX_SUPPORT_CANDIDATES_PER_CAVITY")
						break
					support_by_position_identity[position_identity] = support
		if support_generation_failed:
			level_report.candidate_generation_status = "FAILED_SUPPORT_IDENTITY_OR_CAP"
			report.levels.append(level_report)
			return _finish_cxr_cavity_search(report, best_solution, false, false, "support_candidate_identity_invalid_or_cap")
		level_report.candidate_generation_usec = Time.get_ticks_usec() - generation_started
		level_report.candidate_generation_status = "COMPLETE_R2_SUPPORT_SET_FROZEN"
		support_by_id.clear()
		for support_value in support_by_position_identity.values():
			var support: Dictionary = support_value
			support_by_id[String(support.get("support_id", ""))] = support
		support_rows.assign(support_by_id.values())
		support_rows.sort_custom(Callable(self, "_candidate_less"))
		report.support_candidates_retained.clear()
		var retained_position_ids: Array = support_by_position_identity.keys()
		retained_position_ids.sort()
		for retained_position_id in retained_position_ids:
			report.support_candidates_retained.append(support_by_position_identity[retained_position_id].duplicate(true))
		var cavity_boundary: Dictionary = _boundary_state(residual_triangles)
		if not bool(cavity_boundary.get("valid", false)):
			level_report.candidate_generation_status = "FAILED_CAVITY_BOUNDARY_INVALID"
			level_report.search_status = "NOT_RUN_CAVITY_BOUNDARY_INVALID"
			level_report.terminal_reason = String(cavity_boundary.get("reason", "cavity_boundary_invalid"))
			level_report.cavity_boundary = cavity_boundary
			report.levels.append(level_report)
			return _finish_cxr_cavity_search(report, best_solution, false, false, level_report.terminal_reason)
		var context_result: Dictionary = _r2_make_search_context(residual_triangles, patch_ids, residual_triangles, support_rows, cavity_boundary, all_triangles, residual_fixture, level)
		if not bool(context_result.get("valid", false)):
			level_report.candidate_generation_status = "FAILED_R2_CONTEXT"
			level_report.search_status = "NOT_RUN_R2_CONTEXT_INVALID"
			level_report.terminal_reason = String(context_result.get("reason", "r2_context_invalid"))
			report.levels.append(level_report)
			return _finish_cxr_cavity_search(report, best_solution, false, false, level_report.terminal_reason)
		var context: Dictionary = context_result.context
		context["support_generation_usec"] = level_report.candidate_generation_usec
		print("R12CXR_R2_CONSTRAINED_SEARCH_BEGIN " + JSON.stringify({"attempt_id": OS.get_environment("R12CXR_ATTEMPT_ID"), "source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "scenario_id": "R9.2.SEAM.XPLUS_EQUAL.v1", "cavity_id": cavity_id, "level": level, "candidate_supports": support_rows.size(), "limits": _cxr_limits()}))
		var before_nodes: int = _cxr_search_nodes_total
		var before_triangles: int = _cxr_candidate_triangles_total
		any_search_started = true
		var search_result: Dictionary = _r2_search_level(context)
		var node_delta: int = _cxr_search_nodes_total - before_nodes
		var triangle_delta: int = _cxr_candidate_triangles_total - before_triangles
		level_report.search_nodes = node_delta
		level_report.candidate_triangle_count = triangle_delta
		level_report.branches = int(search_result.get("branches", 0))
		level_report.solutions = int(search_result.get("solution_count", 0))
		level_report.retained_solutions = search_result.get("retained_solutions", [])
		level_report.search_status = "COMPLETE_SOLUTION" if bool(search_result.get("valid", false)) else "COMPLETE_NO_SOLUTION" if bool(search_result.get("search_complete", false)) else "PARTIAL_LIMIT"
		level_report.terminal_reason = String(search_result.get("terminal_reason", "UNKNOWN_NOT_CAPTURED"))
		level_report.candidate_generation_status = "COMPLETE_R2_SUPPORT_SET_FROZEN"
		report.candidate_triangles.append_array(context.get("candidate_triangle_rows", []))
		var candidate_edge_keys: Array = context.get("candidate_edges", {}).keys()
		candidate_edge_keys.sort()
		for edge_key_value in candidate_edge_keys:
			report.candidate_edges.append(context.candidate_edges[edge_key_value])
		if bool(search_result.get("valid", false)):
			var selected: Dictionary = search_result.get("best_solution", {})
			var selected_supports: Array = selected.get("selected_supports", [])
			var replacement: Array[Dictionary] = selected.get("final_replacement_triangles", [])
			var patch_record: Dictionary = {"group_index": level, "level": level, "patch_triangle_ids": patch_ids.duplicate(), "replacement_triangles": replacement.duplicate(true), "selected_supports": selected_supports.duplicate(true), "search_nodes": node_delta, "search_usec": search_result.get("search_usec", "UNKNOWN_NOT_CAPTURED"), "search_phase": "r2", "boundary_signature": String(boundary.get("signature", "")), "surface_diagnostics": selected.get("surface_diagnostics", "UNKNOWN_NOT_CAPTURED"), "candidate_triangle_count": triangle_delta}
			best_solution = {"solution": {"selected_supports": selected_supports, "support_ids": selected.get("support_ids", []), "minimum_cross_squared": selected.get("minimum_cross_squared", "UNKNOWN_NOT_CAPTURED"), "surface_diagnostics": selected.get("surface_diagnostics", "UNKNOWN_NOT_CAPTURED"), "stable_score_key": selected.get("stable_score_key", "")}, "patch_ids": patch_ids.duplicate(), "patch_record": patch_record, "replacement_triangles": replacement.duplicate(true), "level": level}
			report.retained_solutions.append_array(search_result.get("retained_solutions", []))
			report.selected_supports = selected_supports.duplicate(true)
			report.solution_found_levels.append(level)
			report.search_nodes = _cxr_search_nodes_cavity
			report.branches = _cxr_active_cavity_branches
			report.prunes = _cxr_active_cavity_prunes
			level_report.terminal_reason = "minimum_support_solution_found"
			report.levels.append(level_report)
			for later_level in range(level + 1, CXR_MAX_CAVITY_LEVEL + 1):
				report.levels.append(_new_unrun_cxr_level(later_level, "NOT_RUN_SMALLER_PATCH_SOLUTION", "smaller_patch_solution_has_priority"))
			var search_complete: bool = bool(search_result.get("search_complete", false))
			var search_exhaustive: bool = bool(search_result.get("search_exhaustive", false)) and search_complete
			return _finish_cxr_cavity_search(report, best_solution, search_complete, search_exhaustive, "minimum_support_solution_found" if search_complete else String(search_result.get("terminal_reason", "r2_search_partial")))
		report.search_nodes = _cxr_search_nodes_cavity
		report.branches = _cxr_active_cavity_branches
		report.prunes = _cxr_active_cavity_prunes
		report.levels.append(level_report)
		if not bool(search_result.get("search_complete", false)):
			_append_unrun_cxr_levels(report, level + 1, "NOT_RUN_R2_SEARCH_LIMIT", String(search_result.get("terminal_reason", "r2_search_partial")))
			return _finish_cxr_cavity_search(report, best_solution, false, false, String(search_result.get("terminal_reason", "r2_search_partial")))
	if not any_search_started:
		return _finish_cxr_cavity_search(report, best_solution, false, false, "r2_no_valid_boundary_level")
	report.search_nodes = _cxr_search_nodes_cavity
	return _finish_cxr_cavity_search(report, {}, true, true, "r2_all_levels_exhausted_no_solution")

func _r3_make_expanded_patch_context(patch: Array[Dictionary], patch_ids: Array, cavity_seed_triangles: Array[Dictionary], support_rows: Array[Dictionary], boundary: Dictionary, all_triangles: Array[Dictionary], residual_fixture: Dictionary, level: int, preflight_only: bool = false) -> Dictionary:
	# Cavity seed faces own candidate provenance. The selected connected patch
	# is the larger removal domain and can contain unowned adjacent C6 faces.
	return _r2_make_search_context(patch, patch_ids, cavity_seed_triangles, support_rows, boundary, all_triangles, residual_fixture, level, preflight_only)

func _r2_make_search_context(patch: Array[Dictionary], patch_ids: Array, residual_triangles: Array[Dictionary], support_rows: Array[Dictionary], boundary: Dictionary, all_triangles: Array[Dictionary], residual_fixture: Dictionary, level: int, preflight_only: bool = false) -> Dictionary:
	var selected_patch_id_set: Dictionary = {}
	for patch_id_value in patch_ids:
		var patch_id: String = String(patch_id_value)
		if patch_id.is_empty() or selected_patch_id_set.has(patch_id):
			return {"valid": false, "reason": "r2_selected_patch_identity_invalid", "triangle_id": patch_id}
		selected_patch_id_set[patch_id] = true
	if selected_patch_id_set.is_empty():
		return {"valid": false, "reason": "r2_selected_patch_empty"}
	for triangle in residual_triangles:
		var residual_id: String = String(triangle.get("triangle_id", ""))
		if residual_id.is_empty() or not selected_patch_id_set.has(residual_id):
			return {"valid": false, "reason": "r2_residual_owner_outside_selected_patch", "triangle_id": residual_id}
	var cycle_result: Dictionary = _r2_boundary_cycle(boundary)
	if not bool(cycle_result.get("valid", false)):
		return {"valid": false, "reason": String(cycle_result.get("reason", "r2_boundary_cycle_invalid"))}
	var cycle: Array[String] = cycle_result.cycle
	var root_positions: Dictionary = _root_positions
	var vertex_positions: Dictionary = {}
	for root_id in cycle:
		if not root_positions.has(root_id) or not (root_positions[root_id] is Vector3):
			return {"valid": false, "reason": "r2_boundary_root_position_missing", "root_id": root_id}
		vertex_positions[root_id] = root_positions[root_id]
	var source_root_ids: Dictionary = {}
	for triangle in residual_triangles:
		var source_ids: Array = triangle.get("root_ids", [])
		for index in range(source_ids.size()):
			var source_id: String = String(source_ids[index])
			var source_points: Array = triangle.get("points", [])
			if source_points.size() != source_ids.size() or not (source_points[index] is Vector3):
				return {"valid": false, "reason": "r2_residual_owner_geometry_invalid", "triangle_id": triangle.get("triangle_id", "UNKNOWN_NOT_CAPTURED")}
			var source_point: Vector3 = source_points[index]
			if source_root_ids.has(source_id) and Vector3(source_root_ids[source_id]).distance_squared_to(source_point) > 0.0:
				return {"valid": false, "reason": "r2_residual_root_position_conflict", "root_id": source_id}
			source_root_ids[source_id] = source_point
			vertex_positions[source_id] = source_point
	var support_by_id: Dictionary = {}
	for support_value in support_rows:
		var support: Dictionary = support_value
		var support_id: String = String(support.get("support_id", ""))
		var position_value: Variant = support.get("world_position", null)
		if support_id.is_empty() or position_value == null or not (position_value is Vector3) or not position_value.is_finite():
			return {"valid": false, "reason": "r2_support_identity_or_position_invalid", "support": support}
		if support_by_id.has(support_id) or vertex_positions.has(support_id):
			return {"valid": false, "reason": "r2_support_identity_duplicate", "support_id": support_id}
		if not bool(support.get("accepted", false)) or (support.has("supported") and not bool(support.get("supported", false))):
			return {"valid": false, "reason": "r2_support_not_frozen_field_supported", "support_id": support_id}
		var residual_value: Variant = support.get("frozen_field_interpolated_residual", null)
		if typeof(residual_value) != TYPE_FLOAT and typeof(residual_value) != TYPE_INT:
			return {"valid": false, "reason": "r2_support_field_residual_missing", "support_id": support_id}
		if not is_finite(float(residual_value)) or absf(float(residual_value)) > CXR_FIELD_RESIDUAL_EPSILON:
			return {"valid": false, "reason": "r2_support_field_residual_outside_frozen_epsilon", "support_id": support_id, "residual": residual_value}
		for topology_id_value in vertex_positions.keys():
			var topology_id: String = String(topology_id_value)
			if support_id == topology_id or var_to_bytes(Vector3(vertex_positions[topology_id])) == var_to_bytes(Vector3(position_value)):
				var duplicate_reason: String = "r2_support_position_duplicates_frozen_boundary_root" if cycle.has(topology_id) else "r2_support_position_duplicates_frozen_topology_root"
				return {"valid": false, "reason": duplicate_reason, "support_id": support_id, "topology_root_id": topology_id}
		support_by_id[support_id] = support
		vertex_positions[support_id] = position_value
	var all_vertex_ids: Array[String] = []
	for root_id in cycle:
		all_vertex_ids.append(root_id)
	var support_ids: Array = support_by_id.keys()
	support_ids.sort()
	for support_id_value in support_ids:
		all_vertex_ids.append(String(support_id_value))
	var normal: Vector3 = Vector3.ZERO
	for triangle in patch:
		var triangle_normal: Variant = triangle.get("normal", null)
		if triangle_normal is Vector3:
			normal += triangle_normal
	if normal.length_squared() <= 1e-20:
		for triangle in residual_triangles:
			var triangle_normal: Variant = triangle.get("normal", null)
			if triangle_normal is Vector3:
				normal += triangle_normal
	if normal.length_squared() <= 1e-20:
		return {"valid": false, "reason": "r2_reference_normal_unavailable"}
	normal = normal.normalized()
	var origin: Vector3 = vertex_positions[cycle[0]]
	var axis_u: Vector3 = Vector3.ZERO
	for cycle_index in range(1, cycle.size()):
		var candidate_axis: Vector3 = (vertex_positions[cycle[cycle_index]] - origin)
		candidate_axis -= normal * candidate_axis.dot(normal)
		if candidate_axis.length_squared() > 1e-20:
			axis_u = candidate_axis.normalized()
			break
	if axis_u.length_squared() <= 1e-20:
		return {"valid": false, "reason": "r2_projection_axis_unavailable"}
	var axis_v: Vector3 = normal.cross(axis_u).normalized()
	if axis_v.length_squared() <= 1e-20:
		return {"valid": false, "reason": "r2_projection_basis_invalid"}
	var projection_ids: Dictionary = {}
	for vertex_id in all_vertex_ids:
		projection_ids[vertex_id] = true
	for source_id in source_root_ids.keys():
		projection_ids[String(source_id)] = true
	var projected_positions: Dictionary = {}
	var sorted_projection_ids: Array = projection_ids.keys()
	sorted_projection_ids.sort()
	for vertex_id_value in sorted_projection_ids:
		var vertex_id: String = String(vertex_id_value)
		var delta: Vector3 = vertex_positions[vertex_id] - origin
		projected_positions[vertex_id] = Vector2(delta.dot(axis_u), delta.dot(axis_v))
	var boundary_edge_map: Dictionary = {}
	var directed_edges: Array = boundary.get("directed_edges", [])
	for edge_value in directed_edges:
		var edge_text: String = String(edge_value)
		var split: PackedStringArray = edge_text.split("->")
		if split.size() != 2:
			return {"valid": false, "reason": "r2_boundary_edge_encoding_invalid", "edge": edge_text}
		var a: String = String(split[0])
		var b: String = String(split[1])
		var key: String = _edge_key(a, b)
		if boundary_edge_map.has(key):
			return {"valid": false, "reason": "r2_boundary_edge_duplicate", "edge": edge_text}
		boundary_edge_map[key] = {"a": a, "b": b, "edge_key": key}
	var polygon: Array[Vector2] = []
	for vertex_id in cycle:
		polygon.append(projected_positions[vertex_id])
	if polygon.size() < 3 or absf(_r2_polygon_signed_area(polygon)) <= 1e-12:
		return {"valid": false, "reason": "r2_boundary_polygon_degenerate"}
	for first_index in range(polygon.size()):
		var first_next: int = (first_index + 1) % polygon.size()
		for second_index in range(first_index + 1, polygon.size()):
			var second_next: int = (second_index + 1) % polygon.size()
			if first_index == second_index or first_next == second_index or second_next == first_index:
				continue
			if _r2_proper_segments_intersect(polygon[first_index], polygon[first_next], polygon[second_index], polygon[second_next]):
				return {"valid": false, "reason": "r2_boundary_projection_self_intersects", "edge_indices": [first_index, second_index]}
	var owner_arc_result: Dictionary = _r2_residual_owner_boundary_arcs(residual_triangles)
	if not bool(owner_arc_result.get("valid", false)):
		return {"valid": false, "reason": String(owner_arc_result.get("reason", "r2_source_owner_boundary_invalid")), "owner_arc_diagnostics": owner_arc_result}
	var arc_merge: Dictionary = _r2_merge_arc_constraints(residual_fixture.get("arc_map", []), owner_arc_result.get("arc_map", []))
	if not bool(arc_merge.get("valid", false)):
		return {"valid": false, "reason": String(arc_merge.get("reason", "r2_arc_constraint_merge_invalid")), "arc_diagnostics": arc_merge}
	var constraint_arcs: Array = arc_merge.get("arc_map", [])
	var local_arc_result: Dictionary = _r2_localize_topology_arcs(constraint_arcs, source_root_ids, cycle, root_positions, vertex_positions, projected_positions, polygon, origin, axis_u, axis_v)
	if not bool(local_arc_result.get("valid", false)):
		return {"valid": false, "reason": String(local_arc_result.get("reason", "r2_local_topology_arcs_invalid")), "arc_diagnostics": local_arc_result}
	var required_topology_root_ids: Dictionary = local_arc_result.get("topology_root_ids", {})
	if preflight_only:
		return {"valid": true, "preflight_only": true, "boundary_signature": String(boundary.get("signature", "")), "local_required_arc_count": local_arc_result.get("arc_map", []).size(), "source_owner_boundary_arc_count": owner_arc_result.get("arc_map", []).size(), "required_topology_root_ids": required_topology_root_ids.duplicate()}
	for support_id_value in support_by_id.keys():
		var support_id: String = String(support_id_value)
		for topology_root_id_value in required_topology_root_ids.keys():
			var topology_root_id: String = String(topology_root_id_value)
			if support_id == topology_root_id or var_to_bytes(Vector3(vertex_positions[support_id])) == var_to_bytes(Vector3(vertex_positions[topology_root_id])):
				return {"valid": false, "reason": "r2_support_position_duplicates_frozen_topology_root", "support_id": support_id, "topology_root_id": topology_root_id}
	var topology_vertex_ids: Array = required_topology_root_ids.keys()
	topology_vertex_ids.sort()
	for topology_root_id_value in topology_vertex_ids:
		var topology_root_id: String = String(topology_root_id_value)
		if not all_vertex_ids.has(topology_root_id):
			all_vertex_ids.append(topology_root_id)
	# Every selected face is removed from the current level patch before the
	# candidate is published. Keep this replacement set distinct from the
	# smaller owner-provenance set in residual_triangles.
	var residual_id_set: Dictionary = selected_patch_id_set.duplicate()
	var owner_polygon_ids: Dictionary = {}
	var source_polygon_ids: Dictionary = {}
	for triangle in residual_triangles:
		var polygon_id: String = String(triangle.get("polygon_id", ""))
		if polygon_id.is_empty():
			return {"valid": false, "reason": "r2_source_polygon_owner_missing", "triangle_id": triangle.get("triangle_id", "")}
		owner_polygon_ids[polygon_id] = true
		for source_polygon_id_value in triangle.get("source_polygon_ids", [polygon_id]):
			source_polygon_ids[String(source_polygon_id_value)] = true
	var level_patch: Array[Dictionary] = []
	for triangle in all_triangles:
		if selected_patch_id_set.has(String(triangle.get("triangle_id", ""))):
			level_patch.append(triangle)
	if level_patch.size() != selected_patch_id_set.size():
		return {"valid": false, "reason": "r2_selected_patch_face_missing", "expected": selected_patch_id_set.size(), "observed": level_patch.size()}
	var local_residual_fixture: Dictionary = residual_fixture.duplicate(true)
	local_residual_fixture["arc_map"] = local_arc_result.get("arc_map", []).duplicate(true)
	var context: Dictionary = {"phase": _cxr_active_phase, "level": level, "patch": patch.duplicate(), "level_patch": level_patch, "patch_ids": patch_ids.duplicate(), "all_triangles": all_triangles.duplicate(), "residual_triangles": residual_triangles.duplicate(), "residual_id_set": residual_id_set, "owner_polygon_ids": owner_polygon_ids, "source_polygon_ids": source_polygon_ids, "residual_fixture": local_residual_fixture, "global_arc_map": constraint_arcs.duplicate(true), "global_applied_flips": residual_fixture.get("applied_flips", []).duplicate(true), "support_by_id": support_by_id, "vertex_positions": vertex_positions, "source_root_ids": source_root_ids, "required_topology_root_ids": required_topology_root_ids, "local_required_arc_count": local_arc_result.get("arc_map", []).size(), "source_owner_boundary_arc_count": owner_arc_result.get("arc_map", []).size(), "vertex_ids": all_vertex_ids, "boundary_cycle": cycle, "boundary_edge_map": boundary_edge_map, "boundary_signature": String(boundary.get("signature", "")), "r3_cavity_boundary": boundary.duplicate(true) if _cxr_active_phase == "r3" else {}, "projected_positions": projected_positions, "polygon": polygon, "projection_origin": origin, "projection_u": axis_u, "projection_v": axis_v, "reference_normal": normal, "candidate_triangle_rows": [], "candidate_triangle_cache": {}, "candidate_triangle_cache_hits": 0, "candidate_edges": {}, "search_complete": true, "search_exhaustive": true, "limit_reason": "", "limits_hit": [], "search_nodes": 0, "branches": 0, "prunes": {}, "solution_rejections": [], "branch_counts": {}, "candidate_triangle_count": 0, "solution_count": 0, "retained_solutions": [], "best_solution": {}, "visited_by_support_count": {}, "start_usec": Time.get_ticks_usec(), "solution_scoring_enabled": not _cxr_active_snapshot.is_empty()}
	return {"valid": true, "context": context}

func _r2_localize_topology_arcs(arcs: Array, local_root_ids: Dictionary, boundary_cycle: Array[String], root_positions: Dictionary, vertex_positions: Dictionary, projected_positions: Dictionary, polygon: Array[Vector2], origin: Vector3, axis_u: Vector3, axis_v: Vector3) -> Dictionary:
	var boundary_ids: Dictionary = {}
	for root_id in boundary_cycle:
		boundary_ids[root_id] = true
	var local_arcs: Array[Dictionary] = []
	var local_arc_by_edge: Dictionary = {}
	var topology_root_ids: Dictionary = {}
	for arc_value in arcs:
		if typeof(arc_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "r2_topology_arc_malformed"}
		var arc: Dictionary = arc_value
		var ids: Array = arc.get("root_ids", [])
		if ids.size() != 2:
			continue
		var a_id: String = String(ids[0])
		var b_id: String = String(ids[1])
		if a_id.is_empty() or b_id.is_empty() or a_id == b_id:
			return {"valid": false, "reason": "r2_topology_arc_identity_invalid", "arc_id": arc.get("arc_id", "")}
		if not local_root_ids.has(a_id) and not local_root_ids.has(b_id) and not boundary_ids.has(a_id) and not boundary_ids.has(b_id):
			continue
		if not root_positions.has(a_id) or not root_positions.has(b_id) or not (root_positions[a_id] is Vector3) or not (root_positions[b_id] is Vector3):
			return {"valid": false, "reason": "r2_local_topology_arc_root_position_missing", "arc_id": arc.get("arc_id", ""), "root_ids": ids}
		var a3: Vector3 = root_positions[a_id]
		var b3: Vector3 = root_positions[b_id]
		var a_delta: Vector3 = a3 - origin
		var b_delta: Vector3 = b3 - origin
		var a2: Vector2 = Vector2(a_delta.dot(axis_u), a_delta.dot(axis_v))
		var b2: Vector2 = Vector2(b_delta.dot(axis_u), b_delta.dot(axis_v))
		var a_inside: bool = _r2_point_in_polygon(a2, polygon)
		var b_inside: bool = _r2_point_in_polygon(b2, polygon)
		var enters_interior: bool = _r2_segment_enters_polygon_interior(a2, b2, polygon)
		if not a_inside or not b_inside:
			if enters_interior:
				return {"valid": false, "reason": "r2_topology_arc_crosses_cavity_boundary", "arc_id": arc.get("arc_id", ""), "root_ids": ids}
			continue
		if not _r2_segment_contained_in_polygon(a2, b2, polygon):
			return {"valid": false, "reason": "r2_topology_arc_leaves_concave_cavity_domain", "arc_id": arc.get("arc_id", ""), "root_ids": ids}
		for endpoint_index in range(2):
			var endpoint_id: String = a_id if endpoint_index == 0 else b_id
			var endpoint: Vector2 = a2 if endpoint_index == 0 else b2
			if _r2_point_on_polygon_boundary(endpoint, polygon) and not boundary_ids.has(endpoint_id):
				return {"valid": false, "reason": "r2_topology_root_missing_from_boundary_cycle", "arc_id": arc.get("arc_id", ""), "root_id": endpoint_id}
			if not vertex_positions.has(endpoint_id):
				vertex_positions[endpoint_id] = a3 if endpoint_index == 0 else b3
				projected_positions[endpoint_id] = endpoint
			if not boundary_ids.has(endpoint_id):
				topology_root_ids[endpoint_id] = true
		var expected: int = int(arc.get("expected_incidence", 0))
		if expected < 1 or expected > 2:
			return {"valid": false, "reason": "r2_topology_arc_expected_incidence_invalid", "arc_id": arc.get("arc_id", ""), "expected_incidence": expected}
		var arc_key: String = _edge_key(a_id, b_id)
		if local_arc_by_edge.has(arc_key):
			var prior_arc: Dictionary = local_arc_by_edge[arc_key]
			if int(prior_arc.get("expected_incidence", 0)) != expected:
				return {"valid": false, "reason": "r2_topology_arc_incidence_conflict", "root_ids": ids, "expected_incidence_values": [prior_arc.get("expected_incidence", 0), expected]}
			continue
		local_arc_by_edge[arc_key] = arc
		local_arcs.append(arc.duplicate(true))
	local_arcs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("arc_id", "")) < String(b.get("arc_id", "")))
	var topology_ids: Array = topology_root_ids.keys()
	topology_ids.sort()
	return {"valid": true, "arc_map": local_arcs, "topology_root_ids": topology_root_ids, "topology_root_id_list": topology_ids}

func _r2_residual_owner_boundary_arcs(residual_triangles: Array[Dictionary]) -> Dictionary:
	var edge_owners: Dictionary = {}
	var edge_endpoints: Dictionary = {}
	var edge_incidence: Dictionary = {}
	for triangle in residual_triangles:
		var ids: Array = triangle.get("root_ids", [])
		var points: Array = triangle.get("points", [])
		if ids.size() != 3 or points.size() != 3:
			return {"valid": false, "reason": "r2_owner_boundary_triangle_arity_invalid", "triangle_id": triangle.get("triangle_id", "")}
		var polygon_id: String = String(triangle.get("polygon_id", ""))
		if polygon_id.is_empty():
			return {"valid": false, "reason": "r2_owner_boundary_polygon_id_missing", "triangle_id": triangle.get("triangle_id", "")}
		var source_ids: Array = triangle.get("source_polygon_ids", [polygon_id]).duplicate()
		source_ids.sort()
		var source_id_strings: PackedStringArray = PackedStringArray()
		for source_id_value in source_ids:
			source_id_strings.append(String(source_id_value))
		var owner_key: String = polygon_id + "|" + ",".join(source_id_strings)
		for edge_index in range(3):
			var a_id: String = String(ids[edge_index])
			var b_id: String = String(ids[(edge_index + 1) % 3])
			if a_id.is_empty() or b_id.is_empty() or a_id == b_id:
				return {"valid": false, "reason": "r2_owner_boundary_root_edge_invalid", "triangle_id": triangle.get("triangle_id", "")}
			var key: String = _edge_key(a_id, b_id)
			if not edge_owners.has(key): edge_owners[key] = {}
			edge_owners[key][owner_key] = true
			edge_endpoints[key] = [a_id, b_id]
			edge_incidence[key] = int(edge_incidence.get(key, 0)) + 1
	var result: Array[Dictionary] = []
	var edge_keys: Array = edge_owners.keys()
	edge_keys.sort()
	for edge_key_value in edge_keys:
		var edge_key: String = String(edge_key_value)
		if int(edge_incidence.get(edge_key, 0)) > 2:
			return {"valid": false, "reason": "r2_source_owner_edge_nonmanifold", "edge_key": edge_key, "incidence": edge_incidence[edge_key]}
		var owners: Dictionary = edge_owners[edge_key]
		if owners.size() < 2:
			continue
		var endpoints: Array = edge_endpoints[edge_key]
		result.append({"arc_id": "R2_OWNER_BOUNDARY_" + Core.sha256(edge_key.to_utf8_buffer()).substr(0, 20), "root_ids": endpoints.duplicate(), "expected_incidence": 2, "constraint_source": "residual_source_polygon_owner_boundary", "source_owner_keys": _sorted_keys(owners)})
	return {"valid": true, "arc_map": result}

func _r2_merge_arc_constraints(source_arcs: Array, additional_arcs: Array) -> Dictionary:
	var by_edge: Dictionary = {}
	for source_set in [source_arcs, additional_arcs]:
		for arc_value in source_set:
			if typeof(arc_value) != TYPE_DICTIONARY:
				return {"valid": false, "reason": "r2_arc_constraint_not_dictionary"}
			var arc: Dictionary = arc_value
			var ids: Array = arc.get("root_ids", [])
			if ids.size() != 2:
				continue
			var a_id: String = String(ids[0])
			var b_id: String = String(ids[1])
			if a_id.is_empty() or b_id.is_empty() or a_id == b_id:
				return {"valid": false, "reason": "r2_arc_constraint_identity_invalid", "arc_id": arc.get("arc_id", "")}
			var expected: int = int(arc.get("expected_incidence", 0))
			if expected < 1 or expected > 2:
				return {"valid": false, "reason": "r2_arc_constraint_expected_incidence_invalid", "arc_id": arc.get("arc_id", ""), "expected_incidence": expected}
			var key: String = _edge_key(a_id, b_id)
			if not by_edge.has(key):
				by_edge[key] = arc.duplicate(true)
			else:
				var prior: Dictionary = by_edge[key]
				if int(prior.get("expected_incidence", 0)) != expected:
					return {"valid": false, "reason": "r2_arc_constraint_expected_incidence_conflict", "root_ids": ids}
				var sources: Array = prior.get("constraint_sources", [])
				var source: String = String(arc.get("constraint_source", "canonical_topology_arc"))
				if not sources.has(source): sources.append(source)
				prior["constraint_sources"] = sources
				by_edge[key] = prior
	var keys: Array = by_edge.keys()
	keys.sort()
	var merged: Array[Dictionary] = []
	for key_value in keys:
		merged.append(by_edge[String(key_value)])
	return {"valid": true, "arc_map": merged}

func _r2_point_on_polygon_boundary(point: Vector2, polygon: Array[Vector2]) -> bool:
	for index in range(polygon.size()):
		if _r2_endpoint_strictly_inside_segment_2d(point, polygon[index], polygon[(index + 1) % polygon.size()]):
			return true
		if point.distance_squared_to(polygon[index]) <= TRIANGLE_EPSILON * TRIANGLE_EPSILON:
			return true
	return false

func _r2_point_strictly_inside_polygon(point: Vector2, polygon: Array[Vector2]) -> bool:
	return _r2_point_in_polygon(point, polygon) and not _r2_point_on_polygon_boundary(point, polygon)

func _r2_segment_parameters(a: Vector2, b: Vector2, polygon: Array[Vector2]) -> Array[float]:
	var parameters: Array[float] = [0.0, 1.0]
	var direction: Vector2 = b - a
	var length_squared: float = direction.length_squared()
	if length_squared <= 0.0:
		return parameters
	for index in range(polygon.size()):
		var c: Vector2 = polygon[index]
		var d: Vector2 = polygon[(index + 1) % polygon.size()]
		var edge: Vector2 = d - c
		var denominator: float = direction.cross(edge)
		var offset: Vector2 = c - a
		if absf(denominator) > 1e-20:
			var t: float = offset.cross(edge) / denominator
			var u: float = offset.cross(direction) / denominator
			if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
				parameters.append(t)
		elif absf(offset.cross(direction)) <= 1e-12:
			var t0: float = (c - a).dot(direction) / length_squared
			var t1: float = (d - a).dot(direction) / length_squared
			if t0 >= 0.0 and t0 <= 1.0: parameters.append(t0)
			if t1 >= 0.0 and t1 <= 1.0: parameters.append(t1)
	parameters.sort()
	var unique: Array[float] = []
	for value in parameters:
		if unique.is_empty() or absf(value - unique[unique.size() - 1]) > 1e-12:
			unique.append(value)
	return unique

func _r2_segment_enters_polygon_interior(a: Vector2, b: Vector2, polygon: Array[Vector2]) -> bool:
	if _r2_point_strictly_inside_polygon(a, polygon) or _r2_point_strictly_inside_polygon(b, polygon):
		return true
	var parameters: Array[float] = _r2_segment_parameters(a, b, polygon)
	for index in range(parameters.size() - 1):
		if float(parameters[index + 1]) - float(parameters[index]) <= 1e-12:
			continue
		var midpoint: Vector2 = a.lerp(b, (float(parameters[index]) + float(parameters[index + 1])) * 0.5)
		if _r2_point_strictly_inside_polygon(midpoint, polygon):
			return true
	return false

func _r2_segment_contained_in_polygon(a: Vector2, b: Vector2, polygon: Array[Vector2]) -> bool:
	if not _r2_point_in_polygon(a, polygon) or not _r2_point_in_polygon(b, polygon):
		return false
	var parameters: Array[float] = _r2_segment_parameters(a, b, polygon)
	for index in range(parameters.size() - 1):
		if float(parameters[index + 1]) - float(parameters[index]) <= 1e-12:
			continue
		var midpoint: Vector2 = a.lerp(b, (float(parameters[index]) + float(parameters[index + 1])) * 0.5)
		if not _r2_point_in_polygon(midpoint, polygon):
			return false
	return true

func _r2_boundary_cycle(boundary: Dictionary) -> Dictionary:
	var successors: Dictionary = {}
	var incoming: Dictionary = {}
	for edge_value in boundary.get("directed_edges", []):
		var split: PackedStringArray = String(edge_value).split("->")
		if split.size() != 2:
			return {"valid": false, "reason": "boundary_directed_edge_malformed"}
		var a: String = String(split[0])
		var b: String = String(split[1])
		if successors.has(a) or incoming.has(b):
			return {"valid": false, "reason": "boundary_cycle_degree_invalid", "edge": String(edge_value)}
		successors[a] = b
		incoming[b] = a
	if successors.size() < 3 or successors.size() != incoming.size():
		return {"valid": false, "reason": "boundary_cycle_vertex_count_invalid"}
	var starts: Array = successors.keys()
	starts.sort()
	var start: String = String(starts[0])
	var cycle: Array[String] = []
	var seen: Dictionary = {}
	var current: String = start
	while not seen.has(current):
		seen[current] = true
		cycle.append(current)
		if not successors.has(current):
			return {"valid": false, "reason": "boundary_cycle_open", "at": current}
		current = String(successors[current])
	if current != start or cycle.size() != successors.size():
		return {"valid": false, "reason": "boundary_cycle_multiple_loops", "visited": cycle.size(), "vertices": successors.size()}
	return {"valid": true, "cycle": cycle}

func _r2_polygon_signed_area(polygon: Array[Vector2]) -> float:
	var twice_area: float = 0.0
	for index in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		twice_area += a.x * b.y - b.x * a.y
	return twice_area * 0.5

func _r2_point_in_polygon(point: Vector2, polygon: Array[Vector2], epsilon: float = CXR_BARYCENTRIC_EPSILON) -> bool:
	var inside: bool = false
	for index in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var segment: Vector2 = b - a
		var length_squared: float = segment.length_squared()
		if length_squared > 1e-20:
			var t: float = clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
			if (point - (a + segment * t)).length_squared() <= epsilon * epsilon:
				return true
		if (a.y > point.y) != (b.y > point.y):
			var x_cross: float = a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if point.x < x_cross:
				inside = not inside
	return inside

func _r2_orientation(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)

func _r2_proper_segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c: float = _r2_orientation(a, b, c)
	var ab_d: float = _r2_orientation(a, b, d)
	var cd_a: float = _r2_orientation(c, d, a)
	var cd_b: float = _r2_orientation(c, d, b)
	return ab_c * ab_d < -1e-20 and cd_a * cd_b < -1e-20

func _r2_segment_inside_polygon(a_id: String, b_id: String, a: Vector2, b: Vector2, context: Dictionary) -> bool:
	# Partition at every polygon-edge intersection; midpoint-only checks miss a
	# segment that exits and re-enters a concave cavity through a boundary vertex.
	return _r2_segment_contained_in_polygon(a, b, context.polygon)

func _r2_triangle_inside_domain(ids: Array[String], context: Dictionary) -> Dictionary:
	var points: Array[Vector2] = []
	for vertex_id in ids:
		if not context.projected_positions.has(vertex_id):
			return {"valid": false, "reason": "triangle_vertex_projection_missing", "vertex_id": vertex_id}
		var point: Vector2 = context.projected_positions[vertex_id]
		if not _r2_point_in_polygon(point, context.polygon):
			return {"valid": false, "reason": "triangle_vertex_outside_boundary", "vertex_id": vertex_id}
		points.append(point)
	for edge_index in range(3):
		var next_index: int = (edge_index + 1) % 3
		if not _r2_segment_inside_polygon(ids[edge_index], ids[next_index], points[edge_index], points[next_index], context):
			return {"valid": false, "reason": "triangle_edge_outside_or_crosses_boundary", "edge": [ids[edge_index], ids[next_index]]}
	var centroid: Vector2 = (points[0] + points[1] + points[2]) / 3.0
	if not _r2_point_in_polygon(centroid, context.polygon):
		return {"valid": false, "reason": "triangle_centroid_outside_boundary"}
	return {"valid": true}

func _r2_search_level(context: Dictionary) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var solutions_before: int = int(context.solution_count)
	var max_support_count: int = mini(CXR_MAX_SELECTED_SUPPORTS, context.support_by_id.size())
	for target_support_count in range(max_support_count + 1):
		if not bool(context.search_complete):
			break
		_r2_search_fixed_support_count(context, target_support_count)
		if not bool(context.search_complete):
			break
		if int(context.solution_count) > solutions_before:
			break
	var valid: bool = not context.best_solution.is_empty()
	var complete: bool = bool(context.search_complete)
	var terminal_reason: String = String(context.limit_reason) if not String(context.limit_reason).is_empty() else "r2_finite_triangulation_domain_exhausted"
	var support_cardinality_distribution: Dictionary = {}
	var cardinalities: Array = context.visited_by_support_count.keys()
	cardinalities.sort()
	for cardinality_value in cardinalities:
		var cardinality: int = int(cardinality_value)
		support_cardinality_distribution[str(cardinality)] = int(context.visited_by_support_count[cardinality].size())
	return {"valid": valid, "search_complete": complete, "search_exhaustive": bool(context.search_exhaustive) and complete, "terminal_reason": terminal_reason, "best_solution": context.best_solution, "solution_count": int(context.solution_count) - solutions_before, "retained_solutions": context.retained_solutions.duplicate(true), "branches": int(context.branches), "states": int(context.search_nodes), "prune_histogram": context.prunes.duplicate(true), "support_cardinality_distribution_explored": support_cardinality_distribution, "candidate_triangle_cache_hits": int(context.candidate_triangle_cache_hits), "search_usec": Time.get_ticks_usec() - started_usec, "candidate_triangle_count": int(context.candidate_triangle_count)}

func _r2_search_fixed_support_count(context: Dictionary, target_support_count: int) -> void:
	context.target_support_count = target_support_count
	context.visited_by_support_count[target_support_count] = {}
	_r2_search_recursive([], context)

func _r2_search_recursive(triangles: Array[Dictionary], context: Dictionary) -> void:
	if not bool(context.search_complete):
		return
	var now_usec: int = Time.get_ticks_usec()
	var limit_reason: String = _cxr_time_limit_reason_at(now_usec)
	if limit_reason.is_empty():
		limit_reason = _cxr_global_limit_reason_at(now_usec)
	if limit_reason.is_empty() and _cxr_search_nodes_cavity >= CXR_R2_MAX_SEARCH_STATES_PER_CAVITY:
		limit_reason = "R2_MAX_SEARCH_STATES_PER_CAVITY"
	if not limit_reason.is_empty():
		context.search_complete = false
		context.search_exhaustive = false
		context.limit_reason = limit_reason
		_append_limit(context.limits_hit, limit_reason)
		return
	var state_key: String = _r2_state_key(triangles)
	var target_support_count: int = int(context.target_support_count)
	var visited: Dictionary = context.visited_by_support_count[target_support_count]
	if visited.has(state_key):
		_r2_count(context.prunes, "duplicate_state")
		return
	visited[state_key] = true
	context.search_nodes = int(context.search_nodes) + 1
	_cxr_search_nodes_total += 1
	_cxr_search_nodes_cavity += 1
	context.branches = int(context.branches) + 1
	_r2_count(context.branch_counts, "states")
	_r2_count(_cxr_active_cavity_branches, "states")
	var edge_state: Dictionary = _r2_build_edge_state(triangles)
	var edge_check: Dictionary = _r2_next_obligation(edge_state, context)
	if not bool(edge_check.get("valid", false)):
		_r2_count(context.prunes, String(edge_check.get("reason", "invalid_edge_state")))
		_r2_count(_cxr_active_cavity_prunes, String(edge_check.get("reason", "invalid_edge_state")))
		return
	if bool(edge_check.get("complete", false)):
		var selected_support_ids: Array[String] = _r2_used_support_ids(triangles, context)
		if selected_support_ids.size() == target_support_count:
			var solution: Dictionary = _r2_validate_solution(triangles, selected_support_ids, edge_state, context)
			if bool(solution.get("valid", false)):
				_r2_record_solution(solution, context)
			else:
				if context.solution_rejections.size() < 128:
					context.solution_rejections.append({"reason": String(solution.get("reason", "solution_validation_failed")), "triangle_ids": triangles.map(func(triangle: Dictionary) -> String: return String(triangle.get("triangle_id", ""))).duplicate(), "diagnostics": solution.duplicate(true)})
				_r2_count(context.prunes, String(solution.get("reason", "solution_validation_failed")))
				_r2_count(_cxr_active_cavity_prunes, String(solution.get("reason", "solution_validation_failed")))
			return
		if selected_support_ids.size() < target_support_count:
			_r2_branch_insert_support(triangles, edge_state, selected_support_ids, context)
		return
	if triangles.size() >= CXR_MAX_PATCH_TRIANGLES:
		_r2_count(context.prunes, "max_patch_triangles")
		_r2_count(_cxr_active_cavity_prunes, "max_patch_triangles")
		return
	var edge: Dictionary = edge_check.edge
	var a_id: String = String(edge.a)
	var b_id: String = String(edge.b)
	var options: Array = context.vertex_ids.duplicate()
	options.sort()
	for third_value in options:
		if not bool(context.search_complete):
			return
		var third_id: String = String(third_value)
		if third_id == a_id or third_id == b_id:
			continue
		var candidate_result: Dictionary = _r2_get_candidate_triangle([a_id, b_id, third_id], context)
		if not bool(candidate_result.get("valid", false)):
			if bool(candidate_result.get("limit", false)):
				context.search_complete = false
				context.search_exhaustive = false
				context.limit_reason = String(candidate_result.get("reason", "R2_CANDIDATE_TRIANGLE_LIMIT"))
				_append_limit(context.limits_hit, context.limit_reason)
				return
			_r2_count(context.prunes, String(candidate_result.get("reason", "candidate_triangle_invalid")))
			continue
		var candidate: Dictionary = candidate_result.triangle
		if not _r2_candidate_can_extend(candidate, edge_state, context):
			_r2_count(context.prunes, "edge_incidence_or_orientation_conflict")
			continue
		var next_supports: Array[String] = _r2_used_support_ids_with_candidate(triangles, candidate, context)
		if next_supports.size() > target_support_count:
			_r2_count(context.prunes, "support_count_exceeded")
			continue
		if _r2_duplicate_support_positions(next_supports, context):
			_r2_count(context.prunes, "duplicate_support_position")
			continue
		var next_triangles: Array[Dictionary] = triangles.duplicate()
		next_triangles.append(candidate)
		_r2_search_recursive(next_triangles, context)

func _r2_count(counter: Dictionary, key: String) -> void:
	counter[key] = int(counter.get(key, 0)) + 1

func _r2_state_key(triangles: Array[Dictionary]) -> String:
	var triangle_keys: Array[String] = []
	for triangle in triangles:
		triangle_keys.append(_triplet_key(triangle.get("root_ids", [])))
	triangle_keys.sort()
	return "|".join(triangle_keys)

func _r2_build_edge_state(triangles: Array[Dictionary]) -> Dictionary:
	var state: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3:
			continue
		for edge_index in range(3):
			var a: String = String(ids[edge_index])
			var b: String = String(ids[(edge_index + 1) % 3])
			var key: String = _edge_key(a, b)
			if not state.has(key):
				state[key] = []
			state[key].append({"a": a, "b": b, "triangle_id": String(triangle.get("triangle_id", ""))})
	return state

func _r2_next_obligation(edge_state: Dictionary, context: Dictionary) -> Dictionary:
	var boundary_keys: Array = context.boundary_edge_map.keys()
	boundary_keys.sort()
	for key_value in boundary_keys:
		var key: String = String(key_value)
		var expected: Dictionary = context.boundary_edge_map[key]
		var rows: Array = edge_state.get(key, [])
		if rows.size() == 0:
			return {"valid": true, "complete": false, "edge": {"key": key, "a": expected.a, "b": expected.b, "boundary": true}}
		if rows.size() != 1 or String(rows[0].a) != String(expected.a) or String(rows[0].b) != String(expected.b):
			return {"valid": false, "complete": false, "reason": "boundary_edge_incidence_or_winding_invalid", "edge_key": key, "expected": expected, "observed": rows}
	var open_internal: Array = []
	var sorted_state_keys: Array = edge_state.keys()
	sorted_state_keys.sort()
	for key_value in sorted_state_keys:
		var key: String = String(key_value)
		if context.boundary_edge_map.has(key):
			continue
		var rows: Array = edge_state[key]
		if rows.size() > 2:
			return {"valid": false, "complete": false, "reason": "nonmanifold_candidate_edge", "edge_key": key, "incidence": rows.size()}
		if rows.size() == 1:
			open_internal.append(key)
	if not open_internal.is_empty():
		open_internal.sort()
		var rows: Array = edge_state[open_internal[0]]
		return {"valid": true, "complete": false, "edge": {"key": String(open_internal[0]), "a": String(rows[0].b), "b": String(rows[0].a), "boundary": false}}
	for key_value in boundary_keys:
		if not edge_state.has(String(key_value)):
			return {"valid": true, "complete": false, "edge": {"key": String(key_value), "a": context.boundary_edge_map[String(key_value)].a, "b": context.boundary_edge_map[String(key_value)].b, "boundary": true}}
	return {"valid": true, "complete": true}

func _r2_candidate_can_extend(candidate: Dictionary, edge_state: Dictionary, context: Dictionary) -> bool:
	var ids: Array = candidate.get("root_ids", [])
	for edge_index in range(3):
		var a: String = String(ids[edge_index])
		var b: String = String(ids[(edge_index + 1) % 3])
		var key: String = _edge_key(a, b)
		var rows: Array = edge_state.get(key, [])
		if context.boundary_edge_map.has(key):
			var expected: Dictionary = context.boundary_edge_map[key]
			if rows.size() > 0 or a != String(expected.a) or b != String(expected.b):
				return false
		elif rows.size() > 1 or (rows.size() == 1 and String(rows[0].a) == a and String(rows[0].b) == b):
			return false
	return true

func _r2_used_support_ids(triangles: Array[Dictionary], context: Dictionary) -> Array[String]:
	var used: Dictionary = {}
	for triangle in triangles:
		for id_value in triangle.get("root_ids", []):
			var id: String = String(id_value)
			if context.support_by_id.has(id):
				used[id] = true
	var result: Array[String] = []
	for id_value in used.keys():
		result.append(String(id_value))
	result.sort()
	return result

func _r2_used_support_ids_with_candidate(triangles: Array[Dictionary], candidate: Dictionary, context: Dictionary) -> Array[String]:
	var all_triangles: Array[Dictionary] = triangles.duplicate()
	all_triangles.append(candidate)
	return _r2_used_support_ids(all_triangles, context)

func _r2_duplicate_support_positions(ids: Array[String], context: Dictionary) -> bool:
	for i in range(ids.size()):
		var a: Vector3 = context.vertex_positions[ids[i]]
		for j in range(i + 1, ids.size()):
			var b: Vector3 = context.vertex_positions[ids[j]]
			if var_to_bytes(a) == var_to_bytes(b):
				return true
	return false

func _r2_get_candidate_triangle(ids_input: Array, context: Dictionary) -> Dictionary:
	var ids: Array[String] = [String(ids_input[0]), String(ids_input[1]), String(ids_input[2])]
	if ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]:
		return {"valid": false, "reason": "candidate_repeated_vertex"}
	var cache_key: String = _triplet_key(ids)
	if context.candidate_triangle_cache.has(cache_key):
		context.candidate_triangle_cache_hits = int(context.get("candidate_triangle_cache_hits", 0)) + 1
		return context.candidate_triangle_cache[cache_key]
	var time_limit: String = _cxr_time_limit_reason()
	if not time_limit.is_empty():
		return {"valid": false, "limit": true, "reason": time_limit}
	if not _cxr_full_finite_graph_mode and (_cxr_candidate_triangles_cavity >= CXR_R2_MAX_CANDIDATE_TRIANGLES_PER_CAVITY or _cxr_candidate_triangles_total >= CXR_R2_MAX_CANDIDATE_TRIANGLES_TOTAL):
		return {"valid": false, "limit": true, "reason": "R2_MAX_CANDIDATE_TRIANGLES"}
	context.candidate_triangle_count = int(context.candidate_triangle_count) + 1
	_cxr_candidate_triangles_total += 1
	_cxr_candidate_triangles_cavity += 1
	var row: Dictionary = {"candidate_id": "R2T_" + Core.sha256(cache_key.to_utf8_buffer()).substr(0, 20), "vertex_ids": ids.duplicate(), "valid": false, "rejection_reason": "UNKNOWN_NOT_CAPTURED"}
	var points: Array[Vector3] = []
	for id in ids:
		if not context.vertex_positions.has(id):
			row.rejection_reason = "candidate_vertex_position_missing"
			context.candidate_triangle_rows.append(row)
			var rejected: Dictionary = {"valid": false, "reason": row.rejection_reason}
			context.candidate_triangle_cache[cache_key] = rejected
			return rejected
		points.append(context.vertex_positions[id])
	var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	var cross_squared: float = cross.length_squared()
	row["cross_squared"] = cross_squared
	row["cutoff_squared"] = CXR_CUTOFF_SQUARED
	if not is_finite(cross_squared) or cross_squared <= CXR_CUTOFF_SQUARED:
		row.rejection_reason = "candidate_cross_squared_at_or_below_frozen_cutoff"
		context.candidate_triangle_rows.append(row)
		var rejected: Dictionary = {"valid": false, "reason": row.rejection_reason, "cross_squared": cross_squared}
		context.candidate_triangle_cache[cache_key] = rejected
		return rejected
	var domain_check: Dictionary = _r2_triangle_inside_domain(ids, context)
	if not bool(domain_check.get("valid", false)):
		row.rejection_reason = String(domain_check.get("reason", "candidate_outside_boundary"))
		row["domain_diagnostics"] = domain_check
		context.candidate_triangle_rows.append(row)
		var rejected: Dictionary = {"valid": false, "reason": row.rejection_reason, "domain_diagnostics": domain_check}
		context.candidate_triangle_cache[cache_key] = rejected
		return rejected
	var arc_check: Dictionary = _r2_triangle_respects_required_arcs(ids, context)
	if not bool(arc_check.get("valid", false)):
		row.rejection_reason = String(arc_check.get("reason", "candidate_crosses_required_topology_arc"))
		row["arc_diagnostics"] = arc_check
		context.candidate_triangle_rows.append(row)
		var rejected: Dictionary = {"valid": false, "reason": row.rejection_reason, "arc_diagnostics": arc_check}
		context.candidate_triangle_cache[cache_key] = rejected
		return rejected
	var reference_normal: Vector3 = _r2_reference_normal((points[0] + points[1] + points[2]) / 3.0, context)
	var alignment: float = cross.normalized().dot(reference_normal)
	if absf(alignment) <= 1e-8:
		row.rejection_reason = "candidate_winding_reference_ambiguous"
		context.candidate_triangle_rows.append(row)
		var rejected: Dictionary = {"valid": false, "reason": row.rejection_reason, "normal_alignment": alignment}
		context.candidate_triangle_cache[cache_key] = rejected
		return rejected
	if alignment < 0.0:
		var swap_id: String = ids[1]
		ids[1] = ids[2]
		ids[2] = swap_id
		var swap_point: Vector3 = points[1]
		points[1] = points[2]
		points[2] = swap_point
		alignment = -alignment
	var owner: Dictionary = _r2_owner_for_triangle((points[0] + points[1] + points[2]) / 3.0, context)
	if not bool(owner.get("valid", false)):
		row.rejection_reason = String(owner.get("reason", "candidate_owner_unresolved"))
		row["owner_diagnostics"] = owner
		context.candidate_triangle_rows.append(row)
		var rejected: Dictionary = {"valid": false, "reason": row.rejection_reason, "owner_diagnostics": owner}
		context.candidate_triangle_cache[cache_key] = rejected
		return rejected
	var triangle_prefix: String = "R12CXR4_" if String(context.get("phase", "")) == "r4" else "R12CXR3_" if String(context.get("phase", "")) == "r3" else "R12CXR2_"
	var triangle_id: String = triangle_prefix + Core.sha256(cache_key.to_utf8_buffer()).substr(0, 24)
	var triangle: Dictionary = _triangle(triangle_id, String(owner.get("polygon_id", "")), ids, points, "r2_constrained_support_triangulation", false, CXR_CUTOFF_SQUARED)
	triangle["source_polygon_ids"] = owner.get("source_polygon_ids", [owner.get("polygon_id", "")]).duplicate()
	triangle["r2_owner_source_triangle_id"] = String(owner.get("source_triangle_id", ""))
	triangle["r2_owner_candidates"] = owner.get("candidate_source_triangle_ids", [])
	triangle["r2_candidate_id"] = row.candidate_id
	triangle["r2_normal_alignment"] = alignment
	row["valid"] = true
	row["rejection_reason"] = ""
	row["normal_alignment"] = alignment
	row["triangle_id"] = triangle_id
	row["oriented_vertex_ids"] = ids.duplicate()
	row["owner"] = owner
	context.candidate_triangle_rows.append(row)
	_r2_record_candidate_edges(ids, row.candidate_id, context)
	var result: Dictionary = {"valid": true, "triangle": triangle, "candidate_id": row.candidate_id}
	context.candidate_triangle_cache[cache_key] = result
	return result

func _r2_triangle_respects_required_arcs(ids: Array[String], context: Dictionary) -> Dictionary:
	var triangle_points: Array[Vector2] = []
	for root_id in ids:
		if not context.projected_positions.has(root_id):
			return {"valid": false, "reason": "required_arc_triangle_projection_missing", "root_id": root_id}
		triangle_points.append(context.projected_positions[root_id])
	for arc_value in context.residual_fixture.get("arc_map", []):
		var arc: Dictionary = arc_value
		var arc_ids: Array = arc.get("root_ids", [])
		if arc_ids.size() != 2:
			continue
		var arc_a: String = String(arc_ids[0])
		var arc_b: String = String(arc_ids[1])
		var arc_key: String = _edge_key(arc_a, arc_b)
		var exact_triangle_edge: bool = false
		for edge_index in range(3):
			if _edge_key(ids[edge_index], ids[(edge_index + 1) % 3]) == arc_key:
				exact_triangle_edge = true
				break
		if exact_triangle_edge:
			continue
		if not context.projected_positions.has(arc_a) or not context.projected_positions.has(arc_b):
			return {"valid": false, "reason": "required_arc_projection_missing", "arc_id": arc.get("arc_id", ""), "root_ids": arc_ids}
		var a: Vector2 = context.projected_positions[arc_a]
		var b: Vector2 = context.projected_positions[arc_b]
		for index in range(3):
			var edge_a: Vector2 = triangle_points[index]
			var edge_b: Vector2 = triangle_points[(index + 1) % 3]
			var edge_a_id: String = ids[index]
			var edge_b_id: String = ids[(index + 1) % 3]
			if edge_a_id == arc_a or edge_a_id == arc_b or edge_b_id == arc_a or edge_b_id == arc_b:
				# A shared endpoint is legal, but an arc endpoint in the interior of
				# the candidate edge remains a T-junction and is rejected below.
				if (arc_a != edge_a_id and arc_a != edge_b_id and _r2_endpoint_strictly_inside_segment_2d(a, edge_a, edge_b)) or (arc_b != edge_a_id and arc_b != edge_b_id and _r2_endpoint_strictly_inside_segment_2d(b, edge_a, edge_b)):
					return {"valid": false, "reason": "candidate_edge_splits_required_arc_endpoint", "arc_id": arc.get("arc_id", ""), "triangle_edge": [edge_a_id, edge_b_id]}
				if (edge_a_id != arc_a and edge_a_id != arc_b and _r2_endpoint_strictly_inside_segment_2d(edge_a, a, b)) or (edge_b_id != arc_a and edge_b_id != arc_b and _r2_endpoint_strictly_inside_segment_2d(edge_b, a, b)):
					return {"valid": false, "reason": "candidate_edge_overlaps_required_arc_interior", "arc_id": arc.get("arc_id", ""), "triangle_edge": [edge_a_id, edge_b_id]}
				continue
			if _r2_proper_segments_intersect(edge_a, edge_b, a, b) or _r2_endpoint_strictly_inside_segment_2d(edge_a, a, b) or _r2_endpoint_strictly_inside_segment_2d(edge_b, a, b) or _r2_endpoint_strictly_inside_segment_2d(a, edge_a, edge_b) or _r2_endpoint_strictly_inside_segment_2d(b, edge_a, edge_b):
				return {"valid": false, "reason": "candidate_edge_crosses_required_topology_arc", "arc_id": arc.get("arc_id", ""), "triangle_edge": [edge_a_id, edge_b_id]}
		if not ids.has(arc_a) and _r2_point_strictly_inside_triangle_2d(a, triangle_points):
			return {"valid": false, "reason": "required_arc_endpoint_inside_candidate_triangle", "arc_id": arc.get("arc_id", ""), "root_id": arc_a}
		if not ids.has(arc_b) and _r2_point_strictly_inside_triangle_2d(b, triangle_points):
			return {"valid": false, "reason": "required_arc_endpoint_inside_candidate_triangle", "arc_id": arc.get("arc_id", ""), "root_id": arc_b}
	return {"valid": true}

func _r2_owner_for_triangle(centroid: Vector3, context: Dictionary) -> Dictionary:
	var centroid_delta: Vector3 = centroid - context.projection_origin
	var projected_centroid: Vector2 = Vector2(centroid_delta.dot(context.projection_u), centroid_delta.dot(context.projection_v))
	var candidates: Array[Dictionary] = []
	for source_triangle in context.residual_triangles:
		var ids: Array = source_triangle.get("root_ids", [])
		if ids.size() != 3:
			continue
		if not context.projected_positions.has(String(ids[0])) or not context.projected_positions.has(String(ids[1])) or not context.projected_positions.has(String(ids[2])):
			continue
		var a: Vector2 = context.projected_positions[String(ids[0])]
		var b: Vector2 = context.projected_positions[String(ids[1])]
		var c: Vector2 = context.projected_positions[String(ids[2])]
		var bary: Dictionary = _r2_barycentric_2d(projected_centroid, a, b, c)
		if not bool(bary.get("valid", false)):
			continue
		var source_points: Array = source_triangle.get("points", [])
		var source_centroid: Vector3 = (source_points[0] + source_points[1] + source_points[2]) / 3.0
		candidates.append({"triangle_id": String(source_triangle.get("triangle_id", "")), "polygon_id": String(source_triangle.get("polygon_id", "")), "source_polygon_ids": source_triangle.get("source_polygon_ids", [source_triangle.get("polygon_id", "")]).duplicate(), "distance_squared": source_centroid.distance_squared_to(centroid), "barycentric": bary.weights})
	if candidates.is_empty():
		return {"valid": false, "reason": "candidate_centroid_has_no_residual_owner", "projected_centroid": projected_centroid}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.distance_squared) != float(b.distance_squared):
			return float(a.distance_squared) < float(b.distance_squared)
		return String(a.triangle_id) < String(b.triangle_id)
	)
	var selected: Dictionary = candidates[0]
	return {"valid": true, "polygon_id": String(selected.get("polygon_id", "")), "source_polygon_ids": selected.get("source_polygon_ids", []), "source_triangle_id": String(selected.get("triangle_id", "")), "candidate_source_triangle_ids": candidates.map(func(row: Dictionary) -> String: return String(row.get("triangle_id", ""))), "owner_rule": "projected_centroid_in_original_residual_faces_then_nearest_3d_centroid_then_triangle_id"}

func _r2_record_candidate_edges(ids: Array[String], candidate_id: String, context: Dictionary) -> void:
	for index in range(3):
		var a: String = ids[index]
		var b: String = ids[(index + 1) % 3]
		var key: String = _edge_key(a, b)
		if not context.candidate_edges.has(key):
			var vertex_ids: Array[String] = [a, b]
			vertex_ids.sort()
			context.candidate_edges[key] = {"edge_key": key, "vertex_ids": vertex_ids, "candidate_ids": []}
		context.candidate_edges[key].candidate_ids.append(candidate_id)

func _r2_reference_normal(point: Vector3, context: Dictionary) -> Vector3:
	var closest: Dictionary = {}
	var closest_distance: float = INF
	for triangle in context.residual_triangles:
		var points: Array = triangle.get("points", [])
		if points.size() != 3:
			continue
		var centroid: Vector3 = (points[0] + points[1] + points[2]) / 3.0
		var distance_squared: float = centroid.distance_squared_to(point)
		var triangle_id: String = String(triangle.get("triangle_id", ""))
		if distance_squared < closest_distance or (is_equal_approx(distance_squared, closest_distance) and triangle_id < String(closest.get("triangle_id", "~"))):
			closest_distance = distance_squared
			closest = triangle
	var normal: Variant = closest.get("normal", context.reference_normal)
	if normal is not Vector3 or normal.length_squared() <= 1e-20:
		return context.reference_normal
	return normal.normalized()

func _r2_branch_insert_support(triangles: Array[Dictionary], edge_state: Dictionary, selected_support_ids: Array[String], context: Dictionary) -> void:
	var unused_supports: Array = context.support_by_id.keys()
	unused_supports.sort()
	for support_id_value in unused_supports:
		if not bool(context.search_complete):
			return
		var support_id: String = String(support_id_value)
		if selected_support_ids.has(support_id):
			continue
		var point: Vector2 = context.projected_positions[support_id]
		for parent_index in range(triangles.size()):
			if not bool(context.search_complete):
				return
			var parent: Dictionary = triangles[parent_index]
			var parent_ids: Array = parent.get("root_ids", [])
			var parent_points: Array = parent.get("points", [])
			if parent_ids.size() != 3 or parent_points.size() != 3:
				continue
			var p2: Array[Vector2] = [context.projected_positions[String(parent_ids[0])], context.projected_positions[String(parent_ids[1])], context.projected_positions[String(parent_ids[2])]]
			var bary: Dictionary = _r2_barycentric_2d(point, p2[0], p2[1], p2[2])
			if not bool(bary.get("valid", false)):
				continue
			var weights: Array = bary.get("weights", [])
			if weights.size() != 3 or float(weights[0]) <= CXR_BARYCENTRIC_EPSILON or float(weights[1]) <= CXR_BARYCENTRIC_EPSILON or float(weights[2]) <= CXR_BARYCENTRIC_EPSILON:
				continue
			var remaining: Array[Dictionary] = triangles.duplicate()
			remaining.remove_at(parent_index)
			var parent_normal: Vector3 = Vector3(parent.get("normal", Vector3.ZERO))
			if parent_normal.length_squared() <= 1e-20:
				_r2_count(context.prunes, "support_insertion_parent_normal_invalid")
				continue
			var children: Array[Dictionary] = []
			var child_specs: Array = [[0, 1], [1, 2], [2, 0]]
			var insertion_valid: bool = true
			var insertion_reason: String = ""
			for child_spec in child_specs:
				var a_index: int = int(child_spec[0])
				var b_index: int = int(child_spec[1])
				var child_ids: Array[String] = [String(parent_ids[a_index]), String(parent_ids[b_index]), support_id]
				var child_result: Dictionary = _r2_get_candidate_triangle(child_ids, context)
				if not bool(child_result.get("valid", false)):
					insertion_valid = false
					insertion_reason = String(child_result.get("reason", "support_insertion_child_invalid"))
					if bool(child_result.get("limit", false)):
						context.search_complete = false
						context.search_exhaustive = false
						context.limit_reason = insertion_reason
						_append_limit(context.limits_hit, insertion_reason)
						return
					break
				var child: Dictionary = child_result.triangle
				if Vector3(child.normal).dot(parent_normal) <= 0.0:
					insertion_valid = false
					insertion_reason = "support_insertion_winding_mismatch"
					break
				children.append(child)
			if not insertion_valid or children.size() != 3:
				_r2_count(context.prunes, insertion_reason if not insertion_reason.is_empty() else "support_insertion_children_incomplete")
				continue
			var child_edge_state: Dictionary = _r2_build_edge_state(remaining)
			for child in children:
				if not _r2_candidate_can_extend(child, child_edge_state, context):
					insertion_valid = false
					insertion_reason = "support_insertion_edge_conflict"
					break
				_r2_add_triangle_to_edge_state(child, child_edge_state)
			if not insertion_valid:
				_r2_count(context.prunes, insertion_reason)
				continue
			var next_triangles: Array[Dictionary] = remaining.duplicate()
			next_triangles.append_array(children)
			var next_supports: Array[String] = _r2_used_support_ids(next_triangles, context)
			if next_supports.size() != selected_support_ids.size() + 1 or next_supports.size() > int(context.target_support_count):
				_r2_count(context.prunes, "support_insertion_support_count_invalid")
				continue
			if _r2_duplicate_support_positions(next_supports, context):
				_r2_count(context.prunes, "duplicate_support_position")
				continue
			_r2_search_recursive(next_triangles, context)

func _r2_barycentric_2d(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Dictionary:
	var denominator: float = _r2_orientation(a, b, c)
	if not is_finite(denominator) or absf(denominator) <= 1e-20:
		return {"valid": false, "reason": "triangle_projection_degenerate"}
	var w0: float = _r2_orientation(point, b, c) / denominator
	var w1: float = _r2_orientation(a, point, c) / denominator
	var w2: float = 1.0 - w0 - w1
	var inside: bool = w0 >= -CXR_BARYCENTRIC_EPSILON and w1 >= -CXR_BARYCENTRIC_EPSILON and w2 >= -CXR_BARYCENTRIC_EPSILON
	return {"valid": inside, "weights": [w0, w1, w2], "reason": "" if inside else "point_outside_triangle"}

func _r2_add_triangle_to_edge_state(triangle: Dictionary, edge_state: Dictionary) -> void:
	var ids: Array = triangle.get("root_ids", [])
	for edge_index in range(3):
		var a: String = String(ids[edge_index])
		var b: String = String(ids[(edge_index + 1) % 3])
		var key: String = _edge_key(a, b)
		if not edge_state.has(key):
			edge_state[key] = []
		edge_state[key].append({"a": a, "b": b, "triangle_id": String(triangle.get("triangle_id", ""))})

func _r2_validate_solution(triangles: Array[Dictionary], selected_support_ids: Array[String], edge_state: Dictionary, context: Dictionary) -> Dictionary:
	if triangles.is_empty():
		return {"valid": false, "reason": "empty_replacement_triangulation"}
	var edge_audit: Array[Dictionary] = []
	var sorted_edge_keys: Array = edge_state.keys()
	sorted_edge_keys.sort()
	for key_value in sorted_edge_keys:
		var key: String = String(key_value)
		var rows: Array = edge_state[key]
		var expected_count: int = 1 if context.boundary_edge_map.has(key) else 2
		if rows.size() != expected_count:
			return {"valid": false, "reason": "final_edge_incidence_invalid", "edge_key": key, "expected": expected_count, "observed": rows.size(), "rows": rows}
		if rows.size() == 2 and String(rows[0].a) == String(rows[1].a) and String(rows[0].b) == String(rows[1].b):
			return {"valid": false, "reason": "final_internal_edge_winding_inconsistent", "edge_key": key, "rows": rows}
		if rows.size() == 1:
			var expected: Dictionary = context.boundary_edge_map.get(key, {})
			if expected.is_empty() or String(rows[0].a) != String(expected.a) or String(rows[0].b) != String(expected.b):
				return {"valid": false, "reason": "final_boundary_edge_winding_mismatch", "edge_key": key, "expected": expected, "observed": rows[0]}
		edge_audit.append({"edge_key": key, "incidence": rows.size(), "expected": expected_count, "rows": rows.duplicate(true)})
	for key_value in context.boundary_edge_map.keys():
		if not edge_state.has(String(key_value)):
			return {"valid": false, "reason": "final_boundary_edge_missing", "edge_key": String(key_value)}
	var root_identity_rows: Array[Dictionary] = []
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		var points: Array = triangle.get("points", [])
		if ids.size() != 3 or points.size() != 3:
			return {"valid": false, "reason": "candidate_triangle_identity_arity_invalid", "triangle_id": triangle.get("triangle_id", "")}
		var polygon_id: String = String(triangle.get("polygon_id", ""))
		if not context.owner_polygon_ids.has(polygon_id):
			return {"valid": false, "reason": "candidate_triangle_owner_not_in_frozen_source", "triangle_id": triangle.get("triangle_id", ""), "polygon_id": polygon_id}
		for source_polygon_id_value in triangle.get("source_polygon_ids", []):
			if not context.source_polygon_ids.has(String(source_polygon_id_value)):
				return {"valid": false, "reason": "candidate_triangle_source_polygon_not_in_frozen_source", "triangle_id": triangle.get("triangle_id", ""), "source_polygon_id": source_polygon_id_value}
		for index in range(3):
			var root_id: String = String(ids[index])
			if not context.vertex_positions.has(root_id):
				return {"valid": false, "reason": "candidate_triangle_root_identity_missing", "triangle_id": triangle.get("triangle_id", ""), "root_id": root_id}
			var expected_point: Vector3 = context.vertex_positions[root_id]
			var observed_point: Vector3 = points[index]
			if var_to_bytes(expected_point) != var_to_bytes(observed_point):
				return {"valid": false, "reason": "candidate_triangle_root_coordinate_changed", "triangle_id": triangle.get("triangle_id", ""), "root_id": root_id, "expected": expected_point, "observed": observed_point}
			root_identity_rows.append({"triangle_id": triangle.get("triangle_id", ""), "root_id": root_id, "exact_position_bytes_sha256": Core.sha256(var_to_bytes(expected_point))})
	var boundary_after: Dictionary = _boundary_state(triangles)
	if not bool(boundary_after.get("valid", false)) or String(boundary_after.get("signature", "")) != String(context.boundary_signature):
		return {"valid": false, "reason": "cavity_boundary_changed", "expected_signature": context.boundary_signature, "observed": boundary_after}
	var expected_triangle_count: int = context.boundary_cycle.size() + 2 * (selected_support_ids.size() + context.required_topology_root_ids.size()) - 2
	if triangles.size() != expected_triangle_count:
		return {"valid": false, "reason": "disk_euler_triangle_count_mismatch", "expected": expected_triangle_count, "observed": triangles.size()}
	var vertex_audit: Dictionary = _r2_validate_vertex_links(triangles, context, selected_support_ids)
	if not bool(vertex_audit.get("valid", false)):
		return {"valid": false, "reason": String(vertex_audit.get("reason", "vertex_link_invalid")), "vertex_audit": vertex_audit}
	var connected_audit: Dictionary = _r2_validate_triangle_connectivity(triangles)
	if not bool(connected_audit.get("valid", false)):
		return {"valid": false, "reason": "candidate_triangles_disconnected", "connectivity": connected_audit}
	var residual_set: Dictionary = context.residual_id_set
	var replacement: Array[Dictionary] = []
	for triangle in context.level_patch:
		if not residual_set.has(String(triangle.get("triangle_id", ""))):
			replacement.append(triangle)
	replacement.append_array(triangles)
	var level_boundary_before: Dictionary = _boundary_state(context.level_patch)
	if String(context.get("phase", "")) in ["r3", "r4"]:
		level_boundary_before = context.get("r3_cavity_boundary", {})
	var level_boundary_after: Dictionary = _boundary_state(replacement)
	if not bool(level_boundary_before.get("valid", false)) or not bool(level_boundary_after.get("valid", false)) or String(level_boundary_before.get("signature", "")) != String(level_boundary_after.get("signature", "")):
		return {"valid": false, "reason": "level_patch_boundary_changed", "before": level_boundary_before, "after": level_boundary_after}
	var final_mesh: Array[Dictionary] = []
	var patch_id_set: Dictionary = {}
	for patch_id_value in context.patch_ids:
		patch_id_set[String(patch_id_value)] = true
	for triangle in context.all_triangles:
		if not patch_id_set.has(String(triangle.get("triangle_id", ""))):
			final_mesh.append(triangle)
	final_mesh.append_array(replacement)
	if not _r2_intersections_clear(triangles, final_mesh):
		return {"valid": false, "reason": "candidate_self_intersection"}
	if _new_t_junction_count(triangles, final_mesh) > 0:
		return {"valid": false, "reason": "candidate_t_junction"}
	var arcs: Array = context.global_arc_map
	var flips: Array = context.global_applied_flips
	var arc_audit: Dictionary = _validate_required_arcs(final_mesh, arcs, flips)
	if not bool(arc_audit.get("valid", false)):
		return {"valid": false, "reason": "required_topology_arc_mismatch", "arc_audit": arc_audit}
	var surface_diagnostics: Dictionary = {"status": "NOT_RUN_TEST_FIXTURE", "diagnostic_only": true}
	if bool(context.solution_scoring_enabled):
		surface_diagnostics = _surface_diagnostics(triangles, _cxr_active_snapshot)
		if int(surface_diagnostics.get("sample_count", 0)) != triangles.size():
			return {"valid": false, "reason": "surface_diagnostics_incomplete", "surface_diagnostics": surface_diagnostics}
	var minimum_cross: float = INF
	for triangle in triangles:
		var cross_squared: float = float(triangle.get("cross_squared", NAN))
		if not is_finite(cross_squared) or cross_squared <= CXR_CUTOFF_SQUARED:
			return {"valid": false, "reason": "candidate_triangle_cutoff_rejected", "triangle_id": triangle.get("triangle_id", "UNKNOWN_NOT_CAPTURED"), "cross_squared": cross_squared}
		minimum_cross = minf(minimum_cross, cross_squared)
	var triangle_key_parts: Array[String] = []
	for triangle in triangles:
		triangle_key_parts.append(_triplet_key(triangle.get("root_ids", [])))
	triangle_key_parts.sort()
	var stable_key: String = _r2_stable_score_key(selected_support_ids, surface_diagnostics, minimum_cross, triangles.size(), int(context.search_nodes), "|".join(triangle_key_parts))
	return {"valid": true, "selected_supports": _r2_support_rows(selected_support_ids, context), "support_ids": selected_support_ids.duplicate(), "replacement_triangles": triangles.duplicate(true), "final_replacement_triangles": replacement, "minimum_cross_squared": minimum_cross, "surface_diagnostics": surface_diagnostics, "edge_audit": edge_audit, "vertex_audit": vertex_audit, "connectivity": connected_audit, "arc_audit": arc_audit, "root_identity_rows": root_identity_rows, "boundary_after": boundary_after, "level_boundary_after": level_boundary_after, "stable_score_key": stable_key}

func _r2_intersections_clear(patch: Array[Dictionary], all_triangles: Array[Dictionary]) -> bool:
	for a in patch:
		for b in all_triangles:
			if String(a.get("triangle_id", "")) == String(b.get("triangle_id", "")):
				continue
			if not _triangles_intersect(a.get("points", []), b.get("points", [])):
				continue
			if not _r2_intersection_only_shared_simplex(a, b):
				return false
	return true

func _r2_intersection_only_shared_simplex(a: Dictionary, b: Dictionary) -> bool:
	var a_ids: Array = a.get("root_ids", [])
	var b_ids: Array = b.get("root_ids", [])
	var a_points: Array = a.get("points", [])
	var b_points: Array = b.get("points", [])
	if a_ids.size() != 3 or b_ids.size() != 3 or a_points.size() != 3 or b_points.size() != 3:
		return false
	var shared: Array[String] = []
	var a_positions: Dictionary = {}
	var b_positions: Dictionary = {}
	for index in range(3):
		a_positions[String(a_ids[index])] = Vector3(a_points[index])
		b_positions[String(b_ids[index])] = Vector3(b_points[index])
	for id_value in a_ids:
		var id: String = String(id_value)
		if b_positions.has(id):
			if var_to_bytes(a_positions[id]) != var_to_bytes(b_positions[id]):
				return false
			shared.append(id)
	if shared.is_empty() or shared.size() >= 3:
		return false
	if shared.size() == 2:
		return _r2_shared_edge_is_nonoverlapping(a, b, shared)
	var shared_point: Vector3 = Vector3(a_positions[shared[0]])
	var a_normal: Vector3 = (Vector3(a_points[1]) - Vector3(a_points[0])).cross(Vector3(a_points[2]) - Vector3(a_points[0])).normalized()
	var b_normal: Vector3 = (Vector3(b_points[1]) - Vector3(b_points[0])).cross(Vector3(b_points[2]) - Vector3(b_points[0])).normalized()
	var coplanar: bool = a_normal.cross(b_normal).length_squared() <= TRIANGLE_EPSILON * TRIANGLE_EPSILON and absf(a_normal.dot(Vector3(b_points[0]) - Vector3(a_points[0]))) <= TRIANGLE_EPSILON
	if coplanar:
		return not _r2_coplanar_overlap_beyond_shared_vertex(a, b, shared[0], a_normal)
	return not _r2_non_coplanar_overlap_beyond_shared_vertex(a, b, shared_point)

func _r2_shared_edge_is_nonoverlapping(a: Dictionary, b: Dictionary, shared_ids: Array[String]) -> bool:
	var a_points: Array = a.get("points", [])
	var b_points: Array = b.get("points", [])
	var a_ids: Array = a.get("root_ids", [])
	var b_ids: Array = b.get("root_ids", [])
	var a_third: Vector3 = Vector3.ZERO
	var b_third: Vector3 = Vector3.ZERO
	for index in range(3):
		if not shared_ids.has(String(a_ids[index])):
			a_third = Vector3(a_points[index])
		if not shared_ids.has(String(b_ids[index])):
			b_third = Vector3(b_points[index])
	var shared_positions: Array[Vector3] = []
	for shared_id in shared_ids:
		for index in range(3):
			if String(a_ids[index]) == shared_id:
				shared_positions.append(Vector3(a_points[index]))
	if shared_positions.size() != 2:
		return false
	var edge: Vector3 = shared_positions[1] - shared_positions[0]
	var normal_a: Vector3 = edge.cross(a_third - shared_positions[0])
	var normal_b: Vector3 = edge.cross(b_third - shared_positions[0])
	if normal_a.length_squared() <= CXR_CUTOFF_SQUARED or normal_b.length_squared() <= CXR_CUTOFF_SQUARED:
		return false
	if normal_a.cross(normal_b).length_squared() <= TRIANGLE_EPSILON * TRIANGLE_EPSILON * normal_a.length_squared() * normal_b.length_squared() and normal_a.dot(normal_b) > 0.0:
		return false
	return true

func _r2_coplanar_overlap_beyond_shared_vertex(a: Dictionary, b: Dictionary, shared_id: String, normal: Vector3) -> bool:
	var a_ids: Array = a.get("root_ids", [])
	var b_ids: Array = b.get("root_ids", [])
	var a_points: Array = a.get("points", [])
	var b_points: Array = b.get("points", [])
	var a2: Array[Vector2] = []
	var b2: Array[Vector2] = []
	for point in a_points:
		a2.append(_r2_project_point(Vector3(point), normal))
	for point in b_points:
		b2.append(_r2_project_point(Vector3(point), normal))
	for a_edge in range(3):
		var a_next: int = (a_edge + 1) % 3
		for b_edge in range(3):
			var b_next: int = (b_edge + 1) % 3
			if _r2_proper_segments_intersect(a2[a_edge], a2[a_next], b2[b_edge], b2[b_next]):
				return true
			if _r2_endpoint_strictly_inside_segment_2d(a2[a_edge], b2[b_edge], b2[b_next]) and String(a_ids[a_edge]) != shared_id:
				return true
			if _r2_endpoint_strictly_inside_segment_2d(a2[a_next], b2[b_edge], b2[b_next]) and String(a_ids[a_next]) != shared_id:
				return true
			if _r2_endpoint_strictly_inside_segment_2d(b2[b_edge], a2[a_edge], a2[a_next]) and String(b_ids[b_edge]) != shared_id:
				return true
			if _r2_endpoint_strictly_inside_segment_2d(b2[b_next], a2[a_edge], a2[a_next]) and String(b_ids[b_next]) != shared_id:
				return true
	for index in range(3):
		if String(a_ids[index]) != shared_id and _r2_point_strictly_inside_triangle_2d(a2[index], b2):
			return true
		if String(b_ids[index]) != shared_id and _r2_point_strictly_inside_triangle_2d(b2[index], a2):
			return true
	return false

func _r2_non_coplanar_overlap_beyond_shared_vertex(a: Dictionary, b: Dictionary, shared_point: Vector3) -> bool:
	return _r2_triangle_edges_hit_other(a, b, shared_point) or _r2_triangle_edges_hit_other(b, a, shared_point)

func _r2_triangle_edges_hit_other(source: Dictionary, target: Dictionary, ignored_point: Vector3) -> bool:
	var source_points: Array = source.get("points", [])
	var target_points: Array = target.get("points", [])
	if source_points.size() != 3 or target_points.size() != 3:
		return true
	var target_normal: Vector3 = (Vector3(target_points[1]) - Vector3(target_points[0])).cross(Vector3(target_points[2]) - Vector3(target_points[0])).normalized()
	for edge_index in range(3):
		var p0: Vector3 = Vector3(source_points[edge_index])
		var p1: Vector3 = Vector3(source_points[(edge_index + 1) % 3])
		var d0: float = target_normal.dot(p0 - Vector3(target_points[0]))
		var d1: float = target_normal.dot(p1 - Vector3(target_points[0]))
		if absf(d0) <= TRIANGLE_EPSILON and _r2_point_in_triangle_3d(p0, target_points) and p0.distance_to(ignored_point) > TRIANGLE_EPSILON:
			return true
		if absf(d1) <= TRIANGLE_EPSILON and _r2_point_in_triangle_3d(p1, target_points) and p1.distance_to(ignored_point) > TRIANGLE_EPSILON:
			return true
		if d0 * d1 < 0.0:
			var t: float = d0 / (d0 - d1)
			if t > 0.0 and t < 1.0:
				var intersection: Vector3 = p0 + (p1 - p0) * t
				if intersection.distance_to(ignored_point) > TRIANGLE_EPSILON and _r2_point_in_triangle_3d(intersection, target_points):
					return true
	return false

func _r2_project_point(point: Vector3, normal: Vector3) -> Vector2:
	var abs_normal: Vector3 = normal.abs()
	if abs_normal.x >= abs_normal.y and abs_normal.x >= abs_normal.z:
		return Vector2(point.y, point.z)
	if abs_normal.y >= abs_normal.z:
		return Vector2(point.x, point.z)
	return Vector2(point.x, point.y)

func _r2_endpoint_strictly_inside_segment_2d(point: Vector2, a: Vector2, b: Vector2) -> bool:
	var edge: Vector2 = b - a
	var length_squared: float = edge.length_squared()
	if length_squared <= 0.0:
		return false
	var cross_value: float = absf(_r2_orientation(a, b, point))
	if cross_value > TRIANGLE_EPSILON * sqrt(length_squared):
		return false
	var t: float = (point - a).dot(edge) / length_squared
	return t > TRIANGLE_EPSILON and t < 1.0 - TRIANGLE_EPSILON

func _r2_point_strictly_inside_triangle_2d(point: Vector2, triangle: Array[Vector2]) -> bool:
	if triangle.size() != 3:
		return false
	var orientations: Array[float] = [_r2_orientation(triangle[0], triangle[1], point), _r2_orientation(triangle[1], triangle[2], point), _r2_orientation(triangle[2], triangle[0], point)]
	var all_positive: bool = true
	var all_negative: bool = true
	for value in orientations:
		all_positive = all_positive and value > 0.0
		all_negative = all_negative and value < 0.0
	return all_positive or all_negative

func _r2_point_in_triangle_3d(point: Vector3, triangle_points: Array) -> bool:
	if triangle_points.size() != 3:
		return false
	var a: Vector3 = Vector3(triangle_points[0])
	var b: Vector3 = Vector3(triangle_points[1])
	var c: Vector3 = Vector3(triangle_points[2])
	var normal: Vector3 = (b - a).cross(c - a)
	var normal_length: float = normal.length()
	if normal_length <= 0.0 or absf(normal.normalized().dot(point - a)) > TRIANGLE_EPSILON:
		return false
	var v0: Vector3 = b - a
	var v1: Vector3 = c - a
	var v2: Vector3 = point - a
	var d00: float = v0.dot(v0)
	var d01: float = v0.dot(v1)
	var d11: float = v1.dot(v1)
	var d20: float = v2.dot(v0)
	var d21: float = v2.dot(v1)
	var denominator: float = d00 * d11 - d01 * d01
	if denominator == 0.0:
		return false
	var v: float = (d11 * d20 - d01 * d21) / denominator
	var w: float = (d00 * d21 - d01 * d20) / denominator
	var u: float = 1.0 - v - w
	return u >= 0.0 and v >= 0.0 and w >= 0.0

func _r2_validate_vertex_links(triangles: Array[Dictionary], context: Dictionary, selected_support_ids: Array[String]) -> Dictionary:
	var links: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3:
			return {"valid": false, "reason": "triangle_arity_invalid", "triangle_id": triangle.get("triangle_id", "")}
		for vertex_index in range(3):
			var vertex_id: String = String(ids[vertex_index])
			var a: String = String(ids[(vertex_index + 1) % 3])
			var b: String = String(ids[(vertex_index + 2) % 3])
			if not links.has(vertex_id):
				links[vertex_id] = {}
			if not links[vertex_id].has(a):
				links[vertex_id][a] = {}
			if not links[vertex_id].has(b):
				links[vertex_id][b] = {}
			links[vertex_id][a][b] = true
			links[vertex_id][b][a] = true
	var boundary_set: Dictionary = {}
	for id in context.boundary_cycle:
		boundary_set[String(id)] = true
	var expected_vertices: Dictionary = boundary_set.duplicate()
	for id_value in context.required_topology_root_ids.keys():
		expected_vertices[String(id_value)] = true
	for id in selected_support_ids:
		expected_vertices[id] = true
	if links.size() != expected_vertices.size():
		return {"valid": false, "reason": "unused_or_missing_vertex", "expected": expected_vertices.keys(), "observed": links.keys()}
	var rows: Array[Dictionary] = []
	var sorted_vertex_ids: Array = expected_vertices.keys()
	sorted_vertex_ids.sort()
	for vertex_value in sorted_vertex_ids:
		var vertex_id: String = String(vertex_value)
		if not links.has(vertex_id):
			return {"valid": false, "reason": "isolated_vertex", "vertex_id": vertex_id}
		var neighbors: Dictionary = links[vertex_id]
		if neighbors.is_empty():
			return {"valid": false, "reason": "empty_vertex_link", "vertex_id": vertex_id}
		var degree_one: int = 0
		var neighbor_ids: Array = neighbors.keys()
		neighbor_ids.sort()
		for neighbor_value in neighbor_ids:
			var neighbor_id: String = String(neighbor_value)
			var adjacent: Dictionary = neighbors[neighbor_id]
			for adjacent_value in adjacent.keys():
				var adjacent_id: String = String(adjacent_value)
				if not neighbors.has(adjacent_id) or not neighbors[adjacent_id].has(neighbor_id):
					return {"valid": false, "reason": "asymmetric_vertex_link", "vertex_id": vertex_id, "neighbor_id": neighbor_id, "adjacent_id": adjacent_id}
			var degree: int = adjacent.size()
			if degree == 1:
				degree_one += 1
			elif degree != 2:
				return {"valid": false, "reason": "vertex_link_degree_invalid", "vertex_id": vertex_id, "link_node": neighbor_id, "degree": degree}
		if boundary_set.has(vertex_id):
			if degree_one != 2:
				return {"valid": false, "reason": "boundary_vertex_link_not_path", "vertex_id": vertex_id, "degree_one": degree_one}
		else:
			if degree_one != 0:
				return {"valid": false, "reason": "interior_vertex_link_not_cycle", "vertex_id": vertex_id, "degree_one": degree_one}
		var reached: Dictionary = {}
		var queue: Array = []
		if not neighbors.is_empty():
			queue.append(String(neighbor_ids[0]))
		while not queue.is_empty():
			var current: String = String(queue.pop_front())
			if reached.has(current):
				continue
			reached[current] = true
			var adjacent_ids: Array = neighbors.get(current, {}).keys()
			adjacent_ids.sort()
			for next_value in adjacent_ids:
				if not reached.has(String(next_value)):
					queue.append(String(next_value))
		if reached.size() != neighbors.size():
			return {"valid": false, "reason": "vertex_link_disconnected", "vertex_id": vertex_id, "reached": reached.size(), "expected": neighbors.size()}
		rows.append({"vertex_id": vertex_id, "boundary": boundary_set.has(vertex_id), "link_degree": neighbors.size(), "degree_one_link_vertices": degree_one, "connected": true})
	return {"valid": true, "vertices": rows}

func _r2_validate_triangle_connectivity(triangles: Array[Dictionary]) -> Dictionary:
	if triangles.is_empty():
		return {"valid": false, "reason": "empty_triangle_set"}
	var edge_to_triangles: Dictionary = {}
	for triangle_index in range(triangles.size()):
		var ids: Array = triangles[triangle_index].get("root_ids", [])
		for edge_index in range(3):
			var key: String = _edge_key(String(ids[edge_index]), String(ids[(edge_index + 1) % 3]))
			if not edge_to_triangles.has(key):
				edge_to_triangles[key] = []
			edge_to_triangles[key].append(triangle_index)
	var visited: Dictionary = {0: true}
	var queue: Array = [0]
	while not queue.is_empty():
		var current: int = int(queue.pop_front())
		var ids: Array = triangles[current].get("root_ids", [])
		for edge_index in range(3):
			var key: String = _edge_key(String(ids[edge_index]), String(ids[(edge_index + 1) % 3]))
			for neighbor_value in edge_to_triangles[key]:
				var neighbor: int = int(neighbor_value)
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
	return {"valid": visited.size() == triangles.size(), "triangle_count": triangles.size(), "reached": visited.size(), "component_count": 1 if visited.size() == triangles.size() else "GREATER_THAN_ONE"}

func _r2_support_rows(ids: Array[String], context: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in ids:
		rows.append(context.support_by_id[id].duplicate(true))
	return rows

func _r2_stable_score_key(support_ids: Array[String], surface: Dictionary, minimum_cross: float, triangle_count: int, search_nodes: int, stable_geometry_key: String) -> String:
	var surface_text: String = "UNKNOWN_NOT_CAPTURED"
	if typeof(surface.get("max_abs_canonical_sdf_at_triangle_centroid", null)) == TYPE_FLOAT or typeof(surface.get("max_abs_canonical_sdf_at_triangle_centroid", null)) == TYPE_INT:
		var surface_max: float = float(surface.max_abs_canonical_sdf_at_triangle_centroid)
		if is_finite(surface_max):
			surface_text = "%030.12f" % surface_max
	return "%02d|%s|%030.12f|%04d|%08d|%s" % [support_ids.size(), surface_text, -minimum_cross, triangle_count, search_nodes, stable_geometry_key]

func _r2_solution_less(a: Dictionary, b: Dictionary) -> bool:
	var a_supports: Array = a.get("support_ids", [])
	var b_supports: Array = b.get("support_ids", [])
	if a_supports.size() != b_supports.size():
		return a_supports.size() < b_supports.size()
	var a_surface_data: Variant = a.get("surface_diagnostics", {})
	var b_surface_data: Variant = b.get("surface_diagnostics", {})
	var a_surface: float = float(a_surface_data.get("max_abs_canonical_sdf_at_triangle_centroid", INF)) if a_surface_data is Dictionary else INF
	var b_surface: float = float(b_surface_data.get("max_abs_canonical_sdf_at_triangle_centroid", INF)) if b_surface_data is Dictionary else INF
	if not is_equal_approx(a_surface, b_surface):
		return a_surface < b_surface
	var a_cross: float = float(a.get("minimum_cross_squared", 0.0))
	var b_cross: float = float(b.get("minimum_cross_squared", 0.0))
	if not is_equal_approx(a_cross, b_cross):
		return a_cross > b_cross
	var a_triangles: int = int(a.get("triangle_count", 0))
	var b_triangles: int = int(b.get("triangle_count", 0))
	if a_triangles != b_triangles:
		return a_triangles < b_triangles
	var a_cost: int = int(a.get("search_nodes_at_solution", 0))
	var b_cost: int = int(b.get("search_nodes_at_solution", 0))
	if a_cost != b_cost:
		return a_cost < b_cost
	return String(a.get("stable_geometry_key", "")) < String(b.get("stable_geometry_key", ""))

func _r2_record_solution(solution: Dictionary, context: Dictionary) -> void:
	var row: Dictionary = solution.duplicate(true)
	row["triangle_count"] = solution.get("replacement_triangles", []).size()
	row["search_nodes_at_solution"] = int(context.search_nodes)
	var stable_parts: Array[String] = []
	for triangle in solution.get("replacement_triangles", []):
		stable_parts.append(_triplet_key(triangle.get("root_ids", [])))
	stable_parts.sort()
	row["stable_geometry_key"] = "|".join(stable_parts)
	row["stable_score_key"] = _r2_stable_score_key(solution.get("support_ids", []), solution.get("surface_diagnostics", {}), float(solution.get("minimum_cross_squared", 0.0)), int(row.triangle_count), int(row.search_nodes_at_solution), String(row.stable_geometry_key))
	context.solution_count = int(context.solution_count) + 1
	if context.best_solution.is_empty() or _r2_solution_less(row, context.best_solution):
		context.best_solution = row
	var retained: Array = context.retained_solutions
	retained.append(row)
	retained.sort_custom(Callable(self, "_r2_solution_less"))
	if retained.size() > CXR_MAX_RETAINED_SOLUTIONS:
		retained.resize(CXR_MAX_RETAINED_SOLUTIONS)
	context.retained_solutions = retained

func _append_limit(limits: Array, reason: String) -> void:
	if reason.is_empty() or limits.has(reason):
		return
	limits.append(reason)

func _new_unrun_cxr_level(level: int, status: String, reason: String) -> Dictionary:
	return {"level": level, "status": status, "patch_triangle_ids": status, "source_triangle_count": status, "boundary_before": status, "boundary_signature": status, "candidate_count_by_residual": status, "candidate_unique_count_by_residual": status, "candidate_pool_retained_count_by_residual": status, "candidate_fan_status_by_residual": status, "candidate_attempt_count": status, "candidate_attempt_ids": status, "candidate_triangle_count": status, "candidate_generation_usec": status, "candidate_generation_status": status, "search_nodes": status, "branches": status, "solutions": status, "retained_solutions": status, "search_status": status, "terminal_reason": reason}

func _cxr_time_limit_reason_at(now_usec: int) -> String:
	if _cxr_search_started_usec > 0 and now_usec - _cxr_search_started_usec >= CXR_MAX_SEARCH_USEC_TOTAL:
		return "MAX_SEARCH_USEC_TOTAL"
	if _cxr_cavity_started_usec > 0 and now_usec - _cxr_cavity_started_usec >= CXR_MAX_SEARCH_USEC_PER_CAVITY:
		return "MAX_SEARCH_USEC_PER_CAVITY"
	return ""

func solve_r2_fixture_for_test(boundary_triangles: Array[Dictionary], support_candidates: Array[Dictionary], target_support_count: int = -1, required_arcs: Array = []) -> Dictionary:
	_cxr_active_snapshot = {}
	var prior_roots: Dictionary = _root_positions.duplicate(true)
	var roots: Dictionary = {}
	for triangle in boundary_triangles:
		var ids: Array = triangle.get("root_ids", [])
		var points: Array = triangle.get("points", [])
		if ids.size() != 3 or points.size() != 3:
			_root_positions = prior_roots
			return {"valid": false, "search_complete": false, "reason": "fixture_triangle_arity_invalid"}
		for index in range(3):
			var id: String = String(ids[index])
			var point: Vector3 = points[index]
			if roots.has(id) and Vector3(roots[id]).distance_squared_to(point) > 0.0:
				_root_positions = prior_roots
				return {"valid": false, "search_complete": false, "reason": "fixture_root_position_conflict", "root_id": id}
			roots[id] = point
	_root_positions = roots
	var boundary: Dictionary = _boundary_state(boundary_triangles)
	if not bool(boundary.get("valid", false)):
		_root_positions = prior_roots
		return {"valid": false, "search_complete": false, "reason": "fixture_boundary_invalid", "boundary": boundary}
	var fixture_supports: Array[Dictionary] = []
	for support_value in support_candidates:
		var support: Dictionary = support_value.duplicate(true)
		if not support.has("accepted"):
			support["accepted"] = true
		if not support.has("frozen_field_interpolated_residual"):
			support["frozen_field_interpolated_residual"] = 0.0
		if not support.has("binary32_position_identity"):
			support["binary32_position_identity"] = var_to_bytes(support.get("world_position", Vector3.ZERO)).hex_encode()
		fixture_supports.append(support)
	var ids: Array = []
	for triangle in boundary_triangles:
		ids.append(String(triangle.get("triangle_id", "")))
	var context_result: Dictionary = _r2_make_search_context(boundary_triangles, ids, boundary_triangles, fixture_supports, boundary, boundary_triangles, {"arc_map": required_arcs, "applied_flips": []}, 0)
	if not bool(context_result.get("valid", false)):
		_root_positions = prior_roots
		return {"valid": false, "search_complete": false, "reason": String(context_result.get("reason", "fixture_context_invalid"))}
	_cxr_active_phase = "r2"
	_cxr_active_snapshot = {}
	_cxr_search_started_usec = Time.get_ticks_usec()
	_cxr_cavity_started_usec = _cxr_search_started_usec
	_cxr_search_nodes_total = 0
	_cxr_search_nodes_cavity = 0
	_cxr_candidate_triangles_total = 0
	_cxr_candidate_triangles_cavity = 0
	var context: Dictionary = context_result.context
	var result: Dictionary
	if target_support_count >= 0:
		_r2_search_fixed_support_count(context, mini(target_support_count, CXR_MAX_SELECTED_SUPPORTS))
		result = {"valid": not context.best_solution.is_empty(), "search_complete": bool(context.search_complete), "search_exhaustive": bool(context.search_exhaustive) and bool(context.search_complete), "terminal_reason": String(context.limit_reason) if not String(context.limit_reason).is_empty() else "r2_finite_triangulation_domain_exhausted", "best_solution": context.best_solution, "solution_count": int(context.solution_count), "retained_solutions": context.retained_solutions, "search_nodes": _cxr_search_nodes_total, "candidate_triangle_count": _cxr_candidate_triangles_total}
	else:
		result = _r2_search_level(context)
	result["candidate_triangle_rows"] = context.candidate_triangle_rows
	var candidate_edge_keys: Array = context.candidate_edges.keys()
	candidate_edge_keys.sort()
	var candidate_edge_rows: Array[Dictionary] = []
	for edge_key_value in candidate_edge_keys:
		candidate_edge_rows.append(context.candidate_edges[edge_key_value])
	result["candidate_edge_rows"] = candidate_edge_rows
	result["prune_counts"] = context.prunes
	result["solution_rejections"] = context.solution_rejections
	result["boundary_signature"] = boundary.get("signature", "")
	result["phase"] = "r2"
	_root_positions = prior_roots
	return result

func _finish_cxr_cavity_search(cavity_report: Dictionary, best_solution: Dictionary, complete: bool, exhaustive: bool, terminal_reason: String, search_started: bool = true) -> Dictionary:
	cavity_report["search_complete"] = complete
	cavity_report["search_exhaustive"] = exhaustive
	cavity_report["terminal_reason"] = terminal_reason
	cavity_report["search_started"] = search_started
	if best_solution.is_empty():
		return {"valid": false, "search_started": search_started, "search_complete": complete, "search_exhaustive": exhaustive, "terminal_reason": terminal_reason, "cavity_report": cavity_report}
	var selected_solution: Dictionary = best_solution.get("solution", {})
	cavity_report["selected_supports"] = selected_solution.get("selected_supports", [])
	cavity_report["selected_solution"] = selected_solution.duplicate(true)
	cavity_report["selected_level"] = int(best_solution.get("level", -1))
	cavity_report["terminal_reason"] = terminal_reason
	return {"valid": true, "search_started": search_started, "search_complete": complete, "search_exhaustive": exhaustive, "terminal_reason": terminal_reason, "cavity_report": cavity_report, "patch_triangle_ids": best_solution.get("patch_ids", []), "patch_record": best_solution.get("patch_record", {}), "replacement_triangles": best_solution.get("replacement_triangles", []), "selected_supports": selected_solution.get("selected_supports", [])}

func _new_cxr_level_report(level: int, patch_ids: Array, source_triangle_count: int) -> Dictionary:
	return {"level": level, "patch_triangle_ids": patch_ids.duplicate(), "source_triangle_count": source_triangle_count, "boundary_before": "UNKNOWN_NOT_CAPTURED", "boundary_signature": "UNKNOWN_NOT_CAPTURED", "candidate_count_by_residual": {}, "candidate_unique_count_by_residual": {}, "candidate_pool_retained_count_by_residual": {}, "candidate_fan_status_by_residual": {}, "candidate_attempt_count": 0, "candidate_attempt_ids": [], "candidate_triangle_count": 0, "candidate_generation_usec": "NOT_RUN", "candidate_generation_status": "NOT_RUN", "search_nodes": 0, "branches": 0, "solutions": 0, "retained_solutions": [], "search_status": "NOT_RUN", "terminal_reason": "UNKNOWN_NOT_CAPTURED"}

func _mark_unrun_cxr_residuals(level_report: Dictionary, residuals: Array[Dictionary], first_index: int, status: String) -> void:
	for residual_index in range(first_index, residuals.size()):
		var residual_id: String = String(residuals[residual_index].get("triangle_id", "UNKNOWN_NOT_CAPTURED"))
		level_report.candidate_count_by_residual[residual_id] = status
		level_report.candidate_unique_count_by_residual[residual_id] = status
		level_report.candidate_pool_retained_count_by_residual[residual_id] = status
		level_report.candidate_fan_status_by_residual[residual_id] = status

func _preserve_incomplete_candidate_generation(candidate_data: Dictionary, evidence_check: Dictionary, cavity_report: Dictionary, level_report: Dictionary, residuals: Array[Dictionary], current_residual: Dictionary, residual_id: String, level: int) -> void:
	var attempts_value: Variant = candidate_data.get("attempts", null)
	if typeof(attempts_value) == TYPE_ARRAY:
		var attempts: Array = attempts_value
		cavity_report.candidate_attempts.append_array(attempts)
		level_report.candidate_attempt_count = int(level_report.get("candidate_attempt_count", 0)) + attempts.size()
		for attempt_value in attempts:
			level_report.candidate_attempt_ids.append(String(attempt_value.get("attempt_id", attempt_value.get("candidate_id", "UNKNOWN_NOT_CAPTURED"))) if typeof(attempt_value) == TYPE_DICTIONARY else "UNKNOWN_NOT_CAPTURED")
	else:
		level_report["candidate_attempt_count"] = "UNKNOWN_NOT_CAPTURED"
		level_report["candidate_attempt_ids"] = "UNKNOWN_NOT_CAPTURED"
	var generation_time: Variant = candidate_data.get("candidate_generation_usec", null)
	var accumulated_time: Variant = level_report.get("candidate_generation_usec", null)
	if typeof(generation_time) == TYPE_INT and int(generation_time) >= 0 and typeof(accumulated_time) == TYPE_INT:
		level_report["candidate_generation_usec"] = int(accumulated_time) + int(generation_time)
	else:
		level_report["candidate_generation_usec"] = "UNKNOWN_NOT_CAPTURED"
	var candidate_pool_value: Variant = candidate_data.get("candidate_pool", null)
	if typeof(candidate_pool_value) == TYPE_ARRAY:
		var candidate_pool: Array = candidate_pool_value
		cavity_report.support_candidates.append_array(candidate_pool)
		cavity_report.support_candidates_retained.append_array(candidate_pool)
		level_report.candidate_pool_retained_count_by_residual[residual_id] = candidate_pool.size()
	else:
		level_report.candidate_pool_retained_count_by_residual[residual_id] = "UNKNOWN_NOT_CAPTURED"
	var unique_count: Variant = candidate_data.get("candidate_unique_count", null)
	level_report.candidate_unique_count_by_residual[residual_id] = unique_count if typeof(unique_count) == TYPE_INT else "UNKNOWN_NOT_CAPTURED"
	var candidates_value: Variant = candidate_data.get("candidates", null)
	level_report.candidate_count_by_residual[residual_id] = candidates_value.size() if typeof(candidates_value) == TYPE_ARRAY else "UNKNOWN_NOT_CAPTURED"
	level_report.candidate_fan_status_by_residual[residual_id] = "NOT_RUN_EVIDENCE_FAILURE"
	level_report["candidate_generation_status"] = "FAILED_EVIDENCE_INCOMPLETE"
	level_report["search_status"] = "NOT_RUN_EVIDENCE_INCOMPLETE"
	level_report["terminal_reason"] = "candidate_generation_evidence_incomplete"
	level_report["evidence_validation"] = evidence_check
	level_report["candidate_generation_unvalidated"] = candidate_data
	cavity_report.levels.append(level_report)
	cavity_report.terminal_reason = "candidate_generation_evidence_incomplete"
	cavity_report["candidate_generation_evidence_failure"] = evidence_check
	_mark_unrun_cxr_residuals(level_report, residuals, residuals.find(current_residual) + 1, "NOT_RUN_EVIDENCE_FAILURE")
	_append_unrun_cxr_levels(cavity_report, level + 1, "NOT_RUN_EVIDENCE_FAILURE", cavity_report.terminal_reason)

func _validate_candidate_generation_evidence(candidate_data: Dictionary) -> Dictionary:
	var required_keys: Array[String] = ["attempts", "candidate_pool", "candidates", "candidate_attempt_count", "candidate_count", "candidate_unique_count", "candidate_cap_hit", "attempt_cap_hit", "time_cap_reason", "candidate_generation_usec", "source_valid", "source_failure_reason", "source_tetrahedron_count", "invalid_tetrahedron_count", "cell_bounds", "limit_hit", "limits_hit"]
	var missing_keys: Array[String] = []
	for key in required_keys:
		if not candidate_data.has(key):
			missing_keys.append(key)
	if not missing_keys.is_empty():
		return {"valid": false, "reason": "required_candidate_generation_fields_missing", "missing_keys": missing_keys}
	if typeof(candidate_data.attempts) != TYPE_ARRAY or typeof(candidate_data.candidate_pool) != TYPE_ARRAY or typeof(candidate_data.candidates) != TYPE_ARRAY or typeof(candidate_data.limits_hit) != TYPE_ARRAY:
		return {"valid": false, "reason": "candidate_generation_collection_type_invalid", "observed_types": {"attempts": type_string(typeof(candidate_data.attempts)), "candidate_pool": type_string(typeof(candidate_data.candidate_pool)), "candidates": type_string(typeof(candidate_data.candidates)), "limits_hit": type_string(typeof(candidate_data.limits_hit))}}
	if typeof(candidate_data.candidate_attempt_count) != TYPE_INT or int(candidate_data.candidate_attempt_count) != candidate_data.attempts.size():
		return {"valid": false, "reason": "candidate_attempt_count_mismatch", "reported": candidate_data.candidate_attempt_count, "observed_rows": candidate_data.attempts.size()}
	if typeof(candidate_data.candidate_count) != TYPE_INT or int(candidate_data.candidate_count) != candidate_data.candidates.size():
		return {"valid": false, "reason": "candidate_count_mismatch", "reported": candidate_data.candidate_count, "observed_rows": candidate_data.candidates.size()}
	if typeof(candidate_data.candidate_unique_count) != TYPE_INT or int(candidate_data.candidate_unique_count) < candidate_data.candidates.size():
		return {"valid": false, "reason": "candidate_unique_count_invalid", "reported": candidate_data.candidate_unique_count, "retained": candidate_data.candidates.size()}
	if typeof(candidate_data.candidate_cap_hit) != TYPE_BOOL or bool(candidate_data.candidate_cap_hit) != (int(candidate_data.candidate_unique_count) > int(candidate_data.candidate_count)):
		return {"valid": false, "reason": "candidate_cap_evidence_mismatch"}
	if candidate_data.candidate_pool.size() != candidate_data.candidates.size():
		return {"valid": false, "reason": "candidate_pool_retention_mismatch", "pool_rows": candidate_data.candidate_pool.size(), "candidate_rows": candidate_data.candidates.size()}
	if typeof(candidate_data.candidate_generation_usec) != TYPE_INT or int(candidate_data.candidate_generation_usec) < 0:
		return {"valid": false, "reason": "candidate_generation_time_unavailable", "observed": candidate_data.candidate_generation_usec}
	if typeof(candidate_data.source_valid) != TYPE_BOOL or typeof(candidate_data.limit_hit) != TYPE_BOOL:
		return {"valid": false, "reason": "candidate_generation_status_type_invalid"}
	if typeof(candidate_data.attempt_cap_hit) != TYPE_BOOL or typeof(candidate_data.time_cap_reason) != TYPE_STRING or typeof(candidate_data.source_failure_reason) != TYPE_STRING:
		return {"valid": false, "reason": "candidate_generation_limit_or_failure_metadata_invalid"}
	if bool(candidate_data.limit_hit) != (bool(candidate_data.candidate_cap_hit) or bool(candidate_data.attempt_cap_hit) or not String(candidate_data.time_cap_reason).is_empty()):
		return {"valid": false, "reason": "candidate_generation_limit_flags_inconsistent"}
	if typeof(candidate_data.source_tetrahedron_count) != TYPE_INT or typeof(candidate_data.invalid_tetrahedron_count) != TYPE_INT or int(candidate_data.source_tetrahedron_count) < 0 or int(candidate_data.invalid_tetrahedron_count) < 0 or int(candidate_data.invalid_tetrahedron_count) > int(candidate_data.source_tetrahedron_count):
		return {"valid": false, "reason": "candidate_source_tetrahedron_counts_invalid"}
	if typeof(candidate_data.cell_bounds) != TYPE_DICTIONARY and not (typeof(candidate_data.cell_bounds) == TYPE_STRING and not bool(candidate_data.source_valid)):
		return {"valid": false, "reason": "candidate_source_cell_bounds_unavailable"}
	return {"valid": true, "reason": "candidate_generation_evidence_complete"}

func _record_invalid_cxr_boundary_level(cavity_report: Dictionary, level_report: Dictionary, boundary: Dictionary) -> bool:
	level_report["boundary_before"] = boundary.duplicate(true)
	level_report["boundary_signature"] = String(boundary.get("observed_boundary_signature", "UNKNOWN_NOT_CAPTURED"))
	var residual_state: Dictionary = {}
	for residual_id_value in cavity_report.get("residual_triangle_ids", []):
		residual_state[String(residual_id_value)] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["candidate_count_by_residual"] = residual_state.duplicate()
	level_report["candidate_unique_count_by_residual"] = residual_state.duplicate()
	level_report["candidate_pool_retained_count_by_residual"] = residual_state.duplicate()
	level_report["candidate_fan_status_by_residual"] = residual_state.duplicate()
	level_report["candidate_attempt_count"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["candidate_attempt_ids"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["candidate_triangle_count"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["candidate_generation_usec"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["candidate_generation_status"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["search_nodes"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["branches"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["solutions"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["retained_solutions"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["search_status"] = "NOT_RUN_INVALID_BOUNDARY"
	level_report["terminal_reason"] = "patch_boundary_invalid_continue_next_level"
	level_report["boundary_invalid_reason"] = boundary.get("reason", "UNKNOWN_NOT_CAPTURED")
	cavity_report.levels.append(level_report)
	return true

func _append_unrun_cxr_levels(cavity_report: Dictionary, first_level: int, status: String, reason: String) -> void:
	for level in range(first_level, CXR_MAX_CAVITY_LEVEL + 1):
		cavity_report.levels.append({"level": level, "status": status, "patch_triangle_ids": status, "source_triangle_count": status, "boundary_before": status, "boundary_signature": status, "candidate_count_by_residual": status, "candidate_unique_count_by_residual": status, "candidate_pool_retained_count_by_residual": status, "candidate_fan_status_by_residual": status, "candidate_attempt_count": status, "candidate_attempt_ids": status, "candidate_triangle_count": status, "candidate_generation_usec": status, "candidate_generation_status": status, "search_nodes": status, "branches": status, "solutions": status, "retained_solutions": status, "search_status": status, "terminal_reason": reason})

func _not_run_cavity_result(cavity_ids: Array, status: String, reason: String) -> Dictionary:
	var sorted_ids: Array = cavity_ids.duplicate()
	sorted_ids.sort()
	var cavity_id: String = Core.sha256(JSON.stringify(sorted_ids).to_utf8_buffer()).substr(0, 16)
	var cavity_report: Dictionary = {"cavity_id": cavity_id, "residual_triangle_ids": sorted_ids, "levels": [], "candidate_attempts": status, "support_candidates": status, "support_candidates_retained": status, "fan_evaluations": status, "candidate_triangles": status, "retained_solutions": status, "selected_supports": status, "search_nodes": status, "branches": status, "prunes": status, "limits_hit": [reason], "search_complete": false, "search_exhaustive": false, "terminal_reason": reason, "status": status}
	_append_unrun_cxr_levels(cavity_report, 0, status, reason)
	return {"valid": false, "search_started": false, "search_complete": false, "search_exhaustive": false, "terminal_reason": reason, "cavity_report": cavity_report, "status": status}

func _cxr_global_limit_reason() -> String:
	if _cxr_search_started_usec <= 0:
		return ""
	return _cxr_global_limit_reason_at(Time.get_ticks_usec())

func _cxr_global_limit_reason_at(now_usec: int) -> String:
	if _cxr_search_started_usec <= 0:
		return ""
	var elapsed_usec: int = now_usec - _cxr_search_started_usec
	if elapsed_usec >= CXR_MAX_SEARCH_USEC_TOTAL:
		return "MAX_SEARCH_USEC_TOTAL"
	var total_state_limit: int = CXR_R2_MAX_SEARCH_STATES_TOTAL if ["r2", "r3", "r4"].has(_cxr_active_phase) else CXR_MAX_SEARCH_STATES_TOTAL
	if _cxr_search_nodes_total >= total_state_limit:
		return "MAX_SEARCH_STATES_TOTAL"
	return ""

func _run_cxr_cavity_sequence(groups: Array, searcher: Callable, time_override_usec: int = -1) -> Dictionary:
	var results: Array[Dictionary] = []
	var failures: Array[String] = []
	var complete: bool = true
	var exhaustive: bool = true
	var started: bool = false
	var global_reason: String = ""
	for cavity_index in range(groups.size()):
		global_reason = _cxr_global_limit_reason() if time_override_usec < 0 else _cxr_global_limit_reason_at(time_override_usec)
		if not global_reason.is_empty():
			for remaining_index in range(cavity_index, groups.size()):
				var not_run_result: Dictionary = _not_run_cavity_result(groups[remaining_index], "NOT_RUN_GLOBAL_LIMIT", global_reason)
				not_run_result["cavity_index"] = remaining_index
				var not_run_report: Dictionary = not_run_result.get("cavity_report", {})
				not_run_report["cavity_index"] = remaining_index
				results.append(not_run_result)
				failures.append("NOT_RUN_GLOBAL_LIMIT:" + global_reason)
			complete = false
			exhaustive = false
			break
		var cavity_ids: Array = groups[cavity_index]
		var result_value: Variant = searcher.call(cavity_ids)
		if not result_value is Dictionary:
			var invalid_result: Dictionary = _not_run_cavity_result(cavity_ids, "FAILED_SEARCH_RESULT_TYPE", "cavity_search_returned_non_dictionary")
			invalid_result["cavity_index"] = cavity_index
			results.append(invalid_result)
			failures.append("cavity_search_returned_non_dictionary")
			complete = false
			exhaustive = false
			continue
		var result: Dictionary = result_value
		result["cavity_index"] = cavity_index
		var result_report: Dictionary = result.get("cavity_report", {})
		result_report["cavity_index"] = cavity_index
		result_report["cavity_policy"] = "original_overlapping_defect_group"
		var result_patch_record_value: Variant = result.get("patch_record", null)
		if typeof(result_patch_record_value) == TYPE_DICTIONARY:
			var result_patch_record: Dictionary = result_patch_record_value
			result_patch_record["group_index"] = cavity_index
			result_patch_record["cavity_id"] = result_report.get("cavity_id", "UNKNOWN_NOT_CAPTURED")
		results.append(result)
		started = started or bool(result.get("search_started", false))
		complete = complete and bool(result.get("search_complete", false))
		exhaustive = exhaustive and bool(result.get("search_exhaustive", false))
		if not bool(result.get("valid", false)):
			failures.append(String(result.get("terminal_reason", "UNKNOWN_NOT_CAPTURED")))
			global_reason = _cxr_global_limit_reason() if time_override_usec < 0 else _cxr_global_limit_reason_at(time_override_usec)
			if not global_reason.is_empty():
				for remaining_index in range(cavity_index + 1, groups.size()):
					var not_run_after_failure: Dictionary = _not_run_cavity_result(groups[remaining_index], "NOT_RUN_GLOBAL_LIMIT", global_reason)
					not_run_after_failure["cavity_index"] = remaining_index
					var after_failure_report: Dictionary = not_run_after_failure.get("cavity_report", {})
					after_failure_report["cavity_index"] = remaining_index
					results.append(not_run_after_failure)
					failures.append("NOT_RUN_GLOBAL_LIMIT:" + global_reason)
				complete = false
				exhaustive = false
				break
	return {"cavity_results": results, "failure_reasons": failures, "search_started": started, "search_complete": complete and results.size() == groups.size(), "search_exhaustive": exhaustive and results.size() == groups.size(), "global_limit_reason": global_reason}

func _boundary_state(triangles: Array) -> Dictionary:
	var edges: Dictionary = {}
	var input_errors: Array[Dictionary] = []
	for triangle_index in range(triangles.size()):
		var triangle_value: Variant = triangles[triangle_index]
		if not triangle_value is Dictionary:
			input_errors.append({"triangle_index": triangle_index, "reason": "cx_boundary_triangle_invalid"})
			continue
		var triangle: Dictionary = triangle_value
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3:
			input_errors.append({"triangle_index": triangle_index, "triangle_id": String(triangle.get("triangle_id", "")), "reason": "cx_boundary_triangle_arity_invalid", "root_ids": ids.duplicate()})
			continue
		for index in range(3):
			var a_id: String = String(ids[index])
			var b_id: String = String(ids[(index + 1) % 3])
			var key: String = _edge_key(a_id, b_id)
			if not edges.has(key):
				edges[key] = []
			edges[key].append({"triangle_index": triangle_index, "triangle_id": String(triangle.get("triangle_id", "")), "a": a_id, "b": b_id})
	var edge_keys: Array = edges.keys()
	edge_keys.sort()
	var incidence_rows: Array[Dictionary] = []
	var boundary: Array[String] = []
	var indegree: Dictionary = {}
	var outdegree: Dictionary = {}
	var invalid_reasons: Array[Dictionary] = input_errors.duplicate(true)
	for edge_key_value in edge_keys:
		var edge_key: String = String(edge_key_value)
		var owners: Array = edges[edge_key]
		incidence_rows.append({"edge": edge_key, "incidence_count": owners.size(), "owners": owners.duplicate(true)})
		if owners.size() > 2:
			invalid_reasons.append({"reason": "cx_patch_nonmanifold_edge", "edge": edge_key, "incidence": owners.size()})
		if owners.size() == 1:
			var a_id: String = String(owners[0].a)
			var b_id: String = String(owners[0].b)
			boundary.append(a_id + "->" + b_id)
			outdegree[a_id] = int(outdegree.get(a_id, 0)) + 1
			indegree[b_id] = int(indegree.get(b_id, 0)) + 1
	var observed_boundary_signature: String = Core.sha256(JSON.stringify(boundary).to_utf8_buffer())
	if invalid_reasons.is_empty() and boundary.size() < 3:
		invalid_reasons.append({"reason": "cx_patch_boundary_too_small", "boundary_edge_count": boundary.size()})
	if invalid_reasons.is_empty():
		for vertex_value in outdegree.keys():
			var vertex: String = String(vertex_value)
			if int(outdegree[vertex]) != 1 or int(indegree.get(vertex, 0)) != 1:
				invalid_reasons.append({"reason": "cx_patch_boundary_not_single_cycle", "vertex": vertex, "indegree": int(indegree.get(vertex, 0)), "outdegree": int(outdegree[vertex])})
		if indegree.size() != outdegree.size():
			invalid_reasons.append({"reason": "cx_patch_boundary_degree_mismatch", "indegree_vertices": indegree.size(), "outdegree_vertices": outdegree.size()})
	if invalid_reasons.is_empty():
		var successor: Dictionary = {}
		for directed_edge in boundary:
			var split: PackedStringArray = directed_edge.split("->")
			if split.size() != 2:
				invalid_reasons.append({"reason": "cx_patch_boundary_edge_invalid", "edge": directed_edge})
			else:
				successor[split[0]] = split[1]
		var visited: Dictionary = {}
		if not outdegree.is_empty():
			var start_vertex: String = String(outdegree.keys()[0])
			var cursor: String = start_vertex
			while not visited.has(cursor):
				visited[cursor] = true
				if not successor.has(cursor):
					invalid_reasons.append({"reason": "cx_patch_boundary_cycle_open", "vertex": cursor})
					break
				cursor = String(successor[cursor])
			if cursor != start_vertex or visited.size() != outdegree.size():
				invalid_reasons.append({"reason": "cx_patch_boundary_multiple_cycles", "start_vertex": start_vertex, "end_vertex": cursor, "visited_count": visited.size(), "boundary_vertex_count": outdegree.size()})
	boundary.sort()
	var diagnostics: Dictionary = {"edge_incidence": incidence_rows, "edge_count": incidence_rows.size(), "boundary_edges": boundary.duplicate(), "boundary_edge_count": boundary.size(), "input_errors": input_errors, "invalid_reasons": invalid_reasons, "observed_boundary_signature": observed_boundary_signature}
	diagnostics["diagnostic_sha256"] = Core.sha256(JSON.stringify(diagnostics).to_utf8_buffer())
	if not invalid_reasons.is_empty():
		diagnostics["valid"] = false
		diagnostics["reason"] = String(invalid_reasons[0].get("reason", "cx_patch_boundary_invalid"))
		return diagnostics
	boundary.sort()
	diagnostics["valid"] = true
	diagnostics["signature"] = Core.sha256(JSON.stringify(boundary).to_utf8_buffer())
	diagnostics["directed_edges"] = boundary
	diagnostics["vertex_count"] = outdegree.size()
	return diagnostics

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
	var retained: Array = state.get("retained_solutions", [])
	var retained_limit: int = int(state.get("retained_solution_limit", CXR_MAX_RETAINED_SOLUTIONS))
	if retained.size() < retained_limit:
		retained.append({"support_ids": ids.duplicate(), "selected_supports": supports.duplicate(true), "fan_triangles": fan_triangles.duplicate(true), "minimum_cross_squared": min_cross, "maximum_support_displacement": max_displacement, "stable_score_key": score_key})
		state["retained_solutions"] = retained
	var best: Dictionary = state.get("best", {})
	if best.is_empty() or score_key < String(best.get("stable_score_key", "")):
		state["best"] = {"fan_triangles": fan_triangles, "selected_supports": supports, "support_ids": ids, "minimum_cross_squared": min_cross, "maximum_support_displacement": max_displacement, "stable_score_key": score_key}
	if int(state.get("solutions", 0)) >= retained_limit:
		state["complete"] = false
		state["limit_reason"] = "MAX_RETAINED_SOLUTIONS"
func _generate_field_candidates(residual: Dictionary, patch: Array[Dictionary], values: PackedFloat32Array, roi: Dictionary, level: int, max_candidates: int, max_attempts: int, cavity_id: String, fixture_row: Dictionary) -> Dictionary:
	var generation_started_usec: int = Time.get_ticks_usec()
	if not _cxr_local_search_marker_emitted:
		var marker: String = "R12CXR_R3_SUPPORT_GENERATION_BEGIN " if _cxr_active_phase == "r3" else "R12CXR_R4_BOUNDARY_SEARCH_BEGIN " if _cxr_active_phase == "r4" else "R12CXR_LOCAL_PATCH_SEARCH_BEGIN "
		print(marker + JSON.stringify({"attempt_id": OS.get_environment("R12CXR_ATTEMPT_ID"), "source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "scenario_id": "R9.2.SEAM.XPLUS_EQUAL.v1", "cavity_id": cavity_id, "level": level, "support_source": "original_frozen_residual_faces_only" if _cxr_active_phase in ["r3", "r4"] else "phase_defined_residual_set", "preregistered_limits": _cxr_limits()}))
		_cxr_local_search_marker_emitted = true
	var attempts: Array[Dictionary] = []
	var candidates_by_identity: Dictionary = {}
	var triangle_points: Array = residual.get("points", [])
	if triangle_points.size() != 3:
		var invalid_arity_attempts: Array[Dictionary] = [{"candidate_id": "", "accepted": false, "rejection_reason": "residual_point_arity_invalid"}]
		return {"attempts": invalid_arity_attempts, "candidate_pool": [], "candidates": [], "candidate_attempt_count": 1, "candidate_count": 0, "candidate_unique_count": 0, "candidate_cap_hit": false, "attempt_cap_hit": false, "time_cap_reason": "", "candidate_generation_usec": Time.get_ticks_usec() - generation_started_usec, "limit_hit": false, "limits_hit": [], "source_valid": false, "source_failure_reason": "residual_point_arity_invalid", "source_tetrahedron_count": 0, "invalid_tetrahedron_count": 0, "cell_bounds": "NOT_RUN_INVALID_INPUT"}
	var face_centroid: Vector3 = (Vector3(triangle_points[0]) + Vector3(triangle_points[1]) + Vector3(triangle_points[2])) / 3.0
	if not face_centroid.is_finite():
		var nonfinite_attempts: Array[Dictionary] = [{"candidate_id": "", "accepted": false, "rejection_reason": "residual_centroid_nonfinite"}]
		return {"attempts": nonfinite_attempts, "candidate_pool": [], "candidates": [], "candidate_attempt_count": 1, "candidate_count": 0, "candidate_unique_count": 0, "candidate_cap_hit": false, "attempt_cap_hit": false, "time_cap_reason": "", "candidate_generation_usec": Time.get_ticks_usec() - generation_started_usec, "limit_hit": false, "limits_hit": [], "source_valid": false, "source_failure_reason": "residual_centroid_nonfinite", "source_tetrahedron_count": 0, "invalid_tetrahedron_count": 0, "cell_bounds": "NOT_RUN_INVALID_INPUT"}
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
		return {"attempts": [], "candidate_pool": [], "candidates": [], "candidate_attempt_count": 0, "candidate_count": 0, "candidate_unique_count": 0, "candidate_cap_hit": false, "attempt_cap_hit": false, "time_cap_reason": "", "candidate_generation_usec": Time.get_ticks_usec() - generation_started_usec, "limit_hit": false, "limits_hit": [], "source_valid": false, "source_failure_reason": "patch_support_domain_outside_roi", "source_tetrahedron_count": 0, "invalid_tetrahedron_count": 0, "cell_bounds": {"min": cell_min, "max": cell_max}}
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
					source_tet_count += 1
					if not bool(tet_data.get("valid", false)):
						source_valid = false
						invalid_tetrahedra += 1
						_cxr_record_attempt(attempts, "", false, String(tet_data.get("reason", "tetrahedron_invalid")), cavity_id, residual, level, cell, tet_index, "tetra_data", -1, Vector3.ZERO, tet_data, roi_min, step, max_attempts)
						continue
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
	var candidate_unique_count: int = candidates.size()
	var candidate_cap_hit: bool = candidate_unique_count > max_candidates
	if candidate_cap_hit:
		candidates.resize(max_candidates)
	for index in range(candidates.size()):
		var candidate: Dictionary = candidates[index]
		candidate["stable_rank"] = index
		candidates[index] = candidate
	var candidate_pool: Array[Dictionary] = candidates.duplicate(true)
	var limits_hit: Array[String] = []
	if attempt_cap_hit: limits_hit.append("MAX_CANDIDATE_ATTEMPTS_PER_CAVITY")
	if candidate_cap_hit: limits_hit.append("MAX_SUPPORT_CANDIDATES_PER_CAVITY")
	if not time_cap_reason.is_empty(): limits_hit.append(time_cap_reason)
	return {"attempts": attempts, "candidate_pool": candidate_pool, "candidates": candidates, "candidate_attempt_count": attempts.size(), "candidate_count": candidates.size(), "candidate_unique_count": candidate_unique_count, "candidate_cap_hit": candidate_cap_hit, "attempt_cap_hit": attempt_cap_hit, "time_cap_reason": time_cap_reason, "limit_hit": attempt_cap_hit or candidate_cap_hit or not time_cap_reason.is_empty(), "limits_hit": limits_hit, "source_valid": source_valid, "source_failure_reason": "invalid_source_tetrahedra" if not source_valid else "", "invalid_tetrahedron_count": invalid_tetrahedra, "source_tetrahedron_count": source_tet_count, "candidate_generation_usec": Time.get_ticks_usec() - generation_started_usec, "cell_bounds": {"min": cell_min, "max": cell_max}}
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

func _r2_candidate_attempt_ids(attempts: Array) -> Array[String]:
	var ids: Array[String] = []
	for attempt_value in attempts:
		if typeof(attempt_value) != TYPE_DICTIONARY:
			ids.append("UNKNOWN_NOT_CAPTURED")
			continue
		var attempt: Dictionary = attempt_value
		ids.append(String(attempt.get("attempt_id", attempt.get("candidate_id", "UNKNOWN_NOT_CAPTURED"))))
	return ids

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
	var limits: Dictionary = {"phase": _cxr_active_phase, "max_cavity_level": CXR_MAX_CAVITY_LEVEL, "max_cavities": CXR_MAX_CAVITIES, "max_patch_triangles": CXR_MAX_PATCH_TRIANGLES, "max_candidate_attempts_per_cavity": CXR_MAX_CANDIDATE_ATTEMPTS_PER_CAVITY, "max_support_candidates_per_cavity": CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY, "max_selected_supports": CXR_MAX_SELECTED_SUPPORTS, "max_retained_solutions_per_cavity": CXR_MAX_RETAINED_SOLUTIONS, "max_search_usec_per_cavity": CXR_MAX_SEARCH_USEC_PER_CAVITY, "max_search_usec_total": CXR_MAX_SEARCH_USEC_TOTAL, "max_realize_usec": CXR_MAX_REALIZE_USEC, "max_support_distance": CXR_MAX_SUPPORT_DISTANCE, "barycentric_epsilon": CXR_BARYCENTRIC_EPSILON, "field_residual_epsilon": CXR_FIELD_RESIDUAL_EPSILON, "cross_squared_cutoff": CXR_CUTOFF_SQUARED}
	if ["r2", "r3", "r4"].has(_cxr_active_phase):
		limits["max_candidate_triangles_per_cavity"] = CXR_R2_MAX_CANDIDATE_TRIANGLES_PER_CAVITY
		limits["max_candidate_triangles_total"] = CXR_R2_MAX_CANDIDATE_TRIANGLES_TOTAL
		limits["max_search_states_per_cavity"] = CXR_R2_MAX_SEARCH_STATES_PER_CAVITY
		limits["max_search_states_total"] = CXR_R2_MAX_SEARCH_STATES_TOTAL
		if _cxr_active_phase in ["r3", "r4"]:
			limits["max_cavity_level"] = CXR_R3_MAX_CAVITY_LEVEL
			limits["max_cavities"] = CXR_MAX_CAVITIES
			limits["cavity_policy"] = "search_original_groups_independently_then_joint_search_only_intersecting_minimum_patches"
			limits["patch_policy"] = "minimum_cardinality_connected_subsets_within_dual_graph_radius_layers_0_through_4_per_cavity"
			limits["patch_selection_state_cap_per_cavity"] = CXR_R2_MAX_SEARCH_STATES_PER_CAVITY
			limits["patch_selection_state_cap_total"] = CXR_R2_MAX_SEARCH_STATES_TOTAL
			limits["boundary_source"] = "remaining_C6_edge_incidence_after_cavity_patch_removal"
			limits["support_source"] = "original_frozen_residual_faces_only"
	else:
		limits["max_candidate_triangles_per_cavity"] = CXR_MAX_CANDIDATE_TRIANGLES_PER_CAVITY
		limits["max_search_states_per_cavity"] = CXR_MAX_SEARCH_STATES_PER_CAVITY
		limits["max_search_states_total"] = CXR_MAX_SEARCH_STATES_TOTAL
	if _cxr_active_phase == "r4":
		limits["boundary_first_policy"] = "lexicographic_boundary_defect_driven_best_first_connected_face_expansion"
		limits["max_removed_faces"] = CXR_R4_MAX_REMOVED_FACES
		limits["max_boundary_first_states"] = CXR_R4_MAX_BOUNDARY_STATES
		limits["max_boundary_first_queue"] = CXR_R4_MAX_QUEUE_SIZE
		limits["max_boundary_components"] = CXR_R4_MAX_BOUNDARY_COMPONENTS
		limits["max_boundary_first_usec_per_cavity"] = CXR_R4_MAX_BOUNDARY_USEC
	return limits

func _cxr_counters(search_started: bool = true) -> Dictionary:
	if not search_started:
		return {"search_nodes": "UNKNOWN_NOT_CAPTURED", "patch_selection_nodes": "UNKNOWN_NOT_CAPTURED", "candidate_attempts": "UNKNOWN_NOT_CAPTURED", "candidate_triangles": "UNKNOWN_NOT_CAPTURED", "branches": "UNKNOWN_NOT_CAPTURED", "prunes": "UNKNOWN_NOT_CAPTURED"}
	return {"search_nodes": _cxr_search_nodes_total, "patch_selection_nodes": _cxr_patch_selection_nodes_total, "candidate_attempts": _cxr_candidate_attempts_total, "candidate_triangles": _cxr_candidate_triangles_total, "branches": _cxr_branch_counts.duplicate(true), "prunes": _cxr_prune_counts.duplicate(true)}

func _cxr_count(target: Dictionary, key: String) -> void:
	target[key] = int(target.get(key, 0)) + 1

func _cxr_count_branch(key: String) -> void:
	_cxr_count(_cxr_branch_counts, key)
	_cxr_count(_cxr_active_cavity_branches, key)

func _cxr_count_prune(key: String) -> void:
	_cxr_count(_cxr_prune_counts, key)
	_cxr_count(_cxr_active_cavity_prunes, key)

func _cxr_time_limit_reason() -> String:
	if _cxr_full_finite_graph_mode:
		return ""
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
