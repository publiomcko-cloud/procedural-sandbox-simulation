# P3.1 R7.3 — Edited CARVE failure diagnosis

## Disposition

`P3_1_R7_3_READY_FOR_INDEPENDENT_REVIEW`

The frozen CARVE input was reconstructed and reduced to a one-focus-cell diagnostic. Evidence identifies an over-restrictive local edge-collapse boundary rule as the cause of the minimized failure. Strategy A's bounded correction passes the one-cell regression while preserving the exact external patch signature and all frozen local topology invariants. The frozen zero-edit topology/collider gate and the full project validator also pass.

This does **not** qualify the full edited `cave_wall_carve` scenario. Issue #155 requires a separate documented gate decision before one complete CARVE attempt. No complete edited CARVE or ordered FILL/CARVE scenario was executed in R7.3; the prior R7.2 CARVE attempt remains intact and was not rerun.

## Identity and scope

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`; origin verified as `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- R7.3 branch/worktree: `bench/p3-1-r7-3-edited-carve-diagnosis`, `C:\r73`.
- Tested R7.3 source commit: `7ad45d8c817ecb0f54a8eec058babce65af287db`; direct parent and exact R7.2 base: PR #153 head `c54f337cb1f2b1e6d1f61de5c1b9d9f3031e892d`. R7.2's parent is R7.1 evidence head `24d6580b9539b267ef59c209f765607071ee6f48`.
- Production reference: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Live PR #153 and Issue #155 were verified open; PR #153 is draft and unmerged. PRs #149 and #151 remain separate, open, draft and unmerged.
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`; SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Godot was run with redirected `APPDATA`/`LOCALAPPDATA` under disposable profiles. No production terrain or user save was loaded.
- The only code changes are experimental GDScript diagnostics/tests. Production SDF, ledger, mesher, scenes, schemas, dependencies and gameplay are unchanged. No PR #153/#149/#151 or F2-G1 protected state was modified.

Physical SHA-256 values for tested GDScript sources are independently recorded below and in the raw diagnostic records. The follow-up documentation commit does not change tested source.

| Tested source | Physical SHA-256 |
| --- | --- |
| `game/tests/prototypes/p3_1_r7_2_local_retriangulation.gd` | `9ea65149d45be9ef6e747156ea2984e8f75269cca03e11714d72e8354330f3d2` |
| `game/tests/prototypes/p3_1_r7_2_zero_edit_gate.gd` | `04c3656e314ff1a21f10be2d3a034f8ee137e5024c5ea7fa50c5563de21e27d5` |
| `game/tests/prototypes/p3_1_r7_3_minimal_carve_repair.gd` | `f74a51d8f93296181325aa876b442fc42c03ac64c6cf34728b8fe4c755f2b4bf` |
| `game/tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd` (unchanged oracle) | `65addfba047a093def229bd6e2c1c3ac363c8e559cf20cd178cdf7a1264966c7` |

| Changed path | Purpose |
| --- | --- |
| `game/tests/prototypes/p3_1_r7_2_local_retriangulation.gd` | Captures selected-cell ownership, patch boundaries, candidate/accepted/rejected collapse details, target attempts, vertex movement, changed/removed triangles, topology metrics and first failure; tries bounded target positions and accepts only an unchanged external boundary signature. |
| `game/tests/prototypes/p3_1_r7_2_zero_edit_gate.gd` | Adds fail-closed diagnostic-only reconstruction for the frozen CARVE input and preserves the full diagnostic record, canonical input hash and source hashes. |
| `game/tests/prototypes/p3_1_r7_3_minimal_carve_repair.gd` | Adds a deterministic single-focus-cell CARVE regression. It explicitly does not run the full edited scenario or collider gate. |
| `.gitattributes` | Keeps the raw R7.3 evidence bytes unchanged in Git. |
| `docs/reports/P3-1-R7.3/` | Full attempt logs, checksum inventory and this report. |
| `docs/checkpoints/2026-10-27-P3-1-R7.3-EDITED-CARVE-DIAGNOSIS.md` | Immutable event checkpoint added in the documentation follow-up commit. |
| `docs/checkpoints/INDEX.md`, `docs/status/CURRENT_STATUS.md`, `README.md` | Index and current research-state reconciliation. |

## Failure reproduction and cause

The frozen `cave_wall_carve` recipe uses seed `131102026`, generator version from the pinned fixture, region `(0,0)`, revision 1, one CARVE command (mode byte 0), center `(8.0, 1.17898154258728, 5.90309238433838)` and radius `0.58`. Its canonical input JSON SHA-256 is `47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411`.

The first R7.3 instrumentation attempt returned process exit 0 but omitted selected-cell metadata because `_copy_mesh()` did not preserve it. That incomplete record was retained. The next diagnostic attempt emitted the complete record, including selected cell IDs/roles, original and attempted boundary signatures and coordinates, all collapse candidates and target attempts, rejection reasons, vertex/triangle changes, component counts, first failed invariant, canonical input hash and source hashes.

Strategy A's original failing focus contained 29 cells:

`624, 712, 720, 721, 728, 816, 1005, 1053, 1054, 1093, 1100, 1101, 1102, 1103, 1109, 1141, 1142, 1148, 1149, 1150, 1151, 1191, 1197, 1198, 1199, 1207, 1245, 1246, 1295`.

A bounded deterministic deletion reducer made 9 trials and reached a one-focus-cell-minimal reproduction: cell ID 720, coordinate `(0,7,6)`, world minimum `(8.0,1.5,6.0)`. Its X_MIN patch boundary is the plane `x=8`. Before repair, the cell-plus-face-neighbor patch had 152 triangles, 2 nonzero subthreshold triangles, zero internal opens, zero nonmanifold edges, consistent winding, zero T-junctions and one face component.

In the earlier failed attempt, candidate edge `27|30` was rejected immediately as `would_move_fixed_patch_boundary`; edge `27|29` received the same rejection. The edge-collapse targets were never evaluated. The adjacent exterior edge `29|30` correctly failed the two-manifold edge condition. In the corrected A experiment, edge `27|30` is accepted using `keep_higher_id`, and edge `28|29` is accepted using the same target policy. Each boundary-adjacent move preserves the exact sorted external boundary signature; measured displacements were `0.000596476602368057` and `0.000761992065235972` world units. These are exploratory observed values, not an approved geometry tolerance.

After A, the minimal patch has 148 triangles, zero degenerates at the unchanged `cross.length_squared() <= 1e-12` threshold, zero internal open edges, zero nonmanifold edges, consistent winding, zero T-junctions, one face component and an identical external boundary signature. The cell-level regression passed 16/16 assertions. This establishes the local mechanism as **D — an over-restrictive repair constraint**, not an edge-collapse that violates topology. The original blanket endpoint-boundary veto rejected a candidate before its possible targets could be checked. The correction admits boundary-adjacent edges only when the existing manifold/winding/area tests pass and the complete external signature remains unchanged.

This evidence does not prove the entire original multi-cell CARVE gate now passes: the corrected strategy has only been exercised on the minimal patch and the zero-edit control. The final full-failure classification remains bounded to that tested local mechanism; any other whole-gate issue remains unverified.

### Strategy B, evaluated separately

After the A failure mechanism was observed, the independent bounded B diagnostic was run on the minimized CARVE patch. It failed closed with `cavity_boundary_not_disjoint_loops`; no repair geometry was published. B was not silently substituted for A and is not recommended from this result.

No evidence demonstrated an experimental contour-oracle defect. The original and repaired local patches retain matching topology metrics; external boundary comparison is exact under the fixture's existing coordinate-key contract. The degeneracy threshold and geometric tolerances were not changed.

## Sequential gates and validation

| Attempt | Work | Result |
| --- | --- | --- |
| 01 | Verify Godot identity; editor import; R7.2 gate `--check-only` | Godot version/hash matched; import and check-only exit 0, no stderr. No scenario ran. |
| 02 | Frozen CARVE diagnostic, A | Exit 0; retained as `INSTRUMENTATION_INCOMPLETE` because selected-cell metadata was lost by the mesh-copy helper. It was not used as complete causal evidence. |
| 03 | Frozen CARVE diagnostic, A, with corrected metadata propagation | `DIAGNOSTIC_COMPLETE`, exit 0, no stderr. Nine reducer trials reached focus cell 720. The unrepaired-boundary-veto result retained one subthreshold triangle and reported `degenerate_triangle_at_frozen_threshold`; original and attempted boundary signatures both contained 160 entries. |
| 04 | Separate frozen CARVE diagnostic, B | `DIAGNOSTIC_COMPLETE`, exit 0, no stderr; B rejected with `cavity_boundary_not_disjoint_loops`. |
| 05 | Parser check and minimal cell-720 A regression | Exit 0; 16 assertions, zero failures; `full_scenario_gate_executed=false`; frozen input hash above. |
| 06 | Evidence-preparation preflight | Recoverable host-side path-list error before process creation; no Godot process started. Exact error and correction are retained. |
| 07 | One frozen zero-edit gate after the minimal pass | `R72_RESULT status=PASS`, exit 0; 24 assertions, zero failures. Full mesh topology: zero internal openings, degenerate triangles, nonmanifold edges and interface T-junctions; 1,357 interfaces and 2,025 contour segment comparisons with zero contour mismatches. The 1.75-unit cave opening was preserved. Two-sided proxy matched 72/72 independent triangle rays; the one-sided control retained 33 misses. This is disposable proxy evidence only. |
| 08 | `scripts/validate.ps1` once with Godot 4.7.2 and isolated user data | Exit 0; 21 suites, 21,464 assertions, zero failed assertions. Three nonfatal camera `looking_at` colinearity warnings came from existing procedural-object scene tests. Full stdout/stderr are retained. |

The 21 assertion-group counts are: `52, 44, 612, 179, 7637, 11, 907, 3516, 66, 638, 67, 101, 19, 44, 51, 713, 6474, 53, 251, 11, 18` (total 21,464). The full validator's embedded timing output is not used as a performance acceptance claim.

**Not run:** a new full edited `cave_wall_carve` gate, `center_fill_then_wall_carve`, any broad benchmark/GPU campaign, or owner GUI test. The sequential gate requires an additional documented decision before a full CARVE retry; the prior started R7.2 process was not repeated.

### Raw evidence and source integrity

All R7.3 attempt records are preserved under `docs/reports/P3-1-R7.3/evidence/attempt-01` through `attempt-08`. `evidence/SHA256SUMS.txt` lists 50 physical SHA-256 entries, self-excluding. It covers the full stdout/stderr logs, exit codes, durations, process/launch records, environment identity and the preflight recovery record. The failed R7.2 gate log remains at its original R7.2 evidence location and was not altered.

The minimal fixture records physical SHA-256 values for its own test, the R7.2 gate, local repair strategy, conforming mesh fixture, canonical SDF/brush sources and transition fixture. The complete diagnostic log records hashes for its eight source inputs. All are independently re-calculable from the committed tree.

## Limits and next gate

- This is a test-only R7.3 candidate; no production mesher behavior changed.
- Local A correction and the zero-edit gate pass, but complete edited CARVE and ordered FILL/CARVE results remain unqualified.
- Movement values and the `abs(SDF)/gradient` measure are experimental; no product geometry tolerance or metric acceptance threshold was adopted.
- Collider checks are disposable physics-proxy comparisons, not production collider approval.
- No rendered visual or owner GUI acceptance is claimed.
- No geometry contract, storage schema, Issue #108/#154 behavior, merge or release is authorized.
- All holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

Next, independently review the exact source/evidence commit. A separately documented gate decision is required before one complete frozen CARVE attempt. Only if that attempt passes may the ordered FILL/CARVE gate be considered.
