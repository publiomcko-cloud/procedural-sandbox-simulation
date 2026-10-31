extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_cx_micropatch_realizer.gd")

var assertions: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_sliver_flip_and_determinism()
	_test_required_arc_and_boundaries()
	_test_cutoff_and_topology_guards()
	_test_t_junction_oracle()
	_test_fixture_identity()
	if failures.is_empty():
		print("R12CX_CONTRACT_TESTS_PASS " + JSON.stringify({"assertions": assertions, "failures": 0, "suite": "bounded_cx_contract"}))
		quit(0)
	else:
		printerr("R12CX_CONTRACT_TESTS_FAIL " + JSON.stringify({"assertions": assertions, "failures": failures}))
		quit(1)

func _test_sliver_flip_and_determinism() -> void:
	var realizer: RefCounted = Realizer.new()
	var points: Dictionary = {
		"a": Vector3(0.0, 0.0, 0.0),
		"b": Vector3(1.0, 0.0, 0.0),
		"c": Vector3(2.0, 1.0e-7, 0.0),
		"d": Vector3(0.0, 1.0, 0.0)
	}
	var triangles: Array[Dictionary] = [
		_triangle("old-abc", ["a", "b", "c"], points, true),
		_triangle("old-acd", ["a", "c", "d"], points, false)
	]
	var boundary_before: Dictionary = realizer.call("_boundary_state", triangles)
	_check(float(triangles[0].cross_squared) <= 1.0e-12, "synthetic precondition is below fixed cutoff")
	var no_locked_edges: Array[String] = []
	var first: Dictionary = realizer.call("search_patch_for_test", triangles, no_locked_edges, 4096)
	_check(bool(first.get("valid", false)), "bounded edge flip repairs synthetic sliver")
	_check(bool(first.get("search_complete", false)), "synthetic repair search is complete")
	var replacement: Array[Dictionary] = first.get("replacement_triangles", [])
	_check(realizer.call("_cutoff_triangles", replacement).is_empty(), "replacement uses strict unchanged cutoff")
	_check(realizer.call("_boundary_state", replacement).get("signature", "") == boundary_before.get("signature", ""), "replacement preserves exact directed cavity boundary")
	_check(int(first.get("support_vertex_count", 0)) == 0, "edge-flip repair selects no support vertices")
	var second: Dictionary = realizer.call("search_patch_for_test", triangles, no_locked_edges, 4096)
	_check(bool(second.get("valid", false)) and String(realizer.call("_state_key", first.get("replacement_triangles", []))) == String(realizer.call("_state_key", second.get("replacement_triangles", []))), "same inputs select deterministic patch state")
	_check(Core.sha256(JSON.stringify(first.get("flips", [])).to_utf8_buffer()) == Core.sha256(JSON.stringify(second.get("flips", [])).to_utf8_buffer()), "flip provenance is deterministic")

func _test_required_arc_and_boundaries() -> void:
	var realizer: RefCounted = Realizer.new()
	var points: Dictionary = {"a": Vector3.ZERO, "b": Vector3(1.0, 0.0, 0.0), "c": Vector3(2.0, 1.0e-7, 0.0), "d": Vector3(0.0, 1.0, 0.0)}
	var triangles: Array[Dictionary] = [_triangle("old-abc", ["a", "b", "c"], points, true), _triangle("old-acd", ["a", "c", "d"], points, false)]
	var locked_edges: Array[String] = [String(realizer.call("_edge_key", "a", "c"))]
	var locked: Dictionary = realizer.call("search_patch_for_test", triangles, locked_edges, 4096)
	_check(not bool(locked.get("valid", false)) and bool(locked.get("complete", true)), "required topology arc cannot be flipped and search exhausts declared local domain")
	var disconnected: Array[Dictionary] = triangles.duplicate(true)
	disconnected.append(_triangle("separate-xyz", ["x", "y", "z"], {"x": Vector3(3,0,0), "y": Vector3(4,0,0), "z": Vector3(3,1,0)}, false))
	var disconnected_boundary: Dictionary = realizer.call("_boundary_state", disconnected)
	_check(not bool(disconnected_boundary.get("valid", false)), "multiple boundary cycles reject patch")
	var no_locked_edges: Array[String] = []
	var low_cap: Dictionary = realizer.call("search_patch_for_test", triangles, no_locked_edges, 1)
	_check(not bool(low_cap.get("valid", false)) and not bool(low_cap.get("complete", true)), "search node cap returns partial rather than false infeasibility")

func _test_cutoff_and_topology_guards() -> void:
	var realizer: RefCounted = Realizer.new()
	var exact: Array[Dictionary] = [{"triangle_id":"at-cutoff", "cross_squared":1.0e-12}]
	var above: Array[Dictionary] = [{"triangle_id":"above-cutoff", "cross_squared":1.0000001e-12}]
	_check(realizer.call("_cutoff_triangles", exact).size() == 1, "equality to cutoff is rejected")
	_check(realizer.call("_cutoff_triangles", above).is_empty(), "strictly above cutoff is accepted")
	var nonmanifold: Array[Dictionary] = [
		{"triangle_id":"a", "root_ids":["u","v","w"], "points":[Vector3.ZERO,Vector3.RIGHT,Vector3.UP]},
		{"triangle_id":"b", "root_ids":["v","u","x"], "points":[Vector3.RIGHT,Vector3.ZERO,Vector3(0,0,1)]},
		{"triangle_id":"c", "root_ids":["u","v","y"], "points":[Vector3.ZERO,Vector3.RIGHT,Vector3(1,1,1)]}
	]
	var incidences: Dictionary = realizer.call("_edge_incidence", nonmanifold)
	var shared_edge_key: String = String(realizer.call("_edge_key", "u", "v"))
	_check(int(incidences.get(shared_edge_key, 0)) == 3, "nonmanifold shared-edge fixture is detected")
	var invalid_points: Dictionary = {"a":Vector3.ZERO,"b":Vector3.RIGHT,"c":Vector3(2,0,0),"d":Vector3(3,0,0)}
	var invalid: Array[Dictionary] = [_triangle("bad-abc",["a","b","c"],invalid_points,true),_triangle("bad-acd",["a","c","d"],invalid_points,false)]
	var no_locked_edges: Array[String] = []
	var invalid_result: Dictionary = realizer.call("search_patch_for_test", invalid, no_locked_edges, 4096)
	_check(not bool(invalid_result.get("valid", false)), "collinear isolated cavity cannot produce a valid patch")

func _test_t_junction_oracle() -> void:
	var realizer: RefCounted = Realizer.new()
	var points: Dictionary = {"a":Vector3.ZERO,"b":Vector3(2,0,0),"m":Vector3(1,0,0),"c":Vector3(0,1,0),"d":Vector3(2,1,0)}
	var patch: Array[Dictionary] = [_triangle("patch-mcd",["m","c","d"],points,false)]
	var all: Array[Dictionary] = [patch[0],_triangle("edge-ab",["a","b","c"],points,false),_triangle("split-am",["a","m","d"],points,false),_triangle("split-mb",["m","b","d"],points,false)]
	_check(int(realizer.call("_new_t_junction_count", patch, all)) > 0, "T-junction boundary vertex is rejected")
	var conforming_patch: Array[Dictionary] = [_triangle("conforming-amd",["a","m","d"],points,false),_triangle("conforming-mbd",["m","b","d"],points,false)]
	var conforming_all: Array[Dictionary] = conforming_patch.duplicate()
	conforming_all.append(_triangle("adjacent-acm",["a","c","m"],points,false))
	conforming_all.append(_triangle("adjacent-mcb",["m","c","b"],points,false))
	_check(int(realizer.call("_new_t_junction_count", conforming_patch, conforming_all)) == 0, "matching split boundary has no T-junction")

func _test_fixture_identity() -> void:
	var realizer: RefCounted = Realizer.new()
	var base: Dictionary = {"mesh_sha256":Realizer.EXPECTED_C6_MESH_SHA}
	var fixture: Dictionary = {"schema":"P3.1.R12CX.ResidualCutoffFixture.v1", "c6_artifact_sha256":"0c6ae06d368f1a789ddc16fae429700c109d09fc019082fe6356c58fee12c6de", "c6_mesh_sha256":"wrong", "volume_sha256":Realizer.EXPECTED_C6_VOLUME_SHA, "residual_triangle_count":3}
	_check(String(realizer.call("_validate_residual_fixture", fixture, base)) == "cx_c6_mesh_identity_mismatch", "mismatched residual fixture identity fails closed")
	_check(Realizer.EXPECTED_RESIDUAL_FIXTURE_SHA == "ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23", "final residual fixture pin matches corrected Candidate D provenance")
	var empty_supports: Dictionary = realizer.call("validate_support_records", [], {})
	_check(bool(empty_supports.get("valid", false)) and int(empty_supports.get("count", -1)) == 0, "zero-selected-support profile has valid empty provenance")
	_check(String(empty_supports.get("provenance_sha256", "")) == Core.sha256("[]".to_utf8_buffer()), "empty support provenance digest is deterministic")
	var cavity_id: String = "cavity-test"
	var primitive_id: String = "tetra-2-edge-0-3"
	var method: String = "tetrahedral_edge_interpolation"
	var ordering_key: String = "residual-1|candidate-0"
	var support_record: Dictionary = {
		"support_id": realizer.call("support_id", cavity_id, primitive_id, method, ordering_key),
		"cavity_id": cavity_id,
		"parent_topology_face_or_path": "face-test",
		"source_polygon_ids": ["polygon-test"],
		"source_cell": [0, 0, 0],
		"source_tetrahedron": 2,
		"generation_method": method,
		"source_primitive": primitive_id,
		"interpolation_parameter": 0.5,
		"world_position": Vector3(0.25, 0.5, 0.0),
		"field_residual": 0.0,
		"zero_set_residual": 0.0,
		"inside_source_primitive": true,
		"neighboring_output_faces": ["face-test"],
		"ordering_key": ordering_key
	}
	var support_ok: Dictionary = realizer.call("validate_support_record", support_record)
	_check(bool(support_ok.get("valid", false)) and float(support_ok.get("field_residual", INF)) == 0.0 and float(support_ok.get("zero_set_residual", INF)) == 0.0, "complete synthetic support provenance records exact zero residuals")
	_check(String(realizer.call("support_id", cavity_id, primitive_id, method, ordering_key)) == String(support_record.support_id), "support IDs are deterministic for canonical ordering inputs")
	var tampered_support: Dictionary = support_record.duplicate(true)
	tampered_support["source_primitive"] = "tampered-primitive"
	_check(not bool(realizer.call("validate_support_record", tampered_support).get("valid", true)), "tampered support provenance is rejected")
	_check(not bool(realizer.call("validate_support_records", [support_record], {}).get("valid", true)), "profile cap prevents selecting supports in edge-flip-only search")

func _triangle(id: String, root_ids: Array, points_by_id: Dictionary, rejected: bool) -> Dictionary:
	var points: Array[Vector3] = [points_by_id[root_ids[0]], points_by_id[root_ids[1]], points_by_id[root_ids[2]]]
	var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	return {"triangle_id":id, "polygon_id":id, "root_ids":root_ids.duplicate(), "points":points, "normal":cross.normalized() if cross.length_squared() > 0.0 else Vector3.ZERO, "cross_squared":cross.length_squared(), "rejected":rejected, "construction":"synthetic"}

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)
