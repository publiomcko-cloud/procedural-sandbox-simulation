# P3.1 R12-CXR R2 Pre-Target Freeze

Date: 2026-10-31

## Identity and gate

R1 on the unchanged frozen target completed both cavities and all authorized L0-L3 levels with `search_complete=true`, `search_exhaustive=true`, and no fixed-fan solution. That result is recorded in [the R1 result and R2 preregistration checkpoint](2026-10-31-P3-1-R12-CXR-R1-RESULT-R2-PREREGISTRATION.md). It enabled R2 only; it did not qualify geometry.

The R2 implementation is frozen at source commit `ddc761006765527f48b63719523ec83fa6d6ce9a`, direct parent `bb78b600eca3e3af77b6728f459bed41f7743549`, on branch `exp/p3-1-r12-cxr-r1-architecture-convergence`, stacked in draft PR [#213](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/213). PR #213 is open, draft, unmerged, and based on the unchanged draft PR #212. Only the R12-CXR test campaign, R12-CXR contract tests, and test-only field-support realizer changed in the source commit. The new R2 target has **not** started.

Godot contract preflight on this exact source tree used `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`. `--check-only` exited 0; the R12-CXR contract suite emitted `R12CXR_CONTRACT_TESTS_PASS`, 117 assertions, zero failures; stdout/stderr contained no parser, script, or runtime errors and stderr was empty. Raw files are in `C:\Users\PUBLI\AppData\Local\Temp\r12cxr_r2_contract_ffba211e90ac4feca663f29cba068be2`. Earlier failed preflight attempts remain in their separate timestamped directories and are not overwritten.

## Frozen target and immutable inputs

R2 will execute exactly one target, `R9.2.SEAM.XPLUS_EQUAL.v1`, with `R12CXR_PHASE=r2`. The runner must pin the exact R2 source SHA, parent, tree, Godot executable, campaign and realizer byte hashes, C6 sources, canonical stage-0 fixture, residual fixture, R9.2 manifest, Candidate D, topology authority, scalar volume/payload, ROI and expected result path before process creation. The campaign check-only gate must pass on the final pushed source SHA. R1, controls, rays, volume, topology roots/arcs/faces, Candidate D samples, ROI oracle, volume identity and the fixed `cross_squared > 1e-12` cutoff are unchanged. No R1 target, other scenario, full validation, or downstream gate has run in this R2 source commit.

## R2 finite search domain

For each cavity independently and in deterministic cavity order, process valid patch levels L0, L1, L2 and L3. An invalid boundary level records its complete boundary signature/incidence diagnostics and continues to the next level. Any malformed or unhandled topology constraint, support provenance failure, limit, timeout, or incomplete level makes the result partial; it cannot be reported as exhaustive no-solution. Complete each cavity before proceeding to the next. A valid candidate still requires all original geometry and topology checks; a complete no-solution is only a statement about the finite domain below.

1. Generate field-derived support candidates from each frozen residual face using the unchanged Candidate D samples and the existing bounded generator. Preserve every attempt and rejection. Union candidates across valid levels by exact binary32 position identity, reject identity/coordinate conflicts, sort by the existing canonical candidate ordering, retain at most 256 unique candidates per cavity, and select 0 through 4 supports. Source-attempt, support, cavity, patch and time caps remain as preregistered.
2. Build the boundary cycle from the cavity's directed single-loop incidence. Candidate vertices comprise exact boundary roots, endpoints of authoritative arcs wholly contained in the cavity, endpoints of residual source-owner boundaries, and the frozen support candidates. Interior topology roots retain their exact root IDs and binary32 coordinates. Support IDs or coordinates that collide with any retained topology root are rejected. A topology arc that crosses the projected cavity boundary, has a missing root, conflicts in expected incidence, or cannot be represented within a concave cavity invalidates that level as incomplete rather than silently dropping the constraint.
3. Merge the base realization's canonical arc map with deterministic owner-boundary constraints derived from shared edges of residual source faces with distinct frozen owners. Deduplicate by undirected root pair; conflicting expected incidences are invalid. Owner-derived edges require incidence two. Candidate triangles may not cross, split, or cover an internal constrained arc. The complete final mesh is rechecked against the merged canonical and source-owner arc obligations.
4. Enumerate candidate triangles lazily. For each sorted open edge, try every remaining candidate vertex in canonical ID order. Reject repeated identities, missing positions, nonfinite or `cross_squared <= 1e-12`, projected triangles outside the cavity or with an edge leaving a concave boundary, triangles crossing a constrained arc, ambiguous/opposing reference winding, unavailable source owner, or candidate-triangle cap. Accepted orientation is aligned with the frozen reference normal; only vertex order changes. Root coordinates are never changed.
5. Recursively extend the first sorted unsatisfied boundary/open-edge obligation. Require directed boundary incidence and opposite orientation on internal edges; do not allow incidence above two. State identity is the sorted set of triangle root triplets. Enumerate support counts in ascending order from zero through four, with supports counted only when used. Unused supports may be inserted only by a strict interior face split whose three children independently pass the same candidate predicate. Deduplicate visited states per support count.
6. A complete solution must preserve the exact cavity and level-patch boundary signatures; use exactly `B + 2(I + S) - 2` triangles for a single disk (`B` boundary vertices, `I` required interior topology roots, `S` selected field supports); use every required boundary/topology/support vertex; have connected manifold vertex links; be a connected triangle set; preserve owner metadata, every merged arc's expected incidence, fixed cutoff, winding, global intersection and T-junction checks; and preserve topology root coordinates. Surface deviation is a diagnostic and deterministic tie-break, never a replacement for an invariant.

Numerical search predicates are frozen with this source: projected point inclusion uses the existing `CXR_BARYCENTRIC_EPSILON=1e-7`; polygon area must exceed `1e-12`; nonadjacent boundary edges use the existing proper-crossing orientation predicate with product threshold `-1e-20`; segment partition uses denominator threshold `1e-20`, parallel/collinear cross threshold `1e-12`, and parameter deduplication `1e-12`; point-on-segment and final triangle intersection/T-junction checks retain the existing `TRIANGLE_EPSILON`. These are search-domain predicates, not relaxations to the acceptance criteria. Final cutoff and topology gates remain unchanged.

## Deterministic ordering and resource bounds

Candidate support order is the existing `_candidate_less` order; root IDs, edges, third-vertex choices, arcs, and state keys are sorted ordinally; triangle winding is selected against the frozen reference normal; equal score keys end with canonical triangle triplets. Within this finite domain the accepted rank is, in order: topology/invariant validity; fewer supports; smaller modified level patch; lower surface deviation; larger minimum cross squared; fewer triangles; fewer search nodes; stable canonical triplet key.

The source and emitted limits are exact:

| Limit | R2 bound |
| --- | ---: |
| Levels / cavities | L0-L3 / at most 3 |
| Source patch | 64 triangles per cavity |
| Field candidate attempts | 8,192 per cavity |
| Unique field supports | 256 per cavity |
| Selected supports | 0-4 per cavity |
| Candidate triangles | 65,536 per cavity; 131,072 total |
| Visited search states | 32,768 per cavity; 65,536 total |
| Search wall time | 10 seconds per cavity; 20 seconds total |
| Entire realizer | 30 seconds |
| Retained solution records | 32 per cavity (reporting cap only; does not stop enumeration) |

Any hit limit or incomplete provenance returns `search_complete=false` and `search_exhaustive=false`. R2 no-solution can enable R3 only when every cavity and every valid level has explicit complete/exhaustive disposition and there is no solution. A valid equal-LOD result advances immediately to the frozen downstream gates.

## Regression coverage and scope

The 117-assertion CXR contract suite covers finite support-free and one-support triangulations, deterministic output, outside and malformed supports, exact duplicate root coordinates, concave-domain rejection, internal arc retention/crossing, arc/cavity-boundary fail-closed behavior, distinct source-owner boundary derivation, source nonmanifold edge rejection, conflicting arc incidence, topology-root/support separation, crossing/T-junction guards, and partial-versus-exhaustive phase disposition. The suite is a source/contract test, not the frozen target result.

The existing untracked Godot `.gd.uid` files in this isolated worktree were left untouched and unstaged. The development workspace, existing stashes, user saves, other PRs and all five F2-G1 holds are unchanged. This remains a test-only experiment: no production adoption, Issue #108/#154 work, schema change, merge or release is authorized.
