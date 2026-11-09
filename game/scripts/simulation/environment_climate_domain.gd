extends RefCounted
class_name EnvironmentClimateDomain

## P5.0B deterministic climate forcing over P5.0A environment authority.
## Profiles are data-only mod content. This domain owns no SceneTree state and
## never advances the scheduler. It consumes one explicit scope/tick decision.

const HandlerScript := preload("res://scripts/modding/content_type_handler.gd")
const EnvironmentStoreScript := preload("res://scripts/simulation/environment_state_store.gd")

const PROFILE_TYPE := "environment_climate_profile"
const MAX_PROFILES := 256
const MAX_ABS_TEMPERATURE_MC := 1_000_000
const MAX_RATE_UL_PER_CELL_PER_TICK := 1_000_000_000_000
const MAX_ELAPSED_TICKS_PER_STEP := 10_000_000

const PROFILE_FIELDS := [
	"schema_version",
	"type",
	"id",
	"air_temperature_milli_c",
	"precipitation_ul_per_cell_per_tick",
	"infiltration_ul_per_cell_per_tick",
	"soil_capacity_ul_per_cell",
	"evaporation_ul_per_cell_per_tick",
]

var _bound_profiles: Dictionary = {}
var _profile_binds_total := 0
var _steps_total := 0
var _due_steps_total := 0
var _precipitation_ul_total := 0
var _precipitation_overflow_ul_total := 0
var _infiltration_ul_total := 0
var _evaporation_ul_total := 0


func create_content_handler() -> RefCounted:
	return HandlerScript.new(
		PROFILE_TYPE,
		50,
		Callable(self, "validate_profile"),
		"duplicate_environment_climate_profile",
		MAX_PROFILES,
		Callable(self, "normalize_profile")
	)


func validate_profile(record: Dictionary, mod_id: String, _context: Dictionary = {}) -> Dictionary:
	if not _has_exact_fields(record, PROFILE_FIELDS):
		return _failure("environment_climate_profile_fields_invalid")
	if not _integer_like(record["schema_version"]) or int(record["schema_version"]) != 1:
		return _failure("environment_climate_profile_schema_invalid")
	if typeof(record["type"]) != TYPE_STRING or String(record["type"]) != PROFILE_TYPE:
		return _failure("environment_climate_profile_type_invalid")
	if typeof(record["id"]) != TYPE_STRING or not _valid_namespaced_id(String(record["id"]), mod_id):
		return _failure("environment_climate_profile_id_invalid")
	if not _integer_like(record["air_temperature_milli_c"]):
		return _failure("environment_climate_temperature_invalid")
	if absi(int(record["air_temperature_milli_c"])) > MAX_ABS_TEMPERATURE_MC:
		return _failure("environment_climate_temperature_invalid")
	for field in [
		"precipitation_ul_per_cell_per_tick",
		"infiltration_ul_per_cell_per_tick",
		"soil_capacity_ul_per_cell",
		"evaporation_ul_per_cell_per_tick",
	]:
		if not _integer_like(record[field]):
			return _failure("environment_climate_rate_invalid")
		var value := int(record[field])
		if value < 0 or value > MAX_RATE_UL_PER_CELL_PER_TICK:
			return _failure("environment_climate_rate_invalid")
	if int(record["soil_capacity_ul_per_cell"]) > EnvironmentStoreScript.MAX_WATER_UL_PER_CELL:
		return _failure("environment_climate_soil_capacity_invalid")
	return {"ok": true, "reason": "ok"}


func normalize_profile(record: Dictionary, mod_id: String, context: Dictionary) -> Dictionary:
	var validation := validate_profile(record, mod_id, context)
	if not validation.get("ok", false):
		return validation
	var normalized := record.duplicate(true)
	for field in PROFILE_FIELDS:
		if field in ["type", "id"]:
			continue
		normalized[field] = int(normalized[field])
	return {"ok": true, "reason": "ok", "record": normalized}


func bind_registry_profile(registry: RefCounted, profile_id: String) -> Dictionary:
	if registry == null:
		return _failure("environment_climate_registry_unavailable")
	if _bound_profiles.has(profile_id):
		var current_pin: Dictionary = registry.pin_content_record(PROFILE_TYPE, profile_id)
		if not current_pin.get("ok", false):
			return current_pin
		if current_pin["fingerprint"] == _bound_profiles[profile_id]["fingerprint"]:
			return {"ok": true, "reason": "ok", "noop": true}
		return _failure("environment_climate_profile_pin_conflict")
	if _bound_profiles.size() >= MAX_PROFILES:
		return _failure("environment_climate_profile_binding_limit")
	var profile: Dictionary = registry.get_content_record(PROFILE_TYPE, profile_id)
	if profile.is_empty():
		return _failure("environment_climate_profile_missing")
	var pin: Dictionary = registry.pin_content_record(PROFILE_TYPE, profile_id)
	if not pin.get("ok", false):
		return pin
	var fingerprint: Dictionary = pin["fingerprint"]
	var verified: Dictionary = registry.validate_content_fingerprint(fingerprint)
	if not verified.get("ok", false):
		return verified
	var checked := _validate_binding(profile, fingerprint)
	if not checked.get("ok", false):
		return checked
	_bound_profiles[profile_id] = {
		"profile": profile.duplicate(true),
		"fingerprint": fingerprint.duplicate(true),
	}
	_profile_binds_total += 1
	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"profile_id": profile_id,
		"profile_sha256": String(fingerprint["content_sha256"]),
	}


func get_bound_profile_pin(profile_id: String) -> Dictionary:
	if not _bound_profiles.has(profile_id):
		return {}
	var binding: Dictionary = _bound_profiles[profile_id]
	return {
		"profile_id": profile_id,
		"profile_sha256": String(binding["fingerprint"]["content_sha256"]),
	}


func clear_profile_bindings() -> void:
	_bound_profiles.clear()


func process_bound_due_scope(
	environment_store: RefCounted,
	tier_state: RefCounted,
	scope_id: String,
	profile_id: String,
	logical_tick: int
) -> Dictionary:
	if not _bound_profiles.has(profile_id):
		return _failure("environment_climate_profile_not_bound")
	_steps_total += 1
	var due: Dictionary = tier_state.get_due_decision(scope_id, logical_tick)
	if not due.get("ok", false):
		return due
	if not bool(due.get("due", false)):
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"due": false,
			"scope_id": scope_id,
			"logical_tick": logical_tick,
		}
	var binding: Dictionary = _bound_profiles[profile_id]
	var result := _apply_due_step(
		environment_store,
		scope_id,
		binding["profile"],
		binding["fingerprint"],
		logical_tick
	)
	if result.get("ok", false) and not result.get("noop", false):
		_due_steps_total += 1
		_precipitation_ul_total += int(result.get("precipitation_ul", 0))
		_precipitation_overflow_ul_total += int(result.get("precipitation_overflow_ul", 0))
		_infiltration_ul_total += int(result.get("infiltration_ul", 0))
		_evaporation_ul_total += int(result.get("evaporation_ul", 0))
	return result


func get_metrics() -> Dictionary:
	return {
		"bound_profiles": _bound_profiles.size(),
		"profile_binds_total": _profile_binds_total,
		"steps_total": _steps_total,
		"due_steps_total": _due_steps_total,
		"precipitation_ul_total": _precipitation_ul_total,
		"precipitation_overflow_ul_total": _precipitation_overflow_ul_total,
		"infiltration_ul_total": _infiltration_ul_total,
		"evaporation_ul_total": _evaporation_ul_total,
	}


func _apply_due_step(
	environment_store: RefCounted,
	scope_id: String,
	profile: Dictionary,
	fingerprint: Dictionary,
	logical_tick: int
) -> Dictionary:
	if environment_store == null or not environment_store.is_initialized():
		return _failure("environment_climate_store_unavailable")
	var record: Dictionary = environment_store.get_scope(scope_id)
	if record.is_empty():
		return _failure("environment_climate_scope_missing")
	if (
		String(record.get("profile_id", "")) != String(profile["id"])
		or String(record.get("profile_sha256", ""))
			!= String(fingerprint["content_sha256"])
	):
		return _failure("environment_climate_profile_pin_conflict")
	var last_tick := int(record["last_environment_tick"])
	if logical_tick < last_tick:
		return _failure("environment_climate_tick_not_monotonic")
	if logical_tick == last_tick:
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"due": true,
			"scope_id": scope_id,
			"logical_tick": logical_tick,
			"air_temperature_milli_c": int(profile["air_temperature_milli_c"]),
			"precipitation_ul": 0,
			"precipitation_overflow_ul": 0,
			"infiltration_ul": 0,
			"evaporation_ul": 0,
		}
	var elapsed_ticks := logical_tick - last_tick
	if elapsed_ticks <= 0 or elapsed_ticks > MAX_ELAPSED_TICKS_PER_STEP:
		return _failure("environment_climate_elapsed_tick_bound")

	var surface: PackedInt64Array = record["surface_water_ul"].duplicate()
	var soil: PackedInt64Array = record["soil_water_ul"].duplicate()
	var kinds: PackedByteArray = record["reservoir_kind"].duplicate()
	var levels: PackedInt64Array = record["reservoir_level_mm"].duplicate()
	var precipitation_total := 0
	var precipitation_overflow_total := 0
	var infiltration_total := 0
	var evaporation_total := 0

	var precipitation_request := _saturating_product(
		int(profile["precipitation_ul_per_cell_per_tick"]), elapsed_ticks
	)
	var infiltration_request := _saturating_product(
		int(profile["infiltration_ul_per_cell_per_tick"]), elapsed_ticks
	)
	var evaporation_request := _saturating_product(
		int(profile["evaporation_ul_per_cell_per_tick"]), elapsed_ticks
	)
	var soil_capacity := int(profile["soil_capacity_ul_per_cell"])

	for index in range(surface.size()):
		if int(kinds[index]) != EnvironmentStoreScript.RESERVOIR_FINITE:
			continue

		var current_surface := int(surface[index])
		var current_soil := int(soil[index])

		var precipitation_capacity := (
			EnvironmentStoreScript.MAX_WATER_UL_PER_CELL - current_surface
		)
		var precipitation_applied := mini(precipitation_request, precipitation_capacity)
		current_surface += precipitation_applied
		precipitation_total += precipitation_applied
		precipitation_overflow_total += precipitation_request - precipitation_applied

		var soil_room := maxi(0, soil_capacity - current_soil)
		var infiltration := mini(infiltration_request, mini(current_surface, soil_room))
		current_surface -= infiltration
		current_soil += infiltration
		infiltration_total += infiltration

		var evaporation_remaining := evaporation_request
		var surface_evaporation := mini(current_surface, evaporation_remaining)
		current_surface -= surface_evaporation
		evaporation_remaining -= surface_evaporation
		var soil_evaporation := mini(current_soil, evaporation_remaining)
		current_soil -= soil_evaporation
		evaporation_total += surface_evaporation + soil_evaporation

		surface[index] = current_surface
		soil[index] = current_soil

	var update := {
		"scope_id": scope_id,
		"expected_state_revision": int(record["state_revision"]),
		"last_environment_tick": logical_tick,
		"surface_water_ul": surface,
		"soil_water_ul": soil,
		"reservoir_kind": kinds,
		"reservoir_level_mm": levels,
		"reservoir_inflow_ul_delta": 0,
		"reservoir_outflow_ul_delta": 0,
	}
	var commit: Dictionary = environment_store.commit_batch([update])
	if not commit.get("ok", false):
		return commit
	return {
		"ok": true,
		"reason": "ok",
		"noop": bool(commit.get("noop", false)),
		"due": true,
		"scope_id": scope_id,
		"logical_tick": logical_tick,
		"elapsed_ticks": elapsed_ticks,
		"air_temperature_milli_c": int(profile["air_temperature_milli_c"]),
		"precipitation_ul": precipitation_total,
		"precipitation_overflow_ul": precipitation_overflow_total,
		"infiltration_ul": infiltration_total,
		"evaporation_ul": evaporation_total,
		"state_revision": int(environment_store.get_scope(scope_id)["state_revision"]),
	}


func _validate_binding(profile: Dictionary, fingerprint: Dictionary) -> Dictionary:
	var separator := String(profile.get("id", "")).find(":")
	if separator <= 0:
		return _failure("environment_climate_profile_id_invalid")
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
		return _failure("environment_climate_profile_fingerprint_invalid")
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return _failure("environment_climate_profile_fingerprint_invalid")
	if context.update(JSON.stringify(profile, "", true, true).to_utf8_buffer()) != OK:
		return _failure("environment_climate_profile_fingerprint_invalid")
	if context.finish().hex_encode() != String(fingerprint["content_sha256"]):
		return _failure("environment_climate_profile_pin_conflict")
	return {"ok": true, "reason": "ok"}


func _saturating_product(value: int, multiplier: int) -> int:
	if value <= 0 or multiplier <= 0:
		return 0
	var maximum := EnvironmentStoreScript.MAX_WATER_UL_PER_CELL
	if multiplier >= int(maximum / value) if value > 0 else true:
		return maximum
	return mini(maximum, value * multiplier)


func _integer_like(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and floor(numeric) == numeric


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


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
