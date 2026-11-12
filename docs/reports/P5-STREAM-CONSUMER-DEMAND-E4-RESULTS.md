# P5 E4 — final verdict: PERFORMANCE_REJECTED

- Baseline: `adaptive-skip-coarse`, control and variant on the same source SHA `74fcfe8cbb0ba638a937d2fba9a59f54b73bf85d`.
- Profile: `adaptive-skip-coarse-demand`, preserving all worker, revision and effect-source authority budgets.
- Evidence: [GitHub Actions #43194093149](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43194093149), artifact ID `13932068799` containing 16 cold-world trial logs and `consumer-demand-abba-verdict.json`.
- Fixed seed 424242; four routes (idle, 18m/s, 54m/s, return 54m/s); 720 movement frames plus terminal sample; two cold runs per profile/route; no real GPU benchmark, only headless on Windows.

| Route | Definitive regions: control → E4 | Mean _process ms/frame | Frames >20ms | Dispatch submissions |
|---|---:|---:|---:|---:|
| Idle | 9 → 9 | 3.310 → 3.403 | 0.762% → 0.902% | 144 → 144 |
| 18m/s straight | 15 → 16 | 6.226 → 6.614 | 4.646% → 5.132% | 324.5 → 341.5 |
| 54m/s straight | 0 → 0 | 6.322 → 6.556 | 2.288% → 1.734% | 1.5 → 17 |
| 54m/s out-and-back | 0 → 0 | 6.448 → 7.048 | 1.179% → 2.358% | 142.5 → 152 |

All rows are means of two trials. Successful source priority trace was captured (96/112/522/349 prioritized source dispatches across pairs of E4 trials for the routes above). Projection/source prioritization **does admit more mesh workers**, but at 54m/s no region completes all 16 chunks. The E4 scheduler itself adds ~0.31–0.33ms/frame at 18 and outback. The outback 54m/s >20ms frequency increases by 1.179pp, exceeding the predeclared +1pp rejection gate; process mean rises +0.600ms beyond +0.5ms gate.

**Decision:** reject E4 for merge; no main modification. E4.1 tries to reduce scheduling CPU without changing source ranks.