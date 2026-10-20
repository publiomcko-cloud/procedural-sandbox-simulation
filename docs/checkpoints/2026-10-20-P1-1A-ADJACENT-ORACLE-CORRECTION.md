# CHK-2026-10-20-P1-1A-ADJACENT-ORACLE-CORRECTION

**Checkpoint date/timezone:** 2026-10-20, America/Sao_Paulo  
**Event type:** final adjacent-reference placement correction and exact-branch validation  
**Publication state:** prepared on existing draft PR #96; not merged  
**Historical record:** supplements the original P1.1A implementation and review-correction checkpoints; neither is rewritten.

## Identity and scope

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Workspace: `C:\Dev\sandbox-sim-dev`; branch: `feat/p1-1a-lod01-transition-fixture`.
- Existing PR: [#96](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96), draft/open/unmerged at the time of this checkpoint.
- Corrected source/test commit: `2929a01c7d38dde59fdb6e1a4902e2e9183e6a59`; direct parent and reviewed HEAD: `3b596e14b6079104475f1cfb67d032a6cda790d7`.
- Review addressed: [#5584564076](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96#pullrequestreview-5584564076). The prior three source-level corrections from review #5584314194 remain intact.
- Source change is confined to `game/tests/lod01_transition_tests.gd`. The fixture specification was updated to describe the actual spatial preconditions and expanded tests. No production scene, SDF, brush ledger, streamer, or production mesher changed.
- `stash@{0}` and unrelated local work were preserved. The existing branch, workspace, and PR were reused; no additional worktree, branch, or PR was created.

## AABB defect reproduction and correction

`build_uniform_reference_cell(..., lod=0)` builds a 1×1×1 world-unit domain from 2×2×2 half-unit cells. At the mixed signed test origin `Vector3i(-4,-2,-6)`, the transition cell has X bounds `[-2,-1]`. The former negative-neighbor origin offset of -1 LOD0 lattice index gave the reference bounds `[-2.5,-1.5]`, which overlapped the transition interior by 0.5 units and put the nominal interface plane inside that volume.

The test now retains explicit assertions for those old bounds and verifies that the bad offset fails the independent boundary-contact/nonoverlap predicate. The adjacent LOD0 helper uses -2 indices on negative faces and +2 on positive faces. The LOD1 reference helper also uses the corresponding ±2 index offset. The underlying uniform reference builder and its 1×1×1 domain are unchanged.

Before contour comparisons, the suite checks exact requested-plane equality, disjoint interiors, equal tangent-axis ranges, and finite signed world bounds. Both LOD0 and LOD1 reference placement are checked across all six X/Y/Z face orientations. Contour cases independently mesh positive and negative faces on every axis, negative and positive edges/corners, and mixed-sign edge/corner configurations using the existing nonlinear field.

For each selected interface, the assertions require a nonempty contour, exact contour-segment set equality, endpoint-normal agreement, internally consistent normals, nondegenerate/unique source triangles, no zero-length boundary segments, and no contour endpoint lying in another segment's interior (T-junction). The existing production tetrahedron-face parity tests remain unchanged.

## Validation

- Engine: Godot `4.7.2.stable.official.ed1daf0bf`, `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.
- Command: `$env:GODOT_BIN='C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'; .\scripts\validate.ps1`.
- Result: exit 0, `VALIDATION_PASS: L0-L2`; **16,807 assertions across 12 suites, zero failures**. This preserves the previous 16,174 assertions and adds 633 spatial/seam checks. The LOD fixture is 6,441/6,441 (previously 5,808).
- Suite counts: smoke 52; SDF 44; brush 611; chunks 179; multiregion 7,634; terrain performance 11; history 842; picker history 713; LOD transition 6,441; end-to-end performance 251; concurrency 11; bootstrap structure 18.
- Full output: `%TEMP%\p1-1a-adjacent-oracle-validation.log`. `git diff --check` passed. The production source/scene diff check for `game/scripts/terrain` and `game/scenes` was empty.
- The full run also reran the fixture's exploratory benchmark (warmup 2, 12 samples). CPU-only transition p50/p95 in milliseconds: 0 ops `3.076/5.033`; 1 `4.711/9.833`; 32 `4.644/13.141`; 128 `9.784/15.784`; 256 `17.435/21.735`. LOD0 reference p50/p95: 0 `4.848/5.493`; 1 `5.766/6.754`; 32 `11.569/23.829`; 128 `16.013/20.000`; 256 `27.593/37.520`. These are exploratory machine-local measurements. At n=12 p95/p99 are near-maximum order statistics; no owner-approved budgets exist.
- No GUI/GPU/visual test was run. Benchmark completion does not imply performance acceptance.

## Limits and holds

This evidence is for an experimental single-cell transition fixture and independently generated unit-domain reference neighbors. It does not prove arbitrary multi-cell LOD mosaics, production LOD, a visual/GPU result, or performance acceptance. Independent final source rereview remains required; PR #96 stays draft and unmerged.

All F2-G1 operational holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
