# P3.1 R8.3-A — X+ seam correction feasibility

## Identity and disposition

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Branch: `bench/p3-1-r8-3a-xplus-seam-repair`
- Measured source: `94b2d68d5292d2aa9db7586df7ad58266fd1ff36`
- Direct parent / exact R8.2 baseline: `4f08b67522507bd196a74a1089c773f272235343`
- Disposition: **`P3_1_R8_3_A_BLOCKED_WITH_EVIDENCE`**
- Publication: draft PR [#165](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/165), open and unmerged.

The isolated fixture reproduces the missing X+ transition contour. No tested bounded correction satisfies the unchanged geometry and topology constraints, so the sequential experiment stops at the minimal fixture gate. This is not a production repair or geometry-contract decision.

## Frozen reproduction

Input is the R8.2 pinned `center_fill_then_wall_carve` snapshot, seed `131102026`, generator v1, input SHA-256 `55d45d387bd19829bb38c4e988da25a886765f26cc34e19dd07ed808faa1bd46`. The LOD1 transition cell has LOD0-lattice origin `(30,4,14)`, world bounds `[(15,2,7),(16,3,8)]`, selected face X+, and interface plane `x=16`. The production squared-cross degeneracy cutoff remains `1e-12`.

The independent face-triangle oracle requires two X+ contour segments, while the transition cell emits zero. Its two pre-cutoff transition facets have squared cross magnitudes `9.47780916249474e-13` and `9.34902979685126e-13`, so both are omitted by the unchanged production cutoff. The frozen neighboring LOD0 face has 35 contour segments against the negative-side LOD1's 33; the adjacent LOD1 control has 35. The canonical face-sample comparison remains 533/533 bitwise equal. This supports an extraction/cutoff explanation for the local missing contour, not a sample ownership mismatch.

The corresponding X+ interface segments are:

- `(16,2.00160503387451,7)` to `(16,2.00090837478638,7.00090837478638)`
- `(16,2.00090837478638,7.00090837478638)` to `(16,2,7.00159215927124)`

The transition center-to-face linear intersection is `(15.9991540908813,2.00084590911865,7.00084590911865)`. Bisection of the continuous canonical field on that source edge gives `(15.9991502761841,2.00084948539734,7.00084924697876)` after 48 iterations. Substitution of that continuous root still yields squared cross magnitudes `9.5517105509757e-13` and `9.42205081316816e-13`, below the unchanged cutoff.

## Bounded candidate results

The minimal local complex contains two triangles and four unique vertices. Tested strategies were bounded to those frozen vertices and the paired four-vertex patch:

- **A — edge collapse:** collapsing the interior vertex to the shared interface root creates zero-area facets. Collapsing to either outer interface root degenerates a facet and changes contour ownership. Collapsing interface vertices changes the frozen contour endpoints. No tested legal collapse preserves the exact external contour and clears the cutoff.
- **B — constrained cavity retriangulation:** both diagonals of the paired four-vertex patch were evaluated. The source diagonal has `[9.47780916249474e-13, 9.34902979685126e-13]`; the alternate has `[3.67953410795874e-12, 1.21647537962982e-13]`. Each leaves at least one facet below threshold.
- **C — boundary-preserving remeshing:** the fixed triangular cavity has only its existing three boundary vertices; without adding samples or moving vertices, remeshing reproduces the rejected facet. The tested paired-patch alternative is the same two-diagonal case as B.

The 14-assertion isolated prototype validates reproduction and these bounded candidate observations. It is not an accepted repair. This does **not** prove that all larger cavities, extra canonical samples, propagation, or adaptive transition methods are infeasible; those approaches were not tested and would need a separately scoped proposal that preserves the frozen interface and cutoff.

## Attempts and validation

The exact-base R8.2 face oracle and import were captured under `evidence/baseline/`. `attempt-001` preserves a parser failure in the first revision of this new diagnostic (`passed` had ambiguous inferred type); the script was corrected with an explicit `bool`, without changing source geometry or expectations. Attempts 002 and 003 preserve the diagnostic iterations. `attempt-004` is the final measured script: Godot `--check-only` and the bounded diagnostic both exited 0; it emitted `MINIMAL_FIXTURE_REPRODUCED`, 14 assertions, zero diagnostic failures. No failed frozen acceptance scenario was rerun.

Full `scripts/validate.ps1` on the exact measured source exited 0: 21 suites, 21,464 assertions, zero failures, duration 549,463 ms. Three existing non-fatal camera `looking_at` colinearity warnings remain. The complete logs are `evidence/final-validation/stdout.log` and `stderr.log`. Godot version was `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 is `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

## Gate boundary and limitations

Because no tested bounded strategy meets the first minimal repair gate, no repaired mixed-LOD interface, same-LOD interface, neighborhood, full-chunk, R7.3 inherited regression, collider, GUI or performance gate was run. The A report therefore records feasibility evidence only for the fixed local patch. The candidate leaves production, schemas, gameplay, geometry thresholds and save data unchanged. No visual or product acceptance is claimed.

All five F2-G1 holds remain unchanged. See the immutable [checkpoint](../../checkpoints/2026-10-28-P3-1-R8.3-A-XPLUS-SEAM-EXPERIMENT.md) and hash inventories.
