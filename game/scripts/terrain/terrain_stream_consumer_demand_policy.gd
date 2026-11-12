extends RefCounted
class_name TerrainStreamConsumerDemandPolicy

## Priority is advisory: authority, worker quotas, revisions and
## source/projection membership are never changed.
const SOURCE_RADIUS := 2
const MISSING_RANK := 1000000

static func can_prioritize(stage: Dictionary, edit_pending: bool, full_rebuild: bool) -> bool:
	return not edit_pending and not full_rebuild \
		and String(stage.get("purpose", "")) == "load" \
		and int(stage.get("submit_index", -1)) >= 0 \
		and int(stage.get("submit_index", -1)) < (stage.get("chunk_coordinates", []) as Array).size()

static func chunk_targets(region: Vector2i, chunk: Vector2i, count_x: int, count_z: int) -> Array[Vector2i]:
	var xs: Array[int] = [region.x]
	var zs: Array[int] = [region.y]
	if chunk.x == 0:
		xs.append(region.x - 1)
	elif chunk.x == count_x - 1:
		xs.append(region.x + 1)
	if chunk.y == 0:
		zs.append(region.y - 1)
	elif chunk.y == count_z - 1:
		zs.append(region.y + 1)
	var targets: Array[Vector2i] = []
	for z in zs:
		for x in xs:
			targets.append(Vector2i(x, z))
	return targets

static func source_ranks(targets: Array[Vector2i], focus: Vector2i) -> Dictionary:
	var coverage: Dictionary = {}
	for target in targets:
		for z in range(target.y - SOURCE_RADIUS, target.y + SOURCE_RADIUS + 1):
			for x in range(target.x - SOURCE_RADIUS, target.x + SOURCE_RADIUS + 1):
				var key := Vector2i(x, z)
				coverage[key] = int(coverage.get(key, 0)) + 1
	var ranks: Dictionary = {}
	for value in coverage:
		var source: Vector2i = value
		var count := int(coverage[source])
		var distance := maxi(absi(source.x - focus.x), absi(source.y - focus.y))
		ranks[source] = (targets.size() - count) * 100 + distance
	return ranks

static func rank_of(region: Vector2i, ranks: Dictionary) -> int:
	return int(ranks.get(region, MISSING_RANK))

static func best_queue_index(queue: Array[Vector2i], ranks: Dictionary) -> int:
	if queue.is_empty():
		return -1
	if ranks.is_empty():
		return 0
	var best := 0
	var best_rank := rank_of(queue[0], ranks)
	for i in range(1, queue.size()):
		var rank := rank_of(queue[i], ranks)
		if rank < best_rank:
			best = i
			best_rank = rank
	return best

static func best_ready_index(records: Array[Dictionary], ranks: Dictionary) -> int:
	if records.is_empty():
		return -1
	if ranks.is_empty():
		return 0
	var best := 0
	var best_rank := rank_of(records[0]["region"], ranks)
	for i in range(1, records.size()):
		var rank := rank_of(records[i]["region"], ranks)
		if rank < best_rank:
			best = i
			best_rank = rank
	return best
