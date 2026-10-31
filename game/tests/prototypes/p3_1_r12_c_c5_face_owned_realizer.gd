extends "res://tests/prototypes/p3_1_r12_c_c4_patch_realizer.gd"

## R12-C5: bounded face-owned 2-2 patch experiment allowing noncoplanar roots.
## Source roots, density samples, and the canonical volume remain unchanged.

func realize(graph: Dictionary, values: PackedFloat32Array, roi: Dictionary, expected_topology_sha: String, expected_graph_fingerprint_sha: String = "") -> Dictionary:
	var result: Dictionary = super.realize(graph, values, roi, expected_topology_sha, expected_graph_fingerprint_sha)
	if not bool(result.get("valid", false)):
		var reason: String = String(result.get("reason", "c4_realizer_invalid"))
		if reason.begins_with("c4_"): reason = "c5_" + reason.substr(3)
		result["reason"] = reason
		return result
	result["hypothesis"] = "C5_FACE_OWNED_NONCOPLANAR_LOCAL_PATCH"
	result["geometry_error_contract"] = "NOT_FULLY_MEASURED_NO_APPROVED_TOLERANCE"
	result["canonical_surface_deviation_measured"] = false
	result["vertex_positions_changed"] = false
	var maximum_midpoint_displacement: float = 0.0
	for flip in result.get("applied_flips", []):
		maximum_midpoint_displacement = maxf(maximum_midpoint_displacement, float(flip.get("diagonal_midpoint_displacement", 0.0)))
	result["maximum_diagonal_midpoint_displacement"] = maximum_midpoint_displacement
	for triangle in result.get("emitted_triangles", []):
		if String(triangle.get("construction", "")).begins_with("R12C4_"):
			triangle["construction"] = "R12C5_FACE_OWNED_NONCOPLANAR_LOCAL_PATCH"
	return result

func _make_flip(edge_key: String, first: Dictionary, second: Dictionary, tri_a: Dictionary, tri_b: Dictionary, triangles: Array[Dictionary], edge_index: Dictionary, polygon_toward: Dictionary, polygon_by_id: Dictionary, topology_arc_keys: Dictionary, flip_index: int) -> Dictionary:
	var u_id: String = String(first.u); var v_id: String = String(first.v)
	var p_id: String = String(first.opposite); var q_id: String = String(second.opposite)
	if u_id == v_id or p_id == q_id or [u_id, v_id, p_id, q_id].size() != 4: return {"valid": false, "reason": "four_distinct_vertices_required"}
	var roots: Dictionary = {}
	for triangle in triangles:
		for index in range(3): roots[String(triangle.root_ids[index])] = triangle.points[index]
	if not roots.has(p_id) or not roots.has(q_id): return {"valid": false, "reason": "opposite_root_missing"}
	var u: Vector3 = roots[u_id]; var v: Vector3 = roots[v_id]; var p: Vector3 = roots[p_id]; var q: Vector3 = roots[q_id]
	var normal: Vector3 = (v - u).cross(p - u)
	if not normal.is_finite() or normal.length_squared() == 0.0: return {"valid": false, "reason": "source_plane_degenerate"}
	var determinant: float = normal.dot(q - u)
	if not is_finite(determinant): return {"valid": false, "reason": "nonfinite_coplanarity_diagnostic"}
	var side_p: float = normal.dot((v - u).cross(p - u))
	var side_q: float = normal.dot((v - u).cross(q - u))
	if side_p == 0.0 or side_q == 0.0 or signf(side_p) == signf(side_q): return {"valid": false, "reason": "opposite_vertices_not_on_opposite_sides", "details": {"side_p": side_p, "side_q": side_q}}
	var new_diagonal: String = _arc_key(p_id, q_id)
	if edge_index.has(new_diagonal): return {"valid": false, "reason": "replacement_diagonal_already_present"}
	var ids_a: Array[String] = [p_id, q_id, u_id]
	var ids_b: Array[String] = [q_id, p_id, v_id]
	var points_a: Array[Vector3] = [p, q, u]
	var points_b: Array[Vector3] = [q, p, v]
	var source_ids: Array[String] = []
	for source_id in tri_a.source_polygon_ids + tri_b.source_polygon_ids:
		if not source_ids.has(String(source_id)): source_ids.append(String(source_id))
	source_ids.sort()
	if source_ids.size() != 2: return {"valid": false, "reason": "face_owned_patch_requires_exactly_two_source_faces", "details": {"source_polygon_ids": source_ids}}
	var toward: Vector3 = _combined_toward(source_ids, polygon_toward)
	if toward.length_squared() <= 1.0e-20: return {"valid": false, "reason": "source_orientation_missing"}
	var row_a: Dictionary = _make_oriented_triangle(ids_a, points_a, source_ids, toward, "c5-flip:%04d:0" % flip_index)
	var row_b: Dictionary = _make_oriented_triangle(ids_b, points_b, source_ids, toward, "c5-flip:%04d:1" % flip_index)
	if not bool(row_a.get("valid", false)) or not bool(row_b.get("valid", false)): return {"valid": false, "reason": "replacement_orientation_invalid", "details": {"a": row_a, "b": row_b}}
	for polygon_id in source_ids:
		var source_toward: Vector3 = polygon_toward[polygon_id]
		if row_a.normal.dot(source_toward) <= 0.0 or row_b.normal.dot(source_toward) <= 0.0:
			return {"valid": false, "reason": "replacement_orientation_disagrees_with_source_face", "details": {"polygon_id": polygon_id}}
	if float(row_a.cross_squared) <= CUTOFF_SQUARED or float(row_b.cross_squared) <= CUTOFF_SQUARED:
		return {"valid": false, "reason": "replacement_cutoff_failed", "details": {"cross_squared": [row_a.cross_squared, row_b.cross_squared]}}
	var source_provenance: Array[Dictionary] = []
	for polygon_id in source_ids:
		var polygon: Array = polygon_by_id.get(polygon_id, [])
		if polygon.size() < 3: return {"valid": false, "reason": "source_polygon_provenance_missing", "details": {"polygon_id": polygon_id}}
		source_provenance.append({"polygon_id": polygon_id, "source_cell": polygon[1], "source_tetrahedron": polygon[2]})
	var old_diagonal_midpoint: Vector3 = (u + v) * 0.5
	var new_diagonal_midpoint: Vector3 = (p + q) * 0.5
	var midpoint_displacement: float = old_diagonal_midpoint.distance_to(new_diagonal_midpoint)
	if not is_finite(midpoint_displacement): return {"valid": false, "reason": "nonfinite_diagonal_midpoint_displacement"}
	var old_is_source_arc: bool = topology_arc_keys.has(edge_key)
	var flip_id: String = "c5-flip|" + edge_key + "|" + str(flip_index)
	var record: Dictionary = {
		"flip_id": flip_id,
		"removed_edge_key": edge_key,
		"replacement_diagonal_key": new_diagonal,
		"patch_owner_polygon_id": source_ids[0],
		"source_polygon_ids": source_ids,
		"source_face_provenance": source_provenance,
		"source_triangle_ids": [tri_a.triangle_id, tri_b.triangle_id],
		"replacement_triangle_ids": [row_a.triangle_id, row_b.triangle_id],
		"removed_arc_endpoint_ids": [u_id, v_id],
		"vertices": {"edge_u": [u.x, u.y, u.z], "edge_v": [v.x, v.y, v.z], "opposite_p": [p.x, p.y, p.z], "opposite_q": [q.x, q.y, q.z]},
		"coplanarity_scalar_triple_product": determinant,
		"old_diagonal_midpoint": [old_diagonal_midpoint.x, old_diagonal_midpoint.y, old_diagonal_midpoint.z],
		"replacement_diagonal_midpoint": [new_diagonal_midpoint.x, new_diagonal_midpoint.y, new_diagonal_midpoint.z],
		"diagonal_midpoint_displacement": midpoint_displacement,
		"old_cross_squared": [tri_a.cross_squared, tri_b.cross_squared],
		"new_cross_squared": [row_a.cross_squared, row_b.cross_squared],
		"source_arc_removed": old_is_source_arc,
		"removed_arc_path_positions": [u, new_diagonal_midpoint, v],
		"path_segment_triangle_ids": [row_a.triangle_id, row_b.triangle_id],
		"path_midpoint_on_replacement_diagonal": true,
		"path_segment_realization": "u-to-midpoint lies in replacement face A; midpoint-to-v lies in replacement face B"
	}
	return {"valid": true, "replacement_triangles": [row_a, row_b], "flip_record": record}

func _make_oriented_triangle(ids: Array[String], points: Array[Vector3], source_ids: Array[String], toward: Vector3, triangle_id: String) -> Dictionary:
	var result: Dictionary = super._make_oriented_triangle(ids, points, source_ids, toward, triangle_id)
	if bool(result.get("valid", false)): result["construction"] = "R12C5_FACE_OWNED_NONCOPLANAR_LOCAL_PATCH"
	return result
