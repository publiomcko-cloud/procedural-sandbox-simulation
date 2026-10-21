extends SceneTree

const Contract := preload("res://tests/p1_1b_benchmark_contract.gd")
const Fixture := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_manifest_identity_and_freeze_boundary()
	_test_canonical_replay_recipes()
	_test_support_and_rebuild_dependency_are_distinct()
	_test_atomic_and_settled_streaming_contract()
	_test_lod_case_registry()
	_test_tunnel_registry()
	_test_fixed_edits_and_reload()
	_test_review_correction_gates()
	if _failures == 0:
		print("P1B1_CONTRACT_TESTS_PASS: assertions=%d failures=0" % _assertions)
		quit(0)
	else:
		push_error("P1B1_CONTRACT_TESTS_FAIL: assertions=%d failures=%d" % [_assertions, _failures])
		quit(1)


func _test_manifest_identity_and_freeze_boundary() -> void:
	var verified: Dictionary = Contract.verify_manifest()
	_check(verified.get("ok", false), "manifest is canonical UTF-8 JSON and matches its independent SHA-256 sidecar")
	if not verified.get("ok", false):
		return
	var manifest: Dictionary = verified["manifest"]
	_check(String(verified["sha256"]) == Contract.MANIFEST_SHA256, "physical manifest SHA matches the source-pinned digest")
	_check(String(manifest["contract_main_sha"]) == "ea4422d90726d3f2fe6d5cef097126268f93685a", "manifest pins the verified B0 contract main")
	_check(manifest["scenarios"].size() == 44, "manifest contains the complete frozen B0 scenario registry")
	var ids: Dictionary = {}
	for scenario_value in manifest["scenarios"]:
		var scenario: Dictionary = scenario_value
		var id := String(scenario["id"])
		_check(not ids.has(id), "scenario IDs are unique: %s" % id)
		_check(id.ends_with(".v1"), "scenario ID carries an explicit version: %s" % id)
		ids[id] = true
		_check(String(scenario["status"]) == "FROZEN", "only owner-frozen inputs are executable: %s" % id)
	for excluded in manifest["excluded_not_frozen"]:
		_check(not ids.has(String(excluded)), "NOT_FROZEN scenario is absent from executable registry: %s" % excluded)
	_check(not Contract._canonical_value_supported({"fractional": 0.58}), "canonical manifest rejects floating-point JSON values")
	_check(Contract.canonical_json({"z": 1, "a": [true, "x"]}) == "{\"a\":[true,\"x\"],\"z\":1}", "canonical JSON sorts object keys and preserves array order")
	_check(not Contract._is_lower_hex_sha256("A".repeat(64)), "SHA-256 pin validation rejects uppercase hex")
	_check(manifest["excluded_not_frozen"].size() == 9, "all nine unresolved B0 scenarios remain excluded")


func _test_canonical_replay_recipes() -> void:
	var manifest: Dictionary = Contract.verify_manifest()["manifest"]
	var expected_counts := [0, 1, 32, 128, 255, 256]
	for count in expected_counts:
		var suffix := "%03d" % count
		var scenario := _scenario(manifest, "B0A.INTERIOR.N%s.v1" % suffix)
		var commands := Contract.build_commands(scenario, manifest)
		_check(commands.size() == count, "interior recipe expands exactly %d commands" % count)
		_check(Contract.command_list_sha256(commands).length() == 64, "interior command list has a SHA-256 identity at N=%d" % count)
		for index in range(commands.size()):
			_check(int(commands[index]["sequence"]) == index, "sequence is globally ordered at N=%d index=%d" % [count, index])
			_check(String(commands[index]["mode"]) == ("CARVE" if index % 2 == 0 else "FILL"), "modes alternate from CARVE at N=%d index=%d" % [count, index])
			_check(int(commands[index]["radius_mm"]) == 580, "canonical replay radius is exactly 0.58 at N=%d index=%d" % [count, index])
	for recipe_case in [
		["B0A.EDGE.POS_X.N032.v1", [15700, 3200, 6000], ["0,0", "1,0"]],
		["B0A.CORNER.POS_XZ.N032.v1", [15800, 3200, 11800], ["0,0", "1,0", "0,1", "1,1"]],
		["B0A.CORNER.NEG_XZ.N032.v1", [-200, 3200, -200], ["-1,-1", "-1,0", "0,-1", "0,0"]],
	]:
		var scenario := _scenario(manifest, recipe_case[0])
		var commands := Contract.build_commands(scenario, manifest)
		_check(commands[0]["center_mm"] == recipe_case[1], "%s first center matches frozen integer-mm recipe" % recipe_case[0])
		_check(Contract.expected_support_for_command(scenario, commands[0]) == _sorted_strings(recipe_case[2]), "%s first support matches frozen region set" % recipe_case[0])
	var distributed := Contract.build_commands(_scenario(manifest, "B0A.DISTRIBUTED.N256.v1"), manifest)
	var region_keys: Dictionary = {}
	for command in distributed:
		var expected := Contract.expected_support_for_command(_scenario(manifest, "B0A.DISTRIBUTED.N256.v1"), command)
		_check(expected.size() == 1, "distributed command has exactly one canonical support region")
		region_keys[expected[0]] = true
	_check(region_keys.size() == 16, "distributed canonical history covers all sixteen frozen signed region keys")


func _test_support_and_rebuild_dependency_are_distinct() -> void:
	var ledger: RefCounted = BrushState.new(Contract.SEED, Contract.GENERATOR_VERSION)
	_check(ledger.add_sphere(BrushState.Mode.CARVE, Vector3(15.2, 3.2, 6.0), 0.58), "dependency probe command is accepted")
	var operation: Dictionary = ledger.get_last_operation_snapshot()
	var support := Contract.operation_region_keys(operation, "support_regions")
	var dependencies := Contract.operation_region_keys(operation, "dependency_regions")
	var rebuild := Contract.operation_region_keys(operation, "rebuild_regions")
	_check(support == ["0,0"], "geometric support remains the frozen source region")
	_check(dependencies == ["1,0"], "normal-sampling halo is reported as an additional dependency")
	_check(rebuild == ["0,0", "1,0"], "rebuild set contains support and dependent region")


func _test_atomic_and_settled_streaming_contract() -> void:
	var manifest: Dictionary = Contract.verify_manifest()["manifest"]
	var scenario := _scenario(manifest, "B0S.CORNER.DIRECT_ATOMIC_POS_POS.v1")
	_check(scenario["expected_focus_keys"] == [[0, 0], [1, 1]], "atomic diagonal has no intermediate focus key")
	_check(int(scenario["expected_final_active_count"]) == 14, "R4a atomic diagonal records the approved 14-region result")
	var previous: Dictionary = {}
	for z in range(-1, 2):
		for x in range(-1, 2):
			previous["%d,%d" % [x, z]] = true
	var actual: Dictionary = {}
	for key in previous.keys():
		var parts := String(key).split(",")
		if abs(int(parts[0]) - 1) <= 2 and abs(int(parts[1]) - 1) <= 2:
			actual[key] = true
	for z in range(0, 3):
		for x in range(0, 3):
			actual["%d,%d" % [x, z]] = true
	_check(actual.size() == 14, "9 settled origin residents plus target requests minus four overlaps equals 14")
	for id in ["B0S.CORNER.LOOP_POS.v1", "B0S.CORNER.LOOP_NEG.v1", "B0S.CORNER.LOOP_MIXED.v1"]:
		var loop := _scenario(manifest, id)
		_check(loop["expected_settled_counts"] == [9, 12, 15, 16], "%s retains the accepted three-leg settled counts" % id)
		_check(loop["velocity_legs_mm_s"].size() == 3, "%s uses direction-correct velocity for each leg" % id)
	_check(_window_count(Vector2i.ZERO, 1) == 9 and _window_count(Vector2i.ZERO, 2) == 25, "request and retention radii remain 3x3 and 5x5")


func _test_lod_case_registry() -> void:
	var manifest: Dictionary = Contract.verify_manifest()["manifest"]
	var faces := [
		"B0G.LOD01.FACE.X_NEG.v1", "B0G.LOD01.FACE.X_POS.v1",
		"B0G.LOD01.FACE.Y_NEG.v1", "B0G.LOD01.FACE.Y_POS.v1",
		"B0G.LOD01.FACE.Z_NEG.v1", "B0G.LOD01.FACE.Z_POS.v1",
	]
	for id in faces:
		var scenario := _scenario(manifest, id)
		_check(scenario["origin_lod0_lattice"] == [-4, -2, -6], "%s retains signed aligned origin" % id)
		_check(scenario["face_mask"].size() == 1, "%s is one explicit single-face case" % id)
	for id in [
		"B0G.LOD01.EDGE.X_NEG_Y_NEG.v1", "B0G.LOD01.EDGE.X_POS_Y_NEG.v1",
		"B0G.LOD01.CORNER.X_NEG_Y_POS_Z_NEG.v1", "B0G.LOD01.CORNER.ALL_POS.v1",
	]:
		_check(_scenario(manifest, id).has("face_mask"), "%s has an explicit edge/corner face mask" % id)
	_check(Fixture.is_lod1_aligned_origin(Vector3i(-4, -2, -6)), "frozen LOD transition origin satisfies global LOD1 alignment")


func _test_tunnel_registry() -> void:
	var manifest: Dictionary = Contract.verify_manifest()["manifest"]
	var tunnel: Dictionary = manifest["tunnel_field"]
	var min_mm: Array = tunnel["domain_min_mm"]
	var max_mm: Array = tunnel["domain_max_mm"]
	var step := int(tunnel["step_mm"])
	var dimensions := [
		int((int(max_mm[0]) - int(min_mm[0])) / step) + 1,
		int((int(max_mm[1]) - int(min_mm[1])) / step) + 1,
		int((int(max_mm[2]) - int(min_mm[2])) / step) + 1,
	]
	_check(dimensions == [257, 81, 193], "tunnel grid includes both endpoints at exact B0-approved dimensions")
	_check(_scenario(manifest, "B0G.TUNNEL.SYNTH.W500.v1")["radius_mm"] == 250, "500-mm tunnel maps to 250-mm radius")
	_check(_scenario(manifest, "B0G.TUNNEL.SYNTH.W1000.v1")["radius_mm"] == 500, "1000-mm tunnel maps to 500-mm radius")
	_check(_scenario(manifest, "B0G.TUNNEL.CANONICAL_CONTROL.W1840.v1")["radius_mm"] == 920, "1840-mm canonical control preserves source radius")
	_check(String(_scenario(manifest, "B0G.TUNNEL.CANONICAL_CONTROL.W1840.v1")["id"]) == "B0G.TUNNEL.CANONICAL_CONTROL.W1840.v1", "1840-mm case is a separately identified canonical control")
	_check(_scenario(manifest, "B0G.TUNNEL.SYNTH.W2000.v1")["radius_mm"] == 1000, "2000-mm tunnel maps to 1000-mm radius")
	_check(tunnel["connectivity"] == "6-neighbor", "tunnel component diagnostics retain six-neighbor connectivity")
	_check(tunnel["nearest_lattice_tie_rule"].contains("upper index"), "tunnel centerline uses the frozen nearest-sample tie rule")


func _test_fixed_edits_and_reload() -> void:
	var manifest: Dictionary = Contract.verify_manifest()["manifest"]
	for id in [
		"B0E.SEAM.POS_X.CARVE_FILL.v1",
		"B0E.SEAM.POS_XZ.CARVE_FILL.v1",
		"B0E.SEAM.NEG_XZ.CARVE_FILL.v1",
	]:
		var scenario := _scenario(manifest, id)
		var commands := Contract.commands_from_scenario(scenario)
		_check(commands.size() == 2, "%s has exactly two ordered canonical seam commands" % id)
		_check(Contract.command_list_sha256(commands).length() == 64, "%s has deterministic canonical command hashing" % id)
		_check(String(scenario["geometric_scoring"]).begins_with("EXCLUDED"), "%s does not score unverified edited LOD contours" % id)
	var reload := _scenario(manifest, "B0S.EDITED.RELOAD.REGION_2_NEG1.v1")
	_check(reload["expected_support_keys"] == ["2,-1"], "edited unload/reload has one fixed signed target region")
	_check(reload["probe_positions_mm"].size() == 8, "edited unload/reload freezes all eight canonical probes")
	_check(reload["commands"].size() == 2, "edited unload/reload uses the exact carve/fill command list")


func _test_review_correction_gates() -> void:
	var movement_failure := Contract.movement_result_gate("RUNNING", {"ok": false, "reason_code": "invalid_route_leg"})
	_check(movement_failure["abort"] and movement_failure["terminal_status"] == "FAIL", "unsuccessful streaming movement fails closed")
	_check(movement_failure["reason_code"] == "invalid_route_leg", "movement failure preserves the source reason code")
	_check(Contract.movement_result_gate("PASS", {"ok": false})["terminal_status"] == "FAIL", "failed movement cannot retain a preexisting PASS status")
	var timeout_failure := Contract.movement_result_gate("TIMEOUT", {"ok": false, "reason_code": "process_guard_exceeded"})
	_check(timeout_failure["abort"] and timeout_failure["terminal_status"] == "TIMEOUT", "movement failure preserves right-censored TIMEOUT")
	_check(Contract.movement_result_gate("RUNNING", {})["terminal_status"] == "FAIL", "missing movement success flag fails closed")
	_check(not Contract.movement_result_gate("RUNNING", {"ok": true})["abort"], "successful movement does not trigger failure gate")
	_check(Contract.last_successful_movement_base_keys({})["reason_code"] == "nonsettled_route_has_no_successful_movement_record", "nonsettled route cannot pass without a successful movement state")
	_check(Contract.last_successful_movement_base_keys({"active_before_last_crossing": ["0,0"]})["keys"] == ["0,0"], "last successful movement supplies the nonsettled residency base")
	_check(Contract.last_successful_movement_base_keys({"active_before_last_crossing": []})["reason_code"] == "successful_movement_record_missing_crossing_residency", "empty crossing residency fails closed")

	var reference_mesh := {
		"vertices": PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
	}
	var matching_mesh := {
		"vertices": PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(-1, 0, 0)]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
	}
	var valid_contour := Contract.boundary_contour(reference_mesh, 0, 0.0, 0.00001, 0.000001)
	var matching_contour := Contract.boundary_contour(matching_mesh, 0, 0.0, 0.00001, 0.000001)
	_check(Contract.compare_boundary_contours(valid_contour, valid_contour)["ok"], "matching valid boundary contours pass")
	_check(Contract.compare_boundary_contours(valid_contour, matching_contour)["ok"], "independently built matching LOD boundary geometry passes")
	var t_junction_mesh := {
		"vertices": PackedVector3Array([
			Vector3(0, 0, 0), Vector3(0, 2, 0), Vector3(1, 1, 1),
			Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 1),
			Vector3(0, 1, 0), Vector3(0, 2, 0), Vector3(1, 2, 1),
		]),
		"normals": PackedVector3Array([
			Vector3.UP, Vector3.UP, Vector3.UP,
			Vector3.UP, Vector3.UP, Vector3.UP,
			Vector3.UP, Vector3.UP, Vector3.UP,
		]),
	}
	var t_junction_transition := Contract.boundary_contour(t_junction_mesh, 0, 0.0, 0.00001, 0.000001)
	var t_junction_reference := Contract.boundary_contour(t_junction_mesh.duplicate(true), 0, 0.0, 0.00001, 0.000001)
	_check(not t_junction_transition["valid"] and t_junction_transition["reason_code"] == "t_junction_boundary_vertex", "boundary oracle rejects a vertex strictly inside an unsplit segment")
	_check(not t_junction_reference["valid"] and t_junction_reference["reason_code"] == "t_junction_boundary_vertex", "independent reference oracle detects the same T-junction")
	_check(t_junction_transition["segments"] == t_junction_reference["segments"] and t_junction_transition["normals"] == t_junction_reference["normals"], "negative T-junction pair has identical segments and matching normals")
	var matching_t_junction := Contract.compare_boundary_contours(t_junction_transition, t_junction_reference)
	_check(not matching_t_junction["ok"] and matching_t_junction["reason_code"] == "transition_boundary_contour_invalid", "identical segment dictionaries and normals cannot conceal matching T-junctions")
	var split_boundary_mesh := {
		"vertices": PackedVector3Array([
			Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 1),
			Vector3(0, 1, 0), Vector3(0, 2, 0), Vector3(1, 2, 1),
		]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]),
	}
	var split_boundary := Contract.boundary_contour(split_boundary_mesh, 0, 0.0, 0.00001, 0.000001)
	_check(split_boundary["valid"] and split_boundary["segments"].size() == 2, "matching split-only boundary segments remain valid")
	_check(Contract.compare_boundary_contours(split_boundary, split_boundary)["ok"], "matching split-only contour passes without an unsplit parent segment")
	var adjacent_triangle_mesh := {
		"vertices": PackedVector3Array([
			Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 1),
			Vector3(0, 1, 0), Vector3(0, 2, 0), Vector3(1, 1, 1),
		]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]),
	}
	var adjacent_triangle_contour := Contract.boundary_contour(adjacent_triangle_mesh, 0, 0.0, 0.00001, 0.000001)
	_check(adjacent_triangle_contour["valid"] and adjacent_triangle_contour["segments"].size() == 2, "legitimate adjacent triangles sharing an off-plane edge and boundary endpoint remain valid")
	_check(Contract.compare_boundary_contours(split_boundary, adjacent_triangle_contour)["ok"], "adjacent triangle topology is not blanket-rejected as a T-junction")
	var duplicate_mesh := {
		"vertices": PackedVector3Array([
			Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0),
			Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(-1, 0, 0),
		]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]),
	}
	var invalid_transition := Contract.boundary_contour(duplicate_mesh, 0, 0.0, 0.00001, 0.000001)
	_check(Contract.compare_boundary_contours(invalid_transition, valid_contour)["reason_code"] == "transition_boundary_contour_invalid", "invalid transition contour is rejected")
	var conflicting_normals_mesh := {
		"vertices": PackedVector3Array([
			Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
			Vector3(0, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1),
		]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN]),
	}
	var invalid_reference := Contract.boundary_contour(conflicting_normals_mesh, 0, 0.0, 0.00001, 0.000001)
	_check(Contract.compare_boundary_contours(valid_contour, invalid_reference)["reason_code"] == "reference_boundary_contour_invalid", "invalid LOD reference contour is rejected")
	var duplicate_contour := Contract.boundary_contour(duplicate_mesh, 0, 0.0, 0.00001, 0.000001)
	_check(Contract.compare_boundary_contours(duplicate_contour, valid_contour)["contour_reason"] == "duplicate_boundary_segment", "duplicate boundary geometry has an explicit negative regression")
	var mismatching_mesh := {
		"vertices": PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 2, 0), Vector3(1, 0, 0)]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
	}
	var unmatched_contour := Contract.boundary_contour(mismatching_mesh, 0, 0.0, 0.00001, 0.000001)
	_check(Contract.compare_boundary_contours(valid_contour, unmatched_contour)["reason_code"] == "interface_segment_mismatch", "nonmatching LOD contour segments are rejected")
	var degenerate_mesh := {
		"vertices": PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 1)]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
	}
	var degenerate_contour := Contract.boundary_contour(degenerate_mesh, 0, 0.0, 0.00001, 0.000001)
	_check(not degenerate_contour["valid"] and degenerate_contour["reason_code"] == "degenerate_boundary_segment", "degenerate interface geometry is rejected")
	var empty_mesh := {"vertices": PackedVector3Array(), "normals": PackedVector3Array()}
	var empty_contour := Contract.boundary_contour(empty_mesh, 0, 0.0, 0.00001, 0.000001)
	_check(Contract.compare_boundary_contours(empty_contour, valid_contour)["reason_code"] == "transition_boundary_contour_invalid", "malformed transition mesh cannot pass as an empty contour")

	var dimensions := Vector3i(3, 3, 1)
	var total := dimensions.x * dimensions.y * dimensions.z
	var global_empty := PackedByteArray()
	global_empty.resize(total)
	for index in [0, 1, 2, 4, 5, 6, 7, 8]:
		global_empty[index] = 1
	var centerline := PackedInt32Array([0, 5, 6])
	var global_result := Contract.connected_required_samples(global_empty, dimensions, centerline)
	_check(global_result["ok"], "global empty-space component can connect centerline samples through exterior air")
	var corridor_empty := PackedByteArray()
	corridor_empty.resize(total)
	for index in centerline:
		corridor_empty[index] = 1
	var corridor_result := Contract.connected_required_samples(corridor_empty, dimensions, centerline)
	_check(not corridor_result["ok"] and corridor_result["reason_code"] == "required_samples_disconnected", "global empty-space connectivity cannot mask an obstructed centerline-constrained corridor")
	_check(Contract.connected_required_samples(PackedByteArray(), dimensions, centerline)["reason_code"] == "invalid_connectivity_dimensions_or_seeds", "corridor oracle rejects incomplete grid data")

	var good_edit_receipt := {
		"kind": "EDIT_TRANSACTION", "transaction_clear": true, "pending_stage": false,
		"target_region_id": "2,-1",
		"stage_observations": [{"region_id": "2,-1", "purpose": "edit_transaction", "edit_revision": 2, "chunk_count": 4}],
		"stream_errors": [], "expected_revision": 2, "observed_revision": 2,
		"expected_chunk_count": 16, "active_chunk_count": 16, "array_mesh_count": 16,
		"edit_commit_status": "COHERENT_COMMIT", "expected_sequence": 1,
		"edit_commit_sequence": 1, "mesh_job_count": 4,
	}
	_check(Contract.validate_publication_evidence(good_edit_receipt)["ok"], "revision-matched edit mesh publication receipt passes")
	var cleared_only := good_edit_receipt.duplicate(true)
	cleared_only["edit_commit_status"] = ""
	cleared_only["mesh_job_count"] = 0
	_check(Contract.validate_publication_evidence(cleared_only)["reason_code"] == "edit_mesh_commit_receipt_missing_or_mismatched", "empty transaction without a coherent commit receipt fails closed")
	var no_stage_receipt := good_edit_receipt.duplicate(true)
	no_stage_receipt["stage_observations"] = []
	_check(Contract.validate_publication_evidence(no_stage_receipt)["reason_code"] == "revision_pinned_production_stage_not_observed", "publication is rejected without observing the revision-pinned production stage")
	var stale_revision := good_edit_receipt.duplicate(true)
	stale_revision["observed_revision"] = 1
	_check(Contract.validate_publication_evidence(stale_revision)["reason_code"] == "publication_revision_mismatch", "stale mesh publication revision is rejected")
	var partial_meshes := good_edit_receipt.duplicate(true)
	partial_meshes["array_mesh_count"] = 15
	_check(Contract.validate_publication_evidence(partial_meshes)["reason_code"] == "publication_mesh_set_incomplete", "incomplete visible chunk mesh set is rejected")
	var wrong_sequence := good_edit_receipt.duplicate(true)
	wrong_sequence["edit_commit_sequence"] = 0
	_check(Contract.validate_publication_evidence(wrong_sequence)["reason_code"] == "edit_mesh_commit_receipt_missing_or_mismatched", "publication receipt for another command sequence is rejected")
	var pending_publication := good_edit_receipt.duplicate(true)
	pending_publication["pending_stage"] = true
	_check(Contract.validate_publication_evidence(pending_publication)["reason_code"] == "publication_stage_still_pending", "mesh publication is rejected while the region still has a pending stage")
	var reload_receipt := good_edit_receipt.duplicate(true)
	reload_receipt["kind"] = "REGION_LOAD"
	reload_receipt["stage_observations"] = [{"region_id": "2,-1", "purpose": "load", "edit_revision": 2, "chunk_count": 16}]
	reload_receipt["successful_publication_delta"] = 1
	_check(Contract.validate_publication_evidence(reload_receipt)["ok"], "revision-matched region load publication receipt passes")
	reload_receipt["successful_publication_delta"] = 0
	_check(Contract.validate_publication_evidence(reload_receipt)["reason_code"] == "region_load_publication_not_observed", "SDF equality without a successful region publication is rejected")


func _scenario(manifest: Dictionary, id: String) -> Dictionary:
	for value in manifest["scenarios"]:
		var scenario: Dictionary = value
		if String(scenario["id"]) == id:
			return scenario
	return {}


func _window_count(center: Vector2i, radius: int) -> int:
	return (2 * radius + 1) * (2 * radius + 1)


func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("P1B1_CONTRACT_ASSERTION_FAILED: " + label)
