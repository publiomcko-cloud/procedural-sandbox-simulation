extends "res://tests/prototypes/p3_1_r8_2_geometry_provenance.gd"

## R8.3-A isolated, bounded X+ seam experiment. No production path is changed.
const TransitionA := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const FROZEN_LATTICE_A := Vector3i(30, 4, 14)
const PLANE_X_A := 16.0
const AREA2_CUTOFF_A := 1.0e-12
var _assertions_a := 0
var _failures_a: Array[String] = []

func _initialize() -> void:
	call_deferred("_run_r83a")

func _run_r83a() -> void:
	var preflight: Dictionary = _r8_preflight()
	_check_a(bool(preflight.get("valid", false)), "frozen_fill_carve_input_and_source_pins_validate")
	if not bool(preflight.get("valid", false)):
		_emit_r83a({"status": "BLOCKED", "reason": "r8_frozen_preflight_failed", "preflight": preflight})
		quit(1)
		return
	var snapshot: Dictionary = _r8_fill_snapshot
	var cell: Dictionary = TransitionA.build_transition_cell(SEED, FROZEN_LATTICE_A, [1], snapshot)
	_check_a(bool(cell.get("valid", false)), "frozen_lod1_xplus_transition_cell_builds")
	if not bool(cell.get("valid", false)):
		_emit_r83a({"status": "BLOCKED", "reason": "transition_cell_build_failed", "cell_reason": cell.get("reason", "")})
		quit(1)
		return
	var center: Vector3 = Vector3(FROZEN_LATTICE_A) * 0.5 + Vector3.ONE * 0.5
	var rejected: Array[Dictionary] = []
	var interface_segments: Array[Dictionary] = []
	for face_tri_value in TransitionA._boundary_triangles(FROZEN_LATTICE_A, [1]):
		var face_tri: Array = face_tri_value
		if not (absf(face_tri[0].x - PLANE_X_A) < 1.0e-7 and absf(face_tri[1].x - PLANE_X_A) < 1.0e-7 and absf(face_tri[2].x - PLANE_X_A) < 1.0e-7):
			continue
		var values: Array[float] = []
		for point in face_tri:
			values.append(TransitionA.sample_canonical(SEED, point, snapshot))
		var poly: Dictionary = _poly([center, face_tri[0], face_tri[1], face_tri[2]], [TransitionA.sample_canonical(SEED, center, snapshot), values[0], values[1], values[2]], false)
		for row_value in poly.get("pre_cutoff_triangles", []):
			var row: Dictionary = row_value
			var vertices: Array = row.get("vertices", [])
			var face_edges: Array = []
			for edge in [[0, 1], [1, 2], [2, 0]]:
				var a: Vector3 = vertices[edge[0]]
				var b: Vector3 = vertices[edge[1]]
				if absf(a.x - PLANE_X_A) < 1.0e-7 and absf(b.x - PLANE_X_A) < 1.0e-7:
					face_edges.append({"a": a, "b": b})
			if face_edges.size() == 1:
				interface_segments.append(face_edges[0])
			var center_edge_vertex: Vector3 = vertices[0]
			var boundary_points: Array[Vector3] = []
			for vertex_value in vertices:
				var vertex: Vector3 = vertex_value
				if absf(vertex.x - PLANE_X_A) < 1.0e-7:
					boundary_points.append(vertex)
			var cross2: float = (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).length_squared()
			var canonical_relocation: Dictionary = {"bracketed": false}
			if boundary_points.size() == 2:
				for point_index in range(face_tri.size()):
					if values[point_index] < 0.0:
						canonical_relocation = _bisect_edge(face_tri[point_index], center, snapshot)
						break
			var relocated_cross2 := -1.0
			var relocated_vertices: Array = []
			if bool(canonical_relocation.get("bracketed", false)):
				var root: Vector3 = _parse_vector3(canonical_relocation.position)
				var other_boundary: Vector3 = boundary_points[0]
				var candidate_boundary: Vector3 = boundary_points[1]
				relocated_vertices = [root, other_boundary, candidate_boundary]
				relocated_cross2 = (other_boundary - root).cross(candidate_boundary - root).length_squared()
			rejected.append({"face_triangle_world": face_tri, "face_sample_densities": values,
				"face_sample_binary32_bits": values.map(func(value: float) -> String: return _float32_bytes(value)),
				"tetra_points": [center, face_tri[0], face_tri[1], face_tri[2]],
				"tetra_sample_densities": [TransitionA.sample_canonical(SEED, center, snapshot), values[0], values[1], values[2]],
				"tetra_sample_binary32_bits": [TransitionA.sample_canonical(SEED, center, snapshot), values[0], values[1], values[2]].map(func(value: float) -> String: return _float32_bytes(value)),
				"pre_cutoff_triangle": row, "center_edge_linear_vertex": center_edge_vertex,
				"boundary_contour_points": boundary_points, "boundary_contour_segment": face_edges,
				"canonical_center_edge_root": canonical_relocation, "canonical_root_candidate_vertices": relocated_vertices,
				"canonical_root_candidate_cross_squared": relocated_cross2,
				"canonical_root_candidate_passes_unchanged_cutoff": relocated_cross2 > AREA2_CUTOFF_A,
				"source_triangle_emitted": false})
	var baseline_contour: Dictionary = _contour_x(cell.get("vertices", PackedVector3Array()))
	var strategy_result: Dictionary = _evaluate_local_alternatives(rejected, interface_segments)
	_check_a(rejected.size() == 2, "exactly_two_transition_facets_are_rejected_by_frozen_cutoff")
	_check_a(Array(baseline_contour.get("segments", [])).is_empty(), "negative_lod1_transition_cell_omits_both_expected_xplus_segments")
	_check_a(interface_segments.size() == 2, "independent_face_contour_oracle_requires_two_segments")
	var cavity_check: Dictionary = strategy_result.get("paired_two_facet_cavity", {})
	_check_a(bool(cavity_check.get("valid", false)), "two_rejected_facets_form_bounded_four_vertex_cavity")
	_check_a(not bool(cavity_check.get("original_all_above_cutoff", true)), "original_diagonal_violates_subthreshold_invariant")
	_check_a(not bool(cavity_check.get("alternate_all_above_cutoff", true)), "alternate_diagonal_also_violates_subthreshold_invariant")
	for facet in rejected:
		_check_a(float(facet.pre_cutoff_triangle.cross_squared) <= AREA2_CUTOFF_A, "each_frozen_facet_is_below_or_equal_to_cutoff")
		_check_a(bool(facet.canonical_center_edge_root.get("bracketed", false)), "canonical_radial_edge_has_continuous_zero_root")
		_check_a(not bool(facet.canonical_root_candidate_passes_unchanged_cutoff), "continuous_root_relocation_still_cannot_clear_cutoff")
	var result := {"status": "MINIMAL_FIXTURE_REPRODUCED", "scenario_input_sha256": INPUT_SHA_FILL_CARVE,
		"source_head": "4f08b67522507bd196a74a1089c773f272235343", "cell_lod": 1,
		"selected_face_ids": [1], "lattice_origin_lod0": FROZEN_LATTICE_A,
		"cell_world_bounds": {"min": Vector3(FROZEN_LATTICE_A) * 0.5, "max": Vector3(FROZEN_LATTICE_A) * 0.5 + Vector3.ONE},
		"interface_plane_x": PLANE_X_A, "threshold_cross_squared": AREA2_CUTOFF_A,
		"transition_cell_valid": true, "transition_cell_triangles": int(cell.get("triangle_count", -1)),
		"baseline_transition_xplus_contour_segments": baseline_contour.get("segments", []),
		"baseline_transition_xplus_contour_count": baseline_contour.get("segments", []).size(),
		"rejected_transition_facets": rejected, "rejected_facet_count": rejected.size(),
		"independent_face_contour_segments": interface_segments,
		"strategies": strategy_result,
		"assertions": _assertions_a, "failures": _failures_a,
		"gate": "stop_after_minimal_fixture_if_no_bounded_strategy_preserves_interface_and_unchanged_cutoff",
		"limits": "only the two frozen subthreshold facets and their four-vertex local cavity are evaluated; no production, full chunk, GUI, collider, or performance claim"}
	var passed: bool = _failures_a.is_empty()
	result["minimal_reproduction_pass"] = passed
	_emit_r83a(result)
	quit(0 if passed else 1)

func _evaluate_local_alternatives(rejected: Array[Dictionary], _segments: Array[Dictionary]) -> Dictionary:
	var rows: Array[Dictionary] = []
	for i in range(rejected.size()):
		var current: Dictionary = rejected[i]
		var vertices: Array = current.pre_cutoff_triangle.vertices
		var p: Vector3 = vertices[0]
		var q_a: Vector3 = vertices[1]
		var q_b: Vector3 = vertices[2]
		var candidate_a := (q_a - p).cross(q_b - p).length_squared()
		rows.append({"facet": i, "A_edge_collapse": {"legal_boundary_preserving_collapses": [],
			"reason": "only interior-to-interface edges touch this isolated simplex; collapsing the interior root makes zero-area or changes the fixed interface roots"},
			"B_constrained_cavity": {"candidate_vertices": [p, q_a, q_b], "only_boundary_preserving_triangulation_cross_squared": candidate_a,
			"passes_cutoff": candidate_a > AREA2_CUTOFF_A,
			"reason": "three-vertex cavity has one triangulation; it is the rejected source facet"},
			"C_boundary_preserving_remesh": {"valid_cavity_boundary": true, "candidate_vertices": [p, q_a, q_b],
			"only_boundary_preserving_triangulation_cross_squared": candidate_a,
			"passes_cutoff": candidate_a > AREA2_CUTOFF_A,
			"reason": "with no additional surface samples or moved vertices, remeshing the triangular boundary reproduces the same subthreshold facet"},
			"canonical_root_relocation_probe": {"candidate_cross_squared": current.canonical_root_candidate_cross_squared,
			"passes_cutoff": current.canonical_root_candidate_passes_unchanged_cutoff,
			"root": current.canonical_center_edge_root}})
	var cavity: Dictionary = _paired_cavity(rejected)
	return {"A_edge_collapse": "no admissible operation on the fixed three-vertex interface-preserving patch",
		"A_edge_collapse_attempts": _edge_collapse_attempts(cavity),
		"B_constrained_cavity": "fixed-vertex local retriangulation only; no additional samples",
		"C_boundary_preserving_remesh": "fixed-boundary remeshing only; no extra samples",
		"paired_two_facet_cavity": cavity, "facets": rows}

func _edge_collapse_attempts(cavity: Dictionary) -> Array[Dictionary]:
	if not bool(cavity.get("valid", false)):
		return [{"valid": false, "reason": "cavity_unavailable"}]
	var inner: Vector3 = cavity.inner_vertex
	var endpoints: Array = cavity.ordered_interface_vertices
	var outer_a: Vector3 = endpoints[0]
	var shared: Vector3 = endpoints[1]
	var outer_b: Vector3 = endpoints[2]
	var cases := [
		{"edge": "inner_to_shared_interface_root", "collapsed_to": "shared", "preserves_interface": true,
			"result_cross_squared": [0.0, 0.0], "result": "zero-area surface"},
		{"edge": "inner_to_outer_interface_root_a", "collapsed_to": "outer_a", "preserves_interface": false,
			"result_cross_squared": [0.0, (shared - outer_a).cross(outer_b - outer_a).length_squared()],
			"result": "degenerate facet plus boundary-plane triangle changes contour ownership"},
		{"edge": "inner_to_outer_interface_root_b", "collapsed_to": "outer_b", "preserves_interface": false,
			"result_cross_squared": [(outer_a - outer_b).cross(shared - outer_b).length_squared(), 0.0],
			"result": "boundary-plane triangle changes contour ownership plus degenerate facet"},
		{"edge": "outer_a_to_shared", "collapsed_to": "either", "preserves_interface": false,
			"result_cross_squared": [], "result": "changes fixed X+ contour endpoint and segment"},
		{"edge": "shared_to_outer_b", "collapsed_to": "either", "preserves_interface": false,
			"result_cross_squared": [], "result": "changes fixed X+ contour endpoint and segment"},
	]
	return cases

func _paired_cavity(rejected: Array[Dictionary]) -> Dictionary:
	if rejected.size() != 2:
		return {"valid": false, "reason": "expected_two_rejected_facets"}
	var unique: Array[Vector3] = []
	for facet in rejected:
		for point_value in facet.pre_cutoff_triangle.vertices:
			var point: Vector3 = point_value
			var found := false
			for existing in unique:
				if point.distance_squared_to(existing) <= 1.0e-14:
					found = true
					break
			if not found:
				unique.append(point)
	if unique.size() != 4:
		return {"valid": false, "reason": "two_facets_do_not_form_four_vertex_patch", "unique_vertices": unique}
	var inner := Vector3.ZERO
	for point in unique:
		if point.x < PLANE_X_A - 1.0e-6:
			inner = point
	var edge_a: Dictionary = rejected[0].boundary_contour_segment[0]
	var edge_b: Dictionary = rejected[1].boundary_contour_segment[0]
	var endpoints_a: Array[Vector3] = [edge_a.a, edge_a.b]
	var endpoints_b: Array[Vector3] = [edge_b.a, edge_b.b]
	var shared := Vector3.ZERO
	var outer_a := Vector3.ZERO
	var outer_b := Vector3.ZERO
	var shared_found := false
	for point_a in endpoints_a:
		for point_b in endpoints_b:
			if point_a.distance_squared_to(point_b) <= 1.0e-14:
				shared = point_a
				shared_found = true
				break
		if shared_found:
			break
	for point in endpoints_a:
		if point.distance_squared_to(shared) > 1.0e-14:
			outer_a = point
	for point in endpoints_b:
		if point.distance_squared_to(shared) > 1.0e-14:
			outer_b = point
	if not shared_found:
		return {"valid": false, "reason": "interface_segments_do_not_share_a_vertex", "vertices": unique}
	var original: Array[float] = [float(rejected[0].pre_cutoff_triangle.cross_squared), float(rejected[1].pre_cutoff_triangle.cross_squared)]
	var alternate := [
		(outer_a - inner).cross(outer_b - inner).length_squared(),
		(outer_b - outer_a).cross(shared - outer_a).length_squared(),
	]
	return {"valid": unique.size() == 4, "inner_vertex": inner, "ordered_interface_vertices": [outer_a, shared, outer_b],
		"fixed_interface_edges": [[outer_a, shared], [shared, outer_b]], "original_diagonal": [inner, shared],
		"alternative_diagonal": [outer_a, outer_b], "original_cross_squared": original,
		"original_all_above_cutoff": original.all(func(value: float) -> bool: return value > AREA2_CUTOFF_A),
		"alternate_cross_squared": alternate,
		"alternate_all_above_cutoff": alternate.all(func(value: float) -> bool: return value > AREA2_CUTOFF_A),
		"interpretation": "both possible triangulations of this fixed four-vertex local cavity were enumerated; at least one facet remains subthreshold in each"}

func _contour_x(vertices: PackedVector3Array) -> Dictionary:
	var segments: Array[Dictionary] = []
	for i in range(0, vertices.size(), 3):
		var tri: Array[Vector3] = [vertices[i], vertices[i + 1], vertices[i + 2]]
		var hits: Array[Vector3] = []
		for edge in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = tri[int(edge[0])]
			var b: Vector3 = tri[int(edge[1])]
			var da := a.x - PLANE_X_A
			var db := b.x - PLANE_X_A
			if absf(da) <= 1.0e-7:
				hits.append(a)
			if da * db < 0.0:
				hits.append(a.lerp(b, da / (da - db)))
		var unique: Array[Vector3] = []
		for point in hits:
			var found := false
			for old in unique:
				if point.distance_squared_to(old) <= 1.0e-12:
					found = true
					break
			if not found:
				unique.append(point)
		if unique.size() == 2 and unique[0].distance_squared_to(unique[1]) > 1.0e-12:
			segments.append({"a": unique[0], "b": unique[1]})
	return {"segments": segments}

func _emit_r83a(record: Dictionary) -> void:
	var path := OS.get_environment("R83A_OUTPUT_JSON")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("R83A_OUTPUT_WRITE_FAILED " + error_string(FileAccess.get_open_error()))
			return
		file.store_string(JSON.stringify(record) + "\n")
		file.flush()
		file.close()
	print("R83A_SEAM_EXPERIMENT " + JSON.stringify(record))

func _check_a(condition: bool, name: String) -> void:
	_assertions_a += 1
	if not condition:
		_failures_a.append(name)
