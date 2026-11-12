class_name ExperimentalB4RegionStreamPolicy
extends RefCounted

## DM4: all 112 external regions within radius 5 ultimately use the same
## 0.5 m Surface Nets topology as the canonical B4 render chunks. No
## heightfield/LOW mesh is generated. Authority stays in the original 3x3
## load / 5x5 retention, with the 9x9 object-effect source footprint.
const ACTIVE_RADIUS := 5
const FINE_RADIUS := 5
const HIGH_SAMPLE_STEP := 0.5
const RETAIN_RADIUS := 10
const RETAIN_USEC := 20_000_000
const MAX_SHELL_REGIONS := 512
const MAX_DETAILED_VISUAL_REGIONS := 48
const MAX_JOBS_IN_FLIGHT := 2
const RESCAN_USEC := 200_000

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func lod_for_distance(_distance_regions: int) -> int:
	# Always high. There is no fifth-ring downgrade or pending LOD promotion.
	return 0


static func keep(last_near_usec: int, now_usec: int, distance_regions: int) -> bool:
	return distance_regions <= RETAIN_RADIUS \
		or now_usec - last_near_usec < RETAIN_USEC


static func view_alignment(region: Vector2i, focus: Vector2i, forward: Vector3) -> float:
	var diff := region - focus
	var direction := Vector2(float(diff.x) * 16.0, float(diff.y) * 12.0)
	var facing := Vector2(forward.x, forward.z)
	if direction.length_squared() <= 0.00001 \
			or facing.length_squared() <= 0.00001:
		return 0.0
	return direction.normalized().dot(facing.normalized())


static func rank(region: Vector2i, focus: Vector2i, forward: Vector3) -> int:
	var dist := distance(region, focus)
	if dist <= 1:
		# Authoritative centre/near work has absolute priority.
		return dist * 1000
	# Strict nearest-first ring. Within EACH ring, prefer the view cone
	# decisively over lateral / behind. Deterministic y/x tiebreak follows
	# in desired_regions() to eliminate queue-order oscillation.
	var alignment := view_alignment(region, focus, forward)
	var direction_score := roundi((1.0 - alignment) * 10000.0)
	return 1_000_000 + (dist - 2) * 100_000 + direction_score


static func desired_regions(focus: Vector2i, forward: Vector3) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	for z in range(focus.y - ACTIVE_RADIUS, focus.y + ACTIVE_RADIUS + 1):
		for x in range(focus.x - ACTIVE_RADIUS, focus.x + ACTIVE_RADIUS + 1):
			var r := Vector2i(x, z)
			if distance(r, focus) >= 2:
				keys.append(r)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pa := rank(a, focus, forward)
		var pb := rank(b, focus, forward)
		return pa < pb if pa != pb else (
			a.y < b.y if a.y != b.y else a.x < b.x
		)
	)
	return keys
