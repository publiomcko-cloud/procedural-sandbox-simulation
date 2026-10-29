# P3.1 R9.5-A — Candidate A Corrective Disposition

Date: 2026-10-29
Candidate evidence PR: #187 (unchanged, open/draft)
Independent R9.5 oracle: [PR #192](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/192)
Disposition: **BLOCKED_WITH_EVIDENCE**. No Candidate A source correction was implemented. The R9.5 diagnostic establishes the cutoff mechanism and rejects the only vertex-preserving cap hypothesis as infeasible under the immutable threshold.

## Source identity

- Measured Candidate A commit: `f0c93415dd56886a1c05ff2e6a1340e420f22c59`.
- Direct parent: `d5903242e41642a2633e18dc181c4389188c65b2`.
- Path: `game/tests/prototypes/p3_1_r9_2_candidate_impl.gd`.
- Git blob: `5a19b05d3f39108e53c8b7ff47d28303ee7bfbb0`.
- Physical SHA-256: `970fe99f192ea2a3fea3e682072ed3562e6f57c843561dd4440e46381a384d8a`.
- Independent R9.5 snapshot and process mapping match this source. No new Candidate A source bytes were created or executed.

## Hypothesis and evidence

R9.4-A had already changed complete tetrahedron quad diagonal choice and root refinement while preserving squared-cross rejection at `1e-12`. On the R9.5 frozen X+ ROI, the independent trace shows seven additional single-triangle drops below the same threshold and eight internal open edges. Every internal opening is accounted for by a dropped cutoff triangle perimeter; there are no unexplained openings or nonmanifold edges in this diagnostic.

The primary internal loop has six ordered boundary vertices and diameter `0.00380491907708347`. A dynamic-programming search over every triangulation of that ordered polygon using exactly the existing boundary vertices found the best possible minimum triangle cross² is `1.18455592557076e-14`, versus the unchanged `1e-12` rejection threshold. Therefore the proposed hypothesis “cap the loop with a different triangulation of the existing vertices” is rejected before candidate implementation: it cannot produce accepted triangles under the current cutoff. The remaining two-edge open component meets the finite ROI boundary.

**Attempt count:** one bounded vertex-preserving repair-feasibility hypothesis evaluated; zero corrective source revisions, zero correction executions. No source was changed to hide the defect. Adding vertices, moving boundary roots, or expanding the local patch may be viable, but none is proven to preserve the canonical surface within a measurable accepted bound.

## Ray correction and X+ results

The legacy nine ray IDs `[2,8,9,13,14,18,19,23,24]` are not A mesh misses. Their only top roots lie above ROI `y=3`; lower-bound roots lie at the cropped `y=-1` endpoint; none lies strictly inside the mesh ROI. Under the corrected independent root/ROI comparison, A has 0/25 hit/miss disagreements. For its 30 in-ROI root-to-mesh distance diagnostics, p50/p95/max are `0.0000236237 / 0.0000561489 / 0.0000576078` world units. These are observations only; no distance tolerance is approved.

Equal-LOD X+ contours contain 22/22 matching segments, with zero segment deltas, but the full candidate ROI still has 8 internal opens. Mixed LOD has 10 versus 22 segments, all 10/22 unmatched, and a combined adjacent-ROI proxy with 32 opens / 0 nonmanifold. That proxy has no transition surface and is not full transition-cell acceptance.

The raw per-run details, source attribution, full 25-ray matrix, cutoff drops, edge witnesses and SHA-256 inventory are in [the independent oracle evidence](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/192).

## Validation and performance

The exact unchanged A source has R9.4 E2E evidence: 21 frozen variants, process PID 46308, exit 0, 12.994 s; 160 contract assertions, zero failures; full Godot 4.7.2 validation exit 0, 21 suites, 21,464 assertions, zero failures, 516,256 ms. These results are reusable because source blob/physical hash are unchanged. The R9.5 shared diagnostic itself ran A at oracle `75ed1a8...` and `69b323e...`, exit 0 with zero stderr; it is diagnostic completion, not a corrected geometry pass.

R9.4 five-sample X+ build timing remains 105.00/109.07 ms p50/p95 equal LOD and 100.38/102.88 ms mixed LOD, headless CPU only. R9.5 oracle process times are not comparative performance runs because later oracle versions perform additional work. No rendered frame, GPU, PhysicsServer, GUI or production claim is made.

## Next bounded decision

Do not lower `1e-12`. A further A experiment needs a pinned candidate implementation and preregistered checks for topology, winding, nonmanifold edges, seam identity, and measured canonical-surface displacement before it runs. This report does not request production adoption or architecture selection. All F2-G1 holds remain unchanged.