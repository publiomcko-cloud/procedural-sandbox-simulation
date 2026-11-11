extends SceneTree

const Selector := preload("res://scripts/terrain/terrain_stream_dispatch_selector.gd")
const Policy := preload("res://scripts/terrain/terrain_stream_dependency_policy.gd")
const Runtime := preload("res://scripts/terrain/terrain_object_effect_runtime.gd")

class FakeProjection:
	extends RefCounted
	var loaded: Dictionary = {}
	func has_scope(region: Vector2i) -> bool:
		return loaded.has("%d,%d" % [region.x, region.y])

var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var center := Vector2i(5, 13)
	var stages := {
		"5,13": {"purpose": "load", "region_key": center, "chunk_coordinates": [Vector2i.ZERO], "submit_index": 0},
		"6,13": {"purpose": "load", "region_key": Vector2i(6, 13), "chunk_coordinates": [Vector2i.ZERO], "submit_index": 0},
		"8,13": {"purpose": "load", "region_key": Vector2i(8, 13), "chunk_coordinates": [Vector2i.ZERO], "submit_index": 0},
	}
	_check(Selector.next(stages, {}, center).get("id", "") == "5,13", "legacy selector still chooses focus")
	_check(Selector.next(stages, {}, center, {"5,13": 12, "6,13": 0, "8,13": 0}).get("id", "") == "6,13",
		"dependency profile favors a ready visible LOAD, never a farther ready speculative LOAD")
	_check(Selector.next(stages, {}, center, {"5,13": 12, "6,13": 5, "8,13": 0}).get("id", "") == "5,13",
		"no ready visible LOAD keeps the closest first")
	_check(Selector.next(stages, {}, center, {"5,13": 12, "6,13": 0, "8,13": 0}).get("id", "") == "6,13",
		"source readiness never consumes a stage index")
	stages["edit"] = {"purpose": "edit_transaction", "region_key": Vector2i(8, 13), "chunk_coordinates": [Vector2i.ZERO], "submit_index": 0}
	_check(Selector.next(stages, {}, center, {"5,13": 12, "6,13": 0}).get("id", "") == "edit",
		"authoritative edits outrank ready LOADs")
	stages.erase("edit")
	stages["6,13"]["submit_index"] = 1
	_check(Selector.next(stages, {}, center, {"5,13": 12, "6,13": 0}).get("id", "") == "5,13",
		"completed ready LOAD is never restarted")
	var ordered_targets := Policy.stage_targets(stages, center)
	_check(ordered_targets.size() == 2 and ordered_targets[0] == center and ordered_targets[1] == Vector2i(8, 13),
		"only remaining stages enter deterministic demand ordering")
	var q: Array[Vector2i] = [Vector2i(9, 13), Vector2i(7, 13), Vector2i(5, 13), Vector2i(4, 13)]
	var demand: Array[Vector2i] = [center, Vector2i(8, 13)]
	var focused_demand: Array[Vector2i] = [center]
	var empty_demand: Array[Vector2i] = []
	var reordered := Policy.order_prefetch(q, demand, center, {})
	_check(reordered.size() == q.size() and reordered.has(Vector2i(9, 13)), "source queue membership preserved")
	_check(reordered[0] == Vector2i(5, 13), "focused source is prioritized")
	_check(reordered.find(Vector2i(4, 13)) < reordered.find(Vector2i(9, 13)), "critical focus halo precedes speculative source")
	var urgent := {"region:9,13": true}
	var preserving := Policy.order_prefetch(q, focused_demand, center, urgent)
	_check(preserving[0] == Vector2i(9, 13), "urgent effect requests stay ahead of ordinary prefetch")
	_check(Policy.order_prefetch(q, empty_demand, center, urgent) == q, "no demands retain queue unchanged")
	var runtime := Runtime.new()
	runtime.initialized = true
	runtime.incremental_prefetch_enabled = true
	var fake := FakeProjection.new()
	runtime.projection = fake
	runtime._prefetch_queue = q.duplicate()
	var status: Dictionary = runtime.prioritize_prefetch_for_dependency(focused_demand, center)
	_check(status["target_count"] == 1 and status["ready_targets"] == 0, "cold region is blocked by dependencies")
	_check(status["missing_source_counts"].get("5,13", -1) == 25, "full 5x5 halo is required for one target")
	_check(runtime._prefetch_queue.size() == q.size(), "E1 does not add missing sources or expand source residency")
	for z in range(11, 16):
		for x in range(3, 8):
			fake.loaded["%d,%d" % [x, z]] = true
	var ready: Dictionary = runtime.prioritize_prefetch_for_dependency(focused_demand, center)
	_check(ready["ready_targets"] == 1 and ready["missing_source_counts"]["5,13"] == 0, "ready target is recognized")
	runtime._invalidated_scope_ids["region:5,13"] = true
	var invalidated := runtime.prioritize_prefetch_for_dependency(focused_demand, center)
	_check(invalidated["missing_source_counts"]["5,13"] == 1, "stale effect scope cannot count as ready")
	if failures == 0:
		print("P5_STREAM_DEPENDENCY_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P5_STREAM_DEPENDENCY_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)
