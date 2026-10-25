# ADR-0007 — Universal persistent terrain imprints for solid mod objects (PROPOSED)

Date: 2026-10-25. Issue [#108](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/108). Design-only PR #126. **Status: PROPOSED — owner approved two operation semantics on 2026-10-25; architectural review pending, no production implementation/migration authorized.** Baseline main `5997a76d345f45bf86edfe83f690336391e8be27`.

## Owner-approved design requirements (not implementation acceptance)

1. A solid object generated/placed partly inside terrain displaces the intersecting soil. This becomes the **default contract for subsequent solid-object mods**, not a rock-specific workaround. Explicit non-solid/decorative opt-out must be schema-validated.
2. Object creation makes a **durable, identity-stable terrain cut imprint**. Subsequent object removal leaves the cut permanently, even when the mod/object is unloaded; a moved object leaves its old cut and may create another cut at the new position under an explicitly defined movement policy.
3. Subsequent CARVE/FILL edits follow defined global temporal order; player FILL after cut can refill terrain unless a separately designed protected-volume rule exists.
4. Excavating support does not move objects today. Physics/gravity/collision will be developed later, with a decoupled physics state and effective-SDF collision representations.
5. No hidden alteration to canonical SDF v1/seed or silent upgrade of existing world/object saves.

## Proposed authority and geometry

Canonical terrain sample remains `SdfWorld.sample_density(...)`. Effective terrain density is the canonical density composed with an **ordered immutable terrain operation ledger** containing ordinary brushes and object-derived cuts. Density sign convention (positive solid) must be verified in executable fixtures; for a cut signed-volume field `c(p)` positive inside, subtraction can take a bounded min with `-c(p)`, subject to sign/normal tests. The cut must represent the solid object's actual intersecting volume within the supported SDF domain and bounded contact margin, not its simple bounding box unless the mod's explicit certified low-detail excavation recipe specifies that approximation. Preserve cave surfaces and avoid near-coplanar Z-fighting with a capped, versioned margin.

Each immutable imprint records: stable globally unique imprint ID derived from source entity ID + lifecycle event ID, world/seed/generator, validated mod-content geometry pin or durable self-contained certified excavation primitive representation, immutable quantized transform, region overlap/AABB, operation sequence and parent command correlation, version, canonical digest and provenance. The footprint is indexed by all affected signed regions/chunks; indexing/cache is derived, not authority. An object being deleted or unloaded does **not** remove its historical imprint. Missing mods must not erase earlier terrain cuts: either retained self-contained geometry or immutable verified archived recipe is a hard prerequisite.

## Transaction boundary and migration gate

Currently object command receipts/schema 3 and terrain ordered CARVE/FILL ledger are separate authorities. They cannot be claimed atomic by writing one and then the other. **Block implementation of automatic durable cuts until a crash-recoverable shared transaction coordinator or single authoritative ledger is specified, implemented and tested.** A candidate design is an append-only world operation journal with prepare/commit/verified replay and deterministic idempotency; visible object and imprint publication must be derived only from a committed operation. Prove restart recovery at every injected interruption point (before prepare, after prepare, after one store, after commit marker, replay), no double cut or orphan entity, stale revision rejection and cross-region consistency. If storage migration is required, add separate schema with explicit two-stage preflight/confirmation, retained immutable previous generation and rollback/recovery plan. Never upgrade live saves automatically.

For automatically populated static procedural rocks, establish creation epochs and identity-stable one-time imprint materialization, independent of region visit order. Do not make cut applicability conditional on currently streamed instances. Unlimited automatic materialization during region enumeration is unacceptable; bound work and persistent space. Legacy pre-existing rocks and saves require an explicit opt-in backfill policy; do not silently excavate an existing world during load.

## Operation semantics to resolve before production

| Action | Proposed terrain behavior | Entity behavior |
|---|---|---|
| Spawn/PLACE intersecting solid | Commit immutable cut once | Spawn stable entity |
| DELETE/F8 | Retain cut | Tombstone entity |
| Undo DELETE / RESTORE F9 | Retain cut, never cut twice | Restore previous overrides / procedural baseline respectively |
| Undo PLACE | **Owner-approved policy**: retain the committed cut when Undo PLACE removes the entity; excavation reversal is a separate explicit terrain command | Tombstone placed entity |
| SET_COMPONENT transform / F7 | **Owner-approved policy**: keep the old imprint and issue a new, idempotent cut at destination only if the moved solid intersects existing effective solid terrain; no redundant cut for unembedded movement | Preserve entity history |
| CARVE then FILL | Respect global operation order, so later FILL can fill old cut | Object stays fixed for now |
| Mod uninstall/content unavailable | Retain self-contained/archived imprint, fail closed on new operations | Existing identity/visual handled separately |

**Key distinction:** entity Undo/Redo is not automatically terrain Undo/Redo. Make this explicit in UI and specifications to avoid promising that Undo PLACE restores terrain. A terrain-specific reversal operation, if desired, is a distinct versioned edit, not implicit deletion of an authoritative historical event.

## Alternatives

| Option | Hole persists after DELETE? | Universal mod policy? | Fit |
|---|---|---|---|
| Visual skirt/contact mask | No | Limited | Reject as authoritative solution; optional cosmetic supplement |
| Transient derived SDF cut from currently loaded entities | No | Yes | Reject: breaks unload and removal persistence |
| Direct destructive mutation of canonical SDF | Potentially | Limited | Reject: violates v1/seed and reconstruction guarantees |
| **Persistent ordered cut imprint event** | **Yes** | **Yes** | **Preferred**, contingent on cross-store transaction design |
| Mesh-only local cut | Depends on cached meshes | Complicated | Reject as authority; optional render optimization |

## Tests and acceptance gate

Fixtures: flat ground, irregular slopes, caves/overhangs, objects partially/fully embedded, no contact, multiple overlaps, negative X/Z, region edges/LOD seams, deterministic load ordering, mesh normals/coplanar contacts, disappearing/disabled mods, content pin changes, large bounded population, CARVE/FILL before/after cut, F7 movement, F8 DELETE, F9 RESTORE, P3.0C undo/redo, region unload/revisit, restart, injected crash/replay, corrupted ledger, storage exhaustion, invalid declarative volumes and security limits. Measure SDF sample candidate-filter count, dirty chunks, mesh rebuild latency, frame p95/p99, disk growth. Compare actual GUI images at fixed seeds/camera/lighting. Preserve five F2-G1 holds.

## Phase gates

P3.1A: finish architecture, transaction/migration contract and mod excavation schema; owner approved Undo PLACE and movement terrain policies on 2026-10-25. P3.1B: isolated single-writer persistent imprint prototype and deterministic SDF integration with focused tests, then independent review. P3.1C: mod-first default integration, editing/revisions/streaming/GUI. P3.1D: physics/collision-facing interfaces only (no promise of dynamic simulation). No code merge without independent review and owner GUI acceptance.
