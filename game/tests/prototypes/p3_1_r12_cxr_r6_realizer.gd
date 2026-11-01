extends "res://tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd"

const R6_RESIDUAL_EPSILON: float = 1.0e-7
const R6_BARYCENTRIC_EPSILON: float = 1.0e-7
const MAX_ULP_STEPS_PER_COORDINATE: int = 2

func corrected_tetra_zero_sources(tet_data: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var positions: Array = tet_data.get("positions", [])
	var samples: Array = tet_data.get("samples", [])
	if positions.size() != 4 or samples.size() != 4:
		return rows
	var edges: Array = [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]
	var original_positions: Array[Vector3] = []
	var emitted_positions: Array[Vector3] = []
	for edge_value in edges:
		var edge: Array = edge_value
		var ia: int = int(edge[0])
		var ib: int = int(edge[1])
		var va: float = float(samples[ia])
		var vb: float = float(samples[ib])
		var original: Vector3
		var interpolation_parameter: float = NAN
		var carried_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var include: bool = false
		if va == 0.0:
			original = Vector3(positions[ia])
			carried_weights[ia] = 1.0
			interpolation_parameter = 0.0
			include = true
		elif vb == 0.0:
			original = Vector3(positions[ib])
			carried_weights[ib] = 1.0
			interpolation_parameter = 1.0
			include = true
		elif (va < 0.0 and vb > 0.0) or (va > 0.0 and vb < 0.0):
			interpolation_parameter = va / (va - vb)
			original = Vector3(positions[ia]).lerp(Vector3(positions[ib]), interpolation_parameter)
			carried_weights[ia] = 1.0 - interpolation_parameter
			carried_weights[ib] = interpolation_parameter
			include = true
		if not include:
			continue
		if original_positions.has(original):
			continue
		original_positions.append(original)
		var before: Dictionary = _evaluate_zero_point(original, tet_data)
		var selected: Dictionary = {
			"position": original,
			"weights": before.get("weights", []),
			"field_residual": before.get("field_residual", NAN),
			"barycentric_valid": before.get("barycentric_valid", false),
			"barycentric_gate_pass": before.get("barycentric_gate_pass", false),
			"residual_gate_pass": before.get("residual_gate_pass", false),
			"accepted": before.get("accepted", false),
			"ulp_steps": [0, 0, 0],
			"search_state": "unchanged"
		}
		if not bool(before.get("accepted", false)):
			selected = _search_representable_zero(original, tet_data)
		var corrected: Vector3 = Vector3(selected.get("position", original))
		if not emitted_positions.has(corrected):
			emitted_positions.append(corrected)
		rows.append({
			"construction_edge_corner_indices": [ia, ib],
			"construction_edge_id": "corner:%d-%d" % [ia, ib],
			"interpolation_parameter": interpolation_parameter,
			"carried_edge_barycentric_weights": carried_weights,
			"endpoint_samples": [va, vb],
			"endpoint_world_positions": [positions[ia], positions[ib]],
			"original_position": original,
			"original_position_f32_hex": _position_bytes_hex(original),
			"original_barycentric_weights": before.get("weights", []),
			"original_field_residual": before.get("field_residual", "UNKNOWN_NOT_CAPTURED"),
			"original_barycentric_valid": before.get("barycentric_valid", false),
			"original_barycentric_gate_pass": before.get("barycentric_gate_pass", false),
			"original_residual_gate_pass": before.get("residual_gate_pass", false),
			"corrected_position": corrected,
			"corrected_position_f32_hex": _position_bytes_hex(corrected),
			"corrected_barycentric_weights": selected.get("weights", []),
			"corrected_field_residual": selected.get("field_residual", "UNKNOWN_NOT_CAPTURED"),
			"corrected_barycentric_valid": selected.get("barycentric_valid", false),
			"corrected_barycentric_gate_pass": selected.get("barycentric_gate_pass", false),
			"corrected_residual_gate_pass": selected.get("residual_gate_pass", false),
			"coordinate_ulp_steps": selected.get("ulp_steps", [0, 0, 0]),
			"correction_search_state": selected.get("search_state", "UNKNOWN_NOT_CAPTURED"),
			"accepted": selected.get("accepted", false),
			"correction_reason": String(selected.get("reason", ""))
		})
	return rows

func _tetra_zero_points(tet_data: Dictionary) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for row in corrected_tetra_zero_sources(tet_data):
		if not bool(row.get("accepted", false)):
			continue
		var point: Vector3 = Vector3(row.get("corrected_position", Vector3.ZERO))
		if not points.has(point):
			points.append(point)
	return points

func _search_representable_zero(original: Vector3, tet_data: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_residual: float = INF
	var best_step_norm: int = 2147483647
	for step_x in range(-MAX_ULP_STEPS_PER_COORDINATE, MAX_ULP_STEPS_PER_COORDINATE + 1):
		for step_y in range(-MAX_ULP_STEPS_PER_COORDINATE, MAX_ULP_STEPS_PER_COORDINATE + 1):
			for step_z in range(-MAX_ULP_STEPS_PER_COORDINATE, MAX_ULP_STEPS_PER_COORDINATE + 1):
				if step_x == 0 and step_y == 0 and step_z == 0:
					continue
				var candidate: Vector3 = Vector3(
					_step_binary32(original.x, step_x),
					_step_binary32(original.y, step_y),
					_step_binary32(original.z, step_z)
				)
				var evaluation: Dictionary = _evaluate_zero_point(candidate, tet_data)
				if not bool(evaluation.get("barycentric_gate_pass", false)) or not is_finite(float(evaluation.get("field_residual", NAN))):
					continue
				var absolute_residual: float = absf(float(evaluation.get("field_residual", INF)))
				var step_norm: int = absi(step_x) + absi(step_y) + absi(step_z)
				if absolute_residual < best_residual or (absolute_residual == best_residual and step_norm < best_step_norm):
					best_residual = absolute_residual
					best_step_norm = step_norm
					best = evaluation.duplicate(true)
					best["position"] = candidate
					best["ulp_steps"] = [step_x, step_y, step_z]
	if best.is_empty():
		var before: Dictionary = _evaluate_zero_point(original, tet_data)
		before["position"] = original
		before["ulp_steps"] = [0, 0, 0]
		before["search_state"] = "no_valid_point_within_plus_minus_2_ulp_per_coordinate"
		before["reason"] = "R6_A_REPRESENTABLE_ZERO_NOT_FOUND_WITHIN_BOUND"
		return before
	best["search_state"] = "corrected_within_plus_minus_2_ulp_per_coordinate" if bool(best.get("accepted", false)) else "best_same_tetra_residual_within_plus_minus_2_ulp_per_coordinate_gate_failed"
	best["reason"] = "R6_A_MINIMUM_ABSOLUTE_RESIDUAL_THEN_MINIMUM_ULP_STEP_COUNT"
	return best

func _evaluate_zero_point(point: Vector3, tet_data: Dictionary) -> Dictionary:
	var bary_result: Dictionary = _tetra_barycentric(point, tet_data.get("positions", []))
	var weights: Array = bary_result.get("weights", [])
	var barycentric_gate_pass: bool = bool(bary_result.get("valid", false)) and weights.size() == 4
	if barycentric_gate_pass:
		for weight_value in weights:
			var weight: float = float(weight_value)
			if not is_finite(weight) or weight < -R6_BARYCENTRIC_EPSILON or weight > 1.0 + R6_BARYCENTRIC_EPSILON:
				barycentric_gate_pass = false
	var residual: float = NAN
	if weights.size() == 4:
		residual = 0.0
		for index in range(4):
			var weight: float = float(weights[index])
			var sample: float = float(tet_data.samples[index])
			if not is_finite(weight) or not is_finite(sample):
				residual = NAN
				break
			residual += weight * sample
		var residual_gate_pass: bool = is_finite(residual) and absf(residual) <= R6_RESIDUAL_EPSILON
		return {"position": point, "weights": weights, "field_residual": residual, "barycentric_valid": bool(bary_result.get("valid", false)), "barycentric_gate_pass": barycentric_gate_pass, "residual_gate_pass": residual_gate_pass, "accepted": barycentric_gate_pass and residual_gate_pass}
	return {"position": point, "weights": weights, "field_residual": residual, "barycentric_valid": bool(bary_result.get("valid", false)), "barycentric_gate_pass": false, "residual_gate_pass": false, "accepted": false}

func _step_binary32(value: float, direction: int) -> float:
	if direction == 0:
		return value
	var bytes: PackedByteArray = PackedFloat32Array([value]).to_byte_array()
	if bytes.size() != 4:
		return NAN
	var bits: int = int(bytes.decode_u32(0))
	if value == 0.0:
		bits = 1 if direction > 0 else 2147483649
	elif value > 0.0:
		bits += direction
	else:
		bits -= direction
	var result_bytes: PackedByteArray = PackedByteArray()
	result_bytes.resize(4)
	result_bytes.encode_u32(0, bits)
	return result_bytes.decode_float(0)

func _position_bytes_hex(point: Vector3) -> String:
	return PackedFloat32Array([point.x, point.y, point.z]).to_byte_array().hex_encode()

## R6-B: assign each replacement triangle to the full removed patch. A containing
## face wins; ties use world-space centroid distance, then stable source IDs.
func _r2_owner_for_triangle(centroid: Vector3, context: Dictionary) -> Dictionary:
	var centroid_delta: Vector3 = centroid - context.projection_origin
	var projected: Vector2 = Vector2(centroid_delta.dot(context.projection_u), centroid_delta.dot(context.projection_v))
	var candidates: Array[Dictionary] = []
	for source_triangle in context.patch:
		var ids: Array = source_triangle.get("root_ids", [])
		var points: Array = source_triangle.get("points", [])
		if ids.size() != 3 or points.size() != 3:
			continue
		var keys: Array[String] = [String(ids[0]), String(ids[1]), String(ids[2])]
		if not context.projected_positions.has(keys[0]) or not context.projected_positions.has(keys[1]) or not context.projected_positions.has(keys[2]):
			continue
		var bary: Dictionary = _r2_barycentric_2d(projected, context.projected_positions[keys[0]], context.projected_positions[keys[1]], context.projected_positions[keys[2]])
		var source_center: Vector3 = (Vector3(points[0]) + Vector3(points[1]) + Vector3(points[2])) / 3.0
		candidates.append({"triangle_id": String(source_triangle.get("triangle_id", "")), "polygon_id": String(source_triangle.get("polygon_id", "")), "source_polygon_ids": source_triangle.get("source_polygon_ids", [source_triangle.get("polygon_id", "")]).duplicate(), "distance_squared": source_center.distance_squared_to(centroid), "contains": bool(bary.get("valid", false)), "barycentric": bary.get("weights", [])})
	if candidates.is_empty():
		return {"valid": false, "reason": "candidate_centroid_has_no_removed_patch_owner", "projected_centroid": projected}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.contains) != bool(b.contains): return bool(a.contains)
		if float(a.distance_squared) != float(b.distance_squared): return float(a.distance_squared) < float(b.distance_squared)
		if String(a.polygon_id) != String(b.polygon_id): return String(a.polygon_id) < String(b.polygon_id)
		return String(a.triangle_id) < String(b.triangle_id)
	)
	var owner: Dictionary = candidates[0]
	owner.erase("contains")
	return {"valid": true, "owner": owner, "candidate_count": candidates.size(), "selection_rule": "PATCH_CONTAINMENT_THEN_3D_CENTROID_DISTANCE_THEN_STABLE_IDS"}

## R6-C: canonical obligations may be represented by an exact anchor edge or
## by a deterministic mesh-edge path through derived support vertices.
func _validate_required_arcs(triangles: Array[Dictionary], arcs: Array, flips: Array) -> Dictionary:
	var incidence: Dictionary = _edge_incidence(triangles)
	var adjacency: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3: continue
		for i in range(3):
			var a: String = String(ids[i]); var b: String = String(ids[(i + 1) % 3])
			if not adjacency.has(a): adjacency[a] = {}
			if not adjacency.has(b): adjacency[b] = {}
			adjacency[a][b] = true; adjacency[b][a] = true
	var rows: Array[Dictionary] = []; var missing: Array[Dictionary] = []; var paths: Array[Dictionary] = []
	for arc_value in arcs:
		var arc: Dictionary = arc_value; var ids: Array = arc.get("root_ids", [])
		if ids.size() != 2: continue
		var start: String = String(ids[0]); var finish: String = String(ids[1]); var key: String = _edge_key(start, finish)
		var expected: int = int(arc.get("expected_incidence", 0)); var actual: int = int(incidence.get(key, 0))
		var path: Array[String] = []
		var method: String = ""
		if actual == expected and expected > 0:
			path = [start, finish]; method = "ANCHOR_EDGE"
		else:
			path = _r6_piecewise_arc_path(start, finish, adjacency, incidence, expected)
			if not path.is_empty(): method = "PIECEWISE_PATH"
		if path.is_empty():
			missing.append({"arc_id": arc.get("arc_id", ""), "root_ids": ids, "expected_incidence": expected, "actual_direct_incidence": actual})
			rows.append({"arc_id": arc.get("arc_id", ""), "method": "UNREALIZED", "valid": false})
			continue
		var position_rows: Array = []
		var position_bytes: Array = []
		var positions_valid: bool = true
		for root_id in path:
			var found: Variant = null
			for triangle in triangles:
				var tri_ids: Array = triangle.get("root_ids", []); var tri_points: Array = triangle.get("points", [])
				for i in range(mini(tri_ids.size(), tri_points.size())):
					if String(tri_ids[i]) == root_id: found = Vector3(tri_points[i]); break
				if found != null: break
			if found == null: positions_valid = false; break
			var p: Vector3 = Vector3(found); position_rows.append([p.x, p.y, p.z]); position_bytes.append(_position_bytes_hex(p))
		if not positions_valid:
			missing.append({"arc_id": arc.get("arc_id", ""), "reason": "path_vertex_position_missing"}); rows.append({"arc_id": arc.get("arc_id", ""), "method": "UNREALIZED", "valid": false}); continue
		var path_digest: String = Core.sha256(("|".join(path) + "|" + "|".join(position_bytes)).to_utf8_buffer())
		var path_row: Dictionary = {"arc_id": arc.get("arc_id", ""), "method": method, "canonical_root_ids": ids.duplicate(), "ordered_mesh_vertex_ids": path, "ordered_positions": position_rows, "position_f32_hex": position_bytes, "path_sha256": path_digest, "valid": true}
		paths.append(path_row); rows.append({"arc_id": arc.get("arc_id", ""), "method": method, "valid": true, "path_sha256": path_digest, "edge_count": path.size() - 1})
	var intersection_audit: Dictionary = _r6_arc_paths_intersection_audit(paths)
	return {"valid": missing.is_empty() and bool(intersection_audit.get("valid", false)), "missing": missing.size(), "nonmanifold": 0, "rows": rows, "missing_rows": missing, "paths": paths, "intersection_audit": intersection_audit}

func _r6_piecewise_arc_path(start: String, finish: String, adjacency: Dictionary, incidence: Dictionary, expected: int) -> Array[String]:
	if not adjacency.has(start) or not adjacency.has(finish): return []
	var queue: Array[Array] = [[start]]; var visited: Dictionary = {start: true}
	while not queue.is_empty():
		var path: Array = queue.pop_front(); var tail: String = String(path.back())
		var neighbors: Array = adjacency.get(tail, {}).keys(); neighbors.sort()
		for neighbor_value in neighbors:
			var neighbor: String = String(neighbor_value); var edge_incidence: int = int(incidence.get(_edge_key(tail, neighbor), 0))
			if edge_incidence != expected or expected < 1 or expected > 2: continue
			if neighbor != finish and not neighbor.begins_with("R5SUP_"): continue
			if neighbor == finish:
				var result: Array[String] = []
				for node in path:
					result.append(String(node))
				result.append(finish)
				if result.size() >= 3: return result
			elif not visited.has(neighbor):
				visited[neighbor] = true; var next_path: Array = path.duplicate(); next_path.append(neighbor); queue.append(next_path)
	return []

func _r6_arc_paths_intersection_audit(paths: Array[Dictionary]) -> Dictionary:
	var checked: int = 0; var failures: Array[Dictionary] = []
	for i in range(paths.size()):
		for j in range(i + 1, paths.size()):
			var ids_a: Array = paths[i].ordered_mesh_vertex_ids; var ids_b: Array = paths[j].ordered_mesh_vertex_ids
			for index_a in range(1, ids_a.size() - 1):
				for index_b in range(1, ids_b.size() - 1):
					if String(ids_a[index_a]) == String(ids_b[index_b]): failures.append({"arc_a": paths[i].arc_id, "arc_b": paths[j].arc_id, "shared_derived_vertex_id": ids_a[index_a], "reason": "topology_paths_merge_at_derived_vertex"})
			var a: Array = paths[i].ordered_positions; var b: Array = paths[j].ordered_positions
			for ai in range(a.size() - 1):
				for bi in range(b.size() - 1):
					var a0: Vector3 = Vector3(a[ai][0], a[ai][1], a[ai][2]); var a1: Vector3 = Vector3(a[ai + 1][0], a[ai + 1][1], a[ai + 1][2])
					var b0: Vector3 = Vector3(b[bi][0], b[bi][1], b[bi][2]); var b1: Vector3 = Vector3(b[bi + 1][0], b[bi + 1][1], b[bi + 1][2])
					if a0 == b0 or a0 == b1 or a1 == b0 or a1 == b1: continue
					checked += 1
					if _r6_segment_distance_squared(a0, a1, b0, b1) <= 1.0e-16: failures.append({"arc_a": paths[i].arc_id, "arc_b": paths[j].arc_id, "segment_a": ai, "segment_b": bi})
	return {"valid": failures.is_empty(), "checked_segment_pairs": checked, "failures": failures}

func _r6_segment_distance_squared(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1: Vector3 = q1 - p1; var d2: Vector3 = q2 - p2; var r: Vector3 = p1 - p2
	var a: float = d1.dot(d1); var e: float = d2.dot(d2); var f: float = d2.dot(r); var s: float = 0.0; var t: float = 0.0
	if a <= 1.0e-30 and e <= 1.0e-30: return p1.distance_squared_to(p2)
	if a <= 1.0e-30: t = clampf(f / e, 0.0, 1.0)
	else:
		var c: float = d1.dot(r)
		if e <= 1.0e-30: s = clampf(-c / a, 0.0, 1.0)
		else:
			var b: float = d1.dot(d2); var denom: float = a * e - b * b
			if absf(denom) > 1.0e-30: s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0: t = 0.0; s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0: t = 1.0; s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_squared_to(p2 + d2 * t)
