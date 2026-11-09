extends SceneTree

const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const ClimateDomainScript := preload("res://scripts/simulation/environment_climate_domain.gd")
const EnvironmentStoreScript := preload("res://scripts/simulation/environment_state_store.gd")
const SurfaceCacheScript := preload("res://scripts/simulation/environment_surface_cache.gd")
const BatchJobScript := preload("res://scripts/simulation/environment_hydrology_batch_job.gd")
const TierStateScript := preload("res://scripts/simulation/simulation_tier_state.gd")

class FakeClimateRegistry:
	extends RefCounted

	var _profile: Dictionary
	var _fingerprint: Dictionary

	func _init(profile: Dictionary) -> void:
		_profile = profile.duplicate(true)
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(JSON.stringify(_profile, "", true, true).to_utf8_buffer())
		_fingerprint = {
			"content_id": String(_profile["id"]),
			"content_type": String(_profile["type"]),
			"mod_id": String(_profile["id"]).get_slice(":", 0),
			"mod_version": "1.0.0",
			"schema_version": int(_profile["schema_version"]),
			"content_sha256": context.finish().hex_encode(),
		}

	func get_content_record(content_type: String, namespaced_id: String) -> Dictionary:
		if content_type != String(_profile["type"]) or namespaced_id != String(_profile["id"]):
			return {}
		return _profile.duplicate(true)

	func pin_content_record(content_type: String, namespaced_id: String) -> Dictionary:
		var record: Dictionary = get_content_record(content_type, namespaced_id)
		if record.is_empty():
			return {"ok": false, "reason": "content_record_missing"}
		return {"ok": true, "fingerprint": _fingerprint.duplicate(true)}

	func validate_content_fingerprint(fingerprint: Dictionary) -> Dictionary:
		return {
			"ok": fingerprint == _fingerprint,
			"reason": "ok" if fingerprint == _fingerprint else "content_fingerprint_mismatch",
		}


var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_generated_reservoir_binding()
	_test_reservoir_unlimited_withdrawal()
	_test_reservoir_inflow_fixed_level()
	_test_cross_region_finite_atomic_transfer()
	_test_cross_region_stale_conflict_is_all_or_nothing()
	_test_missing_adjacent_cache_defers_without_loss()
	_test_unload_reload_preserves_authority()
	_test_batch_worker_thread_compatibility()
	_test_cross_region_deterministic_replay()
	_test_lifecycle_bounded_batch_scheduling()

	if failures == 0:
		print("P5_0E_CROSS_REGION_HYDROLOGY_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error(
			"P5_0E_CROSS_REGION_HYDROLOGY_FAIL: assertions=%d failures=%d"
			% [assertions, failures]
		)
		quit(1)


func _profile(id: String = "test.hydrology:default") -> Dictionary:
	return {
		"schema_version": 1,
		"type": ClimateDomainScript.PROFILE_TYPE,
		"id": id,
		"air_temperature_milli_c": 20_000,
		"precipitation_ul_per_cell_per_tick": 0,
		"infiltration_ul_per_cell_per_tick": 0,
		"soil_capacity_ul_per_cell": 1_000_000,
		"evaporation_ul_per_cell_per_tick": 0,
	}


func _runtime(
	profile_id: String = "test.hydrology:default",
	aggregate_interval: int = 4
) -> Node:
	var runtime: Node = RuntimeScript.new()
	_check(
		runtime.initialize_runtime(100_000, 4, 0, false, aggregate_interval).get("ok", false),
		"runtime initializes for P5.0E fixture"
	)
	var registry: RefCounted = FakeClimateRegistry.new(_profile(profile_id))
	_check(
		runtime.configure_environment_climate(registry, profile_id).get("ok", false),
		"climate binding succeeds before world hydrology"
	)
	_check(
		runtime.configure_environment_runoff(registry, profile_id).get("ok", false),
		"runoff binding succeeds before world hydrology"
	)
	_check(
		runtime.configure_environment_hydrology(42, 1).get("ok", false),
		"world hydrology binds exact world seed and generator version"
	)
	return runtime


func _register_scope(
	runtime: Node,
	region: Vector2i,
	tier: String = TierStateScript.TIER_ACTIVE
) -> String:
	var scope_id := "region:%d,%d" % [region.x, region.y]
	_check(
		runtime.register_simulation_scope(scope_id, tier).get("ok", false),
		"simulation scope registers: %s" % scope_id
	)
	_check(
		runtime.register_environment_scope(scope_id).get("ok", false),
		"environment scope registers: %s" % scope_id
	)
	return scope_id


func _publish_surface(
	runtime: Node,
	region: Vector2i,
	terrain_revision: int = 0,
	default_height_mm: int = 3_000,
	height_overrides: Dictionary = {}
) -> Dictionary:
	var scope_id := "region:%d,%d" % [region.x, region.y]
	var expected: Dictionary = runtime.expect_environment_surface_cache(
		scope_id, region, 42, 1, terrain_revision, 1000 + region.x * 97 + region.y * 193, 0
	)
	if not expected.get("ok", false):
		return expected
	var count := SurfaceCacheScript.DEFAULT_GRID_WIDTH * SurfaceCacheScript.DEFAULT_GRID_HEIGHT
	var valid := PackedByteArray()
	valid.resize(count)
	valid.fill(1)
	var heights := PackedInt64Array()
	heights.resize(count)
	heights.fill(default_height_mm)
	for key in height_overrides:
		heights[int(key)] = int(height_overrides[key])
	var slopes := PackedInt32Array()
	slopes.resize(count)
	var masks := PackedByteArray()
	masks.resize(count)
	var deltas := PackedInt64Array()
	deltas.resize(count * SurfaceCacheScript.NEIGHBOR_COUNT)
	var downhill := PackedInt32Array()
	downhill.resize(count)
	downhill.fill(-1)
	var drops := PackedInt64Array()
	drops.resize(count)
	return runtime.publish_environment_surface_cache({
		"scope_id": scope_id,
		"region_key": region,
		"world_seed": 42,
		"generator_version": 1,
		"terrain_revision": terrain_revision,
		"terrain_cache_scope_id": 1000 + region.x * 97 + region.y * 193,
		"terrain_effect_revision": 0,
		"grid_width": SurfaceCacheScript.DEFAULT_GRID_WIDTH,
		"grid_height": SurfaceCacheScript.DEFAULT_GRID_HEIGHT,
		"cell_size_x_mm": SurfaceCacheScript.DEFAULT_CELL_SIZE_X_MM,
		"cell_size_z_mm": SurfaceCacheScript.DEFAULT_CELL_SIZE_Z_MM,
		"surface_valid": valid,
		"surface_height_mm": heights,
		"slope_milli": slopes,
		"neighbor_mask": masks,
		"neighbor_delta_mm": deltas,
		"downhill_neighbor": downhill,
		"downhill_drop_mm": drops,
	})


func _set_cell(
	runtime: Node,
	scope_id: String,
	cell: int,
	surface_ul: int,
	soil_ul: int,
	kind: int,
	level_mm: int,
	tick: int
) -> Dictionary:
	var record: Dictionary = runtime.get_environment_scope(scope_id)
	var surface: PackedInt64Array = record["surface_water_ul"].duplicate()
	var soil: PackedInt64Array = record["soil_water_ul"].duplicate()
	var kinds: PackedByteArray = record["reservoir_kind"].duplicate()
	var levels: PackedInt64Array = record["reservoir_level_mm"].duplicate()
	surface[cell] = surface_ul
	soil[cell] = soil_ul
	kinds[cell] = kind
	levels[cell] = level_mm
	return runtime.commit_environment_batch([{
		"scope_id": scope_id,
		"expected_state_revision": int(record["state_revision"]),
		"last_environment_tick": tick,
		"surface_water_ul": surface,
		"soil_water_ul": soil,
		"reservoir_kind": kinds,
		"reservoir_level_mm": levels,
		"reservoir_inflow_ul_delta": 0,
		"reservoir_outflow_ul_delta": 0,
	}])


func _cell_surface(runtime: Node, scope_id: String, cell: int) -> int:
	return int(
		(runtime.get_environment_scope(scope_id)["surface_water_ul"] as PackedInt64Array)[cell]
	)


func _test_generated_reservoir_binding() -> void:
	var runtime := _runtime("test.hydrology:binding")
	var domain: RefCounted = runtime.environment_hydrology_domain
	var ocean: Dictionary = domain.generated_binding_for_cell(Vector2i(0, 10), 0, 3_500)
	_check(
		int(ocean.get("kind", -1)) == EnvironmentStoreScript.RESERVOIR_OCEAN
			and int(ocean.get("level_mm", -1)) == 4_000,
		"generated ocean binding uses fixed authoritative sea level"
	)
	var ocean_repeat: Dictionary = domain.generated_binding_for_cell(Vector2i(0, 10), 0, 3_500)
	_check(ocean == ocean_repeat, "generated ocean placement is deterministic")

	var river_found := false
	for rx in range(-3, 4):
		for rz in range(-2, 3):
			for cell in range(48):
				var river: Dictionary = domain.generated_binding_for_cell(Vector2i(rx, rz), cell, 3_000)
				if int(river.get("kind", -1)) == EnvironmentStoreScript.RESERVOIR_RIVER:
					river_found = true
					_check(
						int(river["level_mm"]) == 3_250,
						"generated river binding pins a fixed level above derived terrain at first binding"
					)
					break
			if river_found:
				break
		if river_found:
			break
	_check(river_found, "integer world-space generator places a deterministic river corridor")


func _test_reservoir_unlimited_withdrawal() -> void:
	var runtime := _runtime("test.hydrology:withdraw")
	var scope := _register_scope(runtime, Vector2i(20, 0))
	_check(
		_publish_surface(runtime, Vector2i(20, 0), 0, 1_000).get("ok", false),
		"withdrawal fixture publishes surface cache"
	)
	_check(
		_set_cell(runtime, scope, 0, 0, 0, EnvironmentStoreScript.RESERVOIR_RIVER, 5_000, 1).get("ok", false),
		"withdrawal fixture binds explicit river reservoir"
	)
	var initial_level := int(
		(runtime.get_environment_scope(scope)["reservoir_level_mm"] as PackedInt64Array)[0]
	)
	for tick in range(2, 6):
		var result: Dictionary = runtime.process_environment_hydrology_batch([scope], tick, 1)
		_check(result.get("ok", false), "reservoir withdrawal batch %d succeeds" % tick)
	var record: Dictionary = runtime.get_environment_scope(scope)
	_check(
		int((record["reservoir_level_mm"] as PackedInt64Array)[0]) == initial_level,
		"repeated withdrawal never lowers authoritative river level"
	)
	_check(
		int((record["reservoir_outflow_ul_total"])) >= 4_000_000,
		"repeated reservoir withdrawal is explicitly accumulated without depletion"
	)
	_check(
		int((record["surface_water_ul"] as PackedInt64Array)[0]) == 0
			and int((record["soil_water_ul"] as PackedInt64Array)[0]) == 0,
		"infinite reservoir cell never stores finite water while supplying neighbors"
	)


func _test_reservoir_inflow_fixed_level() -> void:
	var runtime := _runtime("test.hydrology:inflow")
	var scope := _register_scope(runtime, Vector2i(20, 1))
	_check(
		_publish_surface(
			runtime, Vector2i(20, 1), 0, 5_000, {0: 1_000, 1: 5_000}
		).get("ok", false),
		"inflow fixture publishes reservoir/finite elevations"
	)
	_check(
		_set_cell(runtime, scope, 0, 0, 0, EnvironmentStoreScript.RESERVOIR_RIVER, 1_000, 1).get("ok", false),
		"inflow fixture binds low fixed river level"
	)
	var current: Dictionary = runtime.get_environment_scope(scope)
	var surface: PackedInt64Array = current["surface_water_ul"].duplicate()
	surface[1] = 400
	var seeded: Dictionary = runtime.commit_environment_batch([{
		"scope_id": scope,
		"expected_state_revision": int(current["state_revision"]),
		"last_environment_tick": 2,
		"surface_water_ul": surface,
		"soil_water_ul": (current["soil_water_ul"] as PackedInt64Array).duplicate(),
		"reservoir_kind": (current["reservoir_kind"] as PackedByteArray).duplicate(),
		"reservoir_level_mm": (current["reservoir_level_mm"] as PackedInt64Array).duplicate(),
		"reservoir_inflow_ul_delta": 0,
		"reservoir_outflow_ul_delta": 0,
	}])
	_check(seeded.get("ok", false), "inflow fixture seeds adjacent finite water")
	var before_level := int(
		(runtime.get_environment_scope(scope)["reservoir_level_mm"] as PackedInt64Array)[0]
	)
	var result: Dictionary = runtime.process_environment_hydrology_batch([scope], 3, 1)
	_check(result.get("ok", false), "finite-to-reservoir exchange commits")
	var after: Dictionary = runtime.get_environment_scope(scope)
	_check(
		int(after["reservoir_inflow_ul_total"]) >= 100,
		"finite inflow into infinite reservoir is explicitly counted"
	)
	_check(
		int((after["reservoir_level_mm"] as PackedInt64Array)[0]) == before_level,
		"arbitrary reservoir inflow does not raise fixed authoritative level"
	)


func _test_cross_region_finite_atomic_transfer() -> void:
	var runtime := _runtime("test.hydrology:cross")
	var left_region := Vector2i(10, 0)
	var right_region := Vector2i(11, 0)
	var left := _register_scope(runtime, left_region)
	var right := _register_scope(runtime, right_region)
	var left_edge := 7
	var right_edge := 0
	_check(
		_publish_surface(runtime, left_region, 0, 3_000, {left_edge: 5_000}).get("ok", false),
		"left cross-region cache publishes"
	)
	_check(
		_publish_surface(runtime, right_region, 0, 3_000, {right_edge: 1_000}).get("ok", false),
		"right cross-region cache publishes"
	)
	_check(
		_set_cell(runtime, left, left_edge, 400, 0, EnvironmentStoreScript.RESERVOIR_FINITE, 0, 1).get("ok", false),
		"cross-region source water seeds"
	)
	var result: Dictionary = runtime.process_environment_hydrology_batch(
		[left, right], 2, 2
	)
	_check(
		result.get("ok", false)
			and int(result.get("committed_scope_count", 0)) == 2
			and int(result.get("cross_region_transfer_ul", 0)) == 100,
		"cross-region finite transfer commits both scopes in one atomic batch"
	)
	_check(
		_cell_surface(runtime, left, left_edge) == 300
			and _cell_surface(runtime, right, right_edge) == 100,
		"atomic boundary transfer subtracts and adds the exact same integer volume"
	)


func _test_cross_region_stale_conflict_is_all_or_nothing() -> void:
	var runtime := _runtime("test.hydrology:stale")
	var left_region := Vector2i(12, 0)
	var right_region := Vector2i(13, 0)
	var left := _register_scope(runtime, left_region)
	var right := _register_scope(runtime, right_region)
	_check(_publish_surface(runtime, left_region, 0, 3_000, {7: 5_000}).get("ok", false), "stale left cache publishes")
	_check(_publish_surface(runtime, right_region, 0, 3_000, {0: 1_000}).get("ok", false), "stale right cache publishes")
	_check(_set_cell(runtime, left, 7, 400, 0, EnvironmentStoreScript.RESERVOIR_FINITE, 0, 1).get("ok", false), "stale fixture seeds source")
	var domain: RefCounted = runtime.environment_hydrology_domain
	var built: Dictionary = domain.build_batch_snapshot(
		runtime.environment_state_store,
		runtime.environment_surface_cache,
		[left, right],
		2,
		2
	)
	_check(built.get("ok", false), "stale fixture builds immutable two-scope snapshot")
	var solved: Dictionary = domain.solve_batch_snapshot(built["work_snapshot"])
	_check(solved.get("ok", false), "stale fixture solves boundary batch")

	var right_before: Dictionary = runtime.get_environment_scope(right)
	var left_current: Dictionary = runtime.get_environment_scope(left)
	var changed: PackedInt64Array = left_current["surface_water_ul"].duplicate()
	changed[6] = 1
	_check(
		runtime.commit_environment_batch([{
			"scope_id": left,
			"expected_state_revision": int(left_current["state_revision"]),
			"last_environment_tick": 2,
			"surface_water_ul": changed,
			"soil_water_ul": (left_current["soil_water_ul"] as PackedInt64Array).duplicate(),
			"reservoir_kind": (left_current["reservoir_kind"] as PackedByteArray).duplicate(),
			"reservoir_level_mm": (left_current["reservoir_level_mm"] as PackedInt64Array).duplicate(),
			"reservoir_inflow_ul_delta": 0,
			"reservoir_outflow_ul_delta": 0,
		}]).get("ok", false),
		"one scope advances after worker snapshot"
	)
	var commit: Dictionary = domain.commit_batch_result(
		runtime.environment_state_store,
		runtime.environment_surface_cache,
		solved
	)
	_check(
		commit.get("ok", false)
			and commit.get("deferred", false)
			and int(commit.get("committed_scope_count", -1)) == 0,
		"revision conflict rejects entire cross-region batch before any partial commit"
	)
	_check(
		runtime.get_environment_scope(right) == right_before,
		"stale batch leaves unaffected neighbor byte-equivalent"
	)


func _test_missing_adjacent_cache_defers_without_loss() -> void:
	var runtime := _runtime("test.hydrology:stream")
	var left_region := Vector2i(14, 0)
	var right_region := Vector2i(15, 0)
	var left := _register_scope(runtime, left_region)
	var right := _register_scope(runtime, right_region)
	_check(_publish_surface(runtime, left_region, 0, 3_000, {7: 5_000}).get("ok", false), "streaming source cache publishes")
	_check(_set_cell(runtime, left, 7, 400, 0, EnvironmentStoreScript.RESERVOIR_FINITE, 0, 1).get("ok", false), "streaming source water seeds")
	var first: Dictionary = runtime.process_environment_hydrology_batch([left, right], 2, 2)
	_check(first.get("ok", false), "batch proceeds with available scope while adjacent cache is absent")
	_check(
		first.get("deferred_scope_ids", []).has(right),
		"missing adjacent surface cache is explicitly deferred"
	)
	_check(_cell_surface(runtime, left, 7) == 400, "missing neighbor cache neither loses nor exports source water")
	_check(_publish_surface(runtime, right_region, 0, 3_000, {0: 1_000}).get("ok", false), "adjacent cache later becomes available")
	var second: Dictionary = runtime.process_environment_hydrology_batch([left, right], 3, 2)
	_check(
		second.get("ok", false)
			and int(second.get("cross_region_transfer_ul", 0)) == 100,
		"later common tick performs deferred cross-region flow exactly once"
	)


func _test_unload_reload_preserves_authority() -> void:
	var runtime := _runtime("test.hydrology:reload")
	_check(
		runtime.configure_world_scope_lifecycle("", 4, 16_000, 12_000, 8).get("ok", false),
		"reload fixture configures streaming lifecycle"
	)
	var region := Vector2i(18, 0)
	var scope := "region:18,0"
	_check(runtime.publish_world_region_scope(region).get("ok", false), "reload fixture publishes region scope")
	_check(runtime.update_world_scope_focus(region).get("ok", false), "reload fixture focuses region")
	_check(_publish_surface(runtime, region).get("ok", false), "reload fixture publishes surface cache")
	_check(_set_cell(runtime, scope, 10, 777, 0, EnvironmentStoreScript.RESERVOIR_FINITE, 0, 1).get("ok", false), "reload fixture seeds persistent finite water")
	var before: Dictionary = runtime.get_environment_scope(scope)
	_check(runtime.unload_world_region_scope(region).get("ok", false), "region unload succeeds")
	_check(runtime.get_environment_scope(scope) == before, "region unload retains authoritative water state")
	_check(runtime.publish_world_region_scope(region).get("ok", false), "region reload reuses stable environment scope")
	_check(_publish_surface(runtime, region).get("ok", false), "region reload reconstructs derived surface cache")
	_check(runtime.get_environment_scope(scope) == before, "region reload neither duplicates nor loses committed water")


func _test_batch_worker_thread_compatibility() -> void:
	var runtime := _runtime("test.hydrology:worker")
	var left := _register_scope(runtime, Vector2i(22, 0))
	var right := _register_scope(runtime, Vector2i(23, 0))
	_check(_publish_surface(runtime, Vector2i(22, 0), 0, 3_000, {7: 5_000}).get("ok", false), "worker left cache publishes")
	_check(_publish_surface(runtime, Vector2i(23, 0), 0, 3_000, {0: 1_000}).get("ok", false), "worker right cache publishes")
	_check(_set_cell(runtime, left, 7, 400, 0, EnvironmentStoreScript.RESERVOIR_FINITE, 0, 1).get("ok", false), "worker source seeds")
	var domain: RefCounted = runtime.environment_hydrology_domain
	var built: Dictionary = domain.build_batch_snapshot(
		runtime.environment_state_store,
		runtime.environment_surface_cache,
		[left, right],
		2,
		2
	)
	var job: RefCounted = BatchJobScript.new(built["work_snapshot"])
	var task_id := WorkerThreadPool.add_task(
		Callable(job, "run"), false, "P5.0E cross-region hydrology"
	)
	_check(task_id >= 0, "cross-region hydrology worker is accepted by WorkerThreadPool")
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		_check(job.result.get("ok", false), "cross-region hydrology worker solves immutable batch off-thread")
		_check(int(job.worker_thread_id) != 0, "cross-region hydrology worker records executing thread")


func _test_cross_region_deterministic_replay() -> void:
	var a := _runtime("test.hydrology:replay")
	var b := _runtime("test.hydrology:replay")
	for runtime in [a, b]:
		var left := _register_scope(runtime, Vector2i(24, 0))
		var right := _register_scope(runtime, Vector2i(25, 0))
		_check(_publish_surface(runtime, Vector2i(24, 0), 0, 3_000, {7: 5_000}).get("ok", false), "replay left cache publishes")
		_check(_publish_surface(runtime, Vector2i(25, 0), 0, 3_000, {0: 1_000}).get("ok", false), "replay right cache publishes")
		_check(_set_cell(runtime, left, 7, 1024, 0, EnvironmentStoreScript.RESERVOIR_FINITE, 0, 1).get("ok", false), "replay source seeds")
	for tick in range(2, 7):
		var ar: Dictionary = a.process_environment_hydrology_batch(
			["region:24,0", "region:25,0"], tick, 2
		)
		var br: Dictionary = b.process_environment_hydrology_batch(
			["region:24,0", "region:25,0"], tick, 2
		)
		_check(ar.get("ok", false) and br.get("ok", false), "cross-region replay tick %d succeeds" % tick)
	_check(
		a.get_environment_state_snapshot() == b.get_environment_state_snapshot(),
		"cross-region deterministic replay produces byte-equivalent authoritative state"
	)


func _test_lifecycle_bounded_batch_scheduling() -> void:
	var runtime := _runtime("test.hydrology:lifecycle")
	_check(
		runtime.configure_world_scope_lifecycle("", 3, 16_000, 12_000, 3).get("ok", false),
		"bounded hydrology lifecycle configures exactly one resident sweep per tick"
	)
	for x in range(3):
		var region := Vector2i(30 + x, 0)
		_check(runtime.publish_world_region_scope(region).get("ok", false), "bounded lifecycle publishes region %d" % x)
		_check(_publish_surface(runtime, region).get("ok", false), "bounded lifecycle surface cache publishes %d" % x)
	_check(runtime.update_world_scope_focus(Vector2i(31, 0)).get("ok", false), "bounded lifecycle focus updates")
	var frame: Dictionary = runtime.process_elapsed_usec(400_000)
	_check(frame.get("ok", false), "bounded hydrology scheduler frame succeeds")
	_check(
		int(frame.get("environment_capacity_admission_limit", -1)) == 1,
		"three resident scopes and budget three admit at most one logical tick"
	)
	var lifecycle: Dictionary = runtime.get_world_scope_lifecycle_metrics()
	_check(
		int(lifecycle.get("due_decisions_total", 0)) <= 3,
		"world hydrology neighbor scheduling stays within configured per-frame decision budget"
	)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
