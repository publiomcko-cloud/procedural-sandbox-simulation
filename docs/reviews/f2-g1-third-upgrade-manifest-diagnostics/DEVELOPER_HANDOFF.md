# Developer handoff

Status: READY_FOR_INDEPENDENT_REVIEW

Ticket / acceptance criteria: Issue #48, third F2 G1 protected-upgrade failure; investigate CandidateManifestValidation, reproduce a defect if possible, apply a minimal correction, run Windows PowerShell 5.1 regressions and publish immutable evidence.

Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation`; `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`

Worktree / branch: `C:\Dev\f2-g1-candidate-manifest-diagnostic-review`; `fix/f2-g1-candidate-manifest-validation-diagnostics`

Base SHA: `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`

Production correction SHA: `af9aa616e112e4db4abd7cc607d396fdadb7b76c`; parent `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`.

Review-package commit SHA: see the immutable draft PR head SHA; it contains this complete handoff and evidence directory.

Changed production paths:

- `scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1`
- `scripts/f2-acl/Test-F2ProtectedReleaseDiagnostics.ps1`
- `docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json` (only ReviewedCommitSha and versioned PackageRoot were advanced to the production correction commit)

Review evidence paths are listed in `README.md` and the PR changed-file list. No runtime package member or source-pin hash changed.

Implementation summary: The production manifest loader now validates object/property/type shape before access and converts unanticipated parser exceptions to fixed safe operation codes. Regression coverage uses the actual parser and production child/pipe path with synthetic malformed candidates. The exact reviewed candidate remains valid.

Architectural impact: No protocol or privilege-boundary change. Diagnostic output remains non-authoritative; no transaction or success claim is introduced.

Dependencies added / licenses: None.

Tests executed (Windows PowerShell 5.1.22621.6133):

- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclCapture.Protocol.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclEntrypointArguments.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclProtectedReleaseNativeHelper.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclProtectedReleaseUpdater.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2ProtectedReleaseDiagnostics.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2ProtectedReleaseDiagnosticParser.ps1`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File docs/reviews/f2-g1-third-upgrade-manifest-diagnostics/evidence/Test-F2G1CandidateManifestSourceChain.ps1 -SourceRoot C:\Dev\f2-g1-third-upgrade-source-chain-af9aa616 -ReviewRoot C:\Dev\f2-g1-candidate-manifest-diagnostic-review`
- `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File docs/reviews/f2-g1-third-upgrade-manifest-diagnostics/evidence/Test-F2G1ThirdUpgradeParserSweep.ps1 -RepoRoot C:\Dev\f2-g1-candidate-manifest-diagnostic-review`

Results / assertion counts: 553 assertions, 0 failures across the seven suites; all seven child exit codes were 0. The focused parser test reported 21 files/0 errors; the focused expanded sweep reported 23 files/0 errors. The source-chain test returned `PASS_SOURCE_CHAIN`, exit 0. `git diff --check` passed for the final staged change set. See full logs under `evidence/final/`.

Tests not executed: No elevated or protected updater test; no live `icacls`; no VM/Hyper-V/G: operations. Hosted Windows CI is linked from the final draft PR checks.

Failure/recovery cases: A missing required `BaselineMailboxId` failed before correction with an unclassified StrictMode missing-member condition. The corrected parser returns the fixed `UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID` code, through production child diagnostics, with no transaction writes in the TEMP fixture. The actual elevated incident cause remains UNKNOWN.

Known limitations: Standard-token synthetic child-process tests do not prove Administrator UAC behavior or the cause of the owner's third elevated failure. A separate exploratory whole-repository parser sweep reports errors in two unrelated scripts; the relevant F2 ACL parser suite passes.

Visual reproduction steps: Not applicable.

Rollback instructions: Review only. If rejected before merge, leave this draft PR unmerged; production SourceRoot at the earlier commit and installed v2 files were not modified. Do not reuse any prior UAC authorization.

Reviewer focus / open questions: Verify the complete error mapping in `Get-F2UpdateManifestObject`, malformed JSON/property regressions, exact candidate and production source-chain hashes, and the distinction between the reproducible malformed-input defect and the still-unknown elevated incident cause.
