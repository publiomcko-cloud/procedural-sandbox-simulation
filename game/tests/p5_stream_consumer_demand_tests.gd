extends SceneTree

const Policy := preload("res://scripts/terrain/terrain_stream_consumer_demand_policy.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(good: bool, detail: String) -> void:
	assertions += 1
	if not good:
		failures += 1
		push_error("FAIL: " + detail)

func _run() -> void:
	var focus := Vector2i(8, 13)
	var stage := {
		"purpose": "load", "region_key": focus,
		"chunk_coordinates": [Vector2i.ZERO, Vector2i(1, 0)],
		"submit_index": 0, "stage_token": 8,
		"edit_revision": 2, "terrain_effect_authority_revision": 19,
	}
	_check(Policy.can_prioritize(stage, false, false), "eligible visible LOAD")
	_check(not Policy.can_prioritize(stage, true, false), "edit transaction gates demand")
	_check(not Policy.can_prioritize(stage, false, true), "full rebuild gates demand")
	for purpose in ["edit_transaction", "partial", "full"]:
		var changed := stage.duplicate()
		changed["purpose"] = purpose
		_check(not Policy.can_prioritize(changed, false, false), "no demand ordering for " + purpose)
	var complete := stage.duplicate()
	complete["submit_index"] = 2
	_check(not Policy.can_prioritize(complete, false, false), "no exhausted chunk selection")
	var inner := Policy.chunk_targets(focus, Vector2i(1, 1), Grid.CHUNK_COUNT_X, Grid.CHUNK_COUNT_Z)
	_check(inner.size() == 1 and inner[0] == focus, "interior chunk only own region")
	_check(Policy.source_ranks(inner, focus).size() == 25, "interior halo is 5x5")
	var corner := Policy.chunk_targets(focus, Vector2i.ZERO, Grid.CHUNK_COUNT_X, Grid.CHUNK_COUNT_Z)
	var ranks := Policy.source_ranks(corner, focus)
	_check(corner.size() == 4, "shared corner covers four target regions")
	_check(ranks.size() == 36, "existing 6x6 required source halo for shared corner")
	_check(ranks.has(focus + Vector2i(-3, -3)), "negative halo corner included")
	_check(ranks.has(focus + Vector2i(2, 2)), "positive halo corner included")
	_check(not ranks.has(focus + Vector2i(3, 3)), "outside source not invented")
	var queue: Array[Vector2i] = [focus + Vector2i(3, 3), focus + Vector2i(-3, -3), focus]
	_check(Policy.best_queue_index(queue, ranks) > 0, "consumer source over background queue entry")
	_check(Policy.best_queue_index(queue, {}) == 0, "empty demand preserves baseline FIFO")
	var ready: Array[Dictionary] = [{"region": focus + Vector2i(3, 3)}, {"region": focus}]
	_check(Policy.best_ready_index(ready, ranks) == 1, "projection ready publication is consumer-first")
	_check(Policy.best_ready_index(ready, {}) == 0, "no demand preserves projection FIFO")
	_check(Policy.best_queue_index([], ranks) == -1, "empty source queue stays empty")
	_check(Policy.rank_of(focus + Vector2i(3, 3), ranks) == Policy.MISSING_RANK, "outside source low priority")
	var x_edge := Policy.chunk_targets(focus, Vector2i(Grid.CHUNK_COUNT_X - 1, 1), Grid.CHUNK_COUNT_X, Grid.CHUNK_COUNT_Z)
	_check(x_edge.size() == 2, "shared X edge has two target regions")
	_check(Policy.source_ranks(x_edge, focus).size() == 30, "shared X edge halo has 30 sources")
	# Absolute E4 ranks and precomputed E4.1 relative templates must match
	# for all nine edge topologies, preserving exact halo/priority semantics.
	for x in [0, 1, Grid.CHUNK_COUNT_X - 1]:
		for z in [0, 1, Grid.CHUNK_COUNT_Z - 1]:
			var pos := Vector2i(x, z)
			var abs_targets := Policy.chunk_targets(
				focus, pos, Grid.CHUNK_COUNT_X, Grid.CHUNK_COUNT_Z
			)
			var absolute := Policy.source_ranks(abs_targets, focus)
			var relative := Policy.relative_pattern(
				pos, Grid.CHUNK_COUNT_X, Grid.CHUNK_COUNT_Z
			)
			_check(relative.size() == absolute.size(), "template halo cardinality")
			for scope in absolute:
				_check(Policy.rank_of(scope, relative, focus) == int(absolute[scope]),
					"template reproduces absolute source rank")
	var relative_corner := Policy.relative_pattern(
		Vector2i.ZERO, Grid.CHUNK_COUNT_X, Grid.CHUNK_COUNT_Z
	)
	_check(Policy.best_queue_index(queue, relative_corner, focus) == Policy.best_queue_index(queue, ranks),
		"precomputed queue selection is identical to original E4")
	_check(Policy.best_ready_index(ready, relative_corner, focus) == Policy.best_ready_index(ready, ranks),
		"precomputed projection publication preserves E4 selection")
	if failures == 0:
		print("P5_STREAM_CONSUMER_DEMAND_PASS: assertions=%d failures=0" % assertions)
		quit(0)
	else:
		push_error("P5_STREAM_CONSUMER_DEMAND_FAIL: assertions=%d failures=%d" % [assertions, failures])
		quit(1)
