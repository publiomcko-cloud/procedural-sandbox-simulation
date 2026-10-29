# P3.1 R9.4-A — Root-aware Marching Tetrahedra

Date: 2026-10-28  
Scope: isolated test-only experiment on R9.3-A. No production integration or geometry-contract adoption.

## Disposition

**A_PARTIAL_CORRECTION.** The neighboring and negative-region focused meshes now have zero reported internal openings, and the negative-region run stays within the frozen sample ceiling. The X+ equal/mixed seam still has 8 internal opens and 7 cutoff-dropped triangles. The CPU ray proxy remains at 9/25 hit/miss disagreements with maximum position error 1.795526867 world units. The ordered FILL/CARVE normal p95 is 58.0671 degrees, not improved over the R9.3 report near 57.96 degrees. A did not meet the frozen geometry targets.

## Identity and scope

- Tested source commit: f0c93415dd56886a1c05ff2e6a1340e420f22c59
- Direct parent: d5903242e41642a2633e18dc181c4389188c65b2
- R9.3-A base: ce6d14d5c3d465ac5477e54354f2d1219171f6f0
- Only source paths changed against that base: game/tests/prototypes/p3_1_r9_2_candidate_impl.gd and game/tests/prototypes/p3_1_r9_3_targeted_probe.gd.
- Production files, save schemas, SDF, ledger and frozen manifest were not changed.
- Frozen manifest SHA-256: 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972.
- Godot: 4.7.2.stable.official.ed1daf0bf; executable SHA-256: c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643.

## Corrections and results

1. **2/2 tetrahedron quad triangulation.** Preserve the historical diagonal when both triangles pass the unchanged squared-cross cutoff 1e-12; otherwise select the alternate diagonal only if its two triangles both pass. The implementation rolls back partial emission. A synthetic regression selects the alternate diagonal, but frozen X+ topology did not change.
2. **Root refinement.** Increasing root bisections from 8 to 20 improved the neighboring seam but crossed the 10,000 unique-sample stop-loss on the frozen negative-region pair. That attempt is censored for the affected scenario and was not accepted.
3. **Bounded root refinement.** Reducing to 12 iterations kept the negative-region test within the frozen cap and retained zero internal openings there. Neighbor remains zero; X+ remains at 8 opens / 7 cutoff drops.

The attempt-by-attempt ledger is in ATTEMPT-LEDGER.md. Intermediate working-tree snapshots were not retained. Their raw records contain source_sha values inherited from R9.3 and those values are not valid identity evidence; the intermediate source IDs are explicitly UNPINNED_WORKTREE. The final source commit and its final tests are pinned independently.

## Final focused topology

Counts are exact-edge topology-oracle outputs. “Open” means an internal opening under the frozen ROI classification; ROI-boundary edges are reported separately in the focused CSV.

| Frozen case | R9.3 baseline opens | Final opens | Final nonmanifold | Final triangles | Cutoff drops |
|---|---:|---:|---:|---:|---:|
| Zero | 0 | 0 | 0 | 318 | 0 |
| CARVE | 0 | 0 | 0 | 324 | 0 |
| FILL/CARVE | 0 | 0 | 0 | 404 | 0 |
| Neighbor pair | 4 | 0 | 0 | 870 | 0 |
| X+ equal LOD | 12 | 8 | 0 | 655 | 7 |
| X+ mixed LOD | 12 | 8 | 0 | 655 | 7 |
| Negative-region pair | 0 | 0 | 0 | 1,148 | 0 |
| Historical triangle 3103 | 0 | 0 | 0 | 8 | 0 |

No frozen triangle cutoff was lowered. The alternate-diagonal unit regression passes; it does not prove the X+ defect corrected.

## E2E and performance observations

The final E2E invocation used source f0c934…, Godot PID 46308, exit 0, 12.994 s, run ID A-e2e-final. It emitted 44 JSONL records for 21 manifest variants: 20 execution rows and one D-only corruption scenario explicitly NOT_RUN. Campaign terminal status was COMPLETE, but several result rows are PARTIAL; this is not complete scenario evidence.

Five same-process samples were used for the frozen build measurements below; values are p50/p95 milliseconds, with nearest-rank p95. They are headless CPU build timings, not FPS, presented frames, GPU completion or production performance acceptance.

| Case | p50 / p95 ms |
|---|---:|
| Zero | 45.04 / 49.05 |
| CARVE | 49.50 / 51.40 |
| FILL/CARVE | 58.53 / 63.47 |
| Neighbor pair | 131.43 / 163.06 |
| X+ equal LOD | 105.00 / 109.07 |
| X+ mixed LOD | 100.38 / 102.88 |
| Negative-region pair | 158.47 / 170.22 |

The 25-ray CPU proxy reports 9 disagreements, maximum absolute position error 1.795526867 world units. The reference scan is finite and is not a certified root oracle. FILL/CARVE normal deviation p95 is 58.0671 degrees. These values do not meet frozen A targets.

## Validation

- Focused final probe: 9 scenarios, process exit 0; exact source SHA recorded in evidence/focused/process.json. X+ remains failing against the frozen target.
- R9.2 contract suite: 160 assertions, 0 failures, exit 0.
- scripts/validate.ps1: 21 groups, 21,464 assertions, 0 failures; process exit 0, 516,256 ms. Three existing nonfatal camera colinearity warnings were emitted to stderr. The terminal says GUI visual testing remains an owner task.
- Full raw stdout/stderr and process records are preserved under evidence/.
- SHA256SUMS.txt inventories the packaged evidence. The original raw evidence root is C:\r94-evidence; its oversized historical baseline stderr was not duplicated into this PR package.

## Limits

This is a test-only candidate. CPU ray queries are not PhysicsServer evidence or production picker validation. Headless validation is not GUI/render/GPU verification. Same-process repeated mesh hashes establish only the recorded determinism scope. The final experiment does not meet the R9.4 X+ topology, picker-position, or normal targets. No production architecture is approved.
