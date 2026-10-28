# P3.1 R8.3-B — SDF-to-mesh fidelity and bounded adaptive refinement

**Disposition: `P3_1_R8_3_B_BLOCKED_WITH_EVIDENCE`**

## Identity and scope

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Branch: `bench/p3-1-r8-3b-adaptive-fidelity`
- Final measured source: `bbaf1950547a5cccb1d0e62fcd434a97373bcfee`
- Direct parent of measured source: `c788b8bd28dd4a0e469c78f06f6c7462abe1360b`
- R8.2 base: `4f08b67522507bd196a74a1089c773f272235343`
- Changed source relative to R8.2: only `game/tests/prototypes/p3_1_r8_3b_adaptive_fidelity.gd`; production scripts, project settings, persistence and frozen inputs are unchanged.
- Draft evidence PR: [#166](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/166), linked to Issue #164.

The experiment compares the canonical continuous SDF sampled at spacings 0.5, 0.25 and 0.125 world units, plus one bounded score-driven refinement policy. It does not change the production mesher or adopt a geometry tolerance. All results are diagnostic. No rendered-FPS, GPU, collider, or owner GUI claim is made.

## Correction to the adaptive experiment

The first R8.3-B implementation refined every coarse cell in a preselected cave ROI. That was fixed-ROI refinement, not an adaptive selection rule. The initial attempt and its outputs remain preserved in `evidence/attempt-004/`.

The corrected policy evaluates the eight frozen 0.5-unit cells in that same ROI. At each candidate it samples the eight corners and center from the canonical SDF, records the active ordered-CSG branch labels, and computes `abs(center_density - mean(corner_density))`. A branch-trace/canonical mismatch invalidates the build. Candidates are sorted by descending distinct branch count, descending center residual, then ascending integer cell coordinate; the top four cells are refined into 0.125-unit cells. The selection uses a fixed resource budget of four parent cells, not a product acceptance threshold. It detects branch changes only at these nine probes and does not certify multiple roots or tangencies between probes.

Attempt 005 emitted a successful diagnostic but omitted the actual `adaptive_selection` record from its result JSON. It is retained and superseded for incomplete output custody. Attempt 006 reran the corrected policy and emitted candidate scores and selected cells. The final source commit contains those same source bytes: its physical SHA-256 and Git blob are listed in `SOURCE_SHA256SUMS.txt`.

The selected parent cells were coarse coordinates `(2,1,1)`, `(1,1,1)`, `(1,1,2)`, `(2,1,2)`, at world minima `(0,1.5,5.5)`, `(-0.5,1.5,5.5)`, `(-0.5,1.5,6)`, `(0,1.5,6)`. Each observed two winning labels (`cave_distance`, `surface_top`); center residuals were approximately 0.164466, 0.132120, 0.105620 and 0.082447. The other four candidate scores and all selection inputs are in `evidence/attempt-006/result.json` and `adaptive_roi.json`.

## Frozen inputs and mathematical oracle

The inputs are inherited unchanged from the R8.2/R7.3 contract (generator v1, seed `131102026`):

| Case | Commands | Input SHA-256 |
| --- | --- | --- |
| Zero edit | none | `24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b` |
| Cave CARVE | CARVE sequence 0, center `(8, 1.17898154258728, 5.90309238433838)`, radius `0.58` | `47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411` |
| Ordered cave | FILL sequence 0 at `(8,1.17898154258728,5.10309219360352)`, then CARVE sequence 1 at `(8,1.17898154258728,5.92309236526489)`, both radius `0.58` | `55d45d387bd19829bb38c4e988da25a886765f26cc34e19dd07ed808faa1bd46` |

The continuous SDF is sampled from canonical SDF v1 and rounded through `PackedFloat32Array` before the unchanged tetrahedral polygonizer. For triangle 3103, the diagnostic scans each of its three source edges at 4,096 uniform brackets and bisects sign-changing intervals. It records branch winners and piecewise-linear edge roots for the three mesh spacings. This finite scan does not prove absence of even-multiplicity/tangent roots between samples.

On the three frozen triangle-3103 edges, the continuous-versus-piecewise root offsets were:

| Edge | Ordered branch behavior | h=0.5 | h=0.25 | h=0.125 |
| --- | --- | ---: | ---: | ---: |
| `(8.25,1.5,5.5)` to `(8,1.5,5.5)` | no branch-winner change over the continuous edge | 0.0143810 | 0.0143810 | 0.00422765 |
| `(8.25,1.5,5.5)` to `(8.25,1.75,5.75)` | branch changes; sampled and continuous winning branches differ | 0.0139512 | 0.0139512 | 0.00492490 |
| `(8.25,1.5,5.5)` to `(8.25,1.75,5.5)` | branch changes | 0.00957143 | 0.00957143 | 0.00833508 |

Each finite scan found one sign-change root per edge. That is not a complete root-count certificate. Exact inputs, IEEE values, branch traces, brackets, and positions remain in `triangle_3103_branch_refinement.json`.

## Geometry and resource observations

Centroid density residual is `abs(canonical_density(centroid))`; it is **not** a surface-distance statistic. Ray displacement is a maximum over matched vertical roots on the frozen 25-ray cross-section and is **not** a global surface displacement bound.

| Representation | Samples | Triangles | Build (single diagnostic) | Centroid density residual p50 / p95 / max | Face-normal angle p50 / p95 / max | Winding opposite canonical gradient | Internal open edges | Cropped boundary open edges | Nonmanifold edges | 25 rays with root-count mismatch | Max matched vertical displacement |
| --- | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Uniform 0.5 | 100 | 168 | 4.454 ms | 0.009038 / 0.185246 / 0.231300 | 10.427 / 156.488 / 159.915 deg | 21 | 0 | 48 | 12 | 0.366110 |
| Uniform 0.25 | 567 | 804 | 28.372 ms | 0.002303 / 0.065542 / 0.114005 | 1.440 / 124.458 / 170.285 deg | 62 | 0 | 104 | 6 | 0.139812 |
| Uniform 0.125 | 3,757 | 4,520 | 232.376 ms | 0.000494 / 0.023300 / 0.046533 | 0.703 / 23.107 / 118.897 deg | 7 | 20 | 268 | 0 | 0.026052 |
| Score-driven ROI, four refined parents | 487 | 1,192 | 43.738 ms | 0.000223 / 0.026343 / 0.210675 | 0.528 / 34.811 / 159.915 deg | 19 | 150 | 48 | 6 | 0.559271 |

The adaptive selection used 35 probe positions across the eight candidates. Its float32 sample buffer was 1,948 bytes and its estimated positions-plus-normals attribute payload was 85,824 bytes; these are component estimates, not total allocation or GPU memory. The harness also emitted Godot static-memory readings, which are process-wide snapshots and are not per-mesh deltas or OS RSS. Build times are one headless diagnostic sample per mesh, not p50/p95 benchmark results.

The center ray from `(0,2.5,6)` downward has continuous SDF roots near `y=1.887005150` and `y=1.492090523`. The adaptive mesh had six root-count mismatches among the 25 vertical rays and a maximum matched vertical displacement of about `0.559271` world units. Five of six outer ROI face contours differed from their adjacent coarse references. The equal-resolution neighbor controls matched at h=0.5 (12 segments, 20 shared samples) and h=0.25 (24 segments, 63 shared samples). At h=0.125, shared samples still matched bitwise (221 samples), but contours differed: 68 versus 67 segments, with one unmatched segment. Thus matching shared density nodes alone did not ensure extracted contour agreement.

The adaptive mesh has 150 internal open edges, 19 triangles whose face winding opposes the measured canonical outward gradient, and five nonmatching ROI interfaces. Uniform 0.125 improves the sampled ray displacement but still has 20 internal open edges and seven gradient-opposing triangles. The diagnostic mesh is cropped; crop-boundary open edges are listed separately and no closed-manifold claim is made. Cave connectivity, full 3D Hausdorff distance, collider parity, GPU cost, presented frame time and actual feature-preservation acceptance were not measured.

## Focused execution and final validation

The corrected focused diagnostic (`attempt-006`) used the pinned Godot binary, passed `--check-only`, and emitted `DIAGNOSTIC_COMPLETE`, 15 assertions and zero failures; stderr was empty. Attempt 005's omitted selection record and the earlier parser/runtime failures remain in the evidence tree and are not counted as passing attempts.

On final measured source `bbaf1950547a5cccb1d0e62fcd434a97373bcfee`, the full `scripts/validate.ps1` command completed with exit code 0 in 526,004 ms (8m46s). It reported 21 assertion-bearing suites, 21,464 assertions and zero failures, followed by `VALIDATION_PASS`. There were 22 `L2 PASS` lines because the configured-main-scene startup gate is counted in addition to the 21 assertion-bearing test suites. Stderr contained three existing non-fatal `Camera3D.look_at` colinearity warnings from `procedural_object_tests.gd` at test lines 991, 1060 and 1069; no parser, script or validation error marker was found. Full stdout, stderr and process record are under `evidence/final-validation-r2/`.

The evidence checksum manifest covers 74 retained files (1,184,777 bytes), excluding only the local isolated profile; its SHA-256 is `f5cb2270f9b11e6ac746a67457a5be3724d2f01d01eb26a2ebe7596f7bc2cf8f`. All 74 entries were independently rehashed with zero mismatches. `SOURCE_SHA256SUMS.txt` SHA-256 is `7ff28f99aff958b36f83484cdc16e0083efb780ac2f6919e49c192bc377f75f9`; the source list includes the experimental script, the pinned B0 manifest, validator and the canonical geometry/oracle dependencies.

The validation used Godot `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. `APPDATA`, `LOCALAPPDATA`, `TEMP`, `TMP` and `PSModuleAnalysisCachePath` were redirected under the disposable evidence profile; Windows `USERPROFILE` was retained. No user save or real profile was used intentionally. The isolated profile is not published.

An earlier full validation on the initial R8.3-B source, `c788b8bd28dd4a0e469c78f06f6c7462abe1360b`, also passed 21,464 assertions but had an altered `USERPROFILE`/`HOME` environment and three `GetSystemDir` errors in the stderr capture. That noisy run is preserved as `final-validation/`; the later `final-validation-clean/` and final-source `final-validation-r2/` runs used the corrected isolation setup. The failed first diagnostic/parser attempts are retained; the first attempt's unavailable raw stderr is explicitly labelled reconstructed-from-console rather than raw.

## Disposition and recommendation

**Blocked as an adaptive-fidelity candidate.** The bounded score-driven method is deterministic and its harness passes, but this policy does not materially improve the coarse mesh's maximum observed ray displacement; it worsens it in the selected finite ROI, leaves extensive internal openings, and introduces several nonconforming outer contours. Uniform 0.125 uses about 37.6 times the 0.5 sample count and about 52.2 times the one-sample build duration in this fixture, while retaining topology/winding defects. None of these runs establishes a production choice or owner-approved tolerance.

The next decision should be whether to fund a separate test-only experiment on conforming transition topology and root-aware edge extraction, with explicit geometry and resource budgets set before measurement. Do not promote this adaptive selection rule or infer product acceptability from the headless validation pass.

All results are research evidence only. Production terrain, ledger, save schemas, gameplay, Issue #108, Issue #154 and F2-G1 state were not changed. The five protected-state markers remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
