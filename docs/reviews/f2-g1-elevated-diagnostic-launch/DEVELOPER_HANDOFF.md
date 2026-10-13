# Developer handoff

Status: READY_FOR_INDEPENDENT_REVIEW

Ticket / acceptance criteria: Issue #48 diagnostic-only probe, PR #68 review HEAD `c3d1280f9905730eda8cff40865e8afbbb642367`. Prepare a reviewed Windows PowerShell 5.1 one-time elevated launch plan, exact byte verification, fixed input/token/path checks, proof of diagnostic-only operation, bounded sanitized result channel, source-only negative tests and complete review evidence. No UAC or protected operation is authorized or performed.

Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation`; `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.

Worktree / branch: `C:\Dev\f2-g1-diagnostic-elevation-plan-source`; `feat/f2-g1-diagnostic-elevation-plan-issue48`.

Base SHA: `c3d1280f9905730eda8cff40865e8afbbb642367`.

Candidate SHA (launch implementation): `8c2bddd90c6ac5214eeed08b5648d0ef30b58bf4`; parent `606cddfe8d8c0912093810c22b3cd9692cee9325`. The final documentation/command package is a child of this source commit; its exact HEAD and parent are stated in the PR body and final handoff.

Changed paths:

- `.gitattributes`
- `.github/workflows/f2-acl-source-only.yml`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/OUTER_BOOTSTRAP.ps1`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/EXACT_UAC_COMMAND.txt`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/README.md`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/SECURITY_BOUNDARIES.md`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/DEVELOPER_HANDOFF.md`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/VALIDATION_RESULTS.md`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/FILE_SHA256_MANIFEST.txt`
- `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnostic.ps1`
- `scripts/f2-acl/F2HistoricalManifestLaunch.psm1`
- `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnosticChild.ps1`
- `scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1`
- `scripts/f2-acl/Test-F2HistoricalManifestLaunch.ps1`

Implementation summary: Added a source-hash-pinned standard launcher and elevated diagnostic-only child, with fixed checkout/input pins, in-memory execution of verified bytes, protected one-shot local pipe, process/token/nonce binding, bounded framing and output, and strict response/exit validation. Preserved the reviewed diagnostic module and historical pins. Fixed the wrapper reader so an empty `$PSScriptRoot` in the verified runspace does not prevent consumption of the already hash-verified in-memory diagnostic module bytes. The outer command sanitizes PowerShell module search to `$PSHOME\Modules`. The workflow skips PR #68's exact-HEAD evidence verifier and the historical updater transaction suite on this stacked source branch; it runs this launch suite and the compatible source-only suites.

Architectural impact: Adds a privileged read-only diagnostic proposal, not an active runtime change. Reviewers must assess the UAC/IPC boundary and the explicit unknowns before any future owner authorization.

Dependencies added / licenses: None. Uses Windows PowerShell 5.1/.NET Framework and the existing installed Git executable pinned by path and SHA-256.

Tests executed (exact commands):

- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2HistoricalManifestLaunch.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Corroboration.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Runtime.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclEntrypointArguments.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclProtectedReleaseNativeHelper.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2ProtectedReleaseDiagnostics.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2HistoricalManifestDiagnostic.ps1`
- Windows PowerShell 5.1 `Parser::ParseFile` sweep across the 28 F2 PowerShell source files plus this outer bootstrap.
- `git diff --check` and `git diff --cached --check`.

Results / assertion counts: See `VALIDATION_RESULTS.md` and hosted Windows CI for exact counts and the immutable review HEAD. All eight listed synthetic/TEMP-only suites passed with 564 assertions and zero failures in Windows PowerShell 5.1; parser and whitespace results are recorded there. The PR #68 evidence-manifest checker and `Test-F2AclProtectedReleaseUpdater.ps1` are deliberately excluded on this stacked branch for the reasons documented in the validation record. No actual UAC, cross-integrity connection or historical updater entrypoint was executed.

Tests not executed: UAC/elevation, protected updater, recovery/transaction, protected writes, `icacls`, ACL queries, VM/Hyper-V/G:, native F2 workloads, and the real historical elevated context.

Failure/recovery cases: Cancellation, wrong account, wrong PID/creation time/SID/command line, missing/inaccessible command line, dirty/wrong source, wrong paths, reparse aliases, modified/missing/oversized files, wrong historical pins, malformed/duplicate/oversized frames, bad nonce/schema, raw diagnostic values, false success, exit mismatch, timeout, missing diagnostic and child-may-remain are fail-closed. No automatic retry, recovery, rollback, process termination or cleanup is performed.

Benchmark machine and metrics: Not applicable.

Known limitations: A fresh owner authorization is required before any UAC. The pipe has only same-token synthetic process integration evidence; actual medium/high UAC compatibility and command-line visibility remain UNKNOWN. The consent UI is not time-bounded by this tool. One invocation has one UAC site and no retry, but there is no durable cross-invocation attempt ledger; the owner must never rerun after the first prompt. A diagnostic PASS does not resolve the historical elevated failure or attest ACL/installation state.

Visual reproduction steps: Not applicable.

Rollback instructions: Source-only draft branch. No protected or host state was changed. Close/reject the draft PR if not accepted; do not run the published command.

Reviewer focus / open questions: Verify complete source hash chain and current fixed input pins; assess PSModulePath sanitization, file-to-in-memory execution, pipe ACL/peer binding, one-UAC semantics, timeout/missing-record handling, forbidden-operation proof and all UAC-specific unknowns. Decide whether the no-durable-latch limit is acceptable for a separately authorized one-time run.
