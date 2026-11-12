# P5 E7 — progressive chunk visibility, first prototype

**Verdict: PERFORMANCE_REJECTED.** The experimental profile renders authoritative chunk meshes before a complete 16-chunk region; entire region, object and simulation publication remain committed together. Fail-closed revision and edit gates passed.

- Benchmark source SHA: `12a9385e583cc00dc80d041a76f97c31ccb5558e`.
- Godot 4.7.2, 16 cold-world ABBA runs on a pinned Windows runner, seed 424242, 720 movement frames, identical control/experimental SHA.
- [Actions run #43210564250](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43210564250); raw evidence artifact `13941566394`, qualification `13940394156`.
- Control: `adaptive-skip-coarse`. E7: `adaptive-skip-progressive`.

| Route | Baseline→E7 mean _process ms/frame | >20ms frames baseline→E7 | Full LOADs baseline→E7 | E7 early chunks (2 runs) | Early chunks in focus |
|---|---:|---:|---:|---:|---:|
| Idle | 3.189→3.805 | 0.762%→1.040% | 9→9 | 269 | 30 |
| Straight 18m/s | 5.940→7.702 | 3.884%→4.438% | 15.5→16 | 642 | 330 |
| Straight 54m/s | 5.622→6.953 | 0.277%→0.347% | 0→0 | 38 | 0 |
| Out-back 54m/s | 6.068→7.612 | 1.664%→1.872% | 0→0 | 242 | 152 |

Per-route counts are totals across two runs; frame/process/full LOAD figures are means. At straight 54m/s, all 38 provisional chunks were subsequently revoked and none were near the focus, so high-speed streaming was **not** solved. At outback 54m/s, 232 of 242 early chunks were revoked when moving away; this is correct cancellation, not a commit.

**Cause of rejection:** Main-thread `mesh_dispatch_and_upload` cost increased ~1.3–1.9ms/frame, driven by E7's full scan/sort of all staged regions and LOD checks each frame, even with no new completed job. Coarse preview patch publication adds ~0.03–0.09ms/frame; it is not the dominant source of CPU regression.

**Next isolated experiment E7.1:** move provisional publication to an event-driven queue populated only by successfully completed worker uploads, replacing per-frame region scans. Preserve exact 16-chunk authority, revision gates, coarse patch masking, and edit atomicity. Compare again against original E2 on the same SHA. Do not merge E7.
