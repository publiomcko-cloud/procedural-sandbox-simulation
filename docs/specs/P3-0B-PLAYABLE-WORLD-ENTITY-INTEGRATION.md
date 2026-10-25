# P3.0B — Playable World Transactional Entity Integration

**Status:** implementation candidate on `feat/p3-0b-playable-world-entity-commands`; independent source review and owner GUI retest pending. This specification describes the candidate and is not product acceptance.

## Scope

P3.0B connects the renderer-independent P3.0A command service to the playable terrain scene. Entity identity and mutable state remain in the P2.0B object-state store; procedural population and package pins remain provided by P2.0C; scene nodes and batches remain disposable presentation. The terrain world-save schema 1 and its store are unchanged.

The stream owns one `ProceduralObjectStateService` and one `EntityCommandService` for the loaded world/seed. The command service is initialized only when the object-state snapshot is already command schema 2. Reading schema 1 never changes it. The owner must explicitly press **M** once to preflight and again within six seconds to commit the schema upgrade. The preflight validates the candidate snapshot and reports source/candidate canonical-payload hashes. The existing immutable generation is retained by the store during commit. No automatic schema migration occurs.

After migration, every resident region is queued for forced publication through the existing bounded region queue. The command interface remains unavailable until those resident publications rebuild the service's region identity cache. The stream processes at most the existing configured number of region publications per process tick. A failed publication leaves the previous complete visual root in place, keeps command migration readiness blocked for that region, and requires a later retry (M) or region lifecycle action. Persistence already committed by a command is not rolled back because a later visual publication failed.

## State and command flow

The authoritative flow is:

`player viewport input → command construction → P3.0A validation/revision/idempotency → single P2.0B-backed persistent commit → bounded region rebuild/publication`.

Commands carry schema, command UUID, local-player origin, world identity/seed/generator, expected world revision and (for existing entities) expected entity revision. `ENTITY_PLACE` additionally carries a registered definition ID, canonical region, world-space integer millimeter position, recipe seed, and declared version-1 component records. The accepted definition is pinned by the registry during preparation. Its explicit instance ID derives from the command UUID and is distinct from procedural population IDs; retries with the same UUID and canonical payload return the retained receipt, while a conflicting payload is rejected. Receipt-capacity and retention semantics remain those of P3.0A; this is durable idempotency within retained receipts, not a claim of exactly-once execution without limit.

The command service and P2.0B state service are not parallel authorities: the dispatcher commits candidates through the existing state service and store. Region reconstruction combines deterministic procedural instances and explicit placed-instance records, then resolves sparse overrides and deletion tombstones before creating visual nodes or batches. Explicit world positions are converted to region-local millimeters exactly once; the region root supplies the world origin. A transform whose effective position changes canonical region ownership is rejected with `component_transform_region_transfer_not_supported`; region transfer is not implicit.

Pre-commit command validation/revision/persistence failures do not queue a visual change. After a successful commit, visual refresh is queued for the affected resident region. The HUD distinguishes command rejection, committed/queued visual work, successful publication, and committed state whose visual publication failed. Unloaded regions require no resident node; restore commits the same identity and its next region publication reconstructs it.

## Playable controls

| Input | Behavior |
| --- | --- |
| Ctrl+left click | Select an individual or batched entity under the pointer, subject to terrain occlusion |
| B | Place a registered definition at the terrain surface under the camera crosshair; reject when no hit or the target region is not fully published |
| F6 | Cycle active stable entity identities |
| F7 | Submit transform then appearance as two separate revision-checked `ENTITY_SET_COMPONENT` commands |
| F8 | Submit `ENTITY_DELETE` for the selected identity |
| F9 | Submit `ENTITY_RESTORE` for the selected deleted identity, or the latest retained deletion when none is selected |
| M, then M again within 6 s | Preflight, then explicitly commit object-state schema 1→2; wait for resident regions to finish rebuilding |

Existing terrain controls (WASD/arrows, mouse orbit/zoom, left/Shift+left, C/R/X/L, P/O and V) remain. Key handling accepts logical or physical key codes. F6–F9 keep their familiar functions but the playable scene routes their writes through the transactional command service. Older stream mutator methods remain for P2 compatibility tests/internals; they are not used by these scene controls.

## Selection and batching

Selection uses stable instance records exposed by the stream and a bounded ray/sphere broad-phase derived from declarative geometry bounds. Static batch members retain individual selection records and IDs without being permanently unbatched into individual nodes. This is approximate object selection, not triangle-accurate picking or a physics/collision system. The terrain picker is used to reject a candidate hidden behind a nearer terrain surface.

The HUD reports selected ID, definition, identity kind, global/entity revisions and logical deletion state. Visual records are derived and can be rebuilt from recipe, pins, placement identity and persisted overrides.

## Storage and failure rules

- Terrain saves stay schema 1 in the existing terrain save store.
- Object-state schema 1 is read compatibly; schema 2 is opt-in via the explicit M preflight/commit UI.
- The prior object-state generation remains available through the store's generation retention/recovery contract.
- A failed/uncertain durable commit is fail-closed by the P2.0B service; no successful visual effect is reported.
- A command committed before an object mesh or region publication error remains committed. The old complete region root remains visible and the HUD reports the visual failure; retry/reload can rebuild from authoritative state.
- Missing definitions/pins, invalid origin, stale revisions, deleted state and cross-region transforms are rejected before commit.
- Unload removes only transient region/cache state. A revisit reconstructs from the same store and registered content pins.

## Validation evidence and limits

The candidate adds a disposable fixture for procedural and batch picking, schema migration and compatibility, explicit placement, negative ownership, component updates, stale revisions, identity conflicts, missing packages, persistence failure, visual-publication failure, obsolescence, delete/restore across unload/revisit and service restart. The existing playable-scene suite exercises M and F6–F9 through `Viewport.push_input`, including the rejected repeated delete and unchanged visual state.

Full `scripts/validate.ps1` results are recorded in the implementation checkpoint. All runtime checks are headless developer-run evidence. They do not prove OS window focus, owner visual acceptance, GPU completion, frame performance, cross-process writer exclusion, or power-loss durability. Exploratory microsecond measurements are synthetic/headless only. No physical collision, terrain/object conformation, networking, generalized ECS, executable mod code, full undo/redo or release readiness is included. Issue #108 remains deferred.

## Owner GUI retest

Use a disposable new world or back up the local object-state directory before testing. Launch the main scene. If the HUD reports schema 1, press M once and inspect the no-write preflight result, then press M again within six seconds; wait until the dispatcher reports READY after the resident-region rebuild. Use Ctrl+left on a nearby procedural rock, F6 to cycle, F7 to change transform/appearance, F8 to verify only the selected rock disappears, and F9 to restore the same identity. Press F8 again to verify a clear rejection and no visual change. Press B with a visible terrain surface under the crosshair to place a new entity; verify its ID, definition and placement. Move across a region boundary and return to verify no duplicate/lost entity, then restart the scene/process to verify the committed state reconstructs. Inspect the HUD after each step and confirm terrain controls still respond. Record owner GUI outcomes separately; headless PASS is not visual acceptance.
