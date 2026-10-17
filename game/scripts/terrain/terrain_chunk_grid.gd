class_name TerrainChunkGrid
extends RefCounted

## Half-open region cells partitioned into a fixed 4x4 render grid.
const MIN_BOUND := Vector3(0.0, -2.0, 0.0)
const MAX_BOUND := Vector3(16.0, 8.0, 12.0)
const SAMPLE_STEP := 0.5
const CELL_COUNT_X := 32
const CELL_COUNT_Y := 20
const CELL_COUNT_Z := 24
const CHUNK_COUNT_X := 4
const CHUNK_COUNT_Z := 4
const CELLS_PER_CHUNK_X := 8
const CELLS_PER_CHUNK_Z := 6


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
	# End indices are exclusive for cells. Neighboring chunks share the end sample plane.
	return Vector4i(start_x, start_x + CELLS_PER_CHUNK_X, start_z, start_z + CELLS_PER_CHUNK_Z)


static func origin_for(coordinate: Vector2i) -> Vector3:
	var bounds := cell_bounds(coordinate)
	return Vector3(float(bounds.x) * SAMPLE_STEP, 0.0, float(bounds.z) * SAMPLE_STEP)


static func size_for(coordinate: Vector2i) -> Vector3:
	if not is_valid_coordinate(coordinate):
		return Vector3.ZERO
	return Vector3(CELLS_PER_CHUNK_X * SAMPLE_STEP, MAX_BOUND.y - MIN_BOUND.y, CELLS_PER_CHUNK_Z * SAMPLE_STEP)


static func affected_chunks_for_sphere(center: Vector3, radius: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not center.is_finite() or not is_finite(radius) or radius <= 0.0:
		return result
	# One sample-step halo covers cells whose lattice samples can change.
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
	var min_x := float(bounds.x) * SAMPLE_STEP
	var max_x := float(bounds.y) * SAMPLE_STEP
	var min_z := float(bounds.z) * SAMPLE_STEP
	var max_z := float(bounds.w) * SAMPLE_STEP
	# Region-edge chunks are also shared with adjacent regions in the fixed preview.
	var on_x_boundary := absf(point.x - min_x) <= tolerance \
		or absf(point.x - max_x) <= tolerance
	var on_z_boundary := absf(point.z - min_z) <= tolerance \
		or absf(point.z - max_z) <= tolerance
	return on_x_boundary or on_z_boundary
