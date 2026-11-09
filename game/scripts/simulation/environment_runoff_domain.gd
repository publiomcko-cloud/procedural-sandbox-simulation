extends RefCounted
class_name EnvironmentRunoffDomain

## P5.0D finite runoff orchestration.
## The domain composes P5.0B climate forcing and P5.0C local downhill data into
## one revision-gated authoritative environment commit per due logical tick.

const ClimateDomainScript := preload("res://scripts/simulation/environment_climate_domain.gd")
const RunoffJobScript := preload("res://scripts/simulation/environment_runoff_job.gd")
const EnvironmentStoreScript := preload("res://scripts/simulation/environment_state_store.gd")

var _bound_profiles: Dictionary = {}
var _profile_binds_total := 0
var _steps_total := 0
var _due_steps_total := 0
var _deferred_surface_cache_total := 0
var _stale_state_rejections_total := 0
var _stale_surface_rejections_total := 0
var _precipitation_ul_total := 0
var _precipitation_overflow_ul_total := 0
var _infiltration_ul_total := 0
var _evaporation_ul_total := 0
var _runoff_ul_total := 0
var _runoff_transfer_count_total := 0


func bind_registry_profile(registry: RefCounted, profile_id: String) -> Dictionary:
	if registry == null:
		return _failure("environment_runoff_registry_unavailable")
	if _bound_profiles.has(profile_id):
		var current_pin: Dictionary = registry.pin_content_record(
			ClimateDomainScript.PROFILE_TYPE, profile_id
		)
		if not current_pin.get("ok", false):
			return current_pin
		if current_pin["fingerprint"] == _bound_profiles[profile_id]["fingerprint"]:
			return {"ok": true, "reason": "ok", "noop": true}
		return _failure("environment_runoff_profile_pin_conflict")

	var profile: Dictionary = registry.get_content_record(
		ClimateDomainScript.PROFILE_TYPE, profile_id
	)
	if profile.is_empty():
		return _failure("environment_runoff_profile_missing")
	var pin: Dictionary = registry.pin_content_record(
		ClimateDomainScript.PROFILE_TYPE, profile_id
	)
	if not pin.get("ok", false):
		return pin
	var fingerprint: Dictionary = pin["fingerprint"]
	var verified: Dictionary = registry.validate_content_fingerprint(fingerprint)
	if not verified.get("ok", false):
		return verified

	var separator := profile_id.find(":")
	if separator <= 0:
		return _failure("environment_runoff_profile_id_invalid")
	var mod_id := profile_id.substr(0, separator)
	var climate_validator: RefCounted = ClimateDomainScript.new()
	var validation: Dictionary = climate_validator.validate_profile(profile, mod_id)
	if not validation.get("ok", false):
		return validation
	if (
		String(fingerprint.get("content_id", "")) != profile_id
		or String(fingerprint.get("content_type", ""))
			!= ClimateDomainScript.PROFILE_TYPE
		or String(fingerprint.get("content_sha256", "")).length() != 64
	):
		return _failure("environment_runoff_profile_fingerprint_invalid")

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
	surface_cache: RefCounted,
	scope_id: String,
	profile_id: String,
	logical_tick: int
) -> Dictionary:
	if not _bound_profiles.has(profile_id):
		return _failure("environment_runoff_profile_not_bound")
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
			"deferred": false,
			"scope_id": scope_id,
			"logical_tick": logical_tick,
		}

	var built: Dictionary = build_work_snapshot(
		environment_store,
		surface_cache,
		scope_id,
		profile_id,
		logical_tick
	)
	if not built.get("ok", false):
		return built
	if built.get("deferred", false) or built.get("noop", false):
		if built.get("deferred", false):
			_deferred_surface_cache_total += 1
		return built

	var job: RefCounted = RunoffJobScript.new(built["work_snapshot"])
	job.run()
	var solved: Dictionary = job.result
	if not solved.get("ok", false):
		return solved
	var committed: Dictionary = commit_solved_work(
		environment_store, surface_cache, solved
	)
	if not committed.get("ok", false):
		return committed
	if committed.get("deferred", false):
		return committed

	_due_steps_total += 1
	_precipitation_ul_total += int(solved.get("precipitation_ul", 0))
	_precipitation_overflow_ul_total += int(
		solved.get("precipitation_overflow_ul", 0)
	)
	_infiltration_ul_total += int(solved.get("infiltration_ul", 0))
	_evaporation_ul_total += int(solved.get("evaporation_ul", 0))
	_runoff_ul_total += int(solved.get("runoff_ul", 0))
	_runoff_transfer_count_total += int(solved.get("runoff_transfer_count", 0))

	var result := solved.duplicate(true)
	result.erase("update")
	result["noop"] = bool(committed.get("noop", false))
	result["due"] = true
	result["deferred"] = false
	result["state_revision"] = int(
		environment_store.get_scope(scope_id).get("state_revision", -1)
	)
	return result


func build_work_snapshot(
	environment_store: RefCounted,
	surface_cache: RefCounted,
	scope_id: String,
	profile_id: String,
	logical_tick: int
) -> Dictionary:
	if environment_store == null or not environment_store.is_initialized():
		return _failure("environment_runoff_store_unavailable")
	if surface_cache == null or not surface_cache.is_initialized():
		return _failure("environment_runoff_surface_cache_unavailable")
	if not _bound_profiles.has(profile_id):
		return _failure("environment_runoff_profile_not_bound")

	var record: Dictionary = environment_store.get_scope(scope_id)
	if record.is_empty():
		return _failure("environment_runoff_scope_missing")
	var binding: Dictionary = _bound_profiles[profile_id]
	var fingerprint: Dictionary = binding["fingerprint"]
	if (
		String(record.get("profile_id", "")) != profile_id
		or String(record.get("profile_sha256", ""))
			!= String(fingerprint["content_sha256"])
	):
		return _failure("environment_runoff_profile_pin_conflict")

	var last_tick := int(record["last_environment_tick"])
	if logical_tick < last_tick:
		return _failure("environment_runoff_tick_not_monotonic")
	if logical_tick == last_tick:
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"due": true,
			"deferred": false,
			"scope_id": scope_id,
			"logical_tick": logical_tick,
		}
	var elapsed_ticks := logical_tick - last_tick
	if elapsed_ticks <= 0 or elapsed_ticks > RunoffJobScript.MAX_ELAPSED_TICKS_PER_STEP:
		return _failure("environment_runoff_elapsed_tick_bound")

	var surface_record: Dictionary = surface_cache.get_scope(scope_id)
	if surface_record.is_empty():
		return {
			"ok": true,
			"reason": "environment_runoff_surface_cache_pending",
			"noop": true,
			"due": true,
			"deferred": true,
			"scope_id": scope_id,
			"logical_tick": logical_tick,
		}

	var surface: PackedInt64Array = record["surface_water_ul"]
	var soil: PackedInt64Array = record["soil_water_ul"]
	var kinds: PackedByteArray = record["reservoir_kind"]
	var levels: PackedInt64Array = record["reservoir_level_mm"]
	var valid: PackedByteArray = surface_record["surface_valid"]
	var downhill: PackedInt32Array = surface_record["downhill_neighbor"]
	var drops: PackedInt64Array = surface_record["downhill_drop_mm"]
	if (
		surface.size() != valid.size()
		or surface.size() != downhill.size()
		or surface.size() != drops.size()
	):
		return _failure("environment_runoff_surface_cache_shape_mismatch")

	var profile: Dictionary = binding["profile"]
	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"deferred": false,
		"work_snapshot": {
			"scope_id": scope_id,
			"logical_tick": logical_tick,
			"expected_state_revision": int(record["state_revision"]),
			"profile_id": profile_id,
			"profile_sha256": String(fingerprint["content_sha256"]),
			"elapsed_ticks": elapsed_ticks,
			"surface_water_ul": surface.duplicate(),
			"soil_water_ul": soil.duplicate(),
			"reservoir_kind": kinds.duplicate(),
			"reservoir_level_mm": levels.duplicate(),
			"surface_valid": valid.duplicate(),
			"downhill_neighbor": downhill.duplicate(),
			"downhill_drop_mm": drops.duplicate(),
			"precipitation_ul_per_cell_per_tick": int(
				profile["precipitation_ul_per_cell_per_tick"]
			),
			"infiltration_ul_per_cell_per_tick": int(
				profile["infiltration_ul_per_cell_per_tick"]
			),
			"soil_capacity_ul_per_cell": int(profile["soil_capacity_ul_per_cell"]),
			"evaporation_ul_per_cell_per_tick": int(
				profile["evaporation_ul_per_cell_per_tick"]
			),
			"surface_cache_token": _surface_token(surface_record),
		},
	}


func solve_work_snapshot(work_snapshot: Dictionary) -> Dictionary:
	var job: RefCounted = RunoffJobScript.new(work_snapshot)
	job.run()
	return job.result.duplicate(true)


func commit_solved_work(
	environment_store: RefCounted,
	surface_cache: RefCounted,
	solved: Dictionary
) -> Dictionary:
	if not solved.get("ok", false):
		return _failure("environment_runoff_solve_invalid")
	var scope_id := String(solved.get("scope_id", ""))
	var current: Dictionary = environment_store.get_scope(scope_id)
	if current.is_empty():
		return _failure("environment_runoff_scope_missing")
	if int(current["state_revision"]) != int(solved["expected_state_revision"]):
		_stale_state_rejections_total += 1
		return {
			"ok": true,
			"reason": "environment_runoff_state_stale",
			"noop": true,
			"deferred": true,
			"scope_id": scope_id,
		}
	var current_surface: Dictionary = surface_cache.get_scope(scope_id)
	if current_surface.is_empty():
		_stale_surface_rejections_total += 1
		return {
			"ok": true,
			"reason": "environment_runoff_surface_cache_stale",
			"noop": true,
			"deferred": true,
			"scope_id": scope_id,
		}
	if _surface_token(current_surface) != solved.get("surface_cache_token", {}):
		_stale_surface_rejections_total += 1
		return {
			"ok": true,
			"reason": "environment_runoff_surface_cache_stale",
			"noop": true,
			"deferred": true,
			"scope_id": scope_id,
		}
	var commit: Dictionary = environment_store.commit_batch([solved["update"]])
	if not commit.get("ok", false):
		return commit
	return {
		"ok": true,
		"reason": "ok",
		"noop": bool(commit.get("noop", false)),
		"deferred": false,
		"committed_scope_count": int(commit.get("committed_scope_count", 0)),
	}


func get_metrics() -> Dictionary:
	return {
		"bound_profiles": _bound_profiles.size(),
		"profile_binds_total": _profile_binds_total,
		"steps_total": _steps_total,
		"due_steps_total": _due_steps_total,
		"deferred_surface_cache_total": _deferred_surface_cache_total,
		"stale_state_rejections_total": _stale_state_rejections_total,
		"stale_surface_rejections_total": _stale_surface_rejections_total,
		"precipitation_ul_total": _precipitation_ul_total,
		"precipitation_overflow_ul_total": _precipitation_overflow_ul_total,
		"infiltration_ul_total": _infiltration_ul_total,
		"evaporation_ul_total": _evaporation_ul_total,
		"runoff_ul_total": _runoff_ul_total,
		"runoff_transfer_count_total": _runoff_transfer_count_total,
	}


func _surface_token(record: Dictionary) -> Dictionary:
	return {
		"scope_id": String(record.get("scope_id", "")),
		"region_key": record.get("region_key", Vector2i.ZERO),
		"world_seed": int(record.get("world_seed", 0)),
		"generator_version": int(record.get("generator_version", -1)),
		"terrain_revision": int(record.get("terrain_revision", -1)),
		"terrain_cache_scope_id": int(record.get("terrain_cache_scope_id", 0)),
		"terrain_effect_revision": int(record.get("terrain_effect_revision", -1)),
	}


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
