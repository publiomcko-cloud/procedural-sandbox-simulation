extends RefCounted

## Disposable, content-addressed derived mesh cache. Ledger remains authoritative.
const CACHE_FORMAT := 1

var _directory: String
var hit_count := 0
var miss_count := 0
var total_bytes := 0
var peak_bytes := 0


func _init(directory_path: String) -> void:
	_directory = directory_path
	DirAccess.make_dir_recursive_absolute(_directory)


func get_or_build(identity: Dictionary, builder: Callable) -> Dictionary:
	var identity_bytes := JSON.stringify(identity, "", true).to_utf8_buffer()
	var key := _sha256(identity_bytes)
	var path := _directory.path_join("mesh-%s.bin" % key)
	var sidecar_path := path + ".sha256"
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		var sidecar := FileAccess.get_file_as_string(sidecar_path).strip_edges()
		var expected := sidecar.get_slice(" ", 0)
		if not bytes.is_empty() and _sha256(bytes) == expected:
			var decoded: Variant = bytes_to_var(bytes)
			if typeof(decoded) == TYPE_DICTIONARY and decoded.get("format", 0) == CACHE_FORMAT and decoded.get("identity", {}) == identity:
				var data: Dictionary = decoded.get("mesh", {})
				if _mesh_data_valid(data):
					hit_count += 1
					data["valid"] = true
					data["rebuilt"] = false
					data["cache_path"] = path
					return data
		# Cache is derived and corrupt/stale bytes are never treated as world state.
		DirAccess.remove_absolute(path)
		if FileAccess.file_exists(sidecar_path):
			DirAccess.remove_absolute(sidecar_path)
		total_bytes = maxi(0, total_bytes - bytes.size() - sidecar.to_utf8_buffer().size())
	miss_count += 1
	var built_value: Variant = builder.call()
	if typeof(built_value) != TYPE_DICTIONARY or not bool(built_value.get("valid", false)):
		return {"valid": false, "reason": "canonical_builder_failed", "rebuilt": true}
	var mesh: Dictionary = {
		"positions": built_value.get("positions", PackedVector3Array()),
		"normals": built_value.get("normals", PackedVector3Array()),
		"vertex_count": int(built_value.get("vertex_count", 0)),
		"triangle_count": int(built_value.get("triangle_count", 0)),
		"sample_count": int(built_value.get("sample_count", 0)),
	}
	if not _mesh_data_valid(mesh):
		return {"valid": false, "reason": "canonical_mesh_payload_invalid", "rebuilt": true}
	var bytes := var_to_bytes({"format": CACHE_FORMAT, "identity": identity, "mesh": mesh})
	var temp_path := path + ".tmp-%s" % str(randi()).pad_zeros(8)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"valid": false, "reason": "cache_temp_unavailable", "rebuilt": true}
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temp_path)
		return {"valid": false, "reason": "cache_write_failed", "rebuilt": true}
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
		return {"valid": false, "reason": "cache_publish_failed", "rebuilt": true}
	var sidecar := FileAccess.open(sidecar_path, FileAccess.WRITE)
	if sidecar == null:
		DirAccess.remove_absolute(path)
		return {"valid": false, "reason": "cache_digest_publish_failed", "rebuilt": true}
	sidecar.store_string(_sha256(bytes) + "  " + path.get_file() + "\n")
	var sidecar_bytes := (_sha256(bytes) + "  " + path.get_file() + "\n").to_utf8_buffer().size()
	sidecar.flush()
	sidecar.close()
	total_bytes += bytes.size() + sidecar_bytes
	peak_bytes = maxi(peak_bytes, total_bytes)
	mesh["valid"] = true
	mesh["rebuilt"] = true
	mesh["cache_path"] = path
	return mesh


func corrupt_cache_for_test(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_8(0x7f)
	file.flush()
	return file.get_error() == OK


func _mesh_data_valid(mesh: Dictionary) -> bool:
	var positions: Variant = mesh.get("positions", null)
	var normals: Variant = mesh.get("normals", null)
	if typeof(positions) != TYPE_PACKED_VECTOR3_ARRAY or typeof(normals) != TYPE_PACKED_VECTOR3_ARRAY:
		return false
	if positions.size() != normals.size() or positions.size() % 3 != 0:
		return false
	for point in positions:
		if not point.is_finite():
			return false
	for normal in normals:
		if not normal.is_finite():
			return false
	return true


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
