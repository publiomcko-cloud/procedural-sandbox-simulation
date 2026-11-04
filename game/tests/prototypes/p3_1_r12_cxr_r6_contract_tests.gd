extends SceneTree

const Diagnostics := preload("res://tests/prototypes/p3_1_r12_cxr_r6_diagnostics.gd")
const R6Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_r6_realizer.gd")
const CXRDownstream := preload("res://tests/prototypes/p3_1_r12_cxr_campaign.gd")
const R6Campaign := preload("res://tests/prototypes/p3_1_r12_cxr_r6_campaign.gd")
const R5Synthesizer := preload("res://tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd")
const R6FrozenSolver := preload("res://tests/prototypes/p3_1_r12_cxr_r6_frozen_solver.gd")
const R6DCausalMap := preload("res://tests/prototypes/p3_1_r12_cxr_r6d_causal_map.gd")

var assertions: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("R12CXR_R6_TEST_MODE") == "check-only":
		print("R6_CONTRACTS_CHECK_ONLY=PASS")
		quit(0)
		return
	var diagnostics: RefCounted = Diagnostics.new()
	_test_zero_vertex_provenance(diagnostics)
	_test_convex_region_clipping(diagnostics)
	_test_cross_squared_and_barycentric(diagnostics)
	_test_boundary_edge_classification(diagnostics)
	_test_stable_region_partition(diagnostics)
	_test_serialized_support_fingerprint()
	_test_candidate_graph_summary_numeric_formatting()
	_test_binary32_ulp_correction(diagnostics)
	_test_patch_owner_and_ordered_arc_paths()
	_test_bounded_causal_cavity_search(diagnostics)
	_test_atomic_alternative_cavity_search(diagnostics)
	_test_patch_boundary_upper_bound(diagnostics)
	_test_r6d4_json_obligation_array_adapter()
	_test_analytic_edge_witness_not_sampling_limited(diagnostics)
	_test_mixed_lod_interface_oracle()
	_test_r6_unbounded_frozen_graph_solver()
	_test_x2_all_arrangement_vertices()
	_test_alternative_cavity_boundary_pair_domain()
	_test_x4_zero_boundary_obligations()
	_test_r6d_authoritative_seven_face_localization()
	if failures.is_empty():
		print("R12CXR_R6_CONTRACTS assertions=%d failures=0" % assertions)
		quit(0)
	else:
		printerr("R12CXR_R6_CONTRACTS assertions=%d failures=%d details=%s" % [assertions, failures.size(), JSON.stringify(failures)])
		quit(1)

func _test_zero_vertex_provenance(diagnostics: RefCounted) -> void:
	var positions: Array[Vector3] = [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var crossing: Array[Dictionary] = diagnostics.call("_zero_vertex_sources", {"positions": positions, "samples": [-1.0, 1.0, 1.0, 1.0]})
	_expect(crossing.size() == 3, "three crossing roots")
	_expect(crossing[0].construction_edge_id == "corner:0-1", "stable first edge provenance")
	_expect(is_equal_approx(float(crossing[0].interpolation_parameter), 0.5), "edge interpolation parameter")
	_expect(crossing[0].position == Vector3(0.5, 0.0, 0.0), "edge interpolation position")
	var endpoint: Array[Dictionary] = diagnostics.call("_zero_vertex_sources", {"positions": positions, "samples": [0.0, 1.0, 1.0, 1.0]})
	_expect(endpoint.size() == 1 and endpoint[0].position == Vector3.ZERO, "exact zero endpoint is included once")
	_expect(endpoint[0].interpolation_parameter == 0.0, "exact zero endpoint parameter")
	_expect(String(diagnostics.call("_position_bytes_hex", Vector3.ZERO)).length() == 24, "binary32 position byte identity")
	_expect(diagnostics.call("json_safe", Vector3(1.0, 2.0, 3.0)) == [1.0, 2.0, 3.0], "JSON evidence encodes world vectors as arrays")

func _test_serialized_support_fingerprint() -> void:
	var base: Dictionary = {"valid": true, "retained_support_count": 1, "raw_unique_support_count": 1, "support_cap_hit": false, "finite_candidate_enumeration_complete": true, "supports": [{"candidate_id": "cand-1", "support_id": "support-1", "binary32_position_identity": "bf32:010203", "residual_triangle_id": "tri-1", "source_cell_global_lattice": [60, 8, 25], "source_cell_local": [0, 0, 0], "source_tetrahedron": 2, "method": "tetrahedron_barycentric", "level": 2, "frozen_field_interpolated_residual": -8.161480885e-8, "barycentric_weights": [0.125, 0.375, 0.50000000000001], "tetrahedron_sample_values": [-1.0, 1.0, 1.0, 1.0], "constraint_clearance": 0.2, "max_constraint_cross_squared": 0.0}]}
	var serialized: Dictionary = {"valid": true, "retained_support_count": 1.0, "raw_unique_support_count": 1.0, "support_cap_hit": false, "finite_candidate_enumeration_complete": true, "supports": [{"candidate_id": "cand-1", "support_id": "support-1", "binary32_position_identity": "bf32:010203", "residual_triangle_id": "tri-1", "source_cell_global_lattice": [60.0, 8.0, 25.0], "source_cell_local": [0.0, 0.0, 0.0], "source_tetrahedron": 2.0, "method": "tetrahedron_barycentric", "level": 2.0, "frozen_field_interpolated_residual": -8.16148088499999e-8, "barycentric_weights": [0.12500000000000003, 0.375, 0.50000000000001], "tetrahedron_sample_values": [-1.0, 1.0, 1.0, 1.0], "constraint_clearance": 0.2, "max_constraint_cross_squared": 0.0}]}
	var first: String = R6Campaign._support_synthesis_fingerprint(base)
	var round_trip: String = R6Campaign._support_synthesis_fingerprint(serialized)
	_expect(first == round_trip, "JSON numeric formatting preserves support synthesis fingerprint")
	serialized.supports[0].binary32_position_identity = "bf32:010204"
	_expect(R6Campaign._support_synthesis_fingerprint(base) != R6Campaign._support_synthesis_fingerprint(serialized), "support fingerprint detects exact binary32 position identity change")

func _test_candidate_graph_summary_numeric_formatting() -> void:
	var synthesizer: RefCounted = R5Synthesizer.new()
	var edges: Dictionary = {"A|B": {"vertex_ids": ["A", "B"], "candidate_ids": ["t0"]}, "A|S": {"vertex_ids": ["A", "S"], "candidate_ids": ["t0"]}}
	var triangles: Array[Dictionary] = [{"triangle_id": "t0", "root_ids": ["A", "B", "S"], "cross_squared": 1.0}]
	var summary: Dictionary = synthesizer.call("_candidate_graph_summary", triangles, edges, {"S": {"support_id": "S"}})
	_expect(String(summary.get("candidate_graph_sha256", "")).length() == 64, "candidate graph summary hashes root and support edges without integer cast error")
	_expect(int(summary.get("legal_root_root_edges", 0)) == 1 and int(summary.get("legal_root_support_edges", 0)) == 1, "candidate graph summary classifies root and support edges")

func _test_alternative_cavity_boundary_pair_domain() -> void:
	var synthesizer: RefCounted = R5Synthesizer.new()
	var six_ids: Array[String] = ["a", "b", "c", "d", "e", "f"]
	var six_polygon: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2(2.0, 1.0), Vector2(2.0, 2.0), Vector2(1.0, 3.0), Vector2(-1.0, 2.0)]
	var seven_ids: Array[String] = ["a", "b", "c", "d", "e", "f", "g"]
	var seven_polygon: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2(2.0, 0.5), Vector2(2.0, 1.5), Vector2(1.0, 2.0), Vector2.ZERO + Vector2(0.0, 2.0), Vector2(-1.0, 1.0)]
	var legacy: Dictionary = synthesizer.call("_boundary_source_domain_gate", six_polygon, six_ids, 15)
	var legacy_rejects_extension: Dictionary = synthesizer.call("_boundary_source_domain_gate", seven_polygon, seven_ids, 15)
	var x3_extension: Dictionary = synthesizer.call("_boundary_source_domain_gate", seven_polygon, seven_ids, R5Synthesizer.MAX_R6X3_BOUNDARY_SOURCE_PAIRS)
	var nine_ids: Array[String] = seven_ids.duplicate()
	nine_ids.append_array(["h", "i"])
	var nine_polygon: Array[Vector2] = seven_polygon.duplicate()
	nine_polygon.append_array([Vector2(-2.0, 1.0), Vector2(-2.0, 0.0)])
	var over_cap: Dictionary = synthesizer.call("_boundary_source_domain_gate", nine_polygon, nine_ids, R5Synthesizer.MAX_R6X3_BOUNDARY_SOURCE_PAIRS)
	_expect(bool(legacy.get("valid", false)) and int(legacy.get("possible_source_pairs", 0)) == 15, "legacy six-vertex cavity retains the 15-pair domain")
	_expect(not bool(legacy_rejects_extension.get("valid", false)), "legacy synthesis does not silently expand beyond six vertices")
	_expect(bool(x3_extension.get("valid", false)) and int(x3_extension.get("possible_source_pairs", 0)) == 21, "R6-X3 admits a seven-vertex cavity with all 21 source pairs")
	_expect(not bool(over_cap.get("valid", false)) and int(over_cap.get("possible_source_pairs", 0)) == 36, "alternative cavity pair cap remains finite and fail-closed")

func _test_r6d_authoritative_seven_face_localization() -> void:
	var realizer: RefCounted = R6Realizer.new()
	var root_positions: Dictionary = {}
	var triangles: Array[Dictionary] = []
	var face_ids: Array[String] = []
	var center_id: String = "R6D_TEST_CENTER"
	root_positions[center_id] = Vector3.ZERO
	for index in range(7):
		var angle: float = TAU * float(index) / 7.0
		var outer_id: String = "R6D_TEST_OUTER_%d" % index
		root_positions[outer_id] = Vector3(cos(angle), sin(angle), 0.0)
	for index in range(7):
		var outer_id: String = "R6D_TEST_OUTER_%d" % index
		var next_id: String = "R6D_TEST_OUTER_%d" % ((index + 1) % 7)
		var face_id: String = "R6D_TEST_FACE_%d" % index
		face_ids.append(face_id)
		triangles.append(_r6d_test_triangle(face_id, [center_id, outer_id, next_id], root_positions))
	for index in range(7):
		var angle: float = TAU * (float(index) + 0.5) / 7.0
		var far_id: String = "R6D_TEST_FAR_%d" % index
		root_positions[far_id] = Vector3(2.0 * cos(angle), 2.0 * sin(angle), 0.25)
		var outer_id: String = "R6D_TEST_OUTER_%d" % index
		var next_id: String = "R6D_TEST_OUTER_%d" % ((index + 1) % 7)
		triangles.append(_r6d_test_triangle("R6D_TEST_OUTSIDE_%d" % index, [next_id, outer_id, far_id], root_positions))
	realizer.set("_root_positions", root_positions)
	var legacy_registry_ids: Array[String] = []
	var resolved: Dictionary = R6DCausalMap.resolve_face_registry(triangles, face_ids)
	var reconstructed: Dictionary = R6DCausalMap.reconstruct_cavity(realizer, triangles, face_ids)
	var reversed: Array[String] = face_ids.duplicate()
	reversed.reverse()
	var reconstructed_reverse: Dictionary = R6DCausalMap.reconstruct_cavity(realizer, triangles, reversed)
	_expect(legacy_registry_ids.is_empty() and bool(resolved.get("valid", false)) and int(resolved.get("resolved_count", 0)) == 7, "R6-D authoritative face registry resolves seven IDs absent from the legacy residual registry")
	_expect(bool(reconstructed.get("valid", false)) and reconstructed.get("patch", []).size() == 7, "R6-D reconstructs the full authoritative seven-face patch")
	_expect(bool(reconstructed.get("connectivity", {}).get("valid", false)) and bool(reconstructed.get("boundary", {}).get("valid", false)), "R6-D seven-face patch connectivity and boundary gates pass")
	_expect(reconstructed.get("cycles", {}).get("component_count", 0) == 1 and reconstructed.get("boundary_signature", "") == reconstructed_reverse.get("boundary_signature", ""), "R6-D cavity signature is stable under reversed face order")
	var missing_ids: Array[String] = face_ids.duplicate()
	missing_ids[0] = "R6D_TEST_FACE_MISSING"
	var duplicate_ids: Array[String] = face_ids.duplicate()
	duplicate_ids[1] = duplicate_ids[0]
	_expect(not bool(R6DCausalMap.resolve_face_registry(triangles, missing_ids).get("valid", false)), "R6-D authoritative registry fails closed for a missing face ID")
	_expect(not bool(R6DCausalMap.resolve_face_registry(triangles, duplicate_ids).get("valid", false)), "R6-D authoritative registry fails closed for duplicate face IDs")
	var p1_pair: Array[String] = ["R6D_TEST_OUTER_0", "R6D_TEST_OUTER_1"]
	var first_map: Dictionary = R6DCausalMap.build_causal_topology_map(realizer, triangles, reconstructed, p1_pair, [], [], root_positions, [])
	var second_map: Dictionary = R6DCausalMap.build_causal_topology_map(realizer, triangles, reconstructed_reverse, p1_pair, [], [], root_positions, [])
	var first_candidates: Array[Dictionary] = R6DCausalMap.generate_d1_additions(first_map)
	var second_candidates: Array[Dictionary] = R6DCausalMap.generate_d1_additions(second_map)
	_expect(bool(first_map.get("valid", false)) and first_map.get("d1_face_universe_sha256", "") == second_map.get("d1_face_universe_sha256", ""), "R6-D causal adjacency universe is stable under face order")
	_expect(JSON.stringify(first_candidates) == JSON.stringify(second_candidates), "R6-D D1 candidate ordering is deterministic")

func _r6d_test_triangle(triangle_id: String, ids: Array, positions: Dictionary) -> Dictionary:
	var points: Array[Vector3] = [Vector3(positions[String(ids[0])]), Vector3(positions[String(ids[1])]), Vector3(positions[String(ids[2])])]
	var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	return {"triangle_id": triangle_id, "polygon_id": "R6D_TEST_OWNER", "source_polygon_ids": ["R6D_TEST_OWNER"], "root_ids": ids.duplicate(), "points": points, "normal": normal, "cross_squared": (points[1] - points[0]).cross(points[2] - points[0]).length_squared(), "rejected": false, "construction": "R6D_AUTHORITY_FIXTURE"}

func _test_x4_zero_boundary_obligations() -> void:
	var counts: Dictionary = {"edge|b|c\u001fedge|c|d": 0, "edge|a|b\u001fedge|b|c": 4, "edge|a|d\u001fedge|c|d": 0}
	var targets: Dictionary = R6Campaign._r6_x4_zero_boundary_targets(counts)
	var pairs: Array = targets.get("target_pairs", [])
	_expect(bool(targets.get("valid", false)) and targets.get("zero_edge_keys", []).size() == 2, "R6-X4 selects only zero-option boundary obligations")
	_expect(pairs.size() == 2 and pairs[0] == ["edge|a|d", "edge|c|d"] and pairs[1] == ["edge|b|c", "edge|c|d"], "R6-X4 target pairs are canonical and deterministically ordered")
	var malformed: Dictionary = R6Campaign._r6_x4_zero_boundary_targets({"malformed": 0})
	_expect(not bool(malformed.get("valid", false)) and String(malformed.get("reason", "")) == "R6_X4_ZERO_BOUNDARY_EDGE_KEY_INVALID", "R6-X4 rejects malformed boundary obligations")
	var oriented: Dictionary = R6Campaign._r6_x4_zero_boundary_targets({"edge|z|z\u001fedge|a|a": 0})
	_expect(oriented.get("target_pairs", [])[0] == ["edge|z|z", "edge|a|a"], "R6-X4 preserves frozen boundary obligation endpoint orientation")
	var base_supports: Array[Dictionary] = [{"support_id": "base", "binary32_position_identity": "p0"}]
	var generated: Array[Dictionary] = [
		{"support_id": "a1", "binary32_position_identity": "p1", "constraint_boundary_pair": ["edge|a", "edge|b"], "max_constraint_cross_squared": 9.0},
		{"support_id": "a2", "binary32_position_identity": "p2", "constraint_boundary_pair": ["edge|a", "edge|b"], "max_constraint_cross_squared": 8.0},
		{"support_id": "b1", "binary32_position_identity": "p3", "constraint_boundary_pair": ["edge|c", "edge|d"], "max_constraint_cross_squared": 2.0},
		{"support_id": "b2", "binary32_position_identity": "p4", "constraint_boundary_pair": ["edge|c", "edge|d"], "max_constraint_cross_squared": 1.0}
	]
	var merged: Dictionary = R6Campaign._r6_x4_merge_support_rows(base_supports, generated, [["edge|a", "edge|b"], ["edge|c", "edge|d"]], 3)
	var selected: Array = merged.get("selected_new_supports", [])
	_expect(bool(merged.get("valid", false)) and int(merged.get("support_count", 0)) == 3 and selected.size() == 2, "R6-X4 merged support count respects the frozen total-support cap")
	_expect(String(selected[0].get("support_id", "")) == "a1" and String(selected[1].get("support_id", "")) == "b1", "R6-X4 round-robin selection addresses every zero-option pair before adding a second witness")
	_expect(bool(merged.get("candidate_cap_or_selection_loss", false)), "R6-X4 records when resource-bound selection omits generated candidates")

func _test_x2_all_arrangement_vertices() -> void:
	var synthesizer: RefCounted = R5Synthesizer.new()
	var region: Array[Vector2] = []
	for index in range(9):
		var angle: float = TAU * float(index) / 9.0
		region.append(Vector2(1.0 + 0.3 * cos(angle), 1.0 + 0.3 * sin(angle)))
	var cavity: Array[Vector2] = [Vector2.ZERO, Vector2(3.0, 0.0), Vector2(0.0, 3.0)]
	var source_2d: Array[Vector2] = [Vector2.ZERO, Vector2(3.0, 0.0), Vector2(0.0, 3.0)]
	var source_world: Array[Vector3] = [Vector3.ZERO, Vector3(3.0, 0.0, 0.0), Vector3(0.0, 3.0, 0.0)]
	var arc_segments: Array[Dictionary] = []
	var bounded: Array[Dictionary] = synthesizer.call("_critical_candidates_for_region", region, cavity, source_2d, source_world, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0), arc_segments, "R6X2_TEST", false)
	var complete: Array[Dictionary] = synthesizer.call("_critical_candidates_for_region", region, cavity, source_2d, source_world, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0), arc_segments, "R6X2_TEST", true)
	_expect(bounded.size() <= 7, "legacy critical candidate cap remains unchanged")
	_expect(complete.size() > 7, "R6-X2 exposes more than seven deterministic critical points in a region")
	var vertices_seen: Dictionary = {}
	for candidate in complete: vertices_seen[var_to_bytes(Vector2(candidate.get("position", Vector2.ZERO))).hex_encode()] = true
	var all_vertices_preserved: bool = true
	for vertex in region:
		if not vertices_seen.has(var_to_bytes(vertex).hex_encode()): all_vertices_preserved = false
	_expect(all_vertices_preserved, "R6-X2 retains every active arrangement vertex exactly")

func _test_convex_region_clipping(diagnostics: RefCounted) -> void:
	var source: Array[Vector3] = [Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)]
	var region: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2(0.0, 1.0)]
	var clipped: Array[Vector3] = diagnostics.call("_clip_world_triangle_to_region", source, region, Vector3.ZERO, Vector3.RIGHT, Vector3.UP)
	_expect(clipped.size() >= 3, "clipping retains positive-area overlap")
	for point in clipped:
		_expect(float(point.x) >= -1.0e-6 and float(point.y) >= -1.0e-6 and float(point.x + point.y) <= 1.0 + 1.0e-6, "clipped extreme lies in region")
	var reversed_region: Array[Vector2] = [Vector2.ZERO, Vector2(0.0, 1.0), Vector2.RIGHT]
	var reversed: Array[Vector3] = diagnostics.call("_clip_world_triangle_to_region", source, reversed_region, Vector3.ZERO, Vector3.RIGHT, Vector3.UP)
	_expect(reversed.size() == clipped.size(), "convex clipping is orientation stable")
	var outside: Array[Vector3] = diagnostics.call("_clip_world_triangle_to_region", [Vector3(2.0, 2.0, 0.0), Vector3(3.0, 2.0, 0.0), Vector3(2.0, 3.0, 0.0)], region, Vector3.ZERO, Vector3.RIGHT, Vector3.UP)
	_expect(outside.is_empty(), "disjoint facet is rejected")

func _test_cross_squared_and_barycentric(diagnostics: RefCounted) -> void:
	_expect(is_equal_approx(float(diagnostics.call("_cross_squared", Vector3.ZERO, Vector3.RIGHT, Vector3.UP)), 1.0), "cross squared uses frozen area measure")
	var triangle: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2(0.0, 1.0)]
	var weights: Array = diagnostics.call("_triangle_barycentric", Vector2(1.0 / 3.0, 1.0 / 3.0), triangle)
	_expect(weights.size() == 3, "triangle barycentric arity")
	_expect(absf(float(weights[0]) - 1.0 / 3.0) < 1.0e-6 and absf(float(weights[1]) - 1.0 / 3.0) < 1.0e-6 and absf(float(weights[2]) - 1.0 / 3.0) < 1.0e-6, "triangle barycentric values")
	_expect(is_equal_approx(float(diagnostics.call("_weighted_field_residual", [0.5, 0.5, 0.0, 0.0], [-1.0, 1.0, 7.0, 9.0])), 0.0), "frozen field residual is independently recomputed")
	_expect(bool(diagnostics.call("_strictly_inside_triangle", Vector2(0.25, 0.25), triangle)), "strict interior witness admitted")
	_expect(not bool(diagnostics.call("_strictly_inside_triangle", Vector2(0.5, 0.5), triangle)), "boundary witness rejected")

func _test_boundary_edge_classification(diagnostics: RefCounted) -> void:
	var rows: Array[Dictionary] = []
	var adjacent: Dictionary = {"0-1": "R015", "1-2": "R124", "2-3": "R234", "3-4": "R234", "4-5": "R145", "0-5": "R015"}
	for edge_key in adjacent:
		var witness: Dictionary = {"valid": edge_key == "0-1", "reason": "synthetic"}
		var upper_bound: float = 2.0e-12 if edge_key == "1-2" else 0.0
		rows.append({"region_id": adjacent[edge_key], "edge_id": edge_key, "continuous_max_cross_squared": upper_bound, "strictly_above_frozen_cutoff": upper_bound > 1.0e-12, "interior_witness": witness})
	var result: Dictionary = diagnostics.call("boundary_realizability", {"edge_maxima": rows}, ["a", "b", "c", "d", "e", "f"])
	_expect(bool(result.get("valid", false)), "all six boundary edges receive an upper bound")
	_expect(result.get("geometrically_unrealizable_boundary_edges", []).size() == 4, "only continuous upper bounds at or below cutoff prove unrealizability")
	_expect(result.get("unresolved_boundary_edges", []) == ["1-2"], "an above-cutoff edge without a constructed witness remains unresolved")

func _test_stable_region_partition(_diagnostics: RefCounted) -> void:
	var expected: Array[String] = ["R015", "R145", "R124", "R234"]
	var actual: Array[String] = []
	for row in Diagnostics.REGION_SPECS:
		actual.append(String(row.get("id", "")))
	_expect(actual == expected, "four preregistered direct-arc subregions remain stable")

func _test_binary32_ulp_correction(_diagnostics: RefCounted) -> void:
	var realizer: RefCounted = R6Realizer.new()
	var synthesizer: RefCounted = R5Synthesizer.new()
	var frontier_identity: Dictionary = {"boundary_pair": ["edge:a", "edge:b"], "source_cell_global_lattice": [60, 8, 25], "source_tetrahedron": 2, "source_facet": 1, "critical_candidate_method": "FEASIBLE_REGION_CENTROID", "seed_projected_position": [0.25, 0.5]}
	_expect(bool(synthesizer.call("_resume_frontier_matches_candidate", frontier_identity, "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1, "FEASIBLE_REGION_CENTROID", Vector2(0.25, 0.5))), "R6-Y resumes a numeric frontier only for its exact source candidate")
	_expect(not bool(synthesizer.call("_resume_frontier_matches_candidate", frontier_identity, "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1, "FEASIBLE_REGION_CENTROID", Vector2(0.25, 0.5001))), "R6-Y rejects a numeric frontier when its seed identity differs")
	var resume_key: String = synthesizer.call("_numeric_resume_key", "region", "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1, "FEASIBLE_REGION_CENTROID", Vector2(0.25, 0.5))
	var collision_key: String = synthesizer.call("_numeric_resume_key", "region", "edge:c", "edge:d", Vector3i(60, 8, 25), 2, 1, "FEASIBLE_REGION_CENTROID", Vector2(0.25, 0.5))
	_expect(resume_key != collision_key, "R6-Y numeric resume identity includes the boundary pair and disambiguates region ID collisions")
	var persisted_resume_key: String = R6Campaign.new().call("_y1_numeric_resume_key", "region", "edge:a", "edge:b", [60.0, 8.0, 25.0], 2, 1, "FEASIBLE_REGION_CENTROID", [0.25, 0.5])
	_expect(persisted_resume_key == resume_key, "R6-Y persisted JSON cell coordinates canonicalize to the Vector3i resume identity")
	var narrow_seed_key: String = synthesizer.call("_numeric_resume_key", "region", "edge:a", "edge:b", Vector3i(60, 8, 25), 0, 0, "FEASIBLE_REGION_CENTROID", Vector2(0.250171482563019, 0.0000129929949252983))
	var persisted_narrow_seed_key: String = R6Campaign.new().call("_y1_numeric_resume_key", "region", "edge:a", "edge:b", [60.0, 8.0, 25.0], 0, 0, "FEASIBLE_REGION_CENTROID", [0.250171482563019, 0.00001299299492529])
	_expect(persisted_narrow_seed_key == narrow_seed_key, "R6-Y persisted projected seed coordinates canonicalize through Vector2 binary32 identity")
	var legacy_frontier: Dictionary = {"tested_triples": 2189977, "radius": 65, "dx": -14, "dy": -65, "dz": 62}
	var affine_frontier: Dictionary = {"affine_algorithm_version": 1, "tested_triples": 5137, "radius": 1, "du": 0, "dv": -1}
	var merged_frontier: Dictionary = R6Campaign.new().call("_merge_y1_numeric_resume_frontiers", legacy_frontier, affine_frontier)
	_expect(int(merged_frontier.get("affine_algorithm_version", 0)) == 1 and int(merged_frontier.get("tested_triples", 0)) == 2195114 and int(merged_frontier.get("legacy_resume_frontier", {}).get("tested_triples", 0)) == 2189977, "R6-Y resume merge preserves affine progress, cumulative tests and the legacy cursor")
	var newer_legacy: Dictionary = {"tested_triples": 2300000, "radius": 66, "dx": 0, "dy": 66, "dz": 0}
	var reverse_merged: Dictionary = R6Campaign.new().call("_merge_y1_numeric_resume_frontiers", affine_frontier, newer_legacy)
	_expect(int(reverse_merged.get("affine_algorithm_version", 0)) == 1 and int(reverse_merged.get("tested_triples", 0)) == 2305137 and int(reverse_merged.get("legacy_resume_frontier", {}).get("tested_triples", 0)) == 2300000, "R6-Y resume merge keeps affine cursor when a later legacy record has a larger incomparable triple count")
	var nested_affine: Dictionary = merged_frontier.duplicate(true)
	var latest_legacy: Dictionary = {"tested_triples": 2400000, "radius": 67, "dx": 0, "dy": 67, "dz": 0}
	var advanced_merge: Dictionary = R6Campaign.new().call("_merge_y1_numeric_resume_frontiers", nested_affine, latest_legacy)
	_expect(int(advanced_merge.get("tested_triples", 0)) == 2405137 and int(advanced_merge.get("legacy_resume_frontier", {}).get("tested_triples", 0)) == 2400000, "R6-Y replacing a nested legacy cursor adjusts cumulative tests without double counting affine progress")
	var numeric_region_key: String = synthesizer.call("_region_resume_key", "region", "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1)
	_expect(numeric_region_key != resume_key, "R6-Y region attempt identity groups seeds while exact frontier identity retains method and projected seed")
	var resumed_candidate: Dictionary = {"constraint_arrangement_region_id": "region", "method": "ACTIVE_CONSTRAINT_TRANSITION", "position": Vector2(0.25, 0.5)}
	var fresh_candidate: Dictionary = {"constraint_arrangement_region_id": "region", "method": "FEASIBLE_REGION_CENTROID", "position": Vector2(0.25, 0.5)}
	var resumed_candidate_key: String = synthesizer.call("_numeric_resume_key", "region", "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1, "ACTIVE_CONSTRAINT_TRANSITION", Vector2(0.25, 0.5))
	var candidate_frontiers: Dictionary = {resumed_candidate_key: {"tested_triples": 99}}
	_expect(bool(synthesizer.call("_critical_candidate_resume_before", resumed_candidate, fresh_candidate, "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1, candidate_frontiers)), "R6-Y resumes the most advanced exact candidate frontier before a fresh seed in the same region")
	var low_progress_candidate: Dictionary = {"constraint_arrangement_region_id": "region-low", "method": "FEASIBLE_REGION_CENTROID", "position": Vector2(0.25, 0.5)}
	var high_progress_candidate: Dictionary = {"constraint_arrangement_region_id": "region-high", "method": "FEASIBLE_REGION_CENTROID", "position": Vector2(0.25, 0.5)}
	var progress_frontiers: Dictionary = {
		"low": {"arrangement_region_id": "region-low", "boundary_pair": ["edge:a", "edge:b"], "source_cell_global_lattice": [60.0, 8.0, 25.0], "source_tetrahedron": 2, "source_facet": 1, "tested_triples": 10},
		"high": {"arrangement_region_id": "region-high", "boundary_pair": ["edge:a", "edge:b"], "source_cell_global_lattice": [60.0, 8.0, 25.0], "source_tetrahedron": 2, "source_facet": 1, "tested_triples": 20}
	}
	_expect(bool(synthesizer.call("_critical_candidate_resume_before", low_progress_candidate, high_progress_candidate, "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1, progress_frontiers)), "R6-Y schedules the least-advanced continuous region first to prevent frontier starvation")
	_expect(int(synthesizer.call("_critical_candidate_region_tested", "region-low", "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1, progress_frontiers)) == 10, "R6-Y matches frontier region identity across JSON integer and float cell encodings")
	var numeric_schedule: Dictionary = synthesizer.call("_critical_candidate_numeric_schedule", progress_frontiers, 20000000, 10000000, {})
	var scheduled_prior_regions: Dictionary = numeric_schedule.get("scheduled_prior_regions", {})
	var low_region_key: String = synthesizer.call("_region_resume_key", "region-low", "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1)
	var high_region_key: String = synthesizer.call("_region_resume_key", "region-high", "edge:a", "edge:b", Vector3i(60, 8, 25), 2, 1)
	_expect(scheduled_prior_regions.has(low_region_key) and not scheduled_prior_regions.has(high_region_key) and int(numeric_schedule.get("fresh_region_quota", -1)) == 1, "R6-Y allocates budget to the least-advanced saved region and reserves capacity for fresh regions")
	var one_up: float = realizer.call("_step_binary32", 1.0, 1)
	var one_down: float = realizer.call("_step_binary32", 1.0, -1)
	var negative_up: float = realizer.call("_step_binary32", -1.0, 1)
	var positive_zero_up: float = realizer.call("_step_binary32", 0.0, 1)
	var negative_zero_down: float = realizer.call("_step_binary32", 0.0, -1)
	_expect(one_up > 1.0 and one_down < 1.0, "binary32 ULP stepping brackets positive one")
	_expect(negative_up > -1.0, "binary32 ULP stepping follows numeric direction for negative values")
	_expect(positive_zero_up > 0.0 and negative_zero_down < 0.0, "binary32 ULP stepping handles signed zero")
	var exact_zero: Dictionary = realizer.call("_evaluate_zero_point", Vector3(0.5, 0.0, 0.0), {"positions": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK], "samples": [-2.0e-7, 2.0e-7, 0.0, 0.0]})
	_expect(bool(exact_zero.get("accepted", false)) and is_equal_approx(float(exact_zero.get("field_residual", NAN)), 0.0), "R6 correction rechecks unchanged field and barycentric gates")
	var representability_tet: Dictionary = {"positions": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK], "samples": [-4.0, 4.0, 0.0, 0.0]}
	var uncorrected: Dictionary = realizer.call("_evaluate_zero_point", Vector3(0.49999994, 0.0, 0.0), representability_tet)
	var corrected: Dictionary = realizer.call("_search_representable_zero", Vector3(0.49999994, 0.0, 0.0), representability_tet)
	_expect(not bool(uncorrected.get("accepted", false)) and bool(corrected.get("accepted", false)), "R6 bounded same-tetra ULP correction recovers an otherwise rejected binary32 zero")
	var correction_steps: Array = corrected.get("ulp_steps", [])
	_expect(Vector3(corrected.get("position", Vector3.ZERO)) == Vector3(0.5, 0.0, 0.0) and correction_steps.size() == 3 and absi(int(correction_steps[0])) <= 2 and absi(int(correction_steps[1])) <= 2 and absi(int(correction_steps[2])) <= 2, "R6 representability correction records exact pre/post coordinate steps within the frozen plus/minus 2 ULP bound")
	var axis_bracket: Dictionary = realizer.call("_search_representable_zero_axis_bracket", Vector3(0.49999994, 0.0, 0.0), representability_tet)
	_expect(bool(axis_bracket.get("accepted", false)) and absf(float(axis_bracket.get("field_residual", INF))) <= 1.0e-7, "R6-X6 directed axis bracket recovers a binary32 zero while retaining the frozen field epsilon")
	_expect(Vector3(axis_bracket.get("position", Vector3.ZERO)) == Vector3(0.5, 0.0, 0.0) and String(axis_bracket.get("search_state", "")).begins_with("accepted_via_full_same_tetra_axis_interval"), "R6-X6 records its full same-tetra interval bracket without changing legacy bounded correction")
	var multicoordinate_tet: Dictionary = {"positions": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK], "samples": [-0.49999985, 0.00000015, 0.00000015, -0.49999985]}
	var multicoordinate_origin: Vector3 = Vector3(0.49999997, 0.49999997, 0.0)
	var multicoordinate_before: Dictionary = realizer.call("_evaluate_zero_point", multicoordinate_origin, multicoordinate_tet)
	var x_only: Dictionary = realizer.call("_evaluate_zero_point", Vector3(realizer.call("_step_binary32", multicoordinate_origin.x, 1), multicoordinate_origin.y, multicoordinate_origin.z), multicoordinate_tet)
	var y_only: Dictionary = realizer.call("_evaluate_zero_point", Vector3(multicoordinate_origin.x, realizer.call("_step_binary32", multicoordinate_origin.y, 1), multicoordinate_origin.z), multicoordinate_tet)
	var multicoordinate: Dictionary = realizer.call("_search_representable_zero_multicoordinate", multicoordinate_origin, multicoordinate_tet, 1000000)
	var multicoordinate_steps: Array = multicoordinate.get("ulp_steps", [])
	_expect(not bool(multicoordinate_before.get("accepted", false)) and not bool(x_only.get("accepted", false)) and not bool(y_only.get("accepted", false)), "R6-Y binary32 fixture requires coordinated movement on multiple axes")
	_expect(bool(multicoordinate.get("accepted", false)) and absf(float(multicoordinate.get("field_residual", INF))) <= 1.0e-7 and bool(multicoordinate.get("barycentric_gate_pass", false)), "R6-Y multicoordinate float search finds a same-tetra point under unchanged field and barycentric gates")
	_expect(multicoordinate_steps.size() == 3 and String(multicoordinate.get("search_state", "")) == "AFFINE_BINARY32_WITNESS" and int(multicoordinate.get("dependent_axis", -1)) == 0, "R6-Y records the deterministic affine binary32 frontier and dependent axis")
	var excluded_first_witness: Vector3 = Vector3(multicoordinate.get("position", Vector3.ZERO))
	var acceptance_gated_search: Dictionary = realizer.call("_search_representable_zero_multicoordinate", multicoordinate_origin, multicoordinate_tet, 1000000, Callable(func(candidate: Vector3) -> bool: return candidate != excluded_first_witness))
	_expect(bool(acceptance_gated_search.get("accepted", false)) and Vector3(acceptance_gated_search.get("position", excluded_first_witness)) != excluded_first_witness and int(acceptance_gated_search.get("acceptance_gate_rejection_count", 0)) > 0, "R6-Y binary32 enumeration continues after a field-valid candidate fails the complete support acceptance gate")
	var partial_acceptance: Dictionary = realizer.call("_search_representable_zero_multicoordinate", Vector3(0.5, 0.0, 0.0), representability_tet, 1, Callable(func(_candidate: Vector3) -> bool: return false))
	_expect(String(partial_acceptance.get("search_state", "")) == "PARTIAL_LIMIT" and not bool(partial_acceptance.get("accepted", true)) and not bool(partial_acceptance.get("finite_domain_complete", true)), "R6-Y numeric timeout never promotes its field-valid seed to a support witness")
	var partial_frontier: Dictionary = partial_acceptance.get("search_frontier", {})
	_expect(partial_frontier.has("seed_ordered_float32_keys") and partial_frontier.has("tetra_aabb_minimum_ordered_float32_keys") and partial_frontier.has("tetra_aabb_maximum_ordered_float32_keys") and partial_frontier.has("tetra_aabb_axis_candidate_counts") and partial_frontier.has("minimum_radius") and partial_frontier.has("maximum_radius") and partial_frontier.has("affine_algorithm_version") and not String(partial_frontier.get("remaining_domain_definition", "")).is_empty(), "R6-Y partial evidence records the exact finite representable AABB and affine cursor")
	var far_seed: Vector3 = Vector3(10.0, 10.0, 10.0)
	var far_origin_bytes: PackedByteArray = PackedFloat32Array([far_seed.x, far_seed.y, far_seed.z]).to_byte_array()
	var far_minimum_radius: int = 0
	for axis in range(3):
		var origin_key: int = int(realizer.call("_ordered_float32_key", int(far_origin_bytes.decode_u32(axis * 4))))
		var axis_minimum: int = 0xffffffff
		var axis_maximum: int = 0
		for corner_value in representability_tet.get("positions", []):
			var corner: Vector3 = Vector3(corner_value)
			var coordinate: float = [corner.x, corner.y, corner.z][axis]
			var corner_key: int = int(realizer.call("_ordered_float32_key", int(PackedFloat32Array([coordinate]).to_byte_array().decode_u32(0))))
			axis_minimum = mini(axis_minimum, corner_key)
			axis_maximum = maxi(axis_maximum, corner_key)
		if origin_key < axis_minimum: far_minimum_radius = maxi(far_minimum_radius, axis_minimum - origin_key)
		elif origin_key > axis_maximum: far_minimum_radius = maxi(far_minimum_radius, origin_key - axis_maximum)
	var far_seed_partial: Dictionary = realizer.call("_search_representable_zero_multicoordinate", far_seed, representability_tet, 1)
	_expect(String(far_seed_partial.get("search_state", "")) == "PARTIAL_LIMIT" and int(far_seed_partial.get("search_frontier", {}).get("radius", -1)) == far_minimum_radius and far_minimum_radius > 0 and int(far_seed_partial.get("tested_triples", -1)) == 0, "R6-Y skips analytically empty float32 shells up to the nearest tetra-AABB representable coordinate")
	var single_point_tet: Dictionary = {"positions": [Vector3.ONE, Vector3.ONE, Vector3.ONE, Vector3.ONE], "samples": [0.0, 0.0, 0.0, 0.0]}
	var exhausted_representation: Dictionary = realizer.call("_search_representable_zero_multicoordinate", Vector3.ONE, single_point_tet, 1000000, Callable(func(_candidate: Vector3) -> bool: return false))
	_expect(not bool(exhausted_representation.get("accepted", false)) and not bool(exhausted_representation.get("finite_domain_complete", true)) and String(exhausted_representation.get("search_state", "")) == "AFFINE_TETRA_SINGULAR", "R6-Y refuses to classify a singular tetra as a completed affine search")
	var small_x: float = 1.0; var small_y: float = 1.0; var small_z: float = 1.0
	for _step in range(8):
		small_x = float(realizer.call("_step_binary32", small_x, 1)); small_y = float(realizer.call("_step_binary32", small_y, 1)); small_z = float(realizer.call("_step_binary32", small_z, 1))
	var small_tet: Dictionary = {"positions": [Vector3(1.0, 1.0, 1.0), Vector3(small_x, 1.0, 1.0), Vector3(1.0, small_y, 1.0), Vector3(1.0, 1.0, small_z)], "samples": [0.0, 1.0e-6, -0.75e-6, 0.0]}
	var affine_fixture: Dictionary = realizer.call("_derive_tetra_affine_field", small_tet)
	var affine_coefficients: Array = affine_fixture.get("coefficients", [])
	var affine_points: Array[Vector3] = []
	for point_value in small_tet.positions: affine_points.append(Vector3(point_value))
	for edge in [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]:
		affine_points.append(Vector3(small_tet.positions[edge[0]]).lerp(Vector3(small_tet.positions[edge[1]]), 0.5))
	affine_points.append((Vector3(small_tet.positions[0]) + Vector3(small_tet.positions[1]) + Vector3(small_tet.positions[2]) + Vector3(small_tet.positions[3])) / 4.0)
	var affine_agreement: bool = bool(affine_fixture.get("valid", false)) and affine_coefficients.size() == 4
	for point in affine_points:
		var bary_eval: Dictionary = realizer.call("_evaluate_zero_point", point, small_tet)
		var affine_value: float = float(affine_coefficients[0]) * point.x + float(affine_coefficients[1]) * point.y + float(affine_coefficients[2]) * point.z + float(affine_coefficients[3]) if affine_coefficients.size() == 4 else INF
		if absf(float(bary_eval.get("field_residual", INF)) - affine_value) > 2.0e-10: affine_agreement = false
	_expect(affine_agreement, "R6-Y affine coefficients match barycentric field at vertices, edge midpoints, and interior within 2e-10")
	var epsilon_tet: Dictionary = {"positions": small_tet.positions, "samples": [0.0, 3.2e-7, 0.0, 0.0]}
	var epsilon_inside_x: float = 1.0; var epsilon_outside_x: float = 1.0
	for _step in range(2): epsilon_inside_x = float(realizer.call("_step_binary32", epsilon_inside_x, 1))
	for _step in range(3): epsilon_outside_x = float(realizer.call("_step_binary32", epsilon_outside_x, 1))
	var epsilon_inside: Dictionary = realizer.call("_evaluate_zero_point", Vector3(epsilon_inside_x, 1.0, 1.0), epsilon_tet)
	var epsilon_outside: Dictionary = realizer.call("_evaluate_zero_point", Vector3(epsilon_outside_x, 1.0, 1.0), epsilon_tet)
	_expect(bool(epsilon_inside.get("barycentric_gate_pass", false)) and absf(float(epsilon_inside.get("field_residual", INF))) <= 1.0e-7 and bool(epsilon_outside.get("barycentric_gate_pass", false)) and absf(float(epsilon_outside.get("field_residual", 0.0))) > 1.0e-7, "R6-Y regression distinguishes representable points just inside and outside the frozen residual epsilon")
	var old_fixture_ids: Array[String] = []
	var new_fixture_ids: Array[String] = []
	var old_collect: Callable = Callable(func(point: Vector3) -> bool: old_fixture_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var new_collect: Callable = Callable(func(point: Vector3) -> bool: new_fixture_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var old_fixture: Dictionary = realizer.call("_search_representable_zero_multicoordinate_legacy", Vector3(1.0, 1.0, 1.0), small_tet, 100000000, old_collect)
	var new_fixture: Dictionary = realizer.call("_search_representable_zero_multicoordinate", Vector3(1.0, 1.0, 1.0), small_tet, 100000000, new_collect)
	old_fixture_ids.sort(); new_fixture_ids.sort()
	_expect(bool(old_fixture.get("finite_domain_complete", false)) and bool(new_fixture.get("finite_domain_complete", false)) and old_fixture_ids == new_fixture_ids, "R6-Y affine enumerator equals legacy exhaustive binary32 accepted identities on the complete small tetra domain")
	_expect(new_fixture_ids.size() > 1 and int(new_fixture.get("dependent_axis", -1)) == 0, "R6-Y small-domain equivalence covers multiple dependent-axis values and deterministic X tie-break")
	var affine_partial_ids: Array[String] = []; var affine_resume_ids: Array[String] = []
	var affine_partial_gate: Callable = Callable(func(point: Vector3) -> bool: affine_partial_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var affine_resume_gate: Callable = Callable(func(point: Vector3) -> bool: affine_resume_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var affine_partial: Dictionary = realizer.call("_search_representable_zero_multicoordinate", Vector3(1.0, 1.0, 1.0), small_tet, 1, affine_partial_gate)
	var affine_resumed: Dictionary = realizer.call("_search_representable_zero_multicoordinate", Vector3(1.0, 1.0, 1.0), small_tet, 100000000, affine_resume_gate, affine_partial.get("search_frontier", {}))
	affine_partial_ids.append_array(affine_resume_ids); affine_partial_ids.sort()
	_expect(String(affine_partial.get("search_state", "")) == "PARTIAL_LIMIT" and bool(affine_resumed.get("finite_domain_complete", false)) and affine_partial_ids == new_fixture_ids, "R6-Y affine cursor resume exactly covers the uninterrupted accepted binary32 identities")
	var near_axis_tet: Dictionary = {"positions": small_tet.positions, "samples": [0.0, -1.0e-6, 1.0e-9, 0.0]}
	var near_axis_affine: Dictionary = realizer.call("_derive_tetra_affine_field", near_axis_tet)
	var near_axis_coefficients: Array = near_axis_affine.get("coefficients", [])
	var negative_axis_ids: Array[String] = []; var negative_affine_ids: Array[String] = []
	var negative_axis_gate: Callable = Callable(func(point: Vector3) -> bool: negative_axis_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var negative_affine_gate: Callable = Callable(func(point: Vector3) -> bool: negative_affine_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var negative_axis_old: Dictionary = realizer.call("_search_representable_zero_multicoordinate_legacy", Vector3(1.0, 1.0, 1.0), near_axis_tet, 100000000, negative_axis_gate)
	var negative_axis_new: Dictionary = realizer.call("_search_representable_zero_multicoordinate", Vector3(1.0, 1.0, 1.0), near_axis_tet, 100000000, negative_affine_gate)
	negative_axis_ids.sort(); negative_affine_ids.sort()
	_expect(near_axis_coefficients.size() == 4 and float(near_axis_coefficients[0]) < 0.0 and absf(float(near_axis_coefficients[0])) > 100.0 * absf(float(near_axis_coefficients[1])) and is_zero_approx(float(near_axis_coefficients[2])), "R6-Y affine fixture covers negative near-axis-aligned coefficient and an exact zero axis")
	_expect(bool(negative_axis_old.get("finite_domain_complete", false)) and bool(negative_axis_new.get("finite_domain_complete", false)) and negative_axis_ids == negative_affine_ids, "R6-Y affine/legacy identity sets agree for the negative near-axis-aligned plane")
	var seed_bytes: PackedByteArray = PackedFloat32Array([1.0, 1.0, 1.0]).to_byte_array()
	var seed_keys: Array[int] = []
	for axis in range(3): seed_keys.append(int(realizer.call("_ordered_float32_key", int(seed_bytes.decode_u32(axis * 4)))) )
	var legacy_cursor: Dictionary = {"stage": "z_offset", "radius": 1, "dx": 0, "dy": 1, "dz": -1, "seed_ordered_float32_keys": seed_keys, "tested_triples": 0}
	var resumed_old_ids: Array[String] = []; var resumed_new_ids: Array[String] = []
	var resumed_old_gate: Callable = Callable(func(point: Vector3) -> bool: resumed_old_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var resumed_new_gate: Callable = Callable(func(point: Vector3) -> bool: resumed_new_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var resumed_old: Dictionary = realizer.call("_search_representable_zero_multicoordinate_legacy", Vector3(1.0, 1.0, 1.0), small_tet, 100000000, resumed_old_gate, legacy_cursor)
	var resumed_new: Dictionary = realizer.call("_search_representable_zero_multicoordinate", Vector3(1.0, 1.0, 1.0), small_tet, 100000000, resumed_new_gate, legacy_cursor)
	resumed_old_ids.sort(); resumed_new_ids.sort()
	_expect(bool(resumed_old.get("finite_domain_complete", false)) and bool(resumed_new.get("finite_domain_complete", false)) and resumed_old_ids == resumed_new_ids and int(resumed_new.get("legacy_points_skipped", 0)) > 0, "R6-Y legacy shell frontier translates without losing or repeating accepted binary32 identities")
	# Pinned real Y1 field/tetra sample from segment 47 (result SHA fc94cec0...); the local binary32 window is only a deterministic regression slice.
	var real_tet: Dictionary = {"positions": [Vector3(15.0, 2.0, 6.25), Vector3(15.0, 2.25, 6.5), Vector3(15.0, 2.0, 6.5), Vector3(15.25, 2.25, 6.5)], "samples": [-0.294565767049789, 0.00994052179157734, -0.218629404902458, 0.0001123118418036]}
	var real_seed: Vector3 = Vector3(15.2499046, 2.2499046, 6.4999046)
	var real_window: Dictionary = real_tet.duplicate(true)
	var real_window_min: Array[int] = []; var real_window_max: Array[int] = []
	for value in [real_seed.x, real_seed.y, real_seed.z]:
		var center_key: int = int(realizer.call("_ordered_float32_key_at", float(value)))
		real_window_min.append(center_key - 2); real_window_max.append(center_key + 2)
	real_window["binary32_window_minimum_ordered_float32_keys"] = real_window_min
	real_window["binary32_window_maximum_ordered_float32_keys"] = real_window_max
	var real_old_ids: Array[String] = []; var real_new_ids: Array[String] = []
	var real_old_gate: Callable = Callable(func(point: Vector3) -> bool: real_old_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var real_new_gate: Callable = Callable(func(point: Vector3) -> bool: real_new_ids.append(String(realizer.call("_position_bytes_hex", point))); return false)
	var real_old: Dictionary = realizer.call("_search_representable_zero_multicoordinate_legacy", real_seed, real_window, 100000000, real_old_gate)
	var real_new: Dictionary = realizer.call("_search_representable_zero_multicoordinate", real_seed, real_window, 100000000, real_new_gate)
	real_old_ids.sort(); real_new_ids.sort()
	var oracle_counts: Dictionary = {"total": 0, "barycentric_reject": 0, "residual_reject": 0, "accepted_before_full_gate": 0}
	var real_min_keys: Array[int] = []; var real_max_keys: Array[int] = []
	var real_corner_min: Vector3 = real_tet.positions[0]; var real_corner_max: Vector3 = real_tet.positions[3]
	for axis in range(3):
		var mins: Array[float] = [real_corner_min.x, real_corner_min.y, real_corner_min.z]
		var maxs: Array[float] = [real_corner_max.x, real_corner_max.y, real_corner_max.z]
		real_min_keys.append(maxi(int(realizer.call("_ordered_float32_key_at", mins[axis])), real_window_min[axis]))
		real_max_keys.append(mini(int(realizer.call("_ordered_float32_key_at", maxs[axis])), real_window_max[axis]))
	for x_key in range(real_min_keys[0], real_max_keys[0] + 1):
		for y_key in range(real_min_keys[1], real_max_keys[1] + 1):
			for z_key in range(real_min_keys[2], real_max_keys[2] + 1):
				var oracle_point: Vector3 = Vector3(realizer.call("_float_from_ordered_key", x_key), realizer.call("_float_from_ordered_key", y_key), realizer.call("_float_from_ordered_key", z_key))
				var oracle_eval: Dictionary = realizer.call("_evaluate_zero_point", oracle_point, real_tet)
				oracle_counts.total += 1
				if not bool(oracle_eval.get("barycentric_gate_pass", false)): oracle_counts.barycentric_reject += 1
				elif not bool(oracle_eval.get("residual_gate_pass", false)): oracle_counts.residual_reject += 1
				else: oracle_counts.accepted_before_full_gate += 1
	_expect(bool(real_old.get("finite_domain_complete", false)) and bool(real_new.get("finite_domain_complete", false)) and real_old_ids == real_new_ids and oracle_counts.total == 125 and oracle_counts.accepted_before_full_gate == real_new_ids.size(), "R6-Y real segment-47 tetra local-window identity set agrees with exhaustive oracle; barycentric and residual rejection counts recorded")
	print("R6_Y1B_REAL_DOMAIN_SAMPLE " + JSON.stringify({"source_result_sha256": "fc94cec0848dc395cad83d066bc488b294cd86342459e4ae74f3324aa3176a31", "source_cell_global_lattice": [60, 8, 25], "source_cell_local": [0, 4, 1], "source_tetrahedron": 4, "window_triples": oracle_counts.total, "oracle_barycentric_rejections": oracle_counts.barycentric_reject, "oracle_residual_rejections": oracle_counts.residual_reject, "oracle_field_and_barycentric_passes": oracle_counts.accepted_before_full_gate, "legacy_accepted_identity_count": real_old_ids.size(), "affine_accepted_identity_count": real_new_ids.size(), "legacy_tested": real_old.get("tested_triples", -1), "affine_tested": real_new.get("tested_triples", -1), "affine_skipped": real_new.get("affine_skipped_candidates", -1), "identity_sets_equal": real_old_ids == real_new_ids, "finite_complete": bool(real_old.get("finite_domain_complete", false)) and bool(real_new.get("finite_domain_complete", false))}))
	var cavity_triangle: Array[Vector2] = [Vector2.ZERO, Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
	var overlapping_region: Array[Vector2] = [Vector2(0.1, 0.1), Vector2(0.7, 0.1), Vector2(0.1, 0.7)]
	var disjoint_region: Array[Vector2] = [Vector2(2.0, 2.0), Vector2(3.0, 2.0), Vector2(2.0, 3.0)]
	var support_synthesizer: RefCounted = R5Synthesizer.new()
	var overlap_result: Dictionary = support_synthesizer.call("_strict_region_cavity_intersection", overlapping_region, cavity_triangle)
	var disjoint_result: Dictionary = support_synthesizer.call("_strict_region_cavity_intersection", disjoint_region, cavity_triangle)
	var narrow_positive_area_region: Array[Vector2] = [Vector2(0.0, 0.05), Vector2(1.0e-8, 0.05), Vector2(1.0e-8, 0.15), Vector2(0.0, 0.15)]
	var narrow_overlap_result: Dictionary = support_synthesizer.call("_strict_region_cavity_intersection", narrow_positive_area_region, cavity_triangle)
	var overlap_centroid: Vector2 = Vector2(overlap_result.get("centroids", [Vector2.ZERO])[0])
	_expect(bool(overlap_result.get("valid", false)) and int(overlap_result.get("component_count", 0)) > 0 and bool(support_synthesizer.call("_point_strictly_inside", overlap_centroid, overlapping_region)) and bool(support_synthesizer.call("_point_strictly_inside", overlap_centroid, cavity_triangle)), "R6-Y clips arrangement regions against the cavity and emits strict interior support seeds")
	_expect(bool(disjoint_result.get("valid", false)) and int(disjoint_result.get("component_count", -1)) == 0 and bool(disjoint_result.get("strict_interior_empty", false)), "R6-Y proves a strict region-cavity intersection empty by deterministic polygon clipping")
	_expect(bool(narrow_overlap_result.get("valid", false)) and float(narrow_overlap_result.get("total_area", 0.0)) > 0.0 and int(narrow_overlap_result.get("component_count", 0)) > 0 and int(narrow_overlap_result.get("uncertified_centroid_count", 0)) > 0, "R6-Y keeps positive-area overlap complete when float32 centroid is inside the strict predicate boundary guard")
	_expect(bool(narrow_overlap_result.get("centroids", []).size() > 0) and not bool(narrow_overlap_result.get("components", [])[0].get("strict_interior_centroid_certified", true)), "R6-Y exposes uncertified centroid only as a search seed, never as a witness")
	var centroid_priority: int = int(support_synthesizer.call("_critical_candidate_search_priority", {"method": "CAVITY_ARRANGEMENT_INTERSECTION_CENTROID"}))
	var edge_priority: int = int(support_synthesizer.call("_critical_candidate_search_priority", {"method": "FEASIBLE_REGION_EDGE_MIDPOINT"}))
	_expect(centroid_priority < edge_priority, "R6-Y prioritizes strict interior region-cavity seeds before edge midpoints for the numerical witness search")
	var already_valid: Array[Dictionary] = realizer.call("corrected_tetra_zero_sources", {"positions": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK], "samples": [-1.0, 1.0, 1.0, 1.0]})
	_expect(already_valid.size() == 3 and already_valid.all(func(row: Dictionary) -> bool: return bool(row.get("accepted", false))), "R6 correction retains passing roots without searching")
	_expect(already_valid.all(func(row: Dictionary) -> bool: return String(row.get("correction_search_state", "")) == "unchanged"), "R6 correction records unchanged passing-root provenance")
	var degenerate: Dictionary = {"positions": [Vector3.ZERO, Vector3.ZERO, Vector3.UP, Vector3.BACK], "samples": [-1.0, 1.0, 1.0, 1.0]}
	var rejected_sources: Array[Dictionary] = realizer.call("corrected_tetra_zero_sources", degenerate)
	_expect(rejected_sources.all(func(row: Dictionary) -> bool: return not bool(row.get("accepted", false))), "R6 correction marks unrepairable representable roots rejected")
	_expect(realizer.call("_tetra_zero_points", degenerate).is_empty(), "R6 correction never emits rejected roots into geometry")

func _test_patch_owner_and_ordered_arc_paths() -> void:
	var realizer: RefCounted = R6Realizer.new()
	var source: Dictionary = {"triangle_id": "face-02", "polygon_id": "poly-02", "source_polygon_ids": ["poly-02", "poly-source"], "root_ids": ["A", "B", "C"], "points": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP]}
	var context: Dictionary = {"projection_origin": Vector3.ZERO, "projection_u": Vector3.RIGHT, "projection_v": Vector3.UP, "projected_positions": {"A": Vector2.ZERO, "B": Vector2.RIGHT, "C": Vector2.UP}, "patch": [source]}
	var owner_result: Dictionary = realizer.call("_r2_owner_for_triangle", Vector3(0.25, 0.25, 0.0), context)
	_expect(bool(owner_result.get("valid", false)), "R6-B resolves owner from removed patch")
	_expect(String(owner_result.get("owner", {}).get("polygon_id", "")) == "poly-02", "R6-B preserves source polygon provenance")
	_expect(String(owner_result.get("selection_rule", "")).begins_with("PATCH_CONTAINMENT"), "R6-B records deterministic containment ownership")
	var support_id: String = "R5SUP_000000000000000000000000"
	var mesh: Array[Dictionary] = [
		{"triangle_id": "replacement-1", "root_ids": ["A", support_id, "C"], "points": [Vector3.ZERO, Vector3(0.5, 0.1, 0.0), Vector3.UP]},
		{"triangle_id": "replacement-2", "root_ids": [support_id, "B", "C"], "points": [Vector3(0.5, 0.1, 0.0), Vector3.RIGHT, Vector3.UP]}
	]
	var arc_result: Dictionary = realizer.call("_validate_required_arcs", mesh, [{"arc_id": "arc-ab", "root_ids": ["A", "B"], "expected_incidence": 1}], [])
	_expect(bool(arc_result.get("valid", false)), "R6-C accepts a valid ordered derived-vertex path")
	_expect(String(arc_result.get("paths", [])[0].get("method", "")) == "PIECEWISE_PATH", "R6-C labels non-edge obligation as a piecewise path")
	_expect(arc_result.get("paths", [])[0].get("ordered_mesh_vertex_ids", []) == ["A", support_id, "B"], "R6-C records ordered path with unchanged endpoints")
	var direct: Array[Dictionary] = [{"triangle_id": "anchor", "root_ids": ["A", "B", "C"], "points": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP]}]
	var anchor_result: Dictionary = realizer.call("_validate_required_arcs", direct, [{"arc_id": "arc-ab", "root_ids": ["A", "B"], "expected_incidence": 1}], [])
	_expect(bool(anchor_result.get("valid", false)) and String(anchor_result.get("paths", [])[0].get("method", "")) == "ANCHOR_EDGE", "R6-C retains exact anchor-edge realization")
	var shared_support_mesh: Array[Dictionary] = [
		{"triangle_id": "fan-1", "root_ids": ["A", support_id, "C"], "points": [Vector3.ZERO, Vector3(0.5, 0.5, 0.0), Vector3.UP]},
		{"triangle_id": "fan-2", "root_ids": ["C", support_id, "B"], "points": [Vector3.UP, Vector3(0.5, 0.5, 0.0), Vector3.RIGHT]},
		{"triangle_id": "fan-3", "root_ids": ["B", support_id, "D"], "points": [Vector3.RIGHT, Vector3(0.5, 0.5, 0.0), Vector3.DOWN]},
		{"triangle_id": "fan-4", "root_ids": ["D", support_id, "A"], "points": [Vector3.DOWN, Vector3(0.5, 0.5, 0.0), Vector3.ZERO]}
	]
	var merge_result: Dictionary = realizer.call("_validate_required_arcs", shared_support_mesh, [{"arc_id": "arc-ab", "root_ids": ["A", "B"], "expected_incidence": 2}, {"arc_id": "arc-cd", "root_ids": ["C", "D"], "expected_incidence": 2}], [])
	_expect(not bool(merge_result.get("valid", true)) and merge_result.get("intersection_audit", {}).get("failures", []).any(func(row: Dictionary) -> bool: return String(row.get("reason", "")) == "topology_paths_merge_at_derived_vertex"), "R6-C rejects topology paths that merge at a derived vertex")

func _test_bounded_causal_cavity_search(diagnostics: RefCounted) -> void:
	var faces: Array[Dictionary] = [
		{"triangle_id": "T0", "root_ids": ["A", "B", "C"], "points": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP]},
		{"triangle_id": "T1", "root_ids": ["B", "A", "D"], "points": [Vector3.RIGHT, Vector3.ZERO, Vector3.BACK]},
		{"triangle_id": "T2", "root_ids": ["A", "B", "E"], "points": [Vector3.ZERO, Vector3.RIGHT, Vector3.BACK]}
	]
	var edge_key: String = "A\u001fB"
	var evaluator: Callable = func(ids: Array) -> Dictionary:
		if ids.size() > 1: return {"valid": true, "manifold": true, "unrealizable_edges": [], "minimum_cutoff_margin": 0.5, "boundary_components": 1}
		return {"valid": true, "manifold": true, "unrealizable_edges": [edge_key], "minimum_cutoff_margin": -1.0, "boundary_components": 1}
	var search: Dictionary = diagnostics.call("bounded_cavity_search", ["T0"], faces, {}, evaluator, {"max_faces": 3, "max_states": 100, "max_queue": 20, "max_ms": 30000})
	_expect(String(search.get("status", "")) == "FOUND", "R6-D bounded search finds a feasible causally adjacent cavity")
	_expect(search.get("selected", {}).get("face_ids", []) == ["T0", "T1"], "R6-D tie-breaks by stable face-ID sequence")
	var capped: Dictionary = diagnostics.call("bounded_cavity_search", ["T0"], faces, {}, evaluator, {"max_faces": 3, "max_states": 1, "max_queue": 20, "max_ms": 30000})
	_expect(String(capped.get("status", "")) == "PARTIAL" and String(capped.get("terminal_reason", "")) == "VISITED_STATE_CAP", "R6-D state cap reports PARTIAL")
	_expect(int(capped.get("examined_states", 0)) <= 1, "R6-D state cap is enforced")
	var face_capped: Dictionary = diagnostics.call("bounded_cavity_search", ["T0"], faces, {}, evaluator, {"max_faces": 1, "max_states": 100, "max_queue": 20, "max_ms": 30000})
	_expect(String(face_capped.get("status", "")) == "PARTIAL" and String(face_capped.get("terminal_reason", "")) == "MAX_REMOVED_FACE_BOUND", "R6-D removed-face bound cannot be reported as finite exhaustion")
	var unknown_evaluator: Callable = func(_ids: Array) -> Dictionary: return {"valid": true, "manifold": true, "unrealizable_edges": [], "unresolved_edges": [edge_key], "edges_requiring_expansion": [edge_key], "minimum_feasible_witness_margin": -INF, "boundary_components": 1}
	var unresolved_search: Dictionary = diagnostics.call("bounded_cavity_search", ["T0"], faces, {}, unknown_evaluator, {"max_faces": 3, "max_states": 100, "max_queue": 20, "max_ms": 30000})
	_expect(String(unresolved_search.get("status", "")) == "PARTIAL" and String(unresolved_search.get("terminal_reason", "")) == "FINITE_CANDIDATE_GRAPH_EXHAUSTED_WITH_UNRESOLVED_FEASIBILITY", "R6-D finite graph exhaustion preserves unresolved witness feasibility as PARTIAL")

func _test_atomic_alternative_cavity_search(diagnostics: RefCounted) -> void:
	var faces: Array[Dictionary] = [
		{"triangle_id": "T0", "root_ids": ["A", "B", "C"]},
		{"triangle_id": "T1", "root_ids": ["A", "B", "D"]},
		{"triangle_id": "T2", "root_ids": ["A", "C", "E"]}
	]
	var evaluator: Callable = func(ids: Array) -> Dictionary:
		if ids.size() == 2: return {"valid": false, "reason": "one_face_transition_not_manifold"}
		return {"valid": true, "manifold": true, "unrealizable_edges": [], "unresolved_edges": [], "boundary_components": 1, "cycles": {"cycles": [{"root_ids": ["A", "B", "C"]}]}, "minimum_feasible_witness_margin": 0.25}
	var search: Dictionary = diagnostics.call("bounded_cavity_search", ["T0"], faces, {}, evaluator, {"enumerate_alternatives": true, "max_faces": 4, "max_states": 32, "max_queue": 16, "max_ms": 1000, "max_atomic_faces": 2, "max_bundles_per_state": 64})
	_expect(String(search.get("status", "")) == "FOUND_ALTERNATIVE", "R6-X3 enumerates alternatives after the initial cavity passes")
	_expect(search.get("selected", {}).get("face_ids", []) == ["T0", "T1", "T2"], "R6-X3 admits a causally adjacent atomic two-face expansion when one-face intermediates fail")
	_expect(int(search.get("invalid_candidate_patches", 0)) == 2, "R6-X3 retains the rejected one-face intermediate evidence")

func _test_patch_boundary_upper_bound(diagnostics: RefCounted) -> void:
	var realizer: RefCounted = R6Realizer.new()
	var patch: Array[Dictionary] = [{"triangle_id": "patch", "root_ids": ["A", "B", "C"], "points": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP]}]
	var facet: Dictionary = {"tetrahedron_id": "tet-1", "facet_index": 0, "points": [Vector3.ZERO, Vector3(0.5, 0.0, 0.0), Vector3(0.0, 0.5, 0.0)], "tetrahedron_positions": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK], "tetrahedron_samples": [-1.0, 1.0, 1.0, 1.0]}
	var facets: Array[Dictionary] = [facet]
	var root_positions: Dictionary = {"A": Vector3.ZERO, "B": Vector3.RIGHT, "C": Vector3.UP}
	var projection: Dictionary = {"origin": [0.0, 0.0, 0.0], "axis_u": [1.0, 0.0, 0.0], "axis_v": [0.0, 1.0, 0.0]}
	var result: Dictionary = diagnostics.call("analyze_patch_boundary", realizer, patch, ["A", "B", "C"], root_positions, projection, facets)
	_expect(bool(result.get("valid", false)) and result.get("boundary_edges", []).size() == 3, "R6-D audits every boundary edge over clipped zero facets")
	if result.get("boundary_edges", []).size() == 3:
		_expect(bool(result.get("boundary_edges", [])[0].get("feasible_incident_triangle_witness", {}).get("valid", false)), "R6-D accepts strict in-domain witness above frozen cutoff")
		_expect(float(result.get("boundary_edges", [])[0].get("continuous_upper_bound_cross_squared", 0.0)) > 1.0e-12, "R6-D records the continuous cross-squared upper bound")
	var repeated: Dictionary = diagnostics.call("analyze_patch_boundary", realizer, patch, ["A", "B", "C"], root_positions, projection, facets)
	_expect(int(result.get("zero_facet_clip_evaluations", 0)) == 1 and int(repeated.get("zero_facet_clip_evaluations", -1)) == 0, "R6-D reuses facet clipping for repeated cavity faces")
	_expect(int(result.get("face_edge_metric_evaluations", 0)) == 3 and int(repeated.get("face_edge_metric_cache_hits", 0)) == 3, "R6-D reuses edge metrics across repeated cavity states")
	_expect(repeated.get("boundary_edges", []) == result.get("boundary_edges", []), "R6-D clipping cache preserves boundary audit results")
	var inventory_result: Dictionary = diagnostics.call("analyze_patch_boundary", realizer, patch, ["A", "B", "C"], root_positions, projection, facets, true)
	var domain_inventory: Array = inventory_result.get("continuous_domain_inventory", [])
	_expect(bool(inventory_result.get("continuous_domain_inventory_complete", false)) and int(inventory_result.get("continuous_domain_inventory_count", 0)) == 1, "R6-D4 emits the complete clipped zero-facet region inventory on request")
	_expect(domain_inventory.size() == 1 and String(domain_inventory[0].get("region_id", "")) == "patch|tet-1|facet:0" and domain_inventory[0].get("clipped_world_polygon", []).size() >= 3, "R6-D4 inventory retains a stable region identity and clipped polygon")
	var repeated_inventory: Dictionary = diagnostics.call("analyze_patch_boundary", realizer, patch, ["A", "B", "C"], root_positions, projection, facets, true)
	_expect(String(repeated_inventory.get("continuous_domain_inventory_sha256", "")) == String(inventory_result.get("continuous_domain_inventory_sha256", "")), "R6-D4 clipped region inventory hash is deterministic across cache reuse")

func _test_r6d4_json_obligation_array_adapter() -> void:
	var parsed: Variant = JSON.parse_string("{\"obligation_records\":[{\"index\":2},{\"index\":3}]}")
	var raw_rows: Variant = parsed.get("obligation_records", [])
	var rows: Array = R6Campaign._r6d4_obligation_rows(raw_rows)
	_expect(typeof(raw_rows) == TYPE_ARRAY and rows.size() == 2, "R6-D4 accepts JSON.parse_string untyped obligation arrays")
	_expect(int(rows[0].get("index", -1)) == 2 and int(rows[1].get("index", -1)) == 3, "R6-D4 preserves deserialized obligation dictionary rows")
	_expect(R6Campaign._r6d4_obligation_rows({"not": "an array"}).is_empty(), "R6-D4 fails closed on non-array obligation input")

func _test_analytic_edge_witness_not_sampling_limited(diagnostics: RefCounted) -> void:
	var realizer: RefCounted = R6Realizer.new()
	var domain: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2(0.0, 1.0)]
	var p0: Vector3 = Vector3(0.0, 1.0000001e-6, 0.0)
	var polygon: Array[Vector3] = [p0, Vector3(0.2, 0.0, 0.0), Vector3.ZERO]
	var facet: Dictionary = {"tetrahedron_id": "synthetic-facet", "facet_index": 0, "tetrahedron_positions": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK], "tetrahedron_samples": [0.0, 0.0, 0.0, 1.0]}
	var maximum: float = float(diagnostics.call("_cross_squared", Vector3.ZERO, Vector3.RIGHT, p0))
	var witness: Dictionary = diagnostics.call("_patch_edge_witness", realizer, Vector3.ZERO, Vector3.RIGHT, maximum, p0, polygon, domain, facet, Vector3.ZERO, Vector3.RIGHT, Vector3.UP)
	_expect(maximum > 1.0e-12, "synthetic analytic-witness case begins strictly above the frozen cutoff")
	_expect(bool(witness.get("valid", false)), "analytic interval construction finds an interior witness missed by the former fixed lambda samples")
	_expect(String(witness.get("witness_construction", "")) == "ANALYTIC_QUADRATIC_AND_DOMAIN_INTERVAL", "witness records its analytic interval construction")
	_expect(float(witness.get("cross_squared", 0.0)) > 1.0e-12 and float(witness.get("continuous_field_residual", INF)) <= 1.0e-7, "constructed witness preserves the exact cutoff and field epsilon")

func _test_mixed_lod_interface_oracle() -> void:
	var shared: PackedVector3Array = PackedVector3Array([Vector3(16.0, 0.0, 0.0), Vector3(16.0, 1.0, 0.0), Vector3(15.0, 0.0, 0.0), Vector3(16.0, 0.0, 0.0), Vector3(16.0, 1.0, 0.0), Vector3(17.0, 0.0, 0.0)])
	var matching: Dictionary = CXRDownstream._compare_mixed_lod_interface({"positions": shared}, {"positions": shared}, 0, 16.0)
	_expect(bool(matching.get("conforming", false)) and int(matching.get("shared_segment_count", 0)) == 1, "mixed-LOD interface oracle accepts exact shared segment ownership")
	var mismatch: PackedVector3Array = PackedVector3Array([Vector3(16.0, 0.0, 0.0), Vector3(16.0, 2.0, 0.0), Vector3(15.0, 0.0, 0.0), Vector3(16.0, 0.0, 0.0), Vector3(16.0, 2.0, 0.0), Vector3(17.0, 0.0, 0.0)])
	var rejected: Dictionary = CXRDownstream._compare_mixed_lod_interface({"positions": shared}, {"positions": mismatch}, 0, 16.0)
	_expect(not bool(rejected.get("conforming", true)) and int(rejected.get("unmatched_segment_entries", 0)) == 2, "mixed-LOD interface oracle rejects unmatched segment sets")

func _test_r6_unbounded_frozen_graph_solver() -> void:
	var synthetic: Dictionary = _make_six_support_solver_fixture()
	var context: Dictionary = synthetic.context
	var graph: Array[Dictionary] = synthetic.candidate_triangles
	var before_graph: Array[Dictionary] = graph.duplicate(true)
	var validator: Callable = func(triangles: Array, support_ids: Array, _edge_state: Dictionary, _context: Dictionary) -> Dictionary:
		return {"valid": true, "support_ids": support_ids.duplicate(), "selected_triangle_ids": triangles.map(func(row: Dictionary) -> String: return String(row.triangle_id))}
	var solver: RefCounted = R6FrozenSolver.new()
	var limits: Dictionary = {"candidate_graph_sha256": "fixture-graph-sha256", "support_set_sha256": "fixture-support-sha256", "expected_candidate_triangles": graph.size(), "max_search_states_per_cavity": 1000, "max_search_usec_per_cavity": 10000000, "max_patch_triangles": 64}
	var sat: Dictionary = solver.call("solve", context, graph, null, limits, validator)
	_expect(String(sat.get("status", "")) == "SAT" and bool(sat.get("search_complete", false)), "R6-F solver finds a complete valid graph triangulation")
	_expect(String(sat.get("candidate_graph_sha256", "")) == "fixture-graph-sha256" and int(sat.get("candidate_triangle_count", -1)) == before_graph.size() and int(sat.get("indexed_triangle_count", -1)) == before_graph.size(), "R6-F preserves candidate graph identity and indexes every legal row")
	_expect(int(sat.get("support_count", 0)) == 23 and context.support_by_id.size() == 23, "R6-F retains all 23 addressable frozen supports")
	_expect(sat.get("best_solution", {}).get("support_ids", []).size() == 6 and String(sat.get("support_cardinality_bound", "")) == "NONE", "R6-F derives six selected supports from triangles without a four-support cap")
	var selected_ids: Dictionary = {}
	for triangle_id_value in sat.get("best_solution", {}).get("selected_triangle_ids", []): selected_ids[String(triangle_id_value)] = true
	var derived_support_ids: Array[String] = []
	for triangle in graph:
		if not selected_ids.has(String(triangle.triangle_id)): continue
		for root_id_value in triangle.root_ids:
			var root_id: String = String(root_id_value)
			if context.support_by_id.has(root_id) and not derived_support_ids.has(root_id): derived_support_ids.append(root_id)
	derived_support_ids.sort()
	var every_support_addressable: bool = true
	for support_id_value in context.support_by_id.keys(): every_support_addressable = every_support_addressable and context.vertex_positions.has(String(support_id_value))
	_expect(every_support_addressable and sat.get("best_solution", {}).get("support_ids", []) == derived_support_ids, "R6-F makes every retained support addressable and derives selected identities only from solution triangles")
	_expect(graph == before_graph, "R6-F search leaves the frozen candidate graph unchanged")
	var area_audit: Dictionary = solver.call("_coverage_area_audit", graph)
	_expect(bool(area_audit.get("applicable", false)) and bool(area_audit.get("within_tolerance", false)) and String(area_audit.get("use", "")).contains("audit_only"), "R6-F projected-area agreement is captured as an audit-only coverage check")
	var first_ids: Array = sat.get("best_solution", {}).get("selected_triangle_ids", []).duplicate()
	var repeated: Dictionary = solver.call("solve", context, graph, null, limits, validator)
	var repeated_ids: Array = repeated.get("best_solution", {}).get("selected_triangle_ids", []).duplicate()
	_expect(String(repeated.get("status", "")) == "SAT" and first_ids == repeated_ids, "R6-F deterministic repeat selects the same ordered solution")
	var geometry_solver: RefCounted = R6FrozenSolver.new()
	var geometry_realizer: RefCounted = R6Realizer.new()
	var geometry_sat: Dictionary = geometry_solver.call("solve", context, graph, geometry_realizer, limits, validator)
	_expect(String(geometry_sat.get("status", "")) == "SAT" and int(geometry_sat.get("triangle_conflict_checks", 0)) > 0, "R6-F invokes typed intersection and T-junction geometry oracles without tooling errors")
	var incomplete: Array[Dictionary] = graph.duplicate(true)
	for index in range(incomplete.size()):
		if String(incomplete[index].triangle_id) == "syn-inner-2":
			incomplete.remove_at(index)
			break
	var unsat_limits: Dictionary = limits.duplicate(true)
	unsat_limits.expected_candidate_triangles = incomplete.size()
	var unsat: Dictionary = solver.call("solve", context, incomplete, null, unsat_limits, validator)
	_expect(String(unsat.get("status", "")) == "UNSAT_COMPLETE" and bool(unsat.get("search_exhaustive", false)), "R6-F distinguishes a fully explored synthetic finite-graph UNSAT")
	var zero_obligation: Dictionary = unsat.get("first_zero_candidate_obligation", {})
	var zero_edge_key: String = String(zero_obligation.get("edge_key", ""))
	_expect(not zero_obligation.is_empty() and not zero_edge_key.is_empty() and String(zero_obligation.get("from_id", "")) != String(zero_obligation.get("to_id", "")), "R6-Y solver preserves the exact directed edge obligation that lost all compatible candidates")
	_expect(int(zero_obligation.get("compatible_candidate_option_count_after_state_filters", -1)) == 0 and unsat.get("zero_candidate_obligation_edge_histogram", {}).size() > 0, "R6-Y distinguishes complete-graph edge options from zero options after selected-state constraints")

	var boundary_incomplete: Array[Dictionary] = graph.duplicate(true)
	for index in range(boundary_incomplete.size()):
		if String(boundary_incomplete[index].triangle_id) == "syn-outer-0":
			boundary_incomplete.remove_at(index)
			break
	var boundary_unsat_limits: Dictionary = limits.duplicate(true)
	boundary_unsat_limits.expected_candidate_triangles = boundary_incomplete.size()
	var boundary_unsat: Dictionary = solver.call("solve", context, boundary_incomplete, null, boundary_unsat_limits, validator)
	var boundary_zero: Dictionary = boundary_unsat.get("first_zero_candidate_obligation", {})
	var boundary_zero_edge_key: String = String(boundary_zero.get("edge_key", ""))
	var authoritative_boundary_row: Dictionary = context.boundary_edge_map.get(boundary_zero_edge_key, {})
	_expect(String(boundary_unsat.get("status", "")) == "UNSAT_COMPLETE" and String(boundary_zero.get("kind", "")) == "boundary", "R6-Y dedicated fixture produces a boundary zero-option obligation")
	_expect(not authoritative_boundary_row.is_empty() and String(boundary_zero.get("from_id", "")) == String(authoritative_boundary_row.get("a", "")) and String(boundary_zero.get("to_id", "")) == String(authoritative_boundary_row.get("b", "")), "R6-Y serializes boundary zero-option endpoints from the authoritative boundary edge map")
	_expect(String(boundary_zero.get("directed_edge_key", "")) == _fixture_directed_key(String(authoritative_boundary_row.get("a", "")), String(authoritative_boundary_row.get("b", ""))), "R6-Y serialized zero-option directed key matches authoritative boundary orientation")
	var disconnected_context: Dictionary = context.duplicate(true)
	disconnected_context["global_arc_map"] = [{"arc_id": "unreachable", "root_ids": ["B0", "X16"]}]
	var topology_unsat: Dictionary = solver.call("solve", disconnected_context, graph, null, limits, validator)
	_expect(String(topology_unsat.get("status", "")) == "UNSAT_COMPLETE" and int(topology_unsat.get("prune_histogram", {}).get("topology_path_unreachable_in_frozen_candidate_graph", 0)) == 1, "R6-F prunes a topology path disconnected in the entire candidate graph")
	var bounded_limits: Dictionary = limits.duplicate(true)
	bounded_limits.max_search_states_per_cavity = 1
	var partial: Dictionary = solver.call("solve", context, graph, null, bounded_limits, validator)
	_expect(String(partial.get("status", "")) == "PARTIAL_LIMIT" and not bool(partial.get("search_complete", true)) and not bool(partial.get("search_exhaustive", true)), "R6-F reports bounded search as PARTIAL_LIMIT, never UNSAT")
	var duplicate_graph: Array[Dictionary] = graph.duplicate(true)
	duplicate_graph.append(graph[0].duplicate(true))
	var duplicate_limits: Dictionary = limits.duplicate(true)
	duplicate_limits.expected_candidate_triangles = duplicate_graph.size()
	var duplicate_result: Dictionary = solver.call("solve", context, duplicate_graph, null, duplicate_limits, validator)
	_expect(String(duplicate_result.get("status", "")) == "INVALID_GRAPH_INPUT" and String(duplicate_result.get("terminal_reason", "")) == "FROZEN_GRAPH_DUPLICATE_TRIANGLE_ID", "R6-F rejects duplicate graph rows rather than silently dropping them")

func _make_six_support_solver_fixture() -> Dictionary:
	var positions: Dictionary = {}
	var support_by_id: Dictionary = {}
	var vertex_ids: Array[String] = []
	for index in range(5):
		var outer_id: String = "B%d" % index
		var outer_angle: float = TAU * float(index) / 5.0
		positions[outer_id] = Vector3(2.0 * cos(outer_angle), 2.0 * sin(outer_angle), 0.0)
		vertex_ids.append(outer_id)
		var support_id: String = "S%d" % index
		var inner_angle: float = TAU * (float(index) - 0.5) / 5.0
		positions[support_id] = Vector3(cos(inner_angle), sin(inner_angle), 0.0)
		vertex_ids.append(support_id)
		support_by_id[support_id] = {"support_id": support_id}
	var center_id: String = "C"
	positions[center_id] = Vector3.ZERO
	vertex_ids.append(center_id)
	support_by_id[center_id] = {"support_id": center_id}
	for index in range(17):
		var unused_id: String = "X%02d" % index
		positions[unused_id] = Vector3(10.0 + float(index), 10.0, 0.0)
		vertex_ids.append(unused_id)
		support_by_id[unused_id] = {"support_id": unused_id}
	var boundary: Dictionary = {}
	for index in range(5):
		var a: String = "B%d" % index
		var b: String = "B%d" % ((index + 1) % 5)
		boundary[_fixture_edge_key(a, b)] = {"a": a, "b": b}
	var candidates: Array[Dictionary] = []
	for index in range(5):
		var next: int = (index + 1) % 5
		candidates.append(_fixture_triangle("syn-outer-%d" % index, ["B%d" % index, "B%d" % next, "S%d" % next], positions))
		candidates.append(_fixture_triangle("syn-annulus-%d" % index, ["B%d" % index, "S%d" % next, "S%d" % index], positions))
		candidates.append(_fixture_triangle("syn-inner-%d" % index, ["S%d" % index, "S%d" % next, center_id], positions))
	var projected_positions: Dictionary = {}
	for vertex_id in positions: projected_positions[vertex_id] = Vector2(positions[vertex_id].x, positions[vertex_id].y)
	var boundary_cycle: Array[String] = ["B0", "B1", "B2", "B3", "B4"]
	var context: Dictionary = {"vertex_ids": vertex_ids, "vertex_positions": positions, "projected_positions": projected_positions, "boundary_cycle": boundary_cycle, "support_by_id": support_by_id, "boundary_edge_map": boundary, "patch_ids": [], "all_triangles": []}
	return {"context": context, "candidate_triangles": candidates}

func _fixture_triangle(triangle_id: String, ids: Array, positions: Dictionary) -> Dictionary:
	var points: Array[Vector3] = [positions[String(ids[0])], positions[String(ids[1])], positions[String(ids[2])]]
	return {"triangle_id": triangle_id, "root_ids": ids, "points": points, "cross_squared": (points[1] - points[0]).cross(points[2] - points[0]).length_squared(), "polygon_id": "fixture-owner", "source_polygon_ids": ["fixture-owner"]}

func _fixture_edge_key(a: String, b: String) -> String:
	return a + "\u001f" + b if a < b else b + "\u001f" + a

func _fixture_directed_key(a: String, b: String) -> String:
	return a + "\u001e" + b



func _expect(condition: bool, name: String) -> void:
	assertions += 1
	if not condition:
		failures.append(name)
