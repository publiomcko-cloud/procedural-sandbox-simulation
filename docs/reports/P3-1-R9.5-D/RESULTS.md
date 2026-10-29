# P3.1 R9.5-D — Candidate D Corrective Disposition

Date: 2026-10-29
Candidate evidence PR: #189 (unchanged, open/draft)
Independent R9.5 oracle: [PR #192](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/192)
Disposition: **BLOCKED_WITH_EVIDENCE**. No Candidate D source correction was implemented. The exact cutoff trace attributes all thirteen X+ internal openings to rejected microtriangles; an exhaustive vertex-preserving cap is impossible at the fixed cutoff for both closed loops.

## Source identity

- Measured Candidate D commit: `6ea04229b5ff06090f346c8749c1f5a53994227c`.
- Direct parent: `51744eebf17646ca52612936146adeb0f9db001b`.
- Candidate path: `game/tests/prototypes/p3_1_r9_2_candidate_impl.gd`.
- Git blob: `33ac8bd1f7942ddd71610bd2e2b66f583fdbf3fd`.
- Physical SHA-256: `a33b464ea569f54fb39b72d2198fa971796c0cb5370a64a9696362cd0313f2a6`.
- Test-only reference extractor dependency SHA-256: `d40eb386c534edadae2a8e5d51250bae8a64ef551d5ad5866671afef871f682b`.
- R9.5 source snapshot and 69b process record match the measured D source. No new D implementation bytes were created or executed.

## Hypothesis and evidence

Candidate D's R9.4 independent angle-ordered extractor eliminated the previous severe nonmanifold counts on most frozen cases, but did not close X+. On the exact reloaded float32 volume, D also matches the R9.3 test-only reference extractor's X+ mesh hash; both have the same 13 internal opens. This is agreement between extractors on one frozen byte volume, not proof that the shared output is conforming or canonical.

The R9.5 trace identifies eight three-root fan triangles rejected at the unchanged `1e-12` squared-cross threshold:

- `[6,3,5]`, tetrahedron 4: `9.40420376120688e-13`.
- `[0,4,1]`, tetrahedra 0, 1, 2, 5.
- `[1,4,1]`, tetrahedron 4.
- `[2,5,0]`, tetrahedra 2, 3.

All thirteen internal open edges match these cutoff-created triangle perimeters, with zero nonmanifold edges. The seven-vertex loop has diameter `0.00474863220006227`; exhaustive polygon triangulation gives a best possible minimum cross² of only `4.86268358953069e-15`. The three-vertex loop has diameter `0.00141980650369078`; its maximum possible minimum is `9.40420376120688e-13`, still below the fixed cutoff. These are feasibility bounds only; they do not establish a valid winding, manifold join, or surface error. A local cap using the existing loop vertices cannot pass.

**Attempt count:** one bounded vertex-preserving repair-feasibility hypothesis evaluated; zero corrective source revisions, zero correction executions. The only demonstrated alternatives require additional vertices, vertex movement or expanding the repair patch; their topology and canonical-surface error are unvalidated and no acceptance tolerance is approved.

## Corrected ray interpretation and seams

The nine legacy ray IDs `[2,8,9,13,14,18,19,23,24]` have their top roots above ROI `y=3` and lower-bound roots on its cropped `y=-1` endpoint. They have no in-ROI roots, so no candidate hit is required there. Across all 25 frozen zero-edit vertical rays, D has 0 ROI hit/miss disagreements under the corrected comparison. However, its 30 in-ROI root-to-nearest-mesh distance diagnostics have p50/p95/max `0.00174277 / 0.0482847 / 0.312714` world units. Its ordered X− witness also exhibits later-root deviations from the canonical roots. These distances are descriptive only; no position tolerance is approved.

For equal LOD, the X+ face contour sets match 22/22 segments but D's full ROI still has 13 opens. For the separate mixed-LOD adjacent-ROI proxy, segment counts are 10/22 with 10/22 unmatched and 35 combined internal opens / 0 nonmanifold; no transition mesh is included, so this is a mismatch diagnostic rather than transition acceptance.

Complete cutoff cell/tetra records, raw ray records, shared-sample hash and process metadata are in [R9.5 oracle PR #192](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/192).

## Validation and performance

The exact unchanged D source has R9.4 E2E evidence: 21 variants, PID 55680, exit 0, 13.182 s, including the D-specific corruption reload rejection; contract suite 160 assertions / zero failures; full Godot 4.7.2 validation exit 0, 21 suites, 21,464 assertions / zero failures, 517,271 ms. This evidence remains applicable because the candidate source blob and physical SHA are unchanged.

The R9.5 D diagnostic at oracle `75ed1a8...` and later exact cutoff run at `69b323e...` each exited 0 with zero stderr; later process time was 2.363175 s. This is not a repeated candidate performance benchmark. R9.4 five-sample X+ build p50/p95 values were 106.99/110.10 ms equal LOD and 97.33/99.08 ms mixed LOD. D materialization/extraction timings are in the R9.4 report; no new controlled performance campaign or RSS measurement was run. No FPS, rendered frame, GPU, PhysicsServer or gameplay performance is inferred.

## Next bounded decision

Keep D research-only. A future local repair needs pinned implementation and tests for topology, winding, mixed-LOD interface ownership, picker/ray distance and measured canonical-surface displacement. Do not lower the fixed degeneracy threshold or treat agreement with the R9.3 extractor as acceptance. This is not production integration or architecture approval. All five F2-G1 holds remain unchanged.