extends SceneTree

const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const ClimateDomainScript := preload("res://scripts/simulation/environment_climate_domain.gd")
const RunoffDomainScript := preload("res://scripts/simulation/environment_runoff_domain.gd")
const RunoffJobScript := preload("res://scripts/simulation/environment_runoff_job.gd")
const EnvironmentStoreScript := preload("res://scripts/simulation/environment_state_store.gd")
const SurfaceCacheScript := preload("res://scripts/simulation/environment_surface_cache.gd")
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
	_test_rain_accumulates_and_moves_downhill()
	_test_climate_infiltration_evaporation_composition()
	_test_terrain_revision_changes_later_path()
	_test_closed_fixture_conservation()
	_test_revision_gates()
	_test_tier_policy()
	_test_missing_surface_cache_defers_without_mutation()
	_test_worker_thread_compatibility()
	_test_deterministic_replay()
	_test_lifecycle_backpressure()

	if failures == 0:
		print("P5_0D_FINITE_RUNOFF_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error(
			"P5_0D_FINITE_RUNOFF_FAIL: assertions=%d failures=%d"
			% [assertions, failures]
		)
		quit(1)


func _profile(
	id: String = "test.runoff:default",
	precipitation: int = 0,
	infiltration: int = 0,
	soil_capacity: int = 1_000_000,
	evaporation: int = 0
) -> Dictionary:
	return {
		"schema_version": 1,
		"type": ClimateDomainScript.PROFILE_TYPE,
		"id": id,
		"air_temperature_milli_c": 20_000,
		"precipitation_ul_per_cell_per_tick": precipitation,
		"infiltration_ul_per_cell_per_tick": infiltration,
		"soil_capacity_ul_per_cell": soil_capacity,
		"evaporation_ul_per_cell_per_tick": evaporation,
	}


func _runtime_with_runoff(
	profile: Dictionary,
	tier: String = TierStateScript.TIER_ACTIVE,
	aggregate_interval: int = 4,
	publish_surface: bool = true,
	downhill_destination: int = 1,
	terrain_revision: int = 0
) -> Dictionary:
	var runtime: Node = RuntimeScript.new()
	var initialized: Dictionary = runtime.initialize_runtime(
		100_000, 4, 0, false, aggregate_interval
	)
	_check(initialized.get("ok", false), "runtime initializes for runoff fixture")
	var registry: RefCounted = FakeClimateRegistry.new(profile)
	var climate: Dictionary = runtime.configure_environment_climate(
		registry, String(profile["id"])
	)
	_check(climate.get("ok", false), "runtime binds climate profile before runoff")
	var runoff: Dictionary = runtime.configure_environment_runoff(
		registry, String(profile["id"])
	)
	_check(runoff.get("ok", false), "runtime binds runoff to the exact climate pin")
	var registered: Dictionary = runtime.register_simulation_scope("region:0,0", tier)
	_check(registered.get("ok", false), "simulation scope registers for runoff")
	var environment: Dictionary = runtime.register_environment_scope("region:0,0")
	_check(environment.get("ok", false), "environment scope registers for runoff")
	if publish_surface:
		_check(
			_publish_surface(
				runtime, terrain_revision, downhill_destination
			).get("ok", false),
			"synthetic surface cache publishes"
		)
	return {"runtime": runtime, "registry": registry}


func _publish_surface(
	runtime: Node,
	terrain_revision: int,
	downhill_destination: int,
	scope_id: String = "region:0,0"
) -> Dictionary:
	var expected: Dictionary = runtime.expect_environment_surface_cache(
		scope_id,
		Vector2i.ZERO,
		42,
		1,
		terrain_revision,
		123,
		0
	)
	if not expected.get("ok", false):
		return expected
	var count := SurfaceCacheScript.DEFAULT_GRID_WIDTH * SurfaceCacheScript.DEFAULT_GRID_HEIGHT
	var valid := PackedByteArray()
	valid.resize(count)
	valid.fill(1)
	var heights := PackedInt64Array()
	heights.resize(count)
	heights.fill(1000)
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
	if downhill_destination >= 0 and downhill_destination < count:
		downhill[0] = downhill_destination
		drops[0] = 1000
		heights[0] = 1000
		heights[downhill_destination] = 0
	return runtime.publish_environment_surface_cache({
		"scope_id": scope_id,
		"region_key": Vector2i.ZERO,
		"world_seed": 42,
		"generator_version": 1,
		"terrain_revision": terrain_revision,
		"terrain_cache_scope_id": 123,
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


func _seed_surface(runtime: Node, amount: int, logical_tick: int = 1) -> Dictionary:
	var record: Dictionary = runtime.get_environment_scope("region:0,0")
	var surface: PackedInt64Array = record["surface_water_ul"].duplicate()
	var soil: PackedInt64Array = record["soil_water_ul"].duplicate()
	var kinds: PackedByteArray = record["reservoir_kind"].duplicate()
	var levels: PackedInt64Array = record["reservoir_level_mm"].duplicate()
	surface[0] = amount
	return runtime.commit_environment_batch([{
		"scope_id": "region:0,0",
		"expected_state_revision": int(record["state_revision"]),
		"last_environment_tick": logical_tick,
		"surface_water_ul": surface,
		"soil_water_ul": soil,
		"reservoir_kind": kinds,
		"reservoir_level_mm": levels,
		"reservoir_inflow_ul_delta": 0,
		"reservoir_outflow_ul_delta": 0,
	}])


func _finite_total(record: Dictionary) -> int:
	var surface: PackedInt64Array = record["surface_water_ul"]
	var soil: PackedInt64Array = record["soil_water_ul"]
	var kinds: PackedByteArray = record["reservoir_kind"]
	var total := 0
	for index in range(surface.size()):
		if int(kinds[index]) == EnvironmentStoreScript.RESERVOIR_FINITE:
			total += int(surface[index]) + int(soil[index])
	return total


func _test_rain_accumulates_and_moves_downhill() -> void:
	var fixture := _runtime_with_runoff(_profile("test.runoff:rain", 100, 0, 1000, 0))
	var runtime: Node = fixture["runtime"]
	var result: Dictionary = runtime.process_environment_runoff_scope("region:0,0", 1)
	_check(result.get("ok", false) and not result.get("noop", true), "due runoff step commits")
	var record: Dictionary = runtime.get_environment_scope("region:0,0")
	var surface: PackedInt64Array = record["surface_water_ul"]
	_check(int(surface[0]) == 75, "rain remains bounded at downhill source after runoff")
	_check(int(surface[1]) == 125, "rain moves into deterministic downhill neighbor")
	_check(_finite_total(record) == 4800, "rainfall accounting is exact across all finite cells")
	_check(
		int(result.get("runoff_ul", 0)) == 25
			and int(result.get("precipitation_ul", 0)) == 4800,
		"runoff reports explicit internal transfer and precipitation boundary term"
	)


func _test_climate_infiltration_evaporation_composition() -> void:
	var fixture := _runtime_with_runoff(
		_profile("test.runoff:climate", 100, 40, 1000, 10)
	)
	var runtime: Node = fixture["runtime"]
	var result: Dictionary = runtime.process_environment_runoff_scope("region:0,0", 1)
	_check(result.get("ok", false), "combined climate and runoff step succeeds")
	var record: Dictionary = runtime.get_environment_scope("region:0,0")
	var surface: PackedInt64Array = record["surface_water_ul"]
	var soil: PackedInt64Array = record["soil_water_ul"]
	_check(int(soil[0]) == 40 and int(soil[1]) == 40, "P5.0B infiltration remains composed into P5.0D")
	_check(int(surface[0]) == 37 and int(surface[1]) == 63, "evaporation precedes deterministic runoff in one commit")
	_check(
		int(result.get("infiltration_ul", 0)) == 1920
			and int(result.get("evaporation_ul", 0)) == 480,
		"combined solve exposes infiltration and evaporation accounting"
	)
	_check(_finite_total(record) == 4320, "combined climate boundary accounting conserves exact finite water")


func _test_terrain_revision_changes_later_path() -> void:
	var fixture := _runtime_with_runoff(_profile("test.runoff:terrain"))
	var runtime: Node = fixture["runtime"]
	_check(_seed_surface(runtime, 400, 1).get("ok", false), "terrain-path fixture seeds finite surface water")
	var first: Dictionary = runtime.process_environment_runoff_scope("region:0,0", 2)
	_check(first.get("ok", false) and int(first.get("runoff_ul", 0)) == 100, "first terrain revision routes water")
	var after_first: Dictionary = runtime.get_environment_scope("region:0,0")
	_check(int((after_first["surface_water_ul"] as PackedInt64Array)[1]) == 100, "first cache path targets cell 1")

	_check(_publish_surface(runtime, 1, 2).get("ok", false), "terrain revision invalidates and republishes surface cache")
	var second: Dictionary = runtime.process_environment_runoff_scope("region:0,0", 3)
	_check(second.get("ok", false) and int(second.get("runoff_ul", 0)) == 75, "later runoff uses revised terrain cache")
	var after_second: Dictionary = runtime.get_environment_scope("region:0,0")
	var surface: PackedInt64Array = after_second["surface_water_ul"]
	_check(int(surface[1]) == 100 and int(surface[2]) == 75, "terrain change redirects subsequent runoff without rewriting prior water")


func _test_closed_fixture_conservation() -> void:
	var fixture := _runtime_with_runoff(_profile("test.runoff:closed"))
	var runtime: Node = fixture["runtime"]
	_check(_seed_surface(runtime, 401, 1).get("ok", false), "closed fixture seeds water")
	var before: Dictionary = runtime.get_environment_scope("region:0,0")
	var total_before := _finite_total(before)
	var result: Dictionary = runtime.process_environment_runoff_scope("region:0,0", 2)
	var after: Dictionary = runtime.get_environment_scope("region:0,0")
	_check(result.get("ok", false), "closed runoff solve succeeds")
	_check(total_before == 401 and _finite_total(after) == 401, "closed finite fixture conserves exact integer water")
	_check(int(result.get("runoff_ul", 0)) == 101, "integer runoff uses deterministic ceil-quarter transfer")
	_check(int(result.get("precipitation_ul", 0)) == 0 and int(result.get("evaporation_ul", 0)) == 0, "closed fixture has no hidden boundary terms")


func _test_revision_gates() -> void:
	var fixture := _runtime_with_runoff(_profile("test.runoff:gate"))
	var runtime: Node = fixture["runtime"]
	_check(_seed_surface(runtime, 400, 1).get("ok", false), "state-gate fixture seeds water")
	var domain: RefCounted = runtime.environment_runoff_domain
	var built: Dictionary = domain.build_work_snapshot(
		runtime.environment_state_store,
		runtime.environment_surface_cache,
		"region:0,0",
		"test.runoff:gate",
		2
	)
	_check(built.get("ok", false), "revision gate builds immutable work snapshot")
	var solved: Dictionary = domain.solve_work_snapshot(built["work_snapshot"])
	_check(solved.get("ok", false), "revision gate solves immutable work snapshot")

	var current: Dictionary = runtime.get_environment_scope("region:0,0")
	var changed_surface: PackedInt64Array = current["surface_water_ul"].duplicate()
	changed_surface[3] = 1
	var state_change: Dictionary = runtime.commit_environment_batch([{
		"scope_id": "region:0,0",
		"expected_state_revision": int(current["state_revision"]),
		"last_environment_tick": 2,
		"surface_water_ul": changed_surface,
		"soil_water_ul": (current["soil_water_ul"] as PackedInt64Array).duplicate(),
		"reservoir_kind": (current["reservoir_kind"] as PackedByteArray).duplicate(),
		"reservoir_level_mm": (current["reservoir_level_mm"] as PackedInt64Array).duplicate(),
		"reservoir_inflow_ul_delta": 0,
		"reservoir_outflow_ul_delta": 0,
	}])
	_check(state_change.get("ok", false), "concurrent environment revision advances")
	var stale_state: Dictionary = domain.commit_solved_work(
		runtime.environment_state_store, runtime.environment_surface_cache, solved
	)
	_check(
		stale_state.get("ok", false)
			and stale_state.get("deferred", false)
			and stale_state.get("reason", "") == "environment_runoff_state_stale",
		"stale environment worker result cannot commit"
	)

	var fixture_surface := _runtime_with_runoff(_profile("test.runoff:surface-gate"))
	var runtime_surface: Node = fixture_surface["runtime"]
	_check(_seed_surface(runtime_surface, 400, 1).get("ok", false), "surface-gate fixture seeds water")
	var domain_surface: RefCounted = runtime_surface.environment_runoff_domain
	var built_surface: Dictionary = domain_surface.build_work_snapshot(
		runtime_surface.environment_state_store,
		runtime_surface.environment_surface_cache,
		"region:0,0",
		"test.runoff:surface-gate",
		2
	)
	var solved_surface: Dictionary = domain_surface.solve_work_snapshot(built_surface["work_snapshot"])
	_check(_publish_surface(runtime_surface, 1, 2).get("ok", false), "new terrain revision replaces expected cache token")
	var stale_surface: Dictionary = domain_surface.commit_solved_work(
		runtime_surface.environment_state_store,
		runtime_surface.environment_surface_cache,
		solved_surface
	)
	_check(
		stale_surface.get("ok", false)
			and stale_surface.get("deferred", false)
			and stale_surface.get("reason", "") == "environment_runoff_surface_cache_stale",
		"stale surface-derived worker result cannot commit"
	)


func _test_tier_policy() -> void:
	var dormant_fixture := _runtime_with_runoff(
		_profile("test.runoff:dormant", 100),
		TierStateScript.TIER_DORMANT
	)
	var dormant: Node = dormant_fixture["runtime"]
	var before: Dictionary = dormant.get_environment_scope("region:0,0")
	var dormant_result: Dictionary = dormant.process_environment_runoff_scope("region:0,0", 1)
	var after: Dictionary = dormant.get_environment_scope("region:0,0")
	_check(
		dormant_result.get("ok", false)
			and dormant_result.get("noop", false)
			and not dormant_result.get("due", true),
		"dormant scope retains state without hydrology mutation"
	)
	_check(before == after, "dormant runoff leaves authoritative environment state unchanged")

	var aggregate_fixture := _runtime_with_runoff(
		_profile("test.runoff:aggregate", 100),
		TierStateScript.TIER_AGGREGATE,
		4
	)
	var aggregate: Node = aggregate_fixture["runtime"]
	var due_tick := -1
	var non_due_tick := -1
	for tick in range(1, 9):
		var due: Dictionary = aggregate.get_simulation_due_decision("region:0,0", tick)
		if bool(due.get("due", false)) and due_tick < 0:
			due_tick = tick
		if not bool(due.get("due", false)) and non_due_tick < 0:
			non_due_tick = tick
	_check(due_tick > 0 and non_due_tick > 0, "aggregate fixture exposes due and non-due ticks")
	var non_due: Dictionary = aggregate.process_environment_runoff_scope("region:0,0", non_due_tick)
	_check(non_due.get("ok", false) and non_due.get("noop", false), "aggregate non-due tick performs no mutation")
	var due_result: Dictionary = aggregate.process_environment_runoff_scope("region:0,0", due_tick)
	_check(due_result.get("ok", false) and bool(due_result.get("due", false)), "aggregate due tick executes bounded hydrology")


func _test_missing_surface_cache_defers_without_mutation() -> void:
	var fixture := _runtime_with_runoff(
		_profile("test.runoff:defer", 100),
		TierStateScript.TIER_ACTIVE,
		4,
		false
	)
	var runtime: Node = fixture["runtime"]
	var before: Dictionary = runtime.get_environment_scope("region:0,0")
	var result: Dictionary = runtime.process_environment_runoff_scope("region:0,0", 1)
	var after: Dictionary = runtime.get_environment_scope("region:0,0")
	_check(
		result.get("ok", false)
			and result.get("deferred", false)
			and result.get("reason", "") == "environment_runoff_surface_cache_pending",
		"missing derived terrain cache defers runoff instead of mutating authority"
	)
	_check(before == after, "deferred runoff loses no water and advances no environment revision")


func _test_worker_thread_compatibility() -> void:
	var fixture := _runtime_with_runoff(_profile("test.runoff:worker"))
	var runtime: Node = fixture["runtime"]
	_check(_seed_surface(runtime, 400, 1).get("ok", false), "worker fixture seeds water")
	var domain: RefCounted = runtime.environment_runoff_domain
	var built: Dictionary = domain.build_work_snapshot(
		runtime.environment_state_store,
		runtime.environment_surface_cache,
		"region:0,0",
		"test.runoff:worker",
		2
	)
	var job: RefCounted = RunoffJobScript.new(built["work_snapshot"])
	var task_id := WorkerThreadPool.add_task(
		Callable(job, "run"), false, "P5.0D finite runoff"
	)
	_check(task_id >= 0, "finite runoff worker is accepted by WorkerThreadPool")
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		_check(job.result.get("ok", false), "finite runoff worker solves immutable snapshot off-thread")
		_check(int(job.worker_thread_id) != 0, "finite runoff worker records executing thread identity")


func _test_deterministic_replay() -> void:
	var profile := _profile("test.runoff:replay", 37, 5, 1000, 2)
	var fixture_a := _runtime_with_runoff(profile)
	var fixture_b := _runtime_with_runoff(profile)
	var runtime_a: Node = fixture_a["runtime"]
	var runtime_b: Node = fixture_b["runtime"]
	for tick in range(1, 6):
		var a: Dictionary = runtime_a.process_environment_runoff_scope("region:0,0", tick)
		var b: Dictionary = runtime_b.process_environment_runoff_scope("region:0,0", tick)
		_check(a.get("ok", false) and b.get("ok", false), "deterministic replay step %d succeeds" % tick)
	_check(
		runtime_a.get_environment_state_snapshot()
			== runtime_b.get_environment_state_snapshot(),
		"identical inputs replay to byte-equivalent authoritative environment state"
	)


func _test_lifecycle_backpressure() -> void:
	var profile := _profile("test.runoff:lifecycle", 100)
	var runtime: Node = RuntimeScript.new()
	_check(runtime.initialize_runtime(100_000, 2).get("ok", false), "lifecycle runtime initializes")
	var registry: RefCounted = FakeClimateRegistry.new(profile)
	_check(runtime.configure_environment_climate(registry, String(profile["id"])).get("ok", false), "lifecycle climate config succeeds")
	_check(runtime.configure_environment_runoff(registry, String(profile["id"])).get("ok", false), "lifecycle runoff config succeeds")
	_check(runtime.configure_world_scope_lifecycle("", 2, 16_000, 12_000, 2).get("ok", false), "lifecycle config accepts bounded due budget")
	_check(runtime.publish_world_region_scope(Vector2i.ZERO).get("ok", false), "lifecycle publishes environment scope")

	var deferred_frame: Dictionary = runtime.process_elapsed_usec(100_000)
	_check(deferred_frame.get("ok", false), "scheduler frame remains valid while runoff awaits surface cache")
	var environment_before: Dictionary = runtime.get_environment_scope("region:0,0")
	_check(int(environment_before["last_environment_tick"]) == 0, "deferred lifecycle does not advance environment tick")
	_check(
		int(deferred_frame.get("environment_capacity_admission_limit", -1)) <= 2,
		"runoff shares existing bounded scheduler admission"
	)
	_check(_publish_surface(runtime, 0, 1).get("ok", false), "surface cache becomes available after deferred frame")
	var catchup: Dictionary = runtime.process_elapsed_usec(0)
	_check(catchup.get("ok", false), "zero-elapsed lifecycle frame drains admitted hydrology backlog")
	var environment_after: Dictionary = runtime.get_environment_scope("region:0,0")
	_check(int(environment_after["last_environment_tick"]) == 1, "deferred due tick commits once derived terrain becomes available")
	var lifecycle: Dictionary = runtime.get_world_scope_lifecycle_metrics()
	_check(int(lifecycle.get("runoff_deferred_total", 0)) >= 1, "lifecycle exposes runoff deferral telemetry")


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
