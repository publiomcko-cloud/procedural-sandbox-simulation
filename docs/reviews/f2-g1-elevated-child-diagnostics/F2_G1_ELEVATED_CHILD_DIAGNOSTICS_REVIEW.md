# F2 G1 elevated-child failure diagnostics

**Status: SOURCE-ONLY; awaiting independent exact-SHA review. No UAC or protected updater execution was performed.**

This package resolves the observability gap documented in PR #61 review `5494765012`: the standard requester previously retained the elevated child's PID, timeout and exit status but did not receive the child's bounded internal `Stage` and stable `ErrorCode`. The earlier child exit 1 remains unexplained; this correction does not attribute it to Git, ACLs, PowerShell, or another cause.

## Immutable lineage and current pins

| Item | Value |
|---|---|
| PR #61 diagnostic starting commit | `54e0d25d86bc69e41604f352edf4c2411809b93f` |
| Prior reviewed production SourceRoot | `8b70a70934445bee660c1e53e71b2e7b20a6191f` |
| New production SourceRoot commit | `03882eedf3104fc33aa0cf503ddef9c9a6bec702` |
| New production parent | `12575f4802f471210c0516b68b5d0d37d2eb8642` |
| New candidate v3 manifest SHA-256 | `ac42f719583ba58b1c122a9318368d34699cf60103787034525be4fbe937ad07` |
| Candidate schema / package root | `f2-icacls-runtime-release-v3` / `C:\Program Files\F2-G1-Icacls\releases\03882eedf3104fc33aa0cf503ddef9c9a6bec702` |
| Seven-file source-pin manifest SHA-256 | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |
| Retained baseline mailbox / payload CaptureId | `ecb6deeb424e40feb5354d18908986df` / `489e7fec-0300-467c-bfbd-a46fb8cf7211` |
| Retained baseline payload / integrity SHA-256 | `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014` / `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34` |

The executable Windows checkout SHA-256 values below include the repository's required CRLF line endings. The candidate JSON has a `-text` attribute and retains stable bytes.

| Production source file | Windows checkout SHA-256 |
|---|---|
| `scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1` | `054e69a4b908c1fe1927e5997bf1c7aca003e8ae21fbaa278323fdf6b5179e68` |
| `scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1` | `c4dfc71606888555f7b93930671045490ba8e49d20d65f858eab6c084bf620eb` |
| `scripts/f2-acl/F2ProtectedRelease.Diagnostics.ps1` | `f66783ac53ce84c093193fc6e20547e707da7013f4f1406a87b088ab6898654c` |
| `docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json` | `ac42f719583ba58b1c122a9318368d34699cf60103787034525be4fbe937ad07` |

The source correction series changes only the updater, launcher and new diagnostic protocol module. It does not change the seven installed runtime members or their source-pin manifest. Their hashes remain:

| Runtime member | SHA-256 |
|---|---|
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `F2AclIcacls.Runtime.psm1` | `d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |
| `Invoke-F2IcaclsCapture.ps1` | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515` |
| `F2_ICACLS_SOURCE_PINS.json` | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |

## Communication and trust boundary

The standard-token launcher validates and loads the pinned protocol module, creates a one-instance local named pipe, generates a cryptographic 256-bit nonce and unpredictable request ID, and launches at most one normal consented UAC child. The pipe is created first-instance-only, rejects remote clients, does not inherit its handle, and has a protected DACL granting only the original requester SID read/write access. A medium mandatory label with no-write-up is applied. The elevated child must have the same requester SID under the updater's existing identity gate.

The child sends one length-framed canonical JSON record with a SHA-256 trailer. The payload is limited to 4096 bytes. The record contains only the schema, `NON_AUTHORITATIVE_DIAGNOSTIC` authority label, request ID/nonce, source/launcher/updater/candidate pins, requester PID and creation time, a requester SID digest, child PID and creation time, child exit claim, and allowlisted stage/error codes. It excludes raw SIDs, SDDL, credentials, environment values, paths from exception text and arbitrary exception messages. The pipe client PID is obtained from Windows and must equal the launched child's PID; creation time, all request pins, nonce, schema, field order, canonical encoding, digest, one-record EOF and actual child exit are independently checked. A diagnostic whose claimed exit differs from the observed process exit is rejected.

Only one record is accepted. Missing, duplicate, oversized, malformed, tampered, stale/replayed, wrong-process, conflicting-exit and late records fail closed. Requester-side failures pass through an exact stable-code allowlist; raw SID-like or arbitrary token-shaped exception text is reduced to UPDATE_UNCLASSIFIED_FAILURE. Diagnostic native/pipe server initialization failures use the stable UPDATE_DIAGNOSTIC_CHANNEL_FAILURE code. The connection, record read and complete child execution use bounded monotonic deadlines. If the server cannot begin its pipe wait, the requester still monitors the child to a bounded exit or timeout and preserves that actual status alongside `CHANNEL_FAILED`; it does not return early with an unknown exit. The requester never terminates the child and never retries UAC. `Complete` is a diagnostic stage only: the launcher still reports that child exit zero requires a separate actual-host post-attestation. A diagnostic cannot authorize protected writes, a retry, recovery, rollback, or cleanup.

The pipe sender becomes available only after the elevated child has read, hashed, parsed and loaded the pinned protocol module. If PowerShell cannot start/parse the encoded bootstrap, the module path/hash is invalid, or the transport cannot initialize, no trusted sender is available; the requester can still report the observed child exit, timeout and `MISSING`/`INVALID` channel status, but cannot know a child `Stage` or `ErrorCode`. It does not invent one. This is an explicit fail-closed limitation.

A same-SID process could race to connect first and cause a denial of service; its PID is rejected and it cannot publish an accepted record or obtain an arbitrary privileged operation. The one-shot channel then fails closed. This same-account denial-of-service case and actual medium-to-high UAC pipe access were not exercised by the non-elevated tests. Different-account UAC remains rejected by the existing SID identity gate; no raw SID is in the record.

## Corrected child bootstrap size

An early synthetic measurement found the first implementation embedded the 24,986-byte protocol module into `-EncodedCommand`, yielding 106,524 encoded characters and exceeding Windows' 32,767-character command-line limit. The final launcher embeds only the fixed module path and reads the module once in the child, verifies the exact launcher-pinned SHA-256, strictly decodes/parses it, and dot-sources that exact in-memory byte sequence. The TEMP harness measures the resulting production child command below the limit (18,744 encoded characters for the measured fixture, plus a 100-character fixed argument reserve) and verifies module-hash failure cannot be treated as a complete diagnostic.

## Windows PowerShell 5.1 validation

Run the reproducible suite command from the repository root:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2ProtectedReleaseDiagnosticSuites.ps1
```

The runner invokes seven Windows PowerShell 5.1 suites sequentially with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`, records each exact command and exit status, and stores complete output at [WINDOWS_PS51_REGRESSION.log](evidence/WINDOWS_PS51_REGRESSION.log). The suite inventory and expected assertion totals for the validated run are:

| Suite | Assertions | Failures |
|---|---:|---:|
| Protocol and worker transport | 152 | 0 |
| Icacls corroboration | 118 | 0 |
| Runtime and release loading | 41 | 0 |
| Entrypoint arguments | 18 | 0 |
| Protected release updater and interruption/recovery fault injection | 134 | 0 |
| Production native helper TEMP tests | 20 | 0 |
| Elevated child diagnostic channel | 38 | 0 |
| **Total** | **521** | **0** |

The diagnostics suite invokes the production child-script builder and the real production pipe receiver with ordinary Windows PowerShell 5.1 processes, using only a new GUID directory under TEMP, synthetic updater/candidate files and no UAC. It exercises protocol bootstrap failure; updater and candidate hash rejection; parsing/loading failure; identity rejection; synthetic source Git, parent ACL, old-release, native-helper and release-lock failures; server wait initialization failure with exact child exit; stale nonce; corrupted digest; duplicate, oversized, missing and stalled frames; wrong client PID; conflicting actual exit; and a false `Complete`/zero claim. The fake updater only returns failure objects and cannot create protected transaction paths. A separate updater regression injects a CreateNew lock failure into the actual production transaction using a TEMP fixture and verifies the stable stage/code with no transaction directory. The actual updater native-helper wrapper is separately tested with a synthetic compiler failure; the native helper's actual compile and TEMP behavior remain covered by the 20-assertion production helper suite.

The final parser sweep covers all `.ps1` and `.psm1` files in `scripts/f2-acl`; the changed production scripts and tests must have zero parser errors. `git diff --check` must pass. Windows GitHub CI for the final review commit is a separate required gate; its exact run is linked from the PR checks after publication.

## Exact future command — NOT EXECUTED

This command is included for review only. It has not been executed. It requires a new exact-SHA independent approval and fresh owner authorization. It expects the corrected production checkout at `C:\Dev\f2-g1-protected-updater-source`, the reviewed worktree at `C:\Dev\f2-g1-protected-updater`, all unrelated PowerShell hosts exited normally, and a fresh `cmd.exe /d /k` started directly from Explorer's Run dialog. The old command in the historical PR #59 handoff is superseded.

```cmd
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& { $path='C:\Dev\f2-g1-protected-updater-source\scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'; $expected='054e69a4b908c1fe1927e5997bf1c7aca003e8ae21fbaa278323fdf6b5179e68'; $bytes=[IO.File]::ReadAllBytes($path); $sha=[Security.Cryptography.SHA256]::Create(); try { $actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }; if($actual -cne $expected){throw 'UPDATE_BOOTSTRAP_HASH_MISMATCH'}; $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes); . ([scriptblock]::Create($text)); $rc=Invoke-F2ProtectedReleaseUpdateLauncher -ExpectedSourceCommit 03882eedf3104fc33aa0cf503ddef9c9a6bec702 -ExpectedLauncherSha256 054e69a4b908c1fe1927e5997bf1c7aca003e8ae21fbaa278323fdf6b5179e68 -ExpectedUpdaterSha256 c4dfc71606888555f7b93930671045490ba8e49d20d65f858eab6c084bf620eb -ExpectedCandidateManifestSha256 ac42f719583ba58b1c122a9318368d34699cf60103787034525be4fbe937ad07; exit [int]$rc }"
```

After the PowerShell process returns to CMD, `echo ChildExit=%ERRORLEVEL%` shows the propagated process result. A zero exit is not installation or upgrade proof; independent installed-state attestation remains mandatory. This task did not run the command or request UAC.

## Verified / not run

| Gate | Result |
|---|---|
| Production source commit, parent and clean lineage | Verified at `03882eedf3104fc33aa0cf503ddef9c9a6bec702` / `12575f4802f471210c0516b68b5d0d37d2eb8642` |
| New Windows checkout hashes and launcher-to-protocol pin | Verified; values above |
| Candidate source commit, package root, unchanged seven member pins and retained baseline identities | Verified in the candidate JSON |
| Same-token real PS5.1 local named-pipe cross-process integration and malformed-message cases | Pass in TEMP synthetic tests |
| Full Windows PowerShell 5.1 suites | 521 assertions, 0 failures |
| Real elevated UAC identity/integrity crossing | **NOT_RUN** |
| Actual protected v2-to-v3 update, C: writes, or actual-host post-attestation | **NOT_RUN** |
| Live icacls/VM/Hyper-V/G: or native F2 workload | **NOT_RUN** |

The PR remains draft and unmerged. This package is ready only for independent source review; it is not authorization to execute the command.
