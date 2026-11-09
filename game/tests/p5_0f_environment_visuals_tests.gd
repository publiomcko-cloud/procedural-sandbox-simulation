extends SceneTree

const VisualScript := preload("res://scripts/simulation/environment_visual_presentation.gd")
const EnvironmentStore := preload("res://scripts/simulation/environment_state_store.gd")
const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const ClimateScript := preload("res://scripts/simulation/environment_climate_domain.gd")
const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const StartupLocation := preload("res://scripts/simulation/environment_startup_location.gd")

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
	_check(int(presenter.call("get_visual_metrics")["resident_region_nodes"]) == 1, "repeated publication is idempotent")
	var original := runtime.environment.duplicate(true)
	presenter.call("process_visual_frame", 0.2, Vector3(4, 10, 4), Vector2i.ZERO)
	var node := presenter.get_node("Water_0_0") as MultiMeshInstance3D
	_check(node.visible and node.multimesh.visible_instance_count == 3, "one region MultiMesh shows three water cells")
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
	_check(node.multimesh.visible_instance_count == 2, "new authority revision refreshes finite water visuals")
	runtime.environment["profile_sha256"] = "different"
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(not presenter.get_node("DerivedRain").visible, "rain refuses mismatched climate pin")
	presenter.call("unregister_region", Vector2i.ZERO)
	_check(int(presenter.call("get_visual_metrics")["resident_region_nodes"]) == 0, "unload removes transient region renderer")
	_check(runtime.environment["state_revision"] == 3, "unload does not delete persistent authority")
	presenter.call("register_region", Vector2i.ZERO)
	presenter.call("process_visual_frame", 0.2, Vector3.ZERO, Vector2i.ZERO)
	_check(int(presenter.call("get_visual_metrics")["region_rebuilds_total"]) == 4, "revisit reconstructs derived visuals from authority")
	presenter.queue_free()
	runtime.queue_free()


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
