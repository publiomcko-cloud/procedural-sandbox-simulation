# CHK-2026-10-22-P1-1B-B1-1-EDGE-POS-X-N032-UNSCORED-REVIEW

**Recorded date:** 2026-10-22, America/Sao_Paulo; exact Windows-host execution timestamp not independently established.
**Status:** `EDGE_POS_X_N032_UNSCORED_CONTRACT_REVIEW_PASS / CODEX_RUNTIME_PASS_REPORTED / PID_PROVENANCE_UNRESOLVED / NO_PERFORMANCE_ACCEPTANCE`.
**Publication:** existing documentation-only draft PR #101, not merged at creation. Prior N000–N256 checkpoint files remain unchanged.

## Verified remote identity and contract

Repository `publiomcko-cloud/procedural-sandbox-simulation`; main `ea4422d90726d3f2fe6d5cef097126268f93685a`. [PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) remains open/draft/unmerged at reviewed R7 HEAD `2b4355363a43b73476715cf4002e31575bf9828d` (parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`); PR #100 remains a separate draft. Frozen `B0A.EDGE.POS_X.N032.v1` is 32-operation ledger replay across the +X region boundary. Pinned manifest Git blob `fde2ff84e2754cfef48052b32998903f45276aa1`, external SHA-256 pin `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd`; Godot executable pin `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` Codex-reported checked.

## Independent source and digest verification

Reconstructed 32 canonical commands from R7 `Contract.build_commands()` and sorted-key JSON rules. For i=0..31: zero-based sequence i; alternating CARVE/FILL; radius 580 mm; centers `[15700+(i%3)*20,3200,6000+(floor(i/3)%3)*20]` mm. Independently calculated full-list SHA-256:

`fde68db5ad3248d6a155cc9e54fb6cda664e274348968219c95f151a33a5b305`.

This matches Codex's final replay digest exactly. Source/frozen contract sets two support regions `["0,0","1,0"]`; rebuild/dependency sets must be checked against actual operation metadata, and need not be assumed from unrelated interior scenarios. Expected sequence 0–31, last_sequence=31, revision/edit count=32, 32×7=224 parity probes.

## Codex-reported Windows execution (raw evidence not independently replayed)

| Gate | Result |
| --- | --- |
| A cold editor import | PASS, exit 0 |
| B harness check-only | PASS, exit 0 |
| C R7 contracts | PASS, 2,586 assertions, 0 failures, 11 groups, exit 0 |
| D exactly one EDGE_POS_X N032 | PASS, exit 0, 32 accepted commands, zero scenario failures |

36 JSONL events were reported (one start, 32 acceptances, one successful replay, one completion PASS, one logger overhead); command centers, modes, radii, 32 prefix SHA digests and final digest matched; actual support/rebuild regions `["0,0","1,0"]`, dependencies empty per every event; 224/224 full-versus-filtered SDF probe parity PASS, expected probe positions and probe-command digest matched. Event/run/parent identity, ordering and process-local clocks reportedly validated. Thirty artifact hashes reportedly matched.

Raw evidence retained by Codex in `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_edge_posx_n032_268d1b85c05343f9a30dbb63177be777_evidence`, not independently read/replayed here. **Host PID attribution remains unresolved:** launcher PID 57148 and Godot PID 11344 were not linked; do not attribute any CPU/RSS/GPU process metrics. Tracked worktree remained clean, existing untracked `.gd.uid` files and `stash@{0}` preserved; prior evidence remained intact; no other scenario, source edit, protected F2-G1 action or merge.

**Evidence grading:** independent GitHub source/manifests and final command digest checked; actual Godot events, all prefix digests, runtime probes and Windows files remain Codex-reported. This is **UNSCORED experimental ledger fanout evidence**, not validation of production mesh seams or rendering, geometric LOD, end-to-end streaming, process-resource performance, GUI or release.

## Next isolated candidate and holds

Recommend exactly one `B0A.CORNER.POS_XZ.N032.v1` UNSCORED run: four-region corner support `["0,0","1,0","0,1","1,1"]`, 32 edits, 224 parity probes, expected sequences 0..31 and revision/count=32, first center `[15800,3200,11800]` mm, independent command-list SHA-256 `5b3759d8441a16615751192d0036a80b227377c3d624f6f5a382a87a142f5fa5`. Verify rebuild/dependency fanout against source and observed operation evidence; do not assume empty dependencies. Use same exact reviewed R7 SHA, pinned binary/manifest, cold import, harness check-only and R7 contracts before exactly one scenario run. Permitted bounded host-only recovery before scenario start, plus report reconstruction from immutable logs, no automatic retry after scenario begins. Do not run negative corner, distributed, streaming/LOD, or a broad matrix in that task.

PRs #99/#100/#101 remain draft/unmerged. Five protected F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. [PR #99 independent review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6342282976).
