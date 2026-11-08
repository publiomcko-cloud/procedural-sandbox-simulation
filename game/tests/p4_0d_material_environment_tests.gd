extends SceneTree

const Domain := preload("res://scripts/simulation/material_environment_domain.gd")
const TierState := preload("res://scripts/simulation/simulation_tier_state.gd")
const Registry := preload("res://scripts/modding/content_definition_registry.gd")
const Loader := preload("res://scripts/modding/declarative_mod_loader.gd")
const WorkQueue := preload("res://scripts/simulation/material_environment_work_queue.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_profile_and_state()
	_test_mod_first_discovery_and_pin()
	if failures == 0:
		print("P4_0D_MATERIAL_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("P4_0D_MATERIAL_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_profile_and_state() -> void:
	var domain: MaterialEnvironmentDomain = Domain.new()
	var registry: ContentDefinitionRegistry = Registry.new()
	_check(
		registry.register_engine_content_type_handler(domain.create_content_handler()).get("ok", false),
		"engine registers material handler through M4.0 generic handler API"
	)
	var profile := {
		"schema_version": 1,
		"type": Domain.PROFILE_TYPE,
		"id": "test.mod:stone",
		"ambient_temperature_milli_c": 20000,
		"relaxation_milli_per_due_step": 500,
	}
	_check(domain.validate_profile(profile, "test.mod").get("ok", false), "valid declarative profile")
	var invalid: Dictionary = profile.duplicate(true)
	invalid["script"] = "execute"
	_check(
		domain.validate_profile(invalid, "test.mod").get("reason", "") == "material_profile_fields_invalid",
		"executable/unknown fields fail closed"
	)
	invalid = profile.duplicate(true)
	invalid["relaxation_milli_per_due_step"] = 1001
	_check(not domain.validate_profile(invalid, "test.mod").get("ok", false), "invalid coefficient rejected")
	invalid = profile.duplicate(true)
	invalid["ambient_temperature_milli_c"] = 1.5
	_check(not domain.validate_profile(invalid, "test.mod").get("ok", false), "fractional temperature input rejected")
	var fingerprint := _pin(profile)
	var tiers: SimulationTierState = TierState.new()
	_check(tiers.initialize(2, 3).get("ok", false), "tier authority initialized")
	_check(tiers.register_scope("cell.a", "active", {"other_domain": 7}).get("ok", false), "active scope created")
	_check(tiers.register_scope("cell.b", "dormant").get("ok", false), "dormant scope created")
	_check(domain.initialize_scope_state(tiers, "cell.a", profile, fingerprint, 0).get("ok", false), "bound state initialized")
	_check(domain.initialize_scope_state(tiers, "cell.b", profile, fingerprint, 0).get("ok", false), "dormant state initialized")
	_check(not domain.initialize_scope_state(tiers, "cell.a", profile, fingerprint, 0).get("ok", false), "double initialization rejected")
	var first := domain.process_due_scope(tiers, "cell.a", profile, fingerprint, 1)
	_check(first.get("ok", false) and int(first.get("temperature_milli_c", -1)) == 10000, "active due uses fixed-point half-step")
	_check(tiers.get_scope("cell.a")["state"]["other_domain"] == 7, "unrelated state preserved")
	_check(int(tiers.get_scope("cell.a")["tier_revision"]) == 0, "material update does not change tier revision")
	_check(domain.process_due_scope(tiers, "cell.a", profile, fingerprint, 1).get("reason", "") == "material_tick_not_monotonic", "same tick cannot apply twice")
	_check(domain.process_due_scope(tiers, "cell.b", profile, fingerprint, 2).get("noop", false), "dormant cannot advance")
	_check(int(tiers.get_scope("cell.b")["state"]["material_environment"]["temperature_milli_c"]) == 0, "dormant unchanged")
	var snapshot: Dictionary = tiers.get_authoritative_snapshot()
	var restored: SimulationTierState = TierState.new()
	_check(restored.restore_snapshot(snapshot).get("ok", false), "state snapshot restores")
	_check(restored.get_authoritative_snapshot() == snapshot, "authoritative roundtrip exact")
	var second := domain.process_due_scope(restored, "cell.a", profile, fingerprint, 2)
	_check(second.get("ok", false) and int(second.get("temperature_milli_c", -1)) == 15000, "restored deterministic progression")
	var tampered := fingerprint.duplicate(true)
	tampered["content_sha256"] = "bad"
	_check(not domain.process_due_scope(restored, "cell.a", profile, tampered, 3).get("ok", false), "malformed pin rejected")
	_check(int(restored.get_scope("cell.a")["state_revision"]) == 3, "failed bind cannot mutate authoritative state")



func _test_mod_first_discovery_and_pin() -> void:
	var root := "user://mods/p4_0d_test_%d" % Time.get_ticks_usec()
	var package_path := root.path_join("material_package")
	var profile_path := package_path.path_join("profiles")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_path))
	var manifest := {
		"id": "sample.p4",
		"version": "1.0.0",
		"schema_version": 1,
		"requires_engine": "4.7.2",
		"dependencies": [],
		"content_roots": ["profiles/"],
		"script_policy": "data_only",
	}
	var profile := {
		"schema_version": 1,
		"type": Domain.PROFILE_TYPE,
		"id": "sample.p4:granite",
		"ambient_temperature_milli_c": 15000,
		"relaxation_milli_per_due_step": 250,
	}
	var manifest_path := package_path.path_join("manifest.json")
	var record_path := profile_path.path_join("granite.json")
	_write_json(manifest_path, manifest)
	_write_json(record_path, profile)
	var discovered: Dictionary = Loader.discover_and_validate([root])
	_check(discovered.get("ok", false), "material profile loads through unmodified M4.0 discovery")
	var domain: MaterialEnvironmentDomain = Domain.new()
	var registry: ContentDefinitionRegistry = Registry.new()
	_check(registry.register_engine_content_type_handler(domain.create_content_handler()).get("ok", false), "material handler registers before package commit")
	if discovered.get("ok", false):
		var registered: Dictionary = registry.register_discovered(discovered)
		_check(registered.get("ok", false), "data-only material record registers with generic registry: %s" % String(registered.get("reason", "missing_reason")))
		if registered.get("ok", false):
			var record: Dictionary = registry.get_content_record(Domain.PROFILE_TYPE, profile["id"])
			var pin_result: Dictionary = registry.pin_content_record(Domain.PROFILE_TYPE, profile["id"])
			_check(record == profile, "registered material record roundtrips exactly")
			_check(pin_result.get("ok", false), "M4.0 provides material profile fingerprint")
			if pin_result.get("ok", false):
				var pin: Dictionary = pin_result["fingerprint"]
				_check(registry.validate_content_fingerprint(pin).get("ok", false), "profile pin validates in M4.0")
				var tiers: SimulationTierState = TierState.new()
				tiers.initialize()
				tiers.register_scope("material.area", "active")
				_check(domain.initialize_scope_state(tiers, "material.area", record, pin, 0).get("ok", false), "M4.0-pin-backed material scope initializes")
				_test_bound_queue(domain, registry, record, pin)
				var drift: Dictionary = record.duplicate(true)
				drift["ambient_temperature_milli_c"] = 16000
				_check(domain.process_due_scope(tiers, "material.area", drift, pin, 1).get("reason", "") == "material_profile_pin_conflict", "same-version content drift is rejected before state mutation")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(record_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(package_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


func _test_bound_queue(
	domain: MaterialEnvironmentDomain, registry: ContentDefinitionRegistry,
	profile: Dictionary, pin: Dictionary
) -> void:
	var profile_id := String(profile["id"])
	_check(domain.bind_registry_profile(registry, profile_id).get("ok", false), "cold profile bind validates M4.0")
	_check(domain.bind_registry_profile(registry, profile_id).get("noop", false), "warm bind is idempotent")
	var hash_count := int(domain.get_binding_metrics()["legacy_hash_validations_total"])
	_check(hash_count == 1, "cold binding performs one SHA-256 validation")
	var tiers: SimulationTierState = TierState.new()
	tiers.initialize(2, 64)
	for i in range(20):
		var id := "dense.%02d" % i
		tiers.register_scope(id, "active")
		_check(domain.initialize_bound_scope_state(tiers, id, profile_id, 0).get("ok", false), "bound state init " + id)
	var queue: MaterialEnvironmentWorkQueue = WorkQueue.new()
	_check(queue.initialize(domain, 4, 20).get("ok", false), "bounded ring initialized")
	_check(queue.process_pending(tiers, 5).get("reason", "") == "material_queue_budget_invalid", "cannot exceed per-call budget")
	for i in range(20):
		_check(queue.enqueue(tiers, "dense.%02d" % i, profile_id, 1).get("ok", false), "enqueue ordered dense scope")
	_check(queue.enqueue(tiers, "dense.00", profile_id, 1).get("noop", false), "same scope/tick deduplicated")
	_check(queue.enqueue(tiers, "dense.00", profile_id, 2).get("reason", "") == "material_queue_capacity_reached", "hard capacity rejects without evicting")
	var first: Dictionary = queue.process_pending(tiers)
	_check(first.get("ok", false) and int(first["processed_count"]) == 4 and int(first["pending_count"]) == 16, "first frame admits exactly four")
	_check(String(first["processed"][0]["scope_id"]) == "dense.00", "FIFO receipts preserve admission order")
	for _batch in range(4):
		_check(queue.process_pending(tiers).get("ok", false), "remaining batch succeeds")
	_check(int(queue.get_metrics()["pending_count"]) == 0, "backlog drains without global scans")
	_check(int(queue.get_metrics()["processed_total"]) == 20, "exact bounded decision count")
	for i in range(20):
		var data: Dictionary = tiers.get_scope("dense.%02d" % i)["state"]["material_environment"]
		_check(int(data["temperature_milli_c"]) == 3750 and int(data["last_due_tick"]) == 1, "each scope advanced exactly once")
	_check(int(domain.get_binding_metrics()["legacy_hash_validations_total"]) == hash_count, "hot-path batches never hash profiles")
	_check(int(domain.get_binding_metrics()["bound_update_calls_total"]) == 20, "bound update metrics count admitted work")
	var snapshot: Dictionary = tiers.get_authoritative_snapshot()
	var restored: SimulationTierState = TierState.new()
	_check(restored.restore_snapshot(snapshot).get("ok", false), "dense state restore succeeds")
	var next: MaterialEnvironmentWorkQueue = WorkQueue.new()
	next.initialize(domain, 4, 8)
	_check(next.enqueue(restored, "dense.00", profile_id, 2).get("ok", false), "restored scope accepts next tick")
	_check(next.process_pending(restored).get("ok", false), "restored scope resumes safely")
	_check(int(restored.get_scope("dense.00")["state"]["material_environment"]["temperature_milli_c"]) == 6562, "warm deterministic integer progression after restore")
	_check(int(domain.get_binding_metrics()["legacy_hash_validations_total"]) == hash_count, "restore path still avoids per-tick hashing")


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()

func _pin(profile: Dictionary) -> Dictionary:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(profile, "", true, true).to_utf8_buffer())
	return {
		"content_id": String(profile["id"]),
		"content_type": Domain.PROFILE_TYPE,
		"content_sha256": context.finish().hex_encode(),
	}


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
