# P3.1 R12-C C4 result and C5 preregistration

Date: 2026-10-30
Branch: `exp/p3-1-r12-c-topology-geometry-realization`
C4 source: `01856f529df0a0f8c0bf62be5684d86fd923d071`
Parent: `db130481d79b5ad88fc3e705695bb1530cfadd61`
Tree: `1b361cd8ab0fc4502605956710560abc81939d6e`

## C4 immutable execution

C4 `C4_EXACT_COPLANAR_LOCAL_2TO2_PATCH` was executed once as `C4GEO001`. Campaign and realizer physical SHA-256 values were `a904b9aca601473f1aab152fb8c2b43b71e252bd92c2ac245ee899962206e70c` and `1dcdf7d1374d95d05dce488d5fc91e577ed26f8926dce5818300d8080146017e`. The fixture SHA remained `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`. The result artifact `r12c_C4_C4GEO001.json` has SHA-256 `8cd8de0e49016b8cbfe8014d0372047295f6641a9cceb364f80068262d2edc1e`.

| Measure | C4 result |
|---|---:|
| Roots/anchors / arcs / faces | 369 / 369 / 870 / 502 |
| Initial and final source-cycle triangles | 662 / 662 |
| Initial and final cutoff rejects | 8 / 8 |
| Flip candidates rejected / applied | 18 / 0 |
| Rejection reason | `source_roots_not_exactly_coplanar` for all 18 |
| Minimum `cross_squared` | `8.90332212726756e-17` |
| Internal opens / missing obligations | 0 / 0 |
| Nonmanifold / winding / sub-cutoff (degenerate) faces | 0 / 0 / 8 |
| Topology round-trip | exact match; SHA `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9` |
| Realization-map SHA | `7c713782d0de575bc73a8fe8d5f955e5d5b4c6e022d40fcaee091fe056528e28` |
| Controls | 6/6 PASS |
| ROI rays | 0/25 disagreements |
| Global ray diagnostic | 9/25, diagnostic only |
| Volume identity | PASS |
| Result | `FAILED_TARGET`, first invariant `fixed_cutoff` |

The valid process completed with exit 0 and no runtime errors. A prior check-only on source `db130481d79b5ad88fc3e705695bb1530cfadd61` failed before geometry due duplicate inherited constants; those source-only errors were removed in the measured source. C4 was not rerun after its valid attempt.

## C5 preregistration

ID: `C5_FACE_OWNED_NONCOPLANAR_LOCAL_PATCH`.

C4 showed that every one of 18 repair candidates touching the eight cutoff faces failed its exact-coplanarity predicate. C5 therefore retains C4's bounded face-owned 2–2 local patch algorithm, source roots, sorted edge visitation, convexity and distinct-vertex checks, unchanged cutoff, orientation checks, path-to-arc coverage and 128-flip cap, but permits finite nonzero scalar triple products when replacement triangles remain consistently oriented to both source faces and individually pass the cutoff.

Each patch owner is the ordinally first source polygon ID. Both replacement faces record the full owner set and source polygon/cell/tetra provenance. A removed source arc is represented by its deterministic path through the midpoint of the replacement diagonal, with both path segments tied to replacement triangle IDs. Every flip records the scalar triple product and the old-versus-new diagonal midpoint distance. This is only a local deviation diagnostic, not a maximum surface-error measure or an approved tolerance. Canonical surface deviation is `NOT_FULLY_MEASURED`, and no product geometry-quality claim is permitted.

C5 runs equal-LOD target, six controls, ROI rays and volume. If those gates pass, mixed LOD must be explicitly implemented and executed before a campaign PASS; `NOT_RUN` is never acceptance. A valid failed geometry result consumes C5; pre-geometry tooling faults do not. No source or geometry tolerance may be tuned after execution.

## Campaign accounting

C1: not applicable, unconsumed.
C2/C3/C4: consumed `FAILED_TARGET`.
C5: preregistered, not yet implemented/executed.
C6: unused; preregistration required.
C7: not authorized.

No production code, schema, save, PR #207–#209, or F2-G1 state changed. All five protected-state holds remain unchanged.
