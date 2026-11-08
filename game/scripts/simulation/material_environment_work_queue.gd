extends RefCounted
class_name MaterialEnvironmentWorkQueue

## Explicit, bounded logical-tick admission. No world enumeration or frame joins.
## FIFO ring buffer avoids O(backlog) Array.pop_front() during gameplay.
const DomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const PerformanceTrace := preload("res://scripts/diagnostics/performance_trace.gd")

const DEFAULT_BUDGET := 32
const HARD_MAX_BUDGET := 4096
const DEFAULT_CAPACITY := 8192
const HARD_MAX_CAPACITY := 65536

var _domain: MaterialEnvironmentDomain
var _slots: Array = []
var _index: Dictionary = {}
var _read := 0
var _write := 0
var _count := 0
var _budget := DEFAULT_BUDGET
var _capacity := DEFAULT_CAPACITY
var _submissions := 0
var _accepted := 0
var _deduplicated := 0
var _processed_total := 0
var _deferred_total := 0
var _failed_batches := 0
var _trace := false


func initialize(
	domain: MaterialEnvironmentDomain,
	max_per_call: int = DEFAULT_BUDGET,
	max_pending: int = DEFAULT_CAPACITY
) -> Dictionary:
	if _domain != null:
		return {"ok": false, "reason": "material_queue_already_initialized"}
	if domain == null:
		return {"ok": false, "reason": "material_domain_missing"}
	if max_per_call < 1 or max_per_call > HARD_MAX_BUDGET:
		return {"ok": false, "reason": "material_queue_budget_invalid"}
	if max_pending < 1 or max_pending > HARD_MAX_CAPACITY:
		return {"ok": false, "reason": "material_queue_capacity_invalid"}
	_domain = domain
	_budget = max_per_call
	_capacity = max_pending
	_slots.resize(_capacity)
	_trace = PerformanceTrace.is_enabled()
	return {"ok": true, "reason": "ok"}


func enqueue(
	tier_state: SimulationTierState, scope_id: String,
	profile_id: String, logical_tick: int
) -> Dictionary:
	if _domain == null:
		return {"ok": false, "reason": "material_queue_not_initialized"}
	_submissions += 1
	if logical_tick < 0:
		return {"ok": false, "reason": "material_queue_tick_invalid"}
	if tier_state == null or tier_state.get_scope(scope_id).is_empty():
		return {"ok": false, "reason": "simulation_scope_not_found"}
	if not _domain.has_bound_profile(profile_id):
		return {"ok": false, "reason": "material_profile_not_bound"}
	var key := "%d:%s:%s" % [logical_tick, scope_id, profile_id]
	if _index.has(key):
		_deduplicated += 1
		return {"ok": true, "reason": "ok", "noop": true, "pending_count": _count}
	if _count >= _capacity:
		return {"ok": false, "reason": "material_queue_capacity_reached", "pending_count": _count}
	_slots[_write] = {
		"key": key, "scope_id": scope_id, "profile_id": profile_id, "logical_tick": logical_tick,
	}
	_index[key] = true
	_write = (_write + 1) % _capacity
	_count += 1
	_accepted += 1
	return {"ok": true, "reason": "ok", "noop": false, "pending_count": _count}


func process_pending(tier_state: SimulationTierState, requested_budget: int = -1) -> Dictionary:
	if _domain == null:
		return {"ok": false, "reason": "material_queue_not_initialized"}
	if tier_state == null or not tier_state.is_initialized():
		return {"ok": false, "reason": "material_tier_state_unavailable"}
	if requested_budget == 0 or requested_budget < -1 or requested_budget > _budget:
		return {"ok": false, "reason": "material_queue_budget_invalid"}
	var limit := _budget if requested_budget == -1 else requested_budget
	var started_usec := Time.get_ticks_usec() if _trace else 0
	var receipts: Array = []
	for _i in range(mini(limit, _count)):
		var item: Dictionary = _slots[_read]
		var result: Dictionary = _domain.process_bound_due_scope(
			tier_state, String(item["scope_id"]), String(item["profile_id"]), int(item["logical_tick"])
		)
		if not result.get("ok", false):
			_failed_batches += 1
			return {
				"ok": false, "reason": "material_queue_update_failed",
				"detail": String(result.get("reason", "")),
				"processed": receipts, "pending_count": _count,
			}
		receipts.append({
			"scope_id": item["scope_id"], "logical_tick": item["logical_tick"],
			"due": bool(result.get("due", false)),
			"noop": bool(result.get("noop", false)),
		})
		_index.erase(item["key"])
		_slots[_read] = null
		_read = (_read + 1) % _capacity
		_count -= 1
	_processed_total += receipts.size()
	_deferred_total += _count
	if _trace and (receipts.size() > 0 or _count > 0):
		PerformanceTrace.emit_duration(
			"material_environment_batch", started_usec,
			{"processed_count": receipts.size(), "pending_count": _count,
			 "budget": limit, "bound_updates_total": _domain.get_binding_metrics()["bound_update_calls_total"]},
			true
		)
	return {
		"ok": true, "reason": "ok", "processed": receipts,
		"processed_count": receipts.size(), "pending_count": _count,
		"budget": limit,
	}


func get_metrics() -> Dictionary:
	return {
		"pending_count": _count, "capacity": _capacity, "budget": _budget,
		"submissions_total": _submissions, "accepted_total": _accepted,
		"deduplicated_total": _deduplicated, "processed_total": _processed_total,
		"deferred_total": _deferred_total, "failed_batches": _failed_batches,
	}
