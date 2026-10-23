extends SceneTree

const Store := preload("res://scripts/terrain/terrain_world_save_store.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

var assertions := 0
var failures := 0
var _root := ""


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("user://p1_2_persistence_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_root)
	_test_ordered_roundtrip_and_derived_meshes()
	_test_atomic_generation_recovery()
	_test_corrupt_incompatible_and_semantic_rejection()
	_test_capacity_and_ledger_restore_atomicity()
	_test_process_restart_roundtrip()
	_remove_tree(_root)
	if failures == 0:
		print("TERRAIN_WORLD_PERSISTENCE_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("TERRAIN_WORLD_PERSISTENCE_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_ordered_roundtrip_and_derived_meshes() -> void:
	var directory := _root.path_join("ordered")
	var store := Store.new(directory)
	var ledger: RefCounted = Brush.new(13579, Field.GENERATOR_VERSION)
	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(-32.05, 2.7, -24.05), 0.8), "negative remote carve is accepted")
	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(-0.15, 2.4, -0.15), 0.85), "negative-origin boundary carve is accepted")
	_check(ledger.add_sphere(Brush.Mode.FILL, Vector3(15.85, 2.5, 11.85), 0.7), "positive region-corner fill is accepted")
	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(88.0, 4.0, 41.0), 0.65), "remote carve is accepted")
	var clear_result: Dictionary = ledger.clear_for_region(Vector2i(-2, -2))
	_check(clear_result.get("removed_count", 0) == 1, "focused reset removes only the command touching its support region")
	var before: Dictionary = ledger.get_persistence_snapshot()
	_check(before["revision"] == 5 and before["next_sequence"] == 4, "snapshot preserves revision and next sequence across a removed command")
	_check((before["operations"] as Array).size() == 3 and before["operations"][0]["sequence"] == 1, "snapshot preserves ordered sequence gaps")
	_check(ledger.get_next_sequence() == 4, "next sequence survives reset gaps without reuse")
	var save_result: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
	_check(save_result.get("ok", false), "first world generation saves and verifies (%s)" % save_result.get("reason", "ok"))
	if not save_result.get("ok", false):
		return
	var loaded: Dictionary = store.load_world()
	_check(loaded.get("ok", false) and loaded.get("found", false), "saved world loads through the schema/hash validator")
	var restored: RefCounted = Brush.new(int(before["world_seed"]), int(before["generator_version"]))
	_check(restored.restore_persistence_snapshot(_ledger_snapshot(loaded["payload"])), "ordered commands restore atomically into a pristine ledger")
	_check(restored.get_persistence_snapshot() == before, "restart reconstruction preserves seed, version, sequence, revision and commands")
	for point in [Vector3(-0.2, 2.4, -0.2), Vector3(0.1, 2.5, 0.1), Vector3(15.9, 2.5, 11.9), Vector3(16.1, 2.5, 12.1), Vector3(88.0, 4.0, 41.0)]:
		var mapped: Dictionary = Spatial.world_to_region_local(point)
		var left: float = ledger.sample_density(int(before["world_seed"]), mapped["region_key"], mapped["local_position"])
		var right: float = restored.sample_density(int(before["world_seed"]), mapped["region_key"], mapped["local_position"])
		_check(is_equal_approx(left, right), "restored canonical replay matches original density at %s" % point)
	var lod0: Dictionary = Mesher.build_chunk_cpu_data(13579, Vector2i.ZERO, Vector2i.ZERO, false, restored.get_meshing_snapshot_for_chunk(Vector2i.ZERO, Vector2i.ZERO))
	var lod1: Dictionary = LodMesher.build_chunk_cpu_data(13579, Vector2i.ZERO, Vector2i.ZERO, restored.get_meshing_snapshot_for_chunk(Vector2i.ZERO, Vector2i.ZERO))
	_check(lod0.get("valid", false) and lod1.get("valid", false), "LOD0 and LOD1 meshes rebuild from restored derived-state inputs")
	_check(int(lod1.get("ledger_revision", -1)) == restored.revision, "LOD1 mesh result carries the restored ledger revision")
	_check(int(restored.get_meshing_snapshot_for_chunk(Vector2i.ZERO, Vector2i.ZERO)["revision"]) == restored.revision, "LOD0 mesh input is an immutable snapshot at the restored ledger revision")
	var boundary_ledger: RefCounted = Brush.new(86420, Field.GENERATOR_VERSION)
	_check(boundary_ledger.add_sphere(Brush.Mode.CARVE, Vector3(-16.05, 2.6, -12.05), 1.1), "cross-region negative-coordinate command is accepted before save")
	var boundary_saved: Dictionary = store.save_ledger(Store.WORLD_ID, boundary_ledger)
	_check(boundary_saved.get("ok", false), "edited world can be saved after a boundary command")
	var boundary_loaded: Dictionary = store.load_world()
	var boundary_restored: RefCounted = Brush.new(86420, Field.GENERATOR_VERSION)
	_check(boundary_loaded.get("ok", false) and boundary_restored.restore_persistence_snapshot(_ledger_snapshot(boundary_loaded["payload"])), "cross-region history restores after simulated unload/reload")
	var restored_operations: Array[Dictionary] = boundary_restored.get_operations_snapshot()
	var operation: Dictionary = restored_operations[0]
	_check(operation["support_regions"].has(Vector2i(-2, -1)) and operation["support_regions"].has(Vector2i(-1, -2)), "restored edit retains all negative cross-region support owners")
	for region_key in operation["rebuild_regions"]:
		var chunk_coordinate := Vector2i.ZERO
		var snapshot: Dictionary = boundary_restored.get_meshing_snapshot_for_chunk(region_key, chunk_coordinate)
		var region_state: RefCounted = preload("res://scripts/terrain/terrain_world_state.gd").new(86420, region_key, boundary_restored)
		var rebuilt: Dictionary = LodMesher.build_chunk_cpu_data(86420, region_key, chunk_coordinate, snapshot)
		_check(rebuilt.get("valid", false) and int(rebuilt.get("ledger_revision", -1)) == boundary_restored.revision, "unloaded region %s can rebuild a revision-matched LOD chunk" % region_key)
		_check(region_state.sample_density(Vector3(0.1, 2.6, 0.1)) == boundary_restored.sample_density(86420, region_key, Vector3(0.1, 2.6, 0.1)), "reloaded region %s reads the restored ordered ledger" % region_key)


func _test_atomic_generation_recovery() -> void:
	var directory := _root.path_join("recovery")
	var store := Store.new(directory)
	var ledger: RefCounted = Brush.new(2222, Field.GENERATOR_VERSION)
	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(-4.0, 2.0, -3.0), 0.6), "recovery baseline command is accepted")
	var first: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
	_check(first.get("ok", false) and first.get("generation", 0) == 1, "first immutable generation commits as generation one (%s)" % first.get("reason", "ok"))
	if not first.get("ok", false):
		return
	_check(ledger.add_sphere(Brush.Mode.FILL, Vector3(20.0, 2.5, 15.0), 0.7), "newer recovery command is accepted")
	var second: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
	_check(second.get("ok", false) and second.get("generation", 0) == 2, "second generation commits without replacing generation one in place")
	var incomplete := FileAccess.open(directory.path_join("save-00000003.tmp"), FileAccess.WRITE)
	incomplete.store_string("partial interrupted write")
	incomplete.flush()
	incomplete.close()
	var fallback: Dictionary = store.load_world()
	_check(fallback.get("ok", false) and int(fallback.get("generation", 0)) == 2, "incomplete newer temporary falls back to the latest verified generation")
	_check(int(fallback.get("ignored_invalid_candidates", 0)) == 1, "incomplete temporary is explicitly classified as invalid")
	var committed_path := directory.path_join("save-00000002.json")
	var temporary_path := directory.path_join("save-00000002.tmp")
	_check(DirAccess.rename_absolute(committed_path, temporary_path) == OK, "fixture models process interruption after flush and before rename")
	var recovered: Dictionary = store.load_world()
	_check(recovered.get("ok", false) and int(recovered.get("generation", 0)) == 2 and recovered.get("recovered_temporary", false), "complete interrupted generation is recovered after restart")
	_check(FileAccess.file_exists(committed_path), "recovered temporary is promoted to its immutable final generation")


func _test_corrupt_incompatible_and_semantic_rejection() -> void:
	var directory := _root.path_join("invalid")
	var store := Store.new(directory)
	var ledger: RefCounted = Brush.new(3456, Field.GENERATOR_VERSION)
	_check(ledger.add_sphere(Brush.Mode.CARVE, Vector3(2.0, 2.0, 2.0), 0.6), "invalid-save fixture command is accepted")
	var saved: Dictionary = store.save_ledger(Store.WORLD_ID, ledger)
	_check(saved.get("ok", false), "invalid-save fixture has a known-good physical baseline (%s)" % saved.get("reason", "ok"))
	if not saved.get("ok", false):
		return
	var save_path := directory.path_join("save-00000001.json")
	var original_bytes := FileAccess.get_file_as_bytes(save_path)
	var parsed: Dictionary = JSON.parse_string(original_bytes.get_string_from_utf8())
	var payload: Dictionary = JSON.parse_string(String(parsed["payload_json"]))
	var operations: Array = payload["operations"]
	operations[0]["mode"] = 2
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	parsed["payload_json"] = JSON.stringify(payload, "", true, true)
	hash_context.update(String(parsed["payload_json"]).to_utf8_buffer())
	parsed["payload_sha256"] = hash_context.finish().hex_encode()
	_check(_write_canonical(save_path, parsed), "invalid semantic payload is rewritten with a matching checksum for the oracle test")
	var semantic_rejection: Dictionary = store.load_world()
	_check(not semantic_rejection.get("ok", false) and semantic_rejection.get("reason", "") == "no_valid_save_generation", "mode byte 2 is rejected after integrity verification, not treated as FILL")
	var bad_bytes_path := directory.path_join("save-00000002.json")
	_check(_write_bytes(bad_bytes_path, "{broken".to_utf8_buffer()), "corrupt JSON fixture is written")
	var corrupt_result: Dictionary = store.load_world()
	_check(not corrupt_result.get("ok", false) and int(corrupt_result.get("invalid_candidates", 0)) == 2, "corrupt JSON and semantically invalid save are rejected without partial restore")
	var incompatible_directory := _root.path_join("incompatible")
	var incompatible_store := Store.new(incompatible_directory)
	var valid_again: Dictionary = incompatible_store.save_ledger(Store.WORLD_ID, ledger)
	_check(valid_again.get("ok", false), "incompatible-schema fixture starts from valid bytes")
	var incompatible_path := incompatible_directory.path_join("save-00000001.json")
	var incompatible_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(incompatible_path))
	incompatible_doc["schema_version"] = 99
	_check(_write_canonical(incompatible_path, incompatible_doc), "unsupported schema fixture remains canonical JSON")
	var incompatible_result: Dictionary = incompatible_store.load_world()
	_check(not incompatible_result.get("ok", false) and incompatible_result.get("reason", "") == "no_valid_save_generation", "incompatible schema is rejected with no live state change")
	var target: RefCounted = Brush.new(3456, Field.GENERATOR_VERSION)
	var incompatible_snapshot := {
		"world_seed": 3457,
		"generator_version": Field.GENERATOR_VERSION,
		"revision": 1,
		"next_sequence": 1,
		"operations": [],
	}
	_check(not target.restore_persistence_snapshot(incompatible_snapshot), "incompatible world identity cannot be applied to a candidate ledger")
	_check(target.get_edit_count() == 0 and target.revision == 0, "rejected restore keeps all candidate ledger fields untouched")
	var digest_directory := _root.path_join("digest")
	var digest_store := Store.new(digest_directory)
	_check(digest_store.save_ledger(Store.WORLD_ID, ledger).get("ok", false), "digest rejection fixture starts from a verified save")
	var digest_path := digest_directory.path_join("save-00000001.json")
	var digest_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(digest_path))
	digest_document["payload_sha256"] = "0".repeat(64)
	_check(_write_canonical(digest_path, digest_document), "incorrect payload digest fixture remains syntactically canonical")
	_check(not digest_store.load_world().get("ok", false), "incorrect payload digest is rejected")
	digest_document.erase("payload_sha256")
	_check(_write_canonical(digest_path, digest_document), "missing digest fixture remains syntactically canonical")
	_check(not digest_store.load_world().get("ok", false), "absent payload digest is rejected")


func _test_capacity_and_ledger_restore_atomicity() -> void:
	var ledger: RefCounted = Brush.new(9988, Field.GENERATOR_VERSION)
	for index in range(Brush.MAX_EDITS):
		var center := Vector3(float(index) * 8.0, 3.0, -7.0)
		_check(ledger.add_sphere(Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL, center, 0.45), "capacity operation %d is accepted" % index)
	_check(ledger.get_edit_count() == Brush.MAX_EDITS and ledger.get_last_sequence() == 255, "all 256 accepted edits remain addressable")
	_check(not ledger.add_sphere(Brush.Mode.CARVE, Vector3(9000.0, 3.0, 0.0), 0.45), "257th edit is rejected by the existing explicit cap")
	var invalid_restore: RefCounted = Brush.new(9988, Field.GENERATOR_VERSION)
	var snapshot: Dictionary = ledger.get_persistence_snapshot()
	var malformed_operations: Array = snapshot["operations"].duplicate(true)
	malformed_operations[12]["mode"] = 2
	snapshot["operations"] = malformed_operations
	_check(not invalid_restore.restore_persistence_snapshot(snapshot), "malformed ledger restore fails closed")
	_check(invalid_restore.get_edit_count() == 0 and invalid_restore.revision == 0, "failed ledger restoration does not partially apply commands")
	var restored: RefCounted = Brush.new(9988, Field.GENERATOR_VERSION)
	_check(restored.restore_persistence_snapshot(ledger.get_persistence_snapshot()), "full-capacity canonical history restores")
	_check(restored.get_edit_count() == 256 and restored.get_last_sequence() == 255, "capacity restore retains every ordered command")


func _test_process_restart_roundtrip() -> void:
	var directory := _root.path_join("process_restart")
	var write_result := _run_probe("write", directory)
	_check(write_result["exit_code"] == 0 and String(write_result["output"]).contains("PERSISTENCE_PROBE_WRITE_PASS"), "first child process saves its world and exits cleanly")
	var read_result := _run_probe("read", directory)
	_check(read_result["exit_code"] == 0 and String(read_result["output"]).contains("PERSISTENCE_PROBE_READ_PASS"), "second child process reconstructs the world after process restart")


func _run_probe(phase: String, directory: String) -> Dictionary:
	var output: Array = []
	var project_path := ProjectSettings.globalize_path("res://")
	var arguments: PackedStringArray = [
		"--headless", "--path", project_path, "--script", "res://tests/terrain_world_persistence_process_probe.gd",
		"--", phase, directory,
	]
	var exit_code := OS.execute(OS.get_executable_path(), arguments, output, true, false)
	return {"exit_code": exit_code, "output": "\n".join(output)}


func _ledger_snapshot(payload: Dictionary) -> Dictionary:
	return {
		"world_seed": int(payload["world_seed"]),
		"generator_version": int(payload["generator_version"]),
		"revision": int(payload["ledger_revision"]),
		"next_sequence": int(payload["next_sequence"]),
		"operations": payload["operations"],
	}


func _write_canonical(path: String, value: Dictionary) -> bool:
	return _write_bytes(path, JSON.stringify(value, "", true, true).to_utf8_buffer())


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var success := file.get_error() == OK
	file.close()
	return success


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
