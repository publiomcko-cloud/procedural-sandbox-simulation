# P4.0H — final P4 qualification

Status: **INTEGRATED / AUTOMATED QUALIFIED / OWNER GUI ACCEPTED / P4 CLOSED**.

Dependency chain: P4.0D PR #269 -> P4.0E #270 -> P4.0F #271 -> P4.0G #272 -> P4.0H stacked branch.

## Purpose

P4.0H is the closing qualification/correction slice for P4. It adds no new simulation domain. It exercises the integrated P4.0A–G stack against the real terrain scene and retains only the correction work necessary to close qualification defects.

Automated gates:

- a static cache-independence guard forbidding P4 production scripts from resolving P4 `class_name` symbols through type annotations, static member access or constructors; followed by direct loading of `simulation_runtime.gd` and `terrain_demo.gd`; this targets the P4 cache-staleness failure without requiring unrelated legacy subsystems to abandon their established global classes;

- real cold scene startup with a data-only environment mod discovered through the shared M4.0 registry;
- bounded 25-scope saturation and 26th-scope fail-closed behavior;
- six-region forward streaming and warm return;
- eight-region high-speed jump and return;
- unload/revisit reuse of the deterministic region scope and persisted material profile;
- real terrain edit followed by terrain checkpoint + quiescent simulation sidecar commit;
- scene destruction and fresh scene instantiation using the same durable stores;
- exact terrain/simulation generation pairing after restart;
- scheduler pause/tick persistence through restart;
- material/environment state preservation through real save/restart/load;
- zero outstanding P4 router/material work at steady checkpoints;
- cumulative P4.0G→A regression.

## Performance trace gates

The focused final campaign runs with:

```text
SANDBOX_PERF_TRACE=1
SANDBOX_PERF_TRACE_MIN_MS=0
```

The CI parser requires evidence for the following stages and applies deliberately conservative ceilings on the pinned self-hosted Windows runner:

| Stage | Minimum samples | P99 ceiling |
|---|---:|---:|
| simulation_scheduler_frame | 10 | 5 ms |
| simulation_world_scope_frame | 5 | 5 ms |
| material_environment_batch | 1 | 5 ms |
| terrain_window_reconcile | 3 | 25 ms |
| effect_snapshot_prepare | 1 | 15 ms |

The trace gates use P99 so isolated tracing/runtime outliers remain visible in `max_usec` without being misclassified as systematic regression. The real-scene harness also requires process-work peak and frame-time p99 to remain <= 50 ms. These thresholds are regression ceilings, not target frame budgets. Worker-side asynchronous wall latency such as object prewarm/projection generation is not misclassified as a main-thread stall.

The trace parser emits `P4_0H_TRACE_SUMMARY=<json>` and `P4_0H_TRACE_PASS`.

## Save/restart contract

The final scene campaign pauses simulation before persistence, drains the P4 transient work boundary, performs a real terrain edit, commits the terrain generation, waits for the simulation sidecar keyed to that terrain generation, destroys the scene, then creates a fresh scene against the same storage directories.

Restart must restore:

- the same terrain generation;
- the paired simulation sidecar generation;
- paused scheduler authority and logical tick;
- the origin scope;
- exact persisted material/environment record for that scope.

The P4.0G store-level exact-snapshot/SHA replay tests remain cumulative and provide byte-exact durability proof independently of the scene's derived lifecycle reconstruction.

## Owner GUI gate — ACCEPTED

The owner completed the corrected GUI run under `SANDBOX_PERF_TRACE=1` on Godot 4.7.2 with NVIDIA GTX 1050 Ti after the cold-start class-cache correction. The run contained no script/runtime errors, warnings or failed markers; measured scheduler/lifecycle/terrain/effect trace values remained within the P4.0H regression ceilings. The owner explicitly reported the game as visually good and smooth and authorized P4 closure.

## Closing rule

P4 closing conditions were satisfied:

1. P4.0H automated qualification is green on corrected HEAD `3682491cd50f4a2f9a223a47ae94ebbe952043a1` via run `42519921001`;
2. owner GUI/visual acceptance is green on that source;
3. stacked PRs P4.0D→H were integrated in order, ending at main merge `99e83c0bd6fcc28e55e0977dad41a378a00ea2ee`;
4. the integrated runtime tree exactly matches the final qualified P4.0H tree;
5. project status/checkpoint documentation records P4 closure.

P5 climate/water and later ecology work are explicitly outside this gate.
