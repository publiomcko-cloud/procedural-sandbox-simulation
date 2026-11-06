extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const RockMesh := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const SEEDS := [1, 17, 101, 31337, 91234, 777777]
const LP_POWERS := [2.0, 4.0, 8.0]
const TRANSFORMS := [
	{"name": "identity", "yaw_mdeg": 0, "scale_milli": Vector3i(1000, 1000, 1000)},
	{"name": "yaw45_nonuniform", "yaw_mdeg": 45000, "scale_milli": Vector3i(900, 1100, 1200)},
	{"name": "yaw173_nonuniform", "yaw_mdeg": 173000, "scale_milli": Vector3i(1300, 800, 950)},
]

var assertions := 0
var failures := 0
var evidence: Dictionary = {}
var candidate_aggregate: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := Registry.new()
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repository_root := project_root.get_base_dir()
	var external_root := repository_root.path_join("mods/examples")
	var registration := registry.discover_and_register(["res://mods/first-party", external_root])
	_check(registration.get("ok", false), "first-party and explicit repository example register for characterization")
	if not registration.get("ok", false):
		_finish()
		return

	var synthetic_result := registry.register_discovered(_synthetic_discovery())
	_check(synthetic_result.get("ok", false), "synthetic independent geological profile registers without engine changes")
	if not synthetic_result.get("ok", false):
		_finish()
		return

	var sdf_sign := _characterize_sdf_sign()
	evidence["sdf_sign"] = sdf_sign
	_check(sdf_sign.get("ok", false), "canonical SDF sign is positive solid / negative empty")
	_check(sdf_sign.get("subtract_center_density", 1.0) < 0.0, "subtract-solid semantics reduce density to empty inside cutter")

	var definition_ids := [
		"firstparty.core_rocks:granite",
		"official.example.procedural_rock:basalt_stack",
		"phasea.synthetic:weathered_block",
	]
	var definitions: Dictionary = {}
	for definition_id in definition_ids:
		var resolved := registry.resolve_terrain_interaction(definition_id)
		_check(resolved.get("ok", false) and not resolved.get("rule", {}).is_empty(), "%s has a pinned terrain-interaction rule" % definition_id)
		if not resolved.get("ok", false) or resolved.get("rule", {}).is_empty():
			continue
		var interaction: Dictionary = resolved["rule"]
		var embed_m := float(interaction["embed_depth_mm"]) / 1000.0
		var definition_evidence := {
			"profile": registry.get_definition(definition_id).get("recipe", {}).get("profile", ""),
			"embed_depth_mm": int(interaction["embed_depth_mm"]),
			"blend_radius_mm": int(interaction["blend_radius_mm"]),
			"samples": [],
		}
		for seed in SEEDS:
			var recipe_result := registry.evaluate_rock_recipe(definition_id, seed)
			_check(recipe_result.get("ok", false), "%s seed %d evaluates deterministically" % [definition_id, seed])
			if not recipe_result.get("ok", false):
				continue
			var geometry: Dictionary = recipe_result["geometry"]
			var cpu := RockMesh.build_cpu_data(geometry, recipe_result["geometry_seeds"])
			_check(cpu.get("ok", false), "%s seed %d builds CPU geometry" % [definition_id, seed])
			if not cpu.get("ok", false):
				continue
			var positions: PackedVector3Array = cpu["positions"]
			var bounds_min: Vector3 = cpu["bounds_min"]
			var bounds_max: Vector3 = cpu["bounds_max"]
			_check(absf(bounds_min.y) <= 0.000001, "%s seed %d keeps local minY grounded at zero" % [definition_id, seed])
			var half := Vector3(
				float(geometry["half_extent_x_mm"]),
				float(geometry["half_extent_y_mm"]),
				float(geometry["half_extent_z_mm"])
			) / 1000.0
			var cross_points := _triangle_plane_points(positions, embed_m)
			var hull := _convex_hull(cross_points)
			var hull_area := _polygon_area(hull)
			_check(hull.size() >= 3 and hull_area > 0.000001, "%s seed %d intersects the embed plane with measurable contact section" % [definition_id, seed])
			var sample := {
				"seed": seed,
				"triangle_count": int(cpu["triangle_count"]),
				"bounds_min": bounds_min,
				"bounds_max": bounds_max,
				"recipe_half_extents": half,
				"recipe_box_overrun": _recipe_box_overrun(positions, half),
				"embed_cross_section_point_count": cross_points.size(),
				"embed_cross_section_hull_area_m2": hull_area,
				"candidate_sections": {},
				"transforms": [],
			}
			for power in LP_POWERS:
				var key := "lp%d" % int(power)
				var candidate_area := _lp_cross_section_area(half, embed_m, power)
				var coverage := _lp_point_coverage(cross_points, half, embed_m, power)
				var overcut_ratio := candidate_area / hull_area if hull_area > 0.000001 else INF
				sample["candidate_sections"][key] = {
					"area_m2": candidate_area,
					"point_coverage": coverage,
					"area_over_hull_ratio": overcut_ratio,
				}
				_accumulate_candidate(key, coverage, overcut_ratio)
			var box_area := 4.0 * half.x * half.z if embed_m >= 0.0 and embed_m <= half.y * 2.0 else 0.0
			var box_coverage := _box_point_coverage(cross_points, half)
			var box_ratio := box_area / hull_area if hull_area > 0.000001 else INF
			sample["candidate_sections"]["box"] = {
				"area_m2": box_area,
				"point_coverage": box_coverage,
				"area_over_hull_ratio": box_ratio,
			}
			_accumulate_candidate("box", box_coverage, box_ratio)
			for transform_value in TRANSFORMS:
				sample["transforms"].append(_transform_metrics(positions, embed_m, transform_value))
			definition_evidence["samples"].append(sample)
		definitions[definition_id] = definition_evidence
	evidence["definitions"] = definitions
	evidence["candidate_summary"] = _candidate_summary()
	evidence["candidate_decision"] = _candidate_decision()
	print("ISSUE108_PHASE_A_CHARACTERIZATION=" + JSON.stringify(evidence))
	_finish()


func _synthetic_discovery() -> Dictionary:
	var definition := {
		"schema_version": 2,
		"type": "procedural_rock",
		"id": "phasea.synthetic:weathered_block",
		"display_name": "Phase A Weathered Block",
		"tags": ["rock", "phase_a"],
		"recipe": {
			"algorithm": "geological_halfspace_v1",
			"profile": "phasea_weathered_block_v1",
			"half_extent_x_mm": 650,
			"half_extent_y_mm": 700,
			"half_extent_z_mm": 620,
			"primary_plane_count": 7,
			"fracture_plane_count": 3,
			"anisotropy_axis": "x",
			"anisotropy_milli": 1200,
			"bevel_count": 3,
			"weathering_milli": 500,
			"macro_roughness_mm": 35,
			"meso_roughness_mm": 18,
			"fine_roughness_mm": 7,
		},
	}
	var interaction := {
		"schema_version": 1,
		"type": "terrain_interaction_rule",
		"id": "phasea.synthetic:weathered_ground",
		"definition_id": "phasea.synthetic:weathered_block",
		"algorithm": "sdf_ground_imprint_v1",
		"shape_source": "recipe_envelope_v1",
		"operation": "subtract_solid_v1",
		"embed_depth_mm": 240,
		"blend_radius_mm": 160,
		"edit_order": "terrain_edits_then_imprint_v1",
	}
	var manifest := {
		"id": "phasea.synthetic",
		"version": "1.0.0",
		"schema_version": 1,
		"requires_engine": "4.7.2",
		"dependencies": [],
		"content_roots": ["objects/", "interactions/"],
		"script_policy": "data_only",
	}
	return {
		"ok": true,
		"packages": [{
			"manifest": manifest,
			"definitions": [definition],
			"population_rules": [],
			"terrain_interactions": [interaction],
		}],
	}


func _characterize_sdf_sign() -> Dictionary:
	var region := Vector2i.ZERO
	var x := 8.0
	var z := 5.0
	var upper_y := 8.0
	var upper_d := Field.sample_density(424242, region, Vector3(x, upper_y, z), false)
	var hit_y := NAN
	var prior_y := upper_y
	var prior_d := upper_d
	for i in range(1, 200):
		var y := upper_y - float(i) * 0.05
		var d := Field.sample_density(424242, region, Vector3(x, y, z), false)
		if prior_d < 0.0 and d >= 0.0:
			var lo := y
			var hi := prior_y
			for _j in range(20):
				var mid := (lo + hi) * 0.5
				var md := Field.sample_density(424242, region, Vector3(x, mid, z), false)
				if md >= 0.0:
					lo = mid
				else:
					hi = mid
			hit_y = (lo + hi) * 0.5
			break
		prior_y = y
		prior_d = d
	if not is_finite(hit_y):
		return {"ok": false, "reason": "surface_not_found"}
	var below := Field.sample_density(424242, region, Vector3(x, hit_y - 0.1, z), false)
	var above := Field.sample_density(424242, region, Vector3(x, hit_y + 0.1, z), false)
	var base_at_cutter_center := Field.sample_density(424242, region, Vector3(x, hit_y - 0.05, z), false)
	var cutter_distance := -0.25
	var subtract_density := minf(base_at_cutter_center, cutter_distance)
	return {
		"ok": below > 0.0 and above < 0.0,
		"surface_y": hit_y,
		"below_density": below,
		"above_density": above,
		"base_at_cutter_center": base_at_cutter_center,
		"subtract_center_density": subtract_density,
	}


func _recipe_box_overrun(positions: PackedVector3Array, half: Vector3) -> Dictionary:
	var over_x := 0.0
	var over_y_low := 0.0
	var over_y_high := 0.0
	var over_z := 0.0
	for p in positions:
		over_x = maxf(over_x, absf(p.x) - half.x)
		over_y_low = maxf(over_y_low, -p.y)
		over_y_high = maxf(over_y_high, p.y - half.y * 2.0)
		over_z = maxf(over_z, absf(p.z) - half.z)
	return {
		"x_mm": maxf(0.0, over_x) * 1000.0,
		"y_low_mm": maxf(0.0, over_y_low) * 1000.0,
		"y_high_mm": maxf(0.0, over_y_high) * 1000.0,
		"z_mm": maxf(0.0, over_z) * 1000.0,
	}


func _triangle_plane_points(positions: PackedVector3Array, plane_y: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for index in range(0, positions.size(), 3):
		if index + 2 >= positions.size():
			break
		_append_edge_plane_points(result, positions[index], positions[index + 1], plane_y)
		_append_edge_plane_points(result, positions[index + 1], positions[index + 2], plane_y)
		_append_edge_plane_points(result, positions[index + 2], positions[index], plane_y)
	return result


func _append_edge_plane_points(result: Array[Vector2], a: Vector3, b: Vector3, plane_y: float) -> void:
	var da := a.y - plane_y
	var db := b.y - plane_y
	var eps := 0.000001
	if absf(da) <= eps:
		_append_unique_2d(result, Vector2(a.x, a.z))
	if absf(db) <= eps:
		_append_unique_2d(result, Vector2(b.x, b.z))
	if da * db < 0.0:
		var t := da / (da - db)
		var p := a.lerp(b, t)
		_append_unique_2d(result, Vector2(p.x, p.z))


func _append_unique_2d(points: Array[Vector2], point: Vector2) -> void:
	for existing in points:
		if existing.distance_squared_to(point) <= 0.0000000001:
			return
	points.append(point)


func _convex_hull(points: Array[Vector2]) -> Array[Vector2]:
	if points.size() <= 2:
		return points.duplicate()
	var sorted := points.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x or (is_equal_approx(a.x, b.x) and a.y < b.y)
	)
	var lower: Array[Vector2] = []
	for p in sorted:
		while lower.size() >= 2 and _cross2(lower[-2], lower[-1], p) <= 0.000000001:
			lower.pop_back()
		lower.append(p)
	var upper: Array[Vector2] = []
	for index in range(sorted.size() - 1, -1, -1):
		var p: Vector2 = sorted[index]
		while upper.size() >= 2 and _cross2(upper[-2], upper[-1], p) <= 0.000000001:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	lower.append_array(upper)
	return lower


func _cross2(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


func _polygon_area(points: Array[Vector2]) -> float:
	if points.size() < 3:
		return 0.0
	var twice := 0.0
	for index in range(points.size()):
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		twice += a.x * b.y - b.x * a.y
	return absf(twice) * 0.5


func _lp_cross_section_area(half: Vector3, local_y: float, power: float) -> float:
	var vertical := absf((local_y - half.y) / half.y)
	if vertical >= 1.0:
		return 0.0
	var section_scale := pow(1.0 - pow(vertical, power), 1.0 / power)
	var points: Array[Vector2] = []
	var samples := 720
	for index in range(samples):
		var angle := TAU * float(index) / float(samples)
		var cx := cos(angle)
		var sz := sin(angle)
		var denominator := pow(absf(cx) / half.x, power) + pow(absf(sz) / half.z, power)
		var radius := section_scale / pow(denominator, 1.0 / power)
		points.append(Vector2(cx * radius, sz * radius))
	return _polygon_area(points)


func _lp_point_coverage(points: Array[Vector2], half: Vector3, local_y: float, power: float) -> float:
	if points.is_empty():
		return 0.0
	var vertical := absf((local_y - half.y) / half.y)
	var inside := 0
	for p in points:
		var value := pow(absf(p.x) / half.x, power) + pow(absf(p.y) / half.z, power) + pow(vertical, power)
		if value <= 1.000001:
			inside += 1
	return float(inside) / float(points.size())


func _box_point_coverage(points: Array[Vector2], half: Vector3) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for p in points:
		if absf(p.x) <= half.x + 0.000001 and absf(p.y) <= half.z + 0.000001:
			inside += 1
	return float(inside) / float(points.size())


func _transform_metrics(positions: PackedVector3Array, embed_m: float, transform_value: Dictionary) -> Dictionary:
	var scale_milli: Vector3i = transform_value["scale_milli"]
	var scale := Vector3(scale_milli) / 1000.0
	var yaw := float(transform_value["yaw_mdeg"]) * PI / 180000.0
	var basis := Basis(Vector3.UP, yaw)
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var buried := 0
	for p in positions:
		var transformed := basis * (p * scale)
		transformed.y -= embed_m
		minimum = minimum.min(transformed)
		maximum = maximum.max(transformed)
		if transformed.y < 0.0:
			buried += 1
	return {
		"name": transform_value["name"],
		"yaw_mdeg": int(transform_value["yaw_mdeg"]),
		"scale_milli": scale_milli,
		"effective_anchor_offset": Vector3(0.0, -embed_m, 0.0),
		"bounds_min": minimum,
		"bounds_max": maximum,
		"buried_vertex_fraction": float(buried) / float(positions.size()),
	}


func _accumulate_candidate(name: String, coverage: float, overcut_ratio: float) -> void:
	var record: Dictionary = candidate_aggregate.get(name, {
		"count": 0,
		"coverage_sum": 0.0,
		"coverage_min": 1.0,
		"overcut_sum": 0.0,
		"overcut_max": 0.0,
	})
	record["count"] = int(record["count"]) + 1
	record["coverage_sum"] = float(record["coverage_sum"]) + coverage
	record["coverage_min"] = minf(float(record["coverage_min"]), coverage)
	record["overcut_sum"] = float(record["overcut_sum"]) + overcut_ratio
	record["overcut_max"] = maxf(float(record["overcut_max"]), overcut_ratio)
	candidate_aggregate[name] = record


func _candidate_summary() -> Dictionary:
	var result: Dictionary = {}
	for name in candidate_aggregate:
		var record: Dictionary = candidate_aggregate[name]
		var count := maxi(1, int(record["count"]))
		result[name] = {
			"samples": count,
			"mean_coverage": float(record["coverage_sum"]) / float(count),
			"minimum_coverage": float(record["coverage_min"]),
			"mean_area_over_hull_ratio": float(record["overcut_sum"]) / float(count),
			"maximum_area_over_hull_ratio": float(record["overcut_max"]),
		}
	return result


func _candidate_decision() -> Dictionary:
	var summary := _candidate_summary()
	var best := ""
	var best_ratio := INF
	for name in summary:
		var record: Dictionary = summary[name]
		if float(record["minimum_coverage"]) < 0.995:
			continue
		var ratio := float(record["mean_area_over_hull_ratio"])
		if ratio < best_ratio:
			best = name
			best_ratio = ratio
	if best.is_empty():
		return {
			"simple_envelope_qualified": false,
			"reason": "no candidate reached 99.5% contact-section coverage across every profile/seed; characterize an analytic half-space-derived envelope before runtime integration",
		}
	return {
		"simple_envelope_qualified": true,
		"candidate": best,
		"mean_area_over_hull_ratio": best_ratio,
		"note": "qualification is geometric characterization only; runtime integration still requires explicit owner review",
	}


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("ISSUE108_PHASE_A_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
