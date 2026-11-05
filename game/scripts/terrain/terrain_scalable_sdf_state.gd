class_name TerrainScalableSdfState
extends RefCounted

## Experimental scalable edit state.
##
## The hot path is bounded by:
##   materialized chunk tile(s) + the uncheckpointed edit tail.
## Historical operations are archived by TerrainMaterializedSdfStore and are not
## replayed during normal chunk loading.
##
## Materialized values use the current LOD0 lattice (0.5 m). This makes topology
## and edge interpolation exactly reproducible at the gameplay meshing lattice.
## Off-lattice historical density queries (mainly gradient normals) are
## trilinearly reconstructed from the materialized tiles.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

const FORMAT_ID := "procedural-sandbox-materialized-sdf-state"
const FORMAT_VERSION := 1
const MAX_SAFE_SEQUENCE := 9007199254740991
const MATERIALIZED_STEP := Grid.SAMPLE_STEP
const CHECKPOINT_TAIL_TARGET := 128
const MATERIALIZED_NEIGHBOR_RADIUS := 1

var world_seed: int
var generator_version: int
var revision := 0
var last_rejection_reason := ""
var last_storage_error := ""

var _next_sequence := 0
var _lifetime_operation_count := 0
var _archived_operation_count := 0
var _tail_operations: Array[Dictionary] = []
var _dirty_chunks: Dictionary = {}
var _overlay_tiles: Dictionary = {}
var _tile_source: RefCounted
var _source_metadata: Dictionary = {}
var _validator: RefCounted


func _init(seed_value: int = 424242, generator_value: int = Field.GENERATOR_VERSION) -> void:
	world_seed = seed_value
	generator_version = generator_value
	_validator = Brush.new(world_seed, generator_version)


func add_sphere(mode: int, center: Vector3, radius: float) -> bool:
	last_rejection_reason = ""
	last_storage_error = ""
	if _next_sequence >= MAX_SAFE_SEQUENCE:
		last_rejection_reason = "sequence_space_exhausted"
		return false
	var built: Dictionary = _validator._build_operation(
		mode, center, radius, _next_sequence, revision + 1
	)
	if not built.get("valid", false):
		last_rejection_reason = String(built.get("reason", "invalid_operation"))
		return false
	var operation: Dictionary = built["operation"]
	_tail_operations.append(operation)
	_mark_query_influence_dirty(operation)
	_next_sequence += 1
	revision += 1
	_lifetime_operation_count += 1
	return true


func get_edit_count() -> int:
	return _lifetime_operation_count


func get_tail_edit_count() -> int:
	return _tail_operations.size()


func get_archived_edit_count() -> int:
	return _archived_operation_count


func get_next_sequence() -> int:
	return _next_sequence


func get_last_sequence() -> int:
	return _next_sequence - 1


func get_dirty_chunk_count() -> int:
	return _dirty_chunks.size()


func needs_checkpoint(limit: int = CHECKPOINT_TAIL_TARGET) -> bool:
	return _tail_operations.size() >= maxi(1, limit)


func get_persistence_metadata() -> Dictionary:
	return {
		"format": FORMAT_ID,
		"format_version": FORMAT_VERSION,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"revision": revision,
		"next_sequence": _next_sequence,
		"lifetime_operation_count": _lifetime_operation_count,
		"archived_operation_count": _archived_operation_count,
		"tail_operation_count": _tail_operations.size(),
		"dirty_chunk_count": _dirty_chunks.size(),
	}


func get_meshing_snapshot() -> Dictionary:
	# Global snapshots intentionally contain only the bounded live tail. Historical
	# state is spatially materialized and therefore must be queried by chunk.
	var arrays := _operation_arrays(_tail_operations)
	return {
		"valid": true,
		"revision": revision,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"centers": arrays["centers"],
		"radii": arrays["radii"],
		"modes": arrays["modes"],
		"sequences": arrays["sequences"],
		"materialized_tiles": [],
		"candidate_operation_count": _tail_operations.size(),
		"ledger_operation_count": _lifetime_operation_count,
		"scalable_state": true,
	}


func get_meshing_snapshot_for_chunk(region_key: Vector2i, chunk_coordinate: Vector2i) -> Dictionary:
	last_storage_error = ""
	if not Grid.is_valid_coordinate(chunk_coordinate):
		return {
			"valid": false,
			"storage_error": "invalid_chunk_coordinate",
			"revision": revision,
		}
	var tiles_result := _materialized_tiles_for_chunk(region_key, chunk_coordinate)
	if not tiles_result.get("valid", false):
		last_storage_error = String(tiles_result.get("reason", "materialized_tile_read_failed"))
		return {
			"valid": false,
			"storage_error": last_storage_error,
			"revision": revision,
		}
	var candidates: Array[Dictionary] = []
	for operation in _tail_operations:
		if _operation_may_affect_chunk(operation, region_key, chunk_coordinate):
			candidates.append(operation)
	var arrays := _operation_arrays(candidates)
	return {
		"valid": true,
		"revision": revision,
		"world_seed": world_seed,
		"generator_version": generator_version,
		"centers": arrays["centers"],
		"radii": arrays["radii"],
		"modes": arrays["modes"],
		"sequences": arrays["sequences"],
		"materialized_tiles": tiles_result.get("tiles", []),
		"candidate_operation_count": candidates.size(),
		"tail_operation_count": _tail_operations.size(),
		"ledger_operation_count": _lifetime_operation_count,
		"scalable_state": true,
	}


func build_checkpoint_plan() -> Dictionary:
	last_storage_error = ""
	var tile_replacements: Dictionary = {}
	var ordered_ids: Array[String] = []
	for id_value in _dirty_chunks.keys():
		ordered_ids.append(String(id_value))
	ordered_ids.sort()
	for tile_id in ordered_ids:
		var descriptor: Dictionary = _dirty_chunks[tile_id]
		var built := _build_materialized_tile(
			descriptor["region_key"], descriptor["coordinate"]
		)
		if not built.get("valid", false):
			return {
				"valid": false,
				"reason": String(built.get("reason", "tile_materialization_failed")),
				"tile_id": tile_id,
			}
		tile_replacements[tile_id] = built["tile"]
	var journal_records: Array[Dictionary] = []
	for operation in _tail_operations:
		journal_records.append(_journal_record(operation))
	return {
		"valid": true,
		"token_revision": revision,
		"token_next_sequence": _next_sequence,
		"token_tail_count": _tail_operations.size(),
		"world_seed": world_seed,
		"generator_version": generator_version,
		"revision": revision,
		"next_sequence": _next_sequence,
		"lifetime_operation_count": _lifetime_operation_count,
		"archived_operation_count_before": _archived_operation_count,
		"journal_records": journal_records,
		"tile_replacements": tile_replacements,
		"dirty_chunk_count": tile_replacements.size(),
	}


func commit_checkpoint(plan: Dictionary, tile_source: RefCounted, source_metadata: Dictionary) -> bool:
	if not bool(plan.get("valid", false)):
		last_storage_error = "invalid_checkpoint_plan"
		return false
	if int(plan.get("token_revision", -1)) != revision 		or int(plan.get("token_next_sequence", -1)) != _next_sequence 		or int(plan.get("token_tail_count", -1)) != _tail_operations.size():
		last_storage_error = "checkpoint_plan_stale"
		return false
	_tile_source = tile_source
	_source_metadata = source_metadata.duplicate(true)
	_archived_operation_count = _lifetime_operation_count
	_tail_operations.clear()
	_dirty_chunks.clear()
	_overlay_tiles.clear()
	last_storage_error = ""
	return true


func restore_hot_reference(tile_source: RefCounted, metadata: Dictionary) -> bool:
	last_storage_error = ""
	if revision != 0 or _next_sequence != 0 or _lifetime_operation_count != 0 		or not _tail_operations.is_empty() or not _dirty_chunks.is_empty():
		last_storage_error = "restore_target_not_pristine"
		return false
	if int(metadata.get("world_seed", world_seed)) != world_seed 		or int(metadata.get("generator_version", generator_version)) != generator_version:
		last_storage_error = "restore_world_identity_mismatch"
		return false
	var restored_revision := int(metadata.get("revision", -1))
	var restored_next := int(metadata.get("next_sequence", -1))
	var restored_count := int(metadata.get("lifetime_operation_count", -1))
	var restored_archived := int(metadata.get("archived_operation_count", restored_count))
	if restored_revision < 0 or restored_next < 0 or restored_count < 0 		or restored_archived < 0 or restored_archived > restored_count 		or restored_next > MAX_SAFE_SEQUENCE:
		last_storage_error = "restore_metadata_invalid"
		return false
	revision = restored_revision
	_next_sequence = restored_next
	_lifetime_operation_count = restored_count
	_archived_operation_count = restored_archived
	_tile_source = tile_source
	_source_metadata = metadata.duplicate(true)
	return true


func clear_for_region(_region_key: Vector2i) -> Dictionary:
	# Deletion of already-materialized history requires a region reset/tombstone
	# transaction and is deliberately not part of this scalability candidate.
	return {
		"removed_count": 0,
		"rebuild_regions": [],
		"error": "materialized_history_clear_not_supported",
	}


func clear() -> void:
	last_rejection_reason = "materialized_world_reset_requires_store_transaction"


func _build_materialized_tile(region_key: Vector2i, coordinate: Vector2i) -> Dictionary:
	var current_result := _get_materialized_tile(region_key, coordinate)
	if not current_result.get("ok", false):
		return {
			"valid": false,
			"reason": String(current_result.get("reason", "tile_source_failure")),
		}
	var previous_values := PackedFloat64Array()
	if current_result.get("found", false):
		var current_tile: Dictionary = current_result["tile"]
		var current_values: Variant = current_tile.get("values", PackedFloat64Array())
		if typeof(current_values) == TYPE_PACKED_FLOAT64_ARRAY:
			previous_values = current_values
		elif typeof(current_values) == TYPE_PACKED_FLOAT32_ARRAY:
			previous_values.resize(current_values.size())
			for value_index in range(current_values.size()):
				previous_values[value_index] = float(current_values[value_index])
		else:
			return {"valid": false, "reason": "materialized_tile_values_invalid"}

	var candidates: Array[Dictionary] = []
	for operation in _tail_operations:
		if _operation_may_affect_chunk(operation, region_key, coordinate):
			candidates.append(operation)

	var region_origin := Spatial.region_origin_world(region_key)
	var local_origin := Grid.origin_for(coordinate)
	var world_origin := region_origin + Vector3(local_origin.x, Grid.MIN_BOUND.y, local_origin.z)
	var dims := Vector3i(
		Grid.CELLS_PER_CHUNK_X + 1,
		Grid.CELL_COUNT_Y + 1,
		Grid.CELLS_PER_CHUNK_Z + 1
	)
	var expected_count := dims.x * dims.y * dims.z
	if not previous_values.is_empty() and previous_values.size() != expected_count:
		return {"valid": false, "reason": "materialized_tile_shape_mismatch"}

	# Preserve the selected CSG operand in float64 across checkpoints. Ordered
	# min/max brush evaluation never combines the previous density arithmetically;
	# it selects either the prior density or the current sphere threshold. Keeping
	# that selected value in float64 prevents checkpoint-by-checkpoint rounding
	# from changing later min/max decisions.
	var values := PackedFloat64Array()
	values.resize(expected_count)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var value_index := _tile_index(x, y, z, dims)
				var world_point := world_origin + Vector3(x, y, z) * MATERIALIZED_STEP
				var density: float
				if previous_values.is_empty():
					var mapped: Dictionary = Spatial.world_to_region_local(world_point)
					if not mapped.get("valid", false):
						return {"valid": false, "reason": "materialized_sample_mapping_failed"}
					density = Field.sample_density(
						world_seed, mapped["region_key"], mapped["local_position"], false
					)
				else:
					density = float(previous_values[value_index])
				for operation in candidates:
					var center: Vector3 = operation["center_world"]
					var threshold := world_point.distance_to(center) - float(operation["radius"])
					if int(operation["mode"]) == Brush.Mode.CARVE:
						density = minf(density, threshold)
					else:
						density = maxf(density, -threshold)
				if not is_finite(density):
					return {"valid": false, "reason": "materialized_sample_non_finite"}
				values[value_index] = density

	var tile_id := Grid.stable_id(region_key, coordinate)
	return {
		"valid": true,
		"tile": {
			"format": "materialized-sdf-tile",
			"format_version": 1,
			"tile_id": tile_id,
			"region_key": region_key,
			"coordinate": coordinate,
			"origin_world": world_origin,
			"dims": dims,
			"step": MATERIALIZED_STEP,
			"base_revision": revision,
			"base_sequence": _next_sequence - 1,
			"values": values,
		},
	}


func _materialized_tiles_for_chunk(region_key: Vector2i, coordinate: Vector2i) -> Dictionary:
	var center_global := _global_chunk(region_key, coordinate)
	var tiles: Array[Dictionary] = []
	var seen: Dictionary = {}
	for dz in range(-MATERIALIZED_NEIGHBOR_RADIUS, MATERIALIZED_NEIGHBOR_RADIUS + 1):
		for dx in range(-MATERIALIZED_NEIGHBOR_RADIUS, MATERIALIZED_NEIGHBOR_RADIUS + 1):
			var mapped := _region_chunk_from_global(center_global + Vector2i(dx, dz))
			var neighbor_region: Vector2i = mapped["region_key"]
			var neighbor_coordinate: Vector2i = mapped["coordinate"]
			var tile_id := Grid.stable_id(neighbor_region, neighbor_coordinate)
			if seen.has(tile_id):
				continue
			seen[tile_id] = true
			var tile_result := _get_materialized_tile(neighbor_region, neighbor_coordinate)
			if not tile_result.get("ok", false):
				return {
					"valid": false,
					"reason": String(tile_result.get("reason", "tile_source_failure")),
				}
			if tile_result.get("found", false):
				tiles.append(tile_result["tile"])
	return {"valid": true, "tiles": tiles}


func _get_materialized_tile(region_key: Vector2i, coordinate: Vector2i) -> Dictionary:
	var tile_id := Grid.stable_id(region_key, coordinate)
	if _overlay_tiles.has(tile_id):
		return {"ok": true, "found": true, "tile": _overlay_tiles[tile_id]}
	if _tile_source == null:
		return {"ok": true, "found": false}
	if not _tile_source.has_method("get_materialized_tile"):
		return {"ok": false, "found": false, "reason": "tile_source_api_missing"}
	var result: Dictionary = _tile_source.get_materialized_tile(region_key, coordinate)
	if not result.get("ok", false):
		return result
	return result


func _mark_query_influence_dirty(operation: Dictionary) -> void:
	var center: Vector3 = operation["center_world"]
	var radius := Brush.MESHING_NOOP_DISTANCE
	var chunk_size_x := float(Grid.CELLS_PER_CHUNK_X) * Grid.SAMPLE_STEP
	var chunk_size_z := float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
	var min_gx := floori((center.x - radius) / chunk_size_x)
	var max_gx := floori((center.x + radius) / chunk_size_x)
	var min_gz := floori((center.z - radius) / chunk_size_z)
	var max_gz := floori((center.z + radius) / chunk_size_z)
	for gz in range(min_gz, max_gz + 1):
		for gx in range(min_gx, max_gx + 1):
			var mapped := _region_chunk_from_global(Vector2i(gx, gz))
			var region_key: Vector2i = mapped["region_key"]
			var coordinate: Vector2i = mapped["coordinate"]
			if not _operation_may_affect_chunk(operation, region_key, coordinate):
				continue
			var tile_id := Grid.stable_id(region_key, coordinate)
			_dirty_chunks[tile_id] = {
				"region_key": region_key,
				"coordinate": coordinate,
			}


func _operation_may_affect_chunk(
	operation: Dictionary,
	region_key: Vector2i,
	coordinate: Vector2i
) -> bool:
	if not Grid.is_valid_coordinate(coordinate):
		return false
	var center: Vector3 = operation["center_world"]
	var region_origin := Spatial.region_origin_world(region_key)
	var chunk_origin := region_origin + Grid.origin_for(coordinate)
	var chunk_size := Grid.size_for(coordinate)
	var margin := Brush.MESHING_QUERY_MARGIN
	var chunk_min := Vector3(
		chunk_origin.x - margin,
		Grid.MIN_BOUND.y - margin,
		chunk_origin.z - margin
	)
	var chunk_max := Vector3(
		chunk_origin.x + chunk_size.x + margin,
		Grid.MAX_BOUND.y + margin,
		chunk_origin.z + chunk_size.z + margin
	)
	var nearest := Vector3(
		clampf(center.x, chunk_min.x, chunk_max.x),
		clampf(center.y, chunk_min.y, chunk_max.y),
		clampf(center.z, chunk_min.z, chunk_max.z)
	)
	return nearest.distance_squared_to(center) 		<= Brush.MESHING_NOOP_DISTANCE * Brush.MESHING_NOOP_DISTANCE


func _operation_arrays(operations: Array[Dictionary]) -> Dictionary:
	var centers := PackedVector3Array()
	var radii := PackedFloat64Array()
	var modes := PackedByteArray()
	var sequences := PackedInt64Array()
	for operation in operations:
		centers.append(operation["center_world"])
		radii.append(float(operation["radius"]))
		modes.append(int(operation["mode"]))
		sequences.append(int(operation["sequence"]))
	return {
		"centers": centers,
		"radii": radii,
		"modes": modes,
		"sequences": sequences,
	}


func _journal_record(operation: Dictionary) -> Dictionary:
	var center: Vector3 = operation["center_world"]
	return {
		"sequence": int(operation["sequence"]),
		"revision": int(operation["revision"]),
		"mode": int(operation["mode"]),
		"center": [center.x, center.y, center.z],
		"radius": float(operation["radius"]),
	}


func _global_chunk(region_key: Vector2i, coordinate: Vector2i) -> Vector2i:
	return Vector2i(
		region_key.x * Grid.CHUNK_COUNT_X + coordinate.x,
		region_key.y * Grid.CHUNK_COUNT_Z + coordinate.y
	)


func _region_chunk_from_global(global_chunk: Vector2i) -> Dictionary:
	var region_x := floori(float(global_chunk.x) / float(Grid.CHUNK_COUNT_X))
	var region_z := floori(float(global_chunk.y) / float(Grid.CHUNK_COUNT_Z))
	var local_x := posmod(global_chunk.x, Grid.CHUNK_COUNT_X)
	var local_z := posmod(global_chunk.y, Grid.CHUNK_COUNT_Z)
	return {
		"region_key": Vector2i(region_x, region_z),
		"coordinate": Vector2i(local_x, local_z),
	}


func _tile_index(x: int, y: int, z: int, dims: Vector3i) -> int:
	return (y * dims.z + z) * dims.x + x
