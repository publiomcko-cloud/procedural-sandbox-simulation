# P5 E5 — projection pair-cross reuse: NO_MATERIAL_PROJECTION_GAIN

- Source commit: `577b22baa363a5401b6a9cfb914b86bd0f2542ee`
- Benchmark: [GitHub Actions #43201018376](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43201018376), artifact `13936015921`. Exact 16 ABBA trials, fixed seed 424242, Godot 4.7.2, 720 movement frames, same Windows runner and commit for control/experiment.
- Experimental profile: `adaptive-skip-coarse-projection`, preserving baseline `adaptive-skip-coarse`, SDF, world edits, effect authority and worker budgets.
- **Result**: average projection-worker median improvement ~1.8%, below the predeclared 10% materiality gate. There was no additional definitive LOAD completion. At 54m/s both variants completed 0 regions. No merge.
- The geometry source descriptor parity tests themselves executed without comparison failures, but an error in the formatter for their final PASS receipt produced a Godot `ERROR:` on stderr. The original test harness erroneously accepted the receipt because stderr checked only selected error strings. Both defects have been fixed in follow-on qualification and are **not** used to certify this original run.

| Route | Projection worker median E2→E5 (ms) | Projection worker gain | Final LOAD regions E2→E5 | Mean main process E2→E5 (ms/frame) | Frames >20ms E2→E5 |
|---|---:|---:|---:|---:|---:|
| Idle | 61.550→60.554 | 1.618% | 9→9 | 3.208→3.206 | 1.040%→0.971% |
| 18m/s straight | 64.665→63.117 | 2.394% | 15→15 | 6.000→6.064 | 3.953%→4.369% |
| 54m/s straight | 59.362→58.737 | 1.054% | 0→0 | 5.976→5.918 | 0.485%→0.832% |
| 54m/s out-back | 60.561→59.287 | 2.103% | 0→0 | 6.202→6.288 | 0.762%→0.832% |

**Conclusion:** Pairwise cross-product recomputation is not the dominant cost within `effect_frame_build`. Next investigate deterministic clipped-polyhedron preparation, roughness and guarded-vertex containment with finer-grained profiling. Candidate implementation stays isolated; original main remains unchanged.
