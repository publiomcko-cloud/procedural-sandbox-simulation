# P3.1 R12-CXR R4 — Boundary-First Realizer Results

**Disposition: `R12_CXR_R4_TRIANGULATION_PARTIAL_WITH_EVIDENCE`**

R4 reproduced the frozen support pool, replaced radius/subset cavity selection with bounded boundary-first expansion, and exhaustively checked the resulting finite candidate graph. The selected six-face cavity has a valid single outer boundary, but the frozen field-derived support pool and current candidate domain produce zero legal triangles and zero triangulations. This is a finite-domain negative result, not proof that the selected architecture is mathematically infeasible. No equal-LOD mesh candidate exists, so no target attempt or downstream qualification was run.

## Identity and scope

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`; origin `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- R4 branch: `exp/p3-1-r12-cxr-r4-boundary-first-realizer`.
- R4 source commit: `f48990e25ffb1d377e02a9182240cabe35c815eb`; direct parent `b2480bc71fe9c9616426d378feb00e3e33e785f2`.
- R4 base: R3AB evidence PR #215 head `58f946c857f419dd80b8ab703f4138894aee455c`, parent `78cbe7a45a85c65042c607e683abcd24f977db26`.
- At validation time, main was `5997a76d345f45bf86edfe83f690336391e8be27`; PR #215 was open/draft/unmerged. R4 did not modify PR #215 or production paths.
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- R4 source/instrumentation is test-only. No save, schema, production mesher, Issue #108/#154, merge or release action occurred.

The seven source/input paths in the first R4 commit are `.gitattributes`, the R12-CXR realizer and contract tests, the new R4 D1 diagnostic, and three frozen JSON fixtures. The second source commit pins the exact Candidate D implementation bytes in both D1 and the contract suite. See [`SOURCE-SHA256SUMS.txt`](evidence/final-f48990e/SOURCE-SHA256SUMS.txt).

## Frozen identities

The D1 runner verified these inputs before evaluating the candidate graph:

| Input | SHA-256 |
|---|---|
| Candidate D implementation | `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a` |
| R9.2 input manifest | `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` |
| Stage-0 topology fixture | `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d` |
| Topology identity | `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95` |
| Graph fingerprint | `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9` |
| Residual C6 fixture | `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23` |
| Support pool, attempt 07 | `fe876d0d8a469b5f972c507cf17d9198d26432f9973a41f0d082a6f806f8ddd8` |
| Materialized volume | `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` |
| Payload, revision 2 | `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0` |
| Frozen ray fixture | `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7` |

The three JSON fixtures use a path-specific `-text` Git attribute. A checkout with `core.autocrlf=true` previously risked changing the physical bytes hashed by Godot. The final cold-import/D1 run verified the pins after this attribute was committed; no scientific input was repinned.

## Implementation completed

1. R4 boundary-first search expands only across faces adjacent to the lexicographically selected offending boundary elements, while preserving the preregistered face/state/queue/component/time caps.
2. The boundary cycle set checks directed in/out degree and deterministic cycle ordering. R4 projects accepted cycles onto a plane derived from the selected patch, rejects self-crossing/touching projected components, and records containment depth, parent, winding and `OUTER`/`HOLE`/`ISLAND` relation. A cycle-only result stays explicitly unclassified until projected geometry exists.
3. D1 reconstructs the support pool byte/provenance-exactly and now verifies the physical Candidate D source SHA. It records support-to-edge viability, rejection histograms, the support-eligible triangle preflight, full R2 candidate-triangle rows and D3 search results.
4. Edge preflight rejects out-of-domain endpoints/segments, required-arc crossings, duplicate positions and T-junctions. Contract regressions cover each case, plus single, disjoint and nested cycle sets, crossing loops and winding/parity conflict.
5. The strict degeneracy condition remains `cross_squared > 1e-12`.

## D1, D2 and D3 observations

Target identity: `R9.2.SEAM.XPLUS_EQUAL.v1`. The D1 script operated on pinned fixtures and did not invoke the target campaign or consume any of its five target-attempt slots.

| Measurement | Observed |
|---|---:|
| Frozen support rows reproduced exactly | 115 |
| Support-to-eligible-vertex edge pairs probed | 1,374 |
| Unique legal candidate edges | 18 |
| Supports with at least one / at least two legal edges | 5 / 5 |
| Eligible-vertex triangle preflight | 220 probes, exhaustive |
| D3 candidate triangle rows | 329 |
| Legal candidate triangles / supports with a legal triangle | 0 / 0 |

The D3 rejection histogram sums to all 329 rows: 136 at/below the strict cutoff; 31 cross a required topology arc; 46 leave or cross the boundary; 8 have no residual owner; 108 include a vertex outside the boundary. The `220` D1 preflight combinations and `329` D3 rows are separate counters: the first covers the explicitly projected eligible-vertex subset, while the second is the R2 searcher's complete recorded candidate domain. No accepted triangle was hidden or filtered from the D3 result.

D2 completed without hitting its declared caps. It visited 15 states (queue peak 12), and selected the connected six-face patch containing the two residual seeds plus C6 faces 654–657. Its boundary has six vertices, one component, and signature `90be2d27d3c08ccb2fe93ebf6b8a0da0d8955d3c4d533a4496809b4d07bd363b`. The projected cycle is one CCW `OUTER` loop at depth 0; no hole was present in this target cavity. The expansion rejection counts were: incidence invalid 2, directed-degree defect 8, required arc crossing 2, and projected self-intersection 2.

D3 was complete and exhaustive over its finite recorded domain: 329 candidate rows, 5 branches, 7,099 microseconds, zero solutions, terminal `r2_finite_triangulation_domain_exhausted`. The result establishes that this support pool/candidate graph cannot realize this cavity under the unchanged topology, ownership, domain and cutoff constraints. It does not establish that all deterministic field-derived support sets fail; no such global claim is made.

## Exact-source validation

All stages ran serially on source `f48990e25ffb1d377e02a9182240cabe35c815eb`, with a unique Godot user-data profile and raw stdout/stderr/process records in [`evidence/final-f48990e`](evidence/final-f48990e/).

| Stage | Result |
|---|---|
| Editor import (`--headless --editor --import`) | Exit 0; about 8.3 s; no parser/script error or warning matched the error scan |
| Realizer `--check-only` | Exit 0; about 2.05 s |
| D1 `--check-only` | Exit 0; about 2.77 s |
| R12-CXR contract suite | `R12CXR_CONTRACT_TESTS_PASS`; 216 assertions, zero failures; exit 0 |
| Pinned D1→D2→D3 diagnostic | Exit 0; status `D1_B_LEGAL_EDGES_NO_LEGAL_TRIANGLES`; no candidate geometry |

Free commit remained approximately 8.31–8.14 GiB during the gates, above the 3 GiB warning and 2 GiB stop thresholds. No timeout or resource termination occurred. Process records include the Godot PID, parent PID, command line, timestamps and source identity.

One wrapper call failed before process creation because the D1 stage directory had already been created by its caller; `New-Item` refused the duplicate directory. The failure and corrected distinct stage path are recorded in `evidence/final-f48990e/d1_d2_d3/wrapper-recovery.json`. No Godot process or target began in the failed call. The corrected D1 diagnostic then ran once.

The earlier pre-commit D1 run is preserved separately under the R4 evidence directory but is not relied upon for this disposition. The exact-source run above is authoritative.

## Gates not run and remaining limits

No equal-LOD candidate emerged. Therefore the frozen target attempt, topology round-trip, geometry/volume gates, 6/6 controls, 0/25 ROI rays, mixed-LOD, deterministic repeat, full E2E, and `scripts/validate.ps1` were skipped by the sequential gate. No performance or GUI acceptance is claimed. Attempts 06–11 remain untouched and must not be rerun.

The tested cavity has one boundary loop. Projected multi-loop nesting classification is implemented and covered by synthetic contract cases, but a hole-aware triangulator is not implemented; if a future minimal cavity contains holes or multiple components, R4 must stop partial until that path exists. The finite D3 no-solution also leaves the next candidate-support-generation correction unresolved. It must remain deterministic and field-derived; arbitrary support insertion, topology changes, root movement, threshold changes and input repinning remain prohibited.

## Disposition

`R12_CXR_R4_TRIANGULATION_PARTIAL_WITH_EVIDENCE`

This is not `R12_CXR_R4_STRUCTURAL_BLOCKER_WITH_EVIDENCE`: the finite candidate graph is exhausted, but a broader deterministic field-derived support domain may still satisfy the frozen architecture, so no exact incompatible architecture invariant has been demonstrated. It is not architecture qualification, production readiness or permission to merge.

All protected-state holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
