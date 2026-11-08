extends RefCounted
class_name MaterialEnvironmentRuntimeBridge

## P4.0E non-rendering bridge between P4.0A/B/C and P4.0D.
## Every admitted item comes from an explicit caller-supplied scope ID.
## Shared FIFO budget covers registration, material initialization and due updates.
const DomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const QueueScript := preload("res://scripts/simulation/material_environment_work_queue.gd")
const TierStateScript := preload("res://scripts/simulation/simulation_tier_state.gd")

var _domain: RefCounted
var _queue: RefCounted
var _enabled := false
var _last_frame_index := -1


func configure(
	registry: RefCounted,
	profile_id: String,
	budget_per_frame: int = QueueScript.DEFAULT_BUDGET,
	queue_capacity: int = QueueScript.DEFAULT_CAPACITY
) -> Dictionary:
	if _enabled:
		return {"ok": false, "reason": "material_bridge_already_configured"}
	if registry == null:
		return {"ok": false, "reason": "material_registry_unavailable"}
	var next_domain: RefCounted = DomainScript.new()
	var bind: Dictionary = next_domain.bind_registry_profile(registry, profile_id)
	if not bind.get("ok", false):
		return bind
	var next_queue: RefCounted = QueueScript.new()
	var setup: Dictionary = next_queue.initialize(next_domain, budget_per_frame, queue_capacity)
	if not setup.get("ok", false):
		return setup
	_domain = next_domain
	_queue = next_queue
	_enabled = true
	_last_frame_index = -1
	return {"ok": true, "reason": "ok"}


func is_enabled() -> bool:
	return _enabled


func register_scope(
	tier_state: RefCounted, scope_id: String,
	initial_tier: String = TierStateScript.TIER_DORMANT
) -> Dictionary:
	if not _enabled:
		return {"ok": false, "reason": "material_bridge_not_configured"}
	return _queue.enqueue_scope_registration(tier_state, scope_id, initial_tier)


func initialize_scope(
	tier_state: RefCounted, scope_id: String,
	profile_id: String, temperature_milli_c: int
) -> Dictionary:
	if not _enabled:
		return {"ok": false, "reason": "material_bridge_not_configured"}
	return _queue.enqueue_initialization(
		tier_state, scope_id, profile_id, temperature_milli_c
	)


func submit_due(
	tier_state: RefCounted, scope_id: String,
	profile_id: String, logical_tick: int
) -> Dictionary:
	if not _enabled:
		return {"ok": false, "reason": "material_bridge_not_configured"}
	return _queue.enqueue(tier_state, scope_id, profile_id, logical_tick)


func process_frame(
	tier_state: RefCounted, frame_index: int
) -> Dictionary:
	if not _enabled:
		return {"ok": false, "reason": "material_bridge_not_configured"}
	var result: Dictionary = _queue.process_pending(tier_state, frame_index)
	if result.get("ok", false):
		_last_frame_index = frame_index
	return result


func reset_after_restore() -> void:
	# Pending work references old authority and is disposable. Old registry
	# bindings must not survive a world restore or content package reload.
	_enabled = false
	_queue = null
	if _domain != null:
		_domain.clear_profile_bindings()
	_domain = null
	_last_frame_index = -1


func get_metrics() -> Dictionary:
	if not _enabled:
		return {"enabled": false}
	return {
		"enabled": true, "last_frame_index": _last_frame_index,
		"queue": _queue.get_metrics(),
		"bindings": _domain.get_binding_metrics(),
	}
