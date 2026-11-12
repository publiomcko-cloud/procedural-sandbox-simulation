class_name ExperimentalB4RadiusStreamPolicy
extends RefCounted

## DM3 presentation-only geometry policy. All coordinates here are GLOBAL
## 4x3-meter chunk indices, never region keys. Unmodified game authority stays
## region-based, within its original 5x5 protected projection footprint.
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const LOAD_RADIUS := 5
const FINE_RADIUS := 4
const KEEP_RADIUS := 10
const KEEP_MICROSECONDS := 20_000_000
const MAX_VISUAL_CACHE_CHUNKS := 320


static func global_for(region: Vector2i, coordinate: Vector2i) -> Vector2i:
	return Vector2i(
		region.x * Grid.CHUNK_COUNT_X + coordinate.x,
		region.y * Grid.CHUNK_COUNT_Z + coordinate.y
	)


static func from_world(world_position: Vector3) -> Vector2i:
	var size := Grid.size_for(Vector2i.ZERO)
	return Vector2i(
		floori(world_position.x / size.x),
		floori(world_position.z / size.z)
	)


static func region_for_global(global_chunk: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(global_chunk.x) / float(Grid.CHUNK_COUNT_X)),
		floori(float(global_chunk.y) / float(Grid.CHUNK_COUNT_Z))
	)


static func chunk_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func regions_for_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var seen: Dictionary = {}
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var region := region_for_global(Vector2i(x, z))
			seen[region] = true
	var result: Array[Vector2i] = []
	for key in seen:
		result.append(key)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ac := Vector2i(a.x * Grid.CHUNK_COUNT_X + 2,
			a.y * Grid.CHUNK_COUNT_Z + 2)
		var bc := Vector2i(b.x * Grid.CHUNK_COUNT_X + 2,
			b.y * Grid.CHUNK_COUNT_Z + 2)
		var da := chunk_distance(center, ac)
		var db := chunk_distance(center, bc)
		return da < db if da != db else (
			a.y < b.y if a.y != b.y else a.x < b.x
		)
	)
	return result


static func mesh_lod(focus: Vector2i, region: Vector2i, chunk: Vector2i) -> int:
	return 0 if chunk_distance(focus, global_for(region, chunk)) <= FINE_RADIUS else 1


static func rank(
	focus: Vector2i, region: Vector2i, chunk: Vector2i,
	forward: Vector3
) -> int:
	var global := global_for(region, chunk)
	var delta := global - focus
	var d := chunk_distance(focus, global)
	var forward2 := Vector2(forward.x, forward.z)
	var direction := Vector2(float(delta.x) * 4.0, float(delta.y) * 3.0)
	var alignment := -1.0
	if direction.length_squared() > 0.00001 and forward2.length_squared() > 0.00001:
		alignment = forward2.normalized().dot(direction.normalized())
	var ahead := alignment >= 0.70
	var category := 5
	if d <= 1:
		category = 0
	elif d <= FINE_RADIUS:
		category = 1 if ahead else 2
	elif d == LOAD_RADIUS:
		category = 3 if ahead else 4
	# Remaining chunks in a region are generated only to preserve the
	# existing region publication/terrain-object contract.
	return category * 100_000 + mini(d, 999) * 100 + roundi((1.0 - alignment) * 40.0)


static func should_keep_visual(
	distance: int, last_near_usec: int, now_usec: int
) -> bool:
	return distance <= KEEP_RADIUS or now_usec - last_near_usec < KEEP_MICROSECONDS
