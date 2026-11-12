# E3 — verdict: PERFORMANCE_REJECTED

- **Benchmark HEAD:** `ae5d0e37dc5d035d5a5d225d7b0a7dba44008dfa`
- **Source:** GitHub Actions run `43127869390`, artifact `13903428946`
- **Method:** 16 ABBA cold-world headless simulations on the same Windows runner, Godot 4.7.2, seed 424242, 720 movement steps + 1 final telemetry frame; 2 repetitions/profile/route
- **Control:** `adaptive-skip-coarse`
- **E3:** `adaptive-skip-coarse-ready`
- **Status:** experimental code stays DO NOT MERGE; main unchanged; inherited P4/P5 regression not required to promote a performance-rejected candidate

| Route | Dispatch CPU E2 → E3 (ms/frame) | Main-process CPU E2 → E3 (ms/frame) | Frames >20ms E2 → E3 | Definitive LOADs E2 → E3 |
|---|---:|---:|---:|---:|
| Idle | 1.235 → 1.309 | 3.625 → 3.622 | 1.664% → 1.733% | 9 → 9 |
| Straight 18m/s | 2.276 → 2.315 | 6.250 → 5.902 | 4.854% → 3.259% | 10 → 6.5 |
| Straight 54m/s | 1.752 → 1.947 | 6.462 → 6.626 | 0.762% → 1.179% | 0 → 0 |
| Out-and-back 54m/s | 1.844 → 1.895 | 6.839 → 6.980 | 1.664% → 3.190% | 0 → 0 |

Both variants retain near-complete provisional coarse coverage, not authoritative terrain. The cache made 220 to 897 hits per E3 route on average, and admitted more workers on high-speed routes, but no definitive region at 54 m/s. Dispatch main-thread time **increased in all four routes**. The return route's >20ms frame percentage increased **1.526 percentage points**, exceeding the predeclared 1pp rejection gate. At 18m/s committed LOAD regions fell from 10 to 6.5 on average.

## Interpretation and next intervention

Negative cached readiness probes reduce redundant *attempts* but still do not deliver the prerequisite scope projections soon enough. The cache also has a real per-frame overhead. Do not accelerate SDF or add workers until the projection pipeline's critical path is measured and prioritized. The next isolated experiment should make effect source generation/projection **consumer-driven**, prioritizing the exact ready-to-mesh 3×3 demand, with bounded worker quotas and edit/transaction precedence, and compare against this E2 control on the identical ABBA routes. The prior E1.1 global halo cache/queue re-sort had a frame regression; do not reintroduce it.

This is an experimental diagnostic verdict, not an authorization to merge or promote a candidate.
