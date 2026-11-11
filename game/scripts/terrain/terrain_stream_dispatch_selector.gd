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


static func next(
	stages: Dictionary, excluded: Dictionary, focus: Vector2i,
	missing_source_counts: Dictionary = {}
) -> Dictionary:
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
		# E1 only: within the currently visible 3x3, work on a source-ready
		# LOAD first. Never overtake edit/partial/full or dispatch outside 3x3
		# while a visible LOAD is queued. Actual snapshot checks remain final.
		if pa == 3 and not missing_source_counts.is_empty():
			var a_visible := da <= 1
			var b_visible := db <= 1
			if a_visible != b_visible:
				return a_visible
			if a_visible and b_visible:
				var a_ready := int(missing_source_counts.get(a, -1)) == 0
				var b_ready := int(missing_source_counts.get(b, -1)) == 0
				if a_ready != b_ready:
					return a_ready
		if da == db:
			if pa == 3 and not missing_source_counts.is_empty():
				var ma := int(missing_source_counts.get(a, 2147483647))
				var mb := int(missing_source_counts.get(b, 2147483647))
				if ma != mb:
					return ma < mb
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
		profile in ["adaptive-skip", "adaptive-skip-lookahead", "adaptive-skip-dependency"]
		and has_frame_headroom
		and purpose == "load"
		and skip_count < MAX_SKIPPED_LOAD_REGIONS_PER_FRAME
		and elapsed_usec < budget_usec
	)
