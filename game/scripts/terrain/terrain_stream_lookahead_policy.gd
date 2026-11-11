extends RefCounted
class_name TerrainStreamLookaheadPolicy

## Bounded ordering policy for already-enqueued terrain-object source regions.
## No source authority, cache, protected scope, worker count or queue membership
## changes. Projection SOURCE_REGION_RADIUS=2, so a 3x3 visible window
## needs a 7x7 source footprint. Keep current-focus sources ahead of
## predictive sources and prioritize urgent pending-effect dependencies.
const LOOKAHEAD_SECONDS := 0.75
const MAX_LEAD_REGIONS := 2


static func clamp_lead(focus: Vector2i, proposed: Vector2i) -> Vector2i:
	return focus + Vector2i(
		clampi(proposed.x - focus.x, -MAX_LEAD_REGIONS, MAX_LEAD_REGIONS),
		clampi(proposed.y - focus.y, -MAX_LEAD_REGIONS, MAX_LEAD_REGIONS)
	)


## At most six LOAD stages in the forward row/column at radius 2, always
## within terrain's 5x5 retained window (MAX_ACTIVE_REGIONS=25). The 3x3
## current window remains higher priority in the normal stage selector.
static func forward_stage_targets(focus: Vector2i, ahead: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var lead := clamp_lead(focus, ahead) - focus
	if lead.x != 0:
		var x := focus.x + (2 if lead.x > 0 else -2)
		for z in range(focus.y - 1, focus.y + 2):
			result.append(Vector2i(x, z))
	if lead.y != 0:
		var z := focus.y + (2 if lead.y > 0 else -2)
		for x in range(focus.x - 1, focus.x + 2):
			result.append(Vector2i(x, z))
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return result


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _rank(region: Vector2i, focus: Vector2i, ahead: Vector2i) -> int:
	var d_focus := _distance(region, focus)
	var d_ahead := _distance(region, ahead)
	if d_focus <= 2:
		return 0
	if d_ahead <= 2:
		return 1
	if d_focus <= 3:
		return 2
	if d_ahead <= 3:
		return 3
	return 4


static func ordered_queue(
	queue: Array[Vector2i],
	focus: Vector2i,
	ahead: Vector2i,
	urgent_scope_ids: Dictionary
) -> Array[Vector2i]:
	var urgent: Array[Vector2i] = []
	var normal: Array[Vector2i] = []
	for region in queue:
		var id := "region:%d,%d" % [region.x, region.y]
		if urgent_scope_ids.has(id):
			# Preserve FIFO order for explicit pending-effect prerequisites.
			urgent.append(region)
		else:
			normal.append(region)
	normal.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var rank_a := _rank(a, focus, ahead)
		var rank_b := _rank(b, focus, ahead)
		if rank_a != rank_b:
			return rank_a < rank_b
		var dca := _distance(a, focus)
		var dcb := _distance(b, focus)
		var dpa := _distance(a, ahead)
		var dpb := _distance(b, ahead)
		# Within an active-front rank, service the actual camera first; within
		# an ahead-only rank, service the anticipated camera first.
		if rank_a == 0 or rank_a == 2:
			if dca != dcb:
				return dca < dcb
			if dpa != dpb:
				return dpa < dpb
		else:
			if dpa != dpb:
				return dpa < dpb
			if dca != dcb:
				return dca < dcb
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	urgent.append_array(normal)
	return urgent
