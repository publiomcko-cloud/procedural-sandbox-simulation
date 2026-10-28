# P3.1 R8.1 — Geometry Defect Root-Cause Investigation

**Disposition:** `P3_1_R8_1_READY_FOR_INDEPENDENT_REVIEW` — diagnostic evidence only. This is not geometric acceptance, production approval, or a repair claim.

## Causal disposition

| Finding | Confirmed by this experiment | Exact mechanism status |
|---|---|---|
| Cell 712 / triangle 3103 and normal outliers | The triangle is unchanged by the R7.3 repair; tetrahedral winding points toward the empty side of the sampled linear field, while its face normal opposes the stable outward gradient of the continuous edited field. Pairwise flat-facet normal variation is reproduced. | **PARTIAL / mechanism unresolved.** Evidence isolates disagreement between the local tetrahedral interpolant and the continuous nonlinear field at this triangle. It does not identify whether local sampling, a CSG branch transition, or interpolation causes the discrepancy. The fixture's pair angle is not production shared-vertex-normal evidence. |
| X+ LOD1-side contour | Bitwise-equal shared scalar samples coexist with a 33/35 extracted segment mismatch, independently reproduced from raw single-incidence triangle edges. The opposite LOD orientation matches. | **PARTIAL / generation branch unresolved.** The mismatch is in extracted geometry/subdivision, not only the R8 segment-dictionary comparator. Exact face decomposition, ownership, or interpolation cause is not isolated. |
| X− picker-to-mesh offset | The same-ray SDF picker agrees closely with the independently bracketed canonical zero root, while the first union-mesh hit lies on the positive-density side and differs by about 0.36609 units. Shared face samples match bitwise at 533 probes. | **PARTIAL / mesher mechanism unresolved.** This is a mesh-versus-continuous-field discrepancy, not evidence of a picker transform or first-hit error. The exact mesher branch is not isolated. |

No candidate correction was made because the evidence does not yet justify choosing a particular source mechanism. No geometry tolerance was adopted. This package is ready for independent review of the bounded causal evidence; it does not claim that the three geometry issues are fixed or that a production remedy has been selected.

## Identity and scope

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- R8.1 branch: `bench/p3-1-r8-1-geometry-causality`
- R8 baseline HEAD: `95a17b64aebfdba620ca949b1011c6b124792da6`
- R8 package commit: `73ca1910bb9c7a123a74c1466f4dd1a0c83b74ef`
- Measured R7.3 input source: `7ad45d8c817ecb0f54a8eec058babce65af287db`
- Issue: [#159](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/159)
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`
- New source: `game/tests/prototypes/p3_1_r8_1_geometry_causality.gd` (test-only); no production source, scene, schema, save or dependency was changed.
- Physical SHA-256 of the final measured diagnostic source: `191c37dd8d65f31b94c3a356e1e3232e8483fd037de5d4089844429c3795b9be`.

The harness recomputes the three frozen input pins before each diagnostic run. It replays the R7.3 repair unchanged and compares the original/repaired CPU fixture meshes. The production squared-cross cutoff remains `1e-12`; no geometric tolerance was changed or adopted.

## Findings

### 1. Cell 712 / triangle 3103 and shared-cell normal outliers

The frozen FILL/CARVE target is reproduced at triangle 3103, owner cell 712, centroid `(8.239575386, 1.509850502, 5.506340027)`. Its vertices and float32 bytes are identical before and after the R7.3 repair; cell 712 is outside the repair focus. The triangle cross-product squared length is `4.6430776e-7`, well above the unchanged `1e-12` cutoff, so degeneracy rejection does not explain this observation.

The source tetra trace maps global triangle 3103 to owner-cell local triangle 1, fine subcell `(0,0,0)`, tetrahedron 1, corner order `[0,1,2,6]`. One corner is positive-density solid (`0.0069923233`); the other three are negative-density empty (`-0.0489068180`, `-0.1589843482`, `-0.0849197358`). The emitted cross dotted with the vector from the inside-corner centroid toward the empty-corner centroid is positive (`9.3703296e-5`). This proves the source winding rule points toward the empty side of that tetrahedron's sampled piecewise-linear field.

At the triangle centroid, however, the canonical continuous edited field is `+0.0035693479`. Samples along the emitted face normal are `-0.0029041338` at offset `-0.01` and `+0.0048430729` at `+0.01`; the canonical outward gradient dot is `-0.4682175`. The canonical finite-difference gradient is stable across `h=0.25` through `0.0005`. Thus the frozen triangle's direction is consistent with its tetra corner classifications but opposes the continuous field's local outward direction. This confirms a local disagreement between the tetrahedral linear surface approximation and the canonical nonlinear edited field. It does **not** prove a global vertex-order bug; the exact responsible interpolation or sampling mechanism remains unresolved.

The reported 33.621-degree CARVE pair (cells 528/624) and 87.736-degree FILL/CARVE pair (408/504) are also reproduced. The field-gradient direction is stable at the same shared endpoints; for the FILL/CARVE pair the endpoint face-normal dots are approximately `0.9951` and `0.1368`, while the pair angle is `87.7358` degrees. Crucially, the R7 fixture emits a flat geometric triangle normal at each of its three vertices (`p3_1_r7_conforming_mesh_fixture.gd:427-429`). These are adjacent-facet orientation measurements in the diagnostic fixture, not a measurement of production's shared gradient vertex normals. Production `marching_tetrahedra.gd:232-252` derives normals from the sampled density gradient. No angle acceptance threshold exists, so the facet angles are observations, not a pass/fail product requirement.

**Disposition:** no winding or normal correction is justified by this bounded evidence. A targeted continuous-field-versus-piecewise-linear surface test is the next useful diagnostic; any geometry or normal budget requires owner approval.

### 2. X+ boundary contour with negative-side LOD1

At plane `x=16`, region `(0,0)` chunk `(3,2)` meets region `(1,0)` chunk `(0,2)`. The frozen `[LOD_A, LOD_B]=[1,0]` pair reproduces `33` versus `35` boundary segments, with two unmatched segments on B. The independent raw triangle-edge incidence enumeration reproduces the same `33/35` edge-set mismatch, so the result is not solely the R8 contour dictionary comparator. A `[0,1]` control matches `35/35`. The `[1,1]` pair also mismatches `33/35`, so the result is not limited to a mixed-LOD pair.

All 533 canonical samples on the shared face at spacing `0.25` match bitwise (`max difference 0`, `0` non-bitwise-equal samples). Around `(16,2,7)`, one side emits a single chord from approximately `(16,2.001605,7)` to `(16,2,7.001592)`; the other emits two segments through `(16,2.000908,7.000908)`. That intermediate point is about `0.000154` world units off the single-side chord. The unchanged `1e-5` point key was used; no tolerance was widened. The independent test reports no strict T-junction under its existing exact criterion.

**Disposition:** a real extracted boundary geometry/subdivision mismatch is confirmed; the comparison oracle alone does not explain it. The precise source branch (chunk-face decomposition, transition ownership, or related interpolation path) was not isolated, so no corrective candidate was applied.

### 3. X− picker versus mesh position

The X− probe uses the same world ray for both adjacent meshes and the SDF picker: origin `(0,8,6)`, direction down, length `12`, with region `(-1,0)` chunk `(3,2)` and region `(0,0)` chunk `(0,2)`. At LOD `0/0` and `1/1`, the picker reports distance `6.1130127907`; the independent dense canonical SDF first root is `6.1129949085` (distance error `1.7882e-5`). The first union-mesh hit is at distance `6.4791045` / `6.4790952`, position approximately `(0,1.520895,6)`, a picker-to-mesh position difference of `0.3660917` / `0.3660822` world units.

The independent X+ `0/0` control gives picker/root error `2.1578e-5` and picker/mesh error `2.1935e-5`. The X− mesh hit point has canonical density `+0.0181431`; samples `0.01` units above/below the hit remain positive (`+0.0245658` and `+0.0117838`). The first union-hit triangle vertices are also on the positive side (`+0.0181080`, `+0.0181427`, `+0.0258748` at the B-side triangle; centroid `+0.0206871`). In contrast, the picker/root is the zero crossing. The 533 sampled canonical shared-face values match bitwise for both X− LOD pairs.

**Disposition:** the picker/ray root is not the source of the reported offset. A mesh-versus-continuous-field geometric discrepancy, including a first triangle hit wholly on the canonical solid side, is confirmed. The exact mesh-generation cause is unresolved; this diagnostic did not prove a world/local transform defect or a collider-engine defect. It uses independent two-sided triangle intersections, not PhysicsServer collision queries.

## Execution evidence

Godot diagnostics were run in a fresh disposable APPDATA/LOCALAPPDATA profile per attempt. Frozen data and R8 source pins were verified by the harness preflight. No actual user save, production scene, protected path, renderer, PhysicsServer or native component was accessed.

| Run | Process | Result | Notes |
|---|---:|---|---|
| `run-001` | PID 27116 | BLOCKED, exit 1 | Harness type error: untyped `Array` assigned to `Array[int]` at `_diagnose_r81_normals:65`. Preserved. |
| `run-002` | PID 8876 | BLOCKED, exit 1 | Harness argument mismatch: centroid remained `Array` at `_field_branch_values` call, line 98. Preserved. |
| `run-003` | PID 39708 | `DIAGNOSTIC_COMPLETE`, exit 0 | All three base probes completed; stderr empty. |
| `run-004` | PID 43528 | `DIAGNOSTIC_COMPLETE`, exit 0 | Added canonical density samples for target triangle vertices and unmatched X+ segments, and first picker-hit triangle; stderr empty. |
| `run-005` | PID 12528 | `DIAGNOSTIC_COMPLETE`, exit 0 | Added X− shared-face region-sampling parity; 533/533 equal for both X− LOD pairs; stderr empty. |

These diagnostics report zero conventional assertions by design: `DIAGNOSTIC_COMPLETE` means the fixed observations were measured, **not** that the geometry passed acceptance. Runs 001 and 002 are retained as harness bring-up failures, not geometry findings. The authoritative final focused evidence is run-005, using the final harness source hash listed in `SOURCE_SHA256SUMS.txt`.

The initial full `scripts/validate.ps1` run (`validation-001`) passed 21 marker suites / 21,464 assertions, exit 0, before the final test-only evidence fields were added. The required final-source rerun (`validation-002`) also passed: 21 marker suites, 21,464 assertions, zero failures, exit 0, using Godot `4.7.2.stable.official.ed1daf0bf`. Its process record identifies PID `47500`; stdout is 115,867 bytes and stderr 1,220 bytes. It ended with `VALIDATION_PASS: L0-L2; GUI visual test remains an owner task`. Standard error contains three non-fatal, pre-existing `Target and up vectors are colinear` warnings from `terrain_demo.gd:1755` during `procedural_object_tests`; no parser or script errors occurred. Full stdout, stderr and process metadata are retained under `evidence/validation-002`. No GUI, rendered-frame, GPU or product geometry acceptance is claimed.

The 21 marker groups and assertion totals were: smoke 52; terrain SDF 44; brush 612; chunk 179; multi-region 7,637; terrain performance 11; history 907; world-v2 storage 3,516; declarative mod 66; procedural object 638; entity command 67; entity history 101; entity command harness 19; playable entity command 44; P3.0D placement 51; terrain pick history 713; LOD01 transition 6,474; runtime LOD 53; terrain E2E performance 251; concurrency 11; bootstrap structure 18. Their sum is 21,464. The headless timing output is regression telemetry only and is not presented FPS/GPU evidence.

## Next independent gate

1. Independently reproduce the canonical-field residual at triangle 3103 from its original tetra samples and the continuous sampler; isolate whether the orientation discrepancy comes from local interpolation error, a missed CSG branch transition, or a coordinate/snapshot mismatch.
2. Trace the X+ unmatched segment and X− interior hit triangles to their source chunk cells and tetrahedra; compare their exact nodal values and interpolation edges on both sides. Keep the mixed-LOD and equal-LOD X+ controls.
3. Only after those traces isolate a specific cause, prepare a minimal test-only candidate. Preserve the frozen input, sampled field, source positions, edge topology and existing tolerances; do not change production code or claim geometry acceptance.

PR #158 remains untouched, open, draft and unmerged. PR #159 is a separate diagnostic-evidence draft. The owner must separately review the source/evidence and approve any later production or geometry-contract work.

All five security holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
