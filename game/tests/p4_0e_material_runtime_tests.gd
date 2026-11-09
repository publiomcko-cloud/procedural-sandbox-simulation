extends SceneTree

const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const DomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_runtime_bridge()
	print(
		"P4_0E_RUNTIME_PASS: assertions=%d failures=%d" % [assertions, failures]
		if failures == 0 else
		"P4_0E_RUNTIME_FAIL: assertions=%d failures=%d" % [assertions, failures]
	)
	quit(0 if failures == 0 else 1)


func _test_runtime_bridge() -> void:
	var profile_id := "bridge.test:stone"
	var record := {
		"schema_version": 1, "type": DomainScript.PROFILE_TYPE,
		"id": profile_id, "ambient_temperature_milli_c": 20000,
		"relaxation_milli_per_due_step": 500,
	}
	var manifest := {
		"id": "bridge.test", "version": "1.0.0", "schema_version": 1,
		"requires_engine": "4.7.2", "dependencies": [],
		"content_roots": ["profiles/"], "script_policy": "data_only",
	}
	var domain: MaterialEnvironmentDomain = DomainScript.new()
	var registry: ContentDefinitionRegistry = RegistryScript.new()
	_check(registry.register_engine_content_type_handler(domain.create_content_handler()).get("ok", false), "handler accepted")
	var discovered := {"ok": true, "packages": [{
		"manifest": manifest, "content_records": [record],
		"definitions": [], "population_rules": [], "terrain_interactions": [],
	}]}
	_check(registry.register_discovered(discovered).get("ok", false), "material profile committed")
	var runtime: SimulationRuntime = RuntimeScript.new()
	_check(runtime.initialize_runtime().get("ok", false), "existing runtime initialized")
	var baseline: Dictionary = runtime.get_runtime_snapshot()
	_check(int(baseline["schema_version"]) == 3, "P5 runtime snapshot schema preserves optional material bridge")
	_check(not runtime.get_material_environment_metrics()["enabled"], "material optional by default")
	_check(runtime.configure_material_environment(registry, profile_id, 1, 4).get("ok", false), "material configured with shared budget")
	_check(not runtime.configure_material_environment(registry, profile_id).get("ok", false), "reconfiguration requires restore")
	_check(runtime.enqueue_material_scope_registration("cell.a", "active").get("ok", false), "registration queued")
	_check(runtime.enqueue_material_scope_registration("cell.b", "active").get("ok", false), "second registration queued")
	_check(not runtime.tier_state.has_scope("cell.a"), "registration is not synchronous")
	var frame: Dictionary = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false) and int(frame["material_batch"]["processed_count"]) == 1, "one registration admitted first frame")
	_check(runtime.tier_state.has_scope("cell.a") and not runtime.tier_state.has_scope("cell.b"), "registration budget enforced")
	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false) and runtime.tier_state.has_scope("cell.b"), "remaining registration admitted second frame")
	_check(runtime.enqueue_material_scope_initialization("cell.a", profile_id, 0).get("ok", false), "first material initialization queued")
	_check(runtime.enqueue_material_scope_initialization("cell.b", profile_id, 0).get("ok", false), "second material initialization queued")
	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false) and int(frame["material_batch"]["processed_count"]) == 1, "one initialization per frame")
	_check(runtime.get_simulation_scope("cell.b")["state"].is_empty(), "second initialization deferred")
	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false), "second initialization processed")
	_check(runtime.get_simulation_scope("cell.b")["state"].has("material_environment"), "second material state committed")
	_check(runtime.enqueue_material_due_step("cell.a", profile_id, 1).get("reason", "") == "material_due_tick_not_admitted", "future tick rejected")
	frame = runtime.process_elapsed_usec(100000)
	_check(frame.get("ok", false) and int(frame["last_tick"]) == 1, "scheduler tick admitted")
	_check(runtime.enqueue_material_due_step("cell.a", profile_id, 1).get("ok", false), "explicit admitted tick enqueued")
	_check(runtime.enqueue_material_due_step("cell.b", profile_id, 1).get("ok", false), "second tick enqueued")
	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false) and int(frame["material_batch"]["processed_count"]) == 1, "first due step processed under budget")
	_check(int(runtime.get_simulation_scope("cell.a")["state"]["material_environment"]["temperature_milli_c"]) == 10000, "first temperature transitioned deterministically")
	_check(int(runtime.get_simulation_scope("cell.b")["state"]["material_environment"]["temperature_milli_c"]) == 0, "second temperature still deferred")
	frame = runtime.process_elapsed_usec(0)
	_check(frame.get("ok", false), "second due step processed")
	_check(int(runtime.get_simulation_scope("cell.b")["state"]["material_environment"]["temperature_milli_c"]) == 10000, "second temperature transitioned")
	_check(int(runtime.get_material_environment_metrics()["queue"]["pending_count"]) == 0, "transient queue drained")
	var snapshot: Dictionary = runtime.get_runtime_snapshot()
	_check(int(snapshot["schema_version"]) == 3, "material state composes with P5 runtime snapshot schema")
	_check(runtime.enqueue_material_due_step("cell.a", profile_id, 1).get("ok", false), "pending stale work can be queued before restore")
	_check(runtime.restore_runtime_snapshot(snapshot).get("ok", false), "runtime snapshot restored")
	_check(not runtime.get_material_environment_metrics()["enabled"], "restore invalidates pending work and cached bindings")
	_check(runtime.enqueue_material_due_step("cell.a", profile_id, 1).get("reason", "") == "material_bridge_not_configured", "unbound post-restore mutation rejected")
	_check(runtime.get_runtime_snapshot() == snapshot, "authoritative snapshot roundtrips exactly")
	_check(runtime.configure_material_environment(registry, profile_id, 1, 4).get("ok", false), "validated registry may be rebound after restore")
	_check(int(runtime.get_material_environment_metrics()["bindings"]["legacy_hash_validations_total"]) == 1, "fresh bind uses one full hash")
	_check(runtime.enqueue_material_due_step("cell.a", profile_id, 2).get("reason", "") == "material_due_tick_not_admitted", "restored scheduler tick checked")


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
