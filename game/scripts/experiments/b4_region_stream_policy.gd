class_name ExperimentalB4RegionStreamPolicy
extends RefCounted

## DM4: uniform full-resolution B4 visual halo. Derived rendering only. The canonical 3x3 load / 5x5 retention
## and the 9x9 object-effect source footprint are not changed.
const ACTIVE_RADIUS := 6
const FINE_RADIUS := 6
const RETAIN_RADIUS := 10
const RETAIN_USEC := 20_000_000
const MAX_SHELL_REGIONS := 512 # DM6 warning threshold only; NEVER evict retained HIGH
const MAX_DETAILED_VISUAL_REGIONS := 48 # Warning threshold only; NEVER evict retained HIGH
const MAX_JOBS_IN_FLIGHT := 1
const RESCAN_USEC := 200_000

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func lod_for_distance(distance_regions: int) -> int:
	return 0 # Uniform B4 HIGH in every region; no mismatched LOW band.


## Retained HIGH can be evicted ONLY when BOTH outside radius 10
## AND absent from that radius for at least 20s; no independent hard cap.
static func keep(last_near_usec: int, now_usec: int, distance_regions: int) -> bool:
	return distance_regions <= RETAIN_RADIUS \
		or now_usec - last_near_usec < RETAIN_USEC


static func expected_region_count() -> int:
	return (ACTIVE_RADIUS * 2 + 1) * (ACTIVE_RADIUS * 2 + 1)


static func expected_external_region_count() -> int:
	return expected_region_count() - 9


static func rank(region: Vector2i, focus: Vector2i, forward: Vector3) -> int:
	var diff := region - focus
	var dist := distance(region, focus)
	var direction := Vector2(float(diff.x) * 16.0, float(diff.y) * 12.0)
	var facing := Vector2(forward.x, forward.z)
	var alignment := -1.0
	if direction.length_squared() > 0.00001 \
			and facing.length_squared() > 0.00001:
		alignment = direction.normalized().dot(facing.normalized())
	# Strict near-first dispatch: never spend CPU on a farther ring while
	# a closer one is waiting. Inside each ring, camera forward wins first.
	# Stable tie-breaking is handled by desired_regions().
	return dist * 10000 + roundi((1.0 - alignment) * 1000.0)


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
