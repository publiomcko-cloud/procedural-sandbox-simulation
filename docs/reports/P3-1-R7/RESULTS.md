# P3.1 R7 — Conforming Adaptive SDF Refinement

**Disposition: `P3_1_R7_BLOCKED_WITH_EVIDENCE`**

**Evidence class:** isolated source/test prototype, Godot 4.7.2 headless execution, no owner-approved geometry or performance acceptance.

## Identity and preservation

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- R7 branch: `bench/p3-1-r7-conforming-adaptive`
- R7 prototype commit: `ae184e9253f052401d54ae107b4428fe315f7c69`
- Direct parent / R6-V final HEAD: `0867c0c04b857fae1c71b274b8eac44c6e7dba4f`
- R6-V validated source: `aef090871a7582ee5254511f55624d60882fa00d`
- Production reference: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`
- Live `origin/main` observed during this work: `5997a76d345f45bf86edfe83f690336391e8be27`. R7 is based on the separate R6-V experiment branch and does not modify production.
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`; SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.
- Prototype sources are only `game/tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd` and `game/tests/prototypes/p3_1_r7_conforming_adaptive_diagnostic.gd`, plus their Godot UID sidecars. No production source, production scene, save, storage schema, or Issue #108 path changed.
- Existing worktrees and both stashes were left intact. `stash@{0}` and `stash@{1}` remain present. Three pre-existing untracked P1.1B `.gd.uid` files and the earlier R7 check logs were not staged. No protected C:/G: paths or F2-G1 state were accessed.
- PRs #129, #141, #143, #144, #146 and #147 were observed open/draft/unmerged before this R7 evidence PR was created. No merge was performed.

## Question and experimental scope

R6-V had shown two different cave defects: coarse-boundary interpolation widened the zero-edit vertical cave opening from the canonical 1.75 units to 4.875 units; replacing refined-cell boundary values with canonical fine samples reduced that opening but introduced scalar discontinuities against unrefined neighbors, up to 0.153837. These values and their raw scenario evidence are retained in the parent R6-V report, [R6-V results](../P3-1-R6V/RESULTS.md) and its checksum inventory. R7 preserves those failed results; it does not reinterpret them as accepted tolerances.

R7 implements three bounded, test-only approaches over the same canonical SDF v1 field and the same ordered ledger snapshot:

| Approach | Policy | Zero-edit work produced |
| --- | --- | --- |
| A — conforming propagation | Propagate fine resolution across the connected test patch. | All 1,920 cells fine; no transition cells. |
| B — shared fine faces and transitions | Keep the canonical initial refinement mask and use shared canonical samples plus transition cells at fine/coarse interfaces. | 771 fine cells; 480 transition cells. |
| C — hybrid | Expand the initial mask by one face-neighbor cell layer, then transition remaining interfaces. | 1,251 fine cells; 126 transition cells. |

The patch is bounded to 1,920 coarse cells, with 64-cell maximum propagation radius, 12,000 fine-cell cap, 16 MiB fine-sample payload cap, and 250,000 triangle cap. These are experiment stop-loss limits, not product budgets. Exact workload definitions are in the [R7 experimental contract](../../specs/P3-1-R7-CONFORMING-ADAPTIVE.md).

## Frozen zero-edit input and integrity

The single executed R7 scenario was `P3.1.R7.ZERO_EDIT.v1`: seed `131102026`, generator version 1, region `(0,0)`, revision 0, and no brush commands. The exact UTF-8, no-BOM/no-trailing-newline canonical JSON is retained at `evidence/input-manifest.json`; SHA-256 is `24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b`. The unedited canonical vertical opening measured exactly 1.75.

The mesh digest covers position and normal array lengths followed by packed position and normal bytes. All three approaches produced the same digest:

`8007174a6286c6e20fe9cda44ded992bd9a3b3d27132c4b844ea518d95f48f68`

Identical output digests mean this zero-edit run did not demonstrate a geometry difference between the three policies. It also does not establish that their sampled fields or behavior on edited cases are generally equivalent.

## Focused topology and collider preflight

Both prototype scripts passed Godot `--check-only` after the final harness correction: fixture exit 0/stderr 0 bytes; driver exit 0/stderr 0 bytes. The one final zero-edit invocation is preserved in `evidence/zero-preflight.*`. It ran only the zero-edit control and returned exit code 1 in 7,086 ms. The explicit terminal record was:

```text
R7_RESULT status=FAIL assertions=8 scenario_count=1 preflight_only=true
failures:
  zero_edit_A_conforming_propagation_mesh_topology_gate
  zero_edit_B_shared_faces_transitions_mesh_topology_gate
  zero_edit_C_hybrid_one_cell_halo_mesh_topology_gate
  zero_edit_all_test_only_collider_ray_hit_outcomes_match_canonical
```

There were no stderr bytes, parser errors, or runtime script errors in this final run. The harness now gates both ray directions and defaults to zero-edit only; edited cases require `--run-edited-after-preflight`, and the harness stops after a failed zero-edit gate. Neither edited scenario was started.

| Zero-edit output | A | B | C |
| --- | ---: | ---: | ---: |
| Triangles | 7,118 | 7,118 | 7,118 |
| Internal open edges | **14** | **14** | **14** |
| Expected open edges on the bounded patch exterior | 354 | 354 | 354 |
| Non-manifold edges | 0 | 0 | 0 |
| Degenerate triangles | 0 | 0 | 0 |
| Nonmatching extracted internal interface contours | 0 | 0 | 0 |
| Duplicate coplanar internal surfaces | 0 | 0 | 0 |
| Strict T-junction vertices | 0 | 0 | 0 |
| Exact-zero face surfaces counted once | 96 | 96 | 96 |
| Maximum shared interface endpoint normal-angle difference | 18.5069° | 18.5069° | 18.5069° |

All 14 internal open edges cluster in coarse-cell IDs 1101, 1149, 1150 and 1199. Their reported endpoints lie within a few thousandths of world units of the local lattice points; canonical densities at the sample endpoints range approximately from `-3.89e-6` to `+7.84e-6`. They are within the patch, not among its 354 declared exterior open edges. A representative internal edge is `(10.74947, 3.999473, 5.749473)` to `(10.75, 3.999602, 5.749602)`; the complete edge list and density values are retained in the raw log. The present evidence confirms a real internal mesh-topology failure under the fixture oracle. It does not yet prove whether exact-zero classification, interpolation ordering, tetrahedron ownership, or another extractor detail is the root cause.

### Test-only collider proxy

The harness constructs disposable `ConcavePolygonShape3D` proxies because the pinned production source has no terrain collision provider. Across 72 ray queries, there were 33 hit/miss mismatches against the canonical expectation: 0 outside-to-cave and 33 cave-to-outside. The 39 finite ray-surface differences had p50 0.004853 and p95/max 1.369654 units; the remaining misses are represented as infinity and are not hidden in that finite summary. Across 36 discrete radius-0.1 sphere probes, contact-distance error was p50 0.130000, p95 0.130000 and max 0.130000 units at a 0.05-unit sweep step. This is a material failed proxy comparison, not evidence about a production collider. Back-face query behavior, triangle winding, and the internal openings have not been causally separated.

## Geometry and exploratory cost observations

All three approaches reported the same sampled cave diameters: 31 radial samples, p50 1.836347, p95 1.838929, max 1.839777 units. The mesh-vertex proxy `abs(canonical SDF)/|gradient|` was p50 0.002400, p95 0.103077, max 0.251931 units over 509 vertices; this is not symmetric Hausdorff distance. Mesh-normal-to-canonical-gradient angle was p50 0.4227°, p95 8.3194°, max 11.3042°. The maximum cell-interface endpoint normal difference above is separately reported. No geometry threshold is approved, and these sampled metrics cannot be scored for acceptance.

One headless process measured one build per method. The fixture's internal build timing ends after sampling and extraction; the outer timing includes the approach's additional topology, canonical-surface and field diagnostics. These are one-run timings, not percentiles or cold/warm benchmarks.

| Approach | Build through sampling/extraction | Whole approach incl. diagnostics | Fine scalar payload | Coarse scalar nodes | Triangles |
| --- | ---: | ---: | ---: | ---: | ---: |
| A | 966.193 ms | 1,902.889 ms | 207,360 B | 9,828 B | 7,118 |
| B | 986.019 ms | 1,813.767 ms | 83,268 B | 9,828 B | 7,118 |
| C | 955.585 ms | 1,648.366 ms | 135,108 B | 9,828 B | 7,118 |

The byte counts are only packed scalar node payloads; they are not peak RSS or total in-memory mesh cost. No disk cache or persistent snapshot was created, so disk storage, restart recovery, and serialized-size costs are not measured. Headless timings provide no GPU completion or presented-frame evidence.

## Attempts, validation, and exclusions

- The first hash-instrumented harness attempt failed due to declaring the snapshot radii as `PackedFloat32Array` when the API returns `PackedFloat64Array`, then dereferencing a dictionary key as a property. Both test-only issues were corrected. Earlier raw attempts remain in `C:\Users\PUBLI\AppData\Local\Temp\p31-r7-20ee67476732465c9279cd7b5a9adb6c`; `evidence/attempt-inventory.csv` inventories their paths, lengths and hashes. A large earlier stderr artifact was intentionally retained externally rather than copied into the PR.
- After adding complete two-direction collider gating and the explicit edited-case gate, both R7 scripts passed `--check-only`, then exactly one corrected zero-edit preflight ran and failed as recorded above. The earlier preflight and the corrected final preflight are both preserved.
- Full `scripts/validate.ps1` was run once on a clean tracked-source archive at R6-V final HEAD `0867c0c04b857fae1c71b274b8eac44c6e7dba4f`, with the project name changed only in that disposable archive to isolate Godot user data. The archive hash is `DBEF692C9E593D3CFB750B2CF0AD4250F2122990082D0D50B150E8F741715015`. It exited 1 after 00:10:00.9624893 with 21,458 assertion-marker checks and 5 failed assertions, all in `P3_0D_PLACEMENT_FAIL` (45 assertions, 5 failures). The other 20 marker suites passed. There were three existing colinear camera `look_at` warnings and no `SCRIPT ERROR`. The complete log is `evidence/full-validation.log`. This validates the tracked R6-V parent source, not the newly added R7 prototype as part of the canonical suite.
- R7 did not run either edited cave scenario, cross-chunk streaming/unload/reload, process restart, broad performance repetitions, GPU profiling, or production collision tests. The frozen R6-V raw results remain the source of the 4.875 opening and 0.153837 boundary gap comparison.

## Findings, recommendation, and next gate

1. **Blocking topology:** every tested policy has 14 open edges inside the bounded patch. The edge neighborhoods have scalar values close to zero. Do not continue to edited caves until the extraction/topology cause is isolated and the zero-edit mesh gate passes.
2. **Blocking collider-proxy parity:** 33 reverse-direction ray outcomes differ; sphere contact is displaced by about 0.13 units. The cause is unresolved and the proxy is not a production collider, but it does not meet the diagnostic's exact hit/miss preflight.
3. **No comparative geometry outcome:** A/B/C generated identical zero-edit position/normal bytes, despite different refined/transition counts. The fixture shows distinct resource policies but has not yet shown distinct output behavior for the control case.
4. **No performance conclusion:** one run per method, and no RSS/disk/frame/GPU data. The full campaign was correctly stopped by the topology/collider gates.

Recommended next bounded research step: isolate a minimal zero-edit tetrahedron fixture at the four implicated cells, preserve the canonical scalar bytes, and identify why the extracted interior edge is open; separately verify whether cave-to-outside proxy misses result from face orientation/back-face physics semantics or the mesh cracks. Add deterministic exact-zero and near-zero cases. Re-run only the zero-edit gate after a correction. If that passes, run the two frozen edited snapshots once each before any larger measurement matrix. No production adoption, geometry tolerance, storage change, or Issue #108 action is recommended by this evidence.

## Reproduction

From the R7 worktree with Godot 4.7.2:

```powershell
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path .\game --check-only --script res://tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path .\game --check-only --script res://tests/prototypes/p3_1_r7_conforming_adaptive_diagnostic.gd
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path .\game --script res://tests/prototypes/p3_1_r7_conforming_adaptive_diagnostic.gd -- --preflight-only
```

The final command is expected to return nonzero until both internal topology and all-direction collider preflight gates pass. Do not invoke `--run-edited-after-preflight` unless a fresh zero-edit run passes. Raw command records, stdout/stderr, canonical manifest bytes, full validation output, source/evidence checksums and the external-attempt inventory are under `evidence/`.

All five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
