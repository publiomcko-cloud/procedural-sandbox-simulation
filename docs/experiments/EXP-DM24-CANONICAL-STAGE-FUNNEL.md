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

## Preflight and harness correction (same instrumentation across A/B)

The first DM24 workflow, [run 43605757279](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43605757279), passed exact tests (DM24 **31/31**, DM23 34/34, DM22 22/22, DM19 23/23, DM18 112/112, DM11 geometry parity and D7.3 projection), and completed four cold-forward trials (2 pairs) before a **harness-only assertion** stopped a warmed control trial.

The DM24 probe counts 721 stage-dispatch frame observations for 720 measured warm-route frames because the warmup counters reset during pre-stream motion **before the warmup boundary frame reaches the canonical dispatcher**; the same frame is present under the same instrumentation and conditions in the control and treatment. Therefore the per-dispatch receipt invariant was corrected to require exactly `frames + 1` for warm routes and exactly `frames` for cold and idle routes. The game's scheduling code, instrumentation overhead and treatment behavior were **not changed** by this correction. [Corrected workflow 43606090913](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43606090913) repeats all tests from the revised commit `111c3003fd7ef37bfb8edf1dc3db0ac313e54dbc`; exact qualification PASS. Do not mix any failed-run results with corrected benchmark replications.

The two cold-forward pairs from the failed harness attempt showed `fair−control` canonical absence −3.056 and −3.333 p.p., while p99 rose +4.979ms and +1.389ms. These four runs are **exploratory only** and are **not valid evidence of net performance improvement**, particularly given tail regression and small n. The qualified campaign's smoke and replication determine the verdict.


## Terminal outcome — corrected 40-trial campaign

**Source:** [completed corrected workflow, run 43606090913](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43606090913), commit \`111c3003fd7ef37bfb8edf1dc3db0ac313e54dbc\`, all three jobs PASS (exact, smoke, factorial). Artifact \`dm24-stage-validated-evidence\` (ID 14119642579) contains 40 trial receipts, paired results, stdout/stderr and aggregate summaries. The completion receipt is \`DM24_STAGE_FUNNEL_FAIRNESS_AB_REVIEW_REQUIRED\`: this is **not** a policy promotion approval. Smoke 10/10 and factorial 40/40 complete. DM18 unchanged, instrumentation enabled in BOTH arms, heavy perf trace off. No change to \`main\`; GPU visual validation not performed.

All differences below are **treatment minus control**; 95% intervals are Student-t intervals over *matched pairs*, not frame-level bootstrap intervals. Small samples and temporal runner variance constrain certainty.

| Scenario | Matched pairs | Δ focal missing (percentage points) | 95% paired CI, p.p. | Δ p99, ms | Δ HIGH count | Δ creation→first dispatch, ms |
| --- | ---: | ---: | --- | ---: | ---: | ---: |
| cold-forward | 6 | −1.227 | [−6.497, +4.043] | +2.086 | +2.333 | −149.220 |
| warm-forward | 4 | −1.215 | [−3.658, +1.228] | +3.599 | +1.250 | −89.029 |
| **warm-long (primary)** | **8** | **+0.1405** | **[−0.080, +0.361]** | **0.000** | **+2.375** | **−80.176** |
| idle | 2 | N/A | N/A | 0.000 | 0.000 | −289.580 |

The primary warm-long comparison is ~23.833% missing in control and ~23.974% in treatment. All eight warm-long p99 receipts equal 18.056 ms in both arms; zero difference does not establish tail equivalence beyond the benchmark's measurement granularity. First-dispatch means describe successfully dispatched stages and may involve different stage cohorts across arms: do **not** infer that every focal gap advanced by 80 ms.

**DM19 focal-gap-state decomposition, warm-long (mean frames per trial):**

| State | Control | DM24-F |
| --- | ---: | ---: |
| awaiting_first_dispatch | 533.250 (93.23% of missing frames) | 533.500 (92.72%) |
| submitting chunks | 20.375 | 29.250 |
| awaiting_jobs_or_upload | 18.375 | 12.625 |
| cached_waiting_publish | 0 | 0 |
| not_requested | 0 | 0 |
| **total missing frames** | **572.000** | **575.375** |

The 40-trial summaries show DM24-F actually applied overrides (mean 73 selections/trial in warm-long), but warm-long ended-before-first-dispatch stages were unchanged at 30/trial in both arms. Warm-long selection-stage first snapshot→first dispatch for *successful* stages is ~0.09 ms, but this **excludes** stages blocked or cancelled before dispatch. Therefore these measurements neither exonerate effect dependency gating nor prove worker saturation. DM24's \`eligible_not_yet_submitted\` means available *frame and worker capacity*, not *confirmed effect-source readiness*: do not label those frames as runnable without further instrumentation.

Cold-forward improved stage creation→first dispatch by ~149.2ms and decreased pre-first-dispatch cancellations (mean 11.167→5.000/trial), but focal absence had a paired CI spanning both benefit and harm while frame p99 increased 2.086ms on average. Warm-long is the pre-registered primary condition; neither secondary results nor HIGH count gains rescue promotion.

**Decision:** \`DM24_POLICY_NOT_QUALIFIED_KEEP_DM18\`. Keep DM24-F OFF (the default), keep DM18 ON, and retain DM24 instrumentation as diagnostic. No merge into \`main\`, no production priority-policy change. Exact tests certify contracts, **not** a visual/p99 performance improvement.

## DM25 recommended follow-up: causally resolved first-dispatch stall, diagnostics-first

**Question:** Why do ~93% of warm-long missing-focus frames remain in \`awaiting_first_dispatch\` despite DM24-F changing the selected stage and reducing aggregate creation→first-dispatch time?

1. Add **per-focal-stage/token, per-frame mutually exclusive** attribution for: not selected despite globally available budget/worker slot; selected but snapshot/effects pending; selected but frame/time/worker gate; first submission complete but remaining chunks not submitted; all chunks submitted but worker/upload/publish pending. Tie the observed state to DM19's actual missing-focus frame for the same region/token. Deduplicate multiple selection attempts inside a frame.
2. Distinguish **globally eligible** from **source-ready/runnable**; link each pending first-chunk dependency to the DM22 source-scope lifecycle (queue → generation → projection → publication), with exact scope identity and revision, and note focus-entry, first runnable, first dispatch, cancellation, and stage-token replacement. Do not assume readiness just because workers and frame budget were available.
3. Track longitudinal cohorts of regions that **actually enter focus**, including those whose stage was cancelled or never selected. Report censored stage times, outcomes, and per-frame gap contributions; do not compare only successful first-dispatch survivors. Preserve strict 16-chunk revision-gated publication and existing edit/partial/full precedence.
4. Diagnostic-only first: run fixed-input **A/A with identical DM25 observer overhead** and the already accepted DM18 baseline; primary warm-long, secondary cold, with smoke then paired replication. Include a deliberate observer-on/off cost study in a separate *diagnostic* check to measure overhead, never use unequal-cost runs for a treatment performance comparison. If later testing a scheduling policy, turn its switch on only in treatment while running all observers and shadow computations identically in control.
5. Only after stall attribution is supported, nominate **one** causal intervention targeting the dominant runnable-stage bottleneck. Hold worker count, budgets, radius, required effects, caches, authority, and publication checks fixed unless explicitly being experimentally tested. Require scenario-matched confidence intervals for focal coverage, p99, >33ms, HIGH, plus edition/effect/projection/cache parity and visual GPU review before any promotion.

**Do not repeat DM20-B all-chunk priority, DM23 generic source fairness, or DM24-F age fairness as a presumptive fix.** The stage-level first-dispatch summary alone has not established a transferable improvement to warm-long canonical coverage.
