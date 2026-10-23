class_name SdfBrushEditState
extends RefCounted

## One bounded, globally ordered in-memory command ledger shared by every region.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const SPATIAL := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const GRID := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const MAX_EDITS := 256
const MIN_RADIUS := 0.45
const MAX_RADIUS := 2.0
const MAX_ABS_WORLD_COORDINATE := 1000000.0
const REBUILD_DEPENDENCY_HALO := GRID.SAMPLE_STEP
# Exact meshing-query bound. Mesh samples and central-difference normal probes
# lie in the chunk AABB expanded by SAMPLE_STEP/2. In that domain, the v1 base
# SDF is within [-6.68, 4.0]. A carve threshold at distance >= 9 is >= 7;
# a fill threshold is <= -7. Both are dominated for every possible ordered
# intermediate density. This prunes only provably no-op terms, never by brush
# support alone. General density queries still evaluate the full ledger.
const MESHING_QUERY_MARGIN := GRID.SAMPLE_STEP * 0.5
const MESHING_NOOP_DISTANCE := 9.0
const SURFACE_Y_MIN := 1.57
const SURFACE_Y_MAX := 6.03

enum Mode { CARVE, FILL }

var world_seed: int
var generator_version: int
var _operations: Array[Dictionary] = []
var _by_region: Dictionary = {} # "x,z" -> ordered sequence numbers
var _by_sequence: Dictionary = {} # sequence -> canonical operation
var revision := 0
var _next_sequence := 0
var last_rejection_reason := ""
var last_restore_rejection_reason := ""


func _init(seed_value: int = 424242, generator_value: int = FIELD.GENERATOR_VERSION) -> void:
	world_seed = seed_value
	generator_version = generator_value


## center is canonical world space. Admission is atomic: all validation and fanout
## complete before the operation, sequence, revision or index changes.
func add_sphere(mode: int, center: Vector3, radius: float) -> bool:
	if mode != Mode.CARVE and mode != Mode.FILL:
		last_rejection_reason = "invalid_mode"
		return false
	if not center.is_finite() or not is_finite(radius):
		last_rejection_reason = "non_finite_input"
		return false
	if maxf(absf(center.x), maxf(absf(center.y), absf(center.z))) > MAX_ABS_WORLD_COORDINATE:
		last_rejection_reason = "coordinate_out_of_bounds"
		return false
	if radius < MIN_RADIUS or radius > MAX_RADIUS:
		last_rejection_reason = "radius_out_of_bounds"
		return false
	var support_regions := _regions_intersecting_sphere(center, radius)
	var rebuild_regions := _regions_intersecting_sphere(center, radius + REBUILD_DEPENDENCY_HALO)
	if support_regions.is_empty() or support_regions.size() > 4 or rebuild_regions.is_empty() or rebuild_regions.size() > 4:
		last_rejection_reason = "region_fanout_exceeded"
		return false
	if _operations.size() >= MAX_EDITS:
		last_rejection_reason = "ledger_capacity_exceeded"
		return false
	var dependency_regions: Array[Vector2i] = []
	for region_key in rebuild_regions:
		if not support_regions.has(region_key):
			dependency_regions.append(region_key)
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
		"support_regions": support_regions,
		"dependency_regions": dependency_regions,
		"rebuild_regions": rebuild_regions,
	}
	_operations.append(operation)
	_by_sequence[sequence] = operation
	for region_key in support_regions:
		var region_id := _region_id(region_key)
		if not _by_region.has(region_id):
			_by_region[region_id] = []
		(_by_region[region_id] as Array).append(sequence)
	_next_sequence += 1
	revision += 1
	last_rejection_reason = ""
	return true


## Focused X semantics: remove all globally ordered commands whose support touched
## the focused region. Neighbor regions are returned for a coherent resident remesh.
func clear_for_region(region_key: Vector2i) -> Dictionary:
	var removed_sequences: Dictionary = {}
	var rebuild_regions: Dictionary = {}
	for operation in _operations:
		var support_regions: Array[Vector2i] = operation["support_regions"]
		if support_regions.has(region_key):
			removed_sequences[int(operation["sequence"])] = true
			for key in operation["rebuild_regions"]:
				rebuild_regions[_region_id(key)] = key
	if removed_sequences.is_empty():
		return {"removed_count": 0, "rebuild_regions": []}
	var retained: Array[Dictionary] = []
	for operation in _operations:
		if not removed_sequences.has(int(operation["sequence"])):
			retained.append(operation)
	_operations = retained
	_rebuild_sequence_index()
	_rebuild_spatial_index()
	revision += 1
	var keys: Array[Vector2i] = []
	for key_value in rebuild_regions.values():
		keys.append(key_value)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return {"removed_count": removed_sequences.size(), "rebuild_regions": keys}


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


func get_next_sequence() -> int:
	return _next_sequence


## Durable saves contain commands and ledger metadata, never meshes or scene data.
func get_persistence_snapshot() -> Dictionary:
	var operations: Array[Dictionary] = []
	for operation in _operations:
		operations.append({
			"sequence": int(operation["sequence"]),
			"revision": int(operation["revision"]),
			"mode": int(operation["mode"]),
			"center": [float(operation["center_world"].x), float(operation["center_world"].y), float(operation["center_world"].z)],
			"radius": float(operation["radius"]),
		})
	return {
		"world_seed": world_seed,
		"generator_version": generator_version,
		"revision": revision,
		"next_sequence": _next_sequence,
		"operations": operations,
	}


## Restore is accepted only into a pristine ledger. Validation and spatial fanout
## are completed into temporary structures before any live state is replaced.
func restore_persistence_snapshot(snapshot: Dictionary) -> bool:
	last_restore_rejection_reason = ""
	if not _operations.is_empty() or not _by_region.is_empty() or not _by_sequence.is_empty() or revision != 0 or _next_sequence != 0:
		last_restore_rejection_reason = "restore_target_not_pristine"
		return false
	var saved_seed_value: Variant = snapshot.get("world_seed", null)
	var saved_generator_value: Variant = snapshot.get("generator_version", null)
	if not _is_safe_integer(saved_seed_value) or not _is_safe_integer(saved_generator_value) \
		or int(saved_seed_value) != world_seed or int(saved_generator_value) != generator_version:
		last_restore_rejection_reason = "restore_world_identity_mismatch"
		return false
	var target_revision_value: Variant = snapshot.get("revision", null)
	var next_sequence_value: Variant = snapshot.get("next_sequence", null)
	var operations_value: Variant = snapshot.get("operations", null)
	if not _is_safe_integer(target_revision_value) or not _is_safe_integer(next_sequence_value) \
		or typeof(operations_value) != TYPE_ARRAY:
		last_restore_rejection_reason = "restore_metadata_invalid"
		return false
	var target_revision := int(target_revision_value)
	var target_next_sequence := int(next_sequence_value)
	var source_operations: Array = operations_value
	if target_revision < 0 or target_next_sequence < 0 or source_operations.size() > MAX_EDITS \
		or target_revision < source_operations.size() or target_next_sequence < source_operations.size():
		last_restore_rejection_reason = "restore_metadata_out_of_bounds"
		return false
	var restored: Array[Dictionary] = []
	var restored_by_region: Dictionary = {}
	var restored_by_sequence: Dictionary = {}
	var previous_sequence := -1
	var previous_operation_revision := 0
	for source_value in source_operations:
		if typeof(source_value) != TYPE_DICTIONARY:
			last_restore_rejection_reason = "restore_operation_not_object"
			return false
		var source: Dictionary = source_value
		var sequence_value: Variant = source.get("sequence", null)
		var operation_revision_value: Variant = source.get("revision", null)
		var mode_value: Variant = source.get("mode", null)
		var center_value: Variant = source.get("center", null)
		var radius_value: Variant = source.get("radius", null)
		if not _is_safe_integer(sequence_value) or not _is_safe_integer(operation_revision_value) \
			or not _is_safe_integer(mode_value) or typeof(center_value) != TYPE_ARRAY \
			or not _is_finite_number(radius_value):
			last_restore_rejection_reason = "restore_operation_metadata_invalid"
			return false
		var sequence := int(sequence_value)
		var operation_revision := int(operation_revision_value)
		var mode := int(mode_value)
		var center_values: Array = center_value
		if center_values.size() != 3 or sequence <= previous_sequence \
			or operation_revision <= previous_operation_revision or operation_revision > target_revision \
			or sequence >= target_next_sequence or (mode != Mode.CARVE and mode != Mode.FILL):
			last_restore_rejection_reason = "restore_operation_order_or_mode_invalid"
			return false
		for component in center_values:
			if not _is_finite_number(component):
				last_restore_rejection_reason = "restore_operation_center_invalid"
				return false
		var center := Vector3(float(center_values[0]), float(center_values[1]), float(center_values[2]))
		var radius := float(radius_value)
		var operation_result := _build_operation(mode, center, radius, sequence, operation_revision)
		if not operation_result.get("valid", false):
			last_restore_rejection_reason = "restore_operation_rejected_%s" % operation_result.get("reason", "invalid")
			return false
		var operation: Dictionary = operation_result["operation"]
		restored.append(operation)
		restored_by_sequence[sequence] = operation
		for region_key in operation["support_regions"]:
			var region_id := _region_id(region_key)
			if not restored_by_region.has(region_id):
				restored_by_region[region_id] = []
			(restored_by_region[region_id] as Array).append(sequence)
		previous_sequence = sequence
		previous_operation_revision = operation_revision
	_operations = restored
	_by_region = restored_by_region
	_by_sequence = restored_by_sequence
	revision = target_revision
	_next_sequence = target_next_sequence
	return true


func get_region_edit_count(region_key: Vector2i) -> int:
	return (_by_region.get(_region_id(region_key), []) as Array).size()


func get_operations_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for operation in _operations:
		snapshot.append(operation.duplicate(true))
	return snapshot


func get_last_operation_snapshot() -> Dictionary:
	if _operations.is_empty():
		return {}
	return (_operations[-1] as Dictionary).duplicate(true)


## Compact immutable worker input. Packed arrays are shared read-only with mesh jobs.
func get_meshing_snapshot() -> Dictionary:
	var centers := PackedVector3Array()
	var radii := PackedFloat64Array()
	var modes := PackedByteArray()
	for operation in _operations:
		if int(operation["world_seed"]) != world_seed or int(operation["generator_version"]) != generator_version:
			continue
		centers.append(operation["center_world"])
		radii.append(float(operation["radius"]))
		modes.append(int(operation["mode"]))
	return {
		"revision": revision,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"centers": centers,
		"radii": radii,
		"modes": modes,
	}


## Build an ordered, immutable operation subset for one chunk. Terms are omitted
## only when their sphere SDF is mathematically dominated for every lattice and
## normal probe in this chunk. This is deliberately broader than geometric
## support because min/max SDF tails can affect values beyond the brush sphere.
func get_meshing_snapshot_for_chunk(region_key: Vector2i, chunk_coordinate: Vector2i) -> Dictionary:
	var centers := PackedVector3Array()
	var radii := PackedFloat64Array()
	var modes := PackedByteArray()
	var sequences := PackedInt32Array()
	if GRID.is_valid_coordinate(chunk_coordinate):
		var region_origin := SPATIAL.region_origin_world(region_key)
		var chunk_origin := region_origin + GRID.origin_for(chunk_coordinate)
		var chunk_size := GRID.size_for(chunk_coordinate)
		# origin_for()/size_for() intentionally describe horizontal chunk placement
		# and the vertical extent size, respectively; they do not encode the grid's
		# negative minimum Y. Cover the complete lattice and central-difference
		# normal domain explicitly, including both vertical endpoints.
		var chunk_min := Vector3(
			chunk_origin.x - MESHING_QUERY_MARGIN,
			GRID.MIN_BOUND.y - MESHING_QUERY_MARGIN,
			chunk_origin.z - MESHING_QUERY_MARGIN
		)
		var chunk_max := Vector3(
			chunk_origin.x + chunk_size.x + MESHING_QUERY_MARGIN,
			GRID.MAX_BOUND.y + MESHING_QUERY_MARGIN,
			chunk_origin.z + chunk_size.z + MESHING_QUERY_MARGIN
		)
		var max_distance_squared := MESHING_NOOP_DISTANCE * MESHING_NOOP_DISTANCE
		for operation in _operations:
			if int(operation["world_seed"]) != world_seed \
				or int(operation["generator_version"]) != generator_version:
				continue
			var center: Vector3 = operation["center_world"]
			var nearest := Vector3(
				clampf(center.x, chunk_min.x, chunk_max.x),
				clampf(center.y, chunk_min.y, chunk_max.y),
				clampf(center.z, chunk_min.z, chunk_max.z)
			)
			if nearest.distance_squared_to(center) > max_distance_squared:
				continue
			centers.append(center)
			radii.append(float(operation["radius"]))
			modes.append(int(operation["mode"]))
			sequences.append(int(operation["sequence"]))
	return {
		"revision": revision,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"centers": centers,
		"radii": radii,
		"modes": modes,
		"sequences": sequences,
		"candidate_operation_count": centers.size(),
		"ledger_operation_count": _operations.size(),
	}


## Ordered, conservative subset for every point on one bounded picker ray. The
## interval is propagated through each min/max command, so omitting a command
## is proven harmless even after all earlier retained commands. This preserves
## exact values/order while avoiding a full ledger scan for every ray sample.
func get_ray_snapshot(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	if not ray_origin.is_finite() or not ray_direction.is_finite() \
		or not is_finite(max_distance) or max_distance < 0.0 \
		or ray_direction.length_squared() <= 0.000001:
		return get_meshing_snapshot()
	var direction := ray_direction.normalized()
	var ray_end := ray_origin + direction * max_distance
	var y_min := minf(ray_origin.y, ray_end.y)
	var y_max := maxf(ray_origin.y, ray_end.y)
	# SdfWorld's surface term is min(surface_y-y, y-MIN_Y), with
	# surface_y in [1.57, 6.03]. The cave SDF is always >= -0.92. These are
	# conservative bounds for the base field on the complete ray segment.
	var density_min := minf(SURFACE_Y_MIN - y_max, minf(y_min - FIELD.MIN_Y, -0.92))
	var peak_y := clampf((SURFACE_Y_MAX + FIELD.MIN_Y) * 0.5, y_min, y_max)
	var density_max := minf(SURFACE_Y_MAX - peak_y, peak_y - FIELD.MIN_Y)
	var centers := PackedVector3Array()
	var radii := PackedFloat64Array()
	var modes := PackedByteArray()
	var sequences := PackedInt32Array()
	var segment := ray_end - ray_origin
	var segment_length_squared := segment.length_squared()
	for operation in _operations:
		if int(operation["world_seed"]) != world_seed or int(operation["generator_version"]) != generator_version:
			continue
		var center: Vector3 = operation["center_world"]
		var radius := float(operation["radius"])
		var projection := 0.0
		if segment_length_squared > 0.000001:
			projection = clampf((center - ray_origin).dot(segment) / segment_length_squared, 0.0, 1.0)
		var nearest := ray_origin + segment * projection
		var minimum_distance := center.distance_to(nearest)
		var maximum_distance := maxf(center.distance_to(ray_origin), center.distance_to(ray_end))
		var mode := int(operation["mode"])
		var keep_operation := true
		if mode == Mode.CARVE:
			var threshold_min := minimum_distance - radius
			var threshold_max := maximum_distance - radius
			if threshold_min >= density_max:
				keep_operation = false
			else:
				density_min = minf(density_min, threshold_min)
				density_max = minf(density_max, threshold_max)
		else:
			var threshold_min := radius - maximum_distance
			var threshold_max := radius - minimum_distance
			if threshold_max <= density_min:
				keep_operation = false
			else:
				density_min = maxf(density_min, threshold_min)
				density_max = maxf(density_max, threshold_max)
		if keep_operation:
			centers.append(center)
			radii.append(radius)
			modes.append(mode)
			sequences.append(int(operation["sequence"]))
	return {
		"revision": revision,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"centers": centers,
		"radii": radii,
		"modes": modes,
		"sequences": sequences,
		"candidate_operation_count": centers.size(),
		"ledger_operation_count": _operations.size(),
	}


static func sample_density_snapshot(
	seed: int,
	region_key: Vector2i,
	local_position: Vector3,
	show_cave_section: bool,
	snapshot: Dictionary
) -> float:
	var density: float = FIELD.sample_density(seed, region_key, local_position)
	var world_position := SPATIAL.region_local_to_world(region_key, local_position)
	var centers: PackedVector3Array = snapshot["centers"]
	var radii: PackedFloat64Array = snapshot["radii"]
	var modes: PackedByteArray = snapshot["modes"]
	for index in range(centers.size()):
		var distance_to_surface := world_position.distance_to(centers[index]) - radii[index]
		if modes[index] == Mode.CARVE:
			density = minf(density, distance_to_surface)
		else:
			density = maxf(density, -distance_to_surface)
	if show_cave_section:
		density = minf(density, 6.0 - world_position.z)
	return density


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
			result.append((_by_sequence[sequence] as Dictionary).duplicate(true))
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
		for region_key in operation["support_regions"]:
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


func _build_operation(mode: int, center: Vector3, radius: float, sequence: int, operation_revision: int) -> Dictionary:
	if mode != Mode.CARVE and mode != Mode.FILL:
		return {"valid": false, "reason": "invalid_mode"}
	if not center.is_finite() or not is_finite(radius):
		return {"valid": false, "reason": "non_finite_input"}
	if maxf(absf(center.x), maxf(absf(center.y), absf(center.z))) > MAX_ABS_WORLD_COORDINATE:
		return {"valid": false, "reason": "coordinate_out_of_bounds"}
	if radius < MIN_RADIUS or radius > MAX_RADIUS:
		return {"valid": false, "reason": "radius_out_of_bounds"}
	var support_regions := _regions_intersecting_sphere(center, radius)
	var rebuild_regions := _regions_intersecting_sphere(center, radius + REBUILD_DEPENDENCY_HALO)
	if support_regions.is_empty() or support_regions.size() > 4 or rebuild_regions.is_empty() or rebuild_regions.size() > 4:
		return {"valid": false, "reason": "region_fanout_exceeded"}
	var dependency_regions: Array[Vector2i] = []
	for region_key in rebuild_regions:
		if not support_regions.has(region_key):
			dependency_regions.append(region_key)
	return {
		"valid": true,
		"operation": {
			"operation_id": "sdf-v%d-seed%d-seq%d" % [generator_version, world_seed, sequence],
			"sequence": sequence,
			"revision": operation_revision,
			"world_seed": world_seed,
			"generator_version": generator_version,
			"mode": mode,
			"center_world": center,
			"radius": radius,
			"support_regions": support_regions,
			"dependency_regions": dependency_regions,
			"rebuild_regions": rebuild_regions,
		},
	}


func _is_safe_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return absf(float(value)) <= 9007199254740991.0
	if typeof(value) == TYPE_FLOAT:
		var numeric := float(value)
		return is_finite(numeric) and floorf(numeric) == numeric and absf(numeric) <= 9007199254740991.0
	return false


func _is_finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))
