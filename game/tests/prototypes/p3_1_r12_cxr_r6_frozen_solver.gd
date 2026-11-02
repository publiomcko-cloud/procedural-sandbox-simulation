extends RefCounted

const EDGE_SEPARATOR := "\u001f"
const COVERAGE_AREA_ABS_TOLERANCE: float = 1.0e-12
const COVERAGE_AREA_REL_TOLERANCE: float = 1.0e-9

var _realizer: Variant
var _context: Dictionary
var _edge_options: Dictionary
var _triangles_by_id: Dictionary
var _triangle_by_unoriented_key: Dictionary
var _support_by_id: Dictionary
var _vertex_positions: Dictionary
var _boundary_edge_map: Dictionary
var _topology_obligations: Array
var _topology_adjacency: Dictionary
var _topology_path_audit: Dictionary
var _base_mesh: Array[Dictionary]
var _base_compatibility: Dictionary
var _pair_compatibility: Dictionary
var _visited: Dictionary
var _limits: Dictionary
var _started_usec: int
var _stats: Dictionary
var _solution: Dictionary
var _limit_hit: String = ""
var _frontier: Dictionary = {}

func solve(context: Dictionary, candidate_triangles: Array[Dictionary], realizer: Variant, limits: Dictionary = {}, validator: Callable = Callable()) -> Dictionary:
	_context = context
	_realizer = realizer
	_limits = {"max_search_states_per_cavity": 16384, "max_search_usec_per_cavity": 10000000, "max_patch_triangles": 64}
	for key in limits: _limits[key] = limits[key]
	_started_usec = Time.get_ticks_usec()
	_edge_options = {}
	_triangles_by_id = {}
	_triangle_by_unoriented_key = {}
	_support_by_id = context.get("support_by_id", {})
	_vertex_positions = context.get("vertex_positions", {})
	_boundary_edge_map = context.get("boundary_edge_map", {})
	_topology_obligations = context.get("global_arc_map", [])
	_base_mesh = _build_unmodified_mesh(context)
	_topology_adjacency = _build_topology_adjacency(candidate_triangles, _base_mesh)
	_topology_path_audit = {}
	_base_compatibility = {}
	_pair_compatibility = {}
	_visited = {}
	_solution = {}
	_limit_hit = ""
	_frontier = {}
	_stats = {"nodes": 0, "branches": 0, "max_depth": 0, "prune_histogram": {}, "support_cardinality_distribution": {}, "triangle_option_evaluations": 0, "triangle_conflict_checks": 0, "triangle_conflict_rejections": 0, "base_mesh_conflict_rejections": 0, "duplicate_state_rejections": 0, "obligation_option_histogram": {}, "candidate_graph_triangles": candidate_triangles.size(), "indexed_triangles": 0, "candidate_triangle_reuse_count": 0, "candidate_triangle_edge_index_entries": 0, "peak_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC))}
	var graph_check: Dictionary = _index_frozen_graph(candidate_triangles)
	if not bool(graph_check.get("valid", false)):
		return _terminal("INVALID_GRAPH_INPUT", String(graph_check.get("reason", "frozen_candidate_graph_invalid")), false, graph_check)
	_stats.indexed_triangles = candidate_triangles.size()
	_stats.candidate_triangle_edge_index_entries = candidate_triangles.size() * 3
	_stats.candidate_triangle_reuse_count = maxi(0, int(_stats.candidate_triangle_edge_index_entries) - candidate_triangles.size())
	var configured_expected: int = int(limits.get("expected_candidate_triangles", candidate_triangles.size()))
	if configured_expected != candidate_triangles.size():
		return _terminal("INVALID_GRAPH_INPUT", "FROZEN_GRAPH_TRIANGLE_COUNT_MISMATCH", false, {"expected": configured_expected, "observed": candidate_triangles.size()})
	var final_validator: Callable = validator
	if not final_validator.is_valid() and _realizer != null:
		final_validator = func(triangles: Array, support_ids: Array, edges: Dictionary, validation_context: Dictionary) -> Dictionary:
			return _validate_with_frozen_realizer(triangles, support_ids, edges, validation_context)
	if not final_validator.is_valid():
		return _terminal("INVALID_INPUT", "FINAL_SOLUTION_VALIDATOR_REQUIRED", false, {})
	_search([], {}, {}, final_validator)
	var status: String = "SAT" if not _solution.is_empty() else "PARTIAL_LIMIT" if not _limit_hit.is_empty() else "UNSAT_COMPLETE"
	var reason: String = "VALID_TRIANGULATION_FOUND" if status == "SAT" else _limit_hit if status == "PARTIAL_LIMIT" else "R6_F_FROZEN_GRAPH_UNSAT_COMPLETE"
	_stats.peak_memory_bytes = maxi(int(_stats.peak_memory_bytes), int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	var details: Dictionary = {"candidate_graph_sha256": String(limits.get("candidate_graph_sha256", "UNKNOWN_NOT_CAPTURED")), "support_set_sha256": String(limits.get("support_set_sha256", "UNKNOWN_NOT_CAPTURED")), "candidate_triangle_count": candidate_triangles.size(), "indexed_triangle_count": int(_stats.indexed_triangles), "vertex_count": context.get("vertex_ids", []).size(), "support_count": _support_by_id.size(), "support_cardinality_bound": "NONE", "branches": int(_stats.branches), "nodes": int(_stats.nodes), "prune_histogram": _stats.prune_histogram.duplicate(true), "max_depth": int(_stats.max_depth), "selected_support_cardinality_distribution_explored": _stats.support_cardinality_distribution.duplicate(true), "candidate_triangle_edge_index_entries": int(_stats.candidate_triangle_edge_index_entries), "candidate_triangle_reuse_count": int(_stats.candidate_triangle_reuse_count), "candidate_triangle_option_evaluations": int(_stats.triangle_option_evaluations), "triangle_conflict_checks": int(_stats.triangle_conflict_checks), "triangle_conflict_rejections": int(_stats.triangle_conflict_rejections), "base_mesh_conflict_rejections": int(_stats.base_mesh_conflict_rejections), "boundary_edge_candidate_counts": _boundary_candidate_counts(), "internal_edge_candidate_counts": _internal_candidate_counts(), "topology_path_candidate_counts": _topology_path_candidate_counts(), "selected_component_count_at_terminal": int(_stats.get("selected_component_count", 0)), "deterministic_order": "minimum_compatible_edge_options_then_boundary_priority_then_edge_key_then_triangle_id", "search_usec": Time.get_ticks_usec() - _started_usec, "peak_memory_bytes": int(_stats.peak_memory_bytes), "complete": status != "PARTIAL_LIMIT", "search_exhaustive": status == "UNSAT_COMPLETE", "frontier": _frontier.duplicate(true), "best_solution": _solution.duplicate(true)}
	return _terminal(status, reason, status != "PARTIAL_LIMIT", details)

func _terminal(status: String, reason: String, complete: bool, details: Dictionary) -> Dictionary:
	var result: Dictionary = details.duplicate(true)
	result["status"] = status
	result["terminal_reason"] = reason
	result["valid"] = status == "SAT"
	result["search_complete"] = complete
	result["search_exhaustive"] = status == "UNSAT_COMPLETE"
	result["solver_type"] = "R6_FROZEN_GRAPH_MRV_EDGE_COMPLETION_V1"
	result["support_cardinality_bound"] = "NONE"
	result["candidate_triangle_count"] = int(details.get("candidate_triangle_count", _stats.get("candidate_graph_triangles", 0)))
	result["branches"] = int(details.get("branches", _stats.get("branches", 0)))
	result["nodes"] = int(details.get("nodes", _stats.get("nodes", 0)))
	result["prune_histogram"] = details.get("prune_histogram", _stats.get("prune_histogram", {}).duplicate(true))
	result["max_depth"] = int(details.get("max_depth", _stats.get("max_depth", 0)))
	result["search_usec"] = int(details.get("search_usec", Time.get_ticks_usec() - _started_usec))
	result["best_solution"] = details.get("best_solution", {})
	return result

func _index_frozen_graph(candidate_triangles: Array[Dictionary]) -> Dictionary:
	var ids: Array[String] = []
	for triangle in candidate_triangles:
		var triangle_id: String = String(triangle.get("triangle_id", ""))
		var roots: Array = triangle.get("root_ids", [])
		var points: Array = triangle.get("points", [])
		if triangle_id.is_empty() or roots.size() != 3 or points.size() != 3 or not is_finite(float(triangle.get("cross_squared", NAN))) or float(triangle.get("cross_squared", NAN)) <= 1.0e-12:
			return {"valid": false, "reason": "frozen_candidate_row_invalid", "triangle_id": triangle_id}
		if _triangles_by_id.has(triangle_id):
			return {"valid": false, "reason": "FROZEN_GRAPH_DUPLICATE_TRIANGLE_ID", "triangle_id": triangle_id}
		var ids_in_triangle: Array[String] = []
		for root_value in roots: ids_in_triangle.append(String(root_value))
		for root_id in ids_in_triangle:
			if not _vertex_positions.has(root_id): return {"valid": false, "reason": "FROZEN_GRAPH_VERTEX_NOT_ADDRESSABLE", "triangle_id": triangle_id, "vertex_id": root_id}
		if ids_in_triangle[0] == ids_in_triangle[1] or ids_in_triangle[1] == ids_in_triangle[2] or ids_in_triangle[2] == ids_in_triangle[0]:
			return {"valid": false, "reason": "FROZEN_GRAPH_DUPLICATE_VERTEX_IN_TRIANGLE", "triangle_id": triangle_id}
		var unoriented_key: String = _unoriented_triangle_key(ids_in_triangle)
		if _triangle_by_unoriented_key.has(unoriented_key): return {"valid": false, "reason": "FROZEN_GRAPH_DUPLICATE_FACE", "triangle_id": triangle_id, "prior_triangle_id": _triangle_by_unoriented_key[unoriented_key]}
		var exact_points: Array[Vector3] = []
		for index in range(3):
			if not (points[index] is Vector3): return {"valid": false, "reason": "FROZEN_GRAPH_POINT_TYPE_INVALID", "triangle_id": triangle_id, "point_index": index}
			var point: Vector3 = points[index]
			var vertex_position: Vector3 = _vertex_positions[ids_in_triangle[index]]
			if var_to_bytes(point) != var_to_bytes(vertex_position): return {"valid": false, "reason": "FROZEN_GRAPH_ROOT_COORDINATE_MISMATCH", "triangle_id": triangle_id, "root_id": ids_in_triangle[index]}
			exact_points.append(point)
		var recomputed_cross_squared: float = (exact_points[1] - exact_points[0]).cross(exact_points[2] - exact_points[0]).length_squared()
		if var_to_bytes(recomputed_cross_squared) != var_to_bytes(float(triangle.cross_squared)): return {"valid": false, "reason": "FROZEN_GRAPH_CROSS_SQUARED_MISMATCH", "triangle_id": triangle_id}
		_triangles_by_id[triangle_id] = triangle
		_triangle_by_unoriented_key[unoriented_key] = triangle_id
		ids.append(triangle_id)
		for edge_index in range(3):
			var from_id: String = ids_in_triangle[edge_index]
			var to_id: String = ids_in_triangle[(edge_index + 1) % 3]
			var directed_key: String = _directed_key(from_id, to_id)
			if not _edge_options.has(directed_key): _edge_options[directed_key] = []
			_edge_options[directed_key].append(triangle)
	ids.sort()
	for directed_key in _edge_options:
		_edge_options[directed_key].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("triangle_id", "")) < String(b.get("triangle_id", "")))
	for directed_key in _edge_options: _stats.candidate_triangle_edge_index_entries = int(_stats.candidate_triangle_edge_index_entries) + _edge_options[directed_key].size()
	_stats.candidate_triangle_reuse_count = maxi(0, int(_stats.candidate_triangle_edge_index_entries) - candidate_triangles.size())
	if ids.size() != candidate_triangles.size(): return {"valid": false, "reason": "FROZEN_GRAPH_TRIANGLE_ROWS_DROPPED"}
	return {"valid": true, "triangle_count": ids.size(), "triangle_ids": ids}

func _build_unmodified_mesh(context: Dictionary) -> Array[Dictionary]:
	var patch_ids: Dictionary = {}
	for face_id_value in context.get("patch_ids", []): patch_ids[String(face_id_value)] = true
	var result: Array[Dictionary] = []
	for triangle_value in context.get("all_triangles", []):
		var triangle: Dictionary = triangle_value
		if not patch_ids.has(String(triangle.get("triangle_id", ""))): result.append(triangle)
	return result

func _build_topology_adjacency(candidates: Array[Dictionary], base_mesh: Array[Dictionary]) -> Dictionary:
	var adjacency: Dictionary = {}
	for triangle in candidates + base_mesh:
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3: continue
		for index in range(3):
			var a: String = String(ids[index])
			var b: String = String(ids[(index + 1) % 3])
			if not adjacency.has(a): adjacency[a] = {}
			if not adjacency.has(b): adjacency[b] = {}
			adjacency[a][b] = true
			adjacency[b][a] = true
	return adjacency

func _topology_paths_remain_possible() -> Dictionary:
	if not _topology_path_audit.is_empty(): return _topology_path_audit
	var path_rows: Array[Dictionary] = []
	for arc_value in _topology_obligations:
		if typeof(arc_value) != TYPE_DICTIONARY: continue
		var arc: Dictionary = arc_value
		var ids: Array = arc.get("root_ids", [])
		if ids.size() != 2: continue
		if not _topology_nodes_connected(String(ids[0]), String(ids[1])):
			_topology_path_audit = {"valid": false, "arc_id": String(arc.get("arc_id", "")), "root_ids": ids.duplicate(), "paths": path_rows}
			return _topology_path_audit
		path_rows.append({"arc_id": String(arc.get("arc_id", "")), "root_ids": ids.duplicate(), "candidate_graph_path_reachable": true, "candidate_graph_path_model": "undirected_connectivity_over_frozen_candidate_and_unmodified_mesh_edges; final_ordered_path_and_no_merge_checked_by_frozen_validator"})
	_topology_path_audit = {"valid": true, "paths": path_rows}
	return _topology_path_audit

func _topology_nodes_connected(start_id: String, target_id: String) -> bool:
	if start_id == target_id: return false
	if not _topology_adjacency.has(start_id) or not _topology_adjacency.has(target_id): return false
	var visited: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	var cursor: int = 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		if current == target_id: return true
		var neighbors: Array = _topology_adjacency[current].keys()
		neighbors.sort()
		for neighbor_value in neighbors:
			var neighbor: String = String(neighbor_value)
			if visited.has(neighbor): continue
			visited[neighbor] = true
			queue.append(neighbor)
	return false

func _selected_component_count(selected: Array[Dictionary]) -> int:
	if selected.is_empty(): return 0
	var triangle_by_vertex: Dictionary = {}
	for index in range(selected.size()):
		for root_id_value in selected[index].get("root_ids", []):
			var root_id: String = String(root_id_value)
			if not triangle_by_vertex.has(root_id): triangle_by_vertex[root_id] = []
			triangle_by_vertex[root_id].append(index)
	var visited: Dictionary = {}
	var components: int = 0
	for first in range(selected.size()):
		if visited.has(first): continue
		components += 1
		var queue: Array[int] = [first]
		visited[first] = true
		var cursor: int = 0
		while cursor < queue.size():
			var current: int = queue[cursor]
			cursor += 1
			for root_id_value in selected[current].get("root_ids", []):
				for neighbor_value in triangle_by_vertex[String(root_id_value)]:
					var neighbor: int = int(neighbor_value)
					if visited.has(neighbor): continue
					visited[neighbor] = true
					queue.append(neighbor)
	return components

func _validate_with_frozen_realizer(triangles: Array, support_ids: Array, edge_state: Dictionary, context: Dictionary) -> Dictionary:
	var typed_triangles: Array[Dictionary] = []
	for triangle_value in triangles: typed_triangles.append(triangle_value)
	var typed_support_ids: Array[String] = []
	for support_id_value in support_ids: typed_support_ids.append(String(support_id_value))
	var validation: Dictionary = _realizer.call("_r2_validate_solution", typed_triangles, typed_support_ids, edge_state, context)
	if not bool(validation.get("valid", false)): return validation
	var coverage: Dictionary = _coverage_area_audit(typed_triangles)
	validation["coverage_area_audit"] = coverage
	return validation

func _coverage_area_audit(triangles: Array[Dictionary]) -> Dictionary:
	var boundary_cycle: Array = _context.get("boundary_cycle", [])
	var projected_positions: Dictionary = _context.get("projected_positions", {})
	if boundary_cycle.size() < 3 or projected_positions.is_empty():
		return {"applicable": false, "reason": "frozen_projected_boundary_not_available_for_coverage_audit"}
	var boundary_twice_area: float = 0.0
	for index in range(boundary_cycle.size()):
		var a_id: String = String(boundary_cycle[index])
		var b_id: String = String(boundary_cycle[(index + 1) % boundary_cycle.size()])
		if not projected_positions.has(a_id) or not projected_positions.has(b_id):
			return {"applicable": false, "reason": "frozen_projected_boundary_root_missing", "root_ids": [a_id, b_id]}
		var a: Vector2 = projected_positions[a_id]
		var b: Vector2 = projected_positions[b_id]
		boundary_twice_area += float(a.x) * float(b.y) - float(a.y) * float(b.x)
	var boundary_area: float = absf(boundary_twice_area * 0.5)
	var triangle_area: float = 0.0
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3:
			return {"applicable": false, "reason": "candidate_triangle_root_arity_invalid", "triangle_id": triangle.get("triangle_id", "")}
		for root_id_value in ids:
			if not projected_positions.has(String(root_id_value)):
				return {"applicable": false, "reason": "candidate_triangle_projected_root_missing", "triangle_id": triangle.get("triangle_id", ""), "root_id": root_id_value}
		var a: Vector2 = projected_positions[String(ids[0])]
		var b: Vector2 = projected_positions[String(ids[1])]
		var c: Vector2 = projected_positions[String(ids[2])]
		var signed_double_area: float = (float(b.x) - float(a.x)) * (float(c.y) - float(a.y)) - (float(b.y) - float(a.y)) * (float(c.x) - float(a.x))
		triangle_area += absf(signed_double_area) * 0.5
	var area_error: float = absf(triangle_area - boundary_area)
	var allowed_error: float = maxf(COVERAGE_AREA_ABS_TOLERANCE, boundary_area * COVERAGE_AREA_REL_TOLERANCE)
	return {"applicable": true, "boundary_projected_area": boundary_area, "selected_triangle_projected_area_sum": triangle_area, "absolute_error": area_error, "absolute_tolerance": COVERAGE_AREA_ABS_TOLERANCE, "relative_tolerance": COVERAGE_AREA_REL_TOLERANCE, "allowed_error": allowed_error, "within_tolerance": area_error <= allowed_error, "use": "audit_only_topology_acceptance_uses_exact_boundary_incidence_connectivity_vertex_links_and_intersection_gates"}

func _search(selected: Array[Dictionary], selected_ids: Dictionary, edge_state: Dictionary, validator: Callable) -> bool:
	if not _limit_hit.is_empty() or not _solution.is_empty(): return false
	if int(_stats.nodes) >= int(_limits.max_search_states_per_cavity):
		_limit_hit = "R6_F_MAX_SEARCH_STATES_PER_CAVITY"
		_frontier = _frontier_record(selected, edge_state, "state_limit")
		return false
	if Time.get_ticks_usec() - _started_usec >= int(_limits.max_search_usec_per_cavity):
		_limit_hit = "R6_F_MAX_SEARCH_USEC_PER_CAVITY"
		_frontier = _frontier_record(selected, edge_state, "time_limit")
		return false
	var state_key: String = _state_key(selected)
	if _visited.has(state_key):
		_stats.duplicate_state_rejections = int(_stats.duplicate_state_rejections) + 1
		_count_prune("duplicate_state")
		return false
	_visited[state_key] = true
	_stats.nodes = int(_stats.nodes) + 1
	_stats.peak_memory_bytes = maxi(int(_stats.peak_memory_bytes), int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	_stats.branches = int(_stats.branches) + 1
	_stats.max_depth = maxi(int(_stats.max_depth), selected.size())
	_stats.selected_component_count = _selected_component_count(selected)
	var used_supports: Array[String] = _used_support_ids(selected)
	var topology_check: Dictionary = _topology_paths_remain_possible()
	if not bool(topology_check.get("valid", false)):
		_count_prune("topology_path_unreachable_in_frozen_candidate_graph")
		return false
	var support_count_key: String = str(used_supports.size())
	var distribution: Dictionary = _stats.support_cardinality_distribution
	distribution[support_count_key] = int(distribution.get(support_count_key, 0)) + 1
	if edge_state.is_empty() and not selected.is_empty(): edge_state = _build_edge_state(selected)
	var obligation_result: Dictionary = _collect_obligations(edge_state)
	if not bool(obligation_result.get("valid", false)):
		_count_prune(String(obligation_result.get("reason", "edge_state_invalid")))
		return false
	var obligations: Array[Dictionary] = obligation_result.get("obligations", [])
	if obligations.is_empty():
		var validation_context: Dictionary = _context
		validation_context["search_nodes"] = int(_stats.nodes)
		var validation: Dictionary = validator.call(selected, used_supports, edge_state, validation_context)
		if bool(validation.get("valid", false)):
			_solution = validation
			return true
		_count_prune(String(validation.get("reason", "complete_mesh_validation_rejected")))
		return false
	if selected.size() >= int(_limits.max_patch_triangles):
		_limit_hit = "R6_F_MAX_PATCH_TRIANGLES"
		_frontier = _frontier_record(selected, edge_state, "patch_triangle_limit")
		return false
	var chosen: Dictionary = {}
	for obligation in obligations:
		if _time_limit_hit(selected, edge_state): return false
		var candidates: Array[Dictionary] = _candidate_options(obligation, selected, selected_ids, edge_state, used_supports)
		obligation["candidate_options"] = candidates
		var hist: Dictionary = _stats.obligation_option_histogram
		var option_count_key: String = str(candidates.size())
		hist[option_count_key] = int(hist.get(option_count_key, 0)) + 1
		if chosen.is_empty() or _obligation_less(obligation, chosen): chosen = obligation
	if chosen.is_empty():
		_count_prune("no_unresolved_obligation")
		return false
	var chosen_candidates: Array[Dictionary] = chosen.get("candidate_options", [])
	if chosen_candidates.is_empty():
		_count_prune("required_edge_has_no_remaining_candidate")
		return false
	for candidate in chosen_candidates:
		if not _limit_hit.is_empty() or not _solution.is_empty(): return not _solution.is_empty()
		var candidate_id: String = String(candidate.get("triangle_id", ""))
		if selected_ids.has(candidate_id):
			_count_prune("duplicate_triangle")
			continue
		var next_ids: Dictionary = selected_ids.duplicate()
		next_ids[candidate_id] = true
		var next_selected: Array[Dictionary] = selected.duplicate()
		next_selected.append(candidate)
		var next_edge_state: Dictionary = _build_edge_state(next_selected)
		var next_supports: Array[String] = _used_support_ids(next_selected)
		if _duplicate_support_positions(next_supports):
			_count_prune("duplicate_support_position")
			continue
		if _search(next_selected, next_ids, next_edge_state, validator): return true
	return not _solution.is_empty()

func _collect_obligations(edge_state: Dictionary) -> Dictionary:
	var obligations: Array[Dictionary] = []
	var boundary_keys: Array = _boundary_edge_map.keys()
	boundary_keys.sort()
	for key_value in boundary_keys:
		var key: String = String(key_value)
		var expected: Dictionary = _boundary_edge_map[key]
		var rows: Array = edge_state.get(key, [])
		if rows.size() > 1: return {"valid": false, "reason": "boundary_incidence_exceeds_one", "edge_key": key}
		if rows.is_empty(): obligations.append({"kind": "boundary", "edge_key": key, "from_id": String(expected.get("a", "")), "to_id": String(expected.get("b", "")), "priority": 0})
		elif String(rows[0].get("a", "")) != String(expected.get("a", "")) or String(rows[0].get("b", "")) != String(expected.get("b", "")):
			return {"valid": false, "reason": "boundary_orientation_invalid", "edge_key": key}
	var state_keys: Array = edge_state.keys()
	state_keys.sort()
	for key_value in state_keys:
		var key: String = String(key_value)
		if _boundary_edge_map.has(key): continue
		var rows: Array = edge_state[key]
		if rows.size() > 2: return {"valid": false, "reason": "internal_incidence_exceeds_two", "edge_key": key}
		if rows.size() == 1:
			obligations.append({"kind": "internal", "edge_key": key, "from_id": String(rows[0].get("b", "")), "to_id": String(rows[0].get("a", "")), "priority": 1})
		elif rows.size() == 2 and String(rows[0].get("a", "")) == String(rows[1].get("a", "")) and String(rows[0].get("b", "")) == String(rows[1].get("b", "")):
			return {"valid": false, "reason": "internal_winding_inconsistent", "edge_key": key}
	return {"valid": true, "obligations": obligations}

func _candidate_options(obligation: Dictionary, selected: Array[Dictionary], selected_ids: Dictionary, edge_state: Dictionary, used_supports: Array[String]) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var directed_key: String = _directed_key(String(obligation.from_id), String(obligation.to_id))
	for candidate_value in _edge_options.get(directed_key, []):
		if _time_limit_hit(selected, edge_state): return options
		var candidate: Dictionary = candidate_value
		_stats.triangle_option_evaluations = int(_stats.triangle_option_evaluations) + 1
		var candidate_id: String = String(candidate.get("triangle_id", ""))
		if selected_ids.has(candidate_id): continue
		if not _candidate_can_extend(candidate, edge_state): continue
		var next_supports: Array[String] = _used_support_ids_with_candidate(used_supports, candidate)
		if _duplicate_support_positions(next_supports): continue
		if not _geometry_compatible(candidate, selected):
			_stats.triangle_conflict_rejections = int(_stats.triangle_conflict_rejections) + 1
			continue
		options.append(candidate)
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("triangle_id", "")) < String(b.get("triangle_id", "")))
	return options

func _candidate_can_extend(candidate: Dictionary, edge_state: Dictionary) -> bool:
	var ids: Array = candidate.get("root_ids", [])
	for edge_index in range(3):
		var a: String = String(ids[edge_index]); var b: String = String(ids[(edge_index + 1) % 3]); var key: String = _edge_key(a, b); var rows: Array = edge_state.get(key, [])
		if _boundary_edge_map.has(key):
			var expected: Dictionary = _boundary_edge_map[key]
			if rows.size() > 0 or a != String(expected.get("a", "")) or b != String(expected.get("b", "")): return false
		elif rows.size() > 1 or (rows.size() == 1 and String(rows[0].get("a", "")) == a and String(rows[0].get("b", "")) == b): return false
	return true

func _geometry_compatible(candidate: Dictionary, selected: Array[Dictionary]) -> bool:
	if _realizer == null: return true
	var candidate_id: String = String(candidate.get("triangle_id", ""))
	if not _base_compatibility.has(candidate_id):
		_stats.triangle_conflict_checks = int(_stats.triangle_conflict_checks) + _base_mesh.size()
		var base_ok: bool = bool(_realizer.call("_r2_intersections_clear", [candidate], _base_mesh)) and int(_realizer.call("_new_t_junction_count", [candidate], _base_mesh)) == 0
		_base_compatibility[candidate_id] = base_ok
		if not base_ok: _stats.base_mesh_conflict_rejections = int(_stats.base_mesh_conflict_rejections) + 1
	if not bool(_base_compatibility[candidate_id]): return false
	for selected_triangle in selected:
		var selected_id: String = String(selected_triangle.get("triangle_id", ""))
		var pair_key: String = candidate_id + "|" + selected_id if candidate_id < selected_id else selected_id + "|" + candidate_id
		if not _pair_compatibility.has(pair_key):
			_stats.triangle_conflict_checks = int(_stats.triangle_conflict_checks) + 1
			var compatible: bool = bool(_realizer.call("_r2_intersections_clear", [candidate], [selected_triangle])) and int(_realizer.call("_new_t_junction_count", [candidate], [selected_triangle])) == 0 and int(_realizer.call("_new_t_junction_count", [selected_triangle], [candidate])) == 0
			_pair_compatibility[pair_key] = compatible
			if not compatible: _stats.triangle_conflict_rejections = int(_stats.triangle_conflict_rejections) + 1
		if not bool(_pair_compatibility[pair_key]): return false
	return true

func _build_edge_state(triangles: Array[Dictionary]) -> Dictionary:
	var state: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		for edge_index in range(3):
			var a: String = String(ids[edge_index]); var b: String = String(ids[(edge_index + 1) % 3]); var key: String = _edge_key(a, b)
			if not state.has(key): state[key] = []
			state[key].append({"a": a, "b": b, "triangle_id": String(triangle.get("triangle_id", ""))})
	return state

func _used_support_ids(triangles: Array[Dictionary]) -> Array[String]:
	var used: Dictionary = {}
	for triangle in triangles:
		for id_value in triangle.get("root_ids", []):
			var id: String = String(id_value)
			if _support_by_id.has(id): used[id] = true
	var result: Array[String] = []
	for id_value in used.keys(): result.append(String(id_value))
	result.sort()
	return result

func _used_support_ids_with_candidate(current: Array[String], candidate: Dictionary) -> Array[String]:
	var used: Dictionary = {}
	for id in current: used[id] = true
	for id_value in candidate.get("root_ids", []):
		var id: String = String(id_value)
		if _support_by_id.has(id): used[id] = true
	var result: Array[String] = []
	for id_value in used.keys(): result.append(String(id_value))
	result.sort()
	return result

func _duplicate_support_positions(ids: Array[String]) -> bool:
	for i in range(ids.size()):
		if not _vertex_positions.has(ids[i]): return true
		for j in range(i + 1, ids.size()):
			if not _vertex_positions.has(ids[j]) or var_to_bytes(_vertex_positions[ids[i]]) == var_to_bytes(_vertex_positions[ids[j]]): return true
	return false

func _boundary_candidate_counts() -> Dictionary:
	var result: Dictionary = {}
	for key_value in _boundary_edge_map.keys():
		var key: String = String(key_value); var edge: Dictionary = _boundary_edge_map[key]
		result[key] = _edge_options.get(_directed_key(String(edge.get("a", "")), String(edge.get("b", ""))), []).size()
	return result

func _internal_candidate_counts() -> Dictionary:
	var result: Dictionary = {}
	for directed_key in _edge_options:
		var parts: PackedStringArray = String(directed_key).split("\u001e")
		if parts.size() != 2: continue
		var edge_key: String = _edge_key(parts[0], parts[1])
		if not _boundary_edge_map.has(edge_key): result[directed_key] = _edge_options[directed_key].size()
	return result

func _topology_path_candidate_counts() -> Variant:
	return _topology_paths_remain_possible().get("paths", [])

func _obligation_less(a: Dictionary, b: Dictionary) -> bool:
	var a_count: int = a.candidate_options.size(); var b_count: int = b.candidate_options.size()
	if a_count != b_count: return a_count < b_count
	if int(a.priority) != int(b.priority): return int(a.priority) < int(b.priority)
	return String(a.edge_key) < String(b.edge_key)

func _edge_key(a: String, b: String) -> String:
	return a + EDGE_SEPARATOR + b if a < b else b + EDGE_SEPARATOR + a

func _directed_key(a: String, b: String) -> String:
	return a + "\u001e" + b

func _state_key(selected: Array[Dictionary]) -> String:
	var ids: Array[String] = []
	for triangle in selected: ids.append(String(triangle.get("triangle_id", "")))
	ids.sort()
	return "|".join(ids)

func _unoriented_triangle_key(ids: Array[String]) -> String:
	var sorted_ids: Array[String] = ids.duplicate()
	sorted_ids.sort()
	return "|".join(sorted_ids)

func _frontier_record(selected: Array[Dictionary], edge_state: Dictionary, reason: String) -> Dictionary:
	var ids: Array[String] = []
	for triangle in selected: ids.append(String(triangle.get("triangle_id", "")))
	ids.sort()
	return {"reason": reason, "selected_triangle_ids": ids, "selected_support_ids": _used_support_ids(selected), "edge_keys": edge_state.keys()}

func _count_prune(reason: String) -> void:
	var histogram: Dictionary = _stats.prune_histogram
	histogram[reason] = int(histogram.get(reason, 0)) + 1

func _time_limit_hit(selected: Array[Dictionary], edge_state: Dictionary) -> bool:
	if not _limit_hit.is_empty(): return true
	if Time.get_ticks_usec() - _started_usec < int(_limits.max_search_usec_per_cavity): return false
	_limit_hit = "R6_F_MAX_SEARCH_USEC_PER_CAVITY"
	_frontier = _frontier_record(selected, edge_state, "time_limit")
	return true
