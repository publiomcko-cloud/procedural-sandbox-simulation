# CHK-2026-10-22-P1-1B-B1-1-N128-UNSCORED-REVIEW

**Recorded:** 2026-10-22, America/Sao_Paulo. Exact host execution date is not independently attested.
**Event:** consequential N128 frozen 128-edit ledger preflight and independent command-digest source review.
**Publication:** existing separate docs-only draft PR #101; NOT integrated or merged at creation.
**Disposition:** `N128_UNSCORED_CONTRACT_REVIEW_PASS / CODEX_EXECUTION_REPORTED_PASS / DIGEST_INDEPENDENTLY_MATCHED / NO_BENCHMARK_ACCEPTANCE`.

## Source identity and scope

Repository: `publiomcko-cloud/procedural-sandbox-simulation`. Verified remote `main`: `ea4422d90726d3f2fe6d5cef097126268f93685a`. [Feature PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) remains open/draft/unmerged at exact reviewed R7 commit `2b4355363a43b73476715cf4002e31575bf9828d`, direct parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`. Separate [PR #100](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/100) remains draft/unmerged; no feature/source/manifest modifications occurred in the N128 run.

Frozen manifest `game/tests/fixtures/p1_1b_b0_manifest.json` blob `fde2ff84e2754cfef48052b32998903f45276aa1`; external manifest and sidecar SHA-256 pin `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd`. N128 scenario ID `B0A.INTERIOR.N128.v1`, FROZEN, `ledger_replay`, `operation_count=128`, expected support `["0,0"]`, seven parity probe offsets. Authorized Godot 4.7.2 executable physical SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` reported matched.

## Independently verified exact-source command identity

The reviewer inspected the pinned canonical `Contract.build_commands`, `_command`, sorted-key canonical JSON and `command_list_sha256` functions. Reconstructed all 128 commands, `sequence=i` for `i=0..127`, alternating CARVE/FILL, radius 580 mm and centers `[8000+(i%4)*100,3200,6000+(floor(i/4)%4)*100]` mm. Independently computed exact SHA-256 of the canonical JSON command array:

`62fd8b69b2727007c77a98084cfbf2545f690d0b23f2967cb22fd0f112bf128a`

This matches both previously specified independent reference and the Codex-reported terminal replay digest. Source semantics require 128 accepted edits, revision 128 and last_sequence 127; seven probes per edit yield 896 parity probes.

## Actual Godot execution: Codex-reported, not independently replayed

| Stage | Codex-reported result |
| --- | --- |
| A — detached cold editor import | PASS; exit 0; 11.73 s |
| B — harness `--check-only` | PASS; exit 0; 4.42 s |
| C — R7 contract suite | PASS; exit 0; 4.40 s; 2,586 assertions, zero failures, 11 groups |
| D — one frozen N128 `UNSCORED` | PASS; exit 0; 5.20 s; zero failures |

Codex reported **132 JSONL events**: one `scenario_started`, 128 `ledger_command_accepted`, one successful `ledger_replay_result`, one terminal `scenario_complete=PASS`, one logger-overhead record. No duplicate/out-of-order sequence or mismatched accepted-command prefix digests. All 128 commands, last_sequence 127, revision/count 128, support/rebuild `["0,0"]`, dependencies empty, 896/896 full-vs-filtered SDF parity PASS. Process-local clock and event/parent/run identities reportedly validated; four stderr logs empty. **These runtime claims were not independently checked against raw Windows files by the remote reviewer.**

Godot PID **33056** was reportedly observed as a child of launcher PID **54052** using live PID polling with captured command lines; that establishes reported provenance for this invocation only, not an independent attestation of OS process metrics. Prior N032 PID mismatch remains a historically unresolved separate invocation. Codex reported three pre-scenario setup fixes (manifest field lookup, CIM event-subscription fallback to PID polling, PowerShell evidence-finalizer parser). None required source modifications or a scenario restart.

Raw evidence reported retained at `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_n128_fc9eaa98f6eb4001b76eca91cfa42294_evidence`, with parsed JSONL, integrity, event identity and artifact hash files. Development worktree, three existing untracked `.gd.uid` hashes and `stash@{0}` reportedly preserved.

## Boundary and next gate

**UNSCORED only**: these results establish neither approved numeric CPU/GPU latency budgets nor presented FPS, memory RSS/VRAM, visual GUI acceptance or production LOD readiness. No P1.1C, native Voxel Tools, production terrain changes or merge are approved. All five protected F2-G1 holds continue: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

[Independent N128 review on PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6340831811) records the execution grading.

**Next candidate:** exactly one frozen `B0A.INTERIOR.N255.v1` UNSCORED run on the same exact source, isolated preflight (Godot binary/manifest), import, harness check-only and contract suite, then 255 edits, sequences 0..254, revision/count 255, last_sequence 254, 1785 expected probes, independent digest `b68066c669dd56126fc1fe39f802bc87e2c9e20e29d57e9842b110eb62e03156`. The separate `N256` capacity-boundary scenario should wait for independent N255 evidence review. Permit bounded pre-scenario operational fixes only; never silently relax contract/scenario checks. No full scenario matrix, scored benchmarking, native dependencies, protected operations or merge. Previous documentary checkpoints are not altered retrospectively.
