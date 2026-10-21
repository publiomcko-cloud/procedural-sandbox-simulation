extends SceneTree

## Opt-in one-scenario-at-a-time B1-1 experimental runner. It is never loaded
## by the playable scene, project startup, or scripts/validate.ps1.
const Contract := preload("res://tests/p1_1b_benchmark_contract.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const CanonicalField := preload("res://scripts/terrain/sdf_world.gd")
const LodFixture := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const TerrainScene := preload("res://scenes/terrain_demo.tscn")

const HARNESS_VERSION := "P1.1B-B1-1.v1"
const READINESS_GUARD_USEC := 120000000
const PROCESS_GUARD_USEC := 1800000000
const TUNNEL_SLICE_VISITS := 16384
const ASSERT_TOLERANCE := 0.00001
const SHARED_NORMAL_TOLERANCE := 0.000001

class FrameCapture:
	extends Node
	const MAX_SAMPLES := 10000
	var frame_interval_usec: Array[int] = []
	var total_frame_callbacks := 0
	func _process(delta: float) -> void:
		total_frame_callbacks += 1
		if frame_interval_usec.size() < MAX_SAMPLES:
			frame_interval_usec.append(maxi(0, roundi(delta * 1000000.0)))

var _clock_origin_usec := 0
var _run_id := ""
var _scenario_id := ""
var _scenario_parent_event_id := ""
var _event_counter := 0
var _failure_count := 0
var _scenario_status := "NOT_STARTED"
var _manifest: Dictionary = {}
var _last_log_cost_usec := -1
var _last_log_kind := ""
var _last_event_id := ""
var _frame_capture: FrameCapture


func _initialize() -> void:
	_clock_origin_usec = Time.get_ticks_usec()
	_run_id = "%d-%d" % [OS.get_process_id(), _clock_origin_usec]
	call_deferred("_run")


func _run() -> void:
	_frame_capture = FrameCapture.new()
	_frame_capture.name = "P1B1FrameCapture"
	root.add_child(_frame_capture)
	var parsed_args := _parse_args(OS.get_cmdline_user_args())
	if not parsed_args.get("ok", false):
		_emit_event("invocation_failure", {
			"reason_code": String(parsed_args.get("reason", "invalid_arguments")),
			"usage": "godot --headless --path game --script res://tests/p1_1b_benchmark_harness.gd -- --scenario-id <FROZEN_ID>",
		})
		quit(2)
		return
	var version_info: Dictionary = Engine.get_version_info()
	var engine_version := String(version_info.get("string", ""))
	if engine_version != "4.7.2.stable.official.ed1daf0bf":
		_emit_event("invocation_failure", {
			"reason_code": "godot_version_mismatch",
			"expected_engine": "4.7.2.stable.official.ed1daf0bf",
			"actual_engine": engine_version,
		})
		quit(2)
		return
	var verification: Dictionary = Contract.verify_manifest()
	if not verification.get("ok", false):
		_emit_event("invocation_failure", {
			"reason_code": "manifest_verification_failed",
			"manifest_reason": verification.get("reason", "unknown"),
			"manifest_expected_sha256": verification.get("expected_sha256", ""),
			"manifest_actual_sha256": verification.get("actual_sha256", ""),
		})
		quit(2)
		return
	_manifest = verification["manifest"]
	_scenario_id = String(parsed_args["scenario_id"])
	var scenario := _find_scenario(_scenario_id)
	if scenario.is_empty():
		_emit_event("invocation_failure", {"reason_code": "unknown_or_not_frozen_scenario"})
		quit(2)
		return
	if String(scenario.get("status", "")) != "FROZEN":
		_emit_event("invocation_failure", {"reason_code": "scenario_not_frozen"})
		quit(2)
		return
	_scenario_status = "RUNNING"
	var start_event := _emit_event("scenario_started", {
		"scenario_type": scenario.get("type", ""),
		"scenario_manifest_sha256": verification["sha256"],
		"scenario_manifest_bytes": verification["byte_count"],
		"scenario_contract_main_sha": _manifest.get("contract_main_sha", ""),
		"source_commit_sha": "NOT_RECORDED_BY_HARNESS_VERIFY_GIT_HEAD_EXTERNALLY",
		"godot_version": engine_version,
		"clock": "Time.get_ticks_usec process-local monotonic microseconds",
		"raw_output": "stdout_jsonl_only_artifact_retention_owner_to_define",
	})
	_scenario_parent_event_id = String(start_event["event_id"])
	var scenario_started := Time.get_ticks_usec()
	match String(scenario.get("type", "")):
		"ledger_replay", "ledger_commands":
			await _run_ledger_scenario(scenario)
		"lod_transition":
			await _run_lod_scenario(scenario)
		"tunnel_connectivity":
			await _run_tunnel_scenario(scenario)
		"streaming":
			await _run_streaming_scenario(scenario)
		"edited_reload":
			await _run_edited_reload_scenario(scenario)
		_:
			_fail("unsupported_scenario_type")
	if _scenario_status == "RUNNING":
		_scenario_status = "PASS" if _failure_count == 0 else "FAIL"
	_emit_event("scenario_complete", {
		"status": _scenario_status,
		"failure_count": _failure_count,
		"elapsed_usec": Time.get_ticks_usec() - scenario_started,
		"latency_percentiles": "nearest_rank_ceil_p_n_per_process_no_cross_process_pooling",
		"gpu_completion": "NOT_AVAILABLE",
		"presented_frame": "NOT_AVAILABLE",
		"process_rss": "NOT_AVAILABLE",
		"vram": "NOT_AVAILABLE",
		"process_memory_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"engine_process_frame_intervals_usec": _percentiles(_frame_capture.frame_interval_usec),
		"engine_process_frame_sample_count": _frame_capture.frame_interval_usec.size(),
		"engine_process_frame_callback_count": _frame_capture.total_frame_callbacks,
		"engine_process_frame_samples_usec": _frame_capture.frame_interval_usec,
		"presented_frame_metrics": "NOT_AVAILABLE_HEADLESS_OR_UNCORRELATED",
	})
	if _last_log_cost_usec >= 0:
		_emit_event("logger_overhead_observation", {
			"measured_record_kind": _last_log_kind,
			"measured_record_encode_and_print_usec": _last_log_cost_usec,
		})
	quit(0 if _scenario_status == "PASS" else 1)


func _parse_args(arguments: PackedStringArray) -> Dictionary:
	if arguments.size() != 2 or arguments[0] != "--scenario-id" or arguments[1].is_empty():
		return {"ok": false, "reason": "exactly_one_scenario_id_is_required"}
	return {"ok": true, "scenario_id": arguments[1]}


func _find_scenario(id: String) -> Dictionary:
	for scenario_value in _manifest.get("scenarios", []):
		var scenario: Dictionary = scenario_value
		if String(scenario.get("id", "")) == id:
			return scenario.duplicate(true)
	return {}


func _emit_event(kind: String, fields: Dictionary = {}) -> Dictionary:
	_event_counter += 1
	var now := Time.get_ticks_usec()
	var event := {
		"schema_version": 1,
		"record_type": "event",
		"event_kind": kind,
		"event_id": "%s-e%06d" % [_run_id, _event_counter],
		"parent_event_id": _scenario_parent_event_id,
		"run_id": _run_id,
		"process_id": OS.get_process_id(),
		"scenario_id": _scenario_id,
		"process_clock_origin_usec": _clock_origin_usec,
		"process_elapsed_usec": now - _clock_origin_usec,
		"event_clock_usec": now,
		"previous_record_encode_and_print_usec": _last_log_cost_usec,
		"engine_version": String(Engine.get_version_info().get("string", "")),
	}
	event.merge(fields, true)
	var serialize_started := Time.get_ticks_usec()
	var line := JSON.stringify(event, "", true, true)
	print("P1B1_JSONL " + line)
	_last_log_cost_usec = Time.get_ticks_usec() - serialize_started
	_last_log_kind = kind
	_last_event_id = String(event["event_id"])
	return event


func _fail(reason_code: String, details: Dictionary = {}) -> void:
	_failure_count += 1
	_emit_event("scenario_failure", {"reason_code": reason_code, "details": details})


func _mark_timeout(stage: String, started_usec: int, guard_usec: int) -> void:
	_scenario_status = "TIMEOUT"
	_failure_count += 1
	_emit_event("timeout_censored", {
		"reason_code": "protective_timeout",
		"stage": stage,
		"right_censored": true,
		"lower_bound_elapsed_usec": Time.get_ticks_usec() - started_usec,
		"protective_guard_usec": guard_usec,
		"latency_sample_completed": false,
	})


func _process_guard_exceeded() -> bool:
	return Time.get_ticks_usec() - _clock_origin_usec >= PROCESS_GUARD_USEC


func _run_ledger_scenario(scenario: Dictionary) -> void:
	var seed_value := int(_manifest["global_seed"])
	var ledger: RefCounted = BrushState.new(seed_value, int(_manifest["generator_version"]))
	var commands := Contract.build_commands(scenario, _manifest)
	var actual_commands: Array[Dictionary] = []
	var admission_usec: Array[int] = []
	var admission_started := Time.get_ticks_usec()
	var expected_count := int(scenario.get("operation_count", commands.size()))
	if commands.size() != expected_count:
		_fail("manifest_command_count_mismatch", {"expected": expected_count, "generated": commands.size()})
		return
	for index in range(commands.size()):
		if _process_guard_exceeded():
			_mark_timeout("ledger_admission", admission_started, PROCESS_GUARD_USEC)
			return
		var command: Dictionary = commands[index]
		var center_mm: Array = command["center_mm"]
		var center := Vector3(float(center_mm[0]) / 1000.0, float(center_mm[1]) / 1000.0, float(center_mm[2]) / 1000.0)
		var mode := BrushState.Mode.CARVE if String(command["mode"]) == "CARVE" else BrushState.Mode.FILL
		var command_started := Time.get_ticks_usec()
		var accepted: bool = ledger.add_sphere(mode, center, float(int(command["radius_mm"])) / 1000.0)
		var command_elapsed := Time.get_ticks_usec() - command_started
		admission_usec.append(command_elapsed)
		if not accepted:
			_fail("canonical_ledger_rejected_frozen_command", {
				"command_index": index,
				"ledger_reason": ledger.last_rejection_reason,
				"command": command,
			})
			return
		var operation := ledger.get_last_operation_snapshot()
		var actual_command: Dictionary = Contract.command_from_operation(operation)
		actual_commands.append(actual_command)
		var expected_support: Array[String] = Contract.expected_support_for_command(scenario, command)
		var support: Array[String] = Contract.operation_region_keys(operation, "support_regions")
		var rebuild: Array[String] = Contract.operation_region_keys(operation, "rebuild_regions")
		var dependencies: Array[String] = Contract.operation_region_keys(operation, "dependency_regions")
		if support != expected_support:
			_fail("support_or_rebuild_keys_differ_from_frozen_contract", {
				"command_index": index,
				"expected_support": expected_support,
				"actual_support": support,
			})
			return
		var rebuild_covers_support := true
		for key in support:
			if not rebuild.has(key):
				rebuild_covers_support = false
		if not rebuild_covers_support:
			_fail("rebuild_set_omits_geometric_support", {
				"command_index": index,
				"support": support,
				"rebuild": rebuild,
			})
			return
		var expected_dependencies: Array[String] = []
		for key in rebuild:
			if not support.has(key):
				expected_dependencies.append(key)
		expected_dependencies.sort()
		if dependencies != expected_dependencies:
			_fail("dependency_keys_inconsistent_with_rebuild_set", {
				"expected": expected_dependencies,
				"actual": dependencies,
			})
			return
		_emit_event("ledger_command_accepted", {
			"sequence": operation["sequence"],
			"revision": operation["revision"],
			"mode": command["mode"],
			"center_mm": command["center_mm"],
			"radius_mm": command["radius_mm"],
			"support_region_keys": support,
			"dependency_region_keys": dependencies,
			"rebuild_region_keys": rebuild,
			"acceptance_elapsed_usec": command_elapsed,
			"command_list_sha256_prefix_state": Contract.command_list_sha256(actual_commands),
		})
	var expected_sha := Contract.command_list_sha256(commands)
	var actual_sha := Contract.command_list_sha256(actual_commands)
	if actual_sha != expected_sha:
		_fail("accepted_command_list_hash_mismatch", {"expected": expected_sha, "actual": actual_sha})
		return
	if ledger.get_edit_count() != expected_count or ledger.revision != expected_count:
		_fail("ledger_count_or_revision_mismatch", {
			"expected_count_revision": expected_count,
			"actual_count": ledger.get_edit_count(),
			"actual_revision": ledger.revision,
		})
		return
	var ledger_admission_elapsed := Time.get_ticks_usec() - admission_started
	var parity_started := Time.get_ticks_usec()
	var parity: Dictionary = await _compare_ledger_query_parity(ledger, commands)
	if not parity.get("ok", false):
		_fail("complete_and_filtered_sdf_replay_differ", parity)
		return
	_emit_event("ledger_replay_result", {
		"status": "PASS",
		"operation_count": ledger.get_edit_count(),
		"revision": ledger.revision,
		"last_sequence": ledger.get_last_sequence(),
		"command_list_sha256": actual_sha,
		"acceptance_elapsed_percentiles_usec": _percentiles(admission_usec),
		"acceptance_complete_operation_count": admission_usec.size(),
		"ledger_admission_total_elapsed_usec": ledger_admission_elapsed,
		"query_parity_elapsed_usec": Time.get_ticks_usec() - parity_started,
		"query_parity": parity,
		"edit_geometric_scoring": "NOT_RUN_OR_APPROVED_BY_THIS_LEDGER_REPLAY",
		"gpu_completion": "NOT_AVAILABLE",
	})


func _compare_ledger_query_parity(ledger: RefCounted, commands: Array[Dictionary]) -> Dictionary:
	var full_snapshot: Dictionary = ledger.get_meshing_snapshot()
	var offsets: Array = _manifest["parity_probe_offsets_mm"]
	var centers: Array = []
	if commands.is_empty():
		centers.append(_manifest["empty_parity_center_mm"])
	else:
		for command in commands:
			centers.append(command["center_mm"])
	var probe_positions_mm: Array = []
	var snapshot_cache: Dictionary = {}
	var candidate_total := 0
	var compared := 0
	var per_probe_elapsed_usec: Array[int] = []
	var probe_index := 0
	var snapshot_build_usec := 0
	for center_mm_value in centers:
		var center_mm: Array = center_mm_value
		for offset_value in offsets:
			var offset_mm: Array = offset_value
			var sample_mm := Vector3i(
				int(center_mm[0]) + int(offset_mm[0]),
				int(center_mm[1]) + int(offset_mm[1]),
				int(center_mm[2]) + int(offset_mm[2])
			)
			probe_positions_mm.append([sample_mm.x, sample_mm.y, sample_mm.z])
			var world := Vector3(float(sample_mm.x) / 1000.0, float(sample_mm.y) / 1000.0, float(sample_mm.z) / 1000.0)
			var mapped: Dictionary = Spatial.world_to_region_local(world)
			if not mapped.get("valid", false):
				return {"ok": false, "reason_code": "parity_probe_world_mapping_invalid", "probe_index": probe_index}
			var global_cell := Vector2i(floori(world.x / Grid.SAMPLE_STEP), floori(world.z / Grid.SAMPLE_STEP))
			var region_key: Vector2i = mapped["region_key"]
			var local_cell: Vector2i = Spatial.region_local_cell(global_cell.x, global_cell.y)
			var chunk_coordinate: Vector2i = Spatial.chunk_for_region_cell(local_cell)
			if chunk_coordinate.x < 0:
				return {"ok": false, "reason_code": "parity_probe_chunk_mapping_invalid", "probe_index": probe_index}
			var cache_key := "%s/%d,%d" % [Contract.region_id(region_key), chunk_coordinate.x, chunk_coordinate.y]
			if not snapshot_cache.has(cache_key):
				var snapshot_started := Time.get_ticks_usec()
				var filtered: Dictionary = ledger.get_meshing_snapshot_for_chunk(region_key, chunk_coordinate)
				snapshot_build_usec += Time.get_ticks_usec() - snapshot_started
				snapshot_cache[cache_key] = filtered
				candidate_total += int(filtered.get("candidate_operation_count", 0))
			var filtered_snapshot: Dictionary = snapshot_cache[cache_key]
			var sample_started := Time.get_ticks_usec()
			var expected: float = BrushState.sample_density_snapshot(
				ledger.world_seed, region_key, mapped["local_position"], false, full_snapshot
			)
			var actual: float = BrushState.sample_density_snapshot(
				ledger.world_seed, region_key, mapped["local_position"], false, filtered_snapshot
			)
			per_probe_elapsed_usec.append(Time.get_ticks_usec() - sample_started)
			if expected != actual:
				return {
					"ok": false,
					"reason_code": "exact_sdf_value_mismatch",
					"probe_index": probe_index,
					"probe_position_mm": [sample_mm.x, sample_mm.y, sample_mm.z],
					"full_value": expected,
					"filtered_value": actual,
					"candidate_count": filtered_snapshot.get("candidate_operation_count", 0),
				}
			compared += 1
			probe_index += 1
			if probe_index % 256 == 0:
				await process_frame
				if _process_guard_exceeded():
					return {"ok": false, "reason_code": "process_guard_exceeded_during_parity", "compared": compared}
	var probe_sha := Contract.command_list_sha256(_probe_commands(probe_positions_mm))
	return {
		"ok": true,
		"sample_count": compared,
		"probe_positions_sha256": probe_sha,
		"snapshot_build_elapsed_usec": snapshot_build_usec,
		"probe_positions_mm": probe_positions_mm,
		"per_probe_elapsed_usec": per_probe_elapsed_usec,
		"per_probe_latency_percentiles_usec": _percentiles(per_probe_elapsed_usec),
		"snapshot_cache_count": snapshot_cache.size(),
		"candidate_operation_count_sum_per_cached_chunk": candidate_total,
		"comparison": "exact_float_equality_complete_ordered_ledger_vs_chunk_filtered_snapshot",
	}


func _probe_commands(points_mm: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(points_mm.size()):
		result.append({
			"sequence": index,
			"mode": "PROBE",
			"center_mm": points_mm[index],
			"radius_mm": 0,
		})
	return result


func _run_lod_scenario(scenario: Dictionary) -> void:
	var origin_values: Array = scenario["origin_lod0_lattice"]
	var origin := Vector3i(origin_values[0], origin_values[1], origin_values[2])
	var base := Vector3(origin) * LodFixture.LOD0_STEP
	var sampler := func(point: Vector3) -> float:
		var local := point - base
		return 0.38 * local.x + 0.31 * local.y + 0.27 * local.z + 0.18 * local.x * local.y - 0.45
	var faces: Array[int] = []
	for face_value in scenario["face_mask"]:
		faces.append(int(face_value))
	var transition_started := Time.get_ticks_usec()
	var transition: Dictionary = LodFixture.build_transition_cell(
		int(_manifest["global_seed"]), origin, faces, {}, sampler
	)
	var transition_elapsed := Time.get_ticks_usec() - transition_started
	if not transition.get("valid", false):
		_fail("transition_fixture_build_failed", {"fixture_reason": transition.get("reason", "unknown")})
		return
	if not _mesh_is_finite_non_degenerate(transition):
		_fail("transition_mesh_nonfinite_or_degenerate")
		return
	var reference_build_usec := 0
	var seam_results: Array[Dictionary] = []
	for face in faces:
		var fine_origin := _adjacent_origin(origin, face)
		var fine_started := Time.get_ticks_usec()
		var fine_reference: Dictionary = LodFixture.build_uniform_reference_cell(
			int(_manifest["global_seed"]), fine_origin, 0, {}, sampler
		)
		reference_build_usec += Time.get_ticks_usec() - fine_started
		if not fine_reference.get("valid", false) or not _mesh_is_finite_non_degenerate(fine_reference):
			_fail("lod0_independent_reference_build_failed", {"face": face, "reason": fine_reference.get("reason", "")})
			return
		var fine_result := _compare_adjacent_meshes(transition, fine_reference, origin, fine_origin, face)
		fine_result["neighbor_lod"] = 0
		if not fine_result.get("ok", false):
			_fail("lod0_adjacent_seam_mismatch", fine_result)
			return
		seam_results.append(fine_result)
		var coarse_face := face ^ 1
		var coarse_origin := _adjacent_origin(origin, coarse_face)
		var coarse_started := Time.get_ticks_usec()
		var coarse_reference: Dictionary = LodFixture.build_uniform_reference_cell(
			int(_manifest["global_seed"]), coarse_origin, 1, {}, sampler
		)
		reference_build_usec += Time.get_ticks_usec() - coarse_started
		if not coarse_reference.get("valid", false) or not _mesh_is_finite_non_degenerate(coarse_reference):
			_fail("lod1_independent_reference_build_failed", {"face": coarse_face, "reason": coarse_reference.get("reason", "")})
			return
		var coarse_result := _compare_adjacent_meshes(transition, coarse_reference, origin, coarse_origin, coarse_face)
		coarse_result["neighbor_lod"] = 1
		if not coarse_result.get("ok", false):
			_fail("lod1_adjacent_seam_mismatch", coarse_result)
			return
		seam_results.append(coarse_result)
	_emit_event("lod_fixture_result", {
		"status": "PASS",
		"origin_lod0_lattice": [origin.x, origin.y, origin.z],
		"face_mask": faces,
		"transition_triangles": transition.get("triangle_count", 0),
		"transition_samples": transition.get("sample_count", 0),
		"transition_elapsed_usec": transition_elapsed,
		"transition_stage_timings_usec": transition.get("timings_usec", {}),
		"independent_reference_build_elapsed_usec": reference_build_usec,
		"adjacent_seam_results": seam_results,
		"array_mesh_publication": "NOT_APPLICABLE_CPU_TRIANGLE_FIXTURE",
		"edited_lod_geometry_scoring": "EXCLUDED_NOT_FROZEN",
	})


func _adjacent_origin(origin: Vector3i, face: int) -> Vector3i:
	var neighbor := origin
	var axis := int(face / 2)
	neighbor[axis] += -2 if face % 2 == 0 else 2
	return neighbor


func _mesh_is_finite_non_degenerate(result: Dictionary) -> bool:
	var vertices: PackedVector3Array = result.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = result.get("normals", PackedVector3Array())
	if vertices.size() == 0 or vertices.size() != normals.size() or vertices.size() % 3 != 0:
		return false
	for index in range(vertices.size()):
		if not vertices[index].is_finite() or not normals[index].is_finite():
			return false
	for index in range(0, vertices.size(), 3):
		if (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index]).length_squared() <= ASSERT_TOLERANCE * ASSERT_TOLERANCE:
			return false
	return true


func _compare_adjacent_meshes(
	transition: Dictionary,
	neighbor: Dictionary,
	transition_origin: Vector3i,
	neighbor_origin: Vector3i,
	face: int
) -> Dictionary:
	var axis := int(face / 2)
	var negative := face % 2 == 0
	var transition_min := Vector3(transition_origin) * LodFixture.LOD0_STEP
	var transition_max := transition_min + Vector3.ONE
	var neighbor_min := Vector3(neighbor_origin) * LodFixture.LOD0_STEP
	var neighbor_max := neighbor_min + Vector3.ONE
	var expected_plane := transition_min[axis] if negative else transition_max[axis]
	var contact := neighbor_max[axis] == expected_plane if negative else neighbor_min[axis] == expected_plane
	var disjoint := neighbor_max[axis] <= transition_min[axis] if negative else neighbor_min[axis] >= transition_max[axis]
	var tangents_match := true
	for tangent in range(3):
		if tangent == axis:
			continue
		if neighbor_min[tangent] != transition_min[tangent] or neighbor_max[tangent] != transition_max[tangent]:
			tangents_match = false
	if not contact or not disjoint or not tangents_match:
		return {
			"ok": false,
			"reason_code": "independent_neighbor_not_physically_adjacent",
			"face": face,
			"contact": contact,
			"interiors_disjoint": disjoint,
			"tangent_ranges_match": tangents_match,
			"transition_min": _vector_array(transition_min),
			"transition_max": _vector_array(transition_max),
			"neighbor_min": _vector_array(neighbor_min),
			"neighbor_max": _vector_array(neighbor_max),
		}
	var actual := Contract.boundary_contour(transition, axis, expected_plane, ASSERT_TOLERANCE, SHARED_NORMAL_TOLERANCE)
	var expected := Contract.boundary_contour(neighbor, axis, expected_plane, ASSERT_TOLERANCE, SHARED_NORMAL_TOLERANCE)
	var contour_match := Contract.compare_boundary_contours(actual, expected)
	if not contour_match.get("ok", false):
		contour_match["face"] = face
		return contour_match
	if actual["normals"].size() != expected["normals"].size():
		return {"ok": false, "reason_code": "interface_normal_vertex_count_mismatch", "face": face}
	for point_key in expected["normals"]:
		if not actual["normals"].has(point_key):
			return {"ok": false, "reason_code": "interface_normal_vertex_missing", "face": face, "point": point_key}
		var a: Vector3 = actual["normals"][point_key]
		var b: Vector3 = expected["normals"][point_key]
		if a.distance_to(b) > SHARED_NORMAL_TOLERANCE:
			return {"ok": false, "reason_code": "interface_normal_mismatch", "face": face, "point": point_key}
	return {
		"ok": true,
		"face": face,
		"plane_world": expected_plane,
		"transition_aabb_touches": contact,
		"interiors_disjoint": disjoint,
		"tangent_ranges_match": tangents_match,
		"segment_count": actual["segments"].size(),
		"normal_vertex_count": actual["normals"].size(),
		"normal_tolerance": SHARED_NORMAL_TOLERANCE,
	}


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _run_tunnel_scenario(scenario: Dictionary) -> void:
	var field: Dictionary = _manifest["tunnel_field"]
	var min_mm: Array = field["domain_min_mm"]
	var max_mm: Array = field["domain_max_mm"]
	var step_mm := int(field["step_mm"])
	var nx := int((int(max_mm[0]) - int(min_mm[0])) / step_mm) + 1
	var ny := int((int(max_mm[1]) - int(min_mm[1])) / step_mm) + 1
	var nz := int((int(max_mm[2]) - int(min_mm[2])) / step_mm) + 1
	var plane_size := ny * nz
	var total := nx * plane_size
	var synthetic_tunnel := String(scenario["id"]) != "B0G.TUNNEL.CANONICAL_CONTROL.W1840.v1"
	var radius := float(int(scenario["radius_mm"])) / 1000.0
	var corridor_radius := radius if synthetic_tunnel else 0.92
	if not synthetic_tunnel and not is_equal_approx(radius, 0.92):
		_fail("canonical_tunnel_radius_does_not_match_sdf_v1", {"scenario_radius": radius, "canonical_radius": 0.92})
		return
	var phase := float(posmod(int(_manifest["global_seed"]), 100003)) * 0.000173
	var centerline_y := PackedFloat64Array()
	var centerline_z := PackedFloat64Array()
	centerline_y.resize(nx)
	centerline_z.resize(nx)
	for xi in range(nx):
		var world_x := float(int(min_mm[0]) + xi * step_mm) / 1000.0
		if synthetic_tunnel:
			centerline_y[xi] = _tunnel_center_y(world_x, phase)
			centerline_z[xi] = _tunnel_center_z(world_x, phase)
		else:
			var center_mapping: Dictionary = Spatial.world_to_region_local(Vector3(world_x, 0.0, 0.0))
			if not center_mapping.get("valid", false):
				_fail("canonical_tunnel_centerline_mapping_invalid", {"x_index": xi})
				return
			var center_region: Vector2i = center_mapping["region_key"]
			var center_local_position: Vector3 = center_mapping["local_position"]
			var center_local: Vector2 = CanonicalField.cave_center(
				int(_manifest["global_seed"]), center_region, center_local_position.x
			)
			centerline_y[xi] = center_local.y
			centerline_z[xi] = center_local.x + float(center_region.y) * CanonicalField.REGION_SIZE_Z
	var solid := PackedByteArray()
	solid.resize(total)
	var corridor_empty := PackedByteArray()
	corridor_empty.resize(total)
	var sample_started := Time.get_ticks_usec()
	for xi in range(nx):
		var x_mm := int(min_mm[0]) + xi * step_mm
		for yi in range(ny):
			var y_mm := int(min_mm[1]) + yi * step_mm
			for zi in range(nz):
				var z_mm := int(min_mm[2]) + zi * step_mm
				var index := xi * plane_size + yi * nz + zi
				var world_x := float(x_mm) / 1000.0
				var world_y := float(y_mm) / 1000.0
				var world_z := float(z_mm) / 1000.0
				var density: float
				if not synthetic_tunnel:
					var world_position := Vector3(world_x, world_y, world_z)
					var mapped: Dictionary = Spatial.world_to_region_local(world_position)
					if not mapped.get("valid", false):
						_fail("canonical_tunnel_world_mapping_invalid", {"x_index": xi, "y_index": yi, "z_index": zi})
						return
					density = CanonicalField.sample_density(
						int(_manifest["global_seed"]), mapped["region_key"], mapped["local_position"], false
					)
				else:
					density = _synthetic_tunnel_density(
						world_x,
						world_y,
						world_z,
						radius,
						int(_manifest["global_seed"])
					)
				solid[index] = 1 if density >= 0.0 else 0
				if density < 0.0:
					var center_y := centerline_y[xi]
					var center_z := centerline_z[xi]
					if Vector2(world_y - center_y, world_z - center_z).length_squared() < corridor_radius * corridor_radius:
						corridor_empty[index] = 1
		if xi % 4 == 0:
			await process_frame
			if _process_guard_exceeded():
				_mark_timeout("tunnel_field_sampling", sample_started, PROCESS_GUARD_USEC)
				return
	var sample_elapsed := Time.get_ticks_usec() - sample_started
	var labeling_started := Time.get_ticks_usec()
	var labels := PackedInt32Array()
	labels.resize(total)
	var component_sizes: Dictionary = {}
	var component_id := 0
	var visited := 0
	var next_yield := TUNNEL_SLICE_VISITS
	for seed_index in range(total):
		if solid[seed_index] != 0 or labels[seed_index] != 0:
			continue
		component_id += 1
		var queue := PackedInt32Array([seed_index])
		labels[seed_index] = component_id
		var head := 0
		var component_size := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			component_size += 1
			visited += 1
			var x_index := int(current / plane_size)
			var remainder := current % plane_size
			var y_index := int(remainder / nz)
			var z_index := remainder % nz
			if x_index > 0:
				var neighbor_x_low := current - plane_size
				if solid[neighbor_x_low] == 0 and labels[neighbor_x_low] == 0:
					labels[neighbor_x_low] = component_id
					queue.append(neighbor_x_low)
			if x_index + 1 < nx:
				var neighbor_x_high := current + plane_size
				if solid[neighbor_x_high] == 0 and labels[neighbor_x_high] == 0:
					labels[neighbor_x_high] = component_id
					queue.append(neighbor_x_high)
			if y_index > 0:
				var neighbor_y_low := current - nz
				if solid[neighbor_y_low] == 0 and labels[neighbor_y_low] == 0:
					labels[neighbor_y_low] = component_id
					queue.append(neighbor_y_low)
			if y_index + 1 < ny:
				var neighbor_y_high := current + nz
				if solid[neighbor_y_high] == 0 and labels[neighbor_y_high] == 0:
					labels[neighbor_y_high] = component_id
					queue.append(neighbor_y_high)
			if z_index > 0:
				var neighbor_z_low := current - 1
				if solid[neighbor_z_low] == 0 and labels[neighbor_z_low] == 0:
					labels[neighbor_z_low] = component_id
					queue.append(neighbor_z_low)
			if z_index + 1 < nz:
				var neighbor_z_high := current + 1
				if solid[neighbor_z_high] == 0 and labels[neighbor_z_high] == 0:
					labels[neighbor_z_high] = component_id
					queue.append(neighbor_z_high)
			if visited >= next_yield:
				await process_frame
				next_yield += TUNNEL_SLICE_VISITS
				if _process_guard_exceeded():
					_mark_timeout("tunnel_component_labeling", labeling_started, PROCESS_GUARD_USEC)
					return
		component_sizes[component_id] = component_size
	var tunnel_label := 0
	var centerline_labels: Array[int] = []
	var minimum_centerline_lattice_clearance := INF
	var centerline_indices := PackedInt32Array()
	for xi in range(nx):
		var center_y := centerline_y[xi]
		var center_z := centerline_z[xi]
		var yi := clampi(floori((center_y - float(min_mm[1]) / 1000.0) / (float(step_mm) / 1000.0) + 0.5), 0, ny - 1)
		var zi := clampi(floori((center_z - float(min_mm[2]) / 1000.0) / (float(step_mm) / 1000.0) + 0.5), 0, nz - 1)
		var nearest_y := float(int(min_mm[1]) + yi * step_mm) / 1000.0
		var nearest_z := float(int(min_mm[2]) + zi * step_mm) / 1000.0
		var center_distance := Vector2(nearest_y - center_y, nearest_z - center_z).length()
		minimum_centerline_lattice_clearance = minf(minimum_centerline_lattice_clearance, radius - center_distance)
		var sample_index := xi * plane_size + yi * nz + zi
		centerline_indices.append(sample_index)
		if solid[sample_index] != 0 or labels[sample_index] == 0:
			_fail("centerline_nearest_sample_is_not_empty", {"x_index": xi, "y_index": yi, "z_index": zi})
			return
		var label := labels[sample_index]
		centerline_labels.append(label)
		if xi == 0:
			tunnel_label = label
		elif label != tunnel_label:
			_fail("tunnel_centerline_components_are_disconnected", {"x_index": xi, "first_component": tunnel_label, "actual_component": label})
			return
	var corridor_connectivity := Contract.connected_required_samples(corridor_empty, Vector3i(nx, ny, nz), centerline_indices)
	if not corridor_connectivity.get("ok", false):
		_fail("tunnel_centerline_corridor_disconnected", {
			"field_source": "PRODUCTION_SDF_V1" if not synthetic_tunnel else "B0_R4_SYNTHETIC_FIELD",
			"reason_code": corridor_connectivity.get("reason_code", "unknown"),
			"missing_centerline_sample_indices": corridor_connectivity.get("missing_required_indices", []),
		})
		return
	var top_index := _grid_index(128, 79, 96, plane_size, nz)
	var bottom_index := _grid_index(128, 1, 96, plane_size, nz)
	var top_label := labels[top_index]
	var bottom_label := labels[bottom_index]
	var negative_x_opening_label := centerline_labels[0] if not centerline_labels.is_empty() else 0
	var positive_x_opening_label := centerline_labels[-1] if not centerline_labels.is_empty() else 0
	if tunnel_label == 0 or centerline_labels.size() != nx \
		or negative_x_opening_label != tunnel_label or positive_x_opening_label != tunnel_label:
		_fail("tunnel_component_does_not_reach_both_x_openings")
		return
	var labeling_elapsed := Time.get_ticks_usec() - labeling_started
	_emit_event("tunnel_connectivity_result", {
		"status": "PASS",
		"field_source": "PRODUCTION_SDF_V1" if String(scenario["id"]) == "B0G.TUNNEL.CANONICAL_CONTROL.W1840.v1" else "B0_R4_SYNTHETIC_FIELD",
		"width_mm": scenario["width_mm"],
		"radius_mm": scenario["radius_mm"],
		"grid_dimensions_xyz": [nx, ny, nz],
		"sample_count": total,
		"empty_voxel_count": visited,
		"component_count": component_id,
		"centerline_seed_component_id": tunnel_label,
		"centerline_connected_x_samples": centerline_labels.size(),
		"centerline_corridor_connected": bool(corridor_connectivity.get("ok", false)),
		"centerline_corridor_applicability": "CANONICAL_AND_SYNTHETIC_TUNNEL_FIELDS",
		"centerline_corridor_radius_world": corridor_radius,
		"centerline_corridor_visited_sample_count": int(corridor_connectivity.get("visited_sample_count", 0)),
		"centerline_corridor_method": "six_neighbor_negative_density_mask_constrained_to_seeded_centerline_radius",
		"centerline_corridor_source": "SDF_V1_CAVE_CENTER_RADIUS_0_92" if not synthetic_tunnel else "B0_R4_SYNTHETIC_CENTERLINE_AND_SCENARIO_RADIUS",
		"negative_x_opening_reached": true,
		"positive_x_opening_reached": true,
		"centerline_nearest_lattice_clearance_min_world": minimum_centerline_lattice_clearance,
		"top_exterior_component_id": top_label,
		"top_exterior_component_size": component_sizes.get(top_label, 0),
		"bottom_exterior_component_id": bottom_label,
		"bottom_exterior_component_size": component_sizes.get(bottom_label, 0),
		"tunnel_overlaps_top_component": tunnel_label == top_label,
		"tunnel_overlaps_bottom_component": tunnel_label == bottom_label,
		"field_sampling_elapsed_usec": sample_elapsed,
		"component_labeling_elapsed_usec": labeling_elapsed,
		"topology_thresholds": "UNSCORED_OWNER_TO_DEFINE",
	})


func _synthetic_tunnel_density(x: float, y: float, z: float, radius: float, seed: int) -> float:
	var phase := float(posmod(seed, 100003)) * 0.000173
	var surface_y := 3.8 + 1.25 * sin(0.22 * x + phase) \
		+ 0.70 * cos(0.31 * z - 0.7 * phase) \
		+ 0.28 * sin(0.11 * (x + z) + 0.3 * phase)
	var surface_density := minf(surface_y - y, y - (-1.0))
	var center_y := _tunnel_center_y(x, phase)
	var center_z := _tunnel_center_z(x, phase)
	var tunnel_distance := Vector2(y - center_y, z - center_z).length() - radius
	return minf(surface_density, tunnel_distance)


func _tunnel_center_y(x: float, phase: float) -> float:
	return 1.15 + 0.24 * sin(0.25 * x + phase)


func _tunnel_center_z(x: float, phase: float) -> float:
	return 6.0 + 1.05 * sin(0.17 * x + 0.6 * phase)


func _grid_index(x_index: int, y_index: int, z_index: int, plane_size: int, nz: int) -> int:
	return x_index * plane_size + y_index * nz + z_index


func _run_streaming_scenario(scenario: Dictionary) -> void:
	var scene: Node = TerrainScene.instantiate()
	scene.set("orbit_target", Vector3(8.0, 3.2, 6.0))
	scene.set("orbit_offset", Vector3(12.0, 8.0, 15.0))
	root.add_child(scene)
	var stream_baseline := _stream_counter_snapshot(scene)
	var immediate: Dictionary = _stream_snapshot(scene)
	_emit_event("stream_initial_observation", immediate)
	var initial_focus := Vector2i.ZERO
	var initial_ready: bool = await _wait_for_stream_settled(scene, initial_focus, "initial_window")
	if not initial_ready:
		scene.queue_free()
		await process_frame
		return
	var initial_keys: Array[String] = _active_keys(scene)
	var expected_initial := _window_keys(initial_focus, 1)
	if initial_keys != expected_initial:
		_fail("initial_active_region_set_mismatch", {"expected": expected_initial, "actual": initial_keys})
		scene.queue_free()
		await process_frame
		return
	if String(scenario["id"]) == "B0S.COLD.ORIGIN.v1":
		_emit_event("stream_scenario_result", _stream_summary(scene, initial_keys, [9], stream_baseline))
		scene.queue_free()
		await process_frame
		return
	if String(scenario["id"]) == "B0S.CORNER.DIRECT_ATOMIC_POS_POS.v1":
		var start_mm: Array = scenario["start_focus_mm"]
		var start_focus_world := Vector3(float(start_mm[0]) / 1000.0, float(start_mm[1]) / 1000.0, float(start_mm[2]) / 1000.0)
		scene.set("orbit_target", start_focus_world)
		scene.call("_update_camera")
		scene.call("_update_focus_key")
		var before_key: Vector2i = scene.get("focus_region_key")
		var before_reconciled: Vector2i = scene.get("_last_reconciled_focus")
		var delta_mm: Array = scenario["atomic_delta_mm"]
		var atomic_delta := Vector3(float(delta_mm[0]) / 1000.0, float(delta_mm[1]) / 1000.0, float(delta_mm[2]) / 1000.0)
		var atomic_started := Time.get_ticks_usec()
		scene.call("_move_focus", atomic_delta)
		var after_key: Vector2i = scene.get("focus_region_key")
		var after_reconciled: Vector2i = scene.get("_last_reconciled_focus")
		var expected_focus_sequence := [Vector2i.ZERO, Vector2i(1, 1)]
		if before_key != expected_focus_sequence[0] or after_key != expected_focus_sequence[1] \
			or before_reconciled != before_key or after_reconciled != after_key:
			_fail("atomic_diagonal_observed_intermediate_or_wrong_focus_key", {
				"focus_before": Contract.key_array(before_key),
				"focus_after": Contract.key_array(after_key),
				"reconciled_before": Contract.key_array(before_reconciled),
				"reconciled_after": Contract.key_array(after_reconciled),
			})
			scene.queue_free()
			await process_frame
			return
		var diagonal_ready: bool = await _wait_for_stream_settled(scene, after_key, "atomic_diagonal_final")
		if not diagonal_ready:
			scene.queue_free()
			await process_frame
			return
		var expected_keys := _expected_after_focus(initial_keys, after_key)
		var actual_keys := _active_keys(scene)
		if actual_keys != expected_keys or actual_keys.size() != int(scenario["expected_final_active_count"]):
			_fail("atomic_diagonal_final_active_set_mismatch", {
				"expected_keys": expected_keys,
				"actual_keys": actual_keys,
				"expected_count": scenario["expected_final_active_count"],
			})
		else:
			_emit_event("stream_atomic_diagonal_result", {
				"status": "PASS",
				"focus_key_sequence": [Contract.key_array(before_key), Contract.key_array(after_key)],
				"requested_keys": _window_keys(after_key, 1),
				"retained_active_keys": _retained_keys(initial_keys, after_key, 2),
				"final_active_keys": actual_keys,
				"expected_final_count": scenario["expected_final_active_count"],
				"atomic_update_elapsed_usec": Time.get_ticks_usec() - atomic_started,
				"stream_counts": _stream_counters(scene, stream_baseline),
			})
		scene.queue_free()
		await process_frame
		return
	var waypoints: Array = scenario.get("waypoints", [])
	var expected_counts: Array = scenario.get("expected_settled_counts", [])
	var previous_keys := initial_keys
	var leg_index := 0
	var last_successful_move: Dictionary = {}
	for waypoint_index in range(1, waypoints.size()):
		var target_mm: Array = waypoints[waypoint_index]
		var target := Vector3(float(target_mm[0]) / 1000.0, float(target_mm[1]) / 1000.0, float(target_mm[2]) / 1000.0)
		var velocity_values: Array
		if scenario.has("velocity_legs_mm_s"):
			velocity_values = scenario["velocity_legs_mm_s"][leg_index]
		else:
			velocity_values = scenario["velocity_mm_s"]
		var move_result: Dictionary = await _move_focus_continuously(scene, target, Vector3(velocity_values[0], velocity_values[1], velocity_values[2]))
		var movement_gate := Contract.movement_result_gate(_scenario_status, move_result)
		if movement_gate.get("abort", false):
			_scenario_status = String(movement_gate.get("terminal_status", "FAIL"))
			if _scenario_status != "TIMEOUT":
				_fail("streaming_movement_failed", {"reason_code": movement_gate.get("reason_code", "unknown")})
			scene.queue_free()
			await process_frame
			return
		last_successful_move = move_result
		_emit_event("stream_movement_leg_completed", {
			"waypoint_index": waypoint_index,
			"start_position_world": move_result["start_position"],
			"target_position_world": move_result["target_position"],
			"motion_elapsed_usec": move_result["elapsed_usec"],
			"movement_call_elapsed_usec": move_result["frame_elapsed_usec"],
			"movement_call_latency_percentiles_usec": _percentiles(move_result["frame_elapsed_usec"]),
			"focus_key_at_leg_end": Contract.key_array(scene.get("focus_region_key")),
		})
		if bool(scenario.get("settle_after_each_waypoint", true)):
			var key: Vector2i = scene.get("focus_region_key")
			var waypoint_ready: bool = await _wait_for_stream_settled(scene, key, "waypoint_%d" % waypoint_index)
			if not waypoint_ready:
				scene.queue_free()
				await process_frame
				return
			var actual_keys := _active_keys(scene)
			var expected_keys := _expected_after_focus(previous_keys, key)
			if actual_keys != expected_keys:
				_fail("settled_route_active_set_mismatch", {
					"waypoint_index": waypoint_index,
					"focus_key": Contract.key_array(key),
					"expected_keys": expected_keys,
					"actual_keys": actual_keys,
				})
				scene.queue_free()
				await process_frame
				return
			if not expected_counts.is_empty() and actual_keys.size() != int(expected_counts[waypoint_index]):
				_fail("settled_route_count_mismatch", {
					"waypoint_index": waypoint_index,
					"expected_count": expected_counts[waypoint_index],
					"actual_count": actual_keys.size(),
				})
				scene.queue_free()
				await process_frame
				return
			_emit_event("stream_waypoint_settled", {
				"waypoint_index": waypoint_index,
				"focus_key": Contract.key_array(key),
				"expected_active_keys": expected_keys,
				"actual_active_keys": actual_keys,
				"move_elapsed_usec": move_result["elapsed_usec"],
				"move_frame_samples_usec": move_result["frame_elapsed_usec"],
				"movement_call_latency_percentiles_usec": _percentiles(move_result["frame_elapsed_usec"]),
				"stream_counts": _stream_counters(scene, stream_baseline),
			})
			previous_keys = actual_keys
		leg_index += 1
	var final_focus: Vector2i = scene.get("focus_region_key")
	var final_ready: bool = await _wait_for_stream_settled(scene, final_focus, "route_final")
	if not final_ready:
		scene.queue_free()
		await process_frame
		return
	var final_keys := _active_keys(scene)
	var final_base_keys: Array[String] = previous_keys
	if not bool(scenario.get("settle_after_each_waypoint", true)):
		var movement_base := Contract.last_successful_movement_base_keys(last_successful_move)
		if not movement_base.get("ok", false):
			_fail(String(movement_base.get("reason_code", "nonsettled_route_has_no_successful_movement_record")))
			scene.queue_free()
			await process_frame
			return
		final_base_keys = movement_base["keys"]
	var final_expected := _expected_after_focus(final_base_keys, final_focus)
	if final_keys != final_expected:
		_fail("final_route_active_set_mismatch", {"expected": final_expected, "actual": final_keys})
	else:
		_emit_event("stream_scenario_result", {
			"status": "PASS",
			"route_waypoints_mm": waypoints,
			"observed_focus_crossings": scene.get_meta("p1b_observed_focus_crossings", []),
			"final_focus_key": Contract.key_array(final_focus),
			"final_requested_keys": _window_keys(final_focus, 1),
			"final_active_keys": final_keys,
			"final_active_count": final_keys.size(),
			"stream_counts": _stream_counters(scene, stream_baseline),
			"stream_diagnostics": _stream_diagnostics(scene),
		})
	scene.queue_free()
	await process_frame


func _move_focus_continuously(scene: Node, target: Vector3, requested_velocity: Vector3) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var frame_samples: Array[int] = []
	var active_before_last_crossing := _active_keys(scene)
	var previous_key: Vector2i = scene.get("focus_region_key")
	var previous_frame_usec := Time.get_ticks_usec()
	var start_position: Vector3 = scene.get("orbit_target")
	var delta := target - start_position
	var axis := 0 if absf(delta.x) > 0.000001 else 2
	if (axis == 0 and absf(delta.z) > 0.000001) or (axis == 2 and absf(delta.x) > 0.000001):
		return {"ok": false, "reason_code": "continuous_route_leg_is_not_single_axis"}
	var speed := absf(requested_velocity[axis]) / 1000.0
	if speed <= 0.0 or signf(requested_velocity[axis]) != signf(delta[axis]):
		return {"ok": false, "reason_code": "route_velocity_does_not_match_frozen_waypoint"}
	while (target - (scene.get("orbit_target") as Vector3)).length() > 0.0000001:
		await process_frame
		var frame_now := Time.get_ticks_usec()
		var elapsed := frame_now - previous_frame_usec
		previous_frame_usec = frame_now
		if elapsed <= 0:
			continue
		if _process_guard_exceeded():
			_mark_timeout("streaming_movement", start_usec, PROCESS_GUARD_USEC)
			return {"ok": false, "reason_code": "process_guard_exceeded"}
		var current: Vector3 = scene.get("orbit_target")
		var remaining := target - current
		var travel := minf(remaining.length(), speed * float(elapsed) / 1000000.0)
		var active_before_move := _active_keys(scene)
		var move_started := Time.get_ticks_usec()
		scene.call("_move_focus", remaining.normalized() * travel)
		frame_samples.append(Time.get_ticks_usec() - move_started)
		var focus_key: Vector2i = scene.get("focus_region_key")
		if focus_key != previous_key:
			active_before_last_crossing = active_before_move
			var crossings: Array = scene.get_meta("p1b_observed_focus_crossings", [])
			crossings.append(Contract.key_array(focus_key))
			scene.set_meta("p1b_observed_focus_crossings", crossings)
			_emit_event("stream_focus_crossing_observed", {
				"from_focus_key": Contract.key_array(previous_key),
				"to_focus_key": Contract.key_array(focus_key),
				"active_keys_at_crossing": _active_keys(scene),
				"requested_keys_at_crossing": _window_keys(focus_key, 1),
				"pending_keys_at_crossing": _pending_keys(scene),
				"move_call_elapsed_usec": frame_samples[-1],
			})
			if absi(focus_key.x - previous_key.x) > 1 or absi(focus_key.y - previous_key.y) > 1:
				return {"ok": false, "reason_code": "movement_skipped_observable_region_focus_key"}
			previous_key = focus_key
	return {
		"ok": true,
		"elapsed_usec": Time.get_ticks_usec() - start_usec,
		"frame_elapsed_usec": frame_samples,
		"active_before_last_crossing": active_before_last_crossing,
		"start_position": _vector_array(start_position),
		"target_position": _vector_array(target),
	}


func _wait_for_stream_settled(scene: Node, focus: Vector2i, stage: String) -> bool:
	var started := Time.get_ticks_usec()
	var expected := _window_keys(focus, 1)
	_emit_event("stream_readiness_wait_started", {
		"stage": stage,
		"focus_key": Contract.key_array(focus),
		"requested_keys": expected,
		"initial_active_keys": _active_keys(scene),
		"initial_pending_keys": _pending_keys(scene),
	})
	while true:
		_observe_loading_stage_revisions(scene)
		if _process_guard_exceeded():
			_mark_timeout(stage, started, PROCESS_GUARD_USEC)
			return false
		if Time.get_ticks_usec() - started >= READINESS_GUARD_USEC:
			_mark_timeout(stage, started, READINESS_GUARD_USEC)
			return false
		var active := _active_keys(scene)
		var pending := _pending_keys(scene)
		var errors := _relevant_stream_errors(scene, expected)
		var requested_published := true
		for key in expected:
			if not active.has(key):
				requested_published = false
			if pending.has(key):
				requested_published = false
		var edit_transaction: Dictionary = scene.get("_edit_transaction")
		var transaction_clear := edit_transaction.is_empty()
		if requested_published and errors.is_empty() and transaction_clear and not bool(scene.get("global_rebuild_pending")):
			var diagnostics := _stream_diagnostics(scene)
			var ledger: RefCounted = scene.get("edit_ledger")
			if int(diagnostics.get("active_chunk_count", 0)) > 400 or active.size() > 25:
				_fail("stream_resource_residency_cap_exceeded", {
					"active_region_count": active.size(),
					"active_chunk_count": diagnostics.get("active_chunk_count", 0),
				})
				return false
			_emit_event("stream_readiness_reached", {
				"stage": stage,
				"readiness_elapsed_usec": Time.get_ticks_usec() - started,
				"requested_keys": expected,
				"active_keys": active,
				"pending_keys": pending,
				"unresolved_relevant_errors": errors,
				"ledger_revision": ledger.revision,
				"stream_diagnostics": diagnostics,
			})
			return true
		await process_frame


func _stream_snapshot(scene: Node) -> Dictionary:
	var focus: Vector2i = scene.get("focus_region_key")
	var ledger: RefCounted = scene.get("edit_ledger")
	return {
		"focus_key": Contract.key_array(focus),
		"requested_keys": _window_keys(focus, 1),
		"active_keys": _active_keys(scene),
		"pending_keys": _pending_keys(scene),
		"failed_region_ids": _error_keys(scene),
		"active_count": scene.get("active_regions").size(),
		"pending_count": scene.get("loading_regions").size(),
		"ledger_revision": ledger.revision,
	}


func _stream_summary(scene: Node, initial_keys: Array[String], expected_counts: Array, baseline: Dictionary) -> Dictionary:
	var actual := _active_keys(scene)
	var ok := actual == initial_keys and actual.size() == int(expected_counts[-1])
	if not ok:
		_fail("cold_origin_set_or_count_mismatch", {"expected_keys": initial_keys, "actual_keys": actual})
	return {
		"status": "PASS" if ok else "FAIL",
		"initial_active_keys": initial_keys,
		"final_active_keys": actual,
		"final_active_count": actual.size(),
		"stream_counts": _stream_counters(scene, baseline),
		"stream_diagnostics": _stream_diagnostics(scene),
	}


func _stream_counter_snapshot(scene: Node) -> Dictionary:
	var diagnostics := _stream_diagnostics(scene)
	return {
		"successful_publications": int(diagnostics.get("streamed_region_loads", 0)),
		"successful_unloads": int(diagnostics.get("streamed_region_unloads", 0)),
		"superseded_stages": int(scene.get("_superseded_stage_total")),
		"stage_retries": int(diagnostics.get("mesh_stage_retry_total", 0)),
	}


func _stream_counters(scene: Node, baseline: Dictionary) -> Dictionary:
	var current := _stream_counter_snapshot(scene)
	return {
		"successful_publications": maxi(0, int(current["successful_publications"]) - int(baseline.get("successful_publications", 0))),
		"successful_unloads": maxi(0, int(current["successful_unloads"]) - int(baseline.get("successful_unloads", 0))),
		"superseded_stages": maxi(0, int(current["superseded_stages"]) - int(baseline.get("superseded_stages", 0))),
		"stage_retries": maxi(0, int(current["stage_retries"]) - int(baseline.get("stage_retries", 0))),
		"unresolved_error_region_ids": _error_keys(scene),
	}


func _stream_diagnostics(scene: Node) -> Dictionary:
	var value: Variant = scene.get("last_mesh_diagnostics")
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	# Whitelist finite scalar measurements. Production diagnostics also contain
	# user-facing status/error strings; they must never enter raw benchmark logs.
	var safe_keys := [
		"active_region_count", "active_chunk_count", "requested_region_count", "loading_region_count",
		"queued_chunk_count", "queued_mesh_job_count", "peak_active_region_count", "peak_queue_depth",
		"peak_mesh_job_queue_depth", "last_mesh_upload_ms", "peak_mesh_upload_ms", "last_process_work_ms",
		"peak_process_work_ms", "last_frame_ms", "peak_frame_ms", "streamed_region_loads",
		"streamed_region_unloads", "max_active_region_count", "max_mesh_uploads_per_frame",
		"peak_mesh_uploads_per_frame", "mesh_jobs_in_flight", "peak_mesh_jobs_in_flight",
		"global_edit_count", "global_edit_limit", "global_edit_last_sequence", "global_edit_revision",
		"last_support_region_count", "last_rebuild_region_count", "last_rebuild_chunk_count",
		"last_dirty_mesh_job_count", "active_triangle_count", "queued_region_count",
		"mesh_stage_retry_total", "superseded_stage_total",
	]
	var safe: Dictionary = {}
	for key in safe_keys:
		if not value.has(key):
			continue
		var item: Variant = value[key]
		if typeof(item) == TYPE_INT or typeof(item) == TYPE_BOOL:
			safe[key] = item
		elif typeof(item) == TYPE_FLOAT and is_finite(float(item)):
			safe[key] = item
	return safe


func _active_keys(scene: Node) -> Array[String]:
	var keys: Array[String] = []
	for entry_value in scene.get("active_regions").values():
		var entry: Dictionary = entry_value
		keys.append(Contract.region_id(entry["region_key"]))
	keys.sort()
	return keys


func _pending_keys(scene: Node) -> Array[String]:
	var keys: Array[String] = []
	for stage_value in scene.get("loading_regions").values():
		var stage: Dictionary = stage_value
		keys.append(Contract.region_id(stage["region_key"]))
	keys.sort()
	return keys


func _error_keys(scene: Node) -> Array[String]:
	var errors: Dictionary = scene.get("_stream_errors_by_region")
	var keys: Array[String] = []
	for key in errors.keys():
		keys.append(String(key))
	keys.sort()
	return keys


func _relevant_stream_errors(scene: Node, requested: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var errors: Dictionary = scene.get("_stream_errors_by_region")
	for id_value in errors.keys():
		var id := String(id_value)
		if id == "_global" or requested.has(id):
			result.append(id)
	result.sort()
	return result


func _window_keys(center: Vector2i, radius: int) -> Array[String]:
	var result: Array[String] = []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			result.append("%d,%d" % [x, z])
	result.sort()
	return result


func _retained_keys(previous: Array[String], focus: Vector2i, radius: int) -> Array[String]:
	var retention := {}
	for key in _window_keys(focus, radius):
		retention[key] = true
	var result: Array[String] = []
	for key in previous:
		if retention.has(key):
			result.append(key)
	result.sort()
	return result


func _expected_after_focus(previous: Array[String], focus: Vector2i) -> Array[String]:
	var combined := {}
	for key in _retained_keys(previous, focus, 2):
		combined[key] = true
	for key in _window_keys(focus, 1):
		combined[key] = true
	var result: Array[String] = []
	for key in combined.keys():
		result.append(String(key))
	result.sort()
	return result


func _run_edited_reload_scenario(scenario: Dictionary) -> void:
	var focus_mm: Array = scenario["focus_mm"]
	var away_mm: Array = scenario["away_focus_mm"]
	var initial_focus := Vector3(float(focus_mm[0]) / 1000.0, float(focus_mm[1]) / 1000.0, float(focus_mm[2]) / 1000.0)
	var scene: Node = TerrainScene.instantiate()
	scene.set("orbit_target", initial_focus)
	scene.set("orbit_offset", Vector3(12.0, 8.0, 15.0))
	root.add_child(scene)
	var focus_key := Vector2i(2, -1)
	var initial_region_ready: bool = await _wait_for_stream_settled(scene, focus_key, "edited_reload_initial_region")
	if not initial_region_ready:
		scene.queue_free()
		await process_frame
		return
	var ledger: RefCounted = scene.get("edit_ledger")
	var commands: Array[Dictionary] = Contract.commands_from_scenario(scenario)
	var actual_commands: Array[Dictionary] = []
	var edit_publication_receipts: Array[Dictionary] = []
	for command in commands:
		var center_mm: Array = command["center_mm"]
		var center := Vector3(float(center_mm[0]) / 1000.0, float(center_mm[1]) / 1000.0, float(center_mm[2]) / 1000.0)
		var mode := BrushState.Mode.CARVE if String(command["mode"]) == "CARVE" else BrushState.Mode.FILL
		var acceptance_started := Time.get_ticks_usec()
		var accepted: bool = ledger.add_sphere(mode, center, float(int(command["radius_mm"])) / 1000.0)
		var acceptance_elapsed := Time.get_ticks_usec() - acceptance_started
		if not accepted:
			_fail("edited_reload_frozen_command_rejected", {"ledger_reason": ledger.last_rejection_reason, "command": command})
			scene.queue_free()
			await process_frame
			return
		var operation := ledger.get_last_operation_snapshot()
		var support := Contract.operation_region_keys(operation, "support_regions")
		var dependencies := Contract.operation_region_keys(operation, "dependency_regions")
		var rebuild := Contract.operation_region_keys(operation, "rebuild_regions")
		actual_commands.append(Contract.command_from_operation(operation))
		_emit_event("ledger_command_accepted", {
			"sequence": operation["sequence"],
			"revision": operation["revision"],
			"mode": command["mode"],
			"center_mm": command["center_mm"],
			"radius_mm": command["radius_mm"],
			"support_region_keys": support,
			"dependency_region_keys": dependencies,
			"rebuild_region_keys": rebuild,
			"acceptance_elapsed_usec": acceptance_elapsed,
			"publication_status_at_acceptance": "PENDING",
			"command_list_sha256_prefix_state": Contract.command_list_sha256(actual_commands),
		})
		var expected := Contract.expected_support_for_command(scenario, command)
		if support != expected:
			_fail("edited_reload_support_mismatch", {"expected": expected, "actual": support})
			scene.queue_free()
			await process_frame
			return
		var transaction_started := Time.get_ticks_usec()
		_clear_loading_stage_observation(scene, Contract.region_id(focus_key))
		scene.call("_schedule_edit_transaction", operation)
		var transaction_ready: bool = await _wait_for_edit_transaction(scene, "edited_reload_command_%d" % int(command["sequence"]))
		if not transaction_ready:
			scene.queue_free()
			await process_frame
			return
		var edit_receipt := _region_publication_evidence(
			scene, focus_key, "EDIT_TRANSACTION", int(operation["revision"]),
			int(operation["sequence"]), 0
		)
		var edit_receipt_verdict := Contract.validate_publication_evidence(edit_receipt)
		if not edit_receipt_verdict.get("ok", false):
			_fail("edited_reload_mesh_publication_not_proven", {
				"reason_code": edit_receipt_verdict.get("reason_code", "unknown"),
				"publication_evidence": edit_receipt,
			})
			scene.queue_free()
			await process_frame
			return
		edit_publication_receipts.append(edit_receipt)
		_emit_event("edit_mesh_transaction_completed", {
			"sequence": operation["sequence"],
			"revision": operation["revision"],
			"elapsed_since_scheduling_usec": Time.get_ticks_usec() - transaction_started,
			"acceptance_plus_publication_elapsed_usec": Time.get_ticks_usec() - acceptance_started,
			"coherent_mesh_transaction_completed": true,
			"publication_evidence": edit_receipt,
		})
	var command_sha := Contract.command_list_sha256(actual_commands)
	var probe_positions: Array = scenario["probe_positions_mm"]
	var before_values := _sample_region_probes(scene, focus_key, probe_positions)
	if before_values.size() != probe_positions.size():
		_fail("edited_reload_pre_unload_probes_incomplete")
		scene.queue_free()
		await process_frame
		return
	var target_id := Contract.region_id(focus_key)
	var unloads_before := int(_stream_diagnostics(scene).get("streamed_region_unloads", 0))
	var away_values: Array = scenario["away_focus_mm"]
	var away := Vector3(float(away_values[0]) / 1000.0, float(away_values[1]) / 1000.0, float(away_values[2]) / 1000.0)
	scene.call("_move_focus", away - (scene.get("orbit_target") as Vector3))
	var away_key: Vector2i = scene.get("focus_region_key")
	var away_ready: bool = await _wait_for_stream_settled(scene, away_key, "edited_reload_away")
	if not away_ready:
		scene.queue_free()
		await process_frame
		return
	var unloaded := not scene.get("active_regions").has(target_id)
	var unloads_after := int(_stream_diagnostics(scene).get("streamed_region_unloads", 0))
	if not unloaded or unloads_after <= unloads_before:
		_fail("edited_target_region_was_not_unloaded", {"target_region": target_id, "unload_count_before": unloads_before, "unload_count_after": unloads_after})
		scene.queue_free()
		await process_frame
		return
	var loads_before := int(_stream_diagnostics(scene).get("streamed_region_loads", 0))
	_clear_loading_stage_observation(scene, target_id)
	scene.call("_move_focus", initial_focus - (scene.get("orbit_target") as Vector3))
	var return_ready: bool = await _wait_for_stream_settled(scene, focus_key, "edited_reload_return")
	if not return_ready:
		scene.queue_free()
		await process_frame
		return
	var loads_after := int(_stream_diagnostics(scene).get("streamed_region_loads", 0))
	var after_values := _sample_region_probes(scene, focus_key, probe_positions)
	var reload_receipt := _region_publication_evidence(
		scene, focus_key, "REGION_LOAD", int(ledger.revision), -1, loads_after - loads_before
	)
	var reload_receipt_verdict := Contract.validate_publication_evidence(reload_receipt)
	if not reload_receipt_verdict.get("ok", false):
		_fail("edited_reload_mesh_publication_not_proven", {
			"reason_code": reload_receipt_verdict.get("reason_code", "unknown"),
			"publication_evidence": reload_receipt,
		})
	elif not scene.get("active_regions").has(target_id) or loads_after <= loads_before:
		_fail("edited_target_region_did_not_reload", {"target_region": target_id, "load_count_before": loads_before, "load_count_after": loads_after})
	elif before_values != after_values:
		_fail("edited_reload_probe_values_changed", {"before": before_values, "after": after_values})
	else:
		_emit_event("edited_reload_result", {
			"status": "PASS",
			"target_region": target_id,
			"operation_count": ledger.get_edit_count(),
			"revision": ledger.revision,
			"command_list_sha256": command_sha,
			"probe_positions_mm": probe_positions,
			"probe_densities_before_unload": before_values,
			"probe_densities_after_reload": after_values,
			"target_was_unloaded": unloaded,
			"successful_reload_observed": true,
			"edit_mesh_publication_receipts": edit_publication_receipts,
			"reload_mesh_publication_receipt": reload_receipt,
			"geometric_scoring": "SDF_PROBE_REPLAY_ONLY",
		})
	scene.queue_free()
	await process_frame


func _sample_region_probes(scene: Node, region_key: Vector2i, positions_mm: Array) -> Array:
	if not scene.get("active_regions").has(Contract.region_id(region_key)):
		return []
	var entry: Dictionary = scene.get("active_regions")[Contract.region_id(region_key)]
	var state: RefCounted = entry["world_state"]
	var values: Array = []
	for position_mm in positions_mm:
		var world := Vector3(float(position_mm[0]) / 1000.0, float(position_mm[1]) / 1000.0, float(position_mm[2]) / 1000.0)
		var mapped: Dictionary = Spatial.world_to_region_local(world)
		values.append(state.sample_density(mapped["local_position"]))
	return values


func _region_publication_evidence(
	scene: Node,
	region_key: Vector2i,
	kind: String,
	expected_revision: int,
	expected_sequence: int,
	successful_publication_delta: int
) -> Dictionary:
	var target_id := Contract.region_id(region_key)
	var active_regions: Dictionary = scene.get("active_regions")
	var loading_regions: Dictionary = scene.get("loading_regions")
	var entry: Dictionary = active_regions.get(target_id, {})
	var state_revision := -1
	var nodes: Dictionary = entry.get("chunk_nodes", {})
	if entry.has("world_state"):
		var state: RefCounted = entry["world_state"]
		state_revision = int(state.brush_edits.revision)
	var expected_chunk_count := Grid.CHUNK_COUNT_X * Grid.CHUNK_COUNT_Z
	var array_mesh_count := 0
	var requested_region_ids: Array[String] = [target_id]
	var stage_observations: Array[Dictionary] = []
	var all_stage_observations: Dictionary = scene.get_meta("p1b_stage_revision_observations", {})
	if all_stage_observations.has(target_id):
		stage_observations.append(all_stage_observations[target_id])
	for coordinate in Grid.all_coordinates():
		var chunk_id := Grid.stable_id(region_key, coordinate)
		if not nodes.has(chunk_id):
			continue
		var chunk_node: Variant = nodes[chunk_id]
		if chunk_node is MeshInstance3D:
			var mesh_node: MeshInstance3D = chunk_node
			if mesh_node.mesh is ArrayMesh:
				array_mesh_count += 1
	var receipt: Dictionary = {
		"kind": kind,
		"target_region_id": target_id,
		"stage_observations": stage_observations,
		"transaction_clear": (scene.get("_edit_transaction") as Dictionary).is_empty(),
		"pending_stage": loading_regions.has(target_id),
		"stream_errors": _relevant_stream_errors(scene, requested_region_ids),
		"expected_revision": expected_revision,
		"observed_revision": state_revision,
		"expected_chunk_count": expected_chunk_count,
		"active_chunk_count": nodes.size(),
		"array_mesh_count": array_mesh_count,
		"successful_publication_delta": successful_publication_delta,
		"edit_commit_status": "NOT_APPLICABLE",
		"expected_sequence": expected_sequence,
		"edit_commit_sequence": -1,
		"mesh_job_count": 0,
	}
	if kind == "EDIT_TRANSACTION":
		var result_text := String(scene.get("last_brush_result"))
		var prefix := "Global edit #%d mesh commit complete across " % expected_sequence
		var suffix := " resident region(s)"
		if result_text.begins_with(prefix) and result_text.ends_with(suffix):
			var committed_region_count := result_text.substr(prefix.length(), result_text.length() - prefix.length() - suffix.length())
			if committed_region_count.is_valid_int() and int(committed_region_count) > 0:
				receipt["edit_commit_status"] = "COHERENT_COMMIT"
				receipt["edit_commit_sequence"] = expected_sequence
				receipt["committed_region_count"] = int(committed_region_count)
				receipt["mesh_job_count"] = int(_stream_diagnostics(scene).get("last_dirty_mesh_job_count", 0))
	return receipt


func _wait_for_edit_transaction(scene: Node, label: String) -> bool:
	# Clearing only ends the wait. The caller must separately validate a coherent
	# revision-matched commit receipt before recording publication success.
	var started := Time.get_ticks_usec()
	while not scene.get("_edit_transaction").is_empty():
		_observe_loading_stage_revisions(scene)
		await process_frame
		if _process_guard_exceeded():
			_mark_timeout(label, started, PROCESS_GUARD_USEC)
			return false
		if Time.get_ticks_usec() - started >= READINESS_GUARD_USEC:
			_mark_timeout(label, started, READINESS_GUARD_USEC)
			return false
	return true


func _observe_loading_stage_revisions(scene: Node) -> void:
	var stages: Dictionary = scene.get("loading_regions")
	var observations: Dictionary = scene.get_meta("p1b_stage_revision_observations", {})
	for region_id_value in stages.keys():
		var region_id := String(region_id_value)
		var stage: Dictionary = stages[region_id]
		var coordinates: Array = stage.get("chunk_coordinates", [])
		var meshes: Dictionary = stage.get("meshes", {})
		observations[region_id] = {
			"region_id": region_id,
			"purpose": String(stage.get("purpose", "")),
			"edit_revision": int(stage.get("edit_revision", -1)),
			"chunk_count": coordinates.size(),
			"staged_mesh_count": meshes.size(),
		}
	scene.set_meta("p1b_stage_revision_observations", observations)


func _clear_loading_stage_observation(scene: Node, region_id: String) -> void:
	var observations: Dictionary = scene.get_meta("p1b_stage_revision_observations", {})
	observations.erase(region_id)
	scene.set_meta("p1b_stage_revision_observations", observations)


func _percentiles(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return {"sample_count": 0, "p50": null, "p95": null, "p99": null, "max": null}
	var sorted := samples.duplicate()
	sorted.sort()
	return {
		"sample_count": sorted.size(),
		"p50": _nearest_rank(sorted, 0.50),
		"p95": _nearest_rank(sorted, 0.95),
		"p99": _nearest_rank(sorted, 0.99),
		"max": sorted[-1],
	}


func _nearest_rank(sorted: Array[int], percentile: float) -> int:
	var rank := maxi(1, ceili(percentile * float(sorted.size())))
	return sorted[mini(rank - 1, sorted.size() - 1)]
