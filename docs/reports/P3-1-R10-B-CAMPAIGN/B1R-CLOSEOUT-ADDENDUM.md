# P3.1 R10-B1R — final direct constrained-triangulation result

**Campaign status:** `P3_1_R10_B_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`
**Existing evidence PR:** [#208](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/208), open, draft, unmerged
**R10-A evidence PR #207:** unchanged
**B1R measured source:** `6f28273d0113f93678034b9e482140e73e765721`
**B1R parent:** `9d0217758c84ebd6031fbb1c533943894d1dac10`
**B1R tree:** `7630f95a2c72c0692f52d1dda8b7cbfdcdfd4efc`
**Hypothesis:** `R10B1R_DIRECT_CONSTRAINED_TRIANGULATION_FEASIBILITY`

This append-only result supersedes the earlier statements that B1R remained
unconsumed. The original B1 harness-error record and all prior attempt reports
remain intact.

## Campaign disposition

| Hypothesis | Disposition |
|---|---|
| Original B1 | `BLOCKED_HARNESS_ERROR`; no valid geometry result, not counted as a geometry hypothesis |
| B2 | Valid geometry result, `FAILED_TARGET`; exact local cavity search |
| B3 | Valid geometry result, `FAILED_TARGET`; constrained-Delaunay/Lawson local flips |
| B4 | Valid geometry result, `FAILED_TARGET`; canonical-field Steiner subdivision |
| B5 | Valid geometry result, `FAILED_TARGET`; nested local field refinement |
| B6 | Valid geometry result, `FAILED_TARGET`; bounded cutoff-guided flip beam |
| B1R | Valid terminal geometry result, `PARTIAL`; direct search stopped at a frozen limit |

**Valid geometry hypotheses used:** 6 (B2, B3, B4, B5, B6, B1R).
**Original B1:** remains separately recorded as `BLOCKED_HARNESS_ERROR`.
**B7:** not created or authorized.

## B1R solver and feasibility

The frozen component was `60,8,25|tet:0`: 73 exact roots (34 boundary,
39 interior), 110 target faces, and the unchanged strict cutoff
`cross_squared > 1e-12`. The deterministic candidate-domain builder considered
all `C(73,3)=62,196` raw root triplets and retained 7,608 admissible oriented
triangles. The domain also contains 2,628 candidate-edge records and the fixed
34-edge boundary.

Pruning counts were: duplicate/arity 0, nonfinite 0, fixed cutoff 50,
orientation 993, domain/ownership 42,929, boundary crossing 10,616. The
candidate-domain artifact is 181,753 bytes, SHA-256
`30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22`.
Its identity digest is also pinned in the immutable receipt; the solver's
separately computed identity digest is
`b3c5de9786a078a6568650ef62e2150524f1b387e9e979cba5a060723d990feb`.

The exact-cover backtracking search used the frozen admissibility predicates,
edge incidence/orientation, connectedness, vertex-link, fixed-root, no-crossing
and no-overlap checks. MRV only ordered branches. It found no complete solution
before reaching the intersection-check cap:

- Search status: `INCOMPLETE_LIMIT`; `search_complete=false`,
  `search_exhaustive=false`.
- Stop reason: `intersection_check_limit`.
- Search nodes: 768.
- Intersection checks: 2,000,001 (limit: 2,000,000; the counter stops when the
  configured cap is crossed).
- Candidate triangles: 7,608; roots: 73; fixed boundary edges: 34; target
  triangles: 110.
- Selected triangles: 0; solutions: 0.
- Conflicts: edge incidence 0, triangle intersection 3,656, root link 0,
  disconnected 0.
- Solver elapsed: 9,044 ms in the search record; total reported solver section
  11,141,264 microseconds.

**Feasibility conclusion:** `EXACT_ROOT_REALIZATION_INCONCLUSIVE`. This bounded
search did not prove global exact-root infeasibility and did not produce a
candidate realization. Because the solver did not return a complete candidate,
no deterministic candidate repeat was possible.

## Gates and retained geometry

| Gate | B1R result |
|---|---|
| Equal LOD | Failed target; no direct realization was selected |
| Base mesh triangles | 655 |
| Internal open edges | 10 |
| Required adjacencies missing | 21 |
| Nonmanifold edges | 0 |
| Degenerate emitted triangles | 0 |
| Winding inconsistencies | 0 |
| Fixed-cutoff rejections | 7 |
| Minimum cross-squared | No B1R selected-triangle value. Retained A6 minimum was (1.67075673894024\times10^{-16}); another observed remaining face was (1.65725004791333\times10^{-13}), both below the unchanged cutoff |
| Controls | 6/6: ZERO, CARVE, ordered FILL/CARVE, neighbor, X_NEG and Z_NEG |
| ROI ray | 25 rays; 0/25 hit/miss disagreements |
| Global ray diagnostic | 9/25; separate from the passing ROI oracle, classified as the already established ROI/global scope mismatch |
| Volume | Frozen revision-2 SHA and payload identity preserved |
| Mixed LOD | Not run: equal-LOD prerequisite failed |
| Deterministic realization repeat | Not run: no complete candidate |
| Full E2E | `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE` |
| `scripts/validate.ps1` | `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE` |

Frozen volume identity: SHA-256
`ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`, payload
SHA-256 `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`,
revision 2. Volume integrity gate passed. The ROI ray-position errors were
p50 0.0015989676, p95/max 0.096952811 world units; these are observations, not
new geometry tolerances.

## Exact-source process stages

All nine final-source processes reported exit code 0, with no script errors,
resource aborts or timeouts. The geometry stage's exit 0 records a valid
`PARTIAL` terminal result; it is not a geometry PASS.

| Stage | Godot PID (launcher PID) | Elapsed | Result |
|---|---:|---:|---|
| Import | 18104 (30876) | 7,539 ms | PASS |
| Campaign check-only | 2820 (24752) | 1,603 ms | PASS |
| B1R solver check-only | 17044 (20432) | 1,241 ms | PASS |
| Ray check-only | 28236 (37584) | 1,224 ms | PASS |
| Authority check-only | 25756 (39712) | 1,219 ms | PASS |
| ROI/global ray causality | 38048 (25740) | 2,006 ms | PASS; ROI 0/25, full diagnostic 9/25 |
| Graph contract | 9440 (8820) | 2,003 ms | PASS |
| Domain audit | 21820 (22364) | 14,148 ms | PASS; JSON numeric round-trip and negative tamper checks pass |
| Geometry B1R | 20972 (28248) | 15,746 ms | `PARTIAL`; bounded intersection-check limit |

The minimum observed free commit during geometry was 19,082,887,168 bytes.
No resource or timeout abort occurred. The campaign did not infer presented
FPS, GPU completion, or performance acceptance.

## Source and evidence identity

Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256
`c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

| Source input | Physical SHA-256 |
|---|---|
| B1R campaign | `2fa58b0296abfc37182048d7db08a38fcf66ee3d0c7e4f94d3992b306f0fa15a` |
| B1R direct triangulator | `31fc01c78e273aede396a7596c3827f4520f45259d2c7e0f2ef9663d73ebcb5e` |
| R10-B base realizer | `3601d45652efc420429b5306b1c1102af1e2d008e9d5d73b3004c44bd1667eb9` |
| R10-A authority | `feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216` |
| Ray causality source | `b61dab953ee3048e1e1a666daf32ddb21d964b3ccd44c3616825b13360097af1` |
| Ray fixture | `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7` |
| Candidate D | `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a` |
| Frozen manifest | `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` |
| Runner | `bad5338a07541d490dbeb0e5bc5c923913da9cd33d8652ca9c28c89357d99cda` |

Evidence root:
`C:\Users\PUBLI\AppData\Local\Temp\p3_1_r10b1r_6f28273d0113f93678034b9e482140e73e765721_16cc932006f14a34a0b09dc0c4583238`.

- Domain pin receipt SHA-256:
  `9c641e53e353c4d3544e003dfd5c2d7ebf186258aa6524496f7ce4de722547ce`.
- Geometry attempt JSON SHA-256:
  `b67d6d18db596ee19310973d03ac691646f8a3a1189d52b89945718aa581f7ac`.
- Evidence index: `B1R_EVIDENCE_INDEX.json`, SHA-256
  `d14be31548ba20d2f4888b04287be519eb6f66a7bfc06263c66ba8649ecd6144`;
  97 indexed raw files and 9 process records.
- Evidence archive:
  `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r10b1r_6f28273d0113f93678034b9e482140e73e765721_16cc932006f14a34a0b09dc0c4583238.zip`,
  SHA-256 `388cc418eacf4a40f3fa9a0b027e4b5d2339c41ee25e93272af8a36d7e8a76ea`.

The byte-identical evidence index and archive are published in this PR at
[`B1R_EVIDENCE_INDEX_20261030.json`](evidence/B1R_EVIDENCE_INDEX_20261030.json)
and [`B1R_FINAL_20261030.zip`](evidence/B1R_FINAL_20261030.zip). Their
published-byte hashes were recomputed after copying and match the external
sources above.

Earlier parser, domain-audit, JSON-type, hypothesis-guard and receipt-capture
attempts remain in the separate roots named by the preserved `b1r_*root*.txt`
pointer files. In particular, the two literal-`null` receipt writes were
never used to launch geometry; they remain unchanged alongside the verified
R2 receipt in the source-`9d02177` root. Their cause and correction are
documented in the append-only checkpoints.

## Final campaign fields

```text
CAMPAIGN_STATUS=P3_1_R10_B_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE
VALID_GEOMETRY_HYPOTHESES_USED=6
ORIGINAL_B1_DISPOSITION=BLOCKED_HARNESS_ERROR_NOT_CONSUMED
B1R_SOURCE_SHA=6f28273d0113f93678034b9e482140e73e765721
B1R_PARENT_SHA=9d0217758c84ebd6031fbb1c533943894d1dac10
B1R_TREE_SHA=7630f95a2c72c0692f52d1dda8b7cbfdcdfd4efc
B1R_HYPOTHESIS=R10B1R_DIRECT_CONSTRAINED_TRIANGULATION_FEASIBILITY
B1R_SOLVER_FORMULATION=DETERMINISTIC_MRV_EXACT_COVER_BACKTRACKING
B1R_CANDIDATE_TRIANGLE_DOMAIN=62196_RAW_TRIPLETS; 7608_ACCEPTED; 73_ROOTS; 34_BOUNDARY_EDGES; 110_TARGET_FACES
B1R_DOMAIN_HASH=30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22
B1R_SEARCH_LIMITS=CANDIDATES_62196; NODES_500000; DEPTH_110; WALL_MS_120000; INTERSECTION_CHECKS_2000000; SOLUTIONS_1; ESTIMATED_STATE_BYTES_536870912; PROCESS_TIMEOUT_MS_600000
B1R_SEARCH_COMPLETE=false
B1R_SEARCH_NODES=768
B1R_CONFLICTS=EDGE_INCIDENCE_0; TRIANGLE_INTERSECTION_3656; ROOT_LINK_0; DISCONNECTED_0
B1R_SEARCH_CHECKS=2000001 (CAP 2000000; STOPPED WHEN CROSSING CAP)
B1R_FEASIBILITY_CONCLUSION=EXACT_ROOT_REALIZATION_INCONCLUSIVE
B1R_EQUAL_LOD=FAILED_TARGET
B1R_REQUIRED_ADJACENCY=21_MISSING
B1R_INTERNAL_OPEN_EDGES=10
B1R_NONMANIFOLD=0
B1R_WINDING=0
B1R_MIN_CROSS_SQUARED=NOT_APPLICABLE_NO_SELECTED_TRIANGLES; RETAINED_A6_MIN=1.67075673894024e-16
B1R_FINAL_SUBCUTOFF_FACES=7
B1R_CONTROLS=6/6
B1R_RAY_ROI=0/25
B1R_RAY_GLOBAL_DIAGNOSTIC=9/25
B1R_VOLUME=PASS
B1R_MIXED_LOD=NOT_RUN_PREREQUISITE_FAILED
B1R_DETERMINISM=NOT_RUN_NO_COMPLETE_SOLUTION
B1R_RESOURCE_ABORTS=0
FINAL_TOPOLOGY_ARCHITECTURE=UNRESOLVED_NOT_ADOPTED
FINAL_CONSTRAINED_REALIZATION=NONE_SELECTED
FINAL_EXACT_ROOT_FEASIBILITY=INCONCLUSIVE_LIMIT_REACHED
FINAL_EQUAL_LOD=FAILED_TARGET
FINAL_REQUIRED_ADJACENCY=21_MISSING
FINAL_INTERNAL_OPEN_EDGES=10
FINAL_NONMANIFOLD=0
FINAL_WINDING=0
FINAL_CONTROLS=6/6
FINAL_RAY=ROI_0/25; GLOBAL_DIAGNOSTIC_9/25
FINAL_VOLUME=PASS
FINAL_MIXED_LOD=NOT_RUN_PREREQUISITE_FAILED
FINAL_DETERMINISM=NOT_RUN_NO_COMPLETE_SOLUTION
FINAL_PERFORMANCE=UNSCORED
FULL_E2E_RESULT=NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE
FULL_VALIDATION_RESULT=NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE
EVIDENCE_INTEGRITY=PASS_INDEX_AND_ARCHIVE_HASHED
FINAL_ARCHITECTURAL_RECOMMENDATION=DO_NOT_ADOPT; ANY_FURTHER_GEOMETRY_RESEARCH_REQUIRES_SEPARATE_AUTHORIZATION_AND_PREREGISTRATION
```

## Recommendation and boundaries

The direct realization attempt is inconclusive because its finite intersection
check budget was reached. Do not claim mathematical infeasibility or adopt a
mesh solution. The retained equal-LOD topology remains unsuitable for the
frozen target. Any future research requires a separately authorized campaign
with a preregistered solver/resource plan; this R10-B campaign has no remaining
geometry slot and no B7 is permitted.

No production integration, merge, release, storage/schema change, Issue #108
or #154 work occurred. PR #208 remains draft/unmerged; PR #207 remains
unchanged. Preserve all five F2-G1 holds:
`CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`,
`ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`,
`F2_G1_RELEASE_HOLD`.
