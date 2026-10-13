# Developer handoff — F2 G1 diagnostic launch review

Status: **READY_FOR_INDEPENDENT_LAUNCH_REVIEW** after the new draft PR head passes its Windows check.

## Lineage and scope

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Branch: `feat/f2-g1-diagnostic-elevation-plan-issue48`
- PR #69 base: PR #68 HEAD `c3d1280f9905730eda8cff40865e8afbbb642367`
- Launch implementation commit: `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9`
- Implementation parent: `1f0ddfd26554f1302fc5815084d2adb3b24ea857`
- The final review-package commit is the immutable PR #69 HEAD reported with this handoff; it adds package, tests and evidence to the implementation commit without changing the historical diagnostic inputs.

## Changed paths in the review package

- `docs/reviews/f2-g1-elevated-diagnostic-launch/CMD_ENTRY_BOOTSTRAP.ps1`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/OUTER_BOOTSTRAP.ps1`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/EXACT_UAC_COMMAND.txt`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/README.md`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/SECURITY_BOUNDARIES.md`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/VALIDATION_RESULTS.md`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/TEST_RUN_RESULTS.log`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/FILE_SHA256_MANIFEST.txt`
- `docs/reviews/f2-g1-elevated-diagnostic-launch/DEVELOPER_HANDOFF.md`
- `scripts/f2-acl/F2HistoricalManifestLaunch.psm1`
- `scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1`
- `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnosticChild.ps1`
- `scripts/f2-acl/Test-F2HistoricalManifestLaunch.ps1`

## Correction

The previous encoded outer command was too long for `cmd.exe`; it is replaced by a 4,683-character hash-pinned entry generated from `CMD_ENTRY_BOOTSTRAP.ps1`. The entry verifies a fixed outer bootstrap via a read-only file handle, checks the handle-resolved path and SHA-256, then executes only a ScriptBlock built from those verified bytes. Runtime source uses a separate fixed clean checkout at the pinned implementation commit.

The elevated child command now uses a short generated bootstrap and is rejected if its complete ShellExecute command line exceeds 3,600 characters. Tests exercise the real argument builder and exact bootstrap template using harmless temporary scripts with `UseShellExecute = $true`, but no `runas` verb. A diagnostic PASS must be labeled `TokenClass=ELEVATED`; a `STANDARD`-labeled PASS fails validation.

The Git pin moved from `C:\Program Files\Git\cmd\git.exe` wrapper to `C:\Program Files\Git\mingw64\bin\git.exe` core, with fixed path and hash and only the four existing read-only queries. Git for Windows runtime DLLs remain an explicit dependency trust boundary; their signatures and host ACLs were not inspected.

## Validation commands and results

Eight Windows PowerShell 5.1 suites passed with 585 assertions and zero failures. Their exact commands, sanitized output, assertion counts, and child exits are recorded in `TEST_RUN_RESULTS.log` and summarized in `VALIDATION_RESULTS.md`. The 30-file Windows PowerShell 5.1 parser sweep and `git diff --check` passed. Hosted Windows CI must pass for the exact pushed PR #69 HEAD; its immutable run URL is linked through the PR check and final report.

## Risks and limits

- No UAC, elevated probe, actual `Start-Process -Verb RunAs`, protected updater, `icacls`, ACL/VM/Hyper-V/G: access, native workload, or protected write was run.
- A real cross-integrity named-pipe handshake, UAC command-line behavior, and alternate-account UAC rejection remain unverified.
- Git core DLL dependencies and their host protection are unverified.
- The historical elevated failure remains UNKNOWN. The probe is diagnostic-only; its PASS is not ACL acceptance or installation evidence.
- The exact command is proposed only. It requires later independent review and fresh explicit owner authorization; no authorization is requested or consumed here.

## Rollback and visual checks

This is a source-only draft PR. No host or protected state changed. Do not run the published command during review. Visual reproduction is not applicable. Keep PR #69 draft and unmerged.

**READY_FOR_INDEPENDENT_LAUNCH_REVIEW**
