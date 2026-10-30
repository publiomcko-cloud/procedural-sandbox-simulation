extends "res://tests/prototypes/p3_1_r10_a_topology_authority.gd"

## R10-B1 only: bounded deterministic BFS over legal internal diagonal flips.
## Search states are disposable; the inherited A6 source roots, boundaries,
## topology and scalar volume remain immutable authorities.

const B1_MAX_UNIQUE_STATES: int = 4096
const B1_MAX_FRONTIER: int = 4096
const B1_MAX_EDGE_CANDIDATES: int = 15000
const B1_MAX_SOLVER_MSEC: int = 90000

var _active_cavity_triangle_indices: Dictionary = {}
var _search_limit_override: Dictionary = {}

func _search_limit(name: String) -> int:
	if _search_limit_override.has(name): return int(_search_limit_override[name])
	match name:
		"unique_states": return B1_MAX_UNIQUE_STATES
		"frontier": return B1_MAX_FRONTIER
		"edge_candidates": return B1_MAX_EDGE_CANDIDATES
		"solver_msec": return B1_MAX_SOLVER_MSEC
	return 0

func _candidate_flip_allowed(first_index: int, second_index: int) -> bool:
	return _active_cavity_triangle_indices.is_empty() or (_active_cavity_triangle_indices.has(first_index) and _active_cavity_triangle_indices.has(second_index))

func _optimize_triangulation_edge_flips(input_triangles: Array[Dictionary], boundary_root_ids: Array, projection_axis: int) -> Dictionary:
	var begin_msec: int = Time.get_ticks_msec()
	var boundary_edges: Dictionary = {}
	for index in range(boundary_root_ids.size()):
		boundary_edges[_arc_key(String(boundary_root_ids[index]), String(boundary_root_ids[(index + 1) % boundary_root_ids.size()]))] = true
	var initial: Array[Dictionary] = input_triangles.duplicate(true)
	var expected_roots: Array[String] = _sorted_root_set(initial)
	var initial_quality: Dictionary = _quality(initial)
	var initial_key: String = _state_key(initial)
	var queue: Array[Dictionary] = [{"key": initial_key, "triangles": initial}]
	var queue_head: int = 0
	var parents: Dictionary = {initial_key: ""}
	var incoming_moves: Dictionary = {}
	var candidate_count: int = 0
	var frontier_peak: int = 1
	var pruned: Dictionary = {}
	var best_key: String = initial_key
	var best_triangles: Array[Dictionary] = initial
	var best_quality: Dictionary = initial_quality
	var solution_key: String = ""
	var stop_reason: String = ""
	var exhausted: bool = false
	while queue_head < queue.size():
		if Time.get_ticks_msec() - begin_msec >= _search_limit("solver_msec"):
			stop_reason = "solver_wall_time_limit"
			break
		var state: Dictionary = queue[queue_head]
		queue_head += 1
		var triangles: Array[Dictionary] = state.triangles
		var quality: Dictionary = _quality(triangles)
		if int(quality.subcutoff_count) == 0:
			solution_key = String(state.key)
			best_key = solution_key
			best_triangles = triangles
			best_quality = quality
			break
		var edges: Dictionary = _edge_occurrences(triangles)
		var root_points: Dictionary = _root_point_map(triangles)
		var edge_keys: Array = edges.keys()
		edge_keys.sort()
		for raw_edge_key in edge_keys:
			if Time.get_ticks_msec() - begin_msec >= _search_limit("solver_msec"):
				stop_reason = "solver_wall_time_limit"
				break
			if candidate_count >= _search_limit("edge_candidates"):
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
			if not _projected_orientation_valid(first_points, projection_axis, float(_state_orientation(initial, projection_axis))) or not _projected_orientation_valid(second_points, projection_axis, float(_state_orientation(initial, projection_axis))):
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
			if not _state_contract_valid(next, boundary_edges, expected_roots, projection_axis, float(_state_orientation(initial, projection_axis))):
				_inc(pruned, "state_topology_or_root_contract_invalid")
				continue
			var next_key: String = _state_key(next)
			if parents.has(next_key):
				_inc(pruned, "duplicate_state_or_cycle")
				continue
			if parents.size() >= _search_limit("unique_states") or queue.size() - queue_head >= _search_limit("frontier"):
				stop_reason = "unique_state_or_frontier_limit"
				break
			var next_quality: Dictionary = _quality(next)
			parents[next_key] = String(state.key)
			incoming_moves[next_key] = {"removed_edge": edge_key, "added_edge": new_edge_key, "triangle_indices": [first_index, second_index], "subcutoff_count": next_quality.subcutoff_count, "minimum_cross_squared": next_quality.minimum_cross_squared}
			queue.append({"key": next_key, "triangles": next})
			frontier_peak = maxi(frontier_peak, queue.size() - queue_head)
			if int(next_quality.subcutoff_count) < int(best_quality.subcutoff_count) or (int(next_quality.subcutoff_count) == int(best_quality.subcutoff_count) and float(next_quality.minimum_cross_squared) > float(best_quality.minimum_cross_squared)):
				best_key = next_key
				best_triangles = next
				best_quality = next_quality
		if not stop_reason.is_empty(): break
	if solution_key.is_empty() and stop_reason.is_empty() and queue_head >= queue.size():
		exhausted = true
		stop_reason = "bounded_flip_state_space_exhausted"
	var path: Array[Dictionary] = []
	if not solution_key.is_empty():
		var cursor: String = solution_key
		while String(parents.get(cursor, "")).length() > 0:
			path.push_front(incoming_moves[cursor])
			cursor = String(parents[cursor])
	var subcutoff: Array[Dictionary] = _subcutoff_rows(best_triangles)
	return {
		"valid": not solution_key.is_empty(),
		"reason": "" if not solution_key.is_empty() else stop_reason,
		"construction": "R10B1_BOUNDED_BFS_NON_MONOTONIC_CONSTRAINED_INTERNAL_EDGE_FLIPS",
		"triangles": best_triangles if not solution_key.is_empty() else input_triangles,
		"flip_count": path.size(), "flips": path,
		"remaining_subcutoff_triangles": subcutoff,
		"minimum_cross_squared": best_quality.minimum_cross_squared,
		"search": {"status": "EXACT_ROOT_REALIZATION_FOUND" if not solution_key.is_empty() else ("EXACT_ROOT_REALIZATION_INFEASIBLE_FOR_EXHAUSTED_BOUNDED_DOMAIN" if exhausted else "EXACT_ROOT_REALIZATION_INCONCLUSIVE"),
			"explored_state_count": queue_head, "unique_state_count": parents.size(), "frontier_peak": frontier_peak,
			"edge_candidates_examined": candidate_count, "pruned_by_reason": pruned,
			"best_state_key": best_key, "best_minimum_cross_squared": best_quality.minimum_cross_squared,
			"best_subcutoff_face_count": best_quality.subcutoff_count,
			"search_exhausted": exhausted, "search_limit_hit": not stop_reason.is_empty() and not exhausted and solution_key.is_empty(),
			"stop_reason": stop_reason, "max_unique_states": _search_limit("unique_states"),
			"max_frontier": _search_limit("frontier"), "max_edge_candidates": _search_limit("edge_candidates"),
			"max_solver_msec": _search_limit("solver_msec"), "solver_elapsed_msec": Time.get_ticks_msec() - begin_msec,
			"solution_path": path, "best_state_triangles": best_triangles.map(func(t: Dictionary) -> Dictionary: return {"root_ids": t.root_ids, "cross_squared": t.cross_squared})}
	}

func _state_contract_valid(triangles: Array[Dictionary], boundary_edges: Dictionary, expected_roots: Array[String], projection_axis: int, orientation: float) -> bool:
	if triangles.size() != 110: return false
	var root_set: Dictionary = {}
	var edge_incidence: Dictionary = {}
	var triangle_keys: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		var points: Array = triangle.get("points", [])
		if ids.size() != 3 or points.size() != 3: return false
		var sorted_ids: Array[String] = [String(ids[0]), String(ids[1]), String(ids[2])]
		sorted_ids.sort()
		var tri_key: String = "|".join(sorted_ids)
		if triangle_keys.has(tri_key): return false
		triangle_keys[tri_key] = true
		for i in range(3):
			root_set[String(ids[i])] = true
			var edge_key: String = _arc_key(String(ids[i]), String(ids[(i + 1) % 3]))
			edge_incidence[edge_key] = int(edge_incidence.get(edge_key, 0)) + 1
		var projected_area: float = _projected_double_area(points, projection_axis)
		if not is_finite(projected_area) or projected_area * orientation <= 0.0: return false
	var actual_roots: Array[String] = []
	for root_id in root_set.keys(): actual_roots.append(String(root_id))
	actual_roots.sort()
	if actual_roots != expected_roots: return false
	for raw_edge in boundary_edges.keys():
		if int(edge_incidence.get(String(raw_edge), 0)) != 1: return false
	for raw_edge in edge_incidence.keys():
		var count: int = int(edge_incidence[raw_edge])
		if boundary_edges.has(String(raw_edge)):
			if count != 1: return false
		elif count != 2:
			return false
	return true

func _edge_occurrences(triangles: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for triangle_index in range(triangles.size()):
		var ids: Array = triangles[triangle_index].get("root_ids", [])
		for i in range(3):
			var left: String = String(ids[i])
			var right: String = String(ids[(i + 1) % 3])
			var key: String = _arc_key(left, right)
			if not result.has(key): result[key] = {"a": left, "b": right, "owners": []}
			result[key].owners.append(triangle_index)
	return result

func _new_diagonal_crosses_unrelated_edge(a_id: String, b_id: String, removed_edge: String, edges: Dictionary, root_points: Dictionary, projection_axis: int) -> bool:
	var a: Vector3 = root_points[a_id]
	var b: Vector3 = root_points[b_id]
	var pa: Vector2 = _project_world_point(a, projection_axis)
	var pb: Vector2 = _project_world_point(b, projection_axis)
	for raw_key in edges.keys():
		var key: String = String(raw_key)
		if key == removed_edge: continue
		var row: Dictionary = edges[key]
		var left: String = String(row.a); var right: String = String(row.b)
		if left in [a_id, b_id] or right in [a_id, b_id]: continue
		var pleft: Vector2 = _project_world_point(root_points[left], projection_axis)
		var pright: Vector2 = _project_world_point(root_points[right], projection_axis)
		if _segments_properly_intersect(pa, pb, pleft, pright): return true
	return false

func _root_point_map(triangles: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		var points: Array = triangle.get("points", [])
		for i in range(3):
			result[String(ids[i])] = points[i]
	return result

func _state_orientation(triangles: Array[Dictionary], projection_axis: int) -> float:
	if triangles.is_empty(): return 0.0
	var area: float = _projected_double_area(triangles[0].get("points", []), projection_axis)
	return 1.0 if area > 0.0 else -1.0

func _projected_orientation_valid(points: Array[Vector3], projection_axis: int, orientation: float) -> bool:
	return points.size() == 3 and _projected_double_area(points, projection_axis) * orientation > 0.0

func _projected_double_area(points: Array, projection_axis: int) -> float:
	if points.size() != 3: return NAN
	var a: Vector2 = _project_world_point(points[0], projection_axis)
	var b: Vector2 = _project_world_point(points[1], projection_axis)
	var c: Vector2 = _project_world_point(points[2], projection_axis)
	return (b - a).cross(c - a)

func _sorted_root_set(triangles: Array[Dictionary]) -> Array[String]:
	var seen: Dictionary = {}
	for triangle in triangles:
		for raw_id in triangle.get("root_ids", []): seen[String(raw_id)] = true
	var result: Array[String] = []
	for key in seen.keys(): result.append(String(key))
	result.sort()
	return result

func _quality(triangles: Array[Dictionary]) -> Dictionary:
	var minimum: float = INF
	var count: int = 0
	var rows: Array[Dictionary] = []
	for index in range(triangles.size()):
		var triangle: Dictionary = triangles[index]
		var cross: float = _cross_squared_from_triangle(triangle)
		minimum = minf(minimum, cross)
		if not is_finite(cross) or cross <= CUTOFF_SQUARED:
			count += 1
			rows.append({"triangle_index": index, "cross_squared": cross, "root_ids": triangle.get("root_ids", [])})
	return {"minimum_cross_squared": minimum, "subcutoff_count": count, "subcutoff": rows}

func _subcutoff_rows(triangles: Array[Dictionary]) -> Array[Dictionary]:
	return _quality(triangles).subcutoff

func _state_key(triangles: Array[Dictionary]) -> String:
	var canonical: Array[String] = []
	for triangle in triangles:
		var ids: Array[String] = [String(triangle.root_ids[0]), String(triangle.root_ids[1]), String(triangle.root_ids[2])]
		ids.sort()
		canonical.append("|".join(ids))
	canonical.sort()
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(("\n".join(canonical)).to_utf8_buffer())
	return context.finish().hex_encode()

func _segments_properly_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c: float = (b - a).cross(c - a)
	var ab_d: float = (b - a).cross(d - a)
	var cd_a: float = (d - c).cross(a - c)
	var cd_b: float = (d - c).cross(b - c)
	return ab_c * ab_d < 0.0 and cd_a * cd_b < 0.0

func _inc(counts: Dictionary, reason: String) -> void:
	counts[reason] = int(counts.get(reason, 0)) + 1
