# ADR-0003: Transactional entity commands over P2 object state

**Status:** Proposed by the P3.0A implementation candidate; independent review and owner evaluation pending.

**Date:** 2026-10-24

## Context

P2.0B already owns durable procedural-object overrides and logical deletion in a checksummed immutable-generation store. P2.0C supplies deterministic procedural identities and a data-only content registry. P3 needs one renderer-independent mutation contract that explicit placement and future player/editor/mod callers can share, without creating a second state store or silently rewriting existing saves.

## Decision proposed

1. Keep commands as strict schema-1 dictionaries with a UUID idempotency key, explicit origin label, exact world/generator identity, expected global revision and expected per-entity revision.
2. Dispatch `ENTITY_SET_COMPONENT`, `ENTITY_DELETE`, `ENTITY_RESTORE`, and explicit registered-definition `ENTITY_PLACE` through one `EntityCommandService` with no scene or renderer dependency.
3. Commit every accepted effect by validating and writing one candidate through P2.0B's existing `ProceduralObjectStateService`/`ProceduralObjectStateStore`; publish in-memory state only after storage succeeds.
4. Extend the object-state payload explicitly to schema 2 for placed records, entity revisions and command receipts. Preserve the envelope schema and terrain schema-1 saves. Load old payloads as schema 1 and require an explicit schema-upgrade call before command use.
5. Namespace explicit IDs by world, seed and command UUID, separate from region/population-derived IDs. Do not derive explicit identity from discovery, visitation or registration order.
6. Use a world-global optimistic revision plus monotonic per-entity revision. Persist exact command digests and bounded inverse descriptors. Keep at most 4,096 receipts, never prune in P3.0A, and reject new commands at capacity.
7. Treat exact retry as receipt lookup, conflicting reuse as failure. Do not claim exactly-once, authenticated origins, cross-process locking, power-loss-grade durability or operational authorization.

## Consequences

The dispatcher reuses the existing authoritative P2 snapshot and transaction mechanism. Existing P2 records are not automatically migrated or reinterpreted. Explicit placements persist their base declarative identity and baseline components in schema 2; unmodified procedural instances remain derived from recipe/seed without a per-instance placement record. Receipt retention consumes bounded snapshot space and eventually stops new command acceptance rather than dropping idempotency history.

Inverse descriptors preserve enough prior data to design later compensating operations, including a sparse override removed by deletion. They are not an undo/redo implementation. Origins are validated labels and a mod must be registered for a new command, but P3.0A does not authenticate callers or confer capability permissions.

## Alternatives considered

- **Separate command database/store:** rejected because it would split authority from P2.0B state and require cross-store transactions.
- **Automatic payload rewrite on load:** rejected because it would silently migrate user data. The candidate requires explicit schema upgrade.
- **Use procedural population IDs for explicit placements:** rejected because identity could collide with population order/slot and would not represent user-created instances.
- **Unbounded receipt retention or silent pruning:** rejected; bounded storage is preserved and commands fail closed at the documented cap.
- **Full undo/redo now:** deferred to a separate P3 scope; current inverse metadata is descriptive only.

## Verification gate

This ADR is not accepted until an independent exact-SHA source review examines the schema compatibility path, transaction failure behavior, ID namespace, revisions, receipt retention, content pins, and scene isolation. Owner GUI evaluation is separate. Acceptance of this ADR or P3.0A cannot change the five F2-G1 holds or authorize terrain conformation, networking, merge or release by implication.
