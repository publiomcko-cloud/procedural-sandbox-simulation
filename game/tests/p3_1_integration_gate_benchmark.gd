extends SceneTree

## Opt-in, test-only P3.1 integration benchmark. All world and object stores are
## rooted below P31_BENCH_OUTPUT_DIR; this harness never opens the default save.
const Store := preload("res://scripts/terrain/terrain_world_save_store_v2.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const ObjectStream := preload("res://scripts/objects/procedural_object_stream.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const ModLoader := preload("res://scripts/modding/declarative_mod_loader.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const ObjectStateServiceScript := preload("res://scripts/objects/procedural_object_state_service.gd")
const EntityCommandServiceScript := preload("res://scripts/entities/entity_command_service.gd")
const EntityStateContract := preload("res://scripts/objects/procedural_object_state_contract.gd")

const SEED := 131_102_026
const REPEATS := 5
const OPERATION_COUNTS := [0, 256, 640, 2048, 8192]
const LAYOUTS := ["distributed", "concentrated"]
const FULL_REPLAY_PROBES := [
	Vector3(-16.01, 2.5, -12.01), Vector3(-16.0, 2.5, -12.0), Vector3(-0.01, 2.5, -0.01),
	Vector3.ZERO, Vector3(0.01, 2.5, 0.01), Vector3(15.99, 2.5, 11.99), Vector3(16.01, 2.5, 12.01),
]
const POPULATION_TARGETS := [100, 500, 1000, 2000]
const POPULATION_MAX_REGIONS := 900
const ENTITY_COMMAND_OBJECTS := 16
const ENTITY_WORLD_ID := "p31-issue131-entity-commands"
const ENTITY_DEFINITION_ID := "firstparty.core_rocks:granite"

var _output_root := ""
var _rows: Array[Dictionary] = []
var _population_rows: Array[Dictionary] = []
var _entity_rows: Array[Dictionary] = []
var _failure_count := 0
var _started_usec := 0
var _phase := "all"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_usec = Time.get_ticks_usec()
	_output_root = OS.get_environment("P31_BENCH_OUTPUT_DIR")
	if _output_root.is_empty() or not _output_root.is_absolute_path():
		push_error("P31 benchmark requires an absolute P31_BENCH_OUTPUT_DIR")
		quit(2)
		return
	if DirAccess.dir_exists_absolute(_output_root) and not DirAccess.get_files_at(_output_root).is_empty():
		push_error("P31 benchmark output directory must be new and empty")
		quit(2)
	var make_error := DirAccess.make_dir_recursive_absolute(_output_root)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		push_error("P31 benchmark output directory unavailable: %d" % make_error)
		quit(2)
	_phase = OS.get_environment("P31_BENCH_PHASE")
	if _phase.is_empty():
		_phase = "all"
	if _phase not in ["all", "entities-only"]:
		push_error("P31 benchmark phase must be all or entities-only")
		quit(2)
		return
	_write_input_manifest()
	if _phase == "all":
		for layout in LAYOUTS:
			for operation_count in OPERATION_COUNTS:
				for repetition in range(REPEATS):
					_rows.append(_run_storage_case(String(layout), int(operation_count), repetition + 1))
		for population_repetition in range(REPEATS):
			await _run_population_sweep(population_repetition + 1)
	_run_entity_command_sweep()
	_write_outputs()
	var duration_usec := Time.get_ticks_usec() - _started_usec
	if _failure_count == 0:
		print("P31_INTEGRATION_BENCH_PASS: edit_runs=%d population_targets=%d failures=0 duration_ms=%.3f" % [_rows.size(), _population_rows.size(), float(duration_usec) / 1000.0])
	else:
		push_error("P31_INTEGRATION_BENCH_FAIL: edit_runs=%d population_targets=%d failures=%d duration_ms=%.3f" % [_rows.size(), _population_rows.size(), _failure_count, float(duration_usec) / 1000.0])
	quit(0 if _failure_count == 0 else 1)


func _write_input_manifest() -> void:
	var operations := []
	for layout_value in LAYOUTS:
		for count_value in OPERATION_COUNTS:
			operations.append({
				"scenario_id": "P31.EDIT.%s.N%04d.v1" % [String(layout_value).to_upper(), int(count_value)],
				"scenario_version": 1,
				"world_seed": SEED,
				"generator_version": Field.GENERATOR_VERSION,
				"operation_count": int(count_value),
				"layout": layout_value,
				"radius_mm": 580,
				"ordered_modes": "CARVE for even sequence, FILL for odd sequence",
				"distribution_recipe": "global region lattice with signed coordinates; every fourth command is face/corner-adjacent" if layout_value == "distributed" else "13x11x9-mm deterministic offsets concentrated around origin",
			})
	var manifest := {
		"contract": "P3.1 Issue 131 integration gate",
		"manifest_version": 1,
		"execution_phase": _phase,
		"source_sha": OS.get_environment("P31_SOURCE_SHA"),
		"godot_version": Engine.get_version_info(),
		"seed": SEED,
		"repetitions": REPEATS,
		"edit_scenarios": operations,
		"population_targets": POPULATION_TARGETS,
		"population_repetitions": REPEATS,
		"population_rule": "registered production first-party and example packages; traverse signed regions, preserve 25-region resident cap; cumulative target records first published-region crossing",
		"entity_command_scenario": {
			"scenario_id": "P31.ENTITIES.TRANSACTIONAL.COMMANDS.N0016.v1",
			"schema": 3,
			"explicit_placed_objects": ENTITY_COMMAND_OBJECTS,
			"per_object_order": ["ENTITY_PLACE", "ENTITY_SET_COMPONENT", "ENTITY_DELETE", "ENTITY_UNDO", "ENTITY_REDO", "ENTITY_UNDO"],
			"procedural_control_order": ["ENTITY_SET_COMPONENT", "ENTITY_RESTORE"],
			"seed": SEED,
			"region_key": [0, 0],
			"first_party_and_example_data_only": true,
		},
		"metric_semantics": {
			"headless_frame_metrics": "not measured; do not infer FPS or GPU presentation",
			"SDF": "monotonic Time.get_ticks_usec; indexed source-backed evaluator compared exactly against full ordered CARVE/FILL replay",
			"save_load": "includes segment verification and manifest/index processing performed by v2 store",
			"RAM": "Godot static memory in script; wrapper records process working-set sampling separately",
			"GPU": "not measured by this CPU harness",
		},
	}
	var bytes := JSON.stringify(manifest, "\t", true).to_utf8_buffer()
	var manifest_path := _output_root.path_join("scenario-manifest.json")
	if not _write_new(manifest_path, bytes):
		_failure_count += 1
		return
	_write_new(_output_root.path_join("scenario-manifest.sha256"), (_sha256(bytes) + "  scenario-manifest.json\n").to_utf8_buffer())


func _run_storage_case(layout: String, operation_count: int, repetition: int) -> Dictionary:
	var scenario_id := "P31.EDIT.%s.N%04d.v1" % [layout.to_upper(), operation_count]
	var run_id := "%s.R%02d" % [scenario_id, repetition]
	var store_directory := _output_root.path_join("worlds").path_join(run_id)
	var legacy_directory := _output_root.path_join("legacy-unused").path_join(run_id)
	var ledger: RefCounted = Brush.new(SEED, Field.GENERATOR_VERSION)
	var canonical_commands: Array[Dictionary] = []
	var generation_start := Time.get_ticks_usec()
	var accepted := true
	for sequence in range(operation_count):
		var center := _command_center(layout, sequence)
		var mode := Brush.Mode.CARVE if sequence % 2 == 0 else Brush.Mode.FILL
		if not ledger.add_sphere(mode, center, 0.58):
			accepted = false
			break
		canonical_commands.append({
			"sequence": sequence,
			"revision": sequence + 1,
			"mode": "CARVE" if mode == Brush.Mode.CARVE else "FILL",
			"center_mm": [roundi(center.x * 1000.0), roundi(center.y * 1000.0), roundi(center.z * 1000.0)],
			"radius_mm": 580,
		})
	var generation_usec := Time.get_ticks_usec() - generation_start
	var command_bytes := JSON.stringify(canonical_commands).to_utf8_buffer()
	var command_sha := _sha256(command_bytes)
	var row := {
		"scenario_id": scenario_id,
		"run_id": run_id,
		"repetition": repetition,
		"world_seed": SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"operation_count": operation_count,
		"accepted_operation_count": ledger.get_edit_count(),
		"last_sequence": ledger.get_last_sequence(),
		"ledger_revision": ledger.revision,
		"command_list_sha256": command_sha,
		"layout": layout,
		"generation_ms": _ms(generation_usec),
		"initial_save_ms": 0.0,
		"repeated_save_p50_ms": 0.0,
		"repeated_save_p95_ms": 0.0,
		"repeated_save_p99_ms": 0.0,
		"append_delta_save_ms": 0.0,
		"restart_load_ms": 0.0,
		"cold_query_p50_ms": 0.0,
		"cold_query_p95_ms": 0.0,
		"cold_query_p99_ms": 0.0,
		"warm_query_p50_ms": 0.0,
		"warm_query_p95_ms": 0.0,
		"warm_query_p99_ms": 0.0,
		"indexed_full_replay_mismatches": -1,
		"cold_segment_reads": 0,
		"cold_segment_bytes": 0,
		"warm_segment_reads": 0,
		"warm_cache_hits": 0,
		"query_candidates": 0,
		"lod0_build_ms": 0.0,
		"lod1_build_ms": 0.0,
		"lod0_valid": false,
		"lod1_valid": false,
		"storage_segments": 0,
		"initial_disk_bytes": 0,
		"final_disk_bytes": 0,
		"godot_static_memory_delta_bytes": 0,
		"status": "PASS",
		"failure_reason": "",
	}
	if not accepted or ledger.get_edit_count() != operation_count or ledger.get_last_sequence() != operation_count - 1:
		return _fail_row(row, "ledger_generation_or_sequence_mismatch")
	var memory_before := OS.get_static_memory_usage()
	var store: RefCounted = Store.new(store_directory, legacy_directory)
	var save_start := Time.get_ticks_usec()
	var save_result: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
	row.initial_save_ms = _ms(Time.get_ticks_usec() - save_start)
	row.storage_segments = int(save_result.get("segment_count", -1))
	if not save_result.get("ok", false):
		return _fail_row(row, "initial_save:%s" % save_result.get("reason", "failed"))
	row.initial_disk_bytes = _directory_bytes(store_directory)
	var restart_store: RefCounted = Store.new(store_directory, legacy_directory)
	var load_start := Time.get_ticks_usec()
	var loaded: Dictionary = restart_store.load_world()
	row.restart_load_ms = _ms(Time.get_ticks_usec() - load_start)
	if not loaded.get("ok", false) or not loaded.get("found", false):
		return _fail_row(row, "restart_load:%s" % loaded.get("reason", "not_found"))
	var payload: Dictionary = loaded.get("payload", {})
	var restored: RefCounted = Brush.new(int(payload.get("world_seed", -1)), int(payload.get("generator_version", -1)))
	var persistence_snapshot := {
		"world_seed": int(payload.get("world_seed", -1)),
		"generator_version": int(payload.get("generator_version", -1)),
		"revision": int(payload.get("ledger_revision", -1)),
		"next_sequence": int(payload.get("next_sequence", -1)),
		"storage_reference": payload.get("storage_reference", {}),
	}
	if not restored.restore_persistence_snapshot(persistence_snapshot):
		return _fail_row(row, "restart_attach:%s" % restored.last_restore_rejection_reason)
	if restored.get_edit_count() != operation_count or restored.get_next_sequence() != operation_count:
		return _fail_row(row, "restart_operation_count_mismatch")
	var expected_operations: Array[Dictionary] = ledger.get_operations_snapshot()
	restart_store.clear_segment_cache()
	restart_store.reset_query_stats()
	var cold_samples := PackedFloat64Array()
	var warm_samples := PackedFloat64Array()
	var mismatches := 0
	for probe in FULL_REPLAY_PROBES:
		var mapped: Dictionary = Spatial.world_to_region_local(probe)
		var actual_start := Time.get_ticks_usec()
		var actual: float = restored.sample_density(SEED, mapped.region_key, mapped.local_position)
		cold_samples.append(float(Time.get_ticks_usec() - actual_start))
		var expected := _full_replay_density(SEED, mapped.region_key, mapped.local_position, expected_operations)
		if actual != expected:
			mismatches += 1
		row.query_candidates = maxi(int(row.query_candidates), int(restored.last_sample_candidate_count))
	for repeat in range(3):
		for probe in FULL_REPLAY_PROBES:
			var mapped: Dictionary = Spatial.world_to_region_local(probe)
			var query_start := Time.get_ticks_usec()
			restored.sample_density(SEED, mapped.region_key, mapped.local_position)
			warm_samples.append(float(Time.get_ticks_usec() - query_start))
	row.cold_query_p50_ms = _percentile_ms(cold_samples, 0.50)
	row.cold_query_p95_ms = _percentile_ms(cold_samples, 0.95)
	row.cold_query_p99_ms = _percentile_ms(cold_samples, 0.99)
	row.warm_query_p50_ms = _percentile_ms(warm_samples, 0.50)
	row.warm_query_p95_ms = _percentile_ms(warm_samples, 0.95)
	row.warm_query_p99_ms = _percentile_ms(warm_samples, 0.99)
	row.cold_segment_reads = int(restart_store.segment_read_count)
	row.cold_segment_bytes = int(restart_store.segment_read_bytes)
	row.warm_segment_reads = int(restart_store.last_query_segment_reads)
	row.warm_cache_hits = int(restart_store.segment_cache_hit_count)
	row.indexed_full_replay_mismatches = mismatches
	if mismatches > 0:
		return _fail_row(row, "indexed_full_replay_mismatch")
	var repeat_save_samples := PackedFloat64Array()
	for repeat in range(3):
		var repeated_start := Time.get_ticks_usec()
		var repeated: Dictionary = restart_store.save_ledger(Store.WORLD_ID, restored)
		repeat_save_samples.append(float(Time.get_ticks_usec() - repeated_start))
		if not repeated.get("ok", false) or int(repeated.get("segments_written", -1)) != 0:
			return _fail_row(row, "unchanged_save_reuse:%s" % repeated.get("reason", "unexpected_segment_write"))
	row.repeated_save_p50_ms = _percentile_ms(repeat_save_samples, 0.50)
	row.repeated_save_p95_ms = _percentile_ms(repeat_save_samples, 0.95)
	row.repeated_save_p99_ms = _percentile_ms(repeat_save_samples, 0.99)
	var lod_snapshot: Dictionary = restored.get_meshing_snapshot_for_chunk(Vector2i.ZERO, Vector2i.ZERO)
	var lod0_start := Time.get_ticks_usec()
	var lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, Vector2i.ZERO, Vector2i.ZERO, false, lod_snapshot)
	row.lod0_build_ms = _ms(Time.get_ticks_usec() - lod0_start)
	row.lod0_valid = bool(lod0.get("valid", false))
	var lod1_start := Time.get_ticks_usec()
	var lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, Vector2i.ZERO, Vector2i.ZERO, lod_snapshot)
	row.lod1_build_ms = _ms(Time.get_ticks_usec() - lod1_start)
	row.lod1_valid = bool(lod1.get("valid", false))
	if not row.lod0_valid or not row.lod1_valid:
		return _fail_row(row, "lod_reconstruction_invalid")
	var append_center := Vector3(17.25, 2.5, -12.25)
	var append_mode := Brush.Mode.FILL if operation_count % 2 == 0 else Brush.Mode.CARVE
	if not restored.add_sphere(append_mode, append_center, 0.58):
		return _fail_row(row, "append_after_restart_rejected:%s" % restored.last_rejection_reason)
	var append_start := Time.get_ticks_usec()
	var append_result: Dictionary = restart_store.save_ledger(Store.WORLD_ID, restored)
	row.append_delta_save_ms = _ms(Time.get_ticks_usec() - append_start)
	if not append_result.get("ok", false) or int(append_result.get("segments_written", 0)) != 1:
		return _fail_row(row, "append_delta_save:%s" % append_result.get("reason", "delta_segment_not_written"))
	var final_store: RefCounted = Store.new(store_directory, legacy_directory)
	var final_load: Dictionary = final_store.load_world()
	if not final_load.get("ok", false) or int(final_load.get("payload", {}).get("operation_count", -1)) != operation_count + 1:
		return _fail_row(row, "final_restart_count_mismatch")
	row.final_disk_bytes = _directory_bytes(store_directory)
	row.godot_static_memory_delta_bytes = maxi(0, OS.get_static_memory_usage() - memory_before)
	row["final_sequence"] = restored.get_last_sequence()
	row["final_revision"] = restored.revision
	row["appended_operation_count"] = restored.get_edit_count()
	row["append_segments_reused"] = int(append_result.get("segments_reused", -1))
	row["append_segments_written"] = int(append_result.get("segments_written", -1))
	var sidecar := command_sha + "  %s.commands.json\n" % run_id
	if not _write_new(_output_root.path_join(run_id + ".commands.json"), command_bytes) or not _write_new(_output_root.path_join(run_id + ".commands.sha256"), sidecar.to_utf8_buffer()):
		return _fail_row(row, "command_artifact_write_failed")
	return row


func _command_center(layout: String, sequence: int) -> Vector3:
	if layout == "concentrated":
		var x_mm := -120 + (sequence % 13) * 20
		var y_mm := 2100 + (sequence % 7) * 30
		var z_mm := -160 + (sequence % 11) * 25
		return Vector3(float(x_mm), float(y_mm), float(z_mm)) / 1000.0
	if sequence % 4 != 0:
		var region := Vector2i((sequence % 64) - 32, int(sequence / 64) - 64)
		var origin: Vector3 = Spatial.region_origin_world(region)
		return origin + Vector3(8.0, 2.1 + float(sequence % 7) * 0.1, 6.0)
	var edge_region := Vector2i((sequence % 9) - 4, (int(sequence / 9) % 9) - 4)
	var edge_origin: Vector3 = Spatial.region_origin_world(edge_region)
	var near_x := 15.75 if sequence % 8 == 0 else 0.25
	var near_z := 11.75 if sequence % 16 == 0 else 0.25
	return edge_origin + Vector3(near_x, 2.4 + float(sequence % 3) * 0.1, near_z)


func _full_replay_density(seed: int, region_key: Vector2i, local: Vector3, operations: Array[Dictionary]) -> float:
	var density: float = Field.sample_density(seed, region_key, local)
	var world_point: Vector3 = Spatial.region_local_to_world(region_key, local)
	for operation in operations:
		var signed_distance := world_point.distance_to(operation.center_world) - float(operation.radius)
		if int(operation.mode) == Brush.Mode.CARVE:
			density = minf(density, signed_distance)
		else:
			density = maxf(density, -signed_distance)
	return density


func _run_population_sweep(repetition: int) -> void:
	var stream: ProceduralObjectStream = ObjectStream.new()
	root.add_child(stream)
	var state_root := _output_root.path_join("entity-state-r%02d" % repetition)
	var initialization: Dictionary = stream.initialize(SEED, "issue131-population-r%02d" % repetition, [], state_root)
	if not initialization.get("ok", false):
		_failure_count += 1
		_population_rows.append({"status": "FAIL", "reason": "registry_init:%s" % initialization.get("reason", "unknown")})
		stream.queue_free()
		return
	var seen_ids: Dictionary = {}
	var publication_samples := PackedFloat64Array()
	var region_generation_samples := PackedFloat64Array()
	var cumulative_instances := 0
	var peak_resident_regions := 0
	var peak_resident_instances := 0
	var oldest_regions: Array[Vector2i] = []
	var target_index := 0
	for index in range(POPULATION_MAX_REGIONS):
		var key := Vector2i(index - 450, ((index * 17) % 101) - 50)
		while stream.get_active_region_count() >= ObjectStream.MAX_RESIDENT_REGIONS:
			if oldest_regions.is_empty():
				break
			stream.unload_region(oldest_regions.pop_front())
		var state: RefCounted = WorldState.new(SEED, key, Brush.new(SEED, Field.GENERATOR_VERSION))
		var start := Time.get_ticks_usec()
		var queued: Dictionary = stream.enqueue_region_publication(key, state, index + 1)
		if not queued.get("ok", false):
			_failure_count += 1
			_population_rows.append({"status": "FAIL", "reason": "object_queue:%s" % queued.get("reason", "unknown"), "region_index": index})
			break
		await process_frame
		if stream.process_queued_publications() != 1:
			_failure_count += 1
			_population_rows.append({"status": "FAIL", "reason": "publication_budget_not_one", "region_index": index})
			break
		var region_elapsed := Time.get_ticks_usec() - start
		publication_samples.append(float(region_elapsed))
		region_generation_samples.append(float(stream.get_performance_snapshot().get("last_region", {}).get("mesh_build_usec", 0)))
		var records: Array[Dictionary] = stream.get_region_instance_records(key)
		cumulative_instances += records.size()
		for record in records:
			var instance_id := String(record.get("instance_id", ""))
			if instance_id.is_empty() or seen_ids.has(instance_id):
				_failure_count += 1
				_population_rows.append({"status": "FAIL", "reason": "empty_or_duplicate_instance_id", "region_index": index})
			else:
				seen_ids[instance_id] = true
		if stream.get_active_region_count() > ObjectStream.MAX_RESIDENT_REGIONS:
			_failure_count += 1
			_population_rows.append({"status": "FAIL", "reason": "resident_region_limit_exceeded", "count": stream.get_active_region_count()})
		oldest_regions.append(key)
		peak_resident_regions = maxi(peak_resident_regions, stream.get_active_region_count())
		peak_resident_instances = maxi(peak_resident_instances, stream.get_visible_instance_count())
		while target_index < POPULATION_TARGETS.size() and cumulative_instances >= int(POPULATION_TARGETS[target_index]):
			var performance: Dictionary = stream.get_performance_snapshot()
			var population_row := {
				"scenario_id": "P31.OBJECTS.CUMULATIVE.N%04d.v1.R%02d" % [int(POPULATION_TARGETS[target_index]), repetition],
				"repetition": repetition,
				"target_objects": int(POPULATION_TARGETS[target_index]),
				"actual_cumulative_objects": cumulative_instances,
				"regions_published": index + 1,
				"active_regions": stream.get_active_region_count(),
				"resident_instances": stream.get_visible_instance_count(),
				"peak_active_regions": peak_resident_regions,
				"peak_resident_instances": peak_resident_instances,
				"publication_p50_ms": _percentile_ms(publication_samples, 0.50),
				"publication_p95_ms": _percentile_ms(publication_samples, 0.95),
				"region_mesh_build_p50_ms": _percentile_ms(region_generation_samples, 0.50),
				"region_mesh_build_p95_ms": _percentile_ms(region_generation_samples, 0.95),
				"stream_snapshot": performance,
				"status": "PASS",
			}
			_population_rows.append(population_row)
			target_index += 1
	if target_index != POPULATION_TARGETS.size():
		_failure_count += 1
		_population_rows.append({"status": "FAIL", "reason": "population_targets_not_reached", "targets_reached": target_index, "actual_cumulative_objects": cumulative_instances, "regions_published": oldest_regions.size()})
	stream.queue_free()
	await process_frame


func _run_entity_command_sweep() -> void:
	var row := {
		"scenario_id": "P31.ENTITIES.TRANSACTIONAL.COMMANDS.N0016.v1",
		"source_sha": OS.get_environment("P31_SOURCE_SHA"),
		"world_seed": SEED,
		"object_count": ENTITY_COMMAND_OBJECTS,
		"status": "PASS",
		"failure_reason": "",
	}
	var output_path := _output_root.path_join("entity-command-state")
	var memory_before := OS.get_static_memory_usage()
	var state: RefCounted = ObjectStateServiceScript.new()
	var initialized: Dictionary = state.initialize(ENTITY_WORLD_ID, SEED, Field.GENERATOR_VERSION, output_path)
	if not initialized.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "state_initialize:%s" % initialized.get("reason", "unknown")))
		return
	var migration_start := Time.get_ticks_usec()
	var migrated: Dictionary = state.upgrade_history_snapshot_schema()
	row["explicit_schema3_migration_ms"] = _ms(Time.get_ticks_usec() - migration_start)
	if not migrated.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "schema3_preflight:%s" % migrated.get("reason", "unknown")))
		return
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repository_example_root := project_root.get_base_dir().path_join("mods/examples")
	var discovery: Dictionary = ModLoader.discover_and_validate(["res://mods/first-party", repository_example_root])
	if not discovery.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "first_party_registry_discovery:%s" % discovery.get("reason", "unknown")))
		return
	var registry: RefCounted = RegistryScript.new()
	var registered: Dictionary = registry.register_discovered(discovery)
	if not registered.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "first_party_registry_registration:%s" % registered.get("reason", "unknown")))
		return
	var commands: RefCounted = EntityCommandServiceScript.new()
	var service_init: Dictionary = commands.initialize(state, registry)
	if not service_init.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "entity_service_initialize:%s" % service_init.get("reason", "unknown")))
		return
	var reconstruction: Dictionary = commands.reconstruct_region(Vector2i.ZERO)
	if not reconstruction.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "initial_region_reconstruction:%s" % reconstruction.get("reason", "unknown")))
		return
	var procedural_instances: Array[Dictionary] = commands.get_region_base_instances(Vector2i.ZERO)
	if procedural_instances.is_empty():
		_entity_rows.append(_fail_entity_row(row, "no_procedural_control_entity"))
		return
	var command_records: Array[Dictionary] = []
	var samples_by_operation: Dictionary = {}
	var placed_ids: Array[String] = []
	var command_ordinal := 1
	var command_start := Time.get_ticks_usec()
	for object_index in range(ENTITY_COMMAND_OBJECTS):
		var command_id := _entity_uuid(command_ordinal)
		command_ordinal += 1
		var command := _entity_place_command(state, command_id, object_index)
		command_records.append(command.duplicate(true))
		var place_result := _dispatch_entity_command(commands, state, command, samples_by_operation)
		if not place_result.get("ok", false):
			_entity_rows.append(_fail_entity_row(row, "place_%d:%s" % [object_index, place_result.get("reason", "unknown")]))
			return
		var entity_id := String(place_result.get("entity_id", ""))
		if entity_id.is_empty() or placed_ids.has(entity_id):
			_entity_rows.append(_fail_entity_row(row, "placed_identity_empty_or_duplicate"))
			return
		placed_ids.append(entity_id)
		var transform_id := _entity_uuid(command_ordinal)
		command_ordinal += 1
		var transform_command := _entity_component_command(state, transform_id, entity_id, {"schema_version": 1, "properties": {"translation_mm": [0, 100 + object_index, 0], "rotation_mdeg": [0, 0, object_index * 1000], "scale_milli": [1000, 1000, 1000]}})
		command_records.append(transform_command.duplicate(true))
		var transform_result := _dispatch_entity_command(commands, state, transform_command, samples_by_operation)
		if not transform_result.get("ok", false):
			_entity_rows.append(_fail_entity_row(row, "transform_%d:%s" % [object_index, transform_result.get("reason", "unknown")]))
			return
		var delete_id := _entity_uuid(command_ordinal)
		command_ordinal += 1
		var delete_command := _entity_simple_command(state, "ENTITY_DELETE", delete_id, entity_id)
		command_records.append(delete_command.duplicate(true))
		var delete_result := _dispatch_entity_command(commands, state, delete_command, samples_by_operation)
		if not delete_result.get("ok", false):
			_entity_rows.append(_fail_entity_row(row, "delete_%d:%s" % [object_index, delete_result.get("reason", "unknown")]))
			return
		var undo_delete_id := _entity_uuid(command_ordinal)
		command_ordinal += 1
		var undo_delete_command := _entity_history_command(commands, state, "ENTITY_UNDO", undo_delete_id, entity_id)
		command_records.append(undo_delete_command.duplicate(true))
		var undo_result := _dispatch_entity_command(commands, state, undo_delete_command, samples_by_operation)
		if not undo_result.get("ok", false) or state.snapshot.deleted.has(entity_id):
			_entity_rows.append(_fail_entity_row(row, "undo_delete_%d:%s" % [object_index, undo_result.get("reason", "deleted_after_undo")]))
			return
		var redo_id := _entity_uuid(command_ordinal)
		command_ordinal += 1
		var redo_command := _entity_history_command(commands, state, "ENTITY_REDO", redo_id, entity_id)
		command_records.append(redo_command.duplicate(true))
		var redo_result := _dispatch_entity_command(commands, state, redo_command, samples_by_operation)
		if not redo_result.get("ok", false) or not state.snapshot.deleted.has(entity_id):
			_entity_rows.append(_fail_entity_row(row, "redo_delete_%d:%s" % [object_index, redo_result.get("reason", "not_deleted_after_redo")]))
			return
		var final_undo_id := _entity_uuid(command_ordinal)
		command_ordinal += 1
		var final_undo_command := _entity_history_command(commands, state, "ENTITY_UNDO", final_undo_id, entity_id)
		command_records.append(final_undo_command.duplicate(true))
		var final_undo_result := _dispatch_entity_command(commands, state, final_undo_command, samples_by_operation)
		if not final_undo_result.get("ok", false) or state.snapshot.deleted.has(entity_id):
			_entity_rows.append(_fail_entity_row(row, "final_undo_%d:%s" % [object_index, final_undo_result.get("reason", "still_deleted")]))
			return
	var procedural_id := String(procedural_instances[0].get("instance_id", ""))
	var procedural_transform_id := _entity_uuid(command_ordinal)
	command_ordinal += 1
	var procedural_transform := _entity_component_command(state, procedural_transform_id, procedural_id, {"schema_version": 1, "properties": {"translation_mm": [0, 250, 0], "rotation_mdeg": [0, 5000, 0], "scale_milli": [1000, 1000, 1000]}})
	command_records.append(procedural_transform.duplicate(true))
	var procedural_transform_result := _dispatch_entity_command(commands, state, procedural_transform, samples_by_operation)
	if not procedural_transform_result.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "procedural_transform:%s" % procedural_transform_result.get("reason", "unknown")))
		return
	var restore_id := _entity_uuid(command_ordinal)
	var restore_command := _entity_simple_command(state, "ENTITY_RESTORE", restore_id, procedural_id)
	command_records.append(restore_command.duplicate(true))
	var restore_result := _dispatch_entity_command(commands, state, restore_command, samples_by_operation)
	if not restore_result.get("ok", false) or state.snapshot.overrides.has(procedural_id):
		_entity_rows.append(_fail_entity_row(row, "procedural_restore:%s" % restore_result.get("reason", "override_remains")))
		return
	var valid_snapshot: Dictionary = EntityStateContract.validate_snapshot(state.snapshot, ENTITY_WORLD_ID, SEED, Field.GENERATOR_VERSION)
	if not valid_snapshot.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "entity_snapshot_invalid:%s" % valid_snapshot.get("reason", "unknown")))
		return
	var command_bytes := JSON.stringify(command_records).to_utf8_buffer()
	var command_list_sha := _sha256(command_bytes)
	if not _write_new(_output_root.path_join("entity-command-list.json"), command_bytes) or not _write_new(_output_root.path_join("entity-command-list.sha256"), (command_list_sha + "  entity-command-list.json\n").to_utf8_buffer()):
		_entity_rows.append(_fail_entity_row(row, "entity_command_artifact_write_failed"))
		return
	var restart_start := Time.get_ticks_usec()
	var restarted_state: RefCounted = ObjectStateServiceScript.new()
	var restart_result: Dictionary = restarted_state.initialize(ENTITY_WORLD_ID, SEED, Field.GENERATOR_VERSION, output_path)
	row["restart_load_ms"] = _ms(Time.get_ticks_usec() - restart_start)
	if not restart_result.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "entity_restart_load:%s" % restart_result.get("reason", "unknown")))
		return
	if int(restarted_state.get_revision()) != int(state.get_revision()) or restarted_state.snapshot.command_receipts.size() != command_records.size() or restarted_state.snapshot.placed_entities.size() != ENTITY_COMMAND_OBJECTS:
		_entity_rows.append(_fail_entity_row(row, "entity_restart_snapshot_mismatch"))
		return
	var restarted_commands: RefCounted = EntityCommandServiceScript.new()
	var restarted_service_init: Dictionary = restarted_commands.initialize(restarted_state, registry)
	if not restarted_service_init.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "entity_restart_service:%s" % restarted_service_init.get("reason", "unknown")))
		return
	var restarted_region: Dictionary = restarted_commands.reconstruct_region(Vector2i.ZERO)
	if not restarted_region.get("ok", false):
		_entity_rows.append(_fail_entity_row(row, "entity_restart_region:%s" % restarted_region.get("reason", "unknown")))
		return
	var rehydrated_ids: Dictionary = {}
	for instance in restarted_commands.get_region_base_instances(Vector2i.ZERO):
		rehydrated_ids[String(instance.get("instance_id", ""))] = true
	for entity_id in placed_ids:
		if not rehydrated_ids.has(entity_id):
			_entity_rows.append(_fail_entity_row(row, "entity_missing_after_restart:%s" % entity_id))
			return
	row["command_count"] = command_records.size()
	row["command_list_sha256"] = command_list_sha
	row["world_revision"] = state.get_revision()
	row["history_depth"] = state.snapshot.entity_history.size()
	row["history_cursor"] = state.snapshot.history_cursor
	row["receipt_count"] = state.snapshot.command_receipts.size()
	row["restart_placed_entities"] = restarted_state.snapshot.placed_entities.size()
	row["restart_reconstructed_ids"] = rehydrated_ids.size()
	row["store_bytes"] = _directory_bytes(output_path)
	row["godot_static_memory_delta_bytes"] = maxi(0, OS.get_static_memory_usage() - memory_before)
	row["action_samples"] = _aggregate_entity_action_samples(samples_by_operation)
	row["total_elapsed_ms"] = _ms(Time.get_ticks_usec() - command_start)
	_entity_rows.append(row)


func _dispatch_entity_command(commands: RefCounted, state: RefCounted, command: Dictionary, samples: Dictionary) -> Dictionary:
	var operation := String(command.operation)
	var started := Time.get_ticks_usec()
	var result: Dictionary = commands.dispatch(command)
	var elapsed := float(Time.get_ticks_usec() - started)
	if not result.get("ok", false):
		return {"ok": false, "reason": result.get("reason", "entity_command_rejected"), "elapsed_usec": elapsed}
	var values: Array = samples.get(operation, [])
	values.append(elapsed)
	samples[operation] = values
	return {"ok": true, "reason": result.get("reason", "ok"), "entity_id": result.get("entity_id", command.get("entity_id", "")), "world_revision": state.get_revision(), "elapsed_usec": elapsed, "timings_usec": result.get("timings_usec", {})}


func _aggregate_entity_action_samples(samples: Dictionary) -> Dictionary:
	var result := {}
	for operation in samples:
		var values: Array = samples[operation]
		values.sort()
		result[String(operation)] = {
			"samples": values.size(),
			"p50_ms": float(values[clampi(ceili(values.size() * 0.50) - 1, 0, values.size() - 1)]) / 1000.0,
			"p95_ms": float(values[clampi(ceili(values.size() * 0.95) - 1, 0, values.size() - 1)]) / 1000.0,
			"p99_ms": float(values[clampi(ceili(values.size() * 0.99) - 1, 0, values.size() - 1)]) / 1000.0,
		}
	return result


func _entity_place_command(state: RefCounted, command_id: String, index: int) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": "ENTITY_PLACE",
		"origin": {"type": "player", "id": "player.issue131-benchmark"},
		"world_id": ENTITY_WORLD_ID, "world_seed": SEED, "generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": state.get_revision(), "expected_entity_revision": 0,
		"definition_id": ENTITY_DEFINITION_ID, "position_mm": [2000 + index * 100, 1000, 3000 + index * 75],
		"region_key": [0, 0], "recipe_seed": SEED + index,
		"components": {
			"core.transform": {"schema_version": 1, "properties": {"translation_mm": [0, 0, 0], "rotation_mdeg": [0, 0, 0], "scale_milli": [1000, 1000, 1000]}},
			"core.appearance": {"schema_version": 1, "properties": {"tint_milli": [1000, 1000, 1000], "label": "issue131-%02d" % index}},
			"core.logical": {"schema_version": 1, "properties": {"values": {"benchmark_index": index}}},
		},
	}


func _entity_component_command(state: RefCounted, command_id: String, entity_id: String, component: Dictionary) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": "ENTITY_SET_COMPONENT",
		"origin": {"type": "player", "id": "player.issue131-benchmark"},
		"world_id": ENTITY_WORLD_ID, "world_seed": SEED, "generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": state.get_revision(), "expected_entity_revision": state.get_entity_revision(entity_id),
		"entity_id": entity_id, "component_id": "core.transform", "component": component,
	}


func _entity_simple_command(state: RefCounted, operation: String, command_id: String, entity_id: String) -> Dictionary:
	return {
		"schema_version": 1, "command_id": command_id, "operation": operation,
		"origin": {"type": "player", "id": "player.issue131-benchmark"},
		"world_id": ENTITY_WORLD_ID, "world_seed": SEED, "generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": state.get_revision(), "expected_entity_revision": state.get_entity_revision(entity_id),
		"entity_id": entity_id,
	}


func _entity_history_command(commands: RefCounted, state: RefCounted, operation: String, command_id: String, entity_id: String) -> Dictionary:
	var summary: Dictionary = commands.get_history_summary()
	var entry: Dictionary = summary.get("undo" if operation == "ENTITY_UNDO" else "redo", {})
	return {
		"schema_version": 1, "command_id": command_id, "operation": operation,
		"origin": {"type": "player", "id": "player.issue131-benchmark"},
		"world_id": ENTITY_WORLD_ID, "world_seed": SEED, "generator_version": Field.GENERATOR_VERSION,
		"expected_world_revision": state.get_revision(), "expected_entity_revision": state.get_entity_revision(entity_id),
		"entity_id": entity_id, "history_entry_id": String(entry.get("history_entry_id", "")),
	}


func _entity_uuid(value: int) -> String:
	return "00000000-0000-4000-8000-%012d" % value


func _fail_entity_row(row: Dictionary, reason: String) -> Dictionary:
	row["status"] = "FAIL"
	row["failure_reason"] = reason
	_failure_count += 1
	push_error("P31 entity scenario failed: %s" % reason)
	return row


func _write_outputs() -> void:
	var jsonl := PackedStringArray()
	for row in _rows:
		jsonl.append(JSON.stringify(row))
	var pop_jsonl := PackedStringArray()
	for row in _population_rows:
		pop_jsonl.append(JSON.stringify(row))
	var entity_jsonl := PackedStringArray()
	for row in _entity_rows:
		entity_jsonl.append(JSON.stringify(row))
	_write_new(_output_root.path_join("edit-results.jsonl"), ("\n".join(jsonl) + "\n").to_utf8_buffer())
	_write_new(_output_root.path_join("population-results.jsonl"), ("\n".join(pop_jsonl) + "\n").to_utf8_buffer())
	_write_new(_output_root.path_join("entity-results.jsonl"), ("\n".join(entity_jsonl) + "\n").to_utf8_buffer())
	var edit_csv := "scenario_id,run_id,repetition,layout,operation_count,accepted_operation_count,last_sequence,ledger_revision,command_list_sha256,generation_ms,initial_save_ms,repeated_save_p50_ms,repeated_save_p95_ms,repeated_save_p99_ms,append_delta_save_ms,restart_load_ms,cold_query_p50_ms,cold_query_p95_ms,cold_query_p99_ms,warm_query_p50_ms,warm_query_p95_ms,warm_query_p99_ms,indexed_full_replay_mismatches,cold_segment_reads,cold_segment_bytes,warm_segment_reads,warm_cache_hits,query_candidates,lod0_build_ms,lod1_build_ms,lod0_valid,lod1_valid,storage_segments,initial_disk_bytes,final_disk_bytes,godot_static_memory_delta_bytes,status,failure_reason\n"
	for row in _rows:
		var fields := PackedStringArray()
		for column in edit_csv.get_slice("\n", 0).split(","):
			fields.append(_csv_field(row.get(column, "")))
		edit_csv += ",".join(fields) + "\n"
	_write_new(_output_root.path_join("edit-results.csv"), edit_csv.to_utf8_buffer())
	var population_csv := "scenario_id,target_objects,actual_cumulative_objects,regions_published,active_regions,resident_instances,peak_active_regions,peak_resident_instances,publication_p50_ms,publication_p95_ms,region_mesh_build_p50_ms,region_mesh_build_p95_ms,status,reason\n"
	for row in _population_rows:
		var columns := population_csv.get_slice("\n", 0).split(",")
		var fields := PackedStringArray()
		for column in columns:
			fields.append(_csv_field(row.get(column, "")))
		population_csv += ",".join(fields) + "\n"
	_write_new(_output_root.path_join("population-results.csv"), population_csv.to_utf8_buffer())
	var entity_csv := "scenario_id,object_count,command_count,world_revision,history_depth,receipt_count,restart_load_ms,store_bytes,total_elapsed_ms,godot_static_memory_delta_bytes,status,failure_reason\n"
	for row in _entity_rows:
		var fields := PackedStringArray()
		for column in entity_csv.get_slice("\n", 0).split(","):
			fields.append(_csv_field(row.get(column, "")))
		entity_csv += ",".join(fields) + "\n"
	_write_new(_output_root.path_join("entity-results.csv"), entity_csv.to_utf8_buffer())
	var summary := {
		"source_sha": OS.get_environment("P31_SOURCE_SHA"),
		"execution_phase": _phase,
		"edit_run_count": _rows.size(),
		"population_record_count": _population_rows.size(),
		"entity_record_count": _entity_rows.size(),
		"failures": _failure_count,
		"edits": _aggregate_edit_rows(),
		"population": _population_rows,
		"entities": _entity_rows,
		"metric_limitations": ["headless CPU measurements are not FPS", "GPU utilization and GPU completion unavailable", "Godot static memory and external working-set sampling are different metrics", "five samples allow empirical percentiles, not tight confidence bounds"],
	}
	_write_new(_output_root.path_join("summary.json"), JSON.stringify(summary, "\t", true).to_utf8_buffer())


func _aggregate_edit_rows() -> Array[Dictionary]:
	var aggregate: Array[Dictionary] = []
	for layout in LAYOUTS:
		for count_value in OPERATION_COUNTS:
			var selected: Array[Dictionary] = []
			for row in _rows:
				if row.get("layout") == layout and int(row.get("operation_count", -1)) == int(count_value):
					selected.append(row)
			var group := {"layout": layout, "operation_count": int(count_value), "repetitions": selected.size()}
			for metric in ["generation_ms", "initial_save_ms", "restart_load_ms", "cold_query_p50_ms", "warm_query_p50_ms", "append_delta_save_ms", "lod0_build_ms", "lod1_build_ms", "final_disk_bytes", "godot_static_memory_delta_bytes"]:
				var samples := PackedFloat64Array()
				for row in selected:
					samples.append(float(row.get(metric, 0.0)))
				group[metric + "_p50"] = _percentile_ms(samples, 0.50) if metric.ends_with("_ms") else _percentile_float(samples, 0.50)
				group[metric + "_p95"] = _percentile_ms(samples, 0.95) if metric.ends_with("_ms") else _percentile_float(samples, 0.95)
				group[metric + "_p99"] = _percentile_ms(samples, 0.99) if metric.ends_with("_ms") else _percentile_float(samples, 0.99)
			aggregate.append(group)
	return aggregate


func _percentile_ms(values: PackedFloat64Array, fraction: float) -> float:
	return _percentile_float(values, fraction) / 1000.0


func _percentile_float(values: PackedFloat64Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)
	return float(sorted[index])


func _ms(microseconds: int) -> float:
	return float(microseconds) / 1000.0


func _directory_bytes(path: String) -> int:
	var total := 0
	var directory := DirAccess.open(path)
	if directory == null:
		return total
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if directory.current_is_dir():
			total += _directory_bytes(child)
		else:
			total += int(FileAccess.get_file_as_bytes(child).size())
	directory.list_dir_end()
	return total


func _write_new(path: String, bytes: PackedByteArray) -> bool:
	if FileAccess.file_exists(path):
		return false
	var parent := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(parent)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	file.close()
	return FileAccess.get_file_as_bytes(path) == bytes


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _csv_field(value: Variant) -> String:
	var text := str(value)
	if text.contains(",") or text.contains("\"") or text.contains("\n"):
		return "\"%s\"" % text.replace("\"", "\"\"")
	return text


func _fail_row(row: Dictionary, reason: String) -> Dictionary:
	row.status = "FAIL"
	row.failure_reason = reason
	_failure_count += 1
	push_error("P31 scenario %s failed: %s" % [row.get("run_id", "unknown"), reason])
	return row
