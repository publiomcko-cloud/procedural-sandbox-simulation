# P5 E7.2 — idle-frame gated provisional publication: PERFORMANCE_REJECTED

- Source SHA: `701f5e9eebec1d60ece2cfb4c57f218f746adefa`.
- Same-SHA ABBA, 16 cold-world fixed-seed 424242 routes, 720 movement frames, headless Godot 4.7.2, `sandbox-gpu-interactive`.
- E7.2 limits one provisional node per frame with 1.1ms budget, defers on any mesh upload in that frame and uses 16ms last-frame / 8ms prior-process guard. This is an opt-in optimization of the E7.1 event-driven queue.
- [GitHub Actions run 43266367329](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43266367329); raw evidence artifact `13965798618`, qualification artifact `13964909897`.
- Functional qualification **PASS**, automated benchmark evidence collection **PASS**, technical verdict **PERFORMANCE_REJECTED**.
- All per-route time/load metrics are averages of 2 runs per profile; provisional chunk counts are total of 2 runs.

| Route | Main _process ms/frame E2→E7.2 | Frames >20ms E2→E7.2 | Fully committed LOADs E2→E7.2 | Provisional visible | Focused provisional | Revoked provisional |
|---|---:|---:|---:|---:|---:|---:|
| Idle | 3.687→3.334 | 1.664%→1.040% | 9→9 | 19 | 0 | 0 |
| Straight 18m/s | 5.637→5.859 | 2.566%→3.606% | 9→10.5 | 85 | 54 | 5 |
| Straight 54m/s | 5.883→5.287 | 0.693%→1.595% | 0→0 | 5 | **0** | 5 |
| Out-back 54m/s | 6.739→6.087 | 1.526%→1.248% | 0→0 | 22 | 6 | 21 |

The 18m/s >20ms frequency rises **1.040pp**, narrowly exceeding the predeclared +1pp gate; straight 54m/s still produces no focused provisional chunk or authoritative region. E7.2 reduces average process cost in three routes but loses most provisional visibility to strict admission; 18m/s focused progress falls to 54 chunks vs 326 in separate E7.1 run. These runs have **different source SHAs and separate ABBA control samples**: this cross-run comparison is diagnostic, not proof of a controlled E7.1-vs-E7.2 effect.

**Do not merge or modify main**. E7/E7.1/E7.2 show that splitting the whole-region publication barrier is feasible under revision safety, but does not solve the original high-speed effect-source dependency. Future work should combine a genuinely cheaper per-chunk source/projection workload with visual chunk publication; adding workers or redistributing spikes alone is insufficient. Retain pristine E2 coarse-first as production reference, full P4/P5 and GPU graphical gates not run on rejected candidates.
