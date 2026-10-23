# CHK-2026-10-21-P1-1B-B1-1-N001-SEQUENCE-RECONCILIATION

**Date:** 2026-10-21, America/Sao_Paulo.
**Type:** consequential source-based acceptance-gate correction and reported N001 execution.
**Publication:** separate docs-only draft PR #101, unmerged at creation.
**Source:** feature PR #99, R7 HEAD `2b4355363a43b73476715cf4002e31575bf9828d`; `main` `ea4422d90726d3f2fe6d5cef097126268f93685a`.

## Independent source finding

The previous N001-R1 external task erroneously required `last_sequence=1`. The reviewed frozen contract `build_commands` assigns `sequence=index` starting at zero, and the tests require the same. The production ledger initializes `_next_sequence=0`, assigns sequence before increment, and `get_last_sequence()` returns `_next_sequence-1`. Consequently, **N001 requires sequence=0, last_sequence=0, revision=1 and edit_count=1**. No project-source correction and no N001 rerun is required.

## Developer-reported run

The PowerShell invocation helper was repaired outside the repository using `GodotArguments` and `ProcessStartInfo.ArgumentList` with a token-by-token argument dry-run. On a fresh exact-R7 checkout, Codex reported editor import PASS (exit 0), harness check-only PASS (exit 0), R7 contracts PASS (2,586 assertions, 0 failures, 11 groups), and one N001 UNSCORED scenario PASS (exit 0).

N001 accepted one CARVE at `[8000,3200,6000]` mm, radius 580 mm; support and rebuild `["0,0"]`, dependencies empty; all seven SDF parity probes passed. Reported canonical command-list SHA-256: `411573e8f9bb182fe847e8d5cfdd02a3761817c1a9534d993086d6123d9a7187`. Five JSONL events were reported consistent. Launcher PID 53584 and Godot PID 53020 were reportedly correlated by process provenance evidence.

Host logs at `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_n001r1_8464f24b5566459e9153e66ea2013fef_evidence` were not independently retrieved or replayed: runtime PASS remains **Codex-reported**, while zero-based source semantics were independently verified. [PR #99 review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6324982313).

## Disposition and next gate

`N001_R1_UNSCORED_REPORTED_PASS / FALSE_EXTERNAL_LAST_SEQUENCE_GATE_RECONCILED / NO_RERUN_REQUIRED`.

This supersedes the prior N001 R1 blocker *interpretation*, not the earlier real PowerShell-launcher failure or the historical N000 checkpoints. No scoring, OS/GPU benchmarks, production changes, PR merge, P1.1C or native Voxel Tools approval. Five F2-G1 holds remain.

Next candidate: one frozen `B0A.INTERIOR.N032.v1` UNSCORED run under standing Godot permission, same reviewed SHA, after isolated preflight. Verify 32 commands, sequences 0..31, revision 32, last_sequence 31, parity and terminal PASS. Keep raw evidence and permit bounded recovery of host-side argument/log/cache issues without changing project contracts.
