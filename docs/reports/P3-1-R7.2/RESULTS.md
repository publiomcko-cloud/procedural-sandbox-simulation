# P3.1 R7.2 — Topology-preserving local retriangulation

## Disposition

`P3_1_R7_2_BLOCKED_WITH_EVIDENCE`

The minimal four-cell-plus-neighbors fixture passes for local strategies A and B while retaining the frozen `1e-12` squared-cross threshold. The single frozen zero-edit gate also passes with strategy A. The first frozen edited `cave_wall_carve` gate fails during fail-closed local-patch validation, so its topology/collider acceptance gate did not complete. In accordance with the sequential stop rule, the ordered FILL/CARVE scenario was not started. No production change or geometry-contract adoption is recommended from this result.

## Source and repository identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`.
- Origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Experimental branch/worktree: `bench/p3-1-r7-2-topology-retriangulation`, `C:\r72`.
- Base and initial HEAD: `24d6580b9539b267ef59c209f765607071ee6f48`; direct parent of that R7.1 report/evidence commit: `b32db270ad31d4eee60cbeffee10bdfaf21967fb`.
- R7.1 measured source: `456adc16b2ecbef4e6342e3f6f8731455eb4a917`.
- Production reference: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- R7.1 PR #151 was independently verified open, draft and unmerged, with head `24d6580b9539b267ef59c209f765607071ee6f48`; PR #149 remained separate. Issue #152 was verified open and its scope matches this test-only investigation.
- Godot: `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.

The experimental additions are limited to three GDScript prototype/test files and this report/checkpoint/evidence. The production SDF, ledger, mesher, scenes, schemas and gameplay files are unchanged. The production triangle rejection threshold remains `cross.length_squared() <= 1e-12`.

| Experimental source | Physical SHA-256 | Git blob |
| --- | --- | --- |
| `game/tests/prototypes/p3_1_r7_2_local_retriangulation.gd` | `60b2e6d714945189727c0485224da57896d95a33cf470cf244a62a61ba86bd19` | `0cff59ce5780e0f650a98d3e7e5b2b333e7ffaa1` |
| `game/tests/prototypes/p3_1_r7_2_topology_diagnostic.gd` | `981bac0f62a7fec2f9daaa097d852ab7de3e01cc4f35b7474b64ac10b9390d8e` | `d7fe75274af612e80ce9ea6d1e584f8859ecac11` |
| `game/tests/prototypes/p3_1_r7_2_zero_edit_gate.gd` | `2e111d4080b8d89e43c9c8a8989edacb377298934667e1c0a8344333f5ab2a35` | `e6bdef4599ae1e3caa2eba0ada6e2e46d4ceb247` |

The full source and evidence inventory is `evidence/SHA256SUMS.txt` (113 entries; self-excluded), including the Godot executable and inherited fixture/oracle sources.

## Frozen reproduction and local alternatives

The fixture uses the original zero-edit R7 field (seed `131102026`, ledger revision 0, 1.75-unit vertical opening), focus cells `1101`, `1149`, `1150`, `1199` plus six-neighbor cells (23 cells total). It preserves 621 binary32 SDF samples and their IEEE-754 bit patterns, tetrahedron connectivity, triangle coordinates/winding, and canonical world positions. The retained-microtriangle control and production-cutoff control are both recorded. The cutoff is unchanged at `1e-12`.

The minimal diagnostic completed 17 assertions with zero failures. In its bounded selected-cell fixture, both A (topology-aware edge collapse) and B (constrained cavity fan) had zero internal open edges, subthreshold triangles, nonmanifold edges, T-junctions and same-direction shared edges while keeping the external boundary signature unchanged. A moved vertices by at most `0.00075399037450552` world units (six accepted collapses); B inserted a center displaced by at most `0.00178245` world units (14 faces added, three cavity loops). These measured changes are experimental observations, not approved geometry tolerances. The vertex/SDF residual proxy is not a Hausdorff bound.

C (boundary-preserving patch remeshing) was explicitly rejected: after removing 51 faces its cavity boundary did not form disjoint loops (`cavity_boundary_not_disjoint_loops`; two boundary vertices had degree 1). The implementation does not silently fall back to a different method.

## Frozen zero-edit gate

One zero-edit process completed with exit 0, 20 assertions, zero failures, and one terminal PASS. It compared the production-cutoff mesh (7,118 triangles with 14 internal openings) against an inclusive 7,126-triangle source mesh and selected A's 7,114-triangle repaired mesh. The accepted zero-edit output measured:

- Internal open edges: 0; expected external fixture-boundary opens: 354.
- Degenerate triangles at the frozen threshold: 0.
- Nonmanifold edges: 0; same-winding shared edges: 0.
- Surface face-component count: 3 before and after.
- Extracted internal-interface contour mismatches: 0 across 1,357 interfaces / 2,025 segment comparisons; interface T-junctions: 0; duplicate coplanar interfaces: 0.
- Canonical cave opening: `1.75` world units; frozen centerline samples open: 31/31.
- Local A patch: six collapses, maximum vertex displacement `0.00075399037450552`; canonical zero-set residual proxy maximum `4.32427838527411e-6` world units.
- Full output mesh SHA-256: `6b70a3e780d5a00f255e97eafcd7b434960e459a21b7bd7f28df5c34f22b0b61`; source mesh SHA-256: `28393598194def435e2148e23b53f6733d8dc2f0fe2e3fb519363b8bbf8cf0cf`.

The full-mesh sampled vertex-to-SDF-distance proxy had p50 `0.0021126388376336`, p95 `0.103077422063468`, max `0.251930961095151` world units; sampled normal-to-gradient angle had p50 `0.442255362408134°`, p95 `8.31944190909504°`, max `11.3042465292217°`. These are exploratory sampled proxies, not certified surface-distance bounds or owner-approved acceptance budgets. The entire triangle surface has three connected components; this count alone does not prove volumetric tunnel connectivity.

The inherited collider oracle retained all 72 ray queries and 36 sphere probes. With the two-sided disposable shape/query configuration, ray outcome mismatches against the independent two-sided triangle oracle were 0/72; the default one-sided control retained 33 reverse-direction misses. Sphere-contact difference remained p50/p95/max about `0.13` world units because the sweep is discretized at `0.05` units. This is test-proxy/query evidence, not production collider behavior and not evidence of watertightness. The zero-gate script reused the same selected A geometry in its three legacy approach labels; it does not compare three distinct repair meshes.

Measured headless stages were full build `1.496323 s`, local repair `2.053532 s`, collider probes `2.004423 s`, total `7.305665 s`. These are one-run diagnostic durations, not a performance campaign. The detailed zero-edit run preceded a later CLI/full-scenario refactor of the gate script; the repair helper was unchanged, but no contemporaneous source hash snapshot for that exact run was captured. Treat it as evidence from the preserved run, not as an independently reproducible exact-source pin. The subsequent CARVE attempt and full validation used the refactored source bytes listed above.

## Sequential edited gate and stopping point

Exactly one `cave_wall_carve` process was started. It exited 1 after 7 assertions with these failures:

- `cave_wall_carve_selected_A_repair_satisfies_all_local_invariants`
- `cave_wall_carve_local_A_patch_replaces_only_selected_cells`
- `patch:selected_local_strategy_invalid`

The implementation returns early when A is invalid, before emitting the detailed `R72_SCENARIO` record or running the edited mesh/collider gates. Therefore the exact local A failure metrics for this edited input are unavailable in the preserved output. No CARVE scenario was retried. The ordered FILL/CARVE scenario is `NOT_RUN` under the required sequential gate. The experiment is blocked; no conclusion about the root geometric cause of the edited A failure is claimed from the available diagnostics.

## Validation and evidence

Full `scripts/validate.ps1` ran once on the exact R7.1 base plus the then-current three untracked R7.2 prototype scripts, under an isolated Godot user-data profile. Exit code 0; 21 passing suite markers; 21,464 assertions; zero failures. Stderr contains three non-fatal existing `Target and up vectors are colinear` camera warnings from procedural-object tests. No parser/script error was found in that run. This full project regression does not turn the R7.2 edited topology gate into a pass and does not constitute GUI, rendered-frame, GPU or product-geometry acceptance.

| Attempts | Result |
| --- | --- |
| 01–05 | Iterative exploratory source/fixture diagnostics; all original logs retained. These are not acceptance runs. |
| 06 | Godot `--check-only` emitted a GDScript inference error although the process returned 0. A following diagnostic was terminated after the bounded stop-loss interval (46 s; exit `-1`); it produced no result marker. The source typing defect was corrected before later focused gates. |
| 07 | Godot check-only exited 0 with empty stderr, but the external wrapper incorrectly classified the result because of its null-pattern handling. No scenario acceptance is inferred from this wrapper result. |
| 08 | Minimal local topology fixture: 17 assertions, 0 failures. |
| 09 | Zero-gate script check-only: exit 0, empty stderr. |
| 10 | One frozen zero-edit gate: 20 assertions, 0 failures. Detailed source hash caveat is stated above. |
| 11 | Refactored scenario-gate check-only: exit 0, empty stderr. |
| 12 | Exactly one frozen CARVE scenario: 7 assertions, 3 failures, exit 1; not retried. |
| 13 | Full `scripts/validate.ps1`: 21 suites, 21,464 assertions, 0 failures, exit 0. |

Raw attempt logs, summaries, environment/process records and per-attempt indices are preserved under `evidence/attempt-01` through `evidence/attempt-13`. Earlier failed attempts were not discarded. `.gitattributes` marks this evidence subtree `-text` so raw stdout/stderr and environment bytes are not line-ending-normalized on checkout. `evidence/SHA256SUMS.txt` contains 113 entries for the retained evidence tree, experimental scripts, key inherited diagnostic sources and Godot executable; its entries were independently rechecked with zero missing files or hash mismatches. The inventory omits itself to avoid recursion. The focused source hashes are also listed there.

## Limits and recommendation

- Do not adopt A or B in production based on the zero-edit result; no owner geometry tolerance exists, and the edited CARVE gate failed.
- Do not adopt C; its constrained cavity boundary was not a set of disjoint loops.
- The collider proxy validates query configuration only. No production collision provider exists at the pinned source.
- The zero-edit extraction oracle covers intra-patch cell interfaces and the bounded external patch boundary; it does not establish continuity at production chunk interfaces.
- No GUI/GPU run, broad performance campaign, changed-ledger FILL/CARVE qualification or cross-chunk production integration occurred.
- Before any further scenario, improve the fail-path evidence so an invalid selected repair emits its full strategy diagnostics without retrying an already-started scenario. A separately authorized investigation may then diagnose the CARVE-specific local patch failure. No production integration or merge is authorized.

All five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
