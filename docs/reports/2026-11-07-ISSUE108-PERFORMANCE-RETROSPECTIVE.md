# Issue #108 performance retrospective and forward development rules

**Date:** 2026-11-07  
**Status:** accepted engineering retrospective after Issue #108 closure.  
**Final Issue #108 integration:** D.8 / PR #254 / merge `5a69a2ec9e96411fd256abc97ae9a6c32d4658a9`.  
**Architecture decision:** [ADR-0008](../decisions/ADR-0008-MAIN-THREAD-BUDGET-AND-PERFORMANCE-OBSERVABILITY.md).

## Purpose

This report records the performance failures encountered while integrating deterministic terrain/object SDF effects, the corrections that materially improved gameplay, and the development rules that should be applied to P4/P5 before similar problems appear in simulation.

It is a retrospective, not a claim that every remaining runtime path is fully optimized. Performance work was intentionally paused after D.7.3 once the owner considered gameplay sufficiently improved and D.8 completed the remaining LOD functional limitation.

## 1. Failure pattern: dependency working set did not match configured capacity

Phase D initially required the retained terrain window plus the effect-source halo, which produced an 81-scope normal working set. The effect runtime allowed only 64 resident scopes.

That mismatch created avoidable churn: the runtime could evict scopes that were still part of normal gameplay dependency, then regenerate/reconcile them later.

### D.1 correction

D.1 derived and protected the exact 81-scope working set instead of treating cache capacity as an unrelated constant.

**Rule:** every residency/cache capacity must be checked against the maximum legitimate dependency halo for normal operation. A capacity smaller than the ordinary working set is not a memory optimization; it is systematic thrashing.

## 2. Failure pattern: O(resident-set) scans in per-chunk work

Terrain effect snapshot preparation originally examined resident scope indexes broadly for each target chunk.

Observed D.1 evidence:

- initial lookup examinations: **13,689 -> 61**;
- traversal lookup examinations: **219,024 -> 976**;
- approximately **224x less lookup work** after direct routing.

The correction introduced direct target-chunk -> source-scope routing.

**Rule:** if relevance is spatially computable, maintain a bounded spatial/reverse index. Never repeatedly rediscover relationships by scanning all resident state.

This rule applies directly to future P4/P5 cells, material state, environment sources and simulation neighborhoods.

## 3. Failure pattern: synchronous derived-data repair inside a gameplay hot path

Before D.1, a missing effect source could be generated/reconciled synchronously while terrain mesh snapshot preparation was executing.

This turned a logically small snapshot request into a potentially large generation/projection transaction on the main thread.

Same-runner D.1 A/B evidence:

- peak synchronous main-thread process work: **1381.276 ms -> 9.123 ms**, roughly **99.3% reduction**;
- source-state finalization peak after correction: about **2.5 ms**;
- projection publish peak: about **8.2 ms**;
- terrain effect snapshot preparation peak: about **2.6 ms**.

The fix used incremental prefetch plus bounded worker generation/projection construction while keeping authoritative state resolution and publication checks serialized.

**Rule:** a read/snapshot API must not secretly become a “generate everything I need now” API. Derived-state acquisition and publication are separate pipeline stages.

## 4. Failure pattern: too many per-object render commits

After effect-source performance improved, visual publication became visible as the next stall source.

The object path still performed expensive individual visual work for many immutable procedural rocks. D.7 introduced regional static batching; D.7.1 extended batching to supported mutable/stateful/placed rocks while retaining per-entity authority nodes where required.

Owner trace comparison around D.7.1:

- `object_mesh_commit_step`: **20 -> 0**;
- observed `terrain_process_spike` count: **23 -> 2** in the compared campaign;
- individual mesh nodes for supported batched rocks were eliminated.

The important distinction was preserved:

```text
authoritative identity/state != one render node/mesh per entity
```

Many logical entities can share a regional render batch without losing deterministic entity identity.

**Rule:** domain granularity must not dictate rendering granularity. Keep authority fine-grained and presentation batchable.

## 5. Failure pattern: deterministic CPU work was still performed on the main thread

Batching alone did not remove the cost of building the final combined vertex/normal arrays.

D.7.2 split batch construction into:

1. CPU-only deterministic `prepare` work, suitable for WorkerThreadPool;
2. bounded main-thread `ArrayMesh` commit.

It also reused an already prepared authoritative base/resolved region under an exact revision/membership gate instead of reconstructing it again.

Representative heavy-region D.7.1 -> D.7.2 owner trace:

| Measurement | D.7.1 | D.7.2 | Change |
| --- | ---: | ---: | ---: |
| cold object publication | ~32.54 ms | ~8.542 ms | -73.7% |
| revisit object publication | ~21.96 ms | ~7.79 ms | -64.5% |
| cold main reconstruction | ~12.60 ms | ~0.357 ms | -97.2% |
| revisit main reconstruction | ~8.95 ms | ~0.448 ms | -95.0% |
| cold regional batch work | ~12.18 ms | ~3.169 ms | -74.0% |
| revisit regional batch work | ~8.18 ms | ~2.89 ms | -64.7% |

**Rule:** first ask whether CPU preparation can be made pure and moved off-thread. Keep resource creation/publication on the main thread only where the engine requires it.

## 6. Failure pattern: warm revisits repeated finalization and hashing

After D.7.2, object publication was no longer the dominant revisit cost. The next visible spike was effect source finalization/cache-key preparation even when authoritative content had not changed.

One heavy same-revision revisit showed approximately:

- effect source finalization: ~11.5 ms;
- prefetch tick: ~16.575 ms;
- associated process work: ~18.8 ms.

D.7.3 added a bounded revision-gated projection-source cache upstream of the existing projection-build cache. It reused the already finalized source and canonical projection key only when the world revision matched exactly.

Owner trace result:

- heavy [0,0] same-revision revisit prefetch: **~16.575 ms -> 1.296 ms**;
- improvement: **~92.2%**;
- **126/126** observed source-cache hits also reused the canonical key and hit the projection-build cache;
- the comparable D.7.3 trace contained no terrain-process spike.

**Rule:** cache the highest expensive deterministic stage that can be proven reusable. Do not merely cache the final product if expensive normalization/hash/finalization still happens before the cache lookup.

## 7. Why revision gates mattered

Caching and worker reuse were never allowed to weaken authority.

D.7.2/D.7.3 reuse paths required exact revision/content/membership conditions. A mismatch fell back to canonical reconstruction.

This prevented a common optimization error:

```text
fast cached result + stale authority = incorrect world
```

The accepted design is:

```text
authoritative state
      │
      ├─ exact revision/fingerprint match -> reuse derived result
      │
      └─ mismatch -> rebuild derived result
```

**Rule:** an optimization must be removable without changing world semantics. If removing a cache changes correctness, the cache has accidentally become authority.

## 8. Remaining performance frontier when optimization was paused

D.7.3 intentionally ended the performance campaign rather than chasing every remaining millisecond.

The last representative trace identified these next candidates:

- `terrain_window_reconcile`: observed worst case around **16.067 ms**;
- `effect_snapshot_prepare`: observed worst case around **10.778 ms**;
- cold effect generation/finalization remains more expensive than same-revision revisit, as expected;
- terrain mesh worker jobs can be long-running but are already off-thread, so their concern is queue pressure/latency rather than direct main-thread blocking.

These are **not open Issue #108 blockers**. Issue #108 is closed. They are historical performance frontiers to revisit only if future gameplay evidence makes them relevant.

## 9. Anti-patterns to avoid in P4/P5

Do not introduce:

1. global scans of all regions/cells/entities every tick;
2. synchronous “repair missing state” inside a sampling/query API;
3. cache capacities smaller than normal dependency working sets;
4. one Node/Resource commit per logical simulation item when batching is possible;
5. worker jobs that mutate authoritative state or SceneTree;
6. blocking worker joins in normal gameplay frames;
7. duplicate reconstruction in successive stages;
8. hash/deep-copy work before a cache lookup when a cheaper stable key exists;
9. cache entries without explicit revision/content validity;
10. catch-up that simulates arbitrarily many missed ticks in one frame;
11. instrumentation that reports only total frame time without stage decomposition.

## 10. Required design pattern for P4 simulation

P4 should begin with a staged bounded pipeline:

```text
authoritative simulation state
        │
        ▼
bounded tick admission
        │
        ├─ active work
        ├─ aggregate work
        └─ dormant/catch-up work
        │
        ▼
pure/versioned worker preparation where useful
        │
        ▼
revision check
        │
        ▼
bounded authoritative commit
        │
        ▼
derived presentation/publication
```

The scheduler must control **how much work enters a tick/frame**, not merely when functions are called.

A backlog is acceptable. An unbounded frame stall is not.

## 11. Performance telemetry contract for new systems

Every substantial P4/P5 subsystem should expose opt-in structured trace events compatible with the existing `PERF_TRACE {JSON}` convention.

Useful fields include:

- event/stage name;
- world/region/tier identity;
- authoritative revision;
- duration;
- item/source/candidate count;
- queue depth;
- in-flight worker count;
- worker queue/run time;
- main-thread validation/commit time;
- cache hit/miss/eviction;
- reused/rebuilt count;
- deferred work count;
- stale-result rejection count.

For a new performance problem, instrument the internal stages before attempting broad refactors. This approach repeatedly identified the real Issue #108 bottleneck after the previous one had been removed.

## 12. Qualification matrix

Performance-sensitive changes should be tested under distinct scenarios:

| Scenario | What it detects |
| --- | --- |
| cold startup | first-build/materialization cost |
| stationary warm state | accidental repeated work |
| continuous cross-region movement | streaming/residency churn |
| same-revision revisit | reuse/cache effectiveness |
| post-mutation revisit | invalidation correctness/cost |
| unload/reload | reconstruction and persistence cost |
| dense content | scaling with entity/source count |
| cache capacity pressure | eviction/thrashing |
| shutdown with jobs in flight | lifecycle correctness |

Averages alone are insufficient. Preserve worst-stage timings and counts so a rare visible stall is not hidden by many cheap frames.

## 13. Development workflow derived from the campaign

For future performance work:

1. reproduce owner-visible behavior;
2. add structured stage timing around the suspected path;
3. collect a full trace;
4. rank stages by main-thread contribution and frequency;
5. inspect code only after the measured stage is known;
6. change one architectural bottleneck at a time;
7. keep focused regression tests for the optimization contract;
8. compare cold/warm/invalidation behavior before merge;
9. preserve a fallback canonical path for every reuse optimization;
10. stop optimizing when product behavior is acceptable and remaining costs are outside the current milestone.

This avoids speculative optimization and preserves the evidence-driven workflow that was effective in D.1–D.7.3.
