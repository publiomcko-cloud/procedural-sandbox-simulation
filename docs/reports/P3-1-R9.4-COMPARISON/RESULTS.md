# P3.1 R9.4 — Consolidated Experimental Closeout

Date: 2026-10-28
Repository: publiomcko-cloud/procedural-sandbox-simulation
Authorization: Issue #186. A/C/D only; candidate B excluded. Up to ten implemented attempts per candidate authorized; seven corrections were implemented in total. This is experimental evidence, not production or architecture approval.

## Disposition

All three candidates remain partial. **No candidate met every frozen R9.4 geometry and CPU-ray target. No architecture is selected.** Candidate evidence is in draft PRs [A #187](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/187), [C #188](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/188), and [D #189](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/189). This comparison is a docs-only draft based on the R9.3 comparison branch.

| Candidate | Corrections | Tested source SHA (direct parent) | Current PR HEAD | Status |
|---|---:|---|---|---|
| A — root-aware marching tetrahedra | 3 | f0c93415dd56886a1c05ff2e6a1340e420f22c59 (d5903242e41642a2633e18dc181c4389188c65b2) | b109b4e3b38393b84bf66febe248ac01df9f6b72 | A_PARTIAL_CORRECTION |
| C — Surface Nets | 2 | af4d6027d9d57c9f2b8023aa27b31d2dd2dcedf2 (5def207d7b1cff8d7f70476f1221c7b9c5771e27) | 2cbe572a1fd1e5ebf871e9b43b515ef2522f38c5 | C_PARTIAL_CORRECTION |
| D — materialized volume / independent extraction | 2 | 6ea04229b5ff06090f346c8749c1f5a53994227c (51744eebf17646ca52612936146adeb0f9db001b) | 464087947da00a45090a289ade4917882ce0ada5 | D_PARTIAL_CORRECTION |

The final commit in each candidate PR adds report/evidence material after the tested source commit. Physical SHA-256 and Git blob identities for both changed GDScript files appear in each candidate report. Candidate changes remain in test-only prototype paths; production code, storage/schema, canonical SDF and frozen manifest are unchanged.

## Attempt outcomes

- **A (3):** alternate diagonal for complete 2/2 tetra quads passed its synthetic regression but did not correct frozen X+; 20 root bisections improved neighbor geometry but breached the frozen sample stop-loss on negative regions; 12 bisections stayed within the cap and yielded zero neighbor/negative opens, while X+ stayed at 8 opens.
- **C (2):** connected per-cell contour components reduced neighbor nonmanifold edges 3→0 and FILL/CARVE 2→1, but openings persisted; bilinear saddle decider regression passed but frozen counts did not change. Smoothing was not run because topology gates failed.
- **D (2):** shared lattice-root caching slightly worsened topology; angle-ordered polygon assembly with gradient winding and canonical root identity fixed most tested cases and exactly matched the independent R9.3 X+ mesh on identical reloaded float32 volume. The comparator itself still has 13 X+ openings; the fixed cutoff still drops eight triangles. One compile error was corrected before retry and is operational provenance, not another geometry correction.

All attempt logs are retained in candidate packages. **Intermediate source snapshots were not preserved.** Intermediate records contain source_sha/R9_SOURCE_SHA fields pointing at the R9.3 base rather than the mutable attempt source. These are labeled UNPINNED_WORKTREE and are not treated as exact source identity. Final focused, E2E, contract and full validation runs are pinned to the exact source commits above.

## Geometry comparison

Counts are from the frozen exact-edge topology oracle. Squared-cross triangle cutoff remains 1e-12.

| Candidate / case | R9.3 baseline opens / nonmanifold | R9.4 final opens / nonmanifold | Outcome |
|---|---:|---:|---|
| A zero / CARVE / FILL-CARVE | 0/0 each | 0/0 each | preserved |
| A neighbor pair | 4/0 | 0/0 | corrected |
| A X+ equal and mixed LOD | 12/0 | 8/0 | partial; 7 cutoff drops |
| A negative region | 0/0 | 0/0 | preserved within sample cap |
| C zero / CARVE | 17/0; 22/0 | 17/0; 22/0 | unresolved |
| C FILL-CARVE | 26/2 | 26/1 | nonmanifold reduced; opens persist |
| C neighbor pair | 3/3 | 3/0 | nonmanifold corrected; openings persist |
| C X+ equal/mixed | 26/0 | 26/0 | unresolved |
| C negative region | no baseline acceptance row | 42/0 | observed failure |
| D original extractor: zero / CARVE / F-C | 214/67; 219/71; 272/86 | alternate final 0/0 each | large test-only improvement |
| D original extractor: neighbor | 567/183 | alternate final 0/0 | large test-only improvement |
| D X+ equal/mixed | original 446/136; independent R9.3 comparator 13/0 | alternate final 13/0 | hashes equal comparator; no-open target still fails |
| D negative / triangle 3103 | 0/0 each | 0/0 each | preserved |

CPU ray proxy remains 9/25 disagreements for A/C/D. Maximum absolute mesh-versus-finite-reference position error: A 1.795526867, C 2.089089162, D 2.096206769 world units. The finite scan is not a certified first-root or PhysicsServer oracle. FILL/CARVE normal p95: A 58.0671 degrees, C 74.7785 degrees, D 84.8438 degrees. A does not improve the R9.3 report near 57.96 degrees.

## Headless performance

Five same-process build samples; nearest-rank p50/p95 milliseconds. These are headless CPU measurements, not frame time, GPU completion, PhysicsServer, rendered FPS or product acceptance.

| Scenario | A p50 / p95 ms | C p50 / p95 ms | D p50 / p95 ms |
|---|---:|---:|---:|
| Zero | 45.04 / 49.05 | 21.45 / 27.62 | 46.04 / 47.56 |
| CARVE | 49.50 / 51.40 | 22.15 / 22.32 | 47.99 / 49.75 |
| FILL/CARVE | 58.53 / 63.47 | 25.92 / 28.20 | 56.73 / 58.32 |
| Neighbor pair | 131.43 / 163.06 | 38.06 / 39.21 | 130.88 / 141.48 |
| X+ equal LOD | 105.00 / 109.07 | 35.53 / 37.73 | 106.99 / 110.10 |
| X+ mixed LOD | 100.38 / 102.88 | 36.57 / 37.92 | 97.33 / 99.08 |
| Negative pair | 158.47 / 170.22 | 42.54 / 44.15 | 152.28 / 176.04 |

C builds faster in these headless cases but remains topologically invalid. A and D total build times are similar. D materialization and extraction are separately reported in its E2E JSONL; they do not represent the production storage pipeline. No campaign data measures per-scenario RSS, GUI stalls, GPU timings or presented-frame distributions.

## E2E and validation

| Candidate | E2E process | JSONL events | Manifest variants | Execution disposition | Contract | Full validation |
|---|---|---:|---:|---|---|---|
| A | PID 46308, exit 0, 12.994 s | 44 | 21 | 20 COMPLETE; one D-only NOT_RUN; some rows PARTIAL | 160 assertions, 0 failures | 21 groups, 21,464 assertions, 0 failures; 516,256 ms |
| C | PID 53128, exit 0 | 44 | 21 | 20 COMPLETE; one D-only NOT_RUN; some rows PARTIAL | 160 assertions, 0 failures | 21 groups, 21,464 assertions, 0 failures; 517,003 ms |
| D | PID 55680, exit 0, 13.182 s | 44 | 21 | all 21 COMPLETE; row limitations retained | 160 assertions, 0 failures | 21 groups, 21,464 assertions, 0 failures; 517,271 ms |

All full validations were sequential Godot 4.7.2 runs on exact tested source commits using isolated user profiles. Each emitted three nonfatal existing camera-colinearity warnings. E2E process/campaign COMPLETE is not geometry acceptance or evidence completeness. Focused probe exit 0 means probe execution completed, not that every frozen quality target passed. The 44 JSONL records per candidate include campaign and scenario events. Raw stdout/stderr and extracted JSONL are retained.

## Integrity and limits

- Frozen input manifest SHA-256: 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972.
- Godot executable SHA-256: c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643.
- Candidate evidence packages contain final focused, E2E, contract and full-validation logs, JSONL, scenario CSV and attempt logs. Per-package SHA256SUMS inventories contain 40, 32 and 37 files (A/C/D).
- Comparison artifacts include frozen preregistration, baseline summaries/source hashes, each final package checksum inventory, and a SHA-256 inventory for the preserved external evidence root C:\r94-evidence (244 files, about 21.4 MB). The large 8.7 MB baseline A stderr remains in that external root and was not duplicated to the candidate PRs.
- Confidence is reduced for intermediate attempt-to-source mapping because exact working-tree snapshots were not retained. Final exact-SHA test evidence remains independently identifiable.
- No production integration, storage/schema change, architecture decision or owner GUI/GPU/physics acceptance. No protected F2-G1 operation. Holds remain: CURRENT_PROTECTED_STATE_UNKNOWN, V3_NOT_ATTESTED, ACL_REVIEW_REQUIRED, G1_BLOCKED_ENVIRONMENT, F2_G1_RELEASE_HOLD.

## Recommendation

Do not select or integrate an architecture from this campaign. Next, pin every intermediate source before running and isolate the remaining X+ contour/open-edge and CPU-ray defects. For D, investigate the eight fixed-cutoff omissions and 13 openings shared with the independent comparator. For C, keep smoothing gated until required topology passes.
