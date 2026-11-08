extends SceneTree

# P4.0D performance campaign A: real domain + tier authority + bounded FIFO.
# Headless, isolated, deterministic, machine-readable. Setup is measured separately.
const DomainScript := preload("res://scripts/simulation/material_environment_domain.gd")
const TierScript := preload("res://scripts/simulation/simulation_tier_state.gd")
const QueueScript := preload("res://scripts/simulation/material_environment_work_queue.gd")
const RegistryScript := preload("res://scripts/modding/content_definition_registry.gd")

const COUNTS := [100, 1000, 10000]
const BUDGET := 32
const CAPACITY := 2048
const MAX_BENCHMARK_FRAME_USEC := 10000000

var _errors: Array[String] = []


func _initialize() -> void:
	var results: Array = []
	for count_value in COUNTS:
		var count: int = int(count_value)
		var one: Dictionary = _run_case(count)
		results.append(one)
		print("P4_0D_BENCH_CASE " + JSON.stringify(one, "", true, true))
	var verdict := _errors.is_empty()
	print("P4_0D_BENCH_RESULT " + JSON.stringify({
		"ok": verdict, "results": results, "errors": _errors
	}, "", true, true))
	if verdict:
		print("P4_0D_BENCH_PASS")
	else:
		push_error("P4_0D_BENCH_FAIL: " + JSON.stringify(_errors))
	quit(0 if verdict else 1)


func _run_case(count: int) -> Dictionary:
	var profile_id := "benchmark.p4:stone"
	var record := {
		"schema_version": 1, "type": DomainScript.PROFILE_TYPE,
		"id": profile_id, "ambient_temperature_milli_c": 20000,
		"relaxation_milli_per_due_step": 500,
	}
	var manifest := {
		"id": "benchmark.p4", "version": "1.0.0", "schema_version": 1,
		"requires_engine": "4.7.2", "dependencies": [],
		"content_roots": ["profiles/"], "script_policy": "data_only",
	}
	var domain: MaterialEnvironmentDomain = DomainScript.new()
	var registry: ContentDefinitionRegistry = RegistryScript.new()
	_require(registry.register_engine_content_type_handler(domain.create_content_handler()).get("ok", false), "handler registered")
	var discovery := {"ok": true, "packages": [{
		"manifest": manifest, "content_records": [record],
		"definitions": [], "population_rules": [], "terrain_interactions": [],
	}]}
	var reg: Dictionary = registry.register_discovered(discovery)
	if not _require(reg.get("ok", false), "synthetic M4.0 registry " + str(reg.get("reason", ""))):
		return {"scopes": count, "ok": false}
	var t0 := Time.get_ticks_usec()
	var bind: Dictionary = domain.bind_registry_profile(registry, profile_id)
	var bind_usec := Time.get_ticks_usec() - t0
	if not _require(bind.get("ok", false), "profile bound"):
		return {"scopes": count, "ok": false}
	var tiers: SimulationTierState = TierScript.new()
	if not _require(tiers.initialize(10, count).get("ok", false), "tier initialized"):
		return {"scopes": count, "ok": false}
	t0 = Time.get_ticks_usec()
	for index in range(count):
		var scope_id := "bench.%05d" % index
		var tier := "active" if index % 10 < 6 else ("aggregate" if index % 10 < 9 else "dormant")
		if not _require(tiers.register_scope(scope_id, tier).get("ok", false), "scope registered"):
			return {"scopes": count, "ok": false}
	var setup_usec := Time.get_ticks_usec() - t0
	# Round B: cold initialization uses the same cumulative frame budget as updates.
	var init_queue: MaterialEnvironmentWorkQueue = QueueScript.new()
	if not _require(init_queue.initialize(domain, BUDGET, CAPACITY).get("ok", false), "init queue configured"):
		return {"scopes": count, "ok": false}
	var init_cursor := 0
	var init_frame := 1
	var init_samples: Array[int] = []
	var init_completed := 0
	var init_peak_pending := 0
	while init_completed < count and init_frame < count + 100:
		while init_cursor < count and int(init_queue.get_metrics()["pending_count"]) < CAPACITY:
			var id := "bench.%05d" % init_cursor
			if not _require(init_queue.enqueue_initialization(tiers, id, profile_id, 0).get("ok", false), "cold init admission"):
				return {"scopes": count, "ok": false}
			init_cursor += 1
		init_peak_pending = maxi(init_peak_pending, int(init_queue.get_metrics()["pending_count"]))
		var begin := Time.get_ticks_usec()
		var initialized: Dictionary = init_queue.process_pending(tiers, init_frame)
		init_samples.append(Time.get_ticks_usec() - begin)
		if not _require(initialized.get("ok", false), "cold init batch " + str(initialized.get("detail", ""))):
			return {"scopes": count, "ok": false}
		if not _require(int(initialized["processed_count"]) <= BUDGET, "cold init frame budget"):
			return {"scopes": count, "ok": false}
		init_completed += int(initialized["processed_count"])
		init_frame += 1
	_require(init_completed == count and int(init_queue.get_metrics()["pending_count"]) == 0, "cold initialization fully drained")
	var queue: MaterialEnvironmentWorkQueue = QueueScript.new()
	if not _require(queue.initialize(domain, BUDGET, CAPACITY).get("ok", false), "queue initialized"):
		return {"scopes": count, "ok": false}

	var first_tick := 10
	var cursor := 0
	var frame_index := 1
	var samples: Array[int] = []
	var enqueue_usec_total := 0
	var due_total := 0
	var noops_total := 0
	var completed_total := 0
	var peak_backlog := 0
	var previous_processed := 0
	while completed_total < count and frame_index < count + 100:
		var enqueue_start := Time.get_ticks_usec()
		while cursor < count and int(queue.get_metrics()["pending_count"]) < CAPACITY:
			var scope_id := "bench.%05d" % cursor
			if not _require(queue.enqueue(tiers, scope_id, profile_id, first_tick).get("ok", false), "admission"):
				return {"scopes": count, "ok": false}
			cursor += 1
		enqueue_usec_total += Time.get_ticks_usec() - enqueue_start
		peak_backlog = maxi(peak_backlog, int(queue.get_metrics()["pending_count"]))
		var start := Time.get_ticks_usec()
		var batch: Dictionary = queue.process_pending(tiers, frame_index)
		var elapsed := Time.get_ticks_usec() - start
		if not _require(batch.get("ok", false), "process batch " + str(batch.get("detail", ""))):
			return {"scopes": count, "ok": false}
		if not _require(int(batch["processed_count"]) <= BUDGET, "budget observed"):
			return {"scopes": count, "ok": false}
		if not _require(elapsed <= MAX_BENCHMARK_FRAME_USEC, "stalled benchmark frame"):
			return {"scopes": count, "ok": false}
		samples.append(elapsed)
		for receipt_value in batch["processed"]:
			var receipt: Dictionary = receipt_value
			if bool(receipt["due"]):
				due_total += 1
			else:
				noops_total += 1
		completed_total += int(batch["processed_count"])
		previous_processed = int(batch["processed_count"])
		frame_index += 1
	_require(completed_total == count, "drain completed")
	_require(int(queue.get_metrics()["pending_count"]) == 0, "no backlog after drain")
	_require(int(domain.get_binding_metrics()["legacy_hash_validations_total"]) == 1, "hot-path does not rehash")
	_require(int(domain.get_binding_metrics()["bound_update_calls_total"]) == count, "every admission processed once")
	var warm_scope := "bench.%05d" % 0
	var warm_tick := 20
	t0 = Time.get_ticks_usec()
	var warm_queue: MaterialEnvironmentWorkQueue = QueueScript.new()
	warm_queue.initialize(domain, 1, 1)
	_require(warm_queue.enqueue(tiers, warm_scope, profile_id, warm_tick).get("ok", false), "warm update queued")
	var warm_result: Dictionary = warm_queue.process_pending(tiers, 1)
	var warm_usec := Time.get_ticks_usec() - t0
	_require(warm_result.get("ok", false), "warm update succeeds")
	var pin_metrics: Dictionary = domain.get_binding_metrics()
	return {
		"ok": _errors.is_empty(),
		"scopes": count, "budget": BUDGET, "capacity": CAPACITY,
		"bind_usec": bind_usec, "scope_registration_usec": setup_usec,
		"initialization_frames": init_samples.size(),
		"initialization_batch_p50_usec": _percentile(init_samples, 50),
		"initialization_batch_p95_usec": _percentile(init_samples, 95),
		"initialization_batch_p99_usec": _percentile(init_samples, 99),
		"initialization_batch_max_usec": init_samples.max() if not init_samples.is_empty() else 0,
		"initialization_peak_pending": init_peak_pending,
		"enqueue_total_usec": enqueue_usec_total,
		"processing_frames": samples.size(),
		"batch_p50_usec": _percentile(samples, 50),
		"batch_p95_usec": _percentile(samples, 95),
		"batch_p99_usec": _percentile(samples, 99),
		"batch_max_usec": samples.max() if not samples.is_empty() else 0,
		"processed_total": completed_total, "due_total": due_total,
		"noop_total": noops_total, "peak_pending": peak_backlog,
		"warm_update_usec": warm_usec,
		"hash_validations": pin_metrics["legacy_hash_validations_total"],
		"queue_metrics": queue.get_metrics(),
	}


func _percentile(samples: Array[int], percentile: int) -> int:
	if samples.is_empty():
		return 0
	var ordered: Array[int] = samples.duplicate()
	ordered.sort()
	var index := mini(ordered.size() - 1, int(ceil(float(ordered.size() * percentile) / 100.0)) - 1)
	return ordered[maxi(0, index)]


func _require(ok: bool, description: String) -> bool:
	if not ok:
		if _errors.size() < 20:
			_errors.append(description)
		return false
	return true
