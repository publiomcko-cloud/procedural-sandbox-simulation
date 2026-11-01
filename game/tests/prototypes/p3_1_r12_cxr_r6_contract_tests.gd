extends SceneTree

const Diagnostics := preload("res://tests/prototypes/p3_1_r12_cxr_r6_diagnostics.gd")
const R6Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_r6_realizer.gd")

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
	_test_binary32_ulp_correction(diagnostics)
	_test_patch_owner_and_ordered_arc_paths()
	_test_bounded_causal_cavity_search(diagnostics)
	_test_patch_boundary_upper_bound(diagnostics)
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
		rows.append({"region_id": adjacent[edge_key], "edge_id": edge_key, "continuous_max_cross_squared": 0.0, "strictly_above_frozen_cutoff": false, "interior_witness": witness})
	var result: Dictionary = diagnostics.call("boundary_realizability", {"edge_maxima": rows}, ["a", "b", "c", "d", "e", "f"])
	_expect(bool(result.get("valid", false)), "all six boundary edges receive an upper bound")
	_expect(result.get("geometrically_unrealizable_boundary_edges", []).size() == 5, "only missing witnesses classify as unrealizable")

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

func _expect(condition: bool, name: String) -> void:
	assertions += 1
	if not condition:
		failures.append(name)
