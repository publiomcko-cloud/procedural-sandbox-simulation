extends RefCounted

## Disposable bounded cache of derived CPU mesh arrays. It never stores world
## authority. Cache keys are built by the caller from the exact filtered chunk
## snapshot and dependency versions; ledger revision is intentionally absent.
const FORMAT := 1
const MAX_DISK_BYTES := 64 * 1024 * 1024
const MAX_DISK_ENTRIES := 128
const MAX_MEMORY_BYTES := 16 * 1024 * 1024
const MAX_MEMORY_ENTRIES := 32
const MAGIC := "P31R3B-MESH-CACHE-1"

var _root: String
var _memory := {}
var _memory_sizes := {}
var _memory_order: Array[String] = []
var _memory_bytes := 0
var hit_count := 0
var miss_count := 0
var corrupt_count := 0
var disk_bytes := 0
var peak_memory_bytes := 0
var last_builder_usec := 0
var last_timings_usec: Dictionary = {}


func _init(root_path: String) -> void:
	var started := Time.get_ticks_usec()
	_root = root_path
	DirAccess.make_dir_recursive_absolute(_root)
	_remove_orphan_temps()
	disk_bytes = _scan_disk_bytes()
	last_timings_usec = {"cache_init_scan": Time.get_ticks_usec() - started}


func get_or_build(identity: Dictionary, builder: Callable) -> Dictionary:
	var total_started := Time.get_ticks_usec()
	last_timings_usec = {}
	last_builder_usec = 0
	var started := Time.get_ticks_usec()
	var identity_bytes := var_to_bytes(identity)
	last_timings_usec["identity_encode"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var key := _sha256(identity_bytes)
	last_timings_usec["identity_hash"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	if _memory.has(key):
		hit_count += 1
		_memory_order.erase(key)
		_memory_order.append(key)
		last_timings_usec["memory_lookup_copy"] = Time.get_ticks_usec() - started
		last_timings_usec["total"] = Time.get_ticks_usec() - total_started
		return (_memory[key] as Dictionary).duplicate(true).merged({"valid": true, "cache_hit": true, "cache_layer": "memory"}, true)
	var path := _root.path_join(key + ".bin")
	last_timings_usec["memory_lookup_copy"] = Time.get_ticks_usec() - started
	if FileAccess.file_exists(path):
		started = Time.get_ticks_usec()
		var loaded := _read_entry(path, identity, key)
		last_timings_usec["disk_read_validate"] = Time.get_ticks_usec() - started
		if bool(loaded.get("valid", false)):
			hit_count += 1
			_remember(key, loaded)
			loaded["cache_hit"] = true
			loaded["cache_layer"] = "disk"
			last_timings_usec["total"] = Time.get_ticks_usec() - total_started
			return loaded
		corrupt_count += 1
		DirAccess.remove_absolute(path)
		disk_bytes = _scan_disk_bytes()
	miss_count += 1
	var builder_started_usec := Time.get_ticks_usec()
	var build_value: Variant = builder.call()
	last_builder_usec = Time.get_ticks_usec() - builder_started_usec
	last_timings_usec["builder"] = last_builder_usec
	if typeof(build_value) != TYPE_DICTIONARY or not bool(build_value.get("valid", false)) or not _valid_mesh(build_value):
		return {"valid": false, "reason": "canonical_mesh_build_invalid", "cache_hit": false}
	var mesh := {
		"positions": build_value.get("positions", PackedVector3Array()),
		"normals": build_value.get("normals", PackedVector3Array()),
		"vertex_count": int(build_value.get("vertex_count", 0)),
		"triangle_count": int(build_value.get("triangle_count", 0)),
		"sample_count": int(build_value.get("sample_count", 0)),
	}
	started = Time.get_ticks_usec()
	var payload := var_to_bytes(mesh)
	last_timings_usec["mesh_encode"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var envelope_payload := var_to_bytes({"magic": MAGIC, "format": FORMAT, "identity_sha256": key,
		"identity": identity, "payload_sha256": _sha256(payload), "payload": payload})
	var envelope := _sha256(envelope_payload).hex_decode()
	envelope.append_array(envelope_payload)
	last_timings_usec["envelope_encode_hash"] = Time.get_ticks_usec() - started
	if envelope.size() > MAX_DISK_BYTES:
		return _uncached_result(mesh, "cache_entry_exceeds_disk_quota")
	started = Time.get_ticks_usec()
	if not _make_disk_room(envelope.size()):
		last_timings_usec["quota"] = Time.get_ticks_usec() - started
		return _uncached_result(mesh, "cache_disk_quota_unavailable")
	last_timings_usec["quota"] = Time.get_ticks_usec() - started
	var temp := path + ".tmp-%d-%d" % [Time.get_ticks_usec(), randi()]
	if FileAccess.file_exists(temp):
		return _uncached_result(mesh, "cache_temp_collision")
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _uncached_result(mesh, "cache_temp_open_failed")
	started = Time.get_ticks_usec()
	file.store_buffer(envelope)
	file.flush()
	var write_error := file.get_error()
	file.close()
	last_timings_usec["disk_write_flush"] = Time.get_ticks_usec() - started
	if write_error != OK:
		DirAccess.remove_absolute(temp)
		return _uncached_result(mesh, "cache_temp_write_failed")
	# The entry path is unique to its content key. A failed rename leaves the
	# canonical build available to the caller but never claims a cache hit.
	started = Time.get_ticks_usec()
	var publish_error := DirAccess.rename_absolute(temp, path)
	last_timings_usec["atomic_publish"] = Time.get_ticks_usec() - started
	if publish_error != OK:
		DirAccess.remove_absolute(temp)
		return _uncached_result(mesh, "cache_atomic_publish_failed")
	started = Time.get_ticks_usec()
	disk_bytes = _scan_disk_bytes()
	last_timings_usec["post_publish_full_scan"] = Time.get_ticks_usec() - started
	_remember(key, mesh)
	last_timings_usec["total"] = Time.get_ticks_usec() - total_started
	var result := mesh.duplicate(true)
	result["valid"] = true
	result["cache_hit"] = false
	result["cache_layer"] = "rebuilt"
	result["cache_key"] = key
	return result


func stats() -> Dictionary:
	return {"hits": hit_count, "misses": miss_count, "corrupt_entries": corrupt_count,
		"disk_bytes": disk_bytes, "memory_bytes": _memory_bytes, "memory_entries": _memory.size(),
		"peak_memory_bytes": peak_memory_bytes, "last_builder_usec": last_builder_usec}


func _read_entry(path: String, identity: Dictionary, key: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"valid": false, "reason": "cache_entry_open_failed"}
	var entry_length := file.get_length()
	if entry_length <= 32 or entry_length > MAX_DISK_BYTES:
		file.close()
		return {"valid": false, "reason": "cache_entry_length_out_of_bounds"}
	var bytes: PackedByteArray = file.get_buffer(entry_length)
	file.close()
	last_timings_usec["disk_read_bytes"] = Time.get_ticks_usec() - started
	if bytes.size() != entry_length:
		return {"valid": false, "reason": "cache_entry_empty_or_truncated"}
	var envelope_payload := bytes.slice(32)
	started = Time.get_ticks_usec()
	if bytes.slice(0, 32) != _sha256(envelope_payload).hex_decode():
		return {"valid": false, "reason": "cache_envelope_hash_invalid"}
	last_timings_usec["envelope_verify_hash"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var decoded: Variant = bytes_to_var(envelope_payload)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "cache_envelope_invalid"}
	if decoded.get("magic", "") != MAGIC or int(decoded.get("format", -1)) != FORMAT \
		or String(decoded.get("identity_sha256", "")) != key or decoded.get("identity", {}) != identity:
		return {"valid": false, "reason": "cache_identity_invalid"}
	var payload: Variant = decoded.get("payload", PackedByteArray())
	if typeof(payload) != TYPE_PACKED_BYTE_ARRAY or _sha256(payload) != String(decoded.get("payload_sha256", "")):
		return {"valid": false, "reason": "cache_payload_hash_invalid"}
	started = Time.get_ticks_usec()
	var mesh: Variant = bytes_to_var(payload)
	last_timings_usec["mesh_decode"] = Time.get_ticks_usec() - started
	if typeof(mesh) != TYPE_DICTIONARY or not _valid_mesh(mesh):
		return {"valid": false, "reason": "cache_mesh_invalid"}
	mesh["valid"] = true
	return mesh


func _valid_mesh(mesh: Dictionary) -> bool:
	var positions: Variant = mesh.get("positions", null)
	var normals: Variant = mesh.get("normals", null)
	if typeof(positions) != TYPE_PACKED_VECTOR3_ARRAY or typeof(normals) != TYPE_PACKED_VECTOR3_ARRAY:
		return false
	if positions.size() == 0 or positions.size() != normals.size() or positions.size() % 3 != 0:
		return false
	for value in positions:
		if not value.is_finite():
			return false
	for value in normals:
		if not value.is_finite():
			return false
	return int(mesh.get("vertex_count", positions.size())) == positions.size() \
		and int(mesh.get("triangle_count", positions.size() / 3)) == positions.size() / 3


func _remember(key: String, mesh: Dictionary) -> void:
	var bytes := var_to_bytes(mesh).size()
	if bytes > MAX_MEMORY_BYTES:
		return
	if _memory.has(key):
		_memory_bytes -= int(_memory_sizes[key])
		_memory_order.erase(key)
	_memory[key] = mesh.duplicate(true)
	_memory_sizes[key] = bytes
	_memory_bytes += bytes
	_memory_order.append(key)
	while _memory.size() > MAX_MEMORY_ENTRIES or _memory_bytes > MAX_MEMORY_BYTES:
		var oldest: String = _memory_order.pop_front()
		_memory_bytes -= int(_memory_sizes[oldest])
		_memory.erase(oldest)
		_memory_sizes.erase(oldest)
	peak_memory_bytes = maxi(peak_memory_bytes, _memory_bytes)


func _make_disk_room(incoming: int) -> bool:
	var files := _cache_files()
	while disk_bytes + incoming > MAX_DISK_BYTES or files.size() >= MAX_DISK_ENTRIES:
		if files.is_empty():
			return false
		files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.mtime) < int(b.mtime))
		var victim: Dictionary = files.pop_front()
		if DirAccess.remove_absolute(String(victim.path)) != OK:
			return false
		disk_bytes = _scan_disk_bytes()
	return true


func _cache_files() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(_root)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".bin"):
			var path := _root.path_join(file_name)
			var measured_file := FileAccess.open(path, FileAccess.READ)
			var file_size := measured_file.get_length() if measured_file != null else 0
			if measured_file != null:
				measured_file.close()
			result.append({"path": path, "mtime": FileAccess.get_modified_time(path), "bytes": file_size})
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _scan_disk_bytes() -> int:
	var total := 0
	for entry in _cache_files():
		total += int(entry.bytes)
	return total


func _remove_orphan_temps() -> void:
	var dir := DirAccess.open(_root)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.contains(".tmp-"):
			DirAccess.remove_absolute(_root.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


func _uncached_result(mesh: Dictionary, reason: String) -> Dictionary:
	var result := mesh.duplicate(true)
	result["valid"] = true
	result["cache_hit"] = false
	result["cache_layer"] = "canonical_uncached"
	result["cache_store_error"] = reason
	return result


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
