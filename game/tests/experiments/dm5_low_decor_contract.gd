extends SceneTree

## DM5 pure and worker-source tests. Visual ownership and warm-return
## runtime transitions are asserted separately by the Actions F10 route.
const Decor := preload("res://scripts/experiments/b4_low_detail_decor_job.gd")
const Policy := preload("res://scripts/experiments/b4_region_stream_policy.gd")
const Hydro := preload("res://scripts/simulation/environment_hydrology_domain.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed := 424242
	var sea := Decor.build_data(seed, "dm5", Vector2i(0, 11), null)
	var inland := Decor.build_data(seed, "dm5", Vector2i(0, 1), null)
	_check(sea.get("valid", false), "sea LOW geometry generated")
	_check(inland.get("valid", false), "inland LOW generated")
	_check(int(sea.get("ocean_triangles", 0)) > 0, "ocean preview beyond canonical window")
	_check(int(inland.get("ocean_triangles", 0)) == 0, "inland must not fake ocean")
	_check(sea.get("rock_status", "") == "population_registry_not_available",
		"no fabricated rocks without mod registry")
	_check((sea["water_positions"] as PackedVector3Array).size() ==
		(sea["water_colors"] as PackedColorArray).size(),
		"transparent water vertex/color arrays aligned")
	var river_region := Vector2i.ZERO
	var river_cell := Decor.river_center_global_x(seed, 4)
	river_region.x = floori(float(river_cell) / 8.0)
	_check(Decor.river_center_global_x(seed, 4) == river_cell,
		"river preview uses deterministic hydrology meander")
	for x in range(-10, 11):
		var region := Vector2i(x, 0)
		var result := Decor.build_data(seed, "dm5", region, null)
		_check(result.get("valid", false), "water preview valid for negative/positive regions")
		if x == river_region.x:
			_check(int(result.get("river_triangles", 0)) > 0,
				"generated inland river extends outside authoritative window")
	_check(Policy.RETAIN_RADIUS == 10 and Policy.RETAIN_USEC == 20_000_000,
		"10-region / 20-second cache policy preserved")
	_check(Policy.keep(0, 30_000_000, 9), "retain inside radius 10 indefinitely")
	_check(Policy.keep(30_000_000, 49_000_000, 11), "retain for 19s outside radius")
	_check(not Policy.keep(30_000_000, 51_000_000, 11), "evict after 20s outside radius")
	_check(Policy.lod_for_distance(5) == 0, "no LOW terrain on return")
	_check(Field.REGION_SIZE_X == 16.0 and Field.REGION_SIZE_Z == 12.0,
		"base region ownership unaffected")
	print("DM5_LOW_DECOR_RESULT=" + JSON.stringify({
		"assertions": assertions, "failures": failures,
		"sea_triangles": sea.get("ocean_triangles", 0),
		"river_region": [river_region.x, river_region.y],
		"ocean_level_mm": Hydro.OCEAN_LEVEL_MM,
		"cache_radius": Policy.RETAIN_RADIUS,
	}))
	print("DM5_LOW_DECOR_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("DM5_LOW_DECOR_FAIL: " + label)
