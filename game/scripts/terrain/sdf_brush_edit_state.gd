class_name SdfBrushEditState
extends RefCounted

## One bounded, globally ordered in-memory command ledger shared by every region.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const SPATIAL := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const GRID := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const MAX_EDITS := 32
const MIN_RADIUS := 0.45
const MAX_RADIUS := 2.0
const MAX_ABS_WORLD_COORDINATE := 1000000.0

enum Mode { CARVE, FILL }

var world_seed: int
var generator_version: int
var _operations: Array[Dictionary] = []
var _by_region: Dictionary = {} # "x,z" -> ordered sequence numbers
var _by_sequence: Dictionary = {} # sequence -> canonical operation
var revision := 0
var _next_sequence := 0


func _init(seed_value: int = 424242, generator_value: int = FIELD.GENERATOR_VERSION) -> void:
	world_seed = seed_value
	generator_version = generator_value


## center is canonical world space. Admission is atomic: all validation and fanout
## complete before the operation, sequence, revision or index changes.
func add_sphere(mode: int, center: Vector3, radius: float) -> bool:
	if _operations.size() >= MAX_EDITS:
		return false
	if mode != Mode.CARVE and mode != Mode.FILL:
		return false
	if not center.is_finite() or not is_finite(radius):
		return false
	if maxf(absf(center.x), maxf(absf(center.y), absf(center.z))) > MAX_ABS_WORLD_COORDINATE:
		return false
	if radius < MIN_RADIUS or radius > MAX_RADIUS:
		return false
	var affected_regions := _regions_intersecting_sphere(center, radius)
	if affected_regions.is_empty() or affected_regions.size() > 4:
		return false
	var sequence := _next_sequence
	var operation_id := "sdf-v%d-seed%d-seq%d" % [generator_version, world_seed, sequence]
	var operation := {
		"operation_id": operation_id,
		"sequence": sequence,
		"revision": revision + 1,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"mode": mode,
		"center_world": center,
		"radius": radius,
		"affected_regions": affected_regions,
	}
	_operations.append(operation)
	_by_sequence[sequence] = operation
	for region_key in affected_regions:
		var region_id := _region_id(region_key)
		if not _by_region.has(region_id):
			_by_region[region_id] = []
		(_by_region[region_id] as Array).append(sequence)
	_next_sequence += 1
	revision += 1
	return true


## Focused X semantics: remove all globally ordered commands whose support touched
## the focused region. Neighbor regions are returned for a coherent resident remesh.
func clear_for_region(region_key: Vector2i) -> Dictionary:
	var removed_sequences: Dictionary = {}
	var affected_regions: Dictionary = {}
	for operation in _operations:
		var regions: Array[Vector2i] = operation["affected_regions"]
		if regions.has(region_key):
			removed_sequences[int(operation["sequence"])] = true
			for key in regions:
				affected_regions[_region_id(key)] = key
	if removed_sequences.is_empty():
		return {"removed_count": 0, "affected_regions": []}
	var retained: Array[Dictionary] = []
	for operation in _operations:
		if not removed_sequences.has(int(operation["sequence"])):
			retained.append(operation)
	_operations = retained
	_rebuild_sequence_index()
	_rebuild_spatial_index()
	revision += 1
	var keys: Array[Vector2i] = []
	for key_value in affected_regions.values():
		keys.append(key_value)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return {"removed_count": removed_sequences.size(), "affected_regions": keys}


func clear() -> void:
	if _operations.is_empty():
		return
	_operations.clear()
	_by_region.clear()
	_by_sequence.clear()
	revision += 1


func get_edit_count() -> int:
	return _operations.size()


func get_last_sequence() -> int:
	return _next_sequence - 1


func get_region_edit_count(region_key: Vector2i) -> int:
	return (_by_region.get(_region_id(region_key), []) as Array).size()


func get_operations_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for operation in _operations:
		snapshot.append(operation.duplicate(true))
	return snapshot


func get_operations_for_region(region_key: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var region_id := _region_id(region_key)
	if not _by_region.has(region_id):
		return result
	var sequences: Array = _by_region[region_id]
	for sequence_value in sequences:
		var sequence: int = sequence_value
		# Sequence is monotonic but operations may have been removed by focused reset.
		if _by_sequence.has(sequence):
			result.append(_by_sequence[sequence])
	return result


func sample_density(
	seed: int,
	region_key: Vector2i,
	local_position: Vector3,
	show_cave_section: bool = false
) -> float:
	var density: float = FIELD.sample_density(seed, region_key, local_position)
	var world_position := SPATIAL.region_local_to_world(region_key, local_position)
	# Evaluate one canonical command stream at every world sample. The spatial
	# index controls affected mesh fanout; it never changes shared-border values.
	for operation in _operations:
		if int(operation["world_seed"]) != seed or int(operation["generator_version"]) != generator_version:
			continue
		var center: Vector3 = operation["center_world"]
		var distance_to_surface := world_position.distance_to(center) - float(operation["radius"])
		if int(operation["mode"]) == Mode.CARVE:
			# density >= 0 is solid; min removes a spherical volume.
			density = minf(density, distance_to_surface)
		else:
			# max adds the sphere interior to the solid field.
			density = maxf(density, -distance_to_surface)
	if show_cave_section:
		# The section affects only this visualization sample, after canonical edits.
		density = minf(density, 6.0 - world_position.z)
	return density


func _regions_intersecting_sphere(center: Vector3, radius: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var min_x := floori((center.x - radius) / SPATIAL.REGION_SIZE_X)
	var max_x := floori((center.x + radius) / SPATIAL.REGION_SIZE_X)
	var min_z := floori((center.z - radius) / SPATIAL.REGION_SIZE_Z)
	var max_z := floori((center.z + radius) / SPATIAL.REGION_SIZE_Z)
	for rz in range(min_z, max_z + 1):
		for rx in range(min_x, max_x + 1):
			var region_min := Vector3(float(rx) * SPATIAL.REGION_SIZE_X, GRID.MIN_BOUND.y, float(rz) * SPATIAL.REGION_SIZE_Z)
			var region_max := region_min + Vector3(SPATIAL.REGION_SIZE_X, GRID.MAX_BOUND.y - GRID.MIN_BOUND.y, SPATIAL.REGION_SIZE_Z)
			var closest := Vector3(
				clampf(center.x, region_min.x, region_max.x),
				clampf(center.y, region_min.y, region_max.y),
				clampf(center.z, region_min.z, region_max.z)
			)
			if closest.distance_squared_to(center) <= radius * radius:
				result.append(Vector2i(rx, rz))
	return result


func _rebuild_spatial_index() -> void:
	_by_region.clear()
	for operation in _operations:
		var sequence: int = operation["sequence"]
		for region_key in operation["affected_regions"]:
			var region_id := _region_id(region_key)
			if not _by_region.has(region_id):
				_by_region[region_id] = []
			(_by_region[region_id] as Array).append(sequence)


func _rebuild_sequence_index() -> void:
	_by_sequence.clear()
	for operation in _operations:
		_by_sequence[int(operation["sequence"])] = operation


func _region_id(region_key: Vector2i) -> String:
	return "%d,%d" % [region_key.x, region_key.y]
