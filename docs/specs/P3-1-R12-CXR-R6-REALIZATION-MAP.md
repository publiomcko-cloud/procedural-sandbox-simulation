# P3.1 R12-CXR R6 — realization map and cavity realizability

**Status:** owner-authorized experimental campaign, Issue #218; test-only. No production geometry, saves, schemas, release or architecture adoption is authorized.

## Frozen baseline

- R5 measured source: `8e5211e0665b6f57839d5c7eeae51c28c64325f6`.
- R5 publication head: `64a14d7bc8ddf024933129767b6889146d4645c4` (parent `544dd4595b78979f3e7bd7c011959ae324b131e6`).
- Candidate D source SHA-256: `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`.
- Manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.
- Topology fixture / topology / graph: `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d` / `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95` / `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9`.
- Materialized volume / payload / revision: `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` / `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0` / 2.
- Frozen R5 cavity SHA-256: `a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6`.
- Frozen target: `R9.2.SEAM.XPLUS_EQUAL.v1`.
- Cutoff remains `cross_squared > 1e-12`; residual and barycentric epsilons remain `1e-7`.

Candidate D, all materialized scalar samples, topology authority and root/arc identities, volume and payload identity, ROI oracle, controls, production source, save/schema state and prior evidence are immutable inputs. Offline R5 blocker measurements are hypotheses to reproduce; they are not Godot evidence.

## R6-D0 diagnostic contract

Run only after an exact-source Godot import and check-only preflight. D0 does not consume a scientific target attempt.

- **D0-A:** for every tetra zero-facet vertex, record tetra/cell identity, world binary32 bytes, first deterministic construction edge and interpolation parameter, recomputed tetra barycentric weights and frozen-field residual. Include occurrence and unique-position counts, complete residual histogram, and count above `1e-7`.
- **D0-B:** project the exact frozen cavity and the two seed owner triangles to the frozen cavity basis. Measure polygon intersection area for each owner. Mark seed-only ownership incompatible only when no owner has positive-area interior overlap.
- **D0-C:** for each direct-arc subregion `R015`, `R145`, `R124`, `R234`, clip every triangulated tetra zero facet against that subregion. For every subregion edge, evaluate the convex quadratic cross-squared objective at every extreme point of every clipped polygon. Preserve the full extreme-point table, edge maxima and frozen cutoff margins.
- **D0-D:** for all six exposed cavity boundary edges, use the adjacent subregion and the same complete clipped zero-set enumeration. Record a strict interior field-derived third-point witness above cutoff or the complete continuous upper bound. An upper bound at or below cutoff yields `GEOMETRICALLY_UNREALIZABLE_BOUNDARY_EDGES` for that frozen cavity; it does not establish global impossibility.

Any input hash, materialized volume identity, topology identity or frozen cavity mismatch is a hard D0 preflight failure. Report the raw process, source SHA, exit, stdout/stderr, result hash and resource sample. D0 completion keeps R6 target attempts used at zero.

## Corrections

### R6-A — binary32 zero-set provenance

Carry tetra barycentric weights through every affine zero-facet construction. Reconstruct the binary32 coordinate and recompute the frozen field residual. If it fails, deterministically select the representable same-tetra point minimizing absolute residual within an initial bound of ±2 ULP per coordinate. Re-run the original residual and barycentric gates unchanged. Record before/after positions and residuals, coordinate ULP steps, weights, facet, and reason. No arbitrary projection or epsilon change.

### R6-B — geometry ownership

Keep canonical topology provenance unchanged. Give every accepted replacement triangle exactly one geometry owner chosen from the removed patch: containing face first, then 3D centroid distance, then stable face and triangle IDs. Preserve source polygon/face provenance and deterministic tie-break evidence.

### R6-C — topology realization paths

Keep each canonical topology arc ID, endpoints, expected incidence and source provenance. Realize geometry as an ordered mesh-edge path between the exact unchanged roots, with only derived interior vertices. Require in-domain paths, all segments in the candidate mesh, no unintended intersections, merges, branching or topology collapse. Use `ANCHOR_EDGE` for a valid direct edge and `PIECEWISE_PATH` when needed. Hash the full path and prove topology round-trip.

### R6-D — manifold and boundary-realizable cavity search

Start from the R4 six-face cavity. A candidate cavity must have a manifold boundary, deterministic boundary cycles, at least one feasible incident replacement triangle for every boundary edge, and topology realization paths that can enter/leave without impossible straight barriers. Expand only by causally adjacent surviving faces across unrealizable boundary edges.

Best-first ordering is lexicographic: fewer removed faces; fewer unrealizable edges; larger minimum feasible boundary-edge cross-squared margin; fewer boundary components; stable face-ID sequence.

Frozen resource limits before the first cavity search:

| Search resource | Bound | On bound |
| --- | ---: | --- |
| Total removed faces | 12 | `PARTIAL` |
| Visited cavity states | 10,000 | `PARTIAL` |
| Priority queue entries | 2,000 | `PARTIAL` |
| Wall time | 30,000 ms | `PARTIAL` |

Reaching a limit never implies infeasibility. The finite search domain and terminal reason must be recorded.

### R6-E — support synthesis

Begin only after a manifold boundary-realizable cavity is frozen. Reuse the R5 constraint-guided synthesis structure with R6-A provenance correction. Keep a support only if it passes unchanged field-residual and barycentric gates, lies in the chosen cavity, has deterministic patch ownership where applicable, and contributes to a legal mesh edge or topology path. No broad point cloud retention.

### R6-F — constrained triangulation

Consume patch owners, topology paths and the selected realizable cavity. Require exact cavity coverage, boundary edge incidence 1, internal edge incidence 2, zero opens, nonmanifold edges, winding errors, cutoff rejects, intersections and T-junctions, plus exact topology realization round-trip.

## Target attempts and gates

Authorize up to five valid scientific R6 target attempts. D0 and pre-geometry tooling corrections consume none. Every valid target requires a new pinned source SHA, unique attempt ID, exact input/source hashes, cold import, realizer and R6 check-only gates, contract suites, evidence writer and resource preflight. Never spend an attempt on a simple limit increase. A possibly started target process is never rerun.

Equal-LOD gate: topology realization round-trip PASS; zero missing obligations, internal opens, nonmanifold edges, winding errors, degenerates and cutoff rejects; minimum cross-squared strictly above `1e-12`; unchanged topology roots; volume identity PASS.

After equal-LOD PASS, continue in sequence: controls 6/6; ROI ray oracle 0/25; volume reconfirmation; mixed LOD; deterministic repeat; full E2E; `scripts/validate.ps1`.

No result may elevate source-only or offline numerical observations to Godot runtime, topology acceptance, owner GUI acceptance, release or merge approval. Unknown evidence values are `UNKNOWN_NOT_CAPTURED`.
