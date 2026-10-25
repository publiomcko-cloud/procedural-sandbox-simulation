extends SceneTree

const Store := preload("res://scripts/terrain/terrain_world_save_store_v2.gd")
const LegacyStore := preload("res://scripts/terrain/terrain_world_save_store.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

var assertions := 0
var failures := 0
var _root := ""


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("user://p3_1_storage_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_root)
	_test_scalable_segmented_replay_and_spatial_index()
	_test_dense_history_exact_order_and_reset()
	_test_restart_streaming_lod_and_corruption()
	_test_interruption_legacy_isolation_and_quotas()
	_remove_tree(_root)
	if failures == 0:
		print("TERRAIN_WORLD_V2_STORAGE_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("TERRAIN_WORLD_V2_STORAGE_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_scalable_segmented_replay_and_spatial_index() -> void:
	var ledger: RefCounted = Brush.new(13579, Field.GENERATOR_VERSION)
	var started := Time.get_ticks_usec()
	for index in range(640):
		var region := Vector2i((index % 40) - 20, (index / 40) - 8)
		var origin: Vector3 = Spatial.region_origin_world(region)
		var mode := Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL
		var center := origin + Vector3(8.0, 2.25 + float(index % 5) * 0.1, 6.0)
		_check(ledger.add_sphere(mode, center, 0.58), "distributed edit %d accepted" % index)
	var generation_us := Time.get_ticks_usec() - started
	_check(ledger.get_edit_count() == 640 and ledger.get_last_sequence() == 639 and ledger.revision == 640, "640 distributed operations exceed the old cap with stable order")
	var store := Store.new(_root.path_join("distributed"), _root.path_join("legacy-absent"))
	var save_started := Time.get_ticks_usec()
	var saved: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
	var save_us := Time.get_ticks_usec() - save_started
	_check(saved.get("ok", false), "segmented v2 save succeeds (%s)" % saved.get("reason", "ok"))
	_check(int(saved.get("segment_count", 0)) == 5, "640 operations are written as five bounded segments")
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = store.load_world()
	var load_us := Time.get_ticks_usec() - load_started
	_check(loaded.get("ok", false) and loaded.get("found", false), "v2 manifest and all segment/index checks validate: %s" % JSON.stringify(loaded.get("diagnostics", [])))
	if not loaded.get("ok", false) or not loaded.get("found", false):
		return
	_check(not loaded["payload"].has("operations") and loaded["payload"].has("storage_reference"), "load keeps operation payloads lazy instead of materializing the world log")
	_test_storage_reference_identity(loaded)
	var restored: RefCounted = _restore_loaded(store, loaded)
	if restored.get_edit_count() != 640:
		return
	_check(restored.get_edit_count() == 640 and restored.get_last_sequence() == 639, "lazy ledger exposes durable count and sequence")
	for world_point in [Vector3(-319.9, 2.45, -257.9), Vector3(-0.1, 2.5, 0.1), Vector3(159.9, 2.6, 113.9), Vector3(320.1, 2.4, 257.8)]:
		var mapped: Dictionary = Spatial.world_to_region_local(world_point)
		var expected := _reference_density(13579, mapped["region_key"], mapped["local_position"], ledger.get_operations_snapshot())
		var actual: float = restored.sample_density(13579, mapped["region_key"], mapped["local_position"])
		_check(is_equal_approx(expected, actual), "streamed exact min/max replay matches reference at %s" % world_point)
	var region_key := Vector2i(0, 0)
	var filtered: Dictionary = restored.get_meshing_snapshot_for_chunk(region_key, Vector2i.ZERO)
	var chunk_origin := Spatial.region_origin_world(region_key) + Vector3.ZERO
	var chunk_min := Vector3(chunk_origin.x - Brush.MESHING_QUERY_MARGIN, -8.5, chunk_origin.z - Brush.MESHING_QUERY_MARGIN)
	var chunk_max := Vector3(chunk_origin.x + 4.0 + Brush.MESHING_QUERY_MARGIN, 8.5, chunk_origin.z + 4.0 + Brush.MESHING_QUERY_MARGIN)
	var full_operations: Array[Dictionary] = ledger.get_operations_snapshot()
	for operation in full_operations:
		var center: Vector3 = operation["center_world"]
		var nearest := Vector3(clampf(center.x, chunk_min.x, chunk_max.x), clampf(center.y, chunk_min.y, chunk_max.y), clampf(center.z, chunk_min.z, chunk_max.z))
		if nearest.distance_squared_to(center) <= Brush.MESHING_NOOP_DISTANCE * Brush.MESHING_NOOP_DISTANCE:
			_check((filtered["sequences"] as PackedInt32Array).has(int(operation["sequence"])), "spatial index retains every mathematically relevant SDF tail")
	var chunk_started := Time.get_ticks_usec()
	var mesh0: Dictionary = Mesher.build_chunk_cpu_data(13579, region_key, Vector2i.ZERO, false, filtered)
	var lod0_build_us := Time.get_ticks_usec() - chunk_started
	chunk_started = Time.get_ticks_usec()
	var mesh1: Dictionary = LodMesher.build_chunk_cpu_data(13579, region_key, Vector2i.ZERO, filtered)
	var lod1_build_us := Time.get_ticks_usec() - chunk_started
	_check(mesh0.get("valid", false) and mesh1.get("valid", false), "LOD0/LOD1 reconstruct from lazy chunk candidates")
	print("P3_1_STORAGE_BENCH distributed_count=640 generation_ms=%.3f save_ms=%.3f verify_load_ms=%.3f lod0_chunk_ms=%.3f lod1_chunk_ms=%.3f segments=%d candidate_count=%d" % [float(generation_us) / 1000.0, float(save_us) / 1000.0, float(load_us) / 1000.0, float(lod0_build_us) / 1000.0, float(lod1_build_us) / 1000.0, int(saved.get("segment_count", 0)), int(filtered.get("candidate_operation_count", 0))])


func _test_storage_reference_identity(loaded: Dictionary) -> void:
	var payload: Dictionary = loaded["payload"]
	var reference: Dictionary = payload["storage_reference"]
	for identity_field in ["world_seed", "generator_version"]:
		var forged_reference: Dictionary = reference.duplicate()
		var forged_metadata: Dictionary = (reference["metadata"] as Dictionary).duplicate(true)
		forged_metadata[identity_field] = int(forged_metadata[identity_field]) + 1
		forged_reference["metadata"] = forged_metadata
		var candidate: RefCounted = Brush.new(int(payload["world_seed"]), int(payload["generator_version"]))
		var snapshot := {
			"world_seed": int(payload["world_seed"]),
			"generator_version": int(payload["generator_version"]),
			"revision": int(payload["ledger_revision"]),
			"next_sequence": int(payload["next_sequence"]),
			"storage_reference": forged_reference,
		}
		_check(not candidate.restore_persistence_snapshot(snapshot), "lazy storage reference rejects mismatched %s" % identity_field)
		_check(candidate.get_edit_count() == 0 and candidate.revision == 0 and candidate.get_next_sequence() == 0, "rejected %s reference leaves the target ledger pristine" % identity_field)


func _test_dense_history_exact_order_and_reset() -> void:
	var ledger: RefCounted = Brush.new(2222, Field.GENERATOR_VERSION)
	var started := Time.get_ticks_usec()
	var memory_before_generation := OS.get_static_memory_usage()
	for index in range(2048):
		var mode := Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL
		var delta := float(index % 17) * 0.003
		_check(ledger.add_sphere(mode, Vector3(-0.1 + delta, 2.3 + delta, -0.1 - delta), 0.58), "dense alternating operation %d accepted" % index)
	var generate_us := Time.get_ticks_usec() - started
	var memory_after_generation := OS.get_static_memory_usage()
	_check(ledger.get_edit_count() == 2048 and ledger.get_last_sequence() == 2047, "2048 concentrated alternating operations are represented")
	var persistence_directory := _root.path_join("dense")
	var store := Store.new(persistence_directory, _root.path_join("none-dense"))
	var before_points := [Vector3(-0.1, 2.3, -0.1), Vector3(0.0, 2.4, 0.0), Vector3(0.6, 2.1, -0.4), Vector3(1.4, 3.0, 1.2)]
	var reference_operations: Array[Dictionary] = ledger.get_operations_snapshot()
	for point in before_points:
		var mapped: Dictionary = Spatial.world_to_region_local(point)
		var expected := _reference_density(2222, mapped["region_key"], mapped["local_position"], reference_operations)
		var actual: float = ledger.sample_density(2222, mapped["region_key"], mapped["local_position"])
		_check(is_equal_approx(expected, actual), "in-memory evaluator preserves ordered alternating min/max semantics expected=%s actual=%s" % [expected, actual])
	var save_started := Time.get_ticks_usec()
	var saved: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
	var save_usec := Time.get_ticks_usec() - save_started
	_check(saved.get("ok", false) and int(saved["segment_count"]) == 16, "dense history saves as sixteen immutable segments")
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = store.load_world()
	var load_usec := Time.get_ticks_usec() - load_started
	if not loaded.get("ok", false) or not loaded.get("found", false):
		_check(false, "dense scenario commits and reopens a valid generation: %s %s" % [loaded.get("reason", "missing"), JSON.stringify(loaded.get("diagnostics", []))])
		return
	var restored: RefCounted = _restore_loaded(store, loaded)
	_check(restored.get_edit_count() == 2048 and restored.revision == 2048, "dense history reload preserves count and revision")
	var replay_started := Time.get_ticks_usec()
	for point in before_points:
		var mapped: Dictionary = Spatial.world_to_region_local(point)
		var expected := _reference_density(2222, mapped["region_key"], mapped["local_position"], reference_operations)
		_check(is_equal_approx(expected, restored.sample_density(2222, mapped["region_key"], mapped["local_position"])), "lazy segment evaluator exactly matches full original operator replay")
	var replay_usec := Time.get_ticks_usec() - replay_started
	var restored_chunk_started := Time.get_ticks_usec()
	var restored_chunk_snapshot: Dictionary = restored.get_meshing_snapshot_for_chunk(Vector2i.ZERO, Vector2i.ZERO)
	var restored_lod0 := Mesher.build_chunk_cpu_data(2222, Vector2i.ZERO, Vector2i.ZERO, false, restored_chunk_snapshot)
	var restored_lod0_us := Time.get_ticks_usec() - restored_chunk_started
	var restored_lod1_started := Time.get_ticks_usec()
	var restored_lod1 := LodMesher.build_chunk_cpu_data(2222, Vector2i.ZERO, Vector2i.ZERO, restored_chunk_snapshot)
	var restored_lod1_us := Time.get_ticks_usec() - restored_lod1_started
	_check(restored_lod0.get("valid", false) and restored_lod1.get("valid", false), "dense lazy history reconstructs LOD0/LOD1 chunks without changing the field")
	var cleared: Dictionary = restored.clear_for_region(Vector2i.ZERO)
	_check(int(cleared.get("removed_count", 0)) == 2048 and restored.get_edit_count() == 0, "focused reset tombstones every support command without reusing sequences")
	_check(restored.revision == 2049 and restored.get_next_sequence() == 2048, "reset revision advances while global command sequence remains monotonic")
	var reset_saved: Dictionary = store.save_ledger(Store.WORLD_ID, restored)
	_check(reset_saved.get("ok", false) and int(reset_saved["operation_count"]) == 0, "empty post-reset active log commits as an exact new generation")
	var reset_loaded: Dictionary = store.load_world()
	var reset_ledger: RefCounted = _restore_loaded(store, reset_loaded)
	_check(reset_ledger.get_edit_count() == 0 and reset_ledger.revision == 2049 and reset_ledger.get_next_sequence() == 2048, "reset state survives restart without resurrecting removed edits")
	print("P3_1_STORAGE_BENCH concentrated_count=2048 generation_ms=%.3f process_static_delta_generation_bytes=%d save_ms=%.3f verify_load_ms=%.3f four_probe_replay_ms=%.3f lod0_chunk_ms=%.3f lod1_chunk_ms=%.3f candidates=%d segments=%d" % [float(generate_us) / 1000.0, maxi(0, memory_after_generation - memory_before_generation), float(save_usec) / 1000.0, float(load_usec) / 1000.0, float(replay_usec) / 1000.0, float(restored_lod0_us) / 1000.0, float(restored_lod1_us) / 1000.0, int(restored_chunk_snapshot.get("candidate_operation_count", 0)), int(saved.get("segment_count", 0))])


func _test_restart_streaming_lod_and_corruption() -> void:
	var directory := _root.path_join("restart")
	var store := Store.new(directory, _root.path_join("none-restart"))
	var ledger: RefCounted = Brush.new(13579, Field.GENERATOR_VERSION)
	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(-16.05, 2.6, -12.05), 1.1), "negative corner-crossing operation accepted")
	_check(ledger.add_sphere(Brush.Mode.FILL, Vector3(15.85, 2.5, 11.85), 0.7), "positive corner-crossing fill accepted")
	_check(store.save_ledger(Store.WORLD_ID, ledger).get("ok", false), "boundary history persists")
	var loaded: Dictionary = store.load_world()
	var restored: RefCounted = _restore_loaded(store, loaded)
	var original: Array[Dictionary] = ledger.get_operations_snapshot()
	for operation in original:
		for region_key in operation["rebuild_regions"]:
			var region_state := preload("res://scripts/terrain/terrain_world_state.gd").new(13579, region_key, restored)
			var point := Vector3(0.2, 2.5, 0.2)
			var expected := _reference_density(13579, region_key, point, original)
			_check(is_equal_approx(region_state.sample_density(point), expected), "unloaded negative/positive region replays the same global ordered edit state")
			var snapshot: Dictionary = restored.get_meshing_snapshot_for_chunk(region_key, Vector2i.ZERO)
			var mesh: Dictionary = LodMesher.build_chunk_cpu_data(13579, region_key, Vector2i.ZERO, snapshot)
			_check(mesh.get("valid", false) and int(mesh.get("ledger_revision", -1)) == restored.revision, "streamed region can reconstruct revision-matched LOD geometry")
	var manifests := _list_files(directory, "manifest-")
	_check(manifests.size() == 1, "one manifest generation exists before corruption injection")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(manifests[0])))
	var payload: Dictionary = JSON.parse_string(String(manifest["payload_json"]))
	var segment_name := String(payload["segments"][0]["file"])
	var segment_path := directory.path_join(segment_name)
	var original_bytes := FileAccess.get_file_as_bytes(segment_path)
	_check(_write_bytes(segment_path, "corrupted segment".to_utf8_buffer()), "segment corruption is injected into disposable fixture")
	_check(is_nan(restored.sample_density(13579, Vector2i(-1, -1), Vector3(15.9, 2.6, 11.9))), "runtime segment corruption fails closed instead of falling back to the base SDF")
	_check(not restored.get_meshing_snapshot_for_chunk(Vector2i(-1, -1), Vector2i.ZERO).get("valid", true), "runtime corruption prevents a valid chunk snapshot")
	var corrupt_result: Dictionary = store.load_world()
	_check(not corrupt_result.get("ok", false) and corrupt_result.get("reason", "") == "no_valid_v2_generation", "corrupt segment invalidates the complete generation; no partial replay")
	_check(_write_bytes(segment_path, original_bytes), "known-good segment bytes restored for cleanup")
	var index_path := directory.path_join(String(payload["index_file"]))
	var original_index := FileAccess.get_file_as_bytes(index_path)
	_check(_write_bytes(index_path, "corrupted index".to_utf8_buffer()), "spatial index corruption is injected into disposable fixture")
	_check(not store.load_world().get("ok", false), "corrupt spatial index invalidates the complete generation")
	_check(_write_bytes(index_path, original_index), "known-good index bytes restored")


func _test_interruption_legacy_isolation_and_quotas() -> void:
	var legacy_directory := _root.path_join("legacy-schema1")
	var legacy_store: RefCounted = LegacyStore.new(legacy_directory)
	var legacy_ledger: RefCounted = Brush.new(777, Field.GENERATOR_VERSION)
	_check(legacy_ledger.add_sphere(Brush.Mode.CARVE, Vector3(1.0, 2.0, 1.0), 0.6), "legacy preservation fixture has one edit")
	_check(legacy_store.save_ledger(LegacyStore.WORLD_ID, legacy_ledger).get("ok", false), "legacy schema-1 fixture is created explicitly")
	var legacy_paths := _list_files(legacy_directory, "save-")
	var legacy_path := legacy_directory.path_join(legacy_paths[0])
	var legacy_hash := _sha256(FileAccess.get_file_as_bytes(legacy_path))
	var new_directory := _root.path_join("new-v2")
	var store := Store.new(new_directory, legacy_directory)
	var clean: Dictionary = store.load_world()
	_check(clean.get("ok", false) and not clean.get("found", true) and clean.get("legacy_available", false), "clean-start v2 reports legacy save without importing it")
	var fresh: RefCounted = Brush.new(777, Field.GENERATOR_VERSION)
	_check(fresh.add_sphere(Brush.Mode.FILL, Vector3(-1.0, 2.0, -1.0), 0.6), "fresh v2 world accepts an independent command")
	_check(store.save_ledger(Store.WORLD_ID, fresh).get("ok", false), "fresh schema-2 world is saved in separate namespace")
	_check(_sha256(FileAccess.get_file_as_bytes(legacy_path)) == legacy_hash, "legacy save bytes remain unchanged by all v2 operations")
	var partial := FileAccess.open(new_directory.path_join("manifest-00000002.tmp"), FileAccess.WRITE)
	partial.store_string("partial interrupted manifest")
	partial.flush()
	partial.close()
	var recovery: Dictionary = store.load_world()
	_check(recovery.get("ok", false) and int(recovery.get("generation", -1)) == 1, "partial newer manifest is ignored and previous committed generation recovers")
	_check(int(recovery.get("ignored_invalid_candidates", 0)) == 1, "interrupted manifest is counted as invalid evidence")
	var valid_manifest_path := new_directory.path_join("manifest-00000001.json")
	var valid_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(valid_manifest_path))
	valid_manifest["generation"] = 2
	valid_manifest["schema_version"] = Store.SCHEMA_VERSION
	_check(_write_canonical(new_directory.path_join("manifest-00000002.tmp"), valid_manifest), "complete temporary manifest is staged to model interruption before commit rename")
	var complete_recovery: Dictionary = store.load_world()
	_check(complete_recovery.get("ok", false) and int(complete_recovery.get("generation", -1)) == 2 and complete_recovery.get("recovered_temporary", false), "complete temporary generation is promoted after restart")
	_check(FileAccess.file_exists(new_directory.path_join("manifest-00000002.json")), "recovered temporary is renamed to immutable manifest")
	var committed_directory := _root.path_join("committed-corruption")
	var committed_store := Store.new(committed_directory, _root.path_join("none-committed-corruption"))
	var committed_ledger: RefCounted = Brush.new(778, Field.GENERATOR_VERSION)
	_check(committed_ledger.add_sphere(Brush.Mode.CARVE, Vector3.ZERO, 0.6), "corruption rollback fixture starts with one command")
	_check(committed_store.save_ledger(Store.WORLD_ID, committed_ledger).get("ok", false), "first committed generation is written")
	_check(committed_ledger.add_sphere(Brush.Mode.FILL, Vector3(1.0, 0.0, 0.0), 0.6), "second command is added after first commit")
	_check(committed_store.save_ledger(Store.WORLD_ID, committed_ledger).get("ok", false), "newer committed generation is written")
	var newest_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(committed_directory.path_join("manifest-00000002.json")))
	var newest_payload: Dictionary = JSON.parse_string(String(newest_manifest["payload_json"]))
	var newest_segment_path := committed_directory.path_join(String(newest_payload["segments"][0]["file"]))
	var newest_segment_backup := FileAccess.get_file_as_bytes(newest_segment_path)
	_check(_write_bytes(newest_segment_path, "committed corruption".to_utf8_buffer()), "newest committed generation corruption is injected")
	var rollback_rejected: Dictionary = committed_store.load_world()
	_check(not rollback_rejected.get("ok", false) and rollback_rejected.get("reason", "") == "newest_committed_v2_generation_corrupt", "loader refuses silent rollback to older committed edits")
	_check(_write_bytes(newest_segment_path, newest_segment_backup), "committed corruption fixture is restored")
	_check(Brush.MAX_OPERATION_COUNT == 65536 and Brush.MAX_OPERATION_COUNT > 256, "explicit finite operation quota replaces the former 256 admission cap")
	_check(Store.MAX_TOTAL_BYTES == 268435456 and Store.MAX_SEGMENT_OPERATIONS == 128, "disk and segment bounds are explicit finite limits")
	_check(_directory_bytes(new_directory) <= Store.MAX_TOTAL_BYTES, "fixture storage remains within configured total disk quota")
	var disk_quota_store := Store.new(_root.path_join("disk-quota"), _root.path_join("no-disk-legacy"), {"max_total_bytes": 1024})
	_check(not disk_quota_store.save_ledger(Store.WORLD_ID, fresh).get("ok", false), "configurable disk quota rejects before committing the manifest")
	_check(_list_files(_root.path_join("disk-quota"), "manifest-").is_empty(), "quota rejection does not publish a committed manifest")
	var over_quota: RefCounted = Brush.new(888, Field.GENERATOR_VERSION)
	over_quota.add_sphere(Brush.Mode.CARVE, Vector3.ZERO, 0.6)
	over_quota.add_sphere(Brush.Mode.FILL, Vector3.ONE, 0.6)
	var operation_quota_store := Store.new(_root.path_join("operation-quota"), _root.path_join("no-operation-legacy"), {"max_operations": 1})
	_check(not operation_quota_store.save_ledger(Store.WORLD_ID, over_quota).get("ok", false), "configurable operation quota rejects over-capacity history")


func _restore_loaded(store: RefCounted, loaded: Dictionary) -> RefCounted:
	_check(loaded.get("ok", false) and loaded.get("found", false), "load result is valid before attaching lazy source")
	var payload: Dictionary = loaded.get("payload", {})
	var ledger: RefCounted = Brush.new(int(payload.get("world_seed", -1)), int(payload.get("generator_version", -1)))
	var snapshot := {
		"world_seed": int(payload.get("world_seed", -1)),
		"generator_version": int(payload.get("generator_version", -1)),
		"revision": int(payload.get("ledger_revision", -1)),
		"next_sequence": int(payload.get("next_sequence", -1)),
		"storage_reference": payload.get("storage_reference", {}),
	}
	_check(ledger.restore_persistence_snapshot(snapshot), "validated v2 source attaches without materializing all operations: %s" % ledger.last_restore_rejection_reason)
	return ledger


func _reference_density(seed: int, region: Vector2i, local: Vector3, operations: Array[Dictionary]) -> float:
	var density: float = Field.sample_density(seed, region, local)
	var world := Spatial.region_local_to_world(region, local)
	for operation in operations:
		var distance := world.distance_to(operation["center_world"]) - float(operation["radius"])
		if int(operation["mode"]) == Brush.Mode.CARVE:
			density = minf(density, distance)
		else:
			density = maxf(density, -distance)
	return density


func _list_files(directory_path: String, prefix: String) -> Array[String]:
	var files: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return files
	directory.list_dir_begin()
	while true:
		var filename := directory.get_next()
		if filename.is_empty():
			break
		if not directory.current_is_dir() and filename.begins_with(prefix):
			files.append(filename)
	directory.list_dir_end()
	return files


func _directory_bytes(path: String) -> int:
	var total := 0
	for filename in _list_files(path, ""):
		total += FileAccess.get_file_as_bytes(path.path_join(filename)).size()
	return total


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var success := file.get_error() == OK
	file.close()
	return success and FileAccess.get_file_as_bytes(path) == bytes


func _write_canonical(path: String, value: Dictionary) -> bool:
	return _write_bytes(path, JSON.stringify(value, "", true, true).to_utf8_buffer())


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("ASSERTION FAILED: " + label)
