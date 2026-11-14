class_name DM21StageRetention
extends RefCounted

## Optional reuse of partly generated, unmodified LOAD regions when they
## leave the desired 3x3 but remain within the existing retained 5x5.
## Never expands authoritative residency or publishes outside that window.
const MAX_RETAINED_STAGES := 2
const MIN_SUBMITTED_CHUNKS := 8
const MIN_COMPLETED_CHUNKS := 4

static func eligible(stage: Dictionary, region_is_retained: bool,
		region_is_desired: bool, previous_retained_count: int) -> bool:
	if previous_retained_count >= MAX_RETAINED_STAGES \
	or not region_is_retained or region_is_desired:
		return false
	if String(stage.get("purpose", "")) != "load" \
	or bool(stage.get("dm9_speculative", false)) \
	or bool(stage.get("dm18_cache_ready", false)):
		return false
	var count := int(stage.get("submit_index", 0))
	var done := int(stage.get("next_index", 0))
	var total := (stage.get("chunk_coordinates", []) as Array).size()
	return total == 16 and count >= MIN_SUBMITTED_CHUNKS \
		and done >= MIN_COMPLETED_CHUNKS \
		and done < total
