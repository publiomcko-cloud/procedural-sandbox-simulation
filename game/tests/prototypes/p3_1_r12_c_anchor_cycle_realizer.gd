extends RefCounted

## R12-C2 test-only graph-face anchor-cycle realization. Topology arrays are
## the authority; this class emits geometry from their ordered polygon cycles.

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const Authority := preload("res://tests/prototypes/p3_1_r10_a_topology_authority.gd")
const CUTOFF_SQUARED: float = 1.0e-12
const ARC_SEP: String = "\u001f"

func realize(graph: Dictionary, values: PackedFloat32Array, roi: Dictionary, expected_topology_sha: String, expected_graph_fingerprint_sha: String = "") -> Dictionary:
	var began: int = Time.get_ticks_usec()
	if graph.is_empty() or values.is_empty() or expected_topology_sha.is_empty() or expected_graph_fingerprint_sha.is_empty():
		return {"valid": false, "reason": "c2_input_missing"}
	var source_identity: Dictionary = validate_topology_identity(graph, expected_graph_fingerprint_sha)
	if not bool(source_identity.get("valid", false)):
		return {"valid": false, "reason": "c2_graph_fingerprint_mismatch", "observed_graph_fingerprint_sha256": source_identity.get("observed_sha256", ""), "expected_graph_fingerprint_sha256": expected_graph_fingerprint_sha}
	var roots: Array = graph.get("roots", [])
	var arcs: Array = graph.get("arcs", [])
	var polygons: Array = graph.get("polygons", [])
	var dims: Vector3i = Core.cell_counts(roi) + Vector3i.ONE
	if values.size() != dims.x * dims.y * dims.z:
		return {"valid": false, "reason": "c2_volume_dimensions_invalid"}
	var root_by_id: Dictionary = {}
	var root_map: Array[Dictionary] = []
	for row in roots:
		if not row is Array or row.size() < 4:
			return {"valid": false, "reason": "c2_root_row_invalid"}
		var root_id: String = String(row[0])
		var position := Vector3(float(row[1]), float(row[2]), float(row[3]))
		if root_id.is_empty() or root_by_id.has(root_id) or not position.is_finite():
			return {"valid": false, "reason": "c2_root_identity_or_coordinate_invalid", "root_id": root_id}
		root_by_id[root_id] = position
		root_map.append({"root_id": root_id, "role": "ANCHOR_VERTEX", "geometry_vertex_id": "anchor|" + root_id, "position": [position.x, position.y, position.z], "source_row": row})
	if root_map.size() != roots.size():
		return {"valid": false, "reason": "c2_root_coverage_mismatch"}
	var arc_by_key: Dictionary = {}
	var arc_map: Array[Dictionary] = []
	for row in arcs:
		if not row is Array or row.size() < 5 or not row[1] is Array or row[1].size() != 2 or not row[3] is Array or not row[4] is Array:
			return {"valid": false, "reason": "c2_arc_row_invalid"}
		var key: String = String(row[0])
		var endpoint_a: String = String(row[1][0])
		var endpoint_b: String = String(row[1][1])
		if key.is_empty() or arc_by_key.has(key) or key != _arc_key(endpoint_a, endpoint_b) or endpoint_a == endpoint_b or not root_by_id.has(endpoint_a) or not root_by_id.has(endpoint_b) or int(row[2]) < 1 or int(row[2]) > 2 or row[3].size() != int(row[2]) or row[4].size() != int(row[2]):
			return {"valid": false, "reason": "c2_arc_identity_or_endpoint_invalid", "arc_key": key}
		arc_by_key[key] = row
		arc_map.append({"arc_id": key, "geometry_edge_id": "anchor-edge|" + key, "root_ids": [endpoint_a, endpoint_b], "expected_incidence": int(row[2]), "source_polygon_ids": row[3], "source_face_ids": row[4], "source_row": row})
	if arc_map.size() != arcs.size():
		return {"valid": false, "reason": "c2_arc_coverage_mismatch"}
	var mesh: Dictionary = Core.new_mesh()
	var emitted: Array[Dictionary] = []
	var face_map: Array[Dictionary] = []
	var cutoff_rejections: Array[Dictionary] = []
	var edge_incidence: Dictionary = {}
	var polygon_ids_seen: Dictionary = {}
	for polygon in polygons:
		if not polygon is Array or polygon.size() < 8 or not polygon[3] is Array or not polygon[4] is Array:
			return {"valid": false, "reason": "c2_polygon_row_invalid"}
		var polygon_id: String = String(polygon[0])
		var cell: Array = polygon[1]
		var tet_index: int = int(polygon[2])
		var ids: Array = polygon[3]
		var face_ids: Array = polygon[4]
		if polygon_id.is_empty() or polygon_ids_seen.has(polygon_id) or ids.size() < 3 or ids.size() > 4 or ids.size() != face_ids.size() or cell.size() != 3:
			return {"valid": false, "reason": "c2_face_cycle_shape_invalid", "polygon_id": polygon_id, "root_count": ids.size()}
		polygon_ids_seen[polygon_id] = true
		var cycle_roots: Dictionary = {}
		var cycle_faces: Dictionary = {}
		var points: Array[Vector3] = []
		for cycle_index in range(ids.size()):
			var root_value: Variant = ids[cycle_index]
			var root_id: String = String(root_value)
			var face_id: String = String(face_ids[cycle_index])
			if cycle_roots.has(root_id) or cycle_faces.has(face_id) or not root_by_id.has(root_id):
				return {"valid": false, "reason": "c2_face_references_unknown_root", "polygon_id": polygon_id, "root_id": root_id}
			cycle_roots[root_id] = true
			cycle_faces[face_id] = true
			points.append(root_by_id[root_id])
		for edge_index in range(ids.size()):
			var edge_key: String = _arc_key(String(ids[edge_index]), String(ids[(edge_index + 1) % ids.size()]))
			if not arc_by_key.has(edge_key):
				return {"valid": false, "reason": "c2_face_cycle_arc_missing", "polygon_id": polygon_id, "arc_key": edge_key}
			var source_arc: Array = arc_by_key[edge_key]
			if not source_arc[3].has(polygon_id) or not source_arc[4].has(String(face_ids[edge_index])):
				return {"valid": false, "reason": "c2_face_arc_ownership_mismatch", "polygon_id": polygon_id, "arc_key": edge_key}
		var toward_empty: Vector3 = _toward_empty(cell, tet_index, values, dims, roi)
		if not toward_empty.is_finite() or toward_empty.length_squared() <= 1.0e-20:
			return {"valid": false, "reason": "c2_face_orientation_authority_invalid", "polygon_id": polygon_id}
		var triangles: Array[Dictionary] = _triangulate_cycle(ids, points)
		if triangles.is_empty():
			return {"valid": false, "reason": "c2_face_triangulation_missing", "polygon_id": polygon_id}
		var face_emitted: Array[String] = []
		var face_rejections: Array[Dictionary] = []
		for local_triangle in triangles:
			var tri_ids: Array = local_triangle.root_ids.duplicate()
			var tri_points: Array = local_triangle.points.duplicate()
			var cross: Vector3 = (tri_points[1] - tri_points[0]).cross(tri_points[2] - tri_points[0])
			var cross_squared: float = cross.length_squared()
			if not is_finite(cross_squared) or cross_squared <= CUTOFF_SQUARED:
				var rejection := {"polygon_id": polygon_id, "root_ids": tri_ids, "cross_squared": cross_squared, "reason": "frozen_cross_squared_cutoff"}
				cutoff_rejections.append(rejection)
				face_rejections.append(rejection)
				continue
			if cross.dot(toward_empty) < 0.0:
				var id_swap: Variant = tri_ids[1]
				tri_ids[1] = tri_ids[2]
				tri_ids[2] = id_swap
				var point_swap: Variant = tri_points[1]
				tri_points[1] = tri_points[2]
				tri_points[2] = point_swap
				cross = (tri_points[1] - tri_points[0]).cross(tri_points[2] - tri_points[0])
			var normal: Vector3 = cross.normalized()
			if not normal.is_finite():
				return {"valid": false, "reason": "c2_normal_nonfinite", "polygon_id": polygon_id}
			mesh.positions.append_array(PackedVector3Array(tri_points))
			mesh.normals.append_array(PackedVector3Array([normal, normal, normal]))
			var triangle_id: String = polygon_id + "|c2-tri:" + str(face_emitted.size())
			face_emitted.append(triangle_id)
			emitted.append({"triangle_id": triangle_id, "polygon_id": polygon_id, "source_polygon_ids": [polygon_id], "patch_id": String(polygon[6]), "root_ids": tri_ids, "normal": normal, "cross_squared": cross_squared, "construction": "R12C2_GRAPH_FACE_ANCHOR_CYCLE"})
			for edge_index in range(3):
				var realized_edge: String = _arc_key(String(tri_ids[edge_index]), String(tri_ids[(edge_index + 1) % 3]))
				edge_incidence[realized_edge] = int(edge_incidence.get(realized_edge, 0)) + 1
		face_map.append({"polygon_id": polygon_id, "root_ids": ids, "face_ids": face_ids, "source_cell": cell, "source_tetrahedron": tet_index, "triangle_ids": face_emitted, "rejections": face_rejections})
	var missing_arcs: Array[Dictionary] = []
	for arc in arcs:
		var key: String = String(arc[0])
		var actual: int = int(edge_incidence.get(key, 0))
		if actual != int(arc[2]):
			missing_arcs.append({"arc_id": key, "expected_incidence": int(arc[2]), "actual_incidence": actual, "source_polygon_ids": arc[3]})
	var roi_min: Vector3 = Core.world_min(roi)
	var roi_max: Vector3 = roi_min + Vector3(Core.cell_counts(roi)) * Core.step(roi)
	var topology: Dictionary = Core.topology(mesh, roi_min, roi_max)
	var payload := {"roots": root_map, "arcs": arc_map, "faces": face_map}
	var map_sha: String = Core.sha256(JSON.stringify(payload).to_utf8_buffer())
	var roundtrip_payload: Dictionary = _roundtrip_graph(graph, root_map, arc_map, face_map)
	var roundtrip_equal: bool = JSON.stringify(roundtrip_payload) == JSON.stringify(graph)
	var roundtrip_fingerprint: String = Core.sha256(JSON.stringify(roundtrip_payload).to_utf8_buffer())
	var topology_signature_match: bool = roundtrip_equal and roundtrip_fingerprint == expected_graph_fingerprint_sha and not expected_topology_sha.is_empty()
	var authority: RefCounted = Authority.new()
	var mesh_sha: String = String(authority.call("_mesh_sha", mesh))
	var finite_mesh: bool = _mesh_finite(mesh)
	var complete: bool = topology_signature_match and finite_mesh and cutoff_rejections.is_empty() and missing_arcs.is_empty() and int(topology.get("internal_open_edges", -1)) == 0 and int(topology.get("nonmanifold_edges", -1)) == 0 and int(topology.get("degenerate_triangles", -1)) == 0 and int(topology.get("winding_inconsistencies", -1)) == 0
	return {"valid": true, "reason": "", "hypothesis": "C2_GRAPH_FACE_ANCHOR_CYCLE", "topology_sha256": expected_topology_sha, "graph_fingerprint_sha256": source_identity.get("observed_sha256", ""), "topology_signature_match": topology_signature_match, "topology_roundtrip_sha256": roundtrip_fingerprint if roundtrip_equal else "", "realization_map_sha256": map_sha, "root_map": root_map, "arc_map": arc_map, "face_map": face_map, "mesh": mesh, "mesh_sha256": mesh_sha, "emitted_triangles": emitted, "geometry_vertex_count": root_map.size(), "geometry_triangle_count": emitted.size(), "anchor_root_count": root_map.size(), "path_event_root_count": 0, "support_vertex_count": 0, "realization_path_count": 0, "cutoff_rejections": cutoff_rejections, "missing_topology_obligations": missing_arcs, "mesh_topology": topology, "minimum_cross_squared": _minimum_cross_squared(emitted), "finite_geometry": finite_mesh, "geometry_complete": complete, "build_usec": Time.get_ticks_usec() - began}

func validate_topology_identity(graph: Dictionary, expected_graph_fingerprint_sha: String) -> Dictionary:
	if graph.is_empty() or expected_graph_fingerprint_sha.length() != 64:
		return {"valid": false, "reason": "topology_identity_input_invalid", "observed_sha256": ""}
	var observed_sha: String = Core.sha256(JSON.stringify(graph).to_utf8_buffer())
	return {"valid": observed_sha == expected_graph_fingerprint_sha, "reason": "" if observed_sha == expected_graph_fingerprint_sha else "topology_graph_fingerprint_mismatch", "observed_sha256": observed_sha}

func _roundtrip_graph(graph: Dictionary, root_map: Array[Dictionary], arc_map: Array[Dictionary], face_map: Array[Dictionary]) -> Dictionary:
	var root_rows: Array = []
	for row in root_map: root_rows.append(row.source_row)
	var arc_rows: Array = []
	for row in arc_map: arc_rows.append(row.source_row)
	var polygon_by_id: Dictionary = {}
	for row in face_map: polygon_by_id[String(row.polygon_id)] = true
	var polygon_rows: Array = []
	for row in graph.get("polygons", []):
		if polygon_by_id.has(String(row[0])): polygon_rows.append(row)
	var output: Dictionary = graph.duplicate(true)
	output["roots"] = root_rows
	output["arcs"] = arc_rows
	output["polygons"] = polygon_rows
	return output

func _triangulate_cycle(ids: Array, points: Array[Vector3]) -> Array[Dictionary]:
	if ids.size() == 3:
		return [{"root_ids": [ids[0], ids[1], ids[2]], "points": [points[0], points[1], points[2]]}]
	if ids.size() != 4:
		return []
	var candidates: Array[Dictionary] = []
	for diagonal_index in range(2):
		var rows: Array[Dictionary]
		if diagonal_index == 0:
			rows = [{"indices": [0, 1, 2]}, {"indices": [0, 2, 3]}]
		else:
			rows = [{"indices": [0, 1, 3]}, {"indices": [1, 2, 3]}]
		var triangles: Array[Dictionary] = []
		var minimum: float = INF
		var accepted: bool = true
		for row in rows:
			var indices: Array = row.indices
			var tri_points: Array[Vector3] = [points[int(indices[0])], points[int(indices[1])], points[int(indices[2])]]
			var cross_squared: float = (tri_points[1] - tri_points[0]).cross(tri_points[2] - tri_points[0]).length_squared()
			minimum = minf(minimum, cross_squared)
			if not is_finite(cross_squared) or cross_squared <= CUTOFF_SQUARED: accepted = false
			triangles.append({"root_ids": [ids[int(indices[0])], ids[int(indices[1])], ids[int(indices[2])]], "points": tri_points, "cross_squared": cross_squared})
		candidates.append({"diagonal_index": diagonal_index, "accepted": accepted, "minimum": minimum, "triangles": triangles})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.accepted) != bool(b.accepted): return bool(a.accepted)
		if float(a.minimum) != float(b.minimum): return float(a.minimum) > float(b.minimum)
		return int(a.diagonal_index) < int(b.diagonal_index))
	for candidate in candidates:
		if bool(candidate.accepted): return candidate.triangles
	return candidates[0].triangles

func _toward_empty(cell: Array, tet_index: int, values: PackedFloat32Array, dims: Vector3i, roi: Dictionary) -> Vector3:
	if tet_index < 0 or tet_index >= Core.TETS.size(): return Vector3.ZERO
	var step: float = Core.step(roi)
	var world_min: Vector3 = Core.world_min(roi)
	var lattice_origin := Vector3i(roundi(world_min.x / step), roundi(world_min.y / step), roundi(world_min.z / step))
	var local_cell := Vector3i(int(cell[0]), int(cell[1]), int(cell[2])) - lattice_origin
	var solid := Vector3.ZERO
	var empty := Vector3.ZERO
	var solid_count: int = 0
	var empty_count: int = 0
	var tetra: Array = Core.TETS[tet_index]
	for corner_index in tetra:
		var corner: Vector3i = Core.GRID_CORNERS[int(corner_index)]
		var node: Vector3i = local_cell + corner
		if node.x < 0 or node.y < 0 or node.z < 0 or node.x >= dims.x or node.y >= dims.y or node.z >= dims.z: return Vector3.ZERO
		var point: Vector3 = world_min + Vector3(node) * step
		var density: float = values[(node.y * dims.z + node.z) * dims.x + node.x]
		if not is_finite(density): return Vector3.ZERO
		if density >= 0.0:
			solid += point
			solid_count += 1
		else:
			empty += point
			empty_count += 1
	if solid_count == 0 or empty_count == 0: return Vector3.ZERO
	return empty / float(empty_count) - solid / float(solid_count)

func _arc_key(a: String, b: String) -> String:
	return a + ARC_SEP + b if a < b else b + ARC_SEP + a

func _mesh_finite(mesh: Dictionary) -> bool:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = mesh.get("normals", PackedVector3Array())
	if positions.size() != normals.size(): return false
	for point in positions:
		if not point.is_finite(): return false
	for normal in normals:
		if not normal.is_finite(): return false
	return true

func _minimum_cross_squared(emitted: Array[Dictionary]) -> float:
	var result: float = INF
	for triangle in emitted: result = minf(result, float(triangle.get("cross_squared", INF)))
	return 0.0 if emitted.is_empty() else result
