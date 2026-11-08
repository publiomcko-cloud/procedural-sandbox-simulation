extends SceneTree

const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const DomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_streaming_lifecycle_with_material()
	_test_tier_only_streaming_lifecycle()
	if failures == 0:
		print("P4_0F_STREAMING_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("P4_0F_STREAMING_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_streaming_lifecycle_with_material() -> void:
	var fixture := _build_registry()
	var registry: ContentDefinitionRegistry = fixture["registry"]
	var profile_id := String(fixture["profile_id"])
	var runtime: SimulationRuntime = RuntimeScript.new()
	_check(runtime.initialize_runtime(100_000, 4, 0, false, 2, 64).get("ok", false), "runtime initialized")
	_check(runtime.configure_material_environment(registry, profile_id, 1, 8).get("ok", false), "material bridge uses one commit per frame")
	_check(
		runtime.configure_world_scope_lifecycle(profile_id, 3, 10_000, 10_000, 3).get("ok", false),
		"world lifecycle configured with explicit resident and due bounds"
	)
	_check(runtime.update_world_scope_focus(Vector2i.ZERO).get("ok", false), "initial focus accepted")

	for x in range(3):
		var published := runtime.publish_world_region_scope(Vector2i(x, 0), 0)
		_check(published.get("ok", false), "region publication accepted %d" % x)
		_check(bool(published.get("registered", false)), "new region registers one authoritative scope")
	_check(runtime.get_world_scope_resident_ids() == ["region:0,0", "region:1,0", "region:2,0"], "stable deterministic region scope ids")
	_check(int(runtime.get_simulation_tier_metrics()["scope_count"]) == 3, "three P4.0B scopes registered without world scan")

	var frame := runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false), "first zero-time frame routes and initializes")
	_check(String(runtime.get_simulation_scope("region:0,0")["tier"]) == "active", "focus region routes active")
	_check(String(runtime.get_simulation_scope("region:1,0")["tier"]) == "active", "near region routes active")
	_check(String(runtime.get_simulation_scope("region:2,0")["tier"]) == "active", "bounded resident halo routes active")
	_check(runtime.get_simulation_scope("region:0,0")["state"].has("material_environment"), "first initialization committed")
	_check(not runtime.get_simulation_scope("region:1,0")["state"].has("material_environment"), "second initialization remains queued")

	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false), "second initialization frame succeeds")
	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false), "third initialization frame succeeds")
	for x in range(3):
		_check(runtime.get_simulation_scope("region:%d,0" % x)["state"].has("material_environment"), "all resident states initialized incrementally")
	_check(int(runtime.get_material_environment_metrics()["queue"]["pending_count"]) == 0, "initialization backlog drained")

	frame = runtime.process_elapsed_usec(100_000)
	_check(frame.get("ok", false) and int(frame.get("last_tick", -1)) == 1, "logical tick one admitted")
	_check(int(frame["world_scope_lifecycle"]["due_decisions"]) == 3, "one bounded due decision per active resident")
	_check(int(frame["world_scope_lifecycle"]["due_updates_queued"]) == 3, "three active updates queued deterministically")
	_check(int(runtime.get_material_environment_metrics()["queue"]["pending_count"]) == 2, "shared material budget commits only one update")
	_check(_temperature(runtime, "region:0,0") == 10_000, "FIFO first region advances")
	_check(_temperature(runtime, "region:1,0") == 0 and _temperature(runtime, "region:2,0") == 0, "remaining updates stay deferred")

	runtime.process_elapsed_usec(0)
	runtime.process_elapsed_usec(0)
	_check(_temperature(runtime, "region:1,0") == 10_000 and _temperature(runtime, "region:2,0") == 10_000, "queued due updates drain across later frames")
	_check(int(runtime.get_material_environment_metrics()["bindings"]["legacy_hash_validations_total"]) == 1, "streaming hot path never rehashes bound profile")

	var focus_result := runtime.update_world_scope_focus(Vector2i(8, 0))
	_check(focus_result.get("ok", false) and int(focus_result["observation_count"]) == 3, "focus movement touches only bounded resident set")
	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false), "focus reroute frame succeeds")
	for x in range(3):
		_check(String(runtime.get_simulation_scope("region:%d,0" % x)["tier"]) == "aggregate", "far resident transitions to aggregate")

	var init_count_before := int(runtime.get_world_scope_lifecycle_metrics()["material_initializations_queued_total"])
	var unloaded := runtime.unload_world_region_scope(Vector2i(1, 0))
	_check(unloaded.get("ok", false) and not unloaded.get("noop", true), "unload event accepted")
	_check(not runtime.get_world_scope_resident_ids().has("region:1,0"), "unloaded scope leaves derived resident set immediately")
	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false), "unload routing frame succeeds")
	_check(String(runtime.get_simulation_scope("region:1,0")["tier"]) == "dormant", "unloaded scope becomes dormant through P4.0C")
	_check(_temperature(runtime, "region:1,0") == 10_000, "unload preserves authoritative material state")

	var revisit := runtime.publish_world_region_scope(Vector2i(1, 0), 999_999)
	_check(revisit.get("ok", false) and revisit.get("revisit", false), "revisit reuses deterministic authoritative scope")
	_check(not revisit.get("registered", true), "revisit never double-registers scope")
	_check(not revisit.get("material_initialization_queued", true), "revisit does not reinitialize persisted material state")
	_check(int(runtime.get_world_scope_lifecycle_metrics()["material_initializations_queued_total"]) == init_count_before, "revisit creates no duplicate material work")
	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false), "revisit routing frame succeeds")
	_check(String(runtime.get_simulation_scope("region:1,0")["tier"]) == "aggregate", "revisited far region re-enters aggregate tier")
	_check(_temperature(runtime, "region:1,0") == 10_000, "revisit preserves pre-unload temperature")

	var rejected := runtime.publish_world_region_scope(Vector2i(3, 0), 0)
	_check(rejected.get("reason", "") == "world_scope_resident_limit_reached", "resident cap fails closed")
	_check(runtime.get_simulation_scope("region:3,0").is_empty(), "rejected resident is not registered")

	var republished := runtime.publish_world_region_scope(Vector2i(0, 0), 0)
	_check(republished.get("ok", false), "resident republish is accepted")
	_check(not republished.get("registered", true) and not republished.get("revisit", true), "resident republish is neither registration nor revisit")
	_check(int(runtime.get_world_scope_lifecycle_metrics()["registrations_total"]) == 3, "republish does not duplicate scope authority")

	var metrics := runtime.get_world_scope_lifecycle_metrics()
	_check(int(metrics["peak_resident_scopes"]) == 3, "resident working set peak remains explicit")
	_check(int(metrics["revisits_total"]) == 1, "revisit telemetry exact")
	_check(int(metrics["due_updates_deferred_total"]) == 0, "queue capacity never overflowed in bounded fixture")

	var snapshot := runtime.get_runtime_snapshot()
	_check(runtime.restore_runtime_snapshot(snapshot).get("ok", false), "runtime snapshot restore succeeds")
	_check(not runtime.get_world_scope_lifecycle_metrics()["initialized"], "restore discards derived resident lifecycle")
	_check(not runtime.get_material_environment_metrics()["enabled"], "restore discards transient material queue and bindings")
	_check(_temperature(runtime, "region:1,0") == 10_000, "restore retains authoritative material state")


func _test_tier_only_streaming_lifecycle() -> void:
	var runtime: SimulationRuntime = RuntimeScript.new()
	_check(runtime.initialize_runtime(100_000, 4, 0, false, 2, 16).get("ok", false), "tier-only runtime initialized")
	_check(runtime.configure_world_scope_lifecycle("", 2, 10_000, 10_000, 2).get("ok", false), "lifecycle can run without material content")
	_check(runtime.update_world_scope_focus(Vector2i.ZERO).get("ok", false), "tier-only focus set")
	_check(runtime.publish_world_region_scope(Vector2i.ZERO).get("ok", false), "tier-only region published")
	var frame := runtime.process_elapsed_usec(100_000)
	_check(frame.get("ok", false), "tier-only scheduler frame succeeds")
	_check(String(runtime.get_simulation_scope("region:0,0")["tier"]) == "active", "tier-only scope still routes automatically")
	_check(runtime.get_simulation_scope("region:0,0")["state"].is_empty(), "no engine-only material state invented without mod profile")
	_check(not runtime.get_material_environment_metrics()["enabled"], "material bridge remains disabled")
	_check(int(frame["world_scope_lifecycle"]["due_updates_queued"]) == 0, "tier-only lifecycle submits no material work")


func _build_registry() -> Dictionary:
	var profile_id := "stream.test:temperate"
	var record := {
		"schema_version": 1,
		"type": DomainScript.PROFILE_TYPE,
		"id": profile_id,
		"ambient_temperature_milli_c": 20_000,
		"relaxation_milli_per_due_step": 500,
	}
	var manifest := {
		"id": "stream.test",
		"version": "1.0.0",
		"schema_version": 1,
		"requires_engine": "4.7.2",
		"dependencies": [],
		"content_roots": ["environment/"],
		"script_policy": "data_only",
	}
	var domain: MaterialEnvironmentDomain = DomainScript.new()
	var registry: ContentDefinitionRegistry = RegistryScript.new()
	_check(registry.register_engine_content_type_handler(domain.create_content_handler()).get("ok", false), "fixture material handler registered")
	var discovered := {
		"ok": true,
		"packages": [{
			"manifest": manifest,
			"content_records": [record],
			"definitions": [],
			"population_rules": [],
			"terrain_interactions": [],
		}],
	}
	_check(registry.register_discovered(discovered).get("ok", false), "fixture material profile registered through M4.0")
	return {"registry": registry, "profile_id": profile_id, "domain": domain}


func _temperature(runtime: SimulationRuntime, scope_id: String) -> int:
	return int(
		runtime.get_simulation_scope(scope_id)["state"]["material_environment"]["temperature_milli_c"]
	)


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
