class_name TerrainStreamProgressiveLoadPolicy
extends RefCounted

## Presentation-only, pristine LOAD stages. Nothing in this policy grants
## object/simulation publication or overrides authoritative revision checks.
static func eligible(
	stage: Dictionary, active_region: bool, rebuild_pending: bool,
	edit_transaction_pending: bool, historical_edits: bool, cave_section: bool
) -> bool:
	return String(stage.get("purpose", "")) == "load" \
		and not active_region and not rebuild_pending \
		and not edit_transaction_pending and not historical_edits \
		and not cave_section


static func current(
	stage: Dictionary, stage_token: int, brush_revision: int,
	effect_revision: int
) -> bool:
	return int(stage.get("stage_token", -2)) == stage_token \
		and int(stage.get("edit_revision", -2)) == brush_revision \
		and int(stage.get("terrain_effect_authority_revision", -2)) == effect_revision


## Submit interior first, then face-edge, then corners, preserving the
## full 16-chunk set and existing shared-boundary algorithms.
static func interior_first(coordinates: Array[Vector2i], count_x: int, count_z: int) -> Array[Vector2i]:
	var ordered: Array[Vector2i] = coordinates.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ea := int(a.x == 0 or a.x == count_x - 1) + int(a.y == 0 or a.y == count_z - 1)
		var eb := int(b.x == 0 or b.x == count_x - 1) + int(b.y == 0 or b.y == count_z - 1)
		if ea != eb:
			return ea < eb
		var da := absi(2 * a.x + 1 - count_x) + absi(2 * a.y + 1 - count_z)
		var db := absi(2 * b.x + 1 - count_x) + absi(2 * b.y + 1 - count_z)
		if da != db:
			return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return ordered


static func valid_chunk_publication(
	stage: Dictionary, coordinate: Vector2i, active_region: bool,
	rebuild_pending: bool, edit_transaction_pending: bool,
	historical_edits: bool, cave_section: bool,
	brush_revision: int, effect_revision: int
) -> bool:
	return eligible(
		stage, active_region, rebuild_pending,
		edit_transaction_pending, historical_edits, cave_section
	) and current(
		stage, int(stage.get("stage_token", -1)), brush_revision, effect_revision
	) and stage.get("meshes", {}).has(coordinate)
