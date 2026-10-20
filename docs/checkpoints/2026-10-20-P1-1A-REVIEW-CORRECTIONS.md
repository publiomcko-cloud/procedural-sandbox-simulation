# CHK-2026-10-20-P1-1A-REVIEW-CORRECTIONS

**Checkpoint date/timezone:** 2026-10-20, America/Sao_Paulo
**Event type:** independent source-review correction and validation handoff
**Publication state:** prepared on the existing P1.1A draft PR #96 branch; not merged
**Historical record:** this checkpoint supplements, and does not rewrite, the original P1.1A implementation checkpoint.

## Verified identity and authorization

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Existing workspace: `C:\Dev\sandbox-sim-dev`; branch `feat/p1-1a-lod01-transition-fixture`.
- Existing PR: [#96, draft and unmerged](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96).
- Reviewed HEAD: `2040469bc4ff4a39c5ab181452f291ad9ea112b8`; review #5584314194 required changes. Base/main: `f42f9dbdd54809df202a81b4aa59ed0d1f377a2e`.
- Source/test correction commit: `9669a03ec691532862e9aee1251f15e15f06b690`, direct parent `2040469bc4ff4a39c5ab181452f291ad9ea112b8`.
- Correction code paths: `game/scripts/experiments/lod01_transition_fixture.gd` and `game/tests/lod01_transition_tests.gd`. The fixture specification and this checkpoint are documentation-only changes; no production scene, SDF, brush ledger, streamer, or production mesher is changed.
- `stash@{0}` was preserved. The existing branch/workspace/PR were reused. No new worktree, branch, PR, merge, native dependency, P1.1B/C, or F2-G1 operation was performed.

## Review findings and bounded corrections

1. **Globally misaligned LOD1 origins:** the reviewed builder paths accepted odd LOD0 lattice indices and could place a nominal 1-unit coarse cell between globally anchored coarse lattice points. The fixture now requires each X/Y/Z LOD0 lattice index to be divisible by 2 before transition construction or LOD1 reference generation. Negative odd values are rejected by the same parity test. `interface_triangles(..., resolution=1)` returns an empty result for such an origin. LOD0 references and fine interface triangles remain unrestricted on the LOD0 lattice.
2. **Malformed compact snapshots:** validation now checks required metadata types, seed and generator identity, integer/nonnegative revision, revision not less than retained command count, packed array types and matching lengths, the 256-command cap, finite/bounded world centers, finite radii within the existing ledger min/max, and exactly the two supported mode bytes. The concrete mode-byte-2 case now returns `unsupported_snapshot_mode`; `SdfBrushEditState` and its CSG semantics were not changed. Full validation happens once at builder entry; internal sample calls use that already validated immutable snapshot to avoid rescanning all commands at every vertex/normal probe. The public `sample_canonical` entrypoint still validates supplied snapshots.
3. **Nonfinite density/output:** all mesh and normal-probe field values are checked. NaN or infinity returns `valid=false` with stable reason `non_finite_sample_density`. Triangles are appended only after all three normals are valid, and final output also checks paired finite vertex/normal arrays and nonnegative integer timings. A failed build returns no accepted mesh or timing payload, including when failure occurs after earlier triangles were locally generated.
4. **Independent seam oracle:** tests now construct adjacent uniform reference meshes separately from the transition builder, using a nonlinear synthetic field at signed X/Y/Z coordinates. For face, edge, and corner configurations they extract actual boundary contour segments and endpoint normals from the independently built LOD0 and LOD1 meshes, then compare those with the transition result. The existing production-tetrahedron face parity test and helper-based contour test remain as separate checks. This is still single-cell/adjacent-reference evidence, not a general multi-cell mosaic proof.

### Negative-test evidence

- The prior review supplied the off-lattice examples; tests now cover positive and negative odd indices on each axis: X `(1,0,0)` and `(-3,0,0)`, Y `(0,1,0)` and `(0,-1,0)`, Z `(0,0,1)` and `(0,0,-1)`. Transition/reference builders return a deterministic alignment reason and do not call the provided sampler. LOD0 requests at those positions still build.
- A canonical one-command snapshot mutated to mode byte `2` is explicitly rejected rather than interpreted by the production evaluator's non-CARVE fallback as FILL. Additional malformed metadata, revision, array count, center and radius vectors are rejected with stable reasons.
- NaN and infinity density overrides are rejected in both transition and reference paths. A separate override returns finite values at mesh lattice samples but infinity only at normal-probe offsets; it is rejected without exposing partial geometry or timings.
- The first draft of the new neighbor-mesh test failed because the harness treated the unit-domain LOD0 reference builder as four half-unit reference meshes and used a field that did not cross one selected face. Those were test-construction errors, not production defects: the harness now uses one independently built unit-domain LOD0 mesh per adjacent patch and a nonlinear field whose signed unit-cell endpoints straddle zero. The final exact-SHA validation below passes the corrected face/edge/corner contour and normal comparisons.

## Validation evidence

- Engine: Godot `4.7.2.stable.official.ed1daf0bf` at `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.
- Full command: from repository root, `& '.\scripts\validate.ps1'`.
- Result on the contents of source commit `9669a03ec691532862e9aee1251f15e15f06b690`: exit 0, `VALIDATION_PASS: L0-L2`, **16,174 assertions across 12 suites, zero failures**. Existing suites remain passing; P1.1A transition suite is 5,808/5,808.
- Suite counts: smoke 52; SDF 44; brushes 611; chunks 179; multi-region 7,634; terrain performance 11; history 842; viewport picker history 713; LOD0/1 transition 5,808; end-to-end performance 251; concurrency 11; bootstrap structure 18.
- Exact local log: `%TEMP%\p1-1a-review-corrections-full-final.log`. The previous in-progress validation was interrupted after a source edit and is not counted as evidence. The final full run began only after source/test edits were frozen.
- Production isolation: `git diff origin/main -- game/scenes game/scripts/terrain` was empty. No GUI visual test was run or claimed.

## Updated exploratory fixture benchmark

The full validation's LOD benchmark used two warmups and 12 measured CPU-only samples per case. Times below are milliseconds. p99 is a near-maximum statistic at n=12; values are exploratory and no owner-approved budget exists.

| Ledger ops | Transition p50 / p95 / p99 | LOD0 reference p50 / p95 / p99 | Transition SDF sample avg / normal avg / ArrayMesh avg (ms) | Array payload estimate / transition triangles |
|---:|---:|---:|---:|---:|
| 0 | 2.952 / 4.692 / 4.692 | 4.824 / 5.009 / 5.009 | 0.107 / 2.181 / 0.014 | 2,160 B / 22 |
| 1 | 4.169 / 7.460 / 7.460 | 5.772 / 7.332 / 7.332 | 0.122 / 3.354 / 0.014 | 2,880 B / 32 |
| 32 | 4.619 / 4.800 / 4.800 | 7.773 / 9.098 / 9.098 | 0.176 / 3.608 / 0.011 | 2,160 B / 22 |
| 128 | 9.380 / 19.152 / 19.152 | 17.750 / 28.390 / 28.390 | 0.498 / 10.864 / 0.020 | 2,160 B / 22 |
| 256 | 15.219 / 16.452 / 16.452 | 26.766 / 27.194 / 27.194 | 0.635 / 13.697 / 0.025 | 2,160 B / 22 |

The one-time snapshot validation avoids repeating an O(ledger-size) validation for each sample, while replay semantics remain unchanged. The bytes column counts only packed mesh/sample payload, not process memory, allocator overhead, or peak RSS. These cell-level headless figures do not measure production chunk meshing, frame percentiles, GPU execution, or completed graphics upload. Earlier figures in the original implementation checkpoint remain historical; this table reflects the correction run.

## Limits and next decision

- The fixture remains an experimental single LOD1 transition-cell template, accepts one to three nonopposing fine faces, and intentionally leaves the finite fixture exterior open. Independent adjacent-cell mesh checks strengthen bounded face/edge/corner evidence but do not prove an arbitrary mesh mosaic, production streaming, edit invalidation, worker publication, or atomic world snapshot.
- No owner-defined CPU, memory, geometric-error, normal-angle, or feature-preservation budget exists. Benchmarks and density residuals remain exploratory. No GUI/GPU visual acceptance is claimed.
- The complete implementation remains custom GDScript. No Voxel Tools/native components, production LOD, P1.1B/C, or architecture/backend change is authorized.
- Next authorized action is independent exact-SHA re-review of the updated draft PR #96. Do not merge without separate owner authorization.
- Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
