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

func _search_representable_zero_axis_bracket(original: Vector3, tet_data: Dictionary) -> Dictionary:
	var origin_eval: Dictionary = _evaluate_zero_point(original, tet_data)
	var origin_residual: float = float(origin_eval.get("field_residual", NAN))
	var positions: Array = tet_data.get("positions", [])
	if positions.size() != 4 or not is_finite(origin_residual):
		origin_eval["position"] = original
		origin_eval["search_state"] = "axis_bracket_tetra_or_residual_invalid"
		origin_eval["reason"] = "R6_X6_AXIS_BRACKET_SOURCE_INVALID"
		return origin_eval
	var best: Dictionary = {}
	var best_residual: float = INF
	var best_step_count: int = 2147483647
	var original_bytes: PackedByteArray = PackedFloat32Array([original.x, original.y, original.z]).to_byte_array()
	var original_bits: Array[int] = [int(original_bytes.decode_u32(0)), int(original_bytes.decode_u32(4)), int(original_bytes.decode_u32(8))]
	for axis in range(3):
		var minimum: float = INF
		var maximum: float = -INF
		for corner_value in positions:
			var corner: Vector3 = Vector3(corner_value)
			var coordinate: float = corner.x if axis == 0 else corner.y if axis == 1 else corner.z
			minimum = minf(minimum, coordinate)
			maximum = maxf(maximum, coordinate)
		for direction in [-1, 1]:
			var start_key: int = _ordered_float32_key(original_bits[axis])
			var end_value: float = minimum if direction < 0 else maximum
			var end_bytes: PackedByteArray = PackedFloat32Array([end_value]).to_byte_array()
			var end_key: int = _ordered_float32_key(int(end_bytes.decode_u32(0)))
			var max_steps: int = absi(end_key - start_key)
			if max_steps <= 0: continue
			var legal_steps: int = 0
			var illegal_steps: int = max_steps
			while legal_steps + 1 < illegal_steps:
				var middle: int = legal_steps + (illegal_steps - legal_steps) / 2
				var probe: Vector3 = _axis_step_point(original, axis, direction * middle)
				var probe_eval: Dictionary = _evaluate_zero_point(probe, tet_data)
				if bool(probe_eval.get("barycentric_gate_pass", false)): legal_steps = middle
				else: illegal_steps = middle
			var end_point: Vector3 = _axis_step_point(original, axis, direction * legal_steps)
			var end_eval: Dictionary = _evaluate_zero_point(end_point, tet_data)
			if not bool(end_eval.get("barycentric_gate_pass", false)): continue
			var end_residual: float = float(end_eval.get("field_residual", NAN))
			var candidates: Array[Dictionary] = [end_eval.duplicate(true)]
			candidates[0]["position"] = end_point
			candidates[0]["ulp_steps"] = [direction * legal_steps if axis == 0 else 0, direction * legal_steps if axis == 1 else 0, direction * legal_steps if axis == 2 else 0]
			if is_finite(end_residual) and signf(end_residual) != signf(origin_residual):
				var same_sign_step: int = 0
				var opposite_sign_step: int = legal_steps
				while same_sign_step + 1 < opposite_sign_step:
					var middle: int = same_sign_step + (opposite_sign_step - same_sign_step) / 2
					var probe: Vector3 = _axis_step_point(original, axis, direction * middle)
					var probe_eval: Dictionary = _evaluate_zero_point(probe, tet_data)
					var probe_residual: float = float(probe_eval.get("field_residual", NAN))
					if not bool(probe_eval.get("barycentric_gate_pass", false)) or not is_finite(probe_residual):
						break
					probe_eval["position"] = probe
					probe_eval["ulp_steps"] = [direction * middle if axis == 0 else 0, direction * middle if axis == 1 else 0, direction * middle if axis == 2 else 0]
					candidates.append(probe_eval)
					if signf(probe_residual) == signf(origin_residual): same_sign_step = middle
					else: opposite_sign_step = middle
					if bool(probe_eval.get("accepted", false)): break
					var adjacent: int = same_sign_step + 1
					var adjacent_point: Vector3 = _axis_step_point(original, axis, direction * adjacent)
					var adjacent_eval: Dictionary = _evaluate_zero_point(adjacent_point, tet_data)
					adjacent_eval["position"] = adjacent_point
					adjacent_eval["ulp_steps"] = [direction * adjacent if axis == 0 else 0, direction * adjacent if axis == 1 else 0, direction * adjacent if axis == 2 else 0]
					candidates.append(adjacent_eval)
			for candidate in candidates:
				if not bool(candidate.get("accepted", false)): continue
				var residual_abs: float = absf(float(candidate.get("field_residual", INF)))
				var steps: Array = candidate.get("ulp_steps", [0, 0, 0])
				var step_count: int = absi(int(steps[0])) + absi(int(steps[1])) + absi(int(steps[2]))
				if step_count < best_step_count or (step_count == best_step_count and residual_abs < best_residual):
					best = candidate.duplicate(true)
					best_residual = residual_abs
					best_step_count = step_count
	if best.is_empty():
		origin_eval["position"] = original
		origin_eval["ulp_steps"] = [0, 0, 0]
		origin_eval["search_state"] = "no_accepted_root_on_any_full_same_tetra_axis_interval"
		origin_eval["reason"] = "R6_X6_AXIS_BRACKET_NO_ACCEPTED_POINT"
		return origin_eval
	best["search_state"] = "accepted_via_full_same_tetra_axis_interval_bracket"
	best["reason"] = "R6_X6_AXIS_BRACKET_MINIMUM_ULP_STEP_COUNT_THEN_MINIMUM_RESIDUAL"
	return best

func _ordered_float32_key(bits: int) -> int:
	return (~bits) & 0xffffffff if (bits & 0x80000000) != 0 else bits | 0x80000000

func _float_from_ordered_key(key: int) -> float:
	var bits: int = key & 0x7fffffff if (key & 0x80000000) != 0 else (~key) & 0xffffffff
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, bits)
	return bytes.decode_float(0)

## Enumerates a deterministic Chebyshev shell around the requested binary32
## point. Every representable triple inside the tetrahedron's coordinate AABB
## is visited exactly once if this finite search reaches max_radius. Resource
## interruption returns PARTIAL_LIMIT with the next shell/offset preserved.
func _derive_tetra_affine_field(tet_data: Dictionary) -> Dictionary:
	var positions: Array = tet_data.get("positions", [])
	var samples: Array = tet_data.get("samples", [])
	if positions.size() != 4 or samples.size() != 4:
		return {"valid": false, "reason": "AFFINE_TETRA_SCHEMA_INVALID"}
	var p0: Vector3 = Vector3(positions[0])
	var a: Vector3 = Vector3(positions[1]) - p0
	var b: Vector3 = Vector3(positions[2]) - p0
	var c: Vector3 = Vector3(positions[3]) - p0
	var determinant: float = a.dot(b.cross(c))
	if not is_finite(determinant) or absf(determinant) <= 1.0e-20:
		return {"valid": false, "reason": "AFFINE_TETRA_SINGULAR"}
	var g1: Vector3 = b.cross(c) / determinant
	var g2: Vector3 = c.cross(a) / determinant
	var g3: Vector3 = a.cross(b) / determinant
	var s0: float = float(samples[0])
	var gradient: Vector3 = g1 * (float(samples[1]) - s0) + g2 * (float(samples[2]) - s0) + g3 * (float(samples[3]) - s0)
	var offset: float = s0 - gradient.dot(p0)
	if not gradient.is_finite() or not is_finite(offset):
		return {"valid": false, "reason": "AFFINE_TETRA_COEFFICIENT_NONFINITE"}
	var matrix_norm: float = maxf(absf(a.x) + absf(b.x) + absf(c.x), maxf(absf(a.y) + absf(b.y) + absf(c.y), absf(a.z) + absf(b.z) + absf(c.z)))
	var inverse_norm: float = maxf(absf(g1.x) + absf(g1.y) + absf(g1.z), maxf(absf(g2.x) + absf(g2.y) + absf(g2.z), absf(g3.x) + absf(g3.y) + absf(g3.z)))
	var condition_estimate: float = maxf(1.0, matrix_norm * inverse_norm)
	return {"valid": true, "coefficients": [gradient.x, gradient.y, gradient.z, offset], "gradient": gradient, "offset": offset, "determinant": determinant, "condition_estimate": condition_estimate}

func _ordered_float32_key_at(value: float) -> int:
	var bytes: PackedByteArray = PackedFloat32Array([value]).to_byte_array()
	return _ordered_float32_key(int(bytes.decode_u32(0)))

func _float32_key_ceil(value: float) -> int:
	var key: int = _ordered_float32_key_at(value)
	if _float_from_ordered_key(key) < value: key += 1
	return key

func _float32_key_floor(value: float) -> int:
	var key: int = _ordered_float32_key_at(value)
	if _float_from_ordered_key(key) > value: key -= 1
	return key

func _clip_binary32_search_window(tet_data: Dictionary, minimum_keys: Array[int], maximum_keys: Array[int]) -> Dictionary:
	var window_min: Variant = tet_data.get("binary32_window_minimum_ordered_float32_keys", null)
	var window_max: Variant = tet_data.get("binary32_window_maximum_ordered_float32_keys", null)
	if window_min == null and window_max == null: return {"valid": true, "empty": false, "minimum": minimum_keys, "maximum": maximum_keys}
	if not (window_min is Array) or not (window_max is Array) or window_min.size() != 3 or window_max.size() != 3:
		return {"valid": false, "reason": "BINARY32_SEARCH_WINDOW_SCHEMA_INVALID"}
	var clipped_min: Array[int] = minimum_keys.duplicate()
	var clipped_max: Array[int] = maximum_keys.duplicate()
	for axis in range(3):
		clipped_min[axis] = maxi(clipped_min[axis], int(window_min[axis]))
		clipped_max[axis] = mini(clipped_max[axis], int(window_max[axis]))
		if clipped_min[axis] > clipped_max[axis]: return {"valid": true, "empty": true, "minimum": clipped_min, "maximum": clipped_max}
	return {"valid": true, "empty": false, "minimum": clipped_min, "maximum": clipped_max}

func _affine_barycentric_interval(point: Vector3, axis: int, lower: float, upper: float, positions: Array, condition_estimate: float = 1.0) -> Dictionary:
	var p0: Vector3 = point
	var p1: Vector3 = point
	if axis == 0: p0.x = 0.0; p1.x = 1.0
	elif axis == 1: p0.y = 0.0; p1.y = 1.0
	else: p0.z = 0.0; p1.z = 1.0
	var weights0: Array = _tetra_barycentric(p0, positions).get("weights", [])
	var weights1: Array = _tetra_barycentric(p1, positions).get("weights", [])
	if weights0.size() != 4 or weights1.size() != 4:
		return {"valid": false, "lower": lower, "upper": upper, "reason": "BARYCENTRIC_INTERVAL_UNAVAILABLE"}
	var lo: float = lower
	var hi: float = upper
	# This outward guard is prefilter-only; the unchanged exact gate is still
	# evaluated for every enumerated binary32 point.
	var guard: float = 512.0 * 5.960464477539063e-8 * maxf(1.0, condition_estimate)
	for index in range(4):
		var slope: float = float(weights1[index]) - float(weights0[index])
		var intercept: float = float(weights0[index])
		if absf(slope) <= 1.0e-30:
			if intercept < -R6_BARYCENTRIC_EPSILON - guard or intercept > 1.0 + R6_BARYCENTRIC_EPSILON + guard:
				return {"valid": true, "empty": true, "lower": 1.0, "upper": 0.0}
			continue
		var bound_a: float = (-R6_BARYCENTRIC_EPSILON - guard - intercept) / slope
		var bound_b: float = (1.0 + R6_BARYCENTRIC_EPSILON + guard - intercept) / slope
		lo = maxf(lo, minf(bound_a, bound_b))
		hi = minf(hi, maxf(bound_a, bound_b))
		if lo > hi: return {"valid": true, "empty": true, "lower": lo, "upper": hi}
	return {"valid": true, "empty": false, "lower": lo, "upper": hi}

func _legacy_binary32_point_precedes_frontier(keys: Array[int], frontier: Dictionary) -> bool:
	if not frontier.has("radius") or not frontier.has("dx") or not frontier.has("dy") or not frontier.has("dz"):
		return false
	var seed: Array = frontier.get("seed_ordered_float32_keys", [])
	if seed.size() != 3: return false
	var dx: int = keys[0] - int(seed[0])
	var dy: int = keys[1] - int(seed[1])
	var dz: int = keys[2] - int(seed[2])
	var radius: int = maxi(absi(dx), maxi(absi(dy), absi(dz)))
	var target_radius: int = int(frontier.radius)
	if radius != target_radius: return radius < target_radius
	var target_dx: int = int(frontier.dx)
	var target_dy: int = int(frontier.dy)
	var target_dz: int = int(frontier.dz)
	if dx != target_dx: return dx < target_dx
	if dy != target_dy: return dy < target_dy
	return dz < target_dz

func _search_representable_zero_multicoordinate(original: Vector3, tet_data: Dictionary, max_search_usec: int = 25000, acceptance_gate: Callable = Callable(), resume_frontier: Dictionary = {}) -> Dictionary:
	var positions: Array = tet_data.get("positions", [])
	if positions.size() != 4 or not original.is_finite():
		return {"position": original, "accepted": false, "search_state": "INVALID_TETRA_DOMAIN", "finite_domain_complete": false}
	var affine: Dictionary = _derive_tetra_affine_field(tet_data)
	if not bool(affine.get("valid", false)):
		var invalid: Dictionary = _evaluate_zero_point(original, tet_data)
		invalid["search_state"] = String(affine.get("reason", "AFFINE_TETRA_INVALID")); invalid["finite_domain_complete"] = false
		return invalid
	var coefficients: Array = affine.coefficients
	var gradient: Vector3 = affine.gradient
	var coeffs: Array[float] = [float(coefficients[0]), float(coefficients[1]), float(coefficients[2])]
	var dependent_axis: int = 0
	for axis in range(1, 3):
		if absf(coeffs[axis]) > absf(coeffs[dependent_axis]): dependent_axis = axis
	if absf(coeffs[dependent_axis]) <= 1.0e-30:
		var constant_eval: Dictionary = _evaluate_zero_point(original, tet_data)
		constant_eval["search_state"] = "CONSTANT_FIELD_REQUIRES_EXACT_SOURCE_CLASSIFICATION"
		constant_eval["finite_domain_complete"] = false
		constant_eval["affine_coefficients"] = coefficients
		return constant_eval
	var independent_axes: Array[int] = []
	for axis in range(3):
		if axis != dependent_axis: independent_axes.append(axis)
	var original_bytes: PackedByteArray = PackedFloat32Array([original.x, original.y, original.z]).to_byte_array()
	var original_keys: Array[int] = []
	var minimum_keys: Array[int] = [0xffffffff, 0xffffffff, 0xffffffff]
	var maximum_keys: Array[int] = [0, 0, 0]
	for axis in range(3): original_keys.append(_ordered_float32_key(int(original_bytes.decode_u32(axis * 4))))
	for position_value in positions:
		var corner: Vector3 = Vector3(position_value)
		var values: Array[float] = [corner.x, corner.y, corner.z]
		for axis in range(3):
			var key: int = _ordered_float32_key_at(values[axis])
			minimum_keys[axis] = mini(minimum_keys[axis], key); maximum_keys[axis] = maxi(maximum_keys[axis], key)
	var clipped_window: Dictionary = _clip_binary32_search_window(tet_data, minimum_keys, maximum_keys)
	if not bool(clipped_window.get("valid", false)):
		return {"position": original, "accepted": false, "search_state": "INVALID_BINARY32_SEARCH_WINDOW", "reason": clipped_window.get("reason", "UNKNOWN_NOT_CAPTURED"), "finite_domain_complete": false}
	minimum_keys = clipped_window.minimum; maximum_keys = clipped_window.maximum
	if bool(clipped_window.get("empty", false)):
		var empty_result: Dictionary = _evaluate_zero_point(original, tet_data); empty_result["accepted"] = false; empty_result["search_state"] = "EXHAUSTIVE_EMPTY_BINARY32_TEST_WINDOW"; empty_result["finite_domain_complete"] = true; empty_result["tested_triples"] = 0
		return empty_result
	var started: int = Time.get_ticks_usec()
	var tested: int = int(resume_frontier.get("tested_triples", 0))
	var skipped: int = int(resume_frontier.get("affine_skipped_candidates", 0))
	var gate_rejections: int = int(resume_frontier.get("acceptance_gate_rejection_count", 0))
	var cursor: Dictionary = resume_frontier.duplicate(true)
	var is_affine_resume: bool = int(cursor.get("affine_algorithm_version", 0)) == 1
	var has_legacy_resume: bool = not cursor.is_empty() and not is_affine_resume
	var next_radius: int = int(cursor.get("radius", 0)) if is_affine_resume else 0
	var next_du: int = int(cursor.get("du", 0)) if is_affine_resume else 0
	var next_dv: int = int(cursor.get("dv", 0)) if is_affine_resume else 0
	var next_w: int = int(cursor.get("w_key", minimum_keys[dependent_axis])) if is_affine_resume else minimum_keys[dependent_axis]
	var legacy_frontier: Dictionary = cursor if has_legacy_resume else cursor.get("legacy_resume_frontier", {})
	var has_legacy_frontier: bool = not legacy_frontier.is_empty()
	var skipped_legacy: int = int(cursor.get("legacy_points_skipped", 0))
	var origin_u: int = original_keys[independent_axes[0]]
	var origin_v: int = original_keys[independent_axes[1]]
	var u_min: int = minimum_keys[independent_axes[0]]; var u_max: int = maximum_keys[independent_axes[0]]
	var v_min: int = minimum_keys[independent_axes[1]]; var v_max: int = maximum_keys[independent_axes[1]]
	var minimum_radius: int = maxi(maxi(0, u_min - origin_u), maxi(origin_u - u_max, maxi(maxi(0, v_min - origin_v), origin_v - v_max)))
	var maximum_radius: int = maxi(maxi(absi(u_min - origin_u), absi(u_max - origin_u)), maxi(absi(v_min - origin_v), absi(v_max - origin_v)))
	var axis_candidate_counts: Array[int] = []
	for axis in range(3): axis_candidate_counts.append(maximum_keys[axis] - minimum_keys[axis] + 1)
	for radius in range(minimum_radius, maximum_radius + 1):
		var du_start: int = maxi(-radius, u_min - origin_u); var du_end: int = mini(radius, u_max - origin_u)
		for du in range(du_start, du_end + 1):
			var dv_start: int = maxi(-radius, v_min - origin_v); var dv_end: int = mini(radius, v_max - origin_v)
			for dv in range(dv_start, dv_end + 1):
				if maxi(absi(du), absi(dv)) != radius: continue
				if is_affine_resume and (radius < next_radius or (radius == next_radius and (du < next_du or (du == next_du and dv < next_dv)))): continue
				var u_key: int = origin_u + du; var v_key: int = origin_v + dv
				var u_value: float = _float_from_ordered_key(u_key)
				var v_value: float = _float_from_ordered_key(v_key)
				cursor = {"affine_algorithm_version": 1, "dependent_axis": dependent_axis, "independent_axes": independent_axes.duplicate(), "radius": radius, "du": du, "dv": dv, "w_key": minimum_keys[dependent_axis], "tested_triples": tested, "affine_skipped_candidates": skipped, "legacy_points_skipped": skipped_legacy, "acceptance_gate_rejection_count": gate_rejections, "legacy_resume_frontier": legacy_frontier, "seed_ordered_float32_keys": original_keys, "tetra_aabb_minimum_ordered_float32_keys": minimum_keys, "tetra_aabb_maximum_ordered_float32_keys": maximum_keys, "tetra_aabb_axis_candidate_counts": axis_candidate_counts, "minimum_radius": minimum_radius, "maximum_radius": maximum_radius, "remaining_domain_definition": "ordered Chebyshev shells over the two independent binary32 coordinates; every dependent-axis binary32 value in the conservative residual and barycentric interval is checked by unchanged exact gates"}
				if Time.get_ticks_usec() - started >= max_search_usec:
					return _affine_binary32_partial(original, tet_data, cursor, tested, skipped, skipped_legacy, gate_rejections)
				var base_point: Vector3 = original
				if independent_axes[0] == 0: base_point.x = u_value
				elif independent_axes[0] == 1: base_point.y = u_value
				else: base_point.z = u_value
				if independent_axes[1] == 0: base_point.x = v_value
				elif independent_axes[1] == 1: base_point.y = v_value
				else: base_point.z = v_value
				if dependent_axis == 0: base_point.x = 0.0
				elif dependent_axis == 1: base_point.y = 0.0
				else: base_point.z = 0.0
				var residual_base: float = float(coeffs[0]) * base_point.x + float(coeffs[1]) * base_point.y + float(coeffs[2]) * base_point.z + float(affine.offset)
				var dep_coeff: float = coeffs[dependent_axis]
				var sample_scale: float = absf(float(tet_data.samples[0])) + absf(float(tet_data.samples[1])) + absf(float(tet_data.samples[2])) + absf(float(tet_data.samples[3]))
				var residual_guard: float = 512.0 * 5.960464477539063e-8 * maxf(1.0, float(affine.condition_estimate)) * maxf(1.0, sample_scale)
				var residual_lo: float = (-R6_RESIDUAL_EPSILON - residual_guard - residual_base) / dep_coeff
				var residual_hi: float = (R6_RESIDUAL_EPSILON + residual_guard - residual_base) / dep_coeff
				var w_lo: float = maxf(minf(residual_lo, residual_hi), _float_from_ordered_key(minimum_keys[dependent_axis]))
				var w_hi: float = minf(maxf(residual_lo, residual_hi), _float_from_ordered_key(maximum_keys[dependent_axis]))
				var bary: Dictionary = _affine_barycentric_interval(base_point, dependent_axis, w_lo, w_hi, positions, float(affine.condition_estimate))
				if not bool(bary.get("valid", false)):
					var failed: Dictionary = _evaluate_zero_point(original, tet_data); failed["search_state"] = "PARTIAL_LIMIT"; failed["finite_domain_complete"] = false; failed["reason"] = "BARYCENTRIC_INTERVAL_UNAVAILABLE"; return failed
				var full_w_start: int = minimum_keys[dependent_axis]
				var full_w_end: int = maximum_keys[dependent_axis]
				var interval_w_count: int = 0
				if not bool(bary.get("empty", false)):
					w_lo = float(bary.lower); w_hi = float(bary.upper)
					var w_start: int = maxi(minimum_keys[dependent_axis], _float32_key_ceil(w_lo))
					var w_end: int = mini(maximum_keys[dependent_axis], _float32_key_floor(w_hi))
					interval_w_count = maxi(0, w_end - w_start + 1)
					if is_affine_resume and radius == next_radius and du == next_du and dv == next_dv: w_start = maxi(w_start, next_w)
					for w_key in range(w_start, w_end + 1):
						var keys: Array[int] = [0, 0, 0]; keys[independent_axes[0]] = u_key; keys[independent_axes[1]] = v_key; keys[dependent_axis] = w_key
						cursor = {"affine_algorithm_version": 1, "dependent_axis": dependent_axis, "independent_axes": independent_axes.duplicate(), "radius": radius, "du": du, "dv": dv, "w_key": w_key, "dependent_interval_size": interval_w_count, "tested_triples": tested, "affine_skipped_candidates": skipped, "legacy_points_skipped": skipped_legacy, "acceptance_gate_rejection_count": gate_rejections, "legacy_resume_frontier": legacy_frontier, "seed_ordered_float32_keys": original_keys, "tetra_aabb_minimum_ordered_float32_keys": minimum_keys, "tetra_aabb_maximum_ordered_float32_keys": maximum_keys, "tetra_aabb_axis_candidate_counts": axis_candidate_counts, "minimum_radius": minimum_radius, "maximum_radius": maximum_radius, "remaining_domain_definition": "ordered independent-axis binary32 shell and inclusive dependent-axis interval; unchanged exact gates per candidate"}
						if Time.get_ticks_usec() - started >= max_search_usec:
							return _affine_binary32_partial(original, tet_data, cursor, tested, skipped, skipped_legacy, gate_rejections)
						if has_legacy_frontier and _legacy_binary32_point_precedes_frontier(keys, legacy_frontier):
							skipped += 1; skipped_legacy += 1; continue
						var candidate: Vector3 = Vector3(_float_from_ordered_key(keys[0]), _float_from_ordered_key(keys[1]), _float_from_ordered_key(keys[2]))
						var evaluation: Dictionary = _evaluate_zero_point(candidate, tet_data); tested += 1
						if not bool(evaluation.get("accepted", false)): continue
						if acceptance_gate.is_valid() and not bool(acceptance_gate.call(candidate)):
							gate_rejections += 1; continue
						evaluation["position"] = candidate; evaluation["ulp_steps"] = [keys[0] - original_keys[0], keys[1] - original_keys[1], keys[2] - original_keys[2]]
						evaluation["search_state"] = "AFFINE_BINARY32_WITNESS"; evaluation["finite_domain_complete"] = false
						evaluation["search_frontier"] = cursor; evaluation["tested_triples"] = tested; evaluation["affine_skipped_candidates"] = skipped; evaluation["legacy_points_skipped"] = skipped_legacy; evaluation["acceptance_gate_rejection_count"] = gate_rejections; evaluation["affine_coefficients"] = coefficients; evaluation["dependent_axis"] = dependent_axis
						evaluation["affine_algorithm_version"] = 1; evaluation["minimum_radius"] = minimum_radius; evaluation["maximum_radius"] = maximum_radius
						return evaluation
				skipped += maxi(0, full_w_end - full_w_start + 1 - interval_w_count)
	var exhausted: Dictionary = _evaluate_zero_point(original, tet_data)
	exhausted["position"] = original; exhausted["search_state"] = "EXHAUSTIVE_NO_VALID_REPRESENTABLE_SUPPORT_IN_TETRA_DOMAIN"; exhausted["finite_domain_complete"] = true
	exhausted["tested_triples"] = tested; exhausted["affine_skipped_candidates"] = skipped; exhausted["legacy_points_skipped"] = skipped_legacy; exhausted["acceptance_gate_rejection_count"] = gate_rejections; exhausted["affine_coefficients"] = coefficients; exhausted["dependent_axis"] = dependent_axis
	exhausted["affine_algorithm_version"] = 1; exhausted["minimum_radius"] = minimum_radius; exhausted["maximum_radius"] = maximum_radius
	return exhausted

func _affine_binary32_partial(original: Vector3, tet_data: Dictionary, frontier: Dictionary, tested: int, skipped: int, skipped_legacy: int, gate_rejections: int) -> Dictionary:
	var partial: Dictionary = _evaluate_zero_point(original, tet_data); partial["position"] = original; partial["accepted"] = false
	partial["search_state"] = "PARTIAL_LIMIT"; partial["finite_domain_complete"] = false; partial["search_frontier"] = frontier.duplicate(true)
	partial["tested_triples"] = tested; partial["affine_skipped_candidates"] = skipped; partial["legacy_points_skipped"] = skipped_legacy; partial["acceptance_gate_rejection_count"] = gate_rejections; partial["reason"] = "AFFINE_BINARY32_SEARCH_TIME_LIMIT"
	partial["affine_algorithm_version"] = int(frontier.get("affine_algorithm_version", 1)); partial["dependent_axis"] = frontier.get("dependent_axis", -1); partial["minimum_radius"] = frontier.get("minimum_radius", -1); partial["maximum_radius"] = frontier.get("maximum_radius", -1)
	return partial

func _search_representable_zero_multicoordinate_legacy(original: Vector3, tet_data: Dictionary, max_search_usec: int = 25000, acceptance_gate: Callable = Callable(), resume_frontier: Dictionary = {}) -> Dictionary:
	var positions: Array = tet_data.get("positions", [])
	if positions.size() != 4 or not original.is_finite():
		return {"position": original, "accepted": false, "search_state": "INVALID_TETRA_DOMAIN", "finite_domain_complete": false}
	var original_bytes: PackedByteArray = PackedFloat32Array([original.x, original.y, original.z]).to_byte_array()
	var original_keys: Array[int] = []
	var minimum_keys: Array[int] = [0xffffffff, 0xffffffff, 0xffffffff]
	var maximum_keys: Array[int] = [0, 0, 0]
	for axis in range(3):
		original_keys.append(_ordered_float32_key(int(original_bytes.decode_u32(axis * 4))))
	for position_value in positions:
		var corner: Vector3 = Vector3(position_value)
		var coordinates: Array[float] = [corner.x, corner.y, corner.z]
		for axis in range(3):
			var corner_bytes: PackedByteArray = PackedFloat32Array([coordinates[axis]]).to_byte_array()
			var key: int = _ordered_float32_key(int(corner_bytes.decode_u32(0)))
			minimum_keys[axis] = mini(minimum_keys[axis], key)
			maximum_keys[axis] = maxi(maximum_keys[axis], key)
	var clipped_window: Dictionary = _clip_binary32_search_window(tet_data, minimum_keys, maximum_keys)
	if not bool(clipped_window.get("valid", false)):
		return {"position": original, "accepted": false, "search_state": "INVALID_BINARY32_SEARCH_WINDOW", "reason": clipped_window.get("reason", "UNKNOWN_NOT_CAPTURED"), "finite_domain_complete": false}
	minimum_keys = clipped_window.minimum; maximum_keys = clipped_window.maximum
	if bool(clipped_window.get("empty", false)):
		var empty_result: Dictionary = _evaluate_zero_point(original, tet_data); empty_result["accepted"] = false; empty_result["search_state"] = "EXHAUSTIVE_EMPTY_BINARY32_TEST_WINDOW"; empty_result["finite_domain_complete"] = true; empty_result["tested_triples"] = 0
		return empty_result
	var maximum_radius: int = 0
	var minimum_radius: int = 0
	for axis in range(3):
		maximum_radius = maxi(maximum_radius, maxi(absi(original_keys[axis] - minimum_keys[axis]), absi(maximum_keys[axis] - original_keys[axis])))
		if original_keys[axis] < minimum_keys[axis]: minimum_radius = maxi(minimum_radius, minimum_keys[axis] - original_keys[axis])
		elif original_keys[axis] > maximum_keys[axis]: minimum_radius = maxi(minimum_radius, original_keys[axis] - maximum_keys[axis])
	var started_usec: int = Time.get_ticks_usec()
	var tested: int = int(resume_frontier.get("tested_triples", 0))
	var acceptance_rejection_count: int = 0
	var frontier: Dictionary = resume_frontier.duplicate(true) if not resume_frontier.is_empty() else {"stage": "shell", "radius": minimum_radius, "dx": -minimum_radius, "dy": -minimum_radius, "dz": -minimum_radius, "tested_triples": 0}
	var axis_candidate_counts: Array[int] = []
	for axis in range(3): axis_candidate_counts.append(maximum_keys[axis] - minimum_keys[axis] + 1)
	frontier["seed_world_position"] = [original.x, original.y, original.z]
	frontier["seed_ordered_float32_keys"] = original_keys.duplicate()
	frontier["tetra_aabb_minimum_ordered_float32_keys"] = minimum_keys.duplicate()
	frontier["tetra_aabb_maximum_ordered_float32_keys"] = maximum_keys.duplicate()
	frontier["tetra_aabb_axis_candidate_counts"] = axis_candidate_counts
	frontier["minimum_radius"] = minimum_radius
	frontier["maximum_radius"] = maximum_radius
	frontier["remaining_domain_definition"] = "all ordered-binary32 xyz triples in the inclusive tetra coordinate AABB, at or after this deterministic Chebyshev-shell (radius,dx,dy,dz) cursor, each checked against same-tetra barycentric/residual gates and the unchanged complete support acceptance gate"
	var resume_radius: int = int(frontier.get("radius", 0))
	var resume_dx: int = int(frontier.get("dx", -resume_radius))
	var resume_dy: int = int(frontier.get("dy", -resume_radius))
	var resume_dz: int = int(frontier.get("dz", -resume_radius))
	var resume_active: bool = not resume_frontier.is_empty()
	# If the seed is outside the tetrahedron AABB, every shell below this exact
	# ordered-float32 distance is empty. Skipping those shells preserves the
	# Chebyshev ordering and finite-domain completeness while avoiding millions
	# of iterations that cannot contain a candidate.
	if resume_active and resume_radius < minimum_radius:
		resume_active = false
		frontier = {"stage": "shell", "radius": minimum_radius, "dx": -minimum_radius, "dy": -minimum_radius, "dz": -minimum_radius, "tested_triples": tested}
	for radius in range(minimum_radius, maximum_radius + 1):
		if resume_active and radius < resume_radius: continue
		frontier = {"stage": "shell", "radius": radius, "dx": -radius, "dy": -radius, "dz": -radius, "tested_triples": tested}
		if resume_active and radius == resume_radius and _binary32_frontier_before(radius, -radius, -radius, -radius, resume_radius, resume_dx, resume_dy, resume_dz):
			frontier = resume_frontier.duplicate(true)
		if Time.get_ticks_usec() - started_usec >= max_search_usec:
			return _binary32_search_partial(original, tet_data, _binary32_frontier_with_domain(frontier, original, original_keys, minimum_keys, maximum_keys, minimum_radius, maximum_radius), maximum_radius, tested, acceptance_rejection_count)
		var dx_start: int = maxi(-radius, minimum_keys[0] - original_keys[0])
		var dx_end: int = mini(radius, maximum_keys[0] - original_keys[0])
		for dx in range(dx_start, dx_end + 1):
			if resume_active and radius == resume_radius and dx < resume_dx: continue
			var dy_start: int = maxi(-radius, minimum_keys[1] - original_keys[1])
			var dy_end: int = mini(radius, maximum_keys[1] - original_keys[1])
			var dz_start: int = maxi(-radius, minimum_keys[2] - original_keys[2])
			var dz_end: int = mini(radius, maximum_keys[2] - original_keys[2])
			frontier = {"stage": "x_offset", "radius": radius, "dx": dx, "dy": dy_start, "dz": dz_start, "tested_triples": tested}
			if Time.get_ticks_usec() - started_usec >= max_search_usec:
				return _binary32_search_partial(original, tet_data, _binary32_frontier_with_domain(frontier, original, original_keys, minimum_keys, maximum_keys, minimum_radius, maximum_radius), maximum_radius, tested, acceptance_rejection_count)
			var x_key: int = original_keys[0] + dx
			for dy in range(dy_start, dy_end + 1):
				if resume_active and radius == resume_radius and dx == resume_dx and dy < resume_dy: continue
				frontier = {"stage": "y_offset", "radius": radius, "dx": dx, "dy": dy, "dz": dz_start, "tested_triples": tested}
				if Time.get_ticks_usec() - started_usec >= max_search_usec:
					return _binary32_search_partial(original, tet_data, _binary32_frontier_with_domain(frontier, original, original_keys, minimum_keys, maximum_keys, minimum_radius, maximum_radius), maximum_radius, tested, acceptance_rejection_count)
				var y_key: int = original_keys[1] + dy
				var z_offsets: Array[int] = []
				if maxi(absi(dx), absi(dy)) == radius:
					for dz_shell in range(dz_start, dz_end + 1): z_offsets.append(dz_shell)
				else:
					if -radius >= dz_start and -radius <= dz_end: z_offsets.append(-radius)
					if radius >= dz_start and radius <= dz_end: z_offsets.append(radius)
				for dz in z_offsets:
					if resume_active and radius == resume_radius and dx == resume_dx and dy == resume_dy and dz < resume_dz: continue
					var z_key: int = original_keys[2] + dz
					frontier = {"radius": radius, "dx": dx, "dy": dy, "dz": dz, "tested_triples": tested}
					resume_active = false
					if Time.get_ticks_usec() - started_usec >= max_search_usec:
						return _binary32_search_partial(original, tet_data, _binary32_frontier_with_domain(frontier, original, original_keys, minimum_keys, maximum_keys, minimum_radius, maximum_radius), maximum_radius, tested, acceptance_rejection_count)
					var candidate: Vector3 = Vector3(_float_from_ordered_key(x_key), _float_from_ordered_key(y_key), _float_from_ordered_key(z_key))
					var evaluation: Dictionary = _evaluate_zero_point(candidate, tet_data)
					tested += 1
					if bool(evaluation.get("accepted", false)):
						if acceptance_gate.is_valid() and not bool(acceptance_gate.call(candidate)):
							acceptance_rejection_count += 1
							continue
						evaluation["position"] = candidate
						evaluation["ulp_steps"] = [dx, dy, dz]
						evaluation["search_state"] = "MULTICOORDINATE_BINARY32_WITNESS"
						evaluation["finite_domain_complete"] = false
						evaluation["search_frontier"] = _binary32_frontier_with_domain(frontier, original, original_keys, minimum_keys, maximum_keys, minimum_radius, maximum_radius)
						evaluation["tested_triples"] = tested
						evaluation["acceptance_gate_rejection_count"] = acceptance_rejection_count
						return evaluation
	var exhausted: Dictionary = _evaluate_zero_point(original, tet_data)
	exhausted["position"] = original
	exhausted["search_state"] = "EXHAUSTED_NO_VALID_BINARY32_POINT_IN_TETRA_AABB"
	exhausted["finite_domain_complete"] = true
	exhausted["maximum_radius"] = maximum_radius
	exhausted["tested_triples"] = tested
	exhausted["acceptance_gate_rejection_count"] = acceptance_rejection_count
	exhausted["reason"] = "EXHAUSTIVE_MULTICOORDINATE_BINARY32_TETRA_DOMAIN"
	return exhausted

func _binary32_frontier_before(radius: int, dx: int, dy: int, dz: int, target_radius: int, target_dx: int, target_dy: int, target_dz: int) -> bool:
	if radius != target_radius: return radius < target_radius
	if dx != target_dx: return dx < target_dx
	if dy != target_dy: return dy < target_dy
	return dz < target_dz

func _binary32_frontier_with_domain(frontier: Dictionary, original: Vector3, original_keys: Array[int], minimum_keys: Array[int], maximum_keys: Array[int], minimum_radius: int, maximum_radius: int) -> Dictionary:
	var axis_candidate_counts: Array[int] = []
	for axis in range(3): axis_candidate_counts.append(maximum_keys[axis] - minimum_keys[axis] + 1)
	var result: Dictionary = frontier.duplicate(true)
	result["seed_world_position"] = [original.x, original.y, original.z]
	result["seed_ordered_float32_keys"] = original_keys.duplicate()
	result["tetra_aabb_minimum_ordered_float32_keys"] = minimum_keys.duplicate()
	result["tetra_aabb_maximum_ordered_float32_keys"] = maximum_keys.duplicate()
	result["tetra_aabb_axis_candidate_counts"] = axis_candidate_counts
	result["minimum_radius"] = minimum_radius
	result["maximum_radius"] = maximum_radius
	result["remaining_domain_definition"] = "all ordered-binary32 xyz triples in the inclusive tetra coordinate AABB, at or after this deterministic Chebyshev-shell (radius,dx,dy,dz) cursor, each checked against same-tetra barycentric/residual gates and the unchanged complete support acceptance gate"
	return result

func _binary32_search_partial(original: Vector3, tet_data: Dictionary, frontier: Dictionary, maximum_radius: int, tested: int, acceptance_rejection_count: int) -> Dictionary:
	var partial: Dictionary = _evaluate_zero_point(original, tet_data)
	partial["position"] = original
	# A valid seed only proves field representability. It has not passed the
	# candidate acceptance gate and must never escape as a numeric witness.
	partial["accepted"] = false
	partial["search_state"] = "PARTIAL_LIMIT"
	partial["finite_domain_complete"] = false
	partial["search_frontier"] = frontier.duplicate(true)
	partial["maximum_radius"] = maximum_radius
	partial["tested_triples"] = tested
	partial["acceptance_gate_rejection_count"] = acceptance_rejection_count
	partial["reason"] = "MULTICOORDINATE_FLOAT32_SEARCH_TIME_LIMIT"
	return partial

func _axis_step_point(original: Vector3, axis: int, step: int) -> Vector3:
	var point: Vector3 = original
	var original_value: float = original.x if axis == 0 else original.y if axis == 1 else original.z
	var bytes: PackedByteArray = PackedFloat32Array([original_value]).to_byte_array()
	var key: int = _ordered_float32_key(int(bytes.decode_u32(0)))
	var stepped: float = _float_from_ordered_key(key + step)
	if axis == 0: point.x = stepped
	elif axis == 1: point.y = stepped
	else: point.z = stepped
	return point

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
