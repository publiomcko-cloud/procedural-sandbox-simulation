class_name DM20SnapshotGuard
extends RefCounted

## A primed snapshot can be consumed ONLY by the originating stage/job and
## exact terrain/effect revisions. This is a cache of a CPU snapshot, not a
## second authority; source and edit writes invalidate the original stage.

static func valid(primed: Dictionary, stage: Dictionary,
		coordinate: Vector2i, brush_scope_id: int, brush_revision: int,
		current_effect_revision: int) -> bool:
	if primed.is_empty() or not primed.get("coordinate") is Vector2i:
		return false
	if primed["coordinate"] != coordinate:
		return false
	for key in ["token", "brush_revision", "brush_scope_id", "effect_revision", "snapshot"]:
		if not primed.has(key):
			return false
	if int(primed["token"]) != int(stage.get("stage_token", -1)) \
	or int(primed["brush_revision"]) != brush_revision \
	or int(primed["brush_scope_id"]) != brush_scope_id \
	or int(primed["effect_revision"]) != current_effect_revision \
	or int(stage.get("edit_revision", -1)) != brush_revision \
	or int(stage.get("terrain_effect_authority_revision", -1)) != current_effect_revision:
		return false
	var snapshot: Dictionary = primed["snapshot"]
	return not snapshot.is_empty() \
		and int(snapshot.get("terrain_effect_authority_revision", -1)) \
			== current_effect_revision
