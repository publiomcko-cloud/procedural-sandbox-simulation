# R12-C Stage 0 and C1 preregistration

## Campaign identity and scope

This is a test-only R12-C research branch derived from the final R10-BX evidence state. It does not alter production paths, persistence schemas, the terrain implementation, or prior evidence PRs. The branch base is PR #209 HEAD `eede76dbc8cb967a646679dd137eac0cdb9538aa`; exact tree/parent are recorded in the launch evidence.

Frozen scientific inputs:

- Candidate D: `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`
- R9.2 manifest: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`
- materialized volume: `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`
- volume payload: `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`
- R10-A source topology: `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`
- R10-A6 historical mesh: `de53e9fa326e451ac202beb49c0ef1e56b70500ce1ca3dd9c43565d85e7c5f74` (primary R10-A raw result; see provenance note below)
- cutoff remains `cross_squared > 1e-12`
- frozen candidate domain: `30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22`
- candidate-domain identity: `b3c5de9786a078a6568650ef62e2150524f1b387e9e979cba5a060723d990feb`
- target component: `60,8,25|tet:0`

Target scenario: `R9.2.SEAM.XPLUS_EQUAL.v1`, seed 131102026, ROI minimum [15,1,6], 8×8×8 cells, step 0.25, ordered FILL then CARVE. Candidate D remains the geometry field authority.

### Frozen hash provenance correction (R12-C pre-hypothesis)

The previously copied `1f21af7c...` digest is present in the R10-B6 attempt record (`B6-ATTEMPT-RESULT.md` / B6 JSONL), not in the primary R10-A6 geometry result. The authoritative source is the `R10-A6_geometry/required_equal_lod_gate_full_roi_R9.2.SEAM.XPLUS_EQUAL.v1.json` entry in `docs/reports/P3-1-R10-A-CAMPAIGN/evidence/R10-A-raw-evidence.zip` (archive SHA-256 `ac630bd3b6b8be3494b33367e1896030de541a88ae16e8fdcf8b7ac83ac58e6`); its `geometry.mesh_sha256` is `de53e9fa...`, with 655 triangles, 10 internal opens, 21 missing required adjacencies, zero nonmanifold edges, valid winding, and seven cutoff rejections. The R10-B6 result reports `1f21af7c...` with matching summary counts, but it is a separate R10-B6 attempt output and is not an R10-A6 output pin. R12 Stage 0 now uses the primary R10-A6 artifact digest and still checks every frozen topology metric; this corrects provenance rather than relaxing an acceptance criterion.

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

### Stage 0 result and C1 applicability (2026-10-30)

Stage 0 passed on source `d63394d3c0e255d7d0af547a258aa847700e2f44`; the create-new fixture is SHA-256 `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d0` (2,885,492 bytes). It verifies the 369/502/870 graph and target component 73 roots, 84 polygons, 156 incident arcs, 34 boundary roots, 39 interior roots. The root-degree histogram is 2:2, 3:19, 4:30, 5:1, 6:21; both degree-2 roots are boundary anchors. Therefore the frozen C1 rule has zero eligible interior PATH_EVENT roots and cannot alter this target's geometry. C1 is `NOT_APPLICABLE_NO_ELIGIBLE_INTERIOR_DEGREE2_ROOTS`, is not executed, and is not consumed. It will not be widened after observing this result.

The initial copied A6 digest discrepancy was resolved against primary raw evidence before any C hypothesis: the R10-A6 archive entry identifies `de53e9fa...`; the `1f21af7c...` value belongs to a distinct R10-B6 attempt record. The correction is documented above and both original records remain preserved.

## C2 — graph-face anchor-cycle realization (executed)

**Differentiator.** Build output triangles directly from the authoritative source polygon cycles in the Stage 0 graph. Do not run R10A6 component reconstruction, any edge-flip/beam search, or B1R candidate search. This is a loop/face realization, not a search over complete mesh states.

- Every source topology root is an `ANCHOR_VERTEX` with its frozen ID and Candidate D root position. The 369-root graph and all 870 arcs remain authoritative; for the target component this is 73 anchors and 156 incident arcs. No PATH_EVENT or SUPPORT_VERTEX is generated.
- Each canonical source polygon row supplies one ordered face cycle and source cell/tetra/face ownership. Validate that every consecutive cycle pair corresponds to its declared topology arc and that each arc has the exact source-face incidence from the graph.
- Triangles emit as one face if finite and `cross_squared > 1e-12`. Quads independently evaluate their two cycle-preserving diagonals; choose only a diagonal whose two triangles both exceed the unchanged cutoff, maximizing the smaller cross-squared value with a frozen lexicographic diagonal tie-break. Reject polygons above four roots or quads for which neither diagonal qualifies. No vertex moves or support points are allowed.
- The realization map records one root-to-anchor row per root, one arc-to-anchor-edge row per arc, and one face-cycle-to-triangle list per polygon. Reconstruct and hash the canonical root/arc/owner signature from that map; require byte-identical topology signature before geometry qualification.
- Build full ROI geometry from the full graph, not just the target component. Compute topology from emitted triangles, cutoff rejections and edge incidence against the 870 source arcs. A missing emitted incidence is a geometry failure even if the abstract realization map round-trips.
- Frozen field, input, ROI, seed, volume/revision, controls and ray contracts remain unchanged. C2 geometry, six controls and ROI ray diagnostics are separate records; mixed LOD stays gated on equal LOD + controls + ray + volume.

The C2 algorithm is bounded by the frozen 369 roots, 870 arcs, 502 source faces, 20,000 emitted triangles, 10-minute process limit and 2-GiB free-commit abort. It does not introduce a global combinatorial search.

### C2 result (2026-10-30)

C2 was validly executed once on source `f5b421a0f0e4a020a7fc1a8d00847a8e32f93234` (parent `d936203c5b769c0c022699d6ad5fad12a85b6e40`, tree `27f21a7279bde20f08a7141ff03f729e4599bb29`). The attempt `C2GEO006` reached `R12C_GEOMETRY_BEGIN`, emitted a complete classified artifact and is consumed as `FAILED_TARGET`; it was not rerun. The artifact `r12c_C2_C2GEO006.json` is SHA-256 `469be6d2b18c52cdb6bece2db378de1f8d6a81dd27aaa10fd47c652d3b8ecf25`.

The map retained 369 anchors, 870 arcs and 502 ordered faces; no path events or supports were used. It emitted 654 triangles. Eight triangular faces were rejected by the unchanged `cross_squared > 1e-12` cutoff (minimum accepted cross-squared was `1.34662257473411e-12`); the mesh had 13 internal open edges, 19 missing required arc incidences, zero nonmanifold edges, zero winding inconsistencies and zero emitted degenerate triangles. The target volume and payload SHA/revision checks passed. ROI ray parity was 0/25. Four controls passed; two negative-region controls failed before geometry because the harness used the parent scenario's missing ROI instead of the variant ROI. Their stderr contains Godot `SCRIPT ERROR` records. Thus C2's target failure is established, but the six-control gate is recorded as 4/6 and not passed. The 25 ROI ray result is still diagnostic evidence, not a complete C2 qualification. No mixed LOD, determinism repeat, full E2E or full validation ran.

The 8 cutoff rejections all came from 3-root source faces. This is evidence against the C2 one-cycle/one-anchor triangulation for this input, not a proof that all exact Candidate D realizations are impossible. The attempt's monitor recorded 13 samples, minimum free commit 13.51 GiB, and maximum observed Godot working set 6.14 MiB; working-set sampling is an estimate and does not imply GPU or presented-frame performance.

Four earlier `C2GEO001`–`C2GEO005` processes terminated in pre-geometry identity/setup gates; none emitted `R12C_GEOMETRY_BEGIN`, so they did not consume C2. Causes were exact graph-fingerprint handling after JSON parsing, a misplaced materialized-volume identity lookup, and numeric/serialized graph comparison. Their raw attempts remain under the immutable R12 evidence root. C2's final valid process completed despite the two negative-control script errors; this limitation is explicitly retained rather than hidden by the process wrapper's exit code.

## C3 — field-constrained per-face support fan (preregistered after C2)

**Differentiator and rationale.** C2's eight cutoff rejects were all 3-root source faces. C3 tests whether an explicit, deterministic geometry-only support record plus a face fan yields a useful topology-to-geometry realization map while keeping the exact same Candidate D piecewise-linear zero set. C3 is materially different from C2's direct triangle/quad triangulation. It does not change the cutoff or move source roots. Because a support point inside a rejected triangle cannot increase its area, C3 may produce additional cutoff failures; such a result is still informative and must not be concealed.

- Retain all source roots as `ANCHOR_VERTEX`, all 870 topology arcs, polygon cycles, ownership and incidence. No `PATH_EVENT` is used. Create exactly one deterministic geometry-only `SUPPORT_VERTEX` per source polygon (502 maximum for the full graph), with ID `support|<polygon_id>|centroid`.
- Compute each support point as the arithmetic centroid of its ordered source-cycle roots. Every source face is the zero-set polygon of one Candidate D tetrahedron; the centroid is a convex combination of its vertices and remains on that same piecewise-linear face. Independently compute and record tetrahedral barycentric coordinates, interpolated scalar residual, source cell/tetra, parent face, neighboring arc IDs and insertion reason. Do not introduce a residual tolerance or treat numerical residual evidence as product approval.
- Fan each source cycle edge to its support point: three triangles for a triangle and four for a quad. This keeps each original root-root topology arc as an actual boundary edge of one triangle per incident source face; each support spoke is geometry-only. Preserve source winding by the existing tetrahedral field orientation. Any fan triangle at or below the unchanged `1e-12` cross-squared cutoff is rejected and reported; no sub-cutoff triangle may be emitted.
- Require complete root/arc/face/support maps, exact graph-source identity, topology round-trip, 0 internal open edges, 0 missing obligations, 0 nonmanifold edges, valid winding, 0 degenerates and 0 cutoff rejections. No topology arc can be dropped because its face fan is rejected.
- Bound output to 2,008 triangles and 502 supports for the frozen 502-face graph, within the existing 20,000 triangle stop-loss. Preserve the 10-minute timeout and 2-GiB free-commit hard stop. Run the fixed target, six frozen controls (with each negative variant's actual ROI), the 25-ray ROI gate and volume identity. Mixed LOD remains gated on all equal-LOD gates.
- C3 source and realization hashes must be pinned after implementation. The frozen fixture SHA remains `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`; no input or acceptance threshold changes are authorized.

The C2 negative-region harness defect is corrected only in the C3 test-only campaign: the requested ROI variant must be passed into Candidate D volume construction. The process wrapper will also classify `SCRIPT ERROR`/`ERROR:` in Godot output as a captured runtime-error record, even when a script incorrectly exits zero. These are harness-integrity controls, not geometry hypothesis changes.

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

## C3 result and C4 preregistration (2026-10-30)

C3 `C3_FIELD_CONSTRAINED_SUPPORT_FAN` executed once as `C3GEO001` on source `e9bc9637a9aeadefc4385959c7ff2cf786c35997` (parent `1edb73316876e20a20367c4c88de8b20689eb8f5`, tree `ffc460cf507f083ce8cd6f62e39074ac2f6973ee`). The campaign and realizer physical SHA-256 values were `e2981b34f2cdbf101bfe71840dffba2f2e31ac21a91fd868342c8ad9a64e7926` and `8b8e818feec87daddb7a90ae2ee45a9e91357aa368828485254f017cd848b7d2`; the fixed Stage 0 fixture SHA remained `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`. Import and check-only passed, the geometry process exited 0 without runtime errors, and the result artifact SHA-256 is `81b01ce3f41c6dcbf37965429fc39d54316c8c947a6d88faff4efe7eda8ac80a`.

The target retained 369 anchor roots, 870 arcs, 502 faces, and added 502 deterministic face-centroid supports. It emitted 1,621 triangles; 45 fan triangles failed the unchanged `cross_squared > 1e-12` cutoff, leaving 33 required arc incidences missing and 20 internal open edges. Nonmanifold edges, winding inconsistencies, and emitted degeneracies were 0; minimum accepted `cross_squared` was `2.48140180278411e-12`. The topology round-trip matched (`a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9`); realization-map and support-map hashes were `fbe6e385738b86e4a54490ef5c8768bd682e2199eb450c3db892ba7786fb9518` and `89217712cd60a5d9a22c00ff2b1a9924318aceb17892873317e8ce221c816cf9`. The 502 raw interpolated scalar residuals ranged from -6.65474999550497e-7 to 5.66350110808855e-7; these are reported observations, with no new tolerance inferred. Four positive controls passed; neighbor-pair and X_NEG controls failed in the realizer, but the C3 campaign omitted the nested realizer failure details, so their causes remain UNKNOWN. The required controls gate therefore did not pass. ROI ray parity was 0/25; full-field ray comparison was 9/25 diagnostic only. Frozen volume SHA, payload SHA, revision 2 and reload identity passed. C3 is consumed as `FAILED_TARGET`; the target was not rerun.

### C4 — exact-coplanar local 2–2 patch remeshing (preregistered)

**Differentiator.** C3 added an interior support to every source face and substantially increased cutoff rejections. C4 instead starts from the frozen ordered source face cycles with every source root retained as an anchor, reconstructs all initial face triangles *before* the cutoff filter, and uses a bounded local 2–2 edge flip only to repair a pair containing a sub-cutoff candidate. It does not create centroid fans or alter the volume.

**Frozen algorithm and bounds.** Build the deterministic C2 face-cycle triangulation, retaining rejected candidates as private, unqualified working geometry. Sort shared edge keys lexicographically. A flip is eligible only when exactly two triangles share an internal edge, their four vertices are distinct, the alternate diagonal is absent, opposite vertices lie on opposite sides of the old edge, and the four binary32 source-root coordinates are exactly coplanar under the computed scalar triple product (`determinant == 0.0`; no tolerance). Both replacement triangles must satisfy the unchanged cutoff and agree with both source-face orientation vectors. Select the first eligible edge in key order, apply it, rebuild incidence, and repeat only while at least one current triangle is below cutoff; stop at 128 flips. No vertices or scalar samples move. If a source topology arc is removed as a diagonal, represent it explicitly by a deterministic piecewise path through the midpoint of the replacement diagonal, record both source polygons/cells/tetrahedra and the path coordinates, and count it as covered only if both path segments lie in the two replacement triangles. All other topology arcs must map to an emitted mesh edge. Any uncovered arc, ambiguous owner, noncoplanar candidate, cutoff violation, or cap exhaustion remains a failure; no tolerance or fallback is permitted.

The campaign must report rejected flip candidates and reasons, applied flips, pre/post cutoff counts, changed triangle owners, all six controls with nested failure details, path-to-arc coverage, topology round-trip, mesh topology, ROI rays, global ray diagnostic, volume identity, and the original geometric coordinates. C4 does not claim that noncoplanar patches can be remeshed exactly. The exact-coplanar requirement can make the strategy inapplicable; this is an expected informative outcome. Equal-LOD failure consumes C4 as `FAILED_TARGET` only after complete realization and machine-readable classification. Mixed LOD and later gates remain conditional on all equal-LOD gates passing.

## C1–C6 reservation status

C1 is not applicable under the preregistered degree-2 rule and remains unconsumed. C2 and C3 are consumed as `FAILED_TARGET`. C4 is preregistered above and not yet implemented/executed. C5–C6 remain unused and require evidence-directed preregistration before implementation. No C7 is authorized.

## Safety and interpretation

Only this experimental branch/worktree is mutable. No production code or schemas, user saves, prior PRs, or F2-G1 protected state are touched. Headless metrics are UNSCORED and are not presented FPS/GPU evidence. A failure is evidence about this finite hypothesis only; no result proves global infeasibility.
