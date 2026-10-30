extends RefCounted

const CUTOFF_SQUARED: float = 1.0e-12
const DOMAIN_SCHEMA: String = "P3.1.R10B.B1R.CandidateDomain.v1"
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const LIMITS: Dictionary = {
	"candidate_triangles": 62196,
	"search_nodes": 500000,
	"recursion_depth": 110,
	"wall_milliseconds": 120000,
	"intersection_checks": 2000000,
	"complete_solutions": 1,
	"estimated_state_bytes": 536870912
}

var _domain: Dictionary = {}
var _candidates: Array[Dictionary] = []
var _edge_to_candidates: Dictionary = {}
var _boundary_directions: Dictionary = {}
var _edge_counts: Dictionary = {}
var _edge_directions: Dictionary = {}
var _root_used: PackedByteArray = PackedByteArray()
var _selected: Array[int] = []
var _selected_flags: PackedByteArray = PackedByteArray()
var _edge_points: Dictionary = {}
var _projected: Array[Vector2] = []
var _nodes: int = 0
var _intersection_checks: int = 0
var _started_msec: int = 0
var _limit_reason: String = ""
var _solution: Array[int] = []
var _conflicts: Dictionary = {"edge_incidence": 0, "triangle_intersection": 0, "root_link": 0, "disconnected": 0}

func build_candidate_domain(geometry: Dictionary, identity: Dictionary, roi: Dictionary) -> Dictionary:
	var patch: Dictionary = _find_target_patch(geometry)
	if patch.is_empty(): return {"valid": false, "reason": "target_component_patch_missing"}
	var component_id: String = String(patch.get("component_id", ""))
	if component_id != "60,8,25|tet:0": return {"valid": false, "reason": "target_component_identity_mismatch"}
	var raw_triangles: Variant = patch.get("triangulation", {}).get("triangles", [])
	var raw_paths: Array = patch.get("boundary", {}).get("paths", [])
	if not raw_triangles is Array or raw_paths.size() != 1: return {"valid": false, "reason": "frozen_patch_domain_shape_invalid"}
	var raw_boundary: Variant = raw_paths[0].get("root_ids", [])
	if not raw_boundary is Array or raw_boundary.size() != 34: return {"valid": false, "reason": "frozen_boundary_root_count_mismatch", "count": raw_boundary.size() if raw_boundary is Array else -1}
	var point_by_id: Dictionary = {}
	for raw_triangle in raw_triangles:
		if not raw_triangle is Dictionary: return {"valid": false, "reason": "frozen_triangle_row_invalid"}
		var ids: Variant = raw_triangle.get("root_ids", [])
		var points: Variant = raw_triangle.get("points", [])
		if not ids is Array or not points is Array or ids.size() != 3 or points.size() != 3:
			return {"valid": false, "reason": "frozen_triangle_root_point_arity_invalid"}
		for index in range(3):
			var root_id: String = String(ids[index])
			if not (points[index] is Vector3) or not points[index].is_finite(): return {"valid": false, "reason": "frozen_root_nonfinite", "root_id": root_id}
			if point_by_id.has(root_id) and point_by_id[root_id] != points[index]: return {"valid": false, "reason": "frozen_root_position_disagreement", "root_id": root_id}
			point_by_id[root_id] = points[index]
	var root_ids: Array[String] = []
	for raw_id in point_by_id.keys(): root_ids.append(String(raw_id))
	root_ids.sort()
	if root_ids.size() != 73: return {"valid": false, "reason": "frozen_component_root_count_mismatch", "count": root_ids.size()}
	var root_index: Dictionary = {}
	var root_points: Array[Vector3] = []
	for index in range(root_ids.size()):
		root_index[root_ids[index]] = index
		root_points.append(point_by_id[root_ids[index]])
	var boundary_cycle: Array[int] = []
	var boundary_seen: Dictionary = {}
	for raw_id in raw_boundary:
		var root_id: String = String(raw_id)
		if not root_index.has(root_id) or boundary_seen.has(root_id): return {"valid": false, "reason": "boundary_root_missing_or_duplicated", "root_id": root_id}
		boundary_seen[root_id] = true
		boundary_cycle.append(int(root_index[root_id]))
	var source_polygon_set: Dictionary = {}
	for source_polygon_id in patch.get("source_polygon_ids", []): source_polygon_set[String(source_polygon_id)] = true
	if source_polygon_set.size() != 84: return {"valid": false, "reason": "source_polygon_owner_set_invalid", "count": source_polygon_set.size()}
	var orientation: Vector3 = Vector3.ZERO
	var orientation_samples: int = 0
	for raw_emitted in geometry.get("emitted_triangles", []):
		if not raw_emitted is Dictionary: continue
		var contributes_to_source: bool = source_polygon_set.has(String(raw_emitted.get("polygon_id", "")))
		if not contributes_to_source:
			for source_polygon_id in raw_emitted.get("source_polygon_ids", []):
				if source_polygon_set.has(String(source_polygon_id)):
					contributes_to_source = true
					break
		if not contributes_to_source: continue
		var normal: Variant = raw_emitted.get("normal", Vector3.ZERO)
		if normal is Vector3 and normal.is_finite():
			orientation += normal
			orientation_samples += 1
	if orientation_samples == 0 or not orientation.is_finite() or orientation.length_squared() == 0.0: return {"valid": false, "reason": "component_orientation_authority_invalid", "sample_count": orientation_samples, "source_polygon_count": source_polygon_set.size()}
	orientation = orientation.normalized()
	var candidate_config: RefCounted = CandidateD.new()
	candidate_config.call("configure_roi", roi)
	var grid_step: float = float(candidate_config.get("STEP"))
	if not is_finite(grid_step) or grid_step <= 0.0: return {"valid": false, "reason": "component_grid_step_invalid"}
	var source_polygon_ids: Array = patch.get("source_polygon_ids", []).duplicate()
	var source_cells: Dictionary = {}
	for polygon_id in source_polygon_ids:
		var cell_prefix: String = String(polygon_id).split("|", false, 1)[0]
		var cell_parts: PackedStringArray = cell_prefix.split(",")
		if cell_parts.size() != 3 or not cell_parts[0].is_valid_int() or not cell_parts[1].is_valid_int() or not cell_parts[2].is_valid_int():
			return {"valid": false, "reason": "source_polygon_owner_cell_invalid", "polygon_id": polygon_id}
		source_cells["%d,%d,%d" % [int(cell_parts[0]), int(cell_parts[1]), int(cell_parts[2])]] = true
	if source_cells.is_empty(): return {"valid": false, "reason": "source_component_owner_cells_empty"}
	var projection: Dictionary = _make_projection(root_points, boundary_cycle, orientation)
	if not bool(projection.get("valid", false)): return projection
	_projected = projection.projected
	boundary_cycle = projection.boundary_cycle
	var root_domain: Dictionary = _validate_roots_in_domain(_projected, boundary_cycle)
	if not bool(root_domain.get("valid", false)): return root_domain
	var edge_domain: Dictionary = _build_edge_domain(root_points.size(), _projected, boundary_cycle)
	if not bool(edge_domain.get("valid", false)): return edge_domain
	var candidate_result: Dictionary = _build_candidates(root_points, _projected, boundary_cycle, orientation, int(projection.orientation_sign), edge_domain.allowed, source_cells, grid_step)
	if not bool(candidate_result.get("valid", false)): return candidate_result
	var candidates: Array = candidate_result.candidates
	if candidates.size() > int(LIMITS.candidate_triangles): return {"valid": false, "reason": "candidate_triangle_limit_exceeded", "count": candidates.size(), "limit": LIMITS.candidate_triangles}
	var root_rows: Array[Dictionary] = []
	for index in range(root_ids.size()):
		var p: Vector3 = root_points[index]
		root_rows.append({"index": index, "id": root_ids[index], "xyz": [p.x, p.y, p.z]})
	var required_boundary_edges: Array = []
	for index in range(boundary_cycle.size()):
		var left: int = boundary_cycle[index]
		var right: int = boundary_cycle[(index + 1) % boundary_cycle.size()]
		required_boundary_edges.append([left, right])
	var candidate_triplets: Array = []
	var candidate_owner_cells: Array = []
	for candidate in candidates:
		candidate_triplets.append(candidate.root_indices)
		candidate_owner_cells.append(candidate.owner_cell)
	var source_cell_rows: Array[String] = []
	for cell_key in source_cells.keys(): source_cell_rows.append(String(cell_key))
	source_cell_rows.sort()
	var domain: Dictionary = {
		"schema": DOMAIN_SCHEMA,
		"identity": identity.duplicate(true),
		"component_id": component_id,
		"source_polygon_ids": source_polygon_ids,
		"source_polygon_count": source_polygon_ids.size(),
		"orientation_sample_count": orientation_samples,
		"source_cell_owners": source_cell_rows,
		"grid_step": grid_step,
		"source_root_count": root_rows.size(),
		"source_boundary_root_count": boundary_cycle.size(),
		"source_interior_root_count": root_rows.size() - boundary_cycle.size(),
		"projection_axis_dropped": int(projection.axis),
		"projection_orientation_sign": int(projection.orientation_sign),
		"orientation_toward_empty": [orientation.x, orientation.y, orientation.z],
		"root_rows": root_rows,
		"boundary_cycle": boundary_cycle,
		"required_boundary_edges": required_boundary_edges,
		"prohibited_edges": edge_domain.prohibited,
		"candidate_triplets_oriented": candidate_triplets,
		"candidate_owner_cells": candidate_owner_cells,
		"candidate_count": candidate_triplets.size(),
		"rejection_counts": {
			"duplicate_or_arity": int(candidate_result.duplicate_or_arity),
			"nonfinite": int(candidate_result.nonfinite),
			"fixed_cutoff": int(candidate_result.fixed_cutoff),
			"orientation": int(candidate_result.orientation),
			"domain_or_ownership": int(candidate_result.domain_or_ownership),
			"boundary_crossing": int(candidate_result.boundary_crossing)
		},
		"edge_rejection_counts": edge_domain.rejection_counts,
		"limits": LIMITS.duplicate(true),
		"search_contract": "complete deterministic exact-cover enumeration over the frozen admissible triangle set; any configured limit returns INCOMPLETE, never infeasible"
	}
	var domain_bytes: PackedByteArray = JSON.stringify(domain).to_utf8_buffer()
	return {"valid": true, "domain": domain, "domain_bytes": domain_bytes, "domain_sha256": _sha256(domain_bytes), "identity_sha256": _domain_identity_sha(domain), "metrics": {"candidate_count": candidates.size(), "root_count": root_rows.size(), "boundary_count": boundary_cycle.size(), "edge_count": root_rows.size() * (root_rows.size() - 1) / 2, "rejection_counts": domain.rejection_counts, "edge_rejection_counts": edge_domain.rejection_counts}}

func solve_domain(domain: Dictionary, expected_identity: Dictionary) -> Dictionary:
	_reset_solver_state()
	var load: Dictionary = _load_solver_domain(domain, expected_identity)
	if not bool(load.get("valid", false)): return load
	_root_used.resize(domain.root_rows.size())
	_root_used.fill(0)
	_selected_flags.resize(_candidates.size())
	_selected_flags.fill(0)
	_started_msec = Time.get_ticks_msec()
	var solved: bool = _search(0)
	var status: String = "SOLVED" if solved else ("INCOMPLETE_LIMIT" if not _limit_reason.is_empty() else "INFEASIBLE_EXHAUSTIVE_FROZEN_DOMAIN")
	var triangles: Array = []
	if solved:
		for candidate_index in _solution:
			var row: Dictionary = _candidates[candidate_index]
			triangles.append({"candidate_id": row.id, "root_indices": row.root_indices.duplicate(), "root_ids": row.root_ids.duplicate(), "edge_ids": row.edge_keys.duplicate(), "owner_cell": row.owner_cell.duplicate(), "cross_squared": row.cross_squared})
	return {"status": status, "valid": solved, "triangles": triangles, "search_complete": solved or _limit_reason.is_empty(), "search_exhaustive": not solved and _limit_reason.is_empty(), "limit_reason": _limit_reason, "nodes": _nodes, "intersection_checks": _intersection_checks, "elapsed_milliseconds": Time.get_ticks_msec() - _started_msec, "selected_triangle_count": triangles.size(), "candidate_count": _candidates.size(), "root_count": domain.root_rows.size(), "boundary_edge_count": domain.required_boundary_edges.size(), "expected_triangle_count": 2 * int(domain.root_rows.size()) - int(domain.source_boundary_root_count) - 2, "solutions": 1 if solved else 0, "conflicts": _conflicts.duplicate(true), "pruning": "sound edge-incidence, orientation, connectedness, vertex-link, fixed-root, no-crossing and no-overlap predicates; MRV only orders branches"}

func _find_target_patch(geometry: Dictionary) -> Dictionary:
	for raw_patch in geometry.get("component_reconstruction", {}).get("patches", []):
		if raw_patch is Dictionary and String(raw_patch.get("component_id", "")) == "60,8,25|tet:0": return raw_patch
	return {}

func _make_projection(points: Array[Vector3], boundary: Array[int], orientation: Vector3) -> Dictionary:
	var newell: Vector3 = Vector3.ZERO
	for index in range(boundary.size()):
		var current: Vector3 = points[boundary[index]]
		var next: Vector3 = points[boundary[(index + 1) % boundary.size()]]
		newell.x += (current.y - next.y) * (current.z + next.z)
		newell.y += (current.z - next.z) * (current.x + next.x)
		newell.z += (current.x - next.x) * (current.y + next.y)
	if not newell.is_finite() or newell.length_squared() == 0.0: return {"valid": false, "reason": "boundary_projection_normal_invalid"}
	var axis: int = 0
	if absf(newell.y) > absf(newell.x): axis = 1
	if absf(newell.z) > absf(newell[axis]): axis = 2
	var projected: Array[Vector2] = []
	for point in points:
		if axis == 0: projected.append(Vector2(point.y, point.z))
		elif axis == 1: projected.append(Vector2(point.x, point.z))
		else: projected.append(Vector2(point.x, point.y))
	var normal_axis: float = orientation[axis] * (-1.0 if axis == 1 else 1.0)
	if not is_finite(normal_axis) or normal_axis == 0.0: return {"valid": false, "reason": "orientation_authority_tangent_to_projection"}
	var orientation_sign: int = 1 if normal_axis > 0.0 else -1
	var area: float = _polygon_area2(projected, boundary)
	if not is_finite(area) or area == 0.0: return {"valid": false, "reason": "projected_boundary_area_invalid"}
	if (1 if area > 0.0 else -1) != orientation_sign:
		var reversed: Array[int] = [boundary[0]]
		for index in range(boundary.size() - 1, 0, -1): reversed.append(boundary[index])
		boundary = reversed
		area = _polygon_area2(projected, boundary)
	if (1 if area > 0.0 else -1) != orientation_sign: return {"valid": false, "reason": "boundary_orientation_normalization_failed"}
	if not _boundary_is_simple(projected, boundary): return {"valid": false, "reason": "projected_boundary_self_intersection"}
	return {"valid": true, "axis": axis, "orientation_sign": orientation_sign, "projected": projected, "boundary_cycle": boundary, "area2": area}

func _boundary_is_simple(points: Array[Vector2], boundary: Array[int]) -> bool:
	for left in range(boundary.size()):
		var a: int = boundary[left]
		var b: int = boundary[(left + 1) % boundary.size()]
		for right in range(left + 1, boundary.size()):
			if right == left or right == (left + 1) % boundary.size() or left == (right + 1) % boundary.size(): continue
			var c: int = boundary[right]
			var d: int = boundary[(right + 1) % boundary.size()]
			if _segments_intersect(points[a], points[b], points[c], points[d]): return false
	return true

func _validate_roots_in_domain(projected: Array[Vector2], boundary: Array[int]) -> Dictionary:
	var boundary_set: Dictionary = {}
	for index in boundary: boundary_set[index] = true
	for root_index in range(projected.size()):
		var on_boundary: bool = _point_on_boundary(projected[root_index], projected, boundary)
		if boundary_set.has(root_index):
			if not on_boundary: return {"valid": false, "reason": "boundary_root_not_on_frozen_boundary", "root_index": root_index}
		elif on_boundary or not _point_in_polygon(projected[root_index], projected, boundary):
			return {"valid": false, "reason": "interior_root_outside_or_on_component_boundary", "root_index": root_index}
		for prior in range(root_index):
			if projected[root_index] == projected[prior]: return {"valid": false, "reason": "distinct_roots_share_projected_coordinate", "root_indices": [prior, root_index]}
	return {"valid": true}

func _build_edge_domain(root_count: int, projected: Array[Vector2], boundary: Array[int]) -> Dictionary:
	var boundary_edges: Dictionary = {}
	for index in range(boundary.size()):
		var left: int = boundary[index]
		var right: int = boundary[(index + 1) % boundary.size()]
		boundary_edges[_edge_key(left, right, root_count)] = true
	var allowed: Dictionary = {}
	var prohibited: Array = []
	var crossing: int = 0
	var through_root: int = 0
	var duplicate: int = 0
	for left in range(root_count):
		for right in range(left + 1, root_count):
			var key: int = _edge_key(left, right, root_count)
			var reason: String = ""
			if projected[left] == projected[right]:
				reason = "duplicate_projection"
				duplicate += 1
			elif not boundary_edges.has(key):
				for edge_index in range(boundary.size()):
					var b0: int = boundary[edge_index]
					var b1: int = boundary[(edge_index + 1) % boundary.size()]
					if left == b0 or left == b1 or right == b0 or right == b1: continue
					if _segments_intersect(projected[left], projected[right], projected[b0], projected[b1]):
						reason = "crosses_fixed_boundary"
						crossing += 1
						break
				if reason.is_empty():
					for other in range(root_count):
						if other == left or other == right: continue
						if _point_on_segment(projected[other], projected[left], projected[right]):
							reason = "passes_through_required_root"
							through_root += 1
							break
			if reason.is_empty(): allowed[key] = true
			else: prohibited.append([left, right, reason])
	return {"valid": true, "allowed": allowed, "prohibited": prohibited, "rejection_counts": {"boundary_crossing": crossing, "passes_through_root": through_root, "duplicate_projection": duplicate}}

func _build_candidates(points: Array[Vector3], projected: Array[Vector2], boundary: Array[int], orientation: Vector3, orientation_sign: int, allowed_edges: Dictionary, source_cells: Dictionary, grid_step: float) -> Dictionary:
	var root_count: int = points.size()
	var candidates: Array[Dictionary] = []
	var duplicate_or_arity: int = 0
	var nonfinite: int = 0
	var cutoff: int = 0
	var orientation_rejected: int = 0
	var domain: int = 0
	var crossing: int = 0
	for a in range(root_count - 2):
		for b in range(a + 1, root_count - 1):
			for c in range(b + 1, root_count):
				var raw_points: Array[Vector3] = [points[a], points[b], points[c]]
				if raw_points.size() != 3 or a == b or b == c or a == c:
					duplicate_or_arity += 1
					continue
				if not raw_points[0].is_finite() or not raw_points[1].is_finite() or not raw_points[2].is_finite():
					nonfinite += 1
					continue
				var cross3: Vector3 = (raw_points[1] - raw_points[0]).cross(raw_points[2] - raw_points[0])
				var cross_squared: float = cross3.length_squared()
				if not is_finite(cross_squared):
					nonfinite += 1
					continue
				if cross_squared <= CUTOFF_SQUARED:
					cutoff += 1
					continue
				var oriented: Array[int] = [a, b, c]
				var orientation_dot: float = cross3.dot(orientation)
				if not is_finite(orientation_dot) or orientation_dot == 0.0:
					orientation_rejected += 1
					continue
				if orientation_dot < 0.0:
					oriented[1] = c
					oriented[2] = b
				var area2: float = _cross2(projected[oriented[0]], projected[oriented[1]], projected[oriented[2]])
				if not is_finite(area2) or area2 == 0.0 or (1 if area2 > 0.0 else -1) != orientation_sign:
					orientation_rejected += 1
					continue
				var edge_keys: Array[int] = []
				var edge_dirs: Array[int] = []
				var edge_valid: bool = true
				for edge_index in range(3):
					var u: int = oriented[edge_index]
					var v: int = oriented[(edge_index + 1) % 3]
					var key: int = _edge_key(u, v, root_count)
					if not allowed_edges.has(key):
						edge_valid = false
						break
					edge_keys.append(key)
					edge_dirs.append(1 if u < v else -1)
				if not edge_valid:
					if _edge_crosses_boundary(oriented[0], oriented[1], projected, boundary) or _edge_crosses_boundary(oriented[1], oriented[2], projected, boundary) or _edge_crosses_boundary(oriented[2], oriented[0], projected, boundary): crossing += 1
					else: domain += 1
					continue
				var center: Vector2 = (projected[oriented[0]] + projected[oriented[1]] + projected[oriented[2]]) / 3.0
				if not _point_in_polygon(center, projected, boundary):
					domain += 1
					continue
				var center3: Vector3 = (points[oriented[0]] + points[oriented[1]] + points[oriented[2]]) / 3.0
				var owner_cell: Vector3i = Vector3i(floori(center3.x / grid_step), floori(center3.y / grid_step), floori(center3.z / grid_step))
				var owner_key: String = "%d,%d,%d" % [owner_cell.x, owner_cell.y, owner_cell.z]
				if not source_cells.has(owner_key):
					domain += 1
					continue
				var obstructed: bool = false
				for other in range(root_count):
					if other == a or other == b or other == c: continue
					if _point_in_triangle_inclusive(projected[other], projected[oriented[0]], projected[oriented[1]], projected[oriented[2]]):
						obstructed = true
						break
				if obstructed:
					domain += 1
					continue
				var id_text: String = "%d:%d:%d" % [a, b, c]
				candidates.append({"id": id_text, "root_indices": oriented, "edge_keys": edge_keys, "edge_directions": edge_dirs, "owner_cell": [owner_cell.x, owner_cell.y, owner_cell.z], "cross_squared": cross_squared})
	if candidates.size() > int(LIMITS.candidate_triangles): return {"valid": false, "reason": "candidate_triangle_limit_exceeded", "count": candidates.size()}
	return {"valid": true, "candidates": candidates, "duplicate_or_arity": duplicate_or_arity, "nonfinite": nonfinite, "fixed_cutoff": cutoff, "orientation": orientation_rejected, "domain_or_ownership": domain, "boundary_crossing": crossing}

func _load_solver_domain(domain: Dictionary, expected_identity: Dictionary) -> Dictionary:
	if String(domain.get("schema", "")) != DOMAIN_SCHEMA: return {"valid": false, "reason": "candidate_domain_schema_mismatch"}
	if domain.get("identity", {}) != expected_identity: return {"valid": false, "reason": "candidate_domain_identity_mismatch"}
	if int(domain.get("source_root_count", -1)) != 73 or int(domain.get("source_boundary_root_count", -1)) != 34 or int(domain.get("source_interior_root_count", -1)) != 39:
		return {"valid": false, "reason": "candidate_domain_frozen_counts_mismatch"}
	if int(domain.get("orientation_sample_count", 0)) <= 0: return {"valid": false, "reason": "candidate_domain_orientation_sample_count_invalid"}
	var raw_roots: Variant = domain.get("root_rows", [])
	var raw_candidates: Variant = domain.get("candidate_triplets_oriented", [])
	var raw_owners: Variant = domain.get("candidate_owner_cells", [])
	var raw_boundary: Variant = domain.get("required_boundary_edges", [])
	var raw_source_polygons: Variant = domain.get("source_polygon_ids", [])
	var raw_source_cells: Variant = domain.get("source_cell_owners", [])
	if not raw_roots is Array or not raw_candidates is Array or not raw_owners is Array or not raw_boundary is Array or not raw_source_polygons is Array or not raw_source_cells is Array: return {"valid": false, "reason": "candidate_domain_arrays_invalid"}
	if raw_roots.size() != 73 or raw_boundary.size() != 34 or raw_candidates.size() > int(LIMITS.candidate_triangles): return {"valid": false, "reason": "candidate_domain_limits_invalid"}
	if raw_source_polygons.size() != 84 or int(domain.get("source_polygon_count", -1)) != raw_source_polygons.size(): return {"valid": false, "reason": "candidate_domain_source_polygon_count_mismatch"}
	if int(domain.get("candidate_count", -1)) != raw_candidates.size(): return {"valid": false, "reason": "candidate_domain_candidate_count_mismatch"}
	if raw_owners.size() != raw_candidates.size(): return {"valid": false, "reason": "candidate_domain_owner_row_count_mismatch"}
	_domain = domain
	var root_points: Array[Vector3] = []
	var root_name_seen: Dictionary = {}
	for index in range(raw_roots.size()):
		var row: Variant = raw_roots[index]
		if not row is Dictionary or int(row.get("index", -1)) != index or not row.get("xyz", []) is Array or row.xyz.size() != 3:
			return {"valid": false, "reason": "candidate_domain_root_row_invalid", "root_index": index}
		var root_name: String = String(row.get("id", ""))
		if root_name.is_empty() or root_name_seen.has(root_name): return {"valid": false, "reason": "candidate_domain_root_identity_invalid", "root_index": index}
		root_name_seen[root_name] = true
		var p: Vector3 = Vector3(float(row.xyz[0]), float(row.xyz[1]), float(row.xyz[2]))
		if not p.is_finite(): return {"valid": false, "reason": "candidate_domain_nonfinite_root", "root_index": index}
		root_points.append(p)
	var boundary: Array[int] = []
	for raw_edge in raw_boundary:
		if not raw_edge is Array or raw_edge.size() != 2: return {"valid": false, "reason": "candidate_domain_boundary_edge_invalid"}
		var a: int = int(raw_edge[0]); var b: int = int(raw_edge[1])
		if a < 0 or b < 0 or a >= root_points.size() or b >= root_points.size() or a == b: return {"valid": false, "reason": "candidate_domain_boundary_index_invalid"}
		if boundary.is_empty(): boundary.append(a)
		elif boundary[boundary.size() - 1] != a: return {"valid": false, "reason": "candidate_domain_boundary_not_contiguous"}
		boundary.append(b)
	if boundary.size() != 35 or boundary[0] != boundary[boundary.size() - 1]: return {"valid": false, "reason": "candidate_domain_boundary_not_closed"}
	boundary.resize(34)
	var axis: int = int(domain.get("projection_axis_dropped", -1))
	if axis < 0 or axis > 2: return {"valid": false, "reason": "candidate_domain_projection_axis_invalid"}
	for p in root_points:
		if axis == 0: _projected.append(Vector2(p.y, p.z))
		elif axis == 1: _projected.append(Vector2(p.x, p.z))
		else: _projected.append(Vector2(p.x, p.y))
	var normal_raw: Array = domain.get("orientation_toward_empty", [])
	if normal_raw.size() != 3: return {"valid": false, "reason": "candidate_domain_orientation_invalid"}
	var orientation: Vector3 = Vector3(float(normal_raw[0]), float(normal_raw[1]), float(normal_raw[2]))
	if not orientation.is_finite() or orientation.length_squared() == 0.0: return {"valid": false, "reason": "candidate_domain_orientation_invalid"}
	var grid_step: float = float(domain.get("grid_step", 0.0))
	if not is_finite(grid_step) or grid_step <= 0.0: return {"valid": false, "reason": "candidate_domain_grid_step_invalid"}
	var source_cells: Dictionary = {}
	var source_polygon_seen: Dictionary = {}
	for polygon_id in raw_source_polygons:
		var polygon_text: String = String(polygon_id)
		if polygon_text.is_empty() or source_polygon_seen.has(polygon_text): return {"valid": false, "reason": "candidate_domain_duplicate_source_polygon"}
		source_polygon_seen[polygon_text] = true
		var separator: int = polygon_text.find("|tet:")
		if separator <= 0 or polygon_text.substr(separator + 5).is_empty() or not polygon_text.substr(separator + 5).is_valid_int(): return {"valid": false, "reason": "candidate_domain_source_polygon_id_invalid"}
		var cell_parts: PackedStringArray = polygon_text.substr(0, separator).split(",")
		if cell_parts.size() != 3 or not cell_parts[0].is_valid_int() or not cell_parts[1].is_valid_int() or not cell_parts[2].is_valid_int(): return {"valid": false, "reason": "candidate_domain_source_polygon_owner_invalid"}
		source_cells["%d,%d,%d" % [int(cell_parts[0]), int(cell_parts[1]), int(cell_parts[2])]] = true
	var serialized_source_cells: Dictionary = {}
	for cell_key in raw_source_cells:
		var key: String = String(cell_key)
		if serialized_source_cells.has(key): return {"valid": false, "reason": "candidate_domain_duplicate_source_owner"}
		serialized_source_cells[key] = true
	if source_cells != serialized_source_cells: return {"valid": false, "reason": "candidate_domain_source_owner_set_mismatch"}
	if source_cells.is_empty(): return {"valid": false, "reason": "candidate_domain_source_cells_empty"}
	var norm: Dictionary = _make_projection(root_points, boundary, orientation.normalized())
	if not bool(norm.get("valid", false)) or int(norm.axis) != axis: return {"valid": false, "reason": "candidate_domain_projection_revalidation_failed"}
	_projected = norm.projected
	var closed_boundary: Array[int] = norm.boundary_cycle
	if closed_boundary != boundary: return {"valid": false, "reason": "candidate_domain_boundary_orientation_mismatch"}
	var edge_domain: Dictionary = _build_edge_domain(root_points.size(), _projected, boundary)
	if not bool(edge_domain.get("valid", false)): return {"valid": false, "reason": "candidate_domain_boundary_edge_revalidation_failed", "detail": edge_domain}
	var allowed_edges: Dictionary = edge_domain.allowed
	var seen_boundary: Dictionary = {}
	for row in raw_boundary:
		var a: int = int(row[0]); var b: int = int(row[1])
		var key: int = _edge_key(a, b, 73)
		if seen_boundary.has(key): return {"valid": false, "reason": "candidate_domain_duplicate_boundary_edge"}
		seen_boundary[key] = true
		_boundary_directions[key] = 1 if a < b else -1
		_edge_points[key] = [a, b]
	var seen: Dictionary = {}
	for candidate_index in range(raw_candidates.size()):
		var raw: Variant = raw_candidates[candidate_index]
		if not raw is Array or raw.size() != 3: return {"valid": false, "reason": "candidate_domain_triangle_arity_invalid", "candidate": candidate_index}
		var ids: Array[int] = [int(raw[0]), int(raw[1]), int(raw[2])]
		if ids[0] < 0 or ids[1] < 0 or ids[2] < 0 or ids[0] >= 73 or ids[1] >= 73 or ids[2] >= 73 or ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]: return {"valid": false, "reason": "candidate_domain_triangle_indices_invalid", "candidate": candidate_index}
		var sorted: Array[int] = ids.duplicate(); sorted.sort()
		var id: String = "%d:%d:%d" % [sorted[0], sorted[1], sorted[2]]
		if seen.has(id): return {"valid": false, "reason": "candidate_domain_duplicate_triangle", "candidate_id": id}
		seen[id] = true
		var cross3: Vector3 = (root_points[ids[1]] - root_points[ids[0]]).cross(root_points[ids[2]] - root_points[ids[0]])
		var cross_squared: float = cross3.length_squared()
		if not is_finite(cross_squared) or cross_squared <= CUTOFF_SQUARED: return {"valid": false, "reason": "candidate_domain_cutoff_violation", "candidate_id": id, "cross_squared": cross_squared}
		if cross3.dot(orientation) <= 0.0: return {"valid": false, "reason": "candidate_domain_orientation_violation", "candidate_id": id}
		var centroid: Vector3 = (root_points[ids[0]] + root_points[ids[1]] + root_points[ids[2]]) / 3.0
		var owner: Vector3i = Vector3i(floori(centroid.x / grid_step), floori(centroid.y / grid_step), floori(centroid.z / grid_step))
		var owner_key: String = "%d,%d,%d" % [owner.x, owner.y, owner.z]
		var owner_row: Variant = raw_owners[candidate_index]
		if not owner_row is Array or owner_row.size() != 3 or int(owner_row[0]) != owner.x or int(owner_row[1]) != owner.y or int(owner_row[2]) != owner.z or not source_cells.has(owner_key):
			return {"valid": false, "reason": "candidate_domain_half_open_owner_mismatch", "candidate_id": id, "owner_cell": owner_key}
		var projected_centroid: Vector2 = (_projected[ids[0]] + _projected[ids[1]] + _projected[ids[2]]) / 3.0
		if not _point_in_polygon(projected_centroid, _projected, boundary): return {"valid": false, "reason": "candidate_domain_triangle_centroid_outside", "candidate_id": id}
		for edge_index in range(3):
			var edge_key: int = _edge_key(ids[edge_index], ids[(edge_index + 1) % 3], 73)
			if not allowed_edges.has(edge_key): return {"valid": false, "reason": "candidate_domain_illegal_edge", "candidate_id": id, "edge": edge_key}
		for other_root in range(73):
			if ids.has(other_root): continue
			if _point_in_triangle_inclusive(_projected[other_root], _projected[ids[0]], _projected[ids[1]], _projected[ids[2]]):
				return {"valid": false, "reason": "candidate_domain_triangle_obstructed_by_root", "candidate_id": id, "root_index": other_root}
		var edges: Array[int] = []
		var directions: Array[int] = []
		for edge_index in range(3):
			var u: int = ids[edge_index]; var v: int = ids[(edge_index + 1) % 3]
			var key: int = _edge_key(u, v, 73)
			edges.append(key); directions.append(1 if u < v else -1)
			if not _edge_points.has(key): _edge_points[key] = [mini(u, v), maxi(u, v)]
		var root_names: Array[String] = [String(raw_roots[ids[0]].get("id", "")), String(raw_roots[ids[1]].get("id", "")), String(raw_roots[ids[2]].get("id", ""))]
		_candidates.append({"id": id, "root_indices": ids, "root_ids": root_names, "edge_keys": edges, "edge_directions": directions, "owner_cell": owner_row.duplicate(), "cross_squared": cross_squared})
	for candidate_index in range(_candidates.size()):
		var candidate: Dictionary = _candidates[candidate_index]
		for edge_index in range(3):
			var key: int = candidate.edge_keys[edge_index]
			if not _edge_to_candidates.has(key): _edge_to_candidates[key] = []
			_edge_to_candidates[key].append(candidate_index)
	var estimate: int = _candidates.size() * 192 + int(_edge_to_candidates.size()) * 96
	if estimate > int(LIMITS.estimated_state_bytes): return {"valid": false, "reason": "estimated_solver_state_memory_limit", "estimated_bytes": estimate, "limit": LIMITS.estimated_state_bytes}
	return {"valid": true, "candidate_count": _candidates.size(), "root_count": root_points.size(), "estimated_state_bytes": estimate}

func _reset_solver_state() -> void:
	_domain.clear(); _candidates.clear(); _edge_to_candidates.clear(); _boundary_directions.clear(); _edge_counts.clear(); _edge_directions.clear(); _root_used.clear(); _selected.clear(); _selected_flags.clear(); _edge_points.clear(); _projected.clear()
	_nodes = 0; _intersection_checks = 0; _started_msec = 0; _limit_reason = ""; _solution.clear(); _conflicts = {"edge_incidence": 0, "triangle_intersection": 0, "root_link": 0, "disconnected": 0}

func _search(depth: int) -> bool:
	_nodes += 1
	if _nodes > int(LIMITS.search_nodes): _limit_reason = "search_node_limit"; return false
	if depth > int(LIMITS.recursion_depth): _limit_reason = "recursion_depth_limit"; return false
	if (_nodes & 63) == 0 and Time.get_ticks_msec() - _started_msec > int(LIMITS.wall_milliseconds): _limit_reason = "wall_time_limit"; return false
	if _intersection_checks > int(LIMITS.intersection_checks): _limit_reason = "intersection_check_limit"; return false
	var edge_choice: int = -1
	var choices: Array[int] = []
	var best_count: int = 2147483647
	var open_keys: Array[int] = []
	for raw_key in _boundary_directions.keys():
		var key: int = int(raw_key)
		if int(_edge_counts.get(key, 0)) == 0: open_keys.append(key)
	for raw_key in _edge_counts.keys():
		var key: int = int(raw_key)
		if not _boundary_directions.has(key) and int(_edge_counts.get(key, 0)) == 1: open_keys.append(key)
	open_keys.sort()
	for key in open_keys:
		var available: Array[int] = []
		for candidate_index in _edge_to_candidates.get(key, []):
			if _locally_available(int(candidate_index)): available.append(int(candidate_index))
		if available.is_empty(): return false
		if available.size() < best_count:
			best_count = available.size(); edge_choice = key; choices = available
	if edge_choice < 0:
		var expected_triangles: int = 2 * int(_domain.root_rows.size()) - int(_domain.source_boundary_root_count) - 2
		if _selected.size() != expected_triangles: return false
		for count in _root_used:
			if count == 0: return false
		for key in _boundary_directions.keys():
			if int(_edge_counts.get(key, 0)) != 1: return false
		for key in _edge_counts.keys():
			if not _boundary_directions.has(key) and int(_edge_counts[key]) != 2: return false
		if not _selected_vertex_manifold():
			_conflicts.root_link = int(_conflicts.root_link) + 1
			return false
		if not _selected_connected():
			_conflicts.disconnected = int(_conflicts.disconnected) + 1
			return false
		_solution = _selected.duplicate()
		return true
	for candidate_index in choices:
		if _limit_reason != "": return false
		var added: Dictionary = _add_candidate(candidate_index)
		if not bool(added.get("valid", false)):
			if String(added.get("reason", "")) == "crossing_or_overlap": _conflicts.triangle_intersection = int(_conflicts.triangle_intersection) + 1
			else: _conflicts.edge_incidence = int(_conflicts.edge_incidence) + 1
			continue
		if _search(depth + 1): return true
		_remove_candidate(candidate_index, added)
	return false

func _selected_connected() -> bool:
	if _selected.size() <= 1: return true
	var edge_users: Dictionary = {}
	for candidate_index in _selected:
		for edge_key in _candidates[candidate_index].edge_keys:
			if not edge_users.has(edge_key): edge_users[edge_key] = []
			edge_users[edge_key].append(candidate_index)
	var neighbors: Dictionary = {}
	for candidate_index in _selected: neighbors[candidate_index] = {}
	for edge_key in edge_users:
		var users: Array = edge_users[edge_key]
		if users.size() == 2:
			neighbors[users[0]][users[1]] = true
			neighbors[users[1]][users[0]] = true
	var reached: Dictionary = {}
	var queue: Array = [_selected[0]]
	reached[_selected[0]] = true
	var cursor: int = 0
	while cursor < queue.size():
		var current: int = int(queue[cursor]); cursor += 1
		for next_id in neighbors[current]:
			if reached.has(next_id): continue
			reached[next_id] = true; queue.append(next_id)
	return reached.size() == _selected.size()

func _selected_vertex_manifold() -> bool:
	var boundary_vertices: Dictionary = {}
	for edge_key in _boundary_directions:
		var pair: Array = _edge_points[edge_key]
		boundary_vertices[pair[0]] = true; boundary_vertices[pair[1]] = true
	for vertex in range(_root_used.size()):
		if int(_root_used[vertex]) == 0: return false
		var incident: Array[int] = []
		for candidate_index in _selected:
			if _candidates[candidate_index].root_indices.has(vertex): incident.append(candidate_index)
		var graph: Dictionary = {}
		for candidate_index in incident: graph[candidate_index] = {}
		var boundary_degree: int = 0
		for edge_key in _edge_points:
			var pair: Array = _edge_points[edge_key]
			if int(pair[0]) != vertex and int(pair[1]) != vertex: continue
			var count: int = int(_edge_counts.get(edge_key, 0))
			if _boundary_directions.has(edge_key):
				if count != 1: return false
				boundary_degree += 1
			elif count == 2:
				var users: Array = []
				for candidate_index in incident:
					if _candidates[candidate_index].edge_keys.has(edge_key): users.append(candidate_index)
				if users.size() != 2: return false
				graph[users[0]][users[1]] = true; graph[users[1]][users[0]] = true
			else:
				return false
		if boundary_vertices.has(vertex):
			if boundary_degree != 2: return false
		else:
			if boundary_degree != 0: return false
		var degree_one_count: int = 0
		for candidate_index in incident:
			var degree: int = graph[candidate_index].size()
			if boundary_vertices.has(vertex):
				if degree > 2: return false
				if degree == 1: degree_one_count += 1
			else:
				if degree != 2: return false
		if boundary_vertices.has(vertex) and incident.size() > 1 and degree_one_count != 2: return false
		if incident.is_empty(): return false
		var seen_triangles: Dictionary = {}
		var queue: Array = [incident[0]]
		seen_triangles[incident[0]] = true
		var cursor: int = 0
		while cursor < queue.size():
			var current: int = int(queue[cursor]); cursor += 1
			for next_id in graph[current]:
				if seen_triangles.has(next_id): continue
				seen_triangles[next_id] = true; queue.append(next_id)
		if seen_triangles.size() != incident.size(): return false
	return true

func _locally_available(candidate_index: int) -> bool:
	if candidate_index < 0 or candidate_index >= _candidates.size() or _selected_flags[candidate_index] != 0: return false
	var candidate: Dictionary = _candidates[candidate_index]
	for edge_index in range(3):
		var key: int = candidate.edge_keys[edge_index]
		var count: int = int(_edge_counts.get(key, 0))
		var direction: int = int(candidate.edge_directions[edge_index])
		if _boundary_directions.has(key):
			if count != 0 or direction != int(_boundary_directions[key]): return false
		elif count >= 2 or (count == 1 and direction == int(_edge_directions.get(key, 0))):
			return false
	return true

func _add_candidate(candidate_index: int) -> Dictionary:
	if not _locally_available(candidate_index): return {"valid": false, "reason": "edge_incidence_or_orientation_conflict"}
	var candidate: Dictionary = _candidates[candidate_index]
	for selected_index in _selected:
		if not _triangles_compatible(candidate, _candidates[selected_index]): return {"valid": false, "reason": "crossing_or_overlap"}
	var old_counts: Array[int] = []
	var old_directions: Array[int] = []
	for edge_index in range(3):
		var key: int = candidate.edge_keys[edge_index]
		old_counts.append(int(_edge_counts.get(key, 0)))
		old_directions.append(int(_edge_directions.get(key, 0)))
		_edge_counts[key] = old_counts[edge_index] + 1
		_edge_directions[key] = int(candidate.edge_directions[edge_index])
	for root_index in candidate.root_indices: _root_used[int(root_index)] += 1
	_selected.append(candidate_index); _selected_flags[candidate_index] = 1
	return {"valid": true, "old_counts": old_counts, "old_directions": old_directions}

func _remove_candidate(candidate_index: int, state: Dictionary) -> void:
	var candidate: Dictionary = _candidates[candidate_index]
	for root_index in candidate.root_indices: _root_used[int(root_index)] -= 1
	_selected_flags[candidate_index] = 0
	_selected.pop_back()
	for edge_index in range(3):
		var key: int = candidate.edge_keys[edge_index]
		var old_count: int = int(state.old_counts[edge_index])
		if old_count == 0:
			_edge_counts.erase(key); _edge_directions.erase(key)
		else:
			_edge_counts[key] = old_count
			_edge_directions[key] = int(state.old_directions[edge_index])

func _triangles_compatible(a: Dictionary, b: Dictionary) -> bool:
	var ai: Array = a.root_indices; var bi: Array = b.root_indices
	for edge_a in range(3):
		var a0: int = int(ai[edge_a]); var a1: int = int(ai[(edge_a + 1) % 3])
		for edge_b in range(3):
			_intersection_checks += 1
			if _intersection_checks > int(LIMITS.intersection_checks): _limit_reason = "intersection_check_limit"; return false
			var b0: int = int(bi[edge_b]); var b1: int = int(bi[(edge_b + 1) % 3])
			if (a0 == b0 or a0 == b1 or a1 == b0 or a1 == b1): continue
			if _segments_intersect(_projected[a0], _projected[a1], _projected[b0], _projected[b1]): return false
	var a_center: Vector2 = (_projected[int(ai[0])] + _projected[int(ai[1])] + _projected[int(ai[2])]) / 3.0
	var b_center: Vector2 = (_projected[int(bi[0])] + _projected[int(bi[1])] + _projected[int(bi[2])]) / 3.0
	if _point_in_triangle_strict(a_center, _projected[int(bi[0])], _projected[int(bi[1])], _projected[int(bi[2])]): return false
	if _point_in_triangle_strict(b_center, _projected[int(ai[0])], _projected[int(ai[1])], _projected[int(ai[2])]): return false
	return true

func _edge_key(a: int, b: int, root_count: int) -> int:
	var lo: int = mini(a, b); var hi: int = maxi(a, b)
	return lo * root_count + hi

func _edge_crosses_boundary(a: int, b: int, points: Array[Vector2], boundary: Array[int]) -> bool:
	for index in range(boundary.size()):
		var c: int = boundary[index]; var d: int = boundary[(index + 1) % boundary.size()]
		if a == c or a == d or b == c or b == d: continue
		if _segments_intersect(points[a], points[b], points[c], points[d]): return true
	return false

func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c: float = _cross2(a, b, c); var ab_d: float = _cross2(a, b, d)
	var cd_a: float = _cross2(c, d, a); var cd_b: float = _cross2(c, d, b)
	if ((ab_c > 0.0 and ab_d < 0.0) or (ab_c < 0.0 and ab_d > 0.0)) and ((cd_a > 0.0 and cd_b < 0.0) or (cd_a < 0.0 and cd_b > 0.0)): return true
	return (ab_c == 0.0 and _point_on_segment(c, a, b)) or (ab_d == 0.0 and _point_on_segment(d, a, b)) or (cd_a == 0.0 and _point_on_segment(a, c, d)) or (cd_b == 0.0 and _point_on_segment(b, c, d))

func _point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> bool:
	if _cross2(a, b, p) != 0.0: return false
	return p.x >= minf(a.x, b.x) and p.x <= maxf(a.x, b.x) and p.y >= minf(a.y, b.y) and p.y <= maxf(a.y, b.y)

func _point_on_boundary(p: Vector2, points: Array[Vector2], boundary: Array[int]) -> bool:
	for index in range(boundary.size()):
		if _point_on_segment(p, points[boundary[index]], points[boundary[(index + 1) % boundary.size()]]): return true
	return false

func _point_in_polygon(p: Vector2, points: Array[Vector2], boundary: Array[int]) -> bool:
	var inside: bool = false
	for index in range(boundary.size()):
		var a: Vector2 = points[boundary[index]]; var b: Vector2 = points[boundary[(index + 1) % boundary.size()]]
		if _point_on_segment(p, a, b): return true
		if (a.y > p.y) != (b.y > p.y):
			var x_cross: float = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if p.x < x_cross: inside = not inside
	return inside

func _point_in_triangle_inclusive(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab: float = _cross2(a, b, p); var bc: float = _cross2(b, c, p); var ca: float = _cross2(c, a, p)
	return (ab >= 0.0 and bc >= 0.0 and ca >= 0.0) or (ab <= 0.0 and bc <= 0.0 and ca <= 0.0)

func _point_in_triangle_strict(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab: float = _cross2(a, b, p); var bc: float = _cross2(b, c, p); var ca: float = _cross2(c, a, p)
	return (ab > 0.0 and bc > 0.0 and ca > 0.0) or (ab < 0.0 and bc < 0.0 and ca < 0.0)

func _polygon_area2(points: Array[Vector2], boundary: Array[int]) -> float:
	var area: float = 0.0
	for index in range(boundary.size()): area += points[boundary[index]].cross(points[boundary[(index + 1) % boundary.size()]])
	return area

func _cross2(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)

func _sha256(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().to_lower()

func _domain_identity_sha(domain: Dictionary) -> String:
	var identity: Dictionary = {"schema": domain.schema, "identity": domain.identity, "component_id": domain.component_id, "source_polygon_ids": domain.source_polygon_ids, "source_polygon_count": domain.source_polygon_count, "orientation_sample_count": domain.orientation_sample_count, "source_cell_owners": domain.source_cell_owners, "grid_step": domain.grid_step, "source_root_count": domain.source_root_count, "source_boundary_root_count": domain.source_boundary_root_count, "source_interior_root_count": domain.source_interior_root_count, "projection_axis_dropped": domain.projection_axis_dropped, "projection_orientation_sign": domain.projection_orientation_sign, "orientation_toward_empty": domain.orientation_toward_empty, "root_rows": domain.root_rows, "boundary_cycle": domain.boundary_cycle, "required_boundary_edges": domain.required_boundary_edges, "prohibited_edges": domain.prohibited_edges, "candidate_count": domain.candidate_count, "candidate_triplets_oriented": domain.candidate_triplets_oriented, "candidate_owner_cells": domain.candidate_owner_cells, "rejection_counts": domain.rejection_counts, "edge_rejection_counts": domain.edge_rejection_counts, "limits": domain.limits, "search_contract": domain.search_contract}
	return _sha256(JSON.stringify(identity).to_utf8_buffer())
