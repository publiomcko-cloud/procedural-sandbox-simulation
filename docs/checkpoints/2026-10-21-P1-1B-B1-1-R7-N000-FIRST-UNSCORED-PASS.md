# CHK-2026-10-21-P1-1B-B1-1-R7-N000-FIRST-UNSCORED-PASS

**Date:** 2026-10-21, America/Sao_Paulo.  
**Nature:** consequential reported executable PASS after previously documented N000-R6 blocker; GitHub remote-source evidence reconciliation; next independent gate.  
**State on creation:** `N000_R7_UNSCORED_PREFLIGHT_REPORTED_PASS / RAW_WINDOWS_LOGS_NOT_INDEPENDENTLY_AUDITED / PID_PROVENANCE_UNKNOWN / PR99_DRAFT_UNMERGED`.  
**Publication:** prepared on separate documentation-only **draft PR #101**, not merged/owner-accepted by publication alone.  
**Historical immutability:** this checkpoint supersedes the older N000-R6 *current status*; it does **not** rewrite [the R6 blocker record](2026-10-21-P1-1B-B1-1-R6-N000-CONTRACT-AND-PREFLIGHT.md).

## Exact independently verified remote identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`.
- Remote `main`: `ea4422d90726d3f2fe6d5cef097126268f93685a` as inspected on 2026-10-21.
- [PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) remains **open/draft/unmerged** at `2b4355363a43b73476715cf4002e31575bf9828d`, direct parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd` (R7).
- [Independent exact-SHA R7 source review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6323866160) PASS; [N000 R7 evidence-level reviewer comment](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6324095976).
- [PR #100](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/100) roadmap remains open/draft/unmerged at `45df07487a9d065706c35129e92cff4bccb5bfd2`.
- [PR #101](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/101) is the existing separate docs-only draft PR for historical B1-1 evidence. Its older R6 checkpoint must remain unchanged.
- Manifest source `game/tests/fixtures/p1_1b_b0_manifest.json` Git blob `fde2ff84e2754cfef48052b32998903f45276aa1`, approved SHA-256 `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd`. The matching sidecar blob remains `d43687f7cb772982808ada60b6c35e5f7bc40332`. Frozen N000 is `B0A.INTERIOR.N000.v1`, type `ledger_replay`, zero operations; frozen N001 `B0A.INTERIOR.N001.v1` has one operation. Source definitions are unchanged.
- GitHub `Starter checks` for the R7 feature SHA run #39648145572 passed, **static-only**.

## Reported R7 exact-SHA execution: four sequential gates

All actual Windows Godot execution details below were **reported by the owner/Codex**. Reviewer verified GitHub source/PR state and event schema but did **not** inspect or replay the raw host-only files, so this is **not independent L5 execution attestation**.

| Stage | Codex-reported result | Evidence meaning |
| --- | --- | --- |
| A — Godot 4.7.2 `--editor --import` | **PASS**, exit 0, five global classes registered, no errors/warnings | Cold checkout class bootstrap succeeded |
| B — harness `--check-only` | **PASS**, exit 0, no errors/warnings | R6 test-harness compiler blockers corrected; R7 version validator parsed |
| C — modified contract suite | **PASS**, exit 0, **2,586 assertions, 0 failures, 11 groups** | Includes R7's 29 version-identity checks; cannot substitute for production tests |
| D — **one** frozen N000 `UNSCORED` run | **PASS**, exit 0; four schema-valid `P1B1_JSONL` records; one `scenario_complete` PASS, zero failures, zero edits | First reported end-to-end scenario harness completion; no scored performance acceptance |

The N000 JSONL records were reported to carry unique event IDs, coherent `run_id` and parent-event linkage, monotonic clock observations, and full runtime commit identity `ed1daf0bf001b61586d9930840f2f1394092c079`. The owner reported exactly one `scenario_started` and exactly one terminal `scenario_complete`. The Godot executable identity/version and physical manifest+sidecar SHA-256 were verified externally in the runner preflight; the harness recorded the compatible in-engine structured version and reached the manifest/scenario stages.

**Important limitation:** the observed process IDs differ: PowerShell launcher PID `31188`; Godot JSONL `process_id` `35308`. No parent-child, wrapper, executable or creation-time correlation was independently proven. This is **not by itself an internally incoherent JSONL run**, but the launcher PID must **not** be used as the Godot process identity for CPU/RSS/VRAM or other per-process benchmarking. The cause of the mismatch remains **UNKNOWN** until a non-invasive process-tree observation captures PID, ParentProcessId, CreationDate, executable path and command line on the actual execution host. Do not retrofit an explanation or claim process-attributed performance data.

## Evidence custody and withheld acceptances

- Raw host evidence (not independently mounted here): `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_r7val_cc79e837b5734d78bea672f57ea99c37_evidence`. Includes stdout/stderr, parsed JSONL, stage summaries, hash and cleanup records per developer report.
- Detached R7 checkout reportedly clean in tracked paths with three newly generated untracked `.gd.uid` files. Windows development workspace tracked HEAD, the three pre-existing untracked `.gd.uid` hashes, and `stash@{0}` reportedly unchanged. Prior R3–R6 and first N000 evidence retained.
- **Not performed or authorized by this result:** independent replay of those Windows logs, scored benchmark comparison, target hardware budget acceptance, GPU-completed/presented-frame FPS, OS process RSS/VRAM, GUI/user visual acceptance, complete 44-scenario run, native Voxel Tools usage, P1.1C production LOD integration or merge/release.
- Do not substitute one successful zero-edit ledger scenario for 1/32/128/256-operation behavior, dynamic streaming or terrain-mesh performance.
- The owner's standing Godot execution permission remains recorded in [PR #99 comment #6319312731](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6319312731), bounded by reviewed scenarios, source hashes, protective holds and independent evidence gates.
- The five protected F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

## Next bounded gate

**Recommended candidate:** on the **same exact R7 SHA**, use a fresh disposable checkout and profile; verify engine executable digest and manifest source pin, then editor import, harness check-only, modified 2,586-assertion contract suite and **only if all PASS** run **exactly one frozen `B0A.INTERIOR.N001.v1`** `UNSCORED`.

Require exactly **one accepted canonical command**, command-list digest and revision 1, successful SDF query parity, proper per-process JSONL event/run/parent links, exactly one scenario_started and terminal scenario_complete PASS, zero failures and exit 0. Record process-tree provenance as feasible and leave any unmapped PID **explicitly unresolved**. Never silently infer FPS/GPU completion or collect/score unapproved OS metrics. No N032, no bulk 44-scenario run, no production source changes, no native dependencies and **no merge** of PR #99/#100/#101.

Stop on the first failed stage, preserve full evidence and deliver for independent source/evidence review.

## Record maintenance

The [checkpoint index](INDEX.md) adds a new row for this later event, and [CURRENT_STATUS](../status/CURRENT_STATUS.md) gains a new superseding dated section. No decision-register change is needed because this event reports **evidence**, not a new owner authorization. No changelog merge entry is due: no PR merge occurred. The existing older R6 blocker checkpoint remains immutable as of this writing.
