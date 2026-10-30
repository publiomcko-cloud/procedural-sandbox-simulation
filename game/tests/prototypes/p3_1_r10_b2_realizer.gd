extends "res://tests/prototypes/p3_1_r10_b_realizer.gd"

## R10-B2: bounded exact-root retriangulation of an expanding cavity around
## A6's sub-cutoff faces. The fixed outer mesh and source roots remain intact.

const B2_MAX_CAVITY_RING: int = 4

func _optimize_triangulation_edge_flips(input_triangles: Array[Dictionary], boundary_root_ids: Array, projection_axis: int) -> Dictionary:
	var started_msec: int = Time.get_ticks_msec()
	var seed_rows: Array[Dictionary] = _subcutoff_rows(input_triangles)
	if seed_rows.is_empty(): return super._optimize_triangulation_edge_flips(input_triangles, boundary_root_ids, projection_axis)
	var edges: Dictionary = _edge_occurrences(input_triangles)
	var adjacency: Array[Dictionary] = []
	for index in range(input_triangles.size()): adjacency.append({})
	for edge in edges.values():
		var owners: Array = edge.get("owners", [])
		if owners.size() == 2:
			adjacency[int(owners[0])][int(owners[1])] = true
			adjacency[int(owners[1])][int(owners[0])] = true
	var cavity: Dictionary = {}
	var ring_frontier: Dictionary = {}
	for seed in seed_rows:
		var face_index: int = int(seed.triangle_index)
		cavity[face_index] = true
		ring_frontier[face_index] = true
	var total_states: int = 0
	var total_edge_keys_examined: int = 0
	var total_solver_msec: int = 0
	var frontier_peak: int = 0
	var ring_records: Array[Dictionary] = []
	var any_inconclusive: bool = false
	var best_triangles: Array[Dictionary] = input_triangles
	var best_quality: Dictionary = _quality(input_triangles)
	var fixed_root_boundary: Array = boundary_root_ids.duplicate()
	for ring in range(B2_MAX_CAVITY_RING + 1):
		if ring > 0:
			var next_frontier: Dictionary = {}
			for raw_face in ring_frontier.keys():
				for raw_neighbor in adjacency[int(raw_face)].keys():
					var neighbor: int = int(raw_neighbor)
					if not cavity.has(neighbor):
						cavity[neighbor] = true
						next_frontier[neighbor] = true
			ring_frontier = next_frontier
		if Time.get_ticks_msec() - started_msec >= B1_MAX_SOLVER_MSEC or total_states >= B1_MAX_UNIQUE_STATES or total_edge_keys_examined >= B1_MAX_EDGE_CANDIDATES:
			any_inconclusive = true
			break
		var remaining_states: int = B1_MAX_UNIQUE_STATES - total_states
		var remaining_candidates: int = B1_MAX_EDGE_CANDIDATES - total_edge_keys_examined
		var remaining_msec: int = B1_MAX_SOLVER_MSEC - (Time.get_ticks_msec() - started_msec)
		_search_limit_override = {"unique_states": remaining_states, "frontier": mini(B1_MAX_FRONTIER, remaining_states), "edge_candidates": remaining_candidates, "solver_msec": remaining_msec}
		_active_cavity_triangle_indices = cavity.duplicate()
		var result: Dictionary = super._optimize_triangulation_edge_flips(input_triangles, fixed_root_boundary, projection_axis)
		var search: Dictionary = result.get("search", {})
		var explored: int = int(search.get("unique_state_count", 1))
		var examined: int = int(search.get("edge_candidates_examined", 0))
		var elapsed: int = int(search.get("solver_elapsed_msec", 0))
		total_states += explored
		total_edge_keys_examined += examined
		total_solver_msec += elapsed
		frontier_peak = maxi(frontier_peak, int(search.get("frontier_peak", 0)))
		ring_records.append({"ring": ring, "cavity_face_count": cavity.size(), "status": search.get("status", "UNKNOWN"), "explored_states": explored, "edge_keys_examined": examined, "solver_msec": elapsed, "subcutoff_count": result.get("remaining_subcutoff_triangles", []).size(), "stop_reason": search.get("stop_reason", "")})
		var quality: Dictionary = _quality(result.get("triangles", input_triangles))
		if int(quality.subcutoff_count) < int(best_quality.subcutoff_count) or (int(quality.subcutoff_count) == int(best_quality.subcutoff_count) and float(quality.minimum_cross_squared) > float(best_quality.minimum_cross_squared)):
			best_triangles = result.get("triangles", input_triangles)
			best_quality = quality
		if bool(result.get("valid", false)):
			_active_cavity_triangle_indices.clear()
			_search_limit_override.clear()
			var final_search: Dictionary = search.duplicate(true)
			final_search.merge({"status": "EXACT_ROOT_CAVITY_REALIZATION_FOUND", "expansion_ring": ring, "cavity_face_count": cavity.size(), "ring_records": ring_records, "total_states_across_rings": total_states, "total_edge_keys_examined": total_edge_keys_examined, "total_solver_msec": total_solver_msec, "max_unique_states": B1_MAX_UNIQUE_STATES, "max_frontier": B1_MAX_FRONTIER, "max_edge_candidates": B1_MAX_EDGE_CANDIDATES, "max_solver_msec": B1_MAX_SOLVER_MSEC}, true)
			result.search = final_search
			result.construction = "R10B2_EXPANDING_LOCAL_CAVITY_EXACT_ROOT_RETRIANGULATION"
			result.cavity_expansion = {"rings": ring_records, "selected_ring": ring, "face_count": cavity.size()}
			return result
		var status: String = String(search.get("status", ""))
		if status != "EXACT_ROOT_REALIZATION_INFEASIBLE_FOR_EXHAUSTED_BOUNDED_DOMAIN": any_inconclusive = true
	_active_cavity_triangle_indices.clear()
	_search_limit_override.clear()
	var exhausted: bool = not any_inconclusive and ring_records.size() == B2_MAX_CAVITY_RING + 1
	return {"valid": false, "reason": "bounded_cavity_search_inconclusive" if not exhausted else "no_exact_root_realization_within_expansion_rings_0_to_4", "construction": "R10B2_EXPANDING_LOCAL_CAVITY_EXACT_ROOT_RETRIANGULATION", "triangles": input_triangles, "flip_count": 0, "flips": [], "remaining_subcutoff_triangles": _subcutoff_rows(best_triangles), "minimum_cross_squared": best_quality.minimum_cross_squared, "cavity_expansion": {"rings": ring_records, "max_ring": B2_MAX_CAVITY_RING}, "search": {"status": "EXACT_ROOT_CAVITY_INFEASIBLE_RINGS_0_TO_4" if exhausted else "EXACT_ROOT_CAVITY_SEARCH_INCONCLUSIVE", "search_exhausted": exhausted, "search_limit_hit": not exhausted, "total_states_across_rings": total_states, "total_edge_keys_examined": total_edge_keys_examined, "total_solver_msec": total_solver_msec, "frontier_peak": frontier_peak, "ring_records": ring_records, "max_unique_states": B1_MAX_UNIQUE_STATES, "max_frontier": B1_MAX_FRONTIER, "max_edge_candidates": B1_MAX_EDGE_CANDIDATES, "max_solver_msec": B1_MAX_SOLVER_MSEC}}
