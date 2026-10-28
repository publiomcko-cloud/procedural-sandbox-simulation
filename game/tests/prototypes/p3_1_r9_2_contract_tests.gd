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
	_test_registered_diagnostics(manifest.rows)
	_test_normal_convention(zero_setup.snapshot)
	_check(not Core.iteration_counts({"warmups": 1.5, "repeats": 1}).get("valid", false), "fractional_manifest_repeat_count_rejected")
	_check(not Core.iteration_counts({"warmups": true, "repeats": 1}).get("valid", false), "boolean_manifest_repeat_count_rejected")
	_check(not Core.iteration_counts({"warmups": 1, "repeats": 0}).get("valid", false), "zero_measured_repeats_rejected")
	var d_scope := Core.candidate_scope({"candidate_scope": ["D"]}, "D")
	var c_scope := Core.candidate_scope({"candidate_scope": ["D"]}, "C")
	_check(d_scope.get("valid", false) and d_scope.get("in_scope", false), "D_only_manifest_scope_includes_D")
	_check(c_scope.get("valid", false) and not c_scope.get("in_scope", true), "D_only_manifest_scope_excludes_other_candidates")
	_finish()

func _test_registered_diagnostics(rows: Array) -> void:
	var observed_kinds: Dictionary = {}
	for row_value in rows:
		var row: Dictionary = row_value
		var kind := String(row.get("kind", ""))
		var hooks: Array = Core.diagnostic_hooks(kind)
		_check(not hooks.is_empty(), "registered_diagnostic_hook_" + kind)
		observed_kinds[kind] = true
		var counts := Core.iteration_counts(row)
		_check(counts.get("valid", false) and int(counts.get("warmups", -1)) == int(row.get("warmups", -2)) and int(counts.get("repeats", -1)) == int(row.get("repeats", -2)), "manifest_iteration_counts_" + kind)
		_check(int(row.get("repeats", 0)) >= 1 and int(row.get("repeats", 0)) <= 5 and int(row.get("warmups", -1)) >= 0 and int(row.get("warmups", 6)) <= 5, "frozen_iteration_bounds_" + kind)
		_check(Core.candidate_scope(row, "A").get("valid", false), "candidate_scope_contract_" + kind)
		_check(hooks.has("candidate_mesh") == (kind != "sampled_cave_connectivity"), "hook_mesh_scope_" + kind)
		if kind == "materialized_volume_corrupt_reload":
			_check(row.get("candidate_scope", []) == ["D"] and hooks.has("actual_fresh_reader_corruption_reload"), "corruption_probe_frozen_to_D")
		if kind == "equal_resolution_boundary" or kind == "negative_coordinate_region_boundaries":
			_check(hooks.has("single_roi_contour_proxy_not_chunk_join"), "seam_hook_discloses_proxy_scope_" + kind)
	_check(observed_kinds.size() == 20, "all_twenty_frozen_kinds_registered")

func _test_normal_convention(snapshot: Dictionary) -> void:
	var point := Vector3(0.0, -0.5, 0.0)
	var gradient := Core.canonical_gradient(point, snapshot)
	var outward := Core.canonical_outward_normal(point, snapshot)
	_check(gradient.get("valid", false) and gradient.gradient.dot(Vector3.UP) > 0.99, "lower_boundary_density_gradient_points_into_solid")
	_check(outward.get("valid", false) and outward.outward_normal.dot(Vector3.DOWN) > 0.99, "lower_boundary_outward_normal_points_into_empty")
	var mesh := {"positions": PackedVector3Array([point]), "normals": PackedVector3Array([Vector3.DOWN])}
	var comparison := Core.normal_deviation(mesh, snapshot)
	_check(comparison.get("valid", false) and float(comparison.get("max_degrees", 180.0)) < 0.01, "normal_deviation_uses_production_outward_convention")

func _check(ok: bool, label: String) -> void:
	_assertions += 1
	if not ok:
		_failures.append(label)

func _finish() -> void:
	var status := "PASS" if _failures.is_empty() else "FAIL"
	print("P3_1_R9_2_CONTRACT_TESTS_RESULT " + JSON.stringify({"status": status, "assertions": _assertions,
		"failures": _failures, "expected_manifest_sha256": Core.EXPECTED_MANIFEST_SHA, "runtime_tests_only": true}))
	quit(0 if _failures.is_empty() else 1)
