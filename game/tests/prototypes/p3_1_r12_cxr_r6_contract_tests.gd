extends SceneTree

const Diagnostics := preload("res://tests/prototypes/p3_1_r12_cxr_r6_diagnostics.gd")
const R6Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_r6_realizer.gd")
const CXRDownstream := preload("res://tests/prototypes/p3_1_r12_cxr_campaign.gd")
const R6Campaign := preload("res://tests/prototypes/p3_1_r12_cxr_r6_campaign.gd")
const R5Synthesizer := preload("res://tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd")
const R6FrozenSolver := preload("res://tests/prototypes/p3_1_r12_cxr_r6_frozen_solver.gd")

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
	_test_analytic_edge_witness_not_sampling_limited(diagnostics)
	_test_mixed_lod_interface_oracle()
	_test_r6_unbounded_frozen_graph_solver()
	_test_x2_all_arrangement_vertices()
	_test_alternative_cavity_boundary_pair_domain()
	_test_x4_zero_boundary_obligations()
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



func _expect(condition: bool, name: String) -> void:
	assertions += 1
	if not condition:
		failures.append(name)
