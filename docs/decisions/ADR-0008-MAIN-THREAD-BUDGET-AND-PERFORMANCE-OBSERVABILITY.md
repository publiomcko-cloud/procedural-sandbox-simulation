# ADR-0008 — Main-thread budget, derived-work isolation and performance observability

- **Status:** accepted by owner on 2026-11-07.
- **Date:** 2026-11-07.
- **Decision scope:** runtime architecture for future P4/P5 work and any new streamed world subsystem.
- **Evidence basis:** Issue #108 D.1–D.7.3 performance campaign and owner Windows traces.
- **Companion report:** [Issue #108 performance retrospective](../reports/2026-11-07-ISSUE108-PERFORMANCE-RETROSPECTIVE.md).

## Context

Issue #108 reached correct terrain/object behavior but exposed several performance failure modes that are likely to recur in simulation work:

- working-set capacity smaller than the actual dependency halo caused churn;
- chunk snapshot construction scanned unrelated resident scopes;
- missing derived data could be synchronously generated/reconciled from the gameplay hot path;
- immutable procedural geometry was committed as many individual scene/resource operations;
- the same authoritative base state was reconstructed repeatedly in adjacent pipeline stages;
- warm revisits repeated deterministic finalization and cache-key hashing even when authoritative state had not changed.

The fixes reduced individual stalls dramatically, but the important result is architectural: endless-world systems must make bounded work, ownership and main-thread publication explicit from the beginning.

## Decision

### 1. Gameplay hot paths may not contain unbounded repair work

A frame/tick path must not synchronously perform work whose cost grows with total world history, total resident world state or an unconstrained dependency set.

Missing derived data must normally be:

- prefetched;
- queued;
- built incrementally;
- or treated as unavailable until a bounded asynchronous path completes.

Synchronous fallback is permitted only when its bound is explicit, tested and appropriate to the frame/tick budget.

### 2. Route directly; do not scan unrelated resident state

Spatial or identity relationships that can be indexed must be indexed.

For example, prefer:

```text
target chunk -> exact source scopes
entity ID -> authoritative record
region -> relevant simulation cells
```

over repeatedly scanning every resident scope/entity/cell.

Working-set radius/capacity must be derived from the actual dependency halo and validated as one contract.

### 3. Workers perform pure CPU preparation; main thread performs bounded publication

Worker jobs may perform deterministic CPU work using immutable/versioned inputs.

They must not create or mutate:

- `Node`/`Node3D`;
- SceneTree state;
- `ArrayMesh`/render resources when engine thread-safety is not guaranteed;
- authoritative mutable world state.

The main thread receives prepared results and performs only bounded validation/publication/commit steps.

Large publication sets must be amortized across frames/ticks.

### 4. Every worker result is revision-gated

Asynchronous output must carry enough identity to prove that it still belongs to the current authoritative state.

At minimum, use the relevant combination of:

- world/generator identity;
- region/entity identity;
- authoritative revision;
- content fingerprint;
- request/publication token.

Stale results are rejected rather than patched into newer state.

Fallback paths must preserve correctness and must not silently bypass revision gates.

### 5. Derived caches are bounded, disposable and never authoritative

Caches may store expensive deterministic derived products such as:

- finalized projection sources;
- projection build results;
- CPU geometry;
- batch-preparation arrays;
- materialized snapshots.

Each cache must define:

- key/fingerprint;
- revision/content validity;
- capacity;
- eviction policy;
- invalidation rules;
- cold rebuild path.

Cache loss must affect performance, not world correctness.

### 6. Avoid duplicate reconstruction across adjacent stages

If generation/finalization has already produced a complete immutable authoritative view, downstream stages should adopt/reuse it under an exact revision/membership gate instead of rebuilding the same state.

Reuse is an optimization only; mismatch falls back to the canonical reconstruction path.

### 7. No gameplay-frame worker joins

Normal `_process`, streaming and simulation hot paths must not block waiting for worker completion.

Joining worker tasks is reserved for bounded lifecycle operations such as shutdown, explicit test synchronization, or a separately justified non-gameplay gate.

### 8. New runtime subsystems require decomposition-level performance telemetry

Aggregate “frame took N ms” logging is insufficient.

A new streamed/simulated subsystem must expose timing and work counters for its material stages, including where relevant:

- queue depth and in-flight count;
- worker queue/run time;
- main-thread finalize/validate/publish time;
- source/candidate counts;
- cache hit/miss/eviction;
- reused vs rebuilt work;
- revision/token rejection;
- per-frame/tick work admitted and deferred.

The existing opt-in `PERF_TRACE {JSON}` format remains the preferred runtime evidence path.

Instrumentation should be quiet by default and must not materially perturb the non-traced runtime.

### 9. Performance qualification distinguishes cold, warm and invalidated paths

A subsystem is not qualified from one average timing.

Tests/traces must cover at least:

- cold startup/first generation;
- steady movement/streaming;
- same-revision revisit;
- legitimate invalidation after mutation;
- unload/reload;
- dense/high-work content;
- cache-capacity/eviction behavior;
- shutdown with jobs in flight.

### 10. P4/P5 scheduler work is explicitly budgeted and incremental

The fixed-tick scheduler may not interpret “catch up” as “simulate all missed work immediately”.

P4 must define bounded per-tick/per-frame admission and deterministic deferred backlog semantics.

Active/aggregate/dormant tier transitions must limit work according to explicit budgets. No tier may require scanning the entire expandable world.

## Consequences

These rules trade some implementation simplicity for predictable frame/tick behavior and debuggability. They also make the architecture more compatible with future simulation, where a correct but unbounded catch-up or invalidation strategy would otherwise reproduce the same stalls observed in Issue #108.

Numeric product budgets are deliberately not frozen by this ADR. Each phase must establish scenario-specific budgets with evidence; the architectural requirement is that work is measurable and bounded before those numbers are chosen.
