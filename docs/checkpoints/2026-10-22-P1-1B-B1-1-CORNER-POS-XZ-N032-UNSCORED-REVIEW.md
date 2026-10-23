# CHK-2026-10-22-P1-1B-B1-1-CORNER-POS-XZ-N032-UNSCORED-REVIEW

**Date recorded:** 2026-10-22 (America/Sao_Paulo). Host execution timestamp not independently attested.
**Review disposition:** `CORNER_POS_XZ_N032_UNSCORED_CONTRACT_REVIEW_PASS / CODEX_REPORTED_RUN_PASS / INDEPENDENT_CANONICAL_DIGEST_MATCH / NO_PERFORMANCE_OR_MERGE_APPROVAL`.
**Publication:** added to existing separate documentation-only draft PR #101, not integrated. Earlier immutable checkpoint files preserved.

## Remote provenance and frozen scope

[Feature PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) was verified open/draft/unmerged at exact R7 HEAD `2b4355363a43b73476715cf4002e31575bf9828d`, parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`; remote main `ea4422d90726d3f2fe6d5cef097126268f93685a`. [PR #100](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/100) remains a separate draft. The frozen `B0A.CORNER.POS_XZ.N032.v1` scenario has type `ledger_replay`, recipe `CORNER_POS_XZ`, 32 commands, expected four-region support [0,0], [1,0], [0,1], [1,1]. Manifest Git blob `fde2ff84e2754cfef48052b32998903f45276aa1` and expected external SHA-256 `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd` remain pinned. Godot 4.7.2 binary SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` was Codex-reported verified.

## Independent source review

Rebuilt all 32 commands using the exact source `Contract.build_commands()` and sorted-key `canonical_json()`: index/sequence 0–31, alternating CARVE/FILL, radius 580 mm, center `[15800+(i%2)*10,3200,11800+(floor(i/2)%2)*10]` mm. Independently computed full canonical command JSON SHA-256:

`5b3759d8441a16615751192d0036a80b227377c3d624f6f5a382a87a142f5fa5`.

This matches the reported replay final digest. Source expected count/revision 32, last_sequence 31, seven probes per command (224).

## Codex-reported execution; not an independent Windows replay

Cold editor import, harness `--check-only`, R7 contract suite (2,586 assertions, zero failures across 11 groups) and **one** frozen CORNER +XZ scenario all reportedly exited 0. 32 accepted canonical commands; 36 JSONL records including scenario start, 32 accepted, successful replay, terminal PASS, overhead; all 32 prefix digests reportedly matched. Actual support/rebuild keys for every operation [0,0], [0,1], [1,0], [1,1], with empty additional dependency keys; corroborated in running host report using 0.58m brush radius and 0.50m rebuild sampling halo. Full-vs-filtered SDF query parity **224/224** PASS, probe location identity and digest matched. Live process observation reportedly linked launcher PID 53668 to direct child Godot PID 53564.

One erroneous host-side preflight check reading failed contract-suite plan was corrected to inspect the passing plan before scenario start; no rerun of scenario, no source changes. Raw host logs and 26 hashed artifacts reportedly retained at `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_corner_posxz_n032_64f034dd4f6049d496073b1971344ce2_evidence`. Workspace state, existing three untracked `.gd.uid` files and `stash@{0}` reportedly preserved.

**Evidence limit:** the reviewer independently confirmed source/manifest, canonical command digest and structural expected checks; raw Windows process, JSONL/parity, 26 file hashes and parent PID observation are Codex-reported, not independently replayed. This is UNSCORED ledger geometry-support evidence, **not visual mesh seam acceptance**, GPU-completed timing, presented FPS, RSS/VRAM, target-hardware performance or production release.

## Consolidated next gate

At owner's request to avoid one review per short test, the next bounded task should group **all 11 remaining frozen ledger/seam cases** into one evidence-backed mission: eight unexecuted B0A ledger_replay variants (EDGE.POS_X N128/N256, CORNER.POS_XZ N256, CORNER.NEG_XZ N032/N256, DISTRIBUTED N032/N128/N256), plus three B0E.SEAM CARVE_FILL ledger_commands variants (POS_X, POS_XZ and NEG_XZ). One external pinned preflight and R7 contract suite, then **one isolated Godot process per scenario**, run each at most once, preserving stage-level logs/digest/parity/evidence artifacts independently. Substantive failure of a scenario is not a reason to alter the canonical contract or retry that scenario; continue independent tests if the common environment remains trustworthy, retaining all failures. A single consolidated report and subsequent reviewer checkpoint replace 11 separate owner-review interruptions.

The three B0E cases are explicitly **ledger replay only**, with `geometric_scoring=EXCLUDED_UNTIL_NONEMPTY_EDITED_CONTOUR_PREFLIGHT`; do not misstate as actual edited LOD contour/geometric acceptance. Streaming, standalone LOD, tunnels, edited reload, any NOT_FROZEN cases, scored benchmarks, native Voxel Tools and production code stay out of this batch.

All five F2-G1 holds (`CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`) and separate PRs #99/#100/#101 draft/unmerged remain unchanged. [Independent PR #99 review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6343147092).
