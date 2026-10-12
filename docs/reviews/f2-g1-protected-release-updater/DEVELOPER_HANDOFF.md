# Developer handoff — F2 G1 updater process quiescence

Status: READY_FOR_INDEPENDENT_REVIEW
Ticket / acceptance criteria: Issue #48 process-quiescence gap; PR #59 review 5493067444.
Repository / remote: publiomcko-cloud/procedural-sandbox-simulation / https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git
Worktree / branch: C:\Dev\f2-g1-protected-updater / fix/f2-g1-protected-release-updater
Review branch HEAD: d63b51db7c2de8b8e1197ebede653f4d762cae9a
Review branch parent: c95ce9b5751d7d3a6cb79b85eb2d836d87d762a4
Production SourceRoot SHA: 8b70a70934445bee660c1e53e71b2e7b20a6191f
Production SourceRoot parent: 5d231f4697673569de526c03cedf61c72e769e07
Changed production paths:
- scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1 (production correction at 8b70a709; Windows CRLF SHA-256 d26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e)
- scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1 (production correction at 8b70a709; Windows CRLF SHA-256 8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720)
- scripts/f2-acl/Test-F2AclProtectedReleaseUpdater.ps1 (test-only synthetic diagnostics and canonical path normalization at d63b51db; Windows checkout SHA-256 56c4ee4688a401d249ec67a65187b1dac762226ea7a2a582bf51b5c43c07c046)
- Review documents, candidate manifest, test logs and CI evidence under docs/reviews/f2-g1-protected-release-updater/; see evidence/ARTIFACT_MANIFEST.md.

Implementation summary: Added fail-closed process quiescence for supported v2/v3 PowerShell runtime surfaces. The updater acquires the exclusive v3 lease and v2 active-manifest read barrier before process inventory, permits only the exact current elevated updater and pinned requester bootstrap, rejects every other PowerShell process or unknown inventory state, and repeats inventory immediately before manifest activation. It never terminates processes. Test fixtures now normalize synthetic requester paths using the same GetFullPath behavior as production, avoiding a false failure when hosted Windows TEMP uses an 8.3 alias. The corrected native helper and seven release-package files are unchanged.

Architectural impact: No runtime package member or source-pin digest changed. Candidate v3 manifest ReviewedCommitSha and versioned PackageRoot remain bound to production source commit 8b70a70934445bee660c1e53e71b2e7b20a6191f; candidate manifest SHA-256 is 74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c.
Dependencies added / licenses: None.

Tests executed (exact direct commands, repository root):
$ps51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Corroboration.ps1
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Runtime.ps1
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclEntrypointArguments.ps1
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclProtectedReleaseUpdater.ps1
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclProtectedReleaseNativeHelper.ps1
PowerShell parser sweep: ParseFile for each `git ls-files 'scripts/f2-acl/*.ps1' 'scripts/f2-acl/*.psm1'` result.
Whitespace: git diff --check.

Results / assertion counts: Protocol 152/0, Corroboration 118/0, Runtime 41/0, Entrypoint 18/0, Updater 121/0, Native helper 20/0; total 470 assertions, zero failures; all six child exit codes 0. Parser: 14 files, zero errors. git diff --check: exit 0. Hosted Windows CI run 38277921321 / job 114907827701 succeeded; full log is in evidence/WINDOWS_CI_LOG.txt and the immutable run URL in evidence/WINDOWS_CI.txt.

Tests not executed: No live PowerShell process inventory, UAC, protected update/recovery, C: ACL, icacls, VM/Hyper-V/G:, or native collector workload.
Failure/recovery cases: Synthetic updater tests cover old/new source paths, installed coordinator/runtime surfaces, direct and encoded PowerShell, missing command line, inventory failure, PID reuse, cached v2 manifest, late spawn, barrier ordering, interrupted transaction steps and fail-closed recovery. No process is killed. Unknown process state blocks before activation.
Benchmark machine and metrics: Not applicable.
Known limitations: Real elevated process visibility and GetOwnerSid/CreationDate correlation remain unverified; actual C: share/rename and ACL behavior is untested. A foreign or unrelated PowerShell process intentionally blocks updating. Arbitrary non-PowerShell hosting or renamed/custom PowerShell is outside the supported runtime interface.
Visual reproduction steps: Not applicable.
Rollback instructions: Do not run an upgrade or recovery from this source-only review. No rollback was performed. Any future update/recovery requires a new independent exact-SHA review and fresh owner authorization; updater preserves transaction objects and does not auto-delete or rollback.
Reviewer focus / open questions: Audit the complete legacy/current invocation-path map, lease/manifest barrier ordering, process-inventory exception policy, exact requester identity binding and Windows file-share semantics. Decide whether the explicit supported-host boundary is sufficient before authorizing an upgrade.
