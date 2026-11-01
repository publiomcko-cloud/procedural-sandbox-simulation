extends RefCounted

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")

const MAX_TETRAHEDRA: int = 3072
const MAX_ZERO_FACETS: int = 6144
const MAX_CLIP_FRAGMENTS: int = 32768
const MAX_RAW_SUPPORTS: int = 4096
const MAX_SUPPORTS: int = 64
const MAX_SYNTHESIS_USEC: int = 30000000
const MAX_BOUNDARY_SOURCE_PAIRS: int = 15
const MAX_FEASIBLE_REGION_COMPONENTS: int = 4096
const MAX_CRITICAL_CANDIDATES_PER_PAIR_REGION: int = 7
const MAX_CRITICAL_CANDIDATES_TOTAL: int = 4096
const MAX_CONSTRAINT_LINES_PER_PAIR_REGION: int = 256
const FROZEN_CROSS_SQUARED_CUTOFF: float = 1.0e-12
const SHA256_EMPTY_BYTES: String = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

func synthesize(realizer: RefCounted, values: PackedFloat32Array, roi: Dictionary, context: Dictionary, residual_triangles: Array, cavity_id: String, required_arcs: Array = []) -> Dictionary:
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
	var exact_required_arcs: Array = context.get("residual_fixture", {}).get("arc_map", required_arcs)
	var arc_segment_result: Dictionary = _project_required_arc_segments(exact_required_arcs, context)
	if not bool(arc_segment_result.get("valid", false)):
		return arc_segment_result
	var arc_segments: Array[Dictionary] = arc_segment_result.get("segments", [])
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
	var feasible_region_count: int = 0
	var constraint_line_count: int = 0
	var critical_candidate_count: int = 0
	var feasible_single_support_count: int = 0
	var candidate_triangle_rejections: Dictionary = {}
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
						var root_a_2d: Vector2 = Vector2(projected_positions.get(id_a, Vector2.ZERO))
						var root_b_2d: Vector2 = Vector2(projected_positions.get(id_b, Vector2.ZERO))
						var region_key: String = "%s|%06d|%02d|%02d|%s|%s" % [str(tet_data.global_cell), tet_index, facet_index, domain_index, id_a, id_b]
						var region_result: Dictionary = _triangle_first_critical_candidates(clipped, polygon, root_a_2d, root_b_2d, a, b, source_triangle_2d, world_triangle, arc_segments, feasible_region_count, region_key, critical_candidate_count)
						if not bool(region_result.get("valid", false)):
							cap_reason = String(region_result.get("reason", "R5_FEASIBLE_REGION_INVALID"))
							break
						feasible_region_count += int(region_result.get("region_count", 0))
						constraint_line_count += int(region_result.get("constraint_line_count", 0))
						var witness_records: Array[Dictionary] = region_result.get("candidates", [])
						if critical_candidate_count + witness_records.size() > MAX_CRITICAL_CANDIDATES_TOTAL:
							cap_reason = "R5_MAX_CRITICAL_CANDIDATES_TOTAL"
							break
						critical_candidate_count += witness_records.size()
						for witness_record in witness_records:
							if Time.get_ticks_usec() - started_usec >= MAX_SYNTHESIS_USEC:
								cap_reason = "R5_MAX_SYNTHESIS_USEC"
								break
							var witness: Vector2 = Vector2(witness_record.get("position", Vector2.ZERO))
							var witness_check: Dictionary = _validate_witness(realizer, witness, source_triangle_2d, world_triangle, tet_data, polygon, vertex_positions, source_origins, max_support_distance, residual_epsilon, barycentric_epsilon)
							if not bool(witness_check.get("valid", false)):
								var witness_reason: String = String(witness_check.get("reason", "UNKNOWN_NOT_CAPTURED"))
								if witness_reason == "support_outside_support_distance": skipped_outside_support_distance += 1
								elif witness_reason == "support_field_residual_invalid": skipped_field_residual += 1
								elif witness_reason in ["support_on_cavity_boundary", "support_duplicates_topology_root"]: skipped_boundary_or_root += 1
								_add_rejection(candidate_triangle_rejections, witness_reason)
								continue
							witness_check["critical_candidate_method"] = String(witness_record.get("method", "UNKNOWN_NOT_CAPTURED"))
							var point: Vector3 = Vector3(witness_check.get("world", Vector3.ZERO))
							var cross_squared: float = _support_pair_objective(a, b, point)
							if not is_finite(cross_squared) or cross_squared <= cutoff:
								_add_rejection(candidate_triangle_rejections, "candidate_cross_squared_at_or_below_frozen_cutoff")
								continue
							var exact_gate: Dictionary = _single_support_pair_gate(realizer, context, id_a, id_b, point, _project(point, context), cutoff)
							if not bool(exact_gate.get("valid", false)):
								_add_rejection(candidate_triangle_rejections, String(exact_gate.get("reason", "UNKNOWN_NOT_CAPTURED")))
								continue
							feasible_single_support_count += 1
							var origin: Dictionary = witness_check.origin
							var distance: float = float(witness_check.distance)
							var tetra_weights: Array = witness_check.tetra_weights
							var field_residual: float = float(witness_check.field_residual)
							var binary_identity: String = _binary32_position_identity(point)
							var support_id: String = _support_id(point)
							var arrangement_region_id: String = String(witness_record.get("constraint_arrangement_region_id", "UNKNOWN_NOT_CAPTURED"))
							var source_key: String = "%s|%06d|%02d|%02d|%s|%s|%s|%s" % [str(tet_data.global_cell), tet_index, facet_index, domain_index, id_a, id_b, arrangement_region_id, String(witness_record.get("method", ""))]
							var support: Dictionary = {
								"candidate_id": "R5C_" + Core.sha256(source_key.to_utf8_buffer()).substr(0, 24),
								"support_id": support_id,
								"cavity_id": cavity_id,
								"residual_triangle_id": String(origin.get("id", "")),
								"accepted": true,
								"supported": true,
								"rejection_reason": "",
								"method": "R5_TRIANGLE_FIRST_FEASIBLE_ZERO_REGION",
								"level": 2,
								"source_cell_local": cell,
								"source_cell_global_lattice": tet_data.global_cell,
								"source_tetrahedron": tet_index,
								"tetrahedron_sample_values": tet_data.samples.duplicate(),
								"tetrahedron_corner_world": tet_data.positions.duplicate(),
								"zero_primitive_id": "%s|tet:%d|facet:%d" % [str(tet_data.global_cell), tet_index, facet_index],
								"constraint_boundary_pair": [id_a, id_b],
								"constraint_arrangement_region_id": arrangement_region_id,
								"constraint_clearance": float(witness_record.get("clearance", 0.0)),
								"barycentric_weights": tetra_weights.duplicate(),
								"frozen_field_interpolated_residual": field_residual,
								"world_position": point,
								"distance_to_face_centroid": distance,
								"binary32_position_identity": binary_identity,
								"max_constraint_cross_squared": cross_squared,
								"critical_candidate_method": String(witness_record.get("method", "UNKNOWN_NOT_CAPTURED"))
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
		"projected_required_arc_segment_count": arc_segments.size(),
		"arrangement_region_components_processed": feasible_region_count,
		"constraint_line_count": constraint_line_count,
		"critical_support_candidate_count": critical_candidate_count,
		"single_support_triangle_feasible_candidate_count": feasible_single_support_count,
		"single_support_triangle_rejection_histogram": candidate_triangle_rejections,
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
		"candidate_model": "FINITE_CONSTRAINT_ARRANGEMENT_CRITICAL_POINTS",
		"max_critical_candidates_per_pair_region": MAX_CRITICAL_CANDIDATES_PER_PAIR_REGION,
		"max_critical_candidates_total": MAX_CRITICAL_CANDIDATES_TOTAL,
		"max_constraint_lines_per_pair_region": MAX_CONSTRAINT_LINES_PER_PAIR_REGION,
		"max_feasible_region_components": MAX_FEASIBLE_REGION_COMPONENTS,
		"limits": {"max_tetrahedra": MAX_TETRAHEDRA, "max_zero_facets": MAX_ZERO_FACETS, "max_clip_fragments": MAX_CLIP_FRAGMENTS, "max_raw_supports": MAX_RAW_SUPPORTS, "max_supports": MAX_SUPPORTS, "max_synthesis_usec": MAX_SYNTHESIS_USEC, "max_source_pairs": MAX_BOUNDARY_SOURCE_PAIRS, "max_critical_candidates_per_pair_region": MAX_CRITICAL_CANDIDATES_PER_PAIR_REGION, "max_critical_candidates_total": MAX_CRITICAL_CANDIDATES_TOTAL, "max_constraint_lines_per_pair_region": MAX_CONSTRAINT_LINES_PER_PAIR_REGION, "max_feasible_region_components": MAX_FEASIBLE_REGION_COMPONENTS, "existing_cross_squared_cutoff": cutoff, "existing_max_support_distance": max_support_distance}
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
	return _sha256_allow_empty("\n".join(ordered).to_utf8_buffer())

func _sha256_allow_empty(bytes: PackedByteArray) -> String:
	# HashingContext.update rejects a zero-length update in the pinned Godot build.
	# SHA-256 of the empty byte sequence is fixed and must not emit a runtime error.
	if bytes.is_empty(): return SHA256_EMPTY_BYTES
	return Core.sha256(bytes)

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
	return {"legal_root_root_edges": int(edge_types.root_root), "legal_root_support_edges": int(edge_types.root_support), "legal_support_support_edges": int(edge_types.support_support), "support_degree_ge_1": supports_ge_1, "support_degree_ge_2": supports_ge_2, "supports_with_legal_triangle": supports_with_legal_triangle, "minimum_legal_cross_squared": minimum_cross if minimum_cross < INF else "NO_LEGAL_TRIANGLES", "maximum_legal_cross_squared": maximum_cross if maximum_cross > -INF else "NO_LEGAL_TRIANGLES", "candidate_graph_sha256": _sha256_allow_empty("\n".join(canonical_lines).to_utf8_buffer())}

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

func _interior_witness_records(clipped: Array[Vector2], domain: Array[Vector2]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if clipped.size() < 3 or domain.size() < 3: return result
	var centroid: Vector2 = _polygon_centroid(clipped)
	if _point_strictly_inside(centroid, domain):
		_insert_witness_record(result, centroid, "CLIPPED_ZERO_PRIMITIVE_CENTROID")
	for boundary_point in clipped:
		var candidate: Vector2 = boundary_point
		var method: String = "CLIPPED_ZERO_PRIMITIVE_VERTEX"
		if not _point_strictly_inside(candidate, domain):
			var inset: Dictionary = _nearest_strict_interior_point(boundary_point, centroid, domain)
			if not bool(inset.get("valid", false)): continue
			candidate = Vector2(inset.get("position", Vector2.ZERO))
			method = "ACTIVE_DOMAIN_BOUNDARY_INWARD_LIMIT"
		if _point_strictly_inside(candidate, domain): _insert_witness_record(result, candidate, method)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var point_a: Vector2 = Vector2(a.get("position", Vector2.ZERO))
		var point_b: Vector2 = Vector2(b.get("position", Vector2.ZERO))
		if point_a.x != point_b.x: return point_a.x < point_b.x
		if point_a.y != point_b.y: return point_a.y < point_b.y
		return String(a.get("method", "")) < String(b.get("method", ""))
	)
	return result

func _project_required_arc_segments(required_arcs: Array, context: Dictionary) -> Dictionary:
	var segments: Array[Dictionary] = []
	var projected: Dictionary = context.get("projected_positions", {})
	for arc_value in required_arcs:
		if typeof(arc_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "required_arc_record_malformed"}
		var arc: Dictionary = arc_value
		var root_ids: Array = arc.get("root_ids", [])
		if root_ids.size() != 2 or not projected.has(String(root_ids[0])) or not projected.has(String(root_ids[1])):
			return {"valid": false, "reason": "required_arc_root_projection_missing", "arc_id": arc.get("arc_id", "")}
		var arc_a: Vector2 = Vector2(projected[String(root_ids[0])])
		var arc_b: Vector2 = Vector2(projected[String(root_ids[1])])
		if arc_a != arc_b:
			segments.append({"a": arc_a, "b": arc_b, "arc_id": String(arc.get("arc_id", "")), "segment_index": 0})
	segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var key_a: String = "%s|%08d" % [String(a.get("arc_id", "")), int(a.get("segment_index", 0))]
		var key_b: String = "%s|%08d" % [String(b.get("arc_id", "")), int(b.get("segment_index", 0))]
		return key_a < key_b
	)
	return {"valid": true, "segments": segments}

func _triangle_first_critical_candidates(clipped: Array[Vector2], cavity: Array[Vector2], root_a: Vector2, root_b: Vector2, root_a_world: Vector3, root_b_world: Vector3, source_2d: Array[Vector2], source_world: Array[Vector3], arc_segments: Array[Dictionary], prior_region_count: int, region_source_key: String, prior_candidate_count: int = 0) -> Dictionary:
	var lines: Array[Dictionary] = []
	_add_constraint_line(lines, root_a, root_b, "ROOT_PAIR")
	for edge_index in range(cavity.size()):
		var first: Vector2 = cavity[edge_index]
		var second: Vector2 = cavity[(edge_index + 1) % cavity.size()]
		_add_constraint_line(lines, first, second, "CAVITY_EDGE")
		_add_constraint_line(lines, root_a, first, "ROOT_A_TO_CAVITY_VERTEX")
		_add_constraint_line(lines, root_b, first, "ROOT_B_TO_CAVITY_VERTEX")
	for segment in arc_segments:
		var arc_a: Vector2 = Vector2(segment.get("a", Vector2.ZERO))
		var arc_b: Vector2 = Vector2(segment.get("b", Vector2.ZERO))
		if not _segment_bounds_overlap_polygon(arc_a, arc_b, clipped): continue
		_add_constraint_line(lines, root_a, arc_a, "ROOT_A_TO_ARC_ENDPOINT")
		_add_constraint_line(lines, root_a, arc_b, "ROOT_A_TO_ARC_ENDPOINT")
		_add_constraint_line(lines, root_b, arc_a, "ROOT_B_TO_ARC_ENDPOINT")
		_add_constraint_line(lines, root_b, arc_b, "ROOT_B_TO_ARC_ENDPOINT")
		_add_constraint_line(lines, arc_a, arc_b, "REQUIRED_ARC_SUPPORTING_LINE")
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("key", "")) < String(b.get("key", "")))
	if lines.size() > MAX_CONSTRAINT_LINES_PER_PAIR_REGION:
		return {"valid": false, "reason": "R5_MAX_CONSTRAINT_LINES_PER_PAIR_REGION", "line_count": lines.size()}
	var regions: Array[Array] = [clipped.duplicate()]
	if prior_region_count + regions.size() > MAX_FEASIBLE_REGION_COMPONENTS:
		return {"valid": false, "reason": "R5_MAX_FEASIBLE_REGION_COMPONENTS"}
	for line in lines:
		var next_regions: Array[Array] = []
		for region in regions:
			var split: Dictionary = _split_polygon_by_line(region, Vector2(line.a), Vector2(line.b))
			if bool(split.get("split", false)):
				for half_value in [split.get("positive", []), split.get("negative", [])]:
					var half: Array[Vector2] = half_value
					if half.size() >= 3 and absf(_signed_area(half)) > 0.0: next_regions.append(half)
			else:
				next_regions.append(region)
			if prior_region_count + next_regions.size() > MAX_FEASIBLE_REGION_COMPONENTS:
				return {"valid": false, "reason": "R5_MAX_FEASIBLE_REGION_COMPONENTS", "line_key": line.key}
		regions = next_regions
		if regions.is_empty(): return {"valid": false, "reason": "R5_CONSTRAINT_ARRANGEMENT_ELIMINATED_SOURCE_POLYGON", "line_key": line.key}
	var all_candidates: Array[Dictionary] = []
	for region_index in range(regions.size()):
		var region: Array[Vector2] = regions[region_index]
		var region_id: String = "R5REG_" + Core.sha256((region_source_key + "|" + str(region_index) + "|" + _polygon_identity(region)).to_utf8_buffer()).substr(0, 24)
		all_candidates.append_array(_critical_candidates_for_region(region, cavity, source_2d, source_world, root_a_world, root_b_world, arc_segments, region_id))
		if prior_candidate_count + all_candidates.size() > MAX_CRITICAL_CANDIDATES_TOTAL:
			return {"valid": false, "reason": "R5_MAX_CRITICAL_CANDIDATES_TOTAL"}
	return {"valid": true, "region_count": regions.size(), "constraint_line_count": lines.size(), "candidates": all_candidates}

func _add_constraint_line(lines: Array[Dictionary], a: Vector2, b: Vector2, source: String) -> void:
	if not a.is_finite() or not b.is_finite() or a == b: return
	var left: Vector2 = a
	var right: Vector2 = b
	if left.x > right.x or (left.x == right.x and left.y > right.y):
		var swap_point: Vector2 = left
		left = right
		right = swap_point
	var key: String = var_to_bytes(left).hex_encode() + "|" + var_to_bytes(right).hex_encode()
	for existing in lines:
		if String(existing.get("key", "")) == key: return
	lines.append({"a": left, "b": right, "key": key, "source": source})

func _segment_bounds_overlap_polygon(a: Vector2, b: Vector2, polygon: Array[Vector2]) -> bool:
	if polygon.is_empty(): return false
	var min_x: float = minf(a.x, b.x)
	var max_x: float = maxf(a.x, b.x)
	var min_y: float = minf(a.y, b.y)
	var max_y: float = maxf(a.y, b.y)
	var polygon_min_x: float = INF
	var polygon_max_x: float = -INF
	var polygon_min_y: float = INF
	var polygon_max_y: float = -INF
	for point in polygon:
		polygon_min_x = minf(polygon_min_x, point.x)
		polygon_max_x = maxf(polygon_max_x, point.x)
		polygon_min_y = minf(polygon_min_y, point.y)
		polygon_max_y = maxf(polygon_max_y, point.y)
	return max_x >= polygon_min_x and min_x <= polygon_max_x and max_y >= polygon_min_y and min_y <= polygon_max_y

func _split_polygon_by_line(polygon: Array[Vector2], line_a: Vector2, line_b: Vector2) -> Dictionary:
	if polygon.size() < 3 or line_a == line_b: return {"split": false}
	var positive: Array[Vector2] = []
	var negative: Array[Vector2] = []
	var has_positive: bool = false
	var has_negative: bool = false
	for index in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var side_a: float = (line_b - line_a).cross(a - line_a)
		var side_b: float = (line_b - line_a).cross(b - line_a)
		if side_a > 0.0: has_positive = true
		elif side_a < 0.0: has_negative = true
		if side_a >= 0.0: _append_unique_vector(positive, a)
		if side_a <= 0.0: _append_unique_vector(negative, a)
		if (side_a < 0.0 and side_b > 0.0) or (side_a > 0.0 and side_b < 0.0):
			var denominator: float = side_a - side_b
			if denominator == 0.0: return {"split": false}
			var intersection: Vector2 = a.lerp(b, side_a / denominator)
			_append_unique_vector(positive, intersection)
			_append_unique_vector(negative, intersection)
	if not has_positive or not has_negative: return {"split": false}
	positive = _sanitize_polygon(positive)
	negative = _sanitize_polygon(negative)
	if positive.size() < 3 or negative.size() < 3: return {"split": false}
	return {"split": true, "positive": positive, "negative": negative}

func _append_unique_vector(points: Array[Vector2], point: Vector2) -> void:
	if points.is_empty() or points[points.size() - 1] != point: points.append(point)

func _sanitize_polygon(points: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in points:
		_append_unique_vector(result, point)
	if result.size() > 1 and result[0] == result[result.size() - 1]: result.remove_at(result.size() - 1)
	return result

func _critical_candidates_for_region(region: Array[Vector2], cavity: Array[Vector2], source_2d: Array[Vector2], source_world: Array[Vector3], root_a_world: Vector3, root_b_world: Vector3, arc_segments: Array[Dictionary], region_id: String) -> Array[Dictionary]:
	var center: Vector2 = _polygon_centroid(region)
	var points: Array[Dictionary] = []
	var raw_points: Array[Dictionary] = [{"position": center, "method": "FEASIBLE_REGION_CENTROID"}]
	for edge_index in range(region.size()):
		var edge_a: Vector2 = region[edge_index]
		var edge_b: Vector2 = region[(edge_index + 1) % region.size()]
		raw_points.append({"position": edge_a, "method": "ACTIVE_CONSTRAINT_TRANSITION"})
		raw_points.append({"position": edge_a.lerp(edge_b, 0.5), "method": "FEASIBLE_REGION_EDGE_MIDPOINT"})
	var unique: Dictionary = {}
	for row in raw_points:
		var point: Vector2 = Vector2(row.position)
		if not _point_strictly_inside(point, cavity):
			var inset: Dictionary = _nearest_strict_interior_point(point, center, cavity)
			if not bool(inset.get("valid", false)): continue
			point = Vector2(inset.position)
		if not _point_strictly_inside(point, cavity): continue
		var identity: String = var_to_bytes(point).hex_encode()
		if unique.has(identity):
			var prior_roles: Array = unique[identity].get("critical_roles", [])
			_append_critical_role(prior_roles, String(row.method))
			unique[identity]["critical_roles"] = prior_roles
			continue
		var mapped: Dictionary = _map_projected_point(point, source_2d, source_world)
		if not bool(mapped.get("valid", false)): continue
		var clearance: float = _constraint_clearance(point, region, arc_segments)
		var position: Vector3 = Vector3(mapped.world)
		var cross_squared: float = _support_pair_objective(root_a_world, root_b_world, position)
		if not is_finite(cross_squared): continue
		unique[identity] = {"position": point, "world": position, "clearance": clearance, "method": String(row.method), "critical_roles": [String(row.method)], "cross_squared": cross_squared, "region_id": region_id}
	var unique_ids: Array = unique.keys()
	unique_ids.sort()
	for identity in unique_ids:
		var row: Dictionary = unique[identity]
		points.append(row)
	if points.is_empty(): return []
	var lex_order: Array[Dictionary] = points.duplicate(true)
	lex_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2 = Vector2(a.position)
		var pb: Vector2 = Vector2(b.position)
		if pa.x != pb.x: return pa.x < pb.x
		return pa.y < pb.y
	)
	var cross_order: Array[Dictionary] = points.duplicate(true)
	cross_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.cross_squared) != float(b.cross_squared): return float(a.cross_squared) > float(b.cross_squared)
		return var_to_bytes(Vector2(a.position)).hex_encode() < var_to_bytes(Vector2(b.position)).hex_encode()
	)
	var clearance_order: Array[Dictionary] = points.duplicate(true)
	clearance_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.clearance) != float(b.clearance): return float(a.clearance) > float(b.clearance)
		return var_to_bytes(Vector2(a.position)).hex_encode() < var_to_bytes(Vector2(b.position)).hex_encode()
	)
	var selected: Array[Dictionary] = []
	var selected_ids: Dictionary = {}
	_add_selected_critical(selected, selected_ids, cross_order[0], "MAX_CROSS_SQUARED_CRITICAL_CANDIDATE")
	_add_selected_critical(selected, selected_ids, clearance_order[0], "MAX_BOUNDARY_ARC_CLEARANCE_CRITICAL_CANDIDATE")
	for row in points:
		if String(row.method) == "FEASIBLE_REGION_CENTROID":
			_add_selected_critical(selected, selected_ids, row, "FEASIBLE_REGION_CENTROID")
	_add_selected_critical(selected, selected_ids, lex_order[0], "LEXICOGRAPHIC_REGION_VERTEX")
	_add_selected_critical(selected, selected_ids, lex_order[lex_order.size() - 1], "LEXICOGRAPHIC_REGION_VERTEX")
	for row in cross_order:
		if String(row.method) == "FEASIBLE_REGION_EDGE_MIDPOINT":
			_add_selected_critical(selected, selected_ids, row, "FEASIBLE_REGION_EDGE_MIDPOINT")
			break
	if selected.size() < MAX_CRITICAL_CANDIDATES_PER_PAIR_REGION:
		for row in cross_order:
			_add_selected_critical(selected, selected_ids, row, String(row.method))
			if selected.size() >= MAX_CRITICAL_CANDIDATES_PER_PAIR_REGION: break
	if selected.size() < MAX_CRITICAL_CANDIDATES_PER_PAIR_REGION:
		for row in lex_order:
			_add_selected_critical(selected, selected_ids, row, "LEXICOGRAPHIC_REGION_CRITICAL_CANDIDATE")
			if selected.size() >= MAX_CRITICAL_CANDIDATES_PER_PAIR_REGION: break
	for row in selected:
		row["constraint_arrangement_region_id"] = region_id
	return selected

func _add_selected_critical(selected: Array[Dictionary], selected_ids: Dictionary, row: Dictionary, method: String) -> void:
	var identity: String = var_to_bytes(Vector2(row.position)).hex_encode()
	if selected_ids.has(identity):
		var selected_index: int = int(selected_ids[identity])
		var roles: Array = selected[selected_index].get("critical_roles", [])
		_append_critical_role(roles, method)
		selected[selected_index]["critical_roles"] = roles
		return
	if selected.size() >= MAX_CRITICAL_CANDIDATES_PER_PAIR_REGION: return
	var copy: Dictionary = row.duplicate(true)
	copy["method"] = method
	var roles: Array = copy.get("critical_roles", [])
	_append_critical_role(roles, method)
	copy["critical_roles"] = roles
	selected_ids[identity] = selected.size()
	selected.append(copy)

func _append_critical_role(roles: Array, role: String) -> void:
	if not roles.has(role): roles.append(role)
	roles.sort()

func _constraint_clearance(point: Vector2, cavity: Array[Vector2], arc_segments: Array[Dictionary]) -> float:
	var minimum: float = INF
	for index in range(cavity.size()): minimum = minf(minimum, _point_segment_distance(point, cavity[index], cavity[(index + 1) % cavity.size()]))
	for segment in arc_segments: minimum = minf(minimum, _point_segment_distance(point, Vector2(segment.a), Vector2(segment.b)))
	return minimum

func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment: Vector2 = b - a
	var length_squared: float = segment.length_squared()
	if length_squared == 0.0: return point.distance_to(a)
	var parameter: float = clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * parameter)

func _polygon_identity(polygon: Array[Vector2]) -> String:
	var values: Array[String] = []
	for point in polygon: values.append(var_to_bytes(point).hex_encode())
	values.sort()
	return "|".join(values)

func _single_support_pair_gate(realizer: RefCounted, context: Dictionary, id_a: String, id_b: String, point: Vector3, projected_point: Vector2, cutoff: float) -> Dictionary:
	var vertex_positions: Dictionary = Dictionary(context.get("vertex_positions", {})).duplicate()
	var projected_positions: Dictionary = Dictionary(context.get("projected_positions", {})).duplicate()
	var support_id: String = _support_id(point)
	if vertex_positions.has(support_id) or projected_positions.has(support_id): return {"valid": false, "reason": "candidate_support_identity_conflict"}
	vertex_positions[support_id] = point
	projected_positions[support_id] = projected_point
	var probe_context: Dictionary = context.duplicate(false)
	probe_context["vertex_positions"] = vertex_positions
	probe_context["projected_positions"] = projected_positions
	var ids: Array[String] = [id_a, id_b, support_id]
	ids.sort()
	var points: Array[Vector3] = [Vector3(vertex_positions[ids[0]]), Vector3(vertex_positions[ids[1]]), Vector3(vertex_positions[ids[2]])]
	var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	var cross_squared: float = cross.length_squared()
	if not is_finite(cross_squared) or cross_squared <= cutoff: return {"valid": false, "reason": "candidate_cross_squared_at_or_below_frozen_cutoff", "cross_squared": cross_squared}
	var domain: Dictionary = realizer.call("_r2_triangle_inside_domain", ids, probe_context)
	if not bool(domain.get("valid", false)): return {"valid": false, "reason": String(domain.get("reason", "candidate_domain_invalid"))}
	var arcs: Dictionary = realizer.call("_r2_triangle_respects_required_arcs", ids, probe_context)
	if not bool(arcs.get("valid", false)): return {"valid": false, "reason": String(arcs.get("reason", "candidate_arc_invalid"))}
	var centroid: Vector3 = (points[0] + points[1] + points[2]) / 3.0
	var reference_normal: Vector3 = Vector3(realizer.call("_r2_reference_normal", centroid, probe_context))
	var alignment: float = cross.normalized().dot(reference_normal)
	if not is_finite(alignment) or absf(alignment) <= 1.0e-8: return {"valid": false, "reason": "candidate_winding_reference_ambiguous", "alignment": alignment}
	var owner: Dictionary = realizer.call("_r2_owner_for_triangle", centroid, probe_context)
	if not bool(owner.get("valid", false)): return {"valid": false, "reason": String(owner.get("reason", "candidate_centroid_has_no_residual_owner"))}
	return {"valid": true, "cross_squared": cross_squared, "alignment": alignment, "owner": owner}

func _add_rejection(histogram: Dictionary, reason: String) -> void:
	histogram[reason] = int(histogram.get(reason, 0)) + 1

func _insert_witness_record(records: Array[Dictionary], position: Vector2, method: String) -> void:
	for record in records:
		if Vector2(record.get("position", Vector2.ZERO)) == position:
			if method < String(record.get("method", "")): record["method"] = method
			return
	records.append({"position": position, "method": method})

func _nearest_strict_interior_point(boundary_point: Vector2, interior_point: Vector2, domain: Array[Vector2]) -> Dictionary:
	if not boundary_point.is_finite() or not interior_point.is_finite() or not _point_strictly_inside(interior_point, domain):
		return {"valid": false, "reason": "active_boundary_interior_endpoint_invalid"}
	var lower: float = 0.0
	var upper: float = 1.0
	var best: Vector2 = interior_point
	for _iteration in range(32):
		var parameter: float = (lower + upper) * 0.5
		var candidate: Vector2 = boundary_point.lerp(interior_point, parameter)
		if _point_strictly_inside(candidate, domain):
			upper = parameter
			best = candidate
		else:
			lower = parameter
	if not _point_strictly_inside(best, domain): return {"valid": false, "reason": "active_boundary_interior_search_unresolved"}
	return {"valid": true, "position": best, "parameter": upper, "iterations": 32, "method": "BINARY_SEARCH_FIRST_STRICT_INTERIOR_ALONG_ZERO_PRIMITIVE_SEGMENT"}

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
