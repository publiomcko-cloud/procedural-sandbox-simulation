# P3.1 R8.2 — Exact Geometry Provenance

**Disposition:** `P3_1_R8_2_READY_FOR_INDEPENDENT_REVIEW`
**Scope:** bounded, test-only provenance investigation. The disposition means the investigation and required validation completed; it does **not** mean any geometry passed acceptance or was adopted.

## Identity and boundaries

| Item | Verified identity |
| --- | --- |
| Repository origin | `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git` |
| R8.2 branch | `bench/p3-1-r8-2-exact-geometry-provenance` |
| Measured source HEAD | `d81f29237d47361139b02849a8215c30424be873` |
| Direct parent | `c331deeaa127d1b0e63e19e6582d5d1796c2fc8f` |
| Ancestor diagnostic source | R8.1 `e4b788f1024015a78c087deec78358969cc72972` |
| Pinned R7.3 geometry source | `7ad45d8c817ecb0f54a8eec058babce65af287db` |
| R8.1 report PR | [#160](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/160), observed open/draft/unmerged at HEAD `d81f29237d47361139b02849a8215c30424be873` |
| Issue | [#161](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/161), observed open |
| Godot | `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643` |

The final R8.2 evidence commit is the commit carrying this report and its checkpoint on the branch; the measured production-source baseline remains `d81f292…`. Only experimental diagnostics, raw evidence and documents were added. No production terrain, marching-tetrahedra implementation, schemas, saves, scenes, dependencies, established geometry thresholds, PR #160, Issue #108, or Issue #154 were changed. The source checkout is isolated at `C:\w82`; the functional development workspace and preserved user state were not used for edits. Generated `.gd.uid` files remain untracked and were not staged.

The original frozen input identities were recomputed by the R8.2 diagnostic:

| Scenario | SHA-256 |
| --- | --- |
| Zero edit | `24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b` |
| One CARVE (`cave_wall_carve`) | `47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411` |
| Ordered FILL then CARVE | `55d45d387bd19829bb38c4e988da25a886765f26cc34e19dd07ed808faa1bd46` |

The diagnostic preflight verified the pinned R8.1 script SHA-256 `191c37dd8d65f31b94c3a356e1e3232e8483fd037de5d4089844429c3795b9be` and recorded source hashes for the SDF, brush state, spatial ownership, grid, marching-tetrahedra mesher, LOD chunk mesher, and transition fixture in `evidence/diag-run-006/phase-01-preflight.json`.

## Findings

### 1. Ordered FILL/CARVE triangle 3103 in cell 712

**Classification:** continuous canonical SDF versus its sampled, tetrahedral piecewise-linear reconstruction, with nonlinear CSG active-branch changes inside the cell. The record's generic `CAUSE_UNRESOLVED` label is conservative: the provenance below establishes this mechanism for the frozen triangle. It is not evidence of a global winding or coordinate-transform defect.

The exact input is the frozen ordered FILL then CARVE case (SHA above), seed `131102026`, generator version 1, region `(0,0)`. Region-local and world coordinates coincide for this case. The commands are:

1. sequence 0, FILL, center `(8, 1.17898154258728, 5.10309219360352)`, radius `0.58`;
2. sequence 1, CARVE, center `(8, 1.17898154258728, 5.92309236526489)`, radius `0.58`.

Triangle 3103 is owned by cell id `712`, cell coordinate `(0,7,5)`, fine subcell `(0,0,0)`, tetrahedron 1 with corner order `[0,1,2,6]`. Its four lattice samples and binary32 density bytes are:

| Tetra corner | World coordinate | Stored density | binary32 bytes |
| --- | --- | ---: | --- |
| 0 | `(8,1.5,5.5)` | `-0.0489068180322647` | `845248bd` |
| 1 | `(8.25,1.5,5.5)` | `+0.00699232332408428` | `dc1fe53b` |
| 2 | `(8.25,1.75,5.5)` | `-0.15898434817791` | `cbcc22be` |
| 6 | `(8.25,1.75,5.75)` | `-0.084919735789299` | `66eaadbd` |

The recorded triangle vertices are `(8.21872806549072,1.5,5.5)`, `(8.25,1.5190190076828,5.51901912689209)`, and `(8.25,1.51053214073181,5.5)`. Independent reconstruction from the same ordered tetrahedron and stored samples reproduced the recorded vertex bit patterns and triangle index. Its squared cross magnitude is `4.64307760239535e-7`, far above the unchanged `1e-12` cutoff. The face normal points toward the tetrahedron's sampled empty side (dot `+0.0000937033` before normalization), so tetrahedral winding is correct for that sampled interpolant.

At the centroid, however, the canonical outward gradient at `h=0.01` has dot `-0.468217521905899` with the emitted face normal. The independently bisected continuous-field roots on the triangle's three crossed edges differ from the emitted linear edge intersections by `0.0143814`, `0.0139514`, and `0.00957143` world units. The ordered CSG winner changes between an endpoint and continuous root on two of those three edges. This local branch movement, combined with linear interpolation from lattice samples, explains why a correctly oriented piecewise-linear tetrahedron facet can oppose the continuous-field gradient. The world-coordinate mapping is identity here, all sampled values match the canonical evaluator before packing, and independent reconstruction agrees with the mesh. No threshold or geometry contract was changed.

Raw traces: `evidence/diag-run-006/phase-02-triangle_baseline.json` and `phase-03-triangle_3103_provenance.json`.

### 2. X+ interface at world `x=16`

**Classification:** genuine transition-mesh asymmetry caused by the existing small-triangle cutoff interacting with different interior tetrahedral sample locations. The face contour oracle is not the source of the discrepancy.

For frozen ordered FILL/CARVE, the negative-side LOD1 / positive-side LOD0 interface contains `33/35` contour segments. The negative-side LOD1 / positive-side LOD1 interface also contains `33/35`; the opposite LOD0/LOD1 orientation is a passing `35/35` control. All `533/533` shared scalar probes on the face are bitwise equal, with maximum density difference zero.

At the relevant negative-side transition cell, lattice origin `(30,4,14)` corresponds to world origin `(15,2,7)`, selected face id `1` (`X_POS`), and center `(15.5,2.5,7.5)`, whose sampled density is `+0.757994132041931`. An independent face oracle uses two explicitly specified fine-face triangles, without calling `interface_triangles` or `_boundary_triangles` to construct its expected contour:

| Face triangle vertices | Canonical sample densities | Required piecewise-linear contour |
| --- | --- | --- |
| `(16,2,7)`, `(16,2.5,7)`, `(16,2.5,7.5)` | `-0.00128452301025395`, `+0.39888747215271`, `+0.705813961029053` | `(16,2.00160503387451,7)` to `(16,2.00090837478638,7.00090837478638)` |
| `(16,2,7)`, `(16,2.5,7.5)`, `(16,2,7.5)` | `-0.00128452301025395`, `+0.705813961029053`, `+0.402060823440552` | `(16,2.00090837478638,7.00090837478638)` to `(16,2,7.00159215927124)` |

The binary32 density bytes for the unique face samples are respectively `715da8ba`, `fb3acc3e`, `39b0343f`, and `ebdacd3e`. The manual oracle's two segment keys are present in both positive-side LOD0 and positive-side LOD1 meshes and absent from the negative-side LOD1 transition mesh. The focused transition cell contains 4 triangles, but its extracted `x=16` contour has zero segments. Two expected fan facets are independently reconstructed and rejected by the unchanged cutoff:

| Rejected triangle vertices | squared cross magnitude | Cutoff |
| --- | ---: | ---: |
| `(15.9991540908813,2.00084590911865,7.00084590911865)`, `(16,2.00160503387451,7)`, `(16,2.00090837478638,7.00090837478638)` | `9.47780916249474e-13` | `<= 1e-12` |
| `(15.9991540908813,2.00084590911865,7.00084590911865)`, `(16,2.00090837478638,7.00090837478638)`, `(16,2,7.00159215927124)` | `9.34902979685126e-13` | `<= 1e-12` |

On the positive LOD0 side, source triangles 675 and 676 in region `(1,0)`, chunk `(0,2)`, cell `(0,8,2)`, tetrahedra 3 and 4 respectively, contain the same required interface segments; their squared cross magnitudes are `1.24502296493245e-12` and `1.22812448145188e-12`, just above that same cutoff. Full chunk position-array rebuilds match bitwise on both sides. This rules out wrong ownership, coordinate reconstruction, differing face scalar inputs, and an oracle-only mismatch for this frozen contour. The transition center/fan creates a small facet on one side while the neighboring extraction creates a facet just above the omission threshold. This is a real missing-interface geometry defect. No cutoff change or corrective prototype was attempted.

Raw traces: `evidence/diag-run-006/phase-04-xplus_baseline.json`, `phase-05-xplus_source_provenance.json`, and the independent explicit-coordinate face oracle in `evidence/diag-run-011/xplus-face-oracle.json`.

### 3. X− ray / mesh offset

**Classification:** coarse spatial sampling and tetrahedral linear interpolation of a nonlinear canonical field. Not picker error, region-coordinate transformation error, or chunk-origin reconstruction error.

Frozen ray: origin `(0,8,6)`, direction `(0,-1,0)`, length `12`. The canonical continuous SDF's first root is at distance `6.11299490854144` (approximately world `y=1.88700509146`); the picker reports `6.11301279067993`. The LOD0 mesh's first hit is at distances `6.47910531882559` and `6.47910448258006` on the two neighboring chunk representations, about `0.3661104` and `0.3661096` farther along the ray. At those hits, canonical density is positive (`+0.0181425381` / `+0.0181431341`), so the hit lies in the canonical solid rather than on its zero surface.

The first hit on region `(-1,0)`, chunk `(3,2)`, is triangle 348 in source cell `(7,7,0)`, tetrahedron 1, corner order `[0,1,2,6]`, chunk origin `(-4,0,6)`. The counterpart on region `(0,0)`, chunk `(0,2)`, maps to cell `(0,7,0)`, tetrahedron 2, corner order `[0,2,3,6]`, and triangle 157. Both full chunk rebuilds reproduce the recorded position-array hashes exactly. The source mesh uses a `0.5` world-unit sample step (`terrain_chunk_grid.gd:7`) and `PackedFloat32Array` corner samples (`marching_tetrahedra.gd:115`), followed by edge-linear interpolation in `_polygonize_tetra` (`marching_tetrahedra.gd:254`).

For the negative-region triangle's ray-aligned edge at world `x=0,z=6`, endpoint samples are approximately `+0.00492794998` at `(0,1.5,6)` and `-0.112994857` at `(0,2,6)`. Linear interpolation places the mesh edge root at `y=1.52089476585`; bisection of the continuous canonical field along that same edge places its root near `y=1.88700509`. The emitted face centroid density is `+0.0150416660`. At `x=0`, the global half-open owner maps to region `(0,0)` local x `0`, while the source chunk can address the same boundary as region `(-1,0)` local x `16`; the independently evaluated samples agree at both representations. The X+ same-ray LOD0/LOD0 control has mesh/root separation below `1.3e-7` on the two sides, demonstrating that the ray/picker and world-coordinate conventions can agree in the control case.

This is a real pointwise surface-displacement observation from sampling/interpolation of the continuous field. The evidence does not select a new sampling resolution, geometric tolerance, or product correction.

Raw traces: `evidence/diag-run-006/phase-06-xminus_baseline.json` and `phase-07-xminus_source_provenance.json`.

## Attempts and validation

All failed or superseded attempts are retained under `evidence/` and were not overwritten:

- `diag-run-001`: two earlier `--check-only` attempts failed on harness parse/type errors; attempts R4–R10 parsed. The first diagnostic process recorded a 900,000 ms timeout after an invalid JSON-to-`Vector3` construction and a secondary dictionary access error. No source scenario was changed or rerun as acceptance.
- `diag-run-002` through `diag-run-005`: diagnostic source-map attempts were blocked by incorrect intermediate coordinate/source-map assumptions; their raw JSON/logs are retained.
- `diag-run-006`: seven-phase provenance diagnostic completed, exit 0, `DIAGNOSTIC_COMPLETE`, zero diagnostic failures.
- `diag-run-007` through `diag-run-009`: focused X+ face probes, with the later probe adding raw transition-triangle details. Run 008's derived elapsed field was wrong due to UTC/local parsing; raw outputs remain preserved and run 009 uses `Stopwatch`.
- `diag-run-010`: wrapper captured parser check but failed to retain a usable process exit code and did not start its conditional face probe. Preserved as a launcher/capture defect.
- `diag-run-011`: final focused check-only and explicit-coordinate face probe both exited 0; stderr empty. Two explicit face triangles generate two expected contour segments, present on positive-side LOD0 and LOD1 and missing on negative-side LOD1.

Final `scripts/validate.ps1` was run once against source HEAD `d81f292…`, with the pinned Godot binary and isolated user-data/TEMP profile at `evidence/final-validation/`. Result: **exit 0; 21 named suites; 21,464 assertions; 0 assertion failures; no `SCRIPT ERROR`, parse error, or validation error**. Three non-fatal existing camera `looking_at` colinearity warnings were emitted on stderr. The suite also printed `ISSUE118_REPARSE_FIXTURE_UNAVAILABLE` because `DirAccess.create_link` could not make the optional Windows junction fixture in this environment; this was an explicit unavailable optional fixture, not a suite failure. Full stdout/stderr, process metadata, command and hashes are retained. The full validation does not run the R8.2 probe; the R8.2 scripts were separately parser checked and the focused probe completed as above.

Assertion markers are summarized in `evidence/final-validation/stdout.log`; the exact raw output is authoritative. No headless result is claimed as rendered-frame, GPU, collider, or owner-GUI evidence.

## Evidence integrity and limits

`evidence/SHA256SUMS.txt` inventories the 140 published diagnostic, process and raw-log files under `evidence/`, excluding the checksum file itself and generated `godot-profile/**` caches/user-data. Those per-run isolated profiles are preserved in the local evidence workspace but omitted from the PR as generated user data, not source or test results. The inventory includes all earlier failed attempts, final diagnostic outputs, process records and complete validation stdout/stderr. Experimental source hashes are listed in `SOURCE_SHA256SUMS.txt`. The inventory is for integrity checking, not a claim that every early failed run is successful evidence.

No geometry acceptance thresholds were added or modified. No correction prototype, production change, GUI run, collider/PhysicsServer test, GPU measurement, performance campaign, schema work, save access, native dependency, merge, or release action was performed. The three defects remain open engineering concerns. A separate source/evidence review should verify the experimental scripts and manifests against the exact evidence commit. Any repair of the X+ omitted facets must preserve the established degeneracy contract or obtain an explicit replacement contract; the observed X− and triangle 3103 differences require owner-defined geometric fidelity decisions before adoption.

All five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
