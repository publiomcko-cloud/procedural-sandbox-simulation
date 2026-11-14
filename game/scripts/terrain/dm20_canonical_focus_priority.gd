class_name DM20CanonicalFocusPriority
extends RefCounted

## Experiment: reorder EXISTING stages, no new worker, budget or region.
## Edit/transaction/partial/full always outrank regular LOAD. DM18
## cache stages have already finished submission and are never selected.

static func choose(stages: Dictionary, excluded: Dictionary,
		focus: Vector2i, player_world: Vector3) -> Dictionary:
	var existing := TerrainStreamDispatchSelector.next(stages, excluded, focus)
	if existing.is_empty():
		return {}
	var initial: Dictionary = stages[existing["id"]]
	if String(initial.get("purpose", "")) != "load":
		return existing
	var best := existing
	var best_rank := _rank(initial, focus, player_world, String(existing["id"]))
	if bool(initial.get("dm9_speculative", false)):
		best_rank = [2147483647, INF, "~"]
	for id_value in stages.keys():
		var id := String(id_value)
		if excluded.has(id):
			continue
		var stage: Dictionary = stages[id]
		if String(stage.get("purpose", "")) != "load" or bool(stage.get("dm9_speculative", false)):
			continue
		var index := int(stage.get("submit_index", 0))
		var coordinates: Array = stage.get("chunk_coordinates", [])
		if index < 0 or index >= coordinates.size():
			continue
		var score := _rank(stage, focus, player_world, id)
		if _before(score, best_rank):
			best_rank = score
			best = {"id": id, "coordinate": coordinates[index], "index": index}
	return best


static func _rank(stage: Dictionary, focus: Vector2i,
		player_world: Vector3, id: String) -> Array:
	var region: Vector2i = stage["region_key"]
	# Focus always first; then Chebyshev ring, then real distance in metres.
	var ring := maxi(absi(region.x - focus.x), absi(region.y - focus.y))
	var center := Vector2(
		(float(region.x) + 0.5) * 16.0,
		(float(region.y) + 0.5) * 12.0
	)
	var physical_sq := center.distance_squared_to(Vector2(player_world.x, player_world.z))
	return [ring, physical_sq, id]


static func _before(a: Array, b: Array) -> bool:
	if int(a[0]) != int(b[0]):
		return int(a[0]) < int(b[0])
	if float(a[1]) != float(b[1]):
		return float(a[1]) < float(b[1])
	return String(a[2]) < String(b[2])
