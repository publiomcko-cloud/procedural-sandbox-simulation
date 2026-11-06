# Issue #108 — Pre-D Precision Frame Gate

Status: **PRE_D_COMPLETE / PRECISION_FRAME_PASS / PHASE_D_AUTHORIZED**

Base Phase C HEAD:
`aa487dabb6cfa6420e0cb777923d28ff0f8951ad`

Qualified implementation HEAD:
`e4d7e375fdc4f3800607581b9cb06af668cedb26`

## Problem

Phase-B/C `terrain_object_effect_v1` stores world-space floating-point
planes/bounds. That record remains valid as a derived/persistent compatibility
artifact, but it is not an acceptable live sampling frame for an endlessly
expandable world.

## Accepted solution

A separate precision-safe runtime frame is introduced:

`terrain_object_effect_local_frame_v1`

It is derived directly from the authoritative instance and never reconstructs a
global floating-point position.

Horizontal addressing is represented by:

- signed integer `source_region_key`;
- signed integer `frame_region_key`;
- normalized region-local millimeter origin;
- bounded region-local planes and bounds.

Translation crossing a region edge is normalized with integer floor ownership.
Negative coordinates therefore use the same ownership rule as terrain chunks.

Sampling converts a target `region_key + local_position` into the effect frame
using only a bounded integer region delta. Queries outside the bounded indexed
delta fail closed.

## Spatial index

`TerrainObjectEffectLocalIndex` derives chunk membership without world-space
floats.

It combines:

- integer frame region;
- local effect bounds;
- integer global-chunk arithmetic;
- signed floor mapping back to region/chunk IDs.

Cross-region +X and -X seams were qualified at very large positive and negative
region coordinates.

## Precision qualification

The same rock geometry was built at:

- region `(0, 0)`;
- region `(100000000, 100000000)`;
- region `(-100000000, -100000000)`.

Local planes, bounds, origin, shape descriptor and transforms remained
identical. Only integer region identity changed.

The cutter value at equivalent local interior points was bit-identical across
all three placements:

`-0.562373745491961`

The tests also qualify:

- +X/+Z integer carry;
- negative floor carry;
- cross-region indexing at +/-100M regions;
- identical sampling of one physical point represented from either side of a
  region seam;
- bounded-query fail closed;
- canonical JSON round-trip;
- exact content and terrain-interaction pins;
- absence of `world_planes`, global bounds and `anchor_world_mm` from the
  precision-safe frame.

## Compatibility

The existing Phase-B effect record and Phase-C projection remain unchanged.
The precision-safe frame is a separate derived runtime representation.

This prevents a migration or retrofit of already-qualified persistence while
giving Phase D a safe sampling boundary.

## Exact-head qualification

Workflow: Issue 108 Pre-D precision frame #42229388153 — **SUCCESS**

Godot 4.7.2:

- Pre-D precision frame: **32 assertions / 0 failures**
- Frozen Phase C: **60 / 0**
- Frozen Phase B: **131 / 0**
- canonical `scripts/validate.sh`: **PASS**

## Gate verdict

**PASS. Phase D live integration is authorized only through
`terrain_object_effect_local_frame_v1` and its local index.**

Phase D must not evaluate the legacy world-space effect planes in live SDF
sampling.
