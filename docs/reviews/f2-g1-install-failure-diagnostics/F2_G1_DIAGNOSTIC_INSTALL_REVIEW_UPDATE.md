# F2 G1 diagnostic install source correction

**Disposition:** `READY_FOR_FINAL_DIAGNOSTIC_INSTALL_SOURCE_REVIEW`

**Scope:** one source-only correction on PR #54. No UAC, protected installation, live `icacls`, VM/Hyper-V/G: operation, ACL remediation, baseline change, native execution, or merge was performed.

## Provenance

- Forensic base and independent forensic review: PR #54 exact base `56b4e3c0132436a4b2c918572078fe4d687fb25c`; forensic review comment `5484837259`.
- Original approved installation source: `bd14a1908085065f08d3c62e4dd17fa3203a53ff`.
- This correction is submitted on the existing draft PR #54 branch `docs/f2-g1-install-failure-diagnostics`, based directly on the forensic HEAD. PR #53 and PR #50 were not changed.
- The final commit and parent are supplied in the PR #54 update comment. Every source, test, log, and this report is committed together at that immutable HEAD.

## Corrected PS 5.1 entrypoint failure

The forensic finding was that the bootstrap's `$args.Count` access occurs under `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` before its `try/catch`. In Windows PowerShell 5.1 encoded-command invocation with no arguments, `$args` is undefined; the child exits 1 before the installer is read.

The bootstrap and installer's file entrypoints now read `@($MyInvocation.UnboundArguments)` inside their protected `try/catch`. The bootstrap accepts only the two diagnostic arguments used by the reviewed caller; it fails closed for zero or unexpected arguments. The installer rejects every unbound argument. This does not relax the installer token, baseline, source-pin, ACL, no-overwrite, or post-installation checks.

The reviewed launcher verifies both exact source byte hashes before creating a mailbox or requesting UAC. It reads the bootstrap once, embeds those verified bytes and the mailbox inputs in a bounded PowerShell command, and the elevated child independently rehashes the embedded bytes before compiling and dot-sourcing them. The bootstrap reads the installer once, verifies the pinned hash, decodes and executes that same in-memory byte array. PowerShell 5.1 synthetic tests exercise the actual ScriptBlock and dot-source scopes used in this flow.

## Bounded diagnostic behavior

`Start-F2VerifiedInstall.ps1` is a parameterless, standard-token-only launcher. It fails if started under an Administrator token, pins Windows PowerShell 5.1, and makes at most one ordinary `Start-Process -Verb RunAs` launch. It does not assume `Start-Process -Verb RunAs` can redirect stdout or stderr. The requesting process independently retains the actual child PID/exit code and treats cancellation or launch failure as having no child exit.

Before UAC, the requester creates one unpredictable directory below the local fixed-volume TEMP path with a protected requester/SYSTEM DACL. It records a random correlation nonce. The child may publish only one bounded JSON record (`f2-install-diagnostic-v1`) with exactly `Schema`, `Nonce`, `Component`, `Outcome`, `Stage`, and `ErrorCode`. The file is created with a protected explicit DACL and requester SID as owner, containing only SYSTEM and requester full-control ACEs; this avoids the elevated token's default owner group becoming the file owner. The record is allow-listed, create-new, published through a same-directory temporary file and non-overwriting move, and checked for exact path, owner/DACL, reparse status, size, fields, nonce, contents, and child-exit consistency. Missing, duplicate, oversized, malformed, tampered, or mismatched evidence fails closed. No raw exception text, SDDL, private SID, credentials, or baseline content is put in the record.

The diagnostic is **NON-AUTHORITATIVE**. `INSTALL_COMPLETE` is only the child’s claim. Even a valid claim with exit 0 is reported as `CHILD_CLAIM_ONLY`; success still requires independent inspection of the actual host installation: four protected directories, seven pinned files, one v2 release manifest, ownership/DACL/reparse checks, source and baseline pins, and absence of partial staging. The mailbox is retained for failure diagnosis and is not treated as a success artifact.

If UAC is cancelled, the launcher records `UAC_CANCELLED_OR_LAUNCH_ERROR`, null child PID/exit, and does not retry. If UAC uses a different Administrator account, the elevated process is expected to fail closed when its TEMP path or identity cannot satisfy the requester-owned mailbox contract; the requester then reports a missing/invalid diagnostic and gives the actionable instruction to use the original requester account. This alternate-account behavior is covered by synthetic identity/owner policy tests only; it has **not** been tested across a real UAC boundary. No claim of elevated runtime acceptance is made.

## Files and exact Windows checkout-byte SHA-256

The complete source and tests are in this PR at the final immutable commit:

| Path | Purpose | SHA-256 |
|---|---|---|
| `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1` | Corrected bootstrap entrypoint, one-read verified execution and diagnostic publication | `6f47d802a2cd5d7deb65083c546829de6a71d26356dcf2b71f6cc6f14d81a4a9` |
| `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1` | Existing installer with protected argument guard; seven-file production package pins unchanged | `cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118` |
| `docs/reviews/f2-g1-install-failure-diagnostics/Start-F2VerifiedInstall.ps1` | New source-pinned, single-launch standard-token wrapper and diagnostic mailbox validator | `a27c315b196c1179eb10fba80867829aeac2b333e07415cc13a1326c0c3ad38d` |
| `docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1` | Existing installer regressions plus actual bootstrap source and dot-source behavior checks | Recorded in `EVIDENCE_MANIFEST.md` |
| `docs/reviews/f2-g1-install-failure-diagnostics/Test-F2InstallDiagnosticTransport.ps1` | 38 PS 5.1 transport, launcher, mailbox, scope and failure-path assertions | Recorded in `EVIDENCE_MANIFEST.md` |
| `.github/workflows/f2-acl-source-only.yml` | Existing synthetic suites, new diagnostics suite, parser sweep and diff check on Windows CI | Recorded in `EVIDENCE_MANIFEST.md` |
| `docs/reviews/f2-g1-install-failure-diagnostics/validation.log` | Exact five suite commands/output/exits and local parser/diff evidence | Recorded in `EVIDENCE_MANIFEST.md` |

These SHA-256 values are Windows PowerShell checkout-byte hashes. The repository's `.gitattributes` normalizes Git text blobs and restores the specified checkout line endings; validation and CI execute the checkout bytes, not a separately reserialized source. `F2_ICACLS_SOURCE_PINS.json` and the seven production file hashes were not changed.

## Validation

Local validation used Windows PowerShell `5.1.22621.6133` and the exact commands listed in `validation.log`:

| Suite | Assertions | Failures | Exit |
|---|---:|---:|---:|
| `Test-F2AclCapture.Protocol.ps1` | 152 | 0 | 0 |
| `Test-F2AclIcacls.Corroboration.ps1` | 118 | 0 | 0 |
| `Test-F2AclIcacls.Runtime.ps1` | 35 | 0 | 0 |
| `Test-Install-F2IcaclsProtectedPackage.ps1` | 47 | 0 | 0 |
| `Test-F2InstallDiagnosticTransport.ps1` | 38 | 0 | 0 |
| **Total** | **390** | **0** | **0** |

The diagnostic suite includes zero/extra encoded and file arguments, installer preflight and staged failures, bootstrap exceptions, byte tampering, same-process ScriptBlock scope, source read/hash/execute identity, mailbox access/owner/DACL/path failures, nonce and record corruption, child-exit conflicts, missing evidence, UAC cancellation without retry, and the non-authoritative success claim. Tests use synthetic temporary content and do not perform protected writes, installation, or elevation.

The Windows PowerShell parser sweep and `git diff --check` results are recorded in `validation.log`. The final Windows CI run is associated with the immutable final PR commit; its workflow/check URL and result are recorded in the PR conversation update and final handoff. No tests were intentionally skipped from the listed five suites.

## Exact future invocation after fresh review and authorization

This is a **future** standard-token command only after an independent review accepts the exact final executable bytes and the owner provides fresh installation authorization. First stage the reviewed launcher, bootstrap, and installer into the preparation directory and verify their exact SHA-256 values from this report. The command below uses `-EncodedCommand` to avoid Windows PowerShell 5.1 native argument quoting ambiguities. Its decoded source reads the launcher once, hashes those exact bytes against the SHA-256 above, decodes and executes the same in-memory script block. Do not run it elevated directly; the reviewed launcher requests one ordinary human-consented UAC launch itself. Run from the original requester account:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -EncodedCommand JABwAGEAdABoAD0AJwBDADoAXABEAGUAdgBcAGYAMgAtAGcAMQAtAHAAcgBvAHQAZQBjAHQAZQBkAC0AaQBuAHMAdABhAGwAbAAtAHAAcgBlAHAAXABTAHQAYQByAHQALQBGADIAVgBlAHIAaQBmAGkAZQBkAEkAbgBzAHQAYQBsAGwALgBwAHMAMQAnAAoAJABiAHkAdABlAHMAPQBbAEkATwAuAEYAaQBsAGUAXQA6ADoAUgBlAGEAZABBAGwAbABCAHkAdABlAHMAKAAkAHAAYQB0AGgAKQAKACQAcwBoAGEAPQBbAFMAZQBjAHUAcgBpAHQAeQAuAEMAcgB5AHAAdABvAGcAcgBhAHAAaAB5AC4AUwBIAEEAMgA1ADYAXQA6ADoAQwByAGUAYQB0AGUAKAApAAoAdAByAHkAIAB7ACAAJABhAGMAdAB1AGEAbAA9ACgAWwBCAGkAdABDAG8AbgB2AGUAcgB0AGUAcgBdADoAOgBUAG8AUwB0AHIAaQBuAGcAKAAkAHMAaABhAC4AQwBvAG0AcAB1AHQAZQBIAGEAcwBoACgAJABiAHkAdABlAHMAKQApACkALgBSAGUAcABsAGEAYwBlACgAJwAtACcALAAnACcAKQAuAFQAbwBMAG8AdwBlAHIASQBuAHYAYQByAGkAYQBuAHQAKAApACAAfQAgAGYAaQBuAGEAbABsAHkAIAB7ACAAJABzAGgAYQAuAEQAaQBzAHAAbwBzAGUAKAApACAAfQAKAGkAZgAgACgAJABhAGMAdAB1AGEAbAAgAC0AYwBuAGUAIAAnAGEAMgA3AGMAMwAxADUAYgAxADkANgBjADEAMQA3ADkAZQBiADEAMABmAGIAYQA4ADAAOAA2ADcAOAAyADkAYQBlAGEAYwAyAGIAMwAzADMAZQAwADcANAAxADUAYwBjADEAMwBhADEAMwAyADYAYwAwAGMAMwBhAGQAMwA4AGQAJwApACAAewAgAHQAaAByAG8AdwAgACcARgAyAF8ATABBAFUATgBDAEgARQBSAF8ASABBAFMASABfAE0ASQBTAE0AQQBUAEMASAAnACAAfQAKACQAdQB0AGYAOAA9AE4AZQB3AC0ATwBiAGoAZQBjAHQAIABTAHkAcwB0AGUAbQAuAFQAZQB4AHQALgBVAFQARgA4AEUAbgBjAG8AZABpAG4AZwAoACQAZgBhAGwAcwBlACwAJAB0AHIAdQBlACkACgAkAHYAZQByAGkAZgBpAGUAZAA9AFsAUwBjAHIAaQBwAHQAQgBsAG8AYwBrAF0AOgA6AEMAcgBlAGEAdABlACgAJAB1AHQAZgA4AC4ARwBlAHQAUwB0AHIAaQBuAGcAKAAkAGIAeQB0AGUAcwApACkACgAmACAAJAB2AGUAcgBpAGYAaQBlAGQA

Decoded wrapper source represented by that exact command:

```text
$path='C:\Dev\f2-g1-protected-install-prep\Start-F2VerifiedInstall.ps1'
$bytes=[IO.File]::ReadAllBytes($path)
$sha=[Security.Cryptography.SHA256]::Create()
try { $actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
if ($actual -cne 'a27c315b196c1179eb10fba80867829aeac2b333e07415cc13a1326c0c3ad38d') { throw 'F2_LAUNCHER_HASH_MISMATCH' }
$utf8=New-Object System.Text.UTF8Encoding($false,$true)
$verified=[ScriptBlock]::Create($utf8.GetString($bytes))
& $verified
```
```

The launcher itself raises at most one normal human-consented UAC prompt. This report does not authorize that invocation, installation, ACL collection, or any VM/native operation. A future installation success decision must use actual independent filesystem attestation, never this diagnostic record alone.

## Remaining elevated-only unknowns and limitations

- The new real `Start-Process -Verb RunAs` path, Windows UAC cancellation presentation, elevated mailbox access, elevated token identity, and actual protected-install failure publication have not been executed; only non-elevated Windows PowerShell 5.1 synthetic integration is evidenced.
- An alternate Administrator account is rejected fail-closed by the mailbox path/owner contract, but that behavior has not been exercised through UAC.
- Source tests cannot attest installed filesystem state or prove access-control behavior under an elevated token.
- No fresh owner authorization exists for installation after these executable bytes changed. Independent source review and fresh owner authorization are required before any future UAC attempt.

No PR was merged. PR #54 remains draft; PR #53 and PR #50 remain unchanged.
