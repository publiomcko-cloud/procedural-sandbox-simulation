extends RefCounted
class_name TerrainCoarsePreviewPolicy

## E2 may only show the pristine base top surface for an unedited LOAD stage.
## It never changes canonical mesh/physics/interaction/publication authority.
static func eligible_stage(
	profile: String, stage: Dictionary, has_active_region: bool,
	global_rebuild: bool, edit_pending: bool, has_any_brush_edits: bool,
	cave_section: bool
) -> bool:
	return profile in ["adaptive-skip-coarse", "adaptive-skip-coarse-projection"] \
		and String(stage.get("purpose", "")) == "load" \
		and not has_active_region and not global_rebuild \
		and not edit_pending and not has_any_brush_edits and not cave_section


## Single gate for in-flight completion AND retaining a visible preview.
## Stage identity, source revisions, seed, generator and visibility window are
## all checked. No preview node may grant terrain/object publish permission.
static func revision_matches(
	stage: Dictionary, record: Dictionary,
	world_seed: int, generator_version: int, current_brush_revision: int,
	current_effect_revision: int, focus: Vector2i, has_active_region: bool,
	global_rebuild: bool, edit_pending: bool, has_any_brush_edits: bool,
	cave_section: bool
) -> bool:
	if not eligible_stage(
		"adaptive-skip-coarse", stage, has_active_region, global_rebuild,
		edit_pending, has_any_brush_edits, cave_section
	):
		return false
	var key: Vector2i = stage.get("region_key", Vector2i(-2147483647, -2147483647))
	if key != record.get("region_key", Vector2i(-2147483647, -2147483647)):
		return false
	if maxi(absi(key.x - focus.x), absi(key.y - focus.y)) > 1:
		return false
	return int(record.get("stage_token", -1)) == int(stage.get("stage_token", -2)) \
		and int(record.get("seed", -1)) == world_seed \
		and int(record.get("generator_version", -1)) == generator_version \
		and int(record.get("edit_revision", -1)) == current_brush_revision \
		and int(stage.get("edit_revision", -2)) == current_brush_revision \
		and int(record.get("effect_revision", -1)) == current_effect_revision \
		and int(stage.get("terrain_effect_authority_revision", -2)) == current_effect_revision
