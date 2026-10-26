extends SceneTree

const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const Picker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const ChunkProjection := preload("res://tests/prototypes/r4_chunk_subledger.gd")
const Voxel := preload("res://tests/prototypes/r4_voxel_snapshot.gd")
const MeshCache := preload("res://tests/prototypes/r4_derived_mesh_cache.gd")

const SEED := 131102026
const R3B_SUMS_SHA := "ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1"
const R3C_SUMS_SHA := "cd0026a32e50c24a8af3bec41044bbbdb4a7aa859754aeffd3ab1b0aa141200b"
const R3B_MANIFEST_SHA := "2dff9ccd5b98e1ea722051b25f961ff8f64c3ae698f3bc12102826e04ec3088d"
const R3C_MANIFEST_SHA := "0facbab3b76bdbee78741d02f57bc8c631c3610cfb8758fd42ac868855a0ee03"
const QUERY_COUNT := 64
const FAILURE_COUNT := 0

var _failures: Array[String] = []
var _source_sha := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_usec()
	var memory_before := OS.get_static_memory_usage()
	var scenario := OS.get_environment("P31_R4_SCENARIO")
	var repeat := int(OS.get_environment("P31_R4_REPEAT"))
	var output_root := OS.get_environment("P31_R4_OUTPUT_DIR")
	var storage_root := OS.get_environment("P31_R4_STORAGE_DIR")
	var mesh_cache_root := OS.get_environment("P31_R4_MESH_CACHE_DIR")
	_source_sha = OS.get_environment("P31_R4_SOURCE_SHA")
	var run_id := OS.get_environment("P31_R4_RUN_ID")
	if not _valid_scenario(scenario) or repeat < 1 or repeat > 5 or run_id != "%s.R%02d" % [scenario, repeat] or output_root.is_empty() \
		or storage_root.is_empty() or mesh_cache_root.is_empty() or not _is_empty_or_absent(output_root):
		push_error("p31_r4_invalid_run_arguments_or_output_root")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_root)
	DirAccess.make_dir_recursive_absolute(storage_root)
	DirAccess.make_dir_recursive_absolute(mesh_cache_root)
	var layout: String = "concentrated" if scenario.contains("CONCENTRATED") else "distributed"
	var count := _scenario_count(scenario)
	var nonperiodic := scenario.begins_with("P31.R4.NONPERIODIC.")
	var input_path := _input_path(scenario, layout, count, nonperiodic)
	var input_sha_path := input_path.trim_suffix(".json") + ".sha256"
	var sums_path := "res://tests/fixtures/p3_1_r4/nonperiodic/SHA256SUMS.txt" if nonperiodic else "res://tests/fixtures/p3_1_r4/issue131/SHA256SUMS.txt"
	var manifest_path := "res://tests/fixtures/p3_1_r4/nonperiodic/scenario-manifest.json" if nonperiodic else "res://tests/fixtures/p3_1_r4/issue131/scenario-manifest.json"
	var expected_sums_sha := R3C_SUMS_SHA if nonperiodic else R3B_SUMS_SHA
	var expected_manifest_sha := R3C_MANIFEST_SHA if nonperiodic else R3B_MANIFEST_SHA
	var input_bytes := FileAccess.get_file_as_bytes(input_path)
	var sidecar_text := FileAccess.get_file_as_string(input_sha_path)
	var command_sha := _sha256(input_bytes)
	var fixture_valid := not input_bytes.is_empty() and _sidecar_matches(input_sha_path, input_path.get_file()) \
		and _sha256(FileAccess.get_file_as_bytes(sums_path)) == expected_sums_sha \
		and _sha256(FileAccess.get_file_as_bytes(manifest_path)) == expected_manifest_sha
	if not fixture_valid:
		_failures.append("fixture_digest_or_manifest_invalid")
		_write_failure(output_root, scenario, repeat, command_sha, started)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(input_bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY or (parsed as Array).size() != count:
		_failures.append("command_count_invalid")
		_write_failure(output_root, scenario, repeat, command_sha, started)
		quit(1)
		return
	var region := Vector2i.ZERO if layout == "concentrated" else Vector2i(-31, -64)
	var chunk := Vector2i.ZERO if layout == "concentrated" else Vector2i(2, 2)
	var ledger: RefCounted = Brush.new(SEED, 1)
	var base_ledger: RefCounted = Brush.new(SEED, 1)
	for index in range(count):
		var command: Dictionary = parsed[index]
		if int(command.get("sequence", -1)) != index or int(command.get("revision", -1)) != index + 1:
			_failures.append("frozen_sequence_revision_invalid_%d" % index)
			break
		var center_mm: Array = command.get("center_mm", [])
		if center_mm.size() != 3 or int(command.get("radius_mm", -1)) != 580:
			_failures.append("frozen_command_geometry_invalid_%d" % index)
			break
		var mode := Brush.Mode.CARVE if String(command.get("mode", "")) == "CARVE" else Brush.Mode.FILL
		if String(command.get("mode", "")) != ("CARVE" if index % 2 == 0 else "FILL"):
			_failures.append("frozen_mode_order_invalid_%d" % index)
			break
		var center := Vector3(float(center_mm[0]), float(center_mm[1]), float(center_mm[2])) / 1000.0
		if index < count - 1 and not base_ledger.add_sphere(mode, center, 0.58):
			_failures.append("base_ledger_reject_%d" % index)
			break
		if not ledger.add_sphere(mode, center, 0.58):
			_failures.append("canonical_ledger_reject_%d" % index)
			break
	if not _failures.is_empty():
		_write_failure(output_root, scenario, repeat, command_sha, started)
		quit(1)
		return
	var full_snapshot: Dictionary = ledger.get_meshing_snapshot()
	var full_query_snapshot: Dictionary = ledger.get_meshing_snapshot()
	var base_full_snapshot: Dictionary = base_ledger.get_meshing_snapshot()
	var base_chunk_snapshot_started := Time.get_ticks_usec()
	var base_chunk_snapshot: Dictionary = base_ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var base_chunk_snapshot_usec := Time.get_ticks_usec() - base_chunk_snapshot_started
	var canonical_snapshot_started := Time.get_ticks_usec()
	var canonical_chunk_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var canonical_chunk_snapshot_usec := Time.get_ticks_usec() - canonical_snapshot_started
	var projection_started := Time.get_ticks_usec()
	var projection: RefCounted = ChunkProjection.from_ledger(ledger, region, chunk)
	var projection_build_usec := Time.get_ticks_usec() - projection_started
	if projection == null:
		_failures.append("chunk_projection_build_failed")
		_write_failure(output_root, scenario, repeat, command_sha, started)
		quit(1)
		return
	var projection_snapshot: Dictionary = projection.as_snapshot()
	var base_projection_started := Time.get_ticks_usec()
	var base_projection: RefCounted = ChunkProjection.from_ledger(base_ledger, region, chunk)
	var base_projection_build_usec := Time.get_ticks_usec() - base_projection_started
	if base_projection == null:
		_failures.append("base_chunk_projection_build_failed")
		_write_failure(output_root, scenario, repeat, command_sha, started)
		quit(1)
		return
	var incremental_projection_started := Time.get_ticks_usec()
	var projection_append_ok: bool = true
	if count > 0:
		projection_append_ok = base_projection.append_snapshot(projection_snapshot)
	else:
		projection_append_ok = base_projection.digest() == projection.digest()
	var projection_append_usec := Time.get_ticks_usec() - incremental_projection_started
	if not projection_append_ok or base_projection.digest() != projection.digest():
		_failures.append("chunk_projection_append_rebuild_mismatch")
	var projection_save_started := Time.get_ticks_usec()
	var projection_save: Dictionary = projection.save_atomic(storage_root.path_join("subledger"))
	var projection_save_usec := Time.get_ticks_usec() - projection_save_started
	var projection_reload: RefCounted = ChunkProjection.new()
	var projection_load_started := Time.get_ticks_usec()
	var projection_load_ok: bool = projection_reload.load_into(String(projection_save.get("path", "")), projection.identity)
	var projection_load_usec := Time.get_ticks_usec() - projection_load_started
	if not bool(projection_save.get("valid", false)) or not projection_load_ok \
		or projection_reload.digest() != projection.digest():
		_failures.append("chunk_projection_save_reload_mismatch")

	var query_full_usec := PackedInt64Array()
	var query_projection_usec := PackedInt64Array()
	var query_voxel_usec := PackedInt64Array()
	var exact_projection_probes := 0
	var voxel_query_probe_count := 0
	var voxel_query_max_error := 0.0
	var voxel_query_abs_errors := PackedFloat64Array()
	var voxel_snapshots: Array[Dictionary] = []
	var voxel_artifacts: Array[Dictionary] = []
	var picker_snapshots: Array[Dictionary] = []
	var cache_mesh_candidate: Dictionary = {}
	var cache_voxel_snapshot_sha := ""
	var snapshot_durations: Array[Dictionary] = []
	var canonical_lod0_started := Time.get_ticks_usec()
	var canonical_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, full_snapshot)
	var canonical_lod0_usec := Time.get_ticks_usec() - canonical_lod0_started
	var canonical_lod1_started := Time.get_ticks_usec()
	var canonical_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, region, chunk, full_snapshot)
	var canonical_lod1_usec := Time.get_ticks_usec() - canonical_lod1_started
	if not bool(canonical_lod0.get("valid", false)) or not bool(canonical_lod1.get("valid", false)):
		_failures.append("canonical_mesh_invalid")
	var projection_lod0_started := Time.get_ticks_usec()
	var projection_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, projection_snapshot)
	var projection_lod0_usec := Time.get_ticks_usec() - projection_lod0_started
	var projection_lod1_started := Time.get_ticks_usec()
	var projection_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, region, chunk, projection_snapshot)
	var projection_lod1_usec := Time.get_ticks_usec() - projection_lod1_started
	var exact_lod0 := _mesh_exact(canonical_lod0, projection_lod0)
	var exact_lod1 := _mesh_exact(canonical_lod1, projection_lod1)
	if not exact_lod0 or not exact_lod1:
		_failures.append("projection_mesh_not_bitwise_equal")
	var probe_started_usec := Time.get_ticks_usec()
	for index in range(QUERY_COUNT):
		var local := _probe_local(region, chunk, index)
		var world := Spatial.region_origin_world(region) + local
		var started_query := Time.get_ticks_usec()
		var expected := Brush.sample_density_snapshot(SEED, region, local, false, full_query_snapshot)
		query_full_usec.append(Time.get_ticks_usec() - started_query)
		started_query = Time.get_ticks_usec()
		var actual := Brush.sample_density_snapshot(SEED, region, local, false, projection_snapshot)
		query_projection_usec.append(Time.get_ticks_usec() - started_query)
		if expected == actual:
			exact_projection_probes += 1
		else:
			_failures.append("projection_density_mismatch_probe_%d" % index)
	var projection_query_wall_usec := Time.get_ticks_usec() - probe_started_usec

	var steps: Array[float] = [0.5]
	if count <= 2048:
		steps.append(0.25)
	if count <= 256:
		steps.append(0.125)
	var last_operation: Dictionary = ledger.get_last_operation_snapshot() if count > 0 else {}
	for step in steps:
		var step_label := String.num(step, 3)
		var base_b := Voxel.new()
		var b_started := Time.get_ticks_usec()
		var b_materialized := base_b.materialize(SEED, region, chunk, base_chunk_snapshot, step)
		var b_materialize_usec := Time.get_ticks_usec() - b_started
		var b_delta_usec := 0
		if count > 0:
			var b_delta_started := Time.get_ticks_usec()
			if not base_b.apply_operation(last_operation):
				_failures.append("B_snapshot_delta_failed_%s" % step_label)
			b_delta_usec = Time.get_ticks_usec() - b_delta_started
		var base_c := Voxel.new()
		var c_started := Time.get_ticks_usec()
		var c_materialized := base_c.materialize(SEED, region, chunk, base_projection.as_snapshot(), step)
		var c_materialize_usec := Time.get_ticks_usec() - c_started
		var c_delta_usec := 0
		var tail_projection_contains_operation: bool = count > 0 and projection_snapshot.sequences.has(int(last_operation.sequence))
		if count > 0 and tail_projection_contains_operation:
			var c_delta_started := Time.get_ticks_usec()
			if not base_c.apply_operation(last_operation):
				_failures.append("C_snapshot_delta_failed_%s" % step_label)
			c_delta_usec = Time.get_ticks_usec() - c_delta_started
		elif count > 0:
			base_c.advance_revision_without_geometry(ledger.revision)
		if not b_materialized or not c_materialized:
			_failures.append("voxel_snapshot_materialize_failed_%s" % step_label)
			continue
		var grid_metrics_b := _compare_snapshot_nodes(base_b, projection_snapshot)
		var grid_metrics_c := _compare_snapshot_nodes(base_c, projection_snapshot)
		if not bool(grid_metrics_b.get("valid", false)) or not bool(grid_metrics_c.get("valid", false)):
			_failures.append("voxel_snapshot_node_oracle_invalid_%s" % step_label)
		var b_stats: Dictionary = base_b.statistics()
		var c_stats: Dictionary = base_c.statistics()
		var b_save_started := Time.get_ticks_usec()
		var b_save := base_b.save_atomic(storage_root.path_join("B-" + step_label))
		var b_save_usec := Time.get_ticks_usec() - b_save_started
		var b_reload := Voxel.new()
		var b_load_started := Time.get_ticks_usec()
		var b_load_ok := b_reload.load_file(String(b_save.get("path", "")), region, chunk, step, SEED, 1)
		var b_load_usec := Time.get_ticks_usec() - b_load_started
		if not bool(b_save.get("valid", false)) or not b_load_ok or b_reload.densities != base_b.densities:
			_failures.append("B_snapshot_restart_mismatch_%s" % step_label)
		var c_save_started := Time.get_ticks_usec()
		var c_save := base_c.save_atomic(storage_root.path_join("C-" + step_label))
		var c_save_usec := Time.get_ticks_usec() - c_save_started
		var c_reload := Voxel.new()
		var c_load_started := Time.get_ticks_usec()
		var c_load_ok := c_reload.load_file(String(c_save.get("path", "")), region, chunk, step, SEED, 1)
		var c_load_usec := Time.get_ticks_usec() - c_load_started
		if not bool(c_save.get("valid", false)) or not c_load_ok or c_reload.densities != base_c.densities:
			_failures.append("C_snapshot_restart_mismatch_%s" % step_label)
		voxel_artifacts.append({"spacing": step, "B_path": String(b_save.get("path", "")),
			"B_sha256": _sha256(FileAccess.get_file_as_bytes(String(b_save.get("path", "")))),
			"C_path": String(c_save.get("path", "")),
			"C_sha256": _sha256(FileAccess.get_file_as_bytes(String(c_save.get("path", ""))))})
		var callback_b := Callable(base_b, "sample_world")
		var callback_c := Callable(base_c, "sample_world")
		var b_lod0_started := Time.get_ticks_usec()
		var b_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, full_snapshot, callback_b)
		var b_lod0_usec := Time.get_ticks_usec() - b_lod0_started
		var b_lod1_started := Time.get_ticks_usec()
		var b_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, region, chunk, full_snapshot, callback_b)
		var b_lod1_usec := Time.get_ticks_usec() - b_lod1_started
		var c_lod0_started := Time.get_ticks_usec()
		var c_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, projection_snapshot, callback_c)
		var c_lod0_usec := Time.get_ticks_usec() - c_lod0_started
		var c_lod1_started := Time.get_ticks_usec()
		var c_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, region, chunk, projection_snapshot, callback_c)
		var c_lod1_usec := Time.get_ticks_usec() - c_lod1_started
		if not bool(b_lod0.get("valid", false)) or not bool(b_lod1.get("valid", false)) \
			or not bool(c_lod0.get("valid", false)) or not bool(c_lod1.get("valid", false)):
			_failures.append("voxel_mesh_invalid_%s" % step_label)
		var b_geometry_lod0 := _surface_metrics(canonical_lod0, b_lod0)
		var b_geometry_lod1 := _surface_metrics(canonical_lod1, b_lod1)
		var c_geometry_lod0 := _surface_metrics(canonical_lod0, c_lod0)
		var c_geometry_lod1 := _surface_metrics(canonical_lod1, c_lod1)
		if is_equal_approx(step, 0.5):
			cache_mesh_candidate = c_lod1
			cache_voxel_snapshot_sha = _sha256(var_to_bytes(base_c.densities))
		var b_query_usec := PackedInt64Array()
		var c_query_usec := PackedInt64Array()
		var b_query_errors := PackedFloat64Array()
		var c_query_errors := PackedFloat64Array()
		for query_index in range(QUERY_COUNT):
			var local_query := _probe_local(region, chunk, query_index)
			var world_query := Spatial.region_origin_world(region) + local_query
			var expected_query := Brush.sample_density_snapshot(SEED, region, local_query, false, full_query_snapshot)
			var query_started := Time.get_ticks_usec()
			var b_query_value := base_b.sample_world(world_query)
			b_query_usec.append(Time.get_ticks_usec() - query_started)
			query_started = Time.get_ticks_usec()
			var c_query_value := base_c.sample_world(world_query)
			c_query_usec.append(Time.get_ticks_usec() - query_started)
			b_query_errors.append(absf(b_query_value - expected_query))
			c_query_errors.append(absf(c_query_value - expected_query))
		var picker_metrics := _run_picker_probes(region, chunk, full_query_snapshot,
			projection_snapshot, base_b, base_c)
		picker_snapshots.append({"spacing": step, "metrics": picker_metrics})
		var resolution_result := {"spacing": step, "B": {"materialize_usec": b_materialize_usec,
			"incremental_update_usec": b_delta_usec, "save_usec": b_save_usec, "load_usec": b_load_usec,
			"save_bytes": int(b_save.get("bytes_written", 0)), "snapshot": b_stats,
			"node_error": grid_metrics_b, "query_usec": _summary(b_query_usec),
			"query_abs_error": _float_summary(b_query_errors), "lod0_build_usec": b_lod0_usec, "lod1_build_usec": b_lod1_usec,
			"lod0_surface": b_geometry_lod0, "lod1_surface": b_geometry_lod1},
			"C": {"materialize_usec": c_materialize_usec, "incremental_update_usec": c_delta_usec,
			"tail_operation_in_projection": tail_projection_contains_operation,
			"save_usec": c_save_usec, "load_usec": c_load_usec,
			"save_bytes": int(c_save.get("bytes_written", 0)), "snapshot": c_stats,
			"node_error": grid_metrics_c, "query_usec": _summary(c_query_usec),
			"query_abs_error": _float_summary(c_query_errors), "lod0_build_usec": c_lod0_usec, "lod1_build_usec": c_lod1_usec,
			"lod0_surface": c_geometry_lod0, "lod1_surface": c_geometry_lod1}}
		voxel_snapshots.append(resolution_result)
	var cave_result := _run_cave_oracle(ledger, region, chunk)
	if int(cave_result.get("projection_mismatches", 0)) != 0:
		_failures.append("canonical_cave_projection_mismatch")
	var row := {"scenario_id": scenario, "run_id": run_id,
		"repeat": repeat, "source_sha": _source_sha, "baseline_sha": "92b442d7f5b605c7bc9c48fac2aceea9d71813aa",
		"command_sha256": command_sha, "operation_count": count, "layout": layout,
		"selected_region": [region.x, region.y], "selected_chunk": [chunk.x, chunk.y],
		"ledger_revision": ledger.revision, "sequence_start": 0 if count > 0 else -1,
		"sequence_end": count - 1, "candidate_operation_count": int(projection_snapshot.get("candidate_operation_count", -1)),
		"subledger_artifact": {"path": String(projection_save.get("path", "")),
			"sha256": _sha256(FileAccess.get_file_as_bytes(String(projection_save.get("path", ""))))},
		"voxel_artifacts": voxel_artifacts,
		"canonical_chunk_snapshot_usec": canonical_chunk_snapshot_usec,
		"B_base_chunk_snapshot_usec": base_chunk_snapshot_usec,
		"A_projection_build_usec": projection_build_usec, "A_base_projection_build_usec": base_projection_build_usec,
		"A_incremental_append_usec": projection_append_usec, "A_persist_usec": projection_save_usec,
		"A_reload_usec": projection_load_usec, "A_persist_bytes": int(projection_save.get("bytes_written", 0)),
		"A_projection_digest": projection.digest(), "A_projection_exact_probes": exact_projection_probes,
		"A_full_query_usec": _summary(query_full_usec), "A_projected_query_usec": _summary(query_projection_usec),
		"A_query_pair_wall_usec": projection_query_wall_usec,
		"canonical_lod0_usec": canonical_lod0_usec, "A_lod0_usec": projection_lod0_usec,
		"canonical_lod1_usec": canonical_lod1_usec, "A_lod1_usec": projection_lod1_usec,
		"A_lod0_exact": exact_lod0, "A_lod1_exact": exact_lod1,
		"voxel_resolutions": voxel_snapshots, "picker_resolutions": picker_snapshots,
		"collision_queries": {"status": "NOT_MEASURED", "reason": "baseline has no terrain collision provider"},
		"cave_oracle": cave_result,
		"storage_bytes": _directory_bytes(storage_root), "mesh_cache_stats": _mesh_cache_run(mesh_cache_root,
			projection, cache_mesh_candidate, cache_voxel_snapshot_sha, region, chunk),
		"static_memory_delta_bytes": OS.get_static_memory_usage() - memory_before,
		"status": "PASS" if _failures.is_empty() else "FAIL", "failures": _failures,
		"duration_usec": Time.get_ticks_usec() - started}
	var result_bytes := (JSON.stringify(row, "\t", true) + "\n").to_utf8_buffer()
	var result_file := FileAccess.open(output_root.path_join("result.json"), FileAccess.WRITE)
	if result_file == null:
		push_error("p31_r4_result_file_open_failed")
		quit(2)
		return
	result_file.store_buffer(result_bytes)
	result_file.flush()
	result_file.close()
	print("P31_R4_%s scenario=%s repeat=%d duration_usec=%d operations=%d projection=%d failures=%d" % [
		String(row.status), scenario, repeat, int(row.duration_usec), count,
		int(row.candidate_operation_count), _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _mesh_cache_run(root: String, projection: RefCounted, derived_mesh: Dictionary,
	voxel_snapshot_sha: String, region: Vector2i, chunk: Vector2i) -> Dictionary:
	var identity := {"world_seed": SEED, "generator_version": 1, "region": region, "chunk": chunk,
		"lod": 1, "projection_sha256": projection.digest(), "voxel_snapshot_sha256": voxel_snapshot_sha,
		"snapshot_resolution": 0.5, "halo_contract": "production-mesh-query-v1",
		"mesher": "lod01-v1"}
	var cache := MeshCache.new(root)
	var cold_started := Time.get_ticks_usec()
	var cold_builder_calls := {"count": 0}
	var cold: Dictionary = cache.get_or_build(identity, func() -> Dictionary:
		cold_builder_calls.count = int(cold_builder_calls.count) + 1
		return derived_mesh)
	var cold_usec := Time.get_ticks_usec() - cold_started
	var warm_started := Time.get_ticks_usec()
	var warm_builder_calls := {"count": 0}
	var warm: Dictionary = cache.get_or_build(identity, func() -> Dictionary:
		warm_builder_calls.count = int(warm_builder_calls.count) + 1
		return {})
	var warm_usec := Time.get_ticks_usec() - warm_started
	var new_cache := MeshCache.new(root)
	var disk_started := Time.get_ticks_usec()
	var disk_builder_calls := {"count": 0}
	var disk: Dictionary = new_cache.get_or_build(identity, func() -> Dictionary:
		disk_builder_calls.count = int(disk_builder_calls.count) + 1
		return {})
	var disk_usec := Time.get_ticks_usec() - disk_started
	if int(cold_builder_calls.count) != 1 or int(warm_builder_calls.count) != 0 \
		or int(disk_builder_calls.count) != 0:
		_failures.append("mesh_cache_builder_invocation_contract")
	if not bool(cold.get("valid", false)) or not bool(warm.get("cache_hit", false)) \
		or not bool(disk.get("cache_hit", false)):
		_failures.append("mesh_cache_cold_warm_disk_contract")
	return {"cold_lookup_usec": cold_usec, "warm_memory_usec": warm_usec, "fresh_instance_disk_usec": disk_usec,
		"input_content_sha256": voxel_snapshot_sha,
		"cold_builder_calls": int(cold_builder_calls.count), "warm_builder_calls": int(warm_builder_calls.count),
		"disk_builder_calls": int(disk_builder_calls.count),
		"cold_result_exact": _mesh_exact(derived_mesh, cold), "warm_hit": bool(warm.get("cache_hit", false)),
		"disk_hit": bool(disk.get("cache_hit", false)), "disk_layer": String(disk.get("cache_layer", "")),
		"stats": cache.stats()}


func _run_cave_oracle(ledger: RefCounted, region: Vector2i, chunk: Vector2i) -> Dictionary:
	var cave_region := Vector2i.ZERO
	var full: Dictionary = ledger.get_meshing_snapshot()
	# The seeded centerline crosses the z=6 chunk boundary. Materialize both
	# adjacent chunks so the diagnostic never labels an out-of-domain query as
	# a cave failure or silently serializes NaN as JSON null.
	var cave_chunks: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 2)]
	var cave_voxels: Array[RefCounted] = []
	var projected_by_chunk: Array[Dictionary] = []
	var voxel_started := Time.get_ticks_usec()
	var voxel_all_valid := true
	for cave_chunk in cave_chunks:
		var projected: Dictionary = ledger.get_meshing_snapshot_for_chunk(cave_region, cave_chunk)
		var voxel: RefCounted = Voxel.new()
		var voxel_ok: bool = voxel.materialize(SEED, cave_region, cave_chunk, projected, 0.5)
		voxel_all_valid = voxel_all_valid and voxel_ok
		projected_by_chunk.append(projected)
		cave_voxels.append(voxel)
	var voxel_materialize_usec := Time.get_ticks_usec() - voxel_started
	var full_open := 0
	var projected_open := 0
	var voxel_open := 0
	var mismatches := 0
	var densities: Array[Dictionary] = []
	var cave_chunk_ids: Array[Array] = []
	for cave_chunk in cave_chunks:
		cave_chunk_ids.append([cave_chunk.x, cave_chunk.y])
	for index in range(9):
		var x := float(index) * 0.5
		var center := Field.cave_center(SEED, cave_region, x)
		var local := Vector3(x, center.y, center.x)
		var world_point := Spatial.region_local_to_world(cave_region, local)
		var expected := Brush.sample_density_snapshot(SEED, cave_region, local, false, full)
		var projection_value := expected
		var voxel_value := NAN
		var voxel_in_bounds := false
		var projections_open := true
		for chunk_index in range(cave_voxels.size()):
			var projected: Dictionary = projected_by_chunk[chunk_index]
			var chunk_value := Brush.sample_density_snapshot(SEED, cave_region, local, false, projected)
			if chunk_index == 0: projection_value = chunk_value
			if chunk_value != expected: mismatches += 1
			if chunk_value >= 0.0: projections_open = false
			var voxel: RefCounted = cave_voxels[chunk_index]
			var candidate: float = voxel.sample_world(world_point)
			if is_finite(candidate):
				voxel_value = candidate
				voxel_in_bounds = true
				break
		if expected < 0.0: full_open += 1
		if projections_open: projected_open += 1
		if voxel_in_bounds and voxel_value < 0.0: voxel_open += 1
		if not voxel_in_bounds: _failures.append("cave_centerline_voxel_query_out_of_bounds_%d" % index)
		densities.append({"x": x, "full": expected, "projection": projection_value,
			"voxel": voxel_value if voxel_in_bounds else null, "voxel_in_bounds": voxel_in_bounds})
	return {"region": [cave_region.x, cave_region.y],
		"chunks": cave_chunk_ids,
		"centerline_samples": 9, "full_open_count": full_open, "projection_open_count": projected_open,
		"voxel_materialize_usec": voxel_materialize_usec, "voxel_valid": voxel_all_valid,
		"voxel_open_count": voxel_open, "projection_mismatches": mismatches, "samples": densities}


func _run_picker_probes(region: Vector2i, chunk: Vector2i, full_snapshot: Dictionary,
		projection_snapshot: Dictionary, voxel_b: RefCounted, voxel_c: RefCounted) -> Dictionary:
	var size := Grid.size_for(chunk)
	var origin := Grid.origin_for(chunk)
	var elapsed := {"canonical": PackedInt64Array(), "projection": PackedInt64Array(),
		"B": PackedInt64Array(), "C": PackedInt64Array()}
	var counts := {"canonical": [], "projection": [], "B": [], "C": []}
	var outcomes: Array[Dictionary] = []
	for ray_index in range(3):
		var local_x := origin.x + size.x * (0.2 + 0.3 * float(ray_index))
		var local_z := origin.z + size.z * (0.22 + 0.27 * float(ray_index))
		# Start in air but within the voxel snapshot's vertical halo.
		var ray_origin := Spatial.region_origin_world(region) + Vector3(local_x,
			Grid.MAX_BOUND.y + Grid.SAMPLE_STEP * 0.2, local_z)
		var direction := Vector3.DOWN
		var per_ray := {"ray_index": ray_index}
		var results := {}
		for kind in ["canonical", "projection", "B", "C"]:
			var counter := {"samples": 0}
			var sampler: Callable
			if kind == "canonical":
				sampler = func(point: Vector3) -> float:
					counter.samples = int(counter.samples) + 1
					return Brush.sample_density_snapshot(SEED, region,
						point - Spatial.region_origin_world(region), false, full_snapshot)
			elif kind == "projection":
				sampler = func(point: Vector3) -> float:
					counter.samples = int(counter.samples) + 1
					return Brush.sample_density_snapshot(SEED, region,
						point - Spatial.region_origin_world(region), false, projection_snapshot)
			elif kind == "B":
				sampler = func(point: Vector3) -> float:
					counter.samples = int(counter.samples) + 1
					return voxel_b.sample_world(point)
			else:
				sampler = func(point: Vector3) -> float:
					counter.samples = int(counter.samples) + 1
					return voxel_c.sample_world(point)
			var started_usec := Time.get_ticks_usec()
			var hit: Dictionary = Picker.pick_sdf_v1_surface(ray_origin, direction, sampler)
			var elapsed_usec := Time.get_ticks_usec() - started_usec
			(elapsed[kind] as PackedInt64Array).append(elapsed_usec)
			(counts[kind] as Array).append(int(counter.samples))
			results[kind] = hit
			per_ray[kind] = {"hit": bool(hit.get("hit", false)), "sample_count": int(counter.samples),
				"elapsed_usec": elapsed_usec,
				"position": [hit.position.x, hit.position.y, hit.position.z] if bool(hit.get("hit", false)) else []}
		var canonical_hit: Dictionary = results.canonical
		var projection_hit: Dictionary = results.projection
		per_ray["projection_hit_match"] = bool(canonical_hit.get("hit", false)) == bool(projection_hit.get("hit", false))
		if bool(canonical_hit.get("hit", false)) and bool(projection_hit.get("hit", false)):
			per_ray["projection_hit_distance"] = canonical_hit.position.distance_to(projection_hit.position)
		else:
			per_ray["projection_hit_distance"] = null
		for kind in ["B", "C"]:
			var variant_hit: Dictionary = results[kind]
			per_ray[kind + "_hit_match"] = bool(canonical_hit.get("hit", false)) == bool(variant_hit.get("hit", false))
			per_ray[kind + "_hit_distance"] = canonical_hit.position.distance_to(variant_hit.position) \
				if bool(canonical_hit.get("hit", false)) and bool(variant_hit.get("hit", false)) else null
		outcomes.append(per_ray)
	var summaries := {}
	for kind in ["canonical", "projection", "B", "C"]:
		summaries[kind] = {"elapsed_usec": _summary(elapsed[kind]), "samples": counts[kind]}
	return {"rays": outcomes, "arms": summaries,
		"all_projection_hits_match": outcomes.all(func(item: Dictionary) -> bool: return bool(item.projection_hit_match)),
		"note": "headless SDF ray-picker timings; not input-to-presented-frame latency"}


func _compare_snapshot_nodes(voxel: RefCounted, full_snapshot: Dictionary) -> Dictionary:
	var errors := PackedFloat64Array()
	var exact_count := 0
	var comparisons := 0
	var region: Vector2i = voxel.region
	for y in range(voxel.ny):
		for z in range(voxel.nz):
			for x in range(voxel.nx):
				var point: Vector3 = voxel.world_min + Vector3(x, y, z) * voxel.spacing
				var local := point - Spatial.region_origin_world(region)
				var expected := Brush.sample_density_snapshot(SEED, region, local, false, full_snapshot)
				var actual := float(voxel.densities[voxel._index(x, y, z)])
				if not is_finite(expected) or not is_finite(actual):
					return {"valid": false, "reason": "nonfinite_density", "compared_nodes": comparisons}
				var error := absf(actual - expected)
				errors.append(error)
				if error == 0.0: exact_count += 1
				comparisons += 1
	return {"valid": true, "reference": "canonical_chunk_projection_with_separate_full-ledger probe and mesh parity",
		"compared_nodes": comparisons, "exact_node_count": exact_count,
		"max_abs_error": _max_float(errors), "mean_abs_error": _mean_float(errors),
		"abs_error_quantiles": _float_summary(errors)}


func _surface_metrics(reference: Dictionary, candidate: Dictionary) -> Dictionary:
	var ref_pos: PackedVector3Array = reference.get("positions", PackedVector3Array())
	var ref_norm: PackedVector3Array = reference.get("normals", PackedVector3Array())
	var cand_pos: PackedVector3Array = candidate.get("positions", PackedVector3Array())
	var cand_norm: PackedVector3Array = candidate.get("normals", PackedVector3Array())
	if ref_pos.is_empty() or cand_pos.is_empty() or ref_pos.size() % 3 != 0 or cand_pos.size() % 3 != 0:
		return {"valid": false, "reason": "empty_or_malformed_surface"}
	var distances := PackedFloat64Array()
	var angles := PackedFloat64Array()
	var ref_sample_step := maxi(1, ceili(float(ref_pos.size()) / 128.0))
	var cand_sample_step := maxi(1, ceili(float(cand_pos.size()) / 128.0))
	var forward := _directed_surface_metrics(ref_pos, ref_norm, cand_pos, cand_norm, ref_sample_step)
	var backward := _directed_surface_metrics(cand_pos, cand_norm, ref_pos, ref_norm, cand_sample_step)
	if not bool(forward.get("valid", false)) or not bool(backward.get("valid", false)):
		return {"valid": false, "reason": "surface_distance_failed"}
	for value in forward.distances: distances.append(float(value))
	for value in backward.distances: distances.append(float(value))
	for value in forward.normal_angles_deg: angles.append(float(value))
	for value in backward.normal_angles_deg: angles.append(float(value))
	return {"valid": true, "sampled_symmetric_vertex_to_triangle_distance": _float_summary(distances),
		"sampled_normal_angle_deg": _float_summary(angles), "reference_vertices": ref_pos.size(),
		"candidate_vertices": cand_pos.size(), "reference_sample_step": ref_sample_step,
		"candidate_sample_step": cand_sample_step,
		"metric_note": "bounded symmetric vertex-sampled point-to-triangle estimate; not certified Hausdorff distance"}


func _directed_surface_metrics(source: PackedVector3Array, source_normals: PackedVector3Array,
	target: PackedVector3Array, target_normals: PackedVector3Array, sample_step: int) -> Dictionary:
	var distances := PackedFloat64Array()
	var normal_angles := PackedFloat64Array()
	for source_index in range(0, source.size(), sample_step):
		var point := source[source_index]
		var minimum_distance_squared := INF
		var nearest_normal := Vector3.ZERO
		for tri_start in range(0, target.size(), 3):
			var a := target[tri_start]
			var b := target[tri_start + 1]
			var c := target[tri_start + 2]
			var closest := _closest_point_triangle(point, a, b, c)
			var distance_squared := point.distance_squared_to(closest)
			if distance_squared < minimum_distance_squared:
				minimum_distance_squared = distance_squared
				nearest_normal = (target_normals[tri_start] + target_normals[tri_start + 1] + target_normals[tri_start + 2]).normalized()
		var source_normal := source_normals[source_index].normalized()
		distances.append(sqrt(maxf(0.0, minimum_distance_squared)))
		normal_angles.append(rad_to_deg(source_normal.angle_to(nearest_normal)))
	return {"valid": not distances.is_empty(), "distances": distances, "normal_angles_deg": normal_angles}


func _closest_point_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	var v := vb * denominator
	var w := vc * denominator
	return a + ab * v + ac * w


func _probe_local(region: Vector2i, chunk: Vector2i, index: int) -> Vector3:
	var chunk_origin := Grid.origin_for(chunk)
	var size := Grid.size_for(chunk)
	var x := chunk_origin.x + 0.26 + float(posmod(index * 37, 997)) / 997.0 * (size.x - 0.52)
	var z := chunk_origin.z + 0.26 + float(posmod(index * 53, 991)) / 991.0 * (size.z - 0.52)
	var y := Grid.MIN_BOUND.y + 0.3 + float(posmod(index * 71, 983)) / 983.0 * (Grid.MAX_BOUND.y - Grid.MIN_BOUND.y - 0.6)
	return Vector3(x, y, z)


func _input_path(scenario: String, layout: String, count: int, nonperiodic: bool) -> String:
	if nonperiodic:
		return "res://tests/fixtures/p3_1_r4/nonperiodic/P31.R3C.NONPERIODIC.%s.N%04d.v1.commands.json" % [layout.to_upper(), count]
	return "res://tests/fixtures/p3_1_r4/issue131/P31.EDIT.%s.N%04d.v1.R01.commands.json" % [layout.to_upper(), count]


func _sidecar_matches(sidecar_path: String, filename: String) -> bool:
	var text := FileAccess.get_file_as_string(sidecar_path)
	if text.is_empty(): return false
	var first_line := text.strip_edges().get_slice("\n", 0).strip_edges()
	var pieces := first_line.split(" ", false)
	return pieces.size() >= 1 and String(pieces[0]).to_lower() == _sha256(FileAccess.get_file_as_bytes(_sidecar_source_path(sidecar_path, filename)))


func _sidecar_source_path(sidecar_path: String, filename: String) -> String:
	return sidecar_path.trim_suffix(".sha256") + ".json"


func _valid_scenario(scenario: String) -> bool:
	var parts := scenario.split(".")
	return parts.size() >= 5 and (scenario.begins_with("P31.R4.EDIT.") or scenario.begins_with("P31.R4.NONPERIODIC.")) \
		and ["CONCENTRATED", "DISTRIBUTED"].has(parts[3] if parts.size() > 3 else "") \
		and ["N0000", "N0256", "N0640", "N2048", "N8192"].has(parts[4] if scenario.begins_with("P31.R4.EDIT.") else parts[4])


func _scenario_count(scenario: String) -> int:
	var pieces := scenario.split(".")
	var token := pieces[4] if pieces.size() > 4 else "N0000"
	return int(token.trim_prefix("N"))


func _is_empty_or_absent(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path): return true
	return DirAccess.get_files_at(path).is_empty() and DirAccess.get_directories_at(path).is_empty()


func _mesh_exact(a: Dictionary, b: Dictionary) -> bool:
	return bool(a.get("valid", false)) and bool(b.get("valid", false)) \
		and a.get("positions", PackedVector3Array()) == b.get("positions", PackedVector3Array()) \
		and a.get("normals", PackedVector3Array()) == b.get("normals", PackedVector3Array()) \
		and int(a.get("triangle_count", -1)) == int(b.get("triangle_count", -2))


func _summary(values: PackedInt64Array) -> Dictionary:
	var copy: Array[int] = []
	for value in values: copy.append(value)
	copy.sort()
	return {"count": copy.size(), "p50_usec": _percentile(copy, 0.50), "p95_usec": _percentile(copy, 0.95),
		"p99_usec": _percentile(copy, 0.99), "max_usec": copy[-1] if not copy.is_empty() else -1}


func _float_summary(values: PackedFloat64Array) -> Dictionary:
	var copy: Array[float] = []
	for value in values: copy.append(value)
	copy.sort()
	return {"count": copy.size(), "p50": _float_percentile(copy, 0.50),
		"p95": _float_percentile(copy, 0.95), "p99": _float_percentile(copy, 0.99),
		"max": copy[-1] if not copy.is_empty() else -1.0}


func _percentile(values: Array[int], q: float) -> int:
	if values.is_empty(): return -1
	return values[clampi(ceili(float(values.size()) * q) - 1, 0, values.size() - 1)]


func _float_percentile(values: Array[float], q: float) -> float:
	if values.is_empty(): return -1.0
	return values[clampi(ceili(float(values.size()) * q) - 1, 0, values.size() - 1)]


func _max_float(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values: result = maxf(result, value)
	return result


func _mean_float(values: PackedFloat64Array) -> float:
	if values.is_empty(): return 0.0
	var total := 0.0
	for value in values: total += value
	return total / float(values.size())


func _directory_bytes(path: String) -> int:
	var total := 0
	for name in DirAccess.get_files_at(path):
		total += int(FileAccess.get_file_as_bytes(path.path_join(name)).size())
	return total


func _write_failure(root: String, scenario: String, repeat: int, command_sha: String, started: int) -> void:
	var report := {"scenario_id": scenario, "repeat": repeat, "run_id": OS.get_environment("P31_R4_RUN_ID"), "source_sha": _source_sha,
		"command_sha256": command_sha, "status": "FAIL", "failures": _failures,
		"duration_usec": Time.get_ticks_usec() - started}
	var file := FileAccess.open(root.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true) + "\n")
		file.close()
	push_error("p31_r4_benchmark_failed: " + ",".join(_failures))


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
