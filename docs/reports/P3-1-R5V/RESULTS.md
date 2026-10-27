# P3.1 R5-V — Adaptive Voxel Research Results

## Identity and disposition

- Production authority baseline: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Experimental parent: R4 final `051249642611a7fa9cd2006be450bad0e184e4ee`.
- R4 source measured: `83c7c091bcec0d10534d8638225d3d24d94b6334`.
- Branch: `bench/p3-1-r5v-adaptive-volume`.
- The implementation is isolated under `game/tests/prototypes/`; production terrain, ledger, persistence schemas and scenes were not changed.
- Disposition: **READY_FOR_INDEPENDENT_REVIEW** as an approximate research prototype only. It is not approved for production or geometry-contract adoption.

## Implemented experiment

A complete 0.5-unit base lattice is retained. Macro cells are refined when corner signs straddle zero or center interpolation residual exceeds 0.02 world units. Selectively refined cells use 0.25- or 0.125-unit subspacing, with boundary samples constrained to the shared coarse interpolant. Interior samples come from the canonical continuous SDF plus globally ordered ledger. The ledger remains authoritative. The representation is approximate, is not a substitute for exact SDF queries, and its 0.02 selection heuristic is not an approved geometry tolerance.

The harness also covers deterministic serialization/reload, digest equality, corruption rejection, macro-face scalar continuity, sampled surface displacement, normals, ray picking, and a zero-edit cave control. Collision and GUI rendering are not measured.

## Experimental campaign

The seven frozen edited scenarios each ran once in one Godot process; the separate zero-edit cave control and 256-operation concentrated retest also ran once. All prototype runs reported `status=PASS`, with a combined 22,409 prototype assertions and zero test failures. The per-process records and raw JSON remain in `evidence/matrix-20261027-095416/`; the concentrated retest is in `evidence/final-20261027-256-concentrated/`; the cave control is in `evidence/20261027-095229/`. Do not pool this single-process R5 sample with R4's five-process measurements.

Representative 0.125-unit results:

| Scenario | Operation count | Build | Refined cells | Serialized payload | Sampled surface displacement p95 / max | Normal error p95 / max |
|---|---:|---:|---:|---:|---:|---:|
| Concentrated | 256 | 526 ms | 277 | 150,344 B | 0.000462 / 0.003347 m | 5.56 / 105.50 deg |
| Concentrated | 640 | 1,020 ms | 276 | 149,828 B | 0.000455 / 0.000694 m | 42.10 / 163.65 deg |
| Concentrated | 2,048 | 2,875 ms | 276 | 149,828 B | 0.000520 / 0.003387 m | 3.05 / 163.94 deg |
| Concentrated | 8,192 | 10,250 ms | 277 | 150,344 B | 0.000462 / 0.003387 m | 14.49 / 54.19 deg |
| Distributed | 256 | 562 ms | 312 | 168,404 B | 0.001098 / 0.002490 m | 9.69 / 46.23 deg |
| Distributed | 640 | 1,180 ms | 312 | 168,404 B | 0.001098 / 0.002490 m | 9.69 / 46.23 deg |
| Distributed | 2,048 | 3,095 ms | 312 | 168,404 B | 0.001098 / 0.002490 m | 9.69 / 46.23 deg |
| Distributed | 8,192 | 11,835 ms | 312 | 168,404 B | 0.001098 / 0.002490 m | 9.69 / 46.23 deg |

The full precision measurements, including density p50/p95/max, sampled surface estimates, normal p50/p95/max, runtime, picker mismatches, restart digest and seam gap, are in `evidence/matrix-20261027-095416/metrics-per-run.csv`. The R4 frozen 8,192-command concentrated input has SHA-256 `0b30e1ce2605b3bab504f3f5648c7e63a84c9a22f905721b56defcfe0489f611`.

All edited scenarios reported zero ray-picker classification mismatches and matching restart digests. Macro scalar seam checks reported zero mismatches and maximum interface gaps from `5.96e-8` to `2.38e-7` world-density units. These narrow results do not prove mesh topology, collision, Hausdorff distance, or all-world behavior.

The separate canonical cave control found all 127 centerline probes open for both fields, but canonical vertical opening diameter was exactly 1.75 units while the adaptive estimate ranged 1.75–4.875 units. Maximum centerline density difference was 0.3483. Thus centerline connectivity survived this control, but cross-section shape can expand substantially. Cave continuity with nonzero edit histories remains `NOT_RUN`.

## Interpretation

The preregistration's discussion envelope is explicitly **NOT OWNER APPROVED**. Sampled surface displacement remained below its proposed p95/max limits in these fixtures, but normal error exceeded the proposed 5-degree p95 and 15-degree maximum in multiple scenarios. The cave control also demonstrates cross-section expansion. Surface measurement is sampled bidirectional vertex-to-triangle distance, not certified Hausdorff distance. The prototype therefore demonstrates bounded selective-refinement behavior and deterministic artifact recovery, not acceptance of geometry quality.

At 8,192 concentrated operations, the 0.125 snapshot took 10.25 s to build and was about 150 KB; the candidate LOD0 CPU extraction took 27.4 ms versus 1.824 s for canonical mesh construction in that harness. That apparent extraction improvement excludes the snapshot-build cost and uses approximate geometry, so it is not a like-for-like product performance claim. At 8,192 distributed operations the snapshot build was 11.83 s for about 168 KB. The finer 0.25 candidate build was faster, but that spacing also has its own unapproved fidelity tradeoff. Full exact per-scenario figures are retained in the raw JSON and CSV.

## Validation and limits

- Godot: `4.7.2.stable.official.ed1daf0bf`.
- R5-V prototype matrix: seven frozen edited scenarios, one process each; all PASS, 22,121 assertions total.
- Separate zero-edit cave control: PASS, 17 assertions.
- Separate concentrated 256 retest: PASS, 271 assertions.
- Full `scripts/validate.ps1`: exit 0, all 21,464 project assertions passed across L0-L2. It emitted three existing colinear-camera `look_at` warnings and no script/parser/runtime errors. The persistence regression reported its junction fixture unavailable (`DirAccess.create_link returned Failed`), so that particular reparse case was not exercised. The validator does not certify R5 geometry acceptance.
- SHA-256 inventory: `SHA256SUMS.txt` covers R5-V source, UID files, preregistration, reports and retained evidence files; the inventory does not include its own hash.
- Headless CPU timing is not presented FPS, GPU completion, VRAM, or owner GUI acceptance.
- R5 single-process results are exploratory and do not satisfy the preregistration's five-repeat evidence requirement for performance selection.
- No native Voxel Tools code, production adapter, persistence schema change, cache authority change, or Issue #108 implementation is included.

## Recommendation

Keep the global ordered ledger authoritative and do not adopt this approximate volume for production yet. If pursued, first obtain owner-approved feature and normal tolerances, improve refinement around high-curvature and cave cross-sections, measure multiple repeats including build amortization and invalidation, and independently review the implementation. Collision, GPU, VRAM, full topology, edited-cave connectivity, and actual GUI appearance remain unmeasured.
