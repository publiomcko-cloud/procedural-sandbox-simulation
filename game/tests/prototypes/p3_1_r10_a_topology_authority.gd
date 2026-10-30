extends "res://tests/prototypes/p3_1_r9_2_candidate_impl.gd"

const Field := preload("res://scripts/terrain/sdf_world.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")

## R10-A test-only topology-first realization over Candidate D's reloaded
## materialized float32 volume.  The polygon/root/arc graph is complete before
## any triangle is emitted and is the authority for this experiment.
const CUTOFF_SQUARED: float = 1.0e-12
const ARC_SEPARATOR: String = "\u001f"
const A2_CAUSAL_A1_CASE_SHA256: String = "700c59861d8011f61553848c195e10bb4b2e66cc42433185a56a4720af1f83be"
const A2_REFINE_CELLS: Dictionary = {"60,8,25": true, "61,8,25": true, "62,9,24": true, "66,7,29": true}
const A4_PATCH_HALO_CELLS: int = 1
const A4_PATCH_MAX_POLYGONS: int = 512
const A4_PATCH_MAX_BOUNDARY_ROOTS: int = 96
const A6_MAX_EDGE_FLIPS: int = 512

func realize_topology(values: PackedFloat32Array, hypothesis: String, snapshot: Dictionary = {}, seed: int = 131102026) -> Dictionary:
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
	var source_polygons: Array[Dictionary] = polygons.duplicate(true)
	var source_arcs: Dictionary = arcs.duplicate(true)
	var component_reconstruction: Dictionary = {"valid": true, "applied": false, "source_obligations_valid": true, "patches": [], "reason": "NOT_APPLICABLE"}
	if hypothesis in ["R10A2_CENTROID_TRIANGLE_SUBDIVISION", "R10A3_CANONICAL_FIELD_STEINER"]:
		var refinement_result: Dictionary = _apply_triangle_subdivision(polygons, roots, root_sources, hypothesis, snapshot, seed)
		if bool(refinement_result.get("valid", false)):
			polygons = refinement_result.polygons
			arcs = refinement_result.arcs
			local_refinement = refinement_result.evidence
		else:
			geometry_errors.append({"reason": "a2_local_refinement_failed", "detail": refinement_result})
	elif hypothesis in ["R10A4_MULTI_CELL_COMPONENT_RECONSTRUCTION", "R10A5_INTERIOR_ROOT_PRESERVING_RETRIANGULATION", "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION"]:
		var preserve_interior_roots: bool = hypothesis in ["R10A5_INTERIOR_ROOT_PRESERVING_RETRIANGULATION", "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION"]
		var optimize_edge_flips: bool = hypothesis == "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION"
		component_reconstruction = _apply_multi_cell_component_reconstruction(polygons, roots, source_arcs, values, dims, preserve_interior_roots, optimize_edge_flips)
		if bool(component_reconstruction.get("valid", false)):
			polygons = component_reconstruction.get("polygons", polygons)
			arcs = component_reconstruction.get("arcs", arcs)
			local_refinement.clear()
			var raw_component_patches: Variant = component_reconstruction.get("patches", [])
			if raw_component_patches is Array:
				for raw_patch in raw_component_patches:
					if raw_patch is Dictionary: local_refinement.append(raw_patch)
				if local_refinement.size() != raw_component_patches.size(): geometry_errors.append({"reason": "component_patch_rows_failed_dictionary_validation"})
			else:
				geometry_errors.append({"reason": "component_patch_rows_not_array"})
		else:
			geometry_errors.append({"reason": "component_reconstruction_failed", "detail": component_reconstruction})
	var graph: Dictionary = _topology_graph(roots, root_sources, polygons, arcs, geometry_errors)
	var component_reconstruction_enabled: bool = hypothesis in ["R10A4_MULTI_CELL_COMPONENT_RECONSTRUCTION", "R10A5_INTERIOR_ROOT_PRESERVING_RETRIANGULATION", "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION"]
	var source_graph: Dictionary = _topology_graph(roots, root_sources, source_polygons, source_arcs, []) if component_reconstruction_enabled else {}
	var source_graph_proof: Dictionary = {"schema": source_graph.get("schema", ""), "topology_sha256": source_graph.get("topology_sha256", ""), "valid": source_graph.get("valid", false), "root_count": source_graph.get("root_count", 0), "polygon_count": source_graph.get("polygon_count", 0), "arc_count": source_graph.get("arc_count", 0), "unresolved_required_arc_count": source_graph.get("unresolved_required_arcs", []).size(), "nonmanifold_required_arc_count": source_graph.get("nonmanifold_required_arcs", []).size()}
	if component_reconstruction_enabled:
		component_reconstruction["source_graph_valid"] = bool(source_graph.get("valid", false))
		component_reconstruction["source_obligations_valid"] = bool(component_reconstruction.get("source_obligations_valid", false)) and bool(source_graph.get("valid", false))
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
			emitted_triangles.append({"polygon_id": polygon.id, "source_polygon_ids": polygon.get("source_polygon_ids", [polygon.id]), "patch_id": polygon.get("patch_id", ""), "root_ids": emitted.root_ids, "normal": emitted.normal, "cross_squared": emitted.cross_squared, "construction": triangulation.get("construction", "existing_root_triangulation")})
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
	var source_obligations_valid: bool = bool(component_reconstruction.get("source_obligations_valid", true))
	var required_complete: bool = unresolved.is_empty() and geometry_errors.is_empty() and missing_count == 0 and source_obligations_valid
	var geometry_complete: bool = required_complete and int(mesh_topology.get("internal_open_edges", -1)) == 0 and int(mesh_topology.get("nonmanifold_edges", -1)) == 0 and winding_valid
	return {"valid": geometry_errors.is_empty(), "hypothesis": hypothesis, "mesh": mesh, "mesh_sha256": _mesh_sha(mesh), "topology_graph": graph, "source_topology_graph_proof": source_graph_proof, "component_reconstruction": component_reconstruction,
		"topology_sha256": topology_hash, "mesh_topology": mesh_topology, "emitted_triangles": emitted_triangles,
		"unresolved_obligations": unresolved, "cutoff_rejections": cutoff_rejections, "required_adjacency_obligations": adjacency_obligations,
		"required_adjacency_missing_count": missing_count, "required_adjacency_nonmanifold_count": nonmanifold_count,
		"geometry_realization_complete": geometry_complete, "required_topology_complete": required_complete, "winding_valid": winding_valid,
		"local_refinement": {"enabled": hypothesis in ["R10A2_CENTROID_TRIANGLE_SUBDIVISION", "R10A3_CANONICAL_FIELD_STEINER", "R10A4_MULTI_CELL_COMPONENT_RECONSTRUCTION", "R10A5_INTERIOR_ROOT_PRESERVING_RETRIANGULATION", "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION"], "source_a1_equal_case_sha256": A2_CAUSAL_A1_CASE_SHA256 if hypothesis in ["R10A2_CENTROID_TRIANGLE_SUBDIVISION", "R10A3_CANONICAL_FIELD_STEINER", "R10A4_MULTI_CELL_COMPONENT_RECONSTRUCTION", "R10A5_INTERIOR_ROOT_PRESERVING_RETRIANGULATION", "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION"] else "", "target_parent_cells": A2_REFINE_CELLS.keys() if hypothesis in ["R10A2_CENTROID_TRIANGLE_SUBDIVISION", "R10A3_CANONICAL_FIELD_STEINER", "R10A4_MULTI_CELL_COMPONENT_RECONSTRUCTION", "R10A5_INTERIOR_ROOT_PRESERVING_RETRIANGULATION", "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION"] else [], "subdivided_parent_polygons": local_refinement, "subdivided_count": local_refinement.size(), "field_authority": "Candidate D piecewise-linear tetrahedral field for A2, A4, A5 and A6; canonical SDF plus ordered snapshot for A3; scalar volume unchanged"},
		"metrics": {"root_count": roots.size(), "polygon_count": polygons.size(), "required_arc_count": arcs.size(), "emitted_triangle_count": emitted_triangles.size(),
			"unresolved_polygon_count": unresolved.size(), "cutoff_rejection_count": cutoff_rejections.size(), "topology_build_realize_usec": Time.get_ticks_usec() - begin_usec,
			"fixed_cross_squared_cutoff": CUTOFF_SQUARED, "field_authority": "Candidate D serialized/reloaded float32 materialized volume; no sample mutation"}}

func _apply_triangle_subdivision(source_polygons: Array[Dictionary], roots: Dictionary, root_sources: Dictionary, hypothesis: String, snapshot: Dictionary, seed: int) -> Dictionary:
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
		var canonical_assisted: bool = hypothesis == "R10A3_CANONICAL_FIELD_STEINER"
		var initial_center: Vector3 = (a + b + c) / 3.0
		var center: Vector3 = initial_center
		var field_projection: Dictionary = {"valid": true, "canonical_field_used": false, "initial_density": null, "final_density": null, "iterations": 0, "reason": "AFFINE_TRIANGLE_CENTROID"}
		if hypothesis == "R10A3_CANONICAL_FIELD_STEINER":
			field_projection = _project_steiner_to_canonical(initial_center, snapshot, seed)
			if not bool(field_projection.get("valid", false)):
				return {"valid": false, "reason": "a3_field_constrained_steiner_projection_failed", "polygon_id": polygon.get("id", ""), "detail": field_projection}
			center = field_projection.point
		if not center.is_finite():
			return {"valid": false, "reason": "a2_centroid_nonfinite", "polygon_id": polygon.get("id", "")}
		var parent_id: String = String(polygon.get("id", ""))
		var center_id: String = ("a3-steiner|" if canonical_assisted else "a2-centroid|") + parent_id
		if roots.has(center_id):
			return {"valid": false, "reason": "a2_centroid_identity_collision", "polygon_id": parent_id}
		roots[center_id] = center
		var plane_cross: Vector3 = (b - a).cross(c - a)
		var plane_residual: float = absf((center - a).dot(plane_cross.normalized())) if plane_cross.length_squared() > 0.0 else INF
		root_sources[center_id] = {"authority": "CANONICAL_SDF_ASSISTED_STEINER" if canonical_assisted else "PIECEWISE_LINEAR_TETRA_SURFACE_CENTROID", "source_polygon_id": parent_id, "source_cell": cell, "source_tetrahedron": polygon.get("tet_index", -1), "construction": "canonical_sdf_projected_triangle_centroid" if canonical_assisted else "arithmetic_mean_of_three_existing_surface_roots", "initial_point": [initial_center.x, initial_center.y, initial_center.z], "final_point": [center.x, center.y, center.z], "displacement": initial_center.distance_to(center), "source_triangle_plane_residual_world_units": plane_residual, "canonical_sdf_projection": field_projection, "materialized_samples_mutated": false}
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
		var child_ids: Array[String] = []
		for child in child_rows:
			child_ids.append(String(child.get("id", "")))
		evidence.append({"parent_polygon_id": parent_id, "cell": cell.duplicate(), "tet_index": polygon.get("tet_index", -1), "original_cross_squared": original_cross_squared, "construction": "canonical_sdf_assisted_steiner" if canonical_assisted else "affine_triangle_centroid_subdivision", "initial_point": [initial_center.x, initial_center.y, initial_center.z], "centroid_id": center_id, "final_point": [center.x, center.y, center.z], "displacement": initial_center.distance_to(center), "canonical_field_projection": field_projection, "source_triangle_plane_residual_world_units": plane_residual, "child_cross_squared": [_cross_squared(a, b, center), _cross_squared(b, c, center), _cross_squared(c, a, center)], "child_ids": child_ids, "topology_policy": "retain_all_three_child_obligations_even_if_fixed_cutoff_rejects_them"})
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

func _apply_multi_cell_component_reconstruction(source_polygons: Array[Dictionary], roots: Dictionary, source_arcs: Dictionary, values: PackedFloat32Array, dims: Vector3i, preserve_interior_roots: bool, optimize_edge_flips: bool = false) -> Dictionary:
	var selected: Dictionary = {}
	for polygon in source_polygons:
		var cell: Array = polygon.get("cell", [])
		if cell.size() != 3: continue
		for raw_target in A2_REFINE_CELLS.keys():
			var target_parts: PackedStringArray = String(raw_target).split(",")
			if target_parts.size() != 3: continue
			var within_halo: bool = true
			for axis in range(3):
				if absi(int(cell[axis]) - int(target_parts[axis])) > A4_PATCH_HALO_CELLS: within_halo = false
			if within_halo:
				selected[String(polygon.get("id", ""))] = polygon
				break
	if selected.is_empty():
		return {"valid": true, "applied": false, "source_obligations_valid": true, "reason": "no_polygons_in_bounded_target_patch", "polygons": source_polygons, "arcs": source_arcs, "patches": []}
	if selected.size() > A4_PATCH_MAX_POLYGONS:
		return {"valid": true, "applied": false, "source_obligations_valid": true, "reason": "bounded_patch_polygon_limit_exceeded", "selected_polygon_count": selected.size(), "limit": A4_PATCH_MAX_POLYGONS, "polygons": source_polygons, "arcs": source_arcs, "patches": []}
	var selected_ids: Array = selected.keys(); selected_ids.sort()
	var parent: Dictionary = {}
	var edge_members: Dictionary = {}
	for polygon_id in selected_ids:
		parent[String(polygon_id)] = String(polygon_id)
		var polygon: Dictionary = selected[String(polygon_id)]
		var ids: Array = polygon.get("root_ids", [])
		for edge_index in range(ids.size()):
			var edge_key: String = _arc_key(String(ids[edge_index]), String(ids[(edge_index + 1) % ids.size()]))
			if not edge_members.has(edge_key): edge_members[edge_key] = []
			edge_members[edge_key].append(String(polygon_id))
	for edge_key in edge_members.keys():
		var members: Array = edge_members[edge_key]
		members.sort()
		for member_index in range(1, members.size()): _union_polygon_owners(parent, String(members[0]), String(members[member_index]))
	var component_members: Dictionary = {}
	for polygon_id in selected_ids:
		var component_id: String = _find_polygon_owner(parent, String(polygon_id))
		if not component_members.has(component_id): component_members[component_id] = []
		component_members[component_id].append(String(polygon_id))
	var component_ids: Array = component_members.keys(); component_ids.sort()
	var patches: Array[Dictionary] = []
	var source_obligations_valid: bool = true
	for component_id in component_ids:
		var members: Array = component_members[component_id]; members.sort()
		var group_polygons: Array[Dictionary] = []
		var needs_reconstruction: bool = false
		for member in members:
			var polygon: Dictionary = selected[String(member)]
			group_polygons.append(polygon)
			if _authority_polygon_has_cutoff_triangle(polygon): needs_reconstruction = true
		if not needs_reconstruction: continue
		var record: Dictionary = {"component_id": String(component_id), "source_polygon_ids": members, "source_cell_count": _unique_polygon_cell_count(group_polygons), "status": "PENDING", "source_authority": "CANDIDATE_D_MATERIALIZED_FLOAT32_SCALAR_VOLUME", "construction": "BOUNDED_MULTI_CELL_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION" if optimize_edge_flips else ("BOUNDED_MULTI_CELL_INTERIOR_ROOT_PRESERVING_RETRIANGULATION" if preserve_interior_roots else "BOUNDED_MULTI_CELL_BOUNDARY_ONLY_RETRIANGULATION"), "preserve_interior_roots": preserve_interior_roots, "optimize_edge_flips": optimize_edge_flips}
		if members.size() < 2:
			record.status = "UNRESOLVED"
			record.reason = "cutoff_polygon_has_no_adjacent_polygon_inside_bounded_patch"
			patches.append(record)
			continue
		var edge_occurrences: Dictionary = {}
		var source_root_set: Dictionary = {}
		for polygon in group_polygons:
			var ids: Array = polygon.get("root_ids", [])
			var faces: Array = polygon.get("face_ids", [])
			if ids.size() < 3 or ids.size() != faces.size():
				record.status = "UNRESOLVED"
				record.reason = "source_polygon_root_face_arity_invalid"
				break
			for root_id in ids: source_root_set[String(root_id)] = true
			for edge_index in range(ids.size()):
				var left: String = String(ids[edge_index])
				var right: String = String(ids[(edge_index + 1) % ids.size()])
				var edge_key: String = _arc_key(left, right)
				if not edge_occurrences.has(edge_key): edge_occurrences[edge_key] = []
				edge_occurrences[edge_key].append({"roots": [left, right], "polygon_id": String(polygon.get("id", "")), "face_id": String(faces[edge_index])})
		if String(record.get("status", "")) == "UNRESOLVED":
			patches.append(record)
			continue
		var boundary_rows: Array[Dictionary] = []
		var boundary_face_ids: Dictionary = {}
		var internal_arc_keys: Array[String] = []
		var invalid_edge_multiplicity: Array[String] = []
		for raw_edge_key in edge_occurrences.keys():
			var edge_key: String = String(raw_edge_key)
			var occurrences: Array = edge_occurrences[edge_key]
			if occurrences.size() == 1:
				var occurrence: Dictionary = occurrences[0]
				boundary_rows.append({"edge_key": edge_key, "roots": occurrence.roots})
				boundary_face_ids[edge_key] = occurrence.face_id
			elif occurrences.size() == 2:
				internal_arc_keys.append(edge_key)
			else:
				invalid_edge_multiplicity.append(edge_key)
		boundary_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.edge_key) < String(b.edge_key))
		internal_arc_keys.sort()
		if not invalid_edge_multiplicity.is_empty():
			record.status = "UNRESOLVED"
			record.reason = "source_component_has_nonmanifold_edge_multiplicity"
			record.nonmanifold_source_edges = invalid_edge_multiplicity
			patches.append(record)
			continue
		var boundary: Dictionary = _extract_edge_loops(boundary_rows)
		record.boundary = boundary
		if int(boundary.get("closed_loop_count", 0)) != 1 or int(boundary.get("open_path_count", 0)) != 0 or boundary.get("paths", []).size() != 1:
			record.status = "UNRESOLVED"
			record.reason = "bounded_component_boundary_is_not_one_closed_loop"
			patches.append(record)
			continue
		var boundary_roots: Array = boundary.paths[0].get("root_ids", [])
		if boundary_roots.size() < 3 or boundary_roots.size() > A4_PATCH_MAX_BOUNDARY_ROOTS:
			record.status = "UNRESOLVED"
			record.reason = "boundary_root_count_outside_bounded_triangulator"
			record.boundary_root_count = boundary_roots.size()
			patches.append(record)
			continue
		var all_roots_on_boundary: bool = source_root_set.size() == boundary_roots.size()
		for boundary_root in boundary_roots:
			if not source_root_set.has(String(boundary_root)): all_roots_on_boundary = false
		if not all_roots_on_boundary and not preserve_interior_roots:
			record.status = "UNRESOLVED"
			record.reason = "component_contains_interior_roots_not_supported_by_boundary_only_patch"
			record.source_root_count = source_root_set.size()
			record.boundary_root_count = boundary_roots.size()
			patches.append(record)
			continue
		var interior_root_ids: Array[String] = []
		for source_root in source_root_set.keys():
			if not boundary_roots.has(String(source_root)): interior_root_ids.append(String(source_root))
		interior_root_ids.sort()
		record.source_root_count = source_root_set.size()
		record.boundary_root_count = boundary_roots.size()
		record.interior_root_count = interior_root_ids.size()
		var source_edge_count: int = edge_occurrences.size()
		var euler_characteristic: int = source_root_set.size() - source_edge_count + group_polygons.size()
		record.source_euler_characteristic = euler_characteristic
		if euler_characteristic != 1:
			record.status = "UNRESOLVED"
			record.reason = "bounded_source_component_is_not_a_topological_disk"
			patches.append(record)
			continue
		var triangulation: Dictionary = _triangulate_boundary_cycle(boundary_roots, roots)
		if bool(triangulation.get("valid", false)) and preserve_interior_roots and not interior_root_ids.is_empty():
			var insertion: Dictionary = _insert_interior_roots_into_triangulation(triangulation, interior_root_ids, roots, optimize_edge_flips)
			triangulation = insertion
		record.triangulation = triangulation
		if not bool(triangulation.get("valid", false)):
			record.status = "UNRESOLVED"
			record.reason = "component_triangulation_failed_under_fixed_cutoff"
			patches.append(record)
			continue
		var realized_source_roots: Dictionary = {}
		for triangle_row in triangulation.get("triangles", []):
			for triangle_root in triangle_row.get("root_ids", []): realized_source_roots[String(triangle_root)] = true
		var all_source_roots_realized: bool = realized_source_roots.size() == source_root_set.size()
		for source_root in source_root_set.keys():
			if not realized_source_roots.has(String(source_root)): all_source_roots_realized = false
		if not all_source_roots_realized:
			record.status = "UNRESOLVED"
			record.reason = "component_retriangulation_dropped_or_duplicated_source_root"
			record.realized_source_root_count = realized_source_roots.size()
			patches.append(record)
			continue
		var average_empty: Vector3 = Vector3.ZERO
		for polygon in group_polygons: average_empty += polygon.get("toward_empty", Vector3.ZERO)
		if not average_empty.is_finite() or average_empty.length_squared() == 0.0:
			record.status = "UNRESOLVED"
			record.reason = "source_component_has_no_finite_orientation_authority"
			patches.append(record)
			continue
		average_empty = average_empty.normalized()
		var component_key: String = String(component_id)
		var patch_prefix: String = "r10a6-patch|" if optimize_edge_flips else ("r10a5-patch|" if preserve_interior_roots else "r10a4-patch|")
		var replacement_polygons: Array[Dictionary] = []
		var replacement_ids: Array[String] = []
		var replacement_edge_occurrences: Dictionary = {}
		var field_residual_rows: Array[Dictionary] = []
		var triangle_rows: Array[Dictionary] = []
		var raw_triangulation_rows: Variant = triangulation.get("triangles", [])
		if raw_triangulation_rows is Array:
			for raw_triangle_row in raw_triangulation_rows:
				if raw_triangle_row is Dictionary: triangle_rows.append(raw_triangle_row)
			if triangle_rows.size() != raw_triangulation_rows.size():
				record.status = "UNRESOLVED"
				record.reason = "component_triangulation_rows_not_dictionary_array"
				patches.append(record)
				continue
		else:
			record.status = "UNRESOLVED"
			record.reason = "component_triangulation_rows_not_array"
			patches.append(record)
			continue
		for triangle_index in range(triangle_rows.size()):
			var triangle: Dictionary = triangle_rows[triangle_index]
			var triangle_ids: Array = triangle.get("root_ids", [])
			var triangle_points: Array = triangle.get("points", [])
			var face_ids: Array[String] = []
			for edge_index in range(3):
				var edge_key: String = _arc_key(String(triangle_ids[edge_index]), String(triangle_ids[(edge_index + 1) % 3]))
				if boundary_face_ids.has(edge_key): face_ids.append(String(boundary_face_ids[edge_key]))
				else: face_ids.append("r10a4-patch|" + component_key + "|" + edge_key)
			var centroid: Vector3 = (triangle_points[0] + triangle_points[1] + triangle_points[2]) / 3.0
			var sampled_field: Dictionary = _sample_materialized_piecewise_field(centroid, values, dims)
			if not bool(sampled_field.get("valid", false)):
				record.status = "UNRESOLVED"
				record.reason = "replacement_triangle_centroid_outside_materialized_tetrahedral_domain"
				record.failed_centroid = [centroid.x, centroid.y, centroid.z]
				break
			field_residual_rows.append({"triangle_index": triangle_index, "centroid": [centroid.x, centroid.y, centroid.z], "piecewise_materialized_density": sampled_field.density, "field_residual": absf(float(sampled_field.density)), "source_tetrahedron": sampled_field.tetrahedron_index})
			var owner_cell: Array[int] = [floori(centroid.x / STEP), floori(centroid.y / STEP), floori(centroid.z / STEP)]
			var triangle_id: String = patch_prefix + component_key + "|triangle:" + str(triangle_index)
			replacement_ids.append(triangle_id)
			replacement_polygons.append({"id": triangle_id, "cell": owner_cell, "tet_index": -1, "root_ids": triangle_ids, "points": triangle_points, "face_ids": face_ids, "toward_empty": average_empty, "realization": "PENDING", "patch_id": component_key, "source_polygon_ids": members.duplicate()})
			for edge_index in range(3):
				var edge_key: String = _arc_key(String(triangle_ids[edge_index]), String(triangle_ids[(edge_index + 1) % 3]))
				if not replacement_edge_occurrences.has(edge_key): replacement_edge_occurrences[edge_key] = 0
				replacement_edge_occurrences[edge_key] += 1
		if String(record.get("status", "")) == "UNRESOLVED":
			patches.append(record)
			continue
		var boundary_arc_preservation: Array[Dictionary] = []
		var boundary_preserved: bool = true
		for edge in boundary_rows:
			var edge_key: String = String(edge.edge_key)
			var expected: int = int(source_arcs.get(edge_key, {}).get("required_incidence", 0))
			var observed: int = int(replacement_edge_occurrences.get(edge_key, 0))
			boundary_arc_preservation.append({"edge_key": edge_key, "expected_source_incidence": expected, "replacement_incidence": observed})
			if observed != 1 or expected < 1: boundary_preserved = false
		if not boundary_preserved:
			record.status = "UNRESOLVED"
			record.reason = "patch_changes_or_drops_source_boundary_arc"
			record.boundary_arc_preservation = boundary_arc_preservation
			patches.append(record)
			continue
		record.status = "RECONSTRUCTED"
		record.source_boundary_arc_keys = boundary_rows.map(func(edge: Dictionary) -> String: return String(edge.edge_key))
		record.superseded_internal_arc_keys = internal_arc_keys
		record.replacement_polygon_ids = replacement_ids
		record.source_to_replacement = {"source_polygon_ids": members.duplicate(), "replacement_polygon_ids": replacement_ids, "equivalence_basis": "one connected Euler-characteristic-one polygon disk replaced by a boundary-loop triangulation with all source root identities retained; bounded internal diagonal flips preserve the exact boundary; no new or moved vertices" if optimize_edge_flips else ("one connected Euler-characteristic-one polygon disk replaced by a boundary-loop triangulation with all source root identities retained; boundary vertices/arcs fixed; no new or moved vertices" if preserve_interior_roots else "one connected Euler-characteristic-one polygon disk replaced by an n-2 triangulation of the identical ordered boundary root loop; boundary vertices/arcs fixed; no Steiner vertices")}
		record.boundary_arc_preservation = boundary_arc_preservation
		record.replacement_cross_squared = triangle_rows.map(func(row: Dictionary) -> float: return _cross_squared(row.points[0], row.points[1], row.points[2]))
		record.piecewise_materialized_field_centroid_residuals = field_residual_rows
		record.replacement_polygons = replacement_polygons
		patches.append(record)
		if not boundary_preserved: source_obligations_valid = false
	var expanded: Array[Dictionary] = []
	var emitted_components: Dictionary = {}
	for polygon in source_polygons:
		var polygon_id: String = String(polygon.get("id", ""))
		var replacement_key: String = ""
		for component_record in patches:
			if String(component_record.get("status", "")) == "RECONSTRUCTED" and component_record.get("source_polygon_ids", []).has(polygon_id):
				replacement_key = String(component_record.get("component_id", ""))
				break
		if replacement_key.is_empty():
			expanded.append(polygon)
		elif not emitted_components.has(replacement_key):
			emitted_components[replacement_key] = true
			for record in patches:
				if String(record.get("component_id", "")) == replacement_key and String(record.get("status", "")) == "RECONSTRUCTED":
					expanded.append_array(record.get("replacement_polygons", []))
	var rebuilt_arcs: Dictionary = _build_arcs_from_polygons(expanded)
	for record in patches:
		if String(record.get("status", "")) == "RECONSTRUCTED":
			var boundary_preserved: bool = true
			for edge_key in record.get("source_boundary_arc_keys", []):
				var source_expected: int = int(source_arcs.get(String(edge_key), {}).get("required_incidence", 0))
				var replacement_incidence: int = int(rebuilt_arcs.get(String(edge_key), {}).get("required_incidence", 0))
				if source_expected != replacement_incidence: boundary_preserved = false
			record["global_source_boundary_obligations_preserved"] = boundary_preserved
			if not boundary_preserved: source_obligations_valid = false
	return {"valid": true, "applied": not emitted_components.is_empty(), "source_obligations_valid": source_obligations_valid, "reason": "bounded_component_patch_attempted", "selected_polygon_count": selected.size(), "polygons": expanded, "arcs": rebuilt_arcs, "patches": patches}

func _authority_polygon_has_cutoff_triangle(polygon: Dictionary) -> bool:
	var points: Array = polygon.get("points", [])
	if points.size() == 3: return _cross_squared(points[0], points[1], points[2]) <= CUTOFF_SQUARED
	if points.size() != 4: return false
	var first_valid: bool = _cross_squared(points[0], points[1], points[2]) > CUTOFF_SQUARED and _cross_squared(points[0], points[2], points[3]) > CUTOFF_SQUARED
	var second_valid: bool = _cross_squared(points[0], points[1], points[3]) > CUTOFF_SQUARED and _cross_squared(points[1], points[2], points[3]) > CUTOFF_SQUARED
	return not first_valid and not second_valid

func _unique_polygon_cell_count(polygons: Array[Dictionary]) -> int:
	var cells: Dictionary = {}
	for polygon in polygons:
		var cell: Array = polygon.get("cell", [])
		cells["%s" % [cell]] = true
	return cells.size()

func _build_arcs_from_polygons(polygons: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for polygon in polygons:
		var ids: Array = polygon.get("root_ids", [])
		var faces: Array = polygon.get("face_ids", [])
		if ids.size() < 3 or ids.size() != faces.size(): continue
		for edge_index in range(ids.size()):
			var first_id: String = String(ids[edge_index])
			var second_id: String = String(ids[(edge_index + 1) % ids.size()])
			var arc_key: String = _arc_key(first_id, second_id)
			if not result.has(arc_key): result[arc_key] = {"roots": [first_id, second_id], "polygon_ids": [], "face_ids": [], "required_incidence": 0}
			var arc: Dictionary = result[arc_key]
			arc.polygon_ids.append(String(polygon.get("id", "")))
			arc.face_ids.append(String(faces[edge_index]))
			arc.required_incidence += 1
			result[arc_key] = arc
	return result

func _triangulate_boundary_cycle(root_ids: Array, roots: Dictionary) -> Dictionary:
	if root_ids.size() < 3 or root_ids.size() > A4_PATCH_MAX_BOUNDARY_ROOTS:
		return {"valid": false, "reason": "boundary_cycle_size_unsupported", "root_count": root_ids.size()}
	var points: Array[Vector3] = []
	for root_id in root_ids:
		if not roots.has(String(root_id)): return {"valid": false, "reason": "boundary_cycle_root_missing", "root_id": root_id}
		points.append(roots[String(root_id)])
	var newell: Vector3 = Vector3.ZERO
	for point_index in range(points.size()):
		var current: Vector3 = points[point_index]
		var next: Vector3 = points[(point_index + 1) % points.size()]
		newell.x += (current.y - next.y) * (current.z + next.z)
		newell.y += (current.z - next.z) * (current.x + next.x)
		newell.z += (current.x - next.x) * (current.y + next.y)
	if not newell.is_finite() or newell.length_squared() == 0.0:
		return {"valid": false, "reason": "boundary_cycle_projection_normal_degenerate"}
	var dominant_axis: int = 0
	if absf(newell.y) > absf(newell.x): dominant_axis = 1
	if absf(newell.z) > absf(newell[dominant_axis]): dominant_axis = 2
	var projected: Array[Vector2] = []
	for point in points:
		if dominant_axis == 0: projected.append(Vector2(point.y, point.z))
		elif dominant_axis == 1: projected.append(Vector2(point.x, point.z))
		else: projected.append(Vector2(point.x, point.y))
	var signed_area_twice: float = 0.0
	for index in range(projected.size()): signed_area_twice += projected[index].cross(projected[(index + 1) % projected.size()])
	if not is_finite(signed_area_twice) or signed_area_twice == 0.0:
		return {"valid": false, "reason": "boundary_cycle_projected_area_degenerate"}
	var orientation: float = 1.0 if signed_area_twice > 0.0 else -1.0
	var remaining: Array[int] = []
	for index in range(points.size()): remaining.append(index)
	var triangles: Array[Dictionary] = []
	while remaining.size() > 3:
		var ears: Array[Dictionary] = []
		for slot in range(remaining.size()):
			var previous_index: int = remaining[(slot - 1 + remaining.size()) % remaining.size()]
			var current_index: int = remaining[slot]
			var next_index: int = remaining[(slot + 1) % remaining.size()]
			var turn: float = (projected[current_index] - projected[previous_index]).cross(projected[next_index] - projected[current_index])
			if turn * orientation <= 0.0: continue
			var contains_other: bool = false
			for test_index in remaining:
				if test_index == previous_index or test_index == current_index or test_index == next_index: continue
				if _point_in_projected_triangle(projected[test_index], projected[previous_index], projected[current_index], projected[next_index], orientation):
					contains_other = true
					break
			if contains_other: continue
			var cross_squared: float = _cross_squared(points[previous_index], points[current_index], points[next_index])
			if not is_finite(cross_squared) or cross_squared <= CUTOFF_SQUARED: continue
			ears.append({"slot": slot, "indices": [previous_index, current_index, next_index], "cross_squared": cross_squared})
		if ears.is_empty():
			return {"valid": false, "reason": "no_valid_ear_without_degeneracy_or_boundary_inversion", "remaining_indices": remaining, "triangles": triangles}
		ears.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a.cross_squared) != float(b.cross_squared): return float(a.cross_squared) > float(b.cross_squared)
			return int(a.indices[1]) < int(b.indices[1]))
		var ear: Dictionary = ears[0]
		var ear_indices: Array = ear.indices
		triangles.append({"root_ids": [root_ids[int(ear_indices[0])], root_ids[int(ear_indices[1])], root_ids[int(ear_indices[2])]], "points": [points[int(ear_indices[0])], points[int(ear_indices[1])], points[int(ear_indices[2])]], "cross_squared": ear.cross_squared})
		remaining.remove_at(int(ear.slot))
	var final_cross_squared: float = _cross_squared(points[remaining[0]], points[remaining[1]], points[remaining[2]])
	if not is_finite(final_cross_squared) or final_cross_squared <= CUTOFF_SQUARED:
		return {"valid": false, "reason": "final_boundary_triangle_below_frozen_cutoff", "cross_squared": final_cross_squared, "triangles": triangles}
	triangles.append({"root_ids": [root_ids[remaining[0]], root_ids[remaining[1]], root_ids[remaining[2]]], "points": [points[remaining[0]], points[remaining[1]], points[remaining[2]]], "cross_squared": final_cross_squared})
	return {"valid": true, "construction": "deterministic_boundary_preserving_ear_clipping_max_area_first", "orientation": orientation, "projection_axis": dominant_axis, "triangles": triangles, "boundary_root_ids": root_ids.duplicate(), "boundary_area_twice": signed_area_twice}

func _insert_interior_roots_into_triangulation(base: Dictionary, interior_root_ids: Array[String], roots: Dictionary, allow_temporary_subcutoff: bool = false) -> Dictionary:
	var triangles: Array[Dictionary] = []
	var raw_base_triangles: Variant = base.get("triangles", [])
	if not raw_base_triangles is Array: return {"valid": false, "reason": "initial_boundary_triangulation_not_array"}
	for raw_triangle in raw_base_triangles:
		if not raw_triangle is Dictionary: return {"valid": false, "reason": "initial_boundary_triangulation_row_invalid"}
		triangles.append(raw_triangle)
	var projection_axis: int = int(base.get("projection_axis", -1))
	if projection_axis < 0 or projection_axis > 2: return {"valid": false, "reason": "initial_boundary_projection_axis_invalid"}
	var insertion_rows: Array[Dictionary] = []
	for root_id in interior_root_ids:
		var point: Vector3 = roots[String(root_id)]
		var point2: Vector2 = _project_world_point(point, projection_axis)
		var strict_containing: Array[int] = []
		var edge_matches: Array[Dictionary] = []
		var duplicate_vertex: bool = false
		for triangle_index in range(triangles.size()):
			var triangle: Dictionary = triangles[triangle_index]
			var ids: Array = triangle.get("root_ids", [])
			var points: Array = triangle.get("points", [])
			if ids.size() != 3 or points.size() != 3: return {"valid": false, "reason": "interior_insertion_found_malformed_triangle"}
			var p2: Array[Vector2] = [_project_world_point(points[0], projection_axis), _project_world_point(points[1], projection_axis), _project_world_point(points[2], projection_axis)]
			for vertex_index in range(3):
				if point2 == p2[vertex_index]: duplicate_vertex = true
			var orient_value: float = (p2[1] - p2[0]).cross(p2[2] - p2[0])
			if orient_value == 0.0: continue
			var orientation: float = 1.0 if orient_value > 0.0 else -1.0
			var side_values: Array[float] = [
				(p2[1] - p2[0]).cross(point2 - p2[0]) * orientation,
				(p2[2] - p2[1]).cross(point2 - p2[1]) * orientation,
				(p2[0] - p2[2]).cross(point2 - p2[2]) * orientation
			]
			if side_values[0] < 0.0 or side_values[1] < 0.0 or side_values[2] < 0.0: continue
			var zero_sides: Array[int] = []
			for side_index in range(3):
				if side_values[side_index] == 0.0: zero_sides.append(side_index)
			if zero_sides.is_empty(): strict_containing.append(triangle_index)
			else:
				for side_index in zero_sides:
					var left2: Vector2 = p2[side_index]
					var right2: Vector2 = p2[(side_index + 1) % 3]
					if (point2 - left2).dot(point2 - right2) <= 0.0:
						edge_matches.append({"triangle_index": triangle_index, "edge_index": side_index, "edge_key": _arc_key(String(ids[side_index]), String(ids[(side_index + 1) % 3]))})
		if duplicate_vertex:
			return {"valid": false, "reason": "interior_root_projects_to_existing_vertex", "root_id": root_id}
		if not edge_matches.is_empty():
			var unique_edge_keys: Dictionary = {}
			for edge_match in edge_matches: unique_edge_keys[String(edge_match.edge_key)] = true
			if unique_edge_keys.size() != 1 or edge_matches.size() != 2:
				return {"valid": false, "reason": "interior_root_lies_on_unshared_or_ambiguous_edge", "root_id": root_id, "edge_matches": edge_matches}
			var edge_key: String = String(edge_matches[0].edge_key)
			var replacement_by_index: Dictionary = {}
			for edge_match in edge_matches:
				var triangle_index: int = int(edge_match.triangle_index)
				var old_triangle: Dictionary = triangles[triangle_index]
				var old_ids: Array = old_triangle.root_ids
				var old_points: Array = old_triangle.points
				var edge_index: int = int(edge_match.edge_index)
				var left_id: String = String(old_ids[edge_index])
				var right_id: String = String(old_ids[(edge_index + 1) % 3])
				var opposite_id: String = String(old_ids[(edge_index + 2) % 3])
				var left_point: Vector3 = old_points[edge_index]
				var right_point: Vector3 = old_points[(edge_index + 1) % 3]
				var opposite_point: Vector3 = old_points[(edge_index + 2) % 3]
				var first_cross: float = _cross_squared(left_point, point, opposite_point)
				var second_cross: float = _cross_squared(point, right_point, opposite_point)
				if not is_finite(first_cross) or not is_finite(second_cross) or (not allow_temporary_subcutoff and (first_cross <= CUTOFF_SQUARED or second_cross <= CUTOFF_SQUARED)):
					return {"valid": false, "reason": "edge_root_insertion_children_below_frozen_cutoff", "root_id": root_id, "source_edge": edge_key, "child_cross_squared": [first_cross, second_cross]}
				replacement_by_index[triangle_index] = [
					{"root_ids": [left_id, String(root_id), opposite_id], "points": [left_point, point, opposite_point], "cross_squared": first_cross},
					{"root_ids": [String(root_id), right_id, opposite_id], "points": [point, right_point, opposite_point], "cross_squared": second_cross}
				]
			var edge_split: Array[Dictionary] = []
			for triangle_index in range(triangles.size()):
				if replacement_by_index.has(triangle_index): edge_split.append_array(replacement_by_index[triangle_index])
				else: edge_split.append(triangles[triangle_index])
			triangles = edge_split
			insertion_rows.append({"root_id": root_id, "construction": "shared_edge_split", "source_edge": edge_key, "affected_triangle_count": edge_matches.size()})
			continue
		if strict_containing.size() != 1:
			return {"valid": false, "reason": "interior_root_not_in_exactly_one_projected_triangle", "root_id": root_id, "containing_triangle_indices": strict_containing}
		var containing_index: int = strict_containing[0]
		var parent_triangle: Dictionary = triangles[containing_index]
		var parent_ids: Array = parent_triangle.root_ids
		var parent_points: Array = parent_triangle.points
		var children: Array[Dictionary] = [
			{"root_ids": [parent_ids[0], parent_ids[1], String(root_id)], "points": [parent_points[0], parent_points[1], point]},
			{"root_ids": [parent_ids[1], parent_ids[2], String(root_id)], "points": [parent_points[1], parent_points[2], point]},
			{"root_ids": [parent_ids[2], parent_ids[0], String(root_id)], "points": [parent_points[2], parent_points[0], point]}
		]
		var child_cross_squared: Array[float] = []
		for child in children:
			var cross_squared: float = _cross_squared(child.points[0], child.points[1], child.points[2])
			child.cross_squared = cross_squared
			child_cross_squared.append(cross_squared)
			if not is_finite(cross_squared) or (not allow_temporary_subcutoff and cross_squared <= CUTOFF_SQUARED):
				return {"valid": false, "reason": "interior_root_insertion_children_below_frozen_cutoff", "root_id": root_id, "parent_triangle_index": containing_index, "child_cross_squared": child_cross_squared}
		triangles.remove_at(containing_index)
		triangles.insert(containing_index, children[2])
		triangles.insert(containing_index, children[1])
		triangles.insert(containing_index, children[0])
		insertion_rows.append({"root_id": root_id, "construction": "strict_triangle_interior_split", "parent_triangle_index": containing_index, "child_cross_squared": child_cross_squared})
	if allow_temporary_subcutoff:
		var optimized: Dictionary = _optimize_triangulation_edge_flips(triangles, base.get("boundary_root_ids", []), projection_axis)
		if not bool(optimized.get("valid", false)):
			optimized["interior_root_insertions"] = insertion_rows
			optimized["inserted_root_count"] = insertion_rows.size()
			optimized["all_requested_roots_inserted"] = insertion_rows.size() == interior_root_ids.size()
			return optimized
		triangles = optimized.get("triangles", [])
		return {"valid": true, "construction": "boundary_root_insertion_then_bounded_min_area_improving_internal_edge_flips", "projection_axis": projection_axis, "orientation": base.get("orientation", 1.0), "boundary_root_ids": base.get("boundary_root_ids", []), "triangles": triangles, "interior_root_insertions": insertion_rows, "inserted_root_count": insertion_rows.size(), "all_requested_roots_inserted": insertion_rows.size() == interior_root_ids.size(), "edge_flip_optimization": optimized}
	return {"valid": true, "construction": "boundary_ear_clipping_then_deterministic_source_root_insertion", "projection_axis": projection_axis, "orientation": base.get("orientation", 1.0), "boundary_root_ids": base.get("boundary_root_ids", []), "triangles": triangles, "interior_root_insertions": insertion_rows, "inserted_root_count": insertion_rows.size(), "input_triangle_count": base.get("triangles", []).size(), "output_triangle_count": triangles.size(), "all_requested_roots_inserted": insertion_rows.size() == interior_root_ids.size()}

func _optimize_triangulation_edge_flips(input_triangles: Array[Dictionary], boundary_root_ids: Array, projection_axis: int) -> Dictionary:
	var triangles: Array[Dictionary] = input_triangles.duplicate(true)
	var boundary_edges: Dictionary = {}
	for index in range(boundary_root_ids.size()):
		boundary_edges[_arc_key(String(boundary_root_ids[index]), String(boundary_root_ids[(index + 1) % boundary_root_ids.size()]))] = true
	var flip_rows: Array[Dictionary] = []
	var seen_states: Dictionary = {}
	seen_states[_triangulation_state_key(triangles)] = true
	var stopped_by_cycle: bool = false
	while flip_rows.size() < A6_MAX_EDGE_FLIPS:
		var edge_rows: Dictionary = {}
		for triangle_index in range(triangles.size()):
			var ids: Array = triangles[triangle_index].get("root_ids", [])
			if ids.size() != 3: return {"valid": false, "reason": "edge_flip_triangle_root_arity_invalid", "triangle_index": triangle_index}
			for edge_index in range(3):
				var left_id: String = String(ids[edge_index])
				var right_id: String = String(ids[(edge_index + 1) % 3])
				var edge_key: String = _arc_key(left_id, right_id)
				if not edge_rows.has(edge_key): edge_rows[edge_key] = {"a": left_id, "b": right_id, "triangle_indices": []}
				edge_rows[edge_key].triangle_indices.append(triangle_index)
		var edge_keys: Array = edge_rows.keys()
		edge_keys.sort()
		var best_flip: Dictionary = {}
		for raw_edge_key in edge_keys:
			var edge_key: String = String(raw_edge_key)
			if boundary_edges.has(edge_key): continue
			var edge_row: Dictionary = edge_rows[edge_key]
			var owners: Array = edge_row.triangle_indices
			if owners.size() != 2: continue
			var first_index: int = int(owners[0])
			var second_index: int = int(owners[1])
			var first_triangle: Dictionary = triangles[first_index]
			var second_triangle: Dictionary = triangles[second_index]
			var first_ids: Array = first_triangle.root_ids
			var second_ids: Array = second_triangle.root_ids
			var a_id: String = String(edge_row.a)
			var b_id: String = String(edge_row.b)
			var c_id: String = _opposite_triangle_root(first_ids, a_id, b_id)
			var d_id: String = _opposite_triangle_root(second_ids, a_id, b_id)
			if c_id.is_empty() or d_id.is_empty() or c_id == d_id: continue
			var new_edge_key: String = _arc_key(c_id, d_id)
			if edge_rows.has(new_edge_key) or boundary_edges.has(new_edge_key): continue
			var a_point: Vector3 = _triangle_root_point(first_triangle, a_id)
			var b_point: Vector3 = _triangle_root_point(first_triangle, b_id)
			var c_point: Vector3 = _triangle_root_point(first_triangle, c_id)
			var d_point: Vector3 = _triangle_root_point(second_triangle, d_id)
			if not _segments_properly_intersect(_project_world_point(a_point, projection_axis), _project_world_point(b_point, projection_axis), _project_world_point(c_point, projection_axis), _project_world_point(d_point, projection_axis)):
				continue
			var old_min: float = minf(_cross_squared_from_triangle(first_triangle), _cross_squared_from_triangle(second_triangle))
			var first_new_cross: float = _cross_squared(c_point, d_point, a_point)
			var second_new_cross: float = _cross_squared(d_point, c_point, b_point)
			if not is_finite(first_new_cross) or not is_finite(second_new_cross): continue
			var new_min: float = minf(first_new_cross, second_new_cross)
			if new_min <= old_min: continue
			if not best_flip.is_empty() and new_min <= float(best_flip.get("new_min", -1.0)): continue
			best_flip = {"old_edge_key": edge_key, "new_edge_key": new_edge_key, "first_index": first_index, "second_index": second_index, "a_id": a_id, "b_id": b_id, "c_id": c_id, "d_id": d_id, "a_point": a_point, "b_point": b_point, "c_point": c_point, "d_point": d_point, "old_min": old_min, "new_min": new_min, "first_new_cross": first_new_cross, "second_new_cross": second_new_cross}
		if best_flip.is_empty(): break
		var first_triangle_after: Dictionary = {"root_ids": [String(best_flip.c_id), String(best_flip.d_id), String(best_flip.a_id)], "points": [best_flip.c_point, best_flip.d_point, best_flip.a_point], "cross_squared": best_flip.first_new_cross}
		var second_triangle_after: Dictionary = {"root_ids": [String(best_flip.d_id), String(best_flip.c_id), String(best_flip.b_id)], "points": [best_flip.d_point, best_flip.c_point, best_flip.b_point], "cross_squared": best_flip.second_new_cross}
		triangles[int(best_flip.first_index)] = first_triangle_after
		triangles[int(best_flip.second_index)] = second_triangle_after
		var state_key: String = _triangulation_state_key(triangles)
		flip_rows.append({"removed_edge": best_flip.old_edge_key, "added_edge": best_flip.new_edge_key, "old_min_cross_squared": best_flip.old_min, "new_min_cross_squared": best_flip.new_min, "new_triangle_cross_squared": [best_flip.first_new_cross, best_flip.second_new_cross]})
		if seen_states.has(state_key):
			stopped_by_cycle = true
			break
		seen_states[state_key] = true
	var subcutoff: Array[Dictionary] = []
	var minimum_cross_squared: float = INF
	for triangle_index in range(triangles.size()):
		var cross_squared: float = _cross_squared_from_triangle(triangles[triangle_index])
		minimum_cross_squared = minf(minimum_cross_squared, cross_squared)
		if not is_finite(cross_squared) or cross_squared <= CUTOFF_SQUARED:
			subcutoff.append({"triangle_index": triangle_index, "cross_squared": cross_squared, "root_ids": triangles[triangle_index].get("root_ids", [])})
	return {"valid": subcutoff.is_empty(), "reason": "" if subcutoff.is_empty() else ("edge_flip_state_cycle_detected" if stopped_by_cycle else "no_quality_improving_flip_can_resolve_frozen_cutoff"), "triangles": triangles, "flip_count": flip_rows.size(), "flips": flip_rows, "minimum_cross_squared": minimum_cross_squared, "remaining_subcutoff_triangles": subcutoff, "max_flip_limit": A6_MAX_EDGE_FLIPS, "limit_reached": flip_rows.size() >= A6_MAX_EDGE_FLIPS}

func _opposite_triangle_root(ids: Array, first_id: String, second_id: String) -> String:
	for raw_id in ids:
		var root_id: String = String(raw_id)
		if root_id != first_id and root_id != second_id: return root_id
	return ""

func _triangle_root_point(triangle: Dictionary, root_id: String) -> Vector3:
	var ids: Array = triangle.get("root_ids", [])
	var points: Array = triangle.get("points", [])
	for index in range(mini(ids.size(), points.size())):
		if String(ids[index]) == root_id and points[index] is Vector3: return points[index]
	return Vector3(NAN, NAN, NAN)

func _cross_squared_from_triangle(triangle: Dictionary) -> float:
	var points: Array = triangle.get("points", [])
	if points.size() != 3: return NAN
	return _cross_squared(points[0], points[1], points[2])

func _segments_properly_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c: float = (b - a).cross(c - a)
	var ab_d: float = (b - a).cross(d - a)
	var cd_a: float = (d - c).cross(a - c)
	var cd_b: float = (d - c).cross(b - c)
	return ab_c * ab_d < 0.0 and cd_a * cd_b < 0.0

func _triangulation_state_key(triangles: Array[Dictionary]) -> String:
	var rows: Array[String] = []
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3: return "INVALID"
		var edge_keys: Array[String] = [
			_arc_key(String(ids[0]), String(ids[1])),
			_arc_key(String(ids[1]), String(ids[2])),
			_arc_key(String(ids[2]), String(ids[0]))
		]
		edge_keys.sort()
		rows.append("|".join(edge_keys))
	rows.sort()
	return "\n".join(rows)

func _project_world_point(point: Vector3, projection_axis: int) -> Vector2:
	if projection_axis == 0: return Vector2(point.y, point.z)
	if projection_axis == 1: return Vector2(point.x, point.z)
	return Vector2(point.x, point.y)

func _point_in_projected_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2, orientation: float) -> bool:
	var ab: float = (b - a).cross(point - a) * orientation
	var bc: float = (c - b).cross(point - b) * orientation
	var ca: float = (a - c).cross(point - c) * orientation
	return ab >= 0.0 and bc >= 0.0 and ca >= 0.0

func _sample_materialized_piecewise_field(world_point: Vector3, values: PackedFloat32Array, dims: Vector3i) -> Dictionary:
	if not world_point.is_finite() or values.size() != dims.x * dims.y * dims.z: return {"valid": false, "reason": "invalid_query_or_volume"}
	var grid_position: Vector3 = (world_point - ROI_MIN) / STEP
	var cell: Vector3i = Vector3i(floori(grid_position.x), floori(grid_position.y), floori(grid_position.z))
	cell.x = clampi(cell.x, 0, CELLS.x - 1)
	cell.y = clampi(cell.y, 0, CELLS.y - 1)
	cell.z = clampi(cell.z, 0, CELLS.z - 1)
	var local_point: Vector3 = grid_position - Vector3(cell)
	var best: Dictionary = {}
	var best_violation: float = INF
	for tetrahedron_index in range(Core.TETS.size()):
		var corners: Array = Core.TETS[tetrahedron_index]
		var p0: Vector3 = Vector3(Core.GRID_CORNERS[int(corners[0])])
		var p1: Vector3 = Vector3(Core.GRID_CORNERS[int(corners[1])])
		var p2: Vector3 = Vector3(Core.GRID_CORNERS[int(corners[2])])
		var p3: Vector3 = Vector3(Core.GRID_CORNERS[int(corners[3])])
		var basis: Basis = Basis(p1 - p0, p2 - p0, p3 - p0)
		if basis.determinant() == 0.0: continue
		var coordinates: Vector3 = basis.inverse() * (local_point - p0)
		var weights: Array[float] = [1.0 - coordinates.x - coordinates.y - coordinates.z, coordinates.x, coordinates.y, coordinates.z]
		var violation: float = 0.0
		for weight in weights:
			if weight < 0.0: violation += -weight
			elif weight > 1.0: violation += weight - 1.0
		if violation > best_violation: continue
		var density: float = 0.0
		for corner_index in range(4):
			var corner: Vector3i = Core.GRID_CORNERS[int(corners[corner_index])]
			var sample: float = values[_idx(cell.x + corner.x, cell.y + corner.y, cell.z + corner.z, dims)]
			density += sample * weights[corner_index]
		best_violation = violation
		best = {"valid": true, "density": density, "tetrahedron_index": tetrahedron_index, "barycentric_weights": weights, "barycentric_outside_residual": violation}
	return best

func _project_steiner_to_canonical(initial: Vector3, snapshot: Dictionary, seed: int) -> Dictionary:
	if not initial.is_finite() or snapshot.is_empty():
		return {"valid": false, "reason": "initial_point_or_snapshot_invalid"}
	var position: Vector3 = initial
	var sample_step: float = maxf(STEP * 0.01, 0.0001)
	var convergence_epsilon: float = 1.0e-5
	var initial_density: float = _sample_snapshot_density(position, snapshot, seed)
	if not is_finite(initial_density):
		return {"valid": false, "reason": "initial_canonical_density_nonfinite"}
	var final_density: float = initial_density
	var iterations: int = 0
	var converged: bool = false
	for iteration in range(12):
		iterations = iteration + 1
		final_density = _sample_snapshot_density(position, snapshot, seed)
		if not is_finite(final_density):
			return {"valid": false, "reason": "canonical_density_nonfinite", "iteration": iteration}
		if absf(final_density) <= convergence_epsilon:
			converged = true
			break
		var ex: Vector3 = Vector3(sample_step, 0.0, 0.0)
		var ey: Vector3 = Vector3(0.0, sample_step, 0.0)
		var ez: Vector3 = Vector3(0.0, 0.0, sample_step)
		var gradient: Vector3 = Vector3(
			(_sample_snapshot_density(position + ex, snapshot, seed) - _sample_snapshot_density(position - ex, snapshot, seed)) / (2.0 * sample_step),
			(_sample_snapshot_density(position + ey, snapshot, seed) - _sample_snapshot_density(position - ey, snapshot, seed)) / (2.0 * sample_step),
			(_sample_snapshot_density(position + ez, snapshot, seed) - _sample_snapshot_density(position - ez, snapshot, seed)) / (2.0 * sample_step)
		)
		var gradient_squared: float = gradient.length_squared()
		if not gradient.is_finite() or not is_finite(gradient_squared) or gradient_squared <= 1.0e-12:
			return {"valid": false, "reason": "canonical_gradient_invalid", "iteration": iteration, "density": final_density}
		var delta: Vector3 = gradient * (final_density / gradient_squared)
		if not delta.is_finite():
			return {"valid": false, "reason": "newton_delta_nonfinite", "iteration": iteration}
		var accepted: bool = false
		var alpha: float = 1.0
		for line_search in range(8):
			var candidate: Vector3 = position - delta * alpha
			var candidate_density: float = _sample_snapshot_density(candidate, snapshot, seed)
			if candidate.is_finite() and is_finite(candidate_density) and absf(candidate_density) < absf(final_density):
				position = candidate
				final_density = candidate_density
				accepted = true
				break
			alpha *= 0.5
		if not accepted:
			return {"valid": false, "reason": "canonical_projection_line_search_stalled", "iteration": iteration, "density": final_density}
		if position.distance_to(initial) > STEP:
			return {"valid": false, "reason": "steiner_displacement_bound_exceeded", "displacement": position.distance_to(initial), "maximum": STEP}
	if not converged:
		final_density = _sample_snapshot_density(position, snapshot, seed)
		converged = is_finite(final_density) and absf(final_density) <= convergence_epsilon
	return {"valid": converged and position.is_finite(), "reason": "" if converged else "canonical_projection_did_not_converge", "point": position,
		"canonical_field_used": true, "field_authority": "SDF_GENERATOR_V1_PLUS_ORDERED_SNAPSHOT", "initial_density": initial_density,
		"final_density": final_density, "iterations": iterations, "finite_difference_step": sample_step,
		"convergence_epsilon": convergence_epsilon, "displacement": position.distance_to(initial), "maximum_displacement": STEP,
		"acceptance_tolerance_owner_approved": false}

func _sample_snapshot_density(world_point: Vector3, snapshot: Dictionary, seed: int) -> float:
	var region_key: Vector2i = Vector2i(floori(world_point.x / Field.REGION_SIZE_X), floori(world_point.z / Field.REGION_SIZE_Z))
	var local_position: Vector3 = Vector3(world_point.x - float(region_key.x) * Field.REGION_SIZE_X, world_point.y, world_point.z - float(region_key.y) * Field.REGION_SIZE_Z)
	return BrushState.sample_density_snapshot(seed, region_key, local_position, false, snapshot)

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
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_diagonal: Array = a.diagonal
			var b_diagonal: Array = b.diagonal
			if int(a_diagonal[0]) != int(b_diagonal[0]):
				return int(a_diagonal[0]) < int(b_diagonal[0])
			return int(a_diagonal[1]) < int(b_diagonal[1]))
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
	var polygon_owners: Dictionary = {}
	var polygon_data_by_id: Dictionary = {}
	var polygon_parent: Dictionary = {}
	var sorted_polygons: Array[Dictionary] = polygons.duplicate()
	sorted_polygons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	for polygon in sorted_polygons:
		var polygon_id: String = String(polygon.get("id", ""))
		var cell: Array = polygon.get("cell", [])
		var center: Vector3 = Vector3.ZERO
		for point in polygon.get("points", []): center += point
		var point_count: int = polygon.get("points", []).size()
		if point_count > 0: center /= float(point_count)
		var region_key: Vector2i = Vector2i(floori(center.x / Field.REGION_SIZE_X), floori(center.z / Field.REGION_SIZE_Z))
		var owner_kind: String = "half_open_world_region_and_source_tetrahedron"
		if not String(polygon.get("patch_id", "")).is_empty(): owner_kind = "half_open_world_region_and_r10a4_component_patch"
		var owner: Dictionary = {"owner_kind": owner_kind, "region_key": [region_key.x, region_key.y], "cell": cell.duplicate(), "tetrahedron": polygon.get("tet_index", -1), "face_ids": polygon.get("face_ids", []).duplicate(), "patch_id": polygon.get("patch_id", ""), "source_polygon_ids": polygon.get("source_polygon_ids", [polygon_id]).duplicate(), "lod_step": STEP}
		polygon_owners[polygon_id] = owner
		polygon_data_by_id[polygon_id] = polygon
		polygon_parent[polygon_id] = polygon_id
		polygon_rows.append([polygon_id, cell, polygon.get("tet_index", -1), polygon.get("root_ids", []), polygon.get("face_ids", []), polygon.get("source_polygon_ids", [polygon_id]), polygon.get("patch_id", ""), owner, "CANDIDATE_D_VOLUME"])
	var arc_rows: Array = []
	var arc_keys: Array = arcs.keys()
	arc_keys.sort()
	var unresolved_arcs: Array = []
	var nonmanifold_arcs: Array = []
	var region_relation_set: Dictionary = {}
	var lod_relation_set: Dictionary = {}
	var boundary_edge_rows: Array[Dictionary] = []
	var interior_open_edge_rows: Array[Dictionary] = []
	for raw_key in arc_keys:
		var arc_key: String = String(raw_key)
		var arc: Dictionary = arcs[arc_key]
		var a: Vector3 = roots[String(arc.roots[0])]
		var b: Vector3 = roots[String(arc.roots[1])]
		var roi_boundary: bool = _arc_on_roi_boundary(a, b)
		var roi_faces: Array[String] = _roi_boundary_faces(a, b)
		var owners: Array = arc.polygon_ids.duplicate()
		owners.sort()
		arc_rows.append([arc_key, arc.roots, arc.required_incidence, owners, arc.face_ids, roi_boundary, roi_faces, owners[0] if not owners.is_empty() else ""])
		for owner_index in range(1, owners.size()):
			var first_owner: Dictionary = polygon_owners.get(String(owners[0]), {})
			var other_owner: Dictionary = polygon_owners.get(String(owners[owner_index]), {})
			var first_region: Array = first_owner.get("region_key", [])
			var other_region: Array = other_owner.get("region_key", [])
			if first_region.size() == 2 and other_region.size() == 2 and first_region != other_region:
				var first_key: String = "%d,%d" % [int(first_region[0]), int(first_region[1])]
				var other_key: String = "%d,%d" % [int(other_region[0]), int(other_region[1])]
				var pair_key: String = first_key + "|" + other_key if first_key < other_key else other_key + "|" + first_key
				if not region_relation_set.has(pair_key): region_relation_set[pair_key] = {"region_pair": pair_key.split("|"), "shared_arcs": [], "polygon_owners": []}
				region_relation_set[pair_key].shared_arcs.append(arc_key)
				for polygon_owner in owners:
					if not region_relation_set[pair_key].polygon_owners.has(String(polygon_owner)): region_relation_set[pair_key].polygon_owners.append(String(polygon_owner))
			var first_lod: float = float(first_owner.get("lod_step", STEP))
			var other_lod: float = float(other_owner.get("lod_step", STEP))
			var lod_relation: String = "SAME_STEP" if is_equal_approx(first_lod, other_lod) else "MIXED_STEP"
			lod_relation_set[lod_relation] = true
			_union_polygon_owners(polygon_parent, String(owners[0]), String(owners[owner_index]))
		if roi_boundary:
			boundary_edge_rows.append({"edge_key": arc_key, "roots": arc.roots})
		elif int(arc.required_incidence) != 2:
			interior_open_edge_rows.append({"edge_key": arc_key, "roots": arc.roots})
		if int(arc.required_incidence) > (1 if roi_boundary else 2):
			nonmanifold_arcs.append(arc_key)
		elif int(arc.required_incidence) < (1 if roi_boundary else 2):
			unresolved_arcs.append(arc_key)
	var component_members: Dictionary = {}
	for polygon_id in polygon_parent.keys():
		var component_id: String = _find_polygon_owner(polygon_parent, String(polygon_id))
		if not component_members.has(component_id): component_members[component_id] = []
		component_members[component_id].append(String(polygon_id))
	var component_rows: Array[Dictionary] = []
	var component_ids: Array = component_members.keys()
	component_ids.sort()
	for component_id in component_ids:
		var members: Array = component_members[component_id]
		members.sort()
		var component_roots: Dictionary = {}
		var component_regions: Dictionary = {}
		for member in members:
			var member_polygon: Dictionary = polygon_data_by_id.get(String(member), {})
			for component_root in member_polygon.get("root_ids", []): component_roots[String(component_root)] = true
			var member_region: Array = polygon_owners[String(member)].get("region_key", [])
			if member_region.size() == 2: component_regions["%d,%d" % [int(member_region[0]), int(member_region[1])]] = true
		var sorted_component_roots: Array = component_roots.keys(); sorted_component_roots.sort()
		var sorted_component_regions: Array = component_regions.keys(); sorted_component_regions.sort()
		component_rows.append({"id": String(component_id), "polygon_ids": members, "root_ids": sorted_component_roots, "region_owners": sorted_component_regions})
	var boundary_loops: Dictionary = _extract_edge_loops(boundary_edge_rows)
	var interior_loops: Dictionary = _extract_edge_loops(interior_open_edge_rows)
	if not polygons.is_empty() and lod_relation_set.is_empty(): lod_relation_set["SAME_STEP"] = true
	var region_relations: Array = region_relation_set.values()
	for relation in region_relations:
		relation.shared_arcs.sort()
		relation.polygon_owners.sort()
	region_relations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return JSON.stringify(a.region_pair) < JSON.stringify(b.region_pair))
	var lod_relations: Array = lod_relation_set.keys(); lod_relations.sort()
	var ownership: Dictionary = {"polygon_owner_count": polygon_owners.size(), "owner_rows": polygon_owners, "contract": "signed world-space half-open region ownership; source tetrahedron owns each polygon; shared arcs are recorded once"}
	var canonical: Dictionary = {"schema": "P3.1.R10A.TopologyGraph.v2", "roots": root_rows, "polygons": polygon_rows, "arcs": arc_rows, "surface_components": component_rows, "boundary_loops": boundary_loops, "interior_loops": interior_loops, "ownership": ownership, "neighbor_region_relations": region_relations, "lod_relations": lod_relations, "geometry_errors": geometry_errors}
	var canonical_bytes: PackedByteArray = JSON.stringify(canonical).to_utf8_buffer()
	return {"valid": unresolved_arcs.is_empty() and nonmanifold_arcs.is_empty() and geometry_errors.is_empty(), "schema": canonical.schema,
		"root_count": roots.size(), "polygon_count": polygons.size(), "arc_count": arcs.size(), "unresolved_required_arcs": unresolved_arcs,
		"nonmanifold_required_arcs": nonmanifold_arcs, "geometry_errors": geometry_errors, "surface_components": component_rows, "boundary_loops": boundary_loops, "interior_loops": interior_loops, "ownership": ownership, "neighbor_region_relations": region_relations, "lod_relations": lod_relations, "canonical": canonical,
		"topology_sha256": Core.sha256(canonical_bytes), "authority": "topology graph built from exact Candidate D materialized scalar edge roots before triangle realization"}

func _find_polygon_owner(parent: Dictionary, polygon_id: String) -> String:
	var current: String = polygon_id
	while String(parent.get(current, current)) != current:
		current = String(parent[current])
	var root: String = current
	current = polygon_id
	while String(parent.get(current, current)) != current:
		var next: String = String(parent[current])
		parent[current] = root
		current = next
	return root

func _union_polygon_owners(parent: Dictionary, left: String, right: String) -> void:
	if not parent.has(left) or not parent.has(right): return
	var left_root: String = _find_polygon_owner(parent, left)
	var right_root: String = _find_polygon_owner(parent, right)
	if left_root == right_root: return
	if left_root < right_root:
		parent[right_root] = left_root
	else:
		parent[left_root] = right_root

func _extract_edge_loops(edges: Array[Dictionary]) -> Dictionary:
	var adjacency: Dictionary = {}
	var edge_by_key: Dictionary = {}
	for edge in edges:
		var roots: Array = edge.get("roots", [])
		if roots.size() != 2: continue
		var left: String = String(roots[0])
		var right: String = String(roots[1])
		var edge_key: String = String(edge.get("edge_key", _arc_key(left, right)))
		edge_by_key[edge_key] = [left, right]
		if not adjacency.has(left): adjacency[left] = []
		if not adjacency.has(right): adjacency[right] = []
		adjacency[left].append({"neighbor": right, "edge_key": edge_key})
		adjacency[right].append({"neighbor": left, "edge_key": edge_key})
	for vertex in adjacency.keys():
		adjacency[vertex].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if String(a.neighbor) == String(b.neighbor): return String(a.edge_key) < String(b.edge_key)
			return String(a.neighbor) < String(b.neighbor))
	var unused: Dictionary = {}
	for edge_key in edge_by_key.keys(): unused[String(edge_key)] = true
	var paths: Array[Dictionary] = []
	while not unused.is_empty():
		var sorted_vertices: Array = adjacency.keys(); sorted_vertices.sort()
		var start: String = ""
		for vertex in sorted_vertices:
			var active_degree: int = 0
			for adjacent in adjacency[vertex]:
				if unused.has(String(adjacent.edge_key)): active_degree += 1
			if active_degree > 0 and active_degree != 2:
				start = String(vertex)
				break
		if start.is_empty():
			var sorted_edge_keys: Array = unused.keys(); sorted_edge_keys.sort()
			var first_edge: String = String(sorted_edge_keys[0])
			var endpoints: Array = edge_by_key[first_edge]
			start = String(endpoints[0]) if String(endpoints[0]) < String(endpoints[1]) else String(endpoints[1])
		var current: String = start
		var previous_edge: String = ""
		var ordered_vertices: Array[String] = [start]
		var ordered_edges: Array[String] = []
		var closed: bool = false
		var guard: int = edge_by_key.size() + 1
		while guard > 0:
			guard -= 1
			var next_choice: Dictionary = {}
			for adjacent in adjacency.get(current, []):
				var candidate_edge: String = String(adjacent.edge_key)
				if candidate_edge == previous_edge or not unused.has(candidate_edge): continue
				next_choice = adjacent
				break
			if next_choice.is_empty(): break
			var used_edge: String = String(next_choice.edge_key)
			var next_vertex: String = String(next_choice.neighbor)
			unused.erase(used_edge)
			ordered_edges.append(used_edge)
			previous_edge = used_edge
			current = next_vertex
			if current == start:
				closed = true
				break
			ordered_vertices.append(current)
		var branch_vertices: Array[String] = []
		for vertex in ordered_vertices:
			if adjacency.get(vertex, []).size() != 2: branch_vertices.append(vertex)
		paths.append({"closed": closed, "root_ids": ordered_vertices, "edge_keys": ordered_edges, "branch_vertices": branch_vertices})
	var closed_count: int = 0
	var open_count: int = 0
	for path in paths:
		if bool(path.closed): closed_count += 1
		else: open_count += 1
	return {"path_count": paths.size(), "closed_loop_count": closed_count, "open_path_count": open_count, "paths": paths}

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

func _roi_boundary_faces(a: Vector3, b: Vector3) -> Array[String]:
	var result: Array[String] = []
	var roi_max: Vector3 = ROI_MIN + Vector3(CELLS) * STEP
	for axis in range(3):
		if absf(a[axis] - b[axis]) > 2.0e-6: continue
		var face_axis: String = ["X", "Y", "Z"][axis]
		if absf(a[axis] - ROI_MIN[axis]) <= 2.0e-6: result.append(face_axis + "_NEG")
		if absf(a[axis] - roi_max[axis]) <= 2.0e-6: result.append(face_axis + "_POS")
	result.sort()
	return result

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
