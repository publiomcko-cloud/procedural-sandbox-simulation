extends "res://tests/prototypes/p3_1_r9_2_candidate_impl.gd"

## R10-A test-only topology-first realization over Candidate D's reloaded
## materialized float32 volume.  The polygon/root/arc graph is complete before
## any triangle is emitted and is the authority for this experiment.
const CUTOFF_SQUARED: float = 1.0e-12
const ARC_SEPARATOR: String = "\u001f"
const A2_CAUSAL_A1_CASE_SHA256: String = "700c59861d8011f61553848c195e10bb4b2e66cc42433185a56a4720af1f83be"
const A2_REFINE_CELLS: Dictionary = {"60,8,25": true, "61,8,25": true, "62,9,24": true, "66,7,29": true}

func realize_topology(values: PackedFloat32Array, hypothesis: String) -> Dictionary:
	var dims: Vector3i = CELLS + Vector3i.ONE
	if values.size() != dims.x * dims.y * dims.z:
		return {"valid": false, "reason": "materialized_volume_dimension_mismatch"}
	var begin_usec: int = Time.get_ticks_usec()
	var root_cache: Dictionary = {}
	var roots: Dictionary = {}
	var root_sources: Dictionary = {}
	var polygons: Array[Dictionary] = []
	var arcs: Dictionary = {}
	var geometry_errors: Array[Dictionary] = []
	var local_refinement: Array[Dictionary] = []
	var lattice_origin := Vector3i(roundi(ROI_MIN.x / STEP), roundi(ROI_MIN.y / STEP), roundi(ROI_MIN.z / STEP))
	for y in range(CELLS.y):
		for z in range(CELLS.z):
			for x in range(CELLS.x):
				var points: Array[Vector3] = []
				var samples: Array[float] = []
				var nodes: Array[Vector3i] = []
				var solid := Vector3.ZERO
				var empty := Vector3.ZERO
				var solid_count: int = 0
				var empty_count: int = 0
				for corner in Core.GRID_CORNERS:
					var node: Vector3i = Vector3i(x, y, z) + corner
					var point: Vector3 = ROI_MIN + Vector3(node) * STEP
					var value: float = values[_idx(node.x, node.y, node.z, dims)]
					points.append(point)
					samples.append(value)
					nodes.append(node)
					if value >= 0.0:
						solid += point
						solid_count += 1
					else:
						empty += point
						empty_count += 1
				if solid_count == 0 or empty_count == 0:
					continue
				var cell_id: Vector3i = lattice_origin + Vector3i(x, y, z)
				for tet_index in range(Core.TETS.size()):
					var tet: Array = Core.TETS[tet_index]
					var hit_points: Array[Vector3] = []
					var hit_ids: Array[String] = []
					var hit_edges: Dictionary = {}
					var seen_ids: Dictionary = {}
					for local_edge in [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]:
						var ia: int = int(tet[int(local_edge[0])])
						var ib: int = int(tet[int(local_edge[1])])
						if (samples[ia] >= 0.0) == (samples[ib] >= 0.0):
							continue
						var root: Dictionary = _canonical_volume_root(root_cache, nodes[ia], nodes[ib], samples[ia], samples[ib], points[ia], points[ib])
						if not bool(root.get("valid", false)):
							geometry_errors.append({"cell": _cell_key(cell_id), "tet": tet_index, "reason": "canonical_root_invalid", "detail": root})
							continue
						var root_id: String = String(root.get("root_identity", ""))
						if root_id.is_empty() or not (root.get("point") is Vector3):
							geometry_errors.append({"cell": _cell_key(cell_id), "tet": tet_index, "reason": "canonical_root_identity_or_point_missing"})
							continue
						if not roots.has(root_id):
							roots[root_id] = root.point
						if not root_sources.has(root_id):
							root_sources[root_id] = {"authority": "CANDIDATE_D_MATERIALIZED_FLOAT32_VOLUME", "node_a": [nodes[ia].x, nodes[ia].y, nodes[ia].z], "node_b": [nodes[ib].x, nodes[ib].y, nodes[ib].z]}
						if not seen_ids.has(root_id):
							seen_ids[root_id] = true
							hit_points.append(root.point)
							hit_ids.append(root_id)
							hit_edges[root_id] = [int(local_edge[0]), int(local_edge[1])]
					if hit_ids.size() < 3:
						continue
					var toward_empty: Vector3 = _tetra_toward_empty(points, samples, tet)
					var ordered_points: Array[Vector3] = _order_polygon(hit_points, toward_empty)
					var ordered_ids: Array[String] = _order_root_ids(ordered_points, hit_points, hit_ids)
					if ordered_points.size() != hit_ids.size() or ordered_ids.size() != ordered_points.size():
						geometry_errors.append({"cell": _cell_key(cell_id), "tet": tet_index, "reason": "canonical_polygon_order_failed", "root_count": hit_ids.size()})
						continue
					var polygon_id: String = "%d,%d,%d|tet:%d" % [cell_id.x, cell_id.y, cell_id.z, tet_index]
					var face_ids: Array[String] = []
					for edge_index in range(ordered_ids.size()):
						var first_edge: Array = hit_edges[ordered_ids[edge_index]]
						var second_edge: Array = hit_edges[ordered_ids[(edge_index + 1) % ordered_ids.size()]]
						var local_face: Array[int] = _shared_tetra_face(first_edge, second_edge)
						var face_id: String = "tet-face:%s:%d:%s" % [_cell_key(cell_id), tet_index, _int_list_key(local_face)]
						face_ids.append(face_id)
						var arc_key: String = _arc_key(ordered_ids[edge_index], ordered_ids[(edge_index + 1) % ordered_ids.size()])
						if not arcs.has(arc_key):
							arcs[arc_key] = {"roots": [ordered_ids[edge_index], ordered_ids[(edge_index + 1) % ordered_ids.size()]], "polygon_ids": [], "face_ids": [], "required_incidence": 0}
						var arc: Dictionary = arcs[arc_key]
						arc.polygon_ids.append(polygon_id)
						arc.face_ids.append(face_id)
						arc.required_incidence += 1
						arcs[arc_key] = arc
					polygons.append({"id": polygon_id, "cell": [cell_id.x, cell_id.y, cell_id.z], "tet_index": tet_index, "root_ids": ordered_ids, "points": ordered_points, "face_ids": face_ids, "toward_empty": toward_empty, "realization": "PENDING"})
	if hypothesis == "R10A2_CENTROID_TRIANGLE_SUBDIVISION":
		var refinement_result: Dictionary = _apply_a2_triangle_subdivision(polygons, roots, root_sources)
		if bool(refinement_result.get("valid", false)):
			polygons = refinement_result.polygons
			arcs = refinement_result.arcs
			local_refinement = refinement_result.evidence
		else:
			geometry_errors.append({"reason": "a2_local_refinement_failed", "detail": refinement_result})
	var graph: Dictionary = _topology_graph(roots, root_sources, polygons, arcs, geometry_errors)
	var mesh: Dictionary = Core.new_mesh()
	var emitted_triangles: Array[Dictionary] = []
	var unresolved: Array[Dictionary] = []
	var cutoff_rejections: Array[Dictionary] = []
	for polygon in polygons:
		var triangulation: Dictionary = _triangulate_polygon(polygon, hypothesis)
		if not bool(triangulation.get("valid", false)):
			polygon.realization = "UNRESOLVED"
			unresolved.append({"polygon_id": polygon.id, "reason": triangulation.get("reason", "triangulation_unresolved"), "candidates": triangulation.get("candidates", [])})
			cutoff_rejections.append_array(triangulation.get("rejections", []))
			continue
		var polygon_rows: Array[Dictionary] = []
		var raw_polygon_rows: Variant = triangulation.get("triangles", [])
		if raw_polygon_rows is Array:
			for raw_polygon_row in raw_polygon_rows:
				if raw_polygon_row is Dictionary:
					polygon_rows.append(raw_polygon_row)
		var raw_row_count: int = raw_polygon_rows.size() if raw_polygon_rows is Array else -1
		if polygon_rows.size() != raw_row_count:
			polygon.realization = "UNRESOLVED"
			unresolved.append({"polygon_id": polygon.id, "reason": "triangulation_rows_not_dictionary_array", "raw_count": raw_row_count, "accepted_count": polygon_rows.size()})
			continue
		var emitted_all: bool = true
		for row in polygon_rows:
			var emitted: Dictionary = _emit_triangle(mesh, row.root_ids, row.points, polygon.toward_empty)
			if not bool(emitted.get("valid", false)):
				emitted_all = false
				cutoff_rejections.append({"polygon_id": polygon.id, "triangle_root_ids": row.root_ids, "cross_squared": emitted.get("cross_squared", -1.0), "reason": emitted.get("reason", "emit_rejected")})
				continue
			emitted_triangles.append({"polygon_id": polygon.id, "root_ids": emitted.root_ids, "normal": emitted.normal, "cross_squared": emitted.cross_squared, "construction": triangulation.get("construction", "existing_root_triangulation")})
		polygon.realization = "EMITTED" if emitted_all else "PARTIAL"
		if not emitted_all:
			unresolved.append({"polygon_id": polygon.id, "reason": "required_polygon_triangles_not_all_emitted"})
	var emitted_incidence: Dictionary = _triangle_edge_incidence(emitted_triangles)
	var adjacency_obligations: Array[Dictionary] = []
	var missing_count: int = 0
	var nonmanifold_count: int = 0
	for raw_arc_key in arcs.keys():
		var arc_key: String = String(raw_arc_key)
		var arc: Dictionary = arcs[arc_key]
		var expected: int = int(arc.required_incidence)
		var actual: int = int(emitted_incidence.get(arc_key, 0))
		if actual != expected:
			adjacency_obligations.append({"arc_key": arc_key, "expected_incidence": expected, "realized_incidence": actual, "source_polygons": arc.polygon_ids})
			missing_count += absi(expected - actual)
		if actual > 2:
			nonmanifold_count += 1
	var mesh_topology: Dictionary = Core.topology(mesh, ROI_MIN, ROI_MIN + Vector3(CELLS) * STEP)
	var topology_hash: String = String(graph.get("topology_sha256", ""))
	var winding_valid: bool = int(mesh_topology.get("winding_inconsistencies", -1)) == 0
	var required_complete: bool = unresolved.is_empty() and geometry_errors.is_empty() and missing_count == 0
	var geometry_complete: bool = required_complete and int(mesh_topology.get("internal_open_edges", -1)) == 0 and int(mesh_topology.get("nonmanifold_edges", -1)) == 0 and winding_valid
	return {"valid": geometry_errors.is_empty(), "hypothesis": hypothesis, "mesh": mesh, "mesh_sha256": _mesh_sha(mesh), "topology_graph": graph,
		"topology_sha256": topology_hash, "mesh_topology": mesh_topology, "emitted_triangles": emitted_triangles,
		"unresolved_obligations": unresolved, "cutoff_rejections": cutoff_rejections, "required_adjacency_obligations": adjacency_obligations,
		"required_adjacency_missing_count": missing_count, "required_adjacency_nonmanifold_count": nonmanifold_count,
		"geometry_realization_complete": geometry_complete, "required_topology_complete": required_complete, "winding_valid": winding_valid,
		"local_refinement": {"enabled": hypothesis == "R10A2_CENTROID_TRIANGLE_SUBDIVISION", "source_a1_equal_case_sha256": A2_CAUSAL_A1_CASE_SHA256 if hypothesis == "R10A2_CENTROID_TRIANGLE_SUBDIVISION" else "", "target_parent_cells": A2_REFINE_CELLS.keys() if hypothesis == "R10A2_CENTROID_TRIANGLE_SUBDIVISION" else [], "subdivided_parent_polygons": local_refinement, "subdivided_count": local_refinement.size(), "field_authority": "Candidate D piecewise-linear tetrahedral field; root-triangle centroid lies on source triangle plane; scalar samples unchanged"},
		"metrics": {"root_count": roots.size(), "polygon_count": polygons.size(), "required_arc_count": arcs.size(), "emitted_triangle_count": emitted_triangles.size(),
			"unresolved_polygon_count": unresolved.size(), "cutoff_rejection_count": cutoff_rejections.size(), "topology_build_realize_usec": Time.get_ticks_usec() - begin_usec,
			"fixed_cross_squared_cutoff": CUTOFF_SQUARED, "field_authority": "Candidate D serialized/reloaded float32 materialized volume; no sample mutation"}}

func _apply_a2_triangle_subdivision(source_polygons: Array[Dictionary], roots: Dictionary, root_sources: Dictionary) -> Dictionary:
	var expanded: Array[Dictionary] = []
	var evidence: Array[Dictionary] = []
	for polygon in source_polygons:
		var root_ids: Array = polygon.get("root_ids", [])
		var points: Array = polygon.get("points", [])
		var cell: Array = polygon.get("cell", [])
		var cell_key: String = "%d,%d,%d" % [int(cell[0]), int(cell[1]), int(cell[2])] if cell.size() == 3 else ""
		if root_ids.size() != 3 or points.size() != 3 or not A2_REFINE_CELLS.has(cell_key):
			expanded.append(polygon)
			continue
		var original_cross_squared: float = _cross_squared(points[0], points[1], points[2])
		if original_cross_squared > CUTOFF_SQUARED:
			expanded.append(polygon)
			continue
		var a: Vector3 = points[0]
		var b: Vector3 = points[1]
		var c: Vector3 = points[2]
		var center: Vector3 = (a + b + c) / 3.0
		if not center.is_finite():
			return {"valid": false, "reason": "a2_centroid_nonfinite", "polygon_id": polygon.get("id", "")}
		var parent_id: String = String(polygon.get("id", ""))
		var center_id: String = "a2-centroid|" + parent_id
		if roots.has(center_id):
			return {"valid": false, "reason": "a2_centroid_identity_collision", "polygon_id": parent_id}
		roots[center_id] = center
		var plane_cross: Vector3 = (b - a).cross(c - a)
		var plane_residual: float = absf((center - a).dot(plane_cross.normalized())) if plane_cross.length_squared() > 0.0 else INF
		root_sources[center_id] = {"authority": "PIECEWISE_LINEAR_TETRA_SURFACE_CENTROID", "source_polygon_id": parent_id, "source_cell": cell, "source_tetrahedron": polygon.get("tet_index", -1), "construction": "arithmetic_mean_of_three_existing_surface_roots", "initial_point": [center.x, center.y, center.z], "final_point": [center.x, center.y, center.z], "displacement": 0.0, "source_triangle_plane_residual_world_units": plane_residual, "canonical_sdf_resampled": false, "materialized_samples_mutated": false}
		var parent_faces: Array = polygon.get("face_ids", [])
		if parent_faces.size() != 3:
			return {"valid": false, "reason": "a2_parent_face_arity_invalid", "polygon_id": parent_id}
		var ids: Array[String] = [String(root_ids[0]), String(root_ids[1]), String(root_ids[2])]
		var spoke_a: String = "a2-spoke|" + parent_id + "|" + ids[0]
		var spoke_b: String = "a2-spoke|" + parent_id + "|" + ids[1]
		var spoke_c: String = "a2-spoke|" + parent_id + "|" + ids[2]
		var child_rows: Array[Dictionary] = [
			{"id": parent_id + "|a2-child:0", "root_ids": [ids[0], ids[1], center_id], "points": [a, b, center], "face_ids": [String(parent_faces[0]), spoke_b, spoke_a], "child_index": 0},
			{"id": parent_id + "|a2-child:1", "root_ids": [ids[1], ids[2], center_id], "points": [b, c, center], "face_ids": [String(parent_faces[1]), spoke_c, spoke_b], "child_index": 1},
			{"id": parent_id + "|a2-child:2", "root_ids": [ids[2], ids[0], center_id], "points": [c, a, center], "face_ids": [String(parent_faces[2]), spoke_a, spoke_c], "child_index": 2}
		]
		for child in child_rows:
			expanded.append({"id": child.id, "cell": cell.duplicate(), "tet_index": polygon.get("tet_index", -1), "parent_polygon_id": parent_id, "subdivision_child": child.child_index, "root_ids": child.root_ids, "points": child.points, "face_ids": child.face_ids, "toward_empty": polygon.get("toward_empty", Vector3.ZERO), "realization": "PENDING"})
		evidence.append({"parent_polygon_id": parent_id, "cell": cell.duplicate(), "tet_index": polygon.get("tet_index", -1), "original_cross_squared": original_cross_squared, "centroid_id": center_id, "centroid": [center.x, center.y, center.z], "source_triangle_plane_residual_world_units": plane_residual, "child_cross_squared": [_cross_squared(a, b, center), _cross_squared(b, c, center), _cross_squared(c, a, center)], "child_ids": [child.id for child in child_rows], "topology_policy": "retain_all_three_child_obligations_even_if_fixed_cutoff_rejects_them"})
	var rebuilt_arcs: Dictionary = {}
	for polygon in expanded:
		var ordered_ids: Array = polygon.get("root_ids", [])
		var face_ids: Array = polygon.get("face_ids", [])
		if ordered_ids.size() != face_ids.size():
			return {"valid": false, "reason": "a2_polygon_face_count_mismatch", "polygon_id": polygon.get("id", "")}
		for edge_index in range(ordered_ids.size()):
			var first_id: String = String(ordered_ids[edge_index])
			var second_id: String = String(ordered_ids[(edge_index + 1) % ordered_ids.size()])
			var arc_key: String = _arc_key(first_id, second_id)
			if not rebuilt_arcs.has(arc_key):
				rebuilt_arcs[arc_key] = {"roots": [first_id, second_id], "polygon_ids": [], "face_ids": [], "required_incidence": 0}
			var arc: Dictionary = rebuilt_arcs[arc_key]
			arc.polygon_ids.append(String(polygon.get("id", "")))
			arc.face_ids.append(String(face_ids[edge_index]))
			arc.required_incidence += 1
			rebuilt_arcs[arc_key] = arc
	return {"valid": true, "polygons": expanded, "arcs": rebuilt_arcs, "evidence": evidence}

func _triangulate_polygon(polygon: Dictionary, hypothesis: String) -> Dictionary:
	var ids: Array = polygon.root_ids
	var points: Array = polygon.points
	if ids.size() == 3:
		var cross2: float = _cross_squared(points[0], points[1], points[2])
		if cross2 <= CUTOFF_SQUARED:
			return {"valid": false, "reason": "required_triangle_below_frozen_cutoff", "rejections": [{"polygon_id": polygon.id, "cross_squared": cross2, "reason": "fixed_cutoff"}]}
		return {"valid": true, "construction": "topology_polygon_triangle", "triangles": [{"root_ids": ids.duplicate(), "points": points.duplicate()}], "candidates": [{"cross_squared": cross2}]}
	if ids.size() != 4:
		return {"valid": false, "reason": "unsupported_authority_polygon_size", "candidates": []}
	var candidates: Array[Dictionary] = []
	for diagonal in [[0, 2], [1, 3]]:
		var candidate_rows: Array[Dictionary]
		if diagonal == [0, 2]:
			candidate_rows = [{"indices": [0, 1, 2]}, {"indices": [0, 2, 3]}]
		else:
			candidate_rows = [{"indices": [0, 1, 3]}, {"indices": [1, 2, 3]}]
		var areas: Array[float] = []
		var rows: Array[Dictionary] = []
		var accepted: bool = true
		for candidate_row in candidate_rows:
			var idxs: Array = candidate_row.indices
			var cross2: float = _cross_squared(points[int(idxs[0])], points[int(idxs[1])], points[int(idxs[2])])
			areas.append(cross2)
			if cross2 <= CUTOFF_SQUARED:
				accepted = false
			rows.append({"root_ids": [ids[int(idxs[0])], ids[int(idxs[1])], ids[int(idxs[2])]], "points": [points[int(idxs[0])], points[int(idxs[1])], points[int(idxs[2])]]})
		candidates.append({"diagonal": diagonal, "accepted": accepted, "cross_squared": areas, "minimum_cross_squared": minf(areas[0], areas[1]), "rows": rows})
	if hypothesis == "R10A1_ALT_DIAGONAL_MAX_MIN_AREA":
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if bool(a.accepted) != bool(b.accepted):
				return bool(a.accepted)
			if float(a.minimum_cross_squared) != float(b.minimum_cross_squared):
				return float(a.minimum_cross_squared) > float(b.minimum_cross_squared)
			var a_diagonal: Array = a.diagonal
			var b_diagonal: Array = b.diagonal
			if int(a_diagonal[0]) != int(b_diagonal[0]):
				return int(a_diagonal[0]) < int(b_diagonal[0])
			return int(a_diagonal[1]) < int(b_diagonal[1]))
	else:
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.diagonal) < String(b.diagonal))
	for candidate in candidates:
		if bool(candidate.accepted):
			return {"valid": true, "construction": "alternate_quad_diagonal_maximize_min_cross_squared", "triangles": candidate.rows, "candidates": candidates}
	var rejected: Array[Dictionary] = []
	for candidate in candidates:
		for idx in range(candidate.cross_squared.size()):
			if float(candidate.cross_squared[idx]) <= CUTOFF_SQUARED:
				rejected.append({"polygon_id": polygon.id, "diagonal": candidate.diagonal, "candidate_triangle": idx, "cross_squared": candidate.cross_squared[idx], "reason": "fixed_cutoff"})
	return {"valid": false, "reason": "both_quad_diagonals_blocked_by_frozen_cutoff", "candidates": candidates, "rejections": rejected}

func _emit_triangle(mesh: Dictionary, root_ids: Array, points: Array, toward_empty: Vector3) -> Dictionary:
	if root_ids.size() != 3 or points.size() != 3:
		return {"valid": false, "reason": "triangle_arity_invalid", "cross_squared": -1.0}
	var ids: Array = root_ids.duplicate()
	var p: Array = points.duplicate()
	var cross: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	var cross2: float = cross.length_squared()
	if not is_finite(cross2) or cross2 <= CUTOFF_SQUARED:
		return {"valid": false, "reason": "frozen_cross_squared_cutoff", "cross_squared": cross2}
	if cross.dot(toward_empty) < 0.0:
		var id_swap = ids[1]; ids[1] = ids[2]; ids[2] = id_swap
		var point_swap = p[1]; p[1] = p[2]; p[2] = point_swap
		cross = (p[1] - p[0]).cross(p[2] - p[0])
	var normal: Vector3 = cross.normalized()
	mesh.positions.append_array(PackedVector3Array([p[0], p[1], p[2]]))
	mesh.normals.append_array(PackedVector3Array([normal, normal, normal]))
	return {"valid": true, "root_ids": ids, "normal": normal, "cross_squared": cross2}

func _topology_graph(roots: Dictionary, root_sources: Dictionary, polygons: Array[Dictionary], arcs: Dictionary, geometry_errors: Array[Dictionary]) -> Dictionary:
	var root_rows: Array = []
	var root_ids: Array = roots.keys()
	root_ids.sort()
	for raw_id in root_ids:
		var root_id: String = String(raw_id)
		var point: Vector3 = roots[root_id]
		root_rows.append([root_id, point.x, point.y, point.z, root_sources.get(root_id, {})])
	var polygon_rows: Array = []
	var sorted_polygons: Array[Dictionary] = polygons.duplicate()
	sorted_polygons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	for polygon in sorted_polygons:
		polygon_rows.append([polygon.id, polygon.cell, polygon.tet_index, polygon.root_ids, polygon.face_ids, "CANDIDATE_D_VOLUME"])
	var arc_rows: Array = []
	var arc_keys: Array = arcs.keys()
	arc_keys.sort()
	var unresolved_arcs: Array = []
	var nonmanifold_arcs: Array = []
	for raw_key in arc_keys:
		var arc_key: String = String(raw_key)
		var arc: Dictionary = arcs[arc_key]
		var a: Vector3 = roots[String(arc.roots[0])]
		var b: Vector3 = roots[String(arc.roots[1])]
		var roi_boundary: bool = _arc_on_roi_boundary(a, b)
		var owners: Array = arc.polygon_ids.duplicate()
		owners.sort()
		arc_rows.append([arc_key, arc.roots, arc.required_incidence, owners, arc.face_ids, roi_boundary, owners[0] if not owners.is_empty() else ""])
		if int(arc.required_incidence) > (1 if roi_boundary else 2):
			nonmanifold_arcs.append(arc_key)
		elif int(arc.required_incidence) < (1 if roi_boundary else 2):
			unresolved_arcs.append(arc_key)
	var canonical: Dictionary = {"schema": "P3.1.R10A.TopologyGraph.v1", "roots": root_rows, "polygons": polygon_rows, "arcs": arc_rows, "geometry_errors": geometry_errors}
	var canonical_bytes: PackedByteArray = JSON.stringify(canonical).to_utf8_buffer()
	return {"valid": unresolved_arcs.is_empty() and nonmanifold_arcs.is_empty() and geometry_errors.is_empty(), "schema": canonical.schema,
		"root_count": roots.size(), "polygon_count": polygons.size(), "arc_count": arcs.size(), "unresolved_required_arcs": unresolved_arcs,
		"nonmanifold_required_arcs": nonmanifold_arcs, "geometry_errors": geometry_errors, "canonical": canonical,
		"topology_sha256": Core.sha256(canonical_bytes), "authority": "topology graph built from exact Candidate D materialized scalar edge roots before triangle realization"}

func _triangle_edge_incidence(triangles: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.root_ids
		for edge_index in range(3):
			var key: String = _arc_key(String(ids[edge_index]), String(ids[(edge_index + 1) % 3]))
			result[key] = int(result.get(key, 0)) + 1
	return result

func _shared_tetra_face(a: Array, b: Array) -> Array[int]:
	var union: Dictionary = {}
	for idx in a: union[int(idx)] = true
	for idx in b: union[int(idx)] = true
	var result: Array[int] = []
	for key in union.keys(): result.append(int(key))
	result.sort()
	return result if result.size() == 3 else []

func _int_list_key(values: Array[int]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value in values: parts.append(str(value))
	return ",".join(parts)

func _arc_key(a: String, b: String) -> String:
	return a + ARC_SEPARATOR + b if a < b else b + ARC_SEPARATOR + a

func _arc_on_roi_boundary(a: Vector3, b: Vector3) -> bool:
	for axis in range(3):
		if absf(a[axis] - b[axis]) <= 2.0e-6 and (absf(a[axis] - ROI_MIN[axis]) <= 2.0e-6 or absf(a[axis] - (ROI_MIN + Vector3(CELLS) * STEP)[axis]) <= 2.0e-6):
			return true
	return false

func _cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]

func _idx(x: int, y: int, z: int, dims: Vector3i) -> int:
	return (y * dims.z + z) * dims.x + x

func _cross_squared(a: Vector3, b: Vector3, c: Vector3) -> float:
	return (b - a).cross(c - a).length_squared()

func _mesh_sha(mesh: Dictionary) -> String:
	var position_bytes: PackedByteArray = mesh.positions.to_byte_array()
	var normal_bytes: PackedByteArray = mesh.normals.to_byte_array()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(("%d:%d:" % [position_bytes.size(), normal_bytes.size()]).to_utf8_buffer())
	if not position_bytes.is_empty(): context.update(position_bytes)
	if not normal_bytes.is_empty(): context.update(normal_bytes)
	return context.finish().hex_encode()
