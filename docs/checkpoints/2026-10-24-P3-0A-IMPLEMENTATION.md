# P3.0A — Transactional Entity Command Contract Implementation

**Event:** owner-authorized implementation candidate and local validation

**Date:** 2026-10-24

**Repository:** `publiomcko-cloud/procedural-sandbox-simulation`

**Workspace:** `C:\Dev\sandbox-sim-dev`

**Branch / PR:** `feat/p3-0a-entity-command-contract`, draft PR [#114](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/114)

**Verified main baseline:** `b874991bb0f2cc698e41dd8709f3b0325d73c855`

**Implementation source commit:** `ca2273953d3b578cf349990f487fcac25336db6b` (direct parent `b874991bb0f2cc698e41dd8709f3b0325d73c855`). The same feature branch has a following documentation-only reconciliation commit; this checkpoint records the source implementation identity.

## P2 exit assessment and P3 entry

Verified main already contains P2.0A geological declarative objects, P2.0B sparse durable object state, and P2.0C deterministic modular static population. Together these provide data-only registered definitions, deterministic procedural identities, content pins, region population and a persistent object-state authority. This is the technical foundation for the P3 command layer, not a claim that every P2 visual/product gate is closed. Terrain/object conformation remains deferred to Issue #108. P3.0A is a bounded first command-contract slice; the larger P3 milestone remains incomplete.

## Implementation

- `EntityCommandContract` validates exact schema-1 command fields, UUID command IDs, origins, world/generator identity, parameters, components, and floor-based region ownership using `TerrainSpatialOwnership`.
- `EntityCommandService` dispatches `ENTITY_SET_COMPONENT`, `ENTITY_DELETE`, `ENTITY_RESTORE`, and explicit registered-definition `ENTITY_PLACE` without scene-node or renderer dependencies.
- World-global and per-entity optimistic revisions are checked before persistent mutation. Exact retries return durable receipts; conflicting payload reuse is rejected. Up to 4,096 receipts are retained without pruning. Inverse metadata prepares future compensating operations; no undo stack or redo is implemented.
- P2.0B remains the sole object-state authority. Existing payload schema 1 is loaded unchanged; command use requires an explicit payload schema-2 upgrade in the same object-state store. Terrain world schema-1 files and the P2.0B envelope/storage path remain unchanged.
- Explicit placement IDs use `world/seed-<seed>/placed/<command-uuid>`, separate from region/population-derived IDs. The record pins the registered definition and stores explicit position plus base component values. No per-instance record is added for unchanged procedural population instances.
- A separate `entity_command_harness.tscn` uses a unique disposable state folder, with `P` place, `E` transform edit, `Delete` logical delete, and `R` restore. It does not replace the playable terrain scene or the F6–F9 workflow.

Architecture, command fields, revision semantics, migration, idempotency, inverse metadata and boundaries are detailed in [P3.0A specification](../specs/P3-0A-TRANSACTIONAL-ENTITY-COMMAND-CONTRACT.md) and proposed [ADR-0003](../decisions/ADR-0003-TRANSACTIONAL-ENTITY-COMMANDS.md).

## Validation evidence

Engine: `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.

Command: `scripts/validate.ps1`, with `GODOT_BIN` pinned to that executable and a temporary isolated `APPDATA` profile so user saves and installed mods were not used. Result: `VALIDATION_PASS: L0-L2`; **17,950 assertions, 17 groups, zero failures**. This includes terrain/SDF, brush, streaming, LOD, declarative content, P2 procedural population/state, P3 entity commands, persistence, concurrency and startup regressions. Full log was captured at `C:\Users\PUBLI\AppData\Local\Temp\p3-0a-final-validation-408cd22103cd4c46b71223e9dba31dc1.log`.

Focused entity suite: `ENTITY_COMMAND_PASS: assertions=67 failures=0`.

The isolated harness scene startup smoke passed headlessly (`--scene res://scenes/entity_command_harness.tscn --quit-after 2`, exit 0). This verifies initialization only; it does not validate visible appearance or owner input feel.

Four representative command dispatches included the synchronous P2 store write/readback. Local timings in this run were: place 13.842 ms total / 12.809 ms persistence; component set 17.311 / 16.242 ms; delete 23.207 / 21.523 ms; restore 24.018 / 21.712 ms. These are four local headless observations, not percentiles, thresholds, or performance acceptance.

## Limitations and gates

- Origins are labels, not authenticated principals or a permission system. A mod must be registered for a new command; arbitrary mod scripts are not run.
- Storage remains P2.0B's local single-writer design. No cross-process lock, crash-proof exactly-once guarantee, or power-loss guarantee is added. Uncertain store outcomes block further writes until reload.
- Receipt capacity is finite and receipts are not pruned. A full store or 4,096-receipt cap rejects new commands.
- Multithreaded contention was not exercised; the concurrency regression uses logically competing expected revisions in sequence.
- The command harness runs in its own scene and disposable state path. Owner GUI assessment remains pending. Headless validation does not imply visual acceptance.
- P3.0A does not implement physics, networking, advanced tools, complete undo/redo, terrain conformation or issue #108.
- No merge, release, F2-G1 action or protected-state change is authorized or implied. All five F2-G1 holds remain unchanged.

## Status

Recorded on draft PR #114 for exact-SHA independent source review and owner GUI evaluation. PR #114 remains open/draft/unmerged. The feature branch is not integrated into `main`.
