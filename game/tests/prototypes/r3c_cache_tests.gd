extends SceneTree

const Cache := preload("res://tests/prototypes/r3c_profile_cache.gd")
const CACHE_FORMAT := 1
const CACHE_MAGIC := "P31R3B-MESH-CACHE-1"

var _failures: Array[String] = []
var _assertions := 0
var _root := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var temp := OS.get_environment("TEMP")
	if temp.is_empty():
		temp = OS.get_environment("TMP")
	_root = temp.path_join("p31-r3c-cache-tests-" + Crypto.new().generate_random_bytes(16).hex_encode())
	_expect(DirAccess.make_dir_recursive_absolute(_root) == OK, "unique_disposable_root_created")
	_test_memory_and_disk_hits()
	_test_corrupt_truncated_and_incompatible()
	_test_orphan_temp_and_lock_timeout()
	_test_concurrent_same_key_writers()
	_remove_tree(_root)
	if _failures.is_empty():
		print("R3C_CACHE_TESTS_PASS assertions=%d" % _assertions)
		quit(0)
	else:
		push_error("R3C_CACHE_TESTS_FAIL assertions=%d failures=%s" % [_assertions, ";".join(_failures)])
		quit(1)

func _test_memory_and_disk_hits() -> void:
	var root := _root.path_join("hits")
	var cache: RefCounted = Cache.new(root)
	var identity := {"case": "memory-disk", "revision": 1}
	var cold: Dictionary = cache.get_or_build(identity, Callable(self, "_mesh"))
	_expect(bool(cold.get("valid", false)) and not bool(cold.get("cache_hit", true)), "cold_build_publishes")
	var memory: Dictionary = cache.get_or_build(identity, Callable(self, "_invalid_builder"))
	_expect(bool(memory.get("cache_hit", false)) and String(memory.get("cache_layer", "")) == "memory", "memory_hit_skips_builder")
	var disk_cache: RefCounted = Cache.new(root)
	var disk: Dictionary = disk_cache.get_or_build(identity, Callable(self, "_invalid_builder"))
	_expect(bool(disk.get("cache_hit", false)) and String(disk.get("cache_layer", "")) == "disk", "fresh_instance_disk_hit")
	_expect(_mesh_equal(cold, disk), "disk_mesh_equals_canonical_builder")

func _test_corrupt_truncated_and_incompatible() -> void:
	for kind in ["corrupt", "truncated", "incompatible"]:
		var root := _root.path_join(kind)
		DirAccess.make_dir_recursive_absolute(root)
		var identity := {"case": kind, "chunk": Vector2i(-1, 2)}
		var key := _hash(var_to_bytes(identity))
		var path := root.path_join(key + ".bin")
		if kind == "incompatible":
			_write_envelope(path, identity, key, true)
		else:
			var bad := FileAccess.open(path, FileAccess.WRITE)
			bad.store_buffer(PackedByteArray([0x50, 0x33, 0x31, 0x00]) if kind == "truncated" else PackedByteArray([0x01, 0x02, 0x03, 0x04, 0x05]))
			bad.close()
		var cache: RefCounted = Cache.new(root)
		var result: Dictionary = cache.get_or_build(identity, Callable(self, "_mesh"))
		_expect(bool(result.get("valid", false)) and not bool(result.get("cache_hit", true)), "%s_falls_back_to_canonical" % kind)
		_expect(_mesh_equal(result, _mesh()), "%s_fallback_mesh_exact" % kind)
		_expect(int(cache.stats().corrupt_entries) == 1, "%s_corruption_counted" % kind)
		var disk_check: RefCounted = Cache.new(root)
		var recovered: Dictionary = disk_check.get_or_build(identity, Callable(self, "_invalid_builder"))
		_expect(bool(recovered.get("cache_hit", false)) and String(recovered.get("cache_layer", "")) == "disk", "%s_repaired_entry_readable" % kind)

func _test_orphan_temp_and_lock_timeout() -> void:
	var root := _root.path_join("temp-lock")
	DirAccess.make_dir_recursive_absolute(root)
	var identity := {"case": "orphan-temp"}
	var key := _hash(var_to_bytes(identity))
	var orphan := FileAccess.open(root.path_join(key + ".bin.tmp-interrupted"), FileAccess.WRITE)
	orphan.store_string("incomplete")
	orphan.close()
	var cache: RefCounted = Cache.new(root)
	_expect(FileAccess.file_exists(root.path_join(key + ".bin.tmp-interrupted")), "startup_does_not_delete_another_writer_temp")
	var result: Dictionary = cache.get_or_build(identity, Callable(self, "_mesh"))
	_expect(bool(result.get("valid", false)), "orphan_temp_does_not_block_canonical_result")
	_expect(not FileAccess.file_exists(root.path_join(key + ".bin.tmp-interrupted")), "orphan_temp_cleaned_under_write_lock")
	var lock_path := root.path_join(".r3c-write-lock")
	_expect(DirAccess.make_dir_absolute(lock_path) == OK, "lock_fixture_created")
	var blocked: RefCounted = Cache.new(root)
	var blocked_result: Dictionary = blocked.get_or_build({"case": "locked"}, Callable(self, "_mesh"))
	_expect(bool(blocked_result.get("valid", false)) and String(blocked_result.get("cache_layer", "")) == "canonical_uncached", "lock_timeout_returns_canonical_without_publish")
	_expect(String(blocked_result.get("cache_store_error", "")) == "cache_write_lock_timeout", "lock_timeout_reported")
	DirAccess.remove_absolute(lock_path)
	var bypass: RefCounted = Cache.new(_root.path_join("adaptive-bypass"))
	var bypass_result: Dictionary = bypass.get_or_build({"case": "no-revisit"}, Callable(self, "_mesh"), 0)
	_expect(bool(bypass_result.get("valid", false)) and String(bypass_result.get("cache_layer", "")) == "bypassed_no_expected_revisit", "zero_reuse_policy_returns_canonical_geometry")
	_expect(int(bypass.stats().adaptive_bypass_count) == 1 and int(bypass.stats().disk_bytes) == 0, "zero_reuse_policy_has_no_cache_write")
	var invalid_reuse: Dictionary = bypass.get_or_build({"case": "negative-reuse"}, Callable(self, "_mesh"), -1)
	_expect(not bool(invalid_reuse.get("valid", true)) and String(invalid_reuse.get("reason", "")) == "adaptive_reuse_count_invalid", "negative_reuse_count_rejected")

func _test_concurrent_same_key_writers() -> void:
	var root := _root.path_join("concurrent")
	var project_root := ProjectSettings.globalize_path("res://")
	var barrier := root.path_join("release")
	DirAccess.make_dir_recursive_absolute(root)
	var executable := OS.get_executable_path()
	var children: Array[Dictionary] = []
	for index in range(2):
		var ready := root.path_join("ready-%d" % index)
		var output := root.path_join("result-%d.json" % index)
		var args := ["--headless", "--path", project_root, "--script", "res://tests/prototypes/r3c_cache_writer.gd", "--", root, barrier, ready, output]
		var pid := OS.create_process(executable, args, false)
		_expect(pid > 0, "concurrent_writer_%d_started" % index)
		children.append({"pid": pid, "ready": ready, "output": output})
	var ready_started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - ready_started < 20000:
		if FileAccess.file_exists(String(children[0].ready)) and FileAccess.file_exists(String(children[1].ready)):
			break
		OS.delay_msec(10)
	_expect(FileAccess.file_exists(String(children[0].ready)) and FileAccess.file_exists(String(children[1].ready)), "both_concurrent_writers_reached_barrier")
	var release := FileAccess.open(barrier, FileAccess.WRITE)
	release.store_string("go")
	release.close()
	var process_started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - process_started < 30000:
		var running := false
		for child in children:
			if OS.is_process_running(int(child.pid)):
				running = true
		if not running:
			break
		OS.delay_msec(20)
	var all_outputs := true
	for child in children:
		all_outputs = all_outputs and FileAccess.file_exists(String(child.output)) and not OS.is_process_running(int(child.pid))
	_expect(all_outputs, "both_concurrent_writers_exit_and_capture_result")
	var layers: Array[String] = []
	for child in children:
		if not FileAccess.file_exists(String(child.output)):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(child.output)))
		_expect(typeof(parsed) == TYPE_DICTIONARY and bool(parsed.get("valid", false)), "concurrent_writer_result_valid")
		_expect(String(parsed.get("positions_sha256", "")) == _hash(var_to_bytes(_mesh().positions)), "concurrent_writer_mesh_exact")
		layers.append(String(parsed.get("cache_layer", "")))
	_expect(layers.has("rebuilt"), "one_writer_atomically_publishes")
	_expect(layers.has("disk_concurrent_publish"), "losing_writer_uses_verified_winner")
	var bin_count := 0
	var dir := DirAccess.open(root)
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".bin"):
			bin_count += 1
		name = dir.get_next()
	dir.list_dir_end()
	_expect(bin_count == 1, "exactly_one_complete_final_entry")

func _write_envelope(path: String, identity: Dictionary, key: String, incompatible: bool) -> void:
	var mesh := _mesh()
	mesh.erase("valid")
	var payload := var_to_bytes(mesh)
	var body := var_to_bytes({"magic": CACHE_MAGIC, "format": CACHE_FORMAT + 1 if incompatible else CACHE_FORMAT,
		"identity_sha256": key, "identity": identity, "payload_sha256": _hash(payload), "payload": payload})
	var bytes := _hash(body).hex_decode()
	bytes.append_array(body)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func _mesh() -> Dictionary:
	var positions := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var normals := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	return {"valid": true, "positions": positions, "normals": normals, "vertex_count": 3, "triangle_count": 1, "sample_count": 3}

func _invalid_builder() -> Dictionary:
	return {"valid": false, "reason": "should_not_run"}

func _mesh_equal(left: Dictionary, right: Dictionary) -> bool:
	return left.get("positions", PackedVector3Array()) == right.get("positions", PackedVector3Array()) \
		and left.get("normals", PackedVector3Array()) == right.get("normals", PackedVector3Array())

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _expect(condition: bool, name: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(name)

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if dir.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
