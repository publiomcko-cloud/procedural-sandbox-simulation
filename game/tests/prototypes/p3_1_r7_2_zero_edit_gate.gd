extends "res://tests/prototypes/p3_1_r7_conforming_adaptive_diagnostic.gd"

## R7.2 sequential geometry gates. It applies the selected local-only A repair
## to one frozen full test mesh, then reuses the R7 two-sided collider oracle.
## No production scene, storage or user save is loaded.
const RepairR72 := preload("res://tests/prototypes/p3_1_r7_2_local_retriangulation.gd")
const FocusCellIdsR72: Array[int] = [1101, 1149, 1150, 1199]
const MAX_EDITED_FOCUS_CELLS_R72 := 64

func _run() -> void:
	var gate_start_usec := Time.get_ticks_usec()
	var scenario := _requested_scenario()
	var diagnostic_only := OS.get_cmdline_user_args().has("--diagnose-only")
	var diagnostic_strategy := _requested_diagnostic_strategy()
	if diagnostic_only and scenario != "cave_wall_carve":
		_failures.append("diagnose_only_requires_frozen_cave_wall_carve")
		_finish_diagnostic(false, {"reason": "unsupported_diagnostic_scenario", "scenario": scenario})
		return
	if diagnostic_only and not ["A_edge_collapse", "B_constrained_cavity"].has(diagnostic_strategy):
		_finish_diagnostic(false, {"reason": "unsupported_diagnostic_strategy", "strategy": diagnostic_strategy})
		return
	if not ["zero_edit", "cave_wall_carve", "center_fill_then_wall_carve"].has(scenario):
		_failures.append("unsupported_frozen_scenario:%s" % scenario)
		_finish()
		return
	var snapshot_result := _make_snapshot(scenario)
	_check(bool(snapshot_result.get("valid", false)), "%s_frozen_snapshot_setup" % scenario)
	if not bool(snapshot_result.get("valid", false)):
		_finish()
		return
	var snapshot: Dictionary = snapshot_result.snapshot
	var input_payload: Dictionary = _scenario_input_payload(scenario, snapshot)
	var input_canonical_json := JSON.stringify(input_payload)
	var fixture := Fixture.new()
	var fixture_configured: bool = fixture.configure(SEED, snapshot)
	_check(fixture_configured, "%s_canonical_field_configures" % scenario)
	if not fixture_configured:
		_failures.append("fixture:%s" % fixture.last_reason)
		_finish()
		return
	_check(fixture.configure_r71_polygonizer("production", "reject_only_exact_zero", "production"),
		"inclusive_nonzero_polygonizer_configures_without_changing_threshold")
	var build_start_usec := Time.get_ticks_usec()
	var built: Dictionary = fixture.build_approach("A_conforming_propagation")
	var build_elapsed_usec := Time.get_ticks_usec() - build_start_usec
	_check(bool(built.get("valid", false)), "%s_frozen_full_mesh_builds" % scenario)
	if not bool(built.get("valid", false)):
		_failures.append("full_build:%s" % String(built.get("reason", "unknown")))
		_finish()
		return
	var repair := RepairR72.new()
	var focus_ids: Array[int] = FocusCellIdsR72.duplicate() if scenario == "zero_edit" else _subthreshold_cell_ids(built.cells)
	_check(focus_ids.size() <= MAX_EDITED_FOCUS_CELLS_R72,
		"%s_candidate_patch_within_bounded_focus_cell_limit" % scenario)
	if focus_ids.size() > MAX_EDITED_FOCUS_CELLS_R72:
		_failures.append("local_focus_cell_limit_exceeded:%d" % focus_ids.size())
		_finish()
		return
	var local_before: Dictionary = repair.extract_local_mesh(fixture, built.cells, focus_ids)
	var local_metrics_before: Dictionary = repair.metrics(fixture, local_before)
	if scenario == "zero_edit":
		_check(int(local_metrics_before.internal_open_edges) == 0 and int(local_metrics_before.degenerate_triangles) == 8,
			"full_mesh_local_patch_matches_inclusive_eight_microtriangle_control")
	var local_repair_start_usec := Time.get_ticks_usec()
	var strategy_a: Dictionary
	var strategy_b: Dictionary = {"valid": true, "disposition": "NOT_RUN_OUTSIDE_ZERO_EDIT_STRATEGY_COMPARISON"}
	var strategy_c: Dictionary = {"valid": true, "disposition": "NOT_RUN_OUTSIDE_ZERO_EDIT_STRATEGY_COMPARISON"}
	if not focus_ids.is_empty():
		if diagnostic_only and diagnostic_strategy == "B_constrained_cavity":
			strategy_a = {"valid": true, "strategy": "B_constrained_cavity_DIAGNOSTIC_PENDING"}
		else:
			strategy_a = repair.run_strategy(fixture, local_before, "A_edge_collapse")
		if scenario == "zero_edit":
			strategy_b = repair.run_strategy(fixture, local_before, "B_constrained_cavity")
			strategy_c = repair.run_strategy(fixture, local_before, "C_boundary_patch_remesh")
	else:
		strategy_a = {"valid": true, "no_op": true, "strategy": "A_edge_collapse",
			"disposition": "NO_SUBTHRESHOLD_FACES_FOUND"}
	var local_repair_elapsed_usec := Time.get_ticks_usec() - local_repair_start_usec
	if diagnostic_only:
		var selected_diagnostic_strategy: Dictionary = strategy_a
		if diagnostic_strategy == "B_constrained_cavity":
			var minimal_patch: Dictionary = repair.extract_local_mesh(fixture, built.cells, [720])
			selected_diagnostic_strategy = repair.run_strategy(fixture, minimal_patch, diagnostic_strategy)
		var diagnostic: Dictionary = _make_r73_failure_diagnostic(scenario, snapshot, input_payload,
			input_canonical_json, fixture, built, focus_ids, local_before, local_metrics_before,
			selected_diagnostic_strategy, gate_start_usec, build_elapsed_usec, local_repair_elapsed_usec)
		diagnostic["repair_strategy"] = diagnostic_strategy
		print("R73_FAILURE_DIAGNOSTIC " + JSON.stringify(diagnostic))
		_finish_diagnostic(bool(diagnostic.get("complete", false)), diagnostic)
		return
	_check(bool(strategy_a.get("valid", false)), "%s_selected_A_repair_satisfies_all_local_invariants" % scenario)
	var patched_cells_result := _replace_local_cells(built.cells, strategy_a, repair)
	_check(bool(patched_cells_result.get("valid", false)), "%s_local_A_patch_replaces_only_selected_cells" % scenario)
	if not bool(patched_cells_result.get("valid", false)):
		_failures.append("patch:%s" % String(patched_cells_result.get("reason", "unknown")))
		_finish()
		return
	var patched_cells: Dictionary = patched_cells_result.cells
	var patched_arrays := _flatten_cells(patched_cells)
	var full_topology: Dictionary = fixture._topology_metrics(patched_cells, patched_arrays.positions)
	var interface_metrics: Dictionary = fixture._interface_metrics(patched_cells)
	var all_cell_ids: Array[int] = []
	for y in range(Fixture.CELL_DIMS.y):
		for z in range(Fixture.CELL_DIMS.z):
			for x in range(Fixture.CELL_DIMS.x):
				all_cell_ids.append(fixture._cell_id(Vector3i(x, y, z)))
	var original_whole_mesh: Dictionary = repair.extract_local_mesh(fixture, built.cells, all_cell_ids)
	var whole_mesh: Dictionary = repair.extract_local_mesh(fixture, patched_cells, all_cell_ids)
	var original_component_count: int = repair._face_component_count(original_whole_mesh.faces)
	var whole_component_count: int = repair._face_component_count(whole_mesh.faces)
	var whole_winding_metrics: Dictionary = repair.edge_orientation_metrics(whole_mesh)
	_check(int(full_topology.internal_open_edge_crack_count) == 0, "full_zero_edit_mesh_has_zero_internal_open_edges")
	_check(int(full_topology.degenerate_triangle_count) == 0, "full_zero_edit_mesh_has_zero_degenerate_triangles_at_frozen_threshold")
	_check(int(full_topology.nonmanifold_edge_count) == 0, "full_zero_edit_mesh_has_zero_nonmanifold_edges")
	_check(int(whole_winding_metrics.same_winding_edges) == 0, "full_zero_edit_mesh_has_compatible_triangle_winding")
	_check(whole_component_count == original_component_count, "local_repair_preserves_full_mesh_surface_component_count")
	_check(int(interface_metrics.interfaces_with_nonmatching_extracted_contours) == 0,
		"full_zero_edit_cell_interfaces_have_matching_extracted_contours")
	_check(int(interface_metrics.duplicate_coplanar_surface_interfaces) == 0,
		"full_zero_edit_has_no_duplicate_coplanar_interfaces")
	_check(int(interface_metrics.strict_t_junction_vertex_on_contour_segment_count) == 0,
		"full_zero_edit_interfaces_have_no_T_junctions")
	var diameter: float = _vertical_diameter(func(point: Vector3) -> float:
		return Transition.sample_canonical(SEED, point, snapshot), _cave_center(10.0))
	_check(absf(diameter - EXPECTED_UNEDITED_VERTICAL_OPENING) <= 0.000001,
		"canonical_zero_edit_opening_is_1_75_world_units")
	var single_mesh := {"positions": patched_arrays.positions, "normals": patched_arrays.normals,
		"triangle_count": patched_arrays.positions.size() / 3, "stats": {"topology": full_topology,
		"actual_cell_interface_contours": interface_metrics}}
	var meshes: Dictionary = {}
	for approach in APPROACHES: meshes[String(approach)] = single_mesh
	var collider_start_usec := Time.get_ticks_usec()
	var collider: Dictionary = await _physics_proxy_metrics(meshes, snapshot)
	var collider_elapsed_usec := Time.get_ticks_usec() - collider_start_usec
	_check(String(collider.get("status", "")) == "MEASURED_TEST_ONLY_CONCAVE_POLYGON_PROXIES",
		"%s_disposable_collider_proxy_available" % scenario)
	_check(int(collider.get("ray_query_count", -1)) == 72, "%s_preserves_all_72_frozen_ray_queries" % scenario)
	_check(int(collider.get("physics_vs_two_sided_triangle_hit_mismatches_with_shape_backface_collision_enabled", -1)) == 0,
		"%s_two_sided_collider_matches_independent_triangle_oracle_for_all_rays" % scenario)
	_check(int(collider.get("physics_vs_two_sided_triangle_hit_mismatches_with_default_one_sided_shape", -1)) == 33,
		"%s_one_sided_control_retains_historical_33_reverse_ray_misses" % scenario)
	var two_sided_canonical_mismatches := 0
	for ray_record_value in collider.get("ray_hit_records", []):
		var ray_record: Dictionary = ray_record_value
		if bool(ray_record.shape_backface_collision_enabled_hit) != bool(ray_record.expected_hit):
			two_sided_canonical_mismatches += 1
	_check(two_sided_canonical_mismatches == 0, "%s_two_sided_proxy_matches_canonical_hit_miss_oracle" % scenario)
	var field_geometry: Dictionary = _field_metrics(fixture, "A_conforming_propagation", snapshot)
	if scenario == "zero_edit":
		_check(absf(diameter - EXPECTED_UNEDITED_VERTICAL_OPENING) <= 0.000001,
			"canonical_zero_edit_opening_is_1_75_world_units")
		_check(int(field_geometry.centerline_open_samples) == 31, "zero_edit_canonical_centerline_remains_open_at_all_frozen_slices")
	var scenario_id := "P3.1.R7.%s.v1" % scenario.to_upper()
	var scenario_record := {"scenario": scenario, "scenario_id": scenario_id, "scenario_version": scenario_id,
		"seed": SEED, "ledger_revision": snapshot.get("revision", -1),
		"operation_count": snapshot.get("centers", PackedVector3Array()).size(),
		"input_manifest_canonical_json": input_canonical_json,
		"input_manifest_sha256": _sha256(input_canonical_json.to_utf8_buffer()),
		"ordered_commands": input_payload.get("ordered_commands", []),
		"canonical_vertical_opening_world": diameter, "field_geometry": field_geometry,
		"source_triangle_count_inclusive": built.triangle_count,
		"source_mesh_sha256": _mesh_sha256(built.positions, built.normals),
		"repaired_mesh_sha256": _mesh_sha256(patched_arrays.positions, patched_arrays.normals),
		"repair_strategy": "A_edge_collapse", "local_strategy_A": strategy_a,
		"local_strategy_B": strategy_b, "local_strategy_C": strategy_c,
		"local_before": local_metrics_before, "full_topology": full_topology,
		"interface_metrics": interface_metrics, "full_winding_metrics": whole_winding_metrics,
		"surface_geometry": fixture._canonical_surface_metrics(patched_arrays.positions, patched_arrays.normals),
		"face_component_count_before": original_component_count, "face_component_count_after": whole_component_count,
		"collider": collider, "two_sided_canonical_hit_mismatches": two_sided_canonical_mismatches,
		"timing_usec": {"full_build": build_elapsed_usec, "local_repair": local_repair_elapsed_usec,
			"collider": collider_elapsed_usec, "total": Time.get_ticks_usec() - gate_start_usec},
		"scope": "one frozen test scenario per invocation; test-only; no product tolerance adopted; the inherited 72-ray matrix uses the selected mesh in each legacy approach slot"}
	_scenario_records.append(scenario_record)
	print("R72_SCENARIO " + JSON.stringify(scenario_record))
	var required_topology_pass := _failures.is_empty()
	var final := {"suite": "P3_1_R7_2_SCENARIO_GATE", "status": "PASS" if required_topology_pass else "FAIL",
		"scenario_count": 1, "assertions": _assertions, "failures": _failures,
		"duration_usec": Time.get_ticks_usec() - gate_start_usec,
		"note": "C is recorded as rejected for zero-edit; A is the selected full-mesh repair; collider runs preserve the frozen 72-query schedule"}
	print("R72_RESULT " + JSON.stringify(final))
	quit(0 if required_topology_pass else 1)

func _replace_local_cells(source_cells: Dictionary, strategy: Dictionary, repair: RefCounted) -> Dictionary:
	if not bool(strategy.get("valid", false)):
		return {"valid": false, "reason": "selected_local_strategy_invalid"}
	if bool(strategy.get("no_op", false)):
		return {"valid": true, "cells": source_cells.duplicate(), "replaced_cell_count": 0,
			"affected_cell_count_with_triangles": 0}
	var local: Dictionary = strategy.strategy_attempt.mesh
	var vertices: Array[Vector3] = local.vertices
	var grouped: Dictionary = {}
	for face_value in local.faces:
		var face: Dictionary = face_value
		var cell_id := int(face.cell)
		var data: Dictionary = grouped.get(cell_id, {"vertices": PackedVector3Array(), "normals": PackedVector3Array()})
		var ids: Array = face.v
		var a: Vector3 = vertices[int(ids[0])]; var b: Vector3 = vertices[int(ids[1])]; var c: Vector3 = vertices[int(ids[2])]
		var cross := (b - a).cross(c - a)
		if cross.length_squared() <= RepairR72.AREA2_LIMIT_SQUARED:
			return {"valid": false, "reason": "face_below_frozen_threshold_during_cell_grouping"}
		var normal := cross.normalized()
		var face_vertices: PackedVector3Array = data.vertices
		var face_normals: PackedVector3Array = data.normals
		face_vertices.append_array(PackedVector3Array([a, b, c]))
		face_normals.append_array(PackedVector3Array([normal, normal, normal]))
		data.vertices = face_vertices; data.normals = face_normals
		grouped[cell_id] = data
	var cells: Dictionary = source_cells.duplicate()
	for cell_id_value in local.selected:
		var cell_id := int(cell_id_value)
		cells.erase(cell_id)
	for cell_id_value in grouped:
		var cell_id := int(cell_id_value)
		var data: Dictionary = grouped[cell_id]
		cells[cell_id] = {"vertices": data.vertices, "normals": data.normals,
			"triangle_count": data.vertices.size() / 3}
	return {"valid": true, "cells": cells, "replaced_cell_count": local.selected.size(),
		"affected_cell_count_with_triangles": grouped.size()}

func _flatten_cells(cells: Dictionary) -> Dictionary:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for cell_id_value in cells:
		var geometry: Dictionary = cells[cell_id_value]
		positions.append_array(geometry.vertices)
		normals.append_array(geometry.normals)
	return {"positions": positions, "normals": normals}

func _finish() -> void:
	var final := {"suite": "P3_1_R7_2_SCENARIO_GATE", "status": "FAIL", "scenario_count": 0,
		"assertions": _assertions, "failures": _failures, "note": "stopped during fail-closed preflight"}
	print("R72_RESULT " + JSON.stringify(final))
	quit(1)


func _finish_diagnostic(complete: bool, diagnostic: Dictionary) -> void:
	var result := {"suite": "P3_1_R7_3_CARVE_FAILURE_DIAGNOSTIC",
		"status": "DIAGNOSTIC_COMPLETE" if complete else "DIAGNOSTIC_FAILED",
		"scenario": "cave_wall_carve", "full_scenario_gate_executed": false,
		"scenario_count": 0, "assertions": _assertions, "failure_diagnosed": diagnostic.get("first_failed_invariant", ""),
		"note": "diagnostic-only frozen input reconstruction; no collider or full scenario acceptance gate was run"}
	print("R73_DIAGNOSTIC_RESULT " + JSON.stringify(result))
	quit(0 if complete else 1)


func _make_r73_failure_diagnostic(scenario: String, snapshot: Dictionary, input_payload: Dictionary,
		input_canonical_json: String, fixture: RefCounted, built: Dictionary, focus_ids: Array[int],
		local_before: Dictionary, local_metrics_before: Dictionary, strategy_a: Dictionary,
		gate_start_usec: int, build_elapsed_usec: int, repair_elapsed_usec: int) -> Dictionary:
	var diagnostic: Dictionary = strategy_a.get("diagnostic", {})
	var source_paths := [
		"res://tests/prototypes/p3_1_r7_2_zero_edit_gate.gd",
		"res://tests/prototypes/p3_1_r7_2_local_retriangulation.gd",
		"res://tests/prototypes/p3_1_r7_conforming_adaptive_diagnostic.gd",
		"res://tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd",
		"res://scripts/terrain/marching_tetrahedra.gd",
		"res://scripts/terrain/sdf_world.gd",
		"res://scripts/terrain/sdf_brush_edit_state.gd",
		"res://scripts/experiments/lod01_transition_fixture.gd"]
	var source_hashes: Dictionary = {}
	var missing_sources: Array[String] = []
	for path in source_paths:
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty() and not FileAccess.file_exists(path):
			missing_sources.append(path)
		else:
			source_hashes[path] = _sha256_bytes(bytes)
	var patch_reduction: Dictionary = _reduce_failing_patch(fixture, built.cells, focus_ids) \
		if String(strategy_a.get("strategy", "")) == "A_edge_collapse" else {
			"status": "NOT_RUN_FOR_SEPARATE_B_ALTERNATIVE", "reduced_focus_ids": []}
	var failed := String(diagnostic.get("first_failed_invariant", ""))
	var command_centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
	var command_radii: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
	var command_modes: PackedByteArray = snapshot.get("modes", PackedByteArray())
	var commands: Array[Dictionary] = []
	for index in range(command_centers.size()):
		var center: Vector3 = command_centers[index]
		commands.append({"sequence": index, "mode_byte": int(command_modes[index]),
			"center_world": [center.x, center.y, center.z], "radius_world": float(command_radii[index])})
	return {"complete": failed != "" and missing_sources.is_empty(),
		"scenario_id": "P3.1.R7.CAVE_WALL_CARVE.v1", "scenario_version": "P3.1.R7.CAVE_WALL_CARVE.v1",
		"scenario": scenario, "seed": SEED, "generator_version": Field.GENERATOR_VERSION,
		"region": [REGION.x, REGION.y], "revision": snapshot.get("revision", -1),
		"operation_count": command_centers.size(), "ordered_commands": commands,
		"input_canonical_json": input_canonical_json,
		"input_sha256": _sha256_bytes(input_canonical_json.to_utf8_buffer()),
		"source_sha256_by_path": source_hashes, "missing_source_paths": missing_sources,
		"canonical_source_mesh_sha256": _mesh_sha256(built.positions, built.normals),
		"source_triangle_count": built.triangle_count,
		"scenario_wide_subthreshold_focus_cell_ids": focus_ids,
		"selected_focus_cell_ids": diagnostic.get("selected_focus_cell_ids", focus_ids),
		"selected_cell_ids": diagnostic.get("selected_cell_ids", []),
		"cell_ownership": diagnostic.get("cell_ownership", []),
		"source_face_counts": diagnostic.get("source_face_counts", {}),
		"original_patch_boundary_signature": diagnostic.get("original_patch_boundary_signature", []),
		"attempted_patch_boundary_signature": diagnostic.get("attempted_patch_boundary_signature", []),
		"original_patch_boundary_records": diagnostic.get("original_patch_boundary_records", []),
		"attempted_patch_boundary_records": diagnostic.get("attempted_patch_boundary_records", []),
		"candidate_edge_collapses": diagnostic.get("candidate_edge_collapses", []),
		"accepted_edge_collapses": diagnostic.get("accepted_edge_collapses", []),
		"rejection_reasons": diagnostic.get("strategy_rejection_reasons", []),
		"vertex_movements": diagnostic.get("vertex_movements", []),
		"changed_triangles": diagnostic.get("changed_triangles", []),
		"removed_triangle_ids": diagnostic.get("removed_triangle_ids", []),
		"before_metrics": diagnostic.get("before_metrics", local_metrics_before), "after_metrics": diagnostic.get("after_metrics", {}),
		"face_component_change": diagnostic.get("face_component_change", 0),
		"first_failed_invariant": failed, "strategy_valid": bool(strategy_a.get("valid", false)),
		"strategy_attempt_summary": _strategy_attempt_summary(strategy_a.get("strategy_attempt", {})),
		"patch_reduction": patch_reduction,
		"timing_usec": {"full_build": build_elapsed_usec, "local_repair": repair_elapsed_usec,
			"diagnostic_total": Time.get_ticks_usec() - gate_start_usec},
		"execution_boundary": "diagnostic only; did not run collider, full scenario acceptance, or retry prior complete scenario"}


func _reduce_failing_patch(fixture: RefCounted, cells: Dictionary, original_focus: Array[int]) -> Dictionary:
	var focus: Array[int] = original_focus.duplicate()
	var attempts: Array[Dictionary] = []
	var reducer := RepairR72.new()
	var budget := 64
	var removed_on_last_pass := true
	while removed_on_last_pass and attempts.size() < budget:
		removed_on_last_pass = false
		var cursor := 0
		while cursor < focus.size() and attempts.size() < budget:
			var candidate := focus.duplicate()
			var removed_focus_cell: int = int(candidate[cursor])
			candidate.remove_at(cursor)
			if candidate.is_empty():
				attempts.append({"removed_focus_cell": removed_focus_cell, "trial_focus_ids": candidate,
					"status": "NOT_A_REPRODUCING_PATCH", "reason": "empty_focus_set"})
				cursor += 1
				continue
			var patch: Dictionary = reducer.extract_local_mesh(fixture, cells, candidate)
			var patch_metrics: Dictionary = reducer.metrics(fixture, patch)
			if int(patch_metrics.get("nonzero_subthreshold_triangles", 0)) == 0:
				attempts.append({"removed_focus_cell": removed_focus_cell, "trial_focus_ids": candidate,
					"status": "NOT_A_REPRODUCING_PATCH", "reason": "no_nonzero_subthreshold_source_face"})
				cursor += 1
				continue
			var result: Dictionary = reducer.run_strategy(fixture, patch, "A_edge_collapse")
			var details: Dictionary = result.get("diagnostic", {})
			attempts.append({"removed_focus_cell": removed_focus_cell, "trial_focus_ids": candidate,
				"status": "FAILURE_PRESERVED" if not bool(result.get("valid", false)) else "FAILURE_REMOVED",
				"first_failed_invariant": details.get("first_failed_invariant", ""),
				"source_face_count": patch.faces.size(), "selected_cell_ids": details.get("selected_cell_ids", []),
				"before_metrics": details.get("before_metrics", {}), "after_metrics": details.get("after_metrics", {}),
				"candidate_edge_collapses": details.get("candidate_edge_collapses", [])})
			if not bool(result.get("valid", false)):
				focus = candidate
				removed_on_last_pass = true
				break
			cursor += 1
	return {"original_focus_ids": original_focus, "reduced_focus_ids": focus,
		"one_minimal_under_deterministic_single_cell_deletion": not removed_on_last_pass and attempts.size() < budget,
		"attempt_count": attempts.size(), "attempt_budget": budget, "attempts": attempts,
		"note": "greedy deletion minimality is bounded and does not claim a globally minimum patch"}


func _strategy_attempt_summary(strategy_attempt: Dictionary) -> Dictionary:
	var summary: Dictionary = {}
	for key in ["valid", "reason", "accepted_collapses", "candidate_edges", "rejected_reasons",
			"first_rejection", "max_vertex_displacement_world", "before_metrics", "after_metrics"]:
		if strategy_attempt.has(key): summary[key] = strategy_attempt[key]
	return summary


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK: return "HASH_START_FAILED"
	context.update(bytes)
	return context.finish().hex_encode()

func _requested_scenario() -> String:
	for argument in OS.get_cmdline_user_args():
		var value := String(argument)
		if value.begins_with("--scenario-id="):
			return value.trim_prefix("--scenario-id=")
	return "zero_edit"


func _requested_diagnostic_strategy() -> String:
	for argument in OS.get_cmdline_user_args():
		var value := String(argument)
		if value.begins_with("--repair-strategy="):
			return value.trim_prefix("--repair-strategy=")
	return "A_edge_collapse"

func _subthreshold_cell_ids(cells: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for cell_id_value in cells:
		var cell_id := int(cell_id_value)
		var geometry: Dictionary = cells[cell_id]
		var vertices: PackedVector3Array = geometry.vertices
		for index in range(0, vertices.size(), 3):
			var cross := (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index])
			if cross.length_squared() > 0.0 and cross.length_squared() <= RepairR72.AREA2_LIMIT_SQUARED:
				ids.append(cell_id)
				break
	ids.sort()
	return ids
