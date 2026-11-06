# Issue #108 — Pre-D Precision Frame Results

Status: **PRE_D_COMPLETE / GATE_PRE_D_PASS**

Qualified code HEAD:
`945e99ba4410b3848999d2f26c8b5f10ef52e778`

Phase C base:
`aa487dabb6cfa6420e0cb777923d28ff0f8951ad`

## Goal

Remove world-space floating-point coordinates from the live terrain-object
sampling boundary before Phase D connects object effects to the authoritative
terrain SDF.

## Accepted frame

Live terrain-object effects now use a source-region-local frame:

- signed integer `source_region_key`;
- bounded local planes;
- bounded local AABB and interior point;
- integer source/entity revision;
- stable effect/source identity;
- deterministic source fingerprint;
- deterministic frame SHA-256.

A query in another region converts into the source frame using only the signed
integer region-key delta multiplied by the fixed region dimensions. No absolute
world-space floating-point position is constructed by the live effect
evaluator or the live effect index.

The older world-space planes/bounds remain in `terrain_object_effect_v1` only
as Phase-B compatibility/audit data. They are not live sampling authority.

## Persistence

Projection schema advances from 1 to 2 and persists the local frame next to the
legacy effect record.

Schema-1 Phase-C shards are recognized as derived legacy state and rebuilt from
authoritative entity/object state. They are not treated as authoritative
corruption and no entity-state migration is required.

## Extreme-coordinate qualification

The same interacting object was evaluated at:

- region `(0,0)`;
- region `(100000000,100000000)`;
- region `(-100000000,-100000000)`.

The local planes and bounds were invariant. The interior cutter value was
identical at all three locations:

`-0.568276423736922`

Cross-region representation of the same physical point also produced the same
sample, and the local index preserved influence across a regional seam at
extreme signed coordinates.

## Exact-head qualification

- Pre-D: **20 assertions / 0 failures**
- Phase C regression: **60 / 0**
- frozen Phase B regression: **131 / 0**
- canonical validation: PASS on the final combined Phase-D gate.

Evidence:

`ISSUE108_PRE_D_EVIDENCE={"baseline_cutter":-0.568276423736922,"edge_indexed_chunk_count":4,"negative_cutter":-0.568276423736922,"negative_region":[-100000000,-100000000],"positive_cutter":-0.568276423736922,"positive_region":[100000000,100000000],"projection_schema_version":2}`

## Verdict

The precision-frame blocker identified after Phase C is closed.

Phase D is authorized to use only the region-local frame for live terrain-object
sampling.
