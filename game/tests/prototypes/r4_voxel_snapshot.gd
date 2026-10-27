extends RefCounted

## Test-only float32 materialization. The authoritative ledger is never changed.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const FORMAT := 1
const MAGIC := "P31R4-VOXEL-SNAPSHOT-1"
const MAX_VOXEL_COUNT := 100000
const MAX_STORE_BYTES := 64 * 1024 * 1024

var spacing := 0.5
var region := Vector2i.ZERO
var chunk := Vector2i.ZERO
var world_min := Vector3.ZERO
var nx := 0
var ny := 0
var nz := 0
var revision := -1
var world_seed := 0
var generator_version := 1
var densities := PackedFloat32Array()
var last_reason := ""
var update_node_visits := 0


func materialize(seed: int, region_key: Vector2i, chunk_coordinate: Vector2i,
	brush_snapshot: Dictionary, requested_spacing: float) -> bool:
	last_reason = ""
	if not is_finite(requested_spacing) or requested_spacing <= 0.0:
		last_reason = "snapshot_spacing_invalid"
		return false
	var margin := Grid.SAMPLE_STEP * 0.5
	var region_origin := Spatial.region_origin_world(region_key)
	var chunk_origin := region_origin + Grid.origin_for(chunk_coordinate)
	world_min = Vector3(chunk_origin.x - margin, Grid.MIN_BOUND.y - margin,
		chunk_origin.z - margin)
	var world_max := Vector3(chunk_origin.x + Grid.size_for(chunk_coordinate).x + margin,
		Grid.MAX_BOUND.y + margin,
		chunk_origin.z + Grid.size_for(chunk_coordinate).z + margin)
	var intervals := Vector3((world_max.x - world_min.x) / requested_spacing,
		(world_max.y - world_min.y) / requested_spacing,
		(world_max.z - world_min.z) / requested_spacing)
	if not _near_integer(intervals.x) or not _near_integer(intervals.y) or not _near_integer(intervals.z):
		last_reason = "snapshot_spacing_not_divisor"
		return false
	spacing = requested_spacing
	region = region_key
	chunk = chunk_coordinate
	nx = roundi(intervals.x) + 1
	ny = roundi(intervals.y) + 1
	nz = roundi(intervals.z) + 1
	if nx * ny * nz > MAX_VOXEL_COUNT:
		last_reason = "snapshot_voxel_quota_exceeded"
		return false
	world_seed = seed
	generator_version = int(brush_snapshot.get("generator_version", 1))
	revision = int(brush_snapshot.get("revision", -1))
	densities.resize(nx * ny * nz)
	var sample_snapshot := brush_snapshot
	if not sample_snapshot.has("sequences"):
		var sequences := PackedInt32Array()
		for i in range(sample_snapshot.get("centers", PackedVector3Array()).size()):
			sequences.append(i)
		sample_snapshot = sample_snapshot.duplicate(true)
		sample_snapshot["sequences"] = sequences
	var local_origin := Spatial.region_origin_world(region)
	for y in range(ny):
		for z in range(nz):
			for x in range(nx):
				var world_point := world_min + Vector3(x, y, z) * spacing
				var local_point := world_point - local_origin
				densities[_index(x, y, z)] = Brush.sample_density_snapshot(
					seed, region, local_point, false, sample_snapshot
				)
	return densities.size() == nx * ny * nz


func apply_operation(operation: Dictionary) -> bool:
	last_reason = ""
	var sequence := int(operation.get("sequence", -1))
	var next_revision := int(operation.get("revision", -1))
	# The canonical ledger has one zero-based sequence per committed revision.
	# Requiring the immediate successor prevents gaps, reordering, and replay.
	if sequence != revision or next_revision != revision + 1:
		last_reason = "snapshot_delta_revision_invalid"
		return false
	var mode := int(operation.get("mode", -1))
	if mode != Brush.Mode.CARVE and mode != Brush.Mode.FILL:
		last_reason = "snapshot_delta_mode_invalid"
		return false
	var center: Vector3 = operation.get("center_world", Vector3(NAN, NAN, NAN))
	var radius := float(operation.get("radius", NAN))
	if not center.is_finite() or not is_finite(radius) or radius <= 0.0:
		last_reason = "snapshot_delta_geometry_invalid"
		return false
	# Deliberately visit every voxel: a brush SDF has min/max tails outside its
	# radius when composed with a negative/positive current field. No support-only
	# shortcut is used here.
	update_node_visits = 0
	for y in range(ny):
		for z in range(nz):
			for x in range(nx):
				var index := _index(x, y, z)
				var point := world_min + Vector3(x, y, z) * spacing
				var threshold := point.distance_to(center) - radius
				var current := float(densities[index])
				densities[index] = minf(current, threshold) if mode == Brush.Mode.CARVE else maxf(current, -threshold)
				update_node_visits += 1
	revision = int(operation.get("revision", revision + 1))
	return true


func advance_revision_without_geometry(next_revision: int) -> bool:
	if next_revision != revision + 1:
		last_reason = "snapshot_revision_not_contiguous"
		return false
	revision = next_revision
	return true


func sample_world(world_point: Vector3) -> float:
	if densities.size() != nx * ny * nz or nx < 2 or ny < 2 or nz < 2:
		return NAN
	var grid_position := (world_point - world_min) / spacing
	if grid_position.x < 0.0 or grid_position.y < 0.0 or grid_position.z < 0.0 \
		or grid_position.x > nx - 1 or grid_position.y > ny - 1 or grid_position.z > nz - 1:
		return NAN
	var x0 := mini(floori(grid_position.x), nx - 2)
	var y0 := mini(floori(grid_position.y), ny - 2)
	var z0 := mini(floori(grid_position.z), nz - 2)
	var tx := grid_position.x - x0
	var ty := grid_position.y - y0
	var tz := grid_position.z - z0
	var c000 := float(densities[_index(x0, y0, z0)])
	var c100 := float(densities[_index(x0 + 1, y0, z0)])
	var c010 := float(densities[_index(x0, y0 + 1, z0)])
	var c110 := float(densities[_index(x0 + 1, y0 + 1, z0)])
	var c001 := float(densities[_index(x0, y0, z0 + 1)])
	var c101 := float(densities[_index(x0 + 1, y0, z0 + 1)])
	var c011 := float(densities[_index(x0, y0 + 1, z0 + 1)])
	var c111 := float(densities[_index(x0 + 1, y0 + 1, z0 + 1)])
	var z0_lerp := lerpf(lerpf(c000, c100, tx), lerpf(c010, c110, tx), ty)
	var z1_lerp := lerpf(lerpf(c001, c101, tx), lerpf(c011, c111, tx), ty)
	return lerpf(z0_lerp, z1_lerp, tz)


func statistics() -> Dictionary:
	return {"spacing": spacing, "dimensions": [nx, ny, nz], "voxel_count": densities.size(),
		"payload_bytes": densities.size() * 4, "revision": revision,
		"update_node_visits": update_node_visits}


func save_atomic(root: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(root)
	var payload := var_to_bytes({"spacing": spacing, "region": region, "chunk": chunk,
		"world_min": world_min, "nx": nx, "ny": ny, "nz": nz, "revision": revision,
		"world_seed": world_seed, "generator_version": generator_version, "densities": densities})
	var digest := _sha256(payload)
	var key := _sha256(var_to_bytes({"spacing": spacing, "region": region, "chunk": chunk,
		"world_seed": world_seed, "generator_version": generator_version}))
	var envelope := var_to_bytes({"magic": MAGIC, "format": FORMAT, "key": key,
		"payload_sha256": digest, "payload": payload})
	var path := root.path_join("%s-r%d-%s.vox" % [key, revision, digest])
	if FileAccess.file_exists(path):
		return {"valid": _validate_file(path, key), "path": path, "reused": true, "bytes_written": 0}
	var stored_bytes := 0
	for name in DirAccess.get_files_at(root):
		stored_bytes += int(FileAccess.get_file_as_bytes(root.path_join(name)).size())
	if envelope.size() > MAX_STORE_BYTES or stored_bytes + envelope.size() > MAX_STORE_BYTES:
		return {"valid": false, "reason": "voxel_store_quota_exceeded", "bytes_written": 0}
	var temp := path + ".pending-%d" % Time.get_ticks_usec()
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"valid": false, "reason": "voxel_temp_open_failed"}
	file.store_buffer(envelope)
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(temp, path)
	return {"valid": error == OK and _validate_file(path, key), "path": path,
		"bytes_written": envelope.size(), "publish_error": error}


func load_file(path: String, expected_region: Vector2i, expected_chunk: Vector2i,
	expected_spacing: float, expected_seed: int, expected_generator: int) -> bool:
	last_reason = ""
	var key := _sha256(var_to_bytes({"spacing": expected_spacing, "region": expected_region,
		"chunk": expected_chunk, "world_seed": expected_seed, "generator_version": expected_generator}))
	if not _validate_file(path, key):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_reason = "voxel_reopen_failed"
		return false
	var envelope: Dictionary = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	var payload: PackedByteArray = envelope.get("payload", PackedByteArray())
	var decoded_variant: Variant = bytes_to_var(payload)
	if typeof(decoded_variant) != TYPE_DICTIONARY:
		last_reason = "voxel_payload_invalid"
		return false
	var decoded: Dictionary = decoded_variant
	if decoded.get("region") != expected_region or decoded.get("chunk") != expected_chunk \
		or float(decoded.get("spacing", -1.0)) != expected_spacing \
		or int(decoded.get("world_seed", -1)) != expected_seed \
		or int(decoded.get("generator_version", -1)) != expected_generator:
		last_reason = "voxel_identity_invalid"
		return false
	var minimum_value: Variant = decoded.get("world_min", null)
	var density_value: Variant = decoded.get("densities", null)
	var dimension_x := int(decoded.get("nx", -1))
	var dimension_y := int(decoded.get("ny", -1))
	var dimension_z := int(decoded.get("nz", -1))
	var expected_origin := Spatial.region_origin_world(expected_region) + Grid.origin_for(expected_chunk)
	var expected_minimum := Vector3(expected_origin.x - Grid.SAMPLE_STEP * 0.5,
		Grid.MIN_BOUND.y - Grid.SAMPLE_STEP * 0.5, expected_origin.z - Grid.SAMPLE_STEP * 0.5)
	var expected_size := Grid.size_for(expected_chunk)
	var expected_dimensions := Vector3i(
		roundi((expected_size.x + Grid.SAMPLE_STEP) / expected_spacing) + 1,
		roundi((Grid.MAX_BOUND.y - Grid.MIN_BOUND.y + Grid.SAMPLE_STEP) / expected_spacing) + 1,
		roundi((expected_size.z + Grid.SAMPLE_STEP) / expected_spacing) + 1)
	if typeof(minimum_value) != TYPE_VECTOR3 or not minimum_value.is_finite() \
		or minimum_value != expected_minimum \
		or typeof(density_value) != TYPE_PACKED_FLOAT32_ARRAY \
		or int(decoded.get("revision", -1)) < 0 or int(decoded.get("revision", -1)) > Brush.MAX_OPERATION_COUNT \
		or dimension_x < 2 or dimension_y < 2 or dimension_z < 2 \
		or dimension_x * dimension_y * dimension_z > MAX_VOXEL_COUNT \
		or dimension_x != expected_dimensions.x or dimension_y != expected_dimensions.y \
		or dimension_z != expected_dimensions.z:
		last_reason = "voxel_payload_schema_invalid"
		return false
	var validated_densities: PackedFloat32Array = density_value
	if validated_densities.size() != dimension_x * dimension_y * dimension_z:
		last_reason = "voxel_dimensions_mismatch"
		return false
	for density in validated_densities:
		if not is_finite(density):
			last_reason = "voxel_density_nonfinite"
			return false
	spacing = decoded.spacing
	region = decoded.region
	chunk = decoded.chunk
	world_min = minimum_value
	nx = dimension_x
	ny = dimension_y
	nz = dimension_z
	revision = int(decoded.revision)
	world_seed = int(decoded.world_seed)
	generator_version = int(decoded.generator_version)
	densities = validated_densities
	return true


func _validate_file(path: String, expected_key: String) -> bool:
	last_reason = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_reason = "voxel_open_failed"
		return false
	var length := file.get_length()
	var bytes := file.get_buffer(length)
	file.close()
	if length < 1 or length != bytes.size():
		last_reason = "voxel_truncated"
		return false
	var envelope: Variant = bytes_to_var(bytes)
	if typeof(envelope) != TYPE_DICTIONARY or String(envelope.get("magic", "")) != MAGIC \
		or int(envelope.get("format", -1)) != FORMAT or String(envelope.get("key", "")) != expected_key:
		last_reason = "voxel_envelope_invalid"
		return false
	var payload: Variant = envelope.get("payload", PackedByteArray())
	if typeof(payload) != TYPE_PACKED_BYTE_ARRAY or _sha256(payload) != String(envelope.get("payload_sha256", "")):
		last_reason = "voxel_payload_hash_invalid"
		return false
	return true


func _index(x: int, y: int, z: int) -> int:
	return (y * nz + z) * nx + x


func _near_integer(value: float) -> bool:
	return absf(value - roundf(value)) < 0.00001


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
