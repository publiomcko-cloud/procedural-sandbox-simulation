class_name DM24CanonicalStagePriority
extends RefCounted

## Test-only LOAD arbitration: preserve edit/partial/full precedence, source
## authority, 16-chunk order and all existing worker/frame dispatch limits.
## Evaluate candidate and original in BOTH arms. Only treatment can replace.
const AGE_THRESHOLD_USEC := 600_000
const FAIR_SLOT_PERIOD := 3


static func candidate(stages: Dictionary, excluded: Dictionary, focus: Vector2i,
		now_usec: int, dispatch_sequence: int,
		original: Dictionary) -> Dictionary:
	if original.is_empty():
		return {}
	var old_id := String(original["id"])
	var old_stage: Dictionary = stages.get(old_id, {})
	if String(old_stage.get("purpose", "")) != "load":
		return original

	# Strong preference only for the FIRST missing chunk of the focal region,
	# not its entire 16-chunk sequence (unlike DM20-B).
	var focus_candidate: Dictionary = {}
	var age_candidate: Dictionary = {}
	var oldest_usec := now_usec
	for key_value in stages:
		var id := String(key_value)
		if excluded.has(id):
			continue
		var stage: Dictionary = stages[id]
		if String(stage.get("purpose", "")) != "load" \
		or bool(stage.get("dm9_speculative", false)) \
		or bool(stage.get("dm18_cache_ready", false)):
			continue
		if int(stage.get("submit_index", 0)) != 0:
			continue
		var coordinates: Array = stage.get("chunk_coordinates", [])
		if coordinates.is_empty():
			continue
		var position: Vector2i = stage["region_key"]
		var ring := maxi(absi(position.x - focus.x), absi(position.y - focus.y))
		var candidate_request := {
			"id": id, "index": 0, "coordinate": coordinates[0]
		}
		if ring == 0:
			focus_candidate = candidate_request
		if ring <= 1:
			var queued := int(stage.get("chunk_enqueued_usec", now_usec))
			if queued < oldest_usec or (
				queued == oldest_usec and id < String(age_candidate.get("id", "~"))
			):
				oldest_usec = queued
				age_candidate = candidate_request

	if not focus_candidate.is_empty():
		return focus_candidate
	if dispatch_sequence % FAIR_SLOT_PERIOD == FAIR_SLOT_PERIOD - 1 \
	and now_usec - oldest_usec >= AGE_THRESHOLD_USEC \
	and not age_candidate.is_empty():
		return age_candidate
	return original
