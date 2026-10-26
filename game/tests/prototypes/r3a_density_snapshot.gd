extends RefCounted

## Test-only scalar materialization sampled from canonical SDF v1 + ordered ledger.
## Trilinear evaluation is explicitly approximate between stored lattice points.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Step := 0.5
const FORMAT := 1

var _seed: int
var _operations: Array[Dictionary]
var _region: Vector2i
var _chunk: Vector2i
var _origin: Vector3
var _counts := Vector3i.ZERO
var _values := PackedFloat64Array()
var _ledger_digest := ""
var sample_count := 0
var file_path := ""


func _init(seed_value: int, operations: Array[Dictionary], region_key: Vector2i, chunk_coordinate: Vector2i) -> void:
	_seed = seed_value
	_operations = operations.duplicate(false)
	_region = region_key
	_chunk = chunk_coordinate
	var world_region_origin := Vector3(float(region_key.x) * Field.REGION_SIZE_X, 0.0, float(region_key.y) * Field.REGION_SIZE_Z)
	_origin = world_region_origin + Grid.origin_for(chunk_coordinate) + Vector3(-Step, Grid.MIN_BOUND.y - Step, -Step)
	var size: Vector3 = Grid.size_for(chunk_coordinate)
	_counts = Vector3i(roundi((size.x + Step * 2.0) / Step) + 1, roundi((size.y + Step * 2.0) / Step) + 1, roundi((size.z + Step * 2.0) / Step) + 1)
	_ledger_digest = _digest_operations(_operations)


func build() -> bool:
	if not Grid.is_valid_coordinate(_chunk) or _counts.x < 2 or _counts.y < 2 or _counts.z < 2:
		return false
	_values.resize(_counts.x * _counts.y * _counts.z)
	var index := 0
	for y in range(_counts.y):
		for z in range(_counts.z):
			for x in range(_counts.x):
				var point := _origin + Vector3(float(x), float(y), float(z)) * Step
				_values[index] = _exact_density(point)
				index += 1
	sample_count = index
	return true


## Apply exactly the next canonical ledger command to every stored lattice
## sample. This preserves ordered min/max semantics at the grid nodes, but does
## not make trilinear interpolation equal to the continuous SDF between nodes.
func apply_ordered_delta(operation: Dictionary) -> bool:
	if _values.size() != _counts.x * _counts.y * _counts.z:
		return false
	var sequence := int(operation.get("sequence", -1))
	var revision := int(operation.get("revision", -1))
	var mode := int(operation.get("mode", -1))
	var center_value: Variant = operation.get("center_world", null)
	var radius := float(operation.get("radius", NAN))
	if typeof(center_value) != TYPE_VECTOR3:
		return false
	var center: Vector3 = center_value
	if sequence != _operations.size() or revision != sequence + 1 \
		or int(operation.get("world_seed", -1)) != _seed \
		or int(operation.get("generator_version", -1)) != Field.GENERATOR_VERSION \
		or (mode != Brush.Mode.CARVE and mode != Brush.Mode.FILL) \
		or not center.is_finite() \
		or not is_finite(radius) or radius < Brush.MIN_RADIUS or radius > Brush.MAX_RADIUS:
		return false
	if not _operations.is_empty():
		var previous: Dictionary = _operations.back()
		if sequence != int(previous.get("sequence", -1)) + 1 or revision != int(previous.get("revision", -1)) + 1:
			return false
	var index := 0
	for y in range(_counts.y):
		for z in range(_counts.z):
			for x in range(_counts.x):
				var world_point := _origin + Vector3(float(x), float(y), float(z)) * Step
				var signed_distance := world_point.distance_to(center) - radius
				var value := _values[index]
				_values[index] = minf(value, signed_distance) if mode == Brush.Mode.CARVE else maxf(value, -signed_distance)
				index += 1
	_operations.append(operation.duplicate(true))
	_ledger_digest = _digest_operations(_operations)
	return true


func grid_value_mismatch_count(other_values: PackedFloat64Array) -> int:
	if other_values.size() != _values.size():
		return maxi(1, absi(other_values.size() - _values.size()))
	var mismatches := 0
	for index in range(_values.size()):
		if not is_finite(_values[index]) or _values[index] != other_values[index]:
			mismatches += 1
	return mismatches


func get_grid_values_snapshot() -> PackedFloat64Array:
	return _values


func persist(directory: String) -> int:
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if _values.is_empty() or (directory_error != OK and directory_error != ERR_ALREADY_EXISTS):
		return -1
	var path := directory.path_join("density-snapshot-v1.bin")
	if FileAccess.file_exists(path):
		return -1
	var payload := {
		"format": FORMAT, "seed": _seed, "region": [_region.x, _region.y], "chunk": [_chunk.x, _chunk.y],
		"step": Step, "origin": [_origin.x, _origin.y, _origin.z], "counts": [_counts.x, _counts.y, _counts.z],
		"ledger_digest": _ledger_digest, "values": _values,
	}
	var bytes := var_to_bytes(payload)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return -1
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return -1
	var sidecar := FileAccess.open(path + ".sha256", FileAccess.WRITE)
	if sidecar == null:
		return -1
	sidecar.store_string(_sha256(bytes) + "  " + path.get_file() + "\n")
	sidecar.flush()
	sidecar.close()
	file_path = path
	return bytes.size()


func load_from(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	var sidecar := FileAccess.get_file_as_string(path + ".sha256").strip_edges()
	if bytes.is_empty() or _sha256(bytes) != sidecar.get_slice(" ", 0):
		return false
	var value: Variant = bytes_to_var(bytes)
	if typeof(value) != TYPE_DICTIONARY or int(value.get("format", -1)) != FORMAT:
		return false
	if int(value.get("seed", -1)) != _seed or String(value.get("ledger_digest", "")) != _ledger_digest:
		return false
	var stored_region: Array = value.get("region", [])
	var stored_chunk: Array = value.get("chunk", [])
	if stored_region != [_region.x, _region.y] or stored_chunk != [_chunk.x, _chunk.y] or float(value.get("step", 0.0)) != Step:
		return false
	var origin_values: Array = value.get("origin", [])
	var counts: Array = value.get("counts", [])
	var values: Variant = value.get("values", null)
	if origin_values.size() != 3 or counts != [_counts.x, _counts.y, _counts.z] or typeof(values) != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	var expected_origin := [_origin.x, _origin.y, _origin.z]
	for index in range(3):
		if float(origin_values[index]) != float(expected_origin[index]):
			return false
	if (values as PackedFloat64Array).size() != _counts.x * _counts.y * _counts.z:
		return false
	_values = values
	sample_count = _values.size()
	file_path = path
	return true


func sample_density(world_point: Vector3) -> float:
	if _values.is_empty() or not world_point.is_finite():
		return NAN
	var grid_point := (world_point - _origin) / Step
	var ix := floori(grid_point.x)
	var iy := floori(grid_point.y)
	var iz := floori(grid_point.z)
	var tx := grid_point.x - float(ix)
	var ty := grid_point.y - float(iy)
	var tz := grid_point.z - float(iz)
	if ix < 0 or iy < 0 or iz < 0 or ix >= _counts.x or iy >= _counts.y or iz >= _counts.z:
		return NAN
	if absf(tx) < 0.0000001 and absf(ty) < 0.0000001 and absf(tz) < 0.0000001:
		return _values[_index(ix, iy, iz)]
	if (tx > 0.0 and ix + 1 >= _counts.x) or (ty > 0.0 and iy + 1 >= _counts.y) or (tz > 0.0 and iz + 1 >= _counts.z):
		return NAN
	var x1 := ix + (1 if tx > 0.0 else 0)
	var y1 := iy + (1 if ty > 0.0 else 0)
	var z1 := iz + (1 if tz > 0.0 else 0)
	var c000 := _values[_index(ix, iy, iz)]
	var c100 := _values[_index(x1, iy, iz)]
	var c010 := _values[_index(ix, y1, iz)]
	var c110 := _values[_index(x1, y1, iz)]
	var c001 := _values[_index(ix, iy, z1)]
	var c101 := _values[_index(x1, iy, z1)]
	var c011 := _values[_index(ix, y1, z1)]
	var c111 := _values[_index(x1, y1, z1)]
	var c00 := lerpf(c000, c100, tx)
	var c10 := lerpf(c010, c110, tx)
	var c01 := lerpf(c001, c101, tx)
	var c11 := lerpf(c011, c111, tx)
	return lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tz)


func compare_exact_grid_samples() -> bool:
	if _values.is_empty():
		return false
	var check_count := mini(31, _values.size())
	for sample in range(check_count):
		var index := int((int(sample) * 7919) % _values.size())
		var x := index % _counts.x
		var z := int(index / _counts.x) % _counts.z
		var y := int(index / (_counts.x * _counts.z))
		var point := _origin + Vector3(float(x), float(y), float(z)) * Step
		if _values[index] != _exact_density(point):
			return false
	return true


func compare_probe_samples(probes: Array) -> int:
	var mismatches := 0
	for probe_value in probes:
		if typeof(probe_value) != TYPE_VECTOR3:
			mismatches += 1
			continue
		var point: Vector3 = probe_value
		var approximate := sample_density(point)
		var exact := _exact_density(point)
		if not is_finite(approximate) or absf(approximate - exact) > 0.000001:
			mismatches += 1
	return mismatches


func matches_ledger(operations: Array[Dictionary]) -> bool:
	return _digest_operations(operations) == _ledger_digest


func _exact_density(world_point: Vector3) -> float:
	var density: float = Field.sample_density(_seed, Vector2i.ZERO, world_point)
	for operation in _operations:
		var distance: float = world_point.distance_to(operation["center_world"]) - float(operation["radius"])
		if int(operation["mode"]) == Brush.Mode.CARVE:
			density = minf(density, distance)
		else:
			density = maxf(density, -distance)
	return density


func _index(x: int, y: int, z: int) -> int:
	return (y * _counts.z + z) * _counts.x + x


func _digest_operations(operations: Array[Dictionary]) -> String:
	var canonical: Array[Dictionary] = []
	for operation in operations:
		canonical.append({
			"sequence": int(operation["sequence"]), "revision": int(operation["revision"]),
			"mode": "CARVE" if int(operation["mode"]) == Brush.Mode.CARVE else "FILL",
			"center_mm": [roundi(operation["center_world"].x * 1000.0), roundi(operation["center_world"].y * 1000.0), roundi(operation["center_world"].z * 1000.0)],
			"radius_mm": roundi(float(operation["radius"]) * 1000.0),
		})
	return _sha256(JSON.stringify(canonical).to_utf8_buffer())


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
