# 2026-11-01 — P3.1 R12-CXR R4 triangulation partial

R4 is an isolated test-only experiment on branch `exp/p3-1-r12-cxr-r4-boundary-first-realizer`, based on R3AB PR #215 head `58f946c857f419dd80b8ab703f4138894aee455c`. Measured source is `f48990e25ffb1d377e02a9182240cabe35c815eb` (parent `b2480bc71fe9c9616426d378feb00e3e33e785f2`).

The exact support pool reproduced 115 rows and produced 18 legal candidate edges from 1,374 probes, but zero legal triangles. Boundary-first D2 completed at 15 states/queue peak 12 with a six-face connected cavity and one projected outer loop. D3 exhaustively recorded 329 rejected triangles and zero solutions in five branches; no global infeasibility claim follows from this finite candidate domain. The disposition is `R12_CXR_R4_TRIANGULATION_PARTIAL_WITH_EVIDENCE`.

Godot 4.7.2 import, realizer and D1 parser checks passed; the exact-source R12-CXR suite passed 216/216. The pinned D1-D2-D3 diagnostic exited 0 with the partial result. No equal-LOD target attempt, downstream geometry gate or `scripts/validate.ps1` ran. Evidence is published in [draft PR #216](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/216), stacked on PR #215. See [R4 results](../reports/P3-1-R12-CXR-R4/RESULTS.md) and [raw exact-source evidence](../reports/P3-1-R12-CXR-R4/evidence/final-f48990e/).

No production, schema, save, Issue #108/#154, merge or release work occurred. PR #215 remains open/draft/unmerged. Preserve prior attempts 06–11 without rerunning them. All five F2-G1 holds remain unchanged.
