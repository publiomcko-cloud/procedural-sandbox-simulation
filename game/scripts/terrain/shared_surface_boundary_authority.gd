class_name SharedSurfaceBoundaryAuthority
extends RefCounted

## Experimental production candidate for region-boundary ownership.
## A pair of adjacent edge chunks is polygonized from one canonical world-space
## SDF sample volume and one global lattice-edge root cache, then partitioned
## back into the two existing region/chunk publication units.
##
## The service owns no scene nodes and mutates no ledger state.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

const EPS := 0.000001
const ROOT_QUANT := 1000000.0

const CORNERS := [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1),
]
const TETS := [
	[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
	[0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6],
]


# P1: bounded cross-revision state for append-only shared-volume rebuilds.
# Cached state is immutable after publication. A new revision reuses it only
# when the materialized base is unchanged and the candidate operation stream
# is an exact prefix extension; every other transition falls back to a full build.
const MAX_INCREMENTAL_STATES := 32
static var _incremental_mutex := Mutex.new()
static var _incremental_states: Dictionary = {}
static var _incremental_order: Array[String] = []


static func make_x_pair_snapshot(
	ledger: RefCounted,
	left_region_key: Vector2i,
	z_chunk: int
) -> Dictionary:
	if ledger == null or z_chunk < 0 or z_chunk >= Grid.CHUNK_COUNT_Z:
		return {"valid": false, "reason": "invalid_pair_snapshot_request"}
	var left_coordinate := Vector2i(Grid.CHUNK_COUNT_X - 1, z_chunk)
	var right_region_key := left_region_key + Vector2i.RIGHT
	var right_coordinate := Vector2i(0, z_chunk)
	var left_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(left_region_key, left_coordinate)
	var right_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(right_region_key, right_coordinate)
	if not bool(left_snapshot.get("valid", false)):
		return {"valid": false, "reason": "left_snapshot_failed", "detail": left_snapshot}
	if not bool(right_snapshot.get("valid", false)):
		return {"valid": false, "reason": "right_snapshot_failed", "detail": right_snapshot}

	var by_sequence: Dictionary = {}
	var materialized_by_id: Dictionary = {}
	for snapshot_value in [left_snapshot, right_snapshot]:
		var snapshot: Dictionary = snapshot_value
		var centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
		var radii: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
		var modes: PackedByteArray = snapshot.get("modes", PackedByteArray())
		var sequences_value: Variant = snapshot.get("sequences", PackedInt32Array())
		if typeof(sequences_value) != TYPE_PACKED_INT32_ARRAY 			and typeof(sequences_value) != TYPE_PACKED_INT64_ARRAY:
			return {"valid": false, "reason": "pair_snapshot_sequence_type_invalid"}
		if centers.size() != radii.size() or centers.size() != modes.size() 			or centers.size() != sequences_value.size():
			return {"valid": false, "reason": "pair_snapshot_attribute_mismatch"}
		for index in range(centers.size()):
			var sequence := int(sequences_value[index])
			var row := {
				"center": centers[index],
				"radius": float(radii[index]),
				"mode": int(modes[index]),
			}
			if by_sequence.has(sequence):
				var existing: Dictionary = by_sequence[sequence]
				if existing["center"] != row["center"] 					or float(existing["radius"]) != float(row["radius"]) 					or int(existing["mode"]) != int(row["mode"]):
					return {
						"valid": false,
						"reason": "pair_snapshot_sequence_conflict",
						"sequence": sequence,
					}
			else:
				by_sequence[sequence] = row
		var tiles_value: Variant = snapshot.get("materialized_tiles", [])
		if typeof(tiles_value) == TYPE_ARRAY:
			for tile_value in tiles_value:
				if typeof(tile_value) != TYPE_DICTIONARY:
					continue
				var tile: Dictionary = tile_value
				var tile_id := String(tile.get("tile_id", ""))
				if tile_id.is_empty():
					continue
				if not materialized_by_id.has(tile_id):
					materialized_by_id[tile_id] = tile

	var ordered_sequences: Array[int] = []
	for sequence_value in by_sequence.keys():
		ordered_sequences.append(int(sequence_value))
	ordered_sequences.sort()
	var centers := PackedVector3Array()
	var radii := PackedFloat64Array()
	var modes := PackedByteArray()
	var sequences := PackedInt64Array()
	for sequence in ordered_sequences:
		var row: Dictionary = by_sequence[sequence]
		centers.append(row["center"])
		radii.append(float(row["radius"]))
		modes.append(int(row["mode"]))
		sequences.append(sequence)
	var tile_ids: Array[String] = []
	for tile_id_value in materialized_by_id.keys():
		tile_ids.append(String(tile_id_value))
	tile_ids.sort()
	var materialized_tiles: Array[Dictionary] = []
	for tile_id in tile_ids:
		materialized_tiles.append(materialized_by_id[tile_id])
	return {
		"valid": true,
		"revision": int(ledger.revision),
		"cache_scope_id": int(ledger.get_instance_id()),
		"world_seed": int(ledger.world_seed),
		"generator_version": int(ledger.generator_version),
		"centers": centers,
		"radii": radii,
		"modes": modes,
		"sequences": sequences,
		"materialized_tiles": materialized_tiles,
		"materialized_tile_index": Brush.build_materialized_tile_index(materialized_tiles),
		"candidate_operation_count": centers.size(),
		"ledger_operation_count": int(ledger.get_edit_count()),
	}


static func make_z_pair_snapshot(
	ledger: RefCounted,
	low_z_region_key: Vector2i,
	x_chunk: int
) -> Dictionary:
	if ledger == null or x_chunk < 0 or x_chunk >= Grid.CHUNK_COUNT_X:
		return {"valid": false, "reason": "invalid_z_pair_snapshot_request"}
	return _merge_snapshot_requests(ledger, [
		{"region_key": low_z_region_key, "coordinate": Vector2i(x_chunk, Grid.CHUNK_COUNT_Z - 1)},
		{"region_key": low_z_region_key + Vector2i(0, 1), "coordinate": Vector2i(x_chunk, 0)},
	])


static func make_xz_corner_snapshot(
	ledger: RefCounted,
	min_region_key: Vector2i
) -> Dictionary:
	if ledger == null:
		return {"valid": false, "reason": "invalid_corner_snapshot_request"}
	return _merge_snapshot_requests(ledger, [
		{"region_key": min_region_key, "coordinate": Vector2i(Grid.CHUNK_COUNT_X - 1, Grid.CHUNK_COUNT_Z - 1)},
		{"region_key": min_region_key + Vector2i(1, 0), "coordinate": Vector2i(0, Grid.CHUNK_COUNT_Z - 1)},
		{"region_key": min_region_key + Vector2i(0, 1), "coordinate": Vector2i(Grid.CHUNK_COUNT_X - 1, 0)},
		{"region_key": min_region_key + Vector2i(1, 1), "coordinate": Vector2i(0, 0)},
	])


static func _merge_snapshot_requests(ledger: RefCounted, requests: Array) -> Dictionary:
	var by_sequence: Dictionary = {}
	var materialized_by_id: Dictionary = {}
	for request_value in requests:
		if typeof(request_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "snapshot_request_invalid"}
		var request: Dictionary = request_value
		var snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(
			request["region_key"], request["coordinate"]
		)
		if not bool(snapshot.get("valid", false)):
			return {
				"valid": false,
				"reason": "snapshot_source_failed",
				"request": request,
				"detail": snapshot,
			}
		var centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
		var radii: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
		var modes: PackedByteArray = snapshot.get("modes", PackedByteArray())
		var sequences_value: Variant = snapshot.get("sequences", PackedInt32Array())
		if typeof(sequences_value) != TYPE_PACKED_INT32_ARRAY \
			and typeof(sequences_value) != TYPE_PACKED_INT64_ARRAY:
			return {"valid": false, "reason": "snapshot_sequence_type_invalid"}
		if centers.size() != radii.size() or centers.size() != modes.size() \
			or centers.size() != sequences_value.size():
			return {"valid": false, "reason": "snapshot_attribute_mismatch"}
		for index in range(centers.size()):
			var sequence := int(sequences_value[index])
			var row := {
				"center": centers[index],
				"radius": float(radii[index]),
				"mode": int(modes[index]),
			}
			if by_sequence.has(sequence):
				var existing: Dictionary = by_sequence[sequence]
				if existing["center"] != row["center"] \
					or float(existing["radius"]) != float(row["radius"]) \
					or int(existing["mode"]) != int(row["mode"]):
					return {
						"valid": false,
						"reason": "snapshot_sequence_conflict",
						"sequence": sequence,
					}
			else:
				by_sequence[sequence] = row
		var tiles_value: Variant = snapshot.get("materialized_tiles", [])
		if typeof(tiles_value) == TYPE_ARRAY:
			for tile_value in tiles_value:
				if typeof(tile_value) != TYPE_DICTIONARY:
					continue
				var tile: Dictionary = tile_value
				var tile_id := String(tile.get("tile_id", ""))
				if not tile_id.is_empty() and not materialized_by_id.has(tile_id):
					materialized_by_id[tile_id] = tile

	var ordered_sequences: Array[int] = []
	for sequence_value in by_sequence.keys():
		ordered_sequences.append(int(sequence_value))
	ordered_sequences.sort()
	var centers := PackedVector3Array()
	var radii := PackedFloat64Array()
	var modes := PackedByteArray()
	var sequences := PackedInt64Array()
	for sequence in ordered_sequences:
		var row: Dictionary = by_sequence[sequence]
		centers.append(row["center"])
		radii.append(float(row["radius"]))
		modes.append(int(row["mode"]))
		sequences.append(sequence)
	var tile_ids: Array[String] = []
	for tile_id_value in materialized_by_id.keys():
		tile_ids.append(String(tile_id_value))
	tile_ids.sort()
	var materialized_tiles: Array[Dictionary] = []
	for tile_id in tile_ids:
		materialized_tiles.append(materialized_by_id[tile_id])
	return {
		"valid": true,
		"revision": int(ledger.revision),
		"cache_scope_id": int(ledger.get_instance_id()),
		"world_seed": int(ledger.world_seed),
		"generator_version": int(ledger.generator_version),
		"centers": centers,
		"radii": radii,
		"modes": modes,
		"sequences": sequences,
		"materialized_tiles": materialized_tiles,
		"materialized_tile_index": Brush.build_materialized_tile_index(materialized_tiles),
		"candidate_operation_count": centers.size(),
		"ledger_operation_count": int(ledger.get_edit_count()),
	}


static func build_x_region_boundary_pair(
	world_seed: int,
	left_region_key: Vector2i,
	z_chunk: int,
	brush_snapshot: Dictionary,
	diagnostics_enabled: bool = true
) -> Dictionary:
	if z_chunk < 0 or z_chunk >= Grid.CHUNK_COUNT_Z:
		return {"valid": false, "reason": "invalid_z_chunk"}
	var right_region_key := left_region_key + Vector2i.RIGHT
	var left_coordinate := Vector2i(Grid.CHUNK_COUNT_X - 1, z_chunk)
	var right_coordinate := Vector2i(0, z_chunk)
	var left_origin := Spatial.region_origin_world(left_region_key) + Grid.origin_for(left_coordinate)
	var right_origin := Spatial.region_origin_world(right_region_key) + Grid.origin_for(right_coordinate)
	var seam_x := right_origin.x
	var cells := Vector3i(Grid.CELLS_PER_CHUNK_X * 2, Grid.CELL_COUNT_Y, Grid.CELLS_PER_CHUNK_Z)
	var roi_min := Vector3(left_origin.x, Grid.MIN_BOUND.y, left_origin.z)
	var built := build_x_shared_volume(world_seed, brush_snapshot, roi_min, cells, Grid.SAMPLE_STEP, seam_x, diagnostics_enabled)
	if not built.get("valid", false):
		return built

	var left_positions := PackedVector3Array()
	var left_normals := PackedVector3Array()
	var right_positions := PackedVector3Array()
	var right_normals := PackedVector3Array()
	for triangle_value in built.get("triangles", []):
		var triangle: Dictionary = triangle_value
		var points: Array = triangle["points"]
		var normal: Vector3 = triangle["normal"]
		var side := String(triangle["side"])
		for point_value in points:
			var point: Vector3 = point_value
			if side == "left":
				left_positions.append(point - left_origin)
				left_normals.append(normal)
			else:
				right_positions.append(point - right_origin)
				right_normals.append(normal)

	var shared_timings: Dictionary = (built.get("timings_usec", {}) as Dictionary).duplicate(true)
	var shared_work_counters: Dictionary = (built.get("work_counters", {}) as Dictionary).duplicate(true)
	var common := {
		"ledger_revision": int(brush_snapshot.get("revision", 0)),
		"world_seed": world_seed,
		"generator_version": Field.GENERATOR_VERSION,
		"lod_level": 0,
		"boundary_authority": "shared_surface_x_pair_v1",
		"seam_x": seam_x,
		"shared_mesh_signature": String(built.get("mesh_signature", "")),
		"timings_usec": shared_timings,
		"work_counters": shared_work_counters,
	}
	var left_cpu := common.duplicate(true)
	left_cpu.merge({
		"valid": true,
		"region_key": left_region_key,
		"coordinate": left_coordinate,
		"positions": left_positions,
		"normals": left_normals,
		"vertex_count": left_positions.size(),
		"triangle_count": left_positions.size() / 3,
		"sample_count": int(built.get("sample_count", 0)),
	}, true)
	var right_cpu := common.duplicate(true)
	right_cpu.merge({
		"valid": true,
		"region_key": right_region_key,
		"coordinate": right_coordinate,
		"positions": right_positions,
		"normals": right_normals,
		"vertex_count": right_positions.size(),
		"triangle_count": right_positions.size() / 3,
		"sample_count": int(built.get("sample_count", 0)),
	}, true)
	return {
		"valid": true,
		"left": left_cpu,
		"right": right_cpu,
		"diagnostics": built.get("diagnostics", {}),
		"mesh_signature": built.get("mesh_signature", ""),
		"seam_x": seam_x,
		"z_chunk": z_chunk,
	}


static func build_z_region_boundary_pair(
	world_seed: int,
	low_z_region_key: Vector2i,
	x_chunk: int,
	brush_snapshot: Dictionary,
	diagnostics_enabled: bool = true
) -> Dictionary:
	if x_chunk < 0 or x_chunk >= Grid.CHUNK_COUNT_X:
		return {"valid": false, "reason": "invalid_x_chunk"}
	var high_z_region_key := low_z_region_key + Vector2i(0, 1)
	var low_coordinate := Vector2i(x_chunk, Grid.CHUNK_COUNT_Z - 1)
	var high_coordinate := Vector2i(x_chunk, 0)
	var low_origin := Spatial.region_origin_world(low_z_region_key) + Grid.origin_for(low_coordinate)
	var high_origin := Spatial.region_origin_world(high_z_region_key) + Grid.origin_for(high_coordinate)
	var seam_z := high_origin.z
	var cells := Vector3i(Grid.CELLS_PER_CHUNK_X, Grid.CELL_COUNT_Y, Grid.CELLS_PER_CHUNK_Z * 2)
	var roi_min := Vector3(low_origin.x, Grid.MIN_BOUND.y, low_origin.z)
	var built := build_z_shared_volume(world_seed, brush_snapshot, roi_min, cells, Grid.SAMPLE_STEP, seam_z, diagnostics_enabled)
	if not built.get("valid", false):
		return built

	var low_positions := PackedVector3Array()
	var low_normals := PackedVector3Array()
	var high_positions := PackedVector3Array()
	var high_normals := PackedVector3Array()
	for triangle_value in built.get("triangles", []):
		var triangle: Dictionary = triangle_value
		var points: Array = triangle["points"]
		var normal: Vector3 = triangle["normal"]
		var side := String(triangle["side"])
		for point_value in points:
			var point: Vector3 = point_value
			if side == "low":
				low_positions.append(point - low_origin)
				low_normals.append(normal)
			else:
				high_positions.append(point - high_origin)
				high_normals.append(normal)

	var shared_timings: Dictionary = (built.get("timings_usec", {}) as Dictionary).duplicate(true)
	var shared_work_counters: Dictionary = (built.get("work_counters", {}) as Dictionary).duplicate(true)
	var common := {
		"ledger_revision": int(brush_snapshot.get("revision", 0)),
		"world_seed": world_seed,
		"generator_version": Field.GENERATOR_VERSION,
		"lod_level": 0,
		"boundary_authority": "shared_surface_z_pair_v1",
		"seam_z": seam_z,
		"shared_mesh_signature": String(built.get("mesh_signature", "")),
		"timings_usec": shared_timings,
		"work_counters": shared_work_counters,
	}
	var low_cpu := common.duplicate(true)
	low_cpu.merge({
		"valid": true,
		"region_key": low_z_region_key,
		"coordinate": low_coordinate,
		"positions": low_positions,
		"normals": low_normals,
		"vertex_count": low_positions.size(),
		"triangle_count": low_positions.size() / 3,
		"sample_count": int(built.get("sample_count", 0)),
	}, true)
	var high_cpu := common.duplicate(true)
	high_cpu.merge({
		"valid": true,
		"region_key": high_z_region_key,
		"coordinate": high_coordinate,
		"positions": high_positions,
		"normals": high_normals,
		"vertex_count": high_positions.size(),
		"triangle_count": high_positions.size() / 3,
		"sample_count": int(built.get("sample_count", 0)),
	}, true)
	return {
		"valid": true,
		"low": low_cpu,
		"high": high_cpu,
		"diagnostics": built.get("diagnostics", {}),
		"mesh_signature": built.get("mesh_signature", ""),
		"seam_z": seam_z,
		"x_chunk": x_chunk,
	}


static func build_xz_corner_quad(
	world_seed: int,
	min_region_key: Vector2i,
	brush_snapshot: Dictionary,
	diagnostics_enabled: bool = true
) -> Dictionary:
	var authority_started_usec := Time.get_ticks_usec()
	var regions := {
		"minx_minz": min_region_key,
		"maxx_minz": min_region_key + Vector2i(1, 0),
		"minx_maxz": min_region_key + Vector2i(0, 1),
		"maxx_maxz": min_region_key + Vector2i(1, 1),
	}
	var coordinates := {
		"minx_minz": Vector2i(Grid.CHUNK_COUNT_X - 1, Grid.CHUNK_COUNT_Z - 1),
		"maxx_minz": Vector2i(0, Grid.CHUNK_COUNT_Z - 1),
		"minx_maxz": Vector2i(Grid.CHUNK_COUNT_X - 1, 0),
		"maxx_maxz": Vector2i(0, 0),
	}
	var origins: Dictionary = {}
	for owner in regions.keys():
		origins[owner] = Spatial.region_origin_world(regions[owner]) + Grid.origin_for(coordinates[owner])
	var roi_min: Vector3 = origins["minx_minz"]
	roi_min.y = Grid.MIN_BOUND.y
	var seam_x: float = (origins["maxx_minz"] as Vector3).x
	var seam_z: float = (origins["minx_maxz"] as Vector3).z
	var cells := Vector3i(
		Grid.CELLS_PER_CHUNK_X * 2,
		Grid.CELL_COUNT_Y,
		Grid.CELLS_PER_CHUNK_Z * 2
	)
	var built := build_xz_corner_volume(
		world_seed, brush_snapshot, roi_min, cells, Grid.SAMPLE_STEP, seam_x, seam_z,
		diagnostics_enabled
	)
	if not built.get("valid", false):
		return built

	var partition_started_usec := Time.get_ticks_usec()
	var positions_by_owner: Dictionary = {}
	var normals_by_owner: Dictionary = {}
	for owner in regions.keys():
		positions_by_owner[owner] = PackedVector3Array()
		normals_by_owner[owner] = PackedVector3Array()
	for triangle_value in built.get("triangles", []):
		var triangle: Dictionary = triangle_value
		var owner := String(triangle["owner"])
		var positions: PackedVector3Array = positions_by_owner[owner]
		var normals: PackedVector3Array = normals_by_owner[owner]
		for point_value in triangle["points"]:
			positions.append((point_value as Vector3) - (origins[owner] as Vector3))
			normals.append(triangle["normal"])
		positions_by_owner[owner] = positions
		normals_by_owner[owner] = normals

	var partition_elapsed_usec := Time.get_ticks_usec() - partition_started_usec
	var shared_timings: Dictionary = (built.get("timings_usec", {}) as Dictionary).duplicate(true)
	shared_timings["shared_partition"] = partition_elapsed_usec
	shared_timings["shared_authority_total"] = Time.get_ticks_usec() - authority_started_usec
	var shared_work_counters: Dictionary = (built.get("work_counters", {}) as Dictionary).duplicate(true)
	var result := {
		"valid": true,
		"diagnostics": built.get("diagnostics", {}),
		"mesh_signature": built.get("mesh_signature", ""),
		"seam_x": seam_x,
		"seam_z": seam_z,
		"min_region_key": min_region_key,
	}
	for owner in regions.keys():
		var positions: PackedVector3Array = positions_by_owner[owner]
		result[owner] = {
			"valid": true,
			"ledger_revision": int(brush_snapshot.get("revision", 0)),
			"world_seed": world_seed,
			"generator_version": Field.GENERATOR_VERSION,
			"lod_level": 0,
			"boundary_authority": "shared_surface_xz_corner_v1",
			"shared_mesh_signature": String(built.get("mesh_signature", "")),
			"region_key": regions[owner],
			"coordinate": coordinates[owner],
			"positions": positions,
			"normals": normals_by_owner[owner],
			"vertex_count": positions.size(),
			"triangle_count": positions.size() / 3,
			"sample_count": int(built.get("sample_count", 0)),
			"timings_usec": shared_timings.duplicate(true),
			"work_counters": shared_work_counters.duplicate(true),
		}
	return result


static func build_z_shared_volume(
	world_seed: int,
	brush_snapshot: Dictionary,
	roi_min: Vector3,
	cells: Vector3i,
	step: float,
	seam_z: float,
	diagnostics_enabled: bool = true
) -> Dictionary:
	return _build_shared_volume(
		"z", world_seed, brush_snapshot, roi_min, cells, step,
		0.0, seam_z, diagnostics_enabled
	)


static func build_xz_corner_volume(
	world_seed: int,
	brush_snapshot: Dictionary,
	roi_min: Vector3,
	cells: Vector3i,
	step: float,
	seam_x: float,
	seam_z: float,
	diagnostics_enabled: bool = true
) -> Dictionary:
	return _build_shared_volume(
		"corner", world_seed, brush_snapshot, roi_min, cells, step,
		seam_x, seam_z, diagnostics_enabled
	)


static func build_x_shared_volume(
	world_seed: int,
	brush_snapshot: Dictionary,
	roi_min: Vector3,
	cells: Vector3i,
	step: float,
	seam_x: float,
	diagnostics_enabled: bool = true
) -> Dictionary:
	return _build_shared_volume(
		"x", world_seed, brush_snapshot, roi_min, cells, step,
		seam_x, 0.0, diagnostics_enabled
	)


static func clear_incremental_cache() -> void:
	_incremental_mutex.lock()
	_incremental_states.clear()
	_incremental_order.clear()
	_incremental_mutex.unlock()


static func incremental_cache_count() -> int:
	_incremental_mutex.lock()
	var count := _incremental_states.size()
	_incremental_mutex.unlock()
	return count


static func _build_shared_volume(
	kind: String,
	world_seed: int,
	brush_snapshot: Dictionary,
	roi_min: Vector3,
	cells: Vector3i,
	step: float,
	seam_x: float,
	seam_z: float,
	diagnostics_enabled: bool
) -> Dictionary:
	var total_started_usec := Time.get_ticks_usec()
	if cells.x <= 0 or cells.y <= 0 or cells.z <= 0 or not is_finite(step) or step <= 0.0:
		return {"valid": false, "reason": "invalid_volume_shape"}
	var roi_max := roi_min + Vector3(cells) * step
	if kind == "x":
		if seam_x <= roi_min.x + EPS or seam_x >= roi_max.x - EPS:
			return {"valid": false, "reason": "seam_outside_volume"}
	elif kind == "z":
		if seam_z <= roi_min.z + EPS or seam_z >= roi_max.z - EPS:
			return {"valid": false, "reason": "seam_outside_volume"}
	elif kind == "corner":
		if seam_x <= roi_min.x + EPS or seam_x >= roi_max.x - EPS \
			or seam_z <= roi_min.z + EPS or seam_z >= roi_max.z - EPS:
			return {"valid": false, "reason": "corner_seam_outside_volume"}
	else:
		return {"valid": false, "reason": "invalid_shared_volume_kind"}

	var dims := cells + Vector3i.ONE
	var cache_key := _incremental_scope_key(
		kind, world_seed, brush_snapshot, roi_min, cells, step, seam_x, seam_z
	)
	var sampling_started_usec := Time.get_ticks_usec()
	var prepared := _prepare_incremental_volume(
		cache_key, world_seed, brush_snapshot, roi_min, cells, dims, step
	)
	var sampling_elapsed_usec := Time.get_ticks_usec() - sampling_started_usec
	if not prepared.get("valid", false):
		return prepared

	var values: PackedFloat32Array = prepared["values"]
	var exact_values: PackedFloat64Array = prepared["exact_values"]
	var dirty_flags: PackedByteArray = prepared["dirty_flags"]
	var cell_mixed: PackedByteArray = prepared["cell_mixed"]
	var cell_dropped: PackedInt32Array = prepared["cell_dropped"]
	var cell_triangles: Dictionary = prepared["cell_triangles"]
	var cache_hit := bool(prepared.get("cache_hit", false))
	var dirty_cell_count := int(prepared.get("dirty_cell_count", cells.x * cells.y * cells.z))
	var applied_operation_count := int(prepared.get("applied_operation_count", 0))
	var mixed_cell_count := int(prepared.get("mixed_cell_count", 0))
	var uniform_cell_count := int(prepared.get("uniform_cell_count", 0))
	var total_cell_count := cells.x * cells.y * cells.z

	# If appended operations do not change a single float32 lattice sample, the
	# exact previous geometry remains authoritative. Preserve the new exact SDF
	# state for future appends but avoid polygonization, dedup and signatures.
	if cache_hit and dirty_cell_count == 0:
		var previous_result: Dictionary = prepared.get("previous_result", {})
		if not previous_result.is_empty():
			var reused := previous_result.duplicate(false)
			var reused_timings: Dictionary = (previous_result.get("timings_usec", {}) as Dictionary).duplicate(true)
			reused_timings["shared_sampling"] = sampling_elapsed_usec
			reused_timings["shared_polygonize"] = 0
			reused_timings["shared_deduplicate"] = 0
			reused_timings["shared_diagnostics"] = 0
			reused_timings["shared_signature"] = 0
			reused_timings["shared_volume_total"] = Time.get_ticks_usec() - total_started_usec
			reused["timings_usec"] = reused_timings
			var reused_counters: Dictionary = (previous_result.get("work_counters", {}) as Dictionary).duplicate(true)
			reused_counters["tet_call_count"] = 0
			reused_counters["dirty_cell_count"] = 0
			reused_counters["reused_cell_count"] = total_cell_count
			reused_counters["incremental_cache_hit"] = 1
			reused_counters["incremental_applied_operation_count"] = applied_operation_count
			reused["work_counters"] = reused_counters
			_store_incremental_state(cache_key, _make_incremental_state(
				brush_snapshot, prepared, exact_values, values, cell_mixed,
				cell_dropped, cell_triangles, mixed_cell_count, uniform_cell_count, reused
			))
			return reused

	var polygonize_started_usec := Time.get_ticks_usec()
	var tet_call_count := 0
	var dirty_root_cache: Dictionary = {}
	var dirty_root_position_keys: Dictionary = {}
	for y in range(cells.y):
		for z in range(cells.z):
			for x in range(cells.x):
				var cell_index := _cell_index(x, y, z, cells)
				if dirty_flags[cell_index] == 0:
					continue
				var cell := Vector3i(x, y, z)
				var density: Array[float] = []
				for corner_value in CORNERS:
					var corner: Vector3i = corner_value
					var node := cell + corner
					density.append(values[_index(node.x, node.y, node.z, dims)])
				var has_solid := false
				var has_empty := false
				for density_value in density:
					if density_value > 0.0:
						has_solid = true
					else:
						has_empty = true
				var is_mixed := has_solid and has_empty
				if cache_hit:
					var was_mixed := cell_mixed[cell_index] != 0
					if was_mixed != is_mixed:
						if is_mixed:
							mixed_cell_count += 1
							uniform_cell_count -= 1
						else:
							mixed_cell_count -= 1
							uniform_cell_count += 1
				elif is_mixed:
					mixed_cell_count += 1
				else:
					uniform_cell_count += 1
				cell_mixed[cell_index] = 1 if is_mixed else 0
				if not is_mixed:
					cell_triangles.erase(cell_index)
					cell_dropped[cell_index] = 0
					continue

				var nodes: Array[Vector3i] = []
				var points: Array[Vector3] = []
				for corner_value in CORNERS:
					var corner: Vector3i = corner_value
					var node := cell + corner
					nodes.append(node)
					points.append(roi_min + Vector3(node) * step)
				var emitted_for_cell: Array[Dictionary] = []
				var dropped_for_cell := 0
				for tet in TETS:
					tet_call_count += 1
					var emitted: Dictionary
					if kind == "x":
						emitted = _polygonize_tet(
							tet, nodes, points, density, roi_min, step, seam_x,
							dirty_root_cache, dirty_root_position_keys
						)
					elif kind == "z":
						emitted = _polygonize_tet_z(
							tet, nodes, points, density, roi_min, step, seam_z,
							dirty_root_cache, dirty_root_position_keys
						)
					else:
						emitted = _polygonize_tet_corner(
							tet, nodes, points, density, roi_min, step, seam_x, seam_z,
							dirty_root_cache, dirty_root_position_keys
						)
					dropped_for_cell += int(emitted.get("dropped_degenerate", 0))
					emitted_for_cell.append_array(emitted.get("triangles", []))
				cell_triangles[cell_index] = emitted_for_cell
				cell_dropped[cell_index] = dropped_for_cell

	var polygonize_elapsed_usec := Time.get_ticks_usec() - polygonize_started_usec
	var triangles: Array[Dictionary] = []
	var dropped_degenerate_candidates := 0
	for cell_index in range(total_cell_count):
		dropped_degenerate_candidates += int(cell_dropped[cell_index])
		if cell_triangles.has(cell_index):
			triangles.append_array(cell_triangles[cell_index])
	var triangle_candidate_count := triangles.size()

	var deduplicate_started_usec := Time.get_ticks_usec()
	var deduplicated := _deduplicate_triangles(triangles)
	var dropped_duplicate_candidates := triangles.size() - deduplicated.size()
	var deduplicate_elapsed_usec := Time.get_ticks_usec() - deduplicate_started_usec
	triangles = deduplicated

	# Reconstruct global root identity from the merged reused+dirty triangle set.
	var root_cache: Dictionary = {}
	var root_position_keys: Dictionary = {}
	for triangle_value in triangles:
		var triangle: Dictionary = triangle_value
		var ids: Array = triangle.get("root_ids", [])
		var points: Array = triangle.get("points", [])
		if ids.size() != 3 or points.size() != 3:
			continue
		for index in range(3):
			var root_id := String(ids[index])
			var point: Vector3 = points[index]
			var point_key := _point_key(point)
			if not root_cache.has(root_id):
				root_cache[root_id] = point
				root_position_keys[root_id] = point_key
			elif String(root_position_keys.get(root_id, "")) != point_key:
				root_position_keys[root_id] = "__root_identity_conflict__"

	var diagnostics_started_usec := Time.get_ticks_usec()
	var diagnostics: Dictionary = {}
	if diagnostics_enabled:
		if kind == "x":
			diagnostics = analyze_world_triangles(triangles, seam_x, roi_min, roi_max)
		elif kind == "z":
			diagnostics = analyze_world_triangles_z(triangles, seam_z, roi_min, roi_max)
		else:
			diagnostics = analyze_corner_world_triangles(triangles, seam_x, seam_z, roi_min, roi_max)
	var diagnostics_elapsed_usec := Time.get_ticks_usec() - diagnostics_started_usec

	var signature_started_usec := Time.get_ticks_usec()
	var signature_rows: Array[String] = []
	var owner_key := "owner" if kind == "corner" else "side"
	for triangle_value in triangles:
		var ids: Array = triangle_value["root_ids"]
		var sorted_ids := [String(ids[0]), String(ids[1]), String(ids[2])]
		sorted_ids.sort()
		signature_rows.append("%s:%s" % [String(triangle_value[owner_key]), "|".join(sorted_ids)])
	signature_rows.sort()
	var signature_elapsed_usec := Time.get_ticks_usec() - signature_started_usec

	if diagnostics_enabled:
		diagnostics["root_identity_consistent"] = _root_identity_consistent(root_cache, root_position_keys)
		diagnostics["dropped_degenerate_candidate_count"] = dropped_degenerate_candidates
		diagnostics["dropped_duplicate_candidate_count"] = dropped_duplicate_candidates
		diagnostics["emitted_degenerate_triangle_count"] = 0

	var result := {
		"valid": true,
		"triangles": triangles,
		"diagnostics": diagnostics,
		"mesh_signature": _fnv1a_64("\n".join(signature_rows)),
		"unique_root_count": root_cache.size(),
		"triangle_count": triangles.size(),
		"sample_count": values.size(),
		"roi_min": roi_min,
		"roi_max": roi_max,
		"step": step,
		"timings_usec": {
			"shared_sampling": sampling_elapsed_usec,
			"shared_polygonize": polygonize_elapsed_usec,
			"shared_deduplicate": deduplicate_elapsed_usec,
			"shared_diagnostics": diagnostics_elapsed_usec,
			"shared_signature": signature_elapsed_usec,
			"shared_volume_total": Time.get_ticks_usec() - total_started_usec,
		},
		"work_counters": {
			"cell_count": total_cell_count,
			"mixed_cell_count": mixed_cell_count,
			"uniform_cell_count": uniform_cell_count,
			"tet_call_count": tet_call_count,
			"triangle_candidate_count": triangle_candidate_count,
			"triangle_count": triangles.size(),
			"unique_root_count": root_cache.size(),
			"sample_count": values.size(),
			"dirty_cell_count": dirty_cell_count,
			"reused_cell_count": total_cell_count - dirty_cell_count,
			"incremental_cache_hit": 1 if cache_hit else 0,
			"incremental_applied_operation_count": applied_operation_count,
		},
	}
	if kind == "x" or kind == "corner":
		result["seam_x"] = seam_x
	if kind == "z" or kind == "corner":
		result["seam_z"] = seam_z

	_store_incremental_state(cache_key, _make_incremental_state(
		brush_snapshot, prepared, exact_values, values, cell_mixed,
		cell_dropped, cell_triangles, mixed_cell_count, uniform_cell_count, result
	))
	return result


static func _prepare_incremental_volume(
	cache_key: String,
	world_seed: int,
	snapshot: Dictionary,
	roi_min: Vector3,
	cells: Vector3i,
	dims: Vector3i,
	step: float
) -> Dictionary:
	var centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
	var radii: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
	var modes: PackedByteArray = snapshot.get("modes", PackedByteArray())
	var sequences := _snapshot_sequences(snapshot)
	if centers.size() != radii.size() or centers.size() != modes.size() \
		or centers.size() != sequences.size():
		return {"valid": false, "reason": "incremental_snapshot_attribute_mismatch"}

	var base_signature := _materialized_base_signature(snapshot)
	var previous := _get_incremental_state(cache_key)
	var node_count := dims.x * dims.y * dims.z
	var cell_count := cells.x * cells.y * cells.z
	var can_increment := not previous.is_empty() \
		and String(previous.get("base_signature", "")) == base_signature \
		and _snapshot_extends_state(previous, centers, radii, modes, sequences) \
		and (previous.get("exact_values", PackedFloat64Array()) as PackedFloat64Array).size() == node_count \
		and (previous.get("values", PackedFloat32Array()) as PackedFloat32Array).size() == node_count

	if can_increment:
		var exact_values: PackedFloat64Array = (previous["exact_values"] as PackedFloat64Array).duplicate()
		var values: PackedFloat32Array = (previous["values"] as PackedFloat32Array).duplicate()
		var dirty_flags := PackedByteArray()
		dirty_flags.resize(cell_count)
		var cell_mixed: PackedByteArray = (previous.get("cell_mixed", PackedByteArray()) as PackedByteArray).duplicate()
		var cell_dropped: PackedInt32Array = (previous.get("cell_dropped", PackedInt32Array()) as PackedInt32Array).duplicate()
		if cell_mixed.size() != cell_count or cell_dropped.size() != cell_count:
			can_increment = false
		else:
			var cell_triangles: Dictionary = {}
			var previous_cells: Dictionary = previous.get("cell_triangles", {})
			for key in previous_cells.keys():
				cell_triangles[key] = previous_cells[key]
			var dirty_cell_count := 0
			var previous_operation_count := int(previous.get("operation_count", 0))
			for operation_index in range(previous_operation_count, sequences.size()):
				var center: Vector3 = centers[operation_index]
				var radius := float(radii[operation_index])
				var mode := int(modes[operation_index])
				for y in range(dims.y):
					for z in range(dims.z):
						for x in range(dims.x):
							var node_index := _index(x, y, z, dims)
							var prior_exact := float(exact_values[node_index])
							var world := roi_min + Vector3(x, y, z) * step
							var distance_to_surface := world.distance_to(center) - radius
							var next_exact := minf(prior_exact, distance_to_surface) \
								if mode == Brush.Mode.CARVE \
								else maxf(prior_exact, -distance_to_surface)
							exact_values[node_index] = next_exact
							var prior_value := float(values[node_index])
							values[node_index] = next_exact
							if float(values[node_index]) != prior_value:
								dirty_cell_count += _mark_dirty_cells_for_node(
									dirty_flags, cells, x, y, z
								)
			return {
				"valid": true,
				"cache_hit": true,
				"applied_operation_count": sequences.size() - previous_operation_count,
				"dirty_cell_count": dirty_cell_count,
				"values": values,
				"exact_values": exact_values,
				"dirty_flags": dirty_flags,
				"cell_mixed": cell_mixed,
				"cell_dropped": cell_dropped,
				"cell_triangles": cell_triangles,
				"mixed_cell_count": int(previous.get("mixed_cell_count", 0)),
				"uniform_cell_count": int(previous.get("uniform_cell_count", 0)),
				"base_signature": base_signature,
				"centers": centers,
				"radii": radii,
				"modes": modes,
				"sequences": sequences,
				"previous_result": previous.get("final_result", {}),
			}

	# Conservative full-build fallback for materialization changes, clears,
	# candidate-pruning rewrites, cache eviction, or any state-shape mismatch.
	var exact_values := PackedFloat64Array()
	exact_values.resize(node_count)
	var values := PackedFloat32Array()
	values.resize(node_count)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var world := roi_min + Vector3(x, y, z) * step
				var density := _sample_density(world_seed, world, snapshot)
				if not is_finite(density):
					return {"valid": false, "reason": "non_finite_sample", "sample": [x, y, z]}
				var node_index := _index(x, y, z, dims)
				exact_values[node_index] = density
				values[node_index] = density
	var dirty_flags := PackedByteArray()
	dirty_flags.resize(cell_count)
	dirty_flags.fill(1)
	var cell_mixed := PackedByteArray()
	cell_mixed.resize(cell_count)
	var cell_dropped := PackedInt32Array()
	cell_dropped.resize(cell_count)
	return {
		"valid": true,
		"cache_hit": false,
		"applied_operation_count": sequences.size(),
		"dirty_cell_count": cell_count,
		"values": values,
		"exact_values": exact_values,
		"dirty_flags": dirty_flags,
		"cell_mixed": cell_mixed,
		"cell_dropped": cell_dropped,
		"cell_triangles": {},
		"mixed_cell_count": 0,
		"uniform_cell_count": 0,
		"base_signature": base_signature,
		"centers": centers,
		"radii": radii,
		"modes": modes,
		"sequences": sequences,
	}


static func _make_incremental_state(
	snapshot: Dictionary,
	prepared: Dictionary,
	exact_values: PackedFloat64Array,
	values: PackedFloat32Array,
	cell_mixed: PackedByteArray,
	cell_dropped: PackedInt32Array,
	cell_triangles: Dictionary,
	mixed_cell_count: int,
	uniform_cell_count: int,
	final_result: Dictionary
) -> Dictionary:
	return {
		"revision": int(snapshot.get("revision", -1)),
		"base_signature": String(prepared.get("base_signature", "")),
		"operation_count": (prepared.get("sequences", PackedInt64Array()) as PackedInt64Array).size(),
		"centers": (prepared.get("centers", PackedVector3Array()) as PackedVector3Array).duplicate(),
		"radii": (prepared.get("radii", PackedFloat64Array()) as PackedFloat64Array).duplicate(),
		"modes": (prepared.get("modes", PackedByteArray()) as PackedByteArray).duplicate(),
		"sequences": (prepared.get("sequences", PackedInt64Array()) as PackedInt64Array).duplicate(),
		"exact_values": exact_values.duplicate(),
		"values": values.duplicate(),
		"cell_mixed": cell_mixed.duplicate(),
		"cell_dropped": cell_dropped.duplicate(),
		"cell_triangles": cell_triangles,
		"mixed_cell_count": mixed_cell_count,
		"uniform_cell_count": uniform_cell_count,
		"final_result": final_result,
	}


static func _snapshot_sequences(snapshot: Dictionary) -> PackedInt64Array:
	var result := PackedInt64Array()
	var value: Variant = snapshot.get("sequences", PackedInt64Array())
	if typeof(value) != TYPE_PACKED_INT32_ARRAY and typeof(value) != TYPE_PACKED_INT64_ARRAY:
		return result
	for sequence_value in value:
		result.append(int(sequence_value))
	return result


static func _snapshot_extends_state(
	state: Dictionary,
	centers: PackedVector3Array,
	radii: PackedFloat64Array,
	modes: PackedByteArray,
	sequences: PackedInt64Array
) -> bool:
	var prior_centers: PackedVector3Array = state.get("centers", PackedVector3Array())
	var prior_radii: PackedFloat64Array = state.get("radii", PackedFloat64Array())
	var prior_modes: PackedByteArray = state.get("modes", PackedByteArray())
	var prior_sequences: PackedInt64Array = state.get("sequences", PackedInt64Array())
	var prior_count := prior_sequences.size()
	if prior_centers.size() != prior_count or prior_radii.size() != prior_count \
		or prior_modes.size() != prior_count or sequences.size() < prior_count:
		return false
	for index in range(prior_count):
		if prior_sequences[index] != sequences[index] \
			or prior_centers[index] != centers[index] \
			or float(prior_radii[index]) != float(radii[index]) \
			or int(prior_modes[index]) != int(modes[index]):
			return false
	return true


static func _materialized_base_signature(snapshot: Dictionary) -> String:
	var rows: Array[String] = []
	var tiles_value: Variant = snapshot.get("materialized_tiles", [])
	if typeof(tiles_value) != TYPE_ARRAY:
		return ""
	for tile_value in tiles_value:
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		var origin: Vector3 = tile.get("origin_world", Vector3.INF)
		var dims: Vector3i = tile.get("dims", Vector3i.ZERO)
		var values_value: Variant = tile.get("values", PackedFloat64Array())
		var value_count := values_value.size() if values_value is PackedFloat64Array or values_value is PackedFloat32Array else -1
		rows.append("%s:%d:%d:%s:%d,%d,%d:%d:%d" % [
			String(tile.get("tile_id", "")),
			int(tile.get("base_revision", -1)),
			int(tile.get("base_sequence", -1)),
			_point_key(origin) if origin.is_finite() else "invalid",
			dims.x, dims.y, dims.z,
			roundi(float(tile.get("step", 0.0)) * ROOT_QUANT),
			value_count,
		])
	rows.sort()
	return "\n".join(rows)


static func _incremental_scope_key(
	kind: String,
	world_seed: int,
	snapshot: Dictionary,
	roi_min: Vector3,
	cells: Vector3i,
	step: float,
	seam_x: float,
	seam_z: float
) -> String:
	return "%s:%d:%d:%s:%d,%d,%d:%d:%d:%d" % [
		kind,
		world_seed,
		int(snapshot.get("cache_scope_id", -1)),
		_point_key(roi_min),
		cells.x, cells.y, cells.z,
		roundi(step * ROOT_QUANT),
		roundi(seam_x * ROOT_QUANT),
		roundi(seam_z * ROOT_QUANT),
	]


static func _get_incremental_state(key: String) -> Dictionary:
	_incremental_mutex.lock()
	var result: Dictionary = _incremental_states.get(key, {})
	_incremental_mutex.unlock()
	return result


static func _store_incremental_state(key: String, state: Dictionary) -> void:
	if key.is_empty() or state.is_empty():
		return
	_incremental_mutex.lock()
	var existing: Dictionary = _incremental_states.get(key, {})
	if existing.is_empty() or int(state.get("revision", -1)) >= int(existing.get("revision", -1)):
		if not _incremental_states.has(key):
			_incremental_order.append(key)
		_incremental_states[key] = state
		while _incremental_order.size() > MAX_INCREMENTAL_STATES:
			var oldest := String(_incremental_order.pop_front())
			if oldest != key:
				_incremental_states.erase(oldest)
	_incremental_mutex.unlock()


static func _mark_dirty_cells_for_node(
	dirty_flags: PackedByteArray,
	cells: Vector3i,
	node_x: int,
	node_y: int,
	node_z: int
) -> int:
	var added := 0
	for cy in [node_y - 1, node_y]:
		if cy < 0 or cy >= cells.y:
			continue
		for cz in [node_z - 1, node_z]:
			if cz < 0 or cz >= cells.z:
				continue
			for cx in [node_x - 1, node_x]:
				if cx < 0 or cx >= cells.x:
					continue
				var cell_index := _cell_index(cx, cy, cz, cells)
				if dirty_flags[cell_index] == 0:
					dirty_flags[cell_index] = 1
					added += 1
	return added


static func _cell_index(x: int, y: int, z: int, cells: Vector3i) -> int:
	return (y * cells.z + z) * cells.x + x


static func _deduplicate_triangles(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for triangle in source:
		var points: Array = triangle.get("points", [])
		if points.size() != 3:
			continue
		# Exact-zero SDF nodes may be reached through several lattice edges. Those
		# edges have different root IDs but collapse to the same geometric vertex,
		# so root-ID deduplication can leave coincident triangles and incidence 4.
		# Geometry identity is authoritative here: remove only triangles whose
		# three canonical world-space points are exactly the same set.
		var canonical := [
			_point_key(points[0]),
			_point_key(points[1]),
			_point_key(points[2]),
		]
		canonical.sort()
		var key := "|".join(canonical)
		if seen.has(key):
			continue
		seen[key] = true
		result.append(triangle)
	return result


static func analyze_cpu_pair_plane(
	left_cpu: Dictionary,
	left_world_origin: Vector3,
	right_cpu: Dictionary,
	right_world_origin: Vector3,
	seam_x: float,
	y_min: float,
	y_max: float,
	z_min: float,
	z_max: float
) -> Dictionary:
	var triangles: Array[Dictionary] = []
	_append_cpu_triangles(triangles, left_cpu, left_world_origin, "left")
	_append_cpu_triangles(triangles, right_cpu, right_world_origin, "right")
	return analyze_world_triangles(
		triangles, seam_x,
		Vector3(seam_x - 1.0, y_min, z_min),
		Vector3(seam_x + 1.0, y_max, z_max)
	)


static func analyze_cpu_pair_plane_z(
	low_cpu: Dictionary,
	low_world_origin: Vector3,
	high_cpu: Dictionary,
	high_world_origin: Vector3,
	seam_z: float,
	y_min: float,
	y_max: float,
	x_min: float,
	x_max: float
) -> Dictionary:
	var triangles: Array[Dictionary] = []
	_append_cpu_triangles(triangles, low_cpu, low_world_origin, "low")
	_append_cpu_triangles(triangles, high_cpu, high_world_origin, "high")
	return analyze_world_triangles_z(
		triangles, seam_z,
		Vector3(x_min, y_min, seam_z - 1.0),
		Vector3(x_max, y_max, seam_z + 1.0)
	)


static func analyze_world_triangles(
	triangles: Array,
	seam_x: float,
	roi_min: Vector3,
	roi_max: Vector3
) -> Dictionary:
	var edge_incidence: Dictionary = {}
	var edge_sides: Dictionary = {}
	var edge_points: Dictionary = {}
	var edge_geometry_sides: Dictionary = {}
	var duplicate_triangles := 0
	var triangle_keys: Dictionary = {}
	for triangle_value in triangles:
		var triangle: Dictionary = triangle_value
		var points: Array = triangle["points"]
		if points.size() != 3:
			continue
		var point_keys := [_point_key(points[0]), _point_key(points[1]), _point_key(points[2])]
		var canonical_triangle := point_keys.duplicate()
		canonical_triangle.sort()
		var triangle_key := "|".join(canonical_triangle)
		if triangle_keys.has(triangle_key):
			duplicate_triangles += 1
		triangle_keys[triangle_key] = true
		var triangle_geometry_sides := {}
		for point_value in points:
			var point: Vector3 = point_value
			if point.x < seam_x - EPS:
				triangle_geometry_sides["left"] = true
			elif point.x > seam_x + EPS:
				triangle_geometry_sides["right"] = true
		for pair in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = points[pair[0]]
			var b: Vector3 = points[pair[1]]
			var key := _ordered_pair(_point_key(a), _point_key(b))
			edge_incidence[key] = int(edge_incidence.get(key, 0)) + 1
			if not edge_sides.has(key):
				edge_sides[key] = {}
			var sides: Dictionary = edge_sides[key]
			sides[String(triangle.get("side", "unknown"))] = true
			edge_sides[key] = sides
			if not edge_geometry_sides.has(key):
				edge_geometry_sides[key] = {}
			var geometry_sides: Dictionary = edge_geometry_sides[key]
			for geometry_side in triangle_geometry_sides.keys():
				geometry_sides[geometry_side] = true
			edge_geometry_sides[key] = geometry_sides
			edge_points[key] = [a, b]

	var seam_edges: Array[String] = []
	var bad_incidence := 0
	var cross_owner := 0
	var crossing_edges := 0
	var tangent_contact_edges := 0
	var bad_edges: Array[Dictionary] = []
	var non_cross_owned_edges: Array[Dictionary] = []
	for edge_value in edge_incidence.keys():
		var edge_key := String(edge_value)
		var pts: Array = edge_points[edge_key]
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[1]
		if absf(a.x - seam_x) > EPS or absf(b.x - seam_x) > EPS:
			continue
		if _on_outer_yz(a, roi_min, roi_max) and _on_outer_yz(b, roi_min, roi_max):
			continue
		seam_edges.append(edge_key)
		var incidence := int(edge_incidence[edge_key])
		var sides: Dictionary = edge_sides[edge_key]
		var geometry_sides: Dictionary = edge_geometry_sides.get(edge_key, {})
		var geometrically_crossing := geometry_sides.has("left") and geometry_sides.has("right")
		if geometrically_crossing:
			crossing_edges += 1
		else:
			tangent_contact_edges += 1
		if incidence != 2:
			bad_incidence += 1
			if bad_edges.size() < 32:
				bad_edges.append({"edge": edge_key, "incidence": incidence, "sides": sides.keys(), "geometry_sides": geometry_sides.keys(), "points": [a, b]})
		if geometrically_crossing:
			if sides.has("left") and sides.has("right"):
				cross_owner += 1
			elif non_cross_owned_edges.size() < 32:
				non_cross_owned_edges.append({"edge": edge_key, "incidence": incidence, "sides": sides.keys(), "geometry_sides": geometry_sides.keys(), "points": [a, b]})

	return {
		"seam_edge_count": seam_edges.size(),
		"seam_bad_incidence_count": bad_incidence,
		"seam_cross_owner_count": cross_owner,
		"seam_crossing_edge_count": crossing_edges,
		"seam_tangent_contact_edge_count": tangent_contact_edges,
		"t_junction_count": _count_t_junctions(seam_edges, edge_points),
		"duplicate_triangle_count": duplicate_triangles,
		"bad_edges": bad_edges,
		"non_cross_owned_edges": non_cross_owned_edges,
	}


static func analyze_world_triangles_z(
	triangles: Array,
	seam_z: float,
	roi_min: Vector3,
	roi_max: Vector3
) -> Dictionary:
	var edge_incidence: Dictionary = {}
	var edge_sides: Dictionary = {}
	var edge_points: Dictionary = {}
	var edge_geometry_sides: Dictionary = {}
	var duplicate_triangles := 0
	var triangle_keys: Dictionary = {}
	for triangle_value in triangles:
		var triangle: Dictionary = triangle_value
		var points: Array = triangle["points"]
		if points.size() != 3:
			continue
		var point_keys := [_point_key(points[0]), _point_key(points[1]), _point_key(points[2])]
		var canonical_triangle := point_keys.duplicate()
		canonical_triangle.sort()
		var triangle_key := "|".join(canonical_triangle)
		if triangle_keys.has(triangle_key):
			duplicate_triangles += 1
		triangle_keys[triangle_key] = true
		var triangle_geometry_sides := {}
		for point_value in points:
			var point: Vector3 = point_value
			if point.z < seam_z - EPS:
				triangle_geometry_sides["low"] = true
			elif point.z > seam_z + EPS:
				triangle_geometry_sides["high"] = true
		for pair in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = points[pair[0]]
			var b: Vector3 = points[pair[1]]
			var key := _ordered_pair(_point_key(a), _point_key(b))
			edge_incidence[key] = int(edge_incidence.get(key, 0)) + 1
			if not edge_sides.has(key):
				edge_sides[key] = {}
			var sides: Dictionary = edge_sides[key]
			sides[String(triangle.get("side", "unknown"))] = true
			edge_sides[key] = sides
			if not edge_geometry_sides.has(key):
				edge_geometry_sides[key] = {}
			var geometry_sides: Dictionary = edge_geometry_sides[key]
			for geometry_side in triangle_geometry_sides.keys():
				geometry_sides[geometry_side] = true
			edge_geometry_sides[key] = geometry_sides
			edge_points[key] = [a, b]

	var seam_edges: Array[String] = []
	var bad_incidence := 0
	var cross_owner := 0
	var crossing_edges := 0
	var tangent_contact_edges := 0
	var bad_edges: Array[Dictionary] = []
	var non_cross_owned_edges: Array[Dictionary] = []
	for edge_value in edge_incidence.keys():
		var edge_key := String(edge_value)
		var pts: Array = edge_points[edge_key]
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[1]
		if absf(a.z - seam_z) > EPS or absf(b.z - seam_z) > EPS:
			continue
		if _on_outer_xy(a, roi_min, roi_max) and _on_outer_xy(b, roi_min, roi_max):
			continue
		seam_edges.append(edge_key)
		var incidence := int(edge_incidence[edge_key])
		var sides: Dictionary = edge_sides[edge_key]
		var geometry_sides: Dictionary = edge_geometry_sides.get(edge_key, {})
		var geometrically_crossing := geometry_sides.has("low") and geometry_sides.has("high")
		if geometrically_crossing:
			crossing_edges += 1
		else:
			tangent_contact_edges += 1
		if incidence != 2:
			bad_incidence += 1
			if bad_edges.size() < 32:
				bad_edges.append({"edge": edge_key, "incidence": incidence, "sides": sides.keys(), "geometry_sides": geometry_sides.keys(), "points": [a, b]})
		if geometrically_crossing:
			if sides.has("low") and sides.has("high"):
				cross_owner += 1
			elif non_cross_owned_edges.size() < 32:
				non_cross_owned_edges.append({"edge": edge_key, "incidence": incidence, "sides": sides.keys(), "geometry_sides": geometry_sides.keys(), "points": [a, b]})
	return {
		"seam_edge_count": seam_edges.size(),
		"seam_bad_incidence_count": bad_incidence,
		"seam_cross_owner_count": cross_owner,
		"seam_crossing_edge_count": crossing_edges,
		"seam_tangent_contact_edge_count": tangent_contact_edges,
		"t_junction_count": _count_t_junctions(seam_edges, edge_points),
		"duplicate_triangle_count": duplicate_triangles,
		"bad_edges": bad_edges,
		"non_cross_owned_edges": non_cross_owned_edges,
	}


static func analyze_corner_world_triangles(
	triangles: Array,
	seam_x: float,
	seam_z: float,
	roi_min: Vector3,
	roi_max: Vector3
) -> Dictionary:
	var x_triangles: Array[Dictionary] = []
	var z_triangles: Array[Dictionary] = []
	var edge_incidence: Dictionary = {}
	var edge_points: Dictionary = {}
	var edge_owners: Dictionary = {}
	for triangle_value in triangles:
		var triangle: Dictionary = triangle_value
		var owner := String(triangle.get("owner", ""))
		var x_copy := triangle.duplicate(true)
		x_copy["side"] = "left" if owner.begins_with("minx_") else "right"
		x_triangles.append(x_copy)
		var z_copy := triangle.duplicate(true)
		z_copy["side"] = "low" if owner.ends_with("_minz") else "high"
		z_triangles.append(z_copy)
		var points: Array = triangle.get("points", [])
		if points.size() != 3:
			continue
		for pair in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = points[pair[0]]
			var b: Vector3 = points[pair[1]]
			var key := _ordered_pair(_point_key(a), _point_key(b))
			edge_incidence[key] = int(edge_incidence.get(key, 0)) + 1
			edge_points[key] = [a, b]
			if not edge_owners.has(key):
				edge_owners[key] = {}
			var owners: Dictionary = edge_owners[key]
			owners[owner] = true
			edge_owners[key] = owners
	var x_diag := analyze_world_triangles(x_triangles, seam_x, roi_min, roi_max)
	var z_diag := analyze_world_triangles_z(z_triangles, seam_z, roi_min, roi_max)
	var junction_edges: Array[String] = []
	var junction_bad_incidence := 0
	var junction_multi_owner := 0
	var junction_bad_edges: Array[Dictionary] = []
	for edge_value in edge_incidence.keys():
		var edge_key := String(edge_value)
		var pts: Array = edge_points[edge_key]
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[1]
		if absf(a.x - seam_x) > EPS or absf(b.x - seam_x) > EPS \
			or absf(a.z - seam_z) > EPS or absf(b.z - seam_z) > EPS:
			continue
		if _on_outer_y(a, roi_min, roi_max) and _on_outer_y(b, roi_min, roi_max):
			continue
		junction_edges.append(edge_key)
		var incidence := int(edge_incidence[edge_key])
		var owners: Dictionary = edge_owners.get(edge_key, {})
		if owners.size() >= 2:
			junction_multi_owner += 1
		if incidence != 2:
			junction_bad_incidence += 1
			if junction_bad_edges.size() < 32:
				junction_bad_edges.append({
					"edge": edge_key,
					"incidence": incidence,
					"owners": owners.keys(),
					"points": [a, b],
				})
	return {
		"x": x_diag,
		"z": z_diag,
		"x_seam_bad_incidence_count": int(x_diag.get("seam_bad_incidence_count", -1)),
		"x_t_junction_count": int(x_diag.get("t_junction_count", -1)),
		"x_non_cross_owned_count": (x_diag.get("non_cross_owned_edges", []) as Array).size(),
		"z_seam_bad_incidence_count": int(z_diag.get("seam_bad_incidence_count", -1)),
		"z_t_junction_count": int(z_diag.get("t_junction_count", -1)),
		"z_non_cross_owned_count": (z_diag.get("non_cross_owned_edges", []) as Array).size(),
		"junction_edge_count": junction_edges.size(),
		"junction_bad_incidence_count": junction_bad_incidence,
		"junction_t_junction_count": _count_t_junctions(junction_edges, edge_points),
		"junction_multi_owner_count": junction_multi_owner,
		"junction_bad_edges": junction_bad_edges,
		"duplicate_triangle_count": int(x_diag.get("duplicate_triangle_count", -1)),
	}


static func _append_cpu_triangles(
	target: Array[Dictionary],
	cpu: Dictionary,
	world_origin: Vector3,
	side: String
) -> void:
	var positions: PackedVector3Array = cpu.get("positions", PackedVector3Array())
	for i in range(0, positions.size() - 2, 3):
		var a := positions[i] + world_origin
		var b := positions[i + 1] + world_origin
		var c := positions[i + 2] + world_origin
		target.append({
			"points": [a, b, c],
			"side": side,
			"root_ids": [_point_key(a), _point_key(b), _point_key(c)],
			"normal": (b - a).cross(c - a).normalized(),
		})


static func _sample_density(world_seed: int, world: Vector3, snapshot: Dictionary) -> float:
	var mapped: Dictionary = Spatial.world_to_region_local(world)
	if not bool(mapped.get("valid", false)):
		return NAN
	if snapshot.is_empty():
		return Field.sample_density(world_seed, mapped["region_key"], mapped["local_position"], false)
	return Brush.sample_density_snapshot(
		world_seed, mapped["region_key"], mapped["local_position"], false, snapshot
	)


static func _polygonize_tet(
	tet: Array,
	nodes: Array[Vector3i],
	points: Array[Vector3],
	density: Array[float],
	roi_min: Vector3,
	step: float,
	seam_x: float,
	root_cache: Dictionary,
	root_position_keys: Dictionary
) -> Dictionary:
	var inside: Array[int] = []
	var outside: Array[int] = []
	for local_index in tet:
		# Exact-zero samples use one deterministic half-open convention. Treating
		# zero as empty prevents several crossed lattice edges from collapsing onto
		# the same zero node and creating non-manifold incidence under tetrahedral
		# decomposition. Non-zero topology and interpolation are unchanged.
		if density[local_index] > 0.0:
			inside.append(local_index)
		else:
			outside.append(local_index)
	if inside.is_empty() or outside.is_empty():
		return {"triangles": [], "dropped_degenerate": 0}

	var inside_center := Vector3.ZERO
	var outside_center := Vector3.ZERO
	for i in inside:
		inside_center += points[i]
	for i in outside:
		outside_center += points[i]
	inside_center /= float(inside.size())
	outside_center /= float(outside.size())
	var toward_empty := outside_center - inside_center

	if inside.size() == 1 or inside.size() == 3:
		var singleton: int
		var others: Array[int]
		if inside.size() == 1:
			singleton = inside[0]
			others = outside
		else:
			singleton = outside[0]
			others = inside
		var roots: Array[String] = []
		for other in others:
			roots.append(_root_id_and_cache(
				singleton, other, nodes, points, density, roi_min, step,
				root_cache, root_position_keys
			))
		return _emit_triangle(roots[0], roots[1], roots[2], toward_empty, seam_x, root_cache)

	var r00 := _root_id_and_cache(inside[0], outside[0], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r01 := _root_id_and_cache(inside[0], outside[1], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r10 := _root_id_and_cache(inside[1], outside[0], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r11 := _root_id_and_cache(inside[1], outside[1], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	# Match MarchingTetrahedra and Lod01TransitionFixture exactly for 2/2
	# tetrahedra: both use the a-d diagonal. Root interpolation remains globally
	# canonical, but topology must share the production diagonal convention.
	var result: Array[Dictionary] = []
	var first := _emit_triangle(r00, r01, r11, toward_empty, seam_x, root_cache)
	var second := _emit_triangle(r00, r11, r10, toward_empty, seam_x, root_cache)
	result.append_array(first["triangles"])
	result.append_array(second["triangles"])
	var dropped := int(first["dropped_degenerate"]) + int(second["dropped_degenerate"])
	return {"triangles": result, "dropped_degenerate": dropped}


static func _polygonize_tet_z(
	tet: Array,
	nodes: Array[Vector3i],
	points: Array[Vector3],
	density: Array[float],
	roi_min: Vector3,
	step: float,
	seam_z: float,
	root_cache: Dictionary,
	root_position_keys: Dictionary
) -> Dictionary:
	var inside: Array[int] = []
	var outside: Array[int] = []
	for local_index in tet:
		if density[local_index] > 0.0:
			inside.append(local_index)
		else:
			outside.append(local_index)
	if inside.is_empty() or outside.is_empty():
		return {"triangles": [], "dropped_degenerate": 0}
	var inside_center := Vector3.ZERO
	var outside_center := Vector3.ZERO
	for i in inside:
		inside_center += points[i]
	for i in outside:
		outside_center += points[i]
	inside_center /= float(inside.size())
	outside_center /= float(outside.size())
	var toward_empty := outside_center - inside_center
	if inside.size() == 1 or inside.size() == 3:
		var singleton: int
		var others: Array[int]
		if inside.size() == 1:
			singleton = inside[0]
			others = outside
		else:
			singleton = outside[0]
			others = inside
		var roots: Array[String] = []
		for other in others:
			roots.append(_root_id_and_cache(
				singleton, other, nodes, points, density, roi_min, step,
				root_cache, root_position_keys
			))
		return _emit_triangle_z(roots[0], roots[1], roots[2], toward_empty, seam_z, root_cache)
	var r00 := _root_id_and_cache(inside[0], outside[0], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r01 := _root_id_and_cache(inside[0], outside[1], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r10 := _root_id_and_cache(inside[1], outside[0], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r11 := _root_id_and_cache(inside[1], outside[1], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var result: Array[Dictionary] = []
	var first := _emit_triangle_z(r00, r01, r11, toward_empty, seam_z, root_cache)
	var second := _emit_triangle_z(r00, r11, r10, toward_empty, seam_z, root_cache)
	result.append_array(first["triangles"])
	result.append_array(second["triangles"])
	return {
		"triangles": result,
		"dropped_degenerate": int(first["dropped_degenerate"]) + int(second["dropped_degenerate"]),
	}


static func _polygonize_tet_corner(
	tet: Array,
	nodes: Array[Vector3i],
	points: Array[Vector3],
	density: Array[float],
	roi_min: Vector3,
	step: float,
	seam_x: float,
	seam_z: float,
	root_cache: Dictionary,
	root_position_keys: Dictionary
) -> Dictionary:
	var inside: Array[int] = []
	var outside: Array[int] = []
	for local_index in tet:
		if density[local_index] > 0.0:
			inside.append(local_index)
		else:
			outside.append(local_index)
	if inside.is_empty() or outside.is_empty():
		return {"triangles": [], "dropped_degenerate": 0}
	var inside_center := Vector3.ZERO
	var outside_center := Vector3.ZERO
	for i in inside:
		inside_center += points[i]
	for i in outside:
		outside_center += points[i]
	inside_center /= float(inside.size())
	outside_center /= float(outside.size())
	var toward_empty := outside_center - inside_center
	if inside.size() == 1 or inside.size() == 3:
		var singleton: int
		var others: Array[int]
		if inside.size() == 1:
			singleton = inside[0]
			others = outside
		else:
			singleton = outside[0]
			others = inside
		var roots: Array[String] = []
		for other in others:
			roots.append(_root_id_and_cache(
				singleton, other, nodes, points, density, roi_min, step,
				root_cache, root_position_keys
			))
		return _emit_triangle_corner(
			roots[0], roots[1], roots[2], toward_empty, seam_x, seam_z, root_cache
		)
	var r00 := _root_id_and_cache(inside[0], outside[0], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r01 := _root_id_and_cache(inside[0], outside[1], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r10 := _root_id_and_cache(inside[1], outside[0], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r11 := _root_id_and_cache(inside[1], outside[1], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var result: Array[Dictionary] = []
	var first := _emit_triangle_corner(r00, r01, r11, toward_empty, seam_x, seam_z, root_cache)
	var second := _emit_triangle_corner(r00, r11, r10, toward_empty, seam_x, seam_z, root_cache)
	result.append_array(first["triangles"])
	result.append_array(second["triangles"])
	return {
		"triangles": result,
		"dropped_degenerate": int(first["dropped_degenerate"]) + int(second["dropped_degenerate"]),
	}


static func _emit_triangle_z(
	a: String,
	b: String,
	c: String,
	toward_empty: Vector3,
	seam_z: float,
	roots: Dictionary
) -> Dictionary:
	if a == b or b == c or c == a:
		return {"triangles": [], "dropped_degenerate": 1}
	var pa: Vector3 = roots[a]
	var pb: Vector3 = roots[b]
	var pc: Vector3 = roots[c]
	var normal := (pb - pa).cross(pc - pa)
	if normal.length_squared() <= 1.0e-14:
		return {"triangles": [], "dropped_degenerate": 1}
	if normal.dot(toward_empty) < 0.0:
		var swap := pb
		pb = pc
		pc = swap
		var swap_id := b
		b = c
		c = swap_id
		normal = -normal
	normal = normal.normalized()
	var center_z := (pa.z + pb.z + pc.z) / 3.0
	var side := "low" if center_z < seam_z else "high"
	return {
		"triangles": [{
			"root_ids": [a, b, c],
			"points": [pa, pb, pc],
			"normal": normal,
			"side": side,
		}],
		"dropped_degenerate": 0,
	}


static func _emit_triangle_corner(
	a: String,
	b: String,
	c: String,
	toward_empty: Vector3,
	seam_x: float,
	seam_z: float,
	roots: Dictionary
) -> Dictionary:
	if a == b or b == c or c == a:
		return {"triangles": [], "dropped_degenerate": 1}
	var pa: Vector3 = roots[a]
	var pb: Vector3 = roots[b]
	var pc: Vector3 = roots[c]
	var normal := (pb - pa).cross(pc - pa)
	if normal.length_squared() <= 1.0e-14:
		return {"triangles": [], "dropped_degenerate": 1}
	if normal.dot(toward_empty) < 0.0:
		var swap := pb
		pb = pc
		pc = swap
		var swap_id := b
		b = c
		c = swap_id
		normal = -normal
	normal = normal.normalized()
	var center := (pa + pb + pc) / 3.0
	var owner := ("minx" if center.x < seam_x else "maxx") + "_" \
		+ ("minz" if center.z < seam_z else "maxz")
	return {
		"triangles": [{
			"root_ids": [a, b, c],
			"points": [pa, pb, pc],
			"normal": normal,
			"owner": owner,
		}],
		"dropped_degenerate": 0,
	}


static func _root_id_and_cache(
	a: int,
	b: int,
	nodes: Array[Vector3i],
	points: Array[Vector3],
	density: Array[float],
	roi_min: Vector3,
	step: float,
	root_cache: Dictionary,
	root_position_keys: Dictionary
) -> String:
	var wa := roi_min + Vector3(nodes[a]) * step
	var wb := roi_min + Vector3(nodes[b]) * step
	var node_a := _lattice_key(wa, step)
	var node_b := _lattice_key(wb, step)
	var key := _ordered_pair(node_a, node_b)
	if root_cache.has(key):
		return key
	var point_a: Vector3 = points[a]
	var point_b: Vector3 = points[b]
	var da := density[a]
	var db := density[b]
	# Match Lod01TransitionFixture bit-for-bit: shared crossed edges may be
	# traversed in opposite directions by different mesh owners, so canonicalize
	# endpoint order before the floating-point interpolation.
	if _point_precedes(point_b, point_a):
		var point_swap := point_a
		point_a = point_b
		point_b = point_swap
		var density_swap := da
		da = db
		db = density_swap
	var denominator := da - db
	var t := 0.5 if is_zero_approx(denominator) else clampf(da / denominator, 0.0, 1.0)
	var point := point_a.lerp(point_b, t)
	root_cache[key] = point
	root_position_keys[key] = _point_key(point)
	return key


static func _emit_triangle(
	a: String,
	b: String,
	c: String,
	toward_empty: Vector3,
	seam_x: float,
	roots: Dictionary
) -> Dictionary:
	if a == b or b == c or c == a:
		return {"triangles": [], "dropped_degenerate": 1}
	var pa: Vector3 = roots[a]
	var pb: Vector3 = roots[b]
	var pc: Vector3 = roots[c]
	var normal := (pb - pa).cross(pc - pa)
	if normal.length_squared() <= 1.0e-14:
		return {"triangles": [], "dropped_degenerate": 1}
	if normal.dot(toward_empty) < 0.0:
		var swap := pb
		pb = pc
		pc = swap
		var swap_id := b
		b = c
		c = swap_id
		normal = -normal
	normal = normal.normalized()
	var center_x := (pa.x + pb.x + pc.x) / 3.0
	var side := "left" if center_x < seam_x else "right"
	return {
		"triangles": [{
			"root_ids": [a, b, c],
			"points": [pa, pb, pc],
			"normal": normal,
			"side": side,
		}],
		"dropped_degenerate": 0,
	}


static func _count_t_junctions(seam_edges: Array[String], edge_points: Dictionary) -> int:
	var unique_points: Dictionary = {}
	for edge_key in seam_edges:
		var pts: Array = edge_points[edge_key]
		unique_points[_point_key(pts[0])] = pts[0]
		unique_points[_point_key(pts[1])] = pts[1]
	var count := 0
	for edge_key in seam_edges:
		var pts: Array = edge_points[edge_key]
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[1]
		var ab := b - a
		var len2 := ab.length_squared()
		if len2 <= 1.0e-14:
			continue
		for point_value in unique_points.values():
			var p: Vector3 = point_value
			if p.distance_squared_to(a) <= 1.0e-12 or p.distance_squared_to(b) <= 1.0e-12:
				continue
			var t := (p - a).dot(ab) / len2
			if t <= EPS or t >= 1.0 - EPS:
				continue
			if (a + ab * t).distance_squared_to(p) <= 1.0e-12:
				count += 1
	return count


static func _root_identity_consistent(root_cache: Dictionary, root_position_keys: Dictionary) -> bool:
	for root_id in root_cache.keys():
		var point: Vector3 = root_cache[root_id]
		if String(root_position_keys.get(root_id, "")) != _point_key(point):
			return false
	return true


static func _on_outer_xy(p: Vector3, roi_min: Vector3, roi_max: Vector3) -> bool:
	var px := roundi(p.x * ROOT_QUANT)
	var py := roundi(p.y * ROOT_QUANT)
	return px == roundi(roi_min.x * ROOT_QUANT) \
		or px == roundi(roi_max.x * ROOT_QUANT) \
		or py == roundi(roi_min.y * ROOT_QUANT) \
		or py == roundi(roi_max.y * ROOT_QUANT)


static func _on_outer_y(p: Vector3, roi_min: Vector3, roi_max: Vector3) -> bool:
	var py := roundi(p.y * ROOT_QUANT)
	return py == roundi(roi_min.y * ROOT_QUANT) \
		or py == roundi(roi_max.y * ROOT_QUANT)


static func _on_outer_yz(p: Vector3, roi_min: Vector3, roi_max: Vector3) -> bool:
	# Use the same canonical world-point quantization as topology diagnostics.
	# Exact-zero interpolation can leave a sub-micro-unit float residue even when
	# the canonical point lies exactly on the finite ROI exterior.
	var py := roundi(p.y * ROOT_QUANT)
	var pz := roundi(p.z * ROOT_QUANT)
	return py == roundi(roi_min.y * ROOT_QUANT) \
		or py == roundi(roi_max.y * ROOT_QUANT) \
		or pz == roundi(roi_min.z * ROOT_QUANT) \
		or pz == roundi(roi_max.z * ROOT_QUANT)


static func _index(x: int, y: int, z: int, dims: Vector3i) -> int:
	return (y * dims.z + z) * dims.x + x


static func _point_precedes(a: Vector3, b: Vector3) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


static func _lattice_key(p: Vector3, step: float) -> String:
	return "%d,%d,%d@%d" % [
		roundi(p.x / step), roundi(p.y / step), roundi(p.z / step), roundi(step * ROOT_QUANT)
	]


static func _ordered_pair(a: String, b: String) -> String:
	return a + ">" + b if a < b else b + ">" + a


static func _point_key(p: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(p.x * ROOT_QUANT), roundi(p.y * ROOT_QUANT), roundi(p.z * ROOT_QUANT)
	]


static func _fnv1a_64(text_value: String) -> String:
	var hash: int = 1469598103934665603
	for byte in text_value.to_utf8_buffer():
		hash = hash ^ int(byte)
		hash = hash * 1099511628211
	return "%016x" % hash
