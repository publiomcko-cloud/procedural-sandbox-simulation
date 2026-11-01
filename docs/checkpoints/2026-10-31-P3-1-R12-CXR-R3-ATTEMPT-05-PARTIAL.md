# P3.1 R12-CXR R3 attempt 05 partial geometry result

Date: 2026-10-31 America/Sao_Paulo; process timestamps are UTC.

## Disposition

`R3_TARGET_20261031_05` started exactly once for frozen scenario `R9.2.SEAM.XPLUS_EQUAL.v1` on measured code source `4734e6cb0c80cde086ea86e7d8afcda983e3a24b` and ended with `R12_CXR_PARTIAL_WITH_EVIDENCE`. The equal-LOD geometry gate failed closed with `cx_bounded_patch_search_failed`. This is neither `R12_CXR_ARCHITECTURE_QUALIFIED` nor a completed/exhaustive no-solution result. Do not label the R12-CXR realization family exhausted and do not rerun this attempt.

The target reached R3 field-support generation. The frozen attempt is consumed. The result does not establish that the fixed-fan support realization is geometrically impossible: one cavity hit its preregistered candidate-generation cap before triangulation, while the other had no valid patch boundary in levels 0–3. No downstream gate or broad validation was run because equal-LOD did not pass.

## Identity and execution evidence

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Branch: `exp/p3-1-r12-cxr-per-cavity-continuation`.
- Code source and exact execution checkout: `4734e6cb0c80cde086ea86e7d8afcda983e3a24b`; direct parent `43afc868c9d86678834b3469feef6fd5b8b83180`.
- Draft PR #214 is open, draft and unmerged; its live head at recording is `a0449260643bb25080aa96c79a96094d376f6557`. PRs #212 and #213 remain open/draft/unmerged.
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Measured source physical SHA-256: campaign `1b3a73845ef5bafec6d16fe2a7928ee3599c5e70ba5310070cb845af3687145b`; R3 field-support realizer `a96cc49aeb162381c13f972ef66ad1ece076f1244689362cc8f0a4c7d3d1f7c2`; contract tests `25d86eb5e91a7096ad73244d0710e14379283b757c343673af637e22bcd3e8b7`.
- Frozen input SHA-256: manifest `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`; topology fixture `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`; residual fixture `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23`; Candidate D `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`.
- Scenario and attempt: `R9.2.SEAM.XPLUS_EQUAL.v1`, `R3_TARGET_20261031_05`.
- Godot PID 14544, dispatcher parent PID 45136. Start `2026-11-01T01:08:08.8957542Z`; end `2026-11-01T01:08:19.1342042Z`; exit 0; 45-second timeout not reached; 18 resource samples; no resource stop. `scenario_started=true`.
- Stdout contains exactly one target-begin marker, one R3 support-generation-begin marker and one geometry-complete marker. It contains no parser or script error. Stderr is empty. Exit 0 is process status only; the campaign result is PARTIAL.
- The pinned pretarget gates remain the attempt-05 records: editor import PASS; CXR contracts PASS, 153 assertions and zero failures; campaign check-only PASS; controlled dispatcher child PASS. No runtime suite was rerun after target execution.

## Geometry and search findings

The frozen volume gate passed with volume SHA-256 `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` and payload SHA-256 `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`.

| Cavity | Per-level outcome | Disposition |
| --- | --- | --- |
| `e89d7e6444ead8c6` | L0 and L1 had no boundary-valid patch subset. L2 produced a valid 4-triangle patch boundary and reached field-support generation. It recorded 8,192 attempts, 145 support rows / 114 unique support positions, zero candidate triangles and zero triangulation search nodes. | Candidate-generation cap `MAX_CANDIDATE_ATTEMPTS_PER_CAVITY` reached; L3 marked not run; `search_complete=false`, `search_exhaustive=false`. |
| `aefae75e246e6d28` | L0–L3 each recorded an invalid boundary (`boundary_cycle_vertex_count_invalid`, `r3_patch_open_edge_has_no_remaining_owner`, or `r3_surviving_edge_winding_inconsistent`, as detailed in the raw result). | No candidate generation; all four levels have explicit invalid-boundary records. |

Thus the attempt exercised the corrected adjacency traversal and began candidate generation, but produced no candidate triangles or realized geometry. `geometry_realizer_valid=false`; topology, cutoff, mesh, support selection and geometric deviation fields not produced by the failed path remain `UNKNOWN_NOT_CAPTURED`, not zero. Controls 6/6, ROI rays 0/25, mixed LOD, determinism, full E2E and `scripts/validate.ps1` are `NOT_RUN_EQUAL_LOD_GATE_FAILED`.

## Raw evidence integrity

All 14 raw process/result artifacts are retained under [`r3_target_attempt_05`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_target_attempt_05/). Their physical-byte SHA-256 values are listed in [`evidence-sha256-index.txt`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_target_attempt_05/evidence-sha256-index.txt); the index SHA-256 is `1bded78c614f5d1373c338fc32e5aaba905f59bfe562fb0ee51707f565094fd2`.

- Result JSON physical SHA-256: `25aada1c7f1e8030ebd83f7b1ffd5b9edaebd9a4e3036d24aecc011995df85c5`, matching the campaign's result marker.
- Stdout SHA-256: `a12b8e2b63aff31aec62dfa431404b2a1b695bcdd23c624a3362f9ea77fdef7d`.
- Stderr SHA-256: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` (empty).
- Resource-sample SHA-256: `183ff894ce6eff82e669fd03e34090d99a79ee43293f73a277122d6a44791504`.
- Result, stdout, stderr and resource-stream bytes independently match their recorded hashes.

## Scope and holds

No source or frozen input changed during this attempt. The generated `.gd.uid` files in the detached execution checkout and existing development worktrees/stashes were preserved. No production path, save, schema, Issue #108/#154, PR #212/#213, merge, release, or protected F2-G1 operation was performed.

`CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD` remain unchanged.
