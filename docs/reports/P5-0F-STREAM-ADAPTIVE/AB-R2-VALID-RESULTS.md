# P5.0F R2 A/B/C retest — verified adaptive-skip execution

**Status:** `AB_R2_FUNCTIONAL_CONFIRMED_PERFORMANCE_PROMISING_NOT_PROMOTED`. Date 2026-11-11 (local UTC−03). All three runs were on exact experimental commit `0661e1b9fc32286cce429ecafdd2ffc7e83cfc84`, Godot 4.7.2, NVIDIA GTX 1050 Ti, seed 424242, with PERF_TRACE. The prior trial on `b56131e6` is **invalid** for R2 (runtime silently selected baseline); see `AB-R2-FIRST-RUN-RESULTS.md`. This retest has a verified actual `terrain_stream_profile.profile` equal to each requested profile, `profile_mismatch=false`. Each run logged `P5_0F_STREAM_BUDGET_PASS: assertions=183 failures=0` and exited with code 0.

## User evidence

Uploaded original files and matching `.events.txt` / `.metrics.json`:

- `P5-stream-baseline-20261111-132035.log` (baseline started 13:20:35 local).
- `P5-stream-adaptive-20261111-132101.log` (adaptive started 13:21:01 local).
- `P5-stream-adaptive-skip-20261111-132130.log` (adaptive-skip started 13:21:30 local).

All reported statistics come from those artifacts, decoding the native Powershell console NUL separator before reading `PERF_TRACE` JSON. All PERF_TRACE records parsed (2,882 baseline, 2,897 adaptive, 3,003 skip). Do not treat an unpaired number of loaded regions or raw jobs as a controlled speedup.

## Full-session instrumented metrics

| Metric | baseline | adaptive | adaptive-skip |
|---|---:|---:|---:|
| Windows with trace | 19 | 21 | 21 |
| Accounted frames | 1,116 | 1,246 | 1,245 |
| Loaded regions | 27 | 24 | 27 |
| Mesh dispatches/uploads | 432/432 | 384/384 | 432/432 |
| Dispatches per 100 frames | 38.71 | 30.82 | 34.70 |
| Allowed boosted frames | 0 | 348 | 420 |
| Pending load skips | 0 | 0 | **135** |
| Actual dispatch after skipped region | 0 | 0 | **33** |
| Skip budget exhaustion events | 0 | 0 | **18** |
| Frames >20ms | 68 / 1,116 (6.09%) | 40 / 1,246 (3.21%) | **25 / 1,245 (2.01%)** |
| Frames >33ms | 12 (1.08%) | 5 (0.40%) | **4 (0.32%)** |
| Process frames >16ms | 32 | 19 | 27 |
| Mean frame duration | 17.37ms | 17.11ms | 17.21ms |
| Mean main-process duration | 3.92ms | 3.34ms | 3.70ms |
| Unpaired region load p50 | 1,754.06ms | 1,576.61ms | **1,495.23ms** |
| Unpaired region load p95 | 5,176.16ms | 5,550.62ms | **5,075.93ms** |
| Effect-pending corner blockers | 209 | 222 | 322 (retries across candidates) |
| Worker-capacity blockers | 225 | 241 | 236 |
| Dispatch-cap blockers | 314 | 226 | 264 |
| No eligible stage | 368 | 557 | 538 |

The skip mode **actually executed** its intended bypass: 135 load-region skips created 33 dispatch-after-skip events. These metrics are event counts, not unique regions or individual frame wins; 33/135 (~24.4%) is a descriptive event ratio, not a measured probability of successfully bypassing a specific region.

## Matched-region comparison (required attribution check)

There were **21 identical region IDs** in all three logs. For those **same** regions, unweighted queue-to-load-complete measures were:

| Metric (matched 21 regions) | baseline | adaptive | adaptive-skip |
|---|---:|---:|---:|
| Mean load duration | 2,724.94ms | 2,680.09ms | **2,589.51ms** |
| Median load duration | 1,811.65ms | **1,617.68ms** | 1,705.61ms |
| Versus baseline, mean time saved | — | 44.85ms (1.6%) | **135.43ms (5.0%)** |
| Regions faster versus baseline | — | 12/21 | **14/21** |

The initial shared 3×3 world (4..6, 12..14), which provides the most useful fixed cohort, had mean load durations baseline **4,376.73ms**, adaptive **4,576.18ms**, skip **4,269.07ms**, i.e. skip mean ~2.5% faster than baseline (and ~6.7% faster than adaptive). There is a noteworthy local counterexample: the origin region (5,13) loaded in baseline 2,493.64ms but skip 3,342.45ms. Do not claim all regions were faster.

These are **short, sequential, non-randomized GUI sessions (~19–22 seconds of PERF_TRACE)**, with different after-start navigation and warming effects. Improvement is *promising*, not conclusive; frames >20ms also improved in adaptive without bypass. Repeat representative routes in reverse order and ideally >=60–90 seconds per profile, compare matched regions and actual visual experience before any promotion.

## Live CI at analysis time (exact commit 0661e1b9)

GitHub workflows: P5.0F-focused **success**, P5.0A/B/C/E **success**, P4.0F/G/H **success**, Starter checks **success**, but the **P5.0D cumulative workflow failed** after its own `P5_0D_FINITE_RUNOFF_PASS: assertions=130 failures=0` and `P4_0H_FINAL_PASS: assertions=81 failures=0`. The failure came from `validate-p4-0h-perf-trace.ps1` rejecting `terrain_window_reconcile` p99 **30,524µs** vs hard gate **25,000µs** in that run. A standalone P4.0H workflow on the same commit completed successfully. This is an unresolved cumulative performance qualification failure, not license to relax the gate. The exact same trace metric must be retested/understood before calling the branch cumulatively green.

## Verdict and next action

**R2_FUNCTIONAL_CONFIRMED / STREAM_LATENCY_IMPROVEMENT_PROMISING / CUMULATIVE_CI_PARTIAL / PROMOTION_BLOCKED.**

- Do **not** merge experimental PR #281 directly into `main`, or silently port to P5.0F PR #280. Preserve working baseline.
- Perform longer reverse-order A/B/C on identical routes (baseline, adaptive, skip then skip, adaptive, baseline) with the pinned self-hosted Godot and built-in runner. Collect per-region medians/p95 and visual stutter observations.
- Investigate the failing P5.0D P4.0H performance trace p99 without increasing the threshold or weakening fail-closed validation. Consider separating repeatability from real regression with controlled reruns while preserving evidence.
- The remaining significant architecture-level bottlenecks are effect-snapshot pending and worker capacity (rather than GPU upload). Do not increase max workers or dispatch budgets until the guarded skip's benefit and FPS safety are reproducible.
- Update `docs/checkpoints/P5-0F-STREAM-R2-CONTEXT.md` and PR #281 when the next result arrives.

This document and the checkpoint are sufficient to continue in a new conversation. Only actual repository files and current GitHub CI state determine the latest truth.
