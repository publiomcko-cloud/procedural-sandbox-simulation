extends "res://tests/prototypes/p3_1_r7_2_zero_edit_gate.gd"

## Deterministic one-cell reproduction of the R7.2 edited-CARVE repair failure.
## Runs only the local experimental repair; no collider or scenario gate is invoked.
const RepairR73 := preload("res://tests/prototypes/p3_1_r7_2_local_retriangulation.gd")
const MINIMAL_FOCUS_CELL_ID := 720
const EXPECTED_FOCUS_CELL := Vector3i(0, 7, 6)

var _r73_assertions := 0
var _r73_failures: Array[String] = []


func _run() -> void:
	var snapshot_result: Dictionary = _make_snapshot("cave_wall_carve")
	_check_r73(bool(snapshot_result.get("valid", false)), "frozen_carve_snapshot_reconstructed")
	if not bool(snapshot_result.get("valid", false)):
		_finish_r73({"reason": snapshot_result.get("reason", "snapshot_invalid")})
		return
	var snapshot: Dictionary = snapshot_result.snapshot
	var payload: Dictionary = _scenario_input_payload("cave_wall_carve", snapshot)
	var canonical_json := JSON.stringify(payload)
	var fixture := Fixture.new()
	_check_r73(fixture.configure(SEED, snapshot), "canonical_fixture_configures")
	if not fixture.configure_r71_polygonizer("production", "reject_only_exact_zero", "production"):
		_finish_r73({"reason": "inclusive_polygonizer_setup_failed"})
		return
	var build_started := Time.get_ticks_usec()
	var built: Dictionary = fixture.build_approach("A_conforming_propagation")
	var build_usec := Time.get_ticks_usec() - build_started
	_check_r73(bool(built.get("valid", false)), "frozen_canonical_mesh_builds")
	if not bool(built.get("valid", false)):
		_finish_r73({"reason": built.get("reason", "mesh_build_failed")})
		return
	var focus_cell: Vector3i = fixture._cell_from_id(MINIMAL_FOCUS_CELL_ID)
	_check_r73(focus_cell == EXPECTED_FOCUS_CELL, "cell_720_world_ownership_is_frozen")
	var repair := RepairR73.new()
	var local_mesh: Dictionary = repair.extract_local_mesh(fixture, built.cells, [MINIMAL_FOCUS_CELL_ID])
	var before: Dictionary = repair.metrics(fixture, local_mesh)
	_check_r73(int(before.get("nonzero_subthreshold_triangles", 0)) > 0,
		"minimal_focus_patch_reproduces_nonzero_subthreshold_geometry")
	var repair_started := Time.get_ticks_usec()
	var result: Dictionary = repair.run_strategy(fixture, local_mesh, "A_edge_collapse")
	var repair_usec := Time.get_ticks_usec() - repair_started
	var diagnostic: Dictionary = result.get("diagnostic", {})
	var after: Dictionary = diagnostic.get("after_metrics", {})
	_check_r73(bool(result.get("valid", false)), "boundary_preserving_A_repair_passes_minimal_patch")
	_check_r73(String(diagnostic.get("first_failed_invariant", "")) == "",
		"minimal_patch_has_no_first_failed_invariant")
	_check_r73(before.get("boundary_signature", []) == after.get("boundary_signature", []),
		"external_boundary_signature_is_unchanged")
	_check_r73(int(after.get("internal_open_edges", -1)) == 0, "minimal_patch_has_zero_internal_open_edges")
	_check_r73(int(after.get("degenerate_triangles", -1)) == 0,
		"minimal_patch_has_zero_degenerate_triangles_at_unchanged_threshold")
	_check_r73(int(after.get("nonmanifold_edges", -1)) == 0, "minimal_patch_has_zero_nonmanifold_edges")
	_check_r73(int(after.get("same_winding_edges", -1)) == 0, "minimal_patch_has_compatible_winding")
	_check_r73(int(after.get("t_junctions", -1)) == 0, "minimal_patch_has_zero_t_junctions")
	_check_r73(int(after.get("face_component_count", -1)) == int(before.get("face_component_count", -2)),
		"minimal_patch_preserves_face_component_count")
	_check_r73(float(after.get("threshold_cross_squared", -1.0)) == 1.0e-12,
		"frozen_degeneracy_threshold_is_unchanged")
	var accepted_boundary_collapse := false
	for record_value in diagnostic.get("accepted_edge_collapses", []):
		var record: Dictionary = record_value
		var attempt: Dictionary = record.get("attempt", {})
		if (bool(attempt.get("boundary_vertex_u", false)) or bool(attempt.get("boundary_vertex_v", false))) \
				and bool(attempt.get("boundary_signature_preserved", false)):
			accepted_boundary_collapse = true
	_check_r73(accepted_boundary_collapse,
		"boundary_adjacent_collapse_is_accepted_only_with_identical_external_signature")
	var input_hash := _sha256(canonical_json.to_utf8_buffer())
	var source_hashes := {
		"res://tests/prototypes/p3_1_r7_3_minimal_carve_repair.gd": _file_sha256("res://tests/prototypes/p3_1_r7_3_minimal_carve_repair.gd"),
		"res://tests/prototypes/p3_1_r7_2_zero_edit_gate.gd": _file_sha256("res://tests/prototypes/p3_1_r7_2_zero_edit_gate.gd"),
		"res://tests/prototypes/p3_1_r7_2_local_retriangulation.gd": _file_sha256("res://tests/prototypes/p3_1_r7_2_local_retriangulation.gd"),
		"res://tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd": _file_sha256("res://tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd"),
		"res://scripts/terrain/marching_tetrahedra.gd": _file_sha256("res://scripts/terrain/marching_tetrahedra.gd"),
		"res://scripts/terrain/sdf_world.gd": _file_sha256("res://scripts/terrain/sdf_world.gd"),
		"res://scripts/terrain/sdf_brush_edit_state.gd": _file_sha256("res://scripts/terrain/sdf_brush_edit_state.gd"),
		"res://scripts/experiments/lod01_transition_fixture.gd": _file_sha256("res://scripts/experiments/lod01_transition_fixture.gd")}
	var result_record := {"suite": "P3_1_R7_3_MINIMAL_CARVE_REPAIR", "scenario": "cave_wall_carve",
		"scenario_id": "P3.1.R7.CAVE_WALL_CARVE.v1", "seed": SEED,
		"generator_version": Field.GENERATOR_VERSION, "region": [REGION.x, REGION.y],
		"revision": snapshot.get("revision", -1), "operation_count": payload.ordered_commands.size(),
		"ordered_commands": payload.ordered_commands, "input_canonical_json": canonical_json,
		"input_sha256": input_hash, "source_sha256_by_path": source_hashes,
		"focus_cell_id": MINIMAL_FOCUS_CELL_ID, "focus_cell_coordinate": [focus_cell.x, focus_cell.y, focus_cell.z],
		"focus_cell_world_min": [8.0, 1.5, 6.0], "before": before,
		"strategy": result, "after": after, "assertions": _r73_assertions,
		"failures": _r73_failures, "timing_usec": {"canonical_build": build_usec, "local_repair": repair_usec},
		"scope": "one-cell focus plus face-neighbor local patch; no full edited scenario gate, collider, or performance campaign"}
	print("R73_MINIMAL_CARVE_RESULT " + JSON.stringify(result_record))
	_finish_r73(result_record)


func _check_r73(condition: bool, name: String) -> void:
	_r73_assertions += 1
	if not condition:
		_r73_failures.append(name)


func _file_sha256(path: String) -> String:
	return _sha256(FileAccess.get_file_as_bytes(path))


func _finish_r73(record: Dictionary) -> void:
	var passed := _r73_failures.is_empty()
	print("R73_MINIMAL_CARVE_STATUS " + JSON.stringify({"status": "PASS" if passed else "FAIL",
		"assertions": _r73_assertions, "failures": _r73_failures,
		"input_sha256": record.get("input_sha256", ""), "full_scenario_gate_executed": false}))
	quit(0 if passed else 1)
