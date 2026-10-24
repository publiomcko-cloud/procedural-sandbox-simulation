# P2.0B — Persistent procedural object state (implementation candidate)

Date: 2026-10-24
Status: implemented on `feat/p2-0b-persistent-object-state`; draft PR/source review and owner GUI verification pending. This specification records the candidate contract; it is not a merge or visual-acceptance decision.

## Scope and authority

P2.0B separates the P2.0A procedural recipe and placement identity from sparse mutable instance state. `ProceduralObjectWorld` remains the deterministic source of baseline instances. `ProceduralObjectStateService` is the model authority for persisted overrides and logical deletions. `ProceduralObjectStream` creates and releases only transient `Node3D`/mesh representatives for successfully published terrain regions.

The existing P0.3 declarative registry remains the single path for first-party and external definitions. Definitions are data-only; this change adds no mod-script execution, native dependency, collision/physics, networking, general ECS, terrain-object conformance (Issue #108), or change to terrain SDF, LOD, brush ledger, streaming policy, controls, or terrain save schema 1.

P2.0A stable IDs, world/region placement, seeds, definition namespace, recipe version and content pins remain the baseline identity. Overrides do not rewrite those fields. No individual object record is written until an object is changed or logically excluded.

## Versioned declarative component contracts

Each baseline record advertises `component_contract_version: 1` and these engine-declared contracts:

| Component | Schema 1 properties | Validation bounds |
| --- | --- | --- |
| `core.transform` | `translation_mm`, `rotation_mdeg`, `scale_milli` (three integers each) | Translation ±8000 mm per axis; Euler rotation ±360000 millidegrees per axis; scale 100–5000 milli per axis |
| `core.appearance` | `tint_milli` (RGB integer triple), `label` | Each channel 0–1000; label at most 64 characters |
| `core.logical` | `values` dictionary | At most 32 lowercase keys matching `[a-z][a-z0-9_]*`; values are bool, bounded integral number (±2147483647), or string up to 64 characters |

Every component payload has exactly `schema_version` and `properties`; schema version is 1 and each component rejects unknown/missing properties, unsupported types and out-of-range values. No `Object`, `Callable`, resource, script, or executable value can be persisted. The component set is engine-defined and shared by first-party and external definitions. Future component semantics require a new explicit version; old values are never silently reinterpreted.

## Object state snapshot schema 1

The independent payload has exactly:

```json
{
  "schema_version": 1,
  "world_id": "sandbox-default",
  "world_seed": 424242,
  "generator_version": 1,
  "revision": 0,
  "overrides": {},
  "deleted": {}
}
```

`overrides` maps a stable instance ID to `{ "identity": <pinned identity>, "components": <non-empty sparse component map> }`. Identity records pin the instance ID, namespaced definition ID, exact P0.3 content pin (content/mod ID, mod version and definition schema), world ID/seed/generator, signed region key, slot, placement seed and recipe seed. `deleted` maps the same stable ID to its complete pinned identity. An ID may not appear in both maps. Restore removes its deletion marker and mutable override, returning the exact derived baseline.

Snapshots reject unknown/missing top-level fields, incompatible schema/world seed/generator, malformed IDs or references, content-pin mismatches when the deterministic instance is resolved, revisions outside 0..2147483647, more than 20,000 override or deletion records, invalid component schemas, and a serialized file larger than 4 MiB. World IDs are lowercase slugs (letters, digits, `_` and `-`, beginning with a letter, maximum 64 characters); world seeds are 0..2147483646; generator versions are positive signed 32-bit values; signed region coordinates must fit `Vector2i`. These checks prevent storage-path redirection and coordinate wrap aliases. Runtime validation is fail-closed. References are checked structurally when loaded and checked against regenerated recipe/placement/content identity before that instance can be published or mutated.

## Storage and transaction behavior

Object state is separate from terrain save schema 1:

```text
user://worlds/<world_id>/object-state/seed-<world_seed>-generator-<generator_version>/objects-<generation>.json
```

For the current demo this is under `user://worlds/sandbox-default/object-state/`. Seed/generator partitions prevent old object state from being mixed into a different procedural world. Empty derived worlds create no object-state file. Terrain ledger files are neither opened nor rewritten by this store.

The envelope is canonical JSON with format ID `procedural-sandbox-object-state`, envelope schema 1, generation number, canonical payload JSON, and SHA-256 of the exact UTF-8 payload bytes. The envelope and payload must round-trip to canonical JSON. Each mutation is validated, serialized to a fresh `.tmp`, flushed, read back and revalidated, renamed to a new immutable generation, then verified before the service replaces its in-memory snapshot/revision. A failure before verified commit leaves the previous in-memory authoritative revision unchanged. If a post-rename verification error occurs, the call reports failure and leaves memory unchanged; the next startup validates whichever finalized generation is present rather than assuming rollback. The store retains at most two valid finalized generations.

Startup ignores an incomplete invalid temporary generation while preserving a valid prior generation; it recovers the newest complete valid temporary generation by finalizing it. A corrupt finalized generation fails closed rather than silently rolling back. SHA-256 detects accidental corruption and is not a keyed authenticity mechanism. Flush/rename/readback is not a guarantee against power loss, filesystem/device failure, malicious local modification, or simultaneous independent game processes writing the same world. The demo assumes one local writer; cross-process locking and power-loss-grade durability are not claimed.

## Streaming/publication invariants

- Region objects are generated from the same deterministic world ID/seed and P0.3 registry as P2.0A, then sparse state is resolved against exact identity pins before any visual root is published.
- Logical deletions omit only the visual representative. Overrides and tombstones remain in the state snapshot when a region unloads.
- Visiting regions in any order resolves the same ID, seed, recipe, placement, pin and sparse override. A new world seed switches to its own storage partition and clears old-seed visual roots before publishing the new seed.
- Region publication tokens reject superseded terrain completions. Candidate meshes/nodes are built before replacing the existing region root; rejected generation/resolution/mesh results do not partially publish a replacement.
- Storage commit precedes visual republish. If a visual rebuild fails after a durable commit, the method reports `state_committed_region_rebuild_failed`; the committed model remains authoritative and a later region publication resolves it. This is not a multi-resource filesystem/renderer atomic transaction.
- Mutation requires a reconstructed baseline instance and exact identity/pin validation. Restore of an unloaded deletion regenerates its baseline from world seed, signed region and slot, verifies the pinned identity, and commits the removal of the tombstone; the visual appears when that region is next published.

## GUI verification procedure

Run the project in Godot 4.7.2. Use the normal demo and its visible status line; no test-only save root is used for owner verification.

1. Start from the same saved world/seed and wait for the focused region. Confirm two procedural objects and `Object state revision 0` for a clean object-state partition.
2. Press `F6` to select the next active object; the HUD shows its stable ID.
3. Press `F7`: transform, scale, rotation and tint/label change and the state revision advances by two (one bounded transform commit and one appearance commit).
4. Press `F8`: the selected representative disappears and revision advances once.
5. Press `F9`: its deterministic baseline is restored and revision advances once. Move away until the region unloads, return, and verify the override/deletion/restoration state reconstructs with no duplicate object.
6. Restart the game, revisit the region and verify the last committed transform/appearance and logical state. Press `V` to hide/show object presentation without changing state.

The owner should record visual PASS/FAIL separately. Headless tests verify model, storage, scene mutation APIs and publication invariants, not rendered pixels or artistic quality.

## Verification and limitations

Candidate test coverage includes deterministic signed-region identity/placement, sparse baseline, component/schema/type/range validation, save/reload in a new service and separate Godot process, content-pin mismatch, corruption, invalid/incomplete and complete-temporary recovery, failed-write rollback of in-memory revision, seed partition separation, region unload/revisit, stale publication rejection, logical delete/restore including unloaded restore, terrain schema-1 byte preservation, and playable-scene stream APIs.

The feature remains local single-player mutable state for the two P2.0A slots. It does not make arbitrary world content editable, migrate saves, guarantee cross-version geometry identity after a generator/content version change, add collision, account for terrain intersections, or provide multi-process/power-loss-safe storage. Independent exact-SHA review and owner GUI retest are required; no merge is authorized by this candidate.
