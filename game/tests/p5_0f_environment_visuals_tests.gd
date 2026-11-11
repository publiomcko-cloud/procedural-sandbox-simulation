extends SceneTree

const VisualScript := preload("res://scripts/simulation/environment_visual_presentation.gd")
const OceanVisual := preload("res://scripts/simulation/environment_ocean_visual_domain.gd")
const EnvironmentStore := preload("res://scripts/simulation/environment_state_store.gd")
const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const ClimateScript := preload("res://scripts/simulation/environment_climate_domain.gd")
const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const StartupLocation := preload("res://scripts/simulation/environment_startup_location.gd")
const BrushStateScript := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const SurfaceJobScript := preload("res://scripts/simulation/environment_surface_cache_job.gd")
const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

class FakeRuntime:
	extends Node
	var environment: Dictionary = {}
	var surface: Dictionary = {}

	func get_environment_scope(_scope_id: String) -> Dictionary:
		return environment.duplicate(true)

	func get_environment_surface_cache(_scope_id: String) -> Dictionary:
		return surface.duplicate(true)


var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pure_water_plan()
	_test_invalid_inputs()
	_test_bounded_scene_presentation()
	_test_shoreline_clipping()
	_test_r3_adaptive_coast()
	_test_r4_continuous_ocean()
	_test_r4_connected_basin_and_seams()
	_test_r5_isolated_ocean_binding()
	_test_r5_visual_signature_and_revisit()
	_test_r5_1_submerged_ocean_finite_noop()
	_test_sdf_worker_shoreline_and_edits()
	_test_startup_locations()
	_test_bundled_ocean_end_to_end()
	if failures == 0:
		print("P5_0F_ENVIRONMENT_VISUALS_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P5_0F_ENVIRONMENT_VISUALS_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)


func _environment(region: Vector2i = Vector2i.ZERO) -> Dictionary:
	var water := PackedInt64Array()
	var soil := PackedInt64Array()
	var kinds := PackedByteArray()
	var levels := PackedInt64Array()
	water.resize(48)
	soil.resize(48)
	kinds.resize(48)
	levels.resize(48)
	water[0] = 2_000_000_000
	kinds[1] = EnvironmentStore.RESERVOIR_RIVER
	kinds[2] = EnvironmentStore.RESERVOIR_OCEAN
	levels[1] = 3_500
	levels[2] = 4_000
	return {
		"scope_id": "region:%d,%d" % [region.x, region.y],
		"state_revision": 1,
		"last_environment_tick": 8,
		"profile_id": "test:wet",
		"profile_sha256": "sha-fixture",
		"surface_water_ul": water,
		"soil_water_ul": soil,
		"reservoir_kind": kinds,
		"reservoir_level_mm": levels,
	}


func _surface(region: Vector2i = Vector2i.ZERO) -> Dictionary:
	var valid := PackedByteArray()
	var heights := PackedInt64Array()
	valid.resize(48)
	heights.resize(48)
	valid.fill(1)
	heights.fill(3_000)
	return {
		"scope_id": "region:%d,%d" % [region.x, region.y],
		"region_key": region,
		"grid_width": 8,
		"grid_height": 6,
		"cell_size_x_mm": 2000,
		"cell_size_z_mm": 2000,
		"world_seed": 42,
		"generator_version": 1,
		"terrain_revision": 0,
		"terrain_cache_scope_id": 1000,
		"terrain_effect_revision": 0,
		"surface_valid": valid,
		"surface_height_mm": heights,
	}


func _test_pure_water_plan() -> void:
	var region := Vector2i(-2, 3)
	var environment := _environment(region)
	var terrain := _surface(region)
	var original_water: PackedInt64Array = environment["surface_water_ul"].duplicate()
	var original_levels: PackedInt64Array = environment["reservoir_level_mm"].duplicate()
	var planned: Dictionary = VisualScript.derive_water_cells(region, environment, terrain)
	_check(planned.get("ok", false), "valid environment and SDF produce derived plan")
	if not planned.get("ok", false):
		return
	var cells: Array = planned["cells"]
	_check(cells.size() == 3, "finite, river and ocean become three water instances, not cell nodes")
	_check(int(cells[0]["kind"]) == EnvironmentStore.RESERVOIR_FINITE, "finite surface is drawn")
	_check(is_equal_approx(float(cells[0]["position"].y), 3.512), "finite depth derives from 2 billion microliters over 4 square meters")
	_check(is_equal_approx(float(cells[1]["position"].y), 3.512), "river level comes from immutable fixed reservoir level")
	_check(is_equal_approx(float(cells[2]["position"].y), 4.012), "ocean level comes from immutable fixed reservoir level")
	_check(is_equal_approx(float(cells[0]["position"].x), -31.0), "negative region coordinates map to global X consistently")
	_check(is_equal_approx(float(cells[0]["position"].z), 37.0), "region coordinates map to global Z consistently")
	_check(environment["surface_water_ul"] == original_water and environment["reservoir_level_mm"] == original_levels, "derivation never changes water authority")
	var again: Dictionary = VisualScript.derive_water_cells(region, environment, terrain)
	_check(again == planned, "identical authority and SDF produce identical geometry plan")
	var small_rainfall: PackedInt64Array = environment["surface_water_ul"]
	small_rainfall[0] = 1_000
	environment["surface_water_ul"] = small_rainfall
	_check(
		(VisualScript.derive_water_cells(region, environment, terrain)["cells"] as Array).size() == 2,
		"microscopic rainfall volume is still authoritative but does not paint a false visible puddle"
	)
	small_rainfall[0] = 40_000_000
	environment["surface_water_ul"] = small_rainfall
	var minimum_visible: Dictionary = VisualScript.derive_water_cells(region, environment, terrain)
	_check((minimum_visible["cells"] as Array).size() == 3, "real one-centimeter puddle is rendered")
	_check(
		is_equal_approx(float(minimum_visible["cells"][0]["position"].y), 3.022),
		"finite puddle height reflects 40 L over 4 square meters without inflated depth"
	)
	var dry: PackedInt64Array = environment["surface_water_ul"]
	dry[0] = 0
	environment["surface_water_ul"] = dry
	_check((VisualScript.derive_water_cells(region, environment, terrain)["cells"] as Array).size() == 2, "dry finite cells produce no quad")
	var invalid: PackedByteArray = terrain["surface_valid"]
	invalid[2] = 0
	terrain["surface_valid"] = invalid
	_check((VisualScript.derive_water_cells(region, environment, terrain)["cells"] as Array).size() == 1, "missing SDF sample hides that cell")


func _test_invalid_inputs() -> void:
	var region := Vector2i.ZERO
	_check(not VisualScript.derive_water_cells(region, {}, _surface()).get("ok", false), "missing authority rejected")
	_check(not VisualScript.derive_water_cells(region, _environment(), {}).get("ok", false), "missing terrain rejected")
	_check(not VisualScript.derive_water_cells(Vector2i(1, 0), _environment(), _surface()).get("ok", false), "region mismatch rejected")
	var wrong_scope := _surface()
	wrong_scope["scope_id"] = "region:1,0"
	_check(not VisualScript.derive_water_cells(region, _environment(), wrong_scope).get("ok", false), "scope mismatch rejected")
	var bad_grid := _surface()
	bad_grid["grid_width"] = 9
	_check(not VisualScript.derive_water_cells(region, _environment(), bad_grid).get("ok", false), "foreign grid rejected")
	var bad_arrays := _surface()
	bad_arrays["surface_height_mm"] = PackedInt64Array([3_000])
	_check(not VisualScript.derive_water_cells(region, _environment(), bad_arrays).get("ok", false), "invalid array lengths rejected")



func _shoreline(region: Vector2i = Vector2i.ZERO, terrain: Dictionary = {}) -> Dictionary:
	var heights := PackedInt32Array()
	var valid := PackedByteArray()
	heights.resize(17 * 13)
	valid.resize(heights.size())
	heights.fill(3000)
	valid.fill(1)
	if terrain.is_empty():
		terrain = _surface(region)
	return {
		"ok": true, "width": 17, "height": 13,
		"height_mm": heights, "valid": valid,
		"region_key": region,
		"world_seed": int(terrain.get("world_seed", 42)),
		"generator_version": int(terrain.get("generator_version", 1)),
		"terrain_revision": int(terrain.get("terrain_revision", 0)),
		"terrain_cache_scope_id": int(terrain.get("terrain_cache_scope_id", 1000)),
		"terrain_effect_revision": int(terrain.get("terrain_effect_revision", 0)),
	}


func _projected_area(vertices: PackedVector3Array) -> float:
	var area := 0.0
	for i in range(0, vertices.size(), 3):
		var a := Vector2(vertices[i].x, vertices[i].z)
		var b := Vector2(vertices[i + 1].x, vertices[i + 1].z)
		var c := Vector2(vertices[i + 2].x, vertices[i + 2].z)
		area += absf((b - a).cross(c - a)) * 0.5
	return area


func _test_shoreline_clipping() -> void:
	# Legacy R2 test explicitly exercises the non-ocean-band R3-compatible
	# cell geometry. Real ocean-band regions use the continuous R4 SDF plane.
	var region := Vector2i(-2, 3)
	var terrain := _surface(region)
	var environment := _environment(region)
	var samples := _shoreline(region, terrain)
	var original_environment := environment.duplicate(true)
	var original_terrain := terrain.duplicate(true)
	var complete: Dictionary = VisualScript.derive_shoreline_geometry(region, environment, terrain, samples)
	_check(complete.get("ok", false), "R2 same-source shoreline grid generates mesh")
	if not complete.get("ok", false):
		return
	_check(complete["vertices"].size() == 72, "three fully wet hydro cells generate 24 clipped-grid triangles")
	var full_area := _projected_area(complete["vertices"])
	_check(is_equal_approx(full_area, 12.0), "three completely wet 2m cells cover 12 square meters")
	var dry_corner: PackedInt32Array = samples["height_mm"]
	dry_corner[0] = 6000
	samples["height_mm"] = dry_corner
	var clipped: Dictionary = VisualScript.derive_shoreline_geometry(region, environment, terrain, samples)
	_check(clipped.get("ok", false), "R2 submerged polygon clipping remains valid with dry land")
	_check(_projected_area(clipped["vertices"]) < full_area, "R2 clipped shoreline has less wet area than uncut quad")
	_check(_projected_area(clipped["vertices"]) > 0, "R2 partial wet cell retains its submerged area")
	_check(environment == original_environment and terrain == original_terrain, "R2 mesh derivation cannot mutate authority or SDF cache")
	dry_corner.fill(6000)
	samples["height_mm"] = dry_corner
	var fully_dry: Dictionary = VisualScript.derive_shoreline_geometry(region, environment, terrain, samples)
	_check(fully_dry.get("ok", false) and fully_dry["vertices"].is_empty(), "R2 all-dry SDF does not draw ocean above land")
	_check((fully_dry.get("water_cells", -1)) == 0, "R2 no hydrology cells visually drawn when terrain is higher")
	var invalid_samples := _shoreline(region, terrain)
	invalid_samples["terrain_revision"] = 42
	_check(not VisualScript.derive_shoreline_geometry(region, environment, terrain, invalid_samples).get("ok", false), "R2 stale SDF revision fails closed")
	var wrong_region := _shoreline(Vector2i(1, 1))
	_check(not VisualScript.derive_shoreline_geometry(region, environment, terrain, wrong_region).get("ok", false), "R2 foreign region samples rejected")
	var no_samples := _shoreline(region, terrain)
	no_samples["height_mm"] = PackedInt32Array()
	_check(not VisualScript.derive_shoreline_geometry(region, environment, terrain, no_samples).get("ok", false), "R2 partial sample array rejected")



func _test_r3_adaptive_coast() -> void:
	var region := Vector2i.ZERO
	var environment := _environment(region)
	var terrain := _surface(region)
	var samples := _shoreline(region, terrain)
	var original_environment := environment.duplicate(true)

	var wet_plan: Dictionary = VisualScript.derive_shoreline_geometry(region, environment, terrain, samples)
	_check(wet_plan.get("ok", false), "R3 fully wet environment builds successfully")
	_check(int(wet_plan.get("refined_coast_quads", -1)) == 0, "R3 fully wet interiors retain coarse R2 triangles")
	_check(int(wet_plan.get("coastal_halo_cells", -1)) == 0, "R3 no synthetic ocean halo on physically submerged centers")

	var heights: PackedInt32Array = samples["height_mm"]
	# Hydrologic ocean cell index=2 spans X=[4,6], Z=[0,2].
	# Introduce a dry island crest within that otherwise wet cell.
	heights[1 * 17 + 5] = 5000
	samples["height_mm"] = heights
	var coarse: Dictionary = VisualScript.derive_shoreline_geometry(region, environment, terrain, samples)
	_check(coarse.get("ok", false), "R3 coastline mixed tiles build successfully")
	_check(int(coarse.get("refined_coast_quads", 0)) > 0, "R3 refines only 1m tiles with both wet and dry corners")
	_check(coarse.get("vertices", PackedVector3Array()).size() <= VisualScript.MAX_SHORELINE_VERTICES, "R3 regional mesh stays within hard vertex budget")
	_check(_projected_area(coarse["vertices"]) < _projected_area(wet_plan["vertices"]), "R3 shoreline clipping removes known dry area")

	var fine_heights: Dictionary = {}
	var fine_valid: Dictionary = {}
	fine_heights[1 * 33 + 9] = 6000
	fine_valid[1 * 33 + 9] = 1
	samples["fine_height_mm"] = fine_heights
	samples["fine_valid"] = fine_valid
	var precise: Dictionary = VisualScript.derive_shoreline_geometry(region, environment, terrain, samples)
	_check(precise.get("ok", false), "R3 0.5m true-SDF sparse site is accepted")
	_check(_projected_area(precise["vertices"]) < _projected_area(coarse["vertices"]), "R3 true-SDF sample corrects bilinear boundary interpolation")
	var repeated: Dictionary = VisualScript.derive_shoreline_geometry(region, environment, terrain, samples)
	_check(repeated.get("vertices") == precise.get("vertices"), "R3 stable sparse topography gives bitwise-repeatable mesh")

	var halo_terrain := _surface(region)
	var halo_center: PackedInt64Array = halo_terrain["surface_height_mm"]
	halo_center[3] = 4500
	halo_terrain["surface_height_mm"] = halo_center
	var halo_samples := _shoreline(region, halo_terrain)
	var halo_heights: PackedInt32Array = halo_samples["height_mm"]
	for z in range(3):
		halo_heights[z * 17 + 8] = 5000
	halo_samples["height_mm"] = halo_heights
	var halo: Dictionary = VisualScript.derive_shoreline_geometry(
		region, environment, halo_terrain, halo_samples
	)
	_check(halo.get("ok", false), "R3 coastal dry-centered halo derives bounded water plane")
	_check(int(halo.get("coastal_halo_cells", -1)) == 1, "R3 only authoritative-ocean-adjacent dry center gets visual halo")
	_check(int(halo.get("refined_coast_quads", 0)) > 0, "R3 partial coast halo is clipped at refined resolution")
	_check(environment == original_environment, "R3 coastal closure never changes reservoir kinds or finite water authority")
	var without_ocean := environment.duplicate(true)
	var kinds: PackedByteArray = without_ocean["reservoir_kind"]
	kinds[2] = EnvironmentStore.RESERVOIR_FINITE
	without_ocean["reservoir_kind"] = kinds
	var no_ocean: Dictionary = VisualScript.derive_shoreline_geometry(
		region, without_ocean, halo_terrain, halo_samples
	)
	_check(int(no_ocean.get("coastal_halo_cells", -1)) == 0, "R3 no coast halo can appear without a true authoritative ocean neighbor")


func _test_r4_continuous_ocean() -> void:
	var region := Vector2i(5, 13)
	var terrain := _surface(region)
	var samples := _shoreline(region, terrain)
	var authority := _environment(region)
	var original := authority.duplicate(true)
	var ocean: Dictionary = OceanVisual.build(region, authority, samples)
	_check(ocean.get("ok", false), "R4 valid 1m SDF and ocean authority create a continuous ocean plane")
	if not ocean.get("ok", false):
		return
	_check(int(ocean.get("water_tiles", 0)) == 192, "R4 connected sea covers entire submerged 16x12 region, not just bound 2m cells")
	_check(is_equal_approx(_projected_area(ocean["vertices"]), 192.0), "R4 full 192m2 sea is independent of coarse water-source rectangle")
	_check(int(ocean.get("source_ocean_cells", -1)) == 1, "R4 recognizes exactly one authoritative ocean seed")
	var plane_y_ok := true
	for vertex in ocean["vertices"]:
		if not is_equal_approx(vertex.y, 4.012):
			plane_y_ok = false
			break
	_check(plane_y_ok, "R4 all connected ocean vertices share authoritative fixed 4m level and 12mm draw offset")

	var all_ocean := authority.duplicate(true)
	var kinds: PackedByteArray = all_ocean["reservoir_kind"]
	var levels: PackedInt64Array = all_ocean["reservoir_level_mm"]
	kinds.fill(EnvironmentStore.RESERVOIR_OCEAN)
	levels.fill(4000)
	all_ocean["reservoir_kind"] = kinds
	all_ocean["reservoir_level_mm"] = levels
	var complete: Dictionary = OceanVisual.build(region, all_ocean, samples)
	_check(complete.get("ok", false), "R4 all-ocean region generates clipped plane")
	_check(complete.get("vertices") == ocean.get("vertices"), "R4 shoreline geometry does not depend on how many 2m cells are classified ocean")

	var integrated: Dictionary = VisualScript.derive_shoreline_geometry(
		region, all_ocean, terrain, samples, "sources"
	)
	_check(integrated.get("ok", false), "R4 presenter integrates continuous sea with R3 river/finite pathway")
	_check(int(integrated.get("coastal_halo_cells", -1)) == 0, "R4 ocean band uses no synthetic one-cell coastal halo")
	_check(int(integrated.get("ocean_sdf_tiles", -1)) == 192, "R4 integrated presenter tracks continuous sea tiles")
	_check(is_equal_approx(_projected_area(integrated["vertices"]), 192.0), "R4 presenter does not overlap old ocean rectangles")
	var disabled: Dictionary = VisualScript.derive_shoreline_geometry(
		region, all_ocean, terrain, samples, "normal", false
	)
	_check(disabled.get("ok", false) and (disabled["vertices"] as PackedVector3Array).is_empty(),
		"R4 hydrology-disabled presentation never invents an ocean plane")

	var coast := _shoreline(region, terrain)
	var topography: PackedInt32Array = coast["height_mm"]
	for z in range(13):
		for x in range(17):
			if x <= 5:
				topography[z * 17 + x] = 5000
	coast["height_mm"] = topography
	var cut: Dictionary = OceanVisual.build(region, all_ocean, coast)
	_check(cut.get("ok", false), "R4 SDF-clipped peninsula remains a valid sea mesh")
	_check(_projected_area(cut.get("vertices", PackedVector3Array())) < 192.0, "R4 coastline removes dry SDF terrain without coarse ocean masks")
	_check(_projected_area(cut.get("vertices", PackedVector3Array())) > 0.0, "R4 wet area beyond peninsula remains visible")
	var repeated: Dictionary = OceanVisual.build(region, all_ocean, coast)
	_check(repeated.get("vertices") == cut.get("vertices"), "R4 topology and triangulation are deterministic")
	_check(authority == original, "R4 topology never writes the original hydrology arrays")

	var wrong_level := all_ocean.duplicate(true)
	var wrong_levels: PackedInt64Array = wrong_level["reservoir_level_mm"]
	wrong_levels[0] = 4500
	wrong_level["reservoir_level_mm"] = wrong_levels
	_check(not OceanVisual.build(region, wrong_level, samples).get("ok", false), "R4 rejects ocean authority with mismatched fixed level")
	_check((OceanVisual.build(Vector2i(5, 9), all_ocean, _shoreline(Vector2i(5, 9)))["vertices"] as PackedVector3Array).is_empty(), "R4 ocean plane cannot appear before core ocean world band")


func _test_r4_connected_basin_and_seams() -> void:
	var west := Vector2i(5, 13)
	var east := Vector2i(6, 13)
	var source := _environment(west)
	var pure_west: Dictionary = OceanVisual.build(west, source, _shoreline(west))
	var east_source := _environment(east)
	var pure_east: Dictionary = OceanVisual.build(east, east_source, _shoreline(east))
	_check(pure_west.get("ok", false) and pure_east.get("ok", false), "R4 adjoining regions both derive connected ocean")
	var shared_x := float((west.x + 1) * 16)
	var west_border := 0
	var east_border := 0
	for vertex in pure_west.get("vertices", PackedVector3Array()):
		if is_equal_approx(vertex.x, shared_x):
			west_border += 1
	for vertex in pure_east.get("vertices", PackedVector3Array()):
		if is_equal_approx(vertex.x, shared_x):
			east_border += 1
	_check(west_border > 0 and east_border > 0, "R4 ocean touches same global X seam in both neighboring regions")

	var coastal := _shoreline(west)
	var terrain: PackedInt32Array = coastal["height_mm"]
	terrain.fill(5000)
	for x in range(17):
		terrain[11 * 17 + x] = 3000
		terrain[12 * 17 + x] = 3000
	for z in range(3, 6):
		for x in range(3, 6):
			terrain[z * 17 + x] = 3000
	coastal["height_mm"] = terrain
	var no_source := _environment(west)
	var kinds: PackedByteArray = no_source["reservoir_kind"]
	kinds[2] = EnvironmentStore.RESERVOIR_FINITE
	no_source["reservoir_kind"] = kinds
	var connected: Dictionary = OceanVisual.build(west, no_source, coastal)
	_check(connected.get("ok", false), "R4 open-sea border can seed visual surface before coarse hydrology binds")
	var area := _projected_area(connected.get("vertices", PackedVector3Array()))
	_check(area > 0.0 and area <= 32.0, "R4 landlocked 3x3 depression is not filled merely because it is below sea level")
	_check(int(connected.get("source_ocean_cells", -1)) == 0, "R4 no artificial source is written to authority")
	var isolated := _shoreline(west)
	var isolated_heights: PackedInt32Array = isolated["height_mm"]
	isolated_heights.fill(5000)
	for z in range(3, 6):
		for x in range(3, 6):
			isolated_heights[z * 17 + x] = 3000
	isolated["height_mm"] = isolated_heights
	_check((OceanVisual.build(west, no_source, isolated)["vertices"] as PackedVector3Array).is_empty(), "R4 isolated inland depression without ocean connection draws no sea")




## R5: ocean-cell classification alone cannot flood an isolated excavation
## whose submerged surface has no wet edge to any region boundary.
func _test_r5_isolated_ocean_binding() -> void:
	var region := Vector2i(5, 13)
	var environment := _environment(region)
	var kinds: PackedByteArray = environment["reservoir_kind"]
	var levels: PackedInt64Array = environment["reservoir_level_mm"]
	kinds[2] = EnvironmentStore.RESERVOIR_FINITE
	levels[2] = 0
	kinds[19] = EnvironmentStore.RESERVOIR_OCEAN
	levels[19] = 4000
	environment["reservoir_kind"] = kinds
	environment["reservoir_level_mm"] = levels
	var before := environment.duplicate(true)
	var samples := _shoreline(region)
	var heights: PackedInt32Array = samples["height_mm"]
	heights.fill(5000)
	for z in range(4, 7):
		for x in range(6, 9):
			heights[z * 17 + x] = 3000
	samples["height_mm"] = heights
	var landlocked: Dictionary = OceanVisual.build(region, environment, samples)
	_check(landlocked.get("ok", false), "R5 isolated ocean-cell source remains a valid input")
	_check((landlocked.get("vertices", PackedVector3Array()) as PackedVector3Array).is_empty(),
		"R5 isolated newly dug basin with ocean binding cannot paint a disconnected sea")
	_check(int(landlocked.get("isolated_components_skipped", 0)) == 1,
		"R5 isolated ocean component is explicitly counted")
	for x in range(17):
		heights[11 * 17 + x] = 3000
		heights[12 * 17 + x] = 3000
	samples["height_mm"] = heights
	var two_components: Dictionary = OceanVisual.build(region, environment, samples)
	_check(two_components.get("ok", false), "R5 regional sea and disconnected pit can coexist")
	_check(int(two_components.get("isolated_components_skipped", 0)) == 1,
		"R5 connected seaward sea never legitimizes a second isolated pit")
	_check(_projected_area(two_components.get("vertices", PackedVector3Array())) <= 32.0,
		"R5 isolated inland area stays out of seaward mesh")
	_check(environment == before, "R5 topology does not change persisted ocean bindings")


## R5: revisions and ticks without visible water changes do not cause
## expensive remeshing. A stale shoreline hides; valid samples restore it.
func _test_r5_visual_signature_and_revisit() -> void:
	var runtime := FakeRuntime.new()
	get_root().add_child(runtime)
	runtime.environment = _environment()
	runtime.surface = _surface()
	var presenter: Node3D = VisualScript.new()
	get_root().add_child(presenter)
	presenter.call("configure_environment", runtime)
	presenter.call("register_region", Vector2i.ZERO)
	_check(presenter.call("install_region_shoreline_samples",
		Vector2i.ZERO, runtime.surface, _shoreline()), "R5 initial samples install")
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	var node := presenter.get_node("Water_0_0") as MeshInstance3D
	_check(node.visible, "R5 initial water is visible")
	var start_rebuilds := int(presenter.call("get_visual_metrics")["region_rebuilds_total"])
	runtime.environment["state_revision"] = 100
	runtime.environment["last_environment_tick"] = 200
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == start_rebuilds,
		"R5 tick and revision changes without geometry do not rebuild the sea")
	var water: PackedInt64Array = runtime.environment["surface_water_ul"]
	water[0] += 1_000_000
	runtime.environment["surface_water_ul"] = water
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == start_rebuilds,
		"R5 sub-2mm finite-water changes reuse the last visual mesh")
	water[0] += 8_000_000
	runtime.environment["surface_water_ul"] = water
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == start_rebuilds + 1,
		"R5 visible finite-depth changes still rebuild the water mesh")
	_check(int(presenter.call("get_visual_metrics")["unchanged_visual_skips_total"]) >= 2,
		"R5 bypassed rebuilds are measurable")
	presenter.call("invalidate_region_shoreline_samples", Vector2i.ZERO)
	_check(not node.visible, "R5 edited terrain hides stale water immediately")
	var wrong := _shoreline()
	wrong["terrain_revision"] = 999
	_check(not presenter.call("install_region_shoreline_samples", Vector2i.ZERO, runtime.surface, wrong),
		"R5 rejected shoreline cannot silently mark the region current")
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(not node.visible, "R5 mismatched samples never expose stale geometry")
	_check(presenter.call("install_region_shoreline_samples", Vector2i.ZERO, runtime.surface, _shoreline()),
		"R5 valid retry installs fresh shoreline")
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(node.visible, "R5 region becomes visible again after valid retry")
	presenter.call("unregister_region", Vector2i.ZERO)
	presenter.call("register_region", Vector2i.ZERO)
	_check(presenter.call("install_region_shoreline_samples", Vector2i.ZERO, runtime.surface, _shoreline()),
		"R5 revisit attaches current source samples")
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check((presenter.get_node("Water_0_0") as MeshInstance3D).visible,
		"R5 revisit rebuilds water rather than staying hidden")
	presenter.queue_free()
	runtime.queue_free()


## R5.1: finite water levels below a rendered real sea plane may
## change every tick, but must not remesh the same continuous ocean.
func _test_r5_1_submerged_ocean_finite_noop() -> void:
	var region := Vector2i(5, 13)
	var runtime := FakeRuntime.new()
	get_root().add_child(runtime)
	runtime.environment = _environment(region)
	runtime.surface = _surface(region)
	var presenter: Node3D = VisualScript.new()
	get_root().add_child(presenter)
	presenter.call("configure_environment", runtime)
	presenter.call("register_region", region)
	_check(presenter.call("install_region_shoreline_samples",
		region, runtime.surface, _shoreline(region)), "R5.1 ocean SDF samples install")
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, region)
	var node := presenter.get_node("Water_5_13") as MeshInstance3D
	_check(node.visible, "R5.1 ocean renders before finite-water changes")
	var baseline := int(presenter.call("get_visual_metrics")["region_rebuilds_total"])
	var water: PackedInt64Array = runtime.environment["surface_water_ul"]
	water[0] += 1_000_000_000
	runtime.environment["surface_water_ul"] = water
	runtime.environment["state_revision"] = 2
	runtime.environment["last_environment_tick"] = 9
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, region)
	_check(int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == baseline,
		"R5.1 finite water fully below ocean plane does not rebuild SDF sea")
	water[0] += 3_000_000_000
	runtime.environment["surface_water_ul"] = water
	runtime.environment["state_revision"] = 3
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, region)
	_check(int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == baseline + 1,
		"R5.1 finite water above ocean plane still triggers visual rebuild")
	presenter.queue_free()
	runtime.queue_free()


func _test_bounded_scene_presentation() -> void:
	var runtime := FakeRuntime.new()
	get_root().add_child(runtime)
	runtime.environment = _environment()
	runtime.surface = _surface()
	var presenter: Node3D = VisualScript.new()
	get_root().add_child(presenter)
	presenter.call("configure_environment", runtime, {
		"id": "test:wet",
		"precipitation_ul_per_cell_per_tick": 2_000_000,
	}, "sha-fixture")
	presenter.call("register_region", Vector2i.ZERO)
	presenter.call("register_region", Vector2i.ZERO)
	_check(presenter.call("install_region_shoreline_samples", Vector2i.ZERO, runtime.surface, _shoreline()), "R2 scene receives SDF-derived shoreline samples")
	_check(int(presenter.call("get_visual_metrics")["resident_region_nodes"]) == 1, "repeated publication is idempotent")
	var original := runtime.environment.duplicate(true)
	presenter.call("process_visual_frame", 0.2, Vector3(4, 10, 4), Vector2i.ZERO)
	var node := presenter.get_node("Water_0_0") as MeshInstance3D
	_check(node.visible and node.mesh != null and node.mesh.get_surface_count() == 1, "one regional shoreline MeshInstance renders the three water cells")
	_check(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 72, "R2 one 3-cell water mesh carries 24 triangles")
	_check(presenter.get_node("DerivedRain").visible, "pinned nonzero precipitation produces rain")
	_check(runtime.environment == original, "rendering does not commit or mutate environment authority")
	presenter.call("process_visual_frame", 0.2, Vector3(5, 10, 4), Vector2i.ZERO)
	_check(int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == 1, "unchanged revisions reuse visual product")
	runtime.surface = {}
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(not node.visible, "missing cache immediately hides stale water")
	runtime.surface = _surface()
	runtime.environment["state_revision"] = 2
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(node.visible and int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == 2, "cache return reconstructs derived visuals")
	var dry: PackedInt64Array = runtime.environment["surface_water_ul"]
	dry[0] = 0
	runtime.environment["surface_water_ul"] = dry
	runtime.environment["state_revision"] = 3
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 48, "new authority revision refreshes finite water shoreline mesh")
	runtime.environment["profile_sha256"] = "different"
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(not presenter.get_node("DerivedRain").visible, "rain refuses mismatched climate pin")
	presenter.call("unregister_region", Vector2i.ZERO)
	_check(int(presenter.call("get_visual_metrics")["resident_region_nodes"]) == 0, "unload removes transient region renderer")
	_check(runtime.environment["state_revision"] == 3, "unload does not delete persistent authority")
	presenter.call("register_region", Vector2i.ZERO)
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == 3, "R2 revisit defers until a matching SDF shoreline is available")
	_check(presenter.call("install_region_shoreline_samples", Vector2i.ZERO, runtime.surface, _shoreline()), "R2 regenerated cache attaches to revisited region")
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == 4, "revisit reconstructs the derived water mesh from refreshed SDF")
	_check(presenter.call("set_water_debug_mode", "off"), "diagnostic accepts water-off mode")
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	var debug_node := presenter.get_node("Water_0_0") as MeshInstance3D
	_check(not debug_node.visible and debug_node.mesh == null, "water-off leaves terrain untouched and removes only transient water mesh")
	_check(presenter.call("set_water_debug_mode", "ocean-only"), "diagnostic accepts real-ocean-only mode")
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(debug_node.visible and debug_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 24, "ocean-only mode excludes finite and river water without changing authority")
	_check(presenter.call("set_water_debug_mode", "sources"), "diagnostic accepts provenance-tinted rendering")
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(debug_node.visible and debug_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 48, "source-color diagnostic preserves geometry of remaining real water")
	_check(not presenter.call("set_water_debug_mode", "unsupported"), "invalid debug mode rejected")
	_check(String(presenter.call("get_water_debug_mode")) == "sources", "invalid debug mode does not change valid selected mode")
	_check(runtime.environment["state_revision"] == 3, "diagnostic modes never change environment authority")
	presenter.queue_free()
	runtime.queue_free()


func _test_sdf_worker_shoreline_and_edits() -> void:
	var region := Vector2i(5, 13)
	var brush: RefCounted = BrushStateScript.new(424242, 1)
	var original_job: Dictionary = _shoreline_worker(region, brush)
	_check(original_job.get("valid", false), "R2 full SDF worker derives shoreline with real canonical snapshots")
	if not original_job.get("valid", false):
		return
	var before: Dictionary = original_job.get("visual_shoreline", {})
	_check(before.get("ok", false), "R2 optional SDF shoreline product is available")
	_check((before.get("height_mm", PackedInt32Array()) as PackedInt32Array).size() == 221, "R2 fine grid has 17x13 samples")
	_check(int(before.get("refined_tile_count", 0)) > 0, "R3 actual ocean coast triggers selective true-SDF refinement")
	_check(int(before.get("refined_sample_count", -1)) <= 512, "R3 sampled coastline remains under bounded SDF probe cap")
	_check(int(before.get("refined_tile_count", -1)) <= 96, "R3 sampled coastline remains under bounded coastal tile cap")
	_check((original_job.get("record", {}) as Dictionary).get("surface_height_mm", PackedInt64Array()).size() == 48, "R2 SDF worker preserves unchanged P5.0C record grid")
	var environment := _environment(region)
	var kinds: PackedByteArray = environment["reservoir_kind"]
	var levels: PackedInt64Array = environment["reservoir_level_mm"]
	kinds.fill(EnvironmentStore.RESERVOIR_OCEAN)
	levels.fill(4000)
	environment["reservoir_kind"] = kinds
	environment["reservoir_level_mm"] = levels
	var result_before: Dictionary = VisualScript.derive_shoreline_geometry(
		region, environment, original_job["record"], before
	)
	_check(result_before.get("ok", false), "R2 canonical SDF samples yield clipped ocean geometry")
	var old_area := _projected_area(result_before.get("vertices", PackedVector3Array()))
	_check(old_area > 0.0 and old_area <= 192.0, "R2 canonical SDF ocean footprint stays inside one region")
	var fill_applied: bool = brush.add_sphere(
		BrushStateScript.Mode.FILL, Vector3(88.0, 4.0, 162.0), 1.8
	)
	_check(fill_applied, "R2 terrain fill fixture admits a shoreline-affecting edit")
	if not fill_applied:
		return
	var edited_job: Dictionary = _shoreline_worker(region, brush)
	_check(edited_job.get("valid", false), "R2 edited-SDF shoreline worker succeeds")
	if not edited_job.get("valid", false):
		return
	var after: Dictionary = edited_job.get("visual_shoreline", {})
	_check(after.get("terrain_revision") != before.get("terrain_revision"), "R2 shoreline provenance tracks terrain edit revision")
	_check(after.get("height_mm") != before.get("height_mm"), "R2 real terrain edit changes shoreline topography")
	var result_after: Dictionary = VisualScript.derive_shoreline_geometry(
		region, environment, edited_job["record"], after
	)
	_check(result_after.get("ok", false), "R2 edited canonical SDF builds a new ocean mesh")
	_check(_projected_area(result_after.get("vertices", PackedVector3Array())) < old_area, "R2 filling the coast reduces visible ocean area")
	_check(not VisualScript.derive_shoreline_geometry(
		region, environment, edited_job["record"], before
	).get("ok", false), "R2 stale unedited shoreline is rejected against edited SDF cache")


func _shoreline_worker(region: Vector2i, brush: RefCounted) -> Dictionary:
	var snapshots: Dictionary = {}
	for coordinate in ChunkGrid.all_coordinates():
		var snap: Dictionary = brush.get_meshing_snapshot_for_chunk(region, coordinate)
		if not snap.get("valid", false):
			return {"valid": false, "reason": "snapshot_invalid"}
		snapshots[coordinate] = snap
	var job := SurfaceJobScript.new(
		"region:%d,%d" % [region.x, region.y],
		424242, 1, region, int(brush.revision),
		int(brush.get_instance_id()), 0,
		snapshots, Time.get_ticks_usec()
	)
	job.build_visual_shoreline = true
	job.visual_refine_levels_mm = PackedInt64Array([4000])
	job.run()
	return job.result


func _test_startup_locations() -> void:
	var normal: Dictionary = StartupLocation.select_from_args(PackedStringArray(), 424242)
	_check(normal.get("ok", false) and normal.get("mode") == "default", "default startup behavior unchanged")
	_check(normal.get("target") == Vector3(8.0, 3.1, 6.0), "normal initial camera focus unchanged")

	var manual: Dictionary = StartupLocation.select_from_args(
		PackedStringArray(["--start-region=-2,13"]), 424242
	)
	_check(manual.get("ok", false), "manual negative region coordinates accepted")
	_check(manual.get("region") == Vector2i(-2, 13), "manual region identity preserved")
	_check(manual.get("target") == Vector3(-24.0, 3.1, 162.0), "manual region centers camera exactly")

	var position: Dictionary = StartupLocation.select_from_args(
		PackedStringArray(["--start-position=-27.5,161.25"]), 424242
	)
	_check(position.get("ok", false), "manual floating-point world coordinates accepted")
	_check(position.get("target") == Vector3(-27.5, 3.1, 161.25), "world-space target preserved")
	_check(position.get("region") == Vector2i(-2, 13), "negative fractional world position maps to proper region")

	var water: Dictionary = StartupLocation.select_from_args(
		PackedStringArray(["--start-water=ocean"]), 424242
	)
	_check(water.get("ok", false), "generated ocean start resolves a candidate")
	if water.get("ok", false):
		_check(int(water.get("candidate_water_cells", 0)) >= 1, "ocean start chooses region with base-SDF wet cell")
		var region: Vector2i = water["region"]
		_check(region.y >= 10, "ocean starts at or beyond global cell Z threshold")
		_check(float(water["target"].z) >= 120.0, "ocean start is at or beyond world Z 120 meters")
		_check(region == StartupLocation.select_from_args(
			PackedStringArray(["--start-water=ocean"]), 424242
		).get("region"), "ocean preset is deterministic for identical world seed")

	_check(not StartupLocation.select_from_args(
		PackedStringArray(["--start-water=lake"]), 424242
	).get("ok", false), "unknown water preset rejected")
	_check(not StartupLocation.select_from_args(
		PackedStringArray(["--start-region=2.1,10"]), 424242
	).get("ok", false), "fractional region coordinates rejected")
	_check(not StartupLocation.select_from_args(
		PackedStringArray(["--start-position=nan,120"]), 424242
	).get("ok", false), "nonfinite world coordinates rejected")
	_check(not StartupLocation.select_from_args(
		PackedStringArray(["--start-region=100000,10"]), 424242
	).get("ok", false), "out-of-bounds startup coordinates rejected")
	_check(not StartupLocation.select_from_args(
		PackedStringArray(["--start-water=ocean", "--start-region=0,10"]), 424242
	).get("ok", false), "conflicting startup modes rejected")


func _test_bundled_ocean_end_to_end() -> void:
	# Preserve the strict legacy first-party registry contract when the climate
	# type handler is absent; the playable scene separately opts into profiles.
	var legacy_roots: Array[String] = ["res://mods/first-party"]
	var legacy_discovery: Dictionary = Loader.discover_and_validate(legacy_roots)
	_check(legacy_discovery.get("ok", false), "legacy first-party discovery remains valid")
	var legacy_registry: RefCounted = RegistryScript.new()
	_check(legacy_registry.register_discovered(legacy_discovery).get("ok", false), "legacy registry without climate handler remains valid")
	_check(legacy_registry.get_content_record_ids(ClimateScript.PROFILE_TYPE).is_empty(), "legacy registry does not acquire climate content")
	var roots: Array[String] = ["res://mods/first-party", "res://mods/environment-presets"]
	var discovery: Dictionary = Loader.discover_and_validate(roots)
	_check(discovery.get("ok", false), "playable mod-first discovery joins base and isolated environment root")
	if not discovery.get("ok", false):
		return
	var registry: RefCounted = RegistryScript.new()
	var climate_domain: RefCounted = ClimateScript.new()
	_check(registry.register_engine_content_type_handler(
		climate_domain.create_content_handler()
	).get("ok", false), "climate handler registers alongside first-party packages")
	var registered: Dictionary = registry.register_discovered(discovery)
	_check(registered.get("ok", false), "playable climate JSON validates and registers")
	if not registered.get("ok", false):
		return
	var profile_ids: Array[String] = registry.get_content_record_ids(ClimateScript.PROFILE_TYPE)
	_check(profile_ids.size() == 1, "default playable bundles exactly one climate profile")
	if profile_ids.size() != 1:
		return
	_check(profile_ids[0] == "firstparty.core_climate:temperate", "default first-party climate has stable namespaced ID")
	var runtime: Node = RuntimeScript.new()
	_check(runtime.initialize_runtime(100_000, 4, 0, false).get("ok", false), "ocean runtime initializes")
	var configured: Dictionary = runtime.configure_environment_climate(registry, profile_ids[0])
	_check(configured.get("ok", false), "real climate profile binds with canonical content fingerprint")
	if not configured.get("ok", false):
		runtime.free()
		return
	var runoff: Dictionary = runtime.configure_environment_runoff(registry, profile_ids[0])
	_check(runoff.get("ok", false), "runoff binds actual bundled climate profile")
	var hydrology: Dictionary = runtime.configure_environment_hydrology(424242, 1)
	_check(hydrology.get("ok", false), "ocean hydrology activates with bundled default profile")
	if not hydrology.get("ok", false):
		runtime.free()
		return
	var region := Vector2i(-4, 13)
	var scope_id := "region:-4,13"
	_check(runtime.register_simulation_scope(scope_id, "active").get("ok", false), "ocean simulation scope registers")
	_check(runtime.register_environment_scope(scope_id).get("ok", false), "ocean environment scope registers")
	var baseline: Dictionary = runtime.get_environment_scope(scope_id)
	_check(baseline.get("profile_id") == profile_ids[0], "registered ocean scope inherits the canonical climate pin")
	_check(runtime.expect_environment_surface_cache(
		scope_id, region, 424242, 1, 0, 9876, 0
	).get("ok", false), "ocean surface provenance token is expected")
	var surface: Dictionary = _surface(region)
	surface["world_seed"] = 424242
	surface["terrain_cache_scope_id"] = 9876
	var heights: PackedInt64Array = surface["surface_height_mm"]
	heights.fill(3000)
	surface["surface_height_mm"] = heights
	var slopes := PackedInt32Array()
	slopes.resize(48)
	var masks := PackedByteArray()
	masks.resize(48)
	var deltas := PackedInt64Array()
	deltas.resize(48 * 4)
	var downhill := PackedInt32Array()
	downhill.resize(48)
	downhill.fill(-1)
	var drops := PackedInt64Array()
	drops.resize(48)
	surface["slope_milli"] = slopes
	surface["neighbor_mask"] = masks
	surface["neighbor_delta_mm"] = deltas
	surface["downhill_neighbor"] = downhill
	surface["downhill_drop_mm"] = drops
	_check(runtime.publish_environment_surface_cache(surface).get("ok", false), "real runtime accepts derived ocean SDF cache")
	var batch: Dictionary = runtime.process_environment_hydrology_batch([scope_id], 1, 1)
	_check(batch.get("ok", false), "real climate+runoff+ocean hydrology batch commits")
	var authoritative: Dictionary = runtime.get_environment_scope(scope_id)
	var kinds: PackedByteArray = authoritative.get("reservoir_kind", PackedByteArray())
	var ocean_cells := 0
	for kind in kinds:
		if int(kind) == EnvironmentStore.RESERVOIR_OCEAN:
			ocean_cells += 1
	_check(ocean_cells == 48, "real hydrology binds all 48 ocean cells at fixed 4m plane")
	var plan: Dictionary = VisualScript.derive_water_cells(
		region, authoritative, runtime.get_environment_surface_cache(scope_id)
	)
	_check(plan.get("ok", false), "live runtime ocean authority produces derived visible-water plan")
	_check((plan.get("cells", []) as Array).size() == ocean_cells, "live ocean cell count matches visual quads")
	_check(int(authoritative.get("state_revision", 0)) > 0, "ocean binding changes authoritative state revision")
	runtime.free()


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
