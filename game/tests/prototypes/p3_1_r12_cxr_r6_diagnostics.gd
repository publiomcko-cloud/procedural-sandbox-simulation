extends RefCounted

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const Synthesizer := preload("res://tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd")

const CUTOFF_SQUARED: float = 1.0e-12
const RESIDUAL_EPSILON: float = 1.0e-7
const BARYCENTRIC_EPSILON: float = 1.0e-7
const MAX_TETRAHEDRA: int = 3072
const REGION_SPECS: Array[Dictionary] = [
	{"id": "R015", "boundary_indices": [0, 1, 5]},
	{"id": "R145", "boundary_indices": [1, 4, 5]},
	{"id": "R124", "boundary_indices": [1, 2, 4]},
	{"id": "R234", "boundary_indices": [2, 3, 4]},
]

var _r6_clipped_piece_cache: Dictionary = {}
var _r6_face_edge_metric_cache: Dictionary = {}
var _r6_active_facet_signature: String = ""

func json_safe(value: Variant) -> Variant:
	if value is Vector3:
		return _vector3_array(value)
	if value is Vector2:
		return [value.x, value.y]
	if value is PackedFloat32Array or value is PackedFloat64Array or value is PackedInt32Array or value is PackedInt64Array or value is PackedByteArray:
		var packed_result: Array = []
		for item in value:
			packed_result.append(item)
		return packed_result
	if value is Array:
		var array_result: Array = []
		for item in value:
			array_result.append(json_safe(item))
		return array_result
	if value is Dictionary:
		var dictionary_result: Dictionary = {}
		for key in value.keys():
			dictionary_result[String(key)] = json_safe(value[key])
		return dictionary_result
	return value

func collect_zero_facet_inventory(realizer: RefCounted, values: PackedFloat32Array, roi: Dictionary) -> Dictionary:
	if values.is_empty() or roi.is_empty():
		return {"valid": false, "reason": "zero_inventory_input_missing"}
	var roi_min: Vector3 = Core.world_min(roi)
	var cells: Vector3i = Core.cell_counts(roi)
	var step: float = Core.step(roi)
	var dims: Vector3i = cells + Vector3i.ONE
	var tetrahedron_count: int = cells.x * cells.y * cells.z * Core.TETS.size()
	if not roi_min.is_finite() or not is_finite(step) or step <= 0.0 or values.size() != dims.x * dims.y * dims.z or tetrahedron_count != MAX_TETRAHEDRA:
		return {"valid": false, "reason": "zero_inventory_grid_identity_invalid", "dimensions": dims, "value_count": values.size(), "tetrahedra": tetrahedron_count}
	var synth: RefCounted = Synthesizer.new()
	var facets: Array[Dictionary] = []
	var vertex_records: Array[Dictionary] = []
	var histogram: Dictionary = {"abs_le_1e-8": 0, "abs_gt_1e-8_le_1e-7": 0, "abs_gt_1e-7": 0, "invalid_barycentric": 0}
	var barycentric_gate_failure_count: int = 0
	var primitive_classes: Dictionary = {"empty": 0, "point": 0, "segment": 0, "triangle": 0, "quad": 0}
	var tetrahedra_with_facets: int = 0
	var triangulated_facets: int = 0
	var unique_position_ids: Dictionary = {}
	for flat_index in range(tetrahedron_count):
		var tet_index: int = flat_index % Core.TETS.size()
		var cell_index: int = floori(float(flat_index) / float(Core.TETS.size()))
		var z: int = cell_index % cells.z
		var y: int = floori(float(cell_index) / float(cells.z)) % cells.y
		var x: int = floori(float(cell_index) / float(cells.z * cells.y))
		var cell: Vector3i = Vector3i(x, y, z)
		var tet_data: Dictionary = realizer.call("_tetra_data", cell, tet_index, values, dims, roi_min, step)
		if not bool(tet_data.get("valid", false)):
			return {"valid": false, "reason": "source_tetrahedron_invalid", "cell": cell, "tet_index": tet_index, "detail": tet_data}
		if _all_samples_zero(tet_data.samples):
			continue
		var source_rows: Array[Dictionary] = _zero_vertex_sources(tet_data)
		var points: Array[Vector3] = []
		for row in source_rows:
			points.append(Vector3(row.position))
		var official_points: Array[Vector3] = realizer.call("_tetra_zero_points", tet_data)
		if not _same_points(points, official_points):
			return {"valid": false, "reason": "zero_vertex_inventory_disagrees_with_frozen_constructor", "cell": cell, "tet_index": tet_index}
		var primitive_class: String = "empty" if points.is_empty() else "point" if points.size() == 1 else "segment" if points.size() == 2 else "triangle" if points.size() == 3 else "quad" if points.size() == 4 else "invalid"
		if primitive_class == "invalid":
			return {"valid": false, "reason": "tetra_zero_primitive_arity_invalid", "cell": cell, "tet_index": tet_index, "point_count": points.size()}
		primitive_classes[primitive_class] = int(primitive_classes.get(primitive_class, 0)) + 1
		if points.size() < 3:
			continue
		tetrahedra_with_facets += 1
		for index in range(source_rows.size()):
			var row: Dictionary = source_rows[index]
			var position: Vector3 = Vector3(row.position)
			var bary_result: Dictionary = realizer.call("_tetra_barycentric", position, tet_data.positions)
			var weights: Array = bary_result.get("weights", [])
			var valid_barycentric: bool = bool(bary_result.get("valid", false)) and weights.size() == 4
			var barycentric_gate_pass: bool = valid_barycentric
			for weight_value in weights:
				var weight: float = float(weight_value)
				if not is_finite(weight) or weight < -BARYCENTRIC_EPSILON or weight > 1.0 + BARYCENTRIC_EPSILON:
					barycentric_gate_pass = false
			var residual: float = _weighted_field_residual(weights, tet_data.samples)
			var absolute_residual: float = absf(residual) if is_finite(residual) else INF
			var bin_name: String = "invalid_barycentric"
			if valid_barycentric and is_finite(residual) and absolute_residual <= 1.0e-8:
				bin_name = "abs_le_1e-8"
			elif valid_barycentric and is_finite(residual) and absolute_residual <= RESIDUAL_EPSILON:
				bin_name = "abs_gt_1e-8_le_1e-7"
			elif valid_barycentric and is_finite(residual):
				bin_name = "abs_gt_1e-7"
			histogram[bin_name] = int(histogram.get(bin_name, 0)) + 1
			if valid_barycentric and not barycentric_gate_pass:
				barycentric_gate_failure_count += 1
			var identity: String = _position_identity(position)
			unique_position_ids[identity] = true
			row["cell_local"] = [cell.x, cell.y, cell.z]
			row["cell_global"] = [int(tet_data.global_cell.x), int(tet_data.global_cell.y), int(tet_data.global_cell.z)]
			row["tetrahedron_index"] = tet_index
			row["tetrahedron_id"] = "%d,%d,%d|tet:%d" % [int(tet_data.global_cell.x), int(tet_data.global_cell.y), int(tet_data.global_cell.z), tet_index]
			row["world_position_f32_hex"] = _position_bytes_hex(position)
			row["barycentric_weights"] = weights.duplicate()
			row["frozen_field_residual"] = residual if is_finite(residual) else "UNKNOWN_NOT_CAPTURED"
			row["absolute_residual"] = absolute_residual if is_finite(absolute_residual) else "UNKNOWN_NOT_CAPTURED"
			row["residual_gate_pass"] = is_finite(residual) and absolute_residual <= RESIDUAL_EPSILON
			row["barycentric_gate_pass"] = barycentric_gate_pass
			row["validator_reason"] = "" if barycentric_gate_pass and is_finite(residual) and absolute_residual <= RESIDUAL_EPSILON else "support_field_residual_invalid"
			row["binary32_position_identity"] = identity
			vertex_records.append(row)
		var ordered: Array[Vector3] = synth.call("_order_zero_polygon", points)
		if ordered.size() < 3:
			continue
		var facet_triangles: Array = synth.call("_triangulate_zero_polygon", ordered)
		for facet_index in range(facet_triangles.size()):
			var triangle: Array = facet_triangles[facet_index]
			if triangle.size() != 3:
				return {"valid": false, "reason": "zero_facet_triangle_arity_invalid", "cell": cell, "tet_index": tet_index, "facet_index": facet_index}
			facets.append({"cell_local": [cell.x, cell.y, cell.z], "cell_global": [int(tet_data.global_cell.x), int(tet_data.global_cell.y), int(tet_data.global_cell.z)], "tetrahedron_index": tet_index, "tetrahedron_id": "%d,%d,%d|tet:%d" % [int(tet_data.global_cell.x), int(tet_data.global_cell.y), int(tet_data.global_cell.z), tet_index], "facet_index": facet_index, "points": [Vector3(triangle[0]), Vector3(triangle[1]), Vector3(triangle[2])], "tetrahedron_positions": tet_data.positions.duplicate(), "tetrahedron_samples": tet_data.samples.duplicate()})
			triangulated_facets += 1
	return {"valid": true, "tetrahedra_visited": tetrahedron_count, "tetrahedra_with_zero_facets": tetrahedra_with_facets, "primitive_classes": primitive_classes, "triangulated_zero_facets": triangulated_facets, "tetra_zero_vertex_occurrences": vertex_records.size(), "unique_binary32_position_count": unique_position_ids.size(), "residual_histogram": histogram, "residual_over_epsilon_count": int(histogram.get("abs_gt_1e-7", 0)), "barycentric_gate_failure_count": barycentric_gate_failure_count, "vertex_records": vertex_records, "facets": facets}

func audit_r6a_representability(realizer: RefCounted, values: PackedFloat32Array, roi: Dictionary) -> Dictionary:
	if values.is_empty() or roi.is_empty():
		return {"valid": false, "reason": "r6a_input_missing"}
	var roi_min: Vector3 = Core.world_min(roi)
	var cells: Vector3i = Core.cell_counts(roi)
	var step: float = Core.step(roi)
	var dims: Vector3i = cells + Vector3i.ONE
	var tetrahedron_count: int = cells.x * cells.y * cells.z * Core.TETS.size()
	if values.size() != dims.x * dims.y * dims.z or tetrahedron_count != MAX_TETRAHEDRA:
		return {"valid": false, "reason": "r6a_grid_identity_invalid", "tetrahedra": tetrahedron_count, "value_count": values.size()}
	var rows: Array[Dictionary] = []
	var before_histogram: Dictionary = {"abs_le_1e-8": 0, "abs_gt_1e-8_le_1e-7": 0, "abs_gt_1e-7": 0, "invalid_barycentric": 0}
	var after_histogram: Dictionary = {"abs_le_1e-8": 0, "abs_gt_1e-8_le_1e-7": 0, "abs_gt_1e-7": 0, "invalid_barycentric": 0}
	var corrected_count: int = 0
	var changed_count: int = 0
	var unresolved_count: int = 0
	var best_candidate_count: int = 0
	var barycentric_gate_failure_count: int = 0
	var corrected_barycentric_gate_failure_count: int = 0
	var unique_corrected_positions: Dictionary = {}
	for flat_index in range(tetrahedron_count):
		var tet_index: int = flat_index % Core.TETS.size()
		var cell_index: int = floori(float(flat_index) / float(Core.TETS.size()))
		var z: int = cell_index % cells.z
		var y: int = floori(float(cell_index) / float(cells.z)) % cells.y
		var x: int = floori(float(cell_index) / float(cells.z * cells.y))
		var cell: Vector3i = Vector3i(x, y, z)
		var tet_data: Dictionary = realizer.call("_tetra_data", cell, tet_index, values, dims, roi_min, step)
		if not bool(tet_data.get("valid", false)):
			return {"valid": false, "reason": "r6a_source_tetrahedron_invalid", "cell": cell, "tet_index": tet_index, "detail": tet_data}
		for source_value in realizer.call("corrected_tetra_zero_sources", tet_data):
			if typeof(source_value) != TYPE_DICTIONARY:
				return {"valid": false, "reason": "r6a_source_row_invalid", "cell": cell, "tet_index": tet_index}
			var row: Dictionary = source_value.duplicate(true)
			row["cell_local"] = [cell.x, cell.y, cell.z]
			row["cell_global"] = [int(tet_data.global_cell.x), int(tet_data.global_cell.y), int(tet_data.global_cell.z)]
			row["tetrahedron_index"] = tet_index
			row["tetrahedron_id"] = "%d,%d,%d|tet:%d" % [int(tet_data.global_cell.x), int(tet_data.global_cell.y), int(tet_data.global_cell.z), tet_index]
			var before_residual: float = float(row.get("original_field_residual", NAN))
			var after_residual: float = float(row.get("corrected_field_residual", NAN))
			var before_valid: bool = bool(row.get("original_barycentric_valid", false)) and is_finite(before_residual)
			var after_valid: bool = bool(row.get("accepted", false)) and bool(row.get("corrected_barycentric_gate_pass", false)) and is_finite(after_residual)
			var before_bin: String = _residual_histogram_bin(before_valid, before_residual)
			var after_bin: String = _residual_histogram_bin(bool(row.get("corrected_barycentric_valid", false)), after_residual)
			before_histogram[before_bin] = int(before_histogram.get(before_bin, 0)) + 1
			after_histogram[after_bin] = int(after_histogram.get(after_bin, 0)) + 1
			if not bool(row.get("original_barycentric_gate_pass", false)):
				barycentric_gate_failure_count += 1
			if not bool(row.get("corrected_barycentric_gate_pass", false)):
				corrected_barycentric_gate_failure_count += 1
			if after_valid:
				corrected_count += 1
				var corrected: Vector3 = Vector3(row.corrected_position)
				unique_corrected_positions[_position_identity(corrected)] = true
			if Vector3(row.corrected_position) != Vector3(row.original_position):
				changed_count += 1
			if String(row.get("correction_search_state", "")).begins_with("best_same_tetra_residual"):
				best_candidate_count += 1
			if String(row.get("correction_search_state", "")).begins_with("no_valid_point"):
				unresolved_count += 1
			row["original_position_f32_hex"] = _position_bytes_hex(Vector3(row.original_position))
			row["corrected_position_f32_hex"] = _position_bytes_hex(Vector3(row.corrected_position))
			rows.append(row)
	return {"valid": true, "tetrahedra_visited": tetrahedron_count, "zero_vertex_occurrences": rows.size(), "unique_corrected_binary32_positions": unique_corrected_positions.size(), "original_residual_histogram": before_histogram, "corrected_residual_histogram": after_histogram, "original_residual_over_epsilon_count": int(before_histogram.get("abs_gt_1e-7", 0)), "corrected_residual_over_epsilon_count": int(after_histogram.get("abs_gt_1e-7", 0)), "original_barycentric_gate_failure_count": barycentric_gate_failure_count, "corrected_barycentric_gate_failure_count": corrected_barycentric_gate_failure_count, "corrected_occurrence_count": corrected_count, "corrected_gate_failure_count": rows.size() - corrected_count, "best_same_tetra_candidate_count": best_candidate_count, "changed_occurrence_count": changed_count, "unresolved_occurrence_count": unresolved_count, "vertices": rows}

func _residual_histogram_bin(barycentric_valid: bool, residual: float) -> String:
	if not barycentric_valid or not is_finite(residual):
		return "invalid_barycentric"
	var absolute_residual: float = absf(residual)
	if absolute_residual <= 1.0e-8:
		return "abs_le_1e-8"
	if absolute_residual <= RESIDUAL_EPSILON:
		return "abs_gt_1e-8_le_1e-7"
	return "abs_gt_1e-7"

func analyze_owner_overlap(fixture: Dictionary) -> Dictionary:
	var cavity_polygon: PackedVector2Array = _vector2_polygon(fixture.get("projection", {}).get("polygon", []))
	if cavity_polygon.size() < 3:
		return {"valid": false, "reason": "frozen_cavity_polygon_invalid"}
	var cavity_area: float = absf(_signed_area(cavity_polygon))
	var owner_rows: Array[Dictionary] = []
	var total_intersection_area: float = 0.0
	for owner_value in fixture.get("owner_triangles", []):
		if typeof(owner_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "owner_triangle_record_invalid"}
		var owner: Dictionary = owner_value
		var triangle: PackedVector2Array = _vector2_polygon(owner.get("projected", []))
		if triangle.size() != 3:
			return {"valid": false, "reason": "owner_triangle_projection_invalid", "triangle_id": owner.get("triangle_id", "")}
		var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(triangle, cavity_polygon)
		var area: float = 0.0
		for polygon in clipped:
			area += absf(_signed_area(polygon))
		total_intersection_area += area
		owner_rows.append({"triangle_id": String(owner.get("triangle_id", "")), "source_polygon_ids": owner.get("source_polygon_ids", []).duplicate(), "intersection_area": area, "positive_area_overlap": area > 0.0, "intersection_polygon_count": clipped.size()})
	owner_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.triangle_id) < String(b.triangle_id))
	return {"valid": true, "cavity_projected_area": cavity_area, "owner_triangles": owner_rows, "total_owner_intersection_area": total_intersection_area, "positive_area_owner_count": _positive_owner_count(owner_rows), "seed_only_owner_domain_incompatible": _positive_owner_count(owner_rows) == 0}

func analyze_subregions(realizer: RefCounted, fixture: Dictionary, facets: Array[Dictionary]) -> Dictionary:
	var projection: Dictionary = fixture.get("projection", {})
	var origin: Vector3 = _as_vector3(projection.get("origin", []))
	var axis_u: Vector3 = _as_vector3(projection.get("axis_u", []))
	var axis_v: Vector3 = _as_vector3(projection.get("axis_v", []))
	if not origin.is_finite() or not axis_u.is_finite() or not axis_v.is_finite() or axis_u.length_squared() <= 1.0e-20 or axis_v.length_squared() <= 1.0e-20:
		return {"valid": false, "reason": "frozen_projection_basis_invalid"}
	var cycle: Array = fixture.get("boundary_cycle", [])
	if cycle.size() != 6:
		return {"valid": false, "reason": "frozen_boundary_cycle_arity_invalid", "boundary_cycle_size": cycle.size()}
	var root_positions: Dictionary = {}
	for root_value in fixture.get("root_positions", []):
		if typeof(root_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "frozen_root_position_row_invalid"}
		var root: Dictionary = root_value
		root_positions[String(root.get("root_id", ""))] = _as_vector3(root.get("world", []))
	var boundary_world: Array[Vector3] = []
	var boundary_projected: Array[Vector2] = []
	for root_id_value in cycle:
		var root_id: String = String(root_id_value)
		if not root_positions.has(root_id):
			return {"valid": false, "reason": "frozen_boundary_root_position_missing", "root_id": root_id}
		var point: Vector3 = Vector3(root_positions[root_id])
		boundary_world.append(point)
		boundary_projected.append(_project(point, origin, axis_u, axis_v))
	var direct_arc_edges: Dictionary = {}
	var boundary_edge_set: Dictionary = {}
	for boundary_index in range(6):
		boundary_edge_set[_edge_key(boundary_index, (boundary_index + 1) % 6)] = true
	for arc_value in fixture.get("local_topology_obligations", []):
		if typeof(arc_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "local_topology_arc_row_invalid"}
		var arc: Dictionary = arc_value
		var ids: Array = arc.get("root_ids", [])
		if ids.size() == 2:
			var index_a: int = cycle.find(String(ids[0]))
			var index_b: int = cycle.find(String(ids[1]))
			if index_a >= 0 and index_b >= 0:
				var arc_edge_key: String = _edge_key(index_a, index_b)
				if not boundary_edge_set.has(arc_edge_key):
					direct_arc_edges[arc_edge_key] = true
	var expected_direct_arcs: Array[String] = ["1-4", "1-5", "2-4"]
	var observed_direct_arcs: Array[String] = []
	for arc_edge_key in direct_arc_edges.keys():
		observed_direct_arcs.append(String(arc_edge_key))
	observed_direct_arcs.sort()
	if observed_direct_arcs != expected_direct_arcs:
		return {"valid": false, "reason": "frozen_direct_arc_partition_mismatch", "expected": expected_direct_arcs, "observed": observed_direct_arcs}
	var all_edge_rows: Array[Dictionary] = []
	var region_cache: Array[Dictionary] = []
	for region_spec in REGION_SPECS:
		var indices: Array = region_spec.get("boundary_indices", [])
		var region_world: Array[Vector3] = []
		var region_projected: Array[Vector2] = []
		for boundary_index_value in indices:
			var boundary_index: int = int(boundary_index_value)
			region_world.append(boundary_world[boundary_index])
			region_projected.append(boundary_projected[boundary_index])
		if _signed_area(region_projected) < 0.0:
			var world_swap: Vector3 = region_world[1]
			var projected_swap: Vector2 = region_projected[1]
			region_world[1] = region_world[2]
			region_projected[1] = region_projected[2]
			region_projected[2] = projected_swap
			region_world[2] = world_swap
		var region_edge_rows: Array[Dictionary] = []
		var clipped_facets: Array[Dictionary] = []
		for facet in facets:
			var source_points: Array = facet.get("points", [])
			if source_points.size() != 3:
				return {"valid": false, "reason": "zero_facet_triangle_invalid", "facet": facet}
			var clipped_world: Array[Vector3] = _clip_world_triangle_to_region(source_points, region_projected, origin, axis_u, axis_v)
			if clipped_world.is_empty():
				continue
			clipped_facets.append({"facet": facet, "points": clipped_world})
		for edge_index in range(3):
			var local_a: int = int(indices[edge_index])
			var local_b: int = int(indices[(edge_index + 1) % 3])
			var a: Vector3 = boundary_world[local_a]
			var b: Vector3 = boundary_world[local_b]
			var edge_key: String = _edge_key(local_a, local_b)
			var extreme_rows: Array[Dictionary] = []
			var maximum: float = -INF
			var best_point: Vector3 = Vector3.ZERO
			var best_facet: Dictionary = {}
			var best_polygon: Array[Vector3] = []
			for clipped_value in clipped_facets:
				var clipped: Dictionary = clipped_value
				var facet: Dictionary = clipped.facet
				var polygon: Array = clipped.points
				for extreme_index in range(polygon.size()):
					var point: Vector3 = Vector3(polygon[extreme_index])
					var cross_squared: float = _cross_squared(a, b, point)
					extreme_rows.append({"tetrahedron_id": String(facet.tetrahedron_id), "facet_index": int(facet.facet_index), "extreme_index": extreme_index, "world_position": _vector3_array(point), "cross_squared": cross_squared})
					if cross_squared > maximum:
						maximum = cross_squared
						best_point = point
						best_facet = facet
						best_polygon = polygon
			var witness: Dictionary = _interior_witness(realizer, a, b, best_point, best_polygon, region_projected, origin, axis_u, axis_v, best_facet, maximum)
			var edge_row: Dictionary = {"region_id": String(region_spec.id), "edge_id": edge_key, "boundary_indices": [local_a, local_b], "world_edge": [_vector3_array(a), _vector3_array(b)], "is_direct_topology_arc": direct_arc_edges.has(edge_key), "clipped_zero_facet_count": clipped_facets.size(), "extreme_point_count": extreme_rows.size(), "extreme_point_evaluations": extreme_rows, "continuous_max_cross_squared": maximum if is_finite(maximum) else "UNKNOWN_NOT_CAPTURED", "strictly_above_frozen_cutoff": is_finite(maximum) and maximum > CUTOFF_SQUARED, "cutoff_margin": maximum - CUTOFF_SQUARED if is_finite(maximum) else "UNKNOWN_NOT_CAPTURED", "maximizing_tetrahedron_id": String(best_facet.get("tetrahedron_id", "")), "maximizing_facet_index": int(best_facet.get("facet_index", -1)), "maximizing_point": _vector3_array(best_point) if is_finite(maximum) else "UNKNOWN_NOT_CAPTURED", "interior_witness": witness}
			region_edge_rows.append(edge_row)
			all_edge_rows.append(edge_row)
		region_cache.append({"id": String(region_spec.id), "indices": indices.duplicate(), "edges": region_edge_rows})
	return {"valid": true, "regions": region_cache, "edge_maxima": all_edge_rows, "direct_arc_edge_count": direct_arc_edges.size(), "cutoff": CUTOFF_SQUARED}

func boundary_realizability(subregions: Dictionary, boundary_cycle: Array) -> Dictionary:
	if boundary_cycle.size() != 6:
		return {"valid": false, "reason": "boundary_realizability_cycle_invalid"}
	var adjacent_region_by_edge: Dictionary = {"0-1": "R015", "1-2": "R124", "2-3": "R234", "3-4": "R234", "4-5": "R145", "0-5": "R015"}
	var by_key: Dictionary = {}
	for row_value in subregions.get("edge_maxima", []):
		if typeof(row_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "subregion_edge_row_invalid"}
		var row: Dictionary = row_value
		by_key[String(row.region_id) + "|" + String(row.edge_id)] = row
	var boundary_rows: Array[Dictionary] = []
	for index in range(6):
		var next_index: int = (index + 1) % 6
		var edge_key: String = _edge_key(index, next_index)
		var region_id: String = String(adjacent_region_by_edge.get(edge_key, ""))
		var row_key: String = region_id + "|" + edge_key
		if not by_key.has(row_key):
			return {"valid": false, "reason": "boundary_edge_subregion_maximum_missing", "edge_id": edge_key, "region_id": region_id}
		var edge_row: Dictionary = by_key[row_key]
		var witness: Dictionary = edge_row.get("interior_witness", {})
		boundary_rows.append({"edge_id": edge_key, "adjacent_subregion": region_id, "continuous_upper_bound_cross_squared": edge_row.get("continuous_max_cross_squared", "UNKNOWN_NOT_CAPTURED"), "upper_bound_complete_over_clipped_piecewise_linear_zero_set": true, "strictly_above_frozen_cutoff": bool(edge_row.get("strictly_above_frozen_cutoff", false)), "feasible_incident_triangle_witness": witness, "geometrically_unrealizable_boundary_edge": not bool(witness.get("valid", false))})
	return {"valid": true, "boundary_edges": boundary_rows, "geometrically_unrealizable_boundary_edges": boundary_rows.filter(func(row: Dictionary) -> bool: return bool(row.geometrically_unrealizable_boundary_edge)).map(func(row: Dictionary) -> String: return String(row.edge_id))}

## General R6-D edge audit. Each zero facet is clipped against every removed
## patch triangle, so the upper bound covers the entire projected cavity domain.
func analyze_patch_boundary(realizer: RefCounted, patch: Array[Dictionary], boundary_cycle: Array, root_positions: Dictionary, projection: Dictionary, facets: Array[Dictionary]) -> Dictionary:
	if patch.is_empty() or boundary_cycle.size() < 3:
		return {"valid": false, "reason": "r6_patch_boundary_input_invalid"}
	var origin: Vector3 = _as_vector3(projection.get("origin", [])); var axis_u: Vector3 = _as_vector3(projection.get("axis_u", [])); var axis_v: Vector3 = _as_vector3(projection.get("axis_v", []))
	if not origin.is_finite() or not axis_u.is_finite() or not axis_v.is_finite() or axis_u.length_squared() <= 1.0e-20 or axis_v.length_squared() <= 1.0e-20:
		return {"valid": false, "reason": "r6_projection_basis_invalid"}
	if _r6_active_facet_signature.is_empty(): _r6_active_facet_signature = _r6_facets_signature(facets)
	var patch_face_pieces: Dictionary = {}; var cache_hits: int = 0; var clip_evaluations: int = 0; var metric_cache_hits: int = 0; var metric_evaluations: int = 0
	var projection_key: String = PackedFloat32Array([origin.x, origin.y, origin.z, axis_u.x, axis_u.y, axis_u.z, axis_v.x, axis_v.y, axis_v.z]).to_byte_array().hex_encode()
	for patch_triangle in patch:
		var patch_points: Array = patch_triangle.get("points", [])
		if patch_points.size() != 3: continue
		var patch_projected: Array[Vector2] = []
		for point_value in patch_points: patch_projected.append(_project(Vector3(point_value), origin, axis_u, axis_v))
		var face_clip_key: String = String(patch_triangle.get("triangle_id", "")) + "|" + projection_key + "|" + _r6_vector2_array_key(patch_projected) + "|" + _r6_active_facet_signature
		if _r6_clipped_piece_cache.has(face_clip_key):
			patch_face_pieces[String(patch_triangle.get("triangle_id", ""))] = _r6_clipped_piece_cache[face_clip_key]; cache_hits += 1
			continue
		var face_pieces: Array[Dictionary] = []
		for facet in facets:
			var facet_points: Array = facet.get("points", [])
			if facet_points.size() != 3: return {"valid": false, "reason": "r6_zero_facet_invalid"}
			clip_evaluations += 1
			var clipped: Array[Vector3] = _clip_world_triangle_to_region([Vector3(facet_points[0]), Vector3(facet_points[1]), Vector3(facet_points[2])], patch_projected, origin, axis_u, axis_v)
			if not clipped.is_empty(): face_pieces.append({"points": clipped, "facet": facet, "domain_triangle": patch_projected})
		_r6_clipped_piece_cache[face_clip_key] = face_pieces
		patch_face_pieces[String(patch_triangle.get("triangle_id", ""))] = face_pieces
	var boundary_rows: Array[Dictionary] = []; var minimum_margin: float = INF
	for edge_index in range(boundary_cycle.size()):
		var a_id: String = String(boundary_cycle[edge_index]); var b_id: String = String(boundary_cycle[(edge_index + 1) % boundary_cycle.size()])
		if not root_positions.has(a_id) or not root_positions.has(b_id): return {"valid": false, "reason": "r6_boundary_root_position_missing", "edge": [a_id, b_id]}
		var a: Vector3 = Vector3(root_positions[a_id]); var b: Vector3 = Vector3(root_positions[b_id]); var maximum: float = -INF; var maximum_point: Vector3 = Vector3.ZERO; var maximum_facet: Dictionary = {}; var maximum_piece: Array[Vector3] = []; var maximum_domain: Array[Vector2] = []; var maximum_witness: Dictionary = {}; var piece_count: int = 0; var edge_id: String = String(realizer.call("_edge_key", a_id, b_id))
		for patch_triangle in patch:
			var face_id: String = String(patch_triangle.get("triangle_id", "")); var face_pieces: Array = patch_face_pieces.get(face_id, [])
			var metric: Dictionary = _r6_face_edge_metric(realizer, edge_id, a, b, face_id, face_pieces, origin, axis_u, axis_v)
			if bool(metric.get("cache_hit", false)): metric_cache_hits += 1
			else: metric_evaluations += 1
			piece_count += int(metric.get("piece_count", 0))
			if float(metric.get("maximum", -INF)) > maximum:
				maximum = float(metric.maximum); maximum_point = Vector3(metric.maximum_point); maximum_facet = metric.facet; maximum_piece = metric.piece; maximum_domain = metric.domain; maximum_witness = metric.witness
		var witness: Dictionary = maximum_witness
		var margin: float = maximum - CUTOFF_SQUARED if is_finite(maximum) else -INF
		minimum_margin = minf(minimum_margin, margin)
		boundary_rows.append({"edge_id": String(realizer.call("_edge_key", a_id, b_id)), "root_ids": [a_id, b_id], "continuous_upper_bound_cross_squared": maximum if is_finite(maximum) else "UNKNOWN_NOT_CAPTURED", "cutoff_margin": margin if is_finite(margin) else "UNKNOWN_NOT_CAPTURED", "strictly_above_frozen_cutoff": is_finite(maximum) and maximum > CUTOFF_SQUARED, "clipped_zero_facet_piece_count": piece_count, "feasible_incident_triangle_witness": witness, "geometrically_unrealizable_boundary_edge": not bool(witness.get("valid", false))})
	var blocked: Array[String] = []
	for row in boundary_rows:
		if bool(row.geometrically_unrealizable_boundary_edge): blocked.append(String(row.edge_id))
	return {"valid": true, "boundary_edges": boundary_rows, "geometrically_unrealizable_boundary_edges": blocked, "minimum_cutoff_margin": minimum_margin if is_finite(minimum_margin) else "UNKNOWN_NOT_CAPTURED", "boundary_edge_count": boundary_rows.size(), "clipped_piece_cache_hits": cache_hits, "zero_facet_clip_evaluations": clip_evaluations, "face_edge_metric_cache_hits": metric_cache_hits, "face_edge_metric_evaluations": metric_evaluations}

func _r6_face_edge_metric(realizer: RefCounted, edge_id: String, a: Vector3, b: Vector3, face_id: String, pieces: Array, origin: Vector3, axis_u: Vector3, axis_v: Vector3) -> Dictionary:
	var edge_positions: String = _position_bytes_hex(a) + "|" + _position_bytes_hex(b)
	var projection_key: String = PackedFloat32Array([origin.x, origin.y, origin.z, axis_u.x, axis_u.y, axis_u.z, axis_v.x, axis_v.y, axis_v.z]).to_byte_array().hex_encode()
	var cache_key: String = face_id + "|" + edge_id + "|" + edge_positions + "|" + projection_key + "|" + _r6_active_facet_signature
	if _r6_face_edge_metric_cache.has(cache_key):
		var cached: Dictionary = _r6_face_edge_metric_cache[cache_key].duplicate()
		cached["cache_hit"] = true
		return cached
	var maximum: float = -INF; var maximum_point: Vector3 = Vector3.ZERO; var maximum_facet: Dictionary = {}; var maximum_piece: Array[Vector3] = []; var maximum_domain: Array[Vector2] = []
	for piece_row in pieces:
		var clipped: Array = piece_row.get("points", []); var facet: Dictionary = piece_row.get("facet", {}); var domain_triangle: Array[Vector2] = piece_row.get("domain_triangle", [])
		for point_value in clipped:
			var point: Vector3 = Vector3(point_value); var cross_squared: float = _cross_squared(a, b, point)
			if cross_squared > maximum:
				maximum = cross_squared; maximum_point = point; maximum_facet = facet; maximum_piece = clipped; maximum_domain = domain_triangle
	var witness: Dictionary = _patch_edge_witness(realizer, a, b, maximum, maximum_point, maximum_piece, maximum_domain, maximum_facet, origin, axis_u, axis_v)
	var metric: Dictionary = {"maximum": maximum, "maximum_point": maximum_point, "facet": maximum_facet, "piece": maximum_piece, "domain": maximum_domain, "witness": witness, "piece_count": pieces.size(), "cache_hit": false}
	_r6_face_edge_metric_cache[cache_key] = metric.duplicate()
	return metric

func _r6_facets_signature(facets: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for facet in facets:
		var points: Array = facet.get("points", []); var point_bytes: Array[String] = []
		for point in points: point_bytes.append(PackedFloat32Array([Vector3(point).x, Vector3(point).y, Vector3(point).z]).to_byte_array().hex_encode())
		parts.append(String(facet.get("tetrahedron_id", "")) + ":" + str(facet.get("facet_index", -1)) + ":" + "|".join(point_bytes))
	return Core.sha256("\n".join(parts).to_utf8_buffer())

func _r6_vector2_array_key(points: Array[Vector2]) -> String:
	var parts: Array[String] = []
	for point in points: parts.append(PackedFloat32Array([point.x, point.y]).to_byte_array().hex_encode())
	return "|".join(parts)

func _patch_edge_witness(realizer: RefCounted, a: Vector3, b: Vector3, maximum: float, maximum_point: Vector3, clipped_piece: Array[Vector3], domain_triangle: Array[Vector2], facet: Dictionary, origin: Vector3, axis_u: Vector3, axis_v: Vector3) -> Dictionary:
	if not is_finite(maximum) or maximum <= CUTOFF_SQUARED or clipped_piece.is_empty() or facet.is_empty(): return {"valid": false, "reason": "continuous_upper_bound_not_above_cutoff"}
	var centroid: Vector3 = Vector3.ZERO
	for point in clipped_piece: centroid += point
	centroid /= float(clipped_piece.size())
	for lambda_value in [0.0, 1.0e-12, 1.0e-11, 1.0e-10, 1.0e-9, 1.0e-8, 1.0e-7, 1.0e-6, 1.0e-5, 1.0e-4, 1.0e-3, 1.0e-2, 1.0e-1]:
		var point: Vector3 = maximum_point.lerp(centroid, float(lambda_value)); var cross_squared: float = _cross_squared(a, b, point)
		if cross_squared <= CUTOFF_SQUARED: continue
		if not _strictly_inside_triangle(_project(point, origin, axis_u, axis_v), domain_triangle): continue
		var bary: Dictionary = realizer.call("_tetra_barycentric", point, facet.get("tetrahedron_positions", [])); var weights: Array = bary.get("weights", [])
		if not bool(bary.get("valid", false)) or weights.size() != 4: continue
		var residual: float = 0.0
		for i in range(4): residual += float(weights[i]) * float(facet.get("tetrahedron_samples", [])[i])
		if not is_finite(residual) or absf(residual) > RESIDUAL_EPSILON: continue
		var projected: Vector2 = _project(point, origin, axis_u, axis_v)
		return {"valid": true, "world_position": _vector3_array(point), "cross_squared": cross_squared, "continuous_field_residual": residual, "tetrahedron_id": String(facet.get("tetrahedron_id", "")), "facet_index": int(facet.get("facet_index", -1)), "source": "CLIPPED_ZERO_FACET_INTERIOR"}
	return {"valid": false, "reason": "no_strict_interior_witness_above_cutoff", "continuous_upper_bound_cross_squared": maximum}

## Best-first bounded search over causally adjacent face additions. The caller's
## evaluator must return a complete manifold and boundary-feasibility audit.
func bounded_cavity_search(initial_face_ids: Array, all_triangles: Array[Dictionary], adjacency: Dictionary, evaluator: Callable, limits: Dictionary = {}) -> Dictionary:
	var max_faces: int = int(limits.get("max_faces", 12)); var max_states: int = int(limits.get("max_states", 10000)); var max_queue: int = int(limits.get("max_queue", 2000)); var max_ms: int = int(limits.get("max_ms", 30000))
	if initial_face_ids.is_empty() or max_faces < initial_face_ids.size() or max_states < 1 or max_queue < 1 or max_ms < 1 or not evaluator.is_valid(): return {"status": "INVALID_INPUT", "reason": "r6_cavity_search_preflight_invalid"}
	var face_by_id: Dictionary = {}; var edge_faces: Dictionary = {}
	for triangle in all_triangles:
		var face_id: String = String(triangle.get("triangle_id", "")); var ids: Array = triangle.get("root_ids", [])
		if face_id.is_empty() or ids.size() != 3: return {"status": "INVALID_INPUT", "reason": "r6_mesh_face_identity_invalid"}
		face_by_id[face_id] = triangle
		for i in range(3):
			var key: String = _edge_key_ids(String(ids[i]), String(ids[(i + 1) % 3]))
			if not edge_faces.has(key): edge_faces[key] = []
			edge_faces[key].append(face_id)
	var initial: Array[String] = []; for value in initial_face_ids: initial.append(String(value))
	initial.sort()
	for face_id in initial:
		if not face_by_id.has(face_id): return {"status": "INVALID_INPUT", "reason": "r6_initial_face_missing", "face_id": face_id}
	var initial_audit: Dictionary = evaluator.call(initial)
	if not bool(initial_audit.get("valid", false)): return {"status": "INVALID_INPUT", "reason": "r6_initial_cavity_invalid", "audit": initial_audit}
	var queue: Array[Dictionary] = [{"face_ids": initial, "audit": initial_audit}]; var visited: Dictionary = {"|".join(initial): true}; var examined: int = 0; var generated: int = 1; var started: int = Time.get_ticks_msec(); var best: Dictionary = queue[0]
	while not queue.is_empty():
		if examined >= max_states: return {"status": "PARTIAL", "terminal_reason": "VISITED_STATE_CAP", "selected": best, "examined_states": examined, "generated_states": generated, "queue_depth": queue.size(), "elapsed_ms": Time.get_ticks_msec() - started}
		if Time.get_ticks_msec() - started >= max_ms: return {"status": "PARTIAL", "terminal_reason": "WALL_TIME_CAP", "selected": best, "examined_states": examined, "generated_states": generated, "queue_depth": queue.size(), "elapsed_ms": Time.get_ticks_msec() - started}
		queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _r6_cavity_state_less(a, b))
		var state: Dictionary = queue.pop_front(); examined += 1; var audit: Dictionary = state.audit
		if bool(audit.get("manifold", false)) and int(audit.get("boundary_components", 2147483647)) == 1 and audit.get("unrealizable_edges", []).is_empty(): return {"status": "FOUND", "selected": state, "examined_states": examined, "generated_states": generated, "queue_depth": queue.size(), "elapsed_ms": Time.get_ticks_msec() - started}
		var ids: Array[String] = state.face_ids
		if ids.size() >= max_faces: continue
		var candidate_set: Dictionary = {}
		for edge_value in audit.get("unrealizable_edges", []):
			var edge_key: String = String(edge_value)
			for face_id_value in edge_faces.get(edge_key, []):
				var face_id: String = String(face_id_value)
				if not ids.has(face_id): candidate_set[face_id] = true
		var candidates: Array[String] = []; for value in candidate_set.keys(): candidates.append(String(value)); candidates.sort()
		for face_id in candidates:
			var next_ids: Array[String] = ids.duplicate(); next_ids.append(face_id); next_ids.sort(); var signature: String = "|".join(next_ids)
			if visited.has(signature): continue
			if generated >= max_states: return {"status": "PARTIAL", "terminal_reason": "VISITED_STATE_CAP", "selected": best, "examined_states": examined, "generated_states": generated, "queue_depth": queue.size(), "elapsed_ms": Time.get_ticks_msec() - started}
			visited[signature] = true; generated += 1
			var next_audit: Dictionary = evaluator.call(next_ids)
			if not bool(next_audit.get("valid", false)): continue
			var next_state: Dictionary = {"face_ids": next_ids, "audit": next_audit}
			if _r6_cavity_state_less(next_state, best): best = next_state
			if queue.size() >= max_queue: return {"status": "PARTIAL", "terminal_reason": "PRIORITY_QUEUE_CAP", "selected": best, "examined_states": examined, "generated_states": generated, "queue_depth": queue.size(), "elapsed_ms": Time.get_ticks_msec() - started}
			queue.append(next_state)
	return {"status": "EXHAUSTED", "terminal_reason": "FINITE_CAUSAL_SEARCH_EXHAUSTED", "selected": best, "examined_states": examined, "generated_states": generated, "queue_depth": 0, "elapsed_ms": Time.get_ticks_msec() - started}

func _r6_cavity_state_less(a: Dictionary, b: Dictionary) -> bool:
	var af: Array = a.get("face_ids", []); var bf: Array = b.get("face_ids", [])
	if af.size() != bf.size(): return af.size() < bf.size()
	var aa: Dictionary = a.get("audit", {}); var ba: Dictionary = b.get("audit", {})
	var au: int = aa.get("unrealizable_edges", []).size(); var bu: int = ba.get("unrealizable_edges", []).size()
	if au != bu: return au < bu
	var am: float = float(aa.get("minimum_cutoff_margin", -INF)); var bm: float = float(ba.get("minimum_cutoff_margin", -INF))
	if am != bm: return am > bm
	var ac: int = int(aa.get("boundary_components", 2147483647)); var bc: int = int(ba.get("boundary_components", 2147483647))
	if ac != bc: return ac < bc
	return "|".join(af) < "|".join(bf)

func _edge_key_ids(a: String, b: String) -> String:
	return a + "\u001f" + b if a < b else b + "\u001f" + a

func search_patch_cavities(realizer: RefCounted, all_triangles: Array[Dictionary], initial_face_ids: Array, root_positions: Dictionary, projection: Dictionary, facets: Array[Dictionary], limits: Dictionary = {}) -> Dictionary:
	_r6_clipped_piece_cache.clear()
	_r6_face_edge_metric_cache.clear()
	_r6_active_facet_signature = _r6_facets_signature(facets)
	var evaluate: Callable = func(face_ids: Array) -> Dictionary:
		var patch: Array[Dictionary] = realizer.call("_r3_patch_rows_for_ids", all_triangles, face_ids)
		if patch.size() != face_ids.size(): return {"valid": false, "reason": "r6_candidate_patch_reconstruction_invalid"}
		var connectivity: Dictionary = realizer.call("_r3_patch_connectivity", patch)
		var boundary: Dictionary = realizer.call("_r3_derive_remaining_boundary", all_triangles, face_ids)
		if not bool(connectivity.get("valid", false)) or not bool(boundary.get("valid", false)): return {"valid": false, "reason": "r6_candidate_boundary_nonmanifold", "connectivity": connectivity, "boundary": boundary}
		var cycles: Dictionary = realizer.call("_r4_boundary_cycle_set", boundary)
		if not bool(cycles.get("valid", false)): return {"valid": false, "reason": "r6_candidate_boundary_cycles_invalid", "cycles": cycles}
		var cycle_rows: Array = cycles.get("cycles", []); var blocked: Array[String] = []; var minimum_margin: float = INF; var edge_audits: Array[Dictionary] = []
		for cycle_row in cycle_rows:
			var cycle: Array = cycle_row.get("root_ids", [])
			var edge_audit: Dictionary = analyze_patch_boundary(realizer, patch, cycle, root_positions, projection, facets)
			if not bool(edge_audit.get("valid", false)): return {"valid": false, "reason": "r6_candidate_edge_audit_invalid", "edge_audit": edge_audit}
			for edge in edge_audit.get("geometrically_unrealizable_boundary_edges", []): blocked.append(String(edge))
			minimum_margin = minf(minimum_margin, float(edge_audit.get("minimum_cutoff_margin", -INF)))
			edge_audits.append(edge_audit)
		blocked.sort()
		return {"valid": true, "manifold": true, "boundary_components": cycle_rows.size(), "unrealizable_edges": blocked, "minimum_cutoff_margin": minimum_margin, "boundary": boundary, "cycles": cycles, "edge_audits": edge_audits}
	var adjacency: Dictionary = realizer.call("_adjacency", all_triangles)
	return bounded_cavity_search(initial_face_ids, all_triangles, adjacency, evaluate, limits)

func _zero_vertex_sources(tet_data: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var positions: Array = tet_data.get("positions", [])
	var samples: Array = tet_data.get("samples", [])
	var edges: Array = [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]
	for edge_value in edges:
		var edge: Array = edge_value
		var ia: int = int(edge[0])
		var ib: int = int(edge[1])
		var va: float = float(samples[ia])
		var vb: float = float(samples[ib])
		var point: Vector3
		var t: float
		var include: bool = false
		if va == 0.0:
			point = Vector3(positions[ia])
			t = 0.0
			include = true
		elif vb == 0.0:
			point = Vector3(positions[ib])
			t = 1.0
			include = true
		elif (va < 0.0 and vb > 0.0) or (va > 0.0 and vb < 0.0):
			t = va / (va - vb)
			point = Vector3(positions[ia]).lerp(Vector3(positions[ib]), t)
			include = true
		if not include:
			continue
		var duplicate: bool = false
		for existing in rows:
			if Vector3(existing.position) == point:
				duplicate = true
				break
		if duplicate:
			continue
		rows.append({"position": point, "construction_edge_corner_indices": [ia, ib], "construction_edge_id": "corner:%d-%d" % [ia, ib], "interpolation_parameter": t, "endpoint_samples": [va, vb], "endpoint_world_positions": [_vector3_array(Vector3(positions[ia])), _vector3_array(Vector3(positions[ib]))]})
	return rows

func _clip_world_triangle_to_region(source_points: Array, region: Array[Vector2], origin: Vector3, axis_u: Vector3, axis_v: Vector3) -> Array[Vector3]:
	var polygon: Array[Vector3] = [Vector3(source_points[0]), Vector3(source_points[1]), Vector3(source_points[2])]
	var orientation: float = 1.0 if _signed_area(region) >= 0.0 else -1.0
	for edge_index in range(region.size()):
		var edge_a: Vector2 = region[edge_index]
		var edge_b: Vector2 = region[(edge_index + 1) % region.size()]
		var next_polygon: Array[Vector3] = []
		if polygon.is_empty():
			return next_polygon
		var previous: Vector3 = polygon[polygon.size() - 1]
		var previous_d: float = orientation * (edge_b - edge_a).cross(_project(previous, origin, axis_u, axis_v) - edge_a)
		var previous_inside: bool = previous_d >= -1.0e-12
		for current in polygon:
			var current_point: Vector3 = Vector3(current)
			var current_d: float = orientation * (edge_b - edge_a).cross(_project(current_point, origin, axis_u, axis_v) - edge_a)
			var current_inside: bool = current_d >= -1.0e-12
			if current_inside != previous_inside:
				var denominator: float = previous_d - current_d
				if absf(denominator) > 1.0e-30:
					var t: float = clampf(previous_d / denominator, 0.0, 1.0)
					next_polygon.append(previous.lerp(current_point, t))
			if current_inside:
				next_polygon.append(current_point)
			previous = current_point
			previous_d = current_d
			previous_inside = current_inside
		polygon = _deduplicate_world_polygon(next_polygon)
	return polygon

func _interior_witness(realizer: RefCounted, a: Vector3, b: Vector3, maximum_point: Vector3, clipped_polygon: Array[Vector3], region: Array[Vector2], origin: Vector3, axis_u: Vector3, axis_v: Vector3, facet: Dictionary, maximum: float) -> Dictionary:
	if not is_finite(maximum) or maximum <= CUTOFF_SQUARED or clipped_polygon.is_empty():
		return {"valid": false, "reason": "continuous_upper_bound_not_above_cutoff"}
	var centroid: Vector3 = Vector3.ZERO
	for point in clipped_polygon:
		centroid += Vector3(point)
	centroid /= float(clipped_polygon.size())
	var lambdas: Array[float] = [0.0, 1.0e-8, 1.0e-7, 1.0e-6, 1.0e-5, 1.0e-4, 1.0e-3, 1.0e-2, 1.0e-1]
	for lambda_value in lambdas:
		var point: Vector3 = maximum_point.lerp(centroid, lambda_value)
		var projected: Vector2 = _project(point, origin, axis_u, axis_v)
		if not _strictly_inside_triangle(projected, region):
			continue
		var cross_squared: float = _cross_squared(a, b, point)
		if cross_squared <= CUTOFF_SQUARED:
			continue
		var weights_result: Dictionary = realizer.call("_tetra_barycentric", point, facet.tetrahedron_positions)
		var field_residual: float = NAN
		var weights: Array = weights_result.get("weights", [])
		if bool(weights_result.get("valid", false)) and weights.size() == 4:
			field_residual = 0.0
			for index in range(4):
				field_residual += float(weights[index]) * float(facet.tetrahedron_samples[index])
		return {"valid": true, "world_position": _vector3_array(point), "cross_squared": cross_squared, "continuous_field_residual": field_residual if is_finite(field_residual) else "UNKNOWN_NOT_CAPTURED", "tetrahedron_id": String(facet.tetrahedron_id), "facet_index": int(facet.facet_index), "region_barycentric": _triangle_barycentric(projected, region)}
	return {"valid": false, "reason": "no_strict_interior_witness_above_cutoff", "continuous_upper_bound_cross_squared": maximum}

func _strictly_inside_triangle(point: Vector2, triangle: Array[Vector2]) -> bool:
	var weights: Array[float] = _triangle_barycentric(point, triangle)
	if weights.size() != 3:
		return false
	return weights[0] > 1.0e-9 and weights[1] > 1.0e-9 and weights[2] > 1.0e-9

func _triangle_barycentric(point: Vector2, triangle: Array[Vector2]) -> Array[float]:
	if triangle.size() != 3:
		return []
	var a: Vector2 = triangle[0]
	var b: Vector2 = triangle[1]
	var c: Vector2 = triangle[2]
	var denominator: float = (b - a).cross(c - a)
	if absf(denominator) <= 1.0e-30:
		return []
	var wb: float = (point - a).cross(c - a) / denominator
	var wc: float = (b - a).cross(point - a) / denominator
	return [1.0 - wb - wc, wb, wc]

func _all_samples_zero(samples: Array) -> bool:
	if samples.is_empty():
		return false
	for sample in samples:
		if float(sample) != 0.0:
			return false
	return true

func _same_points(a: Array[Vector3], b: Array[Vector3]) -> bool:
	if a.size() != b.size():
		return false
	for point in a:
		if not b.has(point):
			return false
	return true

func _deduplicate_world_polygon(points: Array[Vector3]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in points:
		if result.is_empty() or result[result.size() - 1] != point:
			result.append(point)
	if result.size() > 1 and result[0] == result[result.size() - 1]:
		result.pop_back()
	return result

func _positive_owner_count(rows: Array[Dictionary]) -> int:
	var result: int = 0
	for row in rows:
		if bool(row.get("positive_area_overlap", false)):
			result += 1
	return result

func _vector2_polygon(values: Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for value in values:
		if not (value is Array) or value.size() != 2:
			return PackedVector2Array()
		result.append(Vector2(float(value[0]), float(value[1])))
	return result

func _as_vector3(value: Variant) -> Vector3:
	if not (value is Array) or value.size() != 3:
		return Vector3(NAN, NAN, NAN)
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _project(point: Vector3, origin: Vector3, axis_u: Vector3, axis_v: Vector3) -> Vector2:
	var delta: Vector3 = point - origin
	return Vector2(delta.dot(axis_u), delta.dot(axis_v))

func _cross_squared(a: Vector3, b: Vector3, point: Vector3) -> float:
	return (b - a).cross(point - a).length_squared()

func _weighted_field_residual(weights: Array, samples: Array) -> float:
	if weights.size() != 4 or samples.size() != 4:
		return NAN
	var residual: float = 0.0
	for index in range(4):
		var weight: float = float(weights[index])
		var sample: float = float(samples[index])
		if not is_finite(weight) or not is_finite(sample):
			return NAN
		residual += weight * sample
	return residual if is_finite(residual) else NAN

func _edge_key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]

func _signed_area(points: Variant) -> float:
	var count: int = points.size()
	if count < 3:
		return 0.0
	var area: float = 0.0
	for index in range(count):
		var a: Vector2 = Vector2(points[index])
		var b: Vector2 = Vector2(points[(index + 1) % count])
		area += a.x * b.y - b.x * a.y
	return area * 0.5

func _position_identity(point: Vector3) -> String:
	return _position_bytes_hex(point)

func _position_bytes_hex(point: Vector3) -> String:
	var bytes: PackedByteArray = PackedFloat32Array([point.x, point.y, point.z]).to_byte_array()
	return bytes.hex_encode()

func _vector3_array(point: Vector3) -> Array[float]:
	return [point.x, point.y, point.z]
