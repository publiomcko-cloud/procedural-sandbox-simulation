# P3.1 R12-C Stage 0 result and A6 provenance correction — 2026-10-30

## Identity and scope

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Isolated worktree: `C:\r12c-20261030`
- Branch: `exp/p3-1-r12-c-topology-geometry-realization`
- Source measured for Stage 0: `d63394d3c0e255d7d0af547a258aa847700e2f44`
- Direct parent: `a42fda77ca27ab3de0401769c2ded4a915663451`
- Tree: `83e16588951ad6b4fd274597de258aa325bfbf94`
- This remains test-only research. No production source, save, schema, PR #207–#209, or F2-G1 protected state was changed.

## Hash-provenance correction

The initial R12 preregistration copied `1f21af7c3856ae72080e3e0c5ad44a3c608703470b5563212902bed08ad0f7d4` as the R10-A6 mesh digest from the R10-B6 report. Inspection of the primary R10-A raw bundle showed that this was a source-provenance mix-up: the R10-A6 result JSON records `geometry.mesh_sha256 = de53e9fa326e451ac202beb49c0ef1e56b70500ce1ca3dd9c43565d85e7c5f74`. The R10-B6 attempt separately records `1f21af7c...` under its `equal_lod.mesh_sha256`; identical high-level counts do not make that artifact the primary R10-A6 output.

Independent physical evidence:

- R10-A raw archive: `docs/reports/P3-1-R10-A-CAMPAIGN/evidence/R10-A-raw-evidence.zip`, SHA-256 `ac630bd3b6b8be3494b33367e1896030de541a88ae16e8fdcf8b7ac83ac58e6`.
- Exact archive entry: `R10-A6_geometry/required_equal_lod_gate_full_roi_R9.2.SEAM.XPLUS_EQUAL.v1.json`, uncompressed 5,158,628 bytes, SHA-256 `664bb61fd060cff689e0b251517503dcb888ead21622d8caae7535f6b66155dc`.
- The extracted entry reports the expected R10-A6 source/topology, 655 triangles, 10 internal opens, 21 missing required adjacencies, 0 nonmanifold edges, 0 degenerates, 0 winding inconsistencies, and 7 fixed-cutoff rejections. Its mesh digest is `de53e9fa...`.
- The frozen R10-B6 attempt record remains unmodified under the prior evidence root. Its distinct `1f21af7c...` value is retained rather than overwritten.

The correction is recorded in the R12 preregistration and the Stage 0 fixture constant. It fixes which primary artifact is pinned; it does not relax or change any geometric acceptance rule.

## Stage 0 runtime evidence

Evidence root: `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r12c_20261030_0a53ac9c6d5245f4a4faffb14089c8be`.

The prior import/check/fixture failures remain preserved in their unique attempt directories. After the provenance correction, exact-source stages passed serially:

| Attempt | Stage | Godot PID | Exit | Elapsed | stdout SHA-256 | stderr |
|---|---|---:|---:|---:|---|---|
| `S0IMPORT5` | editor import | 38020 | 0 | 7,082 ms | `cbed49ff3d4e729fb1e49af6ee70743b8026d8f54e7844e86af5f090d534c2e3` | empty; SHA-256 `e3b0c442...` |
| `S0CHECK5` | Stage 0 `--check-only` | 40660 | 0 | 1,178 ms | `83cf0b082206af2aa236c83064fbcfa76be1e00a4aa3558574b2f65965d9481c` | empty; SHA-256 `e3b0c442...` |
| `S0FIXTURE5` | Stage 0 fixture | 40372 | 0 | 2,358 ms | `e95b22f043e59d6477790e47cad48ae8e96784004cfe0c9cedaf411881a51d50` | empty; SHA-256 `e3b0c442...` |

Each launcher PID, durable launch intent, source identity, stdout/stderr, monitor samples and process record are in the matching attempt directory. Godot binary was `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, version `4.7.2.stable.official.ed1daf0bf`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. The Stage 0 monitor sampled free commit every ~390 ms; minimum observed was 15,522,103,296 bytes. No resource warning, abort, or timeout occurred.

The create-new fixture is 2,885,492 bytes, SHA-256 `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`. Its source graph matches SHA-256 `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95` with 369 roots, 502 polygons and 870 arcs. The target component has 73 roots, 84 polygons, 156 arcs, 34 boundary roots, 39 interior roots and 39 junction roots. The A6 replay matches the primary R10-A hash `de53e9fa...` and all listed historical geometric counts.

## C1 disposition and next gate

The target's degree histogram is 2:2, 3:19, 4:30, 5:1, 6:21. Both degree-2 roots are boundary roots, which the frozen C1 policy requires to remain `BOUNDARY_ANCHOR`. There are zero eligible interior degree-2 transit roots. C1 was not geometrically executed and remains unconsumed; broadening it after observing the data would invalidate its preregistration.

C2's graph-face anchor-cycle realization is now preregistered in `docs/reports/P3-1-R12-C-CAMPAIGN/PREREGISTRATION.md` before implementation/execution. No C1–C6 geometry hypothesis has yet executed or consumed a slot. Mixed LOD, determinism, full E2E and full project validation remain gated.

All five F2-G1 markers remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
