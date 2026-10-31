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

## C4 result, C5 preregistration, and C5 result/C6 preregistration (2026-10-30)

C4 `C4_EXACT_COPLANAR_LOCAL_2TO2_PATCH` executed once as `C4GEO001` on source `01856f529df0a0f8c0bf62be5684d86fd923d071` (parent `db130481d79b5ad88fc3e705695bb1530cfadd61`, tree `1b361cd8ab0fc4502605956710560abc81939d6e`). Import, check-only and the single geometry attempt were clean; a prior C4 check-only on `db13048` found inherited duplicate constant declarations before geometry and did not consume the hypothesis. Campaign and realizer physical SHA-256 values for the valid attempt were `a904b9aca601473f1aab152fb8c2b43b71e252bd92c2ac245ee899962206e70c` and `1dcdf7d1374d95d05dce488d5fc91e577ed26f8926dce5818300d8080146017e`. The Stage 0 fixture remained `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`; artifact `r12c_C4_C4GEO001.json` SHA-256 is `8cd8de0e49016b8cbfe8014d0372047295f6641a9cceb364f80068262d2edc1e`.

C4 retained 369 anchors, 870 arcs and 502 faces; it attempted 18 local flips, rejected all 18 because their source roots were not exactly coplanar, and applied 0. It retained all 662 source-cycle candidate triangles, including eight below the fixed cutoff. Result: 0 internal opens, 0 missing obligations, 0 nonmanifold edges, 0 winding inconsistencies, 8 sub-cutoff/degenerate faces, and minimum `cross_squared=8.90332212726756e-17`. Exact topology round-trip matched (`a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9`); realization-map SHA is `7c713782d0de575bc73a8fe8d5f955e5d5b4c6e022d40fcaee091fe056528e28`. All six controls passed, ROI rays were 0/25, global ray diagnostic 9/25, and volume identity passed. C4 is consumed as `FAILED_TARGET`, first invariant `fixed_cutoff`; the attempt was not rerun.

### C5 — face-owned bounded noncoplanar 2–2 patch realization (preregistered)

C4 established that no target repair edge containing a sub-cutoff triangle met exact coplanarity. C5 changes only that admissibility rule: it uses the same frozen source cycles, anchors, sorted local edge order, four-distinct-vertex and convexity checks, orientation agreement, alternate-diagonal exclusion, 128-flip maximum, fixed cutoff, and explicit removed-arc path. It permits a finite nonzero scalar triple product only when both replacement triangles remain consistently oriented to both owning source faces and each passes the cutoff. No source root, scalar sample, volume, or ownership record changes.

Every flip is owned by the ordinally first source polygon ID. Both replacement faces record the complete two-face owner set, source cell/tetra provenance, triangle IDs, and the original topology arc's path through the midpoint of the replacement diagonal. For each flip, report the scalar triple product and the distance between the old and replacement diagonal midpoints as a local crease/deviation diagnostic. This is not a maximum surface-distance metric and is not an approved geometry tolerance. Canonical surface displacement/error remains `NOT_FULLY_MEASURED`; no product-quality claim follows from satisfying topology, cutoff, controls, rays or volume checks. A path counts only if owner sets match and its two segments lie in the two replacement triangles. All unmatched arcs, orientation conflicts, cutoff faces, topology defects or invalid controls fail closed.

Because no equal-LOD candidate has yet passed, C5 is an equal-LOD face-owned experiment. Mixed LOD and later qualification gates remain conditional on equal-LOD + controls + ROI rays + volume passing. If those gates pass, the campaign must implement and execute the frozen conforming interface ownership/correspondence gate before any PASS classification; a `NOT_RUN` value cannot be promoted.

### C5 result

C5 `C5_FACE_OWNED_NONCOPLANAR_LOCAL_PATCH` executed once as `C5GEO001` on source `40ee966d1cda2ccf5ef42f5e747083d022849fbc` (parent `95d8477cd180fd760571643859d024f63361b41d`, tree `59d18abac9aa69d592c816028d35f790521e50d3`). Campaign and realizer physical SHA-256 values were `c2ea5a8b9d231ff149fc8929514c74c9322fcc621528e3cc9ce174bc1d34e48f` and `0c053bee8709609e69e880aa9ff264b6c88735ff52f7ca097eebbc9e3f1c471f`; fixture SHA remained `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`. The artifact SHA-256 is `401741531a75b7129005120bf3ac67aa5cd74efda02fc48f8dea1c9a045f17e1`. Godot process exit was 0, no runtime errors, and terminal classification was `FAILED_TARGET`; C5 was not rerun.

C5 retained 369 anchors, 870 arcs and 502 faces. It applied four flips and rejected 35 candidates: 22 replacement-cutoff failures, nine patches with more than two source faces, and four orientation conflicts. The four remaining cutoff faces have `cross_squared` values `8.90332212726756e-17`, `2.77538984903934e-15`, `1.11996851137781e-13`, and `6.55420975739091e-13`; the fixed cutoff remains `1e-12`. Minimum cross-squared is `8.90332212726756e-17`. Topology round-trip remains exact (`a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9`), realization-map SHA is `96d710211a630bb1105fc20598fae2225a7d8fb58e73fc95704358df60bb48e3`, internal opens/missing obligations/nonmanifold/winding are 0/0/0/0, and the four remaining sub-cutoff faces are degenerate. Controls passed 6/6, ROI rays were 0/25, global ray diagnostic 9/25, and volume identity passed. The largest old-versus-new diagonal-midpoint displacement among the four applied flips was `0.131427302956581`; this local diagnostic is not a surface-error bound. Canonical surface deviation was not fully measured. The failed invariant was `fixed_cutoff`; mixed LOD and all downstream gates were not run.

### C6 — bounded multi-face noncoplanar patch ownership (preregistered)

C5 directly identified nine rejected local proposals whose accumulated source-triangle ownership set exceeded two faces. C6 tests that single structural limitation by allowing a bounded 2–2 flip patch to span two or more source polygons, while keeping all C5 geometric predicates: finite coordinates/diagnostics, convex opposite-side test, no existing alternate diagonal, orientation agreement with every source face, unchanged `cross_squared > 1e-12`, sorted deterministic edge selection, and the same 128-flip cap. It does not change root coordinates, scalar values, volume, or topology authority.

C6 separates (a) the complete sorted patch-face owner set for replacement triangles from (b) the exact source-face owner set of a removed topology arc. The deterministic patch owner is the ordinally first patch polygon. Each replacement triangle records the complete patch owner set; source-face provenance includes every polygon/cell/tetrahedron. The removed arc path record uses only that arc's exact authoritative owner set and corresponding provenance, so expanding a geometric patch cannot silently expand topology-arc ownership. Non-topology diagonals carry full patch provenance. Each flip records the noncoplanarity scalar triple and old/replacement diagonal-midpoint displacement. No surface-error tolerance is introduced.

C6 executes only the frozen equal-LOD target and its existing controls/ray/volume gates. If all equal-LOD gates pass, the preregistered R12 sequence requires a separate conforming mixed-LOD interface realization and its checks before deterministic repeat, full E2E, or full validation. If C6 fails, it is consumed as `FAILED_TARGET`; the six allowed C slots are then exhausted. The result cannot imply mathematical impossibility or product adoption.

## C1–C6 reservation status

C1 is `NOT_APPLICABLE_NO_ELIGIBLE_INTERIOR_DEGREE2_ROOTS` and remains unconsumed. C2, C3, C4, C5 and C6 are consumed as `FAILED_TARGET`, each after a valid frozen-target geometry attempt. No C7 is authorized. The terminal accounting and evidence references are recorded in [campaign results](RESULTS.md) and the [final campaign checkpoint](../../../checkpoints/2026-10-30-P3-1-R12-C-CAMPAIGN-CLOSEOUT.md).

## C6 result and R12-C campaign closeout (2026-10-30)

C6 `C6_MULTIFACE_NONCOPLANAR_PATCH_WITH_SEPARATE_ARC_OWNERSHIP` ran once as `C6GEO001` on source `4535f4c965db67adab7c93e448492c54be916c92` (parent `289feddccc5a71bd8f9d1f5ff66051d8d4140657`, tree `1c8af8c4050a7b89976331fa1ad20c666d67e3a8`). Import, check-only and the exact-source frozen input gates passed. The process produced a complete geometry artifact; no retry occurred. It is consumed as `FAILED_TARGET` because three final triangles remain at or below the unchanged `cross_squared > 1e-12` cutoff.

C6 retained 369 anchor roots, 870 topology arcs and 502 source faces; it applied five bounded noncoplanar flips and rejected 27 candidates (18 replacement-cutoff failures, five source-face orientation conflicts, and four opposite-side failures). It emitted 662 triangles. Required topology round-trip matched exactly; 0 internal open edges, 0 missing obligations, 0 nonmanifold edges and 0 winding inconsistencies were observed, but 3 sub-cutoff/degenerate faces remained and minimum cross-squared was `2.77538984903934e-15`. All six controls passed; ROI ray disagreements were 0/25; frozen volume, payload and revision-2 reload identity passed. Global ray diagnostic remained 9/25 and was not the frozen ROI gate. Maximum old-versus-new diagonal-midpoint displacement was `0.125083565711975` world units; canonical surface deviation remains incompletely measured and no geometric tolerance is approved.

The full attempt matrix, earlier C2–C6 tool/preflight failures, source and result hashes, process observations, gate disposition and limitations are in [RESULTS.md](RESULTS.md). Raw evidence is preserved in the indexed archive under `evidence/`; the index covers 311 raw files. The archive and index SHA-256 values are `6550788363d1e0ea23df7ed2f560dbf0558fb6c45d769dc642661516c39b4dcb` and `a876444ef103cd7288894fb35066d1f501a61eb5dc45beaead14d94e6145e2a9`.

Final status: `P3_1_R12_C_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`. Equal-LOD failed, so mixed-LOD, deterministic-repeat, full-E2E and `scripts/validate.ps1` gates were not run. This finite campaign does not establish mathematical impossibility, production readiness, or a product geometry acceptance threshold. No production files, schemas, saves, PRs #207–#209, or protected F2-G1 state were modified; all five F2-G1 holds remain unchanged.

## Safety and interpretation

Only this experimental branch/worktree is mutable. No production code or schemas, user saves, prior PRs, or F2-G1 protected state are touched. Headless metrics are UNSCORED and are not presented FPS/GPU evidence. A failure is evidence about this finite hypothesis only; no result proves global infeasibility.
