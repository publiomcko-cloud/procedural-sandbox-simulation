extends SceneTree

const ProjectionService := preload("res://scripts/terrain/terrain_object_effect_projection_service.gd")
const Contract := preload("res://scripts/terrain/terrain_object_effect_projection_contract.gd")

class FakeIndex:
	extends RefCounted
	func get_all_indexed_chunk_ids() -> Array[String]:
		return []
	func get_all_indexed_chunk_ids_unsorted() -> Array[String]:
		return []

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous_trace := OS.get_environment("SANDBOX_PERF_TRACE")
	var previous_rollup := OS.get_environment("SANDBOX_DM15_DORMANT_ROLLUP")
	var previous_lazy := OS.get_environment("SANDBOX_DM14_LAZY_ROUTES")
	OS.set_environment("SANDBOX_PERF_TRACE", "1")
	OS.set_environment("SANDBOX_DM14_LAZY_ROUTES", "0")
	var baseline := _make_service("legacy", false)
	var candidate := _make_service("rollup", true)
	for i in range(9):
		var key := Vector2i(i, -7)
		_install(baseline, key)
		_install(candidate, key)
		baseline.release_scope(key, true)
		candidate.release_scope(key, true)
	_check(baseline.get_loaded_scope_count() == 0
		and candidate.get_loaded_scope_count() == 0,
		"both paths remove active source immediately")
	_check(baseline.get_performance_snapshot()["dormant_scope_store_count"] == 9,
		"legacy retains nine derived dormant sources")
	_check(candidate.get_performance_snapshot()["dormant_scope_store_count"] == 9,
		"rollup retains nine derived dormant sources")
	_check(baseline.get_performance_snapshot()["dm15_dormant_per_scope_trace_count"] == 9,
		"legacy emits nine source-granular events")
	_check(candidate.get_performance_snapshot()["dm15_dormant_per_scope_trace_count"] == 0,
		"rollup avoids per-scope synchronous JSON writes")
	_check(candidate.get_performance_snapshot()["dm15_dormant_unsent_count"] == 9,
		"all nine source events accounted without per-scope output")
	_check(candidate._dormant_scope_order == baseline._dormant_scope_order,
		"same exact dormant LRU order")
	for i in range(9):
		var key := Vector2i(i, -7)
		var id := Contract.scope_id_for_region(key)
		_check(candidate._dormant_scopes[id]["snapshot"] ==
			baseline._dormant_scopes[id]["snapshot"],
			"byte-identical dormant source snapshot for " + id)
		_check(candidate._dormant_scopes[id]["generation"] ==
			baseline._dormant_scopes[id]["generation"],
			"same storage generation")
	var rollup: Dictionary = candidate.take_dormant_store_rollup()
	_check(int(rollup.get("store_count", -1)) == 9,
		"one rollup accounts for all nine stores")
	_check(int(rollup.get("effect_count", -1)) == 18,
		"rollup accounts for exact effect count")
	_check(int(rollup.get("dormant_scope_count", -1)) == 9,
		"dormant occupancy unchanged")
	_check(candidate.take_dormant_store_rollup().is_empty(),
		"rollup is consumed once")
	_check(candidate.get_performance_snapshot()["dm15_dormant_rollup_count"] == 1,
		"one rollup instead of nine events")
	for i in range(9):
		var key := Vector2i(i, -7)
		var before := baseline.load_scope(key)
		var after := candidate.load_scope(key)
		_check(before.get("ok", false) and after.get("ok", false),
			"both can reactivate dormant source")
		_check(before.get("dormant_cache_hit", false) and
			after.get("dormant_cache_hit", false),
			"both reuse dormant cache without regeneration")
		_check(before == after, "reloaded source metadata parity")
		_check(candidate.get_scope_snapshot(key) == baseline.get_scope_snapshot(key),
			"exact reloaded scope snapshot parity")
	_check(candidate.get_performance_snapshot()["dormant_scope_hit_count"] == 9,
		"no effect on cache hit accounting")
	OS.set_environment("SANDBOX_PERF_TRACE", previous_trace)
	OS.set_environment("SANDBOX_DM15_DORMANT_ROLLUP", previous_rollup)
	OS.set_environment("SANDBOX_DM14_LAZY_ROUTES", previous_lazy)
	print("DM15_DORMANT_ROLLUP_RESULT=" + JSON.stringify({
		"checks": checks,
		"failures": failures,
		"source_count": 9,
		"exact_cache": failures == 0,
		"single_rollup": failures == 0
	}))
	print("DM15_DORMANT_ROLLUP_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _make_service(label: String, coalesced: bool) -> RefCounted:
	OS.set_environment("SANDBOX_DM15_DORMANT_ROLLUP", "1" if coalesced else "0")
	var result := ProjectionService.new()
	_check(bool(result.initialize("dm15-" + label, 424242, 1,
		"user://dm15-" + label).get("ok", false)), "projection initialization " + label)
	return result


func _install(service: RefCounted, key: Vector2i) -> void:
	var id := Contract.scope_id_for_region(key)
	service._scopes[id] = {
		"projection_revision": 0,
		"source_world_revision": 0,
		"effects": {"a": {}, "b": {}},
		"local_frames": {},
	}
	service._scope_indexes[id] = FakeIndex.new()
	service._storage_generations[id] = 0


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DM15_DORMANT_ROLLUP_FAIL: " + message)
