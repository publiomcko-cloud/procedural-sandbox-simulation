# DM24 — Canonical first-dispatch funnel and bounded age-fair scheduling

**Date:** 2026-11-14. Code branch `exp/dm24-canonical-stage-funnel-fairness`. Based on DM23 (DM18 canonical revisit cache retained; DM23 source fairness OFF; DM20/DM21 OFF). No modifications to `main`, no visual GPU qualification.

## Problem and pre-registered hypotheses

DM23 observed that in prewarmed long journeys, **11 of 14** LOAD stages entering focus had no first canonical chunk dispatched, while **30 stages** were cancelled without a first chunk. Among successfully dispatched chunks, time *first effect snapshot attempt → dispatch* was ~0.073ms, but *stage creation → first dispatch* averaged **638ms** in control. Because blocked/cancelled stages did not contribute to the former, the latency must be decomposed at the stage selection level instead of extrapolating from effects work.

DM24 instruments the end-to-end `stage created → eligible each frame → actually selected → snapshot attempted → first chunk submitted → all 16 completed → published / cancelled` funnel, correlated with DM22 source lifecycle and DM23 neighbor-to-focus transition.

## Instrumentation: identical in both arms

`DM24CanonicalStageFunnelProbe` tracks each normal LOAD (non-speculative, not restored by DM18) under its region-id + stage-token. Per frame, it classifies an unsubmitted stage by:
- no per-frame dispatch budget remaining;
- no mesh worker slot remaining;
- eligible for dispatch, but still not submitted.

On selection, it notes original vs shadow candidate and actual chosen region. On first snapshot attempt, it records effect-pending attempts. On first dispatch, it measures creation → first selector hit, selection → first snapshot, snapshot → dispatch, and focus entry → first dispatch. On cancellation, it classifies never selected, selected but never snapshot-attempted, effect-blocked, or snapshot-attempted without dispatch. DM23 continues to record region focus promotion, publication, and cancellation. Summary arrays are bounded to 2,048 samples; active stage records to 320. The benchmark warms for 900 stationary frames and resets measurement counters while keeping actual runtime state, caches, active stages and source identity.

**Crucial parity:** `SANDBOX_DM22_SCOPE_TRACE=1`, `SANDBOX_DM23_STAGE_TRACE=1`, `SANDBOX_DM24_STAGE_TRACE=1` and DM19 diagnosis ON in **both** arms. The normal selector, shadow candidate scan and DM24 diagnostic bookkeeping execute equally in control and treatment. Only the final selected stage may change. No control without observability, and no unbalanced trace overhead. Heavy `SANDBOX_PERF_TRACE` is OFF in both.

## Single independent treatment: DM24-F first-chunk temporal fairness

Flag `SANDBOX_DM24_STAGE_FAIR=1` (OFF in control and by default).

1. The normal selector and DM3/L0D policy still compute their baseline candidate. `edit_transaction`, `partial`, `full` maintain strict precedence, including when a LOAD-stage focal candidate exists.
2. If an eligible normal LOAD stage is the current focus and has **no first chunk submitted**, select only this first chunk ahead of other LOADs. Do not prioritize all 16 chunks, unlike rejected DM20-B.
3. Otherwise, every third scheduler selection opportunity, if a normal (non-speculative, non-DM18-cached) LOAD in the focus's Chebyshev radius 1 has been queued >=600ms and has no first chunk dispatched, allow the oldest such stage through. Deterministic ties.
4. Never expand requested/retained region radius, source scope radius or WorkerThreadPool size, disable revision/edit checks, skip mandatory effects, bypass frame budgets, or alter mesh/surface/publication authority.
5. Control uses **exactly the same candidate computation and probe calls** but returns the unchanged original scheduler selection.

## Test matrix

Workflow: [DM24 Actions](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43605757279), script `scripts/perf/run-dm24-canonical-stage-ab.ps1`, PowerShell 5.1 + Godot 4.7.2 Windows. Same SHA, seed=424242, profile=`adaptive-skip-progressive`, 18 m/s measured wall-clock, isolated APPDATA. Every receipt asserts both probes and both-arm flags; source-fair DM23 OFF. DM18 ON.

- **Exact tests**: DM24 selector priority/age/authority + stage cancellation reason instrumentation, DM23, DM22, DM19, DM18, DM17, DM11 geometric parity, D7.3 effect source cache.
- **Smoke**: 10 trials = 2 cold-forward pairs, 1 warm-forward pair, 2 warm-long pairs.
- **Replicated**: 40 trials = 6 cold-forward pairs, 4 warm-forward, 8 warm-long, 2 idle, with alternating A/B order.
- Metrics: focal canonical missing %, frame p99, proportion >33ms, visual HIGH completed/full-fill time, canonical worker jobs, DM18 cache hits, stage creation→selection, creation→first dispatch, per-stage wait cause frames, cancellations before first selection/snapshot/dispatch, activated shadow overrides and applied overrides.
- 95% confidence intervals on **paired trial differences** by scenario; frames in a trial are correlated and not treated as independent.
- Long route is primary (regions enter focus as neighbors), cold is secondary. A gain in frame p99 alone does not qualify if canonical coverage or HIGH degrades, or if the treatment did not actually run. Equal probe overhead is an invariant but cannot eliminate all runner temporal noise; previous DM22 A/A recorded substantial variance.

## Promotion gate

No promotion or main merge until a scenario-matched, replicated improvement in canonical focus availability with no material regression of p99/frames>33ms/HIGH; exact edition/effects/undo/projection/cache and GPU visual correctness still required. If selector changes do not reduce first-dispatch latency, retain DM18, keep DM24 OFF and focus next on worker-budget arbitration/region-in-flight publication. If reduced gaps occur only during cold startup, treat startup and warm streaming as distinct policies.

**Status at initial report:** exact qualification PASS; 10-trial smoke queued/in progress, replicated job awaits smoke. Terminal verdict not yet known.
