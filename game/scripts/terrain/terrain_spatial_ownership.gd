class_name TerrainSpatialOwnership
extends RefCounted

## Pure coordinate mapping for the fixed region lattice; no scene nodes or streaming.
const REGION_SIZE_X := 16.0
const REGION_SIZE_Z := 12.0
const CELLS_PER_REGION_X := 32
const CELLS_PER_REGION_Z := 24
const PREVIEW_RADIUS := 1


static func world_to_region_local(world_position: Vector3) -> Dictionary:
	if not world_position.is_finite():
		return {"valid": false, "region_key": Vector2i.ZERO, "local_position": Vector3.ZERO}
	var region_key := Vector2i(
		floori(world_position.x / REGION_SIZE_X),
		floori(world_position.z / REGION_SIZE_Z)
	)
	var local_position := Vector3(
		world_position.x - float(region_key.x) * REGION_SIZE_X,
		world_position.y,
		world_position.z - float(region_key.y) * REGION_SIZE_Z
	)
	return {"valid": true, "region_key": region_key, "local_position": local_position}


static func region_local_to_world(region_key: Vector2i, local_position: Vector3) -> Vector3:
	return Vector3(
		float(region_key.x) * REGION_SIZE_X + local_position.x,
		local_position.y,
		float(region_key.y) * REGION_SIZE_Z + local_position.z
	)


static func region_origin_world(region_key: Vector2i) -> Vector3:
	return Vector3(float(region_key.x) * REGION_SIZE_X, 0.0, float(region_key.y) * REGION_SIZE_Z)


static func region_key_for_cell(world_cell_x: int, world_cell_z: int) -> Vector2i:
	return Vector2i(
	_floor_divide(world_cell_x, CELLS_PER_REGION_X),
	_floor_divide(world_cell_z, CELLS_PER_REGION_Z)
	)


static func region_local_cell(world_cell_x: int, world_cell_z: int) -> Vector2i:
	var key := region_key_for_cell(world_cell_x, world_cell_z)
	return Vector2i(
		world_cell_x - key.x * CELLS_PER_REGION_X,
		world_cell_z - key.y * CELLS_PER_REGION_Z
	)


static func chunk_for_region_cell(local_cell: Vector2i) -> Vector2i:
	if local_cell.x < 0 or local_cell.x >= CELLS_PER_REGION_X \
		or local_cell.y < 0 or local_cell.y >= CELLS_PER_REGION_Z:
		return Vector2i(-1, -1)
	return Vector2i(
		floori(float(local_cell.x) / float(TerrainChunkGrid.CELLS_PER_CHUNK_X)),
		floori(float(local_cell.y) / float(TerrainChunkGrid.CELLS_PER_CHUNK_Z))
	)


static func owns_world_cell(region_key: Vector2i, chunk_coordinate: Vector2i, world_cell: Vector2i) -> bool:
	if not TerrainChunkGrid.is_valid_coordinate(chunk_coordinate):
		return false
	if region_key_for_cell(world_cell.x, world_cell.y) != region_key:
		return false
	return chunk_for_region_cell(region_local_cell(world_cell.x, world_cell.y)) == chunk_coordinate


static func preview_region_keys() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(-PREVIEW_RADIUS, PREVIEW_RADIUS + 1):
		for x in range(-PREVIEW_RADIUS, PREVIEW_RADIUS + 1):
			result.append(Vector2i(x, z))
	return result


static func _floor_divide(value: int, divisor: int) -> int:
	# Integer division truncates toward zero, so shift negative nonmultiples down one region.
	var quotient: int = value / divisor
	if value < 0 and value % divisor != 0:
		quotient -= 1
	return quotient
