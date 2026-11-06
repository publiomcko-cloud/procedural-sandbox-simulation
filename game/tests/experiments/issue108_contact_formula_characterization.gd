extends SceneTree

const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const RockMesh := preload("res://scripts/objects/procedural_rock_mesh_adapter.gd")

const SEEDS := [1, 17, 101, 31337, 91234, 777777]

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var blend := _characterize_interior_blend()
	evidence["interior_blend"] = blend
	_check(blend.get("outside_unchanged", false), "interior blend has exactly zero influence outside the cutter")
	_check(blend.get("boundary_continuous", false), "interior blend is continuous at the cutter boundary")
	_check(blend.get("hard_after_radius", false), "interior blend becomes exact hard subtraction after blend radius")
	_check(blend.get("bounded_between_original_and_hard", false), "interior blend never carves more than hard subtraction")

	var registry := Registry.new()
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var external_root := project_root.get_base_dir().path_join("mods/examples")
	var registration := registry.discover_and_register(["res://mods/first-party", external_root])
	_check(registration.get("ok", false), "formula characterization registry loads")
	if not registration.get("ok", false):
		_finish()
		return
	var synthetic := registry.register_discovered(_synthetic_discovery())
	_check(synthetic.get("ok", false), "formula characterization synthetic profile registers")
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
		_check(interaction_result.get("ok", false) and not interaction_result.get("rule", {}).is_empty(), "%s interaction resolves" % definition_id)
		if not interaction_result.get("ok", false) or interaction_result.get("rule", {}).is_empty():
			continue
		var interaction: Dictionary = interaction_result["rule"]
		var definition := registry.get_definition(definition_id)
		var recipe: Dictionary = definition["recipe"]
		var configured_amplitude_mm := int(recipe["macro_roughness_mm"]) + int(recipe["meso_roughness_mm"]) + int(recipe["fine_roughness_mm"])
		var samples: Array[Dictionary] = []
		var proxy_max_mm := 0.0
		var proxy_sum_mm := 0.0
		for seed in SEEDS:
			var recipe_result := registry.evaluate_rock_recipe(definition_id, seed)
			var cpu := RockMesh.build_cpu_data(recipe_result.get("geometry", {}), recipe_result.get("geometry_seeds", {}))
			_check(cpu.get("ok", false), "%s seed %d geometry builds for guard proxy" % [definition_id, seed])
			if not cpu.get("ok", false):
				continue
			var proxy := _post_geometry_edge_guard_proxy(
				cpu["positions"], float(configured_amplitude_mm) / 1000.0
			)
			proxy_max_mm = maxf(proxy_max_mm, float(proxy["guard_m"]) * 1000.0)
			proxy_sum_mm += float(proxy["guard_m"]) * 1000.0
			samples.append({
				"seed": seed,
				"guard_proxy_mm": float(proxy["guard_m"]) * 1000.0,
				"minimum_edge_mm": float(proxy["minimum_edge_m"]) * 1000.0,
				"maximum_vertex_shortest_edge_mm": float(proxy["maximum_vertex_shortest_edge_m"]) * 1000.0,
				"unique_vertex_count": int(proxy["unique_vertex_count"]),
			})
		var blend_mm := int(interaction["blend_radius_mm"])
		var embed_mm := int(interaction["embed_depth_mm"])
		definitions[definition_id] = {
			"profile": recipe["profile"],
			"configured_roughness_amplitude_mm": configured_amplitude_mm,
			"guard_proxy_mean_mm": proxy_sum_mm / float(samples.size()) if not samples.is_empty() else 0.0,
			"guard_proxy_max_mm": proxy_max_mm,
			"embed_depth_mm": embed_mm,
			"blend_radius_mm": blend_mm,
			"blend_within_embed": blend_mm <= embed_mm,
			"samples": samples,
		}
	evidence["definitions"] = definitions
	evidence["decision"] = {
		"blend_semantics": "interior_eased_subtract_v1",
		"formula": "if cutter>=0 return terrain; otherwise lerp(terrain, min(terrain,cutter), smoothstep(0,blend_radius,-cutter)); hard subtraction at depth>=blend_radius",
		"no_exterior_moat_by_construction": true,
		"roughness_guard_policy": "derive a deterministic guard from the existing per-vertex safe displacement cap in a shared recipe-shape descriptor; do not use configured amplitude sum directly",
		"runtime_formula_frozen_for_phase_b": true,
	}
	print("ISSUE108_PHASE_A_CONTACT_FORMULA=" + JSON.stringify(evidence))
	_finish()


func _characterize_interior_blend() -> Dictionary:
	var outside_unchanged := true
	var boundary_continuous := true
	var hard_after_radius := true
	var bounded := true
	var cases := 0
	for radius in [0.14, 0.18]:
		for terrain in [-0.2, 0.0, 0.05, 0.2]:
			for cutter in [-0.36, -0.18, -0.14, -0.09, -0.01, -0.000001, 0.0, 0.000001, 0.02, 0.2]:
				var output := _interior_eased_subtract(terrain, cutter, radius)
				var hard := minf(terrain, cutter)
				cases += 1
				if cutter >= 0.0 and not is_equal_approx(output, terrain):
					outside_unchanged = false
				if cutter <= -radius and not is_equal_approx(output, hard):
					hard_after_radius = false
				var lower := minf(terrain, hard)
				var upper := maxf(terrain, hard)
				if output < lower - 0.000001 or output > upper + 0.000001:
					bounded = false
			var at_boundary := _interior_eased_subtract(terrain, 0.0, radius)
			var just_inside := _interior_eased_subtract(terrain, -0.000001, radius)
			if absf(at_boundary - terrain) > 0.000001 or absf(just_inside - terrain) > 0.00001:
				boundary_continuous = false
	return {
		"cases": cases,
		"outside_unchanged": outside_unchanged,
		"boundary_continuous": boundary_continuous,
		"hard_after_radius": hard_after_radius,
		"bounded_between_original_and_hard": bounded,
	}


func _interior_eased_subtract(terrain: float, cutter: float, radius: float) -> float:
	if cutter >= 0.0:
		return terrain
	var hard := minf(terrain, cutter)
	if radius <= 0.0 or -cutter >= radius:
		return hard
	var u := clampf((-cutter) / radius, 0.0, 1.0)
	var weight := u * u * (3.0 - 2.0 * u)
	return lerpf(terrain, hard, weight)


func _post_geometry_edge_guard_proxy(positions: PackedVector3Array, configured_amplitude_m: float) -> Dictionary:
	var shortest: Dictionary = {}
	var unique: Dictionary = {}
	var minimum_edge := INF
	for index in range(0, positions.size(), 3):
		if index + 2 >= positions.size():
			break
		var tri := [positions[index], positions[index + 1], positions[index + 2]]
		for p in tri:
			var key := _point_key(p)
			unique[key] = p
			if not shortest.has(key):
				shortest[key] = INF
		for pair in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = tri[pair[0]]
			var b: Vector3 = tri[pair[1]]
			var length := a.distance_to(b)
			minimum_edge = minf(minimum_edge, length)
			var ka := _point_key(a)
			var kb := _point_key(b)
			shortest[ka] = minf(float(shortest.get(ka, INF)), length)
			shortest[kb] = minf(float(shortest.get(kb, INF)), length)
	var maximum_vertex_shortest := 0.0
	var guard := 0.0
	for key in shortest:
		var edge := float(shortest[key])
		if not is_finite(edge):
			continue
		maximum_vertex_shortest = maxf(maximum_vertex_shortest, edge)
		guard = maxf(guard, minf(configured_amplitude_m, edge * 0.07))
	return {
		"guard_m": guard,
		"minimum_edge_m": minimum_edge if is_finite(minimum_edge) else 0.0,
		"maximum_vertex_shortest_edge_m": maximum_vertex_shortest,
		"unique_vertex_count": unique.size(),
	}


func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(point.x * 1000000.0),
		roundi(point.y * 1000000.0),
		roundi(point.z * 1000000.0),
	]


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
	print("ISSUE108_PHASE_A_CONTACT_FORMULA_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
