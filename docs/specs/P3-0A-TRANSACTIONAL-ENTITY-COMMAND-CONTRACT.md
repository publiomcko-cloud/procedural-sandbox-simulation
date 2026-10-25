# P3.0A — Transactional Entity Command Contract

**Status:** implementation candidate on `feat/p3-0a-entity-command-contract`; independent source review and owner GUI evaluation pending. This specification records the bounded P3.0A implementation, not acceptance of the whole P3 milestone.

## Scope

P3.0A adds a renderer-independent command dispatcher over the existing P2.0B `ProceduralObjectStateService` and `ProceduralObjectStateStore`. The dispatcher accepts four versioned operations: `ENTITY_SET_COMPONENT`, `ENTITY_DELETE`, `ENTITY_RESTORE`, and `ENTITY_PLACE`. Placement is limited to explicit instances of definitions already registered by the data-only P0.3 registry.

The command service contains no `Node3D`, mesh, scene-tree or renderer dependency. Region reconstruction receives canonical P2.0C instances from `ProceduralObjectWorld` and persisted explicit placements from the same state snapshot. Commands that mutate an existing entity require its identity and pinned definition to be present in the reconstructed region cache. Placement validates the destination region from integer millimetre coordinates and the canonical `TerrainSpatialOwnership` mapping.

Out of scope: physics/collision, multiplayer/networking, mod-script execution, advanced editor tools, full undo/redo, P2.0C repopulation changes, terrain conformation (Issue #108), and any changes to F2-G1 protected state.

## Command wire format

Every command has `schema_version: 1`, a lowercase UUID command ID, origin `{type,id}`, exact world ID/seed/generator version, expected world revision and expected entity revision. Unknown or missing fields are rejected. Integer inputs accept JSON integers or finite, exactly integral floating-point parser values only inside the exactly representable range; booleans, strings, fractional values, null and unsafe integers fail validation.

Origins are `player`, `editor`, or `mod`. IDs are bounded syntactic labels. A new `mod` command is accepted only while its package ID is registered in the data-only content registry. This is an origin-integrity check, not authentication, a permission system, or a sandbox. Player and editor IDs likewise are not authenticated in this slice.

| Operation | Operation fields | Effect |
| --- | --- | --- |
| `ENTITY_SET_COMPONENT` | entity ID, component ID, versioned component value | Writes one validated sparse component override. |
| `ENTITY_DELETE` | entity ID | Writes a logical tombstone and clears active sparse overrides in the same candidate snapshot. |
| `ENTITY_RESTORE` | entity ID | Removes a matching tombstone and sparse overrides, restoring the deterministic baseline. |
| `ENTITY_PLACE` | registered definition ID, world anchor `position_mm`, claimed `region_key`, recipe seed, three versioned baseline components | Creates an explicit instance whose ID is derived from the command UUID, not procedural population order. |

For placement, `position_mm` is the world anchor and its `region_key` must match canonical floor-based spatial ownership, including negative coordinates. Transform, appearance and logical properties use P2.0B component schema 1. Transform offsets, orientation and scale are carried only by the transform component; placement has no duplicate transform fields. The registered definition's exact content pin and declared recipe are validated before commit and reconstructed from declarative data; no package script runs.

## Identity and revision contract

Procedural P2.0B/P2.0C identities and content pins are unchanged. Explicit placements use identity schema 3, `identity_kind: placed_explicit_v1`, and the namespace `world/seed-<seed>/placed/<command-uuid>`. The P2.0C procedural region/population namespace cannot alias this format. The identity captures the registered definition pin, world/generator identity, region anchor, placement seed and recipe seed.

`world_revision` is a monotonic revision for every accepted persistent entity command, across the world. A command must provide the exact current value; stale commands reject before candidate construction or storage. `entity_revision` is monotonic for one identity and advances only when that entity changes. A new explicit placement starts at entity revision 1; a legacy procedural entity without a revision record is treated as revision 0 until first mutation, then becomes 1. The entity revision remains recorded after restore so it cannot reset and admit an old command. Placement requires expected entity revision 0.

The dispatcher validates a complete candidate snapshot, writes it through the existing P2.0B immutable-generation store, then publishes it in memory. There is no partial in-memory success before the store commits. If write/readback/rename outcome is uncertain, the command service is poisoned and requires state-service reinitialization before another mutation. This remains a local single-writer contract; it does not add interprocess locks or claim power-loss durability beyond P2.0B's documented file-store behavior.

## Idempotency and receipts

Each accepted command stores a SHA-256 digest of its normalized canonical command, operation, entity ID, resulting world/entity revisions and bounded inverse-operation metadata in the same snapshot transaction. An exact duplicate returns the durable receipt without applying again, including after restart and even if the original mod package is no longer registered. Reusing an ID with a different normalized payload rejects with an idempotency conflict. A new mod command requires the package to be registered.

At most 4,096 command receipts are retained. Receipts are not pruned in P3.0A; when full, new commands fail closed. No exactly-once guarantee is claimed: a caller can lose a reply after a durable commit and must retry the same command ID to discover its receipt. If the commit outcome is uncertain locally, the caller must reload first. This is not distributed idempotency or cross-process concurrency control.

Inverse metadata is preparation for later compensation commands, not executable undo. It records the operation/identity needed to invert place/delete/restore; for component set it records the component key, prior-presence flag and prior sparse value; delete retains the prior sparse override. No undo stack, undo command, branching history, redo, actor authorization, or retention policy beyond the bounded receipt cap exists.

## Persistence and migration

The P2.0B envelope, checksum, immutable generation rotation, storage path, and terrain schema-1 save format are not changed. The object-state payload extends from schema 1 to schema 2 with `placed_entities`, `entity_revisions`, and `command_receipts`; existing P2 overrides and tombstones remain in that same authoritative snapshot. Existing P2 schema-1 data loads unchanged. Command dispatch requires an explicit call to `upgrade_command_snapshot_schema()`, which writes a new validated generation and preserves the world revision. There is no automatic migration during ordinary P2 load and no reinterpretation of existing identities.

Schema-2 validation is strict: bounds, exact key sets, world/region ownership, explicit identity namespace, component schemas, per-entity revisions, receipts, and inverse metadata are checked. Invalid or unsupported snapshots fail closed before command acceptance. Receipt and explicit-instance limits supplement P2.0B's existing total payload/document limits; a store size failure is an ordinary failed transaction.

## Harness and verification boundary

`res://scenes/entity_command_harness.tscn` is a separate scene and starts empty. It creates a unique disposable state directory under Godot user data and removes only that directory on exit. `P` places, `E` changes the selected transform, `Delete` logically deletes and hides only the selected node after the committed state resolves as deleted, and `R` restores the same identity/node from authoritative state. Input matches either `InputEventKey.keycode` or `physical_keycode`; the game window must have OS focus. Rejected commands do not change the visual representation and display their reason in the HUD. It uses the same dispatcher and P2 persistence service. It does not load the playable terrain scene, modify its controls, or use the normal world save path.

Automated tests cover command validation, both revisions, duplicate/conflicting IDs, durable receipt retry, content registration/pinning and missing content, explicit migration, save/restart, store failure/corruption, negative coordinates and boundary ownership, unload/reconstruction, and logical competing commands. Timings print dispatch-plus-persistence and store-save durations separately as local exploratory observations. They are not approved performance budgets. Headless tests do not approve appearance, input feel or GUI usability; owner GUI evaluation remains required.

## Residual limits

This command layer is prepared for shared player/editor/mod submissions but current origins are only syntactically identified; no authenticated users or per-mod capabilities exist. Existing P2 stream/service APIs remain for their existing product paths and are not replaced by a project-wide command-authority migration in P3.0A. Concurrent dispatch was simulated by same-revision sequential contenders, not multithreaded or cross-process writes. Content must remain installed at a matching pin to reconstruct an entity; a missing or changed mod blocks affected reads/mutations rather than silently substituting content. Visual acceptance, source review and later full P3 undo/redo are pending.
