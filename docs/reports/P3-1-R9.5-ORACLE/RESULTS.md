# P3.1 R9.5 — Independent Ray and X+ Causal Results

Date: 2026-10-29
Repository: publiomcko-cloud/procedural-sandbox-simulation
Issue authorization: #191
Disposition: **BLOCKED_WITH_EVIDENCE**. The corrected oracle resolves the historical 9/25 ray *classification* error, but X+ has genuine cutoff-caused internal openings in both A and D; mixed-LOD contours also remain unmatched. No candidate source correction was produced or accepted.

## Exact identities

- Oracle diagnostic source: `69b323efc3d6f9e86eba9ac1e199cbf932761398` (parent `01fb62569bb3ce7249f4e9058371934c7e83c83e`); script physical SHA-256 `c8c99eda8f6f8053fd2ddfce62597e634fa2ce11ff2f1e436f321236257518f4`, Git blob `ea63a537e396dadcba02c8140005f7b54e63122e`.
- Candidate A: source `f0c93415dd56886a1c05ff2e6a1340e420f22c59`, parent `d5903242e41642a2633e18dc181c4389188c65b2`, source blob `5a19b05d3f39108e53c8b7ff47d28303ee7bfbb0`, physical SHA-256 `970fe99f192ea2a3fea3e682072ed3562e6f57c843561dd4440e46381a384d8a`.
- Candidate C control, unchanged: source `af4d6027d9d57c9f2b8023aa27b31d2dd2dcedf2`, blob `d8cd7e32f88d864bef97bfb4d675b7d461bee4c7`, physical SHA-256 `7072f39b2c48dcb38048e2ee3d1687baa9377bcc99ca8250ac2c0f84cff17d24`.
- Candidate D: source `6ea04229b5ff06090f346c8749c1f5a53994227c`, parent `51744eebf17646ca52612936146adeb0f9db001b`, source blob `33ac8bd1f7942ddd71610bd2e2b66f583fdbf3fd`, physical SHA-256 `a33b464ea569f54fb39b72d2198fa971796c0cb5370a64a9696362cd0313f2a6`.
- Frozen input manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.
- Godot `4.7.2.stable.official.ed1daf0bf`; console SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- R9.4 comparison base: `9bdfcd59241d76bd57b95b9e2bb5c1982834071b`; R9.5 oracle commit chain is based on that accepted research branch. No production path was changed.

The committed R9.5 snapshots were independently checked against the measured A/D commits: Git blob IDs match and their physical SHA-256 values match the prior source identity record. The 69b process metadata records the correct candidate blob for each run. The earlier 75ed raw `campaign-index.json` incorrectly repeats D's blob for A/C/D; its preserved `source-attribution-correction.json` supplies the per-process correction without altering the original raw records.

## Ray oracle: cause of the historical 9/25

The frozen 25 rays are vertical, origin Y=8, direction -Y, maximum distance 12, in the CAVE_SMALL ROI with Y bounds [-1,3]. On the zero-edit canonical field, the closed-form enumeration includes top surface, cave upper/lower and lower-bound roots, filtered through the full canonical sampler. A separate adaptive subdivision/bisection implementation uses the 1-Lipschitz exclusion rule. All 25 analytic root sets matched the adaptive results; there were zero unresolved tangent intervals for these fixtures. The legacy 256-step scan remains a comparison method, not a complete oracle.

The legacy disagreement ray IDs are exactly `[2,8,9,13,14,18,19,23,24]` in A, C and D. Each has its top-surface root above the mesh ROI top (y > 3), and its lower-bound root on the cropped y=-1 endpoint. Each has **zero canonical roots strictly inside the ROI**, so the cropped candidate mesh correctly reports no hit. All nine have `roi_hit_miss_disagrees=false` for all three candidates. The old comparator incorrectly required a mesh hit for any full-world root, even when every root was outside/on the cropped ROI boundary. This is a shared comparator defect, not a candidate mesh miss.

Across all 25, A/C/D each have zero ROI hit/miss disagreements. There are 14 rays with a global first root cropped but later in-ROI root(s), nine with no in-ROI root, and two in-ROI distance-only diagnostics. No geometry-distance tolerance has been approved, so these distance values are descriptive only. For in-ROI canonical-root to nearest two-sided candidate-hit distance diagnostics, A has 30 comparisons (p50 0.0000236237, p95 0.0000561489, max 0.0000576078 world units); D has 30 (p50 0.00174277, p95 0.0482847, max 0.312714). D's distance deviations are not resolved by the corrected hit/miss classification. These values are not acceptance results.

The separately frozen ordered X− witness also has a valid adaptive first root inside its ROI. A mesh first hit is 6.11300636 versus canonical 6.11299491; D is 6.11299438. Later-root distances differ more for D. Triangle 3103 remains a local-cell witness only; no historical full-mesh triangle-index equivalence is claimed.

## X+ causal evidence

The shared interface is X=16. The independent region/local mapping test compares 533 canonical binary32 samples; all 533 match bitwise (SHA-256 `084fee4ddb926e2934cd22143d7c10c2f76395c828884f2e9235bf8fe3fc774d`). This rules out an X+ shared-sample coordinate discrepancy for this frozen probe.

| Candidate | Equal-LOD segment counts | Equal contour deltas | Equal-pair internal opens / nonmanifold | Mixed-LOD segments | Mixed contour deltas | Mixed-pair opens / nonmanifold |
|---|---:|---:|---:|---:|---:|---:|
| A | 22 / 22 | 0 / 0 | 8 / 0 | 10 / 22 | 10 / 22 | 32 / 0 |
| D | 22 / 22 | 0 / 0 | 13 / 0 | 10 / 22 | 10 / 22 | 35 / 0 |

Equal-LOD face contours agree as segment sets, yet each full ROI mesh contains cutoff-related internal openings. Independent expected-face endpoint differences are reported in the raw log (A maximum 0.0000428225 world units); no endpoint tolerance is approved. The mixed-pair test builds separate adjacent candidate ROIs and has no transition surface, so it diagnoses mismatch but is not a complete transition-cell acceptance test.

- **A:** 7 three-root single triangles were rejected because their squared cross products are at or below the frozen `1e-12` threshold. They originate at cells `[0,4,1]` (tetrahedra 0,1,2,5), `[1,4,1]` (3,4), and `[2,5,0]` (2). The 6-edge interior cutoff loop has diameter 0.0038049191. Dynamic programming over every triangulation of those ordered existing vertices found the maximum achievable minimum cross² is `1.18455592557076e-14`, far below `1e-12`; a vertex-preserving cap cannot pass the unchanged cutoff. Eight internal open edges are accounted for by cutoff-triangle perimeters; the 2-edge component meets the ROI-cropped boundary. No unexplained X+ internal opens and no nonmanifold edges were observed.
- **D:** 8 three-root fan triangles were rejected by the same cutoff: cell `[6,3,5]` tet 4; `[0,4,1]` tets 0,1,2,5; `[1,4,1]` tet 4; `[2,5,0]` tets 2,3. The 13 internal openings comprise a 7-edge loop (diameter 0.0047486322, best possible minimum cross² `4.86268358953069e-15`), a 3-edge loop (diameter 0.0014198065, best possible `9.40420376120688e-13`, still below cutoff), and a component touching the cropped boundary. All 13 are accounted for by cutoff-triangle edges; none is nonmanifold. D's output equals the R9.3 test-only reference extractor on identical reloaded volume bytes, but that reference also has these openings and is not canonical truth.

This proves the proximate mechanism: the fixed area rejection removes tiny valid-root polygons and exposes their perimeter edges. It does not prove whether the best remedy is new-vertex remeshing, bounded vertex movement, refinement, or another extractor. No candidate source was changed: the only bounded feasibility trial exhaustively rejects a cap using current loop vertices. Moving/adding geometry requires an explicit measured error contract and additional topology validation; no such acceptance tolerance exists in this task. Candidate A/D correction attempts executed: **0**; no candidate corrective source revision or post-correction validation is claimed.

## Runs, checks and performance observations

The 75ed oracle campaign ran A/C/D once each and emitted 25 ray records per candidate; process exit codes were 0, stderr was empty, and each reported `DIAGNOSTIC_COMPLETE_ONLY` with zero harness failures. The later 69b cutoff campaign ran A and D once each, exit 0, zero stderr, and emitted complete cutoff traces. Godot check-only passed on the 69b oracle source. A prior preflight attempt failed before process creation because a Git identity check ran in the wrong working directory; its attempt record is retained and no scenario was started by it.

Oracle diagnostic process elapsed observations (not comparable performance samples): A 2.402 s / later 2.664 s; D 2.301 s / later 2.363 s. The second oracle version performs additional cutoff tracing and loop feasibility work. C ran once at 1.653 s. No RSS or GPU/presented-frame observation is available.

The measured, unchanged exact A/D sources already have R9.4 same-process five-sample build results: A X+ equal/mixed p50/p95 105.00/109.07 ms and 100.38/102.88 ms; D 106.99/110.10 ms and 97.33/99.08 ms. These are headless build timings, not gameplay frame times. R9.4 exact-source evidence also includes each candidate's 21-variant E2E campaign, 160-assertion contract suite, and full Godot validation: 21 suites, 21,464 assertions, zero failures (A validation 516,256 ms; D 517,271 ms). These are reused because the R9.5 measured A/D source bytes are identical to those exact validated commits. No new candidate correction occurred after those runs.

## Attempt ledger and decision

| Item | Pinned source | Outcome |
|---|---|---|
| Ray/ROI oracle and 533-sample face coordinate oracle | oracle `75ed1a8d0ec16a321e2328456a48633fc72ca63e` | Resolved legacy hit/miss comparator classification; all A/C/D ROI hit states match. |
| Exact cutoff trace and existing-vertex cap feasibility | oracle `69b323efc3d6f9e86eba9ac1e199cbf932761398` | Confirms all A/D opens are cutoff explained; exact-vertex cap cannot meet cutoff. |
| Candidate A correction hypotheses | source `f0c93415dd56886a1c05ff2e6a1340e420f22c59` | 0 corrective implementations; unresolved geometry requires a new bounded geometry-preserving strategy or owner-approved error criterion. |
| Candidate D correction hypotheses | source `6ea04229b5ff06090f346c8749c1f5a53994227c` | 0 corrective implementations; same blocker, with mixed-LOD and ray-distance deviations additionally unresolved. |

Recommendation: keep A, C and D as research-only. The next experiment should preregister a bounded local repair that may add/move vertices, but first establish a measurable canonical-surface deviation/normal contract and validate the affected chunk interfaces. Do not lower the fixed `1e-12` cutoff or call the current candidates corrected. No production adoption, release, GUI, physics, or architecture acceptance is implied.

All five F2-G1 holds remain unchanged. Existing PRs #187–#190 and their evidence remain open, draft and unmerged.