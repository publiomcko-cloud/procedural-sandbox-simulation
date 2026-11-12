# P5 E7.1 — event-driven provisional chunk publication: PERFORMANCE_REJECTED

- Head SHA: `7ff7edaf4764d7a8dbcb9e5aaee85b5756a4fe4a`.
- 16 fixed seed 424242, 720 movement frames/headless Godot 4.7.2 ABBA on runner `sandbox-gpu-interactive`, reference E2 `adaptive-skip-coarse` versus `adaptive-skip-progressive` on same SHA.
- [GitHub Actions run 43264788777](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43264788777), raw logs and per-trial JSON artifact `13965347773` and qualification `13965426798`.
- Functional qualification **PASS** including source revisions, edit vetoes, preview mask clipping, complete commit, and real scene.
- All metrics are means of 2 independent trials per profile/route; provisional chunk counts are sums of 2 trials.

| Route | Main _process ms/frame E2→E7.1 | Frames >20ms E2→E7.1 | Fully committed LOAD regions E2→E7.1 | Provisional visible chunks | Focused provisional chunks | Revoked provisional chunks |
|---|---:|---:|---:|---:|---:|---:|
| Idle | 3.282→3.564 | 1.110%→1.595% | 9→9 | 268 | 30 | 0 |
| Straight 18m/s | 6.054→6.485 | 3.121%→4.854% | 14→15.5 | 598 | 326 | 106 |
| Straight 54m/s | 5.810→5.393 | 0.971%→0.554% | 0→0 | 37 | **0** | 37 |
| Out-back 54m/s | 6.051→6.124 | 0.486%→1.734% | 0→0 | 311 | 154 | 298 |

E7.1 replaced the E7 full stage scan/sort with an event-driven, bounded, revision-gated queue and proved canonical chunks can become visible before whole-region commitment without early object/simulation publication. However >20ms frame frequency increased **1.733pp at 18m/s** and **1.248pp out-back at 54m/s**, each exceeding the predeclared +1pp rejection gate. All provisional chunks at straight 54m/s were off-focus and revoked; no persistent definitive region completed.

**Verdict: PERFORMANCE_REJECTED. Do not merge.** E7.2 attempts isolated frame-budget backpressure, preserving same geometry and authority.
