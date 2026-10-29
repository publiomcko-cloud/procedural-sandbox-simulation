# P3.1 R9.5 — Consolidated Ray and X+ Corrective Disposition

Date: 2026-10-29
Authorization: Issue #191
Oracle: [R9.5 shared oracle PR #192](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/192)
Candidate A report: [PR #193](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/193)
Candidate D report: [PR #194](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/194)
Disposition: **P3_1_R9_5_BLOCKED_WITH_EVIDENCE**. No candidate A or D source correction was implemented. The nine historical ray hit/miss disagreements are an ROI comparator defect; X+ cutoff holes are genuine and remain.

## Scope and exact sources

- Production source baseline remained `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`; no production paths were changed.
- R9.5 oracle head: `895dbca3c6dd58bb9adacd63fb39c3ad524226ff` (docs/evidence publication head). The final executed diagnostic implementation is `69b323efc3d6f9e86eba9ac1e199cbf932761398`, parent `01fb62569bb3ce7249f4e9058371934c7e83c83e`, script SHA-256 `c8c99eda8f6f8053fd2ddfce62597e634fa2ce11ff2f1e436f321236257518f4`.
- A: `f0c93415dd56886a1c05ff2e6a1340e420f22c59`, physical `970fe99f192ea2a3fea3e682072ed3562e6f57c843561dd4440e46381a384d8a`, blob `5a19b05d3f39108e53c8b7ff47d28303ee7bfbb0`.
- C unchanged control: `af4d6027d9d57c9f2b8023aa27b31d2dd2dcedf2`, physical `7072f39b2c48dcb38048e2ee3d1687baa9377bcc99ca8250ac2c0f84cff17d24`.
- D: `6ea04229b5ff06090f346c8749c1f5a53994227c`, physical `a33b464ea569f54fb39b72d2198fa971796c0cb5370a64a9696362cd0313f2a6`, blob `33ac8bd1f7942ddd71610bd2e2b66f583fdbf3fd`.
- Frozen input manifest SHA-256 `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`; Godot 4.7.2 binary SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Fixed triangle rejection threshold: squared cross product `1e-12`.

Candidate source snapshots, physical hashes, Git blobs, process identities, raw logs, full ray table, cutoff rows and SHA-256 manifests are in PR #192. The raw 75ed campaign index repeats D's source blob for all three candidates; its raw-preserving correction sidecar and each process record are retained. Later 69b A/D records carry correct source blobs.

## Root causes

### Historical ray matrix

The exact old comparator disagreement IDs were `[2,8,9,13,14,18,19,23,24]` for each of A/C/D. The same nine do not indicate a common candidate defect: all nine have no canonical root strictly inside the candidate's Y-cropped ROI [-1,3]. Their upper roots are above y=3 and the lower-bound roots lie at the y=-1 crop endpoint, so a cropped mesh correctly has no hit. The old finite scan comparison treated a global-field root as a required mesh hit regardless of ROI.

For the specified zero-edit vertical rays, analytic component-root enumeration matches the independently coded adaptive 1-Lipschitz subdivision/bisection on all 25; there are no unresolved tangent intervals in these fixtures. This does not prove completeness for arbitrary ray directions, edits, or tangent configurations. With the root comparison scoped to the same ROI, A/C/D each have zero hit/miss disagreements.

Candidate-to-root distance observations remain separate and unscored. For A's 30 in-ROI comparisons, nearest-hit distance error p50/p95/max is 0.0000236237/0.0000561489/0.0000576078 world units. For D it is 0.00174277/0.0482847/0.312714. D's ordered X− witness also has later-root deviations. No geometry-distance tolerance is owner-approved; therefore these are not passes. CPU proxy results are not PhysicsServer or production picker behavior.

### X+ interface and microtriangle cutoff

All 533 shared X=16 canonical binary32 samples match bitwise (`084fee4d...fc774d`). This excludes a shared-coordinate/sample disagreement in the frozen diagnostic, but does not prove all runtime coordinate mappings.

| Candidate | Equal face contour | Equal-pair opens / nonmanifold | Mixed face contours | Mixed-pair opens / nonmanifold | Internal X+ opens | Cutoff drops |
|---|---:|---:|---:|---:|---:|---:|
| A | 22 vs 22; 0/0 unmatched | 8 / 0 | 10 vs 22; 10/22 unmatched | 32 / 0 | 8 | 7 |
| C (unchanged control) | 28 vs 28; 0/0 unmatched | 40 / 55 | 12 vs 28; 12/28 unmatched | 54 / 0 | 42 | not traced in R9.5 |
| D | 22 vs 22; 0/0 unmatched | 13 / 0 | 10 vs 22; 10/22 unmatched | 35 / 0 | 13 | 8 |

The equal/mixed pair observations are separate candidate ROI meshes; they do not contain a transition surface and are diagnostics, not production chunk acceptance. Equal-LOD segment matching does not remove each candidate's internal openings.

A's seven single-triangle drops occur at cells `[0,4,1]`, `[1,4,1]`, `[2,5,0]`; D's eight fan-triangle drops occur at `[6,3,5]`, `[0,4,1]`, `[1,4,1]`, `[2,5,0]`. The exact tetrahedra, source binary32 samples, crossing-root identities/positions, cross² values and edge incidence are recorded in the machine-readable R9.5 oracle evidence. All A and D internal openings are accounted for by rejected triangle perimeters; no unexplained openings or nonmanifold edges are observed in the equal-pair A/D diagnostic.

A's six-vertex internal loop has diameter 0.0038049191 and the best possible minimum cross² over every triangulation of existing vertices is only `1.18455592557076e-14`. D's 7- and 3-vertex loops have best possible minima `4.86268358953069e-15` and `9.40420376120688e-13`, both below the fixed `1e-12` cutoff. The DP bound rejects the existing-vertex cap hypothesis; it does not establish that vertex movement/addition or outer-ring repair is safe.

## Corrective attempts

| Candidate | R9.5 source-correction hypotheses implemented | Outcome |
|---|---:|---|
| A | 0 | Vertex-preserving loop cap shown infeasible under cutoff. X+ remains 8 internal openings. |
| D | 0 | Both cutoff loop caps infeasible using existing vertices. X+ remains 13 openings and mixed-LOD contours remain mismatched. |

No source correction was attempted because the remaining possible strategies require new/moved geometry or a wider repair patch. Their surface displacement, normals, winding, adjacent chunk topology and picker effects are not proven, and the task has no accepted geometry-error threshold. This is the bounded blocker, not a claimed fix. No thresholds, SDF, frozen inputs or classifications were changed.

## Validation and CPU observations

The exact unchanged A and D sources have existing R9.4 E2E and full-validation evidence, retained under PRs #187/#189: each completed its 21-variant E2E run (A PID 46308 / 12.994 s; D PID 55680 / 13.182 s); each passed the 160-assertion contract suite; and each passed full Godot 4.7.2 validation with 21 suites / 21,464 assertions / zero failures (A 516,256 ms; D 517,271 ms). These results apply to R9.5 because independent blob and physical-hash checks confirm the measured A/D sources are unchanged. They do not validate a correction.

Five same-process headless build samples from R9.4 provide context:

| Candidate | X+ equal p50/p95 ms | X+ mixed p50/p95 ms |
|---|---:|---:|
| A | 105.00 / 109.07 | 100.38 / 102.88 |
| C | 35.53 / 37.73 | NOT_REPORTED |
| D | 106.99 / 110.10 | 97.33 / 99.08 |

R9.5 diagnostic process wall times: A 2.402 s at the initial final-oracle revision and 2.664 s with later cutoff tracing; D 2.301 s and 2.363 s respectively. These runs perform different amounts of oracle work and are not comparable performance repetitions. C ran once. No new multi-run performance campaign, RSS, GPU, presented frame, or gameplay FPS was measured.

Godot 4.7.2 oracle check-only passed at the final diagnostic source. A/C/D R9.5 diagnostics exited 0 with empty stderr and `DIAGNOSTIC_COMPLETE_ONLY`; zero harness failures means the diagnostic completed, not that geometry targets passed. One preflight identity command initially ran from the wrong directory and failed before process creation; it is preserved and followed by a corrected passing check-only. Full validation is reused only for exact unchanged A/D sources.

## Conclusion and next engineering decision

Do not choose or adopt A, C or D for production. Do not lower the cutoff. The exact next research gate is a new pinned A/D experiment for bounded local repair that may add/move vertices, preceded by an explicit geometric-deviation/normal contract and preregistered interface/topology tests. If no such contract is available, retain the candidates as blocked research and stop. No GUI, rendered, GPU, PhysicsServer, save/schema, production, or release claim is established.

PRs #187–#190 remain unchanged and open/draft/unmerged. New R9.5 evidence PRs #192–#194 are draft/unmerged. All five F2-G1 holds remain in force.