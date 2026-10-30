# R12-C Stage 0 and C1 preregistration

## Campaign identity and scope

This is a test-only R12-C research branch derived from the final R10-BX evidence state. It does not alter production paths, persistence schemas, the terrain implementation, or prior evidence PRs. The branch base is PR #209 HEAD `eede76dbc8cb967a646679dd137eac0cdb9538aa`; exact tree/parent are recorded in the launch evidence.

Frozen scientific inputs:

- Candidate D: `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`
- R9.2 manifest: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`
- materialized volume: `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`
- volume payload: `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`
- R10-A source topology: `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`
- R10-A6 historical mesh: `1f21af7c3856ae72080e3e0c5ad44a3c608703470b5563212902bed08ad0f7d4`
- cutoff remains `cross_squared > 1e-12`
- frozen candidate domain: `30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22`
- candidate-domain identity: `b3c5de9786a078a6568650ef62e2150524f1b387e9e979cba5a060723d990feb`
- target component: `60,8,25|tet:0`

Target scenario: `R9.2.SEAM.XPLUS_EQUAL.v1`, seed 131102026, ROI minimum [15,1,6], 8×8×8 cells, step 0.25, ordered FILL then CARVE. Candidate D remains the geometry field authority.

## Stage 0 — fixture contract

Before any C hypothesis, the fixture builder shall:

1. Verify exact source and candidate-domain identities.
2. Rebuild and hash the frozen Candidate D materialized volume and payload.
3. Build the R10-A source topology and compare its canonical hash to the frozen source topology identity.
4. Extract component `60,8,25|tet:0`: 73 roots, 84 source polygons and its complete incident arcs.
5. Match root coordinates against the independently frozen B1R candidate-domain rows.
6. Match its ordered 34-root boundary and 34 boundary arcs to the domain's required boundary edges.
7. Record root degree, all arc endpoint order/provenance, component membership, polygon/cell/tetra source data, half-open ownership and region/LOD transitions.
8. Execute historical R10-A6 as a reproduction check and require its source-topology proof and mesh hash to match the frozen record. Record its 655 triangles, 10 internal open edges, 21 missing required adjacencies, zero nonmanifold edges, recorded winding and seven fixed-cutoff rejections.
9. Emit one create-new fixture JSON with a canonical topology signature/hash and exact volume, payload, revision, ROI and cutoff identities. Failure emits a structured terminal BLOCKED record; it never emits a partial PASS fixture.

Stage 0 is infrastructure and does not consume C1.

## C1 — degree-2 transit-root path realization

### Distinct hypothesis

The R10-A6 small-face failure may be caused by requiring every degree-2 interior topology event to become an independent mesh vertex. C1 keeps all topology roots, arcs and ownership in the authority graph, but permits eligible degree-2 interior roots to be represented as ordered PATH_EVENTs on one maximal topology chain. No support vertices are permitted in C1.

### Classification frozen before execution

- BOUNDARY_ANCHOR: every root on the frozen ROI boundary.
- ANCHOR_VERTEX: every nonboundary root whose graph degree is not exactly 2; every ownership-transition root; every root required to keep component/loop/branch correspondence unambiguous.
- PATH_EVENT: only a nonboundary degree-2 root whose two incident arcs belong to one deterministic chain with unique predecessor and successor and no ownership transition.
- If ordering, path membership, or ownership is ambiguous, fail closed by promoting that root to ANCHOR_VERTEX and record the reason.
- No geometric near-collinearity threshold is used.

### Path construction and geometry

Build maximal paths by sorted anchor IDs and sorted incident arc keys. Walk each arc exactly once; store ordered topology root IDs, root positions, cumulative Euclidean parameters, source arc IDs, source polygon/cell/tetra provenance, and endpoint anchors. Every event parameter is computed from the frozen root coordinates in binary64 and serialized with round-trip precision.

C1's geometry uses only the path endpoint anchors as vertices for a collapsed path segment. Each PATH_EVENT is mapped to its closest point on that segment and its displacement is recorded; a nonzero displacement is evidence of geometric approximation, not a topology change. Each topology arc must map to exactly one ordered path interval. Reconstruct the topology root/arc signature from this map and require exact signature equality. The geometry candidate is still judged by the unchanged frozen mesh, cutoff, topology, controls and ray gates; no tolerance is invented to convert approximation into acceptance.

Triangulate source polygon boundaries after replacing transit events by their path intervals. If the replacement is not a simple, consistently oriented polygon, or produces a sub-cutoff triangle, classify the completed C1 geometry result as FAILED_TARGET. Do not fall back silently to A6 or another hypothesis.

### C1 bounds and gate sequence

C1 processes only the frozen component plus fixed source topology already present in the ROI; no search, mesh subdivision, support vertices, or field mutation. Maximum realization paths: 512; maximum geometry triangles: 20,000; maximum runtime: 10 minutes; per-process hard abort at 2 GiB free system commit. These are execution stop-loss bounds, not product budgets.

Before a valid C1 attempt: exact source/parent/tree/blob and physical hashes, isolated Godot profile, Stage 0 fixture SHA, R10A authority/Candidate D/manifest/domain/Godot hashes, and launch intent must be durably recorded. Then cold import, script check-only and realization contract tests must pass. A valid execution is followed by equal-LOD geometry; six controls, 25 ROI rays and volume integrity execute even if the target geometry fails, so regressions are measured. Mixed LOD and later gates execute only if all preceding required gates pass.

### Result classification

A complete C1 map and completed target geometry with failed frozen invariants consumes C1 as FAILED_TARGET. A parser, runner, fixture, evidence, or resource failure before complete map+geometry does not consume C1; preserve it and correct tooling with a new attempt ID. No C1 result can authorize production adoption.

## C2–C6 reservation

C2–C6 remain unused. Each will receive a separate immutable preregistration after reviewing the preceding completed hypothesis and before its first execution. C2 will follow the frozen anchor-cycle polygon realization family; C3 field-constrained supports; C4 local topology-preserving remesh; C5 face-owned/interface-aware realization; C6 evidence-directed final architecture. No C7 is authorized.

## Safety and interpretation

Only this experimental branch/worktree is mutable. No production code or schemas, user saves, prior PRs, or F2-G1 protected state are touched. Headless metrics are UNSCORED and are not presented FPS/GPU evidence. A failure is evidence about this finite hypothesis only; no result proves global infeasibility.
