# P3.1 R12-C C5 result and C6 preregistration

Date: 2026-10-30
Branch: `exp/p3-1-r12-c-topology-geometry-realization`
C5 source: `40ee966d1cda2ccf5ef42f5e747083d022849fbc`
Parent: `95d8477cd180fd760571643859d024f63361b41d`
Tree: `59d18abac9aa69d592c816028d35f790521e50d3`

## C5 immutable execution

C5 `C5_FACE_OWNED_NONCOPLANAR_LOCAL_PATCH` was executed once as `C5GEO001`. Import and `check-c5` passed; the geometry process exited 0 with no runtime errors. Campaign and realizer physical SHA-256 values were `c2ea5a8b9d231ff149fc8929514c74c9322fcc621528e3cc9ce174bc1d34e48f` and `0c053bee8709609e69e880aa9ff264b6c88735ff52f7ca097eebbc9e3f1c471f`. Fixture SHA remained `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`. Result artifact `r12c_C5_C5GEO001.json` SHA-256 is `401741531a75b7129005120bf3ac67aa5cd74efda02fc48f8dea1c9a045f17e1`.

| Measure | C5 result |
|---|---:|
| Roots/anchors / arcs / faces | 369 / 369 / 870 / 502 |
| Triangles | 662 |
| Noncoplanar flips applied | 4 |
| Flip candidates rejected | 35: 22 cutoff, 9 owner-count, 4 orientation |
| Remaining cutoff rejections | 4 |
| Remaining `cross_squared` | `8.90332212726756e-17`, `2.77538984903934e-15`, `1.11996851137781e-13`, `6.55420975739091e-13` |
| Internal opens / missing obligations | 0 / 0 |
| Nonmanifold / winding / degenerate faces | 0 / 0 / 4 |
| Topology round-trip | exact match; SHA `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9` |
| Realization-map SHA | `96d710211a630bb1105fc20598fae2225a7d8fb58e73fc95704358df60bb48e3` |
| Controls / ROI rays / volume | 6/6 / 0 of 25 disagreements / PASS |
| Global ray diagnostic | 9 disagreements; diagnostic only |
| Max diagonal-midpoint displacement | `0.131427302956581` world units; not a surface-error bound |
| Canonical surface deviation | Not fully measured |
| Result | `FAILED_TARGET`, first invariant `fixed_cutoff` |

No mixed-LOD or later gate ran because equal-LOD failed the fixed cutoff. C5 was not rerun.

## C6 preregistration: bounded multi-face noncoplanar patch ownership

C5 reported nine rejected candidates because a patch included more than two source polygons. C6 is a bounded topology/provenance extension: permit a local 2–2 patch over two or more source faces while preserving the source roots, samples, volume, fixed cutoff, convexity, deterministic sorted edge order, per-source-face winding agreement, no-existing-alternate-diagonal check and 128-flip cap.

Replacement triangles carry the full sorted patch-face owner set; the patch owner is its ordinally first polygon. The provenance map includes each patch polygon, source cell and tetrahedron. For a removed authoritative topology arc, keep its exact topology owner set distinct from the wider patch owner set; record the arc path and provenance only against its canonical owners. Non-topology diagonals retain full patch provenance. Record the scalar triple product and old-versus-new diagonal-midpoint displacement for each flip. No canonical surface-error bound or owner-approved tolerance is claimed.

C6 runs the frozen equal-LOD target and existing six controls, ROI rays and volume checks. If equal-LOD gates pass, the separate conforming mixed-LOD interface gate must run next; deterministic repeat, full E2E and full `scripts/validate.ps1` remain conditional on the earlier gates. If C6 fails, all six C slots have been validly consumed (C1 remains not applicable and unconsumed), and the campaign closes as attempts exhausted without claiming impossibility.

## Campaign accounting

C1: not applicable, unconsumed. C2/C3/C4/C5: `FAILED_TARGET`. C6: preregistered, not yet implemented/executed. No C7 is authorized. All previous result artifacts remain immutable. No production code, schema, save, other PR or F2-G1 state changed; the five holds remain unchanged.
