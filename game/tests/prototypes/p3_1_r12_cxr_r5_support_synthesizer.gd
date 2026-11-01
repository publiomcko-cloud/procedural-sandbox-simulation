extends RefCounted

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")

const MAX_TETRAHEDRA: int = 3072
const MAX_ZERO_FACETS: int = 6144
const MAX_CLIP_FRAGMENTS: int = 32768
const MAX_RAW_SUPPORTS: int = 4096
const MAX_SUPPORTS: int = 64
const MAX_SYNTHESIS_USEC: int = 30000000
const MAX_BOUNDARY_SOURCE_PAIRS: int = 15
const MAX_WITNESSES_PER_CLIPPED_FRAGMENT: int = 7
const FROZEN_CROSS_SQUARED_CUTOFF: float = 1.0e-12

func synthesize(realizer: RefCounted, values: PackedFloat32Array, roi: Dictionary, context: Dictionary, residual_triangles: Array, cavity_id: String) -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var limits: Dictionary = realizer.call("_cxr_limits")
	var cutoff: float = float(limits.get("cross_squared_cutoff", NAN))
	if not is_finite(cutoff) or cutoff != FROZEN_CROSS_SQUARED_CUTOFF:
		return {"valid": false, "reason": "frozen_cutoff_contract_mismatch", "observed_cutoff": cutoff}
	var max_support_distance: float = float(limits.get("max_support_distance", NAN))
	var residual_epsilon: float = float(limits.get("field_residual_epsilon", NAN))
	var barycentric_epsilon: float = float(limits.get("barycentric_epsilon", NAN))
	if not is_finite(max_support_distance) or max_support_distance <= 0.0 or not is_finite(residual_epsilon) or residual_epsilon <= 0.0 or not is_finite(barycentric_epsilon) or barycentric_epsilon <= 0.0:
		return {"valid": false, "reason": "existing_r4_support_limits_unavailable"}
	if values.is_empty() or roi.is_empty() or context.is_empty() or residual_triangles.is_empty():
		return {"valid": false, "reason": "synthesis_input_missing"}
	var roi_min: Vector3 = Core.world_min(roi)
	var cells: Vector3i = Core.cell_counts(roi)
	var step: float = Core.step(roi)
	var dims: Vector3i = cells + Vector3i.ONE
	if not roi_min.is_finite() or not is_finite(step) or step <= 0.0 or values.size() != dims.x * dims.y * dims.z:
		return {"valid": false, "reason": "volume_grid_identity_invalid", "dimensions": dims, "value_count": values.size()}
	var tetra_count: int = cells.x * cells.y * cells.z * Core.TETS.size()
	if tetra_count != MAX_TETRAHEDRA:
		return {"valid": false, "reason": "frozen_tetrahedron_domain_changed", "observed": tetra_count, "expected": MAX_TETRAHEDRA}
	var polygon: Array[Vector2] = context.get("polygon", [])
	var boundary_ids: Array[String] = []
	for id_value in context.get("cycle", context.get("boundary_cycle", [])): boundary_ids.append(String(id_value))
	boundary_ids.sort()
	var possible_source_pairs: int = boundary_ids.size() * maxi(0, boundary_ids.size() - 1) / 2
	if polygon.size() != 6 or boundary_ids.size() != 6 or possible_source_pairs != MAX_BOUNDARY_SOURCE_PAIRS:
		return {"valid": false, "reason": "cavity_polygon_or_boundary_invalid"}
	var triangulation: PackedInt32Array = Geometry2D.triangulate_polygon(PackedVector2Array(polygon))
	if triangulation.is_empty() or triangulation.size() % 3 != 0:
		return {"valid": false, "reason": "cavity_polygon_triangulation_invalid", "index_count": triangulation.size()}
	var domain_triangles: Array[Array] = []
	for index in range(0, triangulation.size(), 3):
		var domain_triangle: Array[Vector2] = [polygon[triangulation[index]], polygon[triangulation[index + 1]], polygon[triangulation[index + 2]]]
		if _signed_area(domain_triangle) < 0.0:
			var swap_point: Vector2 = domain_triangle[1]
			domain_triangle[1] = domain_triangle[2]
			domain_triangle[2] = swap_point
		domain_triangles.append(domain_triangle)
	var vertex_positions: Dictionary = context.get("vertex_positions", {})
	var projected_positions: Dictionary = context.get("projected_positions", {})
	var owner_origin_result: Dictionary = _source_origins(residual_triangles)
	if not bool(owner_origin_result.get("valid", false)):
		return owner_origin_result
	var source_origins: Array[Dictionary] = owner_origin_result.get("origins", [])
	var raw_by_identity: Dictionary = {}
	var zero_tetrahedra: int = 0
	var zero_volume_tetrahedra_skipped: int = 0
	var primitive_classes: Dictionary = {"empty": 0, "point": 0, "segment": 0, "triangle": 0, "quad": 0}
	var zero_facets: int = 0
	var clip_fragments: int = 0
	var skipped_projection_degenerate: int = 0
	var skipped_field_residual: int = 0
	var skipped_outside_support_distance: int = 0
	var skipped_boundary_or_root: int = 0
	var cap_reason: String = ""
	var tetrahedra_visited: int = 0
	var execution_id: String = OS.get_environment("R12CXR_R5_EXECUTION_ID")
	if not execution_id.is_empty():
		print("R5_SYNTHESIS_ENUMERATION_BEGIN " + JSON.stringify({"execution_id": execution_id, "cavity_id": cavity_id, "tetrahedron_count": tetra_count, "owner_origin_count": source_origins.size()}))
	for flat_index in range(tetra_count):
		if Time.get_ticks_usec() - started_usec >= MAX_SYNTHESIS_USEC:
			cap_reason = "R5_MAX_SYNTHESIS_USEC"
			break
		tetrahedra_visited += 1
		var tet_index: int = flat_index % Core.TETS.size()
		var cell_index: int = floori(float(flat_index) / float(Core.TETS.size()))
		var z: int = cell_index % cells.z
		var y: int = floori(float(cell_index) / float(cells.z)) % cells.y
		var x: int = floori(float(cell_index) / float(cells.z * cells.y))
		var cell: Vector3i = Vector3i(x, y, z)
		var tet_data: Dictionary = realizer.call("_tetra_data", cell, tet_index, values, dims, roi_min, step)
		if not bool(tet_data.get("valid", false)):
			return {"valid": false, "reason": "source_tetrahedron_invalid", "cell": cell, "tet_index": tet_index, "detail": tet_data}
		if _all_samples_zero(tet_data.get("samples", [])):
			zero_volume_tetrahedra_skipped += 1
			continue
		var zero_points: Array[Vector3] = realizer.call("_tetra_zero_points", tet_data)
		if zero_points.size() > 4:
			return {"valid": false, "reason": "tetra_zero_primitive_arity_invalid", "cell": cell, "tet_index": tet_index, "point_count": zero_points.size()}
		var primitive_class: String = "empty" if zero_points.is_empty() else "point" if zero_points.size() == 1 else "segment" if zero_points.size() == 2 else "triangle" if zero_points.size() == 3 else "quad"
		primitive_classes[primitive_class] = int(primitive_classes.get(primitive_class, 0)) + 1
		if zero_points.size() < 3: continue
		zero_tetrahedra += 1
		var ordered: Array[Vector3] = _order_zero_polygon(zero_points)
		if ordered.size() < 3:
			skipped_projection_degenerate += 1
			continue
		var facets: Array[Array] = _triangulate_zero_polygon(ordered)
		for facet_index in range(facets.size()):
			if zero_facets >= MAX_ZERO_FACETS:
				cap_reason = "R5_MAX_ZERO_FACETS"
				break
			zero_facets += 1
			var world_triangle: Array[Vector3] = _validated_facet_triangle(facets[facet_index])
			if world_triangle.size() != 3:
				return {"valid": false, "reason": "zero_facet_geometry_invalid", "cell": cell, "tet_index": tet_index, "facet_index": facet_index}
			var source_triangle_2d: Array[Vector2] = []
			for world_point in world_triangle: source_triangle_2d.append(_project(world_point, context))
			if _signed_area(source_triangle_2d) == 0.0:
				skipped_projection_degenerate += 1
				continue
			for domain_index in range(domain_triangles.size()):
				if Time.get_ticks_usec() - started_usec >= MAX_SYNTHESIS_USEC:
					cap_reason = "R5_MAX_SYNTHESIS_USEC"
					break
				var clipped: Array[Vector2] = _clip_convex(source_triangle_2d, domain_triangles[domain_index])
				if clipped.size() < 3 or _signed_area(clipped) == 0.0: continue
				if clip_fragments >= MAX_CLIP_FRAGMENTS:
					cap_reason = "R5_MAX_CLIP_FRAGMENTS"
					break
				clip_fragments += 1
				var witnesses: Array[Vector2] = _interior_witnesses(clipped, polygon)
				if witnesses.is_empty(): continue
				if witnesses.size() > MAX_WITNESSES_PER_CLIPPED_FRAGMENT:
					cap_reason = "R5_MAX_WITNESSES_PER_CLIPPED_FRAGMENT"
					break
				for pair_i in range(boundary_ids.size()):
					if Time.get_ticks_usec() - started_usec >= MAX_SYNTHESIS_USEC:
						cap_reason = "R5_MAX_SYNTHESIS_USEC"
						break
					for pair_j in range(pair_i + 1, boundary_ids.size()):
						var id_a: String = boundary_ids[pair_i]
						var id_b: String = boundary_ids[pair_j]
						if not vertex_positions.has(id_a) or not vertex_positions.has(id_b): continue
						var a: Vector3 = vertex_positions[id_a]
						var b: Vector3 = vertex_positions[id_b]
						var best_witness: Dictionary = {}
						var best_cross_squared: float = -1.0
						for witness in witnesses:
							var witness_check: Dictionary = _validate_witness(realizer, witness, source_triangle_2d, world_triangle, tet_data, polygon, vertex_positions, source_origins, max_support_distance, residual_epsilon, barycentric_epsilon)
							if not bool(witness_check.get("valid", false)):
								var witness_reason: String = String(witness_check.get("reason", "UNKNOWN_NOT_CAPTURED"))
								if witness_reason == "support_outside_support_distance": skipped_outside_support_distance += 1
								elif witness_reason == "support_field_residual_invalid": skipped_field_residual += 1
								elif witness_reason in ["support_on_cavity_boundary", "support_duplicates_topology_root"]: skipped_boundary_or_root += 1
								continue
							var cross: Vector3 = (b - a).cross(Vector3(witness_check.get("world", Vector3.ZERO)) - a)
							var cross_squared: float = cross.length_squared()
							if is_finite(cross_squared) and cross_squared > best_cross_squared:
								best_cross_squared = cross_squared
								best_witness = witness_check
						if best_cross_squared <= cutoff: continue
						var point: Vector3 = best_witness.world
						var origin: Dictionary = best_witness.origin
						var distance: float = float(best_witness.distance)
						var tetra_weights: Array = best_witness.tetra_weights
						var field_residual: float = float(best_witness.field_residual)
						var binary_identity: String = _binary32_position_identity(point)
						var support_id: String = _support_id(point)
						var source_key: String = "%s|%06d|%02d|%02d|%s|%s" % [str(tet_data.global_cell), tet_index, facet_index, domain_index, id_a, id_b]
						var support: Dictionary = {
							"candidate_id": "R5C_" + Core.sha256(source_key.to_utf8_buffer()).substr(0, 24),
							"support_id": support_id,
							"cavity_id": cavity_id,
							"residual_triangle_id": String(origin.get("id", "")),
							"accepted": true,
							"supported": true,
							"rejection_reason": "",
							"method": "R5_CONSTRAINT_CLIPPED_ZERO_PRIMITIVE_MAX_CROSS",
							"level": 2,
							"source_cell_local": cell,
							"source_cell_global_lattice": tet_data.global_cell,
							"source_tetrahedron": tet_index,
							"tetrahedron_sample_values": tet_data.samples.duplicate(),
							"tetrahedron_corner_world": tet_data.positions.duplicate(),
							"zero_primitive_id": "%s|tet:%d|facet:%d" % [str(tet_data.global_cell), tet_index, facet_index],
							"constraint_boundary_pair": [id_a, id_b],
							"barycentric_weights": tetra_weights.duplicate(),
							"frozen_field_interpolated_residual": field_residual,
							"world_position": point,
							"distance_to_face_centroid": distance,
							"binary32_position_identity": binary_identity,
							"max_constraint_cross_squared": best_cross_squared
						}
						if not raw_by_identity.has(binary_identity) and raw_by_identity.size() >= MAX_RAW_SUPPORTS:
							cap_reason = "R5_MAX_RAW_SUPPORTS"
							break
						support["source_key"] = source_key
						_insert_support_by_identity(raw_by_identity, support)
				if not cap_reason.is_empty(): break
			if not cap_reason.is_empty(): break
		if not cap_reason.is_empty(): break
	var ranked: Array[Dictionary] = []
	for support_value in raw_by_identity.values(): ranked.append(support_value)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cross_a: float = float(a.get("max_constraint_cross_squared", -INF))
		var cross_b: float = float(b.get("max_constraint_cross_squared", -INF))
		if cross_a != cross_b: return cross_a > cross_b
		return String(a.get("support_id", "")) < String(b.get("support_id", ""))
	)
	var truncated: bool = ranked.size() > MAX_SUPPORTS
	if truncated:
		ranked.resize(MAX_SUPPORTS)
		if cap_reason.is_empty(): cap_reason = "R5_MAX_SUPPORTS"
	for support in ranked: support.erase("source_key")
	var total_usec: int = Time.get_ticks_usec() - started_usec
	return {
		"valid": true,
		"supports": ranked,
		"tetrahedra_scanned": tetrahedra_visited,
		"zero_tetrahedra": zero_tetrahedra,
		"zero_volume_tetrahedra_skipped": zero_volume_tetrahedra_skipped,
		"zero_primitive_classes": primitive_classes,
		"zero_facets": zero_facets,
		"clip_fragments": clip_fragments,
		"raw_unique_support_count": raw_by_identity.size(),
		"retained_support_count": ranked.size(),
		"support_cap_hit": truncated,
		"cap_reason": cap_reason,
		"finite_candidate_enumeration_complete": cap_reason.is_empty() and not truncated,
		"analytic_feasible_support_domain_exhausted": false,
		"skipped_projection_degenerate": skipped_projection_degenerate,
		"skipped_field_residual": skipped_field_residual,
		"skipped_outside_support_distance": skipped_outside_support_distance,
		"skipped_boundary_or_root": skipped_boundary_or_root,
		"synthesis_usec": total_usec,
		"eligible_boundary_source_pairs": possible_source_pairs,
		"owner_origin_count": source_origins.size(),
		"owner_origin_triangle_ids": source_origins.map(func(row: Dictionary) -> String: return String(row.get("id", ""))),
		"max_witnesses_per_clipped_fragment": MAX_WITNESSES_PER_CLIPPED_FRAGMENT,
		"limits": {"max_tetrahedra": MAX_TETRAHEDRA, "max_zero_facets": MAX_ZERO_FACETS, "max_clip_fragments": MAX_CLIP_FRAGMENTS, "max_raw_supports": MAX_RAW_SUPPORTS, "max_supports": MAX_SUPPORTS, "max_synthesis_usec": MAX_SYNTHESIS_USEC, "max_source_pairs": MAX_BOUNDARY_SOURCE_PAIRS, "max_witnesses_per_clipped_fragment": MAX_WITNESSES_PER_CLIPPED_FRAGMENT, "existing_cross_squared_cutoff": cutoff, "existing_max_support_distance": max_support_distance}
	}

func _clip_linear_interval(lower: float, upper: float, value_at_lower: float, value_at_upper: float) -> Dictionary:
	if not is_finite(lower) or not is_finite(upper) or not is_finite(value_at_lower) or not is_finite(value_at_upper) or lower < 0.0 or upper > 1.0 or lower > upper:
		return {"valid": false, "reason": "interval_input_invalid"}
	var lower_inside: bool = value_at_lower >= 0.0
	var upper_inside: bool = value_at_upper >= 0.0
	if lower_inside and upper_inside: return {"valid": true, "empty": false, "lower": lower, "upper": upper}
	if not lower_inside and not upper_inside: return {"valid": true, "empty": true, "lower": lower, "upper": lower}
	var denominator: float = value_at_lower - value_at_upper
	if denominator == 0.0 or not is_finite(denominator): return {"valid": false, "reason": "interval_crossing_unresolved"}
	var t: float = clampf(lower + (upper - lower) * (value_at_lower / denominator), lower, upper)
	if not is_finite(t): return {"valid": false, "reason": "interval_intersection_nonfinite"}
	return {"valid": true, "empty": false, "lower": t if not lower_inside else lower, "upper": upper if upper_inside else t}

func _clip_segment_to_convex_polygon(start: Vector2, end: Vector2, polygon: Array[Vector2]) -> Dictionary:
	if polygon.size() < 3 or _signed_area(polygon) <= 0.0:
		return {"valid": false, "reason": "convex_domain_must_be_ccw"}
	var lower: float = 0.0
	var upper: float = 1.0
	for edge_index in range(polygon.size()):
		var a: Vector2 = polygon[edge_index]
		var b: Vector2 = polygon[(edge_index + 1) % polygon.size()]
		var interval_start: Vector2 = start.lerp(end, lower)
		var interval_end: Vector2 = start.lerp(end, upper)
		var clipped: Dictionary = _clip_linear_interval(0.0, 1.0, _orientation(a, b, interval_start), _orientation(a, b, interval_end))
		if not bool(clipped.get("valid", false)): return clipped
		if bool(clipped.get("empty", false)): return {"valid": true, "empty": true, "lower": lower, "upper": lower}
		var previous_lower: float = lower
		var span: float = upper - lower
		lower = previous_lower + span * float(clipped.lower)
		upper = previous_lower + span * float(clipped.upper)
	return {"valid": true, "empty": lower > upper, "lower": lower, "upper": upper, "start": start.lerp(end, lower), "end": start.lerp(end, upper)}

func _maximize_cross_squared_on_segment(a: Vector3, b: Vector3, start: Vector3, end: Vector3) -> Dictionary:
	if not a.is_finite() or not b.is_finite() or not start.is_finite() or not end.is_finite(): return {"valid": false, "reason": "cross_objective_nonfinite"}
	var start_cross: Vector3 = (b - a).cross(start - a)
	var end_cross: Vector3 = (b - a).cross(end - a)
	var start_score: float = start_cross.length_squared()
	var end_score: float = end_cross.length_squared()
	if not is_finite(start_score) or not is_finite(end_score): return {"valid": false, "reason": "cross_objective_nonfinite"}
	var choose_end: bool = end_score > start_score
	return {"valid": true, "position": end if choose_end else start, "parameter": 1.0 if choose_end else 0.0, "cross_squared": end_score if choose_end else start_score, "endpoint_scores": [start_score, end_score], "objective": "convex_norm_squared_maximum_at_segment_endpoint"}

func _binary32_position_identity(point: Vector3) -> String:
	return var_to_bytes(point).hex_encode()

func _support_id(point: Vector3) -> String:
	return "R5SUP_" + Core.sha256(_binary32_position_identity(point).to_utf8_buffer()).substr(0, 24)

func _source_origins(residual_rows: Array) -> Dictionary:
	if residual_rows.is_empty(): return {"valid": false, "reason": "residual_owner_rows_missing"}
	var origins: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for row_value in residual_rows:
		if typeof(row_value) != TYPE_DICTIONARY: return {"valid": false, "reason": "residual_owner_row_invalid"}
		var row: Dictionary = row_value
		var triangle_id: String = String(row.get("triangle_id", ""))
		if triangle_id.is_empty() or seen_ids.has(triangle_id): return {"valid": false, "reason": "residual_owner_triangle_id_invalid_or_duplicate", "triangle_id": triangle_id}
		var points_value: Variant = row.get("points", row.get("triangle_vertices_world", null))
		if typeof(points_value) != TYPE_ARRAY or points_value.size() != 3: return {"valid": false, "reason": "residual_owner_vertices_invalid", "triangle_id": triangle_id}
		var points: Array[Vector3] = []
		for point_value in points_value:
			var point: Vector3
			if point_value is Vector3:
				point = Vector3(point_value)
			elif point_value is Array and point_value.size() == 3:
				point = Vector3(float(point_value[0]), float(point_value[1]), float(point_value[2]))
			else:
				return {"valid": false, "reason": "residual_owner_vertex_encoding_invalid", "triangle_id": triangle_id}
			if not point.is_finite(): return {"valid": false, "reason": "residual_owner_vertex_nonfinite", "triangle_id": triangle_id}
			points.append(point)
		var center: Vector3 = (points[0] + points[1] + points[2]) / 3.0
		if not center.is_finite(): return {"valid": false, "reason": "residual_owner_centroid_nonfinite", "triangle_id": triangle_id}
		seen_ids[triangle_id] = true
		origins.append({"id": triangle_id, "center": center})
	origins.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("id", "")) < String(b.get("id", "")))
	return {"valid": true, "origins": origins, "owner_origin_count": origins.size()}

func _insert_support_by_identity(table: Dictionary, support: Dictionary) -> void:
	var identity: String = String(support.get("binary32_position_identity", ""))
	if identity.is_empty(): return
	if not table.has(identity):
		table[identity] = support.duplicate(true)
		return
	var prior: Dictionary = table[identity]
	var prior_cross: float = float(prior.get("max_constraint_cross_squared", -INF))
	var next_cross: float = float(support.get("max_constraint_cross_squared", -INF))
	if next_cross > prior_cross:
		prior["max_constraint_cross_squared"] = next_cross
		prior["constraint_boundary_pair"] = support.get("constraint_boundary_pair", []).duplicate()
	if String(support.get("source_key", "")) < String(prior.get("source_key", "~")):
		var best_cross: float = maxf(prior_cross, next_cross)
		var best_pair: Array = prior.get("constraint_boundary_pair", []).duplicate()
		var replacement: Dictionary = support.duplicate(true)
		replacement["max_constraint_cross_squared"] = best_cross
		if next_cross <= prior_cross: replacement["constraint_boundary_pair"] = best_pair
		table[identity] = replacement

func _candidate_graph_sha256(probe_rows: Array[String]) -> String:
	var ordered: Array[String] = probe_rows.duplicate()
	ordered.sort()
	return Core.sha256("\n".join(ordered).to_utf8_buffer())

func _support_pair_objective(a: Vector3, b: Vector3, point: Vector3) -> float:
	var cross: Vector3 = (b - a).cross(point - a)
	return cross.length_squared() if cross.is_finite() else NAN

func _validate_field_point(realizer: RefCounted, point: Vector3, tetrahedron_positions: Array, samples: Array, residual_epsilon: float, barycentric_epsilon: float) -> Dictionary:
	if not point.is_finite() or tetrahedron_positions.size() != 4 or samples.size() != 4 or not is_finite(residual_epsilon) or residual_epsilon <= 0.0 or not is_finite(barycentric_epsilon) or barycentric_epsilon <= 0.0:
		return {"valid": false, "reason": "support_field_validation_input_invalid"}
	var bary_result: Dictionary = realizer.call("_tetra_barycentric", point, tetrahedron_positions)
	if not bool(bary_result.get("valid", false)): return {"valid": false, "reason": "support_field_residual_invalid"}
	var weights: Array = bary_result.get("weights", [])
	if weights.size() != 4: return {"valid": false, "reason": "support_field_residual_invalid"}
	var field_residual: float = 0.0
	for index in range(weights.size()):
		var weight: float = float(weights[index])
		if not is_finite(weight) or weight < -barycentric_epsilon or weight > 1.0 + barycentric_epsilon: return {"valid": false, "reason": "support_field_residual_invalid"}
		var sample: float = float(samples[index])
		if not is_finite(sample): return {"valid": false, "reason": "support_field_sample_nonfinite"}
		field_residual += weight * sample
	if not is_finite(field_residual) or absf(field_residual) > residual_epsilon:
		return {"valid": false, "reason": "support_field_residual_invalid", "residual": field_residual, "weights": weights}
	return {"valid": true, "weights": weights, "field_residual": field_residual, "barycentric": bary_result}

func _candidate_graph_summary(triangles: Array[Dictionary], edges: Dictionary, support_by_id: Dictionary) -> Dictionary:
	var support_degree: Dictionary = {}
	var edge_types: Dictionary = {"root_root": 0, "root_support": 0, "support_support": 0}
	var canonical_lines: Array[String] = []
	var edge_keys: Array = edges.keys()
	edge_keys.sort()
	for edge_key_value in edge_keys:
		var edge_key: String = String(edge_key_value)
		var ids: Array = edges[edge_key].get("vertex_ids", [])
		if ids.size() != 2: continue
		var first_support: bool = support_by_id.has(String(ids[0]))
		var second_support: bool = support_by_id.has(String(ids[1]))
		if first_support and second_support: edge_types["support_support"] += 1
		elif first_support or second_support: edge_types["root_support"] += 1
		else: edge_types["root_root"] += 1
		for id_value in ids:
			var id: String = String(id_value)
			if support_by_id.has(id): support_degree[id] = int(support_degree.get(id, 0)) + 1
		canonical_lines.append("edge|%s|%s|%s" % [edge_key, String(edges[edge_key].get("candidate_ids", []).size()), "support" if first_support or second_support else "root"])
	var ordered_triangles: Array[Dictionary] = triangles.duplicate(true)
	ordered_triangles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("triangle_id", "")) < String(b.get("triangle_id", "")))
	var supports_with_triangle: Dictionary = {}
	var minimum_cross: float = INF
	var maximum_cross: float = -INF
	for triangle in ordered_triangles:
		var ids: Array = triangle.get("root_ids", [])
		var sorted_ids: Array[String] = []
		for id_value in ids:
			sorted_ids.append(String(id_value))
			if support_by_id.has(String(id_value)): supports_with_triangle[String(id_value)] = true
		sorted_ids.sort()
		var cross_squared: float = float(triangle.get("cross_squared", NAN))
		if is_finite(cross_squared):
			minimum_cross = minf(minimum_cross, cross_squared)
			maximum_cross = maxf(maximum_cross, cross_squared)
		canonical_lines.append("triangle|%s|%s|%s" % [String(triangle.get("triangle_id", "")), ",".join(sorted_ids), str(cross_squared)])
	var supports_ge_1: int = 0
	var supports_ge_2: int = 0
	var supports_with_legal_triangle: int = 0
	for support_id_value in support_by_id.keys():
		var support_id: String = String(support_id_value)
		var degree: int = int(support_degree.get(support_id, 0))
		if degree >= 1: supports_ge_1 += 1
		if degree >= 2: supports_ge_2 += 1
		if supports_with_triangle.has(support_id): supports_with_legal_triangle += 1
	canonical_lines.sort()
	return {"legal_root_root_edges": int(edge_types.root_root), "legal_root_support_edges": int(edge_types.root_support), "legal_support_support_edges": int(edge_types.support_support), "support_degree_ge_1": supports_ge_1, "support_degree_ge_2": supports_ge_2, "supports_with_legal_triangle": supports_with_legal_triangle, "minimum_legal_cross_squared": minimum_cross if minimum_cross < INF else "NO_LEGAL_TRIANGLES", "maximum_legal_cross_squared": maximum_cross if maximum_cross > -INF else "NO_LEGAL_TRIANGLES", "candidate_graph_sha256": Core.sha256("\n".join(canonical_lines).to_utf8_buffer())}

func _project(point: Vector3, context: Dictionary) -> Vector2:
	var delta: Vector3 = point - Vector3(context.get("projection_origin", Vector3.ZERO))
	return Vector2(delta.dot(Vector3(context.get("projection_u", Vector3.ZERO))), delta.dot(Vector3(context.get("projection_v", Vector3.ZERO))))

func _all_samples_zero(samples: Array) -> bool:
	if samples.size() != 4: return false
	for sample in samples:
		if float(sample) != 0.0: return false
	return true

func _order_zero_polygon(points: Array[Vector3]) -> Array[Vector3]:
	if points.size() == 3: return points.duplicate()
	if points.size() != 4: return []
	var canonical_points: Array[Vector3] = points.duplicate()
	canonical_points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return var_to_bytes(a).hex_encode() < var_to_bytes(b).hex_encode())
	var center: Vector3 = Vector3.ZERO
	for point in canonical_points: center += point
	center /= float(canonical_points.size())
	var normal: Vector3 = Vector3.ZERO
	for i in range(canonical_points.size()):
		for j in range(i + 1, canonical_points.size()):
			for k in range(j + 1, canonical_points.size()):
				var candidate: Vector3 = (canonical_points[j] - canonical_points[i]).cross(canonical_points[k] - canonical_points[i])
				if candidate.length_squared() > 0.0:
					normal = candidate.normalized()
					break
			if normal.length_squared() > 0.0: break
		if normal.length_squared() > 0.0: break
	if normal.length_squared() == 0.0: return []
	var axis_u: Vector3 = (canonical_points[0] - center).normalized()
	if axis_u.length_squared() == 0.0: return []
	var axis_v: Vector3 = normal.cross(axis_u).normalized()
	var rows: Array[Dictionary] = []
	for point in canonical_points:
		var delta: Vector3 = point - center
		rows.append({"point": point, "angle": atan2(delta.dot(axis_v), delta.dot(axis_u)), "key": var_to_bytes(point).hex_encode()})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.angle) != float(b.angle): return float(a.angle) < float(b.angle)
		return String(a.key) < String(b.key)
	)
	var ordered: Array[Vector3] = []
	for row in rows: ordered.append(row.point)
	return ordered

func _triangulate_zero_polygon(points: Array[Vector3]) -> Array[Array]:
	var result: Array[Array] = []
	for i in range(1, points.size() - 1): result.append([points[0], points[i], points[i + 1]])
	return result

func _validated_facet_triangle(facet_value: Variant) -> Array[Vector3]:
	var vertices: Array[Vector3] = []
	if typeof(facet_value) != TYPE_ARRAY:
		return vertices
	var raw_vertices: Array = facet_value
	if raw_vertices.size() != 3:
		return vertices
	for raw_point in raw_vertices:
		if typeof(raw_point) != TYPE_VECTOR3:
			return []
		var point: Vector3 = raw_point
		if not point.is_finite():
			return []
		vertices.append(point)
	return vertices

func _interior_witnesses(clipped: Array[Vector2], domain: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var centroid: Vector2 = _polygon_centroid(clipped)
	if _point_strictly_inside(centroid, domain): result.append(centroid)
	for point in clipped:
		if _point_strictly_inside(point, domain) and not result.has(point): result.append(point)
	result.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if a.x != b.x: return a.x < b.x
		return a.y < b.y
	)
	return result

func _polygon_centroid(points: Array[Vector2]) -> Vector2:
	var twice_area: float = 0.0
	var weighted: Vector2 = Vector2.ZERO
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var cross: float = a.cross(b)
		twice_area += cross
		weighted += (a + b) * cross
	if twice_area == 0.0:
		var average: Vector2 = Vector2.ZERO
		for point in points: average += point
		return average / float(points.size())
	return weighted / (3.0 * twice_area)

func _point_strictly_inside(point: Vector2, polygon: Array[Vector2]) -> bool:
	if not Geometry2D.is_point_in_polygon(point, PackedVector2Array(polygon)): return false
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var segment: Vector2 = b - a
		var length_sq: float = segment.length_squared()
		if length_sq == 0.0: continue
		var t: float = clampf((point - a).dot(segment) / length_sq, 0.0, 1.0)
		if point.distance_squared_to(a + segment * t) <= 1.0e-16: return false
	return true

func _point_on_polygon_boundary(point: Vector2, polygon: Array[Vector2]) -> bool:
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var segment: Vector2 = b - a
		var length_sq: float = segment.length_squared()
		if length_sq == 0.0:
			if point == a: return true
			continue
		var t: float = clampf((point - a).dot(segment) / length_sq, 0.0, 1.0)
		if point.distance_squared_to(a + segment * t) <= 1.0e-16: return true
	return false

func _map_projected_point(point: Vector2, source: Array[Vector2], world: Array[Vector3]) -> Dictionary:
	var denominator: float = (source[1] - source[0]).cross(source[2] - source[0])
	if denominator == 0.0 or not is_finite(denominator): return {"valid": false, "reason": "projected_source_triangle_degenerate"}
	var w1: float = (point - source[0]).cross(source[2] - source[0]) / denominator
	var w2: float = (source[1] - source[0]).cross(point - source[0]) / denominator
	var weights: Array[float] = [1.0 - w1 - w2, w1, w2]
	var position: Vector3 = world[0] * weights[0] + world[1] * weights[1] + world[2] * weights[2]
	if not position.is_finite(): return {"valid": false, "reason": "mapped_world_point_nonfinite"}
	return {"valid": true, "world": position, "weights": weights}

func _validate_witness(realizer: RefCounted, projected: Vector2, source_2d: Array[Vector2], source_world: Array[Vector3], tet_data: Dictionary, domain_polygon: Array[Vector2], topology_positions: Dictionary, source_origins: Array[Dictionary], max_distance: float, residual_epsilon: float, barycentric_epsilon: float) -> Dictionary:
	if _point_on_polygon_boundary(projected, domain_polygon): return {"valid": false, "reason": "support_on_cavity_boundary"}
	var mapped: Dictionary = _map_projected_point(projected, source_2d, source_world)
	if not bool(mapped.get("valid", false)): return mapped
	var point: Vector3 = mapped.world
	for root_value in topology_positions.values():
		if point.distance_squared_to(Vector3(root_value)) <= 1.0e-16: return {"valid": false, "reason": "support_duplicates_topology_root"}
	var origin: Dictionary = _nearest_origin(point, source_origins)
	if origin.is_empty(): return {"valid": false, "reason": "residual_owner_centroid_missing"}
	var distance: float = point.distance_to(Vector3(origin.get("center", Vector3.ZERO)))
	if not is_finite(distance) or distance > max_distance: return {"valid": false, "reason": "support_outside_support_distance"}
	var field_check: Dictionary = _validate_field_point(realizer, point, tet_data.get("positions", []), tet_data.get("samples", []), residual_epsilon, barycentric_epsilon)
	if not bool(field_check.get("valid", false)): return field_check
	return {"valid": true, "projected": projected, "world": point, "origin": origin, "distance": distance, "tetra_weights": field_check.get("weights", []), "field_residual": field_check.get("field_residual", NAN)}

func _nearest_origin(point: Vector3, source_origins: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for origin in source_origins:
		var distance: float = point.distance_squared_to(Vector3(origin.get("center", Vector3.ZERO)))
		var id: String = String(origin.get("id", ""))
		if distance < best_distance or (distance == best_distance and id < String(best.get("id", "~"))):
			best_distance = distance
			best = origin
	return best

func _clip_convex(subject: Array[Vector2], clip: Array[Vector2]) -> Array[Vector2]:
	var output: Array[Vector2] = subject.duplicate()
	for edge_index in range(clip.size()):
		var a: Vector2 = clip[edge_index]
		var b: Vector2 = clip[(edge_index + 1) % clip.size()]
		var input: Array[Vector2] = output
		output = []
		if input.is_empty(): break
		var previous: Vector2 = input[input.size() - 1]
		var previous_inside: bool = _orientation(a, b, previous) >= 0.0
		for current in input:
			var current_inside: bool = _orientation(a, b, current) >= 0.0
			if current_inside != previous_inside:
				var intersection: Dictionary = _line_intersection(previous, current, a, b)
				if bool(intersection.get("valid", false)): _append_unique(output, intersection.point)
			if current_inside: _append_unique(output, current)
			previous = current
			previous_inside = current_inside
		output = _remove_duplicate_end(output)
	return output

func _line_intersection(p: Vector2, q: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var r: Vector2 = q - p
	var s: Vector2 = b - a
	var denominator: float = r.cross(s)
	if denominator == 0.0: return {"valid": false}
	var t: float = (a - p).cross(s) / denominator
	return {"valid": true, "point": p + r * t}

func _orientation(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b - a).cross(c - a)

func _signed_area(points: Array) -> float:
	var twice_area: float = 0.0
	for i in range(points.size()): twice_area += Vector2(points[i]).cross(Vector2(points[(i + 1) % points.size()]))
	return twice_area * 0.5

func _append_unique(points: Array[Vector2], point: Vector2) -> void:
	if points.is_empty() or points[points.size() - 1] != point: points.append(point)

func _remove_duplicate_end(points: Array[Vector2]) -> Array[Vector2]:
	if points.size() > 1 and points[0] == points[points.size() - 1]: points.pop_back()
	return points
