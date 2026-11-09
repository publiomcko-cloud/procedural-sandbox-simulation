extends Node
class_name SimulationRuntime

## SceneTree adapter for P4 simulation authority.
##
## P4.0A owns deterministic fixed logical time. P4.0B owns explicit
## active/aggregate/dormant scope authority. P4.0C adds bounded automatic tier
## routing for explicit scope-distance observations. P5.0A adds authoritative
## environmental scope state plus transient scheduler admission backpressure.

const SchedulerScript := preload("res://scripts/simulation/fixed_tick_scheduler.gd")
const TierStateScript := preload("res://scripts/simulation/simulation_tier_state.gd")
const TierRouterScript := preload("res://scripts/simulation/simulation_tier_router.gd")
const MaterialBridgeScript := preload("res://scripts/simulation/material_environment_runtime_bridge.gd")
const MaterialQueueScript := preload("res://scripts/simulation/material_environment_work_queue.gd")
const MaterialDomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const WorldScopeLifecycleScript := preload("res://scripts/simulation/simulation_world_scope_lifecycle.gd")
const EnvironmentStateStoreScript := preload("res://scripts/simulation/environment_state_store.gd")
const EnvironmentSurfaceCacheScript := preload("res://scripts/simulation/environment_surface_cache.gd")
const EnvironmentClimateDomainScript := preload("res://scripts/simulation/environment_climate_domain.gd")
const EnvironmentRunoffDomainScript := preload("res://scripts/simulation/environment_runoff_domain.gd")
const EnvironmentHydrologyDomainScript := preload("res://scripts/simulation/environment_hydrology_domain.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")

const RUNTIME_SNAPSHOT_SCHEMA_VERSION := 3
const RUNTIME_SNAPSHOT_SCHEMA_V1 := 1
const RUNTIME_SNAPSHOT_SCHEMA_V2 := 2

const DEFAULT_TICK_USEC := SchedulerScript.DEFAULT_TICK_USEC
const DEFAULT_MAX_TICKS_PER_FRAME := SchedulerScript.DEFAULT_MAX_TICKS_PER_FRAME
const DEFAULT_AGGREGATE_INTERVAL_TICKS := TierStateScript.DEFAULT_AGGREGATE_INTERVAL_TICKS
const DEFAULT_MAX_SIMULATION_SCOPES := TierStateScript.DEFAULT_MAX_SCOPES
const DEFAULT_ROUTER_ACTIVE_ENTER_MM := TierRouterScript.DEFAULT_ACTIVE_ENTER_MM
const DEFAULT_ROUTER_ACTIVE_EXIT_MM := TierRouterScript.DEFAULT_ACTIVE_EXIT_MM
const DEFAULT_ROUTER_AGGREGATE_ENTER_MM := TierRouterScript.DEFAULT_AGGREGATE_ENTER_MM
const DEFAULT_ROUTER_AGGREGATE_EXIT_MM := TierRouterScript.DEFAULT_AGGREGATE_EXIT_MM
const DEFAULT_ROUTER_MAX_DECISIONS_PER_CALL := TierRouterScript.DEFAULT_MAX_DECISIONS_PER_CALL
const DEFAULT_ROUTER_MAX_TRACKED_OBSERVATIONS := TierRouterScript.DEFAULT_MAX_TRACKED_OBSERVATIONS

const RUNTIME_SNAPSHOT_FIELDS_V1 := [
	"schema_version",
	"fractional_usec",
	"scheduler",
	"tier_state",
]
const RUNTIME_SNAPSHOT_FIELDS_V2 := [
	"schema_version",
	"fractional_usec",
	"scheduler",
	"tier_state",
	"tier_router",
]
const RUNTIME_SNAPSHOT_FIELDS_V3 := [
	"schema_version",
	"fractional_usec",
	"scheduler",
	"tier_state",
	"tier_router",
	"environment_state",
]

var scheduler: RefCounted
var tier_state: RefCounted
var tier_router: RefCounted
var material_bridge: RefCounted
var world_scope_lifecycle: RefCounted
var environment_state_store: RefCounted
var environment_surface_cache: RefCounted
var environment_climate_domain: RefCounted
var environment_runoff_domain: RefCounted
var environment_hydrology_domain: RefCounted
var initialized := false
var initialization_error := ""

var _fractional_usec := 0.0
var _last_result: Dictionary = {}
var _perf_trace_enabled := false
var _environment_tick_admission_limit := -1
var _environment_climate_profile_id := ""
var _environment_climate_profile_sha256 := ""


func _ready() -> void:
	_perf_trace_enabled = PerformanceTrace.is_enabled()
	if not initialized:
		var result: Dictionary = initialize_runtime()
		if not result.get("ok", false):
			push_error("Simulation runtime initialization failed: %s" % result.get("reason", "unknown"))


func _process(delta: float) -> void:
	if not initialized:
		return
	var result: Dictionary = process_delta_seconds(delta)
	if not result.get("ok", false):
		initialization_error = String(result.get("reason", "scheduler_frame_failed"))
		push_error("Simulation scheduler frame failed: %s" % initialization_error)


func initialize_runtime(
	tick_usec: int = DEFAULT_TICK_USEC,
	max_ticks_per_frame: int = DEFAULT_MAX_TICKS_PER_FRAME,
	start_tick: int = 0,
	start_paused: bool = false,
	aggregate_interval_ticks: int = DEFAULT_AGGREGATE_INTERVAL_TICKS,
	max_simulation_scopes: int = DEFAULT_MAX_SIMULATION_SCOPES,
	router_active_enter_mm: int = DEFAULT_ROUTER_ACTIVE_ENTER_MM,
	router_active_exit_mm: int = DEFAULT_ROUTER_ACTIVE_EXIT_MM,
	router_aggregate_enter_mm: int = DEFAULT_ROUTER_AGGREGATE_ENTER_MM,
	router_aggregate_exit_mm: int = DEFAULT_ROUTER_AGGREGATE_EXIT_MM,
	router_max_decisions_per_call: int = DEFAULT_ROUTER_MAX_DECISIONS_PER_CALL,
	router_max_tracked_observations: int = DEFAULT_ROUTER_MAX_TRACKED_OBSERVATIONS
) -> Dictionary:
	if initialized:
		return {"ok": false, "reason": "simulation_runtime_already_initialized"}

	var next_scheduler: RefCounted = SchedulerScript.new()
	var scheduler_result: Dictionary = next_scheduler.initialize(
		tick_usec, max_ticks_per_frame, start_tick, start_paused
	)
	if not scheduler_result.get("ok", false):
		initialization_error = String(
			scheduler_result.get("reason", "scheduler_initialization_failed")
		)
		return scheduler_result

	var next_tier_state: RefCounted = TierStateScript.new()
	var tier_result: Dictionary = next_tier_state.initialize(
		aggregate_interval_ticks, max_simulation_scopes
	)
	if not tier_result.get("ok", false):
		initialization_error = String(
			tier_result.get("reason", "simulation_tier_initialization_failed")
		)
		return tier_result

	var next_tier_router: RefCounted = TierRouterScript.new()
	var router_result: Dictionary = next_tier_router.initialize(
		router_active_enter_mm,
		router_active_exit_mm,
		router_aggregate_enter_mm,
		router_aggregate_exit_mm,
		router_max_decisions_per_call,
		router_max_tracked_observations
	)
	if not router_result.get("ok", false):
		initialization_error = String(
			router_result.get("reason", "simulation_tier_router_initialization_failed")
		)
		return router_result

	var next_environment_store: RefCounted = EnvironmentStateStoreScript.new()
	var environment_result: Dictionary = next_environment_store.initialize(
		EnvironmentStateStoreScript.DEFAULT_GRID_WIDTH,
		EnvironmentStateStoreScript.DEFAULT_GRID_HEIGHT,
		max_simulation_scopes
	)
	if not environment_result.get("ok", false):
		initialization_error = String(
			environment_result.get("reason", "environment_store_initialization_failed")
		)
		return environment_result

	var next_surface_cache: RefCounted = EnvironmentSurfaceCacheScript.new()
	var surface_cache_result: Dictionary = next_surface_cache.initialize(
		max_simulation_scopes
	)
	if not surface_cache_result.get("ok", false):
		initialization_error = String(
			surface_cache_result.get("reason", "surface_cache_initialization_failed")
		)
		return surface_cache_result

	if material_bridge != null:
		material_bridge.reset_after_restore()
	material_bridge = null
	if world_scope_lifecycle != null:
		world_scope_lifecycle.reset_transient()
	world_scope_lifecycle = null
	world_scope_lifecycle = null
	scheduler = next_scheduler
	tier_state = next_tier_state
	tier_router = next_tier_router
	environment_state_store = next_environment_store
	environment_surface_cache = next_surface_cache
	environment_climate_domain = null
	environment_runoff_domain = null
	environment_hydrology_domain = null
	_environment_climate_profile_id = ""
	_environment_climate_profile_sha256 = ""
	_environment_tick_admission_limit = -1
	_fractional_usec = 0.0
	_last_result = {}
	initialization_error = ""
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": get_runtime_snapshot(),
	}


func process_delta_seconds(delta: float) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if not is_finite(delta) or delta < 0.0:
		return {"ok": false, "reason": "simulation_delta_invalid"}

	if scheduler.is_paused():
		return process_elapsed_usec(0)

	var total_usec: float = delta * 1_000_000.0 + _fractional_usec
	var elapsed_usec: int = floori(total_usec)
	var next_fractional_usec: float = total_usec - float(elapsed_usec)
	var result: Dictionary = process_elapsed_usec(elapsed_usec)
	if result.get("ok", false):
		_fractional_usec = next_fractional_usec
	return result


func process_elapsed_usec(elapsed_usec: int) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}

	var started_usec: int = Time.get_ticks_usec() if _perf_trace_enabled else 0
	var effective_environment_limit := _environment_tick_admission_limit
	if (
		(has_environment_climate() or has_environment_runoff() or has_environment_hydrology())
		and world_scope_lifecycle != null
		and world_scope_lifecycle.is_initialized()
	):
		var lifecycle_environment_limit := int(
			world_scope_lifecycle.get_environment_tick_admission_limit(
				scheduler.get_max_ticks_per_frame()
			)
		)
		if lifecycle_environment_limit >= 0:
			effective_environment_limit = (
				lifecycle_environment_limit
				if effective_environment_limit < 0
				else mini(effective_environment_limit, lifecycle_environment_limit)
			)
	var result: Dictionary = scheduler.process_elapsed_usec(
		elapsed_usec, effective_environment_limit
	)
	result["environment_capacity_admission_limit"] = effective_environment_limit
	if (
		result.get("ok", false)
		and world_scope_lifecycle != null
		and world_scope_lifecycle.is_initialized()
	):
		var lifecycle_started_usec := Time.get_ticks_usec() if _perf_trace_enabled else 0
		var lifecycle_result: Dictionary = world_scope_lifecycle.process_scheduler_frame(
			self, result
		)
		if not lifecycle_result.get("ok", false):
			return {
				"ok": false,
				"reason": "world_scope_lifecycle_frame_failed",
				"detail": String(
					lifecycle_result.get("detail", lifecycle_result.get("reason", ""))
				),
			}
		result["world_scope_lifecycle"] = lifecycle_result
		if _perf_trace_enabled:
			var lifecycle_work := (
				int(lifecycle_result.get("routing_processed_count", 0))
				+ int(lifecycle_result.get("due_decisions", 0))
				+ int(lifecycle_result.get("due_updates_queued", 0))
			)
			if lifecycle_work > 0 or int(lifecycle_result.get("resident_count", 0)) > 0:
				PerformanceTrace.emit_duration(
					"simulation_world_scope_frame",
					lifecycle_started_usec,
					lifecycle_result,
					true
				)
	if result.get("ok", false) and material_bridge != null and material_bridge.is_enabled():
		var material_batch: Dictionary = material_bridge.process_frame(
			tier_state, int(result.get("frame_index", -1))
		)
		if not material_batch.get("ok", false):
			return {
				"ok": false, "reason": "material_runtime_frame_failed",
				"detail": String(material_batch.get("detail", material_batch.get("reason", ""))),
			}
		result["material_batch"] = material_batch
	_last_result = result.duplicate(true)

	if _perf_trace_enabled and result.get("ok", false):
		var admitted_ticks: int = int(result.get("admitted_ticks", 0))
		var backlog_ticks: int = int(result.get("backlog_ticks", 0))
		var manual_step_ticks: int = int(result.get("manual_step_ticks", 0))
		if admitted_ticks > 0 or backlog_ticks > 0 or manual_step_ticks > 0:
			PerformanceTrace.emit_duration(
				"simulation_scheduler_frame",
				started_usec,
				{
					"elapsed_usec": elapsed_usec,
					"frame_index": int(result.get("frame_index", 0)),
					"source": String(result.get("source", "")),
					"first_tick": int(result.get("first_tick", -1)),
					"last_tick": int(result.get("last_tick", -1)),
					"admitted_ticks": admitted_ticks,
					"newly_due_ticks": int(result.get("newly_due_ticks", 0)),
					"backlog_ticks": backlog_ticks,
					"manual_step_ticks": manual_step_ticks,
					"paused": bool(result.get("paused", false)),
					"environment_tick_admission_limit": _environment_tick_admission_limit,
					"environment_capacity_admission_limit": effective_environment_limit,
					"backpressure_limited": bool(result.get("backpressure_limited", false)),
					"ticks_deferred_by_backpressure": int(
						result.get("ticks_deferred_by_backpressure", 0)
					),
				},
				true
			)
	return result


func set_simulation_paused(value: bool) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return scheduler.set_paused(value)


func request_simulation_steps(count: int = 1) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return scheduler.request_steps(count)


func register_simulation_scope(
	scope_id: String,
	initial_tier: String = TierStateScript.TIER_DORMANT,
	state: Dictionary = {}
) -> Dictionary:
	if not initialized or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return tier_state.register_scope(scope_id, initial_tier, state)


func transition_simulation_scope(
	scope_id: String,
	target_tier: String,
	expected_tier_revision: int = -1
) -> Dictionary:
	if not initialized or scheduler == null or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}

	var started_usec: int = Time.get_ticks_usec() if _perf_trace_enabled else 0
	var logical_tick: int = int(scheduler.get_current_tick())
	var result: Dictionary = tier_state.transition_scope(
		scope_id, target_tier, logical_tick, expected_tier_revision
	)
	if (
		_perf_trace_enabled
		and result.get("ok", false)
		and not result.get("noop", false)
	):
		var record: Dictionary = result.get("record", {})
		PerformanceTrace.emit_duration(
			"simulation_tier_transition",
			started_usec,
			{
				"scope_id": scope_id,
				"logical_tick": logical_tick,
				"source_tier": String(result.get("source_tier", "")),
				"target_tier": String(result.get("target_tier", "")),
				"tier_revision": int(record.get("tier_revision", -1)),
				"state_revision": int(record.get("state_revision", -1)),
			},
			true
		)
	return result


func replace_simulation_scope_state(
	scope_id: String,
	state: Dictionary,
	expected_state_revision: int = -1
) -> Dictionary:
	if not initialized or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return tier_state.replace_scope_state(
		scope_id, state, expected_state_revision
	)


func configure_material_environment(
	registry: RefCounted, profile_id: String,
	budget_per_frame: int = MaterialQueueScript.DEFAULT_BUDGET,
	queue_capacity: int = MaterialQueueScript.DEFAULT_CAPACITY
) -> Dictionary:
	if not initialized or tier_state == null or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if material_bridge != null and material_bridge.is_enabled():
		return {"ok": false, "reason": "material_bridge_already_configured"}
	var candidate: RefCounted = MaterialBridgeScript.new()
	var outcome: Dictionary = candidate.configure(
		registry, profile_id, budget_per_frame, queue_capacity
	)
	if outcome.get("ok", false):
		material_bridge = candidate
	return outcome


func enqueue_material_scope_registration(
	scope_id: String,
	initial_tier: String = TierStateScript.TIER_DORMANT
) -> Dictionary:
	if material_bridge == null:
		return {"ok": false, "reason": "material_bridge_not_configured"}
	return material_bridge.register_scope(tier_state, scope_id, initial_tier)


func enqueue_material_scope_initialization(
	scope_id: String, profile_id: String, initial_temperature_milli_c: int
) -> Dictionary:
	if material_bridge == null:
		return {"ok": false, "reason": "material_bridge_not_configured"}
	return material_bridge.initialize_scope(
		tier_state, scope_id, profile_id, initial_temperature_milli_c
	)


func enqueue_material_due_step(
	scope_id: String, profile_id: String, logical_tick: int = -1
) -> Dictionary:
	if material_bridge == null or scheduler == null:
		return {"ok": false, "reason": "material_bridge_not_configured"}
	var due_tick: int = int(scheduler.get_current_tick()) if logical_tick == -1 else logical_tick
	if due_tick < 0 or due_tick > scheduler.get_current_tick():
		return {"ok": false, "reason": "material_due_tick_not_admitted"}
	return material_bridge.submit_due(tier_state, scope_id, profile_id, due_tick)


func get_material_environment_metrics() -> Dictionary:
	return material_bridge.get_metrics() if material_bridge != null else {"enabled": false}


func configure_world_scope_lifecycle(
	profile_id: String = "",
	max_resident_scopes: int = WorldScopeLifecycleScript.DEFAULT_MAX_RESIDENT_SCOPES,
	region_size_x_mm: int = WorldScopeLifecycleScript.DEFAULT_REGION_SIZE_X_MM,
	region_size_z_mm: int = WorldScopeLifecycleScript.DEFAULT_REGION_SIZE_Z_MM,
	due_decision_budget: int = WorldScopeLifecycleScript.DEFAULT_DUE_DECISION_BUDGET
) -> Dictionary:
	if not initialized or scheduler == null or tier_state == null or tier_router == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if world_scope_lifecycle != null and world_scope_lifecycle.is_initialized():
		return {"ok": false, "reason": "world_scope_lifecycle_already_initialized"}
	if not profile_id.is_empty():
		if material_bridge == null or not material_bridge.is_enabled():
			return {"ok": false, "reason": "material_bridge_not_configured"}
	var candidate: RefCounted = WorldScopeLifecycleScript.new()
	var result: Dictionary = candidate.initialize(
		profile_id,
		max_resident_scopes,
		region_size_x_mm,
		region_size_z_mm,
		due_decision_budget
	)
	if result.get("ok", false):
		world_scope_lifecycle = candidate
	return result


func publish_world_region_scope(
	region_key: Vector2i,
	initial_temperature_milli_c: int = 0
) -> Dictionary:
	if world_scope_lifecycle == null:
		return {"ok": false, "reason": "world_scope_lifecycle_not_initialized"}
	return world_scope_lifecycle.notify_region_published(
		self, region_key, initial_temperature_milli_c
	)


func unload_world_region_scope(region_key: Vector2i) -> Dictionary:
	if world_scope_lifecycle == null:
		return {"ok": false, "reason": "world_scope_lifecycle_not_initialized"}
	var result: Dictionary = world_scope_lifecycle.notify_region_unloaded(self, region_key)
	if result.get("ok", false) and environment_surface_cache != null:
		environment_surface_cache.discard_scope(
			world_scope_lifecycle.scope_id_for_region(region_key)
		)
	return result


func update_world_scope_focus(region_key: Vector2i) -> Dictionary:
	if world_scope_lifecycle == null:
		return {"ok": false, "reason": "world_scope_lifecycle_not_initialized"}
	return world_scope_lifecycle.update_focus(self, region_key)


func get_world_scope_lifecycle_metrics() -> Dictionary:
	if world_scope_lifecycle == null:
		return {"initialized": false}
	return world_scope_lifecycle.get_metrics()


func get_world_scope_resident_ids() -> Array[String]:
	if world_scope_lifecycle == null:
		return []
	return world_scope_lifecycle.get_resident_scope_ids()


func get_simulation_scope(scope_id: String) -> Dictionary:
	if not initialized or tier_state == null:
		return {}
	return tier_state.get_scope(scope_id)


func get_simulation_due_decision(
	scope_id: String,
	logical_tick: int = -1
) -> Dictionary:
	if not initialized or scheduler == null or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	var query_tick := logical_tick
	if query_tick < 0:
		query_tick = scheduler.get_current_tick()
	return tier_state.get_due_decision(scope_id, query_tick)


func submit_simulation_scope_observation(
	scope_id: String,
	distance_mm: int
) -> Dictionary:
	if not initialized or tier_state == null or tier_router == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return tier_router.submit_observation(scope_id, distance_mm, tier_state)


func process_simulation_tier_routes(requested_budget: int = -1) -> Dictionary:
	if (
		not initialized
		or scheduler == null
		or tier_state == null
		or tier_router == null
	):
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}

	var started_usec: int = Time.get_ticks_usec() if _perf_trace_enabled else 0
	var result: Dictionary = tier_router.process_pending(
		tier_state,
		scheduler.get_current_tick(),
		requested_budget
	)
	if _perf_trace_enabled and result.get("ok", false):
		var processed_count := int(result.get("processed_count", 0))
		var pending_count := int(result.get("pending_count", 0))
		if processed_count > 0 or pending_count > 0:
			PerformanceTrace.emit_duration(
				"simulation_tier_routing_batch",
				started_usec,
				{
					"logical_tick": scheduler.get_current_tick(),
					"processed_count": processed_count,
					"pending_count": pending_count,
					"budget": int(result.get("budget", 0)),
				},
				true
			)
	return result


func get_simulation_scope_observation(scope_id: String) -> Dictionary:
	if not initialized or tier_router == null:
		return {}
	return tier_router.get_observation(scope_id)


func get_scheduler_snapshot() -> Dictionary:
	if not initialized or scheduler == null:
		return {}
	return scheduler.get_authoritative_snapshot()


func get_scheduler_metrics() -> Dictionary:
	if not initialized or scheduler == null:
		return {}
	return scheduler.get_metrics()


func get_simulation_tier_snapshot() -> Dictionary:
	if not initialized or tier_state == null:
		return {}
	return tier_state.get_authoritative_snapshot()


func get_simulation_tier_metrics() -> Dictionary:
	if not initialized or tier_state == null:
		return {}
	return tier_state.get_metrics()


func get_simulation_router_snapshot() -> Dictionary:
	if not initialized or tier_router == null:
		return {}
	return tier_router.get_authoritative_snapshot()


func get_simulation_router_metrics() -> Dictionary:
	if not initialized or tier_router == null:
		return {}
	return tier_router.get_metrics()


func register_environment_scope(
	scope_id: String,
	profile_id: String = "",
	profile_sha256: String = "",
	last_environment_tick: int = -1
) -> Dictionary:
	if not initialized or tier_state == null or environment_state_store == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if tier_state.get_scope(scope_id).is_empty():
		return {"ok": false, "reason": "environment_simulation_scope_missing"}
	if last_environment_tick < -1:
		return {"ok": false, "reason": "environment_tick_invalid"}
	var resolved_tick: int = (
		int(scheduler.get_current_tick())
		if last_environment_tick == -1
		else last_environment_tick
	)
	var resolved_profile_id := profile_id
	var resolved_profile_sha256 := profile_sha256
	if resolved_profile_id.is_empty() and resolved_profile_sha256.is_empty() and has_environment_climate():
		resolved_profile_id = _environment_climate_profile_id
		resolved_profile_sha256 = _environment_climate_profile_sha256
	return environment_state_store.register_scope(
		scope_id, resolved_profile_id, resolved_profile_sha256, resolved_tick
	)


func configure_environment_climate(
	registry: RefCounted,
	profile_id: String
) -> Dictionary:
	if not initialized or environment_state_store == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if registry == null:
		return {"ok": false, "reason": "environment_climate_registry_unavailable"}
	var next_domain: RefCounted = EnvironmentClimateDomainScript.new()
	var bind: Dictionary = next_domain.bind_registry_profile(registry, profile_id)
	if not bind.get("ok", false):
		return bind
	var pin: Dictionary = next_domain.get_bound_profile_pin(profile_id)
	if pin.is_empty():
		return {"ok": false, "reason": "environment_climate_profile_not_bound"}
	var sha := String(pin["profile_sha256"])

	for scope_id in environment_state_store.get_scope_ids():
		var record: Dictionary = environment_state_store.get_scope(scope_id)
		var existing_id := String(record.get("profile_id", ""))
		var existing_sha := String(record.get("profile_sha256", ""))
		if (
			(not existing_id.is_empty() or not existing_sha.is_empty())
			and (existing_id != profile_id or existing_sha != sha)
		):
			return {
				"ok": false,
				"reason": "environment_climate_profile_pin_conflict",
				"scope_id": scope_id,
			}
	for scope_id in environment_state_store.get_scope_ids():
		var record: Dictionary = environment_state_store.get_scope(scope_id)
		if String(record.get("profile_id", "")).is_empty():
			var profile_bind: Dictionary = environment_state_store.bind_scope_profile(
				scope_id, profile_id, sha, int(scheduler.get_current_tick())
			)
			if not profile_bind.get("ok", false):
				return profile_bind

	environment_climate_domain = next_domain
	environment_runoff_domain = null
	_environment_climate_profile_id = profile_id
	_environment_climate_profile_sha256 = sha
	return {
		"ok": true,
		"reason": "ok",
		"profile_id": profile_id,
		"profile_sha256": sha,
	}


func has_environment_climate() -> bool:
	return (
		environment_climate_domain != null
		and not _environment_climate_profile_id.is_empty()
		and not _environment_climate_profile_sha256.is_empty()
	)


func configure_environment_runoff(
	registry: RefCounted,
	profile_id: String
) -> Dictionary:
	if not initialized or environment_state_store == null or environment_surface_cache == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if not has_environment_climate():
		return {"ok": false, "reason": "environment_runoff_climate_not_configured"}
	if (
		profile_id != _environment_climate_profile_id
		or registry == null
	):
		return {"ok": false, "reason": "environment_runoff_profile_pin_conflict"}

	var next_domain: RefCounted = EnvironmentRunoffDomainScript.new()
	var bind: Dictionary = next_domain.bind_registry_profile(registry, profile_id)
	if not bind.get("ok", false):
		return bind
	var pin: Dictionary = next_domain.get_bound_profile_pin(profile_id)
	if (
		pin.is_empty()
		or String(pin.get("profile_sha256", ""))
			!= _environment_climate_profile_sha256
	):
		return {"ok": false, "reason": "environment_runoff_profile_pin_conflict"}
	environment_runoff_domain = next_domain
	environment_hydrology_domain = null
	return {
		"ok": true,
		"reason": "ok",
		"profile_id": profile_id,
		"profile_sha256": _environment_climate_profile_sha256,
	}


func has_environment_runoff() -> bool:
	return (
		environment_runoff_domain != null
		and has_environment_climate()
	)


func configure_environment_hydrology(
	world_seed: int,
	generator_version: int
) -> Dictionary:
	if not initialized or environment_state_store == null or environment_surface_cache == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if not has_environment_runoff():
		return {"ok": false, "reason": "environment_hydrology_runoff_not_configured"}
	var next_domain: RefCounted = EnvironmentHydrologyDomainScript.new()
	var configured: Dictionary = next_domain.initialize(
		environment_runoff_domain,
		_environment_climate_profile_id,
		world_seed,
		generator_version
	)
	if not configured.get("ok", false):
		return configured
	environment_hydrology_domain = next_domain
	return configured


func has_environment_hydrology() -> bool:
	return (
		environment_hydrology_domain != null
		and environment_hydrology_domain.is_initialized()
		and has_environment_runoff()
	)


func process_environment_hydrology_batch(
	scope_ids: Array[String],
	logical_tick: int,
	max_scope_count: int
) -> Dictionary:
	if (
		not initialized
		or environment_state_store == null
		or environment_surface_cache == null
	):
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if not has_environment_hydrology():
		return {"ok": false, "reason": "environment_hydrology_not_configured"}
	return environment_hydrology_domain.process_due_batch(
		environment_state_store,
		environment_surface_cache,
		scope_ids,
		logical_tick,
		max_scope_count
	)


func get_environment_hydrology_metrics() -> Dictionary:
	if not has_environment_hydrology():
		return {"enabled": false, "metrics": {}}
	return {
		"enabled": true,
		"metrics": environment_hydrology_domain.get_metrics(),
	}


func process_environment_runoff_scope(
	scope_id: String,
	logical_tick: int
) -> Dictionary:
	if (
		not initialized
		or environment_state_store == null
		or environment_surface_cache == null
		or tier_state == null
	):
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if not has_environment_runoff():
		return {"ok": false, "reason": "environment_runoff_not_configured"}
	return environment_runoff_domain.process_bound_due_scope(
		environment_state_store,
		tier_state,
		environment_surface_cache,
		scope_id,
		_environment_climate_profile_id,
		logical_tick
	)


func get_environment_runoff_metrics() -> Dictionary:
	if not has_environment_runoff():
		return {
			"enabled": false,
			"profile_id": "",
			"profile_sha256": "",
			"metrics": {},
		}
	return {
		"enabled": true,
		"profile_id": _environment_climate_profile_id,
		"profile_sha256": _environment_climate_profile_sha256,
		"metrics": environment_runoff_domain.get_metrics(),
	}


func process_environment_climate_scope(
	scope_id: String,
	logical_tick: int
) -> Dictionary:
	if not initialized or environment_state_store == null or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if not has_environment_climate():
		return {"ok": false, "reason": "environment_climate_not_configured"}
	return environment_climate_domain.process_bound_due_scope(
		environment_state_store,
		tier_state,
		scope_id,
		_environment_climate_profile_id,
		logical_tick
	)


func get_environment_climate_metrics() -> Dictionary:
	if not has_environment_climate():
		return {
			"enabled": false,
			"profile_id": "",
		"profile_sha256": "",
		"metrics": {},
		}
	return {
		"enabled": true,
		"profile_id": _environment_climate_profile_id,
		"profile_sha256": _environment_climate_profile_sha256,
		"metrics": environment_climate_domain.get_metrics(),
	}


func expect_environment_surface_cache(
	scope_id: String,
	region_key: Vector2i,
	world_seed: int,
	generator_version: int,
	terrain_revision: int,
	terrain_cache_scope_id: int,
	terrain_effect_revision: int
) -> Dictionary:
	if (
		not initialized
		or environment_surface_cache == null
		or tier_state == null
		or environment_state_store == null
	):
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if tier_state.get_scope(scope_id).is_empty() 		or environment_state_store.get_scope(scope_id).is_empty():
		return {"ok": false, "reason": "surface_cache_environment_scope_missing"}
	return environment_surface_cache.expect_scope(
		scope_id,
		region_key,
		world_seed,
		generator_version,
		terrain_revision,
		terrain_cache_scope_id,
		terrain_effect_revision
	)


func publish_environment_surface_cache(record: Dictionary) -> Dictionary:
	if not initialized or environment_surface_cache == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	var scope_id := String(record.get("scope_id", ""))
	if tier_state.get_scope(scope_id).is_empty() 		or environment_state_store.get_scope(scope_id).is_empty():
		return {"ok": false, "reason": "surface_cache_environment_scope_missing"}
	return environment_surface_cache.publish(record)


func discard_environment_surface_cache(scope_id: String) -> Dictionary:
	if not initialized or environment_surface_cache == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return environment_surface_cache.discard_scope(scope_id)


func get_environment_surface_cache(scope_id: String) -> Dictionary:
	if not initialized or environment_surface_cache == null:
		return {}
	return environment_surface_cache.get_scope(scope_id)


func get_environment_surface_cache_metrics() -> Dictionary:
	if not initialized or environment_surface_cache == null:
		return {"initialized": false}
	return environment_surface_cache.get_metrics()


func get_environment_scope(scope_id: String) -> Dictionary:
	if not initialized or environment_state_store == null:
		return {}
	return environment_state_store.get_scope(scope_id)


func commit_environment_batch(updates: Array) -> Dictionary:
	if not initialized or environment_state_store == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	return environment_state_store.commit_batch(updates)


func get_environment_state_snapshot() -> Dictionary:
	if not initialized or environment_state_store == null:
		return {}
	return environment_state_store.get_authoritative_snapshot()


func get_environment_metrics() -> Dictionary:
	if not initialized or environment_state_store == null:
		return {}
	var metrics: Dictionary = environment_state_store.get_metrics()
	metrics["tick_admission_limit"] = _environment_tick_admission_limit
	return metrics


func set_environment_tick_admission_limit(limit: int = -1) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if limit < -1 or limit > SchedulerScript.MAX_TICKS_PER_FRAME_HARD:
		return {"ok": false, "reason": "environment_tick_admission_limit_invalid"}
	_environment_tick_admission_limit = limit
	return {
		"ok": true,
		"reason": "ok",
		"tick_admission_limit": _environment_tick_admission_limit,
	}


func get_environment_tick_admission_limit() -> int:
	return _environment_tick_admission_limit


func get_runtime_snapshot() -> Dictionary:
	if (
		not initialized
		or scheduler == null
		or tier_state == null
		or tier_router == null
	):
		return {}
	return {
		"schema_version": RUNTIME_SNAPSHOT_SCHEMA_VERSION,
		"fractional_usec": _fractional_usec,
		"scheduler": scheduler.get_authoritative_snapshot(),
		"tier_state": tier_state.get_authoritative_snapshot(),
		"tier_router": tier_router.get_authoritative_snapshot(),
		"environment_state": (
			environment_state_store.get_authoritative_snapshot()
			if environment_state_store != null
			else {}
		),
	}


func get_persistence_preflight() -> Dictionary:
	if not initialized or scheduler == null or tier_state == null or tier_router == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	var router_pending: int = int(tier_router.get_pending_count())
	if router_pending > 0:
		return {
			"ok": false,
			"reason": "simulation_router_work_pending",
			"router_pending_count": router_pending,
		}
	if material_bridge != null and material_bridge.is_enabled():
		var material_metrics: Dictionary = material_bridge.get_metrics()
		var queue_metrics: Dictionary = material_metrics.get("queue", {})
		var material_pending := int(queue_metrics.get("pending_count", 0))
		if material_pending > 0:
			return {
				"ok": false,
				"reason": "material_queue_work_pending",
				"material_pending_count": material_pending,
			}
	if world_scope_lifecycle != null and world_scope_lifecycle.is_initialized():
		var lifecycle: Dictionary = world_scope_lifecycle.get_persistence_preflight(
			scheduler.get_current_tick()
		)
		if not lifecycle.get("ok", false):
			return lifecycle
	return {
		"ok": true,
		"reason": "ok",
		"current_tick": scheduler.get_current_tick(),
		"router_pending_count": router_pending,
		"material_pending_count": 0,
		"environment_scope_count": (
			environment_state_store.get_scope_count()
			if environment_state_store != null
			else 0
		),
	}


func get_runtime_snapshot_fingerprint() -> String:
	var snapshot := get_runtime_snapshot()
	if snapshot.is_empty():
		return ""
	var bytes: PackedByteArray = var_to_bytes(snapshot)
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()


func validate_material_state_content(registry: RefCounted) -> Dictionary:
	if not initialized or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	var domain: RefCounted = MaterialDomainScript.new()
	var checked_bindings: Dictionary = {}
	var material_scope_count := 0
	var scopes: Array = tier_state.get_authoritative_snapshot().get("scopes", [])
	for record_value in scopes:
		var record: Dictionary = record_value
		var state: Dictionary = record.get("state", {})
		if not state.has(MaterialDomainScript.STATE_KEY):
			continue
		if typeof(state[MaterialDomainScript.STATE_KEY]) != TYPE_DICTIONARY:
			return {
				"ok": false,
				"reason": "material_state_invalid",
				"scope_id": String(record.get("scope_id", "")),
			}
		var material: Dictionary = state[MaterialDomainScript.STATE_KEY]
		var payload: Dictionary = domain.validate_persisted_state_payload(material)
		if not payload.get("ok", false):
			return {
				"ok": false,
				"reason": String(payload.get("reason", "material_state_invalid")),
				"scope_id": String(record.get("scope_id", "")),
			}
		material_scope_count += 1
		if registry == null:
			return {
				"ok": false,
				"reason": "material_registry_unavailable",
				"scope_id": String(record.get("scope_id", "")),
			}
		var binding_key := "%s|%s" % [
			String(payload["profile_id"]), String(payload["profile_sha256"])
		]
		if checked_bindings.has(binding_key):
			continue
		var binding: Dictionary = domain.validate_persisted_state_binding(
			registry, material
		)
		if not binding.get("ok", false):
			return {
				"ok": false,
				"reason": String(binding.get("reason", "material_persisted_profile_invalid")),
				"profile_id": String(payload["profile_id"]),
			}
		checked_bindings[binding_key] = true
	return {
		"ok": true,
		"reason": "ok",
		"material_scope_count": material_scope_count,
		"validated_binding_count": checked_bindings.size(),
	}


func validate_environment_climate_content(registry: RefCounted) -> Dictionary:
	if not initialized or environment_state_store == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}
	if registry == null:
		return {"ok": false, "reason": "environment_climate_registry_unavailable"}
	var checked: Dictionary = {}
	var scoped := 0
	for scope_id in environment_state_store.get_scope_ids():
		var record: Dictionary = environment_state_store.get_scope(scope_id)
		var profile_id := String(record.get("profile_id", ""))
		var profile_sha := String(record.get("profile_sha256", ""))
		if profile_id.is_empty() and profile_sha.is_empty():
			continue
		if profile_id.is_empty() or profile_sha.length() != 64:
			return {
				"ok": false,
				"reason": "environment_profile_pin_invalid",
				"scope_id": scope_id,
			}
		scoped += 1
		var key := "%s|%s" % [profile_id, profile_sha]
		if checked.has(key):
			continue
		var pin: Dictionary = registry.pin_content_record(
			EnvironmentClimateDomainScript.PROFILE_TYPE, profile_id
		)
		if not pin.get("ok", false):
			return {
				"ok": false,
				"reason": "environment_climate_persisted_profile_missing",
				"profile_id": profile_id,
			}
		var fingerprint: Dictionary = pin.get("fingerprint", {})
		var verified: Dictionary = registry.validate_content_fingerprint(fingerprint)
		if not verified.get("ok", false):
			return {
				"ok": false,
				"reason": "environment_climate_persisted_profile_invalid",
				"profile_id": profile_id,
			}
		if String(fingerprint.get("content_sha256", "")) != profile_sha:
			return {
				"ok": false,
				"reason": "environment_climate_persisted_profile_pin_conflict",
				"profile_id": profile_id,
			}
		checked[key] = true
	return {
		"ok": true,
		"reason": "ok",
		"environment_climate_scope_count": scoped,
		"validated_binding_count": checked.size(),
	}


func consume_last_scheduler_result() -> Dictionary:
	var result: Dictionary = _last_result.duplicate(true)
	_last_result.clear()
	return result


func restore_scheduler_snapshot(snapshot: Dictionary) -> Dictionary:
	var next_scheduler: RefCounted = SchedulerScript.new()
	var result: Dictionary = next_scheduler.restore_snapshot(snapshot)
	if not result.get("ok", false):
		initialization_error = String(result.get("reason", "scheduler_restore_failed"))
		return result

	var next_tier_state: RefCounted = tier_state
	if next_tier_state == null or not next_tier_state.is_initialized():
		next_tier_state = TierStateScript.new()
		var tier_result: Dictionary = next_tier_state.initialize()
		if not tier_result.get("ok", false):
			initialization_error = String(
				tier_result.get("reason", "simulation_tier_initialization_failed")
			)
			return tier_result

	var next_tier_router: RefCounted = tier_router
	if next_tier_router == null or not next_tier_router.is_initialized():
		next_tier_router = TierRouterScript.new()
		var router_result: Dictionary = next_tier_router.initialize()
		if not router_result.get("ok", false):
			initialization_error = String(
				router_result.get("reason", "simulation_tier_router_initialization_failed")
			)
			return router_result

	var next_environment_store: RefCounted = environment_state_store
	if next_environment_store == null or not next_environment_store.is_initialized():
		next_environment_store = EnvironmentStateStoreScript.new()
		var environment_result: Dictionary = next_environment_store.initialize(
			EnvironmentStateStoreScript.DEFAULT_GRID_WIDTH,
			EnvironmentStateStoreScript.DEFAULT_GRID_HEIGHT,
			int(next_tier_state.get_authoritative_snapshot().get(
				"max_scopes", DEFAULT_MAX_SIMULATION_SCOPES
			))
		)
		if not environment_result.get("ok", false):
			return environment_result

	var next_surface_cache: RefCounted = EnvironmentSurfaceCacheScript.new()
	var surface_cache_result: Dictionary = next_surface_cache.initialize(
		int(next_tier_state.get_authoritative_snapshot().get(
			"max_scopes", DEFAULT_MAX_SIMULATION_SCOPES
		))
	)
	if not surface_cache_result.get("ok", false):
		return surface_cache_result

	if material_bridge != null:
		material_bridge.reset_after_restore()
	material_bridge = null
	if world_scope_lifecycle != null:
		world_scope_lifecycle.reset_transient()
	world_scope_lifecycle = null
	scheduler = next_scheduler
	tier_state = next_tier_state
	tier_router = next_tier_router
	environment_state_store = next_environment_store
	environment_surface_cache = next_surface_cache
	environment_climate_domain = null
	environment_runoff_domain = null
	environment_hydrology_domain = null
	_environment_climate_profile_id = ""
	_environment_climate_profile_sha256 = ""
	_environment_tick_admission_limit = -1
	_fractional_usec = 0.0
	_last_result = {}
	initialization_error = ""
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": scheduler.get_authoritative_snapshot(),
	}


func restore_simulation_tier_snapshot(snapshot: Dictionary) -> Dictionary:
	if not initialized or scheduler == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}

	var next_tier_state: RefCounted = TierStateScript.new()
	var result: Dictionary = next_tier_state.restore_snapshot(snapshot)
	if not result.get("ok", false):
		return result

	if tier_router != null and tier_router.is_initialized():
		var router_snapshot: Dictionary = tier_router.get_authoritative_snapshot()
		var compatibility := _validate_router_scope_compatibility(
			router_snapshot,
			next_tier_state
		)
		if not compatibility.get("ok", false):
			return compatibility
	if environment_state_store != null and environment_state_store.is_initialized():
		var environment_compatibility := _validate_environment_scope_compatibility(
			environment_state_store.get_authoritative_snapshot(),
			next_tier_state
		)
		if not environment_compatibility.get("ok", false):
			return environment_compatibility

	if material_bridge != null:
		material_bridge.reset_after_restore()
	material_bridge = null
	if world_scope_lifecycle != null:
		world_scope_lifecycle.reset_transient()
	world_scope_lifecycle = null
	tier_state = next_tier_state
	if environment_surface_cache != null:
		environment_surface_cache.clear_transient()
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": tier_state.get_authoritative_snapshot(),
	}


func restore_simulation_router_snapshot(snapshot: Dictionary) -> Dictionary:
	if not initialized or scheduler == null or tier_state == null:
		return {"ok": false, "reason": "simulation_runtime_not_initialized"}

	var next_router: RefCounted = TierRouterScript.new()
	var result: Dictionary = next_router.restore_snapshot(snapshot)
	if not result.get("ok", false):
		return result
	var compatibility := _validate_router_scope_compatibility(snapshot, tier_state)
	if not compatibility.get("ok", false):
		return compatibility

	if material_bridge != null:
		material_bridge.reset_after_restore()
	material_bridge = null
	if world_scope_lifecycle != null:
		world_scope_lifecycle.reset_transient()
	world_scope_lifecycle = null
	tier_router = next_router
	_environment_tick_admission_limit = -1
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": tier_router.get_authoritative_snapshot(),
	}


func validate_runtime_snapshot(snapshot: Dictionary) -> Dictionary:
	if typeof(snapshot.get("schema_version")) != TYPE_INT:
		return {"ok": false, "reason": "simulation_runtime_snapshot_schema_invalid"}
	var schema_version := int(snapshot["schema_version"])
	if schema_version == RUNTIME_SNAPSHOT_SCHEMA_V1:
		if not _has_exact_fields(snapshot, RUNTIME_SNAPSHOT_FIELDS_V1):
			return {"ok": false, "reason": "simulation_runtime_snapshot_fields_invalid"}
	elif schema_version == RUNTIME_SNAPSHOT_SCHEMA_V2:
		if not _has_exact_fields(snapshot, RUNTIME_SNAPSHOT_FIELDS_V2):
			return {"ok": false, "reason": "simulation_runtime_snapshot_fields_invalid"}
	elif schema_version == RUNTIME_SNAPSHOT_SCHEMA_VERSION:
		if not _has_exact_fields(snapshot, RUNTIME_SNAPSHOT_FIELDS_V3):
			return {"ok": false, "reason": "simulation_runtime_snapshot_fields_invalid"}
	else:
		return {"ok": false, "reason": "simulation_runtime_snapshot_schema_invalid"}

	if typeof(snapshot.get("fractional_usec")) != TYPE_FLOAT:
		return {"ok": false, "reason": "simulation_runtime_snapshot_fractional_usec_invalid"}
	var fractional_usec := float(snapshot["fractional_usec"])
	if not is_finite(fractional_usec) or fractional_usec < 0.0 or fractional_usec >= 1.0:
		return {"ok": false, "reason": "simulation_runtime_snapshot_fractional_usec_invalid"}
	if typeof(snapshot.get("scheduler")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "simulation_runtime_snapshot_scheduler_invalid"}
	if typeof(snapshot.get("tier_state")) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "simulation_runtime_snapshot_tier_state_invalid"}

	var scheduler_candidate: RefCounted = SchedulerScript.new()
	var scheduler_result: Dictionary = scheduler_candidate.restore_snapshot(
		snapshot["scheduler"]
	)
	if not scheduler_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_scheduler_invalid",
			"detail": String(scheduler_result.get("reason", "")),
		}

	var tier_candidate: RefCounted = TierStateScript.new()
	var tier_result: Dictionary = tier_candidate.restore_snapshot(
		snapshot["tier_state"]
	)
	if not tier_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_tier_state_invalid",
			"detail": String(tier_result.get("reason", "")),
		}

	if schema_version >= RUNTIME_SNAPSHOT_SCHEMA_V2:
		if typeof(snapshot.get("tier_router")) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "simulation_runtime_snapshot_router_invalid"}
		var router_candidate: RefCounted = TierRouterScript.new()
		var router_result: Dictionary = router_candidate.restore_snapshot(
			snapshot["tier_router"]
		)
		if not router_result.get("ok", false):
			return {
				"ok": false,
				"reason": "simulation_runtime_snapshot_router_invalid",
				"detail": String(router_result.get("reason", "")),
			}
		var compatibility := _validate_router_scope_compatibility(
			snapshot["tier_router"],
			tier_candidate
		)
		if not compatibility.get("ok", false):
			return compatibility

	if schema_version == RUNTIME_SNAPSHOT_SCHEMA_VERSION:
		if typeof(snapshot.get("environment_state")) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "simulation_runtime_snapshot_environment_invalid"}
		var environment_candidate: RefCounted = EnvironmentStateStoreScript.new()
		var environment_result: Dictionary = environment_candidate.restore_snapshot(
			snapshot["environment_state"]
		)
		if not environment_result.get("ok", false):
			return {
				"ok": false,
				"reason": "simulation_runtime_snapshot_environment_invalid",
				"detail": String(environment_result.get("reason", "")),
			}
		var environment_compatibility := _validate_environment_scope_compatibility(
			snapshot["environment_state"], tier_candidate
		)
		if not environment_compatibility.get("ok", false):
			return environment_compatibility

	return {"ok": true, "reason": "ok"}


func restore_runtime_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_runtime_snapshot(snapshot)
	if not validation.get("ok", false):
		return validation

	var next_scheduler: RefCounted = SchedulerScript.new()
	var scheduler_result: Dictionary = next_scheduler.restore_snapshot(
		snapshot["scheduler"]
	)
	if not scheduler_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_scheduler_invalid",
		}

	var next_tier_state: RefCounted = TierStateScript.new()
	var tier_result: Dictionary = next_tier_state.restore_snapshot(
		snapshot["tier_state"]
	)
	if not tier_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_tier_state_invalid",
		}

	var next_tier_router: RefCounted = TierRouterScript.new()
	var schema_version := int(snapshot["schema_version"])
	var router_result: Dictionary
	if schema_version == RUNTIME_SNAPSHOT_SCHEMA_V1:
		router_result = next_tier_router.initialize()
	else:
		router_result = next_tier_router.restore_snapshot(snapshot["tier_router"])
	if not router_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_router_invalid",
		}

	var next_environment_store: RefCounted = EnvironmentStateStoreScript.new()
	var next_surface_cache: RefCounted = EnvironmentSurfaceCacheScript.new()
	var surface_cache_result: Dictionary = next_surface_cache.initialize(
		int(snapshot["tier_state"].get("max_scopes", DEFAULT_MAX_SIMULATION_SCOPES))
	)
	if not surface_cache_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_surface_cache_restore_failed",
			"detail": String(surface_cache_result.get("reason", "")),
		}
	var environment_result: Dictionary
	if schema_version < RUNTIME_SNAPSHOT_SCHEMA_VERSION:
		environment_result = next_environment_store.initialize(
			EnvironmentStateStoreScript.DEFAULT_GRID_WIDTH,
			EnvironmentStateStoreScript.DEFAULT_GRID_HEIGHT,
			int(snapshot["tier_state"].get("max_scopes", DEFAULT_MAX_SIMULATION_SCOPES))
		)
	else:
		environment_result = next_environment_store.restore_snapshot(
			snapshot["environment_state"]
		)
	if not environment_result.get("ok", false):
		return {
			"ok": false,
			"reason": "simulation_runtime_snapshot_environment_invalid",
			"detail": String(environment_result.get("reason", "")),
		}

	if material_bridge != null:
		material_bridge.reset_after_restore()
	material_bridge = null
	if world_scope_lifecycle != null:
		world_scope_lifecycle.reset_transient()
	world_scope_lifecycle = null
	scheduler = next_scheduler
	tier_state = next_tier_state
	tier_router = next_tier_router
	environment_state_store = next_environment_store
	environment_surface_cache = next_surface_cache
	environment_climate_domain = null
	environment_runoff_domain = null
	environment_hydrology_domain = null
	_environment_climate_profile_id = ""
	_environment_climate_profile_sha256 = ""
	_environment_tick_admission_limit = -1
	_fractional_usec = float(snapshot["fractional_usec"])
	_last_result = {}
	initialization_error = ""
	initialized = true
	return {
		"ok": true,
		"reason": "ok",
		"snapshot": get_runtime_snapshot(),
		"migrated_from_schema": (
			schema_version
			if schema_version < RUNTIME_SNAPSHOT_SCHEMA_VERSION
			else 0
		),
	}


func _validate_environment_scope_compatibility(
	environment_snapshot: Dictionary,
	candidate_tier_state: RefCounted
) -> Dictionary:
	var scopes: Array = environment_snapshot.get("scopes", [])
	for record_value in scopes:
		var record: Dictionary = record_value
		var scope_id := String(record.get("scope_id", ""))
		if candidate_tier_state.get_scope(scope_id).is_empty():
			return {
				"ok": false,
				"reason": "simulation_runtime_snapshot_environment_scope_missing",
				"scope_id": scope_id,
			}
	return {"ok": true, "reason": "ok"}


func _validate_router_scope_compatibility(
	router_snapshot: Dictionary,
	candidate_tier_state: RefCounted
) -> Dictionary:
	var observations: Array = router_snapshot.get("observations", [])
	for observation_value in observations:
		var observation: Dictionary = observation_value
		var scope_id := String(observation.get("scope_id", ""))
		if candidate_tier_state.get_scope(scope_id).is_empty():
			return {
				"ok": false,
				"reason": "simulation_runtime_snapshot_router_scope_missing",
				"scope_id": scope_id,
			}
	return {"ok": true, "reason": "ok"}


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_value in fields:
		if not value.has(String(field_value)):
			return false
	return true
