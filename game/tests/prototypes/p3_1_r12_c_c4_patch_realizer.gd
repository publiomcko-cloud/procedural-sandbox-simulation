extends "res://tests/prototypes/p3_1_r12_c_anchor_cycle_realizer.gd"

## R12-C4: bounded exact-coplanar local 2-2 remeshing of the frozen source faces.
## This is an isolated experiment; source roots and scalar samples remain fixed.

const MAX_FLIPS: int = 128

func realize(graph: Dictionary, values: PackedFloat32Array, roi: Dictionary, expected_topology_sha: String, expected_graph_fingerprint_sha: String = "") -> Dictionary:
	var began: int = Time.get_ticks_usec()
	var base: Dictionary = super.realize(graph, values, roi, expected_topology_sha, expected_graph_fingerprint_sha)
	if not bool(base.get("valid", false)):
		var base_reason: String = String(base.get("reason", "base_graph_validation_failed"))
		if base_reason.begins_with("c2_"): base_reason = "c4_" + base_reason.substr(3)
		return {"valid": false, "reason": base_reason, "detail": base}
	var root_map: Array[Dictionary] = base.get("root_map", [])
	var roots_by_id: Dictionary = {}
	for row in root_map:
		roots_by_id[String(row.get("root_id", ""))] = Vector3(float(row.position[0]), float(row.position[1]), float(row.position[2]))
	var polygons: Array = graph.get("polygons", [])
	var polygon_by_id: Dictionary = {}
	var polygon_toward: Dictionary = {}
	var topology_arc_keys: Dictionary = {}
	for arc in graph.get("arcs", []): topology_arc_keys[String(arc[0])] = true
	var dims: Vector3i = Core.cell_counts(roi) + Vector3i.ONE
	for polygon in polygons:
		var polygon_id: String = String(polygon[0])
		polygon_by_id[polygon_id] = polygon
		polygon_toward[polygon_id] = _toward_empty(polygon[1], int(polygon[2]), values, dims, roi)
	var triangles: Array[Dictionary] = []
	var initial_cutoff: Array[Dictionary] = []
	for polygon in polygons:
		var polygon_id: String = String(polygon[0])
		var ids: Array = polygon[3]
		var points: Array[Vector3] = []
		for id in ids: points.append(roots_by_id[String(id)])
		var candidates: Array[Dictionary] = _triangulate_cycle(ids, points)
		if candidates.is_empty(): return {"valid": false, "reason": "c4_source_face_triangulation_missing", "polygon_id": polygon_id}
		var toward: Vector3 = polygon_toward[polygon_id]
		if not toward.is_finite() or toward.length_squared() <= 1.0e-20:
			return {"valid": false, "reason": "c4_source_face_orientation_missing", "polygon_id": polygon_id}
		for candidate_index in range(candidates.size()):
			var candidate: Dictionary = candidates[candidate_index]
			var tri_ids: Array = candidate.get("root_ids", []).duplicate()
			var tri_points: Array = candidate.get("points", []).duplicate()
			var cross: Vector3 = (tri_points[1] - tri_points[0]).cross(tri_points[2] - tri_points[0])
			var cross_squared: float = cross.length_squared()
			if not is_finite(cross_squared): return {"valid": false, "reason": "c4_source_triangle_nonfinite", "polygon_id": polygon_id}
			if cross.dot(toward) < 0.0:
				var id_swap: Variant = tri_ids[1]; tri_ids[1] = tri_ids[2]; tri_ids[2] = id_swap
				var point_swap: Vector3 = tri_points[1]; tri_points[1] = tri_points[2]; tri_points[2] = point_swap
				cross = (tri_points[1] - tri_points[0]).cross(tri_points[2] - tri_points[0])
			var triangle_id: String = polygon_id + "|c4-source:" + str(candidate_index)
			var row: Dictionary = {"triangle_id": triangle_id, "root_ids": tri_ids, "points": tri_points, "normal": cross.normalized(), "cross_squared": cross.length_squared(), "source_polygon_ids": [polygon_id], "construction": "FROZEN_SOURCE_FACE_CYCLE"}
			triangles.append(row)
			if float(row.cross_squared) <= CUTOFF_SQUARED:
				initial_cutoff.append({"triangle_id": triangle_id, "polygon_id": polygon_id, "root_ids": tri_ids, "cross_squared": row.cross_squared})
	var initial_triangle_count: int = triangles.size()
	var flips: Array[Dictionary] = []
	var rejected_candidates: Array[Dictionary] = []
	var reached_flip_cap: bool = false
	while flips.size() < MAX_FLIPS:
		var edge_index: Dictionary = _edge_index(triangles)
		var edge_keys: Array = edge_index.keys()
		edge_keys.sort()
		var applied: bool = false
		for key_value in edge_keys:
			var edge_key: String = String(key_value)
			var incident: Array = edge_index[edge_key]
			if incident.size() != 2: continue
			var first: Dictionary = incident[0]
			var second: Dictionary = incident[1]
			var triangle_a: Dictionary = triangles[int(first.triangle_index)]
			var triangle_b: Dictionary = triangles[int(second.triangle_index)]
			if float(triangle_a.cross_squared) > CUTOFF_SQUARED and float(triangle_b.cross_squared) > CUTOFF_SQUARED: continue
			var proposal: Dictionary = _make_flip(edge_key, first, second, triangle_a, triangle_b, triangles, edge_index, polygon_toward, polygon_by_id, topology_arc_keys, flips.size())
			if not bool(proposal.get("valid", false)):
				rejected_candidates.append({"edge_key": edge_key, "reason": proposal.get("reason", "flip_rejected"), "source_triangle_ids": [triangle_a.triangle_id, triangle_b.triangle_id], "details": proposal.get("details", {})})
				continue
			var high_index: int = maxi(int(first.triangle_index), int(second.triangle_index))
			var low_index: int = mini(int(first.triangle_index), int(second.triangle_index))
			triangles.remove_at(high_index)
			triangles.remove_at(low_index)
			triangles.append_array(proposal.get("replacement_triangles", []))
			flips.append(proposal.get("flip_record", {}))
			applied = true
			break
		if not applied: break
	if flips.size() == MAX_FLIPS:
		reached_flip_cap = _eligible_bad_edge_remains(triangles)
	var final_cutoff: Array[Dictionary] = []
	for triangle in triangles:
		if not is_finite(float(triangle.cross_squared)) or float(triangle.cross_squared) <= CUTOFF_SQUARED:
			final_cutoff.append({"triangle_id": triangle.triangle_id, "source_polygon_ids": triangle.source_polygon_ids, "root_ids": triangle.root_ids, "cross_squared": triangle.cross_squared, "reason": "frozen_cross_squared_cutoff"})
	var mesh: Dictionary = Core.new_mesh()
	var edge_counts: Dictionary = {}
	for triangle in triangles:
		for point in triangle.points: mesh.positions.append(point)
		for _i in range(3): mesh.normals.append(triangle.normal)
		for edge in range(3):
			var a: String = String(triangle.root_ids[edge]); var b: String = String(triangle.root_ids[(edge + 1) % 3])
			var key: String = _arc_key(a, b)
			edge_counts[key] = int(edge_counts.get(key, 0)) + 1
	var flip_paths: Dictionary = {}
	for flip in flips:
		flip_paths[String(flip.removed_edge_key)] = flip
	var arc_map: Array[Dictionary] = []
	var missing_arcs: Array[Dictionary] = []
	for base_arc in base.get("arc_map", []):
		var arc: Dictionary = base_arc.duplicate(true)
		var key: String = String(arc.arc_id)
		var observed_incidence: int = int(edge_counts.get(key, 0))
		if observed_incidence == int(arc.expected_incidence):
			arc["geometry_mapping"] = "ANCHOR_EDGE"
			arc["geometry_path_positions"] = [_vector_array(roots_by_id[String(arc.root_ids[0])]), _vector_array(roots_by_id[String(arc.root_ids[1])])]
		elif flip_paths.has(key):
			var path_record: Dictionary = flip_paths[key]
			var path_owners: Array = path_record.get("source_polygon_ids", []).duplicate()
			var expected_owners: Array = arc.get("source_polygon_ids", []).duplicate()
			path_owners.sort(); expected_owners.sort()
			if path_owners != expected_owners:
				arc["geometry_mapping"] = "UNREALIZED_OWNER_MISMATCH"
				missing_arcs.append({"arc_id": key, "expected_source_polygon_ids": expected_owners, "path_source_polygon_ids": path_owners})
				arc_map.append(arc)
				continue
			var path_points: Array = path_record.get("removed_arc_path_positions", []).duplicate()
			var path_triangles: Array = path_record.get("path_segment_triangle_ids", []).duplicate()
			if path_record.get("removed_arc_endpoint_ids", []).size() != 2:
				arc["geometry_mapping"] = "UNREALIZED_PATH_ENDPOINTS_MISSING"
				missing_arcs.append({"arc_id": key, "reason": "path_endpoint_provenance_missing"})
				arc_map.append(arc)
				continue
			if String(path_record.removed_arc_endpoint_ids[0]) != String(arc.root_ids[0]):
				path_points.reverse()
				path_triangles.reverse()
			var path_positions: Array = []
			for path_point in path_points: path_positions.append(_vector_array(path_point))
			arc["geometry_mapping"] = "PIECEWISE_PATH_THROUGH_REPLACEMENT_DIAGONAL"
			arc["geometry_path_positions"] = path_positions
			arc["path_segment_triangle_ids"] = path_triangles
			arc["path_parent_polygon_ids"] = path_owners
			arc["path_source_face_provenance"] = path_record.get("source_face_provenance", [])
		else:
			arc["geometry_mapping"] = "UNREALIZED"
			missing_arcs.append({"arc_id": key, "expected_incidence": arc.expected_incidence, "observed_mesh_edge_incidence": observed_incidence, "source_polygon_ids": arc.source_polygon_ids})
		arc_map.append(arc)
	var face_map: Array[Dictionary] = []
	for polygon in polygons:
		var polygon_id: String = String(polygon[0])
		var realized_ids: Array[String] = []
		for triangle in triangles:
			if triangle.source_polygon_ids.has(polygon_id): realized_ids.append(String(triangle.triangle_id))
		face_map.append({"polygon_id": polygon_id, "root_ids": polygon[3], "face_ids": polygon[4], "source_cell": polygon[1], "source_tetrahedron": polygon[2], "geometry_triangle_ids": realized_ids, "source_row": polygon})
	var roi_min: Vector3 = Core.world_min(roi)
	var roi_max: Vector3 = roi_min + Vector3(Core.cell_counts(roi)) * Core.step(roi)
	var topology: Dictionary = Core.topology(mesh, roi_min, roi_max)
	var roundtrip: Dictionary = _roundtrip_graph(graph, root_map, arc_map, face_map)
	var roundtrip_equal: bool = JSON.stringify(roundtrip) == JSON.stringify(graph)
	var roundtrip_sha: String = Core.sha256(JSON.stringify(roundtrip).to_utf8_buffer())
	var topology_signature_match: bool = roundtrip_equal and roundtrip_sha == expected_graph_fingerprint_sha
	var emitted: Array[Dictionary] = []
	for triangle in triangles: emitted.append({"triangle_id": triangle.triangle_id, "source_polygon_ids": triangle.source_polygon_ids, "root_ids": triangle.root_ids, "normal": triangle.normal, "cross_squared": triangle.cross_squared, "construction": triangle.construction})
	var authority: RefCounted = Authority.new()
	var finite_geometry: bool = _mesh_finite(mesh)
	var complete: bool = topology_signature_match and finite_geometry and final_cutoff.is_empty() and missing_arcs.is_empty() and not reached_flip_cap and int(topology.get("internal_open_edges", -1)) == 0 and int(topology.get("nonmanifold_edges", -1)) == 0 and int(topology.get("degenerate_triangles", -1)) == 0 and int(topology.get("winding_inconsistencies", -1)) == 0
	var map_payload: Dictionary = {"roots": root_map, "arcs": arc_map, "faces": face_map, "flips": flips}
	return {"valid": true, "reason": "", "hypothesis": "C4_EXACT_COPLANAR_LOCAL_2TO2_PATCH", "topology_sha256": expected_topology_sha, "graph_fingerprint_sha256": base.get("graph_fingerprint_sha256", ""), "topology_signature_match": topology_signature_match, "topology_roundtrip_sha256": roundtrip_sha if roundtrip_equal else "", "realization_map_sha256": Core.sha256(JSON.stringify(map_payload).to_utf8_buffer()), "root_map": root_map, "arc_map": arc_map, "face_map": face_map, "mesh": mesh, "mesh_sha256": String(authority.call("_mesh_sha", mesh)), "emitted_triangles": emitted, "geometry_vertex_count": root_map.size(), "geometry_triangle_count": triangles.size(), "anchor_root_count": root_map.size(), "path_event_root_count": 0, "support_vertex_count": 0, "realization_path_count": flips.size(), "initial_triangle_count": initial_triangle_count, "initial_cutoff_rejections": initial_cutoff, "cutoff_rejections": final_cutoff, "missing_topology_obligations": missing_arcs, "applied_flips": flips, "rejected_flip_candidates": rejected_candidates, "flip_cap": MAX_FLIPS, "flip_cap_exhausted": reached_flip_cap, "mesh_topology": topology, "minimum_cross_squared": _minimum_cross_squared(emitted), "finite_geometry": finite_geometry, "geometry_complete": complete, "build_usec": Time.get_ticks_usec() - began}

func _edge_index(triangles: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for triangle_index in range(triangles.size()):
		var triangle: Dictionary = triangles[triangle_index]
		for edge in range(3):
			var a: String = String(triangle.root_ids[edge]); var b: String = String(triangle.root_ids[(edge + 1) % 3])
			var key: String = _arc_key(a, b)
			if not result.has(key): result[key] = []
			var opposite: String = String(triangle.root_ids[(edge + 2) % 3])
			result[key].append({"triangle_index": triangle_index, "u": a, "v": b, "opposite": opposite})
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
	if normal.length_squared() == 0.0: return {"valid": false, "reason": "source_plane_degenerate"}
	var determinant: float = normal.dot(q - u)
	if determinant != 0.0: return {"valid": false, "reason": "source_roots_not_exactly_coplanar", "details": {"scalar_triple_product": determinant}}
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
	var toward_a: Vector3 = _combined_toward(source_ids, polygon_toward)
	if toward_a.length_squared() <= 1.0e-20: return {"valid": false, "reason": "source_orientation_missing"}
	var row_a: Dictionary = _make_oriented_triangle(ids_a, points_a, source_ids, toward_a, "c4-flip:%04d:0" % flip_index)
	var row_b: Dictionary = _make_oriented_triangle(ids_b, points_b, source_ids, toward_a, "c4-flip:%04d:1" % flip_index)
	if not bool(row_a.get("valid", false)) or not bool(row_b.get("valid", false)): return {"valid": false, "reason": "replacement_orientation_invalid", "details": {"a": row_a, "b": row_b}}
	for polygon_id in source_ids:
		var source_toward: Vector3 = polygon_toward[polygon_id]
		if row_a.normal.dot(source_toward) <= 0.0 or row_b.normal.dot(source_toward) <= 0.0:
			return {"valid": false, "reason": "replacement_orientation_disagrees_with_source_face", "details": {"polygon_id": polygon_id}}
	if float(row_a.cross_squared) <= CUTOFF_SQUARED or float(row_b.cross_squared) <= CUTOFF_SQUARED: return {"valid": false, "reason": "replacement_cutoff_failed", "details": {"cross_squared": [row_a.cross_squared, row_b.cross_squared]}}
	var old_is_source_arc: bool = topology_arc_keys.has(edge_key)
	var midpoint: Vector3 = (p + q) * 0.5
	var flip_id: String = "c4-flip|" + edge_key + "|" + str(flip_index)
	var source_provenance: Array[Dictionary] = []
	for polygon_id in source_ids:
		var polygon: Array = polygon_by_id.get(polygon_id, [])
		if polygon.size() < 3: return {"valid": false, "reason": "source_polygon_provenance_missing", "details": {"polygon_id": polygon_id}}
		source_provenance.append({"polygon_id": polygon_id, "source_cell": polygon[1], "source_tetrahedron": polygon[2]})
	var record: Dictionary = {"flip_id": flip_id, "removed_edge_key": edge_key, "replacement_diagonal_key": new_diagonal, "source_polygon_ids": source_ids, "source_face_provenance": source_provenance, "source_triangle_ids": [tri_a.triangle_id, tri_b.triangle_id], "replacement_triangle_ids": [row_a.triangle_id, row_b.triangle_id], "removed_arc_endpoint_ids": [u_id, v_id], "vertices": {"edge_u": [u.x, u.y, u.z], "edge_v": [v.x, v.y, v.z], "opposite_p": [p.x, p.y, p.z], "opposite_q": [q.x, q.y, q.z]}, "coplanarity_scalar_triple_product": determinant, "old_cross_squared": [tri_a.cross_squared, tri_b.cross_squared], "new_cross_squared": [row_a.cross_squared, row_b.cross_squared], "source_arc_removed": old_is_source_arc, "removed_arc_path_positions": [u, midpoint, v], "path_segment_triangle_ids": [row_a.triangle_id, row_b.triangle_id], "path_midpoint_on_replacement_diagonal": true, "path_segment_realization": "u-to-midpoint lies in replacement face A; midpoint-to-v lies in replacement face B"}
	return {"valid": true, "replacement_triangles": [row_a, row_b], "flip_record": record}

func _make_oriented_triangle(ids: Array[String], points: Array[Vector3], source_ids: Array[String], toward: Vector3, triangle_id: String) -> Dictionary:
	var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	if not cross.is_finite() or cross.length_squared() == 0.0: return {"valid": false, "reason": "replacement_cross_invalid"}
	if cross.dot(toward) < 0.0:
		var id_swap: String = ids[1]; ids[1] = ids[2]; ids[2] = id_swap
		var point_swap: Vector3 = points[1]; points[1] = points[2]; points[2] = point_swap
		cross = (points[1] - points[0]).cross(points[2] - points[0])
	if cross.dot(toward) <= 0.0: return {"valid": false, "reason": "replacement_winding_disagrees"}
	return {"valid": true, "triangle_id": triangle_id, "root_ids": ids, "points": points, "normal": cross.normalized(), "cross_squared": cross.length_squared(), "source_polygon_ids": source_ids, "construction": "R12C4_EXACT_COPLANAR_LOCAL_2TO2_FLIP"}

func _combined_toward(source_ids: Array[String], polygon_toward: Dictionary) -> Vector3:
	var result: Vector3 = Vector3.ZERO
	for polygon_id in source_ids:
		if not polygon_toward.has(polygon_id): return Vector3.ZERO
		var value: Vector3 = polygon_toward[polygon_id]
		if not value.is_finite(): return Vector3.ZERO
		result += value.normalized()
	return result.normalized() if result.length_squared() > 1.0e-20 else Vector3.ZERO

func _eligible_bad_edge_remains(triangles: Array[Dictionary]) -> bool:
	for triangle in triangles:
		if float(triangle.cross_squared) <= CUTOFF_SQUARED: return true
	return false

func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
