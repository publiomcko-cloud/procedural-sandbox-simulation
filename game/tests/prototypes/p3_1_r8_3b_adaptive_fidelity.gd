extends "res://tests/prototypes/p3_1_r8_2_geometry_provenance.gd"

## Bounded, test-only R8.3-B comparison. The canonical ordered SDF remains the
## authority; every mesh below is disposable and uses production tetrahedral
## extraction over float32 lattice samples. No scene or save is instantiated.
const TransitionB := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const MesherB := preload("res://scripts/terrain/marching_tetrahedra.gd")
const BrushR83 := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const FieldB := preload("res://scripts/terrain/sdf_world.gd")
const SpatialB := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const DOMAIN_MIN_B := Vector3(-1.0, 1.0, 5.0)
const DOMAIN_MAX_B := Vector3(1.0, 2.5, 7.0)
const ADAPT_MIN_B := Vector3(-0.5, 1.0, 5.5)
const ADAPT_MAX_B := Vector3(0.5, 2.0, 6.5)
const DENSE_RAY_STEP_B := 0.0001
const EDGE_ROOT_SCAN_B := 4096
const ADAPT_CELL_BUDGET_B := 4
const AREA2_CUTOFF_B := 1.0e-12

var _b_assertions: int = 0
var _b_failures: Array[String] = []
var _b_started_usec: int = 0
var _b_evidence_dir: String = ""


func _initialize() -> void:
	_b_started_usec = Time.get_ticks_usec()
	_b_evidence_dir = OS.get_environment("P31_R83B_EVIDENCE_DIR")
	call_deferred("_run_r83b")


func _run_r83b() -> void:
	var preflight: Dictionary = _r8_preflight()
	_check_b(bool(preflight.get("valid", false)), "r8_frozen_source_and_three_input_pins_validate")
	_emit_b("preflight", preflight)
	if not bool(preflight.get("valid", false)):
		_finish_b("BLOCKED", "frozen_source_or_input_preflight_failed")
		return
	var zero_result: Dictionary = _make_snapshot("zero_edit")
	var edited_result: Dictionary = _make_snapshot("center_fill_then_wall_carve")
	_check_b(bool(zero_result.get("valid", false)), "zero_edit_snapshot_reconstructs")
	_check_b(bool(edited_result.get("valid", false)), "ordered_fill_carve_snapshot_reconstructs")
	if not bool(zero_result.get("valid", false)) or not bool(edited_result.get("valid", false)):
		_finish_b("BLOCKED", "frozen_snapshot_reconstruction_failed")
		return
	var zero_snapshot: Dictionary = zero_result.get("snapshot", {})
	var edited_snapshot: Dictionary = edited_result.get("snapshot", {})
	var oracle: Dictionary = _central_ray_oracle(zero_snapshot)
	_check_b(bool(oracle.get("valid", false)), "dense_canonical_ray_oracle_has_classified_roots")
	var uniform_cases: Array[Dictionary] = []
	for spacing in [0.5, 0.25, 0.125]:
		if Time.get_ticks_usec() - _b_started_usec > 180000000:
			_finish_b("BLOCKED", "focused_diagnostic_stop_loss_180_seconds")
			return
		var built: Dictionary = _build_uniform_mesh(zero_snapshot, float(spacing), DOMAIN_MIN_B, DOMAIN_MAX_B)
		_check_b(bool(built.get("valid", false)), "uniform_mesh_build_h%s" % str(spacing))
		if not bool(built.get("valid", false)):
			_finish_b("BLOCKED", "uniform_mesh_build_failed_h%s" % str(spacing))
			return
		var metrics: Dictionary = _mesh_case_metrics(built, zero_snapshot, oracle)
		metrics["spacing_world"] = float(spacing)
		metrics["build_usec"] = int(built.get("build_usec", -1))
		metrics["sample_count"] = int(built.get("sample_count", -1))
		metrics["sample_bytes_float32"] = int(built.get("sample_count", -1)) * 4
		metrics["estimated_mesh_attribute_bytes_positions_normals"] = int(built.get("positions", PackedVector3Array()).size()) * 24
		metrics["triangle_count"] = int(built.get("triangle_count", -1))
		metrics["mesh_sha256"] = String(built.get("mesh_sha256", ""))
		metrics["canonical_input_sha256"] = INPUT_SHA_ZERO
		metrics["sample_representation"] = "canonical SDF_v1 queried at nodes, then explicitly rounded through PackedFloat32Array before the unchanged production tetrahedral polygonizer"
		uniform_cases.append(metrics)
		_emit_b("uniform_h%s" % str(spacing).replace(".", "p"), metrics)
	var neighbor_cases: Array[Dictionary] = []
	for spacing in [0.5, 0.25, 0.125]:
		var half_a: Dictionary = _build_uniform_mesh(zero_snapshot, float(spacing), Vector3(-1.0, 1.0, 5.0), Vector3(0.0, 2.5, 7.0))
		var half_b: Dictionary = _build_uniform_mesh(zero_snapshot, float(spacing), Vector3(0.0, 1.0, 5.0), Vector3(1.0, 2.5, 7.0))
		var split: Dictionary = _compare_mesh_plane_contours(half_a.get("positions", PackedVector3Array()), half_b.get("positions", PackedVector3Array()), 0, 0.0)
		var record: Dictionary = {"spacing_world": float(spacing), "left_valid": bool(half_a.get("valid", false)),
			"right_valid": bool(half_b.get("valid", false)), "interface_x": 0.0,
			"left_triangle_count": int(half_a.get("triangle_count", -1)), "right_triangle_count": int(half_b.get("triangle_count", -1)),
			"shared_sample_comparison": _compare_shared_face_samples(zero_snapshot, float(spacing)), "mesh_contour_comparison": split,
			"scope": "disposable equal-resolution neighbors use globally aligned cell coordinates; no chunk or production seam acceptance is inferred"}
		neighbor_cases.append(record)
		_check_b(bool(record.left_valid) and bool(record.right_valid), "equal_resolution_neighbor_meshes_build_h%s" % str(spacing))
		_emit_b("neighbor_h%s" % str(spacing).replace(".", "p"), record)
	var adaptive: Dictionary = _build_adaptive_mesh(zero_snapshot)
	_check_b(bool(adaptive.get("valid", false)), "bounded_adaptive_local_mesh_builds")
	if not bool(adaptive.get("valid", false)):
		_finish_b("BLOCKED", "bounded_adaptive_mesh_build_failed")
		return
	var adaptive_metrics: Dictionary = _mesh_case_metrics(adaptive, zero_snapshot, oracle)
	var selection: Dictionary = adaptive.get("adaptive_selection", {})
	var selected_rows: Array = selection.get("selected_candidates", [])
	_check_b(int(selection.get("candidate_cell_count", 0)) == 8, "adaptive_policy_scores_frozen_roi_cells")
	_check_b(selected_rows.size() == 4, "adaptive_policy_obeys_fixed_refinement_budget")
	_check_b(not bool(selection.get("selection_is_product_threshold", true)), "adaptive_policy_is_exploratory_not_product_acceptance")
	adaptive_metrics["policy"] = String(adaptive.get("adaptive_selection", {}).get("policy", "adaptive_selection_policy_missing"))
	adaptive_metrics["adaptive_selection"] = selection
	adaptive_metrics["refined_base_cell_count"] = selected_rows.size()
	adaptive_metrics["sample_count"] = int(adaptive.get("sample_count", -1))
	adaptive_metrics["sample_bytes_float32"] = int(adaptive.get("sample_count", -1)) * 4
	adaptive_metrics["estimated_mesh_attribute_bytes_positions_normals"] = int(adaptive.get("positions", PackedVector3Array()).size()) * 24
	adaptive_metrics["triangle_count"] = int(adaptive.get("triangle_count", -1))
	adaptive_metrics["build_usec"] = int(adaptive.get("build_usec", -1))
	adaptive_metrics["mesh_sha256"] = String(adaptive.get("mesh_sha256", ""))
	adaptive_metrics["adaptive_interfaces"] = _adaptive_interface_comparison(adaptive.get("cells", []), zero_snapshot)
	adaptive_metrics["canonical_input_sha256"] = INPUT_SHA_ZERO
	adaptive_metrics["limitation"] = "bounded score-driven cell-selection diagnostic; nonconforming transition interfaces are measured but not repaired"
	_emit_b("adaptive_roi", adaptive_metrics)
	var branch_record: Dictionary = _triangle_branch_refinement(edited_snapshot)
	_check_b(bool(branch_record.get("valid", false)), "frozen_triangle_3103_edge_roots_are_compared")
	_emit_b("triangle_3103_branch_refinement", branch_record)
	var result: Dictionary = {"status": "DIAGNOSTIC_COMPLETE", "measured_source_base": "4f08b67522507bd196a74a1089c773f272235343",
		"scenario_inputs": {"zero_edit_sha256": INPUT_SHA_ZERO, "ordered_fill_carve_sha256": INPUT_SHA_FILL_CARVE},
		"ray_oracle": oracle, "uniform_resolution_cases": uniform_cases, "equal_resolution_neighbor_cases": neighbor_cases,
		"adaptive_roi_case": adaptive_metrics, "triangle_3103": branch_record,
		"assertions": _b_assertions, "failures": _b_failures,
		"geometry_contract": "NO_OWNER_APPROVED_TOLERANCE", "performance_disposition": "EXPLORATORY_CPU_ONLY_NOT_ACCEPTANCE",
		"gpu_presented_frame_collider": "NOT_MEASURED", "execution_scope": "small bounded synthetic mesh research; no production or gameplay path"}
	_emit_b("result", result)
	_finish_b("DIAGNOSTIC_COMPLETE" if _b_failures.is_empty() else "BLOCKED", "bounded_resolution_and_adaptive_refinement_measured")


func _build_uniform_mesh(snapshot: Dictionary, spacing: float, minimum: Vector3, maximum: Vector3) -> Dictionary:
	if spacing <= 0.0 or not minimum.is_finite() or not maximum.is_finite():
		return {"valid": false, "reason": "invalid_mesh_domain_or_spacing"}
	var dimensions: Vector3i = Vector3i(roundi((maximum.x - minimum.x) / spacing),
		roundi((maximum.y - minimum.y) / spacing), roundi((maximum.z - minimum.z) / spacing))
	if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.z <= 0:
		return {"valid": false, "reason": "empty_mesh_domain"}
	var cache: Dictionary = {}
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var expected_facets: int = 0
	var emitted_facets: int = 0
	var started: int = Time.get_ticks_usec()
	for y in range(dimensions.y):
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var counts: Dictionary = _append_sampled_cell(minimum + Vector3(x, y, z) * spacing, spacing, snapshot, cache, positions, normals)
				expected_facets += int(counts.get("expected", 0))
				emitted_facets += int(counts.get("emitted", 0))
	var elapsed: int = Time.get_ticks_usec() - started
	return _finish_mesh(positions, normals, cache.size(), elapsed, expected_facets, emitted_facets,
		{"valid": true, "dimensions": dimensions, "domain_min": minimum, "domain_max": maximum})


func _build_adaptive_mesh(snapshot: Dictionary) -> Dictionary:
	var base_step: float = 0.5
	var coarse_dims: Vector3i = Vector3i(4, 3, 4)
	var candidate_probe_cache: Dictionary = {}
	var candidates: Array[Dictionary] = []
	var started: int = Time.get_ticks_usec()
	for y in range(coarse_dims.y):
		for z in range(coarse_dims.z):
			for x in range(coarse_dims.x):
				var coarse_origin: Vector3 = DOMAIN_MIN_B + Vector3(x, y, z) * base_step
				var coarse_max: Vector3 = coarse_origin + Vector3.ONE * base_step
				var within_roi: bool = coarse_origin.x >= ADAPT_MIN_B.x and coarse_max.x <= ADAPT_MAX_B.x \
					and coarse_origin.y >= ADAPT_MIN_B.y and coarse_max.y <= ADAPT_MAX_B.y \
					and coarse_origin.z >= ADAPT_MIN_B.z and coarse_max.z <= ADAPT_MAX_B.z
				if not within_roi:
					continue
				var candidate: Dictionary = _adaptive_probe_score(coarse_origin, base_step, snapshot, candidate_probe_cache)
				if not bool(candidate.get("branch_trace_matches_canonical", false)):
					return {"valid": false, "reason": "adaptive_branch_trace_disagrees_with_canonical_field", "coarse_xyz": [x, y, z]}
				candidate["coarse_xyz"] = [x, y, z]
				candidate["world_min"] = [coarse_origin.x, coarse_origin.y, coarse_origin.z]
				candidates.append(candidate)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_branches: int = int(a.get("branch_label_count", 0))
		var b_branches: int = int(b.get("branch_label_count", 0))
		if a_branches != b_branches:
			return a_branches > b_branches
		var a_error: float = float(a.get("center_interpolation_error", 0.0))
		var b_error: float = float(b.get("center_interpolation_error", 0.0))
		if a_error != b_error:
			return a_error > b_error
		var a_xyz: Array = a.get("coarse_xyz", [0, 0, 0])
		var b_xyz: Array = b.get("coarse_xyz", [0, 0, 0])
		if int(a_xyz[0]) != int(b_xyz[0]):
			return int(a_xyz[0]) < int(b_xyz[0])
		if int(a_xyz[1]) != int(b_xyz[1]):
			return int(a_xyz[1]) < int(b_xyz[1])
		return int(a_xyz[2]) < int(b_xyz[2])
	)
	var selected: Dictionary = {}
	var selected_candidates: Array[Dictionary] = []
	for candidate_index in range(candidates.size()):
		var candidate: Dictionary = candidates[candidate_index]
		var xyz: Array = candidate.get("coarse_xyz", [0, 0, 0])
		var key: String = "%d,%d,%d" % [int(xyz[0]), int(xyz[1]), int(xyz[2])]
		candidate["rank"] = candidate_index + 1
		candidate["selected_for_refinement"] = candidate_index < ADAPT_CELL_BUDGET_B
		if candidate_index < ADAPT_CELL_BUDGET_B:
			selected[key] = true
			selected_candidates.append(candidate)
	var mesh_cache: Dictionary = {}
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var cells: Array[Dictionary] = []
	var expected_facets: int = 0
	var emitted_facets: int = 0
	for y in range(coarse_dims.y):
		for z in range(coarse_dims.z):
			for x in range(coarse_dims.x):
				var coarse_origin: Vector3 = DOMAIN_MIN_B + Vector3(x, y, z) * base_step
				var coarse_max: Vector3 = coarse_origin + Vector3.ONE * base_step
				var refine_key: String = "%d,%d,%d" % [x, y, z]
				if selected.has(refine_key):
					var fine_step: float = 0.125
					for fy in range(4):
						for fz in range(4):
							for fx in range(4):
								var fine_origin: Vector3 = coarse_origin + Vector3(fx, fy, fz) * fine_step
								var fine_pos: PackedVector3Array = PackedVector3Array()
								var fine_norm: PackedVector3Array = PackedVector3Array()
								var fine_counts: Dictionary = _append_sampled_cell(fine_origin, fine_step, snapshot, mesh_cache, fine_pos, fine_norm)
								positions.append_array(fine_pos)
								normals.append_array(fine_norm)
								expected_facets += int(fine_counts.get("expected", 0))
								emitted_facets += int(fine_counts.get("emitted", 0))
								cells.append({"minimum": fine_origin, "maximum": fine_origin + Vector3.ONE * fine_step,
									"spacing": fine_step, "refined": true, "positions": fine_pos})
				else:
					var coarse_pos: PackedVector3Array = PackedVector3Array()
					var coarse_norm: PackedVector3Array = PackedVector3Array()
					var coarse_counts: Dictionary = _append_sampled_cell(coarse_origin, base_step, snapshot, mesh_cache, coarse_pos, coarse_norm)
					positions.append_array(coarse_pos)
					normals.append_array(coarse_norm)
					expected_facets += int(coarse_counts.get("expected", 0))
					emitted_facets += int(coarse_counts.get("emitted", 0))
					cells.append({"minimum": coarse_origin, "maximum": coarse_max, "spacing": base_step,
						"refined": false, "positions": coarse_pos})
	var selection: Dictionary = {
		"policy": "within the frozen eight-cell cave ROI, rank candidates by distinct canonical winning-branch labels, then center-vs-eight-corner trilinear density residual, then lexicographic cell coordinate; refine top four cells to spacing 0.125",
		"selection_probe_samples": candidate_probe_cache.size(),
		"candidate_cell_count": candidates.size(),
		"refined_base_cell_budget": ADAPT_CELL_BUDGET_B,
		"selected_candidates": selected_candidates,
		"candidate_scores": candidates,
		"selection_is_product_threshold": false
	}
	return _finish_mesh(positions, normals, mesh_cache.size(), Time.get_ticks_usec() - started, expected_facets, emitted_facets,
		{"valid": true, "cells": cells, "adaptive_selection": selection,
		"coarse_cell_count": coarse_dims.x * coarse_dims.y * coarse_dims.z,
		"fine_cells_per_refined_base_cell": 64})

func _adaptive_probe_score(origin: Vector3, spacing: float, snapshot: Dictionary, cache: Dictionary) -> Dictionary:
	var corner_density_sum: float = 0.0
	var branch_labels: Dictionary = {}
	var trace_match: bool = true
	for corner_value in MesherB.CORNERS:
		var corner: Vector3i = corner_value
		var point: Vector3 = origin + Vector3(corner) * spacing
		corner_density_sum += _sample_cached_f32(point, snapshot, cache)
		var corner_trace: Dictionary = _field_trace(point, snapshot)
		var corner_branch: String = String(corner_trace.get("winning_branch", "unknown"))
		branch_labels[corner_branch] = true
		trace_match = trace_match and bool(corner_trace.get("matches_canonical", false))
	var center: Vector3 = origin + Vector3.ONE * (spacing * 0.5)
	var center_density: float = _sample_cached_f32(center, snapshot, cache)
	var center_trace: Dictionary = _field_trace(center, snapshot)
	var center_branch: String = String(center_trace.get("winning_branch", "unknown"))
	branch_labels[center_branch] = true
	trace_match = trace_match and bool(center_trace.get("matches_canonical", false))
	var sorted_labels: Array[String] = []
	for label in branch_labels.keys():
		sorted_labels.append(String(label))
	sorted_labels.sort()
	return {"center_interpolation_error": absf(center_density - corner_density_sum / 8.0),
		"branch_label_count": sorted_labels.size(), "branch_labels": sorted_labels,
		"branch_trace_matches_canonical": trace_match}

func _append_sampled_cell(origin: Vector3, spacing: float, snapshot: Dictionary, cache: Dictionary,
		positions: PackedVector3Array, normals: PackedVector3Array) -> Dictionary:
	var points: Array[Vector3] = []
	var values: Array[float] = []
	var solid: bool = false
	var empty: bool = false
	for corner_value in MesherB.CORNERS:
		var corner: Vector3i = corner_value
		var point: Vector3 = origin + Vector3(corner) * spacing
		points.append(point)
		var density: float = _sample_cached_f32(point, snapshot, cache)
		values.append(density)
		solid = solid or density >= 0.0
		empty = empty or density < 0.0
	if not solid or not empty:
		return {"expected": 0, "emitted": 0}
	var expected: int = 0
	var emitted: int = 0
	for tetra_value in MesherB.TETRAHEDRA:
		var tetra: Array = tetra_value
		var inside: int = 0
		for corner_index_value in tetra:
			if values[int(corner_index_value)] >= 0.0:
				inside += 1
		if inside > 0 and inside < 4:
			expected += 2 if inside == 2 else 1
			emitted += MesherB._polygonize_tetra(tetra, points, values, positions, normals)
	return {"expected": expected, "emitted": emitted}


func _sample_cached_f32(point: Vector3, snapshot: Dictionary, cache: Dictionary) -> float:
	var key: String = "%.6f,%.6f,%.6f" % [point.x, point.y, point.z]
	if cache.has(key):
		return float(cache[key])
	var canonical: float = TransitionB.sample_canonical(SEED, point, snapshot)
	var packed: PackedFloat32Array = PackedFloat32Array()
	packed.append(canonical)
	var rounded: float = float(packed[0])
	cache[key] = rounded
	return rounded


func _finish_mesh(positions: PackedVector3Array, normals: PackedVector3Array, samples: int, elapsed: int,
		expected_facets: int, emitted_facets: int, extra: Dictionary) -> Dictionary:
	if positions.size() != normals.size() or positions.size() % 3 != 0:
		return {"valid": false, "reason": "mesh_attribute_or_triangle_count_mismatch"}
	for point in positions:
		if not point.is_finite():
			return {"valid": false, "reason": "nonfinite_mesh_vertex"}
	for normal in normals:
		if not normal.is_finite():
			return {"valid": false, "reason": "nonfinite_mesh_normal"}
	var bytes: PackedByteArray = PackedByteArray()
	bytes.append_array(positions.to_byte_array())
	bytes.append_array(normals.to_byte_array())
	return {"valid": true, "positions": positions, "normals": normals, "sample_count": samples,
		"triangle_count": positions.size() / 3, "build_usec": elapsed, "expected_pre_cutoff_facets": expected_facets,
		"emitted_facets": emitted_facets, "facets_omitted_by_polygonizer": expected_facets - emitted_facets,
		"mesh_sha256": _sha256(bytes), "cpu_array_bytes": positions.size() * 24 + samples * 4}.merged(extra, true)


func _mesh_case_metrics(mesh: Dictionary, snapshot: Dictionary, oracle: Dictionary) -> Dictionary:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = mesh.get("normals", PackedVector3Array())
	var residuals: PackedFloat64Array = PackedFloat64Array()
	var angle_values: PackedFloat64Array = PackedFloat64Array()
	var reversed: int = 0
	var zero_area: int = 0
	for i in range(0, positions.size(), 3):
		var a: Vector3 = positions[i]
		var b: Vector3 = positions[i + 1]
		var c: Vector3 = positions[i + 2]
		var cross: Vector3 = (b - a).cross(c - a)
		if cross.length_squared() <= AREA2_CUTOFF_B:
			zero_area += 1
			continue
		var centroid: Vector3 = (a + b + c) / 3.0
		residuals.append(absf(TransitionB.sample_canonical(SEED, centroid, snapshot)))
		var gradient: Vector3 = _r8_gradient(centroid, snapshot)
		if gradient.length_squared() > 1.0e-12:
			var outward: Vector3 = -gradient
			var face: Vector3 = cross.normalized()
			angle_values.append(rad_to_deg(face.angle_to(outward)))
			if face.dot(outward) < 0.0:
				reversed += 1
	var topology: Dictionary = _local_topology(positions, DOMAIN_MIN_B, DOMAIN_MAX_B)
	var cross_section: Dictionary = _cross_section_comparison(positions, snapshot, DOMAIN_MIN_B.y, DOMAIN_MAX_B.y)
	var center_hits: Array[Dictionary] = _unique_ray_hits(_ray_hits_r81(positions, Vector3(0.0, DOMAIN_MAX_B.y + 0.5, 6.0), Vector3.DOWN, 4.0))
	var roots: Array = oracle.get("continuous_roots_high_to_low", [])
	var first_delta: float = -1.0
	if not center_hits.is_empty() and not roots.is_empty():
		var mesh_y: float = float(center_hits[0].get("position", [0.0, 0.0, 0.0])[1])
		first_delta = absf(mesh_y - float(roots[0]))
	return {"valid": true, "vertex_count": positions.size(), "expected_pre_cutoff_facets": mesh.get("expected_pre_cutoff_facets", -1),
		"facets_omitted_by_unchanged_1e_minus_12_cutoff": mesh.get("facets_omitted_by_polygonizer", -1),
		"center_ray_mesh_hit_count": center_hits.size(), "center_ray_mesh_hits": center_hits,
		"continuous_roots_on_center_ray": roots, "nearest_center_ray_mesh_root_displacement_world": first_delta,
		"cross_section_25_ray_summary": cross_section, "centroid_canonical_density_residual": _summary_b(residuals),
		"face_normal_vs_canonical_outward_gradient_degrees_h0p01": _summary_b(angle_values),
		"face_winding_opposing_canonical_outward_gradient_count": reversed, "subthreshold_emitted_triangle_count": zero_area,
		"topology": topology, "static_memory_bytes": OS.get_static_memory_usage(),
		"static_memory_peak_bytes": OS.get_static_memory_peak_usage(),
		"ray_duplicate_distance_grouping_world": 0.00001,
		"canonical_outward": "negative density gradient; finite differences h=0.01; branch-switching neighborhoods can make this diagnostic nonsmooth"}


func _central_ray_oracle(snapshot: Dictionary) -> Dictionary:
	var origin: Vector3 = Vector3(0.0, DOMAIN_MAX_B.y, 6.0)
	var direction: Vector3 = Vector3.DOWN
	var roots: Array[float] = _scan_roots_y(snapshot, origin.x, origin.z, DOMAIN_MIN_B.y, DOMAIN_MAX_B.y, DENSE_RAY_STEP_B)
	var branches: Array[String] = []
	var last: String = ""
	for i in range(0, 151):
		var y: float = DOMAIN_MIN_B.y + float(i) * 0.01
		var trace: Dictionary = _ordered_branch_at(Vector3(origin.x, y, origin.z), snapshot)
		var signature: String = String(trace.get("winner", "?"))
		if signature != last:
			branches.append(signature)
			last = signature
	var roots_high_to_low: Array[float] = roots.duplicate()
	roots_high_to_low.reverse()
	return {"valid": not roots.is_empty(), "ray_origin": origin, "ray_direction": direction,
		"interval_y": [DOMAIN_MIN_B.y, DOMAIN_MAX_B.y], "dense_step_world": DENSE_RAY_STEP_B,
		"continuous_roots_low_to_high_y": roots, "continuous_roots_high_to_low": roots_high_to_low,
		"sign_change_root_count": roots.size(), "branch_order_from_low_to_high_y": branches,
		"tangency_limit": "dense sign-change scan; exact even-multiplicity roots without sign change are not proven absent",
		"world_boundary_mapping": {"world_x": 0.0, "negative_region_owner": [-1, 0], "negative_region_local_x": 16.0,
			"half_open_owner": [0, 0], "half_open_local_x": 0.0,
			"canonical_density_bits_at_boundary": _boundary_density_bits(snapshot)}}


func _boundary_density_bits(snapshot: Dictionary) -> Dictionary:
	var p: Vector3 = Vector3(0.0, 1.52089476585, 6.0)
	var negative: float = _sample_region_local(Vector2i(-1, 0), Vector3(16.0, p.y, p.z), snapshot)
	var positive: float = _sample_region_local(Vector2i(0, 0), Vector3(0.0, p.y, p.z), snapshot)
	return {"negative_region_density": negative, "half_open_region_density": positive,
		"bitwise_equal_as_binary32": _f32_hex(negative) == _f32_hex(positive), "negative_bits": _f32_hex(negative), "positive_bits": _f32_hex(positive)}


func _sample_region_local(region: Vector2i, local: Vector3, snapshot: Dictionary) -> float:
	var raw: float = BrushR83.sample_density_snapshot(SEED, region, local, false, snapshot)
	var packed: PackedFloat32Array = PackedFloat32Array()
	packed.append(raw)
	return float(packed[0])


func _ordered_branch_at(point: Vector3, snapshot: Dictionary) -> Dictionary:
	var mapped: Dictionary = SpatialB.world_to_region_local(point)
	if not bool(mapped.get("valid", false)):
		return {"winner": "invalid", "density": NAN}
	var density: float = FieldB.sample_density(SEED, mapped.get("region_key", Vector2i.ZERO), mapped.get("local_position", Vector3.ZERO), false)
	var base_trace: Dictionary = _field_branch_values(point, snapshot)
	var winner: String = "base:" + String(base_trace.get("base_terms", {}).get("winner", "unknown"))
	var centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
	var radii: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
	var modes: PackedByteArray = snapshot.get("modes", PackedByteArray())
	for i in range(centers.size()):
		var distance: float = centers[i].distance_to(point)
		var mode: int = int(modes[i])
		var operator_value: float = distance - float(radii[i]) if mode == BrushR83.Mode.CARVE else float(radii[i]) - distance
		if mode == BrushR83.Mode.CARVE and operator_value < density:
			density = operator_value
			winner = "operation:%d:CARVE" % i
		elif mode == BrushR83.Mode.FILL and operator_value > density:
			density = operator_value
			winner = "operation:%d:FILL" % i
	return {"winner": winner, "density": density}


func _scan_roots_y(snapshot: Dictionary, x: float, z: float, ymin: float, ymax: float, step: float) -> Array[float]:
	var roots: Array[float] = []
	var count: int = roundi((ymax - ymin) / step)
	var previous_y: float = ymin
	var previous_d: float = TransitionB.sample_canonical(SEED, Vector3(x, previous_y, z), snapshot)
	for i in range(1, count + 1):
		var current_y: float = ymin + float(i) * step
		var current_d: float = TransitionB.sample_canonical(SEED, Vector3(x, current_y, z), snapshot)
		if (previous_d >= 0.0) != (current_d >= 0.0):
			roots.append(_bisect_root_y(snapshot, x, z, previous_y, current_y, previous_d >= 0.0))
		previous_y = current_y
		previous_d = current_d
	return roots


func _bisect_root_y(snapshot: Dictionary, x: float, z: float, low_in: float, high_in: float, low_positive: bool) -> float:
	var low: float = low_in
	var high: float = high_in
	for _i in range(42):
		var middle: float = (low + high) * 0.5
		var density: float = TransitionB.sample_canonical(SEED, Vector3(x, middle, z), snapshot)
		if (density >= 0.0) == low_positive:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


func _cross_section_comparison(positions: PackedVector3Array, snapshot: Dictionary, ymin: float, ymax: float) -> Dictionary:
	var coords: Array[float] = [-0.5, -0.25, 0.0, 0.25, 0.5]
	var rows: Array[Dictionary] = []
	var mismatches: int = 0
	for x in coords:
		for z in [5.5, 5.75, 6.0, 6.25, 6.5]:
			var roots: Array[float] = _scan_roots_y(snapshot, x, z, ymin, ymax, 0.0025)
			roots.reverse()
			var mesh_hits: Array[Dictionary] = _unique_ray_hits(_ray_hits_r81(positions, Vector3(x, ymax + 0.5, z), Vector3.DOWN, ymax - ymin + 1.0))
			var matched: int = mini(roots.size(), mesh_hits.size())
			if roots.size() != mesh_hits.size():
				mismatches += 1
			var errors: Array[float] = []
			for idx in range(matched):
				var hit_pos: Array = mesh_hits[idx].get("position", [x, 0.0, z])
				errors.append(absf(float(hit_pos[1]) - roots[idx]))
			rows.append({"x": x, "z": z, "canonical_root_y": roots, "mesh_hit_y": mesh_hits.map(func(hit: Dictionary) -> float: return float(hit.get("position", [0.0,0.0,0.0])[1])),
				"root_count": roots.size(), "mesh_hit_count": mesh_hits.size(), "matched_by_high_to_low_order": matched,
				"vertical_displacements_world": errors})
	return {"ray_count": rows.size(), "root_hit_count_mismatch_ray_count": mismatches,
		"maximum_matched_vertical_displacement_world": _max_nested_errors(rows), "rays": rows,
		"classification": "roots and triangle hits are compared high-to-low after collapsing coincident triangle hits within 1e-5 world units; grouping is measurement bookkeeping, not geometry acceptance"}


func _unique_ray_hits(hits: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var prior_distance: float = -INF
	for hit in hits:
		var distance: float = float(hit.get("distance", INF))
		if result.is_empty() or absf(distance - prior_distance) > 0.00001:
			result.append(hit)
			prior_distance = distance
	return result


func _max_nested_errors(rows: Array[Dictionary]) -> float:
	var maximum: float = 0.0
	for row in rows:
		for value in row.get("vertical_displacements_world", []):
			maximum = maxf(maximum, float(value))
	return maximum


func _local_topology(positions: PackedVector3Array, minimum: Vector3, maximum: Vector3) -> Dictionary:
	var incidence: Dictionary = {}
	var triangle_count: int = positions.size() / 3
	for i in range(0, positions.size(), 3):
		var points: Array[Vector3] = [positions[i], positions[i + 1], positions[i + 2]]
		for edge in [[0,1],[1,2],[2,0]]:
			var a: Vector3 = points[int(edge[0])]
			var b: Vector3 = points[int(edge[1])]
			var key: String = _edge_key_b(_point_key_b(a), _point_key_b(b))
			var record: Dictionary = incidence.get(key, {"count":0,"a":a,"b":b})
			record["count"] = int(record.get("count",0)) + 1
			incidence[key] = record
	var crop_open: int = 0
	var internal_open: int = 0
	var nonmanifold: int = 0
	for key in incidence:
		var edge_record: Dictionary = incidence[key]
		var count: int = int(edge_record.get("count",0))
		if count == 1:
			var a: Vector3 = edge_record.a
			var b: Vector3 = edge_record.b
			var on_crop: bool = _edge_on_box_boundary(a, b, minimum, maximum)
			if on_crop:
				crop_open += 1
			else:
				internal_open += 1
		elif count != 2:
			nonmanifold += 1
	return {"triangle_count": triangle_count, "unique_edges": incidence.size(), "crop_boundary_open_edges": crop_open,
		"internal_open_edges": internal_open, "nonmanifold_edges": nonmanifold,
		"edge_key_quantization_world": 0.00001, "note": "finite box boundary edges are separated; this cropped diagnostic is not a closed-manifold claim"}


func _edge_on_box_boundary(a: Vector3, b: Vector3, minimum: Vector3, maximum: Vector3) -> bool:
	var e: float = 0.00001
	return (absf(a.x - minimum.x) <= e and absf(b.x - minimum.x) <= e) \
		or (absf(a.x - maximum.x) <= e and absf(b.x - maximum.x) <= e) \
		or (absf(a.y - minimum.y) <= e and absf(b.y - minimum.y) <= e) \
		or (absf(a.y - maximum.y) <= e and absf(b.y - maximum.y) <= e) \
		or (absf(a.z - minimum.z) <= e and absf(b.z - minimum.z) <= e) \
		or (absf(a.z - maximum.z) <= e and absf(b.z - maximum.z) <= e)


func _compare_shared_face_samples(snapshot: Dictionary, spacing: float) -> Dictionary:
	var differences: int = 0
	var samples: int = 0
	for y_index in range(roundi((DOMAIN_MAX_B.y - DOMAIN_MIN_B.y) / spacing) + 1):
		for z_index in range(roundi((DOMAIN_MAX_B.z - DOMAIN_MIN_B.z) / spacing) + 1):
			var point: Vector3 = Vector3(0.0, DOMAIN_MIN_B.y + float(y_index) * spacing, DOMAIN_MIN_B.z + float(z_index) * spacing)
			var left: float = _sample_region_local(Vector2i(-1,0), Vector3(16.0,point.y,point.z), snapshot)
			var right: float = _sample_region_local(Vector2i(0,0), Vector3(0.0,point.y,point.z), snapshot)
			if _f32_hex(left) != _f32_hex(right):
				differences += 1
			samples += 1
	return {"sample_count": samples, "bitwise_different_count": differences,
		"same_world_coordinates_sampled_from_negative_and_half_open_regions": true}


func _compare_mesh_plane_contours(a: PackedVector3Array, b: PackedVector3Array, axis: int, plane: float) -> Dictionary:
	var segments_a: Dictionary = _mesh_plane_segments(a, axis, plane)
	var segments_b: Dictionary = _mesh_plane_segments(b, axis, plane)
	var only_a: Array[String] = []
	var only_b: Array[String] = []
	for key in segments_a:
		if not segments_b.has(key):
			only_a.append(String(key))
	for key in segments_b:
		if not segments_a.has(key):
			only_b.append(String(key))
	return {"segments_left": segments_a.size(), "segments_right": segments_b.size(), "unmatched_left": only_a,
		"unmatched_right": only_b, "exact_quantized_contour_match": only_a.is_empty() and only_b.is_empty(),
		"key_quantization_world": 0.00001}


func _mesh_plane_segments(positions: PackedVector3Array, axis: int, plane: float) -> Dictionary:
	var result: Dictionary = {}
	for i in range(0, positions.size(), 3):
		var tri: Array[Vector3] = [positions[i], positions[i + 1], positions[i + 2]]
		var hits: Array[Vector3] = []
		for edge in [[0,1],[1,2],[2,0]]:
			var p: Vector3 = tri[int(edge[0])]
			var q: Vector3 = tri[int(edge[1])]
			var dp: float = p[axis] - plane
			var dq: float = q[axis] - plane
			if absf(dp) <= 1.0e-7:
				hits.append(p)
			if dp * dq < 0.0:
				hits.append(p.lerp(q, dp / (dp - dq)))
		var unique: Array[Vector3] = []
		for hit in hits:
			var seen: bool = false
			for prior in unique:
				if hit.distance_squared_to(prior) <= 1.0e-12:
					seen = true
					break
			if not seen:
				unique.append(hit)
		if unique.size() == 2 and unique[0].distance_squared_to(unique[1]) > 1.0e-12:
			var ka: String = _point_key_b(unique[0])
			var kb: String = _point_key_b(unique[1])
			result[_edge_key_b(ka,kb)] = true
	return result


func _adaptive_interface_comparison(cells: Array, _snapshot: Dictionary) -> Dictionary:
	var interfaces: Array[Dictionary] = []
	var total_mismatches: int = 0
	var specs: Array[Dictionary] = [
		{"axis":0,"plane":ADAPT_MIN_B.x,"inside_face":"low"},{"axis":0,"plane":ADAPT_MAX_B.x,"inside_face":"high"},
		{"axis":1,"plane":ADAPT_MIN_B.y,"inside_face":"low"},{"axis":1,"plane":ADAPT_MAX_B.y,"inside_face":"high"},
		{"axis":2,"plane":ADAPT_MIN_B.z,"inside_face":"low"},{"axis":2,"plane":ADAPT_MAX_B.z,"inside_face":"high"}]
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var axis: int = int(spec.axis)
		var plane: float = float(spec.plane)
		var fine: Dictionary = {}
		var coarse: Dictionary = {}
		for cell_value in cells:
			var cell: Dictionary = cell_value
			var lo: Vector3 = cell.minimum
			var hi: Vector3 = cell.maximum
			var low_face: bool = String(spec.inside_face) == "low"
			var face_coordinate: float = lo[axis] if (bool(cell.refined) == low_face) else hi[axis]
			var touches: bool = absf(face_coordinate - plane) <= 1.0e-7
			if not touches:
				continue
			var target_map: Dictionary = fine if bool(cell.refined) else coarse
			var local_segments: Dictionary = _mesh_plane_segments(cell.positions, axis, plane)
			for key in local_segments:
				target_map[key] = true
		var only_fine: int = 0
		var only_coarse: int = 0
		for key in fine:
			if not coarse.has(key): only_fine += 1
		for key in coarse:
			if not fine.has(key): only_coarse += 1
		var mismatch: bool = only_fine + only_coarse > 0
		if mismatch: total_mismatches += 1
		interfaces.append({"axis": axis, "plane": plane, "roi_face": spec.inside_face, "fine_segments": fine.size(),
			"coarse_segments": coarse.size(), "fine_only": only_fine, "coarse_only": only_coarse,
			"exact_contour_match": not mismatch})
	return {"interface_count": interfaces.size(), "interfaces_with_contour_mismatch": total_mismatches,
		"interfaces": interfaces, "acceptance": "diagnostic only; nonconforming ROI boundary is intentionally not repaired"}


func _triangle_branch_refinement(snapshot: Dictionary) -> Dictionary:
	var normals: Dictionary = _diagnose_r81_normals()
	if not bool(normals.get("valid", false)):
		return {"valid": false, "reason": "frozen_triangle_source_trace_unavailable"}
	var trace: Dictionary = _triangle_trace(normals)
	if not bool(trace.get("valid", false)):
		return {"valid": false, "reason": "triangle_3103_reconstruction_failed"}
	var edges: Array = trace.get("interpolation_edges", [])
	var rows: Array[Dictionary] = []
	for edge_value in edges:
		var edge: Dictionary = edge_value
		var a: Vector3 = _parse_vector3(edge.get("a_world", []))
		var b: Vector3 = _parse_vector3(edge.get("b_world", []))
		var original_bracket: Dictionary = edge.get("continuous_root", {})
		var dense_continuous: Dictionary = _continuous_edge_root_scan(snapshot, a, b, EDGE_ROOT_SCAN_B)
		var resolution_rows: Array[Dictionary] = []
		for spacing in [0.5,0.25,0.125]:
			var subdivisions: int = maxi(1, roundi(a.distance_to(b) / float(spacing)))
			var piecewise_roots: Array[Dictionary] = _piecewise_edge_roots(snapshot, a, b, subdivisions)
			var nearest: float = INF
			for root in piecewise_roots:
				for exact_root_value in dense_continuous.get("roots", []):
					var exact_root: Dictionary = exact_root_value
					nearest = minf(nearest, absf(float(root.get("piecewise_linear_t", -1.0)) - float(exact_root.get("t", -2.0))) * a.distance_to(b))
			resolution_rows.append({"nominal_spacing_world": spacing, "edge_subdivisions": subdivisions,
				"piecewise_sign_change_root_count": piecewise_roots.size(), "piecewise_roots": piecewise_roots,
				"nearest_continuous_root_distance_world": nearest if is_finite(nearest) else -1.0})
		rows.append({"tetra_edge_corner_indices": edge.get("corner_indices", []), "world_a": a, "world_b": b,
			"R8_2_original_continuous_root_bracket": original_bracket, "dense_continuous_root_scan": dense_continuous,
			"branch_winner_changes_across_original_edge": edge.get("winner_changes_across_edge", false),
			"sampled_roots_by_spacing": resolution_rows})
	return {"valid": edges.size() >= 3, "scenario_input_sha256": INPUT_SHA_FILL_CARVE,
		"triangle_index": trace.get("triangle_index", -1), "cell_id": trace.get("owner_cell_id", -1),
		"cell_coordinate": trace.get("cell_coordinate", []), "tetrahedron_index": trace.get("tetrahedron_index", -1),
		"edges": rows, "sampled_node_value_representation": "each canonical double result rounded through PackedFloat32Array before edge interpolation",
		"continuous_root_method": "4096 uniform brackets per source edge plus bisection for sign-changing intervals; near-zero local extrema are listed as tangency candidates but exact even-multiplicity roots are not certified",
		"scope": "the frozen triangle 3103 source edges only; does not re-run the full edited chunk at three mesh resolutions"}


func _continuous_edge_root_scan(snapshot:Dictionary,a:Vector3,b:Vector3,divisions:int)->Dictionary:
	var roots:Array[Dictionary]=[]
	var previous_t:float=0.0
	var previous:float=TransitionB.sample_canonical(SEED,a,snapshot)
	var values:PackedFloat64Array=PackedFloat64Array()
	values.append(absf(previous))
	var minimum_abs:float=absf(previous)
	var minimum_t:float=0.0
	for i in range(1,divisions+1):
		var t:float=float(i)/float(divisions)
		var current:float=TransitionB.sample_canonical(SEED,a.lerp(b,t),snapshot)
		values.append(absf(current))
		if absf(current)<minimum_abs:
			minimum_abs=absf(current)
			minimum_t=t
		if (previous>=0.0)!=(current>=0.0):
			var root_t:float=_continuous_edge_bisect(snapshot,a,b,previous_t,t,previous>=0.0)
			var root_point:Vector3=a.lerp(b,root_t)
			var branch:Dictionary=_ordered_branch_at(root_point,snapshot)
			roots.append({"t":root_t,"world":root_point,"density":TransitionB.sample_canonical(SEED,root_point,snapshot),
				"active_branch":branch.get("winner","?"),
				"bracket_t":[previous_t,t],"endpoint_signs":[previous>=0.0,current>=0.0]})
		previous_t=t
		previous=current
	var extrema:Array[Dictionary]=[]
	for i in range(1,values.size()-1):
		if values[i]<=values[i-1] and values[i]<=values[i+1] and values[i]<0.0001:
			extrema.append({"t":float(i)/float(divisions),"absolute_density":values[i],"classification":"near_zero_extremum_candidate_only_not_proven_tangent"})
	return {"division_count":divisions,"sign_change_root_count":roots.size(),"roots":roots,
		"minimum_absolute_sample_density":minimum_abs,"minimum_absolute_sample_t":minimum_t,
		"near_zero_local_extrema_candidates":extrema,"tangency_completeness":"not proven by finite scan"}


func _piecewise_edge_roots(snapshot: Dictionary, a: Vector3, b: Vector3, subdivisions: int) -> Array[Dictionary]:
	var roots: Array[Dictionary] = []
	var previous_t: float = 0.0
	var previous: float = _sample_f32_canonical(a, snapshot)
	for i in range(1, subdivisions + 1):
		var t: float = float(i) / float(subdivisions)
		var current: float = _sample_f32_canonical(a.lerp(b,t), snapshot)
		if (previous >= 0.0) != (current >= 0.0):
			var denom: float = previous - current
			var local: float = 0.5 if is_zero_approx(denom) else previous / denom
			var root_t: float = lerpf(previous_t,t,clampf(local,0.0,1.0))
			var continuous_root: float = _continuous_edge_bisect(snapshot,a,b,previous_t,t,previous>=0.0)
			var branch_before: Dictionary = _ordered_branch_at(a.lerp(b,previous_t),snapshot)
			var branch_after: Dictionary = _ordered_branch_at(a.lerp(b,t),snapshot)
			roots.append({"piecewise_linear_t": root_t,"piecewise_world":a.lerp(b,root_t),
				"continuous_bisected_t":continuous_root,"continuous_world":a.lerp(b,continuous_root),
				"distance_world":a.distance_to(b)*absf(root_t-continuous_root),
				"endpoint_signs":[previous>=0.0,current>=0.0],
				"ordered_active_branches":[branch_before.get("winner","?"),branch_after.get("winner","?")]})
		previous_t=t
		previous=current
	return roots


func _continuous_edge_bisect(snapshot: Dictionary,a:Vector3,b:Vector3,low_in:float,high_in:float,low_positive:bool)->float:
	var low:float=low_in
	var high:float=high_in
	for _i in range(42):
		var middle:float=(low+high)*0.5
		var density:float=TransitionB.sample_canonical(SEED,a.lerp(b,middle),snapshot)
		if (density>=0.0)==low_positive: low=middle
		else: high=middle
	return (low+high)*0.5


func _sample_f32_canonical(point:Vector3,snapshot:Dictionary)->float:
	var packed:PackedFloat32Array=PackedFloat32Array()
	packed.append(TransitionB.sample_canonical(SEED,point,snapshot))
	return float(packed[0])


func _summary_b(values:PackedFloat64Array)->Dictionary:
	if values.is_empty():return {"count":0,"p50":-1.0,"p95":-1.0,"maximum":-1.0}
	var sorted:Array[float]=[]
	for value in values:sorted.append(float(value))
	sorted.sort()
	return {"count":sorted.size(),"p50":sorted[int(floor(float(sorted.size()-1)*0.5))],
		"p95":sorted[int(ceil(float(sorted.size())*0.95))-1],"maximum":sorted.back()}


func _point_key_b(point:Vector3)->String:
	return "%d,%d,%d"%[roundi(point.x*100000.0),roundi(point.y*100000.0),roundi(point.z*100000.0)]


func _edge_key_b(a:String,b:String)->String:
	return a+"|"+b if a<b else b+"|"+a


func _f32_hex(value:float)->String:
	var packed:PackedFloat32Array=PackedFloat32Array()
	packed.append(value)
	var bytes:PackedByteArray=packed.to_byte_array()
	return bytes.hex_encode()


func _check_b(condition:bool,label:String)->void:
	_b_assertions+=1
	if not condition:_b_failures.append(label)
	print("R83B_ASSERT "+JSON.stringify({"name":label,"passed":condition}))


func _emit_b(name:String,record:Dictionary)->void:
	var serialized:String=JSON.stringify(record)+"\n"
	if not _b_evidence_dir.is_empty():
		var path:String=_b_evidence_dir+"\\"+name+".json"
		var file:FileAccess=FileAccess.open(path,FileAccess.WRITE)
		if file==null:
			_b_failures.append("evidence_write_failed:%s"%name)
		else:
			file.store_string(serialized)
			file.flush()
			file.close()
	print("R83B_"+name.to_upper()+" "+serialized.strip_edges())


func _finish_b(status:String,reason:String)->void:
	var result:Dictionary={"status":status,"reason":reason,"assertions":_b_assertions,"failures":_b_failures,
		"duration_usec":Time.get_ticks_usec()-_b_started_usec,"source_baseline":"4f08b67522507bd196a74a1089c773f272235343"}
	print("R83B_RESULT "+JSON.stringify(result))
	quit(0 if status=="DIAGNOSTIC_COMPLETE" and _b_failures.is_empty() else 1)
