# Issue #108 — D.1 Live Effect Runtime Performance

Status: **ISSUE108_D1_PERFORMANCE_PASS / GUI_REVALIDATION_REQUIRED**

Base Phase-D HEAD:

`6017dc95988455bf5f39af8f77523d95e8c156c1`

Qualified D.1 code HEAD:

`2adea3b05181e0492d273fc9a4b10987980e2151`

## Owner-observed regression

After Phase D loaded correctly on the owner Windows machine, terrain/object
streaming became extremely laggy during initial load and movement.

This was reproduced as a runtime architecture problem rather than a local
Godot/version problem.

## Root causes

### 1. Resident working-set mismatch

Terrain retains a radius-2 window (5x5 regions) while terrain-object effects
can originate up to radius 2 away from a target region.

The normal bounded source working set is therefore radius 4:

`(2 * 4 + 1)^2 = 81 scopes`

Phase D capped the projection service at 64 resident scopes. Normal movement
could therefore evict scopes that were still required by the current terrain
window and reload/reconcile them again.

D.1 derives the normal cap from the contracts and uses 81 scopes.

### 2. O(resident scopes) effect lookup per chunk

Phase D called every resident scope index for each chunk snapshot.

D.1 maintains a reverse routing index:

`target chunk -> source scope IDs whose effect footprints touch that chunk`

The hot lookup is now proportional to actual routed candidates.

### 3. Reconciliation inside mesh-job snapshot preparation

Phase D could synchronously generate/reconcile up to 25 source scopes while
preparing one terrain job.

D.1 separates residency preparation from the mesh hot path and uses an
incremental prefetch pipeline.

### 4. Heavy derived construction on the main thread

The final source/effect projection construction still caused hundreds of
milliseconds of synchronous work per scope after the first D.1 changes.

The accepted pipeline is:

1. deterministic procedural source generation on worker;
2. current entity-state resolution on main;
3. pure Effect/LocalFrame/source-digest construction on worker;
4. stale/conflict check, validation, index publication on main.

Workers never mutate entity authority, scene nodes, persistence, or projection
service state.

### 5. Offscreen command-region cache pollution

Phase D used command-region reconstruction for projection halo regions. That
registered offscreen source regions in the entity command service cache.

D.1 adds a read-only projection base builder. Projection prefetch can combine
generated + placed bases without making the source region command-resident.

### 6. Redundant derived work

D.1 also removes:

- rebuilding the same shape descriptor twice for Effect + LocalFrame;
- repeated LocalFrame validation while rebuilding an already validated index;
- snapshot hashes that depended on unrelated resident-scope membership/global
  revision.

## Residency / persistence policy

The retained terrain window is 5x5. Adding the radius-2 effect source halo
protects exactly 81 source scopes.

On a one-region movement, one strip of 9 source scopes leaves the working set
and one strip enters.

Streaming baseline projection is published transiently in memory because it is
fully derived and rebuildable. Entity/object state remains the durable
authority.

Entity lifecycle changes still use the crash-consistent persisted projection
path.

## Domain benchmark

Final D.1 domain evidence:

`ISSUE108_D1_EVIDENCE={"initial_legacy_scope_scans":13689,"initial_routed_scope_scans":61,"initial_snapshot_calls":169,"initial_usec":872154,"peak_resident_scopes":81,"traversal_hot_path_evictions":0,"traversal_legacy_scope_scans":219024,"traversal_routed_scope_scans":976,"traversal_scope_loads":144,"traversal_scope_releases":144,"traversal_snapshot_calls":2704,"traversal_usec":1957704,"traversal_window_evictions":144,"warm_prepare_calls":169,"warm_reconciles":0,"warm_scope_loads":0,"warm_scope_releases":0,"warm_usec":31910}`

Key results:

- initial lookup equivalent: 13,689 legacy scope-index examinations vs 61
  routed examinations;
- traversal: 219,024 legacy-equivalent examinations vs 976 routed;
- about 224x less scope-index lookup work;
- warm steady state: 0 reconciles, 0 scope loads, 0 releases;
- hot-path evictions: 0;
- 16 movement transitions replace exactly 144 scopes = 9 scopes/step.

## Real-scene A/B

The exact same headless `terrain_demo.tscn` traversal was run against:

- Phase-D base `6017dc95988455bf5f39af8f77523d95e8c156c1`;
- D.1 code HEAD `2adea3b05181e0492d273fc9a4b10987980e2151`.

Final same-runner comparison:

| Metric | Phase D base | D.1 | Change |
| --- | ---: | ---: | ---: |
| Initial stable publication | 6.190 s | 5.917 s | ~4.4% faster |
| Streaming step p50 | 1.436 s | 1.340 s | ~6.7% faster |
| Streaming step p95 | 2.221 s | 2.110 s | ~5.0% faster |
| Streaming step max | 2.221 s | 2.110 s | ~5.0% faster |
| Peak synchronous process work | 1381.276 ms | 9.123 ms | ~99.3% lower |

The total streaming step still includes meshing/publication and therefore does
not collapse to single-frame latency. The important GUI hitch signal is the
synchronous process peak: the seconds-scale stall was removed from the main
thread.

Final D.1 effect-runtime characterization:

- source-generation worker peak: ~4.0 ms;
- source-state finalize peak on main: ~2.5 ms;
- projection-build worker peak: ~68.2 ms;
- projection publish peak on main: ~8.2 ms;
- terrain snapshot preparation peak: ~2.6 ms;
- no hot-path scope eviction;
- final resident/protected scopes: 81/81;
- no stream error.

## Regression qualification

Workflow run **42246686585**: SUCCESS.

- D.1 domain performance: **16 / 0**
- D.1 real-scene streaming: **19 / 0**
- Phase D live integration: **22 / 0**
- P3.0D placement: **53 / 0**
- global shared surface: **159 / 0**
- incremental shared surface: **43 / 0**
- pre-D precision: **20 / 0**
- Phase C recovery: **60 / 0**
- frozen Phase B: **131 / 0**
- terrain SDF canonical suite: **46 / 0**
- `scripts/validate.sh`: **VALIDATION_PASS**

No hidden `SCRIPT ERROR` is accepted by the D.1 workflow.

## Invariants retained

- entity/object state remains sole authority;
- projection remains derived/rebuildable;
- live effect sampling remains region-local and precision-safe;
- no absolute world-float effect sampling/index path was reintroduced;
- `terrain_edits_then_imprint_v1` unchanged;
- signed/negative regions and cross-region effects unchanged;
- shared X/Z/corner paths unchanged;
- lifecycle persistence remains crash-consistent;
- stale async results remain bounded/rejected by protected-window/source checks;
- no concrete first-party content IDs were introduced;
- renderer nodes are not terrain/effect authority.

## Controlled limitation

D.1 does **not** remove the Phase-D LOD0 fallback for effect-bearing chunks.
The real-scene benchmark had LOD disabled/default and reported zero fallback
chunks, so the measured regression and D.1 improvement are independent of that
future LOD work.

## Verdict

**ISSUE108_D1_PERFORMANCE_PASS**

The deterministic scope thrashing, O(resident-scope) chunk lookup, and
seconds-scale main-thread projection stalls are removed in source/CI
qualification.

Owner GUI revalidation on Windows is required before considering the D.1
performance regression closed and before any stacked PR merge.
