extends RefCounted
class_name MaterialEnvironmentDomain

## P4.0D engine-owned deterministic material/environment state adapter.
## The profile originates from an M4.0 data-only content handler. No world scans,
## renderer access, arbitrary mod callbacks, or implicit scheduler advancement.

const HandlerScript := preload("res://scripts/modding/content_type_handler.gd")
const PROFILE_TYPE := "material_environment_profile"
const MAX_PROFILES := 256
const MAX_ABS_TEMPERATURE_MC := 1_000_000
const FIELDS := [
	"schema_version", "type", "id", "ambient_temperature_milli_c",
	"relaxation_milli_per_due_step",
]
const STATE_KEY := "material_environment"
const STATE_FIELDS := [
	"profile_id", "profile_sha256", "temperature_milli_c", "last_due_tick",
]


func create_content_handler() -> ContentTypeHandler:
	return HandlerScript.new(
		PROFILE_TYPE, 40, Callable(self, "validate_profile"),
		"duplicate_material_environment_profile", MAX_PROFILES
	)


func validate_profile(record: Dictionary, mod_id: String, _context: Dictionary = {}) -> Dictionary:
	if not _has_exact_fields(record, FIELDS):
		return {"ok": false, "reason": "material_profile_fields_invalid"}
	if typeof(record["schema_version"]) != TYPE_INT or int(record["schema_version"]) != 1:
		return {"ok": false, "reason": "material_profile_schema_invalid"}
	if typeof(record["type"]) != TYPE_STRING or record["type"] != PROFILE_TYPE:
		return {"ok": false, "reason": "material_profile_type_invalid"}
	if typeof(record["id"]) != TYPE_STRING or not _valid_namespaced_id(String(record["id"]), mod_id):
		return {"ok": false, "reason": "material_profile_id_invalid"}
	if typeof(record["ambient_temperature_milli_c"]) != TYPE_INT:
		return {"ok": false, "reason": "material_profile_temperature_invalid"}
	if absi(int(record["ambient_temperature_milli_c"])) > MAX_ABS_TEMPERATURE_MC:
		return {"ok": false, "reason": "material_profile_temperature_invalid"}
	if typeof(record["relaxation_milli_per_due_step"]) != TYPE_INT:
		return {"ok": false, "reason": "material_profile_relaxation_invalid"}
	var relaxation := int(record["relaxation_milli_per_due_step"])
	if relaxation < 0 or relaxation > 1000:
		return {"ok": false, "reason": "material_profile_relaxation_invalid"}
	return {"ok": true, "reason": "ok"}


func initialize_scope_state(
	tier_state: SimulationTierState,
	scope_id: String,
	profile: Dictionary,
	profile_fingerprint: Dictionary,
	initial_temperature_milli_c: int
) -> Dictionary:
	var validation := _validate_binding(profile, profile_fingerprint)
	if not validation.get("ok", false):
		return validation
	if absi(initial_temperature_milli_c) > MAX_ABS_TEMPERATURE_MC:
		return {"ok": false, "reason": "material_initial_temperature_invalid"}
	if tier_state == null or not tier_state.is_initialized():
		return {"ok": false, "reason": "material_tier_state_unavailable"}
	var record: Dictionary = tier_state.get_scope(scope_id)
	if record.is_empty():
		return {"ok": false, "reason": "simulation_scope_not_found"}
	var state: Dictionary = record["state"].duplicate(true)
	if state.has(STATE_KEY):
		return {"ok": false, "reason": "material_scope_already_initialized"}
	state[STATE_KEY] = {
		"profile_id": String(profile["id"]),
		"profile_sha256": String(profile_fingerprint["content_sha256"]),
		"temperature_milli_c": initial_temperature_milli_c,
		"last_due_tick": -1,
	}
	return tier_state.replace_scope_state(scope_id, state, int(record["state_revision"]))


func process_due_scope(
	tier_state: SimulationTierState,
	scope_id: String,
	profile: Dictionary,
	profile_fingerprint: Dictionary,
	logical_tick: int
) -> Dictionary:
	var validation := _validate_binding(profile, profile_fingerprint)
	if not validation.get("ok", false):
		return validation
	if tier_state == null or not tier_state.is_initialized():
		return {"ok": false, "reason": "material_tier_state_unavailable"}
	var record: Dictionary = tier_state.get_scope(scope_id)
	if record.is_empty():
		return {"ok": false, "reason": "simulation_scope_not_found"}
	var state: Dictionary = record["state"]
	if not state.has(STATE_KEY) or typeof(state[STATE_KEY]) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "material_scope_not_initialized"}
	var material: Dictionary = state[STATE_KEY]
	if not _has_exact_fields(material, STATE_FIELDS):
		return {"ok": false, "reason": "material_state_invalid"}
	if (
		typeof(material["profile_id"]) != TYPE_STRING
		or typeof(material["profile_sha256"]) != TYPE_STRING
		or typeof(material["temperature_milli_c"]) != TYPE_INT
		or typeof(material["last_due_tick"]) != TYPE_INT
	):
		return {"ok": false, "reason": "material_state_invalid"}
	if (
		String(material["profile_id"]) != String(profile["id"])
		or String(material["profile_sha256"]) != String(profile_fingerprint["content_sha256"])
	):
		return {"ok": false, "reason": "material_profile_pin_conflict"}
	var temperature := int(material["temperature_milli_c"])
	var last_due_tick := int(material["last_due_tick"])
	if absi(temperature) > MAX_ABS_TEMPERATURE_MC or last_due_tick < -1:
		return {"ok": false, "reason": "material_state_invalid"}
	if logical_tick <= last_due_tick:
		return {"ok": false, "reason": "material_tick_not_monotonic"}
	var due: Dictionary = tier_state.get_due_decision(scope_id, logical_tick)
	if not due.get("ok", false):
		return due
	if not bool(due["due"]):
		return {"ok": true, "reason": "ok", "noop": true, "due": false}
	var ambient := int(profile["ambient_temperature_milli_c"])
	var relaxation := int(profile["relaxation_milli_per_due_step"])
	var delta := ambient - temperature
	# Fixed-point, one bounded transition per admitted due decision.
	var amount := int(absi(delta) * relaxation / 1000)
	var updated := temperature + (mini(absi(delta), amount) * (-1 if delta < 0 else 1))
	var next_state: Dictionary = state.duplicate(true)
	var next_material: Dictionary = material.duplicate(true)
	next_material["temperature_milli_c"] = updated
	next_material["last_due_tick"] = logical_tick
	next_state[STATE_KEY] = next_material
	var commit: Dictionary = tier_state.replace_scope_state(
		scope_id, next_state, int(record["state_revision"])
	)
	if not commit.get("ok", false):
		return commit
	return {
		"ok": true, "reason": "ok", "noop": false, "due": true,
		"temperature_milli_c": updated,
		"state_revision": int(commit["record"]["state_revision"]),
	}


func _validate_binding(profile: Dictionary, fingerprint: Dictionary) -> Dictionary:
	var separator := String(profile.get("id", "")).find(":")
	if separator <= 0:
		return {"ok": false, "reason": "material_profile_id_invalid"}
	var mod_id := String(profile["id"]).substr(0, separator)
	var validation := validate_profile(profile, mod_id)
	if not validation.get("ok", false):
		return validation
	if (
		typeof(fingerprint.get("content_id")) != TYPE_STRING
		or String(fingerprint["content_id"]) != String(profile["id"])
		or typeof(fingerprint.get("content_type")) != TYPE_STRING
		or String(fingerprint["content_type"]) != PROFILE_TYPE
		or typeof(fingerprint.get("content_sha256")) != TYPE_STRING
		or String(fingerprint["content_sha256"]).length() != 64
	):
		return {"ok": false, "reason": "material_profile_fingerprint_invalid"}
	# The caller must obtain this fingerprint from the verified M4.0 registry.
	return {"ok": true, "reason": "ok"}


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field in fields:
		if not value.has(field):
			return false
	return true


func _valid_namespaced_id(id: String, mod_id: String) -> bool:
	if mod_id.is_empty() or not id.begins_with(mod_id + ":"):
		return false
	var local := id.substr(mod_id.length() + 1)
	if local.is_empty() or local.length() > 128:
		return false
	for index in range(local.length()):
		var code := local.unicode_at(index)
		if not (
			(code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
			or code == 95 or code == 45 or code == 46
		):
			return false
	return true
