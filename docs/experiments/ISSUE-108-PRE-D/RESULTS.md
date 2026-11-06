# Issue #108 — Pre-D Precision Frame Results

Status: **PRE_D_COMPLETE / PRECISION_FRAME_PASS / PHASE_D_AUTHORIZED**

Base Phase C:
`aa487dabb6cfa6420e0cb777923d28ff0f8951ad`

Qualified implementation HEAD before this results-only commit:
`6f4518e90e51cab4ae7493b4f348c5f3a800bf7c`

## Result

The terrain-object effect contract was moved from world-space floating-point
geometry to a precision-safe source-region-local frame.

`terrain_object_effect_v1` identity remains stable, while the normalized
record schema advances to v2:

- `frame = source_region_local_v1`
- signed integer `source_region_key`
- integer `anchor_local_mm`
- bounded `region_planes`
- `bounds_min_local` / `bounds_max_local`
- `interior_point_local`

The persisted effect no longer contains:

- `anchor_world_mm`
- `world_planes`
- global `bounds_min` / `bounds_max`
- `interior_point_world`

Cross-region sampling translates only the bounded integer delta between the
sample region and source region. It never forms `region_key * region_size` as
a large floating-point world coordinate.

The effect index likewise maps local bounds to global chunk identities using
integer region/chunk arithmetic.

## Extreme-coordinate qualification

Identical source-local geometry was built at:

- region `(0, 0)`
- region `(100000000, 100000000)`
- region `(-100000000, -100000000)`

All three produced exactly identical local planes, local bounds and local
interior geometry.

Observed cutter value at the same local physical point:

`-0.562371838142982`

for all three regions.

The test also qualified:

- positive and negative extreme-region chunk indexing;
- cross-region seam indexing;
- equivalent physical-point sampling through a neighboring region;
- bounded region-delta fail-closed behavior;
- stable effect identity across frame location;
- source fingerprint sensitivity to signed source-region identity.

## Qualification

Workflow: Issue 108 pre-D precision frame #42214473280 — **SUCCESS**

- Pre-D precision frame: **22 assertions / 0 failures**
- Phase B effect contract: **131 / 0**
- Phase C projection/recovery: **60 / 0**
- Entity command regression: **67 / 0**
- Declarative mod regression: **79 / 0**
- Procedural object regression: **673 / 0**
- canonical `scripts/validate.sh`: **PASS**

Evidence:

- schema version: 2
- frame: `source_region_local_v1`
- positive test region: `(100000000, 100000000)`
- negative test region: `(-100000000, -100000000)`
- max hot-path region delta: 64
- far effect indexed chunk count: 4

## Scope boundary

This gate removes the precision blocker from the **terrain-object effect
representation and evaluator**.

It does not claim that every pre-existing subsystem in the engine is already
precision-safe at arbitrary world coordinates. Existing terrain/edit/runtime
code still contains historical world-space floating-point paths. Phase D must
not reintroduce those paths into terrain-object effect evaluation.

## Gate verdict

**PASS. Phase D live integration is authorized**, provided it:

1. carries only immutable validated effect snapshots into workers;
2. composes `base/materialized terrain -> player edits -> object effects`;
3. uses region-local effect sampling;
4. includes effect snapshot identity in cache/stale-result semantics;
5. preserves shared-surface consistency;
6. keeps renderer meshes non-authoritative;
7. does not set `terrain_interaction_applied=true` until the authoritative
   terrain-side application/recovery contract is satisfied.
