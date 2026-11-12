class_name ExperimentalB4RegionStreamPolicy
extends RefCounted

## DM8: Euclidean X/Z world-distance, centered on the ACTUAL player/camera,
## rather than square Chebyshev rings around a quantized region focus.
## There is no elevation-based exclusion: the SDF world is indexed in X/Z
## and flying vertically must not evict terrain beneath the player.
## Keep every diagonal cell of the previous square under every position
## within the focus region; therefore radius = (old_radius + 0.5) * 20m,
## where 20m is the diagonal of a 16x12m region.
## These expanded circles are presentation-only. No new authoritative
## region, object scope, effect projection or save is allocated.
const REGION_X_M := 16.0
const REGION_Z_M := 12.0
const ACTIVE_RADIUS := 6          # Legacy square equivalence, not meters.
const FINE_RADIUS := 6
const ROCK_HIGH_RADIUS := 4       # Legacy square equivalence, not meters.
const RETAIN_RADIUS := 10         # Legacy square equivalence, not meters.
const RETAIN_USEC := 20_000_000
const MAX_SHELL_REGIONS := 512  # Warning threshold, NEVER a TTL override.
const MAX_DETAILED_VISUAL_REGIONS := 48 # Warning threshold only.
const MAX_JOBS_IN_FLIGHT := 1
const RESCAN_USEC := 200_000
const COVERAGE_EPSILON_SQ := 0.0001


static func distance(a: Vector2i, b: Vector2i) -> int:
	# Canonical Chebyshev region index used ONLY for legacy core gates.
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func radial_radius_m(legacy_radius: int) -> float:
	# Half a focus cell accounts for the player's *actual* position at any
	# point inside it. No diagonal region that was HIGH in DM7 disappears.
	return (float(legacy_radius) + 0.5) * sqrt(
		REGION_X_M * REGION_X_M + REGION_Z_M * REGION_Z_M
	)


static func center_world(region: Vector2i) -> Vector2:
	return Vector2(
		(float(region.x) + 0.5) * REGION_X_M,
		(float(region.y) + 0.5) * REGION_Z_M
	)


static func focus_center_world(focus: Vector2i) -> Vector3:
	var p := center_world(focus)
	return Vector3(p.x, 0.0, p.y)


static func world_distance_squared(region: Vector2i, player_world: Vector3) -> float:
	var center := center_world(region)
	var dx := center.x - player_world.x
	var dz := center.y - player_world.z
	return dx * dx + dz * dz


static func world_distance_m(region: Vector2i, player_world: Vector3) -> float:
	return sqrt(world_distance_squared(region, player_world))


static func within_radius(region: Vector2i, player_world: Vector3, legacy_radius: int) -> bool:
	var radius := radial_radius_m(legacy_radius)
	return world_distance_squared(region, player_world) <= (
		radius * radius + COVERAGE_EPSILON_SQ
	)


static func within_high(region: Vector2i, player_world: Vector3) -> bool:
	return within_radius(region, player_world, ACTIVE_RADIUS)


static func within_rock_high(region: Vector2i, player_world: Vector3) -> bool:
	return within_radius(region, player_world, ROCK_HIGH_RADIUS)


static func within_retention(region: Vector2i, player_world: Vector3) -> bool:
	return within_radius(region, player_world, RETAIN_RADIUS)


static func lod_for_distance(_distance_regions: int) -> int:
	return 0 # Uniform B4 HIGH, never downgrade a previously HIGH region.


## Historical interface retained for earlier DM3 tests. The runtime DM8
## calls keep_radial() with the player's actual world position instead.
static func keep(last_near_usec: int, now_usec: int, distance_regions: int) -> bool:
	return distance_regions <= RETAIN_RADIUS \
		or now_usec - last_near_usec < RETAIN_USEC


static func keep_radial(
	last_near_usec: int, now_usec: int,
	region: Vector2i, player_world: Vector3
) -> bool:
	return within_retention(region, player_world) \
		or now_usec - last_near_usec < RETAIN_USEC


static func expected_region_count() -> int:
	# Deterministic reference at exact center of region (0,0).
	return desired_regions(
		Vector2i.ZERO, Vector3.FORWARD, focus_center_world(Vector2i.ZERO)
	).size() + 9


static func expected_external_region_count() -> int:
	return expected_region_count() - 9


static func expected_rock_region_count() -> int:
	var focus := Vector2i.ZERO
	var player := focus_center_world(focus)
	return desired_regions(focus, Vector3.FORWARD, player).filter(
		func(key: Vector2i) -> bool: return within_rock_high(key, player)
	).size() + 9


static func rank(
	region: Vector2i, focus: Vector2i, forward: Vector3,
	player_world_position: Variant = null
) -> int:
	var player: Vector3 = (
		player_world_position if player_world_position is Vector3
		else focus_center_world(focus)
	)
	var center := center_world(region)
	var direction := center - Vector2(player.x, player.z)
	var facing := Vector2(forward.x, forward.z)
	var alignment := -1.0
	if direction.length_squared() > 0.00001 and facing.length_squared() > 0.00001:
		alignment = direction.normalized().dot(facing.normalized())
	# Distance dominates direction; 0.1m spacing is sufficient for the
	# deterministic regional queue. Tie-break follows camera facing.
	return roundi(sqrt(direction.length_squared()) * 10000.0) \
		+ roundi((1.0 - alignment) * 100.0)


static func desired_regions(
	focus: Vector2i, forward: Vector3,
	player_world_position: Variant = null
) -> Array[Vector2i]:
	var player: Vector3 = (
		player_world_position if player_world_position is Vector3
		else focus_center_world(focus)
	)
	var keys: Array[Vector2i] = []
	# Search a rectangle enclosing the circular world-distance footprint.
	var range_x := ceili(radial_radius_m(ACTIVE_RADIUS) / REGION_X_M) + 1
	var range_z := ceili(radial_radius_m(ACTIVE_RADIUS) / REGION_Z_M) + 1
	for z in range(focus.y - range_z, focus.y + range_z + 1):
		for x in range(focus.x - range_x, focus.x + range_x + 1):
			var r := Vector2i(x, z)
			if distance(r, focus) >= 2 and within_high(r, player):
				keys.append(r)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pa := rank(a, focus, forward, player)
		var pb := rank(b, focus, forward, player)
		return pa < pb if pa != pb else (a.y < b.y if a.y != b.y else a.x < b.x)
	)
	return keys
