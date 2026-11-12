extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const Shape := preload("res://scripts/objects/procedural_rock_shape_descriptor.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, name: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + name)


func _run() -> void:
	var registry := Registry.new()
	var registered: Dictionary = registry.discover_and_register([
		"res://mods/first-party"
	])
	_check(registered.get("ok", false), "registry available for source-equivalent test")
	if not registered.get("ok", false):
		_finish({})
		return
	var sums: Dictionary = {}
	var counts := 0
	for seed in [1, 17, 101, 31337, 424242, 700100, 700101, 700102,
			700103, 700104, 700105, 2147483646]:
		var recipe: Dictionary = registry.evaluate_rock_recipe(
			"firstparty.core_rocks:granite", seed
		)
		_check(recipe.get("ok", false), "mod geometry recipe")
		if not recipe.get("ok", false):
			continue
		var baseline_timings := {"enabled": true}
		var optimized_timings := {"enabled": true}
		var normal: Dictionary = Shape.build_geometry_data(
			recipe["geometry"], recipe["geometry_seeds"], false, baseline_timings
		)
		var opt: Dictionary = Shape.build_geometry_data(
			recipe["geometry"], recipe["geometry_seeds"], true, optimized_timings
		)
		_check(normal.get("ok", false) and opt.get("ok", false), "profiled geometry validates")
		if not normal.get("ok", false) or not opt.get("ok", false):
			continue
		_check(normal["descriptor"] == opt["descriptor"], "profiled render and optimized authority exact")
		for key in [
			"validate_usec", "prepare_usec", "clip_usec", "triangulate_usec",
			"subdivide_usec", "wear_usec", "roughen_usec", "ground_usec",
			"intersect_usec", "finalize_usec", "total_usec"
		]:
			sums[key] = int(sums.get(key, 0)) + int(baseline_timings.get(key, 0))
		sums["opt_total_usec"] = int(sums.get("opt_total_usec", 0)) + int(optimized_timings.get("total_usec", 0))
		sums["opt_intersect_usec"] = int(sums.get("opt_intersect_usec", 0)) + int(optimized_timings.get("intersect_usec", 0))
		counts += 1
	sums["samples"] = counts
	for key in sums.keys():
		if key.ends_with("_usec"):
			sums[key.trim_suffix("_usec") + "_mean_ms"] = float(sums[key]) / maxf(1.0, float(counts)) / 1000.0
	_finish(sums)


func _finish(timings: Dictionary) -> void:
	if failures == 0 and not timings.is_empty() and int(timings["samples"]) >= 12:
		print("P5_E5_STAGE_PROFILE_PASS: " + JSON.stringify(timings))
		quit(0)
	else:
		push_error("P5_E5_STAGE_PROFILE_FAIL: assertions=" + str(assertions) + " failures=" + str(failures))
		quit(1)
