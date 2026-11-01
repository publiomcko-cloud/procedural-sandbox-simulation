# P3.1 R12-CXR R3-A/R3-B Implementation Closeout

**Campaign status:** `R12_CXR_R3B_PARTIAL_WITH_EVIDENCE`
**Measured source:** `16c3dbea7d1b8cd9755ee1f9546516bf45f9181d`
**Source parent:** `78cbe7a45a85c65042c607e683abcd24f977db26`
**Source tree:** `70ef36100dca3821ec113619a07ce484920f3c5f`
**Base:** PR #214 head `5eb82baefe36c7e5f0f8c2e1d500c9895cf54d3a`; production reference `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.

This is a bounded experimental result, not a geometry qualification, production adoption, or proof of infeasibility. Six valid target executions have been consumed under the procedure's six-attempt limit. No prior target was repeated.

## Source change

The final correction is test-only and touches the R3 field-support realizer and its contract tests. It leaves the frozen architecture, geometry inputs, tolerances, SDF, production code, save schemas, and search limits unchanged.

- Indexed patch rows now follow the ordered subset directly, avoiding a per-candidate ID set; rows are sorted only if the supplied order is not already canonical.
- Invalid candidate boundaries use compact incidence diagnostics. Full C6 incidence diagnostics are regenerated only for boundaries that pass the compact screen.
- Patch connectivity is computed only after boundary validity. Before acceptance, the full and compact boundary paths must agree on validity, reason, directed edges, and signature; a mismatch fails closed.
- Reports now expose offending expansion candidate IDs and the screening policy.
- Regression coverage verifies compact/full parity for valid and invalid boundaries and parity of the exact expansion-candidate list.

Godot import passed. The contract suite passed **193 assertions, 0 failures**. The commit's exact-source pretarget additionally passed realizer `--check-only` and campaign internal `check-only`.

## Target campaign

Frozen target: `R9.2.SEAM.XPLUS_EQUAL.v1`. All six valid attempts started once, exited with a machine-readable `PARTIAL` result, and remain preserved in the evidence archive. Attempt sources and outcome details are in `evidence/r3ab-campaign-attempt-matrix.json`; the 99-file raw archive and SHA index are `evidence/r3-target-attempts-06-11-evidence.zip` and `evidence/r3-target-attempts-06-11-evidence.sha256`.

| Attempt | Source | Main cavity result | Other cavity result |
|---|---|---|---|
| 06 | `c04579e1da799ce1c315439c5c1615763e3d7ef2` | 8,192 support attempts; 145 rows / 115 unique positions; 0 candidate edges, 0 candidate triangles; boundary preflight blocked | 131 patch-selection nodes; no valid boundary |
| 07 | `2f6967a46cce2e8d7eef39cb452c2285419d1d61` | Same retained pool and zero triangles; R2 cavity-domain validation rejected the selected subset | 131 nodes; no valid boundary |
| 08 | `2d23755a52f316e54e0569bf0dd421324669fd69` | Boundary search reached the per-cavity time cap after 1,340 nodes | 131 nodes; no valid boundary |
| 09 | `8a55954ce4fae1852ada83c5ddd744088d656041` | Per-cavity time cap after 1,323 nodes | Total-time cap after 1,005 nodes |
| 10C | `78cbe7a45a85c65042c607e683abcd24f977db26` | Per-cavity time cap after 11,288 nodes | 1,539 nodes; no valid boundary through radius 4 |
| 11 | `16c3dbea7d1b8cd9755ee1f9546516bf45f9181d` | Per-cavity time cap after 11,787 nodes; level 3 stopped at 10 seconds | 1,539 nodes; no valid boundary through radius 4 |

The procedure's R3-A minimum is **not met**: attempts 06–07 retained a nonempty support pool, but produced no candidate edges or triangles and no admissible explanation proving that every retained support is unusable. In attempts 08–11, cavity boundary search prevented support generation from starting.

For R3-B attempt 11, cavity A `e89d7e6444ead8c6` had no boundary-valid subset at radii 0–2 and timed out at radius 3. Cavity B `aefae75e246e6d28` completed the bounded radius-0–4 subset enumeration (1,539 nodes) but no valid boundary was found. Rejection counts included `boundary_cycle_vertex_count_invalid` and `r3_patch_open_edge_has_no_remaining_owner`. No selected patch, boundary cycle, supports, candidate triangles, or triangulation search exists for cavity B. No joint-cavity search was eligible because neither independent cavity produced a valid minimum patch.

The compact screening change improved the number of level-3 subsets examined under the same 10-second cap from 4,828 in attempt 10C to 5,594 in attempt 11 (15.9% more); level-3 generated nodes changed from 9,908 to 10,407. This is only an observed bounded-search counter comparison, not a controlled performance benchmark. The time cap still stopped cavity A.

## Attempt 11 process and resource evidence

- Attempt ID: `R3_TARGET_20261101_11_16C3DBE`.
- Exact detached checkout: `C:\r12cxr-r3ab-target-16c3dbe`; origin verified and source SHA matched.
- Godot: `4.7.2.stable.official.ed1daf0bf`, binary SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Godot PID 46308, recorded parent PID 44972; dispatcher PID 44972. The dispatcher runner PID was 20084. Engine command line and parent attribution are captured. OS ancestry of the dispatcher runner itself was not independently captured.
- Exit code 0; no process timeout, resource stop, output-write error, or stderr content. Exactly one target-start marker and one geometry-complete marker.
- 27 commit-memory samples; free commit ranged from 8,700,768,256 to 8,972,599,296 bytes. No warning or stop threshold was reached. This is commit-headroom telemetry, not Godot RSS or total RAM usage.
- Target result SHA-256: `2d1637a4d646ec30a4888018b4bad02551ad565ebe250d04d6490f5e5745226f`; stdout `c45a2b7c218bce8e24c17086400613fb64c43f158d63a6e1e423d80fcb4b3db1`; empty stderr `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`; resource samples `06034c67cd7b8336ce00ddaf8398cbcac37322fd99bc69b242ce1948b121b2aa`.

The volume gate passed unchanged: volume SHA `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`, payload SHA `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`, revision 2.

## Required final fields

| Field | Disposition |
|---|---|
| `R3A_STATUS` | `R12_CXR_R3A_PARTIAL_WITH_EVIDENCE` — support-pool continuation did not generate candidate edges/triangles |
| `R3A_CAVITY_A_SUPPORT_ATTEMPTS` | 8,192 in attempts 06–07; not run in attempt 11 |
| `R3A_CAVITY_A_UNIQUE_SUPPORTS` | 115 in attempts 06–07 |
| `R3A_CAVITY_A_CANDIDATE_EDGES` | 0 in attempts 06–07 |
| `R3A_CAVITY_A_CANDIDATE_TRIANGLES` | 0 in attempts 06–07; `NOT_RUN` in attempt 11 |
| `R3A_CAVITY_A_SEARCH_NODES` | 0 after triangle generation in attempts 06–07; `NOT_RUN` in attempt 11 |
| `R3A_CAVITY_A_SOLUTION` | `NONE` |
| `R3B_STATUS` | `R12_CXR_R3B_PARTIAL_WITH_EVIDENCE` |
| `R3B_CAVITY_B_PATCH_SELECTION_NODES` | 1,539 in attempt 11 |
| `R3B_CAVITY_B_SELECTED_PATCH_SIZE` | `NONE` |
| `R3B_CAVITY_B_BOUNDARY_COMPONENTS` | `NOT_CREATED` |
| `R3B_CAVITY_B_BOUNDARY_VALID` | `false` for all searched candidate subsets |
| `R3B_CAVITY_B_SUPPORTS` | `NOT_RUN` |
| `R3B_CAVITY_B_CANDIDATE_TRIANGLES` | `NOT_RUN` |
| `R3B_CAVITY_B_SEARCH_NODES` | `NOT_RUN` |
| `R3B_CAVITY_B_SOLUTION` | `NONE` |
| `JOINT_CAVITY_USED` | `false`; no eligible intersecting valid patches |
| `FINAL_EQUAL_LOD` | `false` / not qualified |
| `FINAL_TOPOLOGY_ROUNDTRIP` | `NOT_RUN` |
| `FINAL_MISSING_OBLIGATIONS` | `UNKNOWN_NOT_CAPTURED` |
| `FINAL_INTERNAL_OPENS` | `UNKNOWN_NOT_CAPTURED` |
| `FINAL_NONMANIFOLD` | `UNKNOWN_NOT_CAPTURED` |
| `FINAL_WINDING` | `UNKNOWN_NOT_CAPTURED` |
| `FINAL_DEGENERATES` | `UNKNOWN_NOT_CAPTURED` |
| `FINAL_MIN_CROSS_SQUARED` | `UNKNOWN_NOT_CAPTURED` |
| `FINAL_CUTOFF_REJECTIONS` | `UNKNOWN_NOT_CAPTURED` |
| `FINAL_CONTROLS` | `NOT_RUN_EQUAL_LOD_GATE_FAILED` |
| `FINAL_RAY` | `NOT_RUN_EQUAL_LOD_GATE_FAILED` |
| `FINAL_VOLUME` | `PASS` (frozen SHA/payload/revision above) |
| `FINAL_MIXED_LOD` | `NOT_RUN_EQUAL_LOD_GATE_FAILED` |
| `FINAL_DETERMINISM` | `NOT_RUN_EQUAL_LOD_GATE_FAILED` |
| `FULL_E2E_RESULT` | `NOT_RUN_EQUAL_LOD_GATE_FAILED` |
| `FULL_VALIDATION_RESULT` | `NOT_RUN_EQUAL_LOD_GATE_FAILED` |
| `EVIDENCE_INTEGRITY` | `PASS` for the 99-file target archive, archive SHA index, pretarget gate indexes, source pins, and attempt-11 result hashes |
| `FINAL_ARCHITECTURAL_DISPOSITION` | `PARTIAL_NOT_INFEASIBLE`; bounded attempt budget exhausted without equal-LOD candidate |

## Evidence and repository state

- Exact source file physical SHA-256: campaign `dc8f240262c04e4947328bea164893f4749c2cb12506c5c9b770e449487650c6`; realizer `8600219821636067c4ecf6672450726dfeada5b2e899ede9141b193ebd132b9a`; contract tests `4fad905afd9636253f45a2256f10a375638615581fb374dfe728c96399d83c67`; C6 campaign `9a695705c47ad6473b773bbfaeaf35d88306cee6804113a0b1a71c6faca2f348`; C6 realizer `31947e1944a017442ad14cc4f098e67db800d4f5e196d07e047b93dc0fe9d2ac`.
- Git blobs for measured R3 source: realizer `506003e0cb8e0741d1293da501ac5da4c3bd95a7`; contract tests `c6b08145defd44da9f941d1d110f969960413ad8`; campaign `c4dd3fb0678c9a93e8d7a0c26792fb24acb592e6`.
- Attempt archive: `r3-target-attempts-06-11-evidence.zip`, SHA-256 `e5c568d9e88ffaf8404ec0ce41d0cda2fb8a036410817478a3c02d42399b6692` (7,528,804 bytes, 99 files). Every archived member was independently rehashed: 99 verified, 0 missing, 0 mismatches. Sidecar SHA index: `6754aaa65c7aa57c91397a47b76923ee70d22b8fcf33c7006d2f59acd41dd9a0`.
- Attempt-11 index SHA-256: `7daaa3fd8f3467a533374d183442b56b5cd4d267f453760abba95883d6e73c49`. Pretarget-02 index: `d774b8e5bce20369bf24fa0e8d2d101d862ddbc3ea66b62aa943c49389f02f90`; its 17-member archive SHA-256 is `dc5ab4604c2bee62d8eabd82bb0a83e2c64b8519644a892bf77bdf4853d699c1` (343,306 bytes; all members verified). Six-attempt matrix SHA-256: `f5cc3673554bd83a5cfc1d7e8f932fc0b0dee6d82fad4dd95f6eabe5d6435cea`.
- One pretarget wrapper recovery (attempt 01) failed before Godot because a detached branch name was empty and `.Trim()` was called on null. Its failure record is preserved. A second fresh evidence set passed all four gates; no pretarget issue started a target.
- Target attempt 10B was a prelaunch PowerShell 5.1 `Get-FileHash` environment failure; it did not start a target. The corrected run used PowerShell 7.6.9. Attempts 06–11 are the six consuming target executions.
- PRs #212, #213, and #214 remain open/draft/unmerged. This closeout is a separate draft stacked on #214; publication is `RECORDED_IN_DRAFT_PR / NOT_INTEGRATED`.
- The implementation workspace, isolated target worktrees, stashes `stash@{0}` and `stash@{1}`, untracked `.gd.uid` files, and all prior attempt evidence were preserved. No production source, saves, schema, or PR #212–#214 was modified.
- All five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

## Stop condition and next step

The six permitted valid targets are exhausted. Do not rerun any target from this campaign. The current evidence does not establish mathematical or architectural infeasibility. Further work would require a new bounded authorization and should first address (a) why attempts 06–07 created no legal candidate edges/triangles from the retained support pool, and (b) why the remaining-C6 boundary search cannot produce a valid minimum patch for cavity B within its radius/time limits. No downstream controls, mixed-LOD checks, full E2E, `scripts/validate.ps1`, integration, or release are authorized by this partial result.