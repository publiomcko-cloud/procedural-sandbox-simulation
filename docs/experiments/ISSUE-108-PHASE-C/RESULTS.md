# Issue #108 — Phase C Projection / Recovery Results

Status: **PHASE_C_COMPLETE / GATE_C_PASS / PHASE_D_BLOCKED_PRECISION_FRAME**

Phase B base:
`e2bbc94c10d91a1dee4abb1db1f5fc3d08ad2200`

Qualified Phase C code HEAD before this results-only commit:
`b5a48e9a8ca8743f4d47eb207c67e446501ca375`

Phase C implements only the persistent/recoverable projection of
`terrain_object_effect_v1` from authoritative entity/object state.

It does **not** connect effects to live terrain sampling, terrain mesh jobs,
picker/rays, materialized SDF, streaming publication, terrain save mutation, or
`terrain_interaction_applied=true`.

## Authority and recovery model

Entity/object state remains the sole authority.

The terrain-object effect projection is derived and rebuildable. Phase C does
not attempt a distributed transaction between object-state persistence and the
effect projection store.

Instead:

1. entity/object state commits first;
2. the projected regional scope records the authoritative
   `source_world_revision`;
3. each projected effect records its source entity revision and deterministic
   source fingerprint;
4. a source-only commit makes an already loaded regional projection observably
   stale;
5. reconciliation rebuilds that scope from authoritative resolved instances;
6. the validated candidate is persisted before it becomes visible in memory.

A crash between steps 1 and 5 is therefore a recoverable stale projection, not
an ambiguous shared authority.

A persistence failure with an uncertain commit outcome invalidates the
projection service and requires reinitialize/recovery before any later
projection mutation.

## Region-sharded persistence

The initial Phase C prototype used one world-global projection snapshot.
Independent review rejected that design before qualification because an
unbounded world would accumulate every visited effect indefinitely.

The accepted architecture is region-sharded.

Each source region has a spatially computable store:

`terrain-object-effects/regions/r_<x>_<z>/projection-XXXXXXXX.json`

Properties:

- no world-global growing manifest;
- no startup scan of every historical region;
- missing region shard is a valid empty derived scope;
- signed/negative region coordinates are encoded directly;
- immutable generations per region;
- temporary generation recovery is regional;
- corrupt finalized generations fail closed only when that region is loaded;
- one missing/corrupt/rebuilt region does not rewrite neighboring shards;
- old worlds with no projection directory require no migration or write during
  projection-service initialization.

The store retains two finalized generations per regional scope.

## Bounded resident state

World extent and resident projection memory are separate.

The service permits at most **64 resident regional scopes**. Scopes can be
loaded and released independently.

The qualification explicitly verifies:

- exactly 64 scopes can become resident;
- the 65th fails closed with
  `effect_projection_resident_scope_capacity_exceeded`;
- releasing one scope makes capacity reusable.

Each regional projection accepts at most **20,064 source instances/effects**,
matching the current regional authority ceiling of 20,000 explicitly placed
entities plus the existing procedural region budget.

The Phase-B spatial effect index ceiling was aligned to 20,064.

## Regional projection contract

A regional projection snapshot v1 records:

- schema version;
- world identity/seed/generator version;
- deterministic regional scope ID and signed region key;
- projection revision;
- authoritative source world revision;
- deterministic source digest;
- sorted source instance IDs;
- normalized `terrain_object_effect_v1` records.

Validation enforces:

- exact world/scope identity;
- sorted unique source IDs;
- per-scope capacity;
- valid normalized effects;
- one projected effect per source;
- effect source revision not ahead of source world revision;
- exact content and terrain-interaction pins.

## Reconciliation semantics

`TerrainObjectEffectProjectionService.reconcile_command_region()` is a
read-only adapter over the authoritative command/state services.

It:

- enumerates the already reconstructed region base instances;
- resolves each entity through `EntityCommandService.resolve_entity()`;
- excludes deleted entities;
- reads authoritative world/entity revisions;
- constructs effects only from active resolved instances;
- persists before publication;
- removes effects whose authoritative source disappeared;
- recreates a deleted/restored source using the same stable effect ID;
- rejects lower source revisions;
- rejects same-revision/different-fingerprint divergence;
- leaves authoritative object state untouched.

Repeated reconciliation of an unchanged source scope is an idempotent no-op.

## Crash consistency

Each regional generation uses:

1. canonical JSON payload;
2. SHA-256 payload digest;
3. temporary file write;
4. flush;
5. byte-for-byte temporary readback;
6. atomic rename to finalized generation;
7. finalized byte readback.

At load, the highest valid temporary generation can be promoted when no final
file exists.

A corrupt finalized generation is never silently replaced.

The tests simulate a crash by converting the latest finalized generation into
a temporary generation, constructing a fresh service, and requiring regional
recovery to restore the generation and exact normalized effect pins.

## Canonical effect persistence

Phase C exposed two representation issues and closed both before qualification.

First, definition content pins produced by the registry could preserve a
JSON-derived numeric representation for `definition_schema_version`. The
registry now emits canonical string/integer pin fields, matching the existing
state-contract normalization.

Second, Godot JSON round-trip could move the final binary digit of continuous
effect values. One observed example serialized as:

`9.025151079501569`

and parsed/re-serialized as:

`9.025151079501567`.

Continuous normalized effect fields are now canonicalized to 12 decimal places.
For meter-valued fields this is (10^{-12}) m, far below current terrain
sampling resolution, and makes
`validate -> serialize -> parse -> validate` idempotent.

Integral fields and pin schema versions are normalized to integers. IDs, hashes,
content pins and terrain-interaction pins retain exact values.

## Orphan cleanup and lifecycle recovery

Qualification exercises real command-service mutations:

- transform;
- delete;
- restore.

Observed behavior:

- source transform commits independently and makes the projection stale;
- reconciliation preserves stable effect identity while advancing source
  revision/fingerprint;
- delete removes the projected orphan on reconciliation;
- restore recreates the same effect identity at the newer source revision;
- deleting an entire projection shard and rebuilding it from object authority
  reproduces the normalized effect without modifying the authoritative object
  snapshot.

No Phase C code sets `terrain_interaction_applied=true`.

## Compatibility corrections

Phase C also corrected one stale regression fixture:

`game/tests/entity_command_tests.gd`

The copied external declarative package now includes its declared
`interactions/basalt_ground_imprint.json` content root. The previous fixture
copied the updated manifest but omitted the interaction file, causing
`content_root_unavailable` before command behavior was exercised.

This is test-fixture maintenance only.

## Source review

No production Phase C projection file contains concrete first-party, granite,
basalt or example-package IDs.

No Phase C projection file references:

- `TerrainDemo`;
- materialized SDF state;
- terrain mesh publication;
- `MeshInstance3D`;
- `Node3D`;
- renderer meshes as authority;
- `terrain_interaction_applied=true`.

The projection is therefore independent from rendering and live terrain
mutation.

## Exact-head qualification

Qualified code HEAD:
`b5a48e9a8ca8743f4d47eb207c67e446501ca375`

GitHub Actions:

- Starter checks #42211954915: **SUCCESS**
- Issue 108 Phase C projection recovery #42211955018: **SUCCESS**

Godot 4.7.2 results:

- Phase C projection/recovery: **60 assertions, 0 failures**
- Frozen Phase B pure effect: **131 / 0**
- Entity command regression: **67 / 0**
- Declarative mod regression: **79 / 0**
- Procedural object regression: **673 / 0**
- canonical `scripts/validate.sh`: **PASS**

Phase C evidence:

- initial projected effects in region (0,0): 4;
- simulated crash recovered generation: 1;
- final authoritative world revision: 3;
- final target source revision: 3;
- resident scope limit: 64;
- per-scope source/effect limit: 20,064.

## Gate C verdict

**PASS for Phase C projection and recovery.**

The projection is now:

- deterministic;
- derived from entity/object authority;
- crash-recoverable;
- rebuildable;
- region-sharded;
- negative-coordinate-safe;
- bounded in resident memory;
- independent from live terrain/runtime rendering.

## Mandatory precondition before Phase D live integration

Phase D is **not yet authorized to connect the effect evaluator to live terrain
sampling**.

The current `terrain_object_effect_v1`, inherited from Phase B, contains
world-space floating-point planes/bounds and a world-space millimeter anchor.
That is sufficient for the bounded Phase A/B/C characterization ranges and for
derived projection persistence, but it is not an acceptable sampling frame for
an endlessly expandable world.

Before live SDF integration, the effect/sampling boundary must define and
qualify a precision-safe region-local frame, preserving:

- signed integer region identity;
- bounded local coordinates;
- cross-region effect influence;
- deterministic transformed planes/bounds;
- stable effect/source identity and pins;
- persisted-projection rebuild semantics.

This is a **pre-D precision-frame gate**, not a failure of Phase C persistence.

No live terrain integration should begin until that gate is closed.
