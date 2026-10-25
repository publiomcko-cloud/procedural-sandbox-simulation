# P3.1 Storage — Scalable persistent terrain edits (design gate)

**Status: PROPOSED / UNIMPLEMENTED**. Owner prioritized this before Issue #108's five remaining architectural dependencies on 2026-10-25. Baseline main `5997a76d345f45bf86edfe83f690336391e8be27`; [Issue #127](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/127). Separate design PR. Production code, saves and schemas unchanged.

## Verified current contract

`SdfBrushEditState.MAX_EDITS=256` limits one *global* ordered edit ledger for the entire world, not one chunk. `TerrainWorldSaveStore` schema 1 serializes all CARVE/FILL spheres in a generation file: (sequence, revision, mode, center, radius), seed, generator version, next sequence. It does not serialize chunks/meshes. Saves are explicit (P) and load is explicit (O); two valid generations retained. `sample_density` general path iterates operations in sequence; specialized mesh paths prune only mathematically dominated terms, not arbitrary geometric bounding volumes. Raising MAX_EDITS alone cannot ensure scale.

## Proposed storage architecture

- One immutable, globally ordered authoritative operation log (CARVE/FILL) with stable IDs and revision/commit receipts. Segments have canonical hash, length bound and manifest/checkpoint generation. Never split a cross-region operation into independent authoritative copies.
- Region/chunk spatial indices reference the original operation IDs. A query builds a deterministic relevant **ordered** subset; a pruning proof must account for SDF min/max tails and every mesh/normal sample, rather than naive AABB overlap. Unknown/unsafe terms remain included.
- Durable checkpoints/compaction preserve exact sampled density and operation-order semantics. A lossy mesh/voxel approximation is not equivalent to v1 and cannot become authoritative without separate versioned approval. An exact compact form may require retaining substantial historical operations: **do not promise bounded per-query work unless proven**.
- Limit segment size, in-memory windows, active region count, storage bytes, operations per append, outstanding jobs, sequence range and generated index fanout; fail closed on quota/corruption. Scalable means configurable high capacity within available resources, not mathematically infinite.
- **Owner-approved compatibility break (2026-10-25):** new terrain-save format/version starts a fresh world; schema-1 saves need not migrate. New reader rejects old schema clearly and creates a fresh v2 slot only upon explicit new-world selection. Never silently overwrite, prune or delete existing schema-1 generations on disk. Use distinct namespace/filenames, read-only old data, actionable HUD message, disposable tests. No auto-conversion; no startup mutation of old saves.
- Single-writer process assumption must be explicit. Interrupted append/manifest/checkpoint/recovery cases should be injectably tested. Terrain schema/storage remains separate from entity schema 3; object imprint transaction coordination is **not** solved by this step.

## Functional tests before implementation approval

Compare reference full-ledger samples/meshes to indexed and post-compaction outputs at fixed seeds, flat/slope/cave, negative coords, shared edges and LOD seams; overlap sequences CARVE-FILL-CARVE including nonlocal SDF tails. Repeat with >256 edits spread across regions and densely within one region, data corruption/fault injection, unload/revisit, restart/load and fresh process, deterministic ordering irrespective of visit order. Measure p50/p95/p99 query, meshing latency, append/checkpoint time, peak RAM and disk bytes for increasing operation counts. Ensure save/reload does not silently alter historical CARVE/FILL chronology or reset sequences.

## Sequencing

1. P3.1-Storage architecture review (this PR)
2. P3.1-Storage bounded implementation in separate draft PR; developer tests and owner GUI gate
3. Explicit clean-start gate; legacy schema-1 generations remain untouched but unsupported by the new format
4. Return to [Issue #108](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/108): cross-store transaction, mod excavation geometry, procedural population materialization, ordered interop and full recovery, with immutable imprints specified in ADR-0007

Protected five F2-G1 holds, other draft docs PRs and original stashes/UID files unchanged. No merge authorization implied.

## Implementation authorization

Owner authorized initiating implementation on 2026-10-25, with **no requirement to migrate schema-1 terrain saves**. This is not approval to delete old files, alter entity schema-3 saves, bypass code review, or merge. Implement in an isolated draft production PR based on main, keeping this design PR separate. Demonstrate >256 edits, invariant SDF outputs, bounded persistence and transactional recovery before owner GUI testing.
