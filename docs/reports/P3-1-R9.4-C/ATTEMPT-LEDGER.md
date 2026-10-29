# R9.4-C Attempt Ledger

| Attempt | Defect / hypothesis and prediction | Implemented correction | Focused result | Outcome / next action |
|---:|---|---|---|---|
| 1 | One dual vertex averages disconnected surface patches; checkerboard face ambiguity may disconnect or merge incident dual adjacency. Predicted fewer opens/nonmanifold edges. Basis: direct one-vertex-per-cell source and exact topology counts. | Build connected contour components per cell; map each crossing lattice edge to its component vertex; route dual quads through those mappings. | Neighbor nonmanifold 3→0, but opens 3 remain. FILL/CARVE nonmanifold 2→1, 26 opens remain. Other principal counts remained defective. | PARTIAL; investigate shared-face ambiguity. |
| 2 | Face-center sign is not a sufficient checkerboard decider under asymmetric corner magnitudes. Bilinear saddle should select a face-consistent pairing. | Use bilinear asymptotic saddle (a*c-b*d)/(a-b-d+c); add asymmetric synthetic shared-face regression. | Synthetic regression passed on both sides of shared X face; frozen mesh counts unchanged from attempt 1. | FAILED for frozen topology targets; stop before smoothing variants. |

## Provenance qualification

Intermediate attempt source snapshots were not preserved; logged source SHA points to R9.3 base, not the mutable attempt source. Mark intermediate identities UNPINNED_WORKTREE. Final committed source and exact final runs are pinned to af4d6027d9d57c9f2b8023aa27b31d2dd2dcedf2.
