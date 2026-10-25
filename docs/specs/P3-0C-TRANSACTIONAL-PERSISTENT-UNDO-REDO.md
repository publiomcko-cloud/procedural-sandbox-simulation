# P3.0C — Transactional Persistent Entity Undo/Redo

**Status:** implementation candidate on `feat/p3-0c-transactional-undo-redo`; independent source review and owner GUI retest are pending. This specification records the candidate contract and developer-run headless evidence, not product acceptance.

## Scope and authority

P3.0C adds persisted undo/redo navigation to the P3.0A command dispatcher and P3.0B playable integration. The existing `ProceduralObjectStateService` and `ProceduralObjectStateStore` remain the sole authority for entity overrides, tombstones, explicit placements, revisions, receipts, and history. Scene nodes, meshes, and streaming caches remain derived state. Terrain save schema 1 and its files are unchanged.

The versioned operations are `ENTITY_SET_COMPONENT`, `ENTITY_DELETE`, `ENTITY_RESTORE`, `ENTITY_PLACE`, `ENTITY_UNDO`, and `ENTITY_REDO`. Command validation, expected world/entity revisions, origin checks, registered content pins, identity checks, and idempotency receipts continue to apply. A stale or malformed command is rejected before persistence or visual queuing. A persistence commit can succeed while subsequent visual publication fails; the HUD reports that distinction, and a later rebuild resolves the visual from authoritative state.

## Persistent history contract

Object-state schema 3 adds `entity_history` and `history_cursor` to the schema-2 command snapshot. Each history entry retains the canonical source command and its SHA-256, a stable entry/command ID, world and entity identity/revision transitions, the corresponding durable receipt ID, an inverse-metadata digest, and `APPLIED` or `UNDONE` state. Snapshot validation checks exact fields, identities, revisions, ordering, command and inverse digests, receipt linkage, cursor bounds, and cursor/application-state consistency.

Undo and redo are ordinary validated, idempotent commands with their own command IDs and receipts. The selected history entry is checked against the current cursor, source receipt, reconstructed entity identity/content pin, and expected entity revision. Its inverse is applied to a candidate snapshot; the world revision and entity revision advance; the cursor and entry state change; and the new receipt is added. All of those changes are written as one object-state generation before the in-memory snapshot is replaced. Repeating the same command ID and payload returns its durable receipt; a conflicting payload is rejected. Exactly-once behavior beyond the retained receipt window is not claimed.

World revision is the global optimistic-concurrency revision and advances for each committed state command, including undo/redo. Entity revision is per identity and also advances on each committed command affecting that entity; it is not rewound when the historical value is restored. This makes stale clients fail closed while allowing state to move backward without revision reuse.

The history holds at most 256 entries. A new source operation after undo discards the unapplied redo tail. At capacity, the oldest applied entry is pruned only when that does not discard an unapplied entry; otherwise the source operation is rejected. Durable command receipts are bounded by the existing 4096-entry contract, and the complete serialized object-state document is bounded at 4 MiB. Capacity and document-limit rejection are explicit and produce no partial state. These bounds limit undo depth and replay/idempotency retention; they do not promise constant-time validation as history grows.

## Operation semantics and reversibility

- `ENTITY_SET_COMPONENT`: undo restores the prior component value or prior absence; redo reapplies the committed value. If intervening state no longer matches the required precondition, navigation rejects without mutation.
- `ENTITY_DELETE`: the receipt captures the exact pre-delete sparse override. Undo clears the tombstone and restores that override on the same identity, including both F7 transform and appearance edits. Redo verifies the captured override/tombstone preconditions and tombstones the same identity again.
- `ENTITY_RESTORE` / F9: restore means return to procedural baseline by clearing the tombstone and sparse overrides. Undo restores the exact prior deletion and override state; redo returns to baseline. F9 is distinct from undoing a delete. A no-op restore of an already-baseline active instance is rejected.
- `ENTITY_PLACE`: undo tombstones the explicit record while retaining its identity reservation; redo removes the tombstone and republishes the same placement. It never derives a new ID.

Reversibility is limited to the command metadata and source receipts retained by schema 3. History cannot restore missing/unregistered pinned content, undo schema migration, reverse external side effects, or recover after required history/receipt data has been pruned. Region unload does not discard history: navigation requires the target's canonical identity/content to be reconstructed from the registered population/placement sources; streamed scene objects are not serialized.

## Migration and persistence

Schemas 1 and 2 are loaded without rewriting. The scene exposes an explicit two-step **M** migration: first preflight presents source/candidate hashes and counts, then a second M within the displayed window commits schema 3. Migration preserves schema-2 receipts and command state; historical schema-1/2 operations are not retroactively undoable because they have no schema-3 history entries. The prior immutable generation is retained by the store. Terrain world-save schema 1 remains unchanged. Tests use disposable injected state directories and do not upgrade a user's real save.

Each mutation writes a canonical bounded envelope to a new generation's temporary file, flushes and reads it back, validates its payload digest and schema, renames it to the immutable generation path, and verifies the committed bytes before the service publishes the candidate in memory. The store retains the newest two valid generations. This is application-level transactional/recovery behavior; it does not establish power-loss durability, filesystem atomicity on every filesystem, cross-process writer exclusion, or protection against an external writer racing the store.

## Playable controls

| Input | Behavior |
| --- | --- |
| Ctrl+Z | Undo the latest applied entity command |
| Ctrl+Y or Ctrl+Shift+Z | Redo the next undone entity command |
| F7 | Existing transform and appearance command flow; each component write is a separate undoable command |
| F8 | Logical delete; undo restores the same entity and exact prior overrides |
| F9 | Restore selected/latest deleted object to procedural baseline; remains semantically distinct from undo |
| M twice within the displayed migration window | Explicit preflight then commit from object schema 1/2 to schema 3 |

HUD history depth/cursor and the next undo/redo target are informational. Rejections report their reason. A commit reports its world/entity revisions and separately reports visual publication status.

## Validation and limits

The candidate test coverage includes per-command undo/redo, two-command F7 ordering, exact delete restoration after F7, F9 baseline semantics and reversible prior state, explicit migration from schemas 1 and 2, persisted history across service/process-style restart, unload/revisit identity preservation, duplicate/reused command IDs, stale revisions, corrupt payloads, interrupted writes, history branching/capacity, content-pin failures, and scene input routed through the viewport. Full `scripts/validate.ps1` results and the exact evidence log are in the [implementation checkpoint](../checkpoints/2026-10-25-P3-0C-IMPLEMENTATION.md).

Headless results prove deterministic contract behavior in disposable fixtures only. They do not prove owner GUI acceptance, OS focus behavior, GPU completion, visual publication on a physical display, concurrent multi-process writes, power-loss durability, or release readiness. No terrain/SDF, streaming, LOD, population, physics, networking, full editor, or Issue #108 terrain/object conformation feature is added. All five F2-G1 protected-state holds remain unchanged.

## Owner GUI retest

Use a disposable world/object-state root; do not migrate or edit a valued user save. Launch `res://scenes/terrain_demo.tscn` in Godot 4.7.2 (F5 runs this configured main scene; `main.tscn` is the bootstrap reference cube and must not be used for entity GUI acceptance). If object state is schema 1 or 2, press M once and review the preflight, then press M again within the displayed window and wait for readiness. Place/select an entity, press F7, then F8. Press Ctrl+Z and verify the exact same entity returns with its pre-delete F7 transform and appearance. Press Ctrl+Y and verify that same identity is deleted again; Ctrl+Shift+Z is an alternate redo. Press Ctrl+Z, then F9; verify F9 clears to the procedural baseline and that Ctrl+Z restores the exact state that preceded F9. Repeat undo/redo after region unload/revisit and process restart. Confirm HUD revisions/status and that rejected stale commands do not change visuals. This is a retest procedure; GUI acceptance has not yet been reported.
