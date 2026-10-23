# P1.1B +Z LOD seam correction

**Date:** 2026-10-23 (America/Sao_Paulo).
**Implementation branch:** `fix/p1-1b-b0g-plusz-seam`.
**Draft PR:** [#102](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/102), targeting the reviewed P1.1B harness branch.
**Implementation commit:** `89d5b6f5205c354333e66b9044475395a7edacf4`; parent `2b4355363a43b73476715cf4002e31575bf9828d`.
**State:** `PLUSZ_FIX_FOCUSED_VALIDATION_PASS / INDEPENDENT_REVIEW_PENDING / UNSCORED`.

## Root cause

The final B0G campaign had two failures, `B0G.LOD01.FACE.Z_POS.v1` and `B0G.LOD01.CORNER.ALL_POS.v1`, on face 5 (+Z), adjacent LOD0 seam validation. The preserved original JSONL reports `lod0_adjacent_seam_mismatch` with `contour_reason=t_junction_boundary_vertex`; it does not contain coordinates.

A direct pre-correction geometry reproduction using the frozen seed, origin and nonlinear density field showed that transition and independent LOD0 reference generated the same boundary contour, but both were rejected by the unchanged R7 contour oracle. On the z=-2 plane, the segment keys included `-1769231,-769231,-2000000|-1946809,-500000,-2000000` and the alleged interior point was `-1946808,-500000,-2000000` (`t=0.999998209327726`). The two raw crossing positions were approximately `1.1920929e-7` world units apart, but rounded into adjacent 1e-6 coordinate keys.

The defect was order-dependent float32 `Vector3.lerp` rounding: adjacent tetrahedra can request the same sampled edge with reversed endpoints. A direct calculation for the same edge and densities `-0.025` / `0.21` produced x values `-1.94680857658386` and `-1.94680845737457` depending on endpoint order. This was a numerically split duplicate, not a mismatched neighbor mesh or genuine T-junction.

## Correction and validation

The experimental fixture now orders crossed-edge endpoints lexicographically by world coordinates before applying the existing linear density interpolation. No density, triangulation, tolerance, contour oracle, frozen input or production path changed. LOD0 seam tests now also invoke the R7 contract boundary oracle on both independently generated meshes. The R7 genuine T-junction negative regression remains unchanged.

Godot `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`; B0 manifest SHA-256 `BCF49351436F46BAE0512573A77D99E662430BFE65917EBADEBCF96264A1AECD`.

- `lod01_transition_tests.gd`: 6,473 assertions, zero failures.
- `p1_1b_benchmark_contract_tests.gd`: 2,586 assertions, zero failures, including genuine T-junction rejection.
- `B0G.LOD01.FACE.Z_POS.v1`: PASS, face 5 LOD0 and opposite LOD1 checks; 27 transition triangles, four +Z contour segments, five boundary normal vertices.
- `B0G.LOD01.CORNER.ALL_POS.v1`: PASS, all three LOD0 and opposite LOD1 checks; 24 transition triangles; face 5 gives four contour segments and five boundary normal vertices.
- Regression controls `B0G.LOD01.FACE.Y_NEG.v1` and `B0G.LOD01.EDGE.X_NEG_Y_NEG.v1`: PASS.
- All four new scenario invocations exited 0 with one `scenario_started`, one `lod_fixture_result=PASS`, one `scenario_complete=PASS`, and zero failures. Timings are headless and UNSCORED.

Raw stdout/stderr, parsed scenario events, preflight hashes, focused suite logs, diagnostic notes and an artifact hash index are retained at `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_plusz_fix_c29e96f015304daa9a266dd5557cb4e1`. `artifact-index.json` SHA-256: `DA675BB12D1E072A3EE82BD86AEBB41EB6FEFB23BC4D707B6B70826F100D1B03`.

## Scope and remaining limits

The reviewed R7 branch and manifest were not modified. Historical X_NEG and X_POS remain BLOCKED and were not rerun. No broad scenario matrix, production terrain LOD, GUI/pixel acceptance, GPU measurement, performance scoring, merge, or release was performed. This establishes the focused experimental fixture correction only; independent exact-SHA review remains required before further integration decisions.

The five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
