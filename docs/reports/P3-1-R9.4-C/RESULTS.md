# P3.1 R9.4-C — Surface Nets Topology Investigation

Date: 2026-10-28  
Scope: isolated test-only experiment on R9.3-C. No production integration or geometry-contract adoption.

## Disposition

**C_PARTIAL_CORRECTION.** Component splitting plus a face ambiguity decider reduced neighbor nonmanifold edges from 3 to 0 and FILL/CARVE nonmanifold edges from 2 to 1. The mandatory opening counts did not improve: zero 17, CARVE 22, FILL/CARVE 26, X+ 26, and negative-region pair 42. No smoothing variants were run because the topology gate did not pass. The CPU ray proxy remains 9/25 with maximum position error 2.089089162 world units. C did not meet the frozen topology targets.

## Identity and scope

- Tested source commit: af4d6027d9d57c9f2b8023aa27b31d2dd2dcedf2
- Direct parent / R9.3-C base: 5def207d7b1cff8d7f70476f1221c7b9c5771e27
- Only source paths changed: game/tests/prototypes/p3_1_r9_2_candidate_impl.gd, game/tests/prototypes/p3_1_r9_3_targeted_probe.gd.
- Production SDF, ledger, save schemas and manifest were unchanged.
- Frozen manifest SHA-256: 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972.
- Godot: 4.7.2.stable.official.ed1daf0bf; executable SHA-256: c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643.

## Corrections and results

1. **Per-cell connected contour components.** Replace one averaged dual vertex per sign-active cell with one vertex per connected local contour component. Route primal-edge quads through component-local edge ownership. On the frozen neighbor case, nonmanifold count improved 3→0 but 3 internal opens remained. On FILL/CARVE, nonmanifold count improved 2→1 while 26 openings remained.
2. **Bilinear face asymptotic decider.** Replace face-center sign selection for checkerboard faces with the bilinear saddle value (a*c-b*d)/(a-b-d+c). The synthetic asymmetric checkerboard regression passes: center and saddle signs differ, and both sides map to the expected shared-face pairing. Frozen topology counts did not change from the prior component-splitting attempt.

The attempt ledger preserves the causal prediction and outcome. The intermediate working-tree source snapshots were not retained. Their log source_sha fields name the R9.3 base and are not valid identities; they are marked UNPINNED_WORKTREE. Final exact-source evidence is separately pinned to af4d602….

## Final focused topology

| Frozen case | R9.3 baseline opens / nonmanifold | Final opens / nonmanifold | Final triangles |
|---|---:|---:|---:|
| Zero | 17 / 0 | 17 / 0 | 154 |
| CARVE | 22 / 0 | 22 / 0 | 156 |
| FILL/CARVE | 26 / 2 | 26 / 1 | 190 |
| Neighbor pair | 3 / 3 | 3 / 0 | 328 |
| X+ equal LOD | 26 / 0 | 26 / 0 | 234 |
| X+ mixed LOD | 26 / 0 | 26 / 0 | 234 |
| Negative-region pair | not a baseline target row | 42 / 0 | 420 |
| Historical triangle 3103 | 0 / 0 | 6 / 0 | 8 |

Open-edge counts use the frozen exact-edge topology oracle and classification. The candidate’s own summary distinguishes ROI boundary opens, but these internal counts remain nonzero and are not waived as halo effects.

## E2E and performance observations

The final E2E used source af4d602…, Godot PID 53128, exit 0, 21 manifest variants and run ID C-e2e-final. It emitted 44 JSONL records; 20 variants executed and one D-only corruption scenario was marked NOT_RUN. Some rows are PARTIAL. The campaign is not complete evidence for every declared result.

Headless CPU build p50/p95 milliseconds from five same-process samples:

| Case | p50 / p95 ms | Final opens / nonmanifold |
|---|---:|---:|
| Zero | 21.45 / 27.62 | 17 / 0 |
| CARVE | 22.15 / 22.32 | 22 / 0 |
| FILL/CARVE | 25.92 / 28.20 | 26 / 1 |
| Neighbor pair | 38.06 / 39.21 | 3 / 0 |
| X+ equal LOD | 35.53 / 37.73 | 26 / 0 |
| Negative-region pair | 42.54 / 44.15 | 42 / 0 |

The 25-ray CPU proxy reports 9 disagreements and maximum absolute position error 2.089089162 world units. Normal deviation p95 is 74.7785 degrees for FILL/CARVE. Ray scan is finite; these are not PhysicsServer, rendered-FPS or production picker claims. Smoothing variants 1–3 were deliberately not run because the mandatory topology gate failed.

## Validation

- Focused final probe: 9 scenarios, exit 0; exit indicates harness completion, not geometry target acceptance.
- R9.2 contract suite: 160 assertions, 0 failures, exit 0.
- Full scripts/validate.ps1: 21 groups, 21,464 assertions, 0 failures; exit 0, 517,003 ms. Three existing nonfatal camera-colinearity warnings were captured.
- Full logs/process records and extracted JSONL events are in evidence/; SHA256SUMS.txt covers the package.
- The raw baseline includes a large stderr file stored only in the external evidence root C:\r94-evidence, not duplicated here.

## Limits

C remains test-only and fails its mandatory topology targets. Faster headless construction does not offset invalid geometry. No smoothing, production behavior, GUI, GPU, PhysicsServer or product acceptance is claimed. No architecture is selected.
