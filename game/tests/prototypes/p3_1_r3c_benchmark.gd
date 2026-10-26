extends SceneTree

const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const ExactReplay := preload("res://tests/prototypes/r3b_exact_replay.gd")
const MeshCache := preload("res://tests/prototypes/r3c_profile_cache.gd")

const SEED := 131102026
const R3B_SUMS_SHA := "ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1"
const R3C_SUMS_SHA := "cd0026a32e50c24a8af3bec41044bbbdb4a7aa859754aeffd3ab1b0aa141200b"
const R3C_MANIFEST_SHA := "0facbab3b76bdbee78741d02f57bc8c631c3610cfb8758fd42ac868855a0ee03"
const RUNS_IN_PROCESS := 3
const QUERY_PROBES := 64

var _failures: Array[String] = []
var _memory_before := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var start_usec := Time.get_ticks_usec()
	_memory_before = OS.get_static_memory_usage()
	var scenario := OS.get_environment("P31_R3C_SCENARIO")
	var repeat := int(OS.get_environment("P31_R3C_REPEAT"))
	var source_sha := OS.get_environment("P31_R3C_SOURCE_SHA")
	var output_root := OS.get_environment("P31_R3C_OUTPUT_DIR")
	var cache_root := OS.get_environment("P31_R3C_CACHE_DIR")
	if not _valid_scenario(scenario) or repeat < 1 or repeat > 5 or output_root.is_empty() or cache_root.is_empty():
		push_error("r3c_invalid_or_missing_run_arguments")
		quit(2)
		return
	if DirAccess.dir_exists_absolute(output_root) and (not DirAccess.get_files_at(output_root).is_empty() or not DirAccess.get_directories_at(output_root).is_empty()):
		push_error("r3c_output_directory_must_be_new_and_empty")
		quit(2)
	DirAccess.make_dir_recursive_absolute(output_root)
	var nonperiodic := scenario.begins_with("NONPERIODIC-")
	var selection := scenario.trim_prefix("NONPERIODIC-") if nonperiodic else scenario
	var separator := selection.rfind("-")
	var layout := selection.substr(0, separator).to_lower()
	var count := int(selection.substr(separator + 1))
	var input_stem: String
	var input_path: String
	var input_sha_path: String
	var sums_path: String
	if nonperiodic:
		input_stem = "P31.R3C.NONPERIODIC.%s.N%04d.v1" % [layout.to_upper(), count]
		input_path = "res://tests/fixtures/p3_1_r3c/nonperiodic/" + input_stem + ".commands.json"
		input_sha_path = "res://tests/fixtures/p3_1_r3c/nonperiodic/" + input_stem + ".commands.sha256"
		sums_path = "res://tests/fixtures/p3_1_r3c/nonperiodic/SHA256SUMS.txt"
	else:
		input_stem = "P31.EDIT.%s.N%04d.v1.R01.commands" % [layout.to_upper(), count]
		input_path = "res://tests/fixtures/p3_1_r3b/issue131/" + input_stem + ".json"
		input_sha_path = "res://tests/fixtures/p3_1_r3b/issue131/" + input_stem + ".sha256"
		sums_path = "res://tests/fixtures/p3_1_r3b/issue131/SHA256SUMS.txt"
	var input_bytes := FileAccess.get_file_as_bytes(input_path)
	var expected_input_hash := FileAccess.get_file_as_string(input_sha_path).strip_edges()
	var expected_sums_hash := R3C_SUMS_SHA if nonperiodic else R3B_SUMS_SHA
	if input_bytes.is_empty() or _sha256(input_bytes) != expected_input_hash or _sha256(FileAccess.get_file_as_bytes(sums_path)) != expected_sums_hash:
		push_error("r3c_frozen_fixture_digest_mismatch")
		quit(1)
		return
	if nonperiodic and _sha256(FileAccess.get_file_as_bytes("res://tests/fixtures/p3_1_r3c/nonperiodic/scenario-manifest.json")) != R3C_MANIFEST_SHA:
		push_error("r3c_manifest_digest_mismatch")
		quit(1)
		return
	var expected_scenario_id := "P31.R3C.NONPERIODIC.%s.N%04d.v1" % [layout.to_upper(), count] if nonperiodic else "P31.R3B.%s.v1" % scenario
	if nonperiodic:
		var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/p3_1_r3c/nonperiodic/scenario-manifest.json"))
		var manifest_match: Dictionary = {}
		if typeof(manifest_value) == TYPE_DICTIONARY:
			for entry_value in manifest_value.get("scenarios", []):
				if typeof(entry_value) == TYPE_DICTIONARY and String(entry_value.get("scenario_id", "")) == expected_scenario_id:
					manifest_match = entry_value
					break
		var expected_region := [0, 0] if layout == "concentrated" else [-31, -64]
		var expected_chunk := [0, 0] if layout == "concentrated" else [2, 2]
		var manifest_mismatches: Array[String] = []
		if manifest_match.is_empty():
			manifest_mismatches.append("scenario_id")
		else:
			if String(manifest_match.get("command_file", "")) != input_stem + ".commands.json":
				manifest_mismatches.append("command_file")
			if String(manifest_match.get("command_sha256", "")) != expected_input_hash:
				manifest_mismatches.append("command_sha256")
			if int(manifest_match.get("count", -1)) != count:
				manifest_mismatches.append("count")
			if not _integer_array_matches(manifest_match.get("selected_region", null), expected_region):
				manifest_mismatches.append("selected_region")
			if not _integer_array_matches(manifest_match.get("selected_chunk", null), expected_chunk):
				manifest_mismatches.append("selected_chunk")
		if not manifest_mismatches.is_empty():
			push_error("r3c_scenario_manifest_entry_mismatch: " + ",".join(manifest_mismatches))
			quit(1)
			return
	var parsed: Variant = JSON.parse_string(input_bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY or (parsed as Array).size() != count:
		push_error("r3c_frozen_command_count_mismatch")
		quit(1)
		return
	var ledger: RefCounted = Brush.new(SEED, 1)
	var unique_center_keys := {}
	var unique_command_tokens := {}
	for index in range(count):
		var command: Dictionary = parsed[index]
		if int(command.get("sequence", -1)) != index or int(command.get("revision", -1)) != index + 1:
			_failures.append("sequence_or_revision_mismatch_%d" % index)
			break
		var center_mm: Array = command.get("center_mm", [])
		var radius_mm := int(command.get("radius_mm", -1))
		if center_mm.size() != 3 or (not nonperiodic and radius_mm != 580) or (nonperiodic and (radius_mm < int(Brush.MIN_RADIUS * 1000.0) or radius_mm > 1200)):
			_failures.append("frozen_command_shape_invalid_%d" % index)
			break
		if nonperiodic:
			var center_key := "%d,%d,%d" % [int(center_mm[0]), int(center_mm[1]), int(center_mm[2])]
			var token := "%s|%d|%s" % [center_key, radius_mm, String(command.get("mode", ""))]
			if unique_center_keys.has(center_key) or unique_command_tokens.has(token):
				_failures.append("nonperiodic_duplicate_center_or_command_%d" % index)
				break
			unique_center_keys[center_key] = true
			unique_command_tokens[token] = true
			var expected_mode := "CARVE" if index % 2 == 0 else "FILL"
			if String(command.get("mode", "")) != expected_mode:
				_failures.append("nonperiodic_mode_order_invalid_%d" % index)
				break
		var mode: int = Brush.Mode.CARVE if command.get("mode", "") == "CARVE" else Brush.Mode.FILL
		var center := Vector3(float(center_mm[0]), float(center_mm[1]), float(center_mm[2])) / 1000.0
		if not ledger.add_sphere(mode, center, float(radius_mm) / 1000.0):
			_failures.append("ledger_rejected_frozen_command_%d" % index)
			break
	if not _failures.is_empty():
		_write_fail(output_root, scenario, repeat, source_sha)
		quit(1)
		return
	var region := Vector2i.ZERO if layout == "concentrated" else Vector2i(-31, -64)
	var chunk := Vector2i.ZERO if layout == "concentrated" else Vector2i(2, 2)
	var snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	if not bool(snapshot.get("valid", true)):
		_failures.append("canonical_meshing_snapshot_invalid")
	var full_snapshot: Dictionary = ledger.get_meshing_snapshot()
	var exact_init_started := Time.get_ticks_usec()
	var exact: RefCounted = ExactReplay.new(SEED, snapshot, region)
	var exact_init_usec := Time.get_ticks_usec() - exact_init_started
	var exact_world_init_started := Time.get_ticks_usec()
	var exact_world: RefCounted = ExactReplay.new(SEED, snapshot)
	var exact_world_init_usec := Time.get_ticks_usec() - exact_world_init_started
	var exact_query_init_started := Time.get_ticks_usec()
	var exact_query: RefCounted = ExactReplay.new(SEED, full_snapshot)
	var exact_query_init_usec := Time.get_ticks_usec() - exact_query_init_started
	var baseline_query_usec := PackedInt64Array()
	var optimized_query_usec := PackedInt64Array()
	var query_mismatches := 0
	for probe_index in range(QUERY_PROBES):
		var point := _probe(region, chunk, probe_index)
		var expected := _canonical_world_sample(point, full_snapshot)
		var actual: float = exact_query.sample_density(point)
		if expected != actual:
			query_mismatches += 1
		for loop_index in range(RUNS_IN_PROCESS):
			var started := Time.get_ticks_usec()
			if (repeat + probe_index + loop_index) % 2 == 0:
				var baseline := _canonical_world_sample(point, full_snapshot)
				baseline_query_usec.append(Time.get_ticks_usec() - started)
				started = Time.get_ticks_usec()
				var optimized: float = exact_query.sample_density(point) if exact_query.can_reduce_exact_replay() else _canonical_world_sample(point, full_snapshot)
				optimized_query_usec.append(Time.get_ticks_usec() - started)
				if baseline != optimized:
					query_mismatches += 1
			else:
				var optimized: float = exact_query.sample_density(point) if exact_query.can_reduce_exact_replay() else _canonical_world_sample(point, full_snapshot)
				optimized_query_usec.append(Time.get_ticks_usec() - started)
				started = Time.get_ticks_usec()
				var baseline := _canonical_world_sample(point, full_snapshot)
				baseline_query_usec.append(Time.get_ticks_usec() - started)
				if baseline != optimized:
					query_mismatches += 1
	if query_mismatches > 0:
		_failures.append("exact_sdf_query_mismatches_%d" % query_mismatches)
	var callback_lod0 := Callable(exact, "sample_density")
	var callback_lod1 := Callable(exact_world, "sample_density")
	var mesh_samples := {"lod0": {"baseline": PackedInt64Array(), "optimized": PackedInt64Array()}, "lod1": {"baseline": PackedInt64Array(), "optimized": PackedInt64Array()}}
	var canonical_meshes := {}
	var optimized_meshes := {}
	for lod in [0, 1]:
		for iteration in range(RUNS_IN_PROCESS):
			var baseline_mesh: Dictionary
			var optimized_mesh: Dictionary
			var baseline_elapsed := 0
			var optimized_elapsed := 0
			var baseline_first: bool = (repeat + iteration + lod) % 2 == 0
			for phase in range(2):
				var run_baseline: bool = baseline_first if phase == 0 else not baseline_first
				var phase_started := Time.get_ticks_usec()
				var built: Dictionary
				if run_baseline:
					built = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, snapshot) if lod == 0 else LodMesher.build_chunk_cpu_data(SEED, region, chunk, snapshot)
					baseline_elapsed = Time.get_ticks_usec() - phase_started
					baseline_mesh = built
				else:
					if (lod == 0 and exact.can_reduce_exact_replay()) or (lod == 1 and exact_world.can_reduce_exact_replay()):
						built = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, {}, callback_lod0) if lod == 0 else LodMesher.build_chunk_cpu_data(SEED, region, chunk, snapshot, callback_lod1)
					else:
						built = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, snapshot) if lod == 0 else LodMesher.build_chunk_cpu_data(SEED, region, chunk, snapshot)
					optimized_elapsed = Time.get_ticks_usec() - phase_started
					optimized_mesh = built
			var name := "lod%d" % lod
			mesh_samples[name].baseline.append(baseline_elapsed)
			mesh_samples[name].optimized.append(optimized_elapsed)
			if not bool(baseline_mesh.get("valid", false)) or not bool(optimized_mesh.get("valid", false)) or not _mesh_exact(baseline_mesh, optimized_mesh):
				_failures.append("lod%d_exact_geometry_mismatch_iter_%d" % [lod, iteration])
			canonical_meshes[name] = baseline_mesh
			optimized_meshes[name] = optimized_mesh
	var lod0_mesh_equal: bool = _mesh_exact(canonical_meshes.get("lod0", {}), optimized_meshes.get("lod0", {}))
	var lod1_mesh_equal: bool = _mesh_exact(canonical_meshes.get("lod1", {}), optimized_meshes.get("lod1", {}))
	var mesh_data: Dictionary = canonical_meshes.get("lod1", {})
	var mesh_serialization_start := Time.get_ticks_usec()
	var serialized_mesh := var_to_bytes(mesh_data)
	var mesh_serialization_usec := Time.get_ticks_usec() - mesh_serialization_start
	var array_mesh_start := Time.get_ticks_usec()
	var array_mesh_input: Dictionary = canonical_meshes.get("lod0", {}).duplicate(true)
	var array_mesh_result: Dictionary = Mesher.mesh_from_cpu_data(array_mesh_input)
	var array_mesh_usec := Time.get_ticks_usec() - array_mesh_start
	if not bool(array_mesh_result.get("valid", false)):
		_failures.append("array_mesh_construction_invalid")
	var identity_started := Time.get_ticks_usec()
	var identity := _cache_identity(snapshot, region, chunk, 1)
	var identity_lod1_build_usec := Time.get_ticks_usec() - identity_started
	var cache: RefCounted = MeshCache.new(cache_root)
	var cache_init_timings: Dictionary = cache.last_timings_usec.duplicate(true)
	var identity_lod0 := _cache_identity(snapshot, region, chunk, 0)
	var lod0_cache_start := Time.get_ticks_usec()
	var lod0_cache_result: Dictionary = cache.get_or_build(identity_lod0, func() -> Dictionary: return Mesher.build_chunk_cpu_data(SEED, region, chunk, false, snapshot))
	var lod0_cache_cold_usec := Time.get_ticks_usec() - lod0_cache_start
	var lod0_cache_builder_usec := int(cache.last_builder_usec)
	if not bool(lod0_cache_result.get("valid", false)) or not _mesh_exact(canonical_meshes.lod0, lod0_cache_result):
		_failures.append("lod0_cache_cold_result_mismatch")
	var lod0_warm_start := Time.get_ticks_usec()
	var lod0_warm_hit: Dictionary = cache.get_or_build(identity_lod0, func() -> Dictionary: return {})
	var lod0_warm_usec := Time.get_ticks_usec() - lod0_warm_start
	if not bool(lod0_warm_hit.get("cache_hit", false)):
		_failures.append("lod0_cache_memory_hit_missing")
	var fresh_cache_lod0: RefCounted = MeshCache.new(cache_root)
	var lod0_disk_start := Time.get_ticks_usec()
	var lod0_disk_hit: Dictionary = fresh_cache_lod0.get_or_build(identity_lod0, func() -> Dictionary: return {})
	var lod0_disk_usec := Time.get_ticks_usec() - lod0_disk_start
	if not bool(lod0_disk_hit.get("cache_hit", false)) or String(lod0_disk_hit.get("cache_layer", "")) != "disk":
		_failures.append("lod0_fresh_instance_disk_hit_missing")
	var cold_total_start := Time.get_ticks_usec()
	var cache_result: Dictionary = cache.get_or_build(identity, func() -> Dictionary:
		return LodMesher.build_chunk_cpu_data(SEED, region, chunk, snapshot)
	)
	var cache_first_lookup_usec := Time.get_ticks_usec() - cold_total_start
	var cold_builder_usec := int(cache.last_builder_usec)
	var cache_first_call_timings: Dictionary = cache.last_timings_usec.duplicate(true)
	if not bool(cache_result.get("valid", false)) or not _mesh_exact(mesh_data, cache_result):
		_failures.append("cache_first_result_mismatch")
	var memory_start := Time.get_ticks_usec()
	var memory_hit: Dictionary = cache.get_or_build(identity, func() -> Dictionary: return {})
	var memory_hit_usec := Time.get_ticks_usec() - memory_start
	if not bool(memory_hit.get("valid", false)) or not bool(memory_hit.get("cache_hit", false)):
		_failures.append("cache_warm_memory_hit_missing")
	var disk_cache: RefCounted = MeshCache.new(cache_root)
	var disk_start := Time.get_ticks_usec()
	var disk_hit: Dictionary = disk_cache.get_or_build(identity, func() -> Dictionary: return {})
	var disk_hit_usec := Time.get_ticks_usec() - disk_start
	if not bool(disk_hit.get("valid", false)) or not bool(disk_hit.get("cache_hit", false)) or String(disk_hit.get("cache_layer", "")) != "disk":
		_failures.append("cache_fresh_instance_disk_hit_missing")
	var remote_ledger: RefCounted = _copy_ledger(ledger)
	var remote_center := Spatial.region_origin_world(region + Vector2i(2000, -2000)) + Vector3(3.0, 2.0, 3.0)
	if not remote_ledger.add_sphere(Brush.Mode.CARVE, remote_center, 0.58):
		_failures.append("remote_edit_add_failed")
	var remote_snapshot: Dictionary = remote_ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var remote_identity := _cache_identity(remote_snapshot, region, chunk, 1)
	var remote_identity_lod0 := _cache_identity(remote_snapshot, region, chunk, 0)
	if remote_identity.key != identity.key:
		_failures.append("remote_edit_changed_local_cache_identity")
	if remote_identity_lod0.key != identity_lod0.key:
		_failures.append("remote_edit_changed_lod0_cache_identity")
	var remote_cache: RefCounted = MeshCache.new(cache_root)
	var remote_start := Time.get_ticks_usec()
	var remote_result: Dictionary = remote_cache.get_or_build(remote_identity, func() -> Dictionary: return {})
	var remote_lookup_usec := Time.get_ticks_usec() - remote_start
	if not bool(remote_result.get("cache_hit", false)):
		_failures.append("remote_edit_did_not_hit_chunk_cache")
	var remote_lod0_result: Dictionary = remote_cache.get_or_build(remote_identity_lod0, func() -> Dictionary: return {})
	if not bool(remote_lod0_result.get("cache_hit", false)):
		_failures.append("remote_edit_did_not_hit_lod0_chunk_cache")
	var edited_ledger: RefCounted = _copy_ledger(ledger)
	var local_edit_center := Spatial.region_origin_world(region) + Grid.origin_for(chunk) + Vector3(1.0 + float(repeat) * 0.01, 2.5, 1.0)
	if not edited_ledger.add_sphere(Brush.Mode.FILL, local_edit_center, 0.58):
		_failures.append("local_edit_add_failed")
	var edited_snapshot: Dictionary = edited_ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var edited_identity := _cache_identity(edited_snapshot, region, chunk, 1)
	var local_cache: RefCounted = MeshCache.new(cache_root)
	var local_start := Time.get_ticks_usec()
	var local_result: Dictionary = local_cache.get_or_build(edited_identity, func() -> Dictionary: return LodMesher.build_chunk_cpu_data(SEED, region, chunk, edited_snapshot))
	var local_rebuild_usec := Time.get_ticks_usec() - local_start
	var local_builder_usec := int(local_cache.last_builder_usec)
	if edited_identity.key == identity.key or not bool(local_result.get("valid", false)) or bool(local_result.get("cache_hit", true)):
		_failures.append("local_edit_failed_to_invalidate_chunk_cache")
	if not _mesh_exact(LodMesher.build_chunk_cpu_data(SEED, region, chunk, edited_snapshot), local_result):
		_failures.append("post_edit_cache_mesh_mismatch")
	var edited_identity_lod0 := _cache_identity(edited_snapshot, region, chunk, 0)
	var local_lod0_result: Dictionary = local_cache.get_or_build(edited_identity_lod0, func() -> Dictionary: return Mesher.build_chunk_cpu_data(SEED, region, chunk, false, edited_snapshot))
	var local_lod0_builder_usec := int(local_cache.last_builder_usec)
	if edited_identity_lod0.key == identity_lod0.key or bool(local_lod0_result.get("cache_hit", true)) or not _mesh_exact(Mesher.build_chunk_cpu_data(SEED, region, chunk, false, edited_snapshot), local_lod0_result):
		_failures.append("lod0_local_edit_cache_miss_or_rebuild_mismatch")
	var scenario_run_id := "P31.R3C.NONPERIODIC.%s.N%04d.R%02d" % [layout.to_upper(), count, repeat] if nonperiodic else "P31.R3B.%s.R%02d" % [scenario, repeat]
	var row := {
		"scenario_id": expected_scenario_id, "run_id": scenario_run_id, "repeat": repeat,
		"source_sha": source_sha, "baseline_sha": "92b442d7f5b605c7bc9c48fac2aceea9d71813aa", "seed": SEED,
		"operation_count": count, "layout": layout, "command_sha256": _sha256(input_bytes),
		"query_strategy": "exact_period_reduction" if exact_query.can_reduce_exact_replay() else "canonical_fallback_no_reduction",
		"mesh_strategy": "exact_period_reduction" if exact.can_reduce_exact_replay() or exact_world.can_reduce_exact_replay() else "canonical_fallback_no_reduction",
		"meshing_candidate_count": int(snapshot.get("candidate_operation_count", -1)), "query_mismatches": query_mismatches,
		"baseline_query_us": _summary(baseline_query_usec), "optimized_query_us": _summary(optimized_query_usec), "replay_stats": exact_query.stats(),
		"lod0_baseline_build_us": _summary(mesh_samples.lod0.baseline), "lod0_optimized_build_us": _summary(mesh_samples.lod0.optimized),
		"lod1_baseline_build_us": _summary(mesh_samples.lod1.baseline), "lod1_optimized_build_us": _summary(mesh_samples.lod1.optimized),
		"lod0_mesh_equal": lod0_mesh_equal, "lod1_mesh_equal": lod1_mesh_equal,
		"canonical_lod0_samples": int(canonical_meshes.lod0.get("sample_count", 0)), "canonical_lod1_samples": int(canonical_meshes.lod1.get("sample_count", 0)),
		"lod0_phase_timings_us": canonical_meshes.lod0.get("timings_usec", {}), "lod1_phase_timings_us": canonical_meshes.lod1.get("timings_usec", {}),
		"exact_snapshot_init_us": exact_init_usec, "exact_world_snapshot_init_us": exact_world_init_usec, "exact_full_query_init_us": exact_query_init_usec,
		"lod1_serialization_us": mesh_serialization_usec, "lod1_serialized_bytes": serialized_mesh.size(), "array_mesh_build_us": array_mesh_usec,
		"cache_identity_lod1_build_us": identity_lod1_build_usec, "cache_init_internal_timings": cache_init_timings,
		"cache_first_call_internal_timings": cache_first_call_timings,
		"lod0_cache_cold_total_us": lod0_cache_cold_usec, "lod0_cache_builder_us": lod0_cache_builder_usec,
		"lod0_cache_memory_hit_us": lod0_warm_usec, "lod0_cache_fresh_instance_disk_hit_us": lod0_disk_usec,
		"lod0_cache_first_layer": String(lod0_cache_result.get("cache_layer", "")),
		"cache_first_lookup_us": cache_first_lookup_usec, "cache_first_layer": String(cache_result.get("cache_layer", "")),
		"cache_builder_us": cold_builder_usec, "cache_memory_hit_us": memory_hit_usec,
		"cache_fresh_instance_disk_hit_us": disk_hit_usec, "cache_remote_edit_lookup_us": remote_lookup_usec,
		"cache_local_edit_rebuild_us": local_rebuild_usec, "cache_local_edit_builder_us": local_builder_usec,
		"cache_local_edit_lod0_builder_us": local_lod0_builder_usec,
		"cache_disk_bytes": int(local_cache.stats().disk_bytes), "cache_memory_bytes": int(local_cache.stats().memory_bytes),
		"cache_memory_peak_bytes": int(local_cache.stats().peak_memory_bytes), "cache_hits": int(cache.hit_count + disk_cache.hit_count + remote_cache.hit_count),
		"cache_misses": int(cache.miss_count + local_cache.miss_count), "static_memory_delta_bytes": OS.get_static_memory_usage() - _memory_before,
		"status": "PASS" if _failures.is_empty() else "FAIL", "failures": _failures,
		"duration_usec": Time.get_ticks_usec() - start_usec,
	}
	var bytes := (JSON.stringify(row, "\t", true) + "\n").to_utf8_buffer()
	var out := FileAccess.open(output_root.path_join("result.jsonl"), FileAccess.WRITE)
	if out == null:
		push_error("r3b_result_open_failed")
		quit(2)
		return
	out.store_buffer(bytes)
	out.flush()
	out.close()
	print("P31_R3C_%s: %s %s" % [String(row.status), scenario, JSON.stringify({"repeat": repeat, "duration_usec": row.duration_usec, "failures": row.failures})])
	quit(0 if _failures.is_empty() else 1)


func _valid_scenario(value: String) -> bool:
	var selection := value.trim_prefix("NONPERIODIC-") if value.begins_with("NONPERIODIC-") else value
	var pieces := selection.split("-")
	return pieces.size() == 2 and ["CONCENTRATED", "DISTRIBUTED"].has(pieces[0]) and ["256", "640", "2048", "8192"].has(pieces[1])


func _integer_array_matches(value: Variant, expected: Array) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != expected.size():
		return false
	for index in range(expected.size()):
		var item: Variant = value[index]
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item)) or float(item) != floor(float(item)):
			return false
		if int(item) != int(expected[index]):
			return false
	return true


func _probe(region: Vector2i, chunk: Vector2i, index: int) -> Vector3:
	var origin := Spatial.region_origin_world(region) + Grid.origin_for(chunk)
	var fixed := [Vector3(-0.01, 1.15, 5.99), Vector3(0.0, -0.99, 0.0), Vector3(15.99, 4.0, 11.99), Vector3(16.01, 2.0, 12.01), Vector3(-16.01, 2.0, -12.01)]
	if index < fixed.size():
		return fixed[index]
	var x := float((index * 37) % 1600) / 100.0
	var y := -1.5 + float((index * 23) % 900) / 100.0
	var z := float((index * 53) % 1200) / 100.0
	return origin + Vector3(x, y, z)


func _canonical_world_sample(world_point: Vector3, snapshot: Dictionary) -> float:
	var mapped := Spatial.world_to_region_local(world_point)
	if not bool(mapped.get("valid", false)):
		return NAN
	return Brush.sample_density_snapshot(SEED, mapped["region_key"], mapped["local_position"], false, snapshot)


func _mesh_exact(left: Dictionary, right: Dictionary) -> bool:
	return bool(left.get("valid", false)) and bool(right.get("valid", false)) \
		and var_to_bytes(left.get("positions", PackedVector3Array())) == var_to_bytes(right.get("positions", PackedVector3Array())) \
		and var_to_bytes(left.get("normals", PackedVector3Array())) == var_to_bytes(right.get("normals", PackedVector3Array())) \
		and int(left.get("triangle_count", -1)) == int(right.get("triangle_count", -2)) \
		and int(left.get("sample_count", -1)) == int(right.get("sample_count", -2))


func _cache_identity(snapshot: Dictionary, region: Vector2i, chunk: Vector2i, lod: int) -> Dictionary:
	var operations: Array[Dictionary] = []
	var centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
	var radii: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
	var modes: PackedByteArray = snapshot.get("modes", PackedByteArray())
	var sequences: PackedInt32Array = snapshot.get("sequences", PackedInt32Array())
	for index in range(centers.size()):
		operations.append({"sequence": sequences[index], "center": centers[index], "radius": radii[index], "mode": modes[index]})
	var content := {"world_seed": SEED, "generator": 1, "field": "sdf-v1", "lod": lod, "region": region, "chunk": chunk,
		"mesh_algorithm": "marching-tetrahedra-v1/lod01-transition-v1", "dependency_halo": 0.25, "ordered_operations": operations}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(content))
	return {"key": context.finish().hex_encode(), "content": content}


func _copy_ledger(source: RefCounted) -> RefCounted:
	var target: RefCounted = Brush.new(SEED, 1)
	for operation in source.get_operations_snapshot():
		if not target.add_sphere(int(operation.mode), operation.center_world, float(operation.radius)):
			return target
	return target


func _summary(samples: PackedInt64Array) -> Dictionary:
	if samples.is_empty():
		return {"count": 0, "p50": 0, "p95": 0, "p99": 0}
	var sorted := samples.duplicate()
	sorted.sort()
	return {"count": sorted.size(), "p50": _percentile(sorted, 0.50), "p95": _percentile(sorted, 0.95), "p99": _percentile(sorted, 0.99), "max": sorted[-1]}


func _percentile(sorted: PackedInt64Array, quantile: float) -> int:
	return int(sorted[clampi(int(ceil(float(sorted.size()) * quantile)) - 1, 0, sorted.size() - 1)])


func _write_fail(root: String, scenario: String, repeat: int, source_sha: String) -> void:
	var file := FileAccess.open(root.path_join("result.jsonl"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"scenario_id": scenario, "repeat": repeat, "source_sha": source_sha, "status": "FAIL", "failures": _failures}) + "\n")
		file.close()


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
