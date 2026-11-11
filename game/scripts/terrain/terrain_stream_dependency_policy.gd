extends RefCounted
class_name TerrainStreamDependencyPolicy

## E1 opt-in, pure scheduling helpers. This module never changes authority,
## worker capacity, queue membership, stage tokens, edits or region residency.
const Selector := preload("res://scripts/terrain/terrain_stream_dispatch_selector.gd")
const EFFECT_RADIUS := 2


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func stage_targets(stages: Dictionary, focus: Vector2i) -> Array[Vector2i]:
	var pending: Array[String] = []
	for key in stages.keys():
		var id := String(key)
		var stage: Dictionary = stages[id]
		if int(stage.get("submit_index", 0)) >= (stage.get("chunk_coordinates", []) as Array).size():
			continue
		pending.append(id)
	pending.sort_custom(func(a: String, b: String) -> bool:
		var sa: Dictionary = stages[a]
		var sb: Dictionary = stages[b]
		var pa := Selector.stage_priority(String(sa.get("purpose", "load")))
		var pb := Selector.stage_priority(String(sb.get("purpose", "load")))
		if pa != pb:
			return pa < pb
		var ka: Vector2i = sa.get("region_key", Vector2i.ZERO)
		var kb: Vector2i = sb.get("region_key", Vector2i.ZERO)
		var da := _distance(ka, focus)
		var db := _distance(kb, focus)
		if da != db:
			return da < db
		return ka.y < kb.y if ka.y != kb.y else ka.x < kb.x
	)
	var targets: Array[Vector2i] = []
	for id in pending:
		var region: Vector2i = stages[id]["region_key"]
		if not targets.has(region):
			targets.append(region)
	return targets


## Nonurgent queue entries are ranked by the earliest still-staged terrain
## target that requires them. Urgent entries keep their original FIFO order.
## A source affects a target only within the existing +/-2 source halo.
static func order_prefetch(
	queue: Array[Vector2i], targets: Array[Vector2i], focus: Vector2i,
	urgent_scope_ids: Dictionary
) -> Array[Vector2i]:
	if targets.is_empty() or queue.size() <= 1:
		return queue.duplicate()
	var urgent: Array[Vector2i] = []
	var normal: Array[Vector2i] = []
	for region in queue:
		if urgent_scope_ids.has("region:%d,%d" % [region.x, region.y]):
			urgent.append(region)
		else:
			normal.append(region)
	normal.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pa := _first_target(a, targets)
		var pb := _first_target(b, targets)
		if pa != pb:
			return pa < pb
		if pa < targets.size():
			var da := _distance(a, targets[pa])
			var db := _distance(b, targets[pb])
			if da != db:
				return da < db
		var fa := _distance(a, focus)
		var fb := _distance(b, focus)
		if fa != fb:
			return fa < fb
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	urgent.append_array(normal)
	return urgent


static func _first_target(source: Vector2i, targets: Array[Vector2i]) -> int:
	for index in range(targets.size()):
		if _distance(source, targets[index]) <= EFFECT_RADIUS:
			return index
	return targets.size()
