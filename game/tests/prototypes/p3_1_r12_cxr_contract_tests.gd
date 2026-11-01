extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd")
const Campaign := preload("res://tests/prototypes/p3_1_r12_cxr_campaign.gd")

var assertions: int = 0
var failures: Array[String] = []
var _sequence_probe_calls: Array[Array] = []

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
	_test_cxr_r1_level_and_cavity_continuation()
	_test_cxr_r2_constrained_triangulation()
	_test_cxr_r3_remaining_boundary_and_separate_cavities()
	_test_cxr_r3_capped_pool_triangulation_and_valid_witness()
	_test_r3_expanded_patch_owner_and_replacement_sets()
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
	_check(int(first.get("candidate_unique_count", -1)) >= candidate_pool.size() and candidate_pool.size() == int(first.get("candidate_count", -1)), "candidate evidence distinguishes all unique supports from the bounded retained pool")
	var capped: Dictionary = realizer.call("_generate_field_candidates", residual, patch, values, roi, 0, 0, 128, "fixture-cavity-cap", {"triangle_id": "fixture-residual"})
	var capped_evidence: Dictionary = realizer.call("_validate_candidate_generation_evidence", capped)
	_check(bool(capped_evidence.get("valid", false)) and capped.candidate_pool.size() == 0 and int(capped.candidate_unique_count) > 0 and bool(capped.candidate_cap_hit), "candidate retention cap bounds the searchable pool while preserving candidate attempt evidence")

func _test_cxr_r1_level_and_cavity_continuation() -> void:
	var realizer: RefCounted = Realizer.new()
	var nonmanifold: Array[Dictionary] = [
		{"triangle_id":"a", "root_ids":["u","v","w"]},
		{"triangle_id":"b", "root_ids":["v","u","x"]},
		{"triangle_id":"c", "root_ids":["u","v","y"]}
	]
	var boundary: Dictionary = realizer.call("_boundary_state", nonmanifold)
	var shared_edge: String = String(realizer.call("_edge_key", "u", "v"))
	var shared_incidence: int = -1
	for incidence_value in boundary.get("edge_incidence", []):
		var incidence: Dictionary = incidence_value
		if String(incidence.get("edge", "")) == shared_edge:
			shared_incidence = int(incidence.get("incidence_count", -1))
	_check(not bool(boundary.get("valid", true)) and shared_incidence == 3, "invalid boundary reports complete incidence including nonmanifold edge")
	_check(int(boundary.get("edge_count", -1)) == 7 and boundary.has("diagnostic_sha256"), "invalid boundary diagnostics retain every unique edge and a stable digest")
	var cavity_report: Dictionary = {"levels": [], "residual_triangle_ids": ["a", "b", "c"]}
	var level_report: Dictionary = realizer.call("_new_cxr_level_report", 1, ["a", "b", "c"], 3)
	var continue_after_invalid: bool = bool(realizer.call("_record_invalid_cxr_boundary_level", cavity_report, level_report, boundary))
	_check(continue_after_invalid, "invalid patch boundary is a recoverable level result and allows L2 or L3")
	_check(cavity_report.levels.size() == 1 and String(cavity_report.levels[0].candidate_generation_status) == "NOT_RUN_INVALID_BOUNDARY", "invalid boundary records candidate generation as not run instead of an invented timing")
	_check(String(cavity_report.levels[0].candidate_attempt_count) == "NOT_RUN_INVALID_BOUNDARY" and String(cavity_report.levels[0].candidate_triangle_count) == "NOT_RUN_INVALID_BOUNDARY", "invalid boundary marks unrun candidate metrics explicitly instead of inventing zero measurements")
	_check(String(cavity_report.levels[0].candidate_unique_count_by_residual["b"]) == "NOT_RUN_INVALID_BOUNDARY" and String(cavity_report.levels[0].search_nodes) == "NOT_RUN_INVALID_BOUNDARY", "invalid boundary explicitly accounts for every residual and unrun search counters")
	realizer.call("_append_unrun_cxr_levels", cavity_report, 2, "NOT_RUN_CAVITY_LIMIT", "synthetic_stop_limit")
	_check(cavity_report.levels.size() == 3 and cavity_report.levels[1].level == 2 and cavity_report.levels[2].level == 3, "stopped cavity explicitly records every later unrun level")
	_check(String(cavity_report.levels[1].candidate_generation_usec) == "NOT_RUN_CAVITY_LIMIT", "unrun-level time is not fabricated as zero")
	_sequence_probe_calls.clear()
	realizer.set("_cxr_search_started_usec", Time.get_ticks_usec())
	realizer.set("_cxr_search_nodes_total", 0)
	var groups: Array[Array] = [["cavity-a"], ["cavity-b"], ["cavity-c"]]
	var sequence: Dictionary = realizer.call("_run_cxr_cavity_sequence", groups, Callable(self, "_sequence_probe_local_failure"))
	_check(_sequence_probe_calls.size() == 3 and sequence.cavity_results.size() == 3, "a locally failed cavity does not suppress later cavity searches")
	_check(bool(sequence.search_complete) and bool(sequence.search_exhaustive) and sequence.failure_reasons.size() == 3, "all complete local failures are represented without claiming a solution")
	_sequence_probe_calls.clear()
	var partial_groups: Array[Array] = [["partial-cavity"], ["complete-cavity"]]
	var partial_sequence: Dictionary = realizer.call("_run_cxr_cavity_sequence", partial_groups, Callable(self, "_sequence_probe_candidate"))
	_check(_sequence_probe_calls.size() == 2 and partial_sequence.failure_reasons.is_empty(), "a valid candidate retained before a local limit does not suppress another cavity")
	_check(not bool(partial_sequence.search_complete) and not bool(partial_sequence.search_exhaustive), "retained candidates preserve partial rather than exhaustive search status")
	var partial_candidate: Dictionary = realizer.call("_finish_cxr_cavity_search", {"levels": [], "selected_supports": []}, {"solution": {"selected_supports": [{"support_id":"support-r1"}]}, "patch_ids": ["patch-r1"], "patch_record": {}, "replacement_triangles": [], "level": 2}, false, false, "limit_candidate_search")
	_check(bool(partial_candidate.valid) and not bool(partial_candidate.search_complete) and String(partial_candidate.selected_supports[0].support_id) == "support-r1", "best candidate remains available to downstream geometry gates while retaining partial status")
	_sequence_probe_calls.clear()
	realizer.set("_cxr_search_started_usec", 1)
	var limited_sequence: Dictionary = realizer.call("_run_cxr_cavity_sequence", groups, Callable(self, "_sequence_probe_local_failure"), Realizer.CXR_MAX_SEARCH_USEC_TOTAL + 2)
	_check(_sequence_probe_calls.is_empty() and limited_sequence.cavity_results.size() == 3, "a reached global time cap prevents subsequent cavity execution")
	_check(String(limited_sequence.cavity_results[0].get("status", "")) == "NOT_RUN_GLOBAL_LIMIT" and not bool(limited_sequence.search_complete), "global cap marks all skipped cavities and makes the sequence incomplete")
	_sequence_probe_calls.clear()
	var incomplete_evidence: Dictionary = realizer.call("_validate_candidate_generation_evidence", {"attempts": [], "candidate_pool": [], "candidates": [], "candidate_attempt_count": 0, "candidate_count": 0, "source_valid": true, "limit_hit": false, "limits_hit": []})
	_check(not bool(incomplete_evidence.get("valid", true)) and String(incomplete_evidence.get("reason", "")) == "required_candidate_generation_fields_missing", "candidate-generation records missing runtime or provenance fields fail closed")
	var partial_attempts: Array[Dictionary] = [{"candidate_id": "preserve-attempt"}]
	var partial_pool: Array[Dictionary] = [{"candidate_id": "preserve-support"}]
	var failed_cavity: Dictionary = {"levels": [], "candidate_attempts": [], "support_candidates": [], "support_candidates_retained": [], "terminal_reason": "UNKNOWN_NOT_CAPTURED"}
	var failed_level: Dictionary = realizer.call("_new_cxr_level_report", 0, ["patch"], 1)
	failed_level["candidate_generation_usec"] = 0
	var failed_residuals: Array[Dictionary] = [{"triangle_id": "residual-0"}, {"triangle_id": "residual-1"}]
	realizer.call("_preserve_incomplete_candidate_generation", {"attempts": partial_attempts, "candidate_pool": partial_pool, "candidates": partial_pool, "candidate_generation_usec": 7}, incomplete_evidence, failed_cavity, failed_level, failed_residuals, failed_residuals[0], "residual-0", 0)
	_check(failed_cavity.candidate_attempts.size() == 1 and failed_cavity.support_candidates.size() == 1 and failed_cavity.support_candidates_retained.size() == 1 and failed_level.candidate_generation_usec == 7, "incomplete candidate metadata does not discard captured attempts, supports or elapsed time")
	_check(failed_level.candidate_count_by_residual["residual-0"] == 1 and failed_level.candidate_generation_unvalidated.candidates.size() == 1, "evidence failure preserves generated but unvalidated candidate rows without claiming they were tested")
	_check(String(failed_level.candidate_count_by_residual["residual-1"]) == "NOT_RUN_EVIDENCE_FAILURE", "remaining residual faces are explicitly marked unrun after evidence failure")
	var inconsistent_evidence: Dictionary = realizer.call("_validate_candidate_generation_evidence", {"attempts": [], "candidate_pool": [], "candidates": [], "candidate_attempt_count": 1, "candidate_count": 0, "candidate_unique_count": 0, "candidate_cap_hit": false, "attempt_cap_hit": false, "time_cap_reason": "", "candidate_generation_usec": 1, "source_valid": true, "source_failure_reason": "", "source_tetrahedron_count": 0, "invalid_tetrahedron_count": 0, "cell_bounds": {}, "limit_hit": false, "limits_hit": []})
	_check(not bool(inconsistent_evidence.get("valid", true)) and String(inconsistent_evidence.get("reason", "")) == "candidate_attempt_count_mismatch", "candidate-generation counters must match the retained attempt rows")
	var complete_no_solution: Dictionary = {"reason": "cx_bounded_patch_search_failed", "detail": {"details": {"search": {"phase": "r1", "reason": "cxr_no_valid_field_support_solution", "complete": true, "search_exhaustive": true}}}}
	var bounded_failure: Dictionary = {"reason": "cx_bounded_patch_search_failed", "detail": {"details": {"search": {"reason": "limit_MAX_SEARCH_STATES_TOTAL", "complete": false, "search_exhaustive": false}}}}
	var overlapping_best: Dictionary = {"reason": "cx_bounded_patch_search_failed", "detail": {"details": {"search": {"reason": "cxr_joint_patch_overlap", "complete": true, "search_exhaustive": false}}}}
	_check(not Campaign._target_search_partial(complete_no_solution, {}), "R2 advancement gate accepts only a complete exhaustive R1 no-solution result")
	_check(Campaign._target_search_partial(bounded_failure, {}) and Campaign._target_search_partial(overlapping_best, {}), "caps and overlapping cavity choices remain partial rather than proving R1 infeasibility")
	_check(Campaign._result_class("PARTIAL") == "R12_CXR_PARTIAL_WITH_EVIDENCE" and Campaign._result_class("FAILED_TARGET") == "R12_CXR_FAILED_TARGET_WITH_EVIDENCE", "terminal classes retain the preregistered R12-CXR result vocabulary")
	_check(Campaign._campaign_disposition("R12_CXR_PARTIAL_WITH_EVIDENCE", {}, true, {"status": "FAIL"}) == "R12_CXR_PARTIAL_WITH_EVIDENCE", "partial search cannot be overwritten by a later interface failure")
	_check(Campaign._campaign_disposition("R12_CXR_FAILED_TARGET_WITH_EVIDENCE", complete_no_solution, false, {}) == "R12_CXR_R1_COMPLETE_NO_SOLUTION_R2_ELIGIBLE", "only exhaustive R1 failure enables the next architecture phase")
	var r2_complete_no_solution: Dictionary = {"reason": "cx_bounded_patch_search_failed", "detail": {"cx_algorithm_started": true, "details": {"search": {"phase": "r2", "reason": "cxr_r2_no_valid_constrained_triangulation", "complete": true, "search_exhaustive": true}}}}
	var r2_partial_no_solution: Dictionary = {"reason": "cx_bounded_patch_search_failed", "detail": {"cx_algorithm_started": true, "details": {"search": {"phase": "r2", "reason": "R2_MAX_SEARCH_STATES_PER_CAVITY", "complete": false, "search_exhaustive": false}}}}
	_check(Campaign._campaign_disposition("R12_CXR_FAILED_TARGET_WITH_EVIDENCE", r2_complete_no_solution, false, {}) == "R12_CXR_R2_COMPLETE_NO_SOLUTION_R3_ELIGIBLE", "only a complete exhaustive R2 no-solution result enables R3")
	_check(Campaign._campaign_disposition("R12_CXR_PARTIAL_WITH_EVIDENCE", r2_partial_no_solution, false, {}) == "R12_CXR_PARTIAL_WITH_EVIDENCE", "partial R2 resource exhaustion never enables R3")
	_check(Campaign._campaign_disposition("R12_CXR_FAILED_TARGET_WITH_EVIDENCE", {}, true, {"status": "FAIL"}) == "R12_CXR_EQUAL_LOD_QUALIFIED_INTERFACE_BLOCKED_WITH_EVIDENCE", "equal-LOD success followed by interface failure has a distinct disposition")
	_check(Campaign._target_search_partial({"reason": "cx_bounded_patch_search_failed", "detail": "malformed"}, {}) and Campaign._target_search_partial({}, {"cxr_local_search_complete": "UNKNOWN_NOT_CAPTURED"}), "ambiguous or malformed search-completion metadata remains partial")
	_check(Campaign._target_search_partial({"reason": "cxr_realize_time_limit"}, {}), "realizer wall-time exhaustion is classified as partial rather than target infeasibility")
	_check(not Campaign._target_has_structural_regression({"mesh_topology": "UNKNOWN_NOT_CAPTURED", "missing_topology_obligations": "UNKNOWN_NOT_CAPTURED"}), "unknown structural measurements are not misread as geometry regression or zero")
	var within_deadline: Dictionary = realizer.call("_apply_realizer_deadline", {"valid": false, "reason": "synthetic_geometry_failure", "details": {"search_complete": true}}, 1)
	_check(String(within_deadline.get("reason", "")) == "synthetic_geometry_failure" and int(within_deadline.get("realizer_wall_usec", -1)) == 1, "within-budget early failures retain their original classification and wall-time evidence")
	var over_deadline: Dictionary = realizer.call("_apply_realizer_deadline", {"valid": true, "geometry": {"geometry_complete": true, "cxr_local_search_complete": true}}, Realizer.CXR_MAX_REALIZE_USEC + 1)
	_check(bool(over_deadline.get("valid", false)) and not bool(over_deadline.geometry.geometry_complete) and String(over_deadline.geometry.realizer_failure_reason) == "cxr_realize_time_limit", "over-budget candidate geometry is preserved but cannot be marked complete")
	var failed_over_deadline: Dictionary = realizer.call("_apply_realizer_deadline", {"valid": false, "cx_algorithm_started": true, "reason": "synthetic_search_failure", "details": {"search": {"complete": false}}}, Realizer.CXR_MAX_REALIZE_USEC + 1)
	_check(String(failed_over_deadline.get("reason", "")) == "cxr_realize_time_limit" and failed_over_deadline.details.prior_result.details.search.complete == false, "over-budget early failure preserves the complete prior failure evidence")
	var empty_patch: Array[Dictionary] = []
	var no_values: PackedFloat32Array = PackedFloat32Array()
	var invalid_candidate_output: Dictionary = realizer.call("_generate_field_candidates", {"points": []}, empty_patch, no_values, {}, 0, 4, 4, "invalid-cavity", {})
	var invalid_candidate_evidence: Dictionary = realizer.call("_validate_candidate_generation_evidence", invalid_candidate_output)
	_check(bool(invalid_candidate_evidence.get("valid", false)) and String(invalid_candidate_output.get("source_failure_reason", "")) == "residual_point_arity_invalid" and int(invalid_candidate_output.get("candidate_generation_usec", -1)) >= 0, "early invalid-input returns retain complete, measured failure evidence")

func _test_cxr_r2_constrained_triangulation() -> void:
	var realizer: RefCounted = Realizer.new()
	var points: Dictionary = {"a": Vector3(0.0, 0.0, 0.0), "b": Vector3(1.0, 0.0, 0.0), "c": Vector3(1.0, 1.0, 0.0), "d": Vector3(0.0, 1.0, 0.0)}
	var boundary: Array[Dictionary] = [_triangle("owner-left", ["a", "b", "c"], points, false), _triangle("owner-right", ["a", "c", "d"], points, false)]
	for triangle in boundary:
		triangle["polygon_id"] = "frozen-owner"
		triangle["source_polygon_ids"] = ["frozen-owner"]
	var required_diagonal: Array[Dictionary] = [{"arc_id": "frozen-diagonal-a-c", "root_ids": ["a", "c"], "expected_incidence": 2}]
	var exact_boundary: Dictionary = realizer.call("_boundary_state", boundary)
	var no_supports: Array[Dictionary] = []
	var support_free: Dictionary = realizer.call("solve_r2_fixture_for_test", boundary, no_supports, 0, required_diagonal)
	_check(bool(support_free.get("valid", false)) and bool(support_free.get("search_complete", false)) and bool(support_free.get("search_exhaustive", false)), "R2 finite constrained search finds and exhausts the valid support-free disk triangulation")
	_check(realizer.call("_boundary_state", support_free.get("best_solution", {}).get("replacement_triangles", [])).get("signature", "") == exact_boundary.get("signature", ""), "R2 support-free output preserves exact cavity boundary signature")
	var support: Dictionary = {"support_id": "support-center-off-diagonal", "accepted": true, "supported": true, "frozen_field_interpolated_residual": 0.0, "world_position": Vector3(0.25, 0.2, 0.0), "source_polygon_ids": ["frozen-owner"], "binary32_position_identity": var_to_bytes(Vector3(0.25, 0.2, 0.0)).hex_encode()}
	var one_support: Array[Dictionary] = [support]
	var supported: Dictionary = realizer.call("solve_r2_fixture_for_test", boundary, one_support, 1, required_diagonal)
	_check(bool(supported.get("valid", false)) and bool(supported.get("search_complete", false)) and bool(supported.get("search_exhaustive", false)), "R2 general triangulation can insert one frozen-field support and exhaust that support-count domain")
	var supported_solution: Dictionary = supported.get("best_solution", {})
	var supported_triangles: Array[Dictionary] = []
	for triangle_value in supported_solution.get("replacement_triangles", []):
		supported_triangles.append(triangle_value)
	_check(supported_solution.get("support_ids", []) == ["support-center-off-diagonal"] and supported_triangles.size() == 4, "R2 support insertion preserves disk Euler count and exact selected identity")
	_check(realizer.call("_boundary_state", supported_triangles).get("signature", "") == exact_boundary.get("signature", ""), "R2 support insertion preserves exact directed exterior boundary")
	_check(bool(realizer.call("_validate_required_arcs", supported_triangles, required_diagonal, []).get("valid", false)), "R2 support insertion retains frozen internal ownership arc")
	var owner_ids: Dictionary = {"frozen-owner": true}
	var owners_preserved: bool = true
	for triangle in supported_triangles:
		owners_preserved = owners_preserved and owner_ids.has(String(triangle.get("polygon_id", ""))) and triangle.get("source_polygon_ids", []).has("frozen-owner")
	_check(owners_preserved, "R2 candidate triangles preserve frozen source polygon ownership metadata")
	var repeated: Dictionary = realizer.call("solve_r2_fixture_for_test", boundary, one_support, 1, required_diagonal)
	_check(bool(repeated.get("valid", false)) and String(repeated.get("best_solution", {}).get("stable_geometry_key", "")) == String(supported_solution.get("stable_geometry_key", "")), "R2 selected support triangulation is deterministic across identical inputs")
	var outside_support: Dictionary = support.duplicate(true)
	outside_support["support_id"] = "outside-support"
	outside_support["world_position"] = Vector3(2.0, 2.0, 0.0)
	outside_support["binary32_position_identity"] = var_to_bytes(outside_support.world_position).hex_encode()
	var outside_supports: Array[Dictionary] = [outside_support]
	var outside: Dictionary = realizer.call("solve_r2_fixture_for_test", boundary, outside_supports, 1, required_diagonal)
	_check(not bool(outside.get("valid", false)) and bool(outside.get("search_complete", false)) and bool(outside.get("search_exhaustive", false)), "R2 completes a finite no-solution proof when the only frozen support lies outside the cavity")
	var malformed_support: Dictionary = support.duplicate(true)
	malformed_support["support_id"] = "nonfinite-support"
	malformed_support["world_position"] = Vector3(NAN, 0.2, 0.0)
	var malformed_supports: Array[Dictionary] = [malformed_support]
	var malformed: Dictionary = realizer.call("solve_r2_fixture_for_test", boundary, malformed_supports, 1, required_diagonal)
	_check(not bool(malformed.get("valid", false)) and not bool(malformed.get("search_complete", true)) and String(malformed.get("reason", "")) == "r2_support_identity_or_position_invalid", "R2 rejects malformed nonfinite support input before search")
	var boundary_duplicate_support: Dictionary = support.duplicate(true)
	boundary_duplicate_support["support_id"] = "boundary-root-duplicate"
	boundary_duplicate_support["world_position"] = points.a
	var boundary_duplicate_rows: Array[Dictionary] = [boundary_duplicate_support]
	var duplicate_boundary: Dictionary = realizer.call("solve_r2_fixture_for_test", boundary, boundary_duplicate_rows, 1, required_diagonal)
	_check(not bool(duplicate_boundary.get("valid", false)) and String(duplicate_boundary.get("reason", "")) == "r2_support_position_duplicates_frozen_boundary_root", "R2 rejects a support whose coordinates duplicate a frozen boundary root")
	var arc_points: Dictionary = {"a": Vector3(0.0, 0.0, 0.0), "b": Vector3(1.0, 0.0, 0.0), "c": Vector3(1.0, 1.0, 0.0), "d": Vector3(0.0, 1.0, 0.0), "q": Vector3(0.75, 0.5, 0.0), "outside": Vector3(2.0, 2.0, 0.0)}
	var arc_cycle: Array[String] = ["a", "b", "c", "d"]
	var arc_polygon: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var arc_projection: Dictionary = {"a": Vector2(0.0, 0.0), "b": Vector2(1.0, 0.0), "c": Vector2(1.0, 1.0), "d": Vector2(0.0, 1.0), "q": Vector2(0.75, 0.5), "outside": Vector2(2.0, 2.0)}
	var arc_local_positions: Dictionary = {"a": arc_points.a, "b": arc_points.b, "c": arc_points.c, "d": arc_points.d}
	var local_arc: Dictionary = {"arc_id": "internal-a-q", "root_ids": ["a", "q"], "expected_incidence": 2}
	var localized_arc: Dictionary = realizer.call("_r2_localize_topology_arcs", [local_arc], {"a": true}, arc_cycle, arc_points, arc_local_positions, arc_projection, arc_polygon, Vector3.ZERO, Vector3.RIGHT, Vector3.UP)
	_check(bool(localized_arc.get("valid", false)) and localized_arc.get("topology_root_ids", {}).has("q") and localized_arc.get("arc_map", []).size() == 1, "R2 localizes authoritative topology arcs and retains their interior topology roots")
	var split_owner_triangles: Array[Dictionary] = []
	for boundary_triangle in boundary:
		split_owner_triangles.append(boundary_triangle.duplicate(true))
	split_owner_triangles[1]["polygon_id"] = "frozen-owner-right"
	split_owner_triangles[1]["source_polygon_ids"] = ["frozen-owner-right"]
	var owner_arcs: Dictionary = realizer.call("_r2_residual_owner_boundary_arcs", split_owner_triangles)
	_check(bool(owner_arcs.get("valid", false)) and owner_arcs.get("arc_map", []).size() == 1 and owner_arcs.arc_map[0].get("root_ids", []) == ["a", "c"], "R2 derives a constrained arc where adjacent residual faces have different frozen owners")
	var nonmanifold_owner_points: Dictionary = points.duplicate(true)
	nonmanifold_owner_points["e"] = Vector3(0.5, 0.75, 0.0)
	var nonmanifold_owner_rows: Array[Dictionary] = []
	for owner_triangle in split_owner_triangles:
		nonmanifold_owner_rows.append(owner_triangle.duplicate(true))
	nonmanifold_owner_rows.append(_triangle("owner-extra", ["a", "c", "e"], nonmanifold_owner_points, false))
	var nonmanifold_owner: Dictionary = realizer.call("_r2_residual_owner_boundary_arcs", nonmanifold_owner_rows)
	_check(not bool(nonmanifold_owner.get("valid", true)) and String(nonmanifold_owner.get("reason", "")) == "r2_source_owner_edge_nonmanifold", "R2 refuses an exhaustive search over nonmanifold frozen owner-edge incidence")
	var conflicting_arcs: Dictionary = realizer.call("_r2_merge_arc_constraints", [{"arc_id": "one", "root_ids": ["a", "c"], "expected_incidence": 1}], [{"arc_id": "two", "root_ids": ["c", "a"], "expected_incidence": 2}])
	_check(not bool(conflicting_arcs.get("valid", true)) and String(conflicting_arcs.get("reason", "")) == "r2_arc_constraint_expected_incidence_conflict", "R2 fails closed when canonical and owner-derived arc incidence requirements conflict")
	var arc_cross_context: Dictionary = {"projected_positions": arc_projection, "residual_fixture": {"arc_map": [{"arc_id": "d-q", "root_ids": ["d", "q"], "expected_incidence": 2}]}}
	var crossing_triangle_ids: Array[String] = ["a", "b", "c"]
	var crossing_arc: Dictionary = realizer.call("_r2_triangle_respects_required_arcs", crossing_triangle_ids, arc_cross_context)
	_check(not bool(crossing_arc.get("valid", true)) and String(crossing_arc.get("reason", "")) in ["candidate_edge_crosses_required_topology_arc", "required_arc_endpoint_inside_candidate_triangle"], "R2 rejects candidate geometry that crosses or covers a frozen internal topology arc")
	var exact_arc_context: Dictionary = {"projected_positions": arc_projection, "residual_fixture": {"arc_map": [required_diagonal[0]]}}
	var exact_arc_triangle_ids: Array[String] = ["a", "b", "c"]
	_check(bool(realizer.call("_r2_triangle_respects_required_arcs", exact_arc_triangle_ids, exact_arc_context).get("valid", false)), "R2 permits a candidate triangle to use the exact frozen topology arc as an edge")
	var crossing_boundary_arc: Dictionary = realizer.call("_r2_localize_topology_arcs", [{"arc_id": "crossing-boundary", "root_ids": ["a", "outside"], "expected_incidence": 2}], {"a": true}, arc_cycle, arc_points, arc_local_positions, arc_projection, arc_polygon, Vector3.ZERO, Vector3.RIGHT, Vector3.UP)
	_check(not bool(crossing_boundary_arc.get("valid", true)) and String(crossing_boundary_arc.get("reason", "")) == "r2_topology_arc_crosses_cavity_boundary", "R2 refuses an exhaustive local search when an authoritative arc crosses the cavity boundary")
	var l_points: Dictionary = {"la": Vector3(0.0, 0.0, 0.0), "lb": Vector3(2.0, 0.0, 0.0), "lc": Vector3(2.0, 1.0, 0.0), "ld": Vector3(1.0, 1.0, 0.0), "le": Vector3(1.0, 2.0, 0.0), "lf": Vector3(0.0, 2.0, 0.0)}
	var l_boundary: Array[Dictionary] = [_triangle("l0", ["la", "lb", "ld"], l_points, false), _triangle("l1", ["lb", "lc", "ld"], l_points, false), _triangle("l2", ["la", "ld", "lf"], l_points, false), _triangle("l3", ["ld", "le", "lf"], l_points, false)]
	for l_triangle in l_boundary:
		l_triangle["polygon_id"] = "frozen-L-owner"
		l_triangle["source_polygon_ids"] = ["frozen-L-owner"]
	realizer.set("_root_positions", l_points)
	var l_boundary_state: Dictionary = realizer.call("_boundary_state", l_boundary)
	var l_ids: Array = ["l0", "l1", "l2", "l3"]
	var l_context_result: Dictionary = realizer.call("_r2_make_search_context", l_boundary, l_ids, l_boundary, no_supports, l_boundary_state, l_boundary, {"arc_map": [], "applied_flips": []}, 0)
	var concave_triangle_ids: Array[String] = ["lb", "le", "la"]
	var concave_crossing: Dictionary = realizer.call("_r2_triangle_inside_domain", concave_triangle_ids, l_context_result.get("context", {})) if bool(l_context_result.get("valid", false)) else {"valid": true, "reason": "context_not_tested"}
	_check(bool(l_boundary_state.get("valid", false)) and bool(l_context_result.get("valid", false)) and not bool(concave_crossing.get("valid", true)), "R2 rejects a candidate triangle whose edge exits a concave frozen boundary")

	var cap_probe: RefCounted = Realizer.new()
	cap_probe.set("_cxr_active_phase", "r2")
	cap_probe.set("_cxr_search_started_usec", Time.get_ticks_usec())
	cap_probe.set("_cxr_search_nodes_total", Realizer.CXR_R2_MAX_SEARCH_STATES_TOTAL)
	_check(String(cap_probe.call("_cxr_global_limit_reason")) == "MAX_SEARCH_STATES_TOTAL", "R2 total state cap produces a finite-limit stop")
	var intersection_points: Dictionary = {"o": Vector3.ZERO, "ax": Vector3(2.0, 0.0, 0.0), "ay": Vector3(0.0, 2.0, 0.0), "bx": Vector3(2.0, 2.0, 0.0), "by": Vector3(-1.0, 1.0, 0.0), "adjacent": Vector3(-1.0, 0.0, 0.0), "overlap": Vector3(1.0, 0.5, 0.0)}
	var triangle_a: Dictionary = _triangle("intersection-a", ["o", "ax", "ay"], intersection_points, false)
	var shared_vertex_cross: Dictionary = _triangle("intersection-shared-vertex", ["o", "bx", "by"], intersection_points, false)
	var valid_shared_edge: Dictionary = _triangle("intersection-valid-edge", ["o", "ay", "adjacent"], intersection_points, false)
	var overlap_shared_edge: Dictionary = _triangle("intersection-overlap-edge", ["o", "ay", "overlap"], intersection_points, false)
	_check(bool(realizer.call("_triangles_intersect", triangle_a.points, shared_vertex_cross.points)) and not bool(realizer.call("_r2_intersection_only_shared_simplex", triangle_a, shared_vertex_cross)), "R2 rejects triangles that cross beyond one shared vertex")
	_check(bool(realizer.call("_triangles_intersect", triangle_a.points, valid_shared_edge.points)) and bool(realizer.call("_r2_intersection_only_shared_simplex", triangle_a, valid_shared_edge)), "R2 permits legitimate adjacent triangles whose only intersection is their shared edge")
	_check(not bool(realizer.call("_r2_intersection_only_shared_simplex", triangle_a, overlap_shared_edge)), "R2 rejects coplanar triangles that overlap beyond a shared edge")
	_check(Realizer.CXR_R2_MAX_CANDIDATE_TRIANGLES_PER_CAVITY == 65536 and Realizer.CXR_R2_MAX_CANDIDATE_TRIANGLES_TOTAL == 131072 and Realizer.CXR_R2_MAX_SEARCH_STATES_PER_CAVITY == 32768 and Realizer.CXR_R2_MAX_SEARCH_STATES_TOTAL == 65536, "R2 resource caps match the pre-registered design bounds")


func _test_cxr_r3_remaining_boundary_and_separate_cavities() -> void:
	var realizer: RefCounted = Realizer.new()
	var points: Dictionary = {"a": Vector3.ZERO, "b": Vector3.RIGHT, "c": Vector3.UP, "d": Vector3(0.0, 0.0, 1.0)}
	var patch_triangle: Dictionary = _triangle("r3-patch", ["a", "c", "b"], points, false)
	var outside: Array[Dictionary] = [
		_triangle("r3-out-ab", ["a", "b", "d"], points, false),
		_triangle("r3-out-ac", ["a", "d", "c"], points, false),
		_triangle("r3-out-bc", ["b", "c", "d"], points, false)
	]
	var all: Array[Dictionary] = [patch_triangle]
	all.append_array(outside)
	var derived: Dictionary = realizer.call("derive_remaining_boundary_for_test", all, ["r3-patch"])
	var direct: Dictionary = realizer.call("_boundary_state", [patch_triangle])
	_check(bool(derived.get("valid", false)), "R3 derives a single closed cavity boundary from surviving C6 edge incidence")
	_check(String(derived.get("boundary_source", "")) == "remaining_C6_edge_incidence_after_cavity_patch_removal" and derived.get("signature", "") == direct.get("signature", ""), "R3 replacement boundary orientation and signature match the remaining mesh interface")
	_check(derived.get("incidence_diagnostics", []).size() == 3, "R3 records all three removed-to-remaining interface edge incidences")
	var reversed_patch: Array[Dictionary] = all.duplicate(true)
	var reversed_patch_face: Dictionary = reversed_patch[0]
	var reversed_patch_ids: Array = reversed_patch_face.root_ids.duplicate()
	var reversed_patch_points: Array = reversed_patch_face.points.duplicate()
	var patch_swap_id: Variant = reversed_patch_ids[1]
	reversed_patch_ids[1] = reversed_patch_ids[2]
	reversed_patch_ids[2] = patch_swap_id
	var patch_swap_point: Variant = reversed_patch_points[1]
	reversed_patch_points[1] = reversed_patch_points[2]
	reversed_patch_points[2] = patch_swap_point
	reversed_patch_face["root_ids"] = reversed_patch_ids
	reversed_patch_face["points"] = reversed_patch_points
	reversed_patch[0] = reversed_patch_face
	var removed_face_mismatch: Dictionary = realizer.call("derive_remaining_boundary_for_test", reversed_patch, ["r3-patch"])
	_check(bool(removed_face_mismatch.get("valid", false)) and removed_face_mismatch.get("signature", "") == direct.get("signature", ""), "R3 derives replacement orientation from surviving owners when the removed face itself is reversed")
	_check(removed_face_mismatch.get("removed_source_winding_mismatches", []).size() == 3, "R3 preserves diagnostics for each removed-face winding mismatch without using removed winding as boundary authority")
	var wrong_winding: Array[Dictionary] = all.duplicate(true)
	var outside_face: Dictionary = wrong_winding[1]
	var outside_ids: Array = outside_face.root_ids.duplicate()
	var outside_points: Array = outside_face.points.duplicate()
	var swap_id: Variant = outside_ids[0]
	outside_ids[0] = outside_ids[1]
	outside_ids[1] = swap_id
	var swap_point: Variant = outside_points[0]
	outside_points[0] = outside_points[1]
	outside_points[1] = swap_point
	outside_face["root_ids"] = outside_ids
	outside_face["points"] = outside_points
	wrong_winding[1] = outside_face
	var wrong: Dictionary = realizer.call("derive_remaining_boundary_for_test", wrong_winding, ["r3-patch"])
	_check(not bool(wrong.get("valid", true)) and String(wrong.get("reason", "")) == "boundary_cycle_degree_invalid", "R3 rejects inconsistent surviving-owner winding when it cannot form one oriented cavity boundary cycle")
	var open_source: Array[Dictionary] = [patch_triangle]
	var open: Dictionary = realizer.call("derive_remaining_boundary_for_test", open_source, ["r3-patch"])
	_check(not bool(open.get("valid", true)) and String(open.get("reason", "")) == "r3_patch_open_edge_has_no_remaining_owner", "R3 refuses to invent cavity boundary edges without a surviving C6 owner")
	var disconnected: Array[Dictionary] = [patch_triangle, _triangle("r3-island", ["x", "y", "z"], {"x": Vector3(3,0,0), "y": Vector3(4,0,0), "z": Vector3(3,1,0)}, false)]
	var connectivity: Dictionary = realizer.call("_r3_patch_connectivity", disconnected)
	_check(not bool(connectivity.get("valid", true)) and int(connectivity.get("component_count", -1)) == 2, "R3 replacement requires one edge-connected per-cavity patch")
	var all_tetra_ids: Array = ["r3-patch", "r3-out-ab", "r3-out-ac", "r3-out-bc"]
	var full_union_boundary: Dictionary = realizer.call("derive_remaining_boundary_for_test", all, all_tetra_ids)
	var tetra_adjacency: Dictionary = realizer.call("_adjacency", all)
	realizer.set("_cxr_active_phase", "r3")
	realizer.set("_cxr_search_started_usec", Time.get_ticks_usec())
	realizer.set("_cxr_cavity_started_usec", Time.get_ticks_usec())
	realizer.set("_cxr_search_nodes_total", 0)
	realizer.set("_cxr_search_nodes_cavity", 0)
	realizer.set("_cxr_patch_selection_nodes_total", 0)
	var minimal_subset: Dictionary = realizer.call("_r3_select_boundary_patch", ["r3-patch"], all_tetra_ids, all, tetra_adjacency, 1)
	_check(not bool(full_union_boundary.get("valid", true)) and bool(minimal_subset.get("valid", false)), "R3 finds a boundary-valid connected subset even when the full radius union is invalid")
	_check(minimal_subset.get("patch_triangle_ids", []) == ["r3-patch"] and int(minimal_subset.get("search_nodes", 0)) <= Realizer.CXR_R2_MAX_SEARCH_STATES_PER_CAVITY, "R3 selects the minimum-cardinality subset deterministically within the bounded neighborhood")
	_check(int(realizer.get("_cxr_patch_selection_nodes_total")) == int(minimal_subset.get("search_nodes", -1)) and int(realizer.get("_cxr_search_nodes_total")) == int(minimal_subset.get("search_nodes", -1)), "R3 charges subset states to the existing per-cavity and total counters")
	var expanded_selector: RefCounted = Realizer.new()
	expanded_selector.set("_cxr_active_phase", "r3")
	expanded_selector.set("_cxr_search_started_usec", Time.get_ticks_usec())
	expanded_selector.set("_cxr_cavity_started_usec", Time.get_ticks_usec())
	expanded_selector.set("_cxr_search_nodes_total", 0)
	expanded_selector.set("_cxr_search_nodes_cavity", 0)
	expanded_selector.set("_cxr_patch_selection_nodes_total", 0)
	var expanded_subset: Dictionary = expanded_selector.call("_r3_select_boundary_patch", ["r3-patch", "r3-out-ab"], all_tetra_ids, all, tetra_adjacency, 1)
	var expected_expanded_ids: Array = ["r3-out-ab", "r3-patch"]
	_check(bool(expanded_subset.get("valid", false)) and expanded_subset.get("patch_triangle_ids", []) == expected_expanded_ids, "R3 expands multi-triangle seeded patches through Dictionary adjacency rows")
	_check(int(expanded_subset.get("search_nodes", 0)) > 1 and int(expanded_subset.get("candidate_subsets_examined", 0)) == 1, "R3 records connected-subset expansion before field-support generation")
	var reversed_adjacency: Dictionary = {}
	var reversed_triangle_ids: Array = all_tetra_ids.duplicate()
	reversed_triangle_ids.reverse()
	for triangle_id_value in reversed_triangle_ids:
		var original_row: Dictionary = tetra_adjacency.get(String(triangle_id_value), {}).duplicate()
		var reversed_neighbor_ids: Array = original_row.keys()
		reversed_neighbor_ids.reverse()
		var reversed_neighbor_row: Dictionary = {}
		for neighbor_id_value in reversed_neighbor_ids:
			reversed_neighbor_row[String(neighbor_id_value)] = true
		reversed_adjacency[String(triangle_id_value)] = reversed_neighbor_row
	var reordered_selector: RefCounted = Realizer.new()
	reordered_selector.set("_cxr_active_phase", "r3")
	reordered_selector.set("_cxr_search_started_usec", Time.get_ticks_usec())
	reordered_selector.set("_cxr_cavity_started_usec", Time.get_ticks_usec())
	reordered_selector.set("_cxr_search_nodes_total", 0)
	reordered_selector.set("_cxr_search_nodes_cavity", 0)
	reordered_selector.set("_cxr_patch_selection_nodes_total", 0)
	var reordered_subset: Dictionary = reordered_selector.call("_r3_select_boundary_patch", ["r3-out-ab", "r3-patch"], all_tetra_ids, all, reversed_adjacency, 1)
	_check(reordered_subset.get("patch_triangle_ids", []) == expanded_subset.get("patch_triangle_ids", []) and int(reordered_subset.get("search_nodes", -1)) == int(expanded_subset.get("search_nodes", -2)), "R3 subset selection is stable under reordered seed and adjacency insertion")
	var malformed_adjacency: Dictionary = tetra_adjacency.duplicate(true)
	malformed_adjacency["r3-out-ab"] = ["not-a-neighbor-map"]
	var malformed_selector: RefCounted = Realizer.new()
	malformed_selector.set("_cxr_active_phase", "r3")
	malformed_selector.set("_cxr_search_started_usec", Time.get_ticks_usec())
	malformed_selector.set("_cxr_cavity_started_usec", Time.get_ticks_usec())
	malformed_selector.set("_cxr_search_nodes_total", 0)
	malformed_selector.set("_cxr_search_nodes_cavity", 0)
	malformed_selector.set("_cxr_patch_selection_nodes_total", 0)
	var malformed_subset: Dictionary = malformed_selector.call("_r3_select_boundary_patch", ["r3-out-ab", "r3-patch"], all_tetra_ids, all, malformed_adjacency, 1)
	_check(not bool(malformed_subset.get("valid", true)) and String(malformed_subset.get("reason", "")) == "r3_patch_adjacency_row_invalid", "R3 rejects malformed adjacency rows deterministically instead of raising a script error")
	var capped_selector: RefCounted = Realizer.new()
	capped_selector.set("_cxr_active_phase", "r3")
	capped_selector.set("_cxr_search_started_usec", Time.get_ticks_usec())
	capped_selector.set("_cxr_cavity_started_usec", Time.get_ticks_usec())
	capped_selector.set("_cxr_search_nodes_cavity", Realizer.CXR_R2_MAX_SEARCH_STATES_PER_CAVITY)
	var capped_subset: Dictionary = capped_selector.call("_r3_select_boundary_patch", ["r3-patch"], all_tetra_ids, all, tetra_adjacency, 1)
	_check(not bool(capped_subset.get("complete", true)) and String(capped_subset.get("limit_reason", "")) == "R2_MAX_SEARCH_STATES", "R3 fails closed when the shared search-state budget is exhausted")
	var adjacency: Dictionary = {"residual-a": {"residual-b": true}, "residual-b": {"residual-a": true}, "residual-c": {}}
	var residual_rows: Array = [{"triangle_id": "residual-c"}, {"triangle_id": "residual-b"}, {"triangle_id": "residual-a"}]
	var grouped: Array = realizer.call("_overlapping_defect_groups", residual_rows, adjacency)
	var canonical_groups: Array = realizer.call("_canonicalize_defect_groups", grouped)
	_check(canonical_groups.size() == 2 and canonical_groups[0] == ["residual-a", "residual-b"] and canonical_groups[1] == ["residual-c"], "R3 preserves two original overlap groups instead of merging all residual faces")

	var reordered_rows: Array = [residual_rows[2], residual_rows[0], residual_rows[1]]
	var reordered_groups: Array = realizer.call("_canonicalize_defect_groups", realizer.call("_overlapping_defect_groups", reordered_rows, adjacency))
	_check(JSON.stringify(canonical_groups) == JSON.stringify(reordered_groups), "R3 per-cavity group ordering is stable under residual discovery order")
	realizer.set("_cxr_active_phase", "r3")
	var r3_limits: Dictionary = realizer.call("_cxr_limits")
	_check(int(r3_limits.get("max_cavities", -1)) == 3 and String(r3_limits.get("cavity_policy", "")) == "original_overlapping_defect_groups_searched_separately", "R3 permits the preregistered cavity cap and preserves original groups separately")
	_check(int(r3_limits.get("max_cavity_level", -1)) == 4 and String(r3_limits.get("patch_policy", "")) == "minimum_cardinality_connected_subsets_within_dual_graph_radius_layers_0_through_4_per_cavity", "R3 pins deterministic minimum-cardinality subset selection within the evidence-directed four-ring bound")
	_check(int(r3_limits.get("patch_selection_state_cap_per_cavity", -1)) == 32768 and int(r3_limits.get("patch_selection_state_cap_total", -1)) == 65536, "R3 patch selection shares existing per-cavity and total search-state limits")
	_check(String(r3_limits.get("boundary_source", "")) == "remaining_C6_edge_incidence_after_cavity_patch_removal" and String(r3_limits.get("support_source", "")) == "original_frozen_residual_faces_only", "R3 limit contract pins per-cavity remaining-mesh boundary and original residual-only support provenance")
	_check(int(r3_limits.get("max_candidate_triangles_per_cavity", -1)) == 65536 and int(r3_limits.get("max_search_states_total", -1)) == 65536 and float(r3_limits.get("cross_squared_cutoff", 0.0)) == 1.0e-12, "R3 inherits bounded R2 search caps and the unchanged strict geometry cutoff")
	_check(int(r3_limits.get("max_candidate_attempts_per_cavity", -1)) == 8192 and int(r3_limits.get("max_support_candidates_per_cavity", -1)) == 256 and int(r3_limits.get("max_selected_supports", -1)) == 4 and int(r3_limits.get("max_patch_triangles", -1)) == 64, "R3 retains preregistered per-cavity candidate, support, selection and patch-size limits")
	_check(int(r3_limits.get("max_candidate_triangles_total", -1)) == 131072 and int(r3_limits.get("max_search_states_per_cavity", -1)) == 32768 and int(r3_limits.get("max_search_usec_per_cavity", -1)) == 10000000 and int(r3_limits.get("max_search_usec_total", -1)) == 20000000, "R3 retains preregistered aggregate geometry, search-state and wall-time caps")
	_check(int(r3_limits.get("max_retained_solutions_per_cavity", -1)) == 32 and int(r3_limits.get("max_realize_usec", -1)) == 30000000 and float(r3_limits.get("max_support_distance", -1.0)) == 0.5, "R3 retains preregistered retained-solution, realization-time and support-distance bounds")
	var boundary_failure_reason: String = realizer.call("_r3_invalid_level_reason", {"valid": true, "reason": ""}, {"valid": false, "reason": "cx_patch_nonmanifold_edge"})
	_check(boundary_failure_reason == "cx_patch_nonmanifold_edge", "R3 preserves the boundary failure when patch connectivity itself is valid")
	var no_domain_terminal: String = realizer.call("_cxr_failure_terminal_reason", "r3", [{"search_complete": false, "search_exhaustive": false, "terminal_reason": "r3_no_valid_cavity_boundary_level"}], 1, "")
	var exhausted_terminal: String = realizer.call("_cxr_failure_terminal_reason", "r3", [{"search_complete": true, "search_exhaustive": true, "terminal_reason": "r3_all_valid_cavity_levels_exhausted_no_solution"}], 1, "")
	var mixed_terminal: String = realizer.call("_cxr_failure_terminal_reason", "r3", [{"search_complete": false, "search_exhaustive": false, "terminal_reason": "r3_no_valid_cavity_boundary_level"}, {"search_complete": true, "search_exhaustive": true, "terminal_reason": "r3_all_valid_cavity_levels_exhausted_no_solution"}], 2, "")
	var solved_then_unsolved: String = realizer.call("_cxr_failure_terminal_reason", "r3", [{"valid": true, "search_complete": true, "search_exhaustive": true, "terminal_reason": "minimum_valid_cavity_solution"}, {"valid": false, "search_complete": true, "search_exhaustive": true, "terminal_reason": "r3_all_valid_cavity_levels_exhausted_no_solution"}], 2, "")
	var overlap_terminal: String = realizer.call("_cxr_failure_terminal_reason", "r3", [{"valid": true, "search_complete": true, "search_exhaustive": true, "terminal_reason": "minimum_valid_cavity_solution"}], 1, "", true)
	_check(no_domain_terminal == "r3_cavity_boundary_domains_invalid:1/1", "R3 reports invalid per-cavity domain construction instead of false finite exhaustion")
	_check(exhausted_terminal == "r3_all_cavity_domains_finitely_exhausted_no_solution", "R3 reports finite-domain exhaustion only after every valid cavity domain exhausts")
	_check(mixed_terminal == "r3_cavity_boundary_domains_invalid:1/2", "R3 aggregation preserves a partial disposition when any cavity lacks a valid boundary domain")
	_check(solved_then_unsolved == "r3_unsolved_cavity_domain_exhausted_after_other_cavity_solution", "R3 reports an unsolved cavity separately when another cavity already has a solution")
	_check(overlap_terminal == "r3_selected_patch_overlap_requires_alternative_solution_search", "R3 does not claim exhaustion when selected per-cavity patches overlap")
	var one_triangle: Array[Dictionary] = [patch_triangle]
	realizer.set("_cxr_search_started_usec", Time.get_ticks_usec())
	var not_started: Dictionary = realizer.call("_search_cxr_cavity_r3", ["r3-patch"], one_triangle, {}, {"residuals": [{"triangle_id": "r3-patch"}]}, PackedFloat32Array(), {})
	var not_started_report: Dictionary = not_started.get("cavity_report", {})
	_check(not bool(not_started.get("search_started", true)) and not bool(not_started_report.get("search_started", true)), "R3 invalid-boundary-only processing is not mislabeled as a started support search")
	_check(String(not_started_report.get("candidate_attempt_count", "")) == "NOT_RUN" and String(not_started_report.get("candidate_triangle_count", "")) == "NOT_RUN", "R3 reports unmeasured support and triangle counts as NOT_RUN rather than zero")
	var no_domain_reasons: Array[String] = ["r3_no_valid_cavity_boundary_level"]
	var no_domain_reason: String = realizer.call("_cxr_failure_reason", "r3", false, no_domain_reasons)
	_check(no_domain_reason == "cxr_r3_cavity_boundary_domain_invalid", "R3 distinguishes invalid per-cavity boundary domains from generic partial search")
	var partial_target: Dictionary = {"reason": "cx_bounded_patch_search_failed", "detail": {"search": {"complete": false, "search_exhaustive": false, "reason": no_domain_reason}}}
	_check(Campaign._target_search_partial(partial_target, {"cxr_local_search_complete": false}), "R3 invalid-domain result remains classified as PARTIAL by the campaign gate")

func _test_cxr_r3_capped_pool_triangulation_and_valid_witness() -> void:
	var realizer: RefCounted = Realizer.new()
	var continue_with_pool: bool = not bool(realizer.call("_r3_generation_requires_partial_stop", false, true, 1))
	_check(continue_with_pool, "R3 continues to constrained triangulation when generation is capped but a valid support pool is retained")
	_check(bool(realizer.call("_r3_generation_requires_partial_stop", false, true, 0)), "R3 remains partial when a generation cap leaves no support candidate to triangulate")
	_check(bool(realizer.call("_r3_generation_requires_partial_stop", true, true, 1)), "R3 fails closed on invalid source evidence even when earlier supports were retained")
	var points: Dictionary = {"a": Vector3(0.0, 0.0, 0.0), "b": Vector3(1.0, 0.0, 0.0), "c": Vector3(1.0, 1.0, 0.0), "d": Vector3(0.0, 1.0, 0.0)}
	var boundary: Array[Dictionary] = [_triangle("capped-owner-left", ["a", "b", "c"], points, false), _triangle("capped-owner-right", ["a", "c", "d"], points, false)]
	for triangle in boundary:
		triangle["polygon_id"] = "capped-owner"
		triangle["source_polygon_ids"] = ["capped-owner"]
	var support_position: Vector3 = Vector3(0.25, 0.2, 0.0)
	var support: Dictionary = {"support_id": "retained-capped-support", "accepted": true, "supported": true, "frozen_field_interpolated_residual": 0.0, "world_position": support_position, "source_polygon_ids": ["capped-owner"], "binary32_position_identity": var_to_bytes(support_position).hex_encode()}
	var support_rows: Array[Dictionary] = [support]
	var triangulated: Dictionary = realizer.call("solve_r2_fixture_for_test", boundary, support_rows, 1, [])
	_check(continue_with_pool and bool(triangulated.get("valid", false)) and int(triangulated.get("candidate_triangle_count", 0)) > 0, "R3 retained-pool regression exercises actual R2 candidate triangle generation and constrained triangulation")
	var disposition: Dictionary = realizer.call("_r3_search_disposition", {"valid": true, "search_complete": true, "search_exhaustive": true}, false)
	_check(bool(disposition.get("valid_geometry", false)) and not bool(disposition.get("complete", true)) and not bool(disposition.get("exhaustive", true)), "R3 distinguishes a concrete valid geometry witness from incomplete support enumeration")
	var witness_geometry: Dictionary = {"geometry_complete": true, "topology_signature_match": true, "cxr_local_search_complete": false}
	_check(not Campaign._target_search_partial({"valid": true, "reason": ""}, witness_geometry), "campaign accepts a topology-validated complete geometry witness despite non-exhaustive search")
	_check(Campaign._target_search_partial({"valid": false, "reason": "cx_bounded_patch_search_failed"}, witness_geometry), "campaign keeps incomplete search partial when no valid geometry witness exists")
	_check(Campaign._target_search_partial({"valid": true, "reason": "cxr_realize_time_limit"}, witness_geometry), "campaign does not let a valid-witness disposition mask an explicit realization timeout")
	_check(Campaign._target_search_partial({"valid": true, "reason": ""}, {"geometry_complete": true, "topology_signature_match": false, "cxr_local_search_complete": false}), "campaign does not let a valid-witness disposition mask a topology mismatch")

func _test_r3_expanded_patch_owner_and_replacement_sets() -> void:
	var realizer: RefCounted = Realizer.new()
	var points: Dictionary = {
		"a": Vector3(0.0, 0.0, 0.0),
		"b": Vector3(1.0, 0.0, 0.0),
		"c": Vector3(1.0, 1.0, 0.0),
		"d": Vector3(0.0, 1.0, 0.0),
		"outside": Vector3(-1.0, 1.0, 0.0)
	}
	var seed: Dictionary = _triangle("r3-owned-residual-seed", ["a", "b", "c"], points, true)
	seed["polygon_id"] = "frozen-seed-owner"
	seed["source_polygon_ids"] = ["frozen-seed-owner"]
	var adjacent_c6: Dictionary = _triangle("C6-ownerless-adjacent-face", ["a", "c", "d"], points, false)
	adjacent_c6["polygon_id"] = ""
	adjacent_c6["source_polygon_ids"] = []
	var patch: Array[Dictionary] = [seed, adjacent_c6]
	var patch_ids: Array[String] = ["C6-ownerless-adjacent-face", "r3-owned-residual-seed"]
	var owned_residual_rows: Array[Dictionary] = [seed]
	var no_support_rows: Array[Dictionary] = []
	realizer.set("_root_positions", points)
	var boundary: Dictionary = realizer.call("_boundary_state", patch)
	var fixture: Dictionary = {"arc_map": [], "applied_flips": []}
	var incorrectly_scoped: Dictionary = realizer.call("_r2_make_search_context", patch, patch_ids, patch, no_support_rows, boundary, patch, fixture, 2)
	_check(bool(boundary.get("valid", false)) and not bool(incorrectly_scoped.get("valid", true)) and String(incorrectly_scoped.get("reason", "")) == "r2_owner_boundary_polygon_id_missing", "R3 regression reproduces expanded ownerless C6 face rejecting the R2 owner-provenance context")
	var context_result: Dictionary = realizer.call("_r3_make_expanded_patch_context", patch, patch_ids, owned_residual_rows, no_support_rows, boundary, patch, fixture, 2)
	var context: Dictionary = context_result.get("context", {})
	var preflight_result: Dictionary = realizer.call("_r3_make_expanded_patch_context", patch, patch_ids, owned_residual_rows, no_support_rows, boundary, patch, fixture, 2, true)
	_check(bool(preflight_result.get("valid", false)) and bool(preflight_result.get("preflight_only", false)) and not preflight_result.has("context"), "R3 subset preflight validates the same accepted domain without retaining full search context")
	var removed_ids: Dictionary = context.get("residual_id_set", {})
	var owners: Dictionary = context.get("owner_polygon_ids", {})
	_check(bool(context_result.get("valid", false)), "R3 context accepts frozen seed ownership without fabricating an owner for adjacent C6 faces")
	_check(removed_ids.size() == 2 and removed_ids.has("r3-owned-residual-seed") and removed_ids.has("C6-ownerless-adjacent-face"), "R3 replacement set still removes every face in the selected connected patch")
	_check(owners.size() == 1 and owners.has("frozen-seed-owner") and context.get("level_patch", []).size() == 2, "R3 owner provenance stays limited to original residual seeds while the full patch remains the replacement domain")
	var outside_seed: Dictionary = seed.duplicate(true)
	outside_seed["triangle_id"] = "not-in-selected-patch"
	var invalid_seed_rows: Array[Dictionary] = [outside_seed]
	var invalid_seed: Dictionary = realizer.call("_r2_make_search_context", patch, patch_ids, invalid_seed_rows, no_support_rows, boundary, patch, fixture, 2)
	_check(not bool(invalid_seed.get("valid", true)) and String(invalid_seed.get("reason", "")) == "r2_residual_owner_outside_selected_patch", "R3 context rejects owner provenance that is not part of the selected replacement patch")
	var crossing_fixture: Dictionary = fixture.duplicate(true)
	crossing_fixture["arc_map"] = [{"arc_id": "R3_TEST_CROSSING_ARC", "root_ids": ["b", "outside"], "expected_incidence": 2, "constraint_source": "synthetic_topology"}]
	var crossing_preflight: Dictionary = realizer.call("_r3_make_expanded_patch_context", patch, patch_ids, owned_residual_rows, no_support_rows, boundary, patch, crossing_fixture, 2, true)
	var crossing_full: Dictionary = realizer.call("_r3_make_expanded_patch_context", patch, patch_ids, owned_residual_rows, no_support_rows, boundary, patch, crossing_fixture, 2)
	_check(not bool(crossing_preflight.get("valid", true)) and String(crossing_preflight.get("reason", "")) == "r2_topology_arc_crosses_cavity_boundary", "R3 cheap preflight still rejects a mandatory topology arc crossing the candidate cavity")
	_check(not bool(crossing_full.get("valid", true)) and String(crossing_full.get("reason", "")) == String(crossing_preflight.get("reason", "")), "R3 cheap preflight and full context agree on crossing-arc rejection")
	_test_r3_context_domain_preflight()

func _test_r3_context_domain_preflight() -> void:
	var realizer: RefCounted = Realizer.new()
	var root_positions: Dictionary = {
		"a": Vector3(0.0, 0.0, 0.0),
		"b": Vector3(1.0, 0.0, 0.0),
		"c": Vector3(0.0, 1.0, 0.0),
		"outside": Vector3(-1.0, 1.0, 0.0)
	}
	var projected_positions: Dictionary = {"a": Vector2.ZERO, "b": Vector2.RIGHT, "c": Vector2(0.0, 1.0)}
	var polygon: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2(0.0, 1.0)]
	var boundary_cycle: Array[String] = ["a", "b", "c"]
	var crossing_arc: Array[Dictionary] = [{"arc_id": "b\u001foutside", "root_ids": ["b", "outside"]}]
	var crossing: Dictionary = realizer.call("_r2_localize_topology_arcs", crossing_arc, {}, boundary_cycle, root_positions, root_positions.duplicate(), projected_positions, polygon, Vector3.ZERO, Vector3.RIGHT, Vector3(0.0, 1.0, 0.0))
	_check(not bool(crossing.get("valid", true)) and String(crossing.get("reason", "")) == "r2_topology_arc_crosses_cavity_boundary", "projection preflight still rejects a topology arc that crosses the candidate cavity domain")
	_check(bool(realizer.call("_r3_context_failure_is_patch_domain_limited", String(crossing.get("reason", "")))), "R3 may seek a larger bounded patch for a domain-crossing arc instead of discarding it")
	_check(bool(realizer.call("_r3_context_failure_is_patch_domain_limited", "r2_topology_arc_leaves_concave_cavity_domain")), "R3 classifies concave-domain incompatibility as a bounded patch-selection rejection")
	_check(not bool(realizer.call("_r3_context_failure_is_patch_domain_limited", "r2_owner_boundary_polygon_id_missing")), "R3 does not treat missing owner provenance as a geometric patch expansion opportunity")

func _sequence_probe_local_failure(cavity_ids: Array) -> Dictionary:
	_sequence_probe_calls.append(cavity_ids.duplicate())
	return {"valid": false, "search_started": true, "search_complete": true, "search_exhaustive": true, "terminal_reason": "synthetic_local_failure"}

func _sequence_probe_candidate(cavity_ids: Array) -> Dictionary:
	_sequence_probe_calls.append(cavity_ids.duplicate())
	var is_partial: bool = String(cavity_ids[0]) == "partial-cavity"
	return {"valid": true, "search_started": true, "search_complete": not is_partial, "search_exhaustive": not is_partial, "terminal_reason": "limit_candidate_search" if is_partial else "finite_domain_exhausted_with_candidate"}

func _triangle(id: String, root_ids: Array, points_by_id: Dictionary, rejected: bool) -> Dictionary:
	var points: Array[Vector3] = [points_by_id[root_ids[0]], points_by_id[root_ids[1]], points_by_id[root_ids[2]]]
	var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	return {"triangle_id":id, "polygon_id":id, "root_ids":root_ids.duplicate(), "points":points, "normal":cross.normalized() if cross.length_squared() > 0.0 else Vector3.ZERO, "cross_squared":cross.length_squared(), "rejected":rejected, "construction":"synthetic"}

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)
