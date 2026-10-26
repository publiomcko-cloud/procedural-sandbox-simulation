extends SceneTree

## Fresh-process verifier for disposable R4 artifacts. It rebuilds canonical
## projections from the authoritative ledger and checks the saved float32
## snapshots without treating them as authoritative.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const ChunkProjection := preload("res://tests/prototypes/r4_chunk_subledger.gd")
const Voxel := preload("res://tests/prototypes/r4_voxel_snapshot.gd")
const SEED := 131102026
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result_path := OS.get_environment("P31_R4_RESULT_PATH")
	var expected_source := OS.get_environment("P31_R4_SOURCE_SHA")
	var expected_input := OS.get_environment("P31_R4_INPUT_SHA256")
	var expected_run_id := OS.get_environment("P31_R4_RUN_ID")
	var expected_result_sha := OS.get_environment("P31_R4_RESULT_SHA256")
	var output_path := OS.get_environment("P31_R4_RESTART_OUTPUT_PATH")
	if result_path.is_empty() or expected_source.is_empty() or expected_input.is_empty() \
		or expected_run_id.is_empty() or expected_result_sha.is_empty() or output_path.is_empty():
		_failures.append("restart_verifier_environment_invalid")
		_finish(2)
		return
	var result_bytes := FileAccess.get_file_as_bytes(result_path)
	if result_bytes.is_empty() or _sha256(result_bytes) != expected_result_sha:
		_failures.append("restart_result_missing_or_unreadable")
		_finish(2)
		return
	var result_variant: Variant = JSON.parse_string(result_bytes.get_string_from_utf8())
	if typeof(result_variant) != TYPE_DICTIONARY:
		_failures.append("restart_result_json_invalid")
		_finish(2)
		return
	var result: Dictionary = result_variant
	if String(result.get("status", "")) != "PASS" \
		or String(result.get("source_sha", "")) != expected_source \
		or String(result.get("run_id", "")) != expected_run_id:
		_failures.append("restart_result_identity_invalid")
		_finish(1)
		return
	var scenario := String(result.get("scenario_id", ""))
	var nonperiodic := scenario.begins_with("P31.R4.NONPERIODIC.")
	var layout := String(result.get("layout", ""))
	var count := int(result.get("operation_count", -1))
	var input_path := _input_path(layout, count, nonperiodic)
	var input_bytes := FileAccess.get_file_as_bytes(input_path)
	if input_bytes.is_empty() or _sha256(input_bytes) != expected_input \
		or String(result.get("command_sha256", "")) != expected_input:
		_failures.append("restart_frozen_input_identity_invalid")
		_finish(1)
		return
	var commands_variant: Variant = JSON.parse_string(input_bytes.get_string_from_utf8())
	if typeof(commands_variant) != TYPE_ARRAY or (commands_variant as Array).size() != count:
		_failures.append("restart_command_count_invalid")
		_finish(1)
		return
	var region_values: Array = result.get("selected_region", [])
	var chunk_values: Array = result.get("selected_chunk", [])
	if region_values.size() != 2 or chunk_values.size() != 2:
		_failures.append("restart_spatial_identity_invalid")
		_finish(1)
		return
	var region := Vector2i(int(region_values[0]), int(region_values[1]))
	var chunk := Vector2i(int(chunk_values[0]), int(chunk_values[1]))
	var ledger: RefCounted = Brush.new(SEED, 1)
	for index in range(count):
		var command: Dictionary = commands_variant[index]
		if int(command.get("sequence", -1)) != index or int(command.get("revision", -1)) != index + 1:
			_failures.append("restart_sequence_invalid_%d" % index)
			break
		var center_mm: Array = command.get("center_mm", [])
		if center_mm.size() != 3 or int(command.get("radius_mm", -1)) != 580 \
			or String(command.get("mode", "")) != ("CARVE" if index % 2 == 0 else "FILL"):
			_failures.append("restart_command_recipe_invalid_%d" % index)
			break
		var center := Vector3(float(center_mm[0]), float(center_mm[1]), float(center_mm[2])) / 1000.0
		var mode := Brush.Mode.CARVE if String(command.mode) == "CARVE" else Brush.Mode.FILL
		if not ledger.add_sphere(mode, center, 0.58):
			_failures.append("restart_ledger_replay_rejected_%d" % index)
			break
	if not _failures.is_empty():
		_finish(1)
		return
	if int(ledger.revision) != int(result.get("ledger_revision", -1)):
		_failures.append("restart_ledger_revision_mismatch")
	var canonical_projection: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var projection_path := String(result.get("subledger_artifact", {}).get("path", ""))
	if projection_path.is_empty() or _sha256(FileAccess.get_file_as_bytes(projection_path)) != String(result.subledger_artifact.get("sha256", "")):
		_failures.append("restart_subledger_artifact_hash_mismatch")
	else:
		var loaded_projection: RefCounted = ChunkProjection.new()
		var canonical_projection_object: RefCounted = ChunkProjection.from_ledger(ledger, region, chunk)
		if canonical_projection_object == null:
			_failures.append("restart_subledger_rebuild_failed")
		elif not loaded_projection.load_into(projection_path, canonical_projection_object.identity) \
			or loaded_projection.digest() != canonical_projection_object.digest():
			_failures.append("restart_subledger_rebuild_mismatch")
	var maximum_node_error := 0.0
	var loaded_snapshot_count := 0
	var artifacts: Array = result.get("voxel_artifacts", [])
	var voxel_resolutions: Array = result.get("voxel_resolutions", [])
	if artifacts.is_empty() or artifacts.size() != voxel_resolutions.size():
		_failures.append("restart_voxel_artifact_cardinality_invalid")
	for artifact_index in range(artifacts.size()):
		var artifact: Dictionary = artifacts[artifact_index]
		var resolution: Dictionary = voxel_resolutions[artifact_index]
		if not is_equal_approx(float(artifact.get("spacing", -1.0)), float(resolution.get("spacing", -2.0))):
			_failures.append("restart_voxel_resolution_identity_invalid_%d" % artifact_index)
		for arm in ["B", "C"]:
			var artifact_path := String(artifact.get(arm + "_path", ""))
			var expected_hash := String(artifact.get(arm + "_sha256", ""))
			if artifact_path.is_empty() or _sha256(FileAccess.get_file_as_bytes(artifact_path)) != expected_hash:
				_failures.append("restart_voxel_artifact_hash_mismatch_%s_%s" % [arm, artifact.get("spacing", 0.0)])
				continue
			var loaded: RefCounted = Voxel.new()
			if not loaded.load_file(artifact_path, region, chunk, float(artifact.get("spacing", 0.0)), SEED, 1):
				_failures.append("restart_voxel_load_failed_%s_%s" % [arm, artifact.get("spacing", 0.0)])
				continue
			loaded_snapshot_count += 1
			if int(loaded.revision) != int(result.get("ledger_revision", -1)):
				_failures.append("restart_voxel_revision_mismatch_%s_%s" % [arm, artifact.get("spacing", 0.0)])
			for y in range(loaded.ny):
				for z in range(loaded.nz):
					for x in range(loaded.nx):
						var world_point: Vector3 = loaded.world_min + Vector3(x, y, z) * loaded.spacing
						var local_point := world_point - Spatial.region_origin_world(region)
						var expected_density := Brush.sample_density_snapshot(SEED, region, local_point, false, canonical_projection)
						maximum_node_error = maxf(maximum_node_error,
							absf(float(loaded.densities[loaded._index(x, y, z)]) - expected_density))
	var report := {"status": "PASS" if _failures.is_empty() else "FAIL", "source_sha": expected_source,
		"scenario_id": scenario, "run_id": expected_run_id, "command_sha256": expected_input, "operation_count": count,
		"result_sha256": expected_result_sha,
		"fresh_process_restart": true, "loaded_voxel_snapshots": loaded_snapshot_count,
		"expected_voxel_snapshots": result.get("voxel_artifacts", []).size() * 2,
		"maximum_node_error_vs_rebuilt_canonical_chunk_projection": maximum_node_error,
		"failures": _failures}
	var output_file := FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		push_error("restart_report_open_failed")
		quit(2)
		return
	output_file.store_string(JSON.stringify(report, "\t", true) + "\n")
	output_file.flush()
	output_file.close()
	print("P31_R4_RESTART_%s scenario=%s snapshots=%d/%d max_node_error=%.9f failures=%d" % [
		String(report.status), scenario, loaded_snapshot_count, int(report.expected_voxel_snapshots),
		maximum_node_error, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _input_path(layout: String, count: int, nonperiodic: bool) -> String:
	if nonperiodic:
		return "res://tests/fixtures/p3_1_r4/nonperiodic/P31.R3C.NONPERIODIC.%s.N%04d.v1.commands.json" % [layout.to_upper(), count]
	return "res://tests/fixtures/p3_1_r4/issue131/P31.EDIT.%s.N%04d.v1.R01.commands.json" % [layout.to_upper(), count]


func _finish(exit_code: int) -> void:
	print("P31_R4_RESTART_FAIL early=true failures=%s" % JSON.stringify(_failures))
	quit(exit_code)


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
