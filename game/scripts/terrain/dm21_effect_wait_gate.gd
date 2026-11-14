class_name DM21EffectWaitGate
extends RefCounted

## Revision-gated dependency rendezvous for canonical LOAD stages.
## Source generation/projection is already single-flight in EffectRuntime.
## This gate prevents a consumer from retrying the same unresolved snapshot
## on every frame. Publication increments an event generation; watchdog is
## only a recovery mechanism for canceled/evicted dependencies.
const RETRY_WATCHDOG_USEC := 500_000

static func register(stage: Dictionary, coordinate: Vector2i,
		missing_regions: Array, notification_generation: int, now_usec: int,
		brush_scope_id: int) -> Dictionary:
	return {
		"stage_token": int(stage.get("stage_token", -1)),
		"coordinate": coordinate,
		"brush_revision": int(stage.get("edit_revision", -1)),
		"brush_scope_id": brush_scope_id,
		"effect_revision": int(stage.get("terrain_effect_authority_revision", -1)),
		"generation": notification_generation,
		"retry_after_usec": now_usec + RETRY_WATCHDOG_USEC,
		"missing_regions": missing_regions.duplicate(),
	}


static func still_same_request(wait: Dictionary, stage: Dictionary,
		coordinate: Vector2i, brush_revision: int,
		brush_scope_id: int, effect_revision: int) -> bool:
	if wait.is_empty() or not wait.get("coordinate") is Vector2i:
		return false
	return int(wait.get("stage_token", -1)) == int(stage.get("stage_token", -2)) \
		and wait["coordinate"] == coordinate \
		and int(wait.get("brush_revision", -1)) == brush_revision \
		and int(stage.get("edit_revision", -2)) == brush_revision \
		and int(wait.get("brush_scope_id", -1)) == brush_scope_id \
		and int(wait.get("effect_revision", -1)) == effect_revision \
		and int(stage.get("terrain_effect_authority_revision", -2)) == effect_revision


static func should_wait_without_event(wait: Dictionary,
		generation: int, now_usec: int) -> bool:
	return int(wait.get("generation", -1)) == generation \
		and now_usec < int(wait.get("retry_after_usec", 0))


static func should_wait_after_event(wait: Dictionary,
		missing_regions_ready: bool, now_usec: int) -> bool:
	return not missing_regions_ready \
		and now_usec < int(wait.get("retry_after_usec", 0))
