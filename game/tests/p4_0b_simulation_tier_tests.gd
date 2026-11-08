extends SceneTree

const TierStateScript := preload("res://scripts/simulation/simulation_tier_state.gd")
const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_configuration_and_registration()
	_test_transition_roundtrip_conservation()
	_test_state_revision_and_copy_isolation()
	_test_tier_cadence_determinism()
	_test_snapshot_restore()
	_test_runtime_integration_and_atomic_restore()
	_test_playable_scene_surface()

	if failures == 0:
		print("P4_0B_TIER_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error(
			"P4_0B_TIER_FAIL: assertions=%d failures=%d"
			% [assertions, failures]
		)
	quit(0 if failures == 0 else 1)


func _test_configuration_and_registration() -> void:
	var uninitialized: SimulationTierState = TierStateScript.new()
	_check(
		uninitialized.register_scope("scope", "active").get("reason", "")
			== "simulation_tier_state_not_initialized",
		"scope registration requires initialized tier authority"
	)

	var bad_interval: SimulationTierState = TierStateScript.new()
	_check(
		bad_interval.initialize(1, 8).get("reason", "")
			== "aggregate_interval_ticks_invalid",
		"aggregate cadence must be coarser than active cadence"
	)

	var bad_capacity: SimulationTierState = TierStateScript.new()
	_check(
		bad_capacity.initialize(10, 0).get("reason", "")
			== "max_simulation_scopes_invalid",
		"simulation scope capacity has an explicit positive bound"
	)

	var state: SimulationTierState = TierStateScript.new()
	_check(
		state.initialize(10, 2).get("ok", false),
		"valid tier authority configuration initializes"
	)

	var payload := {
		"mass": 12.5,
		"position": Vector3(1.0, 2.0, 3.0),
		"nested": {"count": 3},
		"samples": [1, 2, 3],
	}
	var registered: Dictionary = state.register_scope("scope-a", "active", payload)
	_check(
		registered.get("ok", false)
			and String(registered["record"]["tier"]) == "active",
		"scope registration stores legal tier and data-only state"
	)

	payload["mass"] = 999.0
	payload["nested"]["count"] = 999
	var stored: Dictionary = state.get_scope("scope-a")
	_check(
		float(stored["state"]["mass"]) == 12.5
			and int(stored["state"]["nested"]["count"]) == 3,
		"registration deep-copies caller state"
	)

	_check(
		state.register_scope("scope-a", "active").get("reason", "")
			== "simulation_scope_already_registered",
		"duplicate stable scope identity is rejected"
	)
	_check(
		state.register_scope(" scope-b", "active").get("reason", "")
			== "simulation_scope_id_invalid",
		"scope identity rejects leading or trailing whitespace"
	)
	_check(
		state.register_scope("scope-b", "invalid").get("reason", "")
			== "simulation_tier_invalid",
		"registration rejects unknown tier"
	)

	var unsafe_payload := {"object": RefCounted.new()}
	_check(
		state.register_scope("scope-b", "dormant", unsafe_payload).get("reason", "")
			== "simulation_state_payload_invalid",
		"state payload rejects executable or object references"
	)
	unsafe_payload["object"] = null

	_check(
		state.register_scope("scope-b", "dormant", {"mass": 4}).get("ok", false),
		"second scope registers within configured capacity"
	)
	_check(
		state.register_scope("scope-c", "aggregate").get("reason", "")
			== "simulation_scope_limit_reached",
		"scope capacity fails closed instead of growing without bound"
	)

	var counts: Dictionary = state.get_tier_counts()
	_check(
		int(counts["active"]) == 1
			and int(counts["aggregate"]) == 0
			and int(counts["dormant"]) == 1,
		"tier counts are direct bounded registry metadata"
	)


func _test_transition_roundtrip_conservation() -> void:
	var state: SimulationTierState = _new_tier_state(10, 16)
	var conserved := {
		"mass": 8.25,
		"energy": 17,
		"flags": ["a", "b"],
	}
	_check(
		state.register_scope("conserved", "active", conserved).get("ok", false),
		"roundtrip fixture registers active scope"
	)

	var before: Dictionary = state.get_scope("conserved")
	var noop: Dictionary = state.transition_scope("conserved", "active", 1, 0)
	_check(
		noop.get("ok", false)
			and noop.get("noop", false)
			and int(noop["record"]["tier_revision"]) == 0,
		"same-tier transition is idempotent and revision-neutral"
	)

	var conflict: Dictionary = state.transition_scope(
		"conserved", "aggregate", 2, 7
	)
	_check(
		conflict.get("reason", "") == "simulation_tier_revision_conflict"
			and state.get_scope("conserved") == before,
		"tier revision mismatch rejects without authoritative mutation"
	)

	var to_aggregate: Dictionary = state.transition_scope(
		"conserved", "aggregate", 2, 0
	)
	_check(
		to_aggregate.get("ok", false)
			and not to_aggregate.get("noop", true)
			and int(to_aggregate["record"]["tier_revision"]) == 1,
		"active to aggregate transition commits one tier revision"
	)

	var to_dormant: Dictionary = state.transition_scope(
		"conserved", "dormant", 3, 1
	)
	_check(
		to_dormant.get("ok", false)
			and int(to_dormant["record"]["tier_revision"]) == 2,
		"aggregate to dormant transition is revision gated"
	)

	var to_active: Dictionary = state.transition_scope(
		"conserved", "active", 4, 2
	)
	var after: Dictionary = state.get_scope("conserved")
	_check(
		to_active.get("ok", false)
			and String(after["tier"]) == "active"
			and int(after["tier_revision"]) == 3
			and int(after["last_transition_tick"]) == 4,
		"dormant to active completes explicit tier roundtrip"
	)
	_check(
		after["state"] == before["state"]
			and int(after["state_revision"]) == int(before["state_revision"]),
		"tier roundtrip conserves state payload and state revision exactly"
	)

	var counts: Dictionary = state.get_tier_counts()
	_check(
		int(counts["active"]) == 1
			and int(counts["aggregate"]) == 0
			and int(counts["dormant"]) == 0,
		"tier indexes remain balanced after roundtrip"
	)


func _test_state_revision_and_copy_isolation() -> void:
	var state: SimulationTierState = _new_tier_state(10, 8)
	_check(
		state.register_scope(
			"stateful", "aggregate", {"mass": 2, "nested": {"value": 5}}
		).get("ok", false),
		"state mutation fixture registers"
	)

	var conflict: Dictionary = state.replace_scope_state(
		"stateful", {"mass": 3}, 5
	)
	_check(
		conflict.get("reason", "") == "simulation_state_revision_conflict"
			and int(state.get_scope("stateful")["state_revision"]) == 0,
		"state revision conflict fails without mutation"
	)

	var same: Dictionary = state.replace_scope_state(
		"stateful", {"mass": 2, "nested": {"value": 5}}, 0
	)
	_check(
		same.get("ok", false)
			and same.get("noop", false)
			and int(same["record"]["state_revision"]) == 0,
		"identical state replacement is idempotent"
	)

	var replaced: Dictionary = state.replace_scope_state(
		"stateful", {"mass": 3, "nested": {"value": 6}}, 0
	)
	_check(
		replaced.get("ok", false)
			and int(replaced["record"]["state_revision"]) == 1
			and int(replaced["record"]["tier_revision"]) == 0,
		"state replacement increments only state revision"
	)

	var returned: Dictionary = state.get_scope("stateful")
	returned["state"]["mass"] = 1000
	returned["state"]["nested"]["value"] = 1000
	var stored: Dictionary = state.get_scope("stateful")
	_check(
		int(stored["state"]["mass"]) == 3
			and int(stored["state"]["nested"]["value"]) == 6,
		"scope reads return isolated copies rather than mutable authority"
	)


func _test_tier_cadence_determinism() -> void:
	var first: SimulationTierState = _new_tier_state(7, 16)
	_check(first.register_scope("active-scope", "active").get("ok", false), "active cadence fixture registers")
	_check(first.register_scope("dormant-scope", "dormant").get("ok", false), "dormant cadence fixture registers")
	_check(first.register_scope("aggregate-scope", "aggregate").get("ok", false), "aggregate cadence fixture registers")

	var aggregate_record: Dictionary = first.get_scope("aggregate-scope")
	var phase := int(aggregate_record["aggregate_phase"])
	_check(
		phase >= 0 and phase < 7,
		"aggregate scope receives stable bounded cadence phase"
	)

	var aggregate_due_count := 0
	var all_active_due := true
	var any_dormant_due := false
	var aggregate_matches_formula := true
	for tick in range(28):
		var active_due: Dictionary = first.get_due_decision("active-scope", tick)
		var dormant_due: Dictionary = first.get_due_decision("dormant-scope", tick)
		var aggregate_due: Dictionary = first.get_due_decision("aggregate-scope", tick)
		all_active_due = all_active_due and bool(active_due.get("due", false))
		any_dormant_due = any_dormant_due or bool(dormant_due.get("due", false))
		var expected := tick % 7 == phase
		aggregate_matches_formula = (
			aggregate_matches_formula
			and bool(aggregate_due.get("due", false)) == expected
		)
		if bool(aggregate_due.get("due", false)):
			aggregate_due_count += 1

	_check(all_active_due, "active tier is due on every logical tick")
	_check(not any_dormant_due, "dormant tier is never due")
	_check(
		aggregate_matches_formula and aggregate_due_count == 4,
		"aggregate tier is due exactly once per configured interval"
	)

	var second: SimulationTierState = _new_tier_state(7, 16)
	_check(second.register_scope("other", "active").get("ok", false), "order-independence fixture registers unrelated scope")
	_check(second.register_scope("aggregate-scope", "aggregate").get("ok", false), "order-independence fixture registers aggregate scope")
	_check(
		int(second.get_scope("aggregate-scope")["aggregate_phase"]) == phase,
		"aggregate phase is independent of registration order"
	)

	var same_decisions := true
	for tick in range(28):
		same_decisions = (
			same_decisions
			and bool(first.get_due_decision("aggregate-scope", tick)["due"])
				== bool(second.get_due_decision("aggregate-scope", tick)["due"])
		)
	_check(
		same_decisions,
		"aggregate future due decisions are deterministic across equivalent registries"
	)


func _test_snapshot_restore() -> void:
	var original: SimulationTierState = _new_tier_state(5, 10)
	_check(original.register_scope("b", "dormant", {"mass": 2}).get("ok", false), "snapshot fixture registers b")
	_check(original.register_scope("a", "active", {"mass": 1}).get("ok", false), "snapshot fixture registers a")
	_check(original.transition_scope("b", "aggregate", 7, 0).get("ok", false), "snapshot fixture transitions b")
	_check(original.replace_scope_state("a", {"mass": 3}, 0).get("ok", false), "snapshot fixture updates a")

	var snapshot: Dictionary = original.get_authoritative_snapshot()
	var scopes: Array = snapshot["scopes"]
	_check(
		String(scopes[0]["scope_id"]) == "a"
			and String(scopes[1]["scope_id"]) == "b",
		"snapshot serializes scopes in deterministic identity order"
	)

	var restored: SimulationTierState = TierStateScript.new()
	var restore_result: Dictionary = restored.restore_snapshot(snapshot)
	_check(
		restore_result.get("ok", false)
			and restored.get_authoritative_snapshot() == snapshot,
		"tier snapshot restores exact authoritative state"
	)

	var same_future := true
	for tick in range(25):
		for scope_id in ["a", "b"]:
			same_future = (
				same_future
				and bool(original.get_due_decision(scope_id, tick)["due"])
					== bool(restored.get_due_decision(scope_id, tick)["due"])
			)
	_check(
		same_future,
		"restored tier authority reproduces future due decisions"
	)

	var unknown := snapshot.duplicate(true)
	unknown["unexpected"] = true
	var validator: SimulationTierState = TierStateScript.new()
	_check(
		validator.validate_snapshot(unknown).get("reason", "")
			== "simulation_tier_snapshot_fields_invalid",
		"snapshot rejects unknown top-level fields"
	)

	var duplicate := snapshot.duplicate(true)
	duplicate["scopes"].append(duplicate["scopes"][0].duplicate(true))
	_check(
		validator.validate_snapshot(duplicate).get("reason", "")
			== "simulation_tier_snapshot_duplicate_scope",
		"snapshot rejects duplicate scope identities"
	)

	var unsafe := snapshot.duplicate(true)
	unsafe["scopes"][0]["state"] = {"object": RefCounted.new()}
	_check(
		validator.validate_snapshot(unsafe).get("reason", "")
			== "simulation_tier_snapshot_state_invalid",
		"snapshot rejects non-data state payload"
	)

	var failed_restore: SimulationTierState = TierStateScript.new()
	_check(
		not failed_restore.restore_snapshot(unsafe).get("ok", false)
			and not failed_restore.is_initialized(),
		"invalid snapshot fails without partially initializing authority"
	)
	unsafe["scopes"][0]["state"] = {}


func _test_runtime_integration_and_atomic_restore() -> void:
	var runtime: SimulationRuntime = RuntimeScript.new()
	_check(
		runtime.initialize_runtime(1000, 4, 0, false, 5, 32).get("ok", false),
		"runtime initializes scheduler and tier authority atomically"
	)
	_check(
		runtime.register_simulation_scope(
			"runtime-scope", "active", {"mass": 11}
		).get("ok", false),
		"runtime exposes stable scope registration"
	)

	var active_due: Dictionary = runtime.get_simulation_due_decision(
		"runtime-scope", 0
	)
	_check(
		active_due.get("ok", false) and active_due.get("due", false),
		"runtime exposes direct due decision without world scan"
	)

	var fractional: Dictionary = runtime.process_delta_seconds(0.0000005)
	_check(
		fractional.get("ok", false)
			and int(fractional.get("current_tick", -1)) == 0,
		"runtime retains sub-microsecond adapter carry before snapshot"
	)

	var transitioned: Dictionary = runtime.transition_simulation_scope(
		"runtime-scope", "aggregate", 0
	)
	_check(
		transitioned.get("ok", false)
			and int(transitioned["record"]["tier_revision"]) == 1,
		"runtime transition commits at current logical tick"
	)

	var progressed: Dictionary = runtime.process_elapsed_usec(5000)
	_check(
		progressed.get("ok", false)
			and int(progressed.get("current_tick", -1)) == 4
			and int(progressed.get("backlog_ticks", -1)) == 1,
		"runtime preserves P4.0A bounded scheduler behavior with tier authority mounted"
	)

	var snapshot: Dictionary = runtime.get_runtime_snapshot()
	_check(
		float(snapshot["fractional_usec"]) == 0.5
			and int(snapshot["scheduler"]["current_tick"]) == 4
			and String(snapshot["tier_state"]["scopes"][0]["tier"]) == "aggregate",
		"combined runtime snapshot captures adapter, scheduler and tier authority"
	)

	var restored: SimulationRuntime = RuntimeScript.new()
	var restored_result: Dictionary = restored.restore_runtime_snapshot(snapshot)
	_check(
		restored_result.get("ok", false)
			and restored.get_runtime_snapshot() == snapshot,
		"combined runtime snapshot restores exact scheduler and tier authority"
	)

	var same_future := true
	for tick in range(20):
		same_future = (
			same_future
			and bool(runtime.get_simulation_due_decision("runtime-scope", tick)["due"])
				== bool(restored.get_simulation_due_decision("runtime-scope", tick)["due"])
		)
	_check(
		same_future,
		"combined restore preserves future tier cadence decisions"
	)

	var prior: Dictionary = restored.get_runtime_snapshot()
	var invalid := prior.duplicate(true)
	invalid["tier_state"]["scopes"][0]["tier"] = "invalid"
	var rejected: Dictionary = restored.restore_runtime_snapshot(invalid)
	_check(
		rejected.get("reason", "")
			== "simulation_runtime_snapshot_tier_state_invalid"
			and restored.get_runtime_snapshot() == prior,
		"combined runtime restore rejects invalid tier snapshot atomically"
	)

	var tier_metrics: Dictionary = restored.get_simulation_tier_metrics()
	_check(
		int(tier_metrics["scope_count"]) == 1
			and int(tier_metrics["tier_counts"]["aggregate"]) == 1,
		"runtime exposes bounded tier telemetry without mutable authority"
	)

	runtime.free()
	restored.free()


func _test_playable_scene_surface() -> void:
	var packed: PackedScene = load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "playable scene loads with P4.0B runtime")
	if packed == null:
		return

	var scene: Node = packed.instantiate()
	_check(scene.has_node("SimulationRuntime"), "playable scene retains one SimulationRuntime")
	if scene.has_node("SimulationRuntime"):
		var runtime_node: Node = scene.get_node("SimulationRuntime")
		_check(
			runtime_node.has_method("register_simulation_scope")
				and runtime_node.has_method("transition_simulation_scope")
				and runtime_node.has_method("get_simulation_due_decision")
				and runtime_node.has_method("get_runtime_snapshot")
				and runtime_node.has_method("restore_runtime_snapshot"),
			"playable runtime exposes tier/state foundation without domain simulation"
		)
	scene.free()


func _new_tier_state(
	aggregate_interval_ticks: int,
	max_scopes: int
) -> SimulationTierState:
	var state: SimulationTierState = TierStateScript.new()
	var result: Dictionary = state.initialize(
		aggregate_interval_ticks, max_scopes
	)
	_check(
		result.get("ok", false),
		"tier-state fixture initializes (%s)" % result.get("reason", "ok")
	)
	return state


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)
