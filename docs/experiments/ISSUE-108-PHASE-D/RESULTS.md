# Issue #108 — Phase D Live Terrain-Object SDF Integration Results

Status: **PHASE_D_SOURCE_CI_PASS / GUI_ACCEPTANCE_REQUIRED**

Qualified code HEAD:
`945e99ba4410b3848999d2f26c8b5f10ef52e778`

Base:
`aa487dabb6cfa6420e0cb777923d28ff0f8951ad`

## Live SDF composition

The live terrain sampler now composes:

1. canonical procedural/materialized terrain;
2. player CARVE/FILL edits;
3. active terrain-object imprints;
4. cave-section diagnostic cut.

This implements `terrain_edits_then_imprint_v1`.

An anchored object therefore re-applies its active imprint after player FILL.
If the object is removed, its derived imprint disappears and the accumulated
player terrain edit becomes visible again.

The entity/object state remains the sole authority. No renderer mesh or scene
node becomes terrain authority.

## Runtime projection

A domain-only `TerrainObjectEffectRuntime`:

- reads authoritative resolved object/entity state;
- reconciles the region-sharded derived projection;
- builds immutable local-frame snapshots per terrain job;
- injects only frames whose conservative footprint touches the requested chunk;
- bounds resident projection scopes;
- supports signed regions and cross-region effects;
- invalidates by source region on entity lifecycle changes;
- rejects stale mesh stages when entity authority changes.

The shared X/Z/corner paths receive the same immutable effect snapshot, and
shared-surface/incremental cache keys include the effect snapshot hash.

## Entity lifecycle

Placement, transform, delete, restore, undo and redo invalidate the affected
source region.

After optimization, the runtime compares old/new local-frame hashes and
remeshes only the union of chunks touched by the changed old/new effect
footprints. Unrelated source regions are not rebuilt merely because the global
entity world revision advanced.

A derived projection that is ahead of a newly loaded/rolled-back authoritative
save can be explicitly rebuilt from that current authority. Generic stale
reconcile calls still fail closed.

## Picking and placement

Brush picking, placement picking and terrain occlusion selection now use the
same effect-aware SDF as meshing.

Placement normals are estimated through the same immutable live SDF sampler as
the hit itself.

The previous test invariant that a repeated aim must return the same pre-object
anchor was retired: after #108 a placement changes the authoritative live SDF,
so a repeated aim is required instead to persist the exact current
post-imprint hit.

The placement target marker is refreshed after the terrain effect remesh.

## LOD

Effect-bearing chunks currently force a deterministic LOD0 fallback with:

`terrain_effect_precision_frame_requires_lod0`

Effect-free chunks retain the existing LOD path.

This is a controlled correctness limitation. A future LOD1 implementation must
consume the same precision-safe region-local effect frame before the fallback
can be removed.

## Phase C compatibility

A real schema-1 Phase-C projection envelope is qualified in the Phase-D suite.
Schema 2 recognizes it as derived legacy data and rebuilds it into a new
generation from entity/object authority without migrating that authority.

## Performance correction

The first live implementation remeshed every chunk in all active regions within
a conservative radius after each object lifecycle mutation. It was correct but
too expensive.

The accepted implementation invalidates/reconciles the changed source scope and
remeshes only changed effect footprint chunks.

On the same GitHub runner, the full placement campaign improved from about
**57 s to 23 s**.

Observed milestones:

- isolated scene publication: about **4.7 s -> 3.3 s**;
- repeated-placement imprint publication: about **5.9 s -> 0.38 s**.

These are headless CI characterization numbers, not formal product latency
budgets.

## Exact-head qualification

Workflow run: **42229070219 — SUCCESS**

- Pre-D precision frame: **20 / 0**
- Phase D live SDF: **22 / 0**
- P3.0D placement: **53 / 0**
- global shared surface: **159 / 0**
- incremental shared surface: **43 / 0**
- Phase C recovery: **60 / 0**
- frozen Phase B: **131 / 0**
- terrain SDF canonical suite: **46 / 0**
- `scripts/validate.sh`: **VALIDATION_PASS**
- Starter checks: SUCCESS

Phase-D evidence:

`ISSUE108_PHASE_D_EVIDENCE={"cutter_interior":-0.568276423736922,"fill_density_with_effect":-0.568276423736922,"fill_density_without_effect":1.71221392345934,"left_effect_count":1,"right_effect_count":1,"runtime_loaded_scopes":30,"shared_left_triangles":580,"shared_right_triangles":572}`

The FILL probe demonstrates the ordering contract directly: without the object
effect the density is positive `1.71221392345934`; with the anchored imprint
it becomes `-0.568276423736922`.

## Source review

New Phase-D domain/runtime files contain no concrete granite/basalt/first-party
content IDs and do not use renderer nodes as authority.

`terrain_interaction_applied` remains compatibility metadata and is not used as
a cross-store commit flag. The live terrain effect is derived from the
authoritative entity/object state and the recoverable projection.

## Remaining owner gate

Source/CI qualification passes. GUI visual acceptance is still required before
integration.

Owner GUI checks should include:

- rock-to-ground contact and absence of visible intersection gap;
- seams/corners across region boundaries;
- placement marker against post-imprint terrain;
- place / transform / delete / restore / undo / redo;
- CARVE and FILL near an anchored object;
- free exploration and streaming unload/revisit;
- perceptible placement/remesh latency;
- unexpected artifacts when objects are near chunk/region boundaries.

No merge is authorized by this result.
