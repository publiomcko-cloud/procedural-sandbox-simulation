# P3.1 R10-BX Conflict-Indexed Exact-Root Feasibility Preregistration

- Date: 2026-10-30
- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Branch: `exp/p3-1-r10-bx-conflict-indexed-feasibility`
- Evidence base: final R10-B PR #208, source SHA `4e032085da53c43e78fe6b7ca3af1f569ede03d8`
Frozen B1R measured source: `6f28273d0113f93678034b9e482140e73e765721`

## Purpose and status

This is a test-only solver-architecture experiment. It asks whether the exact same frozen B1R candidate domain has a feasible 110-triangle realization when pairwise conflicts are indexed once and search uses bitset propagation. The projection, source roots, exact candidate list, ownership, orientation, mathematical cut-off, and acceptance rules remain frozen. No result is a production geometry contract, production integration, merge, schema change, or authorization for Issue #108 or #154.

This document fixes the search and graph-construction bounds before the first valid conflict-indexed search. The exact physical SHA-256 of this file is embedded in the campaign script before search execution. No threshold may be changed after observing a valid terminal search result.

## Frozen domain and provenance

| Input | Frozen identity |
|---|---|
| B1R candidate-domain physical SHA-256 | `30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22` |
| B1R candidate-domain identity SHA-256 | `b3c5de9786a078a6568650ef62e2150524f1b387e9e979cba5a060723d990feb` |
| B1R source commit | `6f28273d0113f93678034b9e482140e73e765721` |
| Candidate D SHA-256 | `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a` |
| R10-B manifest SHA-256 | `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` |
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| Godot executable SHA-256 | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |
| Volume SHA-256 | `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` |
| Payload SHA-256 | `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0` |
| Volume revision | `2` |
| Exact-root component | `60,8,25|tet:0` |

Before any search, the campaign rehashes the physical domain and revalidates its complete identity and all candidate records through the unchanged B1R loader. The frozen domain must still contain exactly 73 roots, 34 boundary edges, 39 interior roots, 7,608 ordered candidate triangles, and 2,239 distinct undirected candidate edges (derived independently by canonicalizing each candidate's three endpoint pairs). The 2,628 value is only the maximum possible number of undirected pairs among 73 roots (`73*72/2`), retained as a conservative matrix-memory estimate; it is not the observed candidate-edge count. Any identity/count/order/owner/orientation/cut-off mismatch blocks before search and does not consume the BX feasibility result.

The frozen R10-B ray fixture is pinned at SHA-256 `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7`. The Windows checkout used for this campaign has `core.autocrlf=true`; its tracked working-copy bytes contain one CRLF and hash to `8848b9181f826dc69c49fde222171c5ab1a60ea55daaba4beb4672c7b672ca7e`, while bytewise CRLF-to-LF normalization reproduces the frozen `9780…` hash. R10BX reference gates use a create-new shadow copy only after verifying both observed and canonical hashes; the tracked fixture and PR #208 remain unchanged. A different normalized hash blocks.

## Frozen mathematical problem

The target is a connected, consistently oriented triangulated disk with 73 mandatory roots, one simple ordered boundary of 34 edges, and 110 faces (`2V - B - 2 = 110`). The unchanged squared-cross cutoff is strict: a candidate is admissible only when `cross_squared > 1e-12`. Candidate coordinates, owner cells, edge keys, edge directions, and root indices are those in the frozen B1R file. There is no Steiner point, root movement, tolerance, candidate regeneration, candidate omission, or geometry change in BX.

For a complete triangulated disk with `F=110` faces and `B=34` boundary edges, edge incidence gives `3F = 2(E-B) + B`, hence exactly `E=182` unique used edges; Euler then gives `V-E+F=1`. The solver uses the monotone safe bounds `used_edges <= 182` and `used_edges + 3 * remaining_faces >= 182`. These are necessary conditions only; they do not accept a partial mesh. A completed assignment must satisfy exact face/edge/root incidence, disk connectivity, vertex-link manifoldness, and Euler.

## Conflict-index algorithm

For the 7,608 candidates there are `7,608 * 7,607 / 2 = 28,937,028` unordered candidate pairs. A deterministic X-axis sweep over closed projected AABBs is the broad phase. Only strictly separated closed boxes may be omitted; box touching remains a candidate pair. A Y-interval rejection is also strict, so it cannot remove a crossing or containment pair. Every remaining pair is classified by the same exact projected segment-crossing and strict centroid-in-triangle predicates used by B1R, plus the frozen incidence rules:

- projected edge crossing or positive-length collinear overlap. Edges sharing one canonical root are compatible only when they meet at that root alone; same-ray overlap is a T-junction and is classified as `edge_crossing`. Edges sharing both canonical roots are handled by the incidence/orientation rules;
- strict triangle containment;
- same-direction use of an interior edge;
- repeated use of a boundary edge.

Legal opposite-direction use of an interior edge and permitted root sharing remain compatible. Geometric categories are retained as separate bits; a pair can carry multiple categories. The symmetric candidate conflict bitset is authoritative for search; a symmetric row-major category byte matrix and per-candidate row hashes support audit. Edge rows retain boundary status, exact required direction, positive/negative candidate lists, maximum incidence, required final incidence, and orientation rule. Root rows retain the full candidate list, required-use status, and boundary/interior classification.

The broad phase may retain false positives for exact classification; false negatives are prohibited. The implementation first builds a symmetric byte matrix of exact conflicts between the 2,239 unique frozen root edges. Candidate triangle pairs use a closed-AABB sweep, followed by a conservative single-axis rejection along the vector between the two projected triangle centroids. This direction need not find every separated pair; it rejects only when the closed projection intervals are strictly separated after an IEEE-754 rounding enclosure. Touching intervals remain candidates. Each projected value `d = x*axis.x + y*axis.y` is enclosed with `32 * 2.220446049250313e-16 * (1 + abs(x*axis.x) + abs(y*axis.y) + abs(d))`, then interval-bound arithmetic is expanded by the same unit-roundoff factor. Any pair not proven separated remains in the exact edge-matrix and strict centroid-in-triangle classification. This enclosure only prevents false-negative pruning; it does not change any geometric acceptance predicate, SDF cutoff, or geometry tolerance. The 10,000,000 exact-pair budget counts exact edge-pair segment classifications plus retained candidate-pair classifications; AABB candidates, centroid-axis probes, and proven separations are reported separately and remain bounded by the fixed wall-time limit. The 2,628-root-pair upper bound is used only for conservative preallocation accounting; actual matrix dimensions are validated against the independently derived 2,239 edge count. Graph construction fails closed if its pair/time bounds are reached. Graph audit checks matrix shape, symmetry, zero diagonal, category/bitset agreement, per-candidate conflict/category counts and row hashes, boundary obligations, orientation partitions, witness crossing/containment/compatible pairs, and index completeness against the pinned domain.

Two independent graph builds must produce the same graph SHA-256. Serialized index and matrices are physically hashed, bound to the source/domain identity, reloaded, checked against the pinned candidate/edge/root index, and tested with a byte-tamper negative. Graph and search artifacts are create-new; overwriting is prohibited.

## Search representation and completeness

Search uses deterministic GDScript and a deterministic candidate order. State consists of available and selected candidate bitsets, positive/negative edge incidence counts, root-use counts, unique-edge count, and face count. Selecting candidate `i` removes `i` and all candidates in its precomputed conflict row; no geometric intersection test occurs inside recursion.

Propagation repeatedly applies:

1. boundary edge: incidence is at most one; exactly one legal-orientation use is required; zero choices conflicts; one choice is forced;
2. selected interior edge: at most one incidence per direction; a selected half-edge requires an opposite-orientation completion; zero completions conflicts; one is forced;
3. each frozen root must remain represented; zero remaining candidates conflicts; one is forced;
4. face count and the necessary Euler unique-edge bounds;
5. final connected disk topology and all vertex-link checks before accepting SAT.

Branching uses deterministic MRV in this order: unmet boundary edge, open selected interior edge, unused required root. No heuristic pruning or candidate removal is permitted. Complete UNSAT is reportable only if every branch is exhausted without any limit. Any reached bound or internal incompleteness produces `EXACT_ROOT_REALIZATION_INCONCLUSIVE`.

## Frozen resource and search limits

| Resource | Limit fixed before search | Behavior |
|---|---:|---|
| Exact unique-edge plus candidate-triangle pair tests per conflict-graph build | 10,000,000 total | Stop graph build; no search |
| Conflict-graph build/audit time per build | 180,000 ms | Stop graph build; no search |
| Candidate conflict bit matrix | `n * ceil(n/8)` bytes; 7,235,208 bytes | Exact fixed allocation |
| Category matrix | `n*n` bytes; 57,881,664 bytes | Exact fixed allocation |
| Unique-edge geometry matrix | `2,628*2,628` bytes; 6,906,384 bytes | Exact fixed allocation; used only while building the candidate conflict graph |
| Estimated graph allocation | 512 MiB | Preallocation guard; abort before allocation if exceeded |
| Search node entries | 500,000 | `INCONCLUSIVE` if reached |
| Recursive branch depth | 110 | `INCONCLUSIVE` if exceeded |
| Search wall time | 120,000 ms | `INCONCLUSIVE` if exceeded |
| Search state estimate | 512 MiB | Abort before search if estimate exceeds bound |
| Retained solutions | 1 | Stop on first independently valid SAT assignment |
| Separate propagation-operation cap | None | Search node and wall limits apply |
| Godot process timeout: graph/preflight | 1,200 s | Kill only the launched process; preserve as tooling/resource-limited evidence |
| Godot process timeout: search | 600 s | Kill only the launched process; preserve as inconclusive unless another hard stop applies |

The memory estimates are bounded accounting estimates, not measured RSS guarantees. The external Windows launcher samples host commit approximately every 350 ms. Warning threshold is free commit `<= 3 GiB`; hard abort is `<= 2 GiB`. Only the launched Godot PID may be terminated. At most two resource-safety retries are permitted, each with a new evidence attempt and identical frozen inputs/limits. Process/resource aborts do not create a scientific feasibility conclusion.

## Feasibility result semantics

- **SAT:** `EXACT_ROOT_REALIZATION_FOUND` only after all 110 selected triangles pass complete root/edge/manifold/connectivity/cut-off verification. This establishes combinatorial feasibility only.
- **Exhaustive UNSAT:** `EXACT_ROOT_REALIZATION_INFEASIBLE_FOR_EXHAUSTED_FROZEN_DOMAIN` only after the complete exact finite domain is searched and every pruning rule above is verified necessary. This is not a claim about other realization domains or global terrain geometry.
- **Limit:** `EXACT_ROOT_REALIZATION_INCONCLUSIVE` whenever a search bound is reached.
- **Preflight/tool failure:** no valid search has occurred; preserve evidence and correct/re-pin the tooling before trying again.

If SAT, run the existing frozen equal-LOD assembly/topology, cutoff/winding, 6/6 controls, ROI 0/25 ray, and volume identity gates. Mixed LOD may run only after all those pass and must use a real conforming interface; the equal-LOD frozen B1R domain does not synthesize such an interface, so unsupported mixed-LOD geometry is `NOT_GENERALIZED`, never PASS. Deterministic repetition and full E2E follow only if prior gates pass. `scripts/validate.ps1` runs only after every preceding geometry gate passes. If SAT but a geometry gate fails or is unsupported, report both exact-root SAT and the failed/not-generalized geometry result, close BX, and recommend R10-C.

## Decision and stop rule

R10-BX is the final experiment in the exact-root realization family. An inconclusive or exhaustive-unfeasible result closes this family and recommends a separately authorized R10-C architecture with an explicit topology-to-geometry realization map and geometry-only support vertices. No BX2, R10-C implementation, production adoption, geometry-tolerance decision, or merge is implied.
