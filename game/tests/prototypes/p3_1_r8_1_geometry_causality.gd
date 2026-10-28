extends "res://tests/prototypes/p3_1_r8_geometry_quality_diagnostic.gd"

## R8.1 narrows three R8 observations to source-traceable, test-only probes.
## It reuses pinned frozen R7.3 inputs and CPU builders; no production scene,
## persistence, user save, collision server or renderer is instantiated.

const R81_NORMAL_STEPS := [0.25, 0.125, 0.0625, 0.03125, 0.01, 0.005, 0.001, 0.0005]
const R81_WINDING_TRIANGLE := 3103
const R81_WINDING_CELL := 712

var _r81_evidence_dir := ""
var _r81_started_usec := 0
var _r81_records: Array[Dictionary] = []
var _r81_failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_r81")


func _run_r81() -> void:
	_r81_started_usec = Time.get_ticks_usec()
	_r81_evidence_dir = OS.get_environment("P31_R81_EVIDENCE_DIR")
	var preflight: Dictionary = _r8_preflight()
	_emit_r81("preflight", preflight)
	if not bool(preflight.get("valid", false)):
		_finish_r81("BLOCKED", "frozen_source_or_input_preflight_failed")
		return
	var normals: Dictionary = _diagnose_r81_normals()
	_emit_r81("normal_winding", normals)
	if not bool(normals.get("valid", false)):
		_finish_r81("BLOCKED", "normal_winding_fixture_not_reproduced")
		return
	var seam: Dictionary = _diagnose_r81_xplus_seam()
	_emit_r81("xplus_lod_seam", seam)
	if not bool(seam.get("valid", false)):
		_finish_r81("BLOCKED", "xplus_seam_fixture_not_reproduced")
		return
	var picking: Dictionary = _diagnose_r81_xminus_picker()
	_emit_r81("xminus_picker", picking)
	if not bool(picking.get("valid", false)):
		_finish_r81("BLOCKED", "xminus_picker_fixture_not_reproduced")
		return
	_finish_r81("DIAGNOSTIC_COMPLETE", "three_bounded_causes_measured_no_threshold_or_production_change")


func _diagnose_r81_normals() -> Dictionary:
	var scenario_records: Dictionary = {}
	for scenario in ["cave_wall_carve", "center_fill_then_wall_carve"]:
		var setup: Dictionary = _make_snapshot(String(scenario))
		if not bool(setup.get("valid", false)):
			return {"valid": false, "reason": "snapshot_setup_failed:%s" % scenario}
		var snapshot: Dictionary = setup.snapshot
		var fixture := Fixture.new()
		if not fixture.configure(SEED, snapshot):
			return {"valid": false, "reason": "fixture_setup_failed:%s:%s" % [scenario, fixture.last_reason]}
		if not fixture.configure_r71_polygonizer("production", "reject_only_exact_zero", "production"):
			return {"valid": false, "reason": "polygonizer_configuration_failed"}
		var built: Dictionary = fixture.build_approach("A_conforming_propagation")
		if not bool(built.get("valid", false)):
			return {"valid": false, "reason": "mesh_build_failed:%s" % scenario}
		var repaired: Dictionary = _r8_build_repaired_mesh(fixture, built)
		if not bool(repaired.get("valid", false)):
			return {"valid": false, "reason": "r73_repair_replay_failed:%s" % scenario}
		var requested_pair: Array = [528, 624] if scenario == "cave_wall_carve" else [408, 504]
		var original_pairs: Dictionary = _r8_collect_normal_pairs(fixture, built.cells, [], snapshot)
		var repaired_pairs: Dictionary = _r8_collect_normal_pairs(fixture, repaired.cells,
			repaired.get("focus_cell_ids", []), snapshot)
		if not bool(original_pairs.get("valid", false)) or not bool(repaired_pairs.get("valid", false)):
			return {"valid": false, "reason": "shared_normal_pairs_unavailable:%s" % scenario}
		var before_pair: Dictionary = _find_r81_pair(original_pairs.worst_pairs, requested_pair)
		var after_pair: Dictionary = _find_r81_pair(repaired_pairs.worst_pairs, requested_pair)
		if before_pair.is_empty() or after_pair.is_empty():
			return {"valid": false, "reason": "requested_normal_pair_missing:%s" % scenario}
		var pair_position: Vector3 = _parse_vector3(before_pair.world_position)
		var pair_normals: Array[Dictionary] = []
		for which in ["normal_a", "normal_b"]:
			var normal: Vector3 = _parse_vector3(before_pair[which])
			pair_normals.append({"source": which, "normal": _vec3_array(normal),
				"gradient_stability": _gradient_stability(pair_position, snapshot, normal)})
		var entry: Dictionary = {"scenario": scenario,
			"input_sha256": INPUT_SHA_CARVE if scenario == "cave_wall_carve" else INPUT_SHA_FILL_CARVE,
			"repair_focus_cell_ids": repaired.get("focus_cell_ids", []),
			"requested_cell_pair": requested_pair,
			"original_pair": before_pair,
			"repaired_pair": after_pair,
			"face_normals_and_canonical_gradient_stability": pair_normals,
			"original_mesh_sha256": _mesh_sha256(built.positions, built.normals),
			"repaired_mesh_sha256": _mesh_sha256(repaired.positions, repaired.normals),
			"repair_preserved_requested_pair": before_pair == after_pair,
			"surface_normal_contract": "positive density is solid; geometric outward is toward decreasing density; mesh triangles use tetra inside/outside-center orientation; mesh vertex normals are flat per triangle in this fixture"}
		if scenario == "center_fill_then_wall_carve":
			var target_original: Dictionary = _find_r81_triangle(built.positions, Vector3(8.239575, 1.509851, 5.50634))
			var target_repaired: Dictionary = _find_r81_triangle(repaired.positions, Vector3(8.239575, 1.509851, 5.50634))
			if target_original.is_empty() or target_repaired.is_empty():
				return {"valid": false, "reason": "triangle_3103_missing_before_or_after_repair"}
			var local_trace: Dictionary = _trace_r81_source_tetra(fixture, built, target_original)
			var target_centroid: Vector3 = _parse_vector3(target_original.centroid)
			var target_face_normal: Vector3 = _parse_vector3(target_original.face_normal)
			var field_branches: Dictionary = _field_branch_values(target_centroid, snapshot)
			entry["target_triangle_before_repair"] = target_original
			entry["target_triangle_after_repair"] = target_repaired
			entry["target_tetra_source_trace"] = local_trace
			entry["target_field_branch_values"] = field_branches
			entry["target_centroid_signed_samples_along_face_normal"] = _signed_samples_along_normal(target_centroid,
				target_face_normal, snapshot)
			entry["target_vertex_canonical_density_samples"] = _triangle_canonical_samples(target_original, snapshot)
			entry["target_vertices_identical_after_repair"] = target_original.vertices == target_repaired.vertices
			entry["target_global_triangle_index_before"] = target_original.triangle_index
			entry["target_global_triangle_index_after"] = target_repaired.triangle_index
			if target_original.triangle_index != R81_WINDING_TRIANGLE:
				return {"valid": false, "reason": "frozen_triangle_index_not_reproduced", "partial": entry}
			scenario_records[String(scenario)] = entry
		else:
			scenario_records[String(scenario)] = entry
	var fill_record: Dictionary = scenario_records.get("center_fill_then_wall_carve", {})
	var target: Dictionary = fill_record.get("target_triangle_before_repair", {})
	var target_dot := float(target.get("face_normal_dot_canonical_outward_gradient_h0p01", 1.0))
	return {"valid": not target.is_empty(), "scenarios": scenario_records,
		"reproduced_cell_712_triangle_3103_opposing_gradient": target_dot < 0.0,
		"repair_comparison": "R7.3 repair is replayed unchanged; targeted triangle and shared-normal cell pairs are compared before and after; no candidate correction is applied"}


func _find_r81_pair(records: Array, cells: Array) -> Dictionary:
	for value in records:
		var record: Dictionary = value
		if int(record.get("cell_id_a", -1)) == cells[0] and int(record.get("cell_id_b", -1)) == cells[1]:
			return record
	return {}


func _find_r81_triangle(positions: PackedVector3Array, target_centroid: Vector3) -> Dictionary:
	var best_index := -1
	var best_distance := INF
	for index in range(0, positions.size(), 3):
		var centroid: Vector3 = (positions[index] + positions[index + 1] + positions[index + 2]) / 3.0
		var distance := centroid.distance_to(target_centroid)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index < 0 or best_distance > 0.00001:
		return {}
	var a: Vector3 = positions[best_index]
	var b: Vector3 = positions[best_index + 1]
	var c: Vector3 = positions[best_index + 2]
	var cross: Vector3 = (b - a).cross(c - a)
	var face_normal: Vector3 = cross.normalized()
	var centroid: Vector3 = (a + b + c) / 3.0
	var gradient := _gradient_raw(centroid, _r8_fill_snapshot, 0.01)
	var outward := -gradient.normalized()
	var triangle: Dictionary = {"triangle_index": best_index / 3,
		"owner_cell_id_expected": R81_WINDING_CELL,
		"vertices": [_vec3_array(a), _vec3_array(b), _vec3_array(c)],
		"vertex_float32_bytes": [_vec3_bytes(a), _vec3_bytes(b), _vec3_bytes(c)],
		"centroid": _vec3_array(centroid), "centroid_distance_from_frozen_target": best_distance,
		"face_cross": _vec3_array(cross), "face_normal": _vec3_array(face_normal),
		"canonical_gradient_raw_h0p01": _vec3_array(gradient),
		"canonical_outward_gradient_h0p01": _vec3_array(outward),
		"face_normal_dot_canonical_outward_gradient_h0p01": face_normal.dot(outward),
		"cross_squared_length": cross.length_squared(), "degenerate_threshold_squared_cross": 1.0e-12}
	return triangle


func _trace_r81_source_tetra(fixture: RefCounted, built: Dictionary, target_triangle: Dictionary) -> Dictionary:
	var cell_coordinate: Vector3i = fixture._cell_from_id(R81_WINDING_CELL)
	var cell_geometry: Dictionary = built.cells.get(R81_WINDING_CELL, {})
	if cell_geometry.is_empty():
		return {"valid": false, "reason": "target_owner_cell_geometry_missing", "cell": _vec3i_array(cell_coordinate)}
	var triangle_local_index := -1
	for index in range(0, cell_geometry.vertices.size(), 3):
		var center: Vector3 = (cell_geometry.vertices[index] + cell_geometry.vertices[index + 1] + cell_geometry.vertices[index + 2]) / 3.0
		if center.distance_to(_parse_vector3(target_triangle.centroid)) <= 0.00001:
			triangle_local_index = index / 3
			break
	if triangle_local_index < 0:
		return {"valid": false, "reason": "triangle_not_found_in_owner_cell"}
	var is_fine: bool = fixture.refined_cells.has(R81_WINDING_CELL)
	var candidate_records: Array[Dictionary] = []
	for sub_y in range(2 if is_fine else 1):
		for sub_z in range(2 if is_fine else 1):
			for sub_x in range(2 if is_fine else 1):
				var points: Array[Vector3] = []
				var values: Array[float] = []
				for corner_value in MesherR8.CORNERS:
					var corner: Vector3i = corner_value
					var sample_index := Vector3i(sub_x, sub_y, sub_z) + corner
					var point: Vector3
					var density: float
					if is_fine:
						point = Fixture.PATCH_MIN + Vector3(cell_coordinate) * Fixture.COARSE_STEP + Vector3(sample_index) * Fixture.FINE_STEP
						density = fixture._fine_value(fixture.refined_cells[R81_WINDING_CELL], sample_index.x, sample_index.y, sample_index.z)
					else:
						point = Fixture.PATCH_MIN + Vector3(cell_coordinate + corner) * Fixture.COARSE_STEP
						density = fixture._canonical_sample(point)
					points.append(point)
					values.append(density)
				for tetra_index in range(MesherR8.TETRAHEDRA.size()):
					var tetra: Array = MesherR8.TETRAHEDRA[tetra_index]
					var triangle_positions := PackedVector3Array()
					var triangle_normals := PackedVector3Array()
					MesherR8._polygonize_tetra(tetra, points, values, triangle_positions, triangle_normals)
					for offset in range(0, triangle_positions.size(), 3):
						var a: Vector3 = triangle_positions[offset]
						var b: Vector3 = triangle_positions[offset + 1]
						var c: Vector3 = triangle_positions[offset + 2]
						var target_center: Vector3 = _parse_vector3(target_triangle.centroid)
						if ((a + b + c) / 3.0).distance_to(target_center) <= 0.00001:
							var inside: Array[int] = []
							var outside: Array[int] = []
							var inside_center := Vector3.ZERO
							var outside_center := Vector3.ZERO
							for corner_value in tetra:
								var corner_index: int = int(corner_value)
								if values[corner_index] >= 0.0:
									inside.append(corner_index)
									inside_center += points[corner_index]
								else:
									outside.append(corner_index)
									outside_center += points[corner_index]
							inside_center /= float(inside.size())
							outside_center /= float(outside.size())
							var toward_empty := outside_center - inside_center
							var cross := (b - a).cross(c - a)
							var corner_records: Array[Dictionary] = []
							for corner_value in tetra:
								var ci: int = int(corner_value)
								corner_records.append({"cube_corner_index": ci, "cube_corner": _vec3i_array(MesherR8.CORNERS[ci]),
									"position": _vec3_array(points[ci]), "density": values[ci], "density_float32_bytes": _float32_bytes(values[ci]),
									"classification": "inside_solid" if values[ci] >= 0.0 else "outside_empty"})
							candidate_records.append({"subcell_xyz": [sub_x, sub_y, sub_z], "tetrahedron_index": tetra_index,
								"tetrahedron_corner_indices_in_source_order": tetra,
								"inside_corner_indices": inside, "outside_corner_indices": outside,
								"corners": corner_records, "inside_center": _vec3_array(inside_center),
								"outside_center": _vec3_array(outside_center), "toward_empty": _vec3_array(toward_empty),
								"face_cross": _vec3_array(cross), "face_cross_dot_toward_empty": cross.dot(toward_empty),
								"source_polygonizer_orientation_rule": "swap vertices when face_cross dot (outside_center - inside_center) is negative"})
	var global_offset := 0
	for key in built.cells:
		if int(key) == R81_WINDING_CELL:
			break
		global_offset += int(built.cells[key].triangle_count)
	return {"valid": not candidate_records.is_empty(), "reason": "" if not candidate_records.is_empty() else "source_tetra_not_reproduced",
		"cell_coordinate": _vec3i_array(cell_coordinate), "cell_id": R81_WINDING_CELL,
		"cell_geometry_path": "fine_2x2x2_subcells" if is_fine else "coarse_1x1x1_subcell",
		"cell_local_triangle_index": triangle_local_index,
		"computed_global_triangle_offset": global_offset,
		"global_triangle_index_reconciles": global_offset + triangle_local_index == R81_WINDING_TRIANGLE,
		"matched_source_tetrahedra": candidate_records}


func _field_branch_values(point: Vector3, snapshot: Dictionary) -> Dictionary:
	var mapped: Dictionary = SpatialR8.world_to_region_local(point)
	var density: float = Field.sample_density(SEED, mapped.region_key, mapped.local_position, false)
	var before := density
	var operations: Array[Dictionary] = []
	for index in range(snapshot.centers.size()):
		var center: Vector3 = snapshot.centers[index]
		var radius: float = float(snapshot.radii[index])
		var distance := center.distance_to(point)
		var operation_value := distance - radius if int(snapshot.modes[index]) == Brush.Mode.CARVE else radius - distance
		var after := minf(before, operation_value) if int(snapshot.modes[index]) == Brush.Mode.CARVE else maxf(before, operation_value)
		operations.append({"sequence": index, "mode": "CARVE" if int(snapshot.modes[index]) == Brush.Mode.CARVE else "FILL",
			"center": _vec3_array(center), "radius": radius, "distance_to_center": distance,
			"operator_value": operation_value, "density_before": before, "density_after": after,
			"active_operator_branch": absf(before - operation_value) <= 1.0e-5})
		before = after
	return {"world_position": _vec3_array(point), "region_key": _vec2i_array(mapped.region_key),
		"local_position": _vec3_array(mapped.local_position), "base_sdf_density": density,
		"ordered_operator_evaluation": operations, "final_density": before,
		"reconciles_canonical_sampler_within_1e_minus_5": absf(before - Transition.sample_canonical(SEED, point, snapshot)) <= 1.0e-5}


func _gradient_stability(point: Vector3, snapshot: Dictionary, normal_a: Vector3) -> Dictionary:
	var rows: Array[Dictionary] = []
	for h_value in R81_NORMAL_STEPS:
		var h: float = float(h_value)
		var gradient := _gradient_raw(point, snapshot, h)
		rows.append({"epsilon_world": h, "gradient": _vec3_array(gradient),
			"gradient_magnitude": gradient.length(), "normalized_gradient": _vec3_array(gradient.normalized()),
			"face_normal_dot_outward_gradient": normal_a.dot(-gradient.normalized())})
	return {"sample_world_position": _vec3_array(point), "samples": rows}


func _gradient_raw(point: Vector3, snapshot: Dictionary, h: float) -> Vector3:
	return Vector3(
		Transition.sample_canonical(SEED, point + Vector3.RIGHT * h, snapshot) - Transition.sample_canonical(SEED, point - Vector3.RIGHT * h, snapshot),
		Transition.sample_canonical(SEED, point + Vector3.UP * h, snapshot) - Transition.sample_canonical(SEED, point - Vector3.UP * h, snapshot),
		Transition.sample_canonical(SEED, point + Vector3.BACK * h, snapshot) - Transition.sample_canonical(SEED, point - Vector3.BACK * h, snapshot)
	) / (2.0 * h)


func _signed_samples_along_normal(point: Vector3, face_normal: Vector3, snapshot: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for offset in [-0.125, -0.0625, -0.01, -0.001, 0.0, 0.001, 0.01, 0.0625, 0.125]:
		var p := point + face_normal * float(offset)
		rows.append({"offset_along_oriented_face_normal": float(offset), "position": _vec3_array(p),
			"density": Transition.sample_canonical(SEED, p, _r8_fill_snapshot), "branches": _field_branch_values(p, _r8_fill_snapshot)})
	return rows


func _diagnose_r81_xplus_seam() -> Dictionary:
	var setup: Dictionary = _make_snapshot("center_fill_then_wall_carve")
	if not bool(setup.get("valid", false)):
		return {"valid": false, "reason": "fill_carve_snapshot_invalid"}
	var snapshot: Dictionary = setup.snapshot
	var spec: Dictionary = {"id": "X_POS", "axis": 0, "plane": 16.0,
		"region_a": Vector2i(0, 0), "chunk_a": Vector2i(3, 2),
		"region_b": Vector2i(1, 0), "chunk_b": Vector2i(0, 2)}
	var cases: Array[Dictionary] = []
	for pair_value in [[1, 0], [0, 1], [1, 1]]:
		var pair: Array = pair_value
		var a: Dictionary = _build_r81_world_chunk(int(pair[0]), spec.region_a, spec.chunk_a, snapshot)
		var b: Dictionary = _build_r81_world_chunk(int(pair[1]), spec.region_b, spec.chunk_b, snapshot)
		if not bool(a.get("valid", false)) or not bool(b.get("valid", false)):
			return {"valid": false, "reason": "xplus_pair_build_failed", "lod_pair": pair}
		var contour_a: Dictionary = _contour_with_sources(a.positions, spec.axis, spec.plane)
		var contour_b: Dictionary = _contour_with_sources(b.positions, spec.axis, spec.plane)
		var base_a: Dictionary = _r8_plane_contour(a.positions, a.normals, spec.axis, spec.plane)
		var base_b: Dictionary = _r8_plane_contour(b.positions, b.normals, spec.axis, spec.plane)
		var r8_compare: Dictionary = _r8_compare_contours(base_a, base_b)
		var face_samples: Dictionary = _r8_compare_face_samples(spec, snapshot)
		var exact_edges_a: Dictionary = _independent_boundary_edges(a.positions, spec.axis, spec.plane)
		var exact_edges_b: Dictionary = _independent_boundary_edges(b.positions, spec.axis, spec.plane)
		var independent_compare: Dictionary = _compare_r81_edge_sets(exact_edges_a, exact_edges_b)
		cases.append({"lod_a_negative_side": int(pair[0]), "lod_b_positive_side": int(pair[1]),
			"region_a": _vec2i_array(spec.region_a), "chunk_a": _vec2i_array(spec.chunk_a),
			"region_b": _vec2i_array(spec.region_b), "chunk_b": _vec2i_array(spec.chunk_b),
			"chunk_world_origin_a": _vec3_array(a.origin), "chunk_world_origin_b": _vec3_array(b.origin),
			"world_plane": spec.plane, "a_mesh_sha256": a.sha256, "b_mesh_sha256": b.sha256,
			"a_triangle_count": a.triangle_count, "b_triangle_count": b.triangle_count,
			"r8_contour_oracle": r8_compare, "independent_boundary_edge_oracle": independent_compare,
			"shared_scalar_samples": face_samples,
			"a_contour_with_triangle_sources": contour_a, "b_contour_with_triangle_sources": contour_b,
			"unmatched_segments_from_a": _unmatched_r81_segments(contour_a.segments, contour_b.segments),
			"unmatched_segments_from_b": _unmatched_r81_segments(contour_b.segments, contour_a.segments),
			"unmatched_segment_canonical_density_samples_a": _segment_canonical_samples(
				_unmatched_r81_segments(contour_a.segments, contour_b.segments), snapshot),
			"unmatched_segment_canonical_density_samples_b": _segment_canonical_samples(
				_unmatched_r81_segments(contour_b.segments, contour_a.segments), snapshot),
			"matching_method": "same R8 1e-5 integer point key for reproduction; separate raw boundary-edge set comparison; no tolerance was widened"})
	var mismatch_case: Dictionary = {}
	var reverse_control: Dictionary = {}
	for item in cases:
		if item.lod_a_negative_side == 1 and item.lod_b_positive_side == 0: mismatch_case = item
		if item.lod_a_negative_side == 0 and item.lod_b_positive_side == 1: reverse_control = item
	return {"valid": not mismatch_case.is_empty() and not reverse_control.is_empty(),
		"scenario_input_sha256": INPUT_SHA_FILL_CARVE, "cases": cases,
		"mismatch_reproduced_1_0": not bool(mismatch_case.get("r8_contour_oracle", {}).get("contour_segments_match", true)),
		"opposite_lod_control_matches": bool(reverse_control.get("r8_contour_oracle", {}).get("contour_segments_match", false)),
		"interpretation_scope": "Actual CPU LOD chunk meshes are compared in world space. A raw mesh mismatch is not attributed to the oracle unless the independent edge-set analysis contradicts the R8 contour result."}


func _build_r81_world_chunk(lod: int, region: Vector2i, chunk: Vector2i, snapshot: Dictionary) -> Dictionary:
	var local: Dictionary = _r8_build_chunk(lod, region, chunk, snapshot)
	if not bool(local.get("valid", false)):
		return {"valid": false, "reason": local.get("reason", "chunk_build_failed")}
	var origin: Vector3 = SpatialR8.region_origin_world(region) + GridR8.origin_for(chunk)
	var positions: PackedVector3Array = local.positions.duplicate()
	for index in range(positions.size()):
		positions[index] += origin
	return {"valid": true, "origin": origin, "positions": positions, "normals": local.normals,
		"triangle_count": int(local.triangle_count), "sha256": _mesh_sha256(positions, local.normals)}


func _contour_with_sources(positions: PackedVector3Array, axis: int, plane: float) -> Dictionary:
	var segments: Array[Dictionary] = []
	for index in range(0, positions.size(), 3):
		var triangle: Array[Vector3] = [positions[index], positions[index + 1], positions[index + 2]]
		var hits: Array[Vector3] = []
		for edge in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = triangle[int(edge[0])]
			var b: Vector3 = triangle[int(edge[1])]
			var da := a[axis] - plane
			var db := b[axis] - plane
			if absf(da) <= 1.0e-6:
				hits.append(a)
			if da * db < -1.0e-12:
				hits.append(a.lerp(b, da / (da - db)))
		var unique: Array[Vector3] = []
		for hit in hits:
			var seen := false
			for prior in unique:
				if hit.distance_squared_to(prior) <= 1.0e-12:
					seen = true
					break
			if not seen:
				unique.append(hit)
		if unique.size() != 2 or unique[0].distance_squared_to(unique[1]) <= 1.0e-12:
			continue
		var a: Vector3 = unique[0]
		var b: Vector3 = unique[1]
		var ak := _r8_point_key(a)
		var bk := _r8_point_key(b)
		segments.append({"triangle_index": index / 3, "a": _vec3_array(a), "b": _vec3_array(b),
			"a_key_1e_minus_5": ak, "b_key_1e_minus_5": bk,
			"key_1e_minus_5": _r8_edge_key(ak, bk),
			"a_float32_bytes": _vec3_bytes(a), "b_float32_bytes": _vec3_bytes(b),
			"triangle_vertices": [_vec3_array(triangle[0]), _vec3_array(triangle[1]), _vec3_array(triangle[2])]})
	return {"segment_count": segments.size(), "segments": segments}


func _unmatched_r81_segments(source: Array, other: Array) -> Array[Dictionary]:
	var other_keys: Dictionary = {}
	for value in other:
		other_keys[String(value.key_1e_minus_5)] = true
	var result: Array[Dictionary] = []
	for value in source:
		if not other_keys.has(String(value.key_1e_minus_5)):
			result.append(value)
	return result


func _independent_boundary_edges(positions: PackedVector3Array, axis: int, plane: float) -> Dictionary:
	var incidence: Dictionary = {}
	var source: Dictionary = {}
	for index in range(0, positions.size(), 3):
		var triangle: Array[Vector3] = [positions[index], positions[index + 1], positions[index + 2]]
		for edge in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = triangle[int(edge[0])]
			var b: Vector3 = triangle[int(edge[1])]
			if absf(a[axis] - plane) > 1.0e-6 or absf(b[axis] - plane) > 1.0e-6:
				continue
			var ak := _r8_point_key(a)
			var bk := _r8_point_key(b)
			var key := _r8_edge_key(ak, bk)
			incidence[key] = int(incidence.get(key, 0)) + 1
			if not source.has(key):
				source[key] = {"edge_key": key, "a": _vec3_array(a), "b": _vec3_array(b), "first_triangle_index": index / 3}
	var edges: Array[Dictionary] = []
	var incidence_histogram: Dictionary = {}
	for key in incidence:
		var count := int(incidence[key])
		incidence_histogram[count] = int(incidence_histogram.get(count, 0)) + 1
		if count == 1:
			edges.append(source[key])
	return {"unique_boundary_edges_with_any_incidence": incidence.size(), "incidence_histogram": incidence_histogram,
		"single_incidence_edges": edges, "single_incidence_edge_count": edges.size(),
		"source": "independent triangle edge enumeration; both endpoints must lie on the outer plane; key quantization remains the R8 1e-5 diagnostic key"}


func _compare_r81_edge_sets(a: Dictionary, b: Dictionary) -> Dictionary:
	var map_a: Dictionary = {}
	var map_b: Dictionary = {}
	for edge in a.single_incidence_edges:
		map_a[String(edge.edge_key)] = edge
	for edge in b.single_incidence_edges:
		map_b[String(edge.edge_key)] = edge
	var only_a: Array = []
	var only_b: Array = []
	for key in map_a:
		if not map_b.has(key): only_a.append(map_a[key])
	for key in map_b:
		if not map_a.has(key): only_b.append(map_b[key])
	return {"single_incidence_edge_count_a": map_a.size(), "single_incidence_edge_count_b": map_b.size(),
		"unmatched_a": only_a, "unmatched_b": only_b,
		"exact_boundary_edge_set_match": only_a.is_empty() and only_b.is_empty()}


func _diagnose_r81_xminus_picker() -> Dictionary:
	var setup: Dictionary = _make_snapshot("center_fill_then_wall_carve")
	if not bool(setup.get("valid", false)):
		return {"valid": false, "reason": "fill_carve_snapshot_invalid"}
	var snapshot: Dictionary = setup.snapshot
	var xminus: Dictionary = {"id": "X_NEG", "axis": 0, "plane": 0.0,
		"region_a": Vector2i(-1, 0), "chunk_a": Vector2i(3, 2),
		"region_b": Vector2i(0, 0), "chunk_b": Vector2i(0, 2)}
	var xplus: Dictionary = {"id": "X_POS", "axis": 0, "plane": 16.0,
		"region_a": Vector2i(0, 0), "chunk_a": Vector2i(3, 2),
		"region_b": Vector2i(1, 0), "chunk_b": Vector2i(0, 2)}
	var cases: Array[Dictionary] = []
	for spec in [xminus, xplus]:
		var lods: Array = [[0, 0], [1, 1]] if String(spec.id) == "X_NEG" else [[0, 0]]
		for pair_value in lods:
			var pair: Array = pair_value
			var a: Dictionary = _build_r81_world_chunk(int(pair[0]), spec.region_a, spec.chunk_a, snapshot)
			var b: Dictionary = _build_r81_world_chunk(int(pair[1]), spec.region_b, spec.chunk_b, snapshot)
			if not bool(a.get("valid", false)) or not bool(b.get("valid", false)):
				return {"valid": false, "reason": "picker_chunk_build_failed", "boundary": spec.id, "lod_pair": pair}
			var origin := Vector3(float(spec.plane), 8.0, 6.0)
			var direction := Vector3.DOWN
			var sampler: Callable = func(point: Vector3) -> float:
				return Transition.sample_canonical(SEED, point, snapshot)
			var picked: Dictionary = Picker.pick_sdf_v1_surface(origin, direction, sampler)
			var root_distance: float = _r8_first_surface_distance(origin, direction, snapshot, 12.0)
			var shared_face_samples: Dictionary = _r8_compare_face_samples(spec, snapshot)
			var hits_a: Array[Dictionary] = _ray_hits_r81(a.positions, origin, direction, 12.0)
			var hits_b: Array[Dictionary] = _ray_hits_r81(b.positions, origin, direction, 12.0)
			var combined_positions := PackedVector3Array()
			combined_positions.append_array(a.positions)
			combined_positions.append_array(b.positions)
			var hits_union: Array[Dictionary] = _ray_hits_r81(combined_positions, origin, direction, 12.0)
			var record: Dictionary = {"boundary": spec.id, "lod_a_negative_side": int(pair[0]), "lod_b_positive_side": int(pair[1]),
				"region_a": _vec2i_array(spec.region_a), "chunk_a": _vec2i_array(spec.chunk_a),
				"region_b": _vec2i_array(spec.region_b), "chunk_b": _vec2i_array(spec.chunk_b),
				"world_ray_origin": _vec3_array(origin), "world_ray_direction": _vec3_array(direction),
				"ray_length": 12.0, "canonical_density_at_origin": sampler.call(origin),
				"picker_hit": bool(picked.get("hit", false)),
				"picker_position": _vec3_array(picked.get("position", origin)),
				"picker_distance": origin.distance_to(Vector3(picked.get("position", origin))) if bool(picked.get("hit", false)) else -1.0,
				"independent_dense_sdf_first_root_distance": root_distance,
				"picker_vs_dense_root_distance_error": absf(float(origin.distance_to(Vector3(picked.get("position", origin)))) - root_distance) if bool(picked.get("hit", false)) and root_distance >= 0.0 else -1.0,
				"mesh_a_world_origin": _vec3_array(a.origin), "mesh_b_world_origin": _vec3_array(b.origin),
				"mesh_a_sha256": a.sha256, "mesh_b_sha256": b.sha256,
				"mesh_a_ray_hits": hits_a, "mesh_b_ray_hits": hits_b, "union_ray_hits": hits_union,
				"first_mesh_a_hit_canonical_samples": _triangle_canonical_samples(hits_a[0], snapshot) if not hits_a.is_empty() else {},
				"first_mesh_b_hit_canonical_samples": _triangle_canonical_samples(hits_b[0], snapshot) if not hits_b.is_empty() else {},
				"first_union_hit_canonical_samples": _triangle_canonical_samples(hits_union[0], snapshot) if not hits_union.is_empty() else {},
				"shared_scalar_samples": shared_face_samples,
				"first_union_mesh_hit_position": _hit_position(origin, direction, hits_union),
				"first_union_mesh_distance": float(hits_union[0].distance) if not hits_union.is_empty() else -1.0,
				"picker_mesh_position_error": Vector3(picked.position).distance_to(_hit_position(origin, direction, hits_union)) if bool(picked.get("hit", false)) and not hits_union.is_empty() else -1.0,
				"canonical_density_around_first_picker_and_mesh_hits": _picker_density_probes(origin, direction, root_distance,
					float(origin.distance_to(Vector3(picked.position))) if bool(picked.get("hit", false)) else -1.0,
					float(hits_union[0].distance) if not hits_union.is_empty() else -1.0, snapshot),
				"triangle_ray_oracle": "independent double-sided Moller-Trumbore enumeration using the R7 scalar intersection kernel, preserving every hit by triangle index"}
			cases.append(record)
	return {"valid": cases.size() == 3,
		"frozen_input_sha256": INPUT_SHA_FILL_CARVE,
		"cases": cases,
		"xminus_lod0_reproduces_reported_offset": cases.size() > 0 and absf(float(cases[0].picker_mesh_position_error) - 0.366092) < 0.002,
		"interpretation_scope": "SDF picker is compared with an independently bracketed canonical field root and all triangle intersections on the same physical ray through the adjoining chunk union; no positional acceptance tolerance is adopted"}


func _ray_hits_r81(positions: PackedVector3Array, origin: Vector3, direction: Vector3, max_distance: float) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for index in range(0, positions.size(), 3):
		var hit: Dictionary = _ray_triangle_intersection(origin, direction, max_distance,
			positions[index], positions[index + 1], positions[index + 2])
		if bool(hit.get("hit", false)):
			hits.append({"triangle_index": index / 3, "distance": float(hit.distance_world),
				"position": _vec3_array(origin + direction * float(hit.distance_world)),
				"front_facing": bool(hit.front_facing),
				"triangle_vertices": [_vec3_array(positions[index]), _vec3_array(positions[index + 1]), _vec3_array(positions[index + 2])]})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	return hits


func _hit_position(origin: Vector3, direction: Vector3, hits: Array[Dictionary]) -> Vector3:
	return origin + direction * float(hits[0].distance) if not hits.is_empty() else origin


func _picker_density_probes(origin: Vector3, direction: Vector3, sdf_root_distance: float,
	picker_distance: float, mesh_distance: float, snapshot: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for label in ["sdf_root", "picker", "mesh"]:
		var distance := sdf_root_distance if label == "sdf_root" else (picker_distance if label == "picker" else mesh_distance)
		if distance < 0.0: continue
		for delta in [-0.01, 0.0, 0.01]:
			var t: float = distance + delta
			var point := origin + direction * t
			rows.append({"reference": label, "distance": t, "delta": delta,
				"position": _vec3_array(point), "density": Transition.sample_canonical(SEED, point, snapshot)})
	return rows


func _triangle_canonical_samples(triangle_record: Dictionary, snapshot: Dictionary) -> Dictionary:
	var vertices_value: Variant = triangle_record.get("vertices", triangle_record.get("triangle_vertices", []))
	if not (vertices_value is Array) or vertices_value.size() != 3:
		return {"valid": false, "reason": "triangle_vertices_unavailable"}
	var vertices: Array = vertices_value
	var samples: Array[Dictionary] = []
	var centroid := Vector3.ZERO
	for index in range(3):
		var position: Vector3 = _parse_vector3(vertices[index])
		centroid += position
		samples.append({"vertex_index": index, "position": _vec3_array(position),
			"canonical_density": Transition.sample_canonical(SEED, position, snapshot)})
	centroid /= 3.0
	return {"valid": true, "centroid": _vec3_array(centroid),
		"centroid_canonical_density": Transition.sample_canonical(SEED, centroid, snapshot),
		"vertices": samples}


func _segment_canonical_samples(segments: Array, snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in segments:
		var segment: Dictionary = value
		var a: Vector3 = _parse_vector3(segment.get("a", []))
		var b: Vector3 = _parse_vector3(segment.get("b", []))
		result.append({"edge_key": segment.get("key_1e_minus_5", ""),
			"source_triangle_index": segment.get("triangle_index", -1),
			"a": _vec3_array(a), "a_density": Transition.sample_canonical(SEED, a, snapshot),
			"b": _vec3_array(b), "b_density": Transition.sample_canonical(SEED, b, snapshot)})
	return result


func _vec3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _vec3i_array(value: Vector3i) -> Array[int]:
	return [value.x, value.y, value.z]


func _vec2i_array(value: Vector2i) -> Array[int]:
	return [value.x, value.y]


func _float32_bytes(value: float) -> String:
	return PackedFloat32Array([value]).to_byte_array().hex_encode()


func _vec3_bytes(value: Vector3) -> String:
	return PackedFloat32Array([value.x, value.y, value.z]).to_byte_array().hex_encode()


func _parse_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is String:
		var cleaned: String = String(value).trim_prefix("(").trim_suffix(")")
		var parts: PackedStringArray = cleaned.split(",")
		if parts.size() == 3:
			return Vector3(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float(), parts[2].strip_edges().to_float())
	return Vector3.ZERO


func _emit_r81(name: String, record: Dictionary) -> void:
	_r81_records.append({"phase": name, "record": record})
	var payload: Dictionary = {"phase": name, "record": record}
	print("P3_1_R8_1_JSON " + JSON.stringify(payload))
	if _r81_evidence_dir.is_empty():
		return
	var path := _r81_evidence_dir.path_join("phase-%02d-%s.json" % [_r81_records.size(), name])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_r81_failures.append("evidence_write_failed:%s:%s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(payload) + "\n")
	file.flush()
	file.close()


func _finish_r81(status: String, reason: String) -> void:
	var complete: bool = status == "DIAGNOSTIC_COMPLETE" and _r81_failures.is_empty()
	var result: Dictionary = {"suite": "P3_1_R8_1_GEOMETRY_CAUSALITY",
		"status": status if _r81_failures.is_empty() else "BLOCKED",
		"reason": reason, "elapsed_usec": Time.get_ticks_usec() - _r81_started_usec,
		"phase_count": _r81_records.size(), "phases": _r81_records, "failures": _r81_failures,
		"assertions": 0, "diagnostic_complete": complete, "production_change": false,
		"production_scene_loaded": false, "persistence_or_user_saves_accessed": false,
		"approved_geometry_tolerance": "NONE", "degeneracy_squared_cross_threshold": 1.0e-12}
	print("P3_1_R8_1_RESULT " + JSON.stringify(result))
	if not _r81_evidence_dir.is_empty():
		var output := _r81_evidence_dir.path_join("result.json")
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result) + "\n")
			file.flush()
			file.close()
	quit(0 if complete else 1)
