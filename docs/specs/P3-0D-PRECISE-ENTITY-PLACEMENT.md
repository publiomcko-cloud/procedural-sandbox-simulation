# P3.0D — Precise Entity Placement Contract

Status: implementation candidate on PR #124; independent source review and owner GUI retest pending. This contract does not approve merge.

## Aim selection

Pressing `B` places an explicit entity at the terrain surface selected by the current placement aim:

- If the cursor is visible and its last viewport-space pointer position lies inside the viewport's visible rectangle, use that pointer position.
- If the cursor is captured/hidden or no in-viewport pointer position is available, use the center of the visible viewport as the navigation fallback.
- The placement indicator and `B` use the same `_placement_target_at()` ray/SDF query. The marker shows a valid hit, and its color distinguishes a published target region from one that is not ready for placement.
- A missing surface, unsupported world coordinate, or target whose terrain/object region is not published rejects placement before issuing `ENTITY_PLACE`.

The ray is produced by `Camera3D.project_ray_origin()` and `project_ray_normal()` using viewport coordinates. `BrushPicker.pick_sdf_v1_surface()` selects the first SDF v1 surface crossing. The resulting world-space hit is quantized to integer millimeters. The canonical region owner is then calculated from those quantized world coordinates using `SpatialGrid.world_to_region_local()` and its floor-based ownership rule. The persisted region key and position therefore describe the same quantized point, including negative coordinates and region planes.

## Entity anchor

The persisted world millimeter position is the entity's placement anchor. For the current rock definitions, the procedural mesh root is the center of the base/contact plane (`local y = 0`). That anchor coincides with the SDF hit. The mesh is not rotated to match a slope and is not offset randomly. Repeated placements at the same target are allowed and receive distinct command/entity identities. Terrain/object conformation remains deferred to Issue #108.

## Persistence and compatibility

Placement continues through the existing schema-3 `ENTITY_PLACE` command and object-state stream. Command IDs, entity identities, content pins, receipts, revision checks, history, region ownership, and existing saves are not reinterpreted or migrated by this change. Undo/redo, delete/restore, streaming unload/revisit, and restart reconstruction retain the same global millimeter anchor and single visual identity.

No production SDF, brush ledger, region streamer, population generator, save schema, package format, mod execution, or terrain mesh code is changed. F7/F8/F9 and the existing terrain controls retain their prior meaning.

## Verification boundary

The automated test uses real `Viewport.push_input()` mouse events and the playable scene with disposable isolated storage. It checks distinct screen targets, repeated-target stability, viewport scaling, non-flat terrain, positive/negative ownership boundaries, unavailable surfaces, unpublished regions, history, restart and region revisit. Godot headless does not establish OS cursor focus/visibility or visual marker appearance. Those require the owner's GUI retest.

The mesh anchor convention does not assert visual terrain contact on slopes or eliminate overlap between intentionally co-located placements. No claim is made about GUI acceptance, GPU output, protected F2-G1 state, or release readiness.
