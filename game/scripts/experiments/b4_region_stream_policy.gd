class_name ExperimentalB4RegionStreamPolicy
extends RefCounted

## DM3: derived rendering only. The canonical 3x3 load / 5x5 retention
## and the 9x9 object-effect source footprint are not changed.
const ACTIVE_RADIUS := 5
const FINE_RADIUS := 4
const RETAIN_RADIUS := 10
const RETAIN_USEC := 20_000_000
const MAX_SHELL_REGIONS := 512
const MAX_DETAILED_VISUAL_REGIONS := 48
const MAX_JOBS_IN_FLIGHT := 2
const RESCAN_USEC := 200_000

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func lod_for_distance(distance_regions: int) -> int:
	return 0 if distance_regions <= FINE_RADIUS else 1


static func keep(last_near_usec: int, now_usec: int, distance_regions: int) -> bool:
	return distance_regions <= RETAIN_RADIUS \
		or now_usec - last_near_usec < RETAIN_USEC


static func rank(region: Vector2i, focus: Vector2i, forward: Vector3) -> int:
	var diff := region - focus
	var dist := distance(region, focus)
	var ahead: float = -1.0
	var direction := Vector2(float(diff.x) * 16.0, float(diff.y) * 12.0)
	var facing := Vector2(forward.x, forward.z)
	if direction.length_squared() > 0.00001 \
	and facing.length_squared() > 0.00001:
		ahead = direction.normalized().dot(facing.normalized())
	# Canonical focus always wins; forward sector then gets a distance
	# advantage without starving the close flanks indefinitely.
	var sector := 0 if ahead >= 0.75 else (1 if ahead >= 0.25 else 2)
	if dist <= 1:
		return dist * 10
	return sector * 100_000 + dist * 100 + (100 - roundi(ahead * 20.0))


static func desired_regions(focus: Vector2i, forward: Vector3) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	for z in range(focus.y - ACTIVE_RADIUS, focus.y + ACTIVE_RADIUS + 1):
		for x in range(focus.x - ACTIVE_RADIUS, focus.x + ACTIVE_RADIUS + 1):
			var r := Vector2i(x,z)
			if distance(r, focus) >= 2:
				keys.append(r)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pa := rank(a, focus, forward)
		var pb := rank(b, focus, forward)
		return pa < pb if pa != pb else (a.y < b.y if a.y != b.y else a.x < b.x)
	)
	return keys
