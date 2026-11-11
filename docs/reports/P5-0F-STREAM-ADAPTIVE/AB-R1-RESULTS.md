# P5.0F streaming A/B experiment — R1 evidence

Date: 2026-11-11. Owner ran `P5-stream-baseline-20261111-102738.log` and `P5-stream-adaptive-20261111-102838.log`, both at exactly `aa3ede689a969518f0327e20d923d29d4447d112` on Godot 4.7.2 / NVIDIA GTX 1050 Ti, with PERF_TRACE. Both isolated policy tests: `P5_0F_STREAM_BUDGET_PASS: assertions=152 failures=0`. Both GUI runs exited 0.

Log representation: the PowerShell host emitted interleaved NULs into the native console transcript. Offline metrics here were computed by stripping NULs, then parsing `PERF_TRACE` JSON. No missing parsed trace records. The in-repository A/B runner was later fixed to normalize NULs before its JSON metrics extraction. Changes to that script **postdate** these runs.

| Metric | Baseline | Adaptive |
|---|---:|---:|
| Trace span (seconds) | 25.60 | 26.81 |
| Window-accounted frames | 1,467 | 1,525 |
| Published load completions | 30 | 33 |
| Mesh dispatches | 480 | 528 |
| Uploads | 480 | 528 |
| Boost-enabled frames | 0 | 364 (23.9%) |
| Frames with *actual* second dispatch | 0 | **7** |
| Frames >20ms | 67 (4.57%) | 57 (3.74%) |
| Frames >33ms | 19 (1.30%) | 13 (0.85%) |
| Main process >16ms | 40 (2.73%) | 44 (2.89%) |
| Frame mean | 17.322ms | 17.306ms |
| Main-process mean | 3.675ms | 3.744ms |
| Load p50 across all published regions | 2,261ms | 2,619ms |
| Load p95 across all published regions | 5,473ms | 5,451ms |
| Snapshot median / p95 | 2.66 / 4.46ms | 2.61 / 4.44ms |
| Snapshot queue wait median / p95 | 1,393 / 5,171ms | 1,916 / 4,849ms |
| Mesh worker median / p95 | 145 / 498ms | 145 / 493ms |
| Mesh upload median / p95 | 0.25 / 0.34ms | 0.25 / 0.34ms |
| SDF job worker median / p95 | 575 / 1,194ms | 581 / 1,167ms |

Same nine initial `(4..6,12..14)` regions were loaded in both sessions, and each completed between 0.4% and 2.7% sooner in adaptive; their cohort mean is 4,673ms vs 4,596ms (~1.6% faster). Subsequent paths diverge: adaptive loaded three additional regions `(7..9,19)`, so unpaired p50 and raw total dispatch counts **must not** be interpreted as a speedup or slowdown. Across the 30 matched regions, mean load was 2,775ms baseline and 2,857ms adaptive; 16/30 had lower latency in adaptive. This small, non-randomized sequential test is susceptible to warmed disk caches and route/scene differences.

## Findings

1. **Conditional throughput increase was rarely exercised.** Of the 1,525 adaptive frames, 364 had the two-dispatch budget unlocked, but only seven actually submitted the second snapshot. `terrain_mesh_snapshot` shows 244 single-dispatch snapshots while budget=1 and 24 while budget=2 (17 first + 7 second); the rest of frames had no snapshot. This does not support increasing the configured maximum to three.
2. **Queue/worker readiness dominates** rather than GPU mesh upload. Median worker compute ~145ms, median upload ~0.25ms, queue waits ~1.4–1.9s. First mesh dispatch on the nine initial regions occurred ~1.4 to 5.3s after their stages opened, though the first local effect sources were published earlier; the prioritized first region can still wait on shared-boundary or other effect dependencies.
3. **Frame smoothness was not materially degraded.** Long-frame rates improved numerically in adaptive and the same two-display frame mean stayed ~17.3ms; this is not proof of causality or statistically robust evidence. The worst frame is dominated by startup at ~146–150ms in both.
4. **No quantified streaming acceleration is proven.** Owner visual acceptance and repeated runs under comparable trajectories are required before promotion. Initial 3x3 gains are small, and later differences are inconsistent.

## Next isolated experiment

Prioritize instrumentation of why `_dispatch_mesh_jobs` frequently returns without using a permitted second dispatch: in-flight worker saturation, missing effect snapshots (head-of-line pending), no eligible stage, frame snapshot budget exhaustion, and other stage blockers. If the evidence confirms head-of-line blocking, test bounded **skip-to-next-ready-region** after a pending effect snapshot, retaining order *within* each region, limiting skipped candidates and total main-thread snapshot attempts, while leaving worker and GPU caps unchanged. Benchmark against baseline + existing adaptive to attribute changes separately. Do not deploy extra concurrency or raise frame budget blindly.

Status: **AB_R1_INCONCLUSIVE_FOR_THROUGHPUT**. Keep experimental PR #281 draft; do not merge to qualified P5.0F branch or main.
