extends SceneTree

const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")
const DomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")
const StoreScript := preload("res://scripts/simulation/simulation_runtime_store.gd")

const WORLD_ID := "p4-0g-test-world"
const WORLD_SEED := 424242
const GENERATOR_VERSION := 7
const TERRAIN_GENERATION := 17

var assertions := 0
var failures := 0
var _root := ""
var _package_path := ""


func _initialize() -> void:
	_root = "user://p4_0g_%d" % Time.get_ticks_usec()
	_package_path = "user://mods/p4_0g_environment_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root))
	_write_material_package_fixture()
	_test_mod_material_discovery()
	_test_deterministic_replay_and_tier_invariants()
	_test_durable_runtime_roundtrip_and_content_drift()
	_remove_tree(ProjectSettings.globalize_path(_package_path))
	_remove_tree(ProjectSettings.globalize_path(_root))
	if failures == 0:
		print("P4_0G_REPLAY_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("P4_0G_REPLAY_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_mod_material_discovery() -> void:
	var domain: MaterialEnvironmentDomain = DomainScript.new()
	var registry: ContentDefinitionRegistry = RegistryScript.new()
	_check(
		registry.register_engine_content_type_handler(
			domain.create_content_handler()
		).get("ok", false),
		"runtime registry accepts material handler before package discovery"
	)
	var registered := registry.discover_and_register(["user://mods"])
	_check(registered.get("ok", false), "user data-only environment package registers through M4.0 discovery")
	var ids: Array[String] = registry.get_content_record_ids(
		DomainScript.PROFILE_TYPE
	)
	_check(
		ids == ["p4g.environment:temperate"],
		"fixture discovery exposes exactly one mod-first material/environment profile"
	)
	var profile: Dictionary = registry.get_content_record(
		DomainScript.PROFILE_TYPE, ids[0]
	)
	_check(
		int(profile.get("ambient_temperature_milli_c", -1)) == 18000
		and int(profile.get("relaxation_milli_per_due_step", -1)) == 125,
		"discovered profile preserves explicit fixed-point environment parameters"
	)


func _test_deterministic_replay_and_tier_invariants() -> void:
	var fixture := _fixture_registry()
	var registry: ContentDefinitionRegistry = fixture["registry"]
	var profile_id := String(fixture["profile_id"])

	var first := _run_scripted_replay(registry, profile_id)
	var second := _run_scripted_replay(registry, profile_id)
	_check(first.get("ok", false) and second.get("ok", false), "both deterministic replay runs complete")
	_check(first["snapshot"] == second["snapshot"], "identical command/event sequence yields byte-equivalent authoritative snapshots")
	_check(String(first["fingerprint"]) == String(second["fingerprint"]), "identical replay yields identical SHA-256 runtime fingerprint")
	_check(String(first["fingerprint"]).length() == 64, "runtime replay fingerprint is SHA-256")
	_check(int(first["paused_tick"]) == 2, "manual stepping while paused advances exactly two logical ticks")
	_check(int(first["catchup_peak_admitted"]) <= 2, "catch-up never exceeds configured two-tick scheduler frame budget")
	_check(int(first["final_tick"]) == 7, "five elapsed catch-up ticks drain deterministically after two manual steps")
	_check(bool(first["tier_roundtrip_ok"]), "active -> aggregate -> dormant -> active roundtrip preserves required state")
	_check(int(first["temperature_before_roundtrip"]) == int(first["temperature_after_roundtrip"]), "tier roundtrip conserves material temperature without admitted tick")
	_check(int(first["state_revision_before_roundtrip"]) == int(first["state_revision_after_roundtrip"]), "tier-only roundtrip does not mutate domain state revision")


func _test_durable_runtime_roundtrip_and_content_drift() -> void:
	var fixture := _fixture_registry()
	var registry: ContentDefinitionRegistry = fixture["registry"]
	var profile_id := String(fixture["profile_id"])
	var run := _run_scripted_replay(registry, profile_id)
	_check(run.get("ok", false), "persistence source replay completes")
	var snapshot: Dictionary = run["snapshot"]

	var store_dir := _root.path_join("simulation-store")
	var store: SimulationRuntimeStore = StoreScript.new(store_dir)
	var saved := store.save_snapshot(
		WORLD_ID,
		WORLD_SEED,
		GENERATOR_VERSION,
		TERRAIN_GENERATION,
		snapshot
	)
	_check(saved.get("ok", false), "quiescent authoritative runtime snapshot persists")
	_check(String(saved.get("payload_sha256", "")).length() == 64, "durable payload receives SHA-256")

	var wrong_generation := store.load_snapshot(
		WORLD_ID, WORLD_SEED, GENERATOR_VERSION, TERRAIN_GENERATION + 1
	)
	_check(
		wrong_generation.get("ok", false)
		and not wrong_generation.get("found", true)
		and wrong_generation.get("reason") == "simulation_generation_not_found",
		"terrain generation mismatch never silently selects another simulation snapshot"
	)

	var loaded := store.load_snapshot(
		WORLD_ID, WORLD_SEED, GENERATOR_VERSION, TERRAIN_GENERATION
	)
	_check(loaded.get("ok", false) and loaded.get("found", false), "matching terrain generation restores simulation sidecar")
	_check(loaded["snapshot"] == snapshot, "variant persistence preserves exact runtime types and values")

	var restored: SimulationRuntime = RuntimeScript.new()
	_check(restored.restore_runtime_snapshot(loaded["snapshot"]).get("ok", false), "persisted runtime snapshot restores into fresh authority")
	_check(restored.get_runtime_snapshot() == snapshot, "restore roundtrip is exact")
	_check(
		restored.get_runtime_snapshot_fingerprint() == String(run["fingerprint"]),
		"durable restore preserves deterministic runtime fingerprint"
	)
	var content_validation := restored.validate_material_state_content(registry)
	_check(
		content_validation.get("ok", false)
		and int(content_validation.get("validated_binding_count", 0)) == 1,
		"persisted material states revalidate against the current M4.0 profile pin"
	)
	restored.free()

	var drift_fixture := _synthetic_registry(19000)
	var drift_registry: ContentDefinitionRegistry = drift_fixture["registry"]
	var drifted: SimulationRuntime = RuntimeScript.new()
	_check(drifted.restore_runtime_snapshot(snapshot).get("ok", false), "snapshot structure remains valid before content validation")
	var drift_validation := drifted.validate_material_state_content(drift_registry)
	_check(
		not drift_validation.get("ok", false)
		and drift_validation.get("reason") == "material_persisted_profile_missing",
		"missing persisted profile identity fails closed"
	)
	drifted.free()

	var same_id_drift := _synthetic_registry(
		19000, "p4g.environment", "p4g.environment:temperate"
	)
	var pin_drift_runtime: SimulationRuntime = RuntimeScript.new()
	_check(pin_drift_runtime.restore_runtime_snapshot(snapshot).get("ok", false), "pin-drift fixture restores structurally")
	var pin_drift_validation := pin_drift_runtime.validate_material_state_content(
		same_id_drift["registry"]
	)
	_check(
		not pin_drift_validation.get("ok", false)
		and pin_drift_validation.get("reason") == "material_persisted_profile_pin_conflict",
		"same profile ID with changed content hash is rejected before simulation resumes"
	)
	pin_drift_runtime.free()


func _run_scripted_replay(
	registry: ContentDefinitionRegistry,
	profile_id: String
) -> Dictionary:
	var runtime: SimulationRuntime = RuntimeScript.new()
	var initialized := runtime.initialize_runtime(
		100000, # 10 Hz logical tick for exact test arithmetic.
		2,      # hard catch-up admission bound per scheduler frame.
		0,
		false,
		2,      # aggregate cadence.
		64,
		32000,
		40000,
		96000,
		112000,
		32,
		64
	)
	if not initialized.get("ok", false):
		runtime.free()
		return {"ok": false, "reason": initialized.get("reason", "init")}

	if not runtime.configure_material_environment(
		registry, profile_id, 2, 64
	).get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "material_config"}
	if not runtime.configure_world_scope_lifecycle(
		profile_id, 4, 16000, 12000, 16
	).get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "lifecycle_config"}
	runtime.update_world_scope_focus(Vector2i.ZERO)
	runtime.publish_world_region_scope(Vector2i(0, 0), 0)
	runtime.publish_world_region_scope(Vector2i(1, 0), 0)

	var early_preflight := runtime.get_persistence_preflight()
	_check(
		not early_preflight.get("ok", false),
		"persistence preflight rejects pending initialization/router work"
	)
	if not runtime.process_elapsed_usec(0).get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "initial_frame"}
	if not _drain_transient(runtime, 16):
		runtime.free()
		return {"ok": false, "reason": "initial_drain"}

	var paused := runtime.set_simulation_paused(true)
	if not paused.get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "pause"}
	if not runtime.request_simulation_steps(2).get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "manual_steps"}
	var manual := runtime.process_elapsed_usec(900000)
	if not manual.get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "manual_frame"}
	var paused_tick := int(runtime.get_scheduler_snapshot()["current_tick"])
	if not _drain_transient(runtime, 16):
		runtime.free()
		return {"ok": false, "reason": "manual_drain"}
	if not runtime.set_simulation_paused(false).get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "unpause"}

	var catchup := runtime.process_elapsed_usec(500000)
	if not catchup.get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "catchup"}
	var catchup_peak := int(catchup.get("admitted_ticks", 0))
	var catchup_frames := 0
	while (
		int(runtime.get_scheduler_snapshot().get("backlog_ticks", 0)) > 0
		or not runtime.get_persistence_preflight().get("ok", false)
	):
		var drained := runtime.process_elapsed_usec(0)
		if not drained.get("ok", false):
			runtime.free()
			return {"ok": false, "reason": "catchup_drain"}
		catchup_peak = maxi(catchup_peak, int(drained.get("admitted_ticks", 0)))
		catchup_frames += 1
		if catchup_frames > 32:
			runtime.free()
			return {"ok": false, "reason": "catchup_not_bounded"}

	var scope_before := runtime.get_simulation_scope("region:0,0")
	var material_before: Dictionary = scope_before["state"]["material_environment"]
	var temp_before := int(material_before["temperature_milli_c"])
	var state_revision_before := int(scope_before["state_revision"])

	runtime.update_world_scope_focus(Vector2i(6, 0))
	var aggregate_frame := runtime.process_elapsed_usec(0)
	if not aggregate_frame.get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "aggregate_route"}
	var aggregate_ok := (
		String(runtime.get_simulation_scope("region:0,0")["tier"]) == "aggregate"
		and String(runtime.get_simulation_scope("region:1,0")["tier"]) == "aggregate"
	)

	runtime.unload_world_region_scope(Vector2i(0, 0))
	var dormant_frame := runtime.process_elapsed_usec(0)
	if not dormant_frame.get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "dormant_route"}
	var dormant_ok := String(
		runtime.get_simulation_scope("region:0,0")["tier"]
	) == "dormant"

	runtime.update_world_scope_focus(Vector2i.ZERO)
	var revisit := runtime.publish_world_region_scope(Vector2i(0, 0), 999999)
	var active_frame := runtime.process_elapsed_usec(0)
	if not revisit.get("ok", false) or not active_frame.get("ok", false):
		runtime.free()
		return {"ok": false, "reason": "active_revisit"}
	var active_ok := String(
		runtime.get_simulation_scope("region:0,0")["tier"]
	) == "active"
	var scope_after := runtime.get_simulation_scope("region:0,0")
	var temp_after := int(
		scope_after["state"]["material_environment"]["temperature_milli_c"]
	)
	var state_revision_after := int(scope_after["state_revision"])

	if not _drain_transient(runtime, 16):
		runtime.free()
		return {"ok": false, "reason": "final_drain"}
	var preflight := runtime.get_persistence_preflight()
	if not preflight.get("ok", false):
		runtime.free()
		return {"ok": false, "reason": preflight.get("reason", "preflight")}

	var snapshot := runtime.get_runtime_snapshot()
	var fingerprint := runtime.get_runtime_snapshot_fingerprint()
	var final_tick := int(runtime.get_scheduler_snapshot()["current_tick"])
	runtime.free()
	return {
		"ok": true,
		"snapshot": snapshot,
		"fingerprint": fingerprint,
		"paused_tick": paused_tick,
		"catchup_peak_admitted": catchup_peak,
		"final_tick": final_tick,
		"temperature_before_roundtrip": temp_before,
		"temperature_after_roundtrip": temp_after,
		"state_revision_before_roundtrip": state_revision_before,
		"state_revision_after_roundtrip": state_revision_after,
		"tier_roundtrip_ok": aggregate_ok and dormant_ok and active_ok,
	}


func _drain_transient(runtime: SimulationRuntime, limit: int) -> bool:
	for _index in range(limit):
		var preflight := runtime.get_persistence_preflight()
		if (
			preflight.get("ok", false)
			and int(runtime.get_scheduler_snapshot().get("backlog_ticks", 0)) == 0
		):
			return true
		var frame := runtime.process_elapsed_usec(0)
		if not frame.get("ok", false):
			return false
	return false


func _fixture_registry() -> Dictionary:
	var domain: MaterialEnvironmentDomain = DomainScript.new()
	var registry: ContentDefinitionRegistry = RegistryScript.new()
	var handler := registry.register_engine_content_type_handler(
		domain.create_content_handler()
	)
	if not handler.get("ok", false):
		return {"registry": registry, "profile_id": "", "domain": domain}
	var registered := registry.discover_and_register(["user://mods"])
	if not registered.get("ok", false):
		return {"registry": registry, "profile_id": "", "domain": domain}
	var ids := registry.get_content_record_ids(DomainScript.PROFILE_TYPE)
	return {
		"registry": registry,
		"profile_id": String(ids[0]) if ids.size() == 1 else "",
		"domain": domain,
	}


func _write_material_package_fixture() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_package_path.path_join("environment"))
	)
	var manifest := {
		"id": "p4g.environment",
		"version": "1.0.0",
		"schema_version": 1,
		"requires_engine": "4.7.2",
		"dependencies": [],
		"content_roots": ["environment/"],
		"script_policy": "data_only",
	}
	var profile := {
		"schema_version": 1,
		"type": DomainScript.PROFILE_TYPE,
		"id": "p4g.environment:temperate",
		"ambient_temperature_milli_c": 18000,
		"relaxation_milli_per_due_step": 125,
	}
	_write_text(
		_package_path.path_join("manifest.json"),
		JSON.stringify(manifest, "  ", true, true)
	)
	_write_text(
		_package_path.path_join("environment/temperate.json"),
		JSON.stringify(profile, "  ", true, true)
	)


func _write_text(path: String, value: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		_check(false, "fixture file opens: " + path)
		return
	file.store_string(value)
	file.flush()
	file.close()


func _synthetic_registry(
	ambient: int,
	mod_id: String = "drift.test",
	profile_id: String = "drift.test:temperate"
) -> Dictionary:
	var domain: MaterialEnvironmentDomain = DomainScript.new()
	var registry: ContentDefinitionRegistry = RegistryScript.new()
	registry.register_engine_content_type_handler(domain.create_content_handler())
	var manifest := {
		"id": mod_id,
		"version": "1.0.0",
		"schema_version": 1,
		"requires_engine": "4.7.2",
		"dependencies": [],
		"content_roots": ["environment/"],
		"script_policy": "data_only",
	}
	var profile := {
		"schema_version": 1,
		"type": DomainScript.PROFILE_TYPE,
		"id": profile_id,
		"ambient_temperature_milli_c": ambient,
		"relaxation_milli_per_due_step": 125,
	}
	registry.register_discovered({
		"ok": true,
		"packages": [{
			"manifest": manifest,
			"content_records": [profile],
			"definitions": [],
			"population_rules": [],
			"terrain_interactions": [],
		}],
	})
	return {"registry": registry, "profile_id": profile_id, "domain": domain}


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
