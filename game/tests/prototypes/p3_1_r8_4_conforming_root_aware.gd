extends "res://tests/prototypes/p3_1_r8_2_geometry_provenance.gd"

## R8.4 test-only integrated investigation. All field samples use the immutable
## R8.2 canonical SDF helpers; no production scene, save, or terrain state runs.
const R84_R82_SCRIPT_SHA := "bf822392035825f8b825162a2111508ea62325635e8b536046cb39ece69f6795"
const R84_SEED := 131102026
const R84_TARGET_CELL := Vector3i.ZERO
const R84_CELL_LATTICE_ORIGIN := Vector3i(30, 4, 14)
const R84_MAX_RINGS := 4
const R84_MAX_NODES := 10000
const R84_MAX_TRIANGLES := 20000
const R84_MAX_USEC := 600000000
const R84_ROOT_INTERVALS := 4096
const R84_DEGENERACY_CROSS_SQUARED := 1.0e-12
const R84_FACE_OFFSETS: Array[Vector3i] = [
	Vector3i.LEFT, Vector3i.RIGHT, Vector3i.DOWN,
	Vector3i.UP, Vector3i(0, 0, -1), Vector3i(0, 0, 1)
]

var _r84_started_usec: int = 0
var _r84_evidence_dir: String = ""
var _r84_phase_records: Array[Dictionary] = []
var _r84_assertions: int = 0
var _r84_failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_r84")


func _run_r84() -> void:
	_r84_started_usec = Time.get_ticks_usec()
	_r84_evidence_dir = OS.get_environment("P31_R84_EVIDENCE_DIR")
	_r8_evidence_dir = _r84_evidence_dir
	var preflight: Dictionary = _r8_preflight()
	var r82_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r8_2_geometry_provenance.gd")
	var r82_sha: String = _sha256(r82_bytes)
	var provenance: Dictionary = {
		"valid": bool(preflight.get("valid", false)) and r82_sha == R84_R82_SCRIPT_SHA,
		"r82_preflight": preflight,
		"r82_script_sha256": r82_sha,
		"r82_script_expected_sha256": R84_R82_SCRIPT_SHA,
		"r82_script_pin_match": r82_sha == R84_R82_SCRIPT_SHA,
		"godot": Engine.get_version_info(),
		"godot_precision_metadata": Engine.get_version_info().get("precision", "not_reported_by_engine"),
		"experiment_source_contract": "R8.2 common baseline only; R8.3 implementations are not loaded"
	}
	_r84_emit("source_and_frozen_input_preflight", provenance)
	_r84_check(bool(provenance.get("valid", false)), "pinned_source_and_frozen_inputs")
	if not bool(provenance.valid):
		_r84_finish("BLOCKED", "source_or_frozen_input_identity_failed")
		return

	var root_oracle: Dictionary = _r84_run_root_oracle()
	_r84_emit("root_oracle", root_oracle)
	_r84_check(bool(root_oracle.get("valid", false)), "root_oracle_complete_finite_scan")
	if not bool(root_oracle.get("valid", false)):
		_r84_finish("BLOCKED", "root_oracle_incomplete_or_nonfinite")
		return

	var seam: Dictionary = _diagnose_r81_xplus_seam()
	var seam_summary: Dictionary = _r84_summarize_xplus_reproduction(seam)
	_r84_emit("xplus_frozen_reproduction", seam_summary)
	_r84_check(bool(seam_summary.get("valid", false)), "frozen_xplus_failure_and_controls_reproduced")
	if not bool(seam_summary.get("valid", false)):
		_r84_finish("BLOCKED", "frozen_xplus_source_case_not_reproduced")
		return

	var fill_result: Dictionary = _make_snapshot("center_fill_then_wall_carve")
	if not bool(fill_result.get("valid", false)):
		_r84_finish("BLOCKED", "frozen_fill_carve_snapshot_invalid")
		return
	var candidate: Dictionary = _r84_run_refinement_closure(fill_result.snapshot)
	_r84_emit("bounded_xplus_refinement_closure", candidate)
	_r84_check(candidate.has("gate_pass") and candidate.has("topology"), "candidate_gate_emitted_topology_and_decision")
	if not bool(candidate.get("gate_pass", false)):
		_r84_finish("BLOCKED", "minimal_xplus_conforming_gate_failed_or_stop_loss_reached")
		return

	# These candidate-side gates only run if the required local closure passes.
	var controls: Dictionary = _r84_candidate_control_interfaces(fill_result.snapshot)
	_r84_emit("candidate_interface_controls", controls)
	if not bool(controls.get("valid", false)):
		_r84_finish("BLOCKED", "candidate_interface_control_failed")
		return
	# Root-aware candidate extraction is deliberately not executed until a valid
	# conforming representation exists. That dependent implementation is absent
	# from the inherited source baseline and is the next bounded step only if the
	# conforming gate passes without changing this frozen protocol.
	_r84_finish("BLOCKED", "root_aware_extractor_not_reached_without_reviewed_conforming_candidate")


func _r84_run_root_oracle() -> Dictionary:
	var ray_start: Vector3 = Vector3(0.0, 8.0, 6.0)
	var ray_end: Vector3 = ray_start + Vector3.DOWN * 12.0
	var ray_cases: Array[Dictionary] = []
	var input_digests: Dictionary = {"zero_edit": INPUT_SHA_ZERO, "cave_wall_carve": INPUT_SHA_CARVE,
		"center_fill_then_wall_carve": INPUT_SHA_FILL_CARVE}
	for scenario_name in ["zero_edit", "cave_wall_carve", "center_fill_then_wall_carve"]:
		var setup: Dictionary = _make_snapshot(String(scenario_name))
		if not bool(setup.get("valid", false)):
			return {"valid": false, "reason": "snapshot_invalid:%s" % String(scenario_name)}
		var scan: Dictionary = _r84_scan_roots("xminus_vertical_ray_%s" % String(scenario_name), ray_start, ray_end, setup.snapshot)
		if not bool(scan.get("valid", false)):
			return {"valid": false, "reason": "ray_scan_invalid:%s" % String(scenario_name), "partial": ray_cases}
		ray_cases.append({"scenario": String(scenario_name), "input_sha256": input_digests[String(scenario_name)],
			"revision": int(setup.snapshot.get("revision", -1)), "operation_count": setup.snapshot.centers.size(),
			"scan": scan})

	var triangle_edges: Array[Dictionary] = []
	var triangle_points: Array[Vector3] = [
		Vector3(8.21872806549072, 1.5, 5.5),
		Vector3(8.25, 1.5190190076828, 5.51901912689209),
		Vector3(8.25, 1.51053214073181, 5.5)
	]
	var fill_setup: Dictionary = _make_snapshot("center_fill_then_wall_carve")
	for edge_index in range(3):
		var a: Vector3 = triangle_points[edge_index]
		var b: Vector3 = triangle_points[(edge_index + 1) % 3]
		var edge_scan: Dictionary = _r84_scan_roots("triangle_3103_edge_%d" % edge_index, a, b, fill_setup.snapshot)
		if not bool(edge_scan.get("valid", false)):
			return {"valid": false, "reason": "triangle_edge_scan_invalid:%d" % edge_index, "ray_cases": ray_cases, "triangle_edges": triangle_edges}
		triangle_edges.append({"edge_index": edge_index, "a": _vec3_array(a), "a_bits": _vec3_bytes(a),
			"b": _vec3_array(b), "b_bits": _vec3_bytes(b), "scan": edge_scan})
	return {"valid": ray_cases.size() == 3 and triangle_edges.size() == 3,
		"method": "4096_uniform_intervals_sign-change_scan_plus_48-step_bisection_and_unthresholded_abs_local_minima",
		"root_completeness": "NOT_CERTIFIED; finite scan cannot exclude tangent, narrow, or branch-corner roots",
		"canonical_field": "R8.2 Transition.sample_canonical; ordered snapshot preserved",
		"ray_cases": ray_cases, "triangle_3103_source_edges": triangle_edges,
		"elapsed_usec": Time.get_ticks_usec() - _r84_started_usec}


func _r84_scan_roots(label: String, a: Vector3, b: Vector3, snapshot: Dictionary) -> Dictionary:
	var densities: PackedFloat64Array = PackedFloat64Array()
	var points: Array[Vector3] = []
	var rows: Array[Dictionary] = []
	var branches: Array[String] = []
	densities.resize(R84_ROOT_INTERVALS + 1)
	var branch_changes: Array[Dictionary] = []
	for i in range(R84_ROOT_INTERVALS + 1):
		var t: float = float(i) / float(R84_ROOT_INTERVALS)
		var p: Vector3 = a.lerp(b, t)
		var density: float = T.sample_canonical(R84_SEED, p, snapshot)
		if not is_finite(density):
			return {"valid": false, "reason": "nonfinite_canonical_density", "sample_index": i}
		var trace: Dictionary = _field_trace(p, snapshot)
		if not bool(trace.get("matches_canonical", false)):
			return {"valid": false, "reason": "branch_trace_differs_from_canonical", "sample_index": i}
		var branch: String = _branch(trace)
		if i > 0 and branch != branches[i - 1]:
			branch_changes.append({"sample_index": i, "t": t, "world": _vec3_array(p),
				"previous_branch": branches[i - 1], "branch": branch, "density": density})
		densities[i] = density
		points.append(p)
		branches.append(branch)
		rows.append({"sample_index": i, "t": t, "world": _vec3_array(p), "world_bits": _vec3_bytes(p),
			"density": density, "density_f32_bytes": _float32_bytes(density), "branch": branch})

	var roots: Array[Dictionary] = []
	for i in range(R84_ROOT_INTERVALS):
		var da: float = densities[i]
		var db: float = densities[i + 1]
		if da == 0.0:
			roots.append(_r84_exact_root_record(i, points[i], float(i) / float(R84_ROOT_INTERVALS), da, branches[i]))
		elif (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			var root: Dictionary = _r84_bisect_root(i, a, b, snapshot, da, db, points[i], points[i + 1], branches[i], branches[i + 1])
			if not bool(root.get("valid", false)):
				return {"valid": false, "reason": "bisection_root_invalid", "sample_index": i, "root": root}
			roots.append(root)
	if densities[R84_ROOT_INTERVALS] == 0.0:
		roots.append(_r84_exact_root_record(R84_ROOT_INTERVALS, points[R84_ROOT_INTERVALS], 1.0,
			densities[R84_ROOT_INTERVALS], branches[R84_ROOT_INTERVALS]))

	var extrema: Array[Dictionary] = []
	for i in range(1, R84_ROOT_INTERVALS):
		var before: float = absf(densities[i - 1])
		var current: float = absf(densities[i])
		var after: float = absf(densities[i + 1])
		if current <= before and current <= after and (current < before or current < after):
			extrema.append({"sample_index": i, "t_interval": [float(i - 1) / R84_ROOT_INTERVALS,
				float(i + 1) / R84_ROOT_INTERVALS], "world": _vec3_array(points[i]),
			"density": densities[i], "abs_density": current,
			"classification": "possible_tangent_or_near_miss_not_certified"})
	return {"valid": rows.size() == R84_ROOT_INTERVALS + 1,
		"label": label, "interval_count": R84_ROOT_INTERVALS, "sample_count": rows.size(),
		"segment_world_length": a.distance_to(b), "start": _vec3_array(a), "end": _vec3_array(b),
		"start_bits": _vec3_bytes(a), "end_bits": _vec3_bytes(b),
		"samples": rows, "sign_change_or_exact_roots": roots,
		"detected_root_count": roots.size(), "possible_tangent_candidates": extrema,
		"branch_transition_count": branch_changes.size(), "branch_transitions": branch_changes,
		"root_uncertainty_note": "Root positions are bounded by recorded sign bracket and Vector3 input quantization; tangent/narrow-root completeness unknown."}


func _r84_exact_root_record(index: int, p: Vector3, t: float, density: float, branch: String) -> Dictionary:
	return {"kind": "exact_zero_scan_sample", "index": index, "t": t,
		"world": _vec3_array(p), "world_bits": _vec3_bytes(p), "density": density,
		"bracket_width_world": 0.0, "branch": branch}


func _r84_bisect_root(
	index: int, a: Vector3, b: Vector3, snapshot: Dictionary,
	da: float, db: float, pa: Vector3, pb: Vector3,
	branch_a: String, branch_b: String
) -> Dictionary:
	var low: float = float(index) / float(R84_ROOT_INTERVALS)
	var high: float = float(index + 1) / float(R84_ROOT_INTERVALS)
	var low_density: float = da
	var low_point: Vector3 = pa
	var high_point: Vector3 = pb
	var iterations: int = 0
	for step in range(48):
		var middle: float = (low + high) * 0.5
		if middle == low or middle == high:
			break
		var middle_point: Vector3 = a.lerp(b, middle)
		if middle_point == low_point or middle_point == high_point:
			break
		var middle_density: float = T.sample_canonical(R84_SEED, middle_point, snapshot)
		if not is_finite(middle_density):
			return {"valid": false, "reason": "nonfinite_bisection_density"}
		var middle_trace: Dictionary = _field_trace(middle_point, snapshot)
		if not bool(middle_trace.get("matches_canonical", false)):
			return {"valid": false, "reason": "bisection_branch_trace_mismatch"}
		iterations += 1
		if (low_density < 0.0 and middle_density < 0.0) or (low_density > 0.0 and middle_density > 0.0):
			low = middle
			low_density = middle_density
			low_point = middle_point
		else:
			high = middle
			high_point = middle_point
	var t: float = (low + high) * 0.5
	var root_point: Vector3 = a.lerp(b, t)
	var root_density: float = T.sample_canonical(R84_SEED, root_point, snapshot)
	var root_trace: Dictionary = _field_trace(root_point, snapshot)
	return {"kind": "sign_change_bisection", "index": index, "initial_interval": [float(index) / R84_ROOT_INTERVALS,
		float(index + 1) / R84_ROOT_INTERVALS], "final_t_interval": [low, high],
		"bracket_width_world": low_point.distance_to(high_point), "iterations": iterations,
		"low_world": _vec3_array(low_point), "low_bits": _vec3_bytes(low_point), "low_density": low_density,
		"high_world": _vec3_array(high_point), "high_bits": _vec3_bytes(high_point), "high_density": T.sample_canonical(R84_SEED, high_point, snapshot),
		"root_world": _vec3_array(root_point), "root_bits": _vec3_bytes(root_point), "root_density": root_density,
		"branch_a": branch_a, "branch_b": branch_b, "branch_root": _branch(root_trace),
		"root_branch_trace_matches": bool(root_trace.get("matches_canonical", false)),
		"valid": is_finite(root_density) and bool(root_trace.get("matches_canonical", false))}


func _r84_summarize_xplus_reproduction(seam: Dictionary) -> Dictionary:
	if not bool(seam.get("valid", false)):
		return {"valid": false, "reason": seam.get("reason", "xplus_diagnostic_invalid")}
	var rows: Array[Dictionary] = []
	var failing_reproduced: bool = false
	var same_lod_reproduced: bool = false
	var mirrored_pass_control: bool = false
	for case_value in seam.cases:
		var c: Dictionary = case_value
		var lod_a: int = int(c.lod_a_negative_side)
		var lod_b: int = int(c.lod_b_positive_side)
		var compare: Dictionary = c.r8_contour_oracle
		var row: Dictionary = {"lod_pair_negative_positive": [lod_a, lod_b],
			"segments": [int(c.a_contour_with_triangle_sources.segment_count), int(c.b_contour_with_triangle_sources.segment_count)],
			"unmatched": [c.unmatched_segments_from_a.size(), c.unmatched_segments_from_b.size()],
			"shared_scalar_samples": c.shared_scalar_samples,
			"contour_match": bool(compare.get("contour_segments_match", false)),
			"a_mesh_sha256": c.a_mesh_sha256, "b_mesh_sha256": c.b_mesh_sha256}
		rows.append(row)
		if lod_a == 1 and lod_b == 0:
			failing_reproduced = row.segments == [33, 35] and row.unmatched == [0, 2] \
				and int(c.shared_scalar_samples.get("sample_count", 0)) == 533 \
				and int(c.shared_scalar_samples.get("non_bitwise_equal_count", -1)) == 0
		if lod_a == 1 and lod_b == 1:
			same_lod_reproduced = row.segments == [33, 35] and row.unmatched == [0, 2]
		if lod_a == 0 and lod_b == 1:
			mirrored_pass_control = bool(row.contour_match) and row.segments == [35, 35]
	return {"valid": failing_reproduced and same_lod_reproduced and mirrored_pass_control,
		"xplus_world_plane": 16.0, "expected_frozen_input_sha256": INPUT_SHA_FILL_CARVE,
		"case_rows": rows, "failing_lod1_lod0_reproduced": failing_reproduced,
		"lod1_lod1_reference_reproduced": same_lod_reproduced,
		"mirrored_lod0_lod1_control_passed": mirrored_pass_control,
		"existing_cutoff": R84_DEGENERACY_CROSS_SQUARED,
		"source": "R8.2 common-baseline actual chunk builders and independent plane-contour oracle"}


func _r84_run_refinement_closure(snapshot: Dictionary) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var fine_cells: Dictionary = {R84_TARGET_CELL: true}
	var ring_by_cell: Dictionary = {R84_TARGET_CELL: 0}
	var queue: Array[Vector3i] = [R84_TARGET_CELL]
	var fine_meshes: Dictionary = {}
	var coarse_meshes: Dictionary = {}
	var native_lod0_meshes: Dictionary = {}
	var compared_state_pairs: Dictionary = {}
	var final_interface_rows: Dictionary = {}
	var sample_nodes: Dictionary = {}
	var promotion_rows: Array[Dictionary] = []
	var blocked_frontier: Array[Dictionary] = []
	var initial_neighbor: Vector3i = Vector3i.RIGHT
	var native_result: Dictionary = _r84_build_cell_mesh(initial_neighbor, 0, snapshot)
	if not bool(native_result.get("valid", false)):
		return {"gate_pass": false, "reason": "native_lod0_neighbor_build_failed"}
	native_lod0_meshes[initial_neighbor] = native_result
	_r84_add_sample_lattice_nodes(sample_nodes, initial_neighbor, 0)
	var peak_resident_triangles: int = _r84_resident_triangle_count(fine_meshes, coarse_meshes, native_lod0_meshes)
	if sample_nodes.size() > R84_MAX_NODES or peak_resident_triangles > R84_MAX_TRIANGLES:
		return {"gate_pass": false, "reason": "initial_fixture_resource_stop_loss",
			"unique_sample_lattice_nodes": sample_nodes.size(), "peak_resident_triangles": peak_resident_triangles}
	var cursor: int = 0
	var stop_reason: String = "closure_empty"
	var stopped_early: bool = false
	var stop_loss_triggered: bool = false
	while cursor < queue.size():
		if Time.get_ticks_usec() - started > R84_MAX_USEC:
			stop_reason = "focused_candidate_wall_clock_limit"
			stopped_early = true
			stop_loss_triggered = true
			break
		var current: Vector3i = queue[cursor]
		cursor += 1
		if not fine_meshes.has(current):
			var fine_result: Dictionary = _r84_build_cell_mesh(current, 0, snapshot)
			if not bool(fine_result.get("valid", false)):
				return _r84_candidate_failure("fine_cell_build_failed", current, fine_result, started, sample_nodes, promotion_rows, final_interface_rows)
			fine_meshes[current] = fine_result
			_r84_add_sample_lattice_nodes(sample_nodes, current, 0)
			peak_resident_triangles = maxi(peak_resident_triangles,
				_r84_resident_triangle_count(fine_meshes, coarse_meshes, native_lod0_meshes))
		var current_fine: Dictionary = fine_meshes[current]
		for offset_value in R84_FACE_OFFSETS:
			var offset: Vector3i = offset_value
			var neighbor: Vector3i = current + offset
			var native_neighbor: bool = _r84_is_native_lod0_cell(neighbor)
			var neighbor_is_fine: bool = fine_cells.has(neighbor) or native_neighbor
			var neighbor_lod: int = 0 if neighbor_is_fine else 1
			var status_key: String = _r84_state_pair_key(current, neighbor, true, neighbor_is_fine)
			if compared_state_pairs.has(status_key):
				continue
			compared_state_pairs[status_key] = true
			var neighbor_mesh: Dictionary = {}
			if native_neighbor:
				if not native_lod0_meshes.has(neighbor):
					var native_mesh: Dictionary = _r84_build_cell_mesh(neighbor, 0, snapshot)
					if not bool(native_mesh.get("valid", false)):
						return _r84_candidate_failure("native_lod0_cell_build_failed", neighbor, native_mesh, started, sample_nodes, promotion_rows, final_interface_rows)
					native_lod0_meshes[neighbor] = native_mesh
					_r84_add_sample_lattice_nodes(sample_nodes, neighbor, 0)
					peak_resident_triangles = maxi(peak_resident_triangles,
						_r84_resident_triangle_count(fine_meshes, coarse_meshes, native_lod0_meshes))
				neighbor_mesh = native_lod0_meshes[neighbor]
			elif neighbor_is_fine:
				if not fine_meshes.has(neighbor):
					var fine_neighbor: Dictionary = _r84_build_cell_mesh(neighbor, 0, snapshot)
					if not bool(fine_neighbor.get("valid", false)):
						return _r84_candidate_failure("adjacent_fine_cell_build_failed", neighbor, fine_neighbor, started, sample_nodes, promotion_rows, final_interface_rows)
					fine_meshes[neighbor] = fine_neighbor
					_r84_add_sample_lattice_nodes(sample_nodes, neighbor, 0)
					peak_resident_triangles = maxi(peak_resident_triangles,
						_r84_resident_triangle_count(fine_meshes, coarse_meshes, native_lod0_meshes))
				neighbor_mesh = fine_meshes[neighbor]
			else:
				if not coarse_meshes.has(neighbor):
					var coarse_result: Dictionary = _r84_build_cell_mesh(neighbor, 1, snapshot)
					if not bool(coarse_result.get("valid", false)):
						return _r84_candidate_failure("coarse_reference_cell_build_failed", neighbor, coarse_result, started, sample_nodes, promotion_rows, final_interface_rows)
					coarse_meshes[neighbor] = coarse_result
					_r84_add_sample_lattice_nodes(sample_nodes, neighbor, 1)
					peak_resident_triangles = maxi(peak_resident_triangles,
						_r84_resident_triangle_count(fine_meshes, coarse_meshes, native_lod0_meshes))
					if sample_nodes.size() > R84_MAX_NODES or peak_resident_triangles > R84_MAX_TRIANGLES:
						stop_reason = "unique_sample_node_stop_loss"
						if peak_resident_triangles > R84_MAX_TRIANGLES:
							stop_reason = "emitted_triangle_stop_loss"
						stopped_early = true
						stop_loss_triggered = true
						break
				neighbor_mesh = coarse_meshes[neighbor]
			var face: int = _r84_face_axis(offset)
			var plane: float = _r84_shared_plane(current, offset)
			var contour_a: Dictionary = _contour_with_sources(current_fine.vertices, face, plane)
			var contour_b: Dictionary = _contour_with_sources(neighbor_mesh.vertices, face, plane)
			var comparison: Dictionary = _r84_compare_contour_segments(contour_a, contour_b)
			var pair_key: String = _r84_cell_pair_key(current, neighbor)
			var row: Dictionary = {"pair": pair_key, "cell_a": _vec3i_array(current), "cell_b": _vec3i_array(neighbor),
				"lod_a": 0, "lod_b": neighbor_lod, "axis": face, "plane_world": plane,
				"contour_counts": [contour_a.segment_count, contour_b.segment_count],
				"unmatched_a": comparison.unmatched_a, "unmatched_b": comparison.unmatched_b,
				"match": bool(comparison.match), "native_lod0_contact": native_neighbor}
			final_interface_rows[pair_key] = row
			if not bool(comparison.match) and neighbor_is_fine:
				stop_reason = "already_fine_interface_mismatch"
				stopped_early = true
				break
			if not bool(comparison.match) and not neighbor_is_fine:
				var next_ring: int = int(ring_by_cell.get(current, 0)) + 1
				if next_ring > R84_MAX_RINGS:
					blocked_frontier.append(row.merged({"required_ring": next_ring}, true))
					stop_reason = "four_ring_propagation_stop_loss"
					stopped_early = true
					stop_loss_triggered = true
					break
				fine_cells[neighbor] = true
				ring_by_cell[neighbor] = next_ring
				coarse_meshes.erase(neighbor)
				promotion_rows.append({"cell": _vec3i_array(neighbor), "ring": next_ring,
					"cause_pair": pair_key, "unmatched_a": comparison.unmatched_a.size(),
					"unmatched_b": comparison.unmatched_b.size()})
				queue.append(neighbor)
				_r84_append_progress(promotion_rows.size(), {"event": "cell_promoted", "cell": _vec3i_array(neighbor),
					"ring": next_ring, "unique_sample_nodes": sample_nodes.size(),
					"active_triangles": _r84_active_triangle_count(fine_meshes),
					"elapsed_usec": Time.get_ticks_usec() - started})
			var resident_triangles: int = _r84_resident_triangle_count(fine_meshes, coarse_meshes, native_lod0_meshes)
			peak_resident_triangles = maxi(peak_resident_triangles, resident_triangles)
			if resident_triangles > R84_MAX_TRIANGLES:
				stop_reason = "emitted_triangle_stop_loss"
				stopped_early = true
				stop_loss_triggered = true
				break
			if sample_nodes.size() > R84_MAX_NODES:
				stop_reason = "unique_sample_node_stop_loss"
				stopped_early = true
				stop_loss_triggered = true
				break
		if Time.get_ticks_usec() - started > R84_MAX_USEC:
			stop_reason = "focused_candidate_wall_clock_limit"
			stopped_early = true
			stop_loss_triggered = true
			break
		if stopped_early:
			break

	var interfaces: Array[Dictionary] = []
	var unmatched_count: int = 0
	for pair_key in final_interface_rows:
		var item: Dictionary = final_interface_rows[pair_key]
		interfaces.append(item)
		if not bool(item.match):
			unmatched_count += 1
	var topology: Dictionary = _r84_mesh_topology(fine_meshes)
	var triangle_count: int = _r84_active_triangle_count(fine_meshes)
	var runtime: int = Time.get_ticks_usec() - started
	var closure_complete: bool = cursor >= queue.size() and not stopped_early
	var target_xplus: Dictionary = final_interface_rows.get(_r84_cell_pair_key(R84_TARGET_CELL, initial_neighbor), {})
	var gate_pass: bool = closure_complete and unmatched_count == 0 \
		and int(topology.get("internal_open_edges", -1)) == 0 \
		and int(topology.get("nonmanifold_edges", -1)) == 0 \
		and int(topology.get("degenerate_triangles", -1)) == 0 \
		and int(topology.get("winding_opposed", -1)) == 0 \
		and peak_resident_triangles <= R84_MAX_TRIANGLES and sample_nodes.size() <= R84_MAX_NODES \
		and runtime <= R84_MAX_USEC
	return {"gate_pass": gate_pass, "candidate": "canonical_cell_refinement_closure",
		"closure_complete": closure_complete, "stop_reason": stop_reason,
		"stop_loss_triggered": stop_loss_triggered,
		"seed_cell": _vec3i_array(R84_TARGET_CELL), "native_lod0_neighbor_cell": _vec3i_array(initial_neighbor),
		"maximum_propagation_rings": R84_MAX_RINGS, "observed_max_ring": _r84_max_ring(ring_by_cell),
		"promoted_cell_count": promotion_rows.size(), "promotions": promotion_rows,
		"blocked_frontier": blocked_frontier, "fine_cell_count": fine_cells.size(),
		"unique_sample_lattice_nodes": sample_nodes.size(), "emitted_fine_roi_triangles": triangle_count,
		"peak_resident_reference_and_candidate_triangles": peak_resident_triangles,
		"mesh_attribute_bytes_estimate": _r84_all_mesh_attribute_bytes(fine_meshes, coarse_meshes, native_lod0_meshes),
		"candidate_runtime_usec": runtime, "resource_budgets": {"nodes": R84_MAX_NODES,
			"triangles": R84_MAX_TRIANGLES, "wall_usec": R84_MAX_USEC, "rings": R84_MAX_RINGS},
		"xplus_target_contact": target_xplus, "final_interface_count": interfaces.size(),
		"final_unmatched_interface_count": unmatched_count, "final_interfaces": interfaces,
		"topology": topology,
		"decision": "candidate advances only if closure terminates, every interface matches, and all mandatory local topology/resource checks pass"}


func _r84_candidate_failure(reason: String, cell: Vector3i, build: Dictionary, started: int,
	sample_nodes: Dictionary, promotions: Array[Dictionary], interfaces: Dictionary) -> Dictionary:
	return {"gate_pass": false, "reason": reason, "failed_cell": _vec3i_array(cell),
		"build_result": {"valid": build.get("valid", false), "reason": build.get("reason", "unknown")},
		"unique_sample_lattice_nodes": sample_nodes.size(), "promotions": promotions,
		"interface_rows": interfaces.values(), "candidate_runtime_usec": Time.get_ticks_usec() - started}


func _r84_build_cell_mesh(cell: Vector3i, lod: int, snapshot: Dictionary) -> Dictionary:
	var lattice: Vector3i = R84_CELL_LATTICE_ORIGIN + cell * 2
	var began: int = Time.get_ticks_usec()
	var result: Dictionary = T.build_uniform_reference_cell(R84_SEED, lattice, lod, snapshot)
	result["elapsed_usec"] = Time.get_ticks_usec() - began
	return result


func _r84_add_sample_lattice_nodes(nodes: Dictionary, cell: Vector3i, lod: int) -> void:
	var cell_base: Vector3i = cell * 2
	var step: int = 2 if lod == 1 else 1
	var extent: int = 2 if lod == 0 else 1
	for y in range(extent + 1):
		for z in range(extent + 1):
			for x in range(extent + 1):
				var key: Vector3i = R84_CELL_LATTICE_ORIGIN + cell_base + Vector3i(x, y, z) * step
				nodes[key] = true


func _r84_compare_contour_segments(a: Dictionary, b: Dictionary) -> Dictionary:
	var keys_a: Dictionary = {}
	var keys_b: Dictionary = {}
	for segment in a.get("segments", []):
		keys_a[String(segment.get("key_1e_minus_5", ""))] = true
	for segment in b.get("segments", []):
		keys_b[String(segment.get("key_1e_minus_5", ""))] = true
	var unmatched_a: Array[String] = []
	var unmatched_b: Array[String] = []
	for key in keys_a:
		if not keys_b.has(key):
			unmatched_a.append(String(key))
	for key in keys_b:
		if not keys_a.has(key):
			unmatched_b.append(String(key))
	return {"match": unmatched_a.is_empty() and unmatched_b.is_empty(),
		"unmatched_a": unmatched_a, "unmatched_b": unmatched_b}


func _r84_face_axis(offset: Vector3i) -> int:
	if offset.x != 0:
		return 0
	if offset.y != 0:
		return 1
	return 2


func _r84_is_native_lod0_cell(cell: Vector3i) -> bool:
	return cell.x >= 1 and cell.x < 5 and cell.y >= -4 and cell.y < 6 \
		and cell.z >= -1 and cell.z < 2


func _r84_shared_plane(cell: Vector3i, offset: Vector3i) -> float:
	var base_world: Vector3 = Vector3(R84_CELL_LATTICE_ORIGIN) * 0.5
	var origin: Vector3 = base_world + Vector3(cell)
	var axis: int = _r84_face_axis(offset)
	return origin[axis] + (1.0 if offset[axis] > 0 else 0.0)


func _r84_cell_pair_key(a: Vector3i, b: Vector3i) -> String:
	var a_text: String = "%d,%d,%d" % [a.x, a.y, a.z]
	var b_text: String = "%d,%d,%d" % [b.x, b.y, b.z]
	return a_text + "|" + b_text if a_text < b_text else b_text + "|" + a_text


func _r84_state_pair_key(a: Vector3i, b: Vector3i, a_fine: bool, b_fine: bool) -> String:
	var a_text: String = "%d,%d,%d:%s" % [a.x, a.y, a.z, "F" if a_fine else "C"]
	var b_text: String = "%d,%d,%d:%s" % [b.x, b.y, b.z, "F" if b_fine else "C"]
	return a_text + "|" + b_text if a_text < b_text else b_text + "|" + a_text


func _r84_active_triangle_count(meshes: Dictionary) -> int:
	var total: int = 0
	for key in meshes:
		total += int(meshes[key].get("triangle_count", 0))
	return total


func _r84_resident_triangle_count(fine: Dictionary, coarse: Dictionary, native: Dictionary) -> int:
	return _r84_active_triangle_count(fine) + _r84_active_triangle_count(coarse) + _r84_active_triangle_count(native)


func _r84_mesh_attribute_bytes(meshes: Dictionary) -> int:
	var total: int = 0
	for key in meshes:
		var result: Dictionary = meshes[key]
		var positions: PackedVector3Array = result.get("vertices", PackedVector3Array())
		total += positions.size() * 24
	return total


func _r84_all_mesh_attribute_bytes(fine: Dictionary, coarse: Dictionary, native: Dictionary) -> int:
	return _r84_mesh_attribute_bytes(fine) + _r84_mesh_attribute_bytes(coarse) + _r84_mesh_attribute_bytes(native)


func _r84_max_ring(rings: Dictionary) -> int:
	var maximum: int = 0
	for key in rings:
		maximum = maxi(maximum, int(rings[key]))
	return maximum


func _r84_mesh_topology(meshes: Dictionary) -> Dictionary:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var cell_coords: Array[Vector3i] = []
	for key in meshes:
		var result: Dictionary = meshes[key]
		vertices.append_array(result.get("vertices", PackedVector3Array()))
		normals.append_array(result.get("normals", PackedVector3Array()))
		cell_coords.append(key)
	if vertices.is_empty() or vertices.size() != normals.size():
		return {"valid": false, "reason": "empty_or_mismatched_mesh_arrays"}
	var min_world: Vector3 = Vector3(INF, INF, INF)
	var max_world: Vector3 = Vector3(-INF, -INF, -INF)
	for cell in cell_coords:
		var base: Vector3 = Vector3(R84_CELL_LATTICE_ORIGIN) * 0.5 + Vector3(cell)
		min_world = min_world.min(base)
		max_world = max_world.max(base + Vector3.ONE)
	var incidence: Dictionary = {}
	var edge_points: Dictionary = {}
	var degenerate: int = 0
	var nonfinite: int = 0
	var winding_opposed: int = 0
	var winding_neutral: int = 0
	for i in range(0, vertices.size(), 3):
		var a: Vector3 = vertices[i]
		var b: Vector3 = vertices[i + 1]
		var c: Vector3 = vertices[i + 2]
		if not a.is_finite() or not b.is_finite() or not c.is_finite():
			nonfinite += 1
			continue
		var cross: Vector3 = (b - a).cross(c - a)
		if not cross.is_finite():
			nonfinite += 1
			continue
		if cross.length_squared() <= R84_DEGENERACY_CROSS_SQUARED:
			degenerate += 1
		var centroid: Vector3 = (a + b + c) / 3.0
		var outward: Vector3 = -_r8_gradient(centroid, _r8_fill_snapshot)
		var dot_value: float = cross.dot(outward)
		if dot_value < 0.0:
			winding_opposed += 1
		elif dot_value == 0.0:
			winding_neutral += 1
		for edge in [[a, b], [b, c], [c, a]]:
			var p0: Vector3 = edge[0]
			var p1: Vector3 = edge[1]
			var key0: String = _r8_point_key(p0)
			var key1: String = _r8_point_key(p1)
			var edge_key: String = _r8_edge_key(key0, key1)
			incidence[edge_key] = int(incidence.get(edge_key, 0)) + 1
			if not edge_points.has(edge_key):
				edge_points[edge_key] = [p0, p1]
	var internal_open: int = 0
	var crop_open: int = 0
	var nonmanifold: int = 0
	for edge_key in incidence:
		var count: int = int(incidence[edge_key])
		if count == 1:
			var endpoints: Array = edge_points[edge_key]
			var p0: Vector3 = endpoints[0]
			var p1: Vector3 = endpoints[1]
			var on_outer_plane: bool = false
			for axis in 3:
				if absf(p0[axis] - min_world[axis]) <= 0.00001 and absf(p1[axis] - min_world[axis]) <= 0.00001:
					on_outer_plane = true
				if absf(p0[axis] - max_world[axis]) <= 0.00001 and absf(p1[axis] - max_world[axis]) <= 0.00001:
					on_outer_plane = true
			if on_outer_plane:
				crop_open += 1
			else:
				internal_open += 1
		elif count > 2:
			nonmanifold += 1
	return {"valid": true, "internal_open_edges": internal_open,
		"finite_crop_open_edges": crop_open, "nonmanifold_edges": nonmanifold,
		"degenerate_triangles": degenerate, "nonfinite_triangles": nonfinite,
		"winding_opposed": winding_opposed, "winding_neutral": winding_neutral,
		"triangle_count": vertices.size() / 3, "unique_welded_edges": incidence.size(),
		"crop_bounds": [_vec3_array(min_world), _vec3_array(max_world)],
		"weld_key": "R8.2 1e-5 integer point key; diagnostic only"}


func _r84_candidate_control_interfaces(snapshot: Dictionary) -> Dictionary:
	var cases: Array[Dictionary] = []
	var specs: Array[Dictionary] = [
		{"id": "MIRRORED_LOD0_LOD1", "region_a": Vector2i(-1, 0), "chunk_a": Vector2i(3, 2),
			"region_b": Vector2i(0, 0), "chunk_b": Vector2i(0, 2), "lod_a": 0, "lod_b": 1, "axis": 0, "plane": 0.0},
		{"id": "SAME_LOD1_LOD1", "region_a": Vector2i(0, 0), "chunk_a": Vector2i(3, 2),
			"region_b": Vector2i(1, 0), "chunk_b": Vector2i(0, 2), "lod_a": 1, "lod_b": 1, "axis": 0, "plane": 16.0}
	]
	for spec in specs:
		var a: Dictionary = _build_r81_world_chunk(spec.lod_a, spec.region_a, spec.chunk_a, snapshot)
		var b: Dictionary = _build_r81_world_chunk(spec.lod_b, spec.region_b, spec.chunk_b, snapshot)
		if not bool(a.get("valid", false)) or not bool(b.get("valid", false)):
			return {"valid": false, "reason": "control_chunk_build_failed:%s" % spec.id}
		var ca: Dictionary = _contour_with_sources(a.positions, spec.axis, spec.plane)
		var cb: Dictionary = _contour_with_sources(b.positions, spec.axis, spec.plane)
		var comparison: Dictionary = _r84_compare_contour_segments(ca, cb)
		cases.append({"id": spec.id, "lod_pair": [spec.lod_a, spec.lod_b],
			"segment_counts": [ca.segment_count, cb.segment_count],
			"match": comparison.match, "unmatched_a": comparison.unmatched_a.size(),
			"unmatched_b": comparison.unmatched_b.size()})
	return {"valid": cases.size() == specs.size() and bool(cases[0].match) and bool(cases[1].match), "cases": cases,
		"note": "Candidate-side controls are only reached after the mandatory conforming closure gate passes."}


func _r84_emit(phase: String, record: Dictionary) -> void:
	var evidence_name: String = "%02d-%s.json" % [_r84_phase_records.size() + 1, phase]
	var payload: Dictionary = {"suite": "P3_1_R8_4_CONFORMING_ROOT_AWARE", "phase": phase, "record": record}
	var summary: Dictionary = _r84_stdout_summary(phase, record)
	_r84_phase_records.append({"phase": phase, "evidence_file": evidence_name, "summary": summary})
	print("P3_1_R8_4_JSON " + JSON.stringify({"suite": payload.suite, "phase": phase, "summary": summary,
		"evidence_file": evidence_name}))
	if _r84_evidence_dir.is_empty():
		return
	var file: FileAccess = FileAccess.open(_r84_evidence_dir.path_join(evidence_name), FileAccess.WRITE)
	if file == null:
		_r84_failures.append("evidence_write_failed:%s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(payload) + "\n")
	file.flush()
	file.close()


func _r84_stdout_summary(phase: String, record: Dictionary) -> Dictionary:
	if phase == "root_oracle":
		var rays: Array[Dictionary] = []
		for item in record.get("ray_cases", []):
			var scan: Dictionary = item.scan
			rays.append({"scenario": item.scenario, "input_sha256": item.input_sha256,
				"root_count": scan.detected_root_count, "tangent_candidate_count": scan.possible_tangent_candidates.size(),
				"branch_transition_count": scan.branch_transition_count})
		var edges: Array[Dictionary] = []
		for item in record.get("triangle_3103_source_edges", []):
			var scan: Dictionary = item.scan
			edges.append({"edge_index": item.edge_index, "root_count": scan.detected_root_count,
				"tangent_candidate_count": scan.possible_tangent_candidates.size(),
				"branch_transition_count": scan.branch_transition_count})
		return {"valid": record.get("valid", false), "method": record.get("method", ""),
			"root_completeness": record.get("root_completeness", ""), "rays": rays, "triangle_edges": edges,
			"elapsed_usec": record.get("elapsed_usec", -1)}
	if phase == "bounded_xplus_refinement_closure":
		return {"gate_pass": record.get("gate_pass", false), "closure_complete": record.get("closure_complete", false),
			"stop_reason": record.get("stop_reason", ""), "observed_max_ring": record.get("observed_max_ring", -1),
			"fine_cell_count": record.get("fine_cell_count", 0), "promoted_cell_count": record.get("promoted_cell_count", 0),
			"unique_sample_lattice_nodes": record.get("unique_sample_lattice_nodes", 0),
			"emitted_fine_roi_triangles": record.get("emitted_fine_roi_triangles", 0),
			"candidate_runtime_usec": record.get("candidate_runtime_usec", -1),
			"final_unmatched_interface_count": record.get("final_unmatched_interface_count", -1),
			"topology": record.get("topology", {})}
	return record


func _r84_append_progress(index: int, record: Dictionary) -> void:
	if _r84_evidence_dir.is_empty():
		return
	var file: FileAccess = FileAccess.open(_r84_evidence_dir.path_join("candidate-progress-%04d.json" % index), FileAccess.WRITE)
	if file == null:
		_r84_failures.append("candidate_progress_open_failed:" + error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(record) + "\n")
	file.flush()
	file.close()


func _r84_check(condition: bool, label: String) -> void:
	_r84_assertions += 1
	if not condition:
		_r84_failures.append(label)


func _r84_finish(status: String, reason: String) -> void:
	if not _r84_failures.is_empty():
		status = "BLOCKED"
	var final: Dictionary = {"suite": "P3_1_R8_4_CONFORMING_ROOT_AWARE", "status": status,
		"reason": reason, "assertions": _r84_assertions, "failures": _r84_failures,
		"elapsed_usec": Time.get_ticks_usec() - _r84_started_usec,
		"phase_count": _r84_phase_records.size(), "phases": _r84_phase_records,
		"production_changes": false, "production_reads": false, "save_access": false,
		"geometry_contract_adopted": false, "owner_tolerances": "NONE_APPROVED",
		"resource_limits_are_research_stop_loss": true}
	print("P3_1_R8_4_RESULT " + JSON.stringify(final))
	if not _r84_evidence_dir.is_empty():
		var path: String = _r84_evidence_dir.path_join("result.json")
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("P3_1_R8_4_RESULT_WRITE_FAIL " + error_string(FileAccess.get_open_error()))
			quit(1)
			return
		file.store_string(JSON.stringify(final) + "\n")
		file.flush()
		file.close()
	quit(0 if status == "DIAGNOSTIC_COMPLETE" else 1)
