extends RefCounted

## Disposable derived projection of the canonical ordered SDF ledger.
## The global ledger remains authoritative; projections are rebuilt on mismatch.
const FORMAT := 1
const MAGIC := "P31R4-CHUNK-SUBLEDGER-1"
const MAX_STORE_BYTES := 16 * 1024 * 1024
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")

var identity: Dictionary = {}
var revision := -1
var world_seed := 0
var generator_version := 0
var centers := PackedVector3Array()
var radii := PackedFloat64Array()
var modes := PackedByteArray()
var sequences := PackedInt32Array()
var last_reason := ""


static func from_ledger(ledger: RefCounted, region: Vector2i, chunk: Vector2i) -> RefCounted:
	var instance: RefCounted = load("res://tests/prototypes/r4_chunk_subledger.gd").new()
	if not instance.rebuild(ledger, region, chunk):
		return null
	return instance


func rebuild(ledger: RefCounted, region: Vector2i, chunk: Vector2i) -> bool:
	last_reason = ""
	var snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	if not bool(snapshot.get("valid", false)):
		last_reason = "canonical_projection_unavailable"
		return false
	if not _accept_snapshot(snapshot, region, chunk):
		return false
	return true


func append_snapshot(snapshot: Dictionary) -> bool:
	last_reason = ""
	var next_revision := int(snapshot.get("revision", -1))
	if next_revision <= revision or next_revision > Brush.MAX_OPERATION_COUNT:
		last_reason = "stale_or_duplicate_revision"
		return false
	if int(snapshot.get("world_seed", -1)) != world_seed \
		or int(snapshot.get("generator_version", -1)) != generator_version:
		last_reason = "world_identity_changed"
		return false
	var centers_value: Variant = snapshot.get("centers", null)
	var radii_value: Variant = snapshot.get("radii", null)
	var modes_value: Variant = snapshot.get("modes", null)
	var sequences_value: Variant = snapshot.get("sequences", null)
	if typeof(centers_value) != TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(radii_value) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(modes_value) != TYPE_PACKED_BYTE_ARRAY \
		or typeof(sequences_value) != TYPE_PACKED_INT32_ARRAY:
		last_reason = "snapshot_array_type_invalid"
		return false
	var next_centers: PackedVector3Array = centers_value
	var next_radii: PackedFloat64Array = radii_value
	var next_modes: PackedByteArray = modes_value
	var next_sequences: PackedInt32Array = sequences_value
	if next_centers.size() != next_radii.size() or next_centers.size() != next_modes.size() \
		or next_centers.size() != next_sequences.size() \
		or int(snapshot.get("candidate_operation_count", -1)) != next_centers.size():
		last_reason = "snapshot_array_length_mismatch"
		return false
	if next_sequences.size() < sequences.size():
		last_reason = "snapshot_prefix_shrank_rebuild_required"
		return false
	# Relevance is recomputed against the full ordered history. A later min/max
	# tail can make an older command newly relevant, so an append is safe only
	# when every existing projected entry remains the exact prefix.
	for index in range(sequences.size()):
		if next_sequences[index] != sequences[index] or next_centers[index] != centers[index] \
			or next_radii[index] != radii[index] or next_modes[index] != modes[index]:
			last_reason = "snapshot_prefix_changed_rebuild_required"
			return false
	var previous_sequence := sequences[-1] if not sequences.is_empty() else -1
	var appended_centers := PackedVector3Array()
	var appended_radii := PackedFloat64Array()
	var appended_modes := PackedByteArray()
	var appended_sequences := PackedInt32Array()
	for index in range(sequences.size(), next_sequences.size()):
		var sequence := int(next_sequences[index])
		if sequence <= previous_sequence:
			last_reason = "snapshot_sequence_not_increasing"
			return false
		if int(next_modes[index]) != 0 and int(next_modes[index]) != 1:
			last_reason = "snapshot_mode_invalid"
			return false
		if not next_centers[index].is_finite() or not is_finite(next_radii[index]) \
			or next_radii[index] < Brush.MIN_RADIUS or next_radii[index] > Brush.MAX_RADIUS:
			last_reason = "snapshot_geometry_invalid"
			return false
		appended_centers.append(next_centers[index])
		appended_radii.append(next_radii[index])
		appended_modes.append(next_modes[index])
		appended_sequences.append(sequence)
		previous_sequence = sequence
	centers.append_array(appended_centers)
	radii.append_array(appended_radii)
	modes.append_array(appended_modes)
	sequences.append_array(appended_sequences)
	revision = int(snapshot.get("revision", -1))
	return true


func as_snapshot() -> Dictionary:
	return {"valid": true, "revision": revision, "world_seed": world_seed,
		"generator_version": generator_version, "centers": centers.duplicate(), "radii": radii.duplicate(),
		"modes": modes.duplicate(), "sequences": sequences.duplicate(),
		"region": identity.get("region", Vector2i.ZERO), "chunk": identity.get("chunk", Vector2i.ZERO),
		"candidate_operation_count": centers.size()}


func digest() -> String:
	# Global revision is provenance, not local content identity: a remote edit that
	# leaves this projection byte-identical must remain eligible for cache reuse.
	return _sha256(var_to_bytes({"identity": identity,
		"world_seed": world_seed, "generator_version": generator_version,
		"centers": centers, "radii": radii, "modes": modes, "sequences": sequences}))


func save_atomic(root: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(root)
	var payload := var_to_bytes(as_snapshot())
	var payload_hash := _sha256(payload)
	var key := _sha256(var_to_bytes(identity))
	var envelope := {"magic": MAGIC, "format": FORMAT, "identity": identity,
		"key": key, "payload_sha256": payload_hash, "payload": payload}
	var bytes := var_to_bytes(envelope)
	var final_path := root.path_join("%s-r%d-%s.subledger" % [key, revision, payload_hash])
	if FileAccess.file_exists(final_path):
		return {"valid": load_file(final_path, identity), "path": final_path, "reused": true, "bytes_written": 0}
	var stored_bytes := 0
	for name in DirAccess.get_files_at(root):
		stored_bytes += int(FileAccess.get_file_as_bytes(root.path_join(name)).size())
	if bytes.size() > MAX_STORE_BYTES or stored_bytes + bytes.size() > MAX_STORE_BYTES:
		return {"valid": false, "reason": "subledger_store_quota_exceeded", "bytes_written": 0}
	var temp_path := final_path + ".pending-%d" % Time.get_ticks_usec()
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"valid": false, "reason": "projection_temp_open_failed"}
	file.store_buffer(bytes)
	file.flush()
	file.close()
	var publish_error := DirAccess.rename_absolute(temp_path, final_path)
	if publish_error != OK:
		return {"valid": false, "reason": "projection_atomic_publish_failed", "error": publish_error}
	return {"valid": load_file(final_path, identity), "path": final_path,
		"reused": false, "bytes_written": bytes.size()}


func load_file(path: String, expected_identity: Dictionary) -> bool:
	last_reason = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_reason = "projection_open_failed"
		return false
	var length := file.get_length()
	var bytes := file.get_buffer(length)
	file.close()
	if length < 1 or bytes.size() != length:
		last_reason = "projection_truncated"
		return false
	var envelope: Variant = bytes_to_var(bytes)
	if typeof(envelope) != TYPE_DICTIONARY or String(envelope.get("magic", "")) != MAGIC \
		or int(envelope.get("format", -1)) != FORMAT or envelope.get("identity", {}) != expected_identity \
		or String(envelope.get("key", "")) != _sha256(var_to_bytes(expected_identity)):
		last_reason = "projection_identity_invalid"
		return false
	var payload: Variant = envelope.get("payload", PackedByteArray())
	if typeof(payload) != TYPE_PACKED_BYTE_ARRAY or _sha256(payload) != String(envelope.get("payload_sha256", "")):
		last_reason = "projection_payload_hash_invalid"
		return false
	var decoded: Variant = bytes_to_var(payload)
	if typeof(decoded) != TYPE_DICTIONARY:
		last_reason = "projection_payload_invalid"
		return false
	if not _validate_payload(decoded, expected_identity):
		return false
	return true


func load_into(path: String, expected_identity: Dictionary) -> bool:
	if not load_file(path, expected_identity):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_reason = "projection_reopen_failed"
		return false
	var envelope_bytes := file.get_buffer(file.get_length())
	file.close()
	var envelope: Variant = bytes_to_var(envelope_bytes)
	var payload: PackedByteArray = envelope.get("payload", PackedByteArray())
	var decoded: Dictionary = bytes_to_var(payload)
	identity = expected_identity.duplicate(true)
	revision = int(decoded.get("revision", -1))
	world_seed = int(decoded.get("world_seed", 0))
	generator_version = int(decoded.get("generator_version", 0))
	centers = decoded.get("centers", PackedVector3Array())
	radii = decoded.get("radii", PackedFloat64Array())
	modes = decoded.get("modes", PackedByteArray())
	sequences = decoded.get("sequences", PackedInt32Array())
	if centers.size() != radii.size() or centers.size() != modes.size() or centers.size() != sequences.size():
		last_reason = "projection_array_length_mismatch"
		return false
	return true


func _validate_payload(decoded: Dictionary, expected_identity: Dictionary) -> bool:
	var region_value: Variant = decoded.get("region", null)
	var chunk_value: Variant = decoded.get("chunk", null)
	var centers_value: Variant = decoded.get("centers", null)
	var radii_value: Variant = decoded.get("radii", null)
	var modes_value: Variant = decoded.get("modes", null)
	var sequences_value: Variant = decoded.get("sequences", null)
	if typeof(region_value) != TYPE_VECTOR2I or typeof(chunk_value) != TYPE_VECTOR2I \
		or region_value != expected_identity.get("region") or chunk_value != expected_identity.get("chunk"):
		last_reason = "projection_spatial_identity_invalid"
		return false
	if typeof(centers_value) != TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(radii_value) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(modes_value) != TYPE_PACKED_BYTE_ARRAY \
		or typeof(sequences_value) != TYPE_PACKED_INT32_ARRAY:
		last_reason = "projection_array_type_invalid"
		return false
	var centers_array: PackedVector3Array = centers_value
	var radii_array: PackedFloat64Array = radii_value
	var modes_array: PackedByteArray = modes_value
	var sequences_array: PackedInt32Array = sequences_value
	if centers_array.size() != radii_array.size() or centers_array.size() != modes_array.size() \
		or centers_array.size() != sequences_array.size() \
		or int(decoded.get("candidate_operation_count", -1)) != centers_array.size():
		last_reason = "projection_array_length_mismatch"
		return false
	if int(decoded.get("revision", -1)) < 0 \
		or int(decoded.get("world_seed", 0)) != int(expected_identity.get("world_seed", -1)) \
		or int(decoded.get("generator_version", 0)) != int(expected_identity.get("generator_version", -1)):
		last_reason = "projection_provenance_invalid"
		return false
	var previous_sequence := -1
	for index in range(sequences_array.size()):
		if sequences_array[index] <= previous_sequence or sequences_array[index] >= int(decoded.revision) \
			or (modes_array[index] != 0 and modes_array[index] != 1) \
			or not centers_array[index].is_finite() or not is_finite(radii_array[index]) \
			or radii_array[index] < Brush.MIN_RADIUS or radii_array[index] > Brush.MAX_RADIUS:
			last_reason = "projection_operation_invalid"
			return false
		previous_sequence = sequences_array[index]
	return true


func _accept_snapshot(snapshot: Dictionary, region: Vector2i, chunk: Vector2i) -> bool:
	var cs: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
	var rs: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
	var ms: PackedByteArray = snapshot.get("modes", PackedByteArray())
	var ss: PackedInt32Array = snapshot.get("sequences", PackedInt32Array())
	if cs.size() != rs.size() or cs.size() != ms.size() or cs.size() != ss.size():
		last_reason = "snapshot_array_length_mismatch"
		return false
	var previous := -1
	for index in range(ss.size()):
		if ss[index] <= previous or ss[index] >= int(snapshot.get("revision", -1)) \
			or (ms[index] != 0 and ms[index] != 1) or not cs[index].is_finite() \
			or not is_finite(rs[index]) or rs[index] < Brush.MIN_RADIUS or rs[index] > Brush.MAX_RADIUS:
			last_reason = "snapshot_operation_invalid"
			return false
		previous = ss[index]
		centers.append(cs[index])
		radii.append(rs[index])
		modes.append(ms[index])
		sequences.append(ss[index])
	world_seed = int(snapshot.get("world_seed", 0))
	generator_version = int(snapshot.get("generator_version", 0))
	revision = int(snapshot.get("revision", -1))
	if revision < 0 or int(snapshot.get("candidate_operation_count", -1)) != centers.size():
		last_reason = "snapshot_provenance_invalid"
		return false
	identity = {"region": region, "chunk": chunk, "world_seed": world_seed,
		"generator_version": generator_version, "halo_contract": "production-mesh-query-v1"}
	return revision >= 0


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
