class_name TerrainChunkGrid
extends RefCounted

## Fixed rendering partition for one finite region; IDs include the parent region.
const MIN_BOUND := Vector3(-1.0, -2.0, -1.0)
const MAX_BOUND := Vector3(17.0, 8.0, 13.0)
const SAMPLE_STEP := 0.5
const CELL_COUNT_X := 36
const CELL_COUNT_Y := 20
const CELL_COUNT_Z := 28
const CHUNK_COUNT_X := 4
const CHUNK_COUNT_Z := 4
const CELLS_PER_CHUNK_X := CELL_COUNT_X / CHUNK_COUNT_X
const CELLS_PER_CHUNK_Z := CELL_COUNT_Z / CHUNK_COUNT_Z


static func all_coordinates() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(CHUNK_COUNT_Z):
		for x in range(CHUNK_COUNT_X):
			result.append(Vector2i(x, z))
	return result


static func is_valid_coordinate(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.x < CHUNK_COUNT_X \
		and coordinate.y >= 0 and coordinate.y < CHUNK_COUNT_Z


static func stable_id(region_key: Vector2i, coordinate: Vector2i) -> String:
	return "region:%d,%d/chunk:%d,%d" % [region_key.x, region_key.y, coordinate.x, coordinate.y]


static func cell_bounds(coordinate: Vector2i) -> Vector4i:
	if not is_valid_coordinate(coordinate):
		return Vector4i.ZERO
	var start_x := coordinate.x * CELLS_PER_CHUNK_X
	var start_z := coordinate.y * CELLS_PER_CHUNK_Z
	# x/z are half-open cell ranges. Both neighbors sample the shared end plane.
	return Vector4i(start_x, start_x + CELLS_PER_CHUNK_X, start_z, start_z + CELLS_PER_CHUNK_Z)


static func origin_for(coordinate: Vector2i) -> Vector3:
	var bounds := cell_bounds(coordinate)
	return Vector3(
		MIN_BOUND.x + float(bounds.x) * SAMPLE_STEP,
		0.0,
		MIN_BOUND.z + float(bounds.z) * SAMPLE_STEP
	)


static func size_for(coordinate: Vector2i) -> Vector3:
	if not is_valid_coordinate(coordinate):
		return Vector3.ZERO
	return Vector3(CELLS_PER_CHUNK_X * SAMPLE_STEP, MAX_BOUND.y - MIN_BOUND.y, CELLS_PER_CHUNK_Z * SAMPLE_STEP)


static func affected_chunks_for_sphere(center: Vector3, radius: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not center.is_finite() or not is_finite(radius) or radius <= 0.0:
		return result
	# One sample-step halo conservatively includes cells that depend on affected lattice samples.
	var extent := Vector3.ONE * (radius + SAMPLE_STEP)
	var brush_min := center - extent
	var brush_max := center + extent
	if brush_max.y < MIN_BOUND.y or brush_min.y > MAX_BOUND.y:
		return result
	for coordinate in all_coordinates():
		var origin := origin_for(coordinate)
		var size := size_for(coordinate)
		var chunk_min := origin
		var chunk_max := origin + size
		if brush_max.x < chunk_min.x or brush_min.x > chunk_max.x:
			continue
		if brush_max.z < chunk_min.z or brush_min.z > chunk_max.z:
			continue
		result.append(coordinate)
	return result


static func is_shared_boundary_vertex(point: Vector3, coordinate: Vector2i, tolerance: float = 0.00001) -> bool:
	if not is_valid_coordinate(coordinate):
		return false
	var bounds := cell_bounds(coordinate)
	var min_x := MIN_BOUND.x + float(bounds.x) * SAMPLE_STEP
	var max_x := MIN_BOUND.x + float(bounds.y) * SAMPLE_STEP
	var min_z := MIN_BOUND.z + float(bounds.z) * SAMPLE_STEP
	var max_z := MIN_BOUND.z + float(bounds.w) * SAMPLE_STEP
	var on_x_boundary := (coordinate.x > 0 and absf(point.x - min_x) <= tolerance) \
		or (coordinate.x < CHUNK_COUNT_X - 1 and absf(point.x - max_x) <= tolerance)
	var on_z_boundary := (coordinate.y > 0 and absf(point.z - min_z) <= tolerance) \
		or (coordinate.y < CHUNK_COUNT_Z - 1 and absf(point.z - max_z) <= tolerance)
	return on_x_boundary or on_z_boundary
