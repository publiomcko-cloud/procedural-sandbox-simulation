extends "res://tests/prototypes/p3_1_r10_b_realizer.gd"

## R10-B3: deterministic constrained-Delaunay Lawson flips over the frozen
## root set. The triangulation changes; roots and the continuous field do not.

const B3_MAX_FLIPS: int = 4096
const B3_MAX_SOLVER_MSEC: int = 90000

func _search_limit(name: String) -> int:
	if name == "unique_states": return B3_MAX_FLIPS + 1
	if name == "frontier": return 1
	if name == "edge_candidates": return 15000
	if name == "solver_msec": return B3_MAX_SOLVER_MSEC
	return super._search_limit(name)

func _optimize_triangulation_edge_flips(input_triangles: Array[Dictionary], boundary_root_ids: Array, projection_axis: int) -> Dictionary:
	var started_msec: int = Time.get_ticks_msec()
	var triangles: Array[Dictionary] = input_triangles.duplicate(true)
	var expected_roots: Array[String] = _sorted_root_set(triangles)
	var boundary_edges: Dictionary = {}
	for index in range(boundary_root_ids.size()):
		boundary_edges[_arc_key(String(boundary_root_ids[index]), String(boundary_root_ids[(index + 1) % boundary_root_ids.size()]))] = true
	var orientation: float = _state_orientation(triangles, projection_axis)
	var seen: Dictionary = {_state_key(triangles): true}
	var flips: Array[Dictionary] = []
	var rejected: Dictionary = {}
	var edge_keys_examined: int = 0
	var stop_reason: String = ""
	var exhausted: bool = false
	while flips.size() < B3_MAX_FLIPS:
		if Time.get_ticks_msec() - started_msec >= B3_MAX_SOLVER_MSEC:
			stop_reason = "solver_wall_time_limit"
			break
		var edges: Dictionary = _edge_occurrences(triangles)
		var root_points: Dictionary = _root_point_map(triangles)
		var edge_keys: Array = edges.keys()
		edge_keys.sort()
		var accepted: bool = false
		for raw_edge in edge_keys:
			if edge_keys_examined >= 15000:
				stop_reason = "edge_candidate_limit"
				break
			edge_keys_examined += 1
			var edge_key: String = String(raw_edge)
			if boundary_edges.has(edge_key): _inc(rejected, "fixed_boundary_edge"); continue
			var occurrence: Dictionary = edges[edge_key]
			var owners: Array = occurrence.get("owners", [])
			if owners.size() != 2: _inc(rejected, "edge_incidence_not_two"); continue
			var left_index: int = int(owners[0])
			var right_index: int = int(owners[1])
			var left: Dictionary = triangles[left_index]
			var right: Dictionary = triangles[right_index]
			var a_id: String = String(occurrence.a)
			var b_id: String = String(occurrence.b)
			var c_id: String = _opposite_triangle_root(left.get("root_ids", []), a_id, b_id)
			var d_id: String = _opposite_triangle_root(right.get("root_ids", []), a_id, b_id)
			if c_id.is_empty() or d_id.is_empty() or c_id == d_id: _inc(rejected, "opposite_root_invalid"); continue
			var replacement: String = _arc_key(c_id, d_id)
			if edges.has(replacement) or boundary_edges.has(replacement): _inc(rejected, "replacement_diagonal_exists"); continue
			var a: Vector3 = root_points[a_id]
			var b: Vector3 = root_points[b_id]
			var c: Vector3 = root_points[c_id]
			var d: Vector3 = root_points[d_id]
			if not _segments_properly_intersect(_project_world_point(a, projection_axis), _project_world_point(b, projection_axis), _project_world_point(c, projection_axis), _project_world_point(d, projection_axis)):
				_inc(rejected, "projected_quad_not_strictly_convex")
				continue
			var incircle: float = _incircle_determinant(_project_world_point(a, projection_axis), _project_world_point(b, projection_axis), _project_world_point(c, projection_axis), _project_world_point(d, projection_axis))
			if not is_finite(incircle) or incircle * orientation <= 0.0:
				_inc(rejected, "edge_locally_constrained_delaunay")
				continue
			if _new_diagonal_crosses_unrelated_edge(c_id, d_id, edge_key, edges, root_points, projection_axis):
				_inc(rejected, "projected_nonlocal_edge_crossing")
				continue
			var first_points: Array[Vector3] = [c, d, a]
			var second_points: Array[Vector3] = [d, c, b]
			var first_ids: Array[String] = [c_id, d_id, a_id]
			var second_ids: Array[String] = [d_id, c_id, b_id]
			if not _projected_orientation_valid(first_points, projection_axis, orientation) or not _projected_orientation_valid(second_points, projection_axis, orientation): _inc(rejected, "projected_orientation_changed"); continue
			var old_normal: Vector3 = (left.points[1] - left.points[0]).cross(left.points[2] - left.points[0]) + (right.points[1] - right.points[0]).cross(right.points[2] - right.points[0])
			var new_normal: Vector3 = (first_points[1] - first_points[0]).cross(first_points[2] - first_points[0]) + (second_points[1] - second_points[0]).cross(second_points[2] - second_points[0])
			if not old_normal.is_finite() or not new_normal.is_finite() or old_normal.length_squared() == 0.0 or new_normal.dot(old_normal) <= 0.0: _inc(rejected, "three_dimensional_winding_changed"); continue
			var next: Array[Dictionary] = triangles.duplicate(true)
			var first_cross: float = _cross_squared(first_points[0], first_points[1], first_points[2])
			var second_cross: float = _cross_squared(second_points[0], second_points[1], second_points[2])
			if not is_finite(first_cross) or not is_finite(second_cross): _inc(rejected, "nonfinite_triangle_area"); continue
			next[left_index] = {"root_ids": first_ids, "points": first_points, "cross_squared": first_cross}
			next[right_index] = {"root_ids": second_ids, "points": second_points, "cross_squared": second_cross}
			if not _state_contract_valid(next, boundary_edges, expected_roots, projection_axis, orientation): _inc(rejected, "root_boundary_or_incidence_contract_failed"); continue
			var state_key: String = _state_key(next)
			if seen.has(state_key): _inc(rejected, "state_cycle"); continue
			seen[state_key] = true
			flips.append({"removed_edge": edge_key, "added_edge": replacement, "owner_faces": [left_index, right_index], "incircle_determinant": incircle, "new_cross_squared": [first_cross, second_cross], "state_key": state_key})
			triangles = next
			accepted = true
			break
		if not stop_reason.is_empty(): break
		if not accepted:
			exhausted = true
			stop_reason = "constrained_delaunay_local_optimum"
			break
	if flips.size() >= B3_MAX_FLIPS and stop_reason.is_empty(): stop_reason = "flip_count_limit"
	var quality: Dictionary = _quality(triangles)
	var subcutoff: Array[Dictionary] = quality.subcutoff
	var solved: bool = subcutoff.is_empty()
	var search_status: String = "EXACT_ROOT_DELAUNAY_REALIZATION_FOUND" if solved else ("CONSTRAINED_DELAUNAY_LOCAL_OPTIMUM_RETAINS_SUBCUTOFF" if exhausted else "EXACT_ROOT_DELAUNAY_SEARCH_INCONCLUSIVE")
	return {"valid": solved, "reason": "" if solved else stop_reason, "construction": "R10B3_BOUNDED_CONSTRAINED_DELAUNAY_LAWSON_FLIPS", "triangles": triangles, "flip_count": flips.size(), "flips": flips, "remaining_subcutoff_triangles": subcutoff, "minimum_cross_squared": quality.minimum_cross_squared, "search": {"status": search_status, "search_exhausted": exhausted, "search_limit_hit": not solved and not exhausted, "edge_keys_examined": edge_keys_examined, "unique_state_count": seen.size(), "pruned_by_reason": rejected, "max_flips": B3_MAX_FLIPS, "max_edge_keys_examined": 15000, "max_solver_msec": B3_MAX_SOLVER_MSEC, "solver_elapsed_msec": Time.get_ticks_msec() - started_msec, "stop_reason": stop_reason, "solution_path": flips}}

func _incircle_determinant(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var ax: float = a.x - d.x
	var ay: float = a.y - d.y
	var bx: float = b.x - d.x
	var by: float = b.y - d.y
	var cx: float = c.x - d.x
	var cy: float = c.y - d.y
	return (ax * ax + ay * ay) * (bx * cy - by * cx) - (bx * bx + by * by) * (ax * cy - ay * cx) + (cx * cx + cy * cy) * (ax * by - ay * bx)
