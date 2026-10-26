extends SceneTree

## Isolated P3.1 R3A comparison. This script is opt-in and never touches user://worlds.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Store := preload("res://scripts/terrain/terrain_world_save_store_v2.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const MeshCache := preload("res://tests/prototypes/r3a_mesh_cache.gd")
const DensitySnapshot := preload("res://tests/prototypes/r3a_density_snapshot.gd")
const FastReplay := preload("res://tests/prototypes/r3a_fast_replay.gd")

const SEED := 131102026
const GENERATOR_VERSION := 1
const COUNTS := [256, 640, 2048, 8192]
const LAYOUTS := ["distributed", "concentrated"]
const REPEATS := 3
const ISSUE131_SUMS_SHA256 := "ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1"
const PROBES := [
	Vector3(-16.01, 2.5, -12.01), Vector3(-16.0, 2.5, -12.0), Vector3(-0.01, 2.5, -0.01),
	Vector3.ZERO, Vector3(0.01, 2.5, 0.01), Vector3(15.99, 2.5, 11.99), Vector3(16.01, 2.5, 12.01),
]

var _root_path := ""
var _rows: Array[Dictionary] = []
var _failures := 0
var _assertions := 0
var _started_usec := 0
var _filter := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_usec = Time.get_ticks_usec()
	_root_path = OS.get_environment("P31_R3A_OUTPUT_DIR")
	if _root_path.is_empty() or not _root_path.is_absolute_path():
		push_error("R3A requires an absolute P31_R3A_OUTPUT_DIR")
		quit(2)
		return
	if DirAccess.dir_exists_absolute(_root_path) and (not DirAccess.get_files_at(_root_path).is_empty() or not DirAccess.get_directories_at(_root_path).is_empty()):
		push_error("R3A output root must be new and empty")
		quit(2)
		return
	var error := DirAccess.make_dir_recursive_absolute(_root_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("R3A output root unavailable: %d" % error)
		quit(2)
		return
	if not _verify_reference_artifacts():
		_write_results()
		quit(1)
		return
	if not _write_input_manifest():
		_write_results()
		quit(1)
		return
	_filter = OS.get_environment("P31_R3A_FILTER")
	for layout_value in LAYOUTS:
		for count_value in COUNTS:
			var scenario_suffix := "%s.N%04d" % [String(layout_value).to_upper(), int(count_value)]
			if _filter.is_empty() or _filter == scenario_suffix:
				_rows.append(_run_case(String(layout_value), int(count_value)))
	if _filter.is_empty() or _filter == "CAVE":
		var cave_control: Dictionary = _run_cave_control()
		_rows.append(cave_control)
	_write_results()
	var all_rows_pass := _rows.size() > 0
	for row in _rows:
		if String(row.get("status", "FAIL")) != "PASS":
			all_rows_pass = false
	if _failures == 0 and all_rows_pass:
		print("P31_R3A_PASS: scenarios=%d reference_hash_checks=%d failures=0 duration_ms=%.3f" % [_rows.size(), _assertions, float(Time.get_ticks_usec() - _started_usec) / 1000.0])
	else:
		push_error("P31_R3A_FAIL: scenarios=%d reference_hash_checks=%d failures=%d" % [_rows.size(), _assertions, _failures])
	quit(0 if _failures == 0 and all_rows_pass else 1)


func _write_input_manifest() -> bool:
	var scenarios: Array[Dictionary] = []
	for layout_value in LAYOUTS:
		for count_value in COUNTS:
			var layout := String(layout_value)
			var count := int(count_value)
			var code := "N%04d" % count
			var artifact := "P31.EDIT.%s.%s.v1.R01.commands.json" % [layout.to_upper(), code]
			var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/p3_1_r3a/issue131/" + artifact)
			var mesh_region := Vector2i.ZERO if layout == "concentrated" else Vector2i(-31, -64)
			var mesh_chunk := Vector2i.ZERO if layout == "concentrated" else Vector2i(2, 2)
			scenarios.append({
				"scenario_id": "P31.R3A.%s.%s.v1" % [layout.to_upper(), code], "version": 1,
				"layout": layout, "operation_count": count, "seed": SEED, "generator_version": GENERATOR_VERSION,
				"brush_radius_mm": 580, "mode_order": "CARVE even sequence; FILL odd sequence",
				"command_artifact": artifact, "command_artifact_sha256": _sha256(bytes),
				"mesh_region": [mesh_region.x, mesh_region.y], "mesh_chunk": [mesh_chunk.x, mesh_chunk.y], "mesh_repeats": REPEATS,
				"lod_levels": [0, 1], "edit_revisit_restart_corruption": true,
			})
	var manifest := {
		"contract": "P3.1 R3A ledger/cache/snapshot prototype", "version": 1,
		"source_sha": OS.get_environment("P31_R3A_SOURCE_SHA"), "reference_issue131_seed": SEED,
		"reference_manifest_sha256": "2dff9ccd5b98e1ea722051b25f961ff8f64c3ae698f3bc12102826e04ec3088d",
		"reference_sha256sums_sha256": ISSUE131_SUMS_SHA256, "measurement_repetitions": REPEATS,
		"query_probes": PROBES, "scenario_definitions": scenarios,
		"cave_control": {"scenario_id": "P31.R3A.CAVE.LOD0.N0000.v1", "region": [0, 0], "chunk": [0, 2], "canonical_centerline_samples": 9},
		"alternative_a": "conservative squared-distance no-op pruning in exact ordered replay; GDScript test-only",
		"alternative_b": "content-addressed persistent derived CPU mesh arrays with source-key and payload SHA256",
		"alternative_c": "0.5-unit Float64 density lattice with trilinear interpolation; approximate between exact grid samples",
		"metric_limits": {"GPU": "not measured", "presented_fps": "not measured", "mesh_publication": "not measured; CPU buffers only", "memory": "Godot static-memory delta plus external process working-set sampling"},
	}
	var bytes := JSON.stringify(manifest, "\t", true).to_utf8_buffer()
	var path := _root_path.path_join("r3a-input-manifest.json")
	if not _write_new(path, bytes):
		return false
	return _write_new(_root_path.path_join("r3a-input-manifest.sha256"), (_sha256(bytes) + "  r3a-input-manifest.json\n").to_utf8_buffer())


func _verify_reference_artifacts() -> bool:
	var base := "res://tests/fixtures/p3_1_r3a/issue131/"
	var sums_bytes := FileAccess.get_file_as_bytes(base + "SHA256SUMS.txt")
	if _sha256(sums_bytes) != ISSUE131_SUMS_SHA256:
		_failures += 1
		push_error("issue131_reference_sha_index_mismatch")
		return false
	_assertions += 1
	var ok := _verify_hash(base + "scenario-manifest.json", base + "scenario-manifest.sha256", sums_bytes)
	for layout_value in LAYOUTS:
		for count_value in [0, 256, 640, 2048, 8192]:
			var code := "N%04d" % int(count_value)
			var stem := "P31.EDIT.%s.%s.v1.R01.commands" % [String(layout_value).to_upper(), code]
			ok = _verify_hash(base + stem + ".json", base + stem + ".sha256", sums_bytes) and ok
	return ok


func _verify_hash(file_path: String, sidecar_path: String, sums_bytes: PackedByteArray) -> bool:
	var bytes := FileAccess.get_file_as_bytes(file_path)
	var sidecar := FileAccess.get_file_as_string(sidecar_path).strip_edges()
	var expected := sidecar.get_slice(" ", 0)
	var actual := _sha256(bytes)
	var expected_file_hash := _reference_hash_for(file_path.get_file(), sums_bytes)
	var expected_sidecar_hash := _reference_hash_for(sidecar_path.get_file(), sums_bytes)
	_assertions += 1
	_assertions += 1
	if bytes.is_empty() or expected.length() != 64 or actual != expected or actual != expected_file_hash or _sha256(FileAccess.get_file_as_bytes(sidecar_path)) != expected_sidecar_hash:
		_failures += 1
		push_error("reference_artifact_hash_mismatch:%s" % file_path)
		return false
	return true


func _reference_hash_for(file_name: String, sums_bytes: PackedByteArray) -> String:
	var expected_path := "results/scenario-manifest.json" if file_name == "scenario-manifest.json" else "results/scenario-manifest.sha256" if file_name == "scenario-manifest.sha256" else "results/inputs/" + file_name
	for line in sums_bytes.get_string_from_utf8().split("\n"):
		if line.length() < 67 or line.substr(65).strip_edges() != expected_path:
			continue
		return line.substr(0, 64)
	return ""


func _run_case(layout: String, operation_count: int) -> Dictionary:
	var scenario_id := "P31.R3A.%s.N%04d.v1" % [layout.to_upper(), operation_count]
	var run_id := scenario_id + ".R01"
	var mesh_region := Vector2i.ZERO if layout == "concentrated" else Vector2i(-31, -64)
	var chunk_coordinate := Vector2i.ZERO if layout == "concentrated" else Vector2i(2, 2)
	var static_memory_before := OS.get_static_memory_usage()
	var input_stem := "P31.EDIT.%s.N%04d.v1.R01.commands" % [layout.to_upper(), operation_count]
	var input_path := "res://tests/fixtures/p3_1_r3a/issue131/" + input_stem + ".json"
	var input_bytes := FileAccess.get_file_as_bytes(input_path)
	var parsed: Variant = JSON.parse_string(input_bytes.get_string_from_utf8())
	var row := {
		"scenario_id": scenario_id, "run_id": run_id, "layout": layout, "operation_count": operation_count,
		"world_seed": SEED, "generator_version": GENERATOR_VERSION, "command_input_sha256": _sha256(input_bytes),
		"status": "PASS", "failure_reason": "", "full_vs_indexed_mismatches": 0,
		"fast_sdf_mismatches": 0, "fast_lod0_geometry_mismatches": 0, "fast_lod1_geometry_mismatches": 0,
		"snapshot_lod0_vertex_mismatches": 0, "snapshot_lod1_vertex_mismatches": 0,
		"snapshot_lod0_max_normal_angle_degrees": 0.0, "snapshot_lod1_max_normal_angle_degrees": 0.0,
		"snapshot_lod0_max_vertex_error": 0.0, "snapshot_lod1_max_vertex_error": 0.0,
	}
	if typeof(parsed) != TYPE_ARRAY or (parsed as Array).size() != operation_count:
		return _fail_row(row, "frozen_command_input_invalid")
	var ledger: RefCounted = Brush.new(SEED, GENERATOR_VERSION)
	var generation_started := Time.get_ticks_usec()
	for index in range(operation_count):
		var command_value: Variant = (parsed as Array)[index]
		if typeof(command_value) != TYPE_DICTIONARY:
			return _fail_row(row, "command_record_invalid")
		var command: Dictionary = command_value
		var center_values: Array = command.get("center_mm", [])
		if center_values.size() != 3 or int(command.get("sequence", -1)) != index or int(command.get("revision", -1)) != index + 1:
			return _fail_row(row, "command_order_invalid")
		var mode_name := String(command.get("mode", ""))
		if mode_name != "CARVE" and mode_name != "FILL":
			return _fail_row(row, "command_mode_invalid")
		var mode := Brush.Mode.CARVE if mode_name == "CARVE" else Brush.Mode.FILL
		var center := Vector3(float(center_values[0]), float(center_values[1]), float(center_values[2])) / 1000.0
		if int(command.get("radius_mm", -1)) != 580 or not ledger.add_sphere(mode, center, 0.58):
			return _fail_row(row, "command_not_accepted")
	row["ledger_generation_ms"] = _ms(Time.get_ticks_usec() - generation_started)
	if ledger.get_edit_count() != operation_count or ledger.revision != operation_count:
		return _fail_row(row, "ledger_count_or_revision_mismatch")
	var command_list_sidecar := FileAccess.get_file_as_string("res://tests/fixtures/p3_1_r3a/issue131/" + input_stem + ".sha256").strip_edges()
	row["command_list_sha256"] = command_list_sidecar.get_slice(" ", 0)
	var persist_root := _root_path.path_join("world-v2").path_join(run_id)
	var legacy_root := _root_path.path_join("legacy-unused").path_join(run_id)
	var store: RefCounted = Store.new(persist_root, legacy_root)
	var save_started := Time.get_ticks_usec()
	var save_result: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
	row["initial_save_ms"] = _ms(Time.get_ticks_usec() - save_started)
	if not save_result.get("ok", false):
		return _fail_row(row, "ledger_save:%s" % String(save_result.get("reason", "unknown")))
	row["segment_count"] = int(save_result.get("segment_count", -1))
	row["disk_bytes_initial"] = _directory_bytes(persist_root)
	var restart_store: RefCounted = Store.new(persist_root, legacy_root)
	var restart_started := Time.get_ticks_usec()
	var load_result: Dictionary = restart_store.load_world()
	row["restart_load_ms"] = _ms(Time.get_ticks_usec() - restart_started)
	if not load_result.get("ok", false):
		return _fail_row(row, "ledger_restart:%s" % String(load_result.get("reason", "unknown")))
	var payload: Dictionary = load_result.get("payload", {})
	var restored: RefCounted = Brush.new(SEED, GENERATOR_VERSION)
	var restore_snapshot := {
		"world_seed": int(payload.get("world_seed", -1)), "generator_version": int(payload.get("generator_version", -1)),
		"revision": int(payload.get("ledger_revision", -1)), "next_sequence": int(payload.get("next_sequence", -1)),
		"storage_reference": payload.get("storage_reference", {}),
	}
	if not restored.restore_persistence_snapshot(restore_snapshot):
		return _fail_row(row, "ledger_attach_after_restart:%s" % restored.last_restore_rejection_reason)
	var all_operations: Array[Dictionary] = ledger.get_operations_snapshot()
	var query_samples := PackedFloat64Array()
	var fast_query_samples := PackedFloat64Array()
	var full_mismatch := 0
	var indexed_candidates := 0
	restart_store.clear_segment_cache()
	restart_store.reset_query_stats()
	for probe in PROBES:
		var mapped: Dictionary = Spatial.world_to_region_local(probe)
		var sample_started := Time.get_ticks_usec()
		var full_value := _full_replay(SEED, mapped["region_key"], mapped["local_position"], all_operations)
		query_samples.append(float(Time.get_ticks_usec() - sample_started))
		sample_started = Time.get_ticks_usec()
		var indexed_value: float = restored.sample_density(SEED, mapped["region_key"], mapped["local_position"])
		fast_query_samples.append(float(Time.get_ticks_usec() - sample_started))
		if indexed_value != full_value:
			full_mismatch += 1
		indexed_candidates = maxi(indexed_candidates, int(restored.last_sample_candidate_count))
	row["full_query_p50_ms"] = _percentile_ms(query_samples, 0.50)
	row["full_query_p95_ms"] = _percentile_ms(query_samples, 0.95)
	row["full_query_p99_ms"] = _percentile_ms(query_samples, 0.99)
	row["indexed_query_p50_ms"] = _percentile_ms(fast_query_samples, 0.50)
	row["indexed_query_p95_ms"] = _percentile_ms(fast_query_samples, 0.95)
	row["indexed_query_p99_ms"] = _percentile_ms(fast_query_samples, 0.99)
	row["indexed_max_candidates"] = indexed_candidates
	row["full_vs_indexed_mismatches"] = full_mismatch
	row["cold_segment_reads"] = int(restart_store.segment_read_count)
	row["cold_segment_bytes"] = int(restart_store.segment_read_bytes)
	row["cold_segment_cache_hits"] = int(restart_store.segment_cache_hit_count)
	if full_mismatch > 0:
		return _fail_row(row, "indexed_vs_full_replay_mismatch")
	var warm_query_samples := PackedFloat64Array()
	for warm_repeat in range(3):
		for probe in PROBES:
			var mapped: Dictionary = Spatial.world_to_region_local(probe)
			var warm_started := Time.get_ticks_usec()
			restored.sample_density(SEED, mapped["region_key"], mapped["local_position"])
			warm_query_samples.append(float(Time.get_ticks_usec() - warm_started))
	row["indexed_warm_query_p50_ms"] = _percentile_ms(warm_query_samples, 0.50)
	row["indexed_warm_query_p95_ms"] = _percentile_ms(warm_query_samples, 0.95)
	row["indexed_warm_query_p99_ms"] = _percentile_ms(warm_query_samples, 0.99)
	row["warm_segment_reads"] = int(restart_store.segment_read_count) - int(row["cold_segment_reads"])
	row["warm_segment_cache_hits"] = int(restart_store.segment_cache_hit_count) - int(row["cold_segment_cache_hits"])
	var mesh_snapshot: Dictionary = restored.get_meshing_snapshot_for_chunk(mesh_region, chunk_coordinate)
	if mesh_snapshot.has("valid") and not bool(mesh_snapshot["valid"]):
		return _fail_row(row, "chunk_snapshot_rejected")
	row["mesh_chunk_candidate_count"] = int(mesh_snapshot.get("candidate_operation_count", -1))
	var fast_replay: RefCounted = FastReplay.new(SEED, mesh_snapshot)
	var fast_callback := Callable(fast_replay, "sample_density")
	var reference_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, false, mesh_snapshot)
	var reference_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, mesh_snapshot)
	if not reference_lod0.get("valid", false) or not reference_lod1.get("valid", false):
		return _fail_row(row, "reference_mesh_build_invalid")
	var fast_lod0_samples := PackedFloat64Array()
	var fast_lod1_samples := PackedFloat64Array()
	var lod0_mismatches := 0
	var lod1_mismatches := 0
	var reference_lod0_usec := PackedFloat64Array()
	var reference_lod1_usec := PackedFloat64Array()
	var last_fast_lod0: Dictionary = {}
	var last_fast_lod1: Dictionary = {}
	for repeat_index in range(REPEATS):
		var fast0: Dictionary
		var fast1: Dictionary
		var reference0: Dictionary
		var reference1: Dictionary
		var started: int
		if repeat_index % 2 == 0:
			started = Time.get_ticks_usec()
			reference0 = Mesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, false, mesh_snapshot)
			reference_lod0_usec.append(float(Time.get_ticks_usec() - started))
			started = Time.get_ticks_usec()
			reference1 = LodMesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, mesh_snapshot)
			reference_lod1_usec.append(float(Time.get_ticks_usec() - started))
		started = Time.get_ticks_usec()
		fast0 = Mesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, false, {}, fast_callback)
		fast_lod0_samples.append(float(Time.get_ticks_usec() - started))
		started = Time.get_ticks_usec()
		fast1 = LodMesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, mesh_snapshot, fast_callback)
		fast_lod1_samples.append(float(Time.get_ticks_usec() - started))
		if repeat_index % 2 != 0:
			started = Time.get_ticks_usec()
			reference0 = Mesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, false, mesh_snapshot)
			reference_lod0_usec.append(float(Time.get_ticks_usec() - started))
			started = Time.get_ticks_usec()
			reference1 = LodMesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, mesh_snapshot)
			reference_lod1_usec.append(float(Time.get_ticks_usec() - started))
		if not fast0.get("valid", false) or not fast1.get("valid", false) or not reference0.get("valid", false) or not reference1.get("valid", false):
			return _fail_row(row, "fast_or_reference_mesh_build_invalid")
		lod0_mismatches += _mesh_mismatch_count(reference_lod0, fast0)
		lod1_mismatches += _mesh_mismatch_count(reference_lod1, fast1)
		last_fast_lod0 = fast0
		last_fast_lod1 = fast1
	row["reference_lod0_p50_ms"] = _percentile_ms(reference_lod0_usec, 0.50)
	row["reference_lod0_p95_ms"] = _percentile_ms(reference_lod0_usec, 0.95)
	row["fast_lod0_p50_ms"] = _percentile_ms(fast_lod0_samples, 0.50)
	row["fast_lod0_p95_ms"] = _percentile_ms(fast_lod0_samples, 0.95)
	row["fast_lod0_p99_ms"] = _percentile_ms(fast_lod0_samples, 0.99)
	row["reference_lod1_p50_ms"] = _percentile_ms(reference_lod1_usec, 0.50)
	row["reference_lod1_p95_ms"] = _percentile_ms(reference_lod1_usec, 0.95)
	row["reference_lod0_p99_ms"] = _percentile_ms(reference_lod0_usec, 0.99)
	row["reference_lod1_p99_ms"] = _percentile_ms(reference_lod1_usec, 0.99)
	row["fast_lod1_p50_ms"] = _percentile_ms(fast_lod1_samples, 0.50)
	row["fast_lod1_p95_ms"] = _percentile_ms(fast_lod1_samples, 0.95)
	row["fast_lod1_p99_ms"] = _percentile_ms(fast_lod1_samples, 0.99)
	row["fast_replay_operation_tests"] = fast_replay.operation_tests
	row["fast_replay_sqrt_calls"] = fast_replay.distance_sqrts
	row["fast_replay_sqrt_skipped"] = fast_replay.skipped_sqrts
	row["fast_lod0_geometry_mismatches"] = lod0_mismatches
	row["fast_lod1_geometry_mismatches"] = lod1_mismatches
	row["fast_lod0_vertex_mismatches"] = _mesh_vertex_mismatch_count(reference_lod0, last_fast_lod0)
	row["fast_lod1_vertex_mismatches"] = _mesh_vertex_mismatch_count(reference_lod1, last_fast_lod1)
	row["fast_lod0_max_vertex_error"] = _mesh_max_vertex_error(reference_lod0, last_fast_lod0)
	row["fast_lod1_max_vertex_error"] = _mesh_max_vertex_error(reference_lod1, last_fast_lod1)
	row["fast_lod0_max_normal_angle_degrees"] = _mesh_max_normal_angle(reference_lod0, last_fast_lod0)
	row["fast_lod1_max_normal_angle_degrees"] = _mesh_max_normal_angle(reference_lod1, last_fast_lod1)
	if lod0_mismatches != 0 or lod1_mismatches != 0:
		return _fail_row(row, "fast_replay_geometry_mismatch")
	var op_snapshot: Array[Dictionary] = restored.get_operations_snapshot()
	var cache_directory := _root_path.path_join("mesh-cache").path_join(run_id)
	var cache: RefCounted = MeshCache.new(cache_directory)
	var cache_first_usec := Time.get_ticks_usec()
	var cache0: Dictionary = cache.get_or_build(_cache_identity(layout, operation_count, op_snapshot, "lod0", mesh_region, chunk_coordinate), func() -> Dictionary: return reference_lod0)
	var cache_lod0_first_usec := Time.get_ticks_usec() - cache_first_usec
	cache_first_usec = Time.get_ticks_usec()
	var cache1: Dictionary = cache.get_or_build(_cache_identity(layout, operation_count, op_snapshot, "lod1", mesh_region, chunk_coordinate), func() -> Dictionary: return reference_lod1)
	var cache_lod1_first_usec := Time.get_ticks_usec() - cache_first_usec
	cache_first_usec = Time.get_ticks_usec()
	var warm_lod0: Dictionary = cache.get_or_build(_cache_identity(layout, operation_count, op_snapshot, "lod0", mesh_region, chunk_coordinate), func() -> Dictionary: return reference_lod0)
	var cache_lod0_warm_usec := Time.get_ticks_usec() - cache_first_usec
	cache_first_usec = Time.get_ticks_usec()
	var warm_lod1: Dictionary = cache.get_or_build(_cache_identity(layout, operation_count, op_snapshot, "lod1", mesh_region, chunk_coordinate), func() -> Dictionary: return reference_lod1)
	var cache_lod1_warm_usec := Time.get_ticks_usec() - cache_first_usec
	var restarted_cache: RefCounted = MeshCache.new(cache_directory)
	cache_first_usec = Time.get_ticks_usec()
	var restart_cache_hit: Dictionary = restarted_cache.get_or_build(_cache_identity(layout, operation_count, op_snapshot, "lod1", mesh_region, chunk_coordinate), func() -> Dictionary: return reference_lod1)
	row["mesh_cache_restart_hit_ms"] = _ms(Time.get_ticks_usec() - cache_first_usec)
	row["mesh_cache_lod0_cold_ms"] = _ms(cache_lod0_first_usec)
	row["mesh_cache_lod0_warm_ms"] = _ms(cache_lod0_warm_usec)
	row["mesh_cache_lod1_cold_ms"] = _ms(cache_lod1_first_usec)
	row["mesh_cache_lod1_warm_ms"] = _ms(cache_lod1_warm_usec)
	row["mesh_cache_hits"] = int(cache.hit_count) + int(restarted_cache.hit_count)
	row["mesh_cache_invalidations"] = int(cache.miss_count)
	row["mesh_cache_disk_bytes"] = _directory_bytes(cache_directory)
	row["mesh_cache_lod0_cold_total_ms"] = float(row.get("reference_lod0_p50_ms", 0.0)) + float(row["mesh_cache_lod0_cold_ms"])
	row["mesh_cache_lod1_cold_total_ms"] = float(row.get("reference_lod1_p50_ms", 0.0)) + float(row["mesh_cache_lod1_cold_ms"])
	row["mesh_cache_largest_live_bytes"] = int(cache.peak_bytes)
	if not bool(cache0.get("valid", false)) or not bool(cache1.get("valid", false)):
		return _fail_row(row, "mesh_cache_initial_validation_failed")
	if not bool(cache0.get("rebuilt", false)) or not bool(cache1.get("rebuilt", false)):
		return _fail_row(row, "mesh_cache_cold_build_not_observed")
	if not bool(warm_lod0.get("valid", false)) or bool(warm_lod0.get("rebuilt", true)) or not bool(warm_lod1.get("valid", false)) or bool(warm_lod1.get("rebuilt", true)):
		return _fail_row(row, "mesh_cache_warm_revisit_missed")
	if int(restarted_cache.hit_count) != 1 or bool(restart_cache_hit.get("rebuilt", true)):
		return _fail_row(row, "mesh_cache_restart_hit_missing")
	var appended_center: Vector3 = Spatial.region_origin_world(mesh_region) + Grid.origin_for(chunk_coordinate) + Vector3(1.25, 2.5, 1.25)
	if not restored.add_sphere(Brush.Mode.FILL if operation_count % 2 == 0 else Brush.Mode.CARVE, appended_center, 0.58):
		return _fail_row(row, "post_restart_append_rejected")
	var changed_operations: Array[Dictionary] = restored.get_operations_snapshot()
	var append_started := Time.get_ticks_usec()
	var append_save: Dictionary = restart_store.save_ledger(Store.WORLD_ID, restored)
	row["append_delta_save_ms"] = _ms(Time.get_ticks_usec() - append_started)
	row["append_delta_segments_written"] = int(append_save.get("segments_written", -1))
	if not append_save.get("ok", false):
		return _fail_row(row, "append_delta_save_failed")
	var post_edit_store: RefCounted = Store.new(persist_root, legacy_root)
	var post_edit_load: Dictionary = post_edit_store.load_world()
	if not post_edit_load.get("ok", false) or int(post_edit_load.get("payload", {}).get("operation_count", -1)) != operation_count + 1:
		return _fail_row(row, "post_edit_restart_mismatch")
	row["post_edit_restart_operation_count"] = int(post_edit_load.get("payload", {}).get("operation_count", -1))
	var post_edit_payload: Dictionary = post_edit_load.get("payload", {})
	var post_edit_ledger: RefCounted = Brush.new(SEED, GENERATOR_VERSION)
	var post_edit_snapshot := {
		"world_seed": int(post_edit_payload.get("world_seed", -1)), "generator_version": int(post_edit_payload.get("generator_version", -1)),
		"revision": int(post_edit_payload.get("ledger_revision", -1)), "next_sequence": int(post_edit_payload.get("next_sequence", -1)),
		"storage_reference": post_edit_payload.get("storage_reference", {}),
	}
	if not post_edit_ledger.restore_persistence_snapshot(post_edit_snapshot) or post_edit_ledger.get_edit_count() != operation_count + 1 or post_edit_ledger.get_last_sequence() != operation_count:
		return _fail_row(row, "post_edit_restart_ledger_restore_mismatch")
	var append_mapped: Dictionary = Spatial.world_to_region_local(appended_center)
	var post_edit_value: float = post_edit_ledger.sample_density(SEED, append_mapped["region_key"], append_mapped["local_position"])
	if post_edit_value != _full_replay(SEED, append_mapped["region_key"], append_mapped["local_position"], changed_operations):
		return _fail_row(row, "post_edit_restart_sdf_mismatch")
	var misses_before_edit: int = cache.miss_count
	cache_first_usec = Time.get_ticks_usec()
	var edit_cache_result: Dictionary = cache.get_or_build(_cache_identity(layout, operation_count + 1, changed_operations, "lod1", mesh_region, chunk_coordinate), func() -> Dictionary: return LodMesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, restored.get_meshing_snapshot_for_chunk(mesh_region, chunk_coordinate)))
	row["mesh_cache_edit_invalidation_ms"] = _ms(Time.get_ticks_usec() - cache_first_usec)
	row["mesh_cache_edit_invalidation_misses"] = cache.miss_count - misses_before_edit
	row["mesh_cache_hits_after_edit"] = int(cache.hit_count)
	if not bool(edit_cache_result.get("valid", false)) or not bool(edit_cache_result.get("rebuilt", false)) or int(row["mesh_cache_edit_invalidation_misses"]) != 1:
		return _fail_row(row, "mesh_cache_failed_to_invalidate_after_edit")
	var corrupt_path: String = String(cache1.get("cache_path", ""))
	if corrupt_path.is_empty() or not cache.corrupt_cache_for_test(corrupt_path):
		return _fail_row(row, "mesh_cache_corruption_injection_failed")
	cache_first_usec = Time.get_ticks_usec()
	var corrupt_rebuild: Dictionary = cache.get_or_build(_cache_identity(layout, operation_count, op_snapshot, "lod1", mesh_region, chunk_coordinate), func() -> Dictionary: return reference_lod1)
	row["mesh_cache_corrupt_recovery_ms"] = _ms(Time.get_ticks_usec() - cache_first_usec)
	row["mesh_cache_corrupt_recovered"] = bool(corrupt_rebuild.get("valid", false)) and bool(corrupt_rebuild.get("rebuilt", false))
	row["mesh_cache_corrupt_geometry_mismatches"] = _mesh_vertex_mismatch_count(reference_lod1, corrupt_rebuild)
	if not bool(row["mesh_cache_corrupt_recovered"]):
		return _fail_row(row, "mesh_cache_corruption_not_recovered")
	if int(row["mesh_cache_corrupt_geometry_mismatches"]) != 0:
		return _fail_row(row, "mesh_cache_corruption_rebuild_geometry_mismatch")
	var snapshot_build_usec := Time.get_ticks_usec()
	var density_snapshot: RefCounted = DensitySnapshot.new(SEED, op_snapshot, mesh_region, chunk_coordinate)
	if not density_snapshot.build():
		return _fail_row(row, "density_snapshot_build_failed")
	row["density_snapshot_build_ms"] = _ms(Time.get_ticks_usec() - snapshot_build_usec)
	row["density_snapshot_sample_count"] = density_snapshot.sample_count
	row["density_snapshot_disk_bytes"] = density_snapshot.persist(_root_path.path_join("density-snapshot").path_join(run_id))
	if int(row["density_snapshot_disk_bytes"]) <= 0:
		return _fail_row(row, "density_snapshot_persist_failed")
	var loaded_snapshot: RefCounted = DensitySnapshot.new(SEED, op_snapshot, mesh_region, chunk_coordinate)
	if not loaded_snapshot.load_from(density_snapshot.file_path):
		return _fail_row(row, "density_snapshot_reload_failed")
	var snapshot_callback := Callable(loaded_snapshot, "sample_density")
	var snap_lod0_usec := Time.get_ticks_usec()
	var snap_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, false, {}, snapshot_callback)
	row["snapshot_lod0_build_ms"] = _ms(Time.get_ticks_usec() - snap_lod0_usec)
	snap_lod0_usec = Time.get_ticks_usec()
	var snap_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, {}, snapshot_callback)
	row["snapshot_lod1_build_ms"] = _ms(Time.get_ticks_usec() - snap_lod0_usec)
	if not snap_lod0.get("valid", false) or not snap_lod1.get("valid", false):
		return _fail_row(row, "snapshot_mesh_invalid")
	row["snapshot_lod0_vertex_mismatches"] = _mesh_vertex_mismatch_count(reference_lod0, snap_lod0)
	row["snapshot_lod1_vertex_mismatches"] = _mesh_vertex_mismatch_count(reference_lod1, snap_lod1)
	row["snapshot_lod0_max_vertex_error"] = _mesh_max_vertex_error(reference_lod0, snap_lod0)
	row["snapshot_lod1_max_vertex_error"] = _mesh_max_vertex_error(reference_lod1, snap_lod1)
	row["snapshot_lod0_max_normal_angle_degrees"] = _mesh_max_normal_angle(reference_lod0, snap_lod0)
	row["snapshot_lod1_max_normal_angle_degrees"] = _mesh_max_normal_angle(reference_lod1, snap_lod1)
	row["snapshot_exact_at_grid_samples"] = density_snapshot.compare_exact_grid_samples()
	if not bool(row["snapshot_exact_at_grid_samples"]):
		return _fail_row(row, "snapshot_grid_sample_roundtrip_mismatch")
	row["snapshot_probe_mismatches"] = loaded_snapshot.compare_probe_samples(_snapshot_probes(mesh_region, chunk_coordinate))
	row["snapshot_edit_invalidation_detected"] = not loaded_snapshot.matches_ledger(changed_operations)
	if not bool(row["snapshot_edit_invalidation_detected"]):
		return _fail_row(row, "snapshot_reused_after_ledger_change")
	var invalid_delta_snapshot: RefCounted = DensitySnapshot.new(SEED, op_snapshot, mesh_region, chunk_coordinate)
	if not invalid_delta_snapshot.load_from(density_snapshot.file_path):
		return _fail_row(row, "snapshot_invalid_delta_fixture_load_failed")
	var original_grid_values: PackedFloat64Array = invalid_delta_snapshot.get_grid_values_snapshot()
	var invalid_delta: Dictionary = changed_operations.back().duplicate(true)
	invalid_delta["sequence"] = operation_count + 1
	row["snapshot_invalid_delta_rejected"] = not invalid_delta_snapshot.apply_ordered_delta(invalid_delta)
	row["snapshot_invalid_delta_atomic"] = invalid_delta_snapshot.matches_ledger(op_snapshot) and invalid_delta_snapshot.grid_value_mismatch_count(original_grid_values) == 0
	if not bool(row["snapshot_invalid_delta_rejected"]) or not bool(row["snapshot_invalid_delta_atomic"]):
		return _fail_row(row, "snapshot_invalid_delta_not_fail_closed")
	var incremental_started := Time.get_ticks_usec()
	if not loaded_snapshot.apply_ordered_delta(changed_operations.back()):
		return _fail_row(row, "snapshot_ordered_increment_rejected")
	row["density_snapshot_incremental_update_ms"] = _ms(Time.get_ticks_usec() - incremental_started)
	row["snapshot_incremental_matches_new_ledger"] = loaded_snapshot.matches_ledger(changed_operations)
	if not bool(row["snapshot_incremental_matches_new_ledger"]):
		return _fail_row(row, "snapshot_incremental_digest_mismatch")
	var full_rebuild_snapshot: RefCounted = DensitySnapshot.new(SEED, changed_operations, mesh_region, chunk_coordinate)
	var full_rebuild_started := Time.get_ticks_usec()
	if not full_rebuild_snapshot.build():
		return _fail_row(row, "snapshot_full_rebuild_after_edit_failed")
	row["density_snapshot_full_rebuild_after_edit_ms"] = _ms(Time.get_ticks_usec() - full_rebuild_started)
	row["snapshot_incremental_grid_mismatches"] = loaded_snapshot.grid_value_mismatch_count(full_rebuild_snapshot.get_grid_values_snapshot())
	row["snapshot_incremental_grid_exact"] = int(row["snapshot_incremental_grid_mismatches"]) == 0
	row["snapshot_incremental_sample_check"] = loaded_snapshot.compare_exact_grid_samples()
	if not bool(row["snapshot_incremental_grid_exact"]) or not bool(row["snapshot_incremental_sample_check"]):
		return _fail_row(row, "snapshot_incremental_grid_not_exact")
	var incremental_store_directory: String = _root_path.path_join("density-snapshot-incremental").path_join(run_id)
	row["density_snapshot_incremental_disk_bytes"] = loaded_snapshot.persist(incremental_store_directory)
	if int(row["density_snapshot_incremental_disk_bytes"]) <= 0:
		return _fail_row(row, "snapshot_incremental_persist_failed")
	var incremental_restart_started := Time.get_ticks_usec()
	var incremental_reloaded: RefCounted = DensitySnapshot.new(SEED, changed_operations, mesh_region, chunk_coordinate)
	if not incremental_reloaded.load_from(loaded_snapshot.file_path):
		return _fail_row(row, "snapshot_incremental_restart_load_failed")
	row["density_snapshot_incremental_restart_load_ms"] = _ms(Time.get_ticks_usec() - incremental_restart_started)
	row["snapshot_incremental_restart_grid_mismatches"] = incremental_reloaded.grid_value_mismatch_count(full_rebuild_snapshot.get_grid_values_snapshot())
	if int(row["snapshot_incremental_restart_grid_mismatches"]) != 0:
		return _fail_row(row, "snapshot_incremental_restart_grid_mismatch")
	var post_edit_chunk_snapshot: Dictionary = restored.get_meshing_snapshot_for_chunk(mesh_region, chunk_coordinate)
	if not bool(post_edit_chunk_snapshot.get("valid", false)):
		return _fail_row(row, "snapshot_post_edit_mesh_snapshot_invalid")
	var incremental_reference_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, false, post_edit_chunk_snapshot)
	var incremental_reference_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, post_edit_chunk_snapshot)
	var incremental_callback := Callable(incremental_reloaded, "sample_density")
	var incremental_mesh_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, false, {}, incremental_callback)
	var incremental_mesh_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, mesh_region, chunk_coordinate, {}, incremental_callback)
	if not bool(incremental_reference_lod0.get("valid", false)) or not bool(incremental_reference_lod1.get("valid", false)) \
		or not bool(incremental_mesh_lod0.get("valid", false)) or not bool(incremental_mesh_lod1.get("valid", false)):
		return _fail_row(row, "snapshot_incremental_mesh_build_invalid")
	row["snapshot_incremental_lod0_vertex_mismatches"] = _mesh_vertex_mismatch_count(incremental_reference_lod0, incremental_mesh_lod0)
	row["snapshot_incremental_lod1_vertex_mismatches"] = _mesh_vertex_mismatch_count(incremental_reference_lod1, incremental_mesh_lod1)
	row["snapshot_incremental_lod0_max_normal_angle_degrees"] = _finite_or_null(_mesh_max_normal_angle(incremental_reference_lod0, incremental_mesh_lod0))
	row["snapshot_incremental_lod1_max_normal_angle_degrees"] = _finite_or_null(_mesh_max_normal_angle(incremental_reference_lod1, incremental_mesh_lod1))
	var corrupted_snapshot_path: String = loaded_snapshot.file_path
	var corrupted_snapshot_file := FileAccess.open(corrupted_snapshot_path, FileAccess.READ_WRITE)
	if corrupted_snapshot_file == null:
		return _fail_row(row, "snapshot_corruption_open_failed")
	corrupted_snapshot_file.seek_end()
	corrupted_snapshot_file.store_8(0x7e)
	corrupted_snapshot_file.close()
	var corrupted_snapshot := DensitySnapshot.new(SEED, op_snapshot, mesh_region, chunk_coordinate)
	row["snapshot_corruption_rejected"] = not corrupted_snapshot.load_from(corrupted_snapshot_path)
	if not bool(row["snapshot_corruption_rejected"]):
		return _fail_row(row, "snapshot_corruption_not_rejected")
	var rebuilt_snapshot := DensitySnapshot.new(SEED, op_snapshot, mesh_region, chunk_coordinate)
	var snapshot_rebuild_started := Time.get_ticks_usec()
	if not rebuilt_snapshot.build():
		return _fail_row(row, "snapshot_recovery_build_failed")
	row["snapshot_corrupt_recovery_build_ms"] = _ms(Time.get_ticks_usec() - snapshot_rebuild_started)
	row["snapshot_authority"] = "ledger_schema_2"
	row["snapshot_is_exact_continuous_sdf"] = false
	row["snapshot_deterministic_rebuild_required_after_edit"] = true
	row["disk_bytes_total"] = _directory_bytes(_root_path.path_join("world-v2").path_join(run_id)) + _directory_bytes(cache_directory) + _directory_bytes(_root_path.path_join("density-snapshot").path_join(run_id))
	row["static_memory_delta_bytes"] = maxi(0, OS.get_static_memory_usage() - static_memory_before)
	row["mesh_cache_peak_bytes"] = int(cache.peak_bytes)
	row["mesh_cache_invalidated_stale"] = true
	return row


func _run_cave_control() -> Dictionary:
	var empty_ledger: RefCounted = Brush.new(SEED, GENERATOR_VERSION)
	var snapshot: Dictionary = empty_ledger.get_meshing_snapshot_for_chunk(Vector2i.ZERO, Vector2i(0, 2))
	if not bool(snapshot.get("valid", false)) or int(snapshot.get("candidate_operation_count", -1)) != 0:
		_failures += 1
		push_error("canonical_cave_empty_ledger_snapshot_invalid")
		return {"scenario_id": "P31.R3A.CAVE.LOD0.N0000.v1", "run_id": "P31.R3A.CAVE.LOD0.N0000.v1.R01", "status": "FAIL", "failure_reason": "canonical_cave_empty_ledger_snapshot_invalid"}
	var start := Time.get_ticks_usec()
	var reference: Dictionary = Mesher.build_chunk_cpu_data(SEED, Vector2i.ZERO, Vector2i(0, 2), false, snapshot)
	var reference_usec := Time.get_ticks_usec() - start
	var empty_ops: Array[Dictionary] = []
	var grid: RefCounted = DensitySnapshot.new(SEED, empty_ops, Vector2i.ZERO, Vector2i(0, 2))
	start = Time.get_ticks_usec()
	var built: bool = grid.build()
	var grid_usec := Time.get_ticks_usec() - start
	var approximate: Dictionary = Mesher.build_chunk_cpu_data(SEED, Vector2i.ZERO, Vector2i(0, 2), false, snapshot, Callable(grid, "sample_density")) if built else {"valid": false}
	var cave_open_samples := 0
	var snapshot_cave_open_samples := 0
	var cave_sample_count := 0
	var snapshot_cave_probes: Array[Vector3] = []
	for step_index in range(9):
		var local_x := float(step_index) * 0.5
		var center_yz: Vector2 = Field.cave_center(SEED, Vector2i.ZERO, local_x)
		var center := Vector3(local_x, center_yz.y, center_yz.x)
		snapshot_cave_probes.append(center)
		if Field.sample_density(SEED, Vector2i.ZERO, center) < 0.0:
			cave_open_samples += 1
		if grid.sample_density(center) < 0.0:
			snapshot_cave_open_samples += 1
		cave_sample_count += 1
	var cave_status := "PASS" if reference.get("valid", false) and approximate.get("valid", false) and cave_open_samples == 9 else "FAIL"
	if cave_status != "PASS":
		_failures += 1
		push_error("canonical_cave_centerline_or_mesh_invalid")
	return {
		"scenario_id": "P31.R3A.CAVE.LOD0.N0000.v1", "run_id": "P31.R3A.CAVE.LOD0.N0000.v1.R01",
		"status": cave_status,
		"reference_lod0_ms": _ms(reference_usec), "snapshot_build_ms": _ms(grid_usec),
		"snapshot_sample_count": grid.sample_count, "snapshot_probe_mismatches": grid.compare_probe_samples(snapshot_cave_probes),
		"snapshot_mesh_vertex_mismatches": _mesh_vertex_mismatch_count(reference, approximate),
		"snapshot_mesh_max_normal_angle_degrees": _finite_or_null(_mesh_max_normal_angle(reference, approximate)),
		"canonical_cave_centerline_open_samples": cave_open_samples, "canonical_cave_centerline_sample_count": cave_sample_count,
		"snapshot_cave_centerline_open_samples": snapshot_cave_open_samples,
		"snapshot_authority": "ledger_schema_2", "snapshot_is_exact_continuous_sdf": false,
		"snapshot_production_disposition": "REJECTED_APPROXIMATE_FIELD",
		"snapshot_geometry_acceptance": "UNSCORED_NO_OWNER_TOLERANCE",
		"cave_lod0_valid": bool(reference.get("valid", false)), "snapshot_lod0_valid": bool(approximate.get("valid", false)),
	}


func _finite_or_null(value: float) -> Variant:
	return value if is_finite(value) else null


func _cache_identity(layout: String, count: int, operations: Array[Dictionary], lod: String, region: Vector2i, chunk: Vector2i) -> Dictionary:
	var operation_bytes := JSON.stringify(operations).to_utf8_buffer()
	return {
		"schema": 1, "engine": Engine.get_version_info().get("string", "unknown"), "world_seed": SEED,
		"generator_version": GENERATOR_VERSION, "region": [region.x, region.y], "chunk": [chunk.x, chunk.y], "chunk_id": "region:%d,%d/chunk:%d,%d" % [region.x, region.y, chunk.x, chunk.y],
		"lod": lod, "show_cave_section": false, "ordered_ledger_sha256": _sha256(operation_bytes),
		"ledger_revision": count, "normal_halo": 1, "mesher": "marching-tetrahedra+lod01-transition-v1",
		"world_id": Store.WORLD_ID, "input_layout": layout,
	}


func _snapshot_probes(region: Vector2i, chunk: Vector2i) -> Array[Vector3]:
	var origin: Vector3 = Spatial.region_origin_world(region) + Grid.origin_for(chunk)
	return [
		origin + Vector3(0.0, 2.5, 0.0), origin + Vector3(0.25, 2.25, 0.25),
		origin + Vector3(2.0, 3.125, 1.5), origin + Vector3(3.75, 4.5, 2.75),
		origin + Vector3(4.0, 7.5, 3.0),
	]



func _full_replay(seed: int, region_key: Vector2i, local_position: Vector3, operations: Array[Dictionary]) -> float:
	var density: float = Field.sample_density(seed, region_key, local_position)
	var world_point: Vector3 = Spatial.region_local_to_world(region_key, local_position)
	for operation in operations:
		var distance: float = world_point.distance_to(operation["center_world"]) - float(operation["radius"])
		if int(operation["mode"]) == Brush.Mode.CARVE:
			density = minf(density, distance)
		else:
			density = maxf(density, -distance)
	return density


func _mesh_mismatch_count(expected: Dictionary, actual: Dictionary) -> int:
	# Surface geometry is compared by exact vertex count/order/coordinates.
	# Normals are reported separately in angular diagnostics: float-rounding differences
	# do not change the represented SDF zero set and have no approved acceptance budget.
	return _mesh_vertex_mismatch_count(expected, actual)


func _mesh_vertex_mismatch_count(expected: Dictionary, actual: Dictionary) -> int:
	var a: PackedVector3Array = expected.get("positions", PackedVector3Array())
	var b: PackedVector3Array = actual.get("positions", PackedVector3Array())
	if a.size() != b.size():
		return 1
	var mismatch := 0
	for index in range(a.size()):
		if a[index] != b[index]:
			mismatch += 1
	return mismatch


func _mesh_max_vertex_error(expected: Dictionary, actual: Dictionary) -> float:
	var a: PackedVector3Array = expected.get("positions", PackedVector3Array())
	var b: PackedVector3Array = actual.get("positions", PackedVector3Array())
	if a.size() != b.size():
		return INF
	var maximum := 0.0
	for index in range(a.size()):
		maximum = maxf(maximum, a[index].distance_to(b[index]))
	return maximum


func _mesh_max_normal_angle(expected: Dictionary, actual: Dictionary) -> float:
	var a: PackedVector3Array = expected.get("normals", PackedVector3Array())
	var b: PackedVector3Array = actual.get("normals", PackedVector3Array())
	if a.size() != b.size() or a.is_empty():
		return INF
	var maximum := 0.0
	for index in range(a.size()):
		maximum = maxf(maximum, rad_to_deg(acos(clampf(a[index].normalized().dot(b[index].normalized()), -1.0, 1.0))))
	return maximum


func _fail_row(row: Dictionary, reason: String) -> Dictionary:
	row["status"] = "FAIL"
	row["failure_reason"] = reason
	_failures += 1
	push_error("%s: %s" % [String(row.get("scenario_id", "unknown")), reason])
	return row


func _write_results() -> void:
	var jsonl := PackedByteArray()
	for row in _rows:
		jsonl.append_array((JSON.stringify(row) + "\n").to_utf8_buffer())
	_write_new(_root_path.path_join("r3a-results.jsonl"), jsonl)
	var columns := ["scenario_id", "layout", "operation_count", "status", "full_query_p50_ms", "indexed_query_p50_ms", "indexed_max_candidates", "reference_lod0_p50_ms", "fast_lod0_p50_ms", "reference_lod1_p50_ms", "fast_lod1_p50_ms", "fast_lod0_geometry_mismatches", "fast_lod1_geometry_mismatches", "mesh_cache_lod0_cold_ms", "mesh_cache_lod0_warm_ms", "mesh_cache_lod1_cold_ms", "mesh_cache_lod1_warm_ms", "mesh_cache_disk_bytes", "mesh_cache_corrupt_recovered", "density_snapshot_build_ms", "snapshot_lod0_build_ms", "snapshot_lod1_build_ms", "snapshot_lod0_max_vertex_error", "snapshot_lod1_max_vertex_error", "snapshot_lod0_max_normal_angle_degrees", "snapshot_lod1_max_normal_angle_degrees", "snapshot_probe_mismatches", "failure_reason"]
	var csv := PackedStringArray()
	csv.append(",".join(columns))
	for row in _rows:
		var cells := PackedStringArray()
		for column in columns:
			var value: Variant = row.get(column, "")
			var text := str(value)
			if text.contains(",") or text.contains("\"") or text.contains("\n"):
				text = "\"" + text.replace("\"", "\"\"") + "\""
			cells.append(text)
		csv.append(",".join(cells))
	_write_new(_root_path.path_join("r3a-results.csv"), ("\n".join(csv) + "\n").to_utf8_buffer())
	_write_new(_root_path.path_join("r3a-summary.json"), JSON.stringify({
		"source_sha": OS.get_environment("P31_R3A_SOURCE_SHA"), "seed": SEED,
		"scenarios": _rows.size(), "reference_hash_checks": _assertions, "failures": _failures,
		"result_sha256": _sha256(jsonl), "duration_ms": _ms(Time.get_ticks_usec() - _started_usec),
	}, "\t", true).to_utf8_buffer())


func _write_new(path: String, bytes: PackedByteArray) -> bool:
	if FileAccess.file_exists(path):
		_failures += 1
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures += 1
		return false
	file.store_buffer(bytes)
	file.flush()
	return file.get_error() == OK


func _directory_bytes(path: String) -> int:
	if not DirAccess.dir_exists_absolute(path):
		return 0
	var total := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var absolute := path.path_join(name)
		if dir.current_is_dir():
			total += _directory_bytes(absolute)
		else:
			total += FileAccess.get_file_as_bytes(absolute).size()
		name = dir.get_next()
	dir.list_dir_end()
	return total


func _percentile_ms(samples: PackedFloat64Array, percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var values: Array[float] = []
	for sample in samples:
		values.append(float(sample))
	values.sort()
	var index := clampi(int(ceil(float(values.size()) * percentile)) - 1, 0, values.size() - 1)
	return _ms(int(values[index]))


func _ms(usec: int) -> float:
	return float(usec) / 1000.0


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
