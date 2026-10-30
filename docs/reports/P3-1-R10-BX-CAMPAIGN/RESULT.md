# P3.1 R10-BX — Exact-Root Feasibility Result

**Disposition:** `P3_1_R10_BX_EXACT_ROOT_FEASIBILITY_INCONCLUSIVE_WITH_EVIDENCE`

This is a test-only experimental result. No production implementation, storage schema, geometry contract, Issue #108 work, merge, or release is authorized by it.

## Identity and provenance

| Item | Verified identity |
|---|---|
| Repository origin | `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git` |
| R10-BX measured source commit | `42012b476adb1369a5b281dfe8dac2a38b700751` |
| Direct parent / R10-B base | `4e032085da53c43e78fe6b7ca3af1f569ede03d8` |
| Measured source tree | `6aba347d38c3d54b0c07ff2da8635f3f10cf5d60` |
| Branch | `exp/p3-1-r10-bx-conflict-indexed-feasibility` |
| Base R10-B PR | [#208](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/208), verified open/draft/unmerged before publication |
| Production reference | `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` |
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| Godot console executable SHA-256 | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |
| B1R candidate domain SHA-256 | `30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22` |
| Candidate-domain identity SHA-256 | `b3c5de9786a078a6568650ef62e2150524f1b387e9e979cba5a060723d990feb` |
| Preregistration SHA-256 | `9ec0de228487722cb74f5ea78b33ebda5d5a0d78782edea1bad55cb4dbd4c460` |

The measured source is the parent of this report-only publication commit. The publication commit changes no measured code or frozen inputs; its exact identity is the final PR head.

## Frozen domain and hypothesis

The experiment asked whether the unchanged B1R candidate domain admits a complete exact-root triangulation when incompatibilities are precomputed and searched with bitsets and propagation. It did **not** test alternate geometry, movable mandatory roots, Steiner vertices, a changed cutoff, or a different topology contract.

The verified frozen domain contains 73 roots (34 boundary and 39 interior), 7,608 ordered candidate triangles, 110 target faces, and 2,239 distinct undirected candidate edges. The latter was independently recomputed by canonicalizing each edge in each candidate triangle. The previously used value 2,628 is only the maximum pair count among 73 roots (`73*72/2`); it is not the observed edge count. The preregistration was corrected before the final measured run and its frozen hash remained unchanged thereafter.

Other pinned inputs: source B1R commit `6f28273d0113f93678034b9e482140e73e765721`; B1R realizer `31fc01c78e273aede396a7596c3827f4520f45259d2c7e0f2ef9663d73ebcb5e`; Candidate D `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`; manifest `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`; payload `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`; volume `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`; topology `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`; frozen ray fixture `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7`. The exact-root component is `60,8,25|tet:0`, ROI minimum `[15,1,6]`, extent `[8,8,8]`, grid step `0.25`, revision `2`, with strict unchanged `cross_squared > 1e-12` admission.

The theoretical unordered candidate-pair count is 28,937,028. Limits remained frozen: 10,000,000 exact classifications, 180,000 ms graph-build wall time, then (only if a complete graph exists) 500,000 search nodes, recursion depth 110, 120,000 ms search wall time, and 512 MiB estimated state. The graph estimate formula is 175,676,632 bytes for this candidate count; this is a preallocation estimate, not measured resident memory.

## Stage results on measured source `42012b4`

| Stage | Result | Evidence |
|---|---|---|
| Fresh isolated editor import | PASS, exit 0, 8,358 ms | `cold_import_import/process.json`, stdout/stderr |
| Campaign parse/check-only | PASS, exit 0, 1,256 ms | `campaign_parse_check-campaign/process.json`; source and preregistration pins printed |
| Conflict solver parse/check-only | PASS, exit 0, 1,267 ms | `solver_parse_check-solver/process.json` |
| BX unit regressions | PASS, 20/20, exit 0 | `unit_regression_unit/stdout.txt`: `R10BX_UNIT_TESTS_PASS` |
| Authority reference check | PASS, exit 0 | `ref_authority_reference-check-authority/process.json` |
| B1R reference check | PASS, exit 0 | `ref_b1r_reference-check-b1r/process.json` |
| Frozen graph-contract reference check | PASS, exit 0 | `ref_graph_reference-graph-contract/process.json`; reference fixture itself reports 10 internal open edges, so this is input/contract verification, not a final repaired-mesh pass |
| Frozen ray-causality reference check | PASS, exit 0 | `ref_ray_reference-ray-causality/process.json`; existing ROI diagnostic records 0 ROI-scoped mismatches and its separate global-scope classification |
| Complete conflict graph build | **BLOCKED at fixed wall-time bound** | `centroid_axis_graph_graph/bx_graph_preflight.json`, process exit 3 |
| Search and all post-SAT geometry gates | NOT RUN | Sequential preregistered gate was not passed; no search reservation/start record exists |

All stage outputs, process records and stderr were retained. The latest graph attempt produced no Godot script error, no resource-triggered abort, and no warning-threshold sample.

## Final graph attempt

The final measured attempt added a conservative centroid-vector projection rejection after closed-AABB filtering. It rejects a pair only when the enclosed projection intervals are strictly separated; touching pairs remain. This filter does not alter the exact geometric conflict predicates or candidate domain.

| Counter | Observed at stop |
|---|---:|
| Candidate triangles | 7,608 |
| Theoretical candidate pairs | 28,937,028 |
| Candidate X-sweep pair visits | 12,804,096 |
| Candidate closed-AABB pair tests | 9,926,090 |
| Centroid-axis filter pair tests | 9,926,090 |
| Pairs rejected by the conservative centroid-axis filter | 1,399,420 |
| Candidate exact pair classifications | 8,526,670 |
| Unique-edge X-sweep visits | 1,865,338 |
| Unique-edge exact pair classifications | 1,362,231 |
| Combined exact classifications | 9,888,901 of 10,000,000 |
| Graph-build elapsed time | 180,012 ms; graph failed closed |
| Whole process elapsed time | 183,440.553 ms; exit 3 |
| Conflict graph / graph SHA | Not completed / none |
| Distinct conflict-pair count | Unknown; incomplete graph did not emit it |
| Search nodes / forced propagations | 0 / 0; search never started |
| Resource aborts / warnings | 0 / 0 |
| Minimum global free commit observed | 13,523,562,496 bytes |

Live process observation during this attempt showed launcher PID 4200 starting console wrapper PID 19708, with Godot PID 40092 running as the wrapper's child. The process record identifies PID 19708 as the console wrapper. The evidence runner's per-process memory sampler followed that wrapper PID and recorded approximately 1.27 MB private bytes near the end; it did not reliably account for Godot child PID 40092. Therefore no Godot-process RSS/peak-memory claim is made. The global free-commit observation is system-wide and is reported separately. No memory safety threshold was approached. The host hardware model was not inventoried, so these timings are not a cross-machine performance comparison.

The graph failure artifact SHA-256 is `a48f870d4da2ab8b360411596d8bdab3f4a4be37fa75c5f4020a654a9cf5c40e`. Process stdout SHA-256 is `2bfdeb4e45c3ec4b7c16341b1646eec04bea41b2240a8a59d5ec1181946effcb`; stderr SHA-256 is the empty-stream digest `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`. `process.json` records wrapper PID 19708, parent launcher PID 4200, exit 3, `resource_abort=false`, `timeout_abort=false`, and `search_started=false`. These are distinct process roles; no false parent/child attribution is asserted.

## Preserved attempts and failure classification

Each root is immutable, separate and retained under `%LOCALAPPDATA%\Temp`:

| Source | Evidence root suffix | Outcome | Graph-result SHA-256 |
|---|---|---|---|
| `ac80d5fce0b66db2c8b5ffc4170259d637d59763` | `17c202d0f5cd4bfea5fb7c780bdd1376` | Broad phase hit 180 s after 3,817,472 exact pair tests; no search | `9d284a3f414211f611ec20c8c1dd89ee6dd4eda4182be24933e013e9c0e7d735` |
| `e1e4b6fa9357adfe3ba0479061ff0bbda03c4cad` | `7b141e4141c9429ca87f2822551148e5` | Broad phase hit 180 s after 4,743,168 exact pair tests; no search | `0ddedc3b3c3c378fdbca5ddf5531c8af1184b2e6e01fc856561179f75575acdb` |
| `2d45807b79fb2ae4289f53759ba4ffd7f031d6b5` | `5b4bebedf5ba497e94fe201fd64cf0d7` | GDScript parser failed in campaign/solver check before graph; duplicate local declaration | No graph artifact |
| `67baf9b1f51d86b1efde080d3fdd6bd2b534745f` | `6a406935fc0b4c769f2336ebcf1bdb6c` | Rejected observed unique-edge count mismatch before graph classification; correction followed | `2fefaa2fdd9b52827776b9f1fe102ce7e54c0ca9f1d02835718e7b348ba7e4cd` |
| `091573115ac55837597b2b9c4d7d75d8df62dfe6` | `0c9a7c74861c49f7a2bdc40d7ab72d71` | Fixed 10,000,000 combined exact-pair budget reached at 124,679 ms; no search | `133d372d0d135e789f0b52696df773b897b3b26b583515d67849a070bd23af30` |
| `63d832df187164c3651c52d05574e0b64cfe9eab` | `32018fbea34d447f8177e13548d125ea` | Conservative full triangle SAT broad phase hit 180 s; no search | `2dd2275a6aa1d864b9fb68a174e5d4beb95a6bfde2762b2f8ed0fd762464c327` |
| `42012b476adb1369a5b281dfe8dac2a38b700751` | `8b928f53bfa649fabdd6422e6b09190a` | Conservative centroid-axis filter still hit 180 s; no search | `a48f870d4da2ab8b360411596d8bdab3f4a4be37fa75c5f4020a654a9cf5c40e` |

The early parse/count failures were corrected in later isolated source attempts and were not treated as feasibility evidence. The final graph-stage time bound, after the parse, domain, unit, and reference checks passed, is the scientific blocker. None of the attempts proves SAT or UNSAT.

## Required result fields

| Field | Result |
|---|---|
| `CAMPAIGN_STATUS` | `BLOCKED_GRAPH_PREFLIGHT_WALL_TIME` |
| `BX_SOURCE_SHA` | `42012b476adb1369a5b281dfe8dac2a38b700751` |
| `BX_PARENT_SHA` | `4e032085da53c43e78fe6b7ca3af1f569ede03d8` |
| `BX_TREE_SHA` | `6aba347d38c3d54b0c07ff2da8635f3f10cf5d60` |
| `BX_HYPOTHESIS` | `R10BX_CONFLICT_INDEXED_EXACT_ROOT_FEASIBILITY`; unresolved because the complete graph/search was not produced |
| `BX_FROZEN_B1R_DOMAIN_SHA` | `30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22` |
| `BX_CONFLICT_GRAPH_SHA` | `NONE_GRAPH_BUILD_INCOMPLETE` |
| `BX_CANDIDATE_COUNT` | 7,608 |
| `BX_THEORETICAL_PAIR_COUNT` | 28,937,028 |
| `BX_BROADPHASE_PAIR_COUNT` | 12,804,096 X-sweep visits; 9,926,090 closed-AABB tests |
| `BX_EXACT_PAIR_TESTS` | 9,888,901 at the wall-time stop |
| `BX_CONFLICT_PAIR_COUNT` | `UNKNOWN_INCOMPLETE_GRAPH` |
| `BX_CONFLICT_GRAPH_BUILD_TIME` | 180,012 ms bound hit |
| `BX_CONFLICT_GRAPH_MEMORY` | Static graph preallocation estimate 175,676,632 bytes; actual completed graph memory unavailable; process RSS not reliably captured |
| `BX_SEARCH_BACKEND` | Configured deterministic GDScript conflict-bitset propagation/backtracking; execution `NOT_STARTED` |
| `BX_SEARCH_LIMITS` | 500,000 nodes; depth 110; 120,000 ms; 536,870,912 estimated state bytes; one solution; none consumed |
| `BX_SEARCH_NODES` | 0 |
| `BX_FORCED_PROPAGATIONS` | 0 |
| `BX_SEARCH_COMPLETE` | `false_NOT_STARTED` |
| `BX_FEASIBILITY_CONCLUSION` | `EXACT_ROOT_REALIZATION_INCONCLUSIVE`; incomplete graph is not SAT/UNSAT evidence |
| `BX_SELECTED_TRIANGLES` | `NOT_AVAILABLE` |
| `BX_EQUAL_LOD` / `BX_REQUIRED_ADJACENCY` / `BX_INTERNAL_OPEN_EDGES` / `BX_NONMANIFOLD` / `BX_WINDING` | `NOT_RUN_NO_SELECTED_GEOMETRY` |
| `BX_MIN_CROSS_SQUARED` | Frozen input admission cutoff `1e-12`; selected-mesh cutoff qualification `NOT_RUN` |
| `BX_CONTROLS` | `NOT_RUN_NO_SELECTED_GEOMETRY` |
| `BX_RAY_ROI` | `NOT_RUN_NO_SELECTED_GEOMETRY`; separate frozen ray reference diagnostic passed |
| `BX_RAY_GLOBAL_DIAGNOSTIC` | `NOT_RUN_NO_SELECTED_GEOMETRY` |
| `BX_VOLUME` | Input volume identity verified; selected-mesh volume qualification `NOT_RUN` |
| `BX_MIXED_LOD` | `NOT_GENERALIZED` and not run |
| `BX_DETERMINISM` | Graph deterministic repeat/serialization/reload/tamper `NOT_RUN` because no graph completed |
| `BX_RESOURCE_ABORTS` | 0; no resource stop-loss was triggered |
| `FINAL_EXACT_ROOT_FEASIBILITY` | `INCONCLUSIVE` |
| `FINAL_EQUAL_LOD` / `FINAL_REQUIRED_ADJACENCY` / `FINAL_INTERNAL_OPEN_EDGES` / `FINAL_NONMANIFOLD` / `FINAL_WINDING` | `NOT_RUN` |
| `FINAL_CONTROLS` / `FINAL_RAY` / `FINAL_VOLUME` / `FINAL_MIXED_LOD` / `FINAL_DETERMINISM` | `NOT_RUN` (mixed LOD remains `NOT_GENERALIZED`) |
| `FULL_E2E_RESULT` | `NOT_RUN` |
| `FULL_VALIDATION_RESULT` | `NOT_RUN_BY_SEQUENTIAL_GATE` |
| `EVIDENCE_INTEGRITY` | Final raw-evidence inventory created with `CreateNew`; 71 files hashed before the inventory file; inventory SHA-256 `43859f47965ffdd6854e6b9a93523ea9d8af2483b250b7c6fcafba1e2c29d473` |
| `FINAL_ARCHITECTURAL_RECOMMENDATION` | Close the exact-root mandatory-vertex realization line as inconclusive and proceed to a separately authorized R10-C topology-to-geometry realization design; do not claim infeasibility |

## Evidence and source hashes

Final raw evidence root: `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r10bx_20261030_8b928f53bfa649fabdd6422e6b09190a`.

The `evidence-sha256.json` manifest covers 71 files present in that root before the manifest was created, including input copy, stage process records, full stdout/stderr, profiler/resource samples, and reference artifacts. The manifest is create-new and does not hash itself. Earlier attempts remain in their own roots listed above. No raw run was overwritten or removed.

| Measured tracked path | Git blob | Physical SHA-256 |
|---|---|---|
| `docs/reports/P3-1-R10-BX-CAMPAIGN/BX-PREREGISTRATION.md` | `b4700ecaef6e429d2baba96edb47ca9b04bba5d0` | `9ec0de228487722cb74f5ea78b33ebda5d5a0d78782edea1bad55cb4dbd4c460` |
| `game/tests/prototypes/p3_1_r10_bx_campaign.gd` | `dd8c9d217e5a8c2ab843a999cb2559dad5184b8f` | `c836b029e8549a2c03176dd4852109858ffcc2b9ed767d7fc752872454902657` |
| `game/tests/prototypes/p3_1_r10_bx_conflict_solver.gd` | `17055aecfffd54a1d4809e2afdbb84f86e1162bf` | `d9d0c46e5e38fae3c0cc63ddb90921cbd5c0526c21a8ce0821debf62b3dfdf6c` |
| `game/tests/prototypes/p3_1_r10_bx_tests.gd` | `19566fcd59cc2977dbe489932956d776aa794142` | `05bad0cf4b1cb51384747f2596b3d93d7b92df14cf449ffc905b8b05422e09d2` |
| `scripts/experiments/run_r10bx_stage.ps1` | `714c65fb1e2a1bc31740d99168e3e8c89d6b5e3e` | `2cacb5838c949cd7ddfc577f2d188b6f3dd9f47e91daecafebe20a37a1aac527` |

## Scope, limitations, and next decision

`scripts/validate.ps1`, R10-BX graph serialization/reload/tamper, two deterministic graph builds, search, selected-geometry qualification, mixed LOD, and full E2E were not run because the graph-preflight gate failed. This is deliberate sequential fail-closed behavior, not a claim that those checks passed.

The current experiment does not establish that the frozen domain is feasible or infeasible. It establishes that the tested GDScript graph construction did not complete within the frozen 180-second budget, even after multiple bounded broad-phase changes. Per the R10-BX decision rule, close this exact-root realization family without creating BX2. The next useful question is R10-C: retain topology roots/arcs as authority, add an explicit topology-to-geometry mapping, and permit geometry-only support vertices when independently justified. That is a future design/authorization gate, not implemented here.

Existing workspace worktrees, both stashes, user saves, and F2-G1 holds were left unchanged. Godot-generated `.gd.uid` files in this disposable worktree were preserved and not included in commits. PR #208 and PR #207 were not modified or merged. No production code or schemas changed.

## Publication

Draft evidence PR: [#209](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/209), stacked on [R10-B PR #208](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/208). At publication verification, #209 was open, draft, unmerged, based on `exp/p3-1-r10-b-constrained-realization` at `4e032085da53c43e78fe6b7ca3af1f569ede03d8`; its remote branch matched the locally published source/report commits. The measured code identity remains `42012b476adb1369a5b281dfe8dac2a38b700751`; publication adds report-only commits after that source. PRs #207 and #208 remain open, draft, and unmerged.
