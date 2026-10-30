extends "res://tests/prototypes/p3_1_r10_b_realizer.gd"

## R10-B6: bounded, deterministic beam search guided by the frozen area cutoff.
## Vertices, exact source-root set, boundary arcs, and the production cutoff remain fixed.

const B6_MAX_UNIQUE_STATES: int = 1024
const B6_MAX_BEAM_WIDTH: int = 32
const B6_MAX_EDGE_CANDIDATES: int = 12000
const B6_MAX_SOLVER_MSEC: int = 30000

func _optimize_triangulation_edge_flips(input_triangles: Array[Dictionary], boundary_root_ids: Array, projection_axis: int) -> Dictionary:
	var began: int = Time.get_ticks_msec()
	var boundary_edges: Dictionary = {}
	for index in range(boundary_root_ids.size()):
		boundary_edges[_arc_key(String(boundary_root_ids[index]), String(boundary_root_ids[(index + 1) % boundary_root_ids.size()]))] = true
	var initial: Array[Dictionary] = input_triangles.duplicate(true)
	var expected_roots: Array[String] = _sorted_root_set(initial)
	var orientation: float = _state_orientation(initial, projection_axis)
	var initial_key: String = _state_key(initial)
	var beam: Array[Dictionary] = [{"key": initial_key, "triangles": initial}]
	var parents: Dictionary = {initial_key: ""}
	var incoming: Dictionary = {}
	var pruned: Dictionary = {}
	var best_triangles: Array[Dictionary] = initial
	var best_quality: Dictionary = _quality(initial)
	var best_key: String = initial_key
	var solution_key: String = ""
	var candidate_count: int = 0
	var expanded_count: int = 0
	var frontier_peak: int = 1
	var beam_pruned: int = 0
	var stop_reason: String = ""
	while not beam.is_empty():
		if Time.get_ticks_msec() - began >= B6_MAX_SOLVER_MSEC:
			stop_reason = "solver_wall_time_limit"
			break
		beam.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return _state_precedes(left, right))
		var state: Dictionary = beam.pop_front()
		var triangles: Array[Dictionary] = state.triangles
		var current_quality: Dictionary = _quality(triangles)
		expanded_count += 1
		if _quality_precedes(current_quality, _quality(best_triangles)):
			best_triangles = triangles
			best_quality = current_quality
			best_key = String(state.key)
		if int(current_quality.subcutoff_count) == 0:
			solution_key = String(state.key)
			best_triangles = triangles
			best_quality = current_quality
			best_key = solution_key
			break
		var edges: Dictionary = _edge_occurrences(triangles)
		var root_points: Dictionary = _root_point_map(triangles)
		var edge_keys: Array = edges.keys()
		edge_keys.sort()
		for raw_edge_key in edge_keys:
			if Time.get_ticks_msec() - began >= B6_MAX_SOLVER_MSEC:
				stop_reason = "solver_wall_time_limit"
				break
			if candidate_count >= B6_MAX_EDGE_CANDIDATES:
				stop_reason = "edge_candidate_limit"
				break
			candidate_count += 1
			var edge_key: String = String(raw_edge_key)
			if boundary_edges.has(edge_key):
				_inc(pruned, "fixed_boundary_edge")
				continue
			var edge: Dictionary = edges[edge_key]
			var owners: Array = edge.get("owners", [])
			if owners.size() != 2:
				_inc(pruned, "edge_incidence_not_two")
				continue
			var first_index: int = int(owners[0])
			var second_index: int = int(owners[1])
			if not _candidate_flip_allowed(first_index, second_index):
				_inc(pruned, "outside_expanding_cavity")
				continue
			var first: Dictionary = triangles[first_index]
			var second: Dictionary = triangles[second_index]
			var a_id: String = String(edge.a)
			var b_id: String = String(edge.b)
			var c_id: String = _opposite_triangle_root(first.get("root_ids", []), a_id, b_id)
			var d_id: String = _opposite_triangle_root(second.get("root_ids", []), a_id, b_id)
			if c_id.is_empty() or d_id.is_empty() or c_id == d_id:
				_inc(pruned, "opposite_root_invalid")
				continue
			var new_edge_key: String = _arc_key(c_id, d_id)
			if edges.has(new_edge_key) or boundary_edges.has(new_edge_key):
				_inc(pruned, "replacement_diagonal_already_exists")
				continue
			var a: Vector3 = root_points[a_id]
			var b: Vector3 = root_points[b_id]
			var c: Vector3 = root_points[c_id]
			var d: Vector3 = root_points[d_id]
			if not _segments_properly_intersect(_project_world_point(a, projection_axis), _project_world_point(b, projection_axis), _project_world_point(c, projection_axis), _project_world_point(d, projection_axis)):
				_inc(pruned, "projected_quadrilateral_not_strictly_convex")
				continue
			if _new_diagonal_crosses_unrelated_edge(c_id, d_id, edge_key, edges, root_points, projection_axis):
				_inc(pruned, "projected_nonlocal_edge_crossing")
				continue
			var first_points: Array[Vector3] = [c, d, a]
			var second_points: Array[Vector3] = [d, c, b]
			var first_ids: Array[String] = [c_id, d_id, a_id]
			var second_ids: Array[String] = [d_id, c_id, b_id]
			if not _projected_orientation_valid(first_points, projection_axis, orientation) or not _projected_orientation_valid(second_points, projection_axis, orientation):
				_inc(pruned, "component_orientation_changed")
				continue
			var old_normal: Vector3 = (first.points[1] - first.points[0]).cross(first.points[2] - first.points[0]) + (second.points[1] - second.points[0]).cross(second.points[2] - second.points[0])
			var new_normal: Vector3 = (first_points[1] - first_points[0]).cross(first_points[2] - first_points[0]) + (second_points[1] - second_points[0]).cross(second_points[2] - second_points[0])
			if not old_normal.is_finite() or not new_normal.is_finite() or old_normal.length_squared() == 0.0 or new_normal.dot(old_normal) <= 0.0:
				_inc(pruned, "three_dimensional_orientation_changed")
				continue
			var next: Array[Dictionary] = triangles.duplicate(true)
			var first_cross: float = _cross_squared(first_points[0], first_points[1], first_points[2])
			var second_cross: float = _cross_squared(second_points[0], second_points[1], second_points[2])
			if not is_finite(first_cross) or not is_finite(second_cross):
				_inc(pruned, "nonfinite_triangle_area")
				continue
			next[first_index] = {"root_ids": first_ids, "points": first_points, "cross_squared": first_cross}
			next[second_index] = {"root_ids": second_ids, "points": second_points, "cross_squared": second_cross}
			if not _state_contract_valid(next, boundary_edges, expected_roots, projection_axis, orientation):
				_inc(pruned, "state_topology_or_root_contract_invalid")
				continue
			var next_key: String = _state_key(next)
			if parents.has(next_key):
				_inc(pruned, "duplicate_state_or_cycle")
				continue
			if parents.size() >= B6_MAX_UNIQUE_STATES:
				stop_reason = "unique_state_limit"
				break
			var next_quality: Dictionary = _quality(next)
			parents[next_key] = String(state.key)
			incoming[next_key] = {"removed_edge": edge_key, "added_edge": new_edge_key, "triangle_indices": [first_index, second_index], "subcutoff_count": next_quality.subcutoff_count, "minimum_cross_squared": next_quality.minimum_cross_squared}
			beam.append({"key": next_key, "triangles": next})
			if _quality_precedes(next_quality, _quality(best_triangles)):
				best_triangles = next
				best_quality = next_quality
				best_key = next_key
			if beam.size() > B6_MAX_BEAM_WIDTH:
				beam.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return _state_precedes(left, right))
				beam.remove_at(beam.size() - 1)
				beam_pruned += 1
			frontier_peak = maxi(frontier_peak, beam.size())
		if not stop_reason.is_empty(): break
	var solution_path: Array[Dictionary] = []
	if not solution_key.is_empty():
		var cursor: String = solution_key
		while not String(parents.get(cursor, "")).is_empty():
			solution_path.push_front(incoming[cursor])
			cursor = String(parents[cursor])
	var selected: Array[Dictionary] = best_triangles if solution_key.is_empty() else best_triangles
	var exhausted: bool = beam.is_empty() and stop_reason.is_empty() and solution_key.is_empty()
	return {"valid": not solution_key.is_empty(), "reason": "" if not solution_key.is_empty() else stop_reason, "construction": "R10B6_CUTOFF_DIRECTED_BOUNDED_BEAM_OVER_EXACT_ROOT_INTERNAL_FLIPS", "triangles": selected, "flip_count": solution_path.size(), "flips": solution_path, "remaining_subcutoff_triangles": _subcutoff_rows(selected), "minimum_cross_squared": best_quality.minimum_cross_squared, "search": {"status": "EXACT_ROOT_REALIZATION_FOUND" if not solution_key.is_empty() else ("EXACT_ROOT_REALIZATION_INFEASIBLE_FOR_EXHAUSTED_BOUNDED_BEAM" if exhausted else "EXACT_ROOT_REALIZATION_INCONCLUSIVE"), "explored_state_count": expanded_count, "unique_state_count": parents.size(), "frontier_peak": frontier_peak, "beam_pruned_state_count": beam_pruned, "edge_candidates_examined": candidate_count, "pruned_by_reason": pruned, "best_state_key": best_key, "best_minimum_cross_squared": best_quality.minimum_cross_squared, "best_subcutoff_face_count": best_quality.subcutoff_count, "search_exhausted": exhausted, "search_limit_hit": not stop_reason.is_empty() and not exhausted, "stop_reason": stop_reason, "max_unique_states": B6_MAX_UNIQUE_STATES, "max_beam_width": B6_MAX_BEAM_WIDTH, "max_edge_candidates": B6_MAX_EDGE_CANDIDATES, "max_solver_msec": B6_MAX_SOLVER_MSEC, "solver_elapsed_msec": Time.get_ticks_msec() - began, "solution_path": solution_path, "best_state_triangles": selected.map(func(triangle: Dictionary) -> Dictionary: return {"root_ids": triangle.root_ids, "cross_squared": triangle.cross_squared})}}

func _quality_precedes(left: Dictionary, right: Dictionary) -> bool:
	if int(left.subcutoff_count) != int(right.subcutoff_count): return int(left.subcutoff_count) < int(right.subcutoff_count)
	return float(left.minimum_cross_squared) > float(right.minimum_cross_squared)

func _state_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_quality: Dictionary = _quality(left.triangles)
	var right_quality: Dictionary = _quality(right.triangles)
	if _quality_precedes(left_quality, right_quality): return true
	if _quality_precedes(right_quality, left_quality): return false
	return String(left.key) < String(right.key)
