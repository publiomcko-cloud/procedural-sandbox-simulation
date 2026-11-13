# DM12 — Frame-spike attribution after canonical B4 fast path

**Status:** Stage attribution validated on Windows self-hosted Godot 4.7.2, with subsequent opt-in experiments isolated. No change to `main` or normal DM11 defaults.

## Baseline DM11 evidence

The qualified DM11 canonical fast B4 candidate reduces the 18m/s core-missing percentage to about 30%, but occasionally raises the fraction of frames above 33ms to approximately 3.2%. Existing `terrain_region_publish_detail` showed most completed canonical region commits below 3ms, so the long frames were not demonstrably caused by the atomic 16-chunk commit itself.

## New attribution instrument

`SANDBOX_DM12_FRAME_TRACE=1` enables per-frame main-thread measurements for focus/reconciliation, effect prefetch, mesh job prune/progressive/complete/dispatch, coarse previews, HIGH visual publications, object publications, SDF surface cache, water visualization and diagnostics. It logs `dm12_frame_attribution` only on frames with a **prior-frame delta ≥33ms** or **current tracked process ≥14ms**. Previous frame stage durations, process duration and publication counters are explicitly carried forward, because Godot `_process(delta)` receives the elapsed delta from the preceding frame. This prevents temporal misattribution. `SANDBOX_DM12_FRAME_TRACE=0` retains the original runtime except for inactive instrumentation hooks.

A same-seed 720-frame headless 18m/s route was executed twice with trace and once without. Contract/benchmark CI run **43427719706** PASS. With instrumentation OFF: mean 17.969ms/frame, 3.051% frames >33ms, 77 exterior HIGH visual completions, canonical focus missing 25.28%. With instrumentation ON: frames >33ms 4.993% and 4.577% in the two traced trials. **Tracing itself changes frame tails: do not use instrumented results as unbiased performance A/B.**

Across the two traced normal-speed routes:
- 69 frames had a previous delta ≥33ms, including two unclassified startup frame deltas (150ms). In 65/69 spike events, the **previous _process** independently took ≥14ms, supporting the main-thread workload explanation.
- Dominant preceding main-script stage frequencies: **SDF surface cache 25**, **water_visual 15**, **focus_window_lookahead 13**, **derived HIGH visual 12**, **mesh_dispatch_and_upload 1**, **effect_prefetch 1**, **startup/no prior frame 2**.
- Heavy SDF cache stage examples 15–35ms. Heavy focus reconciliation examples 20–35ms, water 19–26ms.
- Only 13 of 69 spike events followed a canonical region commit; 10 of 69 followed an exterior HIGH publication. Counts are not disjoint and do not prove causality.
- SDF cache on main thread prepares all 16 per-chunk brush/edit snapshots, effect targets, effect snapshot and deep copied records before dispatching the worker. Even with canonical meshing fast, this separate synchronous cache preparation remains expensive.

**Decision:** `DM12_SPIKE_SOURCES_IDENTIFIED`. **Do not** reduce canonical HIGH SDF sampling quality, blindly throttle visual workers or change the region commit based on these results. This is attributable main-thread work, not proof of GPU saturation.

## Isolated follow-up experiments

1. [DM12 SDF snapshot slicing](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/tree/exp/dm12-surface-snapshot-slicing): `SANDBOX_DM12_SURFACE_SLICE=1` captures up to 3 immutable chunk snapshots/frame (and stops after a soft 2.5ms per-step budget). It preserves revision and scope guards, original effect composition and final worker/publish path. Batching tests **306 assertions/0 failures**, plus baseline P5.0C cache **53/0**. Final runtime A/B and GPU qualification must complete before recommending activation. The first A/B run was blocked by a typed-array initialization error in the **baseline branch path**, corrected without touching DM11. The corrected run is [43429301805](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43429301805).
2. [DM12 focus and water breakdown](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/tree/exp/dm12-focus-water-attribution): additional opt-in splits for focus source updates, unload, staging and diagnostics and water geometry derivation/ArrayMesh creation/post-swap bookkeeping. [Focused run 43429769132](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43429769132). Instrumentation-only; no change to water authority/persistence/LOD.

### Commands

For repeatable diagnostic local launch on the DM12 attribution branch, retain the existing DM11 command, add:
```powershell
$env:SANDBOX_DM12_FRAME_TRACE = "1"
$env:SANDBOX_PERF_TRACE = "1"
```
For unbiased performance, set `SANDBOX_DM12_FRAME_TRACE=0`.

## Qualification gates

A speed candidate must demonstrate no regression in `canonical_focus_missing_pct`, canonical p95, full-HIGH stationary fill, visual HIGH completions, water shoreline readiness and exact snapshot/edit/effect semantics, and reduce 20/33ms frame tails in repeated identical routes. The `main` branch remains untouched until these gates and local GUI acceptance.
