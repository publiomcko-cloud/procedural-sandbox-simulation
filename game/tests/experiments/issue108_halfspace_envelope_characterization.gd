extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const RockMesh := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")

const SEEDS := [1, 17, 101, 31337, 91234, 777777]
const RAND_MOD := 2147483647
const EPS := 0.000001

var assertions := 0
var failures := 0
var evidence: Dictionary = {}
var aggregate := {
	"samples": 0,
	"required_margin_mm_sum": 0.0,
	"required_margin_mm_max": 0.0,
	"uninflated_coverage_sum": 0.0,
	"configured_coverage_sum": 0.0,
	"configured_coverage_min": 1.0,
	"required_area_ratio_sum": 0.0,
	"required_area_ratio_max": 0.0,
	"configured_area_ratio_sum": 0.0,
	"configured_area_ratio_max": 0.0,
	"configured_bound_contains_required": 0,
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := Registry.new()
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var external_root := project_root.get_base_dir().path_join("mods/examples")
	var registration := registry.discover_and_register(["res://mods/first-party", external_root])
	_check(registration.get("ok", false), "characterization registry loads first-party and explicit external example")
	if not registration.get("ok", false):
		_finish()
		return
	var synthetic := registry.register_discovered(_synthetic_discovery())
	_check(synthetic.get("ok", false), "independent synthetic profile registers for half-space characterization")
	if not synthetic.get("ok", false):
		_finish()
		return

	var definitions: Dictionary = {}
	for definition_id in [
		"firstparty.core_rocks:granite",
		"official.example.procedural_rock:basalt_stack",
		"phasea.synthetic:weathered_block",
	]:
		var interaction_result := registry.resolve_terrain_interaction(definition_id)
		_check(interaction_result.get("ok", false) and not interaction_result.get("rule", {}).is_empty(), "%s resolves interaction" % definition_id)
		if not interaction_result.get("ok", false) or interaction_result.get("rule", {}).is_empty():
			continue
		var interaction: Dictionary = interaction_result["rule"]
		var embed_m := float(interaction["embed_depth_mm"]) / 1000.0
		var samples: Array[Dictionary] = []
		for seed in SEEDS:
			var recipe_result := registry.evaluate_rock_recipe(definition_id, seed)
			_check(recipe_result.get("ok", false), "%s seed %d recipe evaluates" % [definition_id, seed])
			if not recipe_result.get("ok", false):
				continue
			var geometry: Dictionary = recipe_result["geometry"]
			var cpu := RockMesh.build_cpu_data(geometry, recipe_result["geometry_seeds"])
			_check(cpu.get("ok", false), "%s seed %d CPU geometry builds" % [definition_id, seed])
			if not cpu.get("ok", false):
				continue
			var descriptor := _build_descriptor(geometry, recipe_result["geometry_seeds"])
			_check(descriptor.get("ok", false), "%s seed %d analytic half-space descriptor builds" % [definition_id, seed])
			if not descriptor.get("ok", false):
				continue
			var positions: PackedVector3Array = cpu["positions"]
			var cross_points := _triangle_plane_points(positions, embed_m)
			var actual_hull := _convex_hull(cross_points)
			var actual_area := _polygon_area(actual_hull)
			_check(actual_area > EPS, "%s seed %d has measurable contact section" % [definition_id, seed])
			if actual_area <= EPS:
				continue
			var planes: Array[Dictionary] = descriptor["planes"]
			var required_margin := maxf(0.0, _required_margin(cross_points, embed_m, planes))
			var configured_margin := (
				float(geometry["macro_roughness_mm"])
				+ float(geometry["meso_roughness_mm"])
				+ float(geometry["fine_roughness_mm"])
			) / 1000.0
			var uninflated := _section_metrics(cross_points, actual_area, planes, embed_m, 0.0)
			var required := _section_metrics(cross_points, actual_area, planes, embed_m, required_margin + 0.000001)
			var configured := _section_metrics(cross_points, actual_area, planes, embed_m, configured_margin)
			var bound_contains := required_margin <= configured_margin + 0.000001
			var sample := {
				"seed": seed,
				"base_ground_shift_mm": float(descriptor["base_ground_shift"]) * 1000.0,
				"plane_count": planes.size(),
				"actual_contact_hull_area_m2": actual_area,
				"actual_contact_point_count": cross_points.size(),
				"required_plane_margin_mm": required_margin * 1000.0,
				"configured_roughness_amplitude_mm": configured_margin * 1000.0,
				"configured_bound_contains_required": bound_contains,
				"uninflated": uninflated,
				"minimal_observed_margin": required,
				"configured_amplitude_margin": configured,
			}
			samples.append(sample)
			_accumulate(sample)
		definitions[definition_id] = {
			"profile": registry.get_definition(definition_id).get("recipe", {}).get("profile", ""),
			"embed_depth_mm": int(interaction["embed_depth_mm"]),
			"blend_radius_mm": int(interaction["blend_radius_mm"]),
			"samples": samples,
		}
	evidence["definitions"] = definitions
	evidence["summary"] = _summary()
	evidence["decision"] = _decision()
	print("ISSUE108_PHASE_A_HALFSPACE=" + JSON.stringify(evidence))
	_finish()


func _build_descriptor(recipe: Dictionary, seeds: Dictionary) -> Dictionary:
	var half := Vector3(
		float(recipe["half_extent_x_mm"]),
		float(recipe["half_extent_y_mm"]),
		float(recipe["half_extent_z_mm"])
	) / 1000.0
	var center := Vector3(0.0, half.y, 0.0)
	var planes: Array[Dictionary] = [
		{"normal": Vector3.RIGHT, "distance": half.x},
		{"normal": Vector3.LEFT, "distance": half.x},
		{"normal": Vector3.UP, "distance": half.y * 2.0},
		{"normal": Vector3.DOWN, "distance": 0.0},
		{"normal": Vector3.BACK, "distance": half.z},
		{"normal": Vector3.FORWARD, "distance": half.z},
	]

	var structure_state := int(seeds["structure"])
	for _index in range(int(recipe["primary_plane_count"])):
		var sampled := _random_unit(structure_state)
		structure_state = int(sampled["state"])
		var normal: Vector3 = sampled["vector"]
		var fraction := 0.64 + _random_unit_float(structure_state) * 0.20
		structure_state = _next_random(structure_state)
		planes.append({
			"normal": normal,
			"distance": center.dot(normal) + _support_distance(normal, half) * fraction,
		})

	var fracture_state := int(seeds["fracture"])
	var preferred_axis := _axis_index(String(recipe["anisotropy_axis"]))
	for _index in range(int(recipe["fracture_plane_count"])):
		var sampled := _random_unit(fracture_state)
		fracture_state = int(sampled["state"])
		var normal: Vector3 = sampled["vector"]
		var attenuation := 1.0 - float(recipe["anisotropy_milli"]) / 2000.0
		normal[preferred_axis] *= attenuation
		if normal.length_squared() < 0.04:
			normal[preferred_axis] = 0.35
		normal = normal.normalized()
		var fraction := 0.62 + _random_unit_float(fracture_state) * 0.20
		fracture_state = _next_random(fracture_state)
		planes.append({
			"normal": normal,
			"distance": center.dot(normal) + _support_distance(normal, half) * fraction,
		})

	var wear_state := int(seeds["wear"])
	for _index in range(int(recipe["bevel_count"])):
		var signs := Vector3(
			-1.0 if _random_bit(wear_state) == 0 else 1.0,
			-1.0 if _random_bit(_next_random(wear_state)) == 0 else 1.0,
			-1.0 if _random_bit(_next_random(_next_random(wear_state))) == 0 else 1.0
		)
		wear_state = _next_random(_next_random(_next_random(wear_state)))
		var normal := Vector3(signs.x / half.x, signs.y / half.y, signs.z / half.z).normalized()
		var bevel_fraction := 0.055 + _random_unit_float(wear_state) * 0.065
		wear_state = _next_random(wear_state)
		planes.append({
			"normal": normal,
			"distance": center.dot(normal) + _support_distance(normal, half) * (1.0 - bevel_fraction),
		})

	var vertices := _intersection_vertices(planes)
	if vertices.size() < 4:
		return {"ok": false, "reason": "analytic_polyhedron_empty"}
	var lowest_y := INF
	for vertex in vertices:
		lowest_y = minf(lowest_y, vertex.y)
	var grounded: Array[Dictionary] = []
	for plane in planes:
		var normal: Vector3 = plane["normal"]
		grounded.append({
			"normal": normal,
			"distance": float(plane["distance"]) - normal.y * lowest_y,
		})
	return {
		"ok": true,
		"planes": grounded,
		"base_ground_shift": lowest_y,
		"base_vertex_count": vertices.size(),
	}


func _intersection_vertices(planes: Array[Dictionary]) -> Array[Vector3]:
	var vertices: Array[Vector3] = []
	for i in range(planes.size() - 2):
		var a: Vector3 = planes[i]["normal"]
		var da := float(planes[i]["distance"])
		for j in range(i + 1, planes.size() - 1):
			var b: Vector3 = planes[j]["normal"]
			var db := float(planes[j]["distance"])
			for k in range(j + 1, planes.size()):
				var c: Vector3 = planes[k]["normal"]
				var dc := float(planes[k]["distance"])
				var determinant := a.dot(b.cross(c))
				if absf(determinant) <= 0.00000001:
					continue
				var point := (
					b.cross(c) * da
					+ c.cross(a) * db
					+ a.cross(b) * dc
				) / determinant
				if not point.is_finite() or not _inside_planes(point, planes, 0.00001):
					continue
				_append_unique_3d(vertices, point)
	return vertices


func _inside_planes(point: Vector3, planes: Array[Dictionary], margin: float) -> bool:
	for plane in planes:
		var normal: Vector3 = plane["normal"]
		if normal.dot(point) > float(plane["distance"]) + margin:
			return false
	return true


func _required_margin(points: Array[Vector2], local_y: float, planes: Array[Dictionary]) -> float:
	var required := 0.0
	for p in points:
		var point := Vector3(p.x, local_y, p.y)
		for plane in planes:
			var normal: Vector3 = plane["normal"]
			required = maxf(required, normal.dot(point) - float(plane["distance"]))
	return required


func _section_metrics(
	actual_points: Array[Vector2],
	actual_area: float,
	planes: Array[Dictionary],
	local_y: float,
	margin: float
) -> Dictionary:
	var polygon := _section_polygon(planes, local_y, margin)
	var area := _polygon_area(polygon)
	var inside := 0
	for p in actual_points:
		var point := Vector3(p.x, local_y, p.y)
		if _inside_planes(point, planes, margin + 0.000001):
			inside += 1
	return {
		"margin_mm": margin * 1000.0,
		"point_coverage": float(inside) / float(actual_points.size()) if not actual_points.is_empty() else 0.0,
		"area_m2": area,
		"area_over_actual_hull_ratio": area / actual_area if actual_area > EPS else INF,
		"polygon_vertex_count": polygon.size(),
	}


func _section_polygon(planes: Array[Dictionary], local_y: float, margin: float) -> Array[Vector2]:
	var limit := 10.0
	var polygon: Array[Vector2] = [
		Vector2(-limit, -limit),
		Vector2(limit, -limit),
		Vector2(limit, limit),
		Vector2(-limit, limit),
	]
	for plane in planes:
		var normal: Vector3 = plane["normal"]
		var rhs := float(plane["distance"]) + margin - normal.y * local_y
		if absf(normal.x) + absf(normal.z) <= 0.00000001:
			if rhs < -EPS:
				return []
			continue
		polygon = _clip_polygon_2d(polygon, normal.x, normal.z, rhs)
		if polygon.is_empty():
			return polygon
	return polygon


func _clip_polygon_2d(input: Array[Vector2], a: float, b: float, rhs: float) -> Array[Vector2]:
	var output: Array[Vector2] = []
	if input.is_empty():
		return output
	for index in range(input.size()):
		var current := input[index]
		var previous := input[posmod(index - 1, input.size())]
		var current_delta := a * current.x + b * current.y - rhs
		var previous_delta := a * previous.x + b * previous.y - rhs
		var current_inside := current_delta <= EPS
		var previous_inside := previous_delta <= EPS
		if current_inside != previous_inside:
			var denominator := previous_delta - current_delta
			if absf(denominator) > 0.0000000001:
				var t := previous_delta / denominator
				output.append(previous.lerp(current, clampf(t, 0.0, 1.0)))
		if current_inside:
			output.append(current)
	return output


func _accumulate(sample: Dictionary) -> void:
	aggregate["samples"] = int(aggregate["samples"]) + 1
	var required_mm := float(sample["required_plane_margin_mm"])
	aggregate["required_margin_mm_sum"] = float(aggregate["required_margin_mm_sum"]) + required_mm
	aggregate["required_margin_mm_max"] = maxf(float(aggregate["required_margin_mm_max"]), required_mm)
	var uninflated: Dictionary = sample["uninflated"]
	var required: Dictionary = sample["minimal_observed_margin"]
	var configured: Dictionary = sample["configured_amplitude_margin"]
	aggregate["uninflated_coverage_sum"] = float(aggregate["uninflated_coverage_sum"]) + float(uninflated["point_coverage"])
	aggregate["configured_coverage_sum"] = float(aggregate["configured_coverage_sum"]) + float(configured["point_coverage"])
	aggregate["configured_coverage_min"] = minf(float(aggregate["configured_coverage_min"]), float(configured["point_coverage"]))
	aggregate["required_area_ratio_sum"] = float(aggregate["required_area_ratio_sum"]) + float(required["area_over_actual_hull_ratio"])
	aggregate["required_area_ratio_max"] = maxf(float(aggregate["required_area_ratio_max"]), float(required["area_over_actual_hull_ratio"]))
	aggregate["configured_area_ratio_sum"] = float(aggregate["configured_area_ratio_sum"]) + float(configured["area_over_actual_hull_ratio"])
	aggregate["configured_area_ratio_max"] = maxf(float(aggregate["configured_area_ratio_max"]), float(configured["area_over_actual_hull_ratio"]))
	if bool(sample["configured_bound_contains_required"]):
		aggregate["configured_bound_contains_required"] = int(aggregate["configured_bound_contains_required"]) + 1


func _summary() -> Dictionary:
	var count := maxi(1, int(aggregate["samples"]))
	return {
		"samples": count,
		"mean_required_margin_mm": float(aggregate["required_margin_mm_sum"]) / float(count),
		"maximum_required_margin_mm": float(aggregate["required_margin_mm_max"]),
		"mean_uninflated_coverage": float(aggregate["uninflated_coverage_sum"]) / float(count),
		"mean_configured_coverage": float(aggregate["configured_coverage_sum"]) / float(count),
		"minimum_configured_coverage": float(aggregate["configured_coverage_min"]),
		"configured_bound_contains_required_samples": int(aggregate["configured_bound_contains_required"]),
		"mean_minimal_margin_area_ratio": float(aggregate["required_area_ratio_sum"]) / float(count),
		"maximum_minimal_margin_area_ratio": float(aggregate["required_area_ratio_max"]),
		"mean_configured_margin_area_ratio": float(aggregate["configured_area_ratio_sum"]) / float(count),
		"maximum_configured_margin_area_ratio": float(aggregate["configured_area_ratio_max"]),
	}


func _decision() -> Dictionary:
	var summary := _summary()
	var all_bounded := int(summary["configured_bound_contains_required_samples"]) == int(summary["samples"])
	var full_coverage := float(summary["minimum_configured_coverage"]) >= 0.995
	return {
		"halfspace_core_supported": true,
		"configured_roughness_bound_is_conservative_for_matrix": all_bounded and full_coverage,
		"runtime_formula_frozen": false,
		"reason": "half-space geometry is the preferred recipe-derived core; Phase A must use measured margin/area evidence to choose a tighter deterministic roughness/contact policy before runtime integration",
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
	if absf(da) <= EPS:
		_append_unique_2d(result, Vector2(a.x, a.z))
	if absf(db) <= EPS:
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


func _append_unique_3d(points: Array[Vector3], point: Vector3) -> void:
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


func _support_distance(normal: Vector3, extents: Vector3) -> float:
	return absf(normal.x) * extents.x + absf(normal.y) * extents.y + absf(normal.z) * extents.z


func _random_unit(state: int) -> Dictionary:
	var next := state
	var vector := Vector3.ZERO
	for axis in range(3):
		next = _next_random(next)
		vector[axis] = float(next) / float(RAND_MOD) * 2.0 - 1.0
	if vector.length_squared() < 0.08:
		vector = Vector3(0.71, 0.41, 0.57)
	return {"state": next, "vector": vector.normalized()}


func _random_unit_float(state: int) -> float:
	return float(posmod(state, RAND_MOD)) / float(RAND_MOD)


func _next_random(state: int) -> int:
	return int((state * 48271 + 1) % RAND_MOD)


func _random_bit(state: int) -> int:
	return posmod(state, 2)


func _axis_index(axis: String) -> int:
	match axis:
		"x": return 0
		"y": return 1
		"z": return 2
	return 1


func _synthetic_discovery() -> Dictionary:
	return {
		"ok": true,
		"packages": [{
			"manifest": {
				"id": "phasea.synthetic",
				"version": "1.0.0",
				"schema_version": 1,
				"requires_engine": "4.7.2",
				"dependencies": [],
				"content_roots": ["objects/", "interactions/"],
				"script_policy": "data_only",
			},
			"definitions": [{
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
			}],
			"population_rules": [],
			"terrain_interactions": [{
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
			}],
		}],
	}


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("ISSUE108_PHASE_A_HALFSPACE_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
