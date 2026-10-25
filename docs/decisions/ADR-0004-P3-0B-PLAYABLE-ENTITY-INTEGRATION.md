# ADR-0004 — P3.0B playable entity commands

- **Status:** proposed by the P3.0B implementation candidate; not accepted until independent source review and owner GUI retest.
- **Date:** 2026-10-25.
- **Supersedes:** none. Builds on the P3.0A command contract in ADR-0003 and the P2.0B/C state/population services.

## Context

P3.0A defines transactional entity commands independently of renderer nodes. The playable terrain scene still needs to expose selection, placement, component edits, deletion and restoration without creating a second source of truth or silently rewriting existing object saves. Static P2.0C batches must remain identity-addressable. Streamed presentation can fail after a durable command has committed.

## Decision proposed

1. Keep `ProceduralObjectStateService` as the only object-state writer/store for the loaded world and seed. `EntityCommandService` validates commands and commits through that service; it does not own a second persistence layer.
2. Keep terrain schema-1 save data isolated from object-state records. Schema-1 object state remains readable. An owner explicitly opts into the versioned schema-1→2 object-state upgrade using an in-scene preflight followed by a second M confirmation within six seconds. The prior immutable generation is retained by the existing store contract.
3. Use the P3.0A command schema for playable mutations. The local player is an explicit origin; commands include current world/entity revisions and stable command UUIDs. Receipt replay is idempotent only while the receipt is retained; no unbounded exactly-once promise is made.
4. Reconstruct deterministic procedural identities, explicit placements, overrides and tombstones into region data before deriving nodes/batches. Reuse the bounded region publication queue. After migration, temporarily reject commands until all resident region caches have been rebuilt; unload removes that region from the pending gate.
5. Commit authoritative state before visual publication. Rejected commands do not queue presentation work. Once a commit succeeds, a later visual failure is reported as committed-but-not-visible and does not silently roll back; the previous complete region root remains until a replacement is ready.
6. Keep stable per-instance selection records for batch members and perform approximate ray/sphere selection with terrain occlusion testing. Do not add physics or permanently unbatch static population.
7. Reject transforms whose effective position crosses the entity's canonical owner region. A future region-transfer policy needs its own versioned semantics.
8. Retain F6–F9 and add Ctrl+left selection, B placement and explicit M migration. The playable scene submits all entity writes through the command dispatcher. P2 compatibility APIs are not removed by this slice, but are not used by the new scene controls.

## Consequences

- P2.0B sparse state, P2.0C population IDs/pins, terrain streaming and terrain schema 1 remain intact.
- Command acceptance and visual publication are separate outcomes and need separate HUD/report fields.
- Migration may require the owner to wait for active-region republishing before commands are enabled.
- Selection is approximate; no collision accuracy is claimed.
- Cross-process simultaneous writers, power-loss durability, persistent command history beyond receipt retention, rollback after a post-commit rendering failure, terrain/rock conformation and owner visual acceptance are not established here.

## Evidence gates

Independent exact-SHA source review and owner GUI retest are required. Headless tests and repository CI cannot substitute for either. No merge, release, F2-G1 operation, networking, full undo/redo, physics, or Issue #108 implementation is authorized by this ADR candidate.
