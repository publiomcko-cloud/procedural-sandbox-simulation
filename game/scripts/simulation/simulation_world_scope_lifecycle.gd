extends RefCounted
class_name SimulationWorldScopeLifecycle

## P4.0F explicit streamed-region -> simulation-scope lifecycle.
##
## The caller emits publication/unload/focus events. This class never scans the
## SceneTree, terrain registry, world history or unloaded simulation scopes.
## Its only iterable working set is the explicitly bounded resident region set.

const DomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const TierStateScript := preload("res://scripts/simulation/simulation_tier_state.gd")
const TierRouterScript := preload("res://scripts/simulation/simulation_tier_router.gd")

const DEFAULT_MAX_RESIDENT_SCOPES := 25
const MAX_RESIDENT_SCOPES_HARD := 4096
const DEFAULT_REGION_SIZE_X_MM := 16_000
const DEFAULT_REGION_SIZE_Z_MM := 12_000
const MAX_REGION_SIZE_MM := 1_000_000_000
const DEFAULT_DUE_DECISION_BUDGET := 128
const MAX_DUE_DECISION_BUDGET_HARD := 4096
const SCOPE_PREFIX := "region:"

var _initialized := false
var _profile_id := ""
var _max_resident_scopes := DEFAULT_MAX_RESIDENT_SCOPES
var _region_size_x_mm := DEFAULT_REGION_SIZE_X_MM
var _region_size_z_mm := DEFAULT_REGION_SIZE_Z_MM
var _due_decision_budget := DEFAULT_DUE_DECISION_BUDGET
var _focus_region := Vector2i.ZERO
var _has_focus := false
var _resident: Dictionary = {}

var _publication_events_total := 0
var _unload_events_total := 0
var _focus_events_total := 0
var _registrations_total := 0
var _revisits_total := 0
var _material_initializations_queued_total := 0
var _environment_registrations_total := 0
var _route_observations_total := 0
var _route_batches_total := 0
var _due_decisions_total := 0
var _due_updates_queued_total := 0
var _due_updates_deferred_total := 0
var _climate_steps_total := 0
var _climate_noops_total := 0
var _runoff_steps_total := 0
var _runoff_noops_total := 0
var _runoff_deferred_total := 0
var _peak_resident_scopes := 0
var _last_frame_index := -1


func initialize(
	profile_id: String = "",
	max_resident_scopes: int = DEFAULT_MAX_RESIDENT_SCOPES,
	region_size_x_mm: int = DEFAULT_REGION_SIZE_X_MM,
	region_size_z_mm: int = DEFAULT_REGION_SIZE_Z_MM,
	due_decision_budget: int = DEFAULT_DUE_DECISION_BUDGET
) -> Dictionary:
	if _initialized:
		return {"ok": false, "reason": "world_scope_lifecycle_already_initialized"}
	if max_resident_scopes < 1 or max_resident_scopes > MAX_RESIDENT_SCOPES_HARD:
		return {"ok": false, "reason": "world_scope_resident_limit_invalid"}
	if region_size_x_mm < 1 or region_size_x_mm > MAX_REGION_SIZE_MM:
		return {"ok": false, "reason": "world_scope_region_size_invalid"}
	if region_size_z_mm < 1 or region_size_z_mm > MAX_REGION_SIZE_MM:
		return {"ok": false, "reason": "world_scope_region_size_invalid"}
	if (
		due_decision_budget < max_resident_scopes
		or due_decision_budget > MAX_DUE_DECISION_BUDGET_HARD
	):
		# One sweep can always examine every bounded resident scope; smaller
		# budgets would deterministically starve later stable IDs.
		return {"ok": false, "reason": "world_scope_due_budget_invalid"}
	_profile_id = profile_id
	_max_resident_scopes = max_resident_scopes
	_region_size_x_mm = region_size_x_mm
	_region_size_z_mm = region_size_z_mm
	_due_decision_budget = due_decision_budget
	_resident.clear()
	_reset_metrics()
	_initialized = true
	return {"ok": true, "reason": "ok", "config": get_config()}


func is_initialized() -> bool:
	return _initialized


func has_material_profile() -> bool:
	return not _profile_id.is_empty()


func get_config() -> Dictionary:
	return {
		"profile_id": _profile_id,
		"max_resident_scopes": _max_resident_scopes,
		"region_size_x_mm": _region_size_x_mm,
		"region_size_z_mm": _region_size_z_mm,
		"due_decision_budget": _due_decision_budget,
	}


func scope_id_for_region(region_key: Vector2i) -> String:
	return "%s%d,%d" % [SCOPE_PREFIX, region_key.x, region_key.y]


func notify_region_published(
	runtime: Object,
	region_key: Vector2i,
	initial_temperature_milli_c: int = 0
) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "world_scope_lifecycle_not_initialized"}
	if runtime == null:
		return {"ok": false, "reason": "simulation_runtime_unavailable"}
	_publication_events_total += 1
	var scope_id := scope_id_for_region(region_key)
	var already_resident := _resident.has(scope_id)
	if not already_resident and _resident.size() >= _max_resident_scopes:
		return {
			"ok": false,
			"reason": "world_scope_resident_limit_reached",
			"scope_id": scope_id,
		}

	var record: Dictionary = runtime.get_simulation_scope(scope_id)
	var registered_now := false
	if record.is_empty():
		var registration: Dictionary = runtime.register_simulation_scope(
			scope_id, TierStateScript.TIER_DORMANT
		)
		if not registration.get("ok", false):
			return {
				"ok": false,
				"reason": "world_scope_registration_failed",
				"detail": String(registration.get("reason", "")),
				"scope_id": scope_id,
			}
		_registrations_total += 1
		registered_now = true
		record = registration.get("record", {})
	elif not already_resident:
		_revisits_total += 1

	if not already_resident:
		var next_tick := int(runtime.get_scheduler_snapshot().get("current_tick", 0)) + 1
		_resident[scope_id] = {
			"scope_id": scope_id,
			"region_key": region_key,
			"next_tick": next_tick,
		}
	else:
		var resident_record: Dictionary = _resident[scope_id]
		resident_record["region_key"] = region_key
		_resident[scope_id] = resident_record
	_peak_resident_scopes = maxi(_peak_resident_scopes, _resident.size())

	var environment_registration: Dictionary = runtime.register_environment_scope(scope_id)
	if not environment_registration.get("ok", false):
		return {
			"ok": false,
			"reason": "world_scope_environment_registration_failed",
			"detail": String(environment_registration.get("reason", "")),
			"scope_id": scope_id,
		}
	if not environment_registration.get("noop", false):
		_environment_registrations_total += 1

	var observation := _submit_observation(runtime, scope_id, region_key)
	if not observation.get("ok", false):
		if registered_now:
			# Registration is authoritative and intentionally not rolled back.
			# The caller can retry the explicit publication observation.
			pass
		return observation

	var material_queued := false
	if not _profile_id.is_empty():
		record = runtime.get_simulation_scope(scope_id)
		var state: Dictionary = record.get("state", {})
		if not state.has(DomainScript.STATE_KEY):
			var material_init: Dictionary = runtime.enqueue_material_scope_initialization(
				scope_id, _profile_id, initial_temperature_milli_c
			)
			if not material_init.get("ok", false):
				return {
					"ok": false,
					"reason": "world_scope_material_initialization_failed",
					"detail": String(material_init.get("reason", "")),
					"scope_id": scope_id,
				}
			if not material_init.get("noop", false):
				_material_initializations_queued_total += 1
				material_queued = true

	return {
		"ok": true,
		"reason": "ok",
		"scope_id": scope_id,
		"registered": registered_now,
		"revisit": not registered_now and not already_resident,
		"material_initialization_queued": material_queued,
		"resident_count": _resident.size(),
	}


func notify_region_unloaded(runtime: Object, region_key: Vector2i) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "world_scope_lifecycle_not_initialized"}
	if runtime == null:
		return {"ok": false, "reason": "simulation_runtime_unavailable"}
	_unload_events_total += 1
	var scope_id := scope_id_for_region(region_key)
	if not _resident.has(scope_id):
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"scope_id": scope_id,
			"resident_count": _resident.size(),
		}
	var observation: Dictionary = runtime.submit_simulation_scope_observation(
		scope_id, TierRouterScript.MAX_DISTANCE_MM
	)
	if not observation.get("ok", false):
		return {
			"ok": false,
			"reason": "world_scope_unload_observation_failed",
			"detail": String(observation.get("reason", "")),
			"scope_id": scope_id,
		}
	_route_observations_total += 1
	_resident.erase(scope_id)
	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"scope_id": scope_id,
		"resident_count": _resident.size(),
	}


func update_focus(runtime: Object, focus_region: Vector2i) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "world_scope_lifecycle_not_initialized"}
	if runtime == null:
		return {"ok": false, "reason": "simulation_runtime_unavailable"}
	if _has_focus and focus_region == _focus_region:
		return {
			"ok": true,
			"reason": "ok",
			"noop": true,
			"observation_count": 0,
		}
	_focus_region = focus_region
	_has_focus = true
	_focus_events_total += 1
	var ids := _sorted_resident_ids()
	var submitted := 0
	for scope_id_value in ids:
		var scope_id := String(scope_id_value)
		var record: Dictionary = _resident[scope_id]
		var observation := _submit_observation(
			runtime, scope_id, record["region_key"]
		)
		if not observation.get("ok", false):
			return observation
		submitted += 1
	return {
		"ok": true,
		"reason": "ok",
		"noop": false,
		"observation_count": submitted,
	}


func process_scheduler_frame(
	runtime: Object,
	scheduler_result: Dictionary
) -> Dictionary:
	if not _initialized:
		return {"ok": false, "reason": "world_scope_lifecycle_not_initialized"}
	if runtime == null:
		return {"ok": false, "reason": "simulation_runtime_unavailable"}
	if not scheduler_result.get("ok", false):
		return {"ok": false, "reason": "world_scope_scheduler_result_invalid"}
	var frame_index := int(scheduler_result.get("frame_index", -1))
	if frame_index < 0 or frame_index < _last_frame_index:
		return {"ok": false, "reason": "world_scope_frame_invalid"}
	_last_frame_index = frame_index

	var routing: Dictionary = runtime.process_simulation_tier_routes()
	if not routing.get("ok", false):
		return {
			"ok": false,
			"reason": "world_scope_routing_failed",
			"detail": String(routing.get("reason", "")),
		}
	_route_batches_total += 1

	var due_result := {
		"decisions": 0,
		"queued": 0,
		"deferred": 0,
	}
	if not _profile_id.is_empty() or runtime.has_environment_climate() or runtime.has_environment_runoff():
		due_result = _schedule_due_work(
			runtime, int(scheduler_result.get("current_tick", 0))
		)
		if due_result.has("error"):
			return {
				"ok": false,
				"reason": "world_scope_due_scheduling_failed",
				"detail": String(due_result.get("error", "")),
			}

	return {
		"ok": true,
		"reason": "ok",
		"frame_index": frame_index,
		"resident_count": _resident.size(),
		"routing_processed_count": int(routing.get("processed_count", 0)),
		"routing_pending_count": int(routing.get("pending_count", 0)),
		"due_decisions": int(due_result["decisions"]),
		"due_updates_queued": int(due_result["queued"]),
		"due_updates_deferred": int(due_result["deferred"]),
		"climate_steps": int(due_result.get("climate_steps", 0)),
		"climate_noops": int(due_result.get("climate_noops", 0)),
		"runoff_steps": int(due_result.get("runoff_steps", 0)),
		"runoff_noops": int(due_result.get("runoff_noops", 0)),
		"runoff_deferred": int(due_result.get("runoff_deferred", 0)),
	}


func get_environment_tick_admission_limit(
	max_ticks_per_frame: int
) -> int:
	if not _initialized or _resident.is_empty():
		return -1
	if max_ticks_per_frame <= 0:
		return 0
	var capacity_per_tick := maxi(1, _resident.size())
	var bounded_ticks := int(_due_decision_budget / capacity_per_tick)
	return mini(max_ticks_per_frame, maxi(0, bounded_ticks))


func get_persistence_preflight(current_tick: int) -> Dictionary:
	if not _initialized:
		return {"ok": true, "reason": "ok", "resident_count": 0}
	if current_tick < 0:
		return {"ok": false, "reason": "world_scope_persistence_tick_invalid"}
	var pending_due_scope_count := 0
	for scope_id_value in _resident.keys():
		var scope_id := String(scope_id_value)
		var record: Dictionary = _resident[scope_id]
		if int(record.get("next_tick", current_tick + 1)) <= current_tick:
			pending_due_scope_count += 1
	if pending_due_scope_count > 0:
		return {
			"ok": false,
			"reason": "world_scope_due_cursors_pending",
			"resident_count": _resident.size(),
			"pending_due_scope_count": pending_due_scope_count,
		}
	return {
		"ok": true,
		"reason": "ok",
		"resident_count": _resident.size(),
		"pending_due_scope_count": 0,
	}


func reset_transient() -> void:
	_resident.clear()
	_has_focus = false
	_focus_region = Vector2i.ZERO
	_last_frame_index = -1


func get_resident_scope_ids() -> Array[String]:
	return _sorted_resident_ids()


func get_metrics() -> Dictionary:
	return {
		"initialized": _initialized,
		"resident_count": _resident.size(),
		"peak_resident_scopes": _peak_resident_scopes,
		"profile_id": _profile_id,
		"publication_events_total": _publication_events_total,
		"unload_events_total": _unload_events_total,
		"focus_events_total": _focus_events_total,
		"registrations_total": _registrations_total,
		"revisits_total": _revisits_total,
		"material_initializations_queued_total": _material_initializations_queued_total,
		"environment_registrations_total": _environment_registrations_total,
		"route_observations_total": _route_observations_total,
		"route_batches_total": _route_batches_total,
		"due_decisions_total": _due_decisions_total,
		"due_updates_queued_total": _due_updates_queued_total,
		"due_updates_deferred_total": _due_updates_deferred_total,
		"climate_steps_total": _climate_steps_total,
		"climate_noops_total": _climate_noops_total,
		"runoff_steps_total": _runoff_steps_total,
		"runoff_noops_total": _runoff_noops_total,
		"runoff_deferred_total": _runoff_deferred_total,
		"last_frame_index": _last_frame_index,
	}


func _schedule_due_work(runtime: Object, current_tick: int) -> Dictionary:
	var ids := _sorted_resident_ids()
	var decisions := 0
	var queued := 0
	var deferred := 0
	var climate_steps := 0
	var climate_noops := 0
	var runoff_steps := 0
	var runoff_noops := 0
	var runoff_deferred := 0
	var blocked_scope_ids: Dictionary = {}
	if ids.is_empty():
		return {
			"decisions": 0,
			"queued": 0,
			"deferred": 0,
			"climate_steps": 0,
			"climate_noops": 0,
			"runoff_steps": 0,
			"runoff_noops": 0,
			"runoff_deferred": 0,
		}

	var climate_enabled := bool(runtime.has_environment_climate())
	var runoff_enabled := bool(runtime.has_environment_runoff())
	var material_enabled := not _profile_id.is_empty()

	# Fair bounded sweeps. At most one next logical tick per resident per pass.
	while decisions < _due_decision_budget:
		var made_progress := false
		for scope_id_value in ids:
			if decisions >= _due_decision_budget:
				break
			var scope_id := String(scope_id_value)
			if not _resident.has(scope_id) or blocked_scope_ids.has(scope_id):
				continue
			var resident_record: Dictionary = _resident[scope_id]
			var next_tick := int(resident_record.get("next_tick", current_tick + 1))
			if next_tick > current_tick:
				continue

			var scope: Dictionary = runtime.get_simulation_scope(scope_id)
			var state: Dictionary = scope.get("state", {})
			if material_enabled and not state.has(DomainScript.STATE_KEY):
				deferred += 1
				continue

			var due: Dictionary = runtime.get_simulation_due_decision(
				scope_id, next_tick
			)
			if not due.get("ok", false):
				return {
					"decisions": decisions,
					"queued": queued,
					"deferred": deferred,
					"climate_steps": climate_steps,
					"climate_noops": climate_noops,
					"error": String(due.get("reason", "")),
				}
			decisions += 1
			_due_decisions_total += 1

			if bool(due.get("due", false)):
				if runoff_enabled:
					var runoff: Dictionary = runtime.process_environment_runoff_scope(
						scope_id, next_tick
					)
					if not runoff.get("ok", false):
						return {
							"decisions": decisions,
							"queued": queued,
							"deferred": deferred,
							"climate_steps": climate_steps,
							"climate_noops": climate_noops,
							"runoff_steps": runoff_steps,
							"runoff_noops": runoff_noops,
							"runoff_deferred": runoff_deferred,
							"error": String(runoff.get("reason", "")),
						}
					if runoff.get("deferred", false):
						deferred += 1
						runoff_deferred += 1
						_due_updates_deferred_total += 1
						_runoff_deferred_total += 1
						blocked_scope_ids[scope_id] = true
						continue
					if runoff.get("noop", false):
						runoff_noops += 1
						_runoff_noops_total += 1
					else:
						runoff_steps += 1
						_runoff_steps_total += 1
				elif climate_enabled:
					var climate: Dictionary = runtime.process_environment_climate_scope(
						scope_id, next_tick
					)
					if not climate.get("ok", false):
						return {
							"decisions": decisions,
							"queued": queued,
							"deferred": deferred,
							"climate_steps": climate_steps,
							"climate_noops": climate_noops,
							"runoff_steps": runoff_steps,
							"runoff_noops": runoff_noops,
							"runoff_deferred": runoff_deferred,
							"error": String(climate.get("reason", "")),
						}
					if climate.get("noop", false):
						climate_noops += 1
						_climate_noops_total += 1
					else:
						climate_steps += 1
						_climate_steps_total += 1

				if material_enabled:
					var admitted: Dictionary = runtime.enqueue_material_due_step(
						scope_id, _profile_id, next_tick
					)
					if not admitted.get("ok", false):
						if admitted.get("reason") == "material_queue_capacity_reached":
							deferred += 1
							_due_updates_deferred_total += 1
							continue
						return {
							"decisions": decisions,
							"queued": queued,
							"deferred": deferred,
							"climate_steps": climate_steps,
							"climate_noops": climate_noops,
							"error": String(admitted.get("reason", "")),
						}
					queued += 1
					_due_updates_queued_total += 1

			resident_record["next_tick"] = next_tick + 1
			_resident[scope_id] = resident_record
			made_progress = true
		if not made_progress:
			break
	return {
		"decisions": decisions,
		"queued": queued,
		"deferred": deferred,
		"climate_steps": climate_steps,
		"climate_noops": climate_noops,
		"runoff_steps": runoff_steps,
		"runoff_noops": runoff_noops,
		"runoff_deferred": runoff_deferred,
	}


func _submit_observation(
	runtime: Object,
	scope_id: String,
	region_key: Vector2i
) -> Dictionary:
	var distance_mm := _distance_from_focus_mm(region_key)
	var observation: Dictionary = runtime.submit_simulation_scope_observation(
		scope_id, distance_mm
	)
	if not observation.get("ok", false):
		return {
			"ok": false,
			"reason": "world_scope_observation_failed",
			"detail": String(observation.get("reason", "")),
			"scope_id": scope_id,
		}
	_route_observations_total += 1
	return {
		"ok": true,
		"reason": "ok",
		"scope_id": scope_id,
		"distance_mm": distance_mm,
	}


func _distance_from_focus_mm(region_key: Vector2i) -> int:
	if not _has_focus:
		return 0
	var dx := absi(region_key.x - _focus_region.x) * _region_size_x_mm
	var dz := absi(region_key.y - _focus_region.y) * _region_size_z_mm
	return maxi(dx, dz)


func _sorted_resident_ids() -> Array[String]:
	var ids: Array[String] = []
	for value in _resident.keys():
		ids.append(String(value))
	ids.sort()
	return ids


func _reset_metrics() -> void:
	_publication_events_total = 0
	_unload_events_total = 0
	_focus_events_total = 0
	_registrations_total = 0
	_revisits_total = 0
	_material_initializations_queued_total = 0
	_environment_registrations_total = 0
	_route_observations_total = 0
	_route_batches_total = 0
	_due_decisions_total = 0
	_due_updates_queued_total = 0
	_due_updates_deferred_total = 0
	_climate_steps_total = 0
	_climate_noops_total = 0
	_runoff_steps_total = 0
	_runoff_noops_total = 0
	_runoff_deferred_total = 0
	_peak_resident_scopes = 0
	_last_frame_index = -1
