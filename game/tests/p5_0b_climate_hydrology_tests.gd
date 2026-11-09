extends SceneTree

const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const ClimateDomainScript := preload("res://scripts/simulation/environment_climate_domain.gd")
const EnvironmentStoreScript := preload("res://scripts/simulation/environment_state_store.gd")
const TierStateScript := preload("res://scripts/simulation/simulation_tier_state.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")

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
		var record := get_content_record(content_type, namespaced_id)
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
	_test_real_registry_ingestion()
	_test_profile_contract_and_water_accounting()
	_test_tier_policy()
	_test_infinite_reservoir_exclusion()
	_test_lifecycle_integration()
	_test_snapshot_rebind()

	if failures == 0:
		print("P5_0B_CLIMATE_HYDROLOGY_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error(
			"P5_0B_CLIMATE_HYDROLOGY_FAIL: assertions=%d failures=%d"
			% [assertions, failures]
		)
		quit(1)


func _test_real_registry_ingestion() -> void:
	var profile := _profile("test.climate:registry", 123, 45, 10_000, 6)
	var domain: RefCounted = ClimateDomainScript.new()
	var registry: RefCounted = RegistryScript.new()
	_check(
		registry.register_engine_content_type_handler(
			domain.create_content_handler()
		).get("ok", false),
		"real content registry accepts engine-owned climate handler"
	)
	var discovery := {
		"ok": true,
		"packages": [{
			"manifest": {
				"id": "test.climate",
				"version": "1.0.0",
				"schema_version": 1,
				"requires_engine": "4.7.2",
				"dependencies": [],
				"content_roots": ["climate/"],
				"script_policy": "data_only",
			},
			"content_records": [profile],
		}],
	}
	var registered: Dictionary = registry.register_discovered(discovery)
	_check(registered.get("ok", false), "real registry ingests climate profile as data-only mod content")
	_check(
		registry.get_content_record(
			ClimateDomainScript.PROFILE_TYPE, String(profile["id"])
		) == profile,
		"real registry exposes normalized climate profile"
	)
	var pin: Dictionary = registry.pin_content_record(
		ClimateDomainScript.PROFILE_TYPE, String(profile["id"])
	)
	_check(
		pin.get("ok", false)
			and String(pin["fingerprint"]["content_sha256"]).length() == 64,
		"real registry produces canonical climate content fingerprint"
	)


func _profile(
	id: String = "test.climate:rain",
	precipitation: int = 10_000,
	infiltration: int = 4_000,
	soil_capacity: int = 100_000,
	evaporation: int = 1_000
) -> Dictionary:
	return {
		"schema_version": 1,
		"type": ClimateDomainScript.PROFILE_TYPE,
		"id": id,
		"air_temperature_milli_c": 21_500,
		"precipitation_ul_per_cell_per_tick": precipitation,
		"infiltration_ul_per_cell_per_tick": infiltration,
		"soil_capacity_ul_per_cell": soil_capacity,
		"evaporation_ul_per_cell_per_tick": evaporation,
	}


func _runtime_with_climate(
	profile: Dictionary,
	initial_tier: String = TierStateScript.TIER_ACTIVE
) -> Dictionary:
	var runtime: Node = RuntimeScript.new()
	var initialized: Dictionary = runtime.initialize_runtime(100_000, 4, 0, false, 4)
	_check(initialized.get("ok", false), "runtime initializes for climate fixture")
	var registry: RefCounted = FakeClimateRegistry.new(profile)
	var configured: Dictionary = runtime.configure_environment_climate(
		registry, String(profile["id"])
	)
	_check(configured.get("ok", false), "runtime binds climate profile through registry fingerprint")
	var scope_registration: Dictionary = runtime.register_simulation_scope(
		"region:0,0", initial_tier
	)
	_check(scope_registration.get("ok", false), "simulation scope registers")
	var environment_registration: Dictionary = runtime.register_environment_scope("region:0,0")
	_check(environment_registration.get("ok", false), "environment scope registers with climate pin")
	return {"runtime": runtime, "registry": registry}


func _test_profile_contract_and_water_accounting() -> void:
	var profile := _profile()
	var domain: RefCounted = ClimateDomainScript.new()
	_check(
		domain.validate_profile(profile, "test.climate").get("ok", false),
		"climate profile schema validates"
	)
	var invalid := profile.duplicate(true)
	invalid["precipitation_ul_per_cell_per_tick"] = -1
	_check(
		domain.validate_profile(invalid, "test.climate").get("reason", "")
			== "environment_climate_rate_invalid",
		"negative climate forcing is rejected"
	)

	var fixture := _runtime_with_climate(profile)
	var runtime: Node = fixture["runtime"]
	var before: Dictionary = runtime.get_environment_scope("region:0,0")
	_check(
		String(before["profile_id"]) == String(profile["id"])
			and String(before["profile_sha256"]).length() == 64,
		"environment authority persists climate profile id and sha pin"
	)

	var result: Dictionary = runtime.process_environment_climate_scope("region:0,0", 1)
	_check(result.get("ok", false) and not result.get("noop", false), "active climate due step commits")
	_check(int(result["precipitation_ul"]) == 480_000, "precipitation accounting is exact")
	_check(int(result["infiltration_ul"]) == 192_000, "infiltration accounting is exact")
	_check(int(result["evaporation_ul"]) == 48_000, "evaporation accounting is exact")
	var after: Dictionary = runtime.get_environment_scope("region:0,0")
	_check(_sum_i64(after["surface_water_ul"]) == 240_000, "surface water matches rain minus infiltration and evaporation")
	_check(_sum_i64(after["soil_water_ul"]) == 192_000, "soil water receives bounded infiltration")
	_check(
		_sum_i64(after["surface_water_ul"]) + _sum_i64(after["soil_water_ul"])
			== int(result["precipitation_ul"]) - int(result["evaporation_ul"]),
		"finite-water conservation closes for the climate step"
	)
	_check(int(after["last_environment_tick"]) == 1, "climate mutation advances environment logical tick")

	var duplicate: Dictionary = runtime.process_environment_climate_scope("region:0,0", 1)
	_check(duplicate.get("ok", false) and duplicate.get("noop", false), "same-tick climate replay is idempotent")
	_check(runtime.get_environment_scope("region:0,0") == after, "same-tick replay does not duplicate rain")
	runtime.free()


func _test_tier_policy() -> void:
	var profile := _profile("test.climate:tier", 1_000, 0, 100_000, 0)
	var dormant_fixture := _runtime_with_climate(profile, TierStateScript.TIER_DORMANT)
	var dormant: Node = dormant_fixture["runtime"]
	var dormant_before: Dictionary = dormant.get_environment_scope("region:0,0")
	var dormant_step: Dictionary = dormant.process_environment_climate_scope("region:0,0", 1)
	_check(dormant_step.get("ok", false) and dormant_step.get("noop", false), "dormant scope performs no climate work")
	_check(dormant.get_environment_scope("region:0,0") == dormant_before, "dormant tier preserves environment authority")
	dormant.free()

	var aggregate_fixture := _runtime_with_climate(profile, TierStateScript.TIER_AGGREGATE)
	var aggregate: Node = aggregate_fixture["runtime"]
	var due_count := 0
	var noop_count := 0
	for tick in range(1, 9):
		var step: Dictionary = aggregate.process_environment_climate_scope("region:0,0", tick)
		_check(step.get("ok", false), "aggregate climate decision succeeds")
		if step.get("noop", false):
			noop_count += 1
		else:
			due_count += 1
	_check(due_count > 0 and noop_count > 0, "aggregate tier runs reduced-frequency climate steps")
	var aggregate_state: Dictionary = aggregate.get_environment_scope("region:0,0")
	_check(
		int(aggregate_state["last_environment_tick"]) > 0
			and int(aggregate_state["last_environment_tick"]) <= 8,
		"aggregate climate records its latest committed due tick"
	)
	aggregate.free()


func _test_infinite_reservoir_exclusion() -> void:
	var profile := _profile("test.climate:reservoir", 50_000, 20_000, 100_000, 5_000)
	var fixture := _runtime_with_climate(profile)
	var runtime: Node = fixture["runtime"]
	var record: Dictionary = runtime.get_environment_scope("region:0,0")
	var kinds: PackedByteArray = record["reservoir_kind"].duplicate()
	var levels: PackedInt64Array = record["reservoir_level_mm"].duplicate()
	kinds[0] = EnvironmentStoreScript.RESERVOIR_RIVER
	levels[0] = 12_345
	var commit: Dictionary = runtime.commit_environment_batch([{
		"scope_id": "region:0,0",
		"expected_state_revision": int(record["state_revision"]),
		"last_environment_tick": 1,
		"surface_water_ul": record["surface_water_ul"].duplicate(),
		"soil_water_ul": record["soil_water_ul"].duplicate(),
		"reservoir_kind": kinds,
		"reservoir_level_mm": levels,
		"reservoir_inflow_ul_delta": 0,
		"reservoir_outflow_ul_delta": 0,
	}])
	_check(commit.get("ok", false), "river fixture commits")
	var climate: Dictionary = runtime.process_environment_climate_scope("region:0,0", 2)
	_check(climate.get("ok", false), "climate processes finite cells beside river")
	var after: Dictionary = runtime.get_environment_scope("region:0,0")
	_check(int(after["surface_water_ul"][0]) == 0 and int(after["soil_water_ul"][0]) == 0, "climate never stores finite rain in infinite reservoir cell")
	_check(int(after["reservoir_level_mm"][0]) == 12_345, "climate cannot alter river fixed level")
	runtime.free()


func _test_lifecycle_integration() -> void:
	var profile := _profile("test.climate:lifecycle", 2_000, 500, 100_000, 0)
	var runtime: Node = RuntimeScript.new()
	runtime.initialize_runtime(100_000, 4)
	var registry: RefCounted = FakeClimateRegistry.new(profile)
	_check(
		runtime.configure_environment_climate(registry, String(profile["id"])).get("ok", false),
		"lifecycle fixture configures climate"
	)
	_check(
		runtime.configure_world_scope_lifecycle("", 25, 16_000, 12_000).get("ok", false),
		"lifecycle configures without material profile"
	)
	runtime.update_world_scope_focus(Vector2i.ZERO)
	_check(runtime.publish_world_region_scope(Vector2i.ZERO).get("ok", false), "resident scope publishes")
	var frame: Dictionary = runtime.process_elapsed_usec(100_000)
	_check(frame.get("ok", false), "scheduler frame with climate succeeds")
	var lifecycle: Dictionary = frame.get("world_scope_lifecycle", {})
	_check(int(lifecycle.get("climate_steps", 0)) >= 1, "world lifecycle executes climate due work")
	var state: Dictionary = runtime.get_environment_scope("region:0,0")
	_check(_sum_i64(state["surface_water_ul"]) > 0 or _sum_i64(state["soil_water_ul"]) > 0, "lifecycle rain reaches authoritative environment state")
	runtime.free()


func _test_snapshot_rebind() -> void:
	var profile := _profile("test.climate:reload", 3_000, 1_000, 100_000, 100)
	var fixture := _runtime_with_climate(profile)
	var runtime: Node = fixture["runtime"]
	var registry: RefCounted = fixture["registry"]
	runtime.process_environment_climate_scope("region:0,0", 1)
	_check(
		runtime.validate_environment_climate_content(registry).get("ok", false),
		"save preflight validates persisted climate profile fingerprint"
	)
	var changed_same_id: Dictionary = profile.duplicate(true)
	changed_same_id["precipitation_ul_per_cell_per_tick"] = int(profile["precipitation_ul_per_cell_per_tick"]) + 1
	var changed_registry: RefCounted = FakeClimateRegistry.new(changed_same_id)
	var changed_validation: Dictionary = runtime.validate_environment_climate_content(
		changed_registry
	)
	_check(
		changed_validation.get("reason", "") == "environment_climate_persisted_profile_pin_conflict",
		"save preflight rejects same-id climate content changed behind persisted sha"
	)
	var snapshot: Dictionary = runtime.get_runtime_snapshot()

	var restored: Node = RuntimeScript.new()
	var restore: Dictionary = restored.restore_runtime_snapshot(snapshot)
	_check(restore.get("ok", false), "runtime snapshot with climate-pinned environment restores")
	_check(not restored.has_environment_climate(), "climate registry binding remains transient across restore")
	var restored_record: Dictionary = restored.get_environment_scope("region:0,0")
	_check(
		String(restored_record["profile_id"]) == String(profile["id"]),
		"authoritative climate profile pin survives restore"
	)
	_check(
		restored.configure_environment_climate(registry, String(profile["id"])).get("ok", false),
		"matching registry profile safely rebinds after restore"
	)
	var next: Dictionary = restored.process_environment_climate_scope("region:0,0", 2)
	_check(next.get("ok", false), "restored climate authority resumes deterministically")

	var conflicting_registry: RefCounted = FakeClimateRegistry.new(
		_profile("test.climate:other", 1, 0, 100_000, 0)
	)
	var conflict: Dictionary = restored.configure_environment_climate(
		conflicting_registry, "test.climate:other"
	)
	_check(
		conflict.get("reason", "") == "environment_climate_profile_pin_conflict",
		"restored authority rejects conflicting climate profile pin"
	)
	runtime.free()
	restored.free()


func _sum_i64(values: PackedInt64Array) -> int:
	var total := 0
	for value in values:
		total += int(value)
	return total


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)
