extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
var _assertions := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest := Core.load_manifest()
	_check(bool(manifest.get("valid", false)), "manifest_bytes_sidecar_schema_and_case_integrity")
	if not manifest.get("valid", false):
		_finish()
		return
	_check(manifest.rows.size() == 20, "twenty_frozen_scenario_rows")
	_check(manifest.case_digests.size() == 20 and manifest.command_digests.size() == 20, "raw_case_and_command_byte_hashes_available")
	var negative := Core.case_by_id(manifest.rows, "R9.2.SEAM.NEGATIVE_REGIONS.v1")
	_check(negative.get("variants", []).size() == 2, "negative_x_and_z_seams_are_separate_variants")
	var rays := Core.case_by_id(manifest.rows, "R9.2.RAY.CANONICAL_PICKER.v1")
	_check(Core.ray_grid(rays.roi, rays.ray_grid).size() == 25, "exactly_twenty_five_shared_picker_rays")
	var proxy := Core.case_by_id(manifest.rows, "R9.2.COLLISION.TWO_SIDED_PROXY.v1")
	_check(proxy.rays.size() == 12, "twelve_explicit_cpu_proxy_rays")
	for row_value in manifest.rows:
		var row: Dictionary = row_value
		var setup := Core.make_snapshot(row)
		_check(bool(setup.get("valid", false)), "canonical_ordered_snapshot_" + String(row.scenario_id))
		if not setup.get("valid", false):
			continue
		_check(int(setup.revision) == row.commands.size(), "revision_matches_command_count_" + String(row.scenario_id))
	var cave := Core.case_by_id(manifest.rows, "R9.2.CAVE.SAMPLED_CONNECTIVITY.v1")
	var cave_nodes := Core.validate_roi(cave.roi)
	_check(bool(cave_nodes.valid) and int(cave_nodes.node_count) <= Core.MAX_NODES, "sampled_cave_roi_within_10000_node_cap")
	var zero := Core.case_by_id(manifest.rows, "R9.2.GEO.ZERO.v1")
	var zero_setup := Core.make_snapshot(zero)
	_check(bool(zero_setup.valid) and int(zero_setup.revision) == 0, "zero_edit_snapshot_revision_is_zero")
	_finish()

func _check(ok: bool, label: String) -> void:
	_assertions += 1
	if not ok:
		_failures.append(label)

func _finish() -> void:
	var status := "PASS" if _failures.is_empty() else "FAIL"
	print("P3_1_R9_2_CONTRACT_TESTS_RESULT " + JSON.stringify({"status": status, "assertions": _assertions,
		"failures": _failures, "expected_manifest_sha256": Core.EXPECTED_MANIFEST_SHA, "runtime_tests_only": true}))
	quit(0 if _failures.is_empty() else 1)
