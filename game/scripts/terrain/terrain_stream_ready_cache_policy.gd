extends RefCounted
class_name TerrainStreamReadyCachePolicy

## Negative LOAD-stage cache only. Never substitutes for authoritative effects
## snapshots, revisions, terrain meshes, transactions, or worker completion.
const MAX_TRACKED_STAGES := 64
const MAX_BLOCKED_FRAMES := 30

static func pending_ticket(stage: Dictionary, scope_epoch: int, frame: int) -> Dictionary:
	return {
		"purpose": String(stage.get("purpose", "")),
		"stage_token": int(stage.get("stage_token", -1)),
		"submit_index": int(stage.get("submit_index", -1)),
		"edit_revision": int(stage.get("edit_revision", -1)),
		"effect_revision": int(stage.get("terrain_effect_authority_revision", -1)),
		"scope_epoch": scope_epoch,
		"expires_at_frame": frame + MAX_BLOCKED_FRAMES,
	}

static func still_pending(ticket: Dictionary, stage: Dictionary, scope_epoch: int, frame: int) -> bool:
	return String(stage.get("purpose", "")) == "load" \
		and String(ticket.get("purpose", "")) == "load" \
		and int(ticket.get("scope_epoch", -1)) == scope_epoch \
		and int(ticket.get("stage_token", -1)) == int(stage.get("stage_token", -2)) \
		and int(ticket.get("submit_index", -1)) == int(stage.get("submit_index", -2)) \
		and int(ticket.get("edit_revision", -1)) == int(stage.get("edit_revision", -2)) \
		and int(ticket.get("effect_revision", -1)) == int(stage.get("terrain_effect_authority_revision", -2)) \
		and frame < int(ticket.get("expires_at_frame", -1))

static func excluded(stages: Dictionary, tickets: Dictionary, scope_epoch: int, frame: int) -> Dictionary:
	var result: Dictionary = {}
	for stage_id in tickets:
		if not stages.has(stage_id):
			continue
		if still_pending(tickets[stage_id], stages[stage_id], scope_epoch, frame):
			result[stage_id] = true
	return result
