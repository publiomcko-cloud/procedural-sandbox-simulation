# P3.1 R12-C C3 result and C4 preregistration

Date: 2026-10-30  
Branch: `exp/p3-1-r12-c-topology-geometry-realization`  
C3 source: `e9bc9637a9aeadefc4385959c7ff2cf786c35997`  
Parent: `1edb73316876e20a20367c4c88de8b20689eb8f5`  
Tree: `ffc460cf507f083ce8cd6f62e39074ac2f6973ee`

## C3 immutable execution

`C3_FIELD_CONSTRAINED_SUPPORT_FAN` was executed once as `C3GEO001`. The campaign physical SHA-256 was `e2981b34f2cdbf101bfe71840dffba2f2e31ac21a91fd868342c8ad9a64e7926`; the realizer SHA-256 was `8b8e818feec87daddb7a90ae2ee45a9e91357aa368828485254f017cd848b7d2`. The Stage 0 topology fixture remained pinned at `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`. Godot import, check-only and the single geometry attempt completed without parser/runtime errors. The process exit code was 0. The exact process record, stdout, stderr and monitor samples are in the unique evidence directory listed below.

| Measure | C3 result |
|---|---:|
| Anchors / topology roots | 369 / 369 |
| Topology arcs / source faces | 870 / 502 |
| Geometry-only support vertices | 502 |
| Emitted triangles | 1,621 |
| Fixed-cutoff rejected triangles | 45 |
| Missing topology obligations | 33 |
| Internal open edges | 20 |
| Nonmanifold / winding inconsistencies / emitted degeneracies | 0 / 0 / 0 |
| Minimum accepted `cross_squared` | `2.48140180278411e-12` |
| Topology round-trip match | true; `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9` |
| Realization-map SHA-256 | `fbe6e385738b86e4a54490ef5c8768bd682e2199eb450c3db892ba7786fb9518` |
| Support-map SHA-256 | `89217712cd60a5d9a22c00ff2b1a9924318aceb17892873317e8ce221c816cf9` |
| ROI rays | 0/25 disagreements |
| Global ray diagnostic | 9/25 disagreements; diagnostic only |
| Controls | 4/6; neighbor-pair and X_NEG realizer failures, causes UNKNOWN |
| Frozen volume identity | PASS; SHA/payload/revision 2/reload identity |
| Result | `FAILED_TARGET`, first invariant `fixed_cutoff` |

Support scalar residuals are stored per face and ranged from `-6.65474999550497e-7` to `5.66350110808855e-7`. No tolerance is inferred. The result artifact is `r12c_C3_C3GEO001.json`, SHA-256 `81b01ce3f41c6dcbf37965429fc39d54316c8c947a6d88faff4efe7eda8ac80a`.

The C3 control summary omitted nested realizer details for two failures. This is retained as an observability defect and is not retroactively classified as a C3 hypothesis failure cause. The ROI variant wiring was independently corrected in the C3 campaign; the cause of these two C3 realizer failures is still unknown. C4 must capture the full realizer result for every control.

Evidence root: `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r12c_20261030_0a53ac9c6d5245f4a4faffb14089c8be`.

## C4 preregistration

ID: `C4_EXACT_COPLANAR_LOCAL_2TO2_PATCH`.

C3's centroid fan made the small-face cutoff problem worse. C4 will reconstruct deterministic source-face triangles before filtering, retain every source root as an anchor, and attempt at most 128 deterministic 2–2 flips, in lexicographically sorted shared-edge order. It may flip only an edge incident to a sub-cutoff working triangle when exactly two triangles share the edge, the four vertices are distinct, the alternate diagonal is absent, opposite vertices lie on opposite sides, all four source-root coordinates are exactly coplanar (`scalar triple product == 0.0`, no epsilon), both replacement triangles pass `cross_squared > 1e-12`, and both replacement orientations agree with the source faces. No sample or vertex moves.

If a source topology arc is removed as the flipped diagonal, C4 records a deterministic path through the midpoint of the replacement diagonal, with source polygon/cell/tetra ownership and segment-to-triangle evidence. It is covered only when both path segments lie in the replacement triangles. Every other arc must correspond to an emitted mesh edge. C4 reports all eligible/rejected/applied flips, nested control diagnostics, path coverage, cutoff counts, topology, rays, volume and source provenance. Exact coplanarity can make the strategy inapplicable; no approximate pass or post-result tolerance is authorized.

C4 gates remain the R12-C frozen equal-LOD target, six controls, 25 ROI rays, volume identity and exact topology realization. A completed failed result consumes C4 as `FAILED_TARGET`; tooling failure before geometry does not. Mixed LOD, determinism, E2E and full validation remain conditional on all preceding required gates passing.

## Campaign accounting

C1: `NOT_APPLICABLE_NO_ELIGIBLE_INTERIOR_DEGREE2_ROOTS`, unconsumed.  
C2: consumed `FAILED_TARGET`; preserved, not rerun.  
C3: consumed `FAILED_TARGET`; preserved, not rerun.  
C4: preregistered, not yet implemented or executed.  
C5/C6: unused; evidence-directed preregistration required before implementation.  
C7: not authorized.

No production path, schema, save, PR #207–#209, or F2-G1 state was modified. All five protected-state holds remain unchanged.
