extends SceneTree

const Domain := preload("res://scripts/simulation/material_environment_domain.gd")
const TierState := preload("res://scripts/simulation/simulation_tier_state.gd")
const Registry := preload("res://scripts/modding/content_definition_registry.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_profile_and_state()
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
	invalid["ambient_temperature_milli_c"] = 1.0
	_check(not domain.validate_profile(invalid, "test.mod").get("ok", false), "float input rejected")
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
