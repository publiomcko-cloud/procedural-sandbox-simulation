# F2 G1 protected-install failure investigation

**Disposition:** `READY_FOR_NON_ELEVATED_FAILURE_DIAGNOSTICS_REVIEW`

**Scope:** non-elevated forensics and synthetic PowerShell 5.1 transport tests only. No source correction or new UAC attempt was performed.

## Provenance and approved source

- Exhausted attempt receipt: [PR #53 comment 6113226032](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/53#issuecomment-6113226032).
- Independent finding: [Issue #48 comment 6113258502](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48#issuecomment-6113258502).
- The exact reviewed source tree is PR #53 HEAD `bd14a1908085065f08d3c62e4dd17fa3203a53ff`, parent `c391836da9a4bea70d46a46af42bd6f64323ace8`; PR #53 remains open/draft/unmerged.
- Production SourceRoot is `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`.
- Reviewed bootstrap: [`Invoke-F2VerifiedInstaller.ps1`](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/bd14a1908085065f08d3c62e4dd17fa3203a53ff/docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1), SHA-256 `3ae8fee4cfa7c809110a3233f9df2ad8f1fe877c91f1a4067e08541c5e893060`.
- Reviewed installer: [`Install-F2IcaclsProtectedPackage.ps1`](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/bd14a1908085065f08d3c62e4dd17fa3203a53ff/docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1), SHA-256 `be622923a5931a1cc1ce8cfff18c72952b836f8f84e403a419254c6c2c778b0e`.

The receipt confirms one UAC launch, elevated child exit code 1, requester wrapper exit code 1, no retry, both final directories absent, and no matching staging directories. It correctly records `ORIGINAL_INSTALLER_JSON_NOT_CAPTURED`.

## Recoverable host evidence

The receipt comment is the only retained requester-side run receipt found in the preparation directory; that directory contains no stdout/stderr capture or process transcript for the attempt. The requester’s PSReadLine history had no matching command. The checked in-memory process table is not historical process evidence.

The already-enabled `Microsoft-Windows-PowerShell/Operational` log and the `Windows PowerShell` log were readable without elevation. Targeted records immediately before the receipt time (local `America/Sao_Paulo`, UTC−03:00) yielded:

| Log record | Local time | Sanitized observation |
|---|---|---|
| PowerShell Operational 4104, record 152951, process 7292 | 2026-10-11 17:09:36.853 | Requester-side PowerShell 5.1 script-block record contains the reviewed installer/bootstrap pin checks and `Start-Process -Verb RunAs`. Its event account matches the current requester account. |
| Windows PowerShell 400, record 251925, process 18284 | 2026-10-11 17:09:39.228 | A Windows PowerShell 5.1 engine started in the child-launch window. |
| PowerShell Operational 4100, record 152955, process 18284 | 2026-10-11 17:09:39.295 | Same child process logged `VariableIsUndefined`: PowerShell could not retrieve `$args` because it had not been set. The localized event text was “A variável '$args' não pode ser recuperada porque ainda não foi definida.” Event severity was Warning. Its event account matches the requester account. |
| Windows PowerShell 403, record 251926, process 18284 | 2026-10-11 17:09:39.381 | The child PowerShell engine stopped. |

No private SID or raw ACL data is included. The Security log could not be read under the requester token; no elevation was requested. No Sysmon channel was registered. The System log had no matching event in the examined time interval. Thus no Security 4688 process-creation record or token-integrity/elevation field was available.

**UAC identity finding:** the child PowerShell Operational event’s account SID was compared in memory with the requester’s current SID and matched; the SID is intentionally not published. This supports that the child ran under the original requester account and does not support different-account credentials. The logs do not record the UAC dialog selection or token integrity level, so those details remain `UNKNOWN`.

## Confirmed root cause

At the approved bootstrap source:

1. `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` are set at lines 4–5.
2. The standalone-entrypoint branch evaluates `$args.Count` at line 41.
3. That argument check is **before** the `try` beginning at line 45.
4. Only after the check does the bootstrap enter `Invoke-F2VerifiedInstallerCore`, read/hash-check the installer, and execute its verified bytes.

The UAC child is started using `-EncodedCommand` with the approved bootstrap text and no script arguments. In this Windows PowerShell 5.1 invocation, `$args` is undefined under the active strict mode. Because the preference is `Stop`, the guard terminates before the `try`, bypasses the bootstrap diagnostic prefix/catch, and exits 1. The event’s error identifier and message match the guard exactly. A synthetic Windows PowerShell 5.1 fixture with the same guard, strict mode, error preference, and no arguments reproduced exit 1 and no body marker. A candidate guard based on `$MyInvocation.UnboundArguments` passed that fixture.

This is a confirmed bootstrap entrypoint failure. The installer was not reached. It explains the observed empty staging and final paths without inferring any ACL, storage, source-pin, or baseline failure. The installer has a separate `$args.Count` guard at line 366, but the approved bootstrap invokes its verified script block; a synthetic nested script-block check did not reproduce the undefined-`$args` failure there. It is not the observed failure.

## Exact exit-code / failure-stage matrix

The table follows the immutable reviewed source. “Can leave both final paths and staging absent” is a source-level possibility; it is not a claim that every such path occurred.

| Boundary / stage | Observable process result | Can leave both final destinations and staging absent? | Evidence status for this attempt |
|---|---|---:|---|
| Requester SHA guard fails before `Start-Process` | No elevated child; requester throws before UAC | Yes | Excluded by the receipt and child engine events; no new attempt. |
| UAC cancelled or ShellExecute launch fails | No child exit code; requester receives launch exception | Yes | Excluded as a no-child outcome: child PowerShell engine and exit 1 were observed. Exact dialog choice is unknown. |
| Bootstrap argument guard `$args.Count` before `try` | Child exit 1; PowerShell engine error; no bootstrap prefix | Yes | **Confirmed** by event 4100 and PS 5.1 synthetic reproduction. |
| Bootstrap enters `try`, then expected-hash/read/size/hash/UTF-8/ScriptBlock failure | Bootstrap prints `F2_INSTALL_BOOTSTRAP:` and exits 1 | Yes when failure precedes installer side effects | Not reached in the observed attempt. |
| Installer refuses non-Administrator token | Installer JSON outcome `ADMINISTRATOR_TOKEN_REQUIRED`, exit 1 | Yes | Not reached/observed; the event account alone does not prove token integrity. |
| Installer `Preflight` (path collision, parent ACL, baseline identity/integrity/path set, or seven source pins) | Structured `INSTALL_BLOCKED`, `Stage=Preflight`, exit 1 | Yes | Not reached: bootstrap guard terminated first. |
| `CreateStagingDirectories` | Structured failure, exit 1; zero stages possible only if the first create failed before creating a directory | Sometimes | Not reached. |
| `CopyCreateNewPackageFiles` / manifest creation | Structured failure, exit 1; stage paths normally remain and are returned | No, unless an external actor removed them | Not reached. |
| `PrePublishAttestation` | Structured failure, exit 1; staging remains | No, absent external removal | Not reached. |
| `PublishCreateNewDirectories` | Structured failure, exit 1; before first move stages remain; after package move package final and release stage remain | No, under the reviewed code’s own behavior | Not reached. |
| `PostInstallAttestation` | Structured failure, exit 1; both final directories have already moved into place | No, absent external removal | Not reached; both final paths were absent afterward. |
| Installer internal caught exception | Installer serializes sanitized JSON with `Success=false`, `Outcome=INSTALL_BLOCKED`, stage and allow-listed error code, then exits 1 | Depends on stage | No JSON was retained; event proves the bootstrap failed earlier. |
| Installer top-level/unhandled failure | Generic `F2_INSTALL:` stderr and exit 1; may occur before staging | Yes | Not reached based on the confirmed earlier bootstrap failure. |
| Installer success | JSON `Success=true`, `Outcome=INSTALL_COMPLETE`, child exit 0; later independent host attestation still required | No; final paths exist | Did not occur. |

The reviewed coordinator does not clean stages in its catch path; it reports remaining stage paths. A zero-stage/zero-destination postflight alone would not identify the stage. Here the PowerShell event provides the missing discriminating evidence.

## Capture approach comparison

1. **Current `Start-Process -Verb RunAs -Wait -PassThru`:** reliably provides the process exit code after completion but not the child JSON/stderr. This is the observed gap.
2. **`Start-Process -Verb RunAs -RedirectStandardOutput/-RedirectStandardError`:** do not use. Windows PowerShell 5.1 documents separate parameter sets: the default set has redirect parameters; the `UseShellExecute` set has `-Verb` but no redirect parameters. The synthetic test confirms the installed 5.1 parameter metadata has no set combining them. See [Windows PowerShell 5.1 Start-Process](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-5.1).
3. **Elevated `cmd.exe /c` or an inner PowerShell `>` wrapper:** could redirect streams inside the elevated process, but adds command-shell quoting, redirection, and exit-propagation edge cases. It is not selected; this task did not invoke such a wrapper or UAC.
4. **Pipe across elevation:** unnecessary for this narrow receipt; it reintroduces cross-integrity and account-authentication design questions. Not selected.
5. **Recommended: child-written, bounded diagnostic mailbox in a standard-user-created per-attempt temp directory.** The parent creates a GUID-named directory before UAC with protected DACL for SYSTEM and the requester SID only. The reviewed child receives that exact path plus a random correlation nonce. The child atomically create-news a small allow-listed JSON record for bootstrap failure or installer result. The parent waits for the ordinary `-Wait -PassThru` process object, records the actual child exit code, then validates the diagnostic’s canonical path, owner/DACL, no-reparse status, bounded size, schema, nonce, stage and error-code enums. Missing, duplicate, malformed, oversized, or mismatched data is a hard diagnostic failure. A different-account elevated token should be unable to write to the requester-only mailbox; absent output becomes `CHILD_DIAGNOSTIC_MISSING`, while the installer’s existing requester/baseline identity check still fails closed.

The diagnostic file is **not** proof of successful installation. Treat it as attacker-modifiable same-user diagnostic input. Success remains determined only by requester-side independent read-only postflight of the four expected directories, seven exact file hashes, v2 release manifest, exact protected DACL/owner and no-reparse conditions. Do not include SDDL, private account SIDs, credentials, raw baseline payloads, or unrestricted exception text in the diagnostic record. Store only stage, allow-listed error code, component, outcome, correlation nonce and bounded publication flags. Preserve the file on failure for review; no automatic cleanup/retry.

The synthetic test uses a temporary requester-owned DACL-protected directory and an ordinary non-elevated PS 5.1 child. It validates the status-file framing and rejection rules; it **does not** prove behavior across UAC, a high-integrity token, or a different-account credential prompt.

## Minimal proposed source correction and review gates

No production files were changed here. Before any fresh installation attempt, make one narrow source update in a new independently reviewed SHA:

1. Replace the bootstrap’s brittle no-argument check with a PS 5.1-tested `$MyInvocation.UnboundArguments` check, and move argument rejection inside the outer diagnostic `try/catch`.
2. Keep the exact one-read/hash/execute-identical-in-memory-bytes property. Dot-source the already verified installer script block in a scoped invocation, then call its existing `Invoke-F2InstallMain` function to retrieve the structured result instead of allowing its top-level `exit` to bypass the bootstrap reporter. Verify scope/strict-mode behavior in PS 5.1 synthetic tests before review.
3. Add a constrained diagnostic-path/nonce input only to the reviewed one-time bootstrap command. Validate that the path is a new canonical child of the parent-created GUID directory, that the directory is protected and owned by the original requester, and that neither file nor directory is a reparse point. Publish one create-new bounded JSON file atomically; never overwrite a prior file.
4. Put the entire bootstrap dispatch, argument validation, source verification, installer call and report publication under one catch/finally boundary. Convert exceptions to an allow-listed `Stage` / `ErrorCode`; do not serialize arbitrary exception text. Installer caught status remains distinct from bootstrap failure.
5. Parent records start disposition (`NOT_LAUNCHED`, `UAC_CANCELLED_OR_LAUNCH_ERROR`, or launched), the real returned child PID/exit code, wait/cleanup status, and the parsed diagnostic. If the process was not created, do not invent a child exit code. Never classify a missing diagnostic as success.
6. Preserve separate independent host postflight. A diagnostic `Outcome=INSTALL_COMPLETE` must never replace verification of actual final paths, seven hashes, external manifest, owner/DACL protections and no-reparse status.

Required focused PS 5.1 review tests: encoded entry with no args passes; unexpected args fail with a sanitized diagnostic; bootstrap wrong hash/read/size/encoding and invalid script parse are separately classed; installer Preflight error and staging/partial-publication results survive the bootstrap boundary; normal failure preserves the child’s actual exit code; missing/corrupt/oversized/wrong-nonce/reparse diagnostic is rejected; a diagnostic that claims success with nonzero exit or missing independent postflight is never success; same-account mailbox write succeeds; alternate-account/no-access case fails closed; no existing diagnostic file is overwritten. Re-run both existing PowerShell suites, full parser, diff check and Windows CI on the new reviewed SHA. Test UAC cross-account behavior only with a separately approved safe fixture; do not infer it from this synthetic suite.

**Security impact:** the proposed status mailbox adds one short-lived, standard-user-created local temp directory but no new install destination or privilege. Its DACL is requester/SYSTEM only and protected. The only privileged write is a single bounded create-new diagnostic file by the consented child. Diagnostic data is untrusted and non-authoritative. The one-time owner authorization is exhausted; any changed executable bytes require independent exact-SHA review and fresh explicit owner authorization before UAC.

## Scope and outcome

Confirmed: the failing process reached Windows PowerShell 5.1 and terminated at the bootstrap’s unbound `$args.Count` guard. This explains why no staging path or protected destination remained. Same-account identity is supported by the child event account comparison. No installer JSON, internal installer stage, elevated token integrity, or Security process-creation record was retained/accesssible.

No second UAC, installation, source/ACL change, `icacls`, VM/Hyper-V/G: operation, native execution, or PR merge occurred. PR #53 and PR #50 remain unchanged and unmerged. This package is a non-elevated forensic/design review only; a future install is not authorized by this report.
