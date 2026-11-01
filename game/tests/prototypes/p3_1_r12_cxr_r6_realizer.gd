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
			"original_barycentric_gate_pass": before.get("barycentric_gate_pass", false),
			"original_residual_gate_pass": before.get("residual_gate_pass", false),
			"corrected_position": corrected,
			"corrected_position_f32_hex": _position_bytes_hex(corrected),
			"corrected_barycentric_weights": selected.get("weights", []),
			"corrected_field_residual": selected.get("field_residual", "UNKNOWN_NOT_CAPTURED"),
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
				if not bool(evaluation.get("accepted", false)):
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
	best["search_state"] = "corrected_within_plus_minus_2_ulp_per_coordinate"
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
