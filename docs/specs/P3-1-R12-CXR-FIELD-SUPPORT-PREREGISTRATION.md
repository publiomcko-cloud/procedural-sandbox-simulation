# P3.1 R12-CXR — Field-Constrained Support Micro-Patch Preregistration

Date: 2026-10-31  
Status: preregistered; geometry execution has not started.

## Identity and scope

Repository: `publiomcko-cloud/procedural-sandbox-simulation`  
Experimental branch: `exp/p3-1-r12-cxr-field-support-micropatch`  
Parent stack: draft PR #211 at `209e301fc4576d0b7ef713a1b2ab3f86996f9db3`, itself stacked on draft PR #210.  
Frozen C6 measured source: `4535f4c965db67adab7c93e448492c54be916c92`.  
R12-CX source/reference: `a9c1353db49a7bb5607ce8eaf91d8032c7dc4bea`.

This is the corrected execution of the original CX hypothesis. It is not C7, a new architecture family, production integration, geometry-contract adoption, or authorization for Issues #108/#154. R12-CXR may modify only test-only experiment code and its documentation/evidence. Frozen C6 topology authority, original root coordinates, Candidate D field and volume, residual fixture, cutoff, controls, ROI ray oracle, and all pins remain unchanged.

The prior CX attempt exercised edge-flip search with support candidate and support selection caps equal to zero. It therefore failed to test the field-constrained-support core. This preregistration corrects that omission. Prior attempts and evidence remain immutable.

## Frozen inputs and required invariants

- Topology authority: 369 roots, 870 arcs, 502 source faces.
- C6 topology round-trip, root coordinates and face/arc ownership must be exact.
- Frozen C6 artifact, residual fixture and Candidate D volume hashes are checked before target execution. No fixture is regenerated or repinned to accommodate a result.
- Three residual faces grouped into two cavities; each support is geometry derived from the pinned Candidate D piecewise-linear tetrahedral field and is never topology authority.
- Final triangles must satisfy strict `cross_squared > 1e-12`; no cutoff or topology tolerance is relaxed.
- The cavity boundary and all topology roots/arcs/owners remain preserved. Candidate supports may not replace, rename, move or become authority for frozen roots.
- No unapproved surface displacement tolerance is introduced; geometric residuals/displacements are reported diagnostically and the frozen acceptance gates remain controlling.

## Deterministic field-constrained candidate method

For each cavity at levels L0 through L3, enumerate the bounded source tetrahedra intersecting the residual/cavity domain expanded by that level, using the frozen `Core.GRID_CORNERS`, `Core.TETS`, and exact pinned `PackedFloat32Array` samples. Enumerate tetrahedra by signed global cell coordinate then tetrahedron index.

Generate candidates from (a) exact linear zero crossings on the six tetrahedron edges and deterministic pairwise/interior points on the resulting piecewise-linear zero polygon, and (b) bounded orthogonal projection of fixed residual-root, residual-edge-midpoint, and residual-face-centroid seeds onto that tetrahedron's four-sample linear zero plane. Projection candidates are accepted only when their tetrahedral barycentric coordinates lie in the closed tetrahedron and the recomputed interpolated scalar residual is finite and within the preregistered arithmetic verification bound `1e-7` in the frozen field's stored units. These are field intersections/projections, not unconstrained centroid insertion. A projected point must also be within `0.5` world units of its residual face and distinct from every topology root.

Candidate provenance records the residual/cavity ID, LOD level, signed cell, tetrahedron, four exact sample values, construction method, seed, projection factor or edge parameter, barycentric weights, field residual, world coordinate and stable candidate ID. Rejected candidates retain their first rejection reason. Deduplication uses exact binary32 coordinate identity; candidate sorting uses squared distance to the residual face centroid, then signed cell coordinates, tetrahedron, method, seed index, and stable ID. This ordering is frozen before search.

A selected support replaces only its associated rejected face with a deterministic oriented three-triangle fan over that face's original root boundary. The face's three root-root boundary edges are preserved. If the candidate fan fails the fixed cutoff, winding, local incidence, boundary, intersection, or topology checks, record the rejection and continue within the finite domain. A solution is valid only after whole-mesh validation; it is not accepted merely because the local fan is valid.

## Finite stop-loss limits (fixed before geometry)

| Resource | Limit |
|---|---:|
| Residual cavities | 3 (frozen observed count is 2) |
| Cavity expansion | L0–L3 |
| Source triangles per cavity | 64 |
| Field-derived candidates retained per cavity | 96 |
| Selected support vertices total | 4 |
| Candidate fan triangles tested per cavity | 1,024 |
| Search states per cavity | 16,384 |
| Search states total | 32,768 |
| Solutions retained per cavity | 32 |
| Local search wall time per cavity | 10,000,000 µs |
| Local search wall time total | 20,000,000 µs |
| Complete realizer wall time | 30,000,000 µs |
| Memory safety guard | warn below 3 GiB free commit; abort before geometry below 2 GiB; monitor during target and abort at 2 GiB |

Any cap, deadline, or resource guard hit yields `PARTIAL`; it never becomes proof of local-domain infeasibility. A failed preflight is pregeometry and does not consume the target. Once the target emits its local-search-start marker and terminal result, that R12-CXR geometry attempt is consumed exactly once. No rerun or additional hypothesis is automatic.

Search explores all candidate combinations in deterministic order up to the declared state/time bounds, scores complete valid solutions lexicographically by maximum minimum `cross_squared`, minimum maximum support displacement, then stable support IDs, and retains at most 32. A successful candidate discovered before a bound is hit may proceed through qualification gates, but the terminal classification remains `PARTIAL` if the search was not complete.

## Evidence contract

The terminal artifact must include, for each cavity: ID, L0–L3 levels attempted, source patch IDs and size, all candidate rows including rejection reasons, support selections, every candidate triangle row and cutoff result, actual search-state count, branches and prune counts by reason, limits hit, search completion/exhaustiveness, terminal reason, retained/selected solution, boundary signature, topology validations and support provenance. Unmeasured quantities use `UNKNOWN_NOT_CAPTURED`, never numeric zero. Evidence serialization failure is a source/evidence hard stop and cannot produce a PASS.

## Sequential qualification gates

Before target: exact source/fixture/hash validation; fresh isolated Godot profile; cold import; campaign check-only; realizer check-only; contract tests. Before search: frozen topology authority, Candidate D volume, residual count, and C6 round-trip must pass.

For equal-LOD, require all simultaneously: exact topology round-trip; missing obligations 0; internal opens 0; nonmanifold 0; winding errors 0; degenerates 0; cutoff rejects 0; minimum cross-squared strictly greater than `1e-12`; exact frozen volume PASS.

Only after equal-LOD PASS, automatically execute in order: controls 6/6; ROI rays with 0/25 disagreements; volume confirmation; frozen conforming mixed-LOD; deterministic repeat; full E2E; `scripts/validate.ps1`. Stop immediately on a failed gate. Preserve all raw output and do not rerun any started target or scenario.

## Classification and exclusions

Use only: `R12_CXR_EXPERIMENTAL_TARGET_PASS`, `R12_CXR_FAILED_TARGET_WITH_EVIDENCE`, `R12_CXR_PARTIAL_WITH_EVIDENCE`, `R12_CXR_RESOURCE_SAFETY_HARD_STOP`, `R12_CXR_SOURCE_OR_EVIDENCE_INTEGRITY_HARD_STOP`.

No production adoption, merge, release, GUI acceptance, Issue #108/#154, native component, save/schema modification, or F2-G1 operation is authorized. Preserve all five protected-state holds.