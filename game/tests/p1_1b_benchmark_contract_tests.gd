extends SceneTree

const Contract := preload("res://tests/p1_1b_benchmark_contract.gd")
const Fixture := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")

var _assertions := 0
var _failures := 0
var _manifest: Dictionary = {}
var _manifest_sha256 := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var verification: Dictionary = Contract.verify_manifest()
	var plan: Dictionary = Contract.contract_suite_plan(verification)
	if not plan.get("ok", false):
		print("P1B1_CONTRACT_TESTS_FAIL: stage=manifest_preflight reason=%s dependent_groups=0" % String(plan.get("reason", "manifest_preflight_failed")))
		quit(1)
		return
	_manifest = plan["manifest"]
	_manifest_sha256 = String(verification.get("sha256", ""))
	for group_value in plan["dependent_groups"]:
		_run_group(String(group_value))
	if _failures == 0:
		print("P1B1_CONTRACT_TESTS_PASS: assertions=%d failures=0" % _assertions)
		quit(0)
	else:
		push_error("P1B1_CONTRACT_TESTS_FAIL: assertions=%d failures=%d" % [_assertions, _failures])
		quit(1)


func _run_group(group: String) -> void:
	match group:
		"manifest_identity":
			_test_manifest_identity_and_freeze_boundary()
		"canonical_replay":
			_test_canonical_replay_recipes()
		"support_rebuild_dependency":
			_test_support_and_rebuild_dependency_are_distinct()
		"streaming_contract":
			_test_atomic_and_settled_streaming_contract()
		"lod_registry":
			_test_lod_case_registry()
		"tunnel_registry":
			_test_tunnel_registry()
		"fixed_edits_reload":
			_test_fixed_edits_and_reload()
		"review_correction_gates":
			_test_review_correction_gates()
		"manifest_normalization":
			_test_manifest_numeric_normalization()
		"manifest_file_failures":
			_test_manifest_file_failures()
		"preflight_fail_closed":
			_test_preflight_fail_closed()
		_:
			_check(false, "unknown contract group is rejected: %s" % group)


func _test_manifest_identity_and_freeze_boundary() -> void:
	var manifest := _manifest
	_check(not manifest.is_empty(), "suite uses the single validated canonical manifest")
	_check(_manifest_sha256 == Contract.MANIFEST_SHA256, "physical manifest SHA matches the source-pinned digest")
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
	_check(not Contract._canonical_value_supported({"fractional": 0.58}), "normalizer rejects fractional numeric values")
	_check(Contract.canonical_json({"z": 1, "a": [true, "x"]}) == "{\"a\":[true,\"x\"],\"z\":1}", "canonical JSON sorts object keys and preserves array order")
	_check(not Contract._is_lower_hex_sha256("A".repeat(64)), "SHA-256 pin validation rejects uppercase hex")
	_check(manifest["excluded_not_frozen"].size() == 9, "all nine unresolved B0 scenarios remain excluded")


func _test_manifest_numeric_normalization() -> void:
	var canonical_integer_bytes := "{\"items\":[-2,0,7],\"version\":1}".to_utf8_buffer()
	var canonical_integer_value: Variant = JSON.parse_string(canonical_integer_bytes.get_string_from_utf8())
	var canonical_integer_check := Contract.validate_canonical_json_bytes(canonical_integer_bytes, canonical_integer_value)
	_check(canonical_integer_check.get("ok", false), "canonical JSON with integer number tokens validates after safe normalization")
	if canonical_integer_check.get("ok", false):
		var normalized: Dictionary = canonical_integer_check["value"]
		_check(typeof(normalized["version"]) == TYPE_INT and typeof(normalized["items"][0]) == TYPE_INT, "integral parser floats are normalized to integer Variants")
		_check(normalized["items"] == [-2, 0, 7], "normalization preserves array order and signed integer values")
	var float_backed_integer_value: Dictionary = {"items": [-2.0, 0.0, 7.0], "version": 1.0}
	var float_backed_check := Contract.validate_canonical_json_bytes(canonical_integer_bytes, float_backed_integer_value)
	_check(float_backed_check.get("ok", false), "integer-token bytes remain valid when the parser supplies integral TYPE_FLOAT values")
	if float_backed_check.get("ok", false):
		_check(typeof(float_backed_check["value"]["version"]) == TYPE_INT, "float-backed parsed integer is normalized before returning the manifest")
	var fractional_value: Variant = JSON.parse_string("{\"value\":0.58}")
	var fractional_result := Contract.normalize_json_value(fractional_value)
	_check(not fractional_result.get("ok", false) and fractional_result.get("reason", "") == "manifest_json_number_not_integral", "fractional JSON numbers are rejected with an exact reason")
	for lexical_number in ["1.0", "1e0", "1.00"]:
		var alternate_bytes: PackedByteArray = ("{\"value\":" + String(lexical_number) + "}").to_utf8_buffer()
		var alternate_value: Variant = JSON.parse_string(alternate_bytes.get_string_from_utf8())
		var alternate_result := Contract.validate_canonical_json_bytes(alternate_bytes, alternate_value)
		_check(not alternate_result.get("ok", false) and alternate_result.get("reason", "") == "manifest_bytes_not_canonical_utf8_json", "integral decimal/exponent spelling %s is rejected by exact-byte comparison" % lexical_number)
	var maximum_safe := Contract.normalize_json_value(Contract.MAX_SAFE_JSON_INTEGER)
	var minimum_safe := Contract.normalize_json_value(Contract.MIN_SAFE_JSON_INTEGER)
	_check(maximum_safe.get("ok", false) and minimum_safe.get("ok", false), "both boundaries of the safe integer range are accepted")
	var above_safe := Contract.normalize_json_value(9007199254740992.0)
	var below_safe := Contract.normalize_json_value(-9007199254740992.0)
	_check(above_safe.get("reason", "") == "manifest_json_integer_outside_safe_range", "integer above the safe range is rejected")
	_check(below_safe.get("reason", "") == "manifest_json_integer_outside_safe_range", "integer below the safe range is rejected")
	_check(Contract.normalize_json_value(INF).get("reason", "") == "manifest_json_number_not_finite", "infinite numeric values are rejected")
	_check(Contract.normalize_json_value(NAN).get("reason", "") == "manifest_json_number_not_finite", "NaN numeric values are rejected")
	var reordered_bytes := "{\"z\":0,\"a\":1}".to_utf8_buffer()
	var reordered_value: Variant = JSON.parse_string(reordered_bytes.get_string_from_utf8())
	_check(Contract.validate_canonical_json_bytes(reordered_bytes, reordered_value).get("reason", "") == "manifest_bytes_not_canonical_utf8_json", "object keys must retain the canonical sorted byte representation")


func _test_manifest_file_failures() -> void:
	var temporary_root := OS.get_user_data_dir().path_join("p1_1b_manifest_contract_%d" % Time.get_ticks_usec())
	var directory_result := DirAccess.make_dir_recursive_absolute(temporary_root)
	_check(directory_result == OK, "manifest validation fixtures use a disposable user-data directory")
	if directory_result != OK:
		return
	var manifest_path := temporary_root.path_join("manifest.json")
	var pin_path := temporary_root.path_join("manifest.sha256")
	var incorrect_pin_path := temporary_root.path_join("incorrect.sha256")
	var canonical_bytes := Contract.canonical_json(_manifest).to_utf8_buffer()
	var manifest_written := _write_test_bytes(manifest_path, canonical_bytes)
	var pin_written := _write_test_text(pin_path, Contract.MANIFEST_SHA256 + "\n")
	_check(manifest_written and pin_written, "temporary manifest and correct sidecar are written completely")
	if manifest_written and pin_written:
		var valid_file := Contract.verify_manifest(manifest_path, pin_path)
		_check(valid_file.get("ok", false), "canonical integer-token manifest with pinned bytes and sidecar verifies")
		var corrupted_bytes := canonical_bytes.duplicate()
		corrupted_bytes.insert(0, 0x20)
		_check(_write_test_bytes(manifest_path, corrupted_bytes), "corrupted-byte fixture is written")
		var corrupted := Contract.verify_manifest(manifest_path, pin_path)
		_check(corrupted.get("reason", "") == "manifest_bytes_not_canonical_utf8_json", "corrupted manifest bytes fail exact canonical comparison")
		_check(_write_test_bytes(manifest_path, canonical_bytes), "canonical manifest bytes are restored in the disposable fixture")
		_check(_write_test_text(incorrect_pin_path, "0".repeat(64) + "\n"), "incorrect sidecar fixture is written")
		var incorrect_pin := Contract.verify_manifest(manifest_path, incorrect_pin_path)
		_check(incorrect_pin.get("reason", "") == "manifest_sha256_pin_does_not_match_reviewed_source", "incorrect but well-formed sidecar is rejected")
		var absent_pin := Contract.verify_manifest(manifest_path, temporary_root.path_join("absent.sha256"))
		_check(absent_pin.get("reason", "") == "manifest_or_digest_file_missing", "absent SHA-256 sidecar is rejected")
	DirAccess.remove_absolute(manifest_path)
	DirAccess.remove_absolute(pin_path)
	DirAccess.remove_absolute(incorrect_pin_path)
	DirAccess.remove_absolute(temporary_root)


func _test_preflight_fail_closed() -> void:
	var failure := Contract.contract_suite_plan({"ok": false, "reason": "manifest_json_number_not_integral"})
	_check(not failure.get("ok", false) and failure.get("status", "") == "FAIL", "failed manifest preflight has an explicit FAIL suite decision")
	_check(failure.get("reason", "") == "manifest_json_number_not_integral", "suite preflight preserves the exact manifest verification reason")
	_check((failure.get("dependent_groups", []) as Array).is_empty(), "failed preflight schedules zero dependent test groups")
	var missing_manifest := Contract.contract_suite_plan({"ok": true})
	_check(not missing_manifest.get("ok", false) and missing_manifest.get("status", "") == "FAIL", "success without a manifest is rejected before dependent tests")
	_check((missing_manifest.get("dependent_groups", []) as Array).is_empty(), "malformed successful preflight also schedules zero dependent groups")


func _write_test_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return FileAccess.get_file_as_bytes(path) == bytes


func _write_test_text(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return FileAccess.get_file_as_string(path) == value


func _test_canonical_replay_recipes() -> void:
	var manifest := _manifest
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
	var manifest := _manifest
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
	var manifest := _manifest
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
	var manifest := _manifest
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
	var manifest := _manifest
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
	_test_engine_version_validation()
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


func _test_engine_version_validation() -> void:
	var authorized_prefix_identity := {
		"major": 4, "minor": 7, "patch": 2, "status": "stable", "build": "official",
		"hash": "ed1daf0bf", "string": "4.7.2.stable.official.ed1daf0bf",
	}
	var prefix_result: Dictionary = Contract.validate_engine_version_info(authorized_prefix_identity)
	_check(prefix_result.get("ok", false), "exact structured 4.7.2 stable official identity with the authorized commit prefix passes")
	_check(prefix_result.get("runtime_hash_status", "") == "MATCHED_COMMIT_PREFIX", "runtime commit prefix is reported as matched, not as a full-hash observation")
	var display_variant: Dictionary = authorized_prefix_identity.duplicate(true)
	display_variant["string"] = "4.7.2-stable (official)"
	_check(Contract.validate_engine_version_info(display_variant).get("ok", false), "authorized structured identity passes with Godot's alternate display string")
	var full_hash_identity: Dictionary = authorized_prefix_identity.duplicate(true)
	full_hash_identity["hash"] = "ed1daf0bf001b61586d9930840f2f1394092c079"
	var full_hash_result: Dictionary = Contract.validate_engine_version_info(full_hash_identity)
	_check(full_hash_result.get("ok", false), "exact full Godot source commit hash passes")
	_check(full_hash_result.get("runtime_hash_status", "") == "MATCHED_FULL_COMMIT_SHA", "full source hash is identified separately from the abbreviated prefix")
	var missing_hash_identity: Dictionary = authorized_prefix_identity.duplicate(true)
	missing_hash_identity.erase("hash")
	var missing_hash_result: Dictionary = Contract.validate_engine_version_info(missing_hash_identity)
	_check(missing_hash_result.get("ok", false), "unavailable runtime hash does not override the external executable SHA pin or block matching structured version fields")
	_check(missing_hash_result.get("runtime_hash_status", "") == "UNAVAILABLE_MISSING", "missing runtime hash is explicitly reported as unavailable")
	var empty_hash_identity: Dictionary = authorized_prefix_identity.duplicate(true)
	empty_hash_identity["hash"] = ""
	_check(Contract.validate_engine_version_info(empty_hash_identity).get("runtime_hash_status", "") == "UNAVAILABLE_EMPTY", "empty runtime hash is explicitly reported as unavailable")
	for wrong_version in [
		{"field": "major", "value": 5},
		{"field": "minor", "value": 6},
		{"field": "patch", "value": 3},
	]:
		var wrong_tuple: Dictionary = authorized_prefix_identity.duplicate(true)
		wrong_tuple[wrong_version["field"]] = wrong_version["value"]
		var wrong_tuple_result: Dictionary = Contract.validate_engine_version_info(wrong_tuple)
		_check(not wrong_tuple_result.get("ok", false) and wrong_tuple_result.get("reason", "") == "runtime_version_tuple_mismatch", "wrong structured %s version is rejected" % wrong_version["field"])
	for unsupported_status in ["beta", "rc"]:
		var prerelease: Dictionary = authorized_prefix_identity.duplicate(true)
		prerelease["status"] = unsupported_status
		_check(Contract.validate_engine_version_info(prerelease).get("reason", "") == "runtime_version_status_mismatch", "unsupported %s status is rejected" % unsupported_status)
	var custom_build: Dictionary = authorized_prefix_identity.duplicate(true)
	custom_build["build"] = "custom_build"
	_check(Contract.validate_engine_version_info(custom_build).get("reason", "") == "runtime_version_build_mismatch", "custom engine build is rejected")
	for field in ["major", "minor", "patch", "status", "build"]:
		var missing_field: Dictionary = authorized_prefix_identity.duplicate(true)
		missing_field.erase(field)
		var missing_result: Dictionary = Contract.validate_engine_version_info(missing_field)
		_check(not missing_result.get("ok", false) and missing_result.get("reason", "") == "runtime_version_field_missing" and missing_result.get("field", "") == field, "missing required %s field is rejected with its field identity" % field)
	for invalid_field in [
		{"field": "major", "value": "4"},
		{"field": "minor", "value": 7.0},
		{"field": "patch", "value": true},
		{"field": "status", "value": 1},
		{"field": "build", "value": 1},
	]:
		var invalid_type: Dictionary = authorized_prefix_identity.duplicate(true)
		invalid_type[invalid_field["field"]] = invalid_field["value"]
		var invalid_type_result: Dictionary = Contract.validate_engine_version_info(invalid_type)
		_check(not invalid_type_result.get("ok", false) and invalid_type_result.get("reason", "") == "runtime_version_field_invalid_type", "invalid type for required %s field is rejected" % invalid_field["field"])
	for wrong_hash in ["ed1daf0b0", "000000000", "ed1daf0bf001b61586d9930840f2f1394092c078"]:
		var arbitrary_hash: Dictionary = authorized_prefix_identity.duplicate(true)
		arbitrary_hash["hash"] = wrong_hash
		var wrong_hash_result: Dictionary = Contract.validate_engine_version_info(arbitrary_hash)
		_check(not wrong_hash_result.get("ok", false) and wrong_hash_result.get("reason", "") == "runtime_version_git_hash_mismatch", "nonmatching runtime Git hash is rejected: %s" % wrong_hash)
	var invalid_hash_type: Dictionary = authorized_prefix_identity.duplicate(true)
	invalid_hash_type["hash"] = 4
	_check(Contract.validate_engine_version_info(invalid_hash_type).get("reason", "") == "runtime_version_hash_invalid_type", "provided non-string runtime hash is rejected")
	var misleading_display: Dictionary = authorized_prefix_identity.duplicate(true)
	misleading_display["patch"] = 3
	misleading_display["string"] = "4.7.2-stable (official)"
	_check(not Contract.validate_engine_version_info(misleading_display).get("ok", false), "a correct-looking display string cannot override an incorrect structured version")


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
