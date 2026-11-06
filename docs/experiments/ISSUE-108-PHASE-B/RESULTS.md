# Issue #108 — Phase B Pure Effect Results

Status: **PHASE_B_COMPLETE / GATE_B_PASS / PHASE_C_READY_NOT_STARTED**

Phase A base: `efa93af61eee0f8654fdbbb9993d8dc099e7b25e`

Qualified code HEAD before this results-only commit:
`6484ff1dc0474626be27c03fa66cfe42fde63046`

Phase B intentionally does **not** integrate terrain-object effects into the live terrain runtime, persistence, entity lifecycle, meshing, picker or streaming publication.

## Implemented domain components

### Shared procedural rock shape authority

Added:

`game/scripts/objects/procedural_rock_shape_descriptor.gd`

`ProceduralRockShapeDescriptor` is a pure `RefCounted` domain component. It owns the deterministic `geological_halfspace_v1` shape construction used by both visual geometry and future terrain effects:

- recipe/profile validation;
- primary deterministic clipping planes;
- anisotropic fracture planes;
- bevel planes;
- deterministic weathering;
- deterministic coherent roughness;
- shortest-incident-edge roughness safety cap;
- grounding shift;
- analytic convex half-space descriptor;
- conservative guard;
- deterministic descriptor SHA-256.

The descriptor creates no `Mesh`, `Resource`, `RenderingServer` or scene-node authority.

### Renderer deduplication

`ProceduralRockMeshAdapter` was reduced to a renderer adapter over
`ProceduralRockShapeDescriptor.build_geometry_data()`.

This removes the prior risk that terrain-authoritative shape logic and visual rock generation could drift into two independent algorithms.

Existing visual/procedural behavior remains covered by the full procedural-object regression suite.

### Terrain object effect v1

Added:

`game/scripts/terrain/terrain_object_effect.gd`

The normalized `terrain_object_effect` v1 record carries:

- stable effect ID;
- source instance ID;
- source revision;
- deterministic source fingerprint;
- world identity/version;
- definition ID;
- exact content pin;
- exact terrain-interaction pin;
- shape descriptor version/SHA;
- algorithm/shape source/operation/edit order;
- `interior_eased_subtract_v1` blend mode;
- embed/blend parameters;
- canonical anchor;
- resolved translation/rotation/scale;
- transformed unit half-space planes;
- conservative world bounds;
- interior point.

The effect ID is stable across source revisions/transform changes. The source fingerprint changes when the source state that defines the effect changes.

The builder rejects:

- missing or malformed source fields;
- mismatched content pins;
- mismatched terrain-interaction pins;
- contradictory explicit world anchors;
- unsupported interaction contracts;
- invalid transform/scale;
- invalid normalized effect records.

`terrain_interaction_applied` is not mutated.

### Exact transform semantics

The effect evaluator supports the same effective transform semantics as object visualization:

- region-local base anchor;
- explicit world-anchor consistency check when present;
- default yaw/scale;
- full `core.transform` translation/rotation/scale override;
- non-uniform scale.

Local half-space planes are transformed analytically using the inverse-transpose plane transform. Renderer mesh data is not sampled to construct the terrain cutter.

### Pure SDF evaluator

The evaluator implements the Phase-A frozen contract:

- positive density = solid;
- negative density = empty;
- `subtract_solid_v1`;
- `interior_eased_subtract_v1`;
- zero influence outside the cutter;
- hard subtraction after the interior blend depth.

Multiple effects are evaluated in stable lexical `effect_id` order, making overlapping-effect replay independent from discovery/insertion/visit order.

Two APIs are provided:

- safe APIs that validate normalized effect records;
- explicit `*_prevalidated` APIs for a future immutable snapshot hot path.

The prevalidated path is semantically tested against the safe path and avoids full structural validation at each SDF lattice sample.

### Bounded spatial index

Added:

`game/scripts/terrain/terrain_object_effect_index.gd`

This is a derived in-memory index, not persistence authority.

Properties:

- maximum 20,000 resident effects;
- maximum 256 candidate chunks per effect;
- 0.5 m sampling halo;
- deterministic effect ordering;
- negative-coordinate-safe floor ownership;
- cross-region chunk indexing;
- replace semantics remove stale old-footprint memberships;
- deterministic chunk snapshot SHA-256.

The index currently provides pure candidate snapshots only. It is not connected to terrain meshing or streaming.

## Qualification matrix

The Phase-B tests exercise:

- first-party granite;
- explicit external basalt example;
- independent synthetic external geological profile;
- multiple deterministic recipe seeds;
- descriptor determinism;
- conservative containment of final CPU geometry;
- roughness guard bounds;
- exact terrain-interaction pin carry;
- exact descriptor SHA carry;
- stable effect identity;
- revision/transform-sensitive source fingerprint;
- translation;
- full Euler rotation;
- non-uniform scale;
- malformed pin rejection;
- malformed plane rejection;
- world-anchor contradiction rejection;
- interior subtraction;
- exterior no-op;
- zero-radius hard subtraction;
- safe/prevalidated evaluator equivalence;
- deterministic overlapping-effect order;
- +X region seam indexing;
- negative-region seam indexing;
- stale-footprint removal after replacement;
- effect removal;
- existing procedural-world instance compatibility.

## Exact-head evidence

Qualified code HEAD:
`6484ff1dc0474626be27c03fa66cfe42fde63046`

- Phase B pure effect: **131 assertions, 0 failures**
- Phase A grounding characterization: **79 / 0**
- Phase A half-space characterization: **77 / 0**
- Phase A contact formula characterization: **27 / 0**
- Declarative mod regression: **79 / 0**
- Procedural object regression: **673 / 0**
- Canonical `scripts/validate.sh`: **PASS**
- Starter checks: **PASS**

Observed maximum descriptor guards in the Phase-B seed matrix:

- first-party granite: **27.693 mm**
- external basalt: **30.851 mm**
- independent synthetic profile: **31.732 mm**

Every tested final CPU vertex was contained by the corresponding guarded descriptor; maximum observed containment violation was **0.0 m**.

## Corrections discovered during Phase B

The first qualification exposed two implementation/harness defects and both were corrected before qualification:

1. The clipping point buffer retains vertices removed from all published faces. These dead points have no incident published triangle and therefore cannot participate in the roughness safety guard. The shared descriptor now excludes them from guard derivation while preserving the generator's existing grounded point-buffer semantics.
2. A test fixture passed an untyped array to the registry's typed `Array[String]` API. The fixture now uses the declared registry type.

The first implementation also duplicated geological construction logic between the mesh adapter and descriptor. Independent source review treated this as an architectural drift risk even though tests passed. The duplication was removed: both renderer and terrain-effect domain now consume one shared pure geometry core.

## Source review

No production Phase-B file contains concrete first-party, granite, basalt or example-package IDs.

No terrain-effect domain component depends on:

- `TerrainDemo`;
- live terrain state;
- materialized SDF storage;
- entity command persistence;
- scene nodes;
- renderer meshes as terrain authority.

The only renderer-facing Phase-B change is the mesh adapter delegating shape generation to the shared pure core.

## Gate B verdict

**PASS.**

Phase B has produced a deterministic, versioned, mod-first, renderer-independent effect representation and bounded candidate index suitable for Phase C.

Phase C may implement the effect projection/recovery layer and store, including:

- persistent terrain-effect projection;
- exact interaction-pin persistence;
- source/effect revision reconciliation;
- orphan cleanup;
- crash recovery;
- old-world compatibility;
- projection rebuild from authoritative entity/object state.

Phase C has **not** started.

No live terrain sample, mesh job, picker, streaming state, save format or entity lifecycle currently consumes `terrain_object_effect_v1`.
