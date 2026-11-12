extends SceneTree

const Policy := preload("res://scripts/experiments/b4_region_stream_policy.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(Policy.ACTIVE_RADIUS == 6, "HIGH extends to former radius+1")
	_check(Policy.FINE_RADIUS == 6, "no LOW band at edge of HIGH")
	_check(Policy.RETAIN_RADIUS == 10, "retention radius is 10 regions")
	_check(Policy.RETAIN_USEC == 20_000_000, "retention grace is 20 seconds")
	_check(Policy.expected_region_count() == 277, "130m disc has 277 HIGH cells centered")
	_check(Policy.expected_external_region_count() == 268,
		"268 external HIGH plus nine authoritative at center")
	var focus := Vector2i(0, 0)
	var player := Policy.focus_center_world(focus)
	var regions := Policy.desired_regions(focus, Vector3(1, 0, 0), player)
	_check(regions.size() == 268, "priority queue covers 130m circular footprint")
	var counted: Dictionary = {}
	for region in regions:
		_check(Policy.distance(region, focus) >= 2
			and Policy.within_high(region, player),
			"all queued regions in 130m radial footprint")
		_check(Policy.lod_for_distance(Policy.distance(region, focus)) == 0,
			"no dynamic LOW downgrade")
		_check(not counted.has(region), "each region at most once")
		counted[region] = true
	_check(Policy.rank(Vector2i(2,0), focus, Vector3(1,0,0), player)
		< Policy.rank(Vector2i(3,0),focus,Vector3(1,0,0), player),
		"proximity priority dominates farther regions")
	_check(Policy.rank(Vector2i(4,0), focus, Vector3(1,0,0), player)
		< Policy.rank(Vector2i(-4,0),focus,Vector3(1,0,0), player),
		"within same ring camera facing wins")
	for sec in range(0, 61):
		var now := sec * 1_000_000
		_check(Policy.keep(0,now,10), "inside 10 HIGH always retained")
	for sec in range(0, 20):
		var now := sec * 1_000_000
		_check(Policy.keep(0,now,11), "outside 10 but under 20s HIGH retained")
	_check(not Policy.keep(0,20_000_000,11),
		"outside 10 after full 20s is eligible for eviction")
	_check(not Policy.keep(0,29_000_000,20),
		"far outside still only expires after TTL")
	var reentered_at := 30_000_000
	_check(Policy.keep(reentered_at, 49_000_000,17),
		"revisited HIGH keeps new 20s clock")
	_check(not Policy.keep(reentered_at, 50_000_000,17),
		"after 20s outside retention, expire")
	_check(Grid.CHUNK_COUNT_X == 4 and Grid.CHUNK_COUNT_Z == 4,
		"16 chunks per region unchanged")
	print("DM6_HIGH_RETENTION_POLICY_RESULT=" + JSON.stringify({
		"assertions": assertions, "failures": failures,
		"high_regions": Policy.expected_region_count(),
		"high_radius_m": Policy.radial_radius_m(Policy.ACTIVE_RADIUS),
		"rock_radius_m": Policy.radial_radius_m(Policy.ROCK_HIGH_RADIUS),
		"retention_radius_m": Policy.radial_radius_m(Policy.RETAIN_RADIUS),
		"high_external": Policy.expected_external_region_count(),
		"retention_radius": Policy.RETAIN_RADIUS,
		"grace_seconds": float(Policy.RETAIN_USEC) / 1_000_000.0,
		"no_cache_capacity_early_eviction": true,
	}))
	print("DM6_HIGH_RETENTION_POLICY_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("DM6_HIGH_RETENTION_FAIL: "+label)
