# Developer handoff — F2 G1 wrapper type correction and CI triage

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Branch: `docs/f2-g1-child-auth-postmortem`
- PR: #71, draft and unmerged
- PR #69 base: `56a34d7899ba31b0d3fe6d3185435bc182ac453f` (unchanged)
- Source correction commit: `41e9c34843815dbd69770de36c9525f44e218e1f`, parent `58991441cfd6ca21cf7bc3cb2fda5f69b97a8633`
- Review/evidence commit: the final commit on this branch containing this handoff; its exact immutable SHA is reported in the response.
- Source path changed: `scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1`
- Regression path changed: `docs/reviews/f2-g1-child-auth-postmortem/Test-F2ChildAuthenticationClassification.ps1`
- Evidence paths: `INCIDENT_POSTMORTEM.md`, `TEST_RESULTS.txt`, and the launch-package `FILE_SHA256_MANIFEST.txt`.

## Finding and correction

Windows PowerShell 5.1 enumerated a `System.Byte[]` returned by the generic child-authentication operation wrapper into `System.Object[]`. The production frame converter's direct return was still `System.Byte[]`. A read-only in-memory `MemoryStream` accepted the object array by converting its elements and produced identical bytes, so the type defect is confirmed but is not established as the cause of an actual pipe failure. The minimal production correction returns `,$result` to preserve array values. Authentication, error codes, framing, identity, and fail-closed conditions were not changed.

## Validation

- Exact command: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\docs\reviews\f2-g1-child-auth-postmortem\Test-F2ChildAuthenticationClassification.ps1`
- Windows PowerShell 5.1.22621.6133: 48 assertions, 0 failures, exit 0.
- The focused test used in-memory production AST function definitions and `MemoryStream`; `CHILD_PROCESSES_STARTED=0`; `UAC_ATTEMPTS=0`.
- Parser checks: production launcher and regression script, 0 parse errors.
- `git diff --check`: pass.
- No full suite or workflow rerun was performed. PR #71 run `38559236368` remains failed at 68 assertions / 28 failures / process exit 1. Prior PR #69 run `38471926228` passed the same unchanged step at 68 / 0 / exit 0. The repeat timeout symptom is documented, but its root cause is not established.

## Scope and limitations

- The consumed elevated `ChildAuthentication` incident exception remains UNKNOWN.
- The CI timeout condition is also UNKNOWN; available logs do not prove runner resource exhaustion or identify the failing child/pipe operation.
- Existing `EXACT_UAC_COMMAND.txt` and `OUTER_BOOTSTRAP.ps1` remain pinned to the older `78a3cb...` candidate and must not be used for the follow-up source bytes. No launch authorization is present.
- No UAC/RunAs, diagnostic child, protected updater, recovery, rollback, ACL modification, protected write, process termination, VM/Hyper-V/G: operation, native workload, baseline change, workflow rerun, or merge occurred.
- Any future attempt requires a new independent source review and fresh explicit owner authorization; the earlier UAC authorization was consumed.

## Disposition

The source return-value defect is corrected and focused regression coverage passes. Final correction readiness remains **BLOCKED_WITH_EVIDENCE** because the required hosted CI failure is unexplained. PR #71 remains open, draft, and unmerged.
