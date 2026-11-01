extends SceneTree

const Synthesizer := preload("res://tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd")
const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")

var assertions: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var synth: RefCounted = Synthesizer.new()
	_test_convex_clipping(synth)
	_test_projection_mapping(synth)
	_test_zero_primitive_ordering(synth)
	_test_zero_volume_classification(synth)
	_test_field_zero_edge_intersections()
	_test_constraint_intervals_and_cross_objective(synth)
	_test_support_identity_and_graph_digest(synth)
	_test_r2_candidate_gates()
	_test_constraint_guided_support_r2_triangulation(synth)
	_test_campaign_result_scope()
	_test_residual_owner_normalization(synth)
	if failures.is_empty():
		print("R12CXR_R5_CONTRACT_TESTS_PASS assertions=%d failures=0" % assertions)
		quit(0)
	else:
		printerr("R12CXR_R5_CONTRACT_TESTS_FAIL assertions=%d failures=%d details=%s" % [assertions, failures.size(), JSON.stringify(failures)])
		quit(2)

func _test_convex_clipping(synth: RefCounted) -> void:
	var subject: Array[Vector2] = [Vector2(-1, -1), Vector2(2, -1), Vector2(-1, 2)]
	var domain: Array[Vector2] = [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)]
	var clipped: Array[Vector2] = synth.call("_clip_convex", subject, domain)
	_expect(clipped.size() == 3, "clip_triangle_vertex_count")
	_expect(is_equal_approx(absf(float(synth.call("_signed_area", clipped))), 0.5), "clip_triangle_area")
	var witnesses: Array[Vector2] = synth.call("_interior_witnesses", clipped, domain)
	_expect(not witnesses.is_empty(), "clipped_domain_has_interior_witness")
	_expect(bool(synth.call("_point_strictly_inside", Vector2(0.2, 0.2), domain)), "strict_interior_point")
	_expect(not bool(synth.call("_point_strictly_inside", Vector2(0.5, 0.5), domain)), "boundary_point_not_in_strict_interior")
	var disjoint_subject: Array[Vector2] = [Vector2(2, 2), Vector2(3, 2), Vector2(2, 3)]
	var disjoint: Array[Vector2] = synth.call("_clip_convex", disjoint_subject, domain)
	_expect(disjoint.is_empty(), "disjoint_clip_empty")

func _test_projection_mapping(synth: RefCounted) -> void:
	var source: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN]
	var world: Array[Vector3] = [Vector3.ZERO, Vector3(2, 0, 0), Vector3(0, 0, 2)]
	var mapped: Dictionary = synth.call("_map_projected_point", Vector2(0.2, 0.3), source, world)
	_expect(bool(mapped.get("valid", false)), "projected_point_maps")
	if bool(mapped.get("valid", false)):
		var expected: Vector3 = Vector3(0.4, 0, 0.6)
		_expect(Vector3(mapped.get("world", Vector3.ZERO)).distance_squared_to(expected) <= 1.0e-12, "projected_mapping_preserves_barycentric_world_point")
		var weights: Array = mapped.get("weights", [])
		_expect(weights.size() == 3 and is_equal_approx(float(weights[0]) + float(weights[1]) + float(weights[2]), 1.0), "projected_mapping_weights_sum_to_one")
	var degenerate_source: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2(2, 0)]
	var degenerate: Dictionary = synth.call("_map_projected_point", Vector2.ZERO, degenerate_source, world)
	_expect(not bool(degenerate.get("valid", false)), "degenerate_projection_rejected")
	var projected: Vector2 = synth.call("_project", Vector3(2, 3, 4), {"projection_origin": Vector3.ONE, "projection_u": Vector3.RIGHT, "projection_v": Vector3.BACK})
	_expect(projected == Vector2(1, 3), "source_context_projection_keys_are_used")

func _test_zero_primitive_ordering(synth: RefCounted) -> void:
	var points: Array[Vector3] = [Vector3(1, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]
	var ordered: Array[Vector3] = synth.call("_order_zero_polygon", points)
	var reversed_input: Array[Vector3] = points.duplicate()
	reversed_input.reverse()
	var ordered_again: Array[Vector3] = synth.call("_order_zero_polygon", reversed_input)
	_expect(ordered.size() == 4, "quad_zero_primitive_keeps_four_vertices")
	_expect(ordered == ordered_again, "quad_order_independent_of_input_permutation")
	var facets: Array[Array] = synth.call("_triangulate_zero_polygon", ordered)
	_expect(facets.size() == 2, "quad_zero_primitive_has_two_facets")
	var triangle_input: Array[Vector3] = [Vector3.ZERO, Vector3.RIGHT, Vector3.BACK]
	var triangle: Array[Vector3] = synth.call("_order_zero_polygon", triangle_input)
	_expect(triangle.size() == 3, "triangle_zero_primitive_preserved")
	var line_input: Array[Vector3] = [Vector3.ZERO, Vector3.RIGHT]
	var line_result: Array[Vector3] = synth.call("_order_zero_polygon", line_input)
	_expect(line_result.is_empty(), "lower_dimensional_zero_primitive_rejected")

func _test_zero_volume_classification(synth: RefCounted) -> void:
	_expect(bool(synth.call("_all_samples_zero", [0.0, 0.0, 0.0, 0.0])), "all_zero_tetra_is_not_a_surface_facet")
	_expect(not bool(synth.call("_all_samples_zero", [0.0, 0.0, 0.0, 1.0])), "three_zero_face_is_a_surface_not_volume")

func _test_field_zero_edge_intersections() -> void:
	var realizer: RefCounted = Realizer.new()
	var tet_data: Dictionary = {
		"positions": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK],
		"samples": [-1.0, 1.0, 1.0, 1.0]
	}
	var points: Array[Vector3] = realizer.call("_tetra_zero_points", tet_data)
	_expect(points.size() == 3, "one_negative_tetra_creates_zero_triangle")
	for point in points:
		var bary: Dictionary = realizer.call("_tetra_barycentric", point, tet_data.positions)
		var scalar: float = 0.0
		if bool(bary.get("valid", false)):
			for index in range(4): scalar += float(bary.weights[index]) * float(tet_data.samples[index])
		_expect(bool(bary.get("valid", false)) and absf(scalar) <= 1.0e-7, "zero_intersection_remains_on_piecewise_linear_field")
	var quad_data: Dictionary = {"positions": [Vector3(1, 1, 1), Vector3(-1, -1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1)], "samples": [1.0, 1.0, -1.0, -1.0]}
	var quad: Array[Vector3] = realizer.call("_tetra_zero_points", quad_data)
	_expect(quad.size() == 4, "two_positive_two_negative_tetra_has_quad_zero_set")
	for point in quad:
		var field_check: Dictionary = Synthesizer.new().call("_validate_field_point", realizer, point, quad_data.positions, quad_data.samples, 1.0e-7, 1.0e-7)
		_expect(bool(field_check.get("valid", false)), "quad_edge_intersection_on_piecewise_linear_zero_set")
	var off_field: Dictionary = Synthesizer.new().call("_validate_field_point", realizer, Vector3(0, 0, 0.25), quad_data.positions, quad_data.samples, 1.0e-7, 1.0e-7)
	_expect(not bool(off_field.get("valid", false)), "off_field_support_rejected")

func _test_constraint_intervals_and_cross_objective(synth: RefCounted) -> void:
	var interval: Dictionary = synth.call("_clip_linear_interval", 0.0, 1.0, -1.0, 1.0)
	_expect(bool(interval.get("valid", false)) and not bool(interval.get("empty", true)) and is_equal_approx(float(interval.get("lower", -1.0)), 0.5) and is_equal_approx(float(interval.get("upper", -1.0)), 1.0), "linear_feasible_interval_clipped")
	var empty: Dictionary = synth.call("_clip_linear_interval", 0.0, 1.0, -1.0, -0.1)
	_expect(bool(empty.get("valid", false)) and bool(empty.get("empty", false)), "infeasible_linear_interval_rejected")
	var square: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var clipped: Dictionary = synth.call("_clip_segment_to_convex_polygon", Vector2(-2, 0), Vector2(2, 0), square)
	_expect(bool(clipped.get("valid", false)) and not bool(clipped.get("empty", true)) and is_equal_approx(float(clipped.get("lower", -1.0)), 0.25) and is_equal_approx(float(clipped.get("upper", -1.0)), 0.75), "segment_clipped_to_convex_domain")
	var reversed: Array[Vector2] = square.duplicate()
	reversed.reverse()
	_expect(not bool(synth.call("_clip_segment_to_convex_polygon", Vector2(-2, 0), Vector2(2, 0), reversed).get("valid", false)), "clockwise_domain_fails_closed")
	var maximum: Dictionary = synth.call("_maximize_cross_squared_on_segment", Vector3.ZERO, Vector3.RIGHT, Vector3(0.25, 0.1, 0), Vector3(0.25, 0.8, 0))
	_expect(bool(maximum.get("valid", false)) and Vector3(maximum.get("position", Vector3.ZERO)) == Vector3(0.25, 0.8, 0) and is_equal_approx(float(maximum.get("cross_squared", -1.0)), 0.64), "cross_squared_maximum_on_zero_set_segment")
	_expect(is_equal_approx(float(synth.call("_support_pair_objective", Vector3.ZERO, Vector3.RIGHT, Vector3(0.25, 0.8, 0))), 0.64), "support_pair_objective_matches_cutoff_metric")

func _test_support_identity_and_graph_digest(synth: RefCounted) -> void:
	var point: Vector3 = Vector3(0.25, -0.5, 0.75)
	_expect(String(synth.call("_binary32_position_identity", point)) == String(synth.call("_binary32_position_identity", point)), "binary_position_identity_deterministic")
	_expect(String(synth.call("_support_id", point)) == String(synth.call("_support_id", point)), "support_id_deterministic")
	_expect(String(synth.call("_binary32_position_identity", point)) != String(synth.call("_binary32_position_identity", point + Vector3(0.00001, 0, 0))), "distinct_binary_positions_not_merged")
	var rows: Dictionary = {}
	var first: Dictionary = {"support_id": "S", "binary32_position_identity": synth.call("_binary32_position_identity", point), "source_key": "z", "max_constraint_cross_squared": 1.0, "constraint_boundary_pair": ["A", "B"]}
	var better: Dictionary = {"support_id": "S", "binary32_position_identity": synth.call("_binary32_position_identity", point), "source_key": "a", "max_constraint_cross_squared": 2.0, "constraint_boundary_pair": ["C", "D"]}
	synth.call("_insert_support_by_identity", rows, first)
	synth.call("_insert_support_by_identity", rows, better)
	_expect(rows.size() == 1 and is_equal_approx(float(rows.values()[0].get("max_constraint_cross_squared", 0.0)), 2.0), "support_identity_deduplicates_and_keeps_best_score")
	var digest_rows_a: Array[String] = ["A|PASS", "B|REJECT"]
	var digest_rows_b: Array[String] = ["B|REJECT", "A|PASS"]
	var digest_a: String = synth.call("_candidate_graph_sha256", digest_rows_a)
	var digest_b: String = synth.call("_candidate_graph_sha256", digest_rows_b)
	_expect(digest_a == digest_b, "candidate_graph_digest_order_independent")

func _test_r2_candidate_gates() -> void:
	var realizer: RefCounted = Realizer.new()
	var triangle_positions: Dictionary = {"A": Vector3(0, 0, 0), "B": Vector3(2, 0, 0), "P": Vector3(1, 2, 0), "X": Vector3(0.5, 1, 0), "Y": Vector3(1.5, 1, 0)}
	var arc_context: Dictionary = {"projected_positions": {"A": Vector2(0, 0), "B": Vector2(2, 0), "P": Vector2(1, 2), "X": Vector2(0.5, 1), "Y": Vector2(1.5, 1)}, "residual_fixture": {"arc_map": [{"root_ids": ["X", "Y"], "arc_id": "TEST_ARC"}]}}
	var arc_triangle_ids: Array[String] = ["A", "B", "P"]
	var crossing: Dictionary = realizer.call("_r2_triangle_respects_required_arcs", arc_triangle_ids, arc_context)
	_expect(not bool(crossing.get("valid", false)), "topology_arc_crossing_is_rejected")
	arc_context.residual_fixture.arc_map = []
	var clear: Dictionary = realizer.call("_r2_triangle_respects_required_arcs", arc_triangle_ids, arc_context)
	_expect(bool(clear.get("valid", false)), "non_crossing_topology_arc_constraints_pass")
	var owner_context: Dictionary = _make_candidate_context(realizer, triangle_positions, [])
	var owner_in: Dictionary = realizer.call("_r2_owner_for_triangle", Vector3(1, 0.5, 0), owner_context)
	var owner_out: Dictionary = realizer.call("_r2_owner_for_triangle", Vector3(20, 20, 0), owner_context)
	_expect(bool(owner_in.get("valid", false)), "source_triangle_ownership_is_assigned")
	_expect(not bool(owner_out.get("valid", false)), "ownerless_candidate_is_rejected")
	var root_support_realizer: RefCounted = Realizer.new()
	var root_support_positions: Dictionary = {"A": Vector3(-1, 0, 0), "B": Vector3(1, 0, 0), "S1": Vector3(0, 1, 0)}
	var root_support_context: Dictionary = _make_candidate_context(root_support_realizer, root_support_positions, ["S1"])
	var root_support_ids: Array[String] = ["A", "B", "S1"]
	var root_support: Dictionary = root_support_realizer.call("_r2_get_candidate_triangle", root_support_ids, root_support_context)
	_expect(bool(root_support.get("valid", false)), "legal_root_support_triangle_passes")
	var support_realizer: RefCounted = Realizer.new()
	var support_positions: Dictionary = {"A": Vector3(0, -1, 0), "S1": Vector3(-1, 0, 0), "S2": Vector3(1, 0, 0)}
	var support_context: Dictionary = _make_candidate_context(support_realizer, support_positions, ["S1", "S2"])
	var support_support_ids: Array[String] = ["A", "S1", "S2"]
	var support_support: Dictionary = support_realizer.call("_r2_get_candidate_triangle", support_support_ids, support_context)
	_expect(bool(support_support.get("valid", false)), "legal_support_support_triangle_passes")
	var outside_realizer: RefCounted = Realizer.new()
	var outside_positions: Dictionary = {"A": Vector3(-1, 0, 0), "B": Vector3(1, 0, 0), "S1": Vector3(10, 10, 0)}
	var outside_context: Dictionary = _make_candidate_context(outside_realizer, outside_positions, ["S1"])
	_expect(not bool(outside_realizer.call("_r2_get_candidate_triangle", root_support_ids, outside_context).get("valid", false)), "off_domain_support_triangle_rejected")

func _make_candidate_context(realizer: RefCounted, positions: Dictionary, support_ids: Array[String]) -> Dictionary:
	var all_positions: Dictionary = positions.duplicate(true)
	all_positions["O0"] = Vector3(-5, -5, 0)
	all_positions["O1"] = Vector3(5, -5, 0)
	all_positions["O2"] = Vector3(0, 5, 0)
	var projected: Dictionary = {}
	for id_value in all_positions.keys():
		var point: Vector3 = all_positions[String(id_value)]
		projected[String(id_value)] = Vector2(point.x, point.y)
	var support_by_id: Dictionary = {}
	for support_id in support_ids:
		var support_point: Vector3 = all_positions[support_id]
		support_by_id[support_id] = {"support_id": support_id, "world_position": support_point, "accepted": true, "supported": true, "frozen_field_interpolated_residual": 0.0}
	var owner_triangle: Dictionary = {"triangle_id": "OWNER", "root_ids": ["O0", "O1", "O2"], "points": [all_positions.O0, all_positions.O1, all_positions.O2], "polygon_id": "owner", "source_polygon_ids": ["owner"], "normal": Vector3.BACK}
	var candidate_domain: Array[Vector2] = [Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)]
	realizer.set("_cxr_search_started_usec", Time.get_ticks_usec())
	realizer.set("_cxr_cavity_started_usec", Time.get_ticks_usec())
	realizer.set("_cxr_candidate_triangles_total", 0)
	realizer.set("_cxr_candidate_triangles_cavity", 0)
	return {"phase": "r4", "vertex_positions": all_positions, "projected_positions": projected, "support_by_id": support_by_id, "candidate_triangle_cache": {}, "candidate_triangle_rows": [], "candidate_edges": {}, "candidate_triangle_count": 0, "polygon": candidate_domain, "residual_fixture": {"arc_map": []}, "residual_triangles": [owner_triangle], "projection_origin": Vector3.ZERO, "projection_u": Vector3.RIGHT, "projection_v": Vector3.UP, "reference_normal": Vector3.BACK}

func _test_constraint_guided_support_r2_triangulation(synth: RefCounted) -> void:
	var realizer: RefCounted = Realizer.new()
	var tetra_positions: Array[Vector3] = [Vector3(1, 1, 1), Vector3(-1, -1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1)]
	var samples: Array[float] = [1.0, 1.0, -1.0, -1.0]
	var tetra_data: Dictionary = {"positions": tetra_positions, "samples": samples}
	var zero_points: Array[Vector3] = realizer.call("_tetra_zero_points", tetra_data)
	var domain: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	_expect(zero_points.size() == 4, "synthetic_zero_set_has_frozen_quad")
	var point_first_supports: Array[Vector3] = []
	for point in zero_points:
		if bool(synth.call("_point_strictly_inside", Vector2(point.x, point.y), domain)): point_first_supports.append(point)
	_expect(point_first_supports.is_empty(), "point_first_zero_edge_pool_misses_interior_support")
	var source_world: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(-1, 0, 0)]
	var source_projected: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	var clipped: Array[Vector2] = synth.call("_clip_convex", source_projected, domain)
	var witnesses: Array[Vector2] = synth.call("_interior_witnesses", clipped, domain)
	_expect(not witnesses.is_empty(), "constraint_clipped_zero_facet_finds_interior_witness")
	var repeated_witnesses: Array[Vector2] = synth.call("_interior_witnesses", clipped, domain)
	_expect(witnesses == repeated_witnesses, "constraint_witness_enumeration_deterministic")
	var support_projection: Vector2 = Vector2.ZERO
	for witness in witnesses:
		var score: float = float(synth.call("_support_pair_objective", Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(witness.x, witness.y, 0)))
		if score > float(synth.call("_support_pair_objective", Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(support_projection.x, support_projection.y, 0))): support_projection = witness
	var mapped: Dictionary = synth.call("_map_projected_point", support_projection, source_projected, source_world)
	_expect(bool(mapped.get("valid", false)), "constraint_critical_point_maps_to_zero_facet")
	var support_point: Vector3 = Vector3(mapped.get("world", Vector3.ZERO))
	var field: Dictionary = synth.call("_validate_field_point", realizer, support_point, tetra_positions, samples, 1.0e-7, 1.0e-7)
	_expect(bool(field.get("valid", false)), "synthesized_support_remains_on_exact_tetra_zero_set")
	var support_id: String = String(synth.call("_support_id", support_point))
	var support: Dictionary = {"support_id": support_id, "world_position": support_point, "accepted": true, "supported": true, "frozen_field_interpolated_residual": field.get("field_residual", NAN), "binary32_position_identity": synth.call("_binary32_position_identity", support_point)}
	var A: Vector3 = Vector3(1, 0, 0)
	var B: Vector3 = Vector3(0, 1, 0)
	var C: Vector3 = Vector3(-1, 0, 0)
	var D: Vector3 = Vector3(0, -1, 0)
	var base_a: Dictionary = realizer.call("_triangle", "BASE_ABC", "owner", ["A", "B", "C"], [A, B, C], "SYNTHETIC_POINT_FIRST_BASE", false)
	var base_b: Dictionary = realizer.call("_triangle", "BASE_ACD", "owner", ["A", "C", "D"], [A, C, D], "SYNTHETIC_POINT_FIRST_BASE", false)
	var source_triangles: Array[Dictionary] = [base_a, base_b]
	var synthesized_supports: Array[Dictionary] = [support]
	var d3: Dictionary = realizer.call("solve_r2_fixture_for_test", source_triangles, synthesized_supports, 1, [])
	_expect(bool(d3.get("valid", false)) and bool(d3.get("search_complete", false)), "existing_d3_search_triangulates_constraint_guided_support_fixture")
	if bool(d3.get("valid", false)):
		var best: Dictionary = d3.get("best_solution", {})
		_expect(best.get("selected_supports", []).size() == 1, "d3_uses_the_synthesized_interior_support")
		_expect(best.get("replacement_triangles", []).size() == 4, "d3_emits_complete_four_triangle_fan")

func _test_campaign_result_scope() -> void:
	var campaign_source: String = FileAccess.get_file_as_string("res://tests/prototypes/p3_1_r12_cxr_r5_campaign.gd")
	var synthesizer_source: String = FileAccess.get_file_as_string("res://tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd")
	_expect(campaign_source.contains("R5_EQUAL_LOD_PASS_DOWNSTREAM_PENDING"), "equal_lod_pass_does_not_claim_full_downstream_qualification")
	_expect(campaign_source.contains("UNKNOWN_NOT_CAPTURED_FINITE_WITNESS_MODEL_DOES_NOT_ENUMERATE_ALL_REGIONS"), "unmodeled_feasible_region_counts_are_not_reported_as_zero")
	_expect(synthesizer_source.contains("R5_SYNTHESIS_ENUMERATION_BEGIN") and synthesizer_source.contains("R12CXR_R5_EXECUTION_ID"), "target_attempt_marker_is_execution_scoped")

func _test_residual_owner_normalization(synth: RefCounted) -> void:
	var frozen_row: Dictionary = {"triangle_id": "FROZEN_OWNER", "triangle_vertices_world": [[0.0, 0.0, 0.0], [3.0, 0.0, 0.0], [0.0, 3.0, 0.0]]}
	var frozen: Dictionary = synth.call("_source_origins", [frozen_row])
	_expect(bool(frozen.get("valid", false)) and frozen.get("origins", []).size() == 1, "r4_triangle_vertices_world_owner_shape_is_supported")
	if bool(frozen.get("valid", false)):
		_expect(Vector3(frozen.origins[0].center) == Vector3(1.0, 1.0, 0.0), "r4_owner_centroid_is_reconstructed_from_frozen_vertices")
	var normalized_row: Dictionary = {"triangle_id": "NORMALIZED_OWNER", "points": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP]}
	_expect(bool(synth.call("_source_origins", [normalized_row]).get("valid", false)), "normalized_point_owner_shape_remains_supported")
	_expect(not bool(synth.call("_source_origins", [frozen_row, frozen_row.duplicate(true)]).get("valid", false)), "duplicate_residual_owner_identity_fails_closed")
	var frozen_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r4/residual-c6.json")
	_expect(Core.sha256(frozen_bytes) == "ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23", "actual_r4_residual_fixture_remains_pinned")
	var frozen_value: Variant = JSON.parse_string(frozen_bytes.get_string_from_utf8())
	var frozen_rows: Array = frozen_value.get("residuals", []) if typeof(frozen_value) == TYPE_DICTIONARY else []
	var frozen_result: Dictionary = synth.call("_source_origins", frozen_rows)
	_expect(bool(frozen_result.get("valid", false)), "actual_r4_residual_rows_normalize")
	_expect(frozen_result.get("origins", []).size() == frozen_rows.size(), "every_actual_r4_owner_row_is_retained")

func _expect(condition: bool, name: String) -> void:
	assertions += 1
	if not condition: failures.append(name)
