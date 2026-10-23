# CHK-2026-10-22-P1-1B-B1-1-STREAMING-REQUALIFICATION-OWNER-AUTHORIZATION

**Date:** 2026-10-22, America/Sao_Paulo.
**Decision:** `OWNER_AUTHORIZED_STREAMING_REQUALIFICATION_WITH_MANDATORY_HOST_EVIDENCE_GUARDS / ESSENTIAL_TESTS_ONLY / NO_OPEN_ENDED_RETRIES`.
**Publication:** new owner-decision checkpoint in existing separate docs-only draft [PR #101](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/101), not merged.

## Owner authorization and source pin

Owner explicitly authorized a **single fresh** qualification of the 11 previously frozen B0S streaming + edited-reload scenarios, conditional on correcting the evidence-custody safeguards, and requested tests remain limited to what is essential rather than indefinite cycles. The failed prior campaign remains **historically** `0 QUALIFIED PASS / 0 FAIL / 2 BLOCKED / 9 NOT_RUN`. Do not replace, delete or reclassify its captures/checkpoint.

Reviewed source is still [feature PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) at exact R7 HEAD `2b4355363a43b73476715cf4002e31575bf9828d`, direct parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`. Frozen manifest physical SHA-256 `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd`; required Godot 4.7.2 console binary physical SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. No source, test oracle, frozen manifest or production changes authorized.

## Minimal custody repair before Godot scenario execution

1. Preserve previous incident evidence read-only; create a **new unique campaign ID** and all-new evidence directories.
2. Separate the executable-launching runner from the strictly offline parser/validator. Validator must be incapable of spawning any Godot scenario process; treat it as data-only.
3. Atomic persistent one-launch reservation per scenario, exclusive raw stdout/stderr/JSONL creation (create-new/fail-if-existing), no truncation/overwriting; preserve original raw files and immediately index SHA-256. An uncertain/crashed launch is BLOCKED, never silently retried.
4. **No-Godot tests limited to essential failure vectors:** duplicate-launch denial; existing-raw-file collision denial; offline postprocessor with missing optional FACE `expected_settled_counts` and wrong-crossing-vector input—verify safe rejection/handling without runner call, no raw changes or new Godot process. Keep actual Windows USERPROFILE unchanged and use supported APPDATA/LOCALAPPDATA isolation.

Only after these minimal safeguards PASS: run a **single** common cold import, harness check-only, full 11-group R7 contract suite, then exactly one invocation per frozen B0S scenario in individual sequential Godot processes.

## Finite operational limits and grading

- Allow at most **two recovery attempts per distinct host-only operational issue**, with a hard ceiling of **four total corrections** for this entire mission. No recurring preflight/repetition loops; any exceeded gate becomes BLOCKED and reported.
- **Never rerun a started scenario**, even if the validator/report generator fails afterward. Offline reprocess its original retained logs only.
- Isolated scenario-specific functional FAIL may leave subsequent independent scenarios runnable if environment, process limits and custody remain intact. Stop entirely on any global identity/custody or unsafe resource failure.
- Validate frozen scenario-specific outputs rather than imposing ledger event counts. Streaming residency/waypoints and correct flow counters, atomic diagonal 14-region case, three 9/12/15/16-region corner-loop cases, nonsettled reversal semantics, and edited reload of region (2,-1) with two edits, coherent publication receipts and eight SDF pre/post probes. This reload is **in-process**, not durable disk persistence.
- One unique immutable evidence root and per-run evidence indexes, plus one consolidated 11-case result table. PASS only if all mandatory scenario checks pass with custody intact. No scored FPS/GPU/RSS/VRAM performance claims.

## Out of scope

No broad synthetic test matrix, extra benchmark scenarios, independent LOD/tunnel run, native Voxel Tools, PR merge/change, production integration, source fixes or protected F2-G1 actions. Preserve the development workspace and three existing untracked `.gd.uid` files, `stash@{0}`, prior evidence, all five F2-G1 holds `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. Review the complete new campaign **once**, not after each short scenario.

[Owner decision and exact guard requirements recorded on PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6345382070). This authorization supersedes the previous *future-execution hold*, **not** the prior incident's factual findings or any release/merge hold.
