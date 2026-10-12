# F2 G1 v2-to-v3 upgrade post-failure diagnosis

**Disposition:** `READY_FOR_F2_G1_POST_FAILURE_DIAGNOSTIC_REVIEW`
**Scope:** Source analysis, Windows PowerShell 5.1 synthetic TEMP tests, and non-elevated read-only checks of the existing v2 installation and retained baseline. No production source was changed.

## Finding

The single approved elevation ended with child PID `50432`, exit code `1`; the CMD wrapper also returned `1`. The one-time UAC authorization is **CONSUMED**. The elevated child's internal `Stage` and `ErrorCode` were not retained and remain **UNKNOWN**. The immutable launcher does not capture the elevated child's stdout or stderr, so no internal diagnostic is available to attribute the failure.

The postfailure state is consistent with failure before a durable `release.lock` was created. The reviewed updater has no transaction cleanup path. If a lock or transaction root had been created and the updater then failed, the source would leave it behind. A failure while attempting the first lock-file create can return exit `1` while leaving no lock. An external deletion or concurrent actor cannot be excluded from the available evidence.

No unconditional Windows PowerShell 5.1 runtime defect was reproduced. A controlled PS 5.1 TEMP fixture did reproduce one **conditional** source-preflight failure: when `git.exe` is absent from the process `PATH`, the production transaction function returns `UPDATE_BLOCKED`, stage `CandidateAndSourceValidation`, error `UPDATE_UNCLASSIFIED_FAILURE`, and `CommandNotFoundException`, without creating a lock or touching a protected path. This is a viable explanation shape, not evidence that it happened in the elevated child.

## Attempt and source identity

The owner-provided attempt record is in [Issue #48 comment 6129922269](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48#issuecomment-6129922269). Its seven old-package hashes and active v2 manifest hash match the pins in the reviewed updater. The current read-only checks independently repeated those hash checks.

| Input | Immutable identity |
|---|---|
| Reviewed updater PR | #59, HEAD `9e9915e6eb15bcb20cc2f5a1c990791e2a822b90` |
| Production source commit | `8b70a70934445bee660c1e53e71b2e7b20a6191f` |
| Windows CRLF updater SHA-256 | `d26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e` |
| Windows CRLF launcher SHA-256 | `8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720` |
| v3 candidate manifest SHA-256 | `74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c` |
| Owner-reported child | PID `50432`, exit `1`; CMD exit `1`; one UAC launch |

The production checkout has the reviewed CRLF hashes. Its Git blobs equal the reviewed PR source blobs. The PR review checkout used by the regression suite has LF working-tree bytes due to local checkout configuration; its Git blob IDs are the same. The exact production checkout's 14 PowerShell files were separately parsed under Windows PowerShell 5.1 with zero parse errors.

## Read-only postfailure checks

Checks ran under the ordinary, non-elevated token using `Get-Acl`, item metadata, exact one-level listings and SHA-256 reads. No `icacls` or live Hyper-V/VM/G: query was used. The sanitized machine-readable details are in [`evidence/postfailure-readonly-results.json`](evidence/postfailure-readonly-results.json).

| Objects | Observation |
|---|---|
| Four protected installation directories | Present; Administrators owner category; protected DACL; exact reviewed three-ACE profile; no reparse point in each path or its ancestors |
| Seven installed v2 files | Present 7/7; each SHA-256 equals the immutable v2 pin; each owner/DACL profile passes; no reparse point in each path or its ancestors |
| Active v2 release manifest | SHA-256 `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9`; schema v2; old source commit and seven pins match; distinct mailbox and payload capture IDs and both baseline hashes match; owner/DACL and reparse checks pass |
| Retained baseline mailbox directory | Present; Administrators owner category; protected exact four-ACE mailbox profile; no reparse point in the path or ancestors; private requester SID and raw SDDL omitted |
| Retained baseline payload and integrity files | Raw SHA-256 values match the approved pins; payload reports the pinned CaptureId and Complete=true; integrity byte count and payload digest match the payload |
| Transaction state | `release.lock`, `ProgramData\updates`, `ProgramData\backups`, and `Program Files\...\releases` are absent; v2 package and release roots contain only their expected entries |

The baseline mailbox contained seven expected evidence entries. This check revalidated the pinned payload and integrity files and the mailbox directory DACL; it did not publish raw SDDL or expose supporting diagnostic contents. No protected object was modified.

## Reviewed exit-1 paths before a durable release lock

The path analysis uses only the exact PR #59 source. The relevant code is in [`Start-F2ProtectedReleaseUpdate.ps1`](../../../scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1) and [`Invoke-F2ProtectedReleaseUpdate.ps1`](../../../scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1).

| Component and source path | Exit-1 behavior before lock | How it relates to this attempt |
|---|---|---|
| Standard requester launcher preflight (`Start-F2ProtectedReleaseUpdate.ps1`, lines 24–78) | Identity, current process metadata, path/reparse, Git commit/origin/cleanliness, input type/size/hash, candidate schema/commit or PowerShell 5.1 path failures return `1` as `UPDATE_NON_ELEVATED_PREFLIGHT_FAILURE`. | The supplied child PID and child exit imply a process was launched, so a pre-launch failure does not fit the supplied record. The original full parent transcript is not available here. |
| UAC launch/wait wrapper (lines 124–140) | UAC cancellation or launch/wait exception returns `1`; timeout returns `124`. It records the child exit when available. | A reported child exit `1` distinguishes the child result from a no-child preflight result, but the PID/exit values remain owner-supplied evidence. |
| Elevated bootstrap before updater invocation (`Start-F2ProtectedReleaseUpdate.ps1`, embedded child lines 80–119) | Child command decoding/parsing, no-reparse, input size/hash, or updater-load failure reaches `UPDATE_BOOTSTRAP_BLOCKED` and exit `1`; an error before its `try` could emit no JSON. Elevated requester SID/admin mismatch is checked before updater work and also exits `1`. These branches have no transaction `Stage`. | All can leave no transaction paths. Child identity and internal JSON were not retained, so none can be excluded. |
| Public updater entrypoint (`Invoke-F2ProtectedReleaseUpdate.ps1`, `Invoke-F2ProtectedReleaseUpdate`, lines 776–788) | Elevated requester identity and v3 manifest parsing/identity checks occur before `Invoke-F2UpdateTransaction`; a throw is caught by the embedded child wrapper and exits `1` without a transaction stage. | Possible source path; actual error is unknown. |
| Transaction candidate/source validation (`Invoke-F2ProtectedReleaseUpdate.ps1`, lines 521–540) | Stage begins as `CandidateAndSourceValidation`. Candidate schema/hash/commit/PackageRoot, Git command/commit/origin/clean state, seven source files and pins, parent ACLs, native ACL-query setup, exact installed-v2 paths/files/ACLs/manifest, or transaction-path collisions can return `UPDATE_BLOCKED`, `Stage=CandidateAndSourceValidation`, exit `1`. | This is the main pre-lock set. Current postfailure v2 checks pass, but a current observation cannot prove every predicate had the same value during the elevated run. Parent ACL checks are separate from protected child DACL checks. |
| First barrier/lock operation (`Invoke-F2ProtectedReleaseUpdate.ps1`, lines 541–565) | Stage becomes `AcquireReleaseBarrier`. Native helper load, create-new lock creation, lock DACL/hash validation, exclusive lease open, or manifest barrier open can fail and return exit `1`. If create-new fails before a file is established, no lock remains. | This path also fits the observed empty transaction state. The lock creation attempt and its internal error are not recorded. |
| After a successfully created lock (lines 566 onward) | Process inventory, module/query availability, manifest barrier validation and later transaction failures return `1`. The source does not remove the lock or transaction objects. Creating transaction roots begins at line 573; later failures preserve partial paths. | The currently absent lock/roots argue against this path assuming observations are complete and no external deletion or concurrent actor intervened. They do not establish the exact failure stage. |

Inside the transaction catch, the updater returns a structured failure object containing `Stage`, a bounded `ErrorCode`, failure type and state. The embedded child writes that object to its own console and exits `1`. The standard launcher uses `Start-Process -Verb RunAs -PassThru`, waits on the process and records its exit code; it does not configure redirected output or a diagnostic mailbox. Therefore the outer record can establish exit `1` while losing the child's structured stage/error. This report does not assign any missing internal value.

## PowerShell 5.1, Git and module findings

Validation ran with `powershell.exe` 5.1.22621.6133 and `-NoProfile -NonInteractive`:

- `Test-F2AclProtectedReleaseUpdater.ps1`: **133 assertions, 0 failures, exit 0**. It uses TEMP fixture roots, hashes an old-source archive, exercises transaction success and fail-closed cases, and removes only its fixture root.
- `Test-F2AclProtectedReleaseNativeHelper.ps1`: **20 assertions, 0 failures, exit 0**. It compiles the exact embedded C# helper and tests create-new, DACL readback and collision behavior only below TEMP; cleanup passed. It does not run the ACL collector or protected updater.
- Embedded encoded-child template parse: **PASS**, PS 5.1; no execution or UAC.
- Production CRLF parser sweep: **14 files, 0 parse errors, exit 0**.
- Synthetic missing-Git test: **PASS_EXPECTED_FAIL_CLOSED**. The real `Invoke-F2UpdateTransaction` function was run with only TEMP roots and a child-local PATH lacking Git. It returned `UPDATE_BLOCKED`, `CandidateAndSourceValidation`, `UPDATE_UNCLASSIFIED_FAILURE`, and `CommandNotFoundException`. No lock or package/data roots were created and no protected path was accessed. This was a controlled conditional failure, not a reproduction of the owner's actual elevated environment.
- Current no-profile PS 5.1 dependency probe: Git and `CimCmdlets` resolved successfully. Under the synthetic system-only PATH, Git did not resolve while `Get-CimInstance` and `CimCmdlets` remained available.

In the current non-elevated no-profile PS 5.1 process, `git.exe` resolves to `C:\Program Files\Git\cmd\git.exe`, and `CimCmdlets`/`Get-CimInstance` are available. With a synthetic system-only PATH, `git.exe` does not resolve while `CimCmdlets` remains available. The updater resolves Git using `Get-Command git.exe` rather than an absolute binary path. Microsoft's [Start-Process documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-5.1) says the default child environment inherits variables from the current process. That makes a missing Git path less likely under an unchanged same-account launch, but the actual elevated child's PATH was not saved. The source also requires the elevated token SID to equal the requester SID; a different-account credential would fail earlier with an identity mismatch.

`Get-CimInstance` is used for process inventory after the release lock is acquired. If that cmdlet/module were missing in the elevated child, the failure would occur after lock creation and the source would leave the lock. The standard requester also uses `Get-CimInstance` before UAC to bind its process PID and creation time; the child launch indicates that path passed. The current host's PS 5.1 has the module. Module absence does not fit the observed no-lock state without an unrecorded external deletion.

Complete logs and reproducible synthetic scripts are included under [`evidence/`](evidence/). Their SHA-256 values are listed in [`evidence-manifest.json`](evidence-manifest.json). No raw ACL/SDDL, private requester SID, credential, VM evidence, or baseline payload is included.

The test processes were invoked with the following commands from the review worktree `C:\Dev\f2-g1-post-failure-diagnostic-review`:

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\Dev\f2-g1-post-failure-diagnostic-review\scripts\f2-acl\Test-F2AclProtectedReleaseUpdater.ps1'
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\Dev\f2-g1-post-failure-diagnostic-review\scripts\f2-acl\Test-F2AclProtectedReleaseNativeHelper.ps1'
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\Dev\f2-g1-post-failure-diagnostic-review\docs\reviews\f2-g1-post-failure-diagnostics\evidence\Test-SyntheticMissingGitPreflight.ps1'
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\Dev\f2-g1-post-failure-diagnostic-review\docs\reviews\f2-g1-post-failure-diagnostics\evidence\Test-EncodedChildTemplateParse.ps1'
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\Dev\f2-g1-post-failure-diagnostic-review\docs\reviews\f2-g1-post-failure-diagnostics\evidence\Test-ProductionPowerShellParserSweep.ps1' -SourceRoot 'C:\Dev\f2-g1-protected-updater-source'
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\Dev\f2-g1-post-failure-diagnostic-review\docs\reviews\f2-g1-post-failure-diagnostics\evidence\Test-CurrentPS51Dependencies.ps1'
```

All returned exit `0`. The updater suite logged 133 `PASS` assertions and zero failures; the native-helper suite logged 20 assertions and zero failures. The parser sweep covered 14 production PowerShell files. The synthetic missing-Git fixture intentionally returned an expected blocked transaction and its test harness exited `0` after verifying that result.

## Recommended next action

Keep the installed v2 package and retained baseline untouched. Do not make another elevated attempt under the consumed authorization.

The smallest useful source-only correction is failure observability: retain the current error gates and child exit handling, while adding a bounded nonce-bound diagnostic publication from the elevated wrapper to a requester-owned protected TEMP mailbox. The record should contain only a component, known stage and allowlisted error code; bind it to the current request/child process and exact reviewed hashes; reject missing, duplicate, malformed or tampered records; and label it `NON_AUTHORITATIVE`. The parent must continue to treat actual child exit and independent installed-state attestation as separate success requirements. Do not add arbitrary exception text, raw SDDL or private SID values. Independent review of any changed executable bytes and **fresh explicit owner authorization** are required before a later UAC attempt.

No production source correction is established by the evidence in this report. A fixed-path Git binding is a possible separate correction only if future reviewed evidence confirms that Git lookup caused the failed attempt.

## Evidence and handoff

| Item | Evidence |
|---|---|
| Immutable diagnostic base | PR #59 HEAD `9e9915e6eb15bcb20cc2f5a1c990791e2a822b90` |
| Production source | Commit `8b70a70934445bee660c1e53e71b2e7b20a6191f` |
| Branch | `docs/f2-g1-upgrade-post-failure-diagnostics` |
| Changed paths | This diagnostic, sanitized result JSON, evidence manifest, synthetic probe scripts, and complete PS 5.1 logs |
| Tests | Exact commands and exit/count evidence are in the evidence log filenames and this report |
| Production source changed | None |
| Elevated actions | None in this diagnostic turn |
| Limitations | Actual child Stage/ErrorCode/PATH/token and stdout remain unavailable; no live VM/G:/Hyper-V/icacls query |
| Review disposition | Documentation/evidence only; PR remains draft and unmerged |

Developer handoff: diagnostic-only evidence update; no architectural runtime acceptance or ACL security acceptance is claimed.
Task status: `READY_FOR_F2_G1_POST_FAILURE_DIAGNOSTIC_REVIEW`.
