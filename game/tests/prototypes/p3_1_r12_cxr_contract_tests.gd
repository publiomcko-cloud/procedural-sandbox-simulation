extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd")
const Campaign := preload("res://tests/prototypes/p3_1_r12_cxr_campaign.gd")

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
	_test_json_root_position_reconstruction()
	_test_c6_rejection_schema_reconstruction()
	_test_cx_start_classification()
	_test_cxr_field_support_invariants()
	_test_cxr_field_candidate_enumeration()
	if failures.is_empty():
		print("R12CXR_CONTRACT_TESTS_PASS " + JSON.stringify({"assertions": assertions, "failures": 0, "suite": "bounded_cxr_contract"}))
		quit(0)
	else:
		printerr("R12CXR_CONTRACT_TESTS_FAIL " + JSON.stringify({"assertions": assertions, "failures": failures}))
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
	var residual_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r12_cx_residual_fixture.json")
	var residual_fixture: Variant = JSON.parse_string(residual_bytes.get_string_from_utf8())
	_check(Core.sha256(residual_bytes) == Realizer.EXPECTED_RESIDUAL_FIXTURE_SHA and residual_fixture is Dictionary, "tracked residual fixture bytes match the immutable physical digest")
	if residual_fixture is Dictionary:
		_check(String(residual_fixture.get("volume_payload_sha256", "")) == "2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0", "campaign schema field matches the frozen volume payload pin")
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

func _test_json_root_position_reconstruction() -> void:
	var realizer: RefCounted = Realizer.new()
	var geometry: Dictionary = {
		"root_map": [
			{"root_id": "a", "position": [0.25, -1.5, 2.0]},
			{"root_id": "b", "position": [1.25, -1.5, 2.0]},
			{"root_id": "c", "position": [0.25, -0.5, 2.0]}
		],
		"emitted_triangles": [{"polygon_id": "fixture-face", "root_ids": ["a", "b", "c"]}],
		"cutoff_rejections": []
	}
	var built: Dictionary = realizer.call("_build_triangles", geometry, {"residuals": []})
	_check(bool(built.get("valid", false)), "JSON array root positions reconstruct without Variant-to-Vector3 assignment failure")
	if bool(built.get("valid", false)):
		var points: Array = built.triangles[0].points
		_check(points.size() == 3 and points[0] is Vector3 and points[1] is Vector3 and points[2] is Vector3, "reconstructed C6 triangle positions have concrete Vector3 values")
		_check(points[0] == Vector3(0.25, -1.5, 2.0) and points[1] == Vector3(1.25, -1.5, 2.0) and points[2] == Vector3(0.25, -0.5, 2.0), "JSON root position components preserve their exact world coordinates")
	var malformed: Dictionary = geometry.duplicate(true)
	malformed["root_map"][0]["position"] = [0.25, -1.5]
	var rejected: Dictionary = realizer.call("_build_triangles", malformed, {"residuals": []})
	_check(not bool(rejected.get("valid", true)) and String(rejected.get("reason", "")) == "cx_root_position_representation_invalid", "malformed JSON root position fails closed before patch search")

func _test_cx_start_classification() -> void:
	_check(not Campaign.cx_algorithm_started({"valid": false, "reason": "fixture_reconstruction_failed"}), "missing algorithm marker is classified as pre-geometry tooling failure")
	_check(not Campaign.cx_algorithm_started({"valid": false, "cx_algorithm_started": false, "detail": {"cx_algorithm_started": true}}), "explicit top-level false marker overrides nested incidental detail")
	_check(Campaign.cx_algorithm_started({"valid": false, "detail": {"cx_algorithm_started": true}}), "started local patch search is recognized from preserved realizer detail")
	_check(Campaign.cx_algorithm_started({"valid": true, "cx_algorithm_started": true}), "completed target retains local patch search start marker")

func _test_c6_rejection_schema_reconstruction() -> void:
	var realizer: RefCounted = Realizer.new()
	var root_ids: Array = ["a", "b", "c"]
	var expected_cross_squared: float = Vector3.RIGHT.cross(Vector3(0.0, 1.0e-8, 0.0)).length_squared()
	var geometry: Dictionary = {
		"root_map": [
			{"root_id": "a", "position": [0.0, 0.0, 0.0]},
			{"root_id": "b", "position": [1.0, 0.0, 0.0]},
			{"root_id": "c", "position": [0.0, 1.0e-8, 0.0]}
		],
		"emitted_triangles": [],
		"cutoff_rejections": [{"triangle_id": "triangle-a", "source_polygon_ids": ["source-face"], "root_ids": root_ids.duplicate(), "cross_squared": expected_cross_squared}]
	}
	var fixture: Dictionary = {"residuals": [{"triangle_id": "triangle-a", "source_polygon_id": "source-face", "triangle_root_ids": root_ids.duplicate(), "rejection": {"source_polygon_ids": ["source-face"], "root_ids": root_ids.duplicate(), "cross_squared": expected_cross_squared}}]}
	var built: Dictionary = realizer.call("_build_triangles", geometry, fixture)
	_check(bool(built.get("valid", false)), "C6 source_polygon_ids/root_ids rejection schema matches the residual fixture")
	if bool(built.get("valid", false)):
		_check(built.triangles.size() == 1 and bool(built.triangles[0].get("rejected", false)), "matched C6 cutoff face is reconstructed as the single rejected source triangle")
		_check(float(built.triangles[0].get("cross_squared", INF)) == expected_cross_squared and expected_cross_squared <= 1.0e-12, "reconstructed rejection retains its measured sub-cutoff area")
	var wrong_roots: Dictionary = geometry.duplicate(true)
	wrong_roots["cutoff_rejections"][0]["root_ids"] = ["a", "b", "missing"]
	var mismatch: Dictionary = realizer.call("_build_triangles", wrong_roots, fixture)
	_check(not bool(mismatch.get("valid", true)) and String(mismatch.get("reason", "")) == "cx_fixture_to_base_rejection_mismatch", "C6 rejection with different roots is rejected before geometry search")
	var rounded_fixture: Dictionary = fixture.duplicate(true)
	rounded_fixture["residuals"][0]["rejection"]["cross_squared"] = expected_cross_squared * 0.998
	var rounded: Dictionary = realizer.call("_build_triangles", geometry, rounded_fixture)
	_check(bool(rounded.get("valid", false)), "pinned residual diagnostic rounded by less than the documented 0.5 percent is accepted against exact C6 area")
	var stale_fixture: Dictionary = fixture.duplicate(true)
	stale_fixture["residuals"][0]["rejection"]["cross_squared"] = expected_cross_squared * 0.98
	var stale: Dictionary = realizer.call("_build_triangles", geometry, stale_fixture)
	_check(not bool(stale.get("valid", true)) and String(stale.get("reason", "")) == "cx_fixture_cutoff_area_mismatch", "residual diagnostic outside its bounded rounding envelope is rejected")
	var wrong_c6_area: Dictionary = geometry.duplicate(true)
	wrong_c6_area["cutoff_rejections"][0]["cross_squared"] = expected_cross_squared * 2.0
	var c6_mismatch: Dictionary = realizer.call("_build_triangles", wrong_c6_area, fixture)
	_check(not bool(c6_mismatch.get("valid", true)) and String(c6_mismatch.get("reason", "")) == "cx_c6_cutoff_area_mismatch", "exact C6 area disagreement is rejected even when residual metadata remains pinned")
	var nonfinite_fixture: Dictionary = fixture.duplicate(true)
	nonfinite_fixture["residuals"][0]["rejection"]["cross_squared"] = NAN
	var bad_fixture_area: Dictionary = realizer.call("_build_triangles", geometry, nonfinite_fixture)
	_check(not bool(bad_fixture_area.get("valid", true)) and String(bad_fixture_area.get("reason", "")) == "cx_fixture_cutoff_area_mismatch", "nonfinite residual annotation fails closed")
	var nonfinite_c6: Dictionary = geometry.duplicate(true)
	nonfinite_c6["cutoff_rejections"][0]["cross_squared"] = NAN
	var bad_c6_area: Dictionary = realizer.call("_build_triangles", nonfinite_c6, fixture)
	_check(not bool(bad_c6_area.get("valid", true)) and String(bad_c6_area.get("reason", "")) == "cx_c6_cutoff_area_mismatch", "nonfinite canonical C6 cutoff area fails closed")

func _test_cxr_field_support_invariants() -> void:
	var realizer: RefCounted = Realizer.new()
	var positions: Array[Vector3] = [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var barycentric: Dictionary = realizer.call("_tetra_barycentric", Vector3(1.0 / 6.0, 1.0 / 6.0, 1.0 / 6.0), positions)
	var bary_weights: Array = barycentric.get("weights", [])
	_check(bool(barycentric.get("valid", false)) and bary_weights.size() == 4, "CXR accepts finite tetrahedron barycentric coordinates")
	var field_value: float = -1.0 * float(bary_weights[0]) + float(bary_weights[1]) + float(bary_weights[2]) + float(bary_weights[3])
	_check(absf(field_value) <= Realizer.CXR_FIELD_RESIDUAL_EPSILON, "CXR barycentric support lies on pinned piecewise-linear frozen field")
	var projection: Dictionary = realizer.call("_project_to_tetra_zero_plane", Vector3(0.25, 0.25, 0.25), {"positions": positions, "samples": [-1.0, 1.0, 1.0, 1.0]})
	_check(bool(projection.get("valid", false)) and Vector3(projection.get("point", Vector3.ZERO)).is_finite(), "CXR bounded projection returns a finite point on a valid tetrahedral zero plane")
	_check(absf(float(projection.get("frozen_field_residual", INF))) <= Realizer.CXR_FIELD_RESIDUAL_EPSILON, "CXR projection records and satisfies frozen-field residual tolerance")
	var residual: Dictionary = {"triangle_id": "fixture-residual", "polygon_id": "fixture-polygon", "root_ids": ["a", "b", "c"], "points": [Vector3.ZERO, Vector3.RIGHT, Vector3.UP], "normal": Vector3.BACK}
	var fan: Dictionary = realizer.call("_candidate_support_fan", residual, {"support_id": "support-fixture", "world_position": Vector3(0.3, 0.3, 0.2)})
	_check(bool(fan.get("valid", false)) and fan.get("triangles", []).size() == 3 and fan.get("triangle_rows", []).size() == 3, "CXR emits a complete oriented three-triangle support fan")
	_check(float(fan.get("minimum_cross_squared", 0.0)) > Realizer.CXR_CUTOFF_SQUARED, "CXR fan preserves the frozen strict cross-squared cutoff")
	var bad_orientation: Dictionary = residual.duplicate(true)
	bad_orientation["normal"] = Vector3.FORWARD
	var inverted_fan: Dictionary = realizer.call("_candidate_support_fan", bad_orientation, {"support_id": "support-inverted", "world_position": Vector3(0.3, 0.3, 0.2)})
	_check(not bool(inverted_fan.get("valid", true)) and String(inverted_fan.get("reason", "")) == "candidate_triangle_winding" and not inverted_fan.get("triangle_rows", []).is_empty(), "CXR rejects winding inconsistent with parent orientation while retaining geometry diagnostics")
	_check(Realizer.CXR_MAX_CANDIDATE_ATTEMPTS_PER_CAVITY == 8192 and Realizer.CXR_MAX_SUPPORT_CANDIDATES_PER_CAVITY == 256 and Realizer.CXR_MAX_SELECTED_SUPPORTS == 4, "CXR runtime search caps match the preregistration")
	_check(Realizer.CXR_MAX_SEARCH_STATES_PER_CAVITY == 16384 and Realizer.CXR_MAX_SEARCH_STATES_TOTAL == 32768 and Realizer.CXR_MAX_RETAINED_SOLUTIONS == 32, "CXR search and retained-solution caps match the preregistration")

func _test_cxr_field_candidate_enumeration() -> void:
	var realizer: RefCounted = Realizer.new()
	realizer.set("_cxr_local_search_marker_emitted", true)
	realizer.set("_cxr_search_started_usec", Time.get_ticks_usec())
	realizer.set("_cxr_cavity_started_usec", Time.get_ticks_usec())
	var values: PackedFloat32Array = PackedFloat32Array()
	for y in range(2):
		for z in range(2):
			for x in range(2):
				values.append(-0.25 if x == 0 else 0.75)
	var residual_points: Array[Vector3] = [Vector3(0.25, 0.25, 0.25), Vector3(0.25, 0.75, 0.25), Vector3(0.25, 0.25, 0.75)]
	var residual: Dictionary = {"triangle_id": "fixture-residual", "points": residual_points}
	var patch: Array[Dictionary] = [{"triangle_id": "fixture-patch", "points": residual_points}]
	var roi: Dictionary = {"min": [0.0, 0.0, 0.0], "cells": [1, 1, 1], "step": 1.0}
	var first: Dictionary = realizer.call("_generate_field_candidates", residual, patch, values, roi, 0, 16, 128, "fixture-cavity", {"triangle_id": "fixture-residual"})
	var attempts: Array = first.get("attempts", [])
	var candidate_pool: Array = first.get("candidate_pool", [])
	_check(attempts.size() > 1, "CXR candidate enumeration tests multiple frozen tetrahedron intersections instead of exiting the loop body")
	_check(not candidate_pool.is_empty(), "CXR retains support candidates derived from the synthetic frozen-field zero set")
	_check(not bool(first.get("attempt_cap_hit", true)) and bool(first.get("source_valid", false)), "bounded CXR candidate fixture completes without an attempt cap or invalid source tetrahedron")
func _triangle(id: String, root_ids: Array, points_by_id: Dictionary, rejected: bool) -> Dictionary:
	var points: Array[Vector3] = [points_by_id[root_ids[0]], points_by_id[root_ids[1]], points_by_id[root_ids[2]]]
	var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	return {"triangle_id":id, "polygon_id":id, "root_ids":root_ids.duplicate(), "points":points, "normal":cross.normalized() if cross.length_squared() > 0.0 else Vector3.ZERO, "cross_squared":cross.length_squared(), "rejected":rejected, "construction":"synthetic"}

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)
