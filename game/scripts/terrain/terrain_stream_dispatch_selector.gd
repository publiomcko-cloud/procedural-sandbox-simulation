extends RefCounted
class_name TerrainStreamDispatchSelector

## Deterministic, presentation-only stage selection. Exclusion applies only
## within one _dispatch_mesh_jobs() invocation; it is not persisted.
## Selection retains the existing priority and per-region chunk order.
const MAX_SKIPPED_LOAD_REGIONS_PER_FRAME := 3


static func stage_priority(purpose: String) -> int:
	if purpose == "edit_transaction":
		return 0
	if purpose == "partial":
		return 1
	if purpose == "full":
		return 2
	return 3


static func next(stages: Dictionary, excluded: Dictionary, focus: Vector2i) -> Dictionary:
	var candidates: Array[String] = []
	for value in stages.keys():
		var id := String(value)
		if not excluded.has(id):
			candidates.append(id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var stage_a: Dictionary = stages[a]
		var stage_b: Dictionary = stages[b]
		var pa := stage_priority(String(stage_a["purpose"]))
		var pb := stage_priority(String(stage_b["purpose"]))
		if pa != pb:
			return pa < pb
		var ka: Vector2i = stage_a["region_key"]
		var kb: Vector2i = stage_b["region_key"]
		var da := maxi(absi(ka.x - focus.x), absi(ka.y - focus.y))
		var db := maxi(absi(kb.x - focus.x), absi(kb.y - focus.y))
		if da == db:
			return ka.y < kb.y if ka.y != kb.y else ka.x < kb.x
		return da < db
	)
	for id in candidates:
		var stage: Dictionary = stages[id]
		var submit_index := int(stage.get("submit_index", 0))
		var coordinates: Array = stage["chunk_coordinates"]
		if submit_index >= 0 and submit_index < coordinates.size():
			return {"id": id, "coordinate": coordinates[submit_index], "index": submit_index}
	return {}


static func can_skip_pending(
	profile: String, purpose: String, skip_count: int, elapsed_usec: int, budget_usec: int,
	has_frame_headroom: bool
) -> bool:
	return (
		profile in ["adaptive-skip", "adaptive-skip-lookahead", "adaptive-skip-coarse", "adaptive-skip-coarse-ready"]
		and has_frame_headroom
		and purpose == "load"
		and skip_count < MAX_SKIPPED_LOAD_REGIONS_PER_FRAME
		and elapsed_usec < budget_usec
	)
