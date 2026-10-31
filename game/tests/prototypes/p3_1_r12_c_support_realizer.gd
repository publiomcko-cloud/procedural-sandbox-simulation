extends "res://tests/prototypes/p3_1_r12_c_anchor_cycle_realizer.gd"

## R12-C3 test-only field-constrained support-fan realization.
## Every support point is a deterministic centroid of one frozen source face.

func realize(graph: Dictionary, values: PackedFloat32Array, roi: Dictionary, expected_topology_sha: String, expected_graph_fingerprint_sha: String = "") -> Dictionary:
	var began: int = Time.get_ticks_usec()
	if graph.is_empty() or values.is_empty() or expected_topology_sha.is_empty() or expected_graph_fingerprint_sha.is_empty():
		return {"valid": false, "reason": "c3_input_missing"}
	var source_identity: Dictionary = validate_topology_identity(graph, expected_graph_fingerprint_sha)
	if not bool(source_identity.get("valid", false)):
		return {"valid": false, "reason": "c3_graph_fingerprint_mismatch", "observed_graph_fingerprint_sha256": source_identity.get("observed_sha256", ""), "expected_graph_fingerprint_sha256": expected_graph_fingerprint_sha}
	var roots: Array = graph.get("roots", [])
	var arcs: Array = graph.get("arcs", [])
	var polygons: Array = graph.get("polygons", [])
	var dims: Vector3i = Core.cell_counts(roi) + Vector3i.ONE
	if values.size() != dims.x * dims.y * dims.z:
		return {"valid": false, "reason": "c3_volume_dimensions_invalid"}
	var root_by_id: Dictionary = {}
	var root_map: Array[Dictionary] = []
	var roi_min: Vector3 = Core.world_min(roi)
	var roi_max: Vector3 = roi_min + Vector3(Core.cell_counts(roi)) * Core.step(roi)
	for row in roots:
		if not row is Array or row.size() < 4:
			return {"valid": false, "reason": "c3_root_row_invalid"}
		var root_id: String = String(row[0])
		var point: Vector3 = Vector3(float(row[1]), float(row[2]), float(row[3]))
		if root_id.is_empty() or root_by_id.has(root_id) or not point.is_finite():
			return {"valid": false, "reason": "c3_root_identity_or_coordinate_invalid", "root_id": root_id}
		root_by_id[root_id] = point
		var boundary: bool = point.x == roi_min.x or point.x == roi_max.x or point.y == roi_min.y or point.y == roi_max.y or point.z == roi_min.z or point.z == roi_max.z
		root_map.append({"root_id": root_id, "role": "BOUNDARY_ANCHOR" if boundary else "ANCHOR_VERTEX", "geometry_vertex_id": "anchor|" + root_id, "position": [point.x, point.y, point.z], "source_row": row})
	if root_map.size() != roots.size():
		return {"valid": false, "reason": "c3_root_coverage_mismatch"}
	var arc_by_key: Dictionary = {}
	var arc_map: Array[Dictionary] = []
	for row in arcs:
		if not row is Array or row.size() < 5 or not row[1] is Array or row[1].size() != 2 or not row[3] is Array or not row[4] is Array:
			return {"valid": false, "reason": "c3_arc_row_invalid"}
		var key: String = String(row[0])
		var endpoint_a: String = String(row[1][0])
		var endpoint_b: String = String(row[1][1])
		var incidence: int = int(row[2])
		if key.is_empty() or arc_by_key.has(key) or key != _arc_key(endpoint_a, endpoint_b) or endpoint_a == endpoint_b or not root_by_id.has(endpoint_a) or not root_by_id.has(endpoint_b) or incidence < 1 or incidence > 2 or row[3].size() != incidence or row[4].size() != incidence:
			return {"valid": false, "reason": "c3_arc_identity_or_endpoint_invalid", "arc_key": key}
		arc_by_key[key] = row
		arc_map.append({"arc_id": key, "geometry_edge_id": "anchor-edge|" + key, "root_ids": [endpoint_a, endpoint_b], "expected_incidence": incidence, "source_polygon_ids": row[3], "source_face_ids": row[4], "source_row": row})
	if arc_map.size() != arcs.size():
		return {"valid": false, "reason": "c3_arc_coverage_mismatch"}
	var mesh: Dictionary = Core.new_mesh()
	var emitted: Array[Dictionary] = []
	var face_map: Array[Dictionary] = []
	var support_vertices: Array[Dictionary] = []
	var cutoff_rejections: Array[Dictionary] = []
	var edge_incidence: Dictionary = {}
	var polygon_ids_seen: Dictionary = {}
	for polygon in polygons:
		if not polygon is Array or polygon.size() < 8 or not polygon[3] is Array or not polygon[4] is Array:
			return {"valid": false, "reason": "c3_polygon_row_invalid"}
		var polygon_id: String = String(polygon[0])
		var cell: Array = polygon[1]
		var tet_index: int = int(polygon[2])
		var ids: Array = polygon[3]
		var face_ids: Array = polygon[4]
		if polygon_id.is_empty() or polygon_ids_seen.has(polygon_id) or ids.size() < 3 or ids.size() > 4 or ids.size() != face_ids.size() or cell.size() != 3:
			return {"valid": false, "reason": "c3_face_cycle_shape_invalid", "polygon_id": polygon_id}
		polygon_ids_seen[polygon_id] = true
		var cycle_roots: Dictionary = {}
		var cycle_faces: Dictionary = {}
		var points: Array[Vector3] = []
		for cycle_index in range(ids.size()):
			var root_id: String = String(ids[cycle_index])
			var face_id: String = String(face_ids[cycle_index])
			if root_id.is_empty() or face_id.is_empty() or cycle_roots.has(root_id) or cycle_faces.has(face_id) or not root_by_id.has(root_id):
				return {"valid": false, "reason": "c3_face_cycle_identity_invalid", "polygon_id": polygon_id, "root_id": root_id}
			cycle_roots[root_id] = true
			cycle_faces[face_id] = true
			points.append(root_by_id[root_id])
		for edge_index in range(ids.size()):
			var arc_key: String = _arc_key(String(ids[edge_index]), String(ids[(edge_index + 1) % ids.size()]))
			if not arc_by_key.has(arc_key):
				return {"valid": false, "reason": "c3_face_cycle_arc_missing", "polygon_id": polygon_id, "arc_key": arc_key}
			var source_arc: Array = arc_by_key[arc_key]
			if not source_arc[3].has(polygon_id) or not source_arc[4].has(String(face_ids[edge_index])):
				return {"valid": false, "reason": "c3_face_arc_ownership_mismatch", "polygon_id": polygon_id, "arc_key": arc_key}
		var support_point: Vector3 = Vector3.ZERO
		for point in points: support_point += point
		support_point /= float(points.size())
		if not support_point.is_finite():
			return {"valid": false, "reason": "c3_support_nonfinite", "polygon_id": polygon_id}
		var field_evidence: Dictionary = _support_field_evidence(cell, tet_index, support_point, values, dims, roi)
		if not bool(field_evidence.get("valid", false)):
			return {"valid": false, "reason": "c3_support_field_provenance_invalid", "polygon_id": polygon_id, "detail": field_evidence}
		var support_id: String = "support|" + polygon_id + "|centroid"
		support_vertices.append({"support_id": support_id, "role": "SUPPORT_VERTEX", "parent_polygon_id": polygon_id, "source_cell": cell, "source_tetrahedron": tet_index, "generation_method": "ordered_face_root_arithmetic_centroid", "field_authority": "Candidate D materialized tetrahedral piecewise-linear field", "position": [support_point.x, support_point.y, support_point.z], "barycentric_weights": field_evidence.get("barycentric_weights", []), "interpolated_scalar_residual": field_evidence.get("interpolated_scalar_residual", null), "neighboring_arc_ids": _cycle_arc_ids(ids), "insertion_reason": "deterministic face-fan support for C3 hypothesis"})
		var toward_empty: Vector3 = _toward_empty(cell, tet_index, values, dims, roi)
		if not toward_empty.is_finite() or toward_empty.length_squared() <= 1.0e-20:
			return {"valid": false, "reason": "c3_face_orientation_authority_invalid", "polygon_id": polygon_id}
		var face_triangles: Array[String] = []
		var face_rejections: Array[Dictionary] = []
		for edge_index in range(ids.size()):
			var next_index: int = (edge_index + 1) % ids.size()
			var tri_ids: Array[String] = [String(ids[edge_index]), String(ids[next_index]), support_id]
			var tri_points: Array[Vector3] = [points[edge_index], points[next_index], support_point]
			var cross: Vector3 = (tri_points[1] - tri_points[0]).cross(tri_points[2] - tri_points[0])
			var cross_squared: float = cross.length_squared()
			if not is_finite(cross_squared) or cross_squared <= CUTOFF_SQUARED:
				var rejection: Dictionary = {"polygon_id": polygon_id, "support_id": support_id, "root_ids": [tri_ids[0], tri_ids[1]], "cross_squared": cross_squared, "reason": "frozen_cross_squared_cutoff"}
				cutoff_rejections.append(rejection)
				face_rejections.append(rejection)
				continue
			if cross.dot(toward_empty) < 0.0:
				var id_swap: String = tri_ids[1]
				tri_ids[1] = tri_ids[2]
				tri_ids[2] = id_swap
				var point_swap: Vector3 = tri_points[1]
				tri_points[1] = tri_points[2]
				tri_points[2] = point_swap
				cross = (tri_points[1] - tri_points[0]).cross(tri_points[2] - tri_points[0])
			var normal: Vector3 = cross.normalized()
			if not normal.is_finite():
				return {"valid": false, "reason": "c3_normal_nonfinite", "polygon_id": polygon_id}
			mesh.positions.append_array(PackedVector3Array(tri_points))
			mesh.normals.append_array(PackedVector3Array([normal, normal, normal]))
			var triangle_id: String = polygon_id + "|c3-fan:" + str(edge_index)
			face_triangles.append(triangle_id)
			emitted.append({"triangle_id": triangle_id, "polygon_id": polygon_id, "support_id": support_id, "source_polygon_ids": [polygon_id], "patch_id": String(polygon[6]), "root_ids": tri_ids, "normal": normal, "cross_squared": cross_squared, "construction": "R12C3_FIELD_CONSTRAINED_SUPPORT_FAN"})
			var source_edge: String = _arc_key(String(ids[edge_index]), String(ids[next_index]))
			edge_incidence[source_edge] = int(edge_incidence.get(source_edge, 0)) + 1
		face_map.append({"polygon_id": polygon_id, "root_ids": ids, "face_ids": face_ids, "source_cell": cell, "source_tetrahedron": tet_index, "support_id": support_id, "triangle_ids": face_triangles, "rejections": face_rejections})
	if polygons.size() > 502 or support_vertices.size() > 502 or emitted.size() > 2008:
		return {"valid": false, "reason": "c3_frozen_geometry_bound_exceeded", "polygon_count": polygons.size(), "support_count": support_vertices.size(), "triangle_count": emitted.size()}
	var missing_arcs: Array[Dictionary] = []
	for arc in arcs:
		var key: String = String(arc[0])
		var actual: int = int(edge_incidence.get(key, 0))
		if actual != int(arc[2]):
			missing_arcs.append({"arc_id": key, "expected_incidence": int(arc[2]), "actual_incidence": actual, "source_polygon_ids": arc[3]})
	var topology: Dictionary = Core.topology(mesh, roi_min, roi_max)
	var roundtrip_payload: Dictionary = _roundtrip_graph(graph, root_map, arc_map, face_map)
	var roundtrip_equal: bool = JSON.stringify(roundtrip_payload) == JSON.stringify(graph)
	var roundtrip_fingerprint: String = Core.sha256(JSON.stringify(roundtrip_payload).to_utf8_buffer())
	var topology_signature_match: bool = roundtrip_equal and roundtrip_fingerprint == expected_graph_fingerprint_sha and not expected_topology_sha.is_empty()
	var support_payload: Dictionary = {"supports": support_vertices, "faces": face_map}
	var support_map_sha: String = Core.sha256(JSON.stringify(support_payload).to_utf8_buffer())
	var realization_payload: Dictionary = {"roots": root_map, "arcs": arc_map, "faces": face_map, "supports": support_vertices}
	var realization_map_sha: String = Core.sha256(JSON.stringify(realization_payload).to_utf8_buffer())
	var authority: RefCounted = Authority.new()
	var mesh_sha: String = String(authority.call("_mesh_sha", mesh))
	var finite_geometry: bool = _mesh_finite(mesh)
	var complete: bool = topology_signature_match and finite_geometry and cutoff_rejections.is_empty() and missing_arcs.is_empty() and int(topology.get("internal_open_edges", -1)) == 0 and int(topology.get("nonmanifold_edges", -1)) == 0 and int(topology.get("degenerate_triangles", -1)) == 0 and int(topology.get("winding_inconsistencies", -1)) == 0
	return {"valid": true, "reason": "", "hypothesis": "C3_FIELD_CONSTRAINED_SUPPORT_FAN", "topology_sha256": expected_topology_sha, "graph_fingerprint_sha256": source_identity.get("observed_sha256", ""), "topology_signature_match": topology_signature_match, "topology_roundtrip_sha256": roundtrip_fingerprint if roundtrip_equal else "", "realization_map_sha256": realization_map_sha, "support_map_sha256": support_map_sha, "root_map": root_map, "arc_map": arc_map, "face_map": face_map, "support_vertices": support_vertices, "mesh": mesh, "mesh_sha256": mesh_sha, "emitted_triangles": emitted, "geometry_vertex_count": root_map.size() + support_vertices.size(), "geometry_triangle_count": emitted.size(), "anchor_root_count": root_map.size(), "path_event_root_count": 0, "support_vertex_count": support_vertices.size(), "realization_path_count": 0, "cutoff_rejections": cutoff_rejections, "missing_topology_obligations": missing_arcs, "mesh_topology": topology, "minimum_cross_squared": _minimum_cross_squared(emitted), "finite_geometry": finite_geometry, "geometry_complete": complete, "build_usec": Time.get_ticks_usec() - began}

func _cycle_arc_ids(ids: Array) -> Array[String]:
	var result: Array[String] = []
	for index in range(ids.size()): result.append(_arc_key(String(ids[index]), String(ids[(index + 1) % ids.size()])))
	return result

func _support_field_evidence(cell: Array, tet_index: int, point: Vector3, values: PackedFloat32Array, dims: Vector3i, roi: Dictionary) -> Dictionary:
	if tet_index < 0 or tet_index >= Core.TETS.size() or cell.size() != 3: return {"valid": false, "reason": "tetrahedron_or_cell_invalid"}
	var tet: Array = Core.TETS[tet_index]
	var roi_min: Vector3 = Core.world_min(roi)
	var step: float = Core.step(roi)
	var cell_i: Vector3i = Vector3i(int(cell[0]), int(cell[1]), int(cell[2]))
	var lattice_origin: Vector3i = Vector3i(roundi(roi_min.x / step), roundi(roi_min.y / step), roundi(roi_min.z / step))
	var local_cell: Vector3i = cell_i - lattice_origin
	var positions: Array[Vector3] = []
	var samples: Array[float] = []
	for corner_index in tet:
		var corner: Vector3i = Core.GRID_CORNERS[int(corner_index)]
		var grid: Vector3i = local_cell + corner
		if grid.x < 0 or grid.y < 0 or grid.z < 0 or grid.x >= dims.x or grid.y >= dims.y or grid.z >= dims.z:
			return {"valid": false, "reason": "support_sample_coordinate_out_of_range", "sample_coordinate": grid, "source_cell": cell_i, "local_cell": local_cell}
		var sample_index: int = (grid.y * dims.z + grid.z) * dims.x + grid.x
		if sample_index < 0 or sample_index >= values.size(): return {"valid": false, "reason": "support_sample_index_out_of_range", "sample_index": sample_index}
		if not is_finite(float(values[sample_index])): return {"valid": false, "reason": "support_sample_nonfinite", "sample_index": sample_index}
		positions.append(roi_min + Vector3(grid) * step)
		samples.append(float(values[sample_index]))
	var a: Vector3 = positions[1] - positions[0]
	var b: Vector3 = positions[2] - positions[0]
	var c: Vector3 = positions[3] - positions[0]
	var q: Vector3 = point - positions[0]
	var determinant: float = a.dot(b.cross(c))
	if not is_finite(determinant) or determinant == 0.0: return {"valid": false, "reason": "support_tetrahedron_determinant_invalid", "determinant": determinant}
	var w1: float = q.dot(b.cross(c)) / determinant
	var w2: float = a.dot(q.cross(c)) / determinant
	var w3: float = a.dot(b.cross(q)) / determinant
	var weights: Array[float] = [1.0 - w1 - w2 - w3, w1, w2, w3]
	var residual: float = 0.0
	for index in range(4): residual += weights[index] * samples[index]
	if not is_finite(residual): return {"valid": false, "reason": "support_interpolated_residual_nonfinite"}
	return {"valid": true, "barycentric_weights": weights, "interpolated_scalar_residual": residual, "tetrahedron_samples": samples, "source_cell": cell_i, "source_local_cell": local_cell, "lattice_origin": lattice_origin, "source_tetrahedron": tet_index}
