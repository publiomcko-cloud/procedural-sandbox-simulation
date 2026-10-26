# P3.1 R3 — Hybrid ledger and derived snapshots (owner-approved direction)

Status: design/prototype authorization only; **not production merge or geometry contract change**. Owner approved 2026-10-26. Issue #135; perf evidence Issue #131/PR #134. Baseline production PR #129 at `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.

## Authority model

- **Ledger remains sole durable terrain history and replay authority**, globally ordered CARVE/FILL with existing v1 continuous SDF algebra, identity and hash guarantees.
- Derived per-region/chunk materializations are read accelerators, not an alternate truth: optional mesh/LOD cache, exact-query-capable volumetric representation *only if mathematically proven* for all supported probes, and separate entity state snapshots with schema-3 authority unchanged.
- Version every materialization against world/seed/generator, ordered ledger prefix or exact affected-operation fingerprint, signed chunk/region, mesher/LOD/cave flags and neighbor sampling/normal dependency halo. Missing, stale, mismatched or corrupt snapshots fail closed to reference replay; never silently accept stale visuals or collisions.
- New edits append to ledger before any durably acknowledged derived snapshot; invalidate/recompute only impacted chunks including seam, collision and normal dependencies; budget CPU, memory, disk, writes and scheduler work. No blocking main-thread synchronous snapshot rebuild. Reconstruct deterministically after crash with verified ledger.
- Dynamic entity movement/physics must not generate durable events every frame. Future cross-store object/terrain atomicity remains Issue #108 blocker, not solved by snapshots.

## Phase R3A — comparative isolated prototypes, no production modifications

Same baseline + harness/seed/hardware of Issue #131. Compare (A) improved dense SDF replay/LOD1, (B) versioned persistent derived mesh cache for revisits, (C) candidate exact volumetric materialization with reference oracle. For C, sampled scalar grids and interpolation are **not** equivalent to continuous v1 min/max field: either prove exact reconstruction on all admitted queries, retain residual operation replay for exactness, or explicitly classify it as approximate and reject for production under existing contract. Test concentrated 256/640/2048/8192, distributed baselines, repeated edits/revisit/restart, cross-region seams, caves and normals, adversarial CARVE/FILL temporal order, corrupted/stale snapshots and quotas. Capture p50/p95/p99 of hot-path samples, LOD1 CPU builds, accepted-to-visible, frame loop stalls, disk/RSS, cache-hit %, rebuild and invalidation cost; quantify pre/post on same host.

## Phase R3B — only after independent prototype review

Implement approved derived cache/materialization in separate draft PR with deterministic key, atomic publication, reference fallback, bounded retention/eviction and streamer integration. Ensure no new terrain authority, no schema-1 migration, preserve schema-2 ledger + schema-3 entity state. Explicit owner GUI gate and separate performance regression review.

## Gates

1. Prototype comparative evidence and independent exact-SHA review.
2. Owner selects strategy based on measured benefit and exactness.
3. Controlled production integration and full Godot 4.7.2 validation, owner GUI.
4. Issue #131 performance gate re-evaluation; only then Issue #108 begins.

Keep #129 and #134 draft/unmerged, other draft docs/PRs, stashes and preexisting UID files, five F2-G1 holds. No release or merge implied.
