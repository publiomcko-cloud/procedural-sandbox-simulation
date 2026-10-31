# P3.1 R12-C — C2 Result and C3 Preregistration

Date: 2026-10-30

Repository: `publiomcko-cloud/procedural-sandbox-simulation`

Branch: `exp/p3-1-r12-c-topology-geometry-realization`

Evidence root: `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r12c_20261030_0a53ac9c6d5245f4a4faffb14089c8be`

## Scope and preserved gates

This checkpoint records the one valid C2 execution and preregisters C3 before implementation. The branch remains an isolated test-only experiment based on final R10-BX evidence PR #209. No production paths, saves, storage schemas, Issues #108/#154, or PRs #207–#209 were modified. All five F2-G1 holds remain unchanged.

## C2 identity and pinned inputs

- C2 hypothesis source: `f5b421a0f0e4a020a7fc1a8d00847a8e32f93234`
- Direct parent: `d936203c5b769c0c022699d6ad5fad12a85b6e40`
- Tree: `27f21a7279bde20f08a7141ff03f729e4599bb29`
- Campaign source SHA-256: `36a7ae8e13a932b429e3a251bcf68204b1497019638ae83cc1dd558dacc40286`
- C2 realizer source SHA-256: `656e558eefbf5b3cdada663c8252843bbcf391a568127c240a92bc01f430edb8`
- Godot 4.7.2 executable SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`
- Candidate D SHA-256: `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`
- R9.2 manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`
- Candidate-domain SHA-256: `30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22`
- Stage 0 fixture SHA-256: `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`
- Source topology authority SHA-256: `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`
- Parsed fixture graph fingerprint SHA-256: `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9`
- Volume / payload SHA-256: `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` / `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`, revision 2
- Fixed triangle cutoff: `cross_squared > 1e-12`

## C2 execution result

Attempt `C2GEO006` reached `R12C_GEOMETRY_BEGIN`, executed the frozen `R9.2.SEAM.XPLUS_EQUAL.v1` target exactly once, and emitted a complete machine-readable result. It is consumed as `FAILED_TARGET`; no rerun is authorized or performed.

Raw result: `r12c_C2_C2GEO006.json`, SHA-256 `469be6d2b18c52cdb6bece2db378de1f8d6a81dd27aaa10fd47c652d3b8ecf25`. The JSONL-style completion marker was captured in `C2GEO006_geometry/stdout.txt`; process evidence is preserved under the same evidence root.

| Measure | Result |
|---|---:|
| Roots / anchors | 369 / 369 |
| Topology arcs / source faces | 870 / 502 |
| Path events / support vertices | 0 / 0 |
| Realization map SHA-256 | `64cddc36dce07dc71fe09f7eaab12909c6140ba956a1bc1fc35c44f645b6a236` |
| Topology round-trip SHA-256 / match | `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9` / true |
| Geometry triangles | 654 |
| Minimum accepted cross-squared | `1.34662257473411e-12` |
| Fixed-cutoff rejected triangles | 8 |
| Missing required topology arc incidences | 19 |
| Internal open edges | 13 |
| Nonmanifold / winding inconsistencies / degenerates | 0 / 0 / 0 |
| Controls | 4/6; negative X and Z variants failed setup |
| ROI rays | 0/25 disagreements |
| Target volume identity | pass; frozen volume/payload/revision reproduced |
| Mixed LOD / determinism / full E2E / full validation | not run; equal-LOD gate failed |
| Result class / failed invariant | `FAILED_TARGET` / `fixed_cutoff` |

All eight rejected polygons had three roots. Their rejected `cross_squared` values are present in the raw JSON. The failure is specific to direct per-face anchor-cycle triangulation under this cutoff; it does not establish global infeasibility.

### Preserved control harness defect

The four positive controls passed. Both negative-region variants logged Godot `SCRIPT ERROR` because the C2 helper configured Candidate D using a missing parent-row ROI rather than the explicit negative variant ROI. This is a harness error, not a geometry result for those controls. The C2 result remains FAILED_TARGET based on its completed target geometry, but the 6/6 control gate is explicitly not passed. The C3 campaign must pass each variant ROI into volume construction and the process wrapper must record/fail closed on runtime errors even if Godot exits zero.

## Pre-geometry recovery attempts

`C2GEO001`–`C2GEO005` are preserved as unique attempts. Each terminated before `R12C_GEOMETRY_BEGIN` and did not consume the C2 slot. Causes included graph fingerprint versus authority hash conflation, lookup of `materialized_volume_identity_preserved` at the wrong level, JSON serialization normalization, and strict integer/float Variant comparison. Exact outputs remain in the evidence root. A further host-side parent-argument typo was rejected by the runner before attempt-directory/process creation and created no scenario evidence.

## C3 preregistration

`C3_FIELD_CONSTRAINED_SUPPORT_FAN` will retain every topology root as an anchor and add exactly one derived geometry-only support vertex at the centroid of each ordered source polygon. Each triangle/quad face will be fanned to that support, preserving every original root-root arc as a mesh edge with the source incidence. Support rows will record stable ID, source polygon/cell/tetra, field provenance, tetrahedral barycentric weights, interpolated scalar residual, adjacent arcs, and insertion rationale.

The support is the arithmetic centroid of roots of one Candidate D tetrahedral zero polygon; it is therefore a convex combination on the same piecewise-linear zero face. No scalar sample, root, field, cutoff or product geometry tolerance changes. No support is a topology root. C3 is bounded to 502 supports and 2,008 triangles, keeps all original fixed controls, 25 ROI rays and volume checks, and uses the existing ten-minute / 2-GiB free-commit stop-loss. A fan triangle at or below `1e-12` is rejected; incomplete incidence or topology is a failure, never silently omitted. Because an interior support cannot enlarge a rejected triangle, C3 may worsen the cutoff outcome; it remains a distinct, evidence-directed test of the required support-map architecture.

The C3 implementation and physical hashes are not yet present in this checkpoint. They must be pinned after implementation, followed by cold import, check-only, contract tests, then one C3 target attempt. No mixed-LOD or later gate runs unless equal LOD, six controls, ROI rays and volume all pass.

## Remaining campaign state

- C1: `NOT_APPLICABLE_NO_ELIGIBLE_INTERIOR_DEGREE2_ROOTS`, not consumed.
- C2: consumed `FAILED_TARGET`.
- C3: preregistered, not implemented/executed.
- C4–C6: unused; each requires separate evidence-directed preregistration.
- Campaign remains open; no full qualification or production adoption is claimed.
