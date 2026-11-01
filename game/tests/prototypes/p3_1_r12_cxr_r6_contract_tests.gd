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

func _expect(condition: bool, name: String) -> void:
	assertions += 1
	if not condition:
		failures.append(name)
