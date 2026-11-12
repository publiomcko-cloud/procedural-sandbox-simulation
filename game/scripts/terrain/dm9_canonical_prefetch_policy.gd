extends RefCounted
class_name DM9CanonicalPrefetchPolicy

## DM9: opt-in speculative CPU staging only. No new object/effect authority,
## collision, persistence, or early publication. The 5x5 retained window and
## 9x9 effect source footprint are strictly unchanged.
const REGION_X_M := 16.0
const REGION_Z_M := 12.0
const HORIZON_SECONDS := 3.1 # 18m/s * measured ~3.07s canonical p95
const MAX_SPEED_MPS := 20.0 # Excludes boosted F10 (54 m/s).
const MAX_LEAD_REGIONS := 2
const MAX_SPECULATIVE_REGIONS := 6

static func targets(focus: Vector2i, player: Vector3, velocity: Vector3) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not player.is_finite() or not velocity.is_finite():
		return result
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() < 0.01 or horizontal.length() > MAX_SPEED_MPS:
		return result
	var projected := player + Vector3(velocity.x, 0.0, velocity.z) * HORIZON_SECONDS
	var predicted := Vector2i(
		floori(projected.x / REGION_X_M),
		floori(projected.z / REGION_Z_M)
	)
	var delta := Vector2i(
		clampi(predicted.x - focus.x, -MAX_LEAD_REGIONS, MAX_LEAD_REGIONS),
		clampi(predicted.y - focus.y, -MAX_LEAD_REGIONS, MAX_LEAD_REGIONS)
	)
	# A row/column of three at the retained boundary; no diagonal
	# expansion of authoritative scopes or sources.
	if delta.x != 0:
		var x := focus.x + (MAX_LEAD_REGIONS if delta.x > 0 else -MAX_LEAD_REGIONS)
		for z in range(focus.y - 1, focus.y + 2):
			result.append(Vector2i(x, z))
	if delta.y != 0:
		var z := focus.y + (MAX_LEAD_REGIONS if delta.y > 0 else -MAX_LEAD_REGIONS)
		for x in range(focus.x - 1, focus.x + 2):
			result.append(Vector2i(x, z))
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return result

static func is_inside_core(region: Vector2i, focus: Vector2i) -> bool:
	return maxi(absi(region.x - focus.x), absi(region.y - focus.y)) <= 1

static func valid_revision(
	stage_seed: int, expected_seed: int,
	stage_brush_revision: int, actual_brush_revision: int,
	stage_effect_revision: int, actual_effect_revision: int,
	stage_caves: bool, actual_caves: bool
) -> bool:
	return stage_seed == expected_seed \
		and stage_brush_revision == actual_brush_revision \
		and stage_effect_revision == actual_effect_revision \
		and stage_caves == actual_caves
