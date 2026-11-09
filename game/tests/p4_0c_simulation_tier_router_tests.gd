extends SceneTree

const TierStateScript := preload("res://scripts/simulation/simulation_tier_state.gd")
const TierRouterScript := preload("res://scripts/simulation/simulation_tier_router.gd")
const RuntimeScript := preload("res://scripts/simulation/simulation_runtime.gd")

var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_configuration_and_observation_contract()
	_test_bounded_fifo_and_deduplication()
	_test_hysteresis_and_state_conservation()
	_test_deterministic_equivalent_streams()
	_test_snapshot_restore_and_preflight()
	_test_runtime_integration_and_schema_migration()
	_test_playable_scene_surface()

	if failures == 0:
		print("P4_0C_ROUTER_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error(
			"P4_0C_ROUTER_FAIL: assertions=%d failures=%d"
			% [assertions, failures]
		)
	quit(0 if failures == 0 else 1)


func _test_configuration_and_observation_contract() -> void:
	var invalid: SimulationTierRouter = TierRouterScript.new()
	_check(
		invalid.initialize(40, 30, 100, 120, 4, 8).get("reason", "")
			== "simulation_router_thresholds_invalid",
		"router rejects inverted active hysteresis"
	)

	var invalid_gap: SimulationTierRouter = TierRouterScript.new()
	_check(
		invalid_gap.initialize(30, 40, 35, 120, 4, 8).get("reason", "")
			== "simulation_router_thresholds_invalid",
		"aggregate enter must not overlap inside active exit"
	)

	var invalid_budget: SimulationTierRouter = TierRouterScript.new()
	_check(
		invalid_budget.initialize(10, 20, 30, 40, 0, 8).get("reason", "")
			== "simulation_router_decision_budget_invalid",
		"router requires positive hard decision budget"
	)

	var router: SimulationTierRouter = _new_router(10, 20, 50, 60, 2, 2)
	var tiers: SimulationTierState = _new_tiers()
	_check(
		tiers.register_scope("a", "dormant", {"mass": 5}).get("ok", false),
		"observation fixture scope a registers"
	)
	_check(
		tiers.register_scope("b", "dormant", {"mass": 6}).get("ok", false),
		"observation fixture scope b registers"
	)

	_check(
		router.submit_observation("missing", 10, tiers).get("reason", "")
			== "simulation_scope_not_found"
			and router.get_pending_count() == 0,
		"unknown scope observation is rejected without queue mutation"
	)
	_check(
		router.submit_observation("a", -1, tiers).get("reason", "")
			== "simulation_router_distance_invalid",
		"negative deterministic distance is rejected"
	)
	_check(
		router.submit_observation(" a", 10, tiers).get("reason", "")
			== "simulation_router_scope_id_invalid",
		"router reuses exact stable scope identity constraints"
	)

	var first: Dictionary = router.submit_observation("a", 42, tiers)
	_check(
		first.get("ok", false)
			and not first.get("noop", true)
			and int(first["observation"]["observation_revision"]) == 0
			and router.get_pending_count() == 1,
		"first valid observation creates revision zero and queues once"
	)

	var same: Dictionary = router.submit_observation("a", 42, tiers)
	_check(
		same.get("ok", false)
			and same.get("noop", false)
			and router.get_pending_count() == 1,
		"identical observation is idempotent and does not duplicate dirty work"
	)

	var changed: Dictionary = router.submit_observation("a", 41, tiers)
	_check(
		changed.get("ok", false)
			and int(changed["observation"]["observation_revision"]) == 1
			and router.get_pending_count() == 1,
		"changed pending observation advances revision without duplicating queue entry"
	)

	_check(
		router.submit_observation("b", 55, tiers).get("ok", false)
			and router.get_pending_count() == 2,
		"second observation fills configured tracking capacity"
	)

	var tiers_extra: SimulationTierState = _new_tiers()
	_check(
		tiers_extra.register_scope("a", "dormant").get("ok", false)
			and tiers_extra.register_scope("b", "dormant").get("ok", false)
			and tiers_extra.register_scope("c", "dormant").get("ok", false),
		"capacity fixture registers three tier scopes"
	)
	var capacity_router: SimulationTierRouter = _new_router(10, 20, 50, 60, 2, 2)
	_check(capacity_router.submit_observation("a", 10, tiers_extra).get("ok", false), "capacity router tracks first scope")
	_check(capacity_router.submit_observation("b", 10, tiers_extra).get("ok", false), "capacity router tracks second scope")
	_check(
		capacity_router.submit_observation("c", 10, tiers_extra).get("reason", "")
			== "simulation_router_observation_limit_reached",
		"tracked observation capacity is hard bounded"
	)


func _test_bounded_fifo_and_deduplication() -> void:
	var tiers: SimulationTierState = _new_tiers()
	for scope_id in ["a", "b", "c", "d"]:
		_check(
			tiers.register_scope(scope_id, "dormant").get("ok", false),
			"FIFO fixture registers " + scope_id
		)

	var router: SimulationTierRouter = _new_router(10, 20, 50, 60, 2, 8)
	_check(router.submit_observation("a", 5, tiers).get("ok", false), "FIFO queues a")
	_check(router.submit_observation("b", 30, tiers).get("ok", false), "FIFO queues b")
	_check(router.submit_observation("c", 55, tiers).get("ok", false), "FIFO queues c")
	_check(router.submit_observation("d", 70, tiers).get("ok", false), "FIFO queues d")

	var first_batch: Dictionary = router.process_pending(tiers, 3)
	var processed: Array = first_batch.get("processed", [])
	_check(
		first_batch.get("ok", false)
			and int(first_batch.get("processed_count", -1)) == 2
			and int(first_batch.get("pending_count", -1)) == 2,
		"default processing is capped by configured max decisions"
	)
	_check(
		String(processed[0]["scope_id"]) == "a"
			and String(processed[1]["scope_id"]) == "b",
		"dirty queue processing order is deterministic FIFO"
	)
	_check(
		String(tiers.get_scope("a")["tier"]) == "active"
			and String(tiers.get_scope("b")["tier"]) == "aggregate",
		"first bounded batch applies expected tier classifications"
	)
	_check(
		String(tiers.get_scope("c")["tier"]) == "dormant"
			and String(tiers.get_scope("d")["tier"]) == "dormant",
		"unprocessed dirty scopes remain untouched"
	)

	_check(
		router.process_pending(tiers, 3, 3).get("reason", "")
			== "simulation_router_budget_exceeds_configured_max",
		"caller cannot bypass configured routing budget"
	)

	var second_batch: Dictionary = router.process_pending(tiers, 4, 1)
	_check(
		second_batch.get("ok", false)
			and int(second_batch["processed_count"]) == 1
			and String(second_batch["processed"][0]["scope_id"]) == "c"
			and router.get_pending_count() == 1,
		"caller may request a smaller bounded budget"
	)

	var third_batch: Dictionary = router.process_pending(tiers, 5)
	_check(
		third_batch.get("ok", false)
			and int(third_batch["processed_count"]) == 1
			and String(third_batch["processed"][0]["scope_id"]) == "d"
			and router.get_pending_count() == 0,
		"remaining FIFO work drains without synthetic iterations"
	)

	var metrics: Dictionary = router.get_metrics()
	_check(
		int(metrics["peak_pending_count"]) == 4
			and int(metrics["decisions_total"]) == 4,
		"router telemetry records bounded queue pressure and actual decisions"
	)


func _test_hysteresis_and_state_conservation() -> void:
	var tiers: SimulationTierState = _new_tiers()
	_check(
		tiers.register_scope("scope", "dormant", {"mass": 9, "energy": 3}).get("ok", false),
		"hysteresis fixture registers conserved state"
	)
	var router: SimulationTierRouter = _new_router(10, 20, 50, 60, 8, 8)
	var initial: Dictionary = tiers.get_scope("scope")

	_check(router.submit_observation("scope", 50, tiers).get("ok", false), "dormant observation reaches aggregate enter boundary")
	_check(router.process_pending(tiers, 1).get("ok", false), "dormant boundary route processes")
	_check(
		String(tiers.get_scope("scope")["tier"]) == "aggregate",
		"dormant enters aggregate at aggregate-enter boundary"
	)

	_check(router.submit_observation("scope", 19, tiers).get("ok", false), "aggregate observation enters active-exit band")
	_check(router.process_pending(tiers, 2).get("ok", false), "aggregate hysteresis route processes")
	_check(
		String(tiers.get_scope("scope")["tier"]) == "aggregate",
		"aggregate does not promote inside active exit band until active-enter is crossed"
	)

	_check(router.submit_observation("scope", 10, tiers).get("ok", false), "aggregate reaches active enter boundary")
	_check(router.process_pending(tiers, 3).get("ok", false), "active promotion route processes")
	_check(
		String(tiers.get_scope("scope")["tier"]) == "active",
		"aggregate promotes at active-enter boundary"
	)

	_check(router.submit_observation("scope", 20, tiers).get("ok", false), "active reaches active exit boundary")
	_check(router.process_pending(tiers, 4).get("ok", false), "active boundary route processes")
	_check(
		String(tiers.get_scope("scope")["tier"]) == "active",
		"active remains active through active-exit boundary"
	)

	_check(router.submit_observation("scope", 21, tiers).get("ok", false), "active crosses active exit")
	_check(router.process_pending(tiers, 5).get("ok", false), "active demotion route processes")
	_check(
		String(tiers.get_scope("scope")["tier"]) == "aggregate",
		"active demotes to aggregate only after active-exit is crossed"
	)

	_check(router.submit_observation("scope", 55, tiers).get("ok", false), "aggregate remains inside aggregate exit")
	_check(router.process_pending(tiers, 6).get("ok", false), "aggregate hold route processes")
	_check(
		String(tiers.get_scope("scope")["tier"]) == "aggregate",
		"aggregate remains aggregate through hysteresis band"
	)

	_check(router.submit_observation("scope", 61, tiers).get("ok", false), "aggregate crosses aggregate exit")
	_check(router.process_pending(tiers, 7).get("ok", false), "dormant demotion route processes")
	var final_record: Dictionary = tiers.get_scope("scope")
	_check(
		String(final_record["tier"]) == "dormant",
		"aggregate demotes to dormant only after aggregate-exit is crossed"
	)
	_check(
		final_record["state"] == initial["state"]
			and int(final_record["state_revision"]) == int(initial["state_revision"]),
		"automatic routing preserves domain state and state revision exactly"
	)


func _test_deterministic_equivalent_streams() -> void:
	var first_tiers: SimulationTierState = _new_tiers()
	var second_tiers: SimulationTierState = _new_tiers()
	for scope_id in ["north", "south", "east"]:
		_check(
			first_tiers.register_scope(scope_id, "dormant").get("ok", false)
				and second_tiers.register_scope(scope_id, "dormant").get("ok", false),
			"determinism fixture registers " + scope_id
		)

	var first: SimulationTierRouter = _new_router(100, 120, 300, 330, 2, 8)
	var second: SimulationTierRouter = _new_router(100, 120, 300, 330, 2, 8)
	var stream := [
		["north", 80],
		["south", 250],
		["east", 400],
		["south", 240],
	]
	for item in stream:
		var scope_id := String(item[0])
		var distance_mm := int(item[1])
		_check(
			first.submit_observation(scope_id, distance_mm, first_tiers).get("ok", false)
				and second.submit_observation(scope_id, distance_mm, second_tiers).get("ok", false),
			"equivalent stream submits " + scope_id
		)

	var first_results: Array = []
	var second_results: Array = []
	for tick in [10, 11]:
		var first_batch: Dictionary = first.process_pending(first_tiers, tick)
		var second_batch: Dictionary = second.process_pending(second_tiers, tick)
		first_results.append(first_batch["processed"])
		second_results.append(second_batch["processed"])

	_check(
		first_results == second_results,
		"equivalent observation streams produce identical ordered decisions"
	)
	_check(
		first_tiers.get_authoritative_snapshot()
			== second_tiers.get_authoritative_snapshot(),
		"equivalent streams converge to identical authoritative tier state"
	)


func _test_snapshot_restore_and_preflight() -> void:
	var tiers: SimulationTierState = _new_tiers()
	for scope_id in ["a", "b", "c"]:
		_check(
			tiers.register_scope(scope_id, "dormant").get("ok", false),
			"snapshot fixture registers " + scope_id
		)

	var router: SimulationTierRouter = _new_router(10, 20, 50, 60, 2, 8)
	_check(router.submit_observation("b", 40, tiers).get("ok", false), "snapshot queues b")
	_check(router.submit_observation("a", 5, tiers).get("ok", false), "snapshot queues a")
	_check(router.submit_observation("c", 70, tiers).get("ok", false), "snapshot queues c")
	_check(router.process_pending(tiers, 2, 1).get("ok", false), "snapshot fixture consumes one FIFO item")
	_check(router.submit_observation("b", 35, tiers).get("ok", false), "processed scope can be requeued at tail")

	var snapshot: Dictionary = router.get_authoritative_snapshot()
	var observations: Array = snapshot["observations"]
	var pending: Array = snapshot["pending_scope_ids"]
	_check(
		String(observations[0]["scope_id"]) == "a"
			and String(observations[1]["scope_id"]) == "b"
			and String(observations[2]["scope_id"]) == "c",
		"snapshot sorts observation records by scope identity"
	)
	_check(
		pending == ["a", "c", "b"],
		"snapshot preserves exact FIFO dirty queue order"
	)

	var restored: SimulationTierRouter = TierRouterScript.new()
	_check(
		restored.restore_snapshot(snapshot).get("ok", false)
			and restored.get_authoritative_snapshot() == snapshot,
		"router snapshot restores exact observations and queue order"
	)

	var tier_snapshot_before_future := tiers.get_authoritative_snapshot()
	var restored_tiers: SimulationTierState = TierStateScript.new()
	_check(
		restored_tiers.restore_snapshot(tier_snapshot_before_future).get("ok", false),
		"router future-decision fixture clones tier authority"
	)
	var original_future := router.process_pending(tiers, 3, 2)
	var restored_future := restored.process_pending(restored_tiers, 3, 2)
	_check(
		original_future["processed"] == restored_future["processed"],
		"restored router reproduces future bounded decisions"
	)

	var bad := snapshot.duplicate(true)
	bad["pending_scope_ids"][2] = "a"
	var validator: SimulationTierRouter = TierRouterScript.new()
	_check(
		validator.validate_snapshot(bad).get("reason", "")
			== "simulation_router_snapshot_pending_duplicate",
		"snapshot rejects duplicate pending identities"
	)

	var incompatible_snapshot := {
		"schema_version": 1,
		"active_enter_mm": 10,
		"active_exit_mm": 20,
		"aggregate_enter_mm": 50,
		"aggregate_exit_mm": 60,
		"max_decisions_per_call": 2,
		"max_tracked_observations": 8,
		"observations": [
			{"scope_id": "gone", "distance_mm": 5, "observation_revision": 0},
		],
		"pending_scope_ids": ["gone"],
	}
	var incompatible: SimulationTierRouter = TierRouterScript.new()
	_check(
		incompatible.restore_snapshot(incompatible_snapshot).get("ok", false),
		"standalone router may restore structurally valid observations"
	)
	var pending_before := incompatible.get_pending_count()
	var missing_result: Dictionary = incompatible.process_pending(tiers, 4)
	_check(
		missing_result.get("reason", "") == "simulation_scope_not_found"
			and incompatible.get_pending_count() == pending_before,
		"batch preflight rejects missing tier scope without consuming queue"
	)


func _test_runtime_integration_and_schema_migration() -> void:
	var runtime: SimulationRuntime = RuntimeScript.new()
	_check(
		runtime.initialize_runtime(
			1000, 4, 0, false, 5, 32,
			10, 20, 50, 60, 2, 16
		).get("ok", false),
		"runtime initializes scheduler tier authority and router atomically"
	)
	_check(
		runtime.register_simulation_scope(
			"runtime-a", "dormant", {"mass": 11}
		).get("ok", false),
		"runtime routing fixture registers stable scope"
	)

	_check(
		runtime.submit_simulation_scope_observation("runtime-a", 5).get("ok", false),
		"runtime exposes explicit distance observation submission"
	)
	var route: Dictionary = runtime.process_simulation_tier_routes()
	_check(
		route.get("ok", false)
			and int(route["processed_count"]) == 1
			and String(runtime.get_simulation_scope("runtime-a")["tier"]) == "active",
		"runtime bounded routing promotes observed scope"
	)

	var state_before: Dictionary = runtime.get_simulation_scope("runtime-a")
	_check(
		runtime.submit_simulation_scope_observation("runtime-a", 70).get("ok", false)
			and runtime.process_simulation_tier_routes().get("ok", false),
		"runtime processes later distance demotion"
	)
	var state_after: Dictionary = runtime.get_simulation_scope("runtime-a")
	_check(
		String(state_after["tier"]) == "dormant"
			and state_after["state"] == state_before["state"]
			and int(state_after["state_revision"]) == int(state_before["state_revision"]),
		"runtime automatic routing preserves domain state through demotion"
	)

	_check(
		runtime.submit_simulation_scope_observation("runtime-a", 40).get("ok", false),
		"runtime snapshot fixture leaves pending observation"
	)
	var snapshot: Dictionary = runtime.get_runtime_snapshot()
	_check(
		int(snapshot["schema_version"]) == 3
			and snapshot.has("tier_router")
			and snapshot["tier_router"]["pending_scope_ids"] == ["runtime-a"],
		"runtime schema 3 preserves router observations and pending order"
	)

	var restored: SimulationRuntime = RuntimeScript.new()
	_check(
		restored.restore_runtime_snapshot(snapshot).get("ok", false)
			and restored.get_runtime_snapshot() == snapshot,
		"combined runtime restore reproduces scheduler tier and router authority"
	)
	var restored_route: Dictionary = restored.process_simulation_tier_routes()
	_check(
		restored_route.get("ok", false)
			and String(restored.get_simulation_scope("runtime-a")["tier"]) == "aggregate",
		"restored pending router work produces same next decision"
	)

	var bad := snapshot.duplicate(true)
	bad["tier_router"]["observations"][0]["scope_id"] = "missing"
	bad["tier_router"]["pending_scope_ids"] = ["missing"]
	var prior: Dictionary = restored.get_runtime_snapshot()
	var rejected: Dictionary = restored.restore_runtime_snapshot(bad)
	_check(
		rejected.get("reason", "")
			== "simulation_runtime_snapshot_router_scope_missing"
			and restored.get_runtime_snapshot() == prior,
		"combined runtime restore rejects router/tier identity mismatch atomically"
	)

	var legacy := snapshot.duplicate(true)
	legacy.erase("tier_router")
	legacy.erase("environment_state")
	legacy["schema_version"] = 1
	var migrated: SimulationRuntime = RuntimeScript.new()
	var migration_result: Dictionary = migrated.restore_runtime_snapshot(legacy)
	_check(
		migration_result.get("ok", false)
			and int(migration_result.get("migrated_from_schema", 0)) == 1
			and int(migrated.get_runtime_snapshot()["schema_version"]) == 3
			and int(migrated.get_simulation_router_metrics()["tracked_observation_count"]) == 0,
		"runtime restores P4.0B schema-1 snapshot into default router plus empty P5 environment authority"
	)

	var metrics: Dictionary = runtime.get_simulation_router_metrics()
	_check(
		int(metrics["tracked_observation_count"]) == 1
			and int(metrics["max_decisions_per_call"]) == 2,
		"runtime exposes router telemetry without mutable authority"
	)

	runtime.free()
	restored.free()
	migrated.free()


func _test_playable_scene_surface() -> void:
	var packed: PackedScene = load("res://scenes/terrain_demo.tscn") as PackedScene
	_check(packed != null, "playable scene loads with P4.0C runtime")
	if packed == null:
		return

	var scene: Node = packed.instantiate()
	_check(scene.has_node("SimulationRuntime"), "playable scene retains one SimulationRuntime")
	if scene.has_node("SimulationRuntime"):
		var runtime_node: Node = scene.get_node("SimulationRuntime")
		_check(
			runtime_node.has_method("submit_simulation_scope_observation")
				and runtime_node.has_method("process_simulation_tier_routes")
				and runtime_node.has_method("get_simulation_router_snapshot")
				and runtime_node.has_method("restore_simulation_router_snapshot"),
			"playable runtime exposes bounded tier routing foundation"
		)
	scene.free()


func _new_tiers() -> SimulationTierState:
	var tiers: SimulationTierState = TierStateScript.new()
	var result: Dictionary = tiers.initialize(10, 64)
	_check(
		result.get("ok", false),
		"tier fixture initializes (%s)" % result.get("reason", "ok")
	)
	return tiers


func _new_router(
	active_enter_mm: int,
	active_exit_mm: int,
	aggregate_enter_mm: int,
	aggregate_exit_mm: int,
	max_decisions_per_call: int,
	max_tracked_observations: int
) -> SimulationTierRouter:
	var router: SimulationTierRouter = TierRouterScript.new()
	var result: Dictionary = router.initialize(
		active_enter_mm,
		active_exit_mm,
		aggregate_enter_mm,
		aggregate_exit_mm,
		max_decisions_per_call,
		max_tracked_observations
	)
	_check(
		result.get("ok", false),
		"router fixture initializes (%s)" % result.get("reason", "ok")
	)
	return router


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)
