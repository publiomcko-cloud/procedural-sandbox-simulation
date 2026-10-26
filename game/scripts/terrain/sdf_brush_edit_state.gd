class_name SdfBrushEditState
extends RefCounted

## One bounded, globally ordered in-memory command ledger shared by every region.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const SPATIAL := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const GRID := preload("res://scripts/terrain/terrain_chunk_grid.gd")
# Explicit finite world quota. This replaces the old 256-command prototype cap.
# The v2 store enforces the same limit before committing a generation.
const MAX_EDITS := 256 # Historical fixture-size constant; no longer an admission cap.
const MAX_OPERATION_COUNT := 65536
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
var _by_query_region: Dictionary = {} # conservative min/max influence index for chunk queries
var _operation_source: RefCounted
var _source_storage_metadata: Dictionary = {}
var _source_operation_count := 0
var _excluded_sequences: Dictionary = {}
var revision := 0
var _next_sequence := 0
var last_rejection_reason := ""
var last_restore_rejection_reason := ""
var last_storage_error := ""
var last_sample_candidate_count := 0


func _init(seed_value: int = 424242, generator_value: int = FIELD.GENERATOR_VERSION) -> void:
	world_seed = seed_value
	generator_version = generator_value


## center is canonical world space. Admission is atomic: all validation and fanout
## complete before the operation, sequence, revision or index changes.
func add_sphere(mode: int, center: Vector3, radius: float) -> bool:
	if _operation_source != null and not String(_operation_source.last_read_error).is_empty():
		last_rejection_reason = "storage_integrity_failure"
		return false
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
	if get_edit_count() >= MAX_OPERATION_COUNT:
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
	_index_overlay_for_queries(operation)
	_next_sequence += 1
	revision += 1
	last_rejection_reason = ""
	return true


## Focused X semantics: remove all globally ordered commands whose support touched
## the focused region. Neighbor regions are returned for a coherent resident remesh.
func clear_for_region(region_key: Vector2i) -> Dictionary:
	last_storage_error = ""
	var removed_sequences: Dictionary = {}
	var rebuild_regions: Dictionary = {}
	if _operation_source != null:
		for operation_value in _operation_source.get_operations_for_support_region(region_key):
			var source_operation: Dictionary = operation_value
			var source_sequence := int(source_operation["sequence"])
			if not _excluded_sequences.has(source_sequence):
				removed_sequences[source_sequence] = true
				_excluded_sequences[source_sequence] = true
				for key in source_operation["rebuild_regions"]:
					rebuild_regions[_region_id(key)] = key
		last_storage_error = String(_operation_source.last_read_error)
		if not last_storage_error.is_empty():
			return {"removed_count": 0, "rebuild_regions": [], "error": last_storage_error}
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
	_rebuild_query_index()
	revision += 1
	var keys: Array[Vector2i] = []
	for key_value in rebuild_regions.values():
		keys.append(key_value)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return {"removed_count": removed_sequences.size(), "rebuild_regions": keys}


func clear() -> void:
	last_storage_error = ""
	if get_edit_count() == 0:
		return
	if _operation_source != null:
		var source_sequences: Array[int] = []
		_operation_source.for_each_operation(func(operation: Dictionary) -> void:
			source_sequences.append(int(operation["sequence"]))
		)
		last_storage_error = String(_operation_source.last_read_error)
		if not last_storage_error.is_empty():
			return
		for sequence in source_sequences:
			_excluded_sequences[sequence] = true
	_operations.clear()
	_by_region.clear()
	_by_sequence.clear()
	_by_query_region.clear()
	revision += 1


func get_edit_count() -> int:
	return maxi(0, _source_operation_count - _excluded_sequences.size()) + _operations.size()


func get_last_sequence() -> int:
	return _next_sequence - 1


func get_next_sequence() -> int:
	return _next_sequence


## Durable saves contain commands and ledger metadata, never meshes or scene data.
func get_persistence_snapshot() -> Dictionary:
	var operations: Array[Dictionary] = []
	for operation in _all_active_operations():
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
	if not _operations.is_empty() or not _by_region.is_empty() or not _by_sequence.is_empty() \
		or _operation_source != null or revision != 0 or _next_sequence != 0:
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
	var storage_value: Variant = snapshot.get("storage_reference", null)
	if typeof(storage_value) == TYPE_DICTIONARY:
		var storage_reference: Dictionary = storage_value
		var source_value: Variant = storage_reference.get("source", null)
		var metadata_value: Variant = storage_reference.get("metadata", null)
		if source_value is RefCounted and typeof(metadata_value) == TYPE_DICTIONARY:
			var metadata: Dictionary = metadata_value
			if not source_value.validate_storage_reference(metadata):
				last_restore_rejection_reason = "restore_storage_reference_invalid"
				return false
			var source_count_value: Variant = metadata.get("operation_count", null)
			var source_revision_value: Variant = metadata.get("ledger_revision", null)
			var source_next_value: Variant = metadata.get("next_sequence", null)
			if not _is_safe_integer(source_count_value) or not _is_safe_integer(source_revision_value) or not _is_safe_integer(source_next_value) \
				or int(source_count_value) > MAX_OPERATION_COUNT or int(source_revision_value) < 0 or int(source_next_value) < 0:
				last_restore_rejection_reason = "restore_storage_metadata_invalid"
				return false
			_operation_source = source_value
			_source_storage_metadata = metadata.duplicate(true)
			_source_operation_count = int(source_count_value)
			revision = int(source_revision_value)
			_next_sequence = int(source_next_value)
			return true
	if not _is_safe_integer(target_revision_value) or not _is_safe_integer(next_sequence_value) \
		or typeof(operations_value) != TYPE_ARRAY:
		last_restore_rejection_reason = "restore_metadata_invalid"
		return false
	var target_revision := int(target_revision_value)
	var target_next_sequence := int(next_sequence_value)
	var source_operations: Array = operations_value
	if target_revision < 0 or target_next_sequence < 0 or source_operations.size() > MAX_OPERATION_COUNT \
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
	var region_id := _region_id(region_key)
	var count := (_by_region.get(region_id, []) as Array).size()
	if _operation_source != null:
		for operation in _operation_source.get_operations_for_support_region(region_key):
			if not _excluded_sequences.has(int(operation["sequence"])):
				count += 1
	return count


func get_operations_snapshot() -> Array[Dictionary]:
	last_storage_error = ""
	var snapshot: Array[Dictionary] = []
	for operation in _all_active_operations():
		snapshot.append(operation.duplicate(true))
	if _operation_source != null:
		last_storage_error = String(_operation_source.last_read_error)
		if not last_storage_error.is_empty():
			return []
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
	last_storage_error = ""
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
		var density_interval := _base_density_interval(chunk_min.y, chunk_max.y)
		var candidates := get_operations_for_query_regions([region_key])
		if not last_storage_error.is_empty():
			return {"valid": false, "storage_error": last_storage_error, "revision": revision}
		var have_previous_operation := false
		var previous_mode := -1
		var previous_center := Vector3.ZERO
		var previous_radius := -1.0
		for operation in candidates:
			if int(operation["world_seed"]) != world_seed \
				or int(operation["generator_version"]) != generator_version:
				continue
			var center: Vector3 = operation["center_world"]
			var radius := float(operation["radius"])
			var mode := int(operation["mode"])
			# Consecutive identical min/max operators are idempotent. This exact
			# reduction does not assume anything about the field or later commands.
			if have_previous_operation and mode == previous_mode and center == previous_center and radius == previous_radius:
				continue
			have_previous_operation = true
			previous_mode = mode
			previous_center = center
			previous_radius = radius
			var nearest := Vector3(
				clampf(center.x, chunk_min.x, chunk_max.x),
				clampf(center.y, chunk_min.y, chunk_max.y),
				clampf(center.z, chunk_min.z, chunk_max.z)
			)
			var farthest := Vector3(
				maxf(absf(center.x - chunk_min.x), absf(center.x - chunk_max.x)),
				maxf(absf(center.y - chunk_min.y), absf(center.y - chunk_max.y)),
				maxf(absf(center.z - chunk_min.z), absf(center.z - chunk_max.z))
			)
			var minimum_distance := nearest.distance_to(center)
			var maximum_distance := farthest.length()
			if mode == Mode.CARVE:
				var threshold_min := minimum_distance - radius
				var threshold_max := maximum_distance - radius
				if threshold_min >= float(density_interval["maximum"]):
					continue
				density_interval["minimum"] = minf(float(density_interval["minimum"]), threshold_min)
				density_interval["maximum"] = minf(float(density_interval["maximum"]), threshold_max)
			else:
				var threshold_min := radius - maximum_distance
				var threshold_max := radius - minimum_distance
				if threshold_max <= float(density_interval["minimum"]):
					continue
				density_interval["minimum"] = maxf(float(density_interval["minimum"]), threshold_min)
				density_interval["maximum"] = maxf(float(density_interval["maximum"]), threshold_max)
			centers.append(center)
			radii.append(radius)
			modes.append(mode)
			sequences.append(int(operation["sequence"]))
	return {
		"valid": true,
		"revision": revision,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"centers": centers,
		"radii": radii,
		"modes": modes,
		"sequences": sequences,
		"candidate_operation_count": centers.size(),
		"ledger_operation_count": get_edit_count(),
	}


func _base_density_interval(minimum_y: float, maximum_y: float) -> Dictionary:
	# The v1 field is min(surface_y-y, y-MIN_Y, cave_distance), with
	# surface_y in [1.57,6.03] and cave_distance >= -0.92. These bounds cover
	# every point in the chunk and the normal-probe margin.
	var density_min := minf(SURFACE_Y_MIN - maximum_y, minf(minimum_y - FIELD.MIN_Y, -0.92))
	var peak_y := clampf((SURFACE_Y_MAX + FIELD.MIN_Y) * 0.5, minimum_y, maximum_y)
	var density_max := minf(SURFACE_Y_MAX - peak_y, peak_y - FIELD.MIN_Y)
	return {"minimum": density_min, "maximum": density_max}


## Ordered, conservative subset for every point on one bounded picker ray. The
## interval is propagated through each min/max command, so omitting a command
## is proven harmless even after all earlier retained commands. This preserves
## exact values/order while avoiding a full ledger scan for every ray sample.
func get_ray_snapshot(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	last_storage_error = ""
	if not ray_origin.is_finite() or not ray_direction.is_finite() \
		or not is_finite(max_distance) or max_distance < 0.0 \
		or ray_direction.length_squared() <= 0.000001:
		return {"valid": false, "storage_error": "invalid_ray_query", "revision": revision}
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
	var interval_state := {"minimum": density_min, "maximum": density_max}
	var consume_operation := func(operation: Dictionary) -> void:
		if _excluded_sequences.has(int(operation["sequence"])):
			return
		if int(operation["world_seed"]) != world_seed or int(operation["generator_version"]) != generator_version:
			return
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
			if threshold_min >= float(interval_state["maximum"]):
				keep_operation = false
			else:
				interval_state["minimum"] = minf(float(interval_state["minimum"]), threshold_min)
				interval_state["maximum"] = minf(float(interval_state["maximum"]), threshold_max)
		else:
			var threshold_min := radius - maximum_distance
			var threshold_max := radius - minimum_distance
			if threshold_max <= float(interval_state["minimum"]):
				keep_operation = false
			else:
				interval_state["minimum"] = maxf(float(interval_state["minimum"]), threshold_min)
				interval_state["maximum"] = maxf(float(interval_state["maximum"]), threshold_max)
		if keep_operation:
			centers.append(center)
			radii.append(radius)
			modes.append(mode)
			sequences.append(int(operation["sequence"]))
	var candidates: Array[Dictionary] = []
	if y_min >= GRID.MIN_BOUND.y - MESHING_QUERY_MARGIN and y_max <= GRID.MAX_BOUND.y + MESHING_QUERY_MARGIN:
		var min_region_x := floori(minf(ray_origin.x, ray_end.x) / SPATIAL.REGION_SIZE_X)
		var max_region_x := floori(maxf(ray_origin.x, ray_end.x) / SPATIAL.REGION_SIZE_X)
		var min_region_z := floori(minf(ray_origin.z, ray_end.z) / SPATIAL.REGION_SIZE_Z)
		var max_region_z := floori(maxf(ray_origin.z, ray_end.z) / SPATIAL.REGION_SIZE_Z)
		var region_count := (max_region_x - min_region_x + 1) * (max_region_z - min_region_z + 1)
		if region_count <= 4096:
			var query_regions: Array[Vector2i] = []
			for region_z in range(min_region_z, max_region_z + 1):
				for region_x in range(min_region_x, max_region_x + 1):
					query_regions.append(Vector2i(region_x, region_z))
			candidates = get_operations_for_query_regions(query_regions)
		else:
			candidates = _all_active_operations()
	else:
		# Outside the bounded terrain sample domain the base field is not bounded
		# by the proof below, so retain the exact full ordered replay.
		candidates = _all_active_operations()
	if _operation_source != null:
		last_storage_error = String(_operation_source.last_read_error)
	for operation in candidates:
		consume_operation.call(operation)
	return {
		"valid": last_storage_error.is_empty(),
		"storage_error": last_storage_error,
		"revision": revision,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"centers": centers,
		"radii": radii,
		"modes": modes,
		"sequences": sequences,
		"candidate_operation_count": centers.size(),
		"ledger_operation_count": get_edit_count(),
	}


static func sample_density_snapshot(
	seed: int,
	region_key: Vector2i,
	local_position: Vector3,
	show_cave_section: bool,
	snapshot: Dictionary
) -> float:
	if snapshot.has("valid") and not bool(snapshot["valid"]):
		return NAN
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
	if _operation_source != null:
		for operation in _operation_source.get_operations_for_support_region(region_key):
			if not _excluded_sequences.has(int(operation["sequence"])):
				result.append(operation)
	var region_id := _region_id(region_key)
	for sequence_value in _by_region.get(region_id, []):
		var sequence: int = sequence_value
		if _by_sequence.has(sequence):
			result.append((_by_sequence[sequence] as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["sequence"]) < int(b["sequence"]))
	return result


func sample_density(
	seed: int,
	region_key: Vector2i,
	local_position: Vector3,
	show_cave_section: bool = false
) -> float:
	last_storage_error = ""
	var density: float = FIELD.sample_density(seed, region_key, local_position)
	var world_position := SPATIAL.region_local_to_world(region_key, local_position)
	# Within the finite mesh/sample domain, the v1 base field is in
	# [-6.68, 3.515]. A command more than 9 units away has CARVE threshold > 7
	# or FILL threshold < -7 (radius <= 2), so it is a no-op for every ordered
	# prefix. The persisted query-region index stores every command whose 9-unit
	# sphere intersects that region's full x/z extent and full sample y interval.
	# This is a conservative superset; it does not filter by brush support.
	var operations: Array[Dictionary]
	if world_position.y >= GRID.MIN_BOUND.y - MESHING_QUERY_MARGIN \
		and world_position.y <= GRID.MAX_BOUND.y + MESHING_QUERY_MARGIN:
		var mapped := SPATIAL.world_to_region_local(world_position)
		operations = get_operations_for_query_regions([mapped["region_key"]])
	else:
		# Preserve exact semantics for callers outside the terrain mesh domain.
		operations = _all_active_operations()
		if _operation_source != null:
			last_storage_error = String(_operation_source.last_read_error)
	if not last_storage_error.is_empty():
		return NAN
	last_sample_candidate_count = operations.size()
	# Replay selected commands in their original global sequence order.
	for operation in operations:
		if int(operation["world_seed"]) != world_seed or int(operation["generator_version"]) != generator_version:
			continue
		var center: Vector3 = operation["center_world"]
		var distance_to_surface := world_position.distance_to(center) - float(operation["radius"])
		if int(operation["mode"]) == Mode.CARVE:
			density = minf(density, distance_to_surface)
		else:
			density = maxf(density, -distance_to_surface)
	if show_cave_section:
		# The section affects only this visualization sample, after canonical edits.
		density = minf(density, 6.0 - world_position.z)
	return density


func get_operations_for_query_regions(region_keys: Array) -> Array[Dictionary]:
	last_storage_error = ""
	var result: Array[Dictionary] = []
	var seen_sequences: Dictionary = {}
	if _operation_source != null:
		result.append_array(_operation_source.get_operations_for_query_regions(region_keys, _excluded_sequences))
		last_storage_error = String(_operation_source.last_read_error)
		if not last_storage_error.is_empty():
			return []
		for operation in result:
			seen_sequences[int(operation["sequence"])] = true
	var overlay_sequences: Dictionary = {}
	for region_key_value in region_keys:
		var region_key: Vector2i = region_key_value
		for sequence_value in _by_query_region.get(_region_id(region_key), []):
			overlay_sequences[int(sequence_value)] = true
	var sorted_overlay_sequences: Array[int] = []
	for sequence_value in overlay_sequences.keys():
		sorted_overlay_sequences.append(int(sequence_value))
	sorted_overlay_sequences.sort()
	for sequence in sorted_overlay_sequences:
		if seen_sequences.has(sequence) or _excluded_sequences.has(sequence) or not _by_sequence.has(sequence):
			continue
		result.append((_by_sequence[sequence] as Dictionary).duplicate(true))
	return result


func get_persistence_delta() -> Dictionary:
	var append_compatible := _operation_source != null and _excluded_sequences.is_empty()
	var baseline_next := int(_source_storage_metadata.get("next_sequence", 0))
	var baseline_revision := int(_source_storage_metadata.get("ledger_revision", 0))
	if append_compatible:
		if _operations.size() != get_edit_count() - _source_operation_count:
			append_compatible = false
		for index in range(_operations.size()):
			var operation: Dictionary = _operations[index]
			if int(operation["sequence"]) != baseline_next + index \
				or int(operation["revision"]) != baseline_revision + index + 1:
				append_compatible = false
				break
	var overlay: Array[Dictionary] = []
	if append_compatible:
		for operation in _operations:
			overlay.append(operation.duplicate(true))
	return {
		"append_compatible": append_compatible,
		"source": _operation_source,
		"source_metadata": _source_storage_metadata.duplicate(true),
		"overlay_operations": overlay,
		"base_operation_count": _source_operation_count,
	}


func accept_persistence_save(source: RefCounted, metadata: Dictionary) -> bool:
	if source == null or not source.validate_storage_reference(metadata) \
		or int(metadata.get("operation_count", -1)) != get_edit_count() \
		or int(metadata.get("ledger_revision", -1)) != revision \
		or int(metadata.get("next_sequence", -1)) != _next_sequence:
		return false
	_operation_source = source
	_source_storage_metadata = metadata.duplicate(true)
	_source_operation_count = int(metadata.get("operation_count", -1))
	_operations.clear()
	_excluded_sequences.clear()
	_by_region.clear()
	_by_sequence.clear()
	_by_query_region.clear()
	return true


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


func _rebuild_query_index() -> void:
	_by_query_region.clear()
	for operation in _operations:
		_index_overlay_for_queries(operation)


func _index_overlay_for_queries(operation: Dictionary) -> void:
	var center: Vector3 = operation["center_world"]
	var radius := MESHING_NOOP_DISTANCE
	var min_x := floori((center.x - radius) / SPATIAL.REGION_SIZE_X)
	var max_x := floori((center.x + radius) / SPATIAL.REGION_SIZE_X)
	var min_z := floori((center.z - radius) / SPATIAL.REGION_SIZE_Z)
	var max_z := floori((center.z + radius) / SPATIAL.REGION_SIZE_Z)
	for rz in range(min_z, max_z + 1):
		for rx in range(min_x, max_x + 1):
			var region_min := Vector3(float(rx) * SPATIAL.REGION_SIZE_X, GRID.MIN_BOUND.y - MESHING_QUERY_MARGIN, float(rz) * SPATIAL.REGION_SIZE_Z)
			var region_max := Vector3(region_min.x + SPATIAL.REGION_SIZE_X, GRID.MAX_BOUND.y + MESHING_QUERY_MARGIN, region_min.z + SPATIAL.REGION_SIZE_Z)
			var nearest := Vector3(clampf(center.x, region_min.x, region_max.x), clampf(center.y, region_min.y, region_max.y), clampf(center.z, region_min.z, region_max.z))
			if nearest.distance_squared_to(center) <= radius * radius:
				var key := _region_id(Vector2i(rx, rz))
				if not _by_query_region.has(key):
					_by_query_region[key] = []
				(_by_query_region[key] as Array).append(int(operation["sequence"]))


func _all_active_operations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _operation_source != null:
		_operation_source.for_each_operation(func(operation: Dictionary) -> void:
			if not _excluded_sequences.has(int(operation["sequence"])):
				result.append(operation.duplicate(true))
		)
	for operation in _operations:
		result.append(operation.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["sequence"]) < int(b["sequence"]))
	return result


func get_persistence_metadata() -> Dictionary:
	return {
		"world_seed": world_seed,
		"generator_version": generator_version,
		"revision": revision,
		"next_sequence": _next_sequence,
		"operation_count": get_edit_count(),
	}


func get_persistence_page(offset: int, limit: int) -> Array[Dictionary]:
	# Page access is an explicit persistence operation. Source pages are read and
	# released in bounded blocks; only the returned page is materialized.
	var result: Array[Dictionary] = []
	if offset < 0 or limit <= 0:
		return result
	var current := 0
	if _operation_source != null:
		_operation_source.for_each_operation(func(operation: Dictionary) -> void:
			if _excluded_sequences.has(int(operation["sequence"])):
				return
			if current >= offset and result.size() < limit:
				result.append(operation.duplicate(true))
			current += 1
		)
	for operation in _operations:
		if current >= offset and result.size() < limit:
			result.append(operation.duplicate(true))
		current += 1
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["sequence"]) < int(b["sequence"]))
	return result


func for_each_persistence_operation(callback: Callable) -> void:
	last_storage_error = ""
	if _operation_source != null:
		_operation_source.for_each_operation(func(operation: Dictionary) -> void:
			if not _excluded_sequences.has(int(operation["sequence"])):
				callback.call(operation)
		)
		last_storage_error = String(_operation_source.last_read_error)
		if not last_storage_error.is_empty():
			return
	for operation in _operations:
		callback.call(operation)


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
