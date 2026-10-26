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
const LOCK_TIMEOUT_MSEC := 5000
const WRITE_LOCK_NAME := ".r3c-write-lock"

var _root: String
var _memory := {}
var _memory_sizes := {}
var _memory_order: Array[String] = []
var _memory_bytes := 0
var _disk_inventory: Array[Dictionary] = []
var _write_lock_path: String
var hit_count := 0
var miss_count := 0
var corrupt_count := 0
var adaptive_bypass_count := 0
var disk_bytes := 0
var peak_memory_bytes := 0
var last_builder_usec := 0
var last_timings_usec: Dictionary = {}


func _init(root_path: String) -> void:
	var started := Time.get_ticks_usec()
	_root = root_path
	DirAccess.make_dir_recursive_absolute(_root)
	_disk_inventory = _cache_files()
	disk_bytes = _inventory_bytes()
	last_timings_usec = {"cache_init_scan": Time.get_ticks_usec() - started}
	_write_lock_path = _root.path_join(WRITE_LOCK_NAME)


func get_or_build(identity: Dictionary, builder: Callable, expected_reuse_count: int = 1) -> Dictionary:
	var total_started := Time.get_ticks_usec()
	last_timings_usec = {}
	if expected_reuse_count < 0:
		return {"valid": false, "reason": "adaptive_reuse_count_invalid", "cache_hit": false}
	if expected_reuse_count == 0:
		adaptive_bypass_count += 1
		miss_count += 1
		var bypass_started := Time.get_ticks_usec()
		var bypass_value: Variant = builder.call()
		last_builder_usec = Time.get_ticks_usec() - bypass_started
		last_timings_usec = {"builder": last_builder_usec, "adaptive_decision": 0}
		if typeof(bypass_value) != TYPE_DICTIONARY or not bool(bypass_value.get("valid", false)) or not _valid_mesh(bypass_value):
			return {"valid": false, "reason": "canonical_mesh_build_invalid", "cache_hit": false}
		var bypass_result := _uncached_result(_mesh_payload(bypass_value), "adaptive_expected_reuse_zero")
		bypass_result["cache_layer"] = "bypassed_no_expected_revisit"
		bypass_result["adaptive_bypass"] = true
		last_timings_usec["total"] = Time.get_ticks_usec() - total_started
		return bypass_result
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
	var publish_started := Time.get_ticks_usec()
	var publish_result := _publish_entry(path, identity, key, envelope)
	last_timings_usec["publish_transaction"] = Time.get_ticks_usec() - publish_started
	for timing_name in publish_result.get("timings_usec", {}):
		last_timings_usec[timing_name] = int(publish_result.timings_usec[timing_name])
	if not bool(publish_result.get("stored", false)):
		var winner: Variant = publish_result.get("winner", null)
		if typeof(winner) == TYPE_DICTIONARY and bool(winner.get("valid", false)):
			_remember(key, winner)
			winner["cache_hit"] = true
			winner["cache_layer"] = "disk_concurrent_publish"
			winner["duplicate_build_discarded"] = true
			hit_count += 1
			last_timings_usec["total"] = Time.get_ticks_usec() - total_started
			return winner
		var publish_reason := String(publish_result.get("reason", "cache_publish_unavailable"))
		last_timings_usec["total"] = Time.get_ticks_usec() - total_started
		return _uncached_result(mesh, publish_reason)
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
		"peak_memory_bytes": peak_memory_bytes, "last_builder_usec": last_builder_usec,
		"adaptive_bypass_count": adaptive_bypass_count, "disk_entries": _disk_inventory.size()}


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


func _mesh_payload(value: Dictionary) -> Dictionary:
	return {"positions": value.get("positions", PackedVector3Array()),
		"normals": value.get("normals", PackedVector3Array()),
		"vertex_count": int(value.get("vertex_count", 0)),
		"triangle_count": int(value.get("triangle_count", 0)),
		"sample_count": int(value.get("sample_count", 0))}


func _publish_entry(path: String, identity: Dictionary, key: String, envelope: PackedByteArray) -> Dictionary:
	var timings := {}
	var lock_started := Time.get_ticks_usec()
	if not _acquire_write_lock():
		timings["write_lock_wait"] = Time.get_ticks_usec() - lock_started
		return {"stored": false, "reason": "cache_write_lock_timeout", "timings_usec": timings}
	timings["write_lock_wait"] = Time.get_ticks_usec() - lock_started
	var result := {"stored": false, "timings_usec": timings}
	_remove_orphan_temps_locked()
	var scan_started := Time.get_ticks_usec()
	_disk_inventory = _cache_files()
	disk_bytes = _inventory_bytes()
	timings["quota_inventory_scan"] = Time.get_ticks_usec() - scan_started
	if FileAccess.file_exists(path):
		var existing := _read_entry(path, identity, key)
		if bool(existing.get("valid", false)):
			result["winner"] = existing
			_release_write_lock()
			return result
		var existing_bytes := _file_size(path)
		if DirAccess.remove_absolute(path) != OK:
			result["reason"] = "cache_corrupt_entry_remove_failed"
			_release_write_lock()
			return result
		_remove_inventory_path(path, existing_bytes)
	var quota_started := Time.get_ticks_usec()
	if not _make_disk_room_locked(envelope.size()):
		timings["quota"] = Time.get_ticks_usec() - quota_started
		result["reason"] = "cache_disk_quota_unavailable"
		_release_write_lock()
		return result
	timings["quota"] = Time.get_ticks_usec() - quota_started
	var temp := path + ".tmp-%d-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec(), randi()]
	if FileAccess.file_exists(temp):
		result["reason"] = "cache_temp_collision"
		_release_write_lock()
		return result
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		result["reason"] = "cache_temp_open_failed"
		_release_write_lock()
		return result
	var write_started := Time.get_ticks_usec()
	file.store_buffer(envelope)
	file.flush()
	var write_error := file.get_error()
	file.close()
	timings["disk_write_flush"] = Time.get_ticks_usec() - write_started
	if write_error != OK:
		DirAccess.remove_absolute(temp)
		result["reason"] = "cache_temp_write_failed"
		_release_write_lock()
		return result
	var rename_started := Time.get_ticks_usec()
	var publish_error := DirAccess.rename_absolute(temp, path)
	timings["atomic_publish"] = Time.get_ticks_usec() - rename_started
	if publish_error != OK:
		DirAccess.remove_absolute(temp)
		result["reason"] = "cache_atomic_publish_failed"
		_release_write_lock()
		return result
	_disk_inventory.append({"path": path, "mtime": FileAccess.get_modified_time(path), "bytes": envelope.size()})
	disk_bytes += envelope.size()
	result["stored"] = true
	_release_write_lock()
	return result


func _make_disk_room_locked(incoming: int) -> bool:
	while disk_bytes + incoming > MAX_DISK_BYTES or _disk_inventory.size() >= MAX_DISK_ENTRIES:
		if _disk_inventory.is_empty():
			return false
		_disk_inventory.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.mtime) < int(b.mtime))
		var victim: Dictionary = _disk_inventory.pop_front()
		if DirAccess.remove_absolute(String(victim.path)) != OK:
			_disk_inventory.append(victim)
			return false
		disk_bytes = maxi(0, disk_bytes - int(victim.bytes))
	return true


func _acquire_write_lock() -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < LOCK_TIMEOUT_MSEC:
		if DirAccess.make_dir_absolute(_write_lock_path) == OK:
			return true
		OS.delay_msec(10)
	return false


func _release_write_lock() -> void:
	DirAccess.remove_absolute(_write_lock_path)


func _remove_inventory_path(path: String, bytes: int) -> void:
	for index in range(_disk_inventory.size() - 1, -1, -1):
		if String(_disk_inventory[index].path) == path:
			var removed_bytes := int(_disk_inventory[index].bytes)
			_disk_inventory.remove_at(index)
			disk_bytes = maxi(0, disk_bytes - removed_bytes)
			return
	disk_bytes = maxi(0, disk_bytes - bytes)


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


func _inventory_bytes() -> int:
	var total := 0
	for entry in _disk_inventory:
		total += int(entry.bytes)
	return total


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var result := file.get_length()
	file.close()
	return result


func _remove_orphan_temps_locked() -> void:
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
