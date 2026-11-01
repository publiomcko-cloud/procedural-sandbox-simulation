# P3.1 R12-CXR R5 — Constraint-Guided Field-Support Synthesis

**State:** experimental preregistration; no production adoption.
**Baseline:** R4 PR #216 HEAD `6407572f1ee9c57e2c530e0f021490d5a90ba8e3`.
**Measured Candidate D source:** `f48990e25ffb1d377e02a9182240cabe35c815eb`.
**Frozen target:** `R9.2.SEAM.XPLUS_EQUAL.v1`.
**R4 D1 result:** SHA-256 `927ec58f8f4e7821d9acb27a46068a4fa5fccf4f354f22b24be9cf88f90970c4`.
**R4 D2 cavity:** six faces, six boundary edges, one boundary cycle, signature `90be2d27d3c08ccb2fe93ebf6b8a0da0d8955d3c4d533a4496809b4d07bd363b`.

## Experimental boundary

R5 operates only under `game/tests/prototypes/` and its fixtures. It keeps Candidate D's volume values and revision, the exact R4 topology/roots/arcs, cavity ownership, patch and cutoff unchanged. It does not edit the R4 realizer, Candidate D, scalar samples, mesh topology, production SDF, save formats, or gameplay. It may call the unchanged R4 constrained candidate validator and solver after synthesizing bounded field-supported vertices.

The original R4 cavity is regenerated from its pinned source and D1 evidence before either mode runs. Its canonical JSON bytes and SHA-256 must equal `fixtures/r12_cxr_r5/frozen-cavity.json`; otherwise the campaign fails before synthesis.

## Constraint-guided construction

The target manifest fixes an 8×8×8 cell ROI at 0.25-world-unit spacing: 729 binary32 scalar samples and exactly 3,072 tetrahedra using the existing six-tetrahedra decomposition per cell. R5 enumerates those tetrahedra, calls the unchanged R4 zero-edge interpolation, classifies zero primitives, and deterministically triangulates only triangular or quadrilateral field-zero primitives. No density values are resampled or changed.

Each zero-set facet is projected into the frozen cavity's R4 plane and clipped against the deterministic ear triangles of the frozen boundary polygon. Exactly six boundary roots define 15 unordered boundary-root pairs. For each clipped component and pair, R5 evaluates its deterministic interior witnesses (strictly interior clipped vertices and the clipped-component centroid), then retains the greatest admissible 3D squared cross-product for that pair/component. The witness count is capped at seven, the geometric maximum for a triangle clipped by a triangle plus its centroid. A candidate must remain on the source tetrahedron's piecewise-linear zero set, pass the existing field-residual and support-distance limits, be finite, lie strictly inside the frozen cavity projection, and not duplicate a topology root. Binary32-position identity deduplicates shared points; provenance retains source cell, tetrahedron, samples, barycentric weights, primitive, constraint pair, and residual owner.

This is a finite, constraint-derived candidate construction, not a dense point-cloud filter. The projected cavity is clipped before support emission. Arc crossings and exact triangle ownership/orientation remain checked by the unchanged R4 candidate-triangle gate; a triangle rejection does not establish that an entire continuous subregion is infeasible. The current candidate enumerator does not analytically partition every support region by every arc, owner, support-distance boundary, or T-junction constraint. Therefore `finite_candidate_enumeration_complete` means only that the declared finite witnesses were examined. It is never an analytic feasible-domain exhaustion claim. A missing witness, unpartitioned active constraint, or candidate cap keeps the result **PARTIAL**, never a claim of global infeasibility.

The graph gate passes each triplet from the finite support set through the unchanged `_r2_get_candidate_triangle`, which enforces the frozen `cross_squared > 1e-12` cutoff, domain containment, required arcs, ownership and winding. If the complete finite triplet set contains zero legal triangles, D3 is not invoked. If it contains legal triangles, the unchanged `_r2_search_level` runs with R4 limits. Any solution is sent through the existing final patch, topology, path, root, arc, and fixed-cutoff gates before it can be called realized.

## Preregistered resource caps

These caps are committed before a valid synthesis execution:

| Resource | Cap | Exhaustion behavior |
| --- | ---: | --- |
| Source tetrahedra | 3,072 for the frozen 8³ ROI | Input mismatch blocks preflight |
| Enumerated zero facets | 6,144 | Stop; `PARTIAL` |
| Projected clip fragments | 32,768 | Stop; `PARTIAL` |
| Eligible source pairs | 15 unordered pairs of the six frozen boundary roots | Input mismatch blocks preflight |
| Critical witnesses per clipped fragment | 7 (strictly interior clipped vertices plus centroid) | Stop; `PARTIAL` |
| Unique raw field supports | 4,096 | Stop; `PARTIAL` |
| Retained supports | 64, ranked by maximum accepted cross-squared then stable ID | Truncation marks `PARTIAL` |
| Synthesis wall time | 30,000,000 μs | Stop; `PARTIAL` |
| Candidate triangle probes | `min(R4 per-cavity 65,536, total 131,072)` = 65,536 | Stop; `PARTIAL` |
| Candidate graph vertices | At most 74, because `C(n,3)` must remain within the 65,536 probe cap; derived edge ceiling is `C(n,2)` | Stop before graph probing; `PARTIAL` |
| D3 | Existing R4 limits: 32,768 search states/cavity; 65,536 total; 10,000,000 μs/cavity; 20,000,000 μs total | Existing solver emits its terminal limit; no cap increase |

The geometric acceptance cutoff remains exactly `cross_squared > 1e-12`. R4's `CXR_MAX_SUPPORT_DISTANCE=0.5`, `CXR_FIELD_RESIDUAL_EPSILON=1e-7`, and `CXR_BARYCENTRIC_EPSILON=1e-7` are read from the pinned R4 realizer; they are not tuned by R5.

## Contract and synthetic solver fixture

The R5 contract suite checks linear-interval and convex-domain clipping, the cross-squared endpoint maximum on a segment, triangle/quad/degenerate zero primitives, exact barycentric field-zero validation, deterministic support IDs, binary-position deduplication, order-independent graph hashing, required-arc crossing rejection, owner assignment/rejection, root-support and support-support candidate triangles, and off-domain rejection. A synthetic tetra with two positive and two negative samples has a diamond zero quad; its edge roots are all cavity-boundary points, so a point-first edge-root pool has no interior support. The clipped zero facet's deterministic interior centroid supplies a field-valid support, and the unchanged R2 solver is exercised at the fixed one-support level to require a complete four-triangle fan. This is a harness contract fixture, not evidence that the frozen R4 target succeeds.

The campaign emits an R5-A constraint report with the exact frozen cavity cycle, directed edges, required topology roots/arcs, projection basis, all 15 boundary-root pairs, and the pinned R4 D1 graph totals. The R5-C report records every finite triplet probe, rejection histogram, legal graph-edge classes, support degrees, supports used by legal triangles, legal cross-squared extrema, and both probe-audit and candidate-graph SHA-256 values. If the finite graph has no legal triangle, D3 is skipped and the outcome remains partial because the full continuous feasible-support domain has not been analytically exhausted.

The frozen R4 residual fixture encodes owner-face geometry as `triangle_vertices_world`; normalized synthetic rows may use `points`. R5 validates either representation with strict three-vertex and finite-coordinate checks, derives centroids in stable triangle-ID order, and fails before tetrahedron enumeration if any owner row is malformed. The first post-commit target launch exposed the fixture-field mismatch before scanning the zero-set; it is retained as a pre-geometry tooling/source failure and does not count as a valid scientific synthesis execution. Its process exit code was not captured by the first launcher and remains `UNKNOWN_NOT_CAPTURED`.

## Attempt policy and classification

Import, `--check-only`, R5 contract tests, and exact R4 cavity reconstitution are preflight, not scientific target executions. A valid `synthesize` invocation of the frozen target consumes one of the procedure's maximum five scientific executions. No automatic retry is allowed after that target process starts. A process/fixture failure before synthesis is recorded and may be corrected under the procedure's recovery rules.

Possible equal-LOD outcomes are `R5_EQUAL_LOD_PASS_DOWNSTREAM_PENDING`, `R5_EQUAL_LOD_GATE_FAIL`, or `R5_SUPPORT_SYNTHESIS_PARTIAL`. The equal-LOD result never represents completion of R5-Q. A successful equal-LOD mesh requires the separately executed control, ROI-ray, volume reconfirmation, mixed-LOD, deterministic-repeat and full-E2E gates; `R12_CXR_R5_ARCHITECTURE_QUALIFIED` also requires `scripts/validate.ps1` to pass. If mixed LOD fails after equal LOD passes, preserve the equal-LOD artifact and report `R12_CXR_R5_EQUAL_LOD_QUALIFIED_INTERFACE_BLOCKED_WITH_EVIDENCE`. Zero legal triangles in a fully enumerated finite graph is reported with its exact finite-witness scope; it is not a proof that no support exists on the continuous field. Performance remains UNSCORED and headless timings are not presented-frame evidence.
