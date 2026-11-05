# P3.1 shared-surface authority — E2E integration protocol

Status: PREREGISTERED / EXPERIMENTAL / NO MERGE AUTHORIZATION

## Source identity

- Parent success branch: `exp/p3-1-shared-surface-authority-success`
- Parent commit: `4de772ecaa86639e98be41ed031447e82ba5851c`
- E2E branch: `exp/p3-1-shared-surface-e2e-integration`
- R6 branch remains out of scope and must not be modified.

## Architecture under qualification

A new data-only `SharedSurfaceBoundaryAuthority` owns X-adjacent region-edge chunk pairs. It samples one canonical world-space SDF volume, uses one global lattice-edge root cache, polygonizes once, then partitions the triangles back into the existing left/right region chunk publication units.

The production LOD policy tested here is deliberately conservative:

- region-edge chunks participating in a regional seam are LOD0;
- LOD1 may begin one chunk inward;
- the existing LOD1 transition-cell mesher must conform to the LOD0 boundary chunk at that internal chunk boundary.

This removes mixed resolution from the regional seam itself while retaining LOD1 in region interiors.

## Frozen scientific replay

The R9.2/R6 target family remains unchanged:

- seed: `131102026`
- generator version: `1`
- ROI min: `(15,1,6)`
- ROI cells: `(8,8,8)`
- sample step: `0.25`
- seam: `x=16`
- edit 0: FILL `(8,1.17898154258728,5.10309219360352)`, radius `0.58`
- edit 1: CARVE `(8,1.17898154258728,5.92309236526489)`, radius `0.58`

## E2E PASS gates

The campaign passes only if all of the following hold in stock Godot 4.7.2:

1. Exact 0.25 R6 replay builds through the reusable authority with non-empty seam, incidence 2, zero T-junctions, no duplicate/emitted-degenerate triangles and stable global root identities.
2. All four production X+ boundary chunk pairs for regions `(0,0)` and `(1,0)` build at the production 0.5 sample step through worker-compatible jobs.
3. Aggregated production regional seam has at least one surface edge, zero bad incidence, zero T-junctions, and every seam edge has geometry from both region sides.
4. At least one left and one right shared boundary CPU result successfully publishes to real Godot `ArrayMesh` resources.
5. Mixed LOD is qualified on both sides for all four z chunk rows by pairing existing LOD1 interior chunks with forced-LOD0 shared boundary chunks. Aggregated internal seams must be non-empty, incidence-correct, T-junction-free and cross-owned.
6. Schema-v2 terrain persistence saves generation 1, all live ledger/store objects are dropped, a fresh store reloads the generation, and the complete four-pair boundary signature reproduces exactly.
7. A fixed FILL centered on the regional seam at `(16,1.75,7)`, radius `1.25`, is accepted as one ordered edit; it must change the complete boundary signature.
8. After that cross-region edit, both the regional seam and mixed-LOD collars retain zero bad incidence and zero T-junctions.
9. The edited generation is persisted, unloaded, reloaded through a fresh store, and reproduces its complete boundary signature exactly.
10. Temporary test persistence is removed at the end of the run.

Any tooling/parser defect is recorded separately and does not count as a scientific failure until the harness reaches the relevant gate. No gate may be weakened after observing a geometric failure.
