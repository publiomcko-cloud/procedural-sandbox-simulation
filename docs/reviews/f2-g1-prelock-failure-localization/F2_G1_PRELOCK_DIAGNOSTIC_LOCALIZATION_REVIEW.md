# F2 G1 pre-lock failure localization

**Status: SOURCE-ONLY; ready for independent exact-SHA review. No UAC, protected updater, live ACL, VM, or native workload was run.**

## Scope and confirmed limits

This correction addresses Issue #48 review finding `6143131598` against PR #64. The two prior UAC attempts remain consumed. The second child reported `CandidateAndSourceValidation / UPDATE_UNCLASSIFIED_FAILURE`; its exact operation and exception are still **UNKNOWN**. This source correction does not claim to identify that historical cause. It makes a future separately authorized run report one fixed pre-lock substage and a stable allowlisted error code.

The correction is limited to the updater's diagnostic stage context, the diagnostic protocol allowlists, and synthetic regressions. Candidate/source validation, requester and elevated identity checks, protected ACL policies, process quiescence, source pins, deadlines, no-overwrite behavior, transaction handling, and the seven installed runtime members remain enforced.

## Immutable lineage and pins

| Item | Value |
|---|---|
| Reviewed starting PR #64 HEAD | `40f1385913a42aa11e88814c70cbec882082ac3d` |
| Production source commit | `396c44965c90c08292ad2835f8317e81b6b9daaf` |
| Production source parent | `f58b7fdfaf71e212213d559480e1913ae6c210f8` |
| Expected clean source checkout | `C:\Dev\f2-g1-protected-updater-source` |
| Repository origin | `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git` |
| Candidate schema | `f2-icacls-runtime-release-v3` |
| Candidate manifest SHA-256 | `b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022` |
| Candidate `ReviewedCommitSha` / `PackageRoot` suffix | `396c44965c90c08292ad2835f8317e81b6b9daaf` |
| Seven-file source-pin manifest SHA-256 | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |

Windows PowerShell 5.1 checkout hashes for the changed production files and candidate are:

| File | SHA-256 |
|---|---|
| `scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1` | `9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9` |
| `scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1` | `d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2` |
| `scripts/f2-acl/F2ProtectedRelease.Diagnostics.ps1` | `66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7` |
| `docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json` | `b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022` |

The launcher pins the diagnostic protocol hash above. The updater and candidate executable pins in the future command are the exact bytes reported here. `.gitattributes` specifies CRLF for PowerShell source and the candidate retains its original byte formatting.

For source provenance, the three production updater files at the reviewed starting commit `40f1385913a42aa11e88814c70cbec882082ac3d` were compared byte-for-byte with the reviewed production source commit `03882eedf3104fc33aa0cf503ddef9c9a6bec702`; the trees matched before correction. The new source commit is based on the PR #64 review branch, and the source-chain check below verifies the exact resulting file bytes and seven package hashes in the new clean checkout.

The unchanged seven release-package member hashes are:

| Runtime member | SHA-256 |
|---|---|
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `F2AclIcacls.Runtime.psm1` | `d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4` |
| `Invoke-F2IcaclsCapture.ps1` | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515` |
| `F2_ICACLS_SOURCE_PINS.json` | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

The retained baseline contract is unchanged: mailbox ID `ecb6deeb424e40feb5354d18908986df`, payload CaptureId `489e7fec-0300-467c-bfbd-a46fb8cf7211`, payload SHA-256 `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`, and integrity SHA-256 `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`. No retained evidence was read, recaptured, rewritten, or published by this task.

## Pre-lock stage contract

The updater records a closed set of stage values in its per-invocation context. The transaction catch uses only that validated context value. The diagnostic protocol independently accepts the same fixed substage names and stable error-code allowlist; it does not receive exception text, exception types, paths, SIDs, SDDL, environment values, or baseline contents.

| Stage | Exact operation boundary |
|---|---|
| `CandidateManifestValidation` | Parse and validate candidate bytes, schema, hash, reviewed commit, package root, baseline identities, and seven package declarations. |
| `SourceGitValidation` | `Get-F2UpdateSourceBytes`: normalize the source root, resolve Git, read `HEAD`, verify origin, and require a clean worktree. The stage is set inside this function before any of those operations. |
| `SourcePackagePinValidation` | `Get-F2UpdateSourceBytes`: after Git identity and clean-worktree checks pass, read/hash the seven source files and validate their internal pin manifest. This stage transition is also inside the function, immediately before package reads. |
| `ParentAclValidation` | Validate both protected destination parent chains and their expected ACL policy. |
| `InstalledV2Validation` | Validate the complete active v2 manifest and all seven installed v2 file hashes and security profiles. |
| `TransactionCollisionValidation` | Check release, update, backup, journal and lock paths for expected type/content and reject unknown/pre-existing transaction objects. |

After these six gates pass, the existing stages remain in effect: release-barrier acquisition, runtime quiescence, transaction-root creation, package staging, side-by-side package activation, manifest activation, and completion. The transaction remains fail-closed. The six test injections fail before transaction roots are created; they do not simulate or claim a successful protected update.

Two candidate failures now have explicit stable protocol codes—`UPDATE_CANDIDATE_COMMIT_MISMATCH` and `UPDATE_CANDIDATE_PACKAGE_ROOT_MISMATCH`—so they are not reduced to the generic fallback. `Get-F2UpdateSourceBytes` keeps Git and package-pin failures separate even though they share one function. The child diagnostic continues to be non-authoritative; independent state attestation remains necessary for any future claim of success.

## Regression and source-chain evidence

The real production child-script builder and pipe receiver were exercised in separate Windows PowerShell 5.1 processes with temporary Git, candidate and old-v2 fixtures. Each injected case asserted the exact substage and stable safe code, validated the fixed diagnostic schema and verified that the synthetic old release remained active without transaction-root creation:

| Injected operation failure | Reported stage / error |
|---|---|
| Malformed candidate JSON parsed in the elevated child bootstrap | `CandidateManifestValidation / UPDATE_MANIFEST_JSON_INVALID` |
| Candidate package-root identity | `CandidateManifestValidation / UPDATE_CANDIDATE_PACKAGE_ROOT_MISMATCH` |
| Git origin check | `SourceGitValidation / UPDATE_SOURCE_ORIGIN_MISMATCH` |
| Source package hash pin | `SourcePackagePinValidation / UPDATE_SOURCE_PACKAGE_HASH_MISMATCH` |
| Parent ACL check | `ParentAclValidation / UPDATE_PARENT_CHAIN_UNSAFE` |
| Installed v2 manifest validation | `InstalledV2Validation / UPDATE_FILE_HASH_MISMATCH` |
| Existing non-empty release-lock collision | `TransactionCollisionValidation / UPDATE_FILE_TYPE_OR_SIZE_INVALID` |

The pipe suite also rejects an authenticated unlisted stage, stale nonce, bad digest, missing or duplicate frames, oversize output, wrong process, conflicting child exit and false success claim. It retains the real child exit and emits only the fixed sanitized record. Full command output and per-suite exits are in [the Windows PowerShell 5.1 regression log](evidence/WINDOWS_PS51_REGRESSION.log); its SHA-256 is recorded in `evidence/VALIDATION_HASHES.txt`.

`evidence/Test-F2PrelockSourceChain.ps1` rechecks the source checkout commit, parent, origin and clean state; candidate identity/hash; all seven candidate file hashes and internal source pins; unchanged baseline identities/hashes; and byte equality of the three changed production files between the source and review checkout. Its complete output and actual exit code are in `evidence/SOURCE_CHAIN_VALIDATION.log`. The parser sweep and whitespace/source-base comparison are recorded in `evidence/PARSER_AND_DIFF_VALIDATION.log`.

Validation run on this candidate:

| Check | Result |
|---|---|
| Seven Windows PowerShell 5.1 suites | 542 assertions, 0 failures; 7/7 process exits 0 |
| Parser sweep | 21 PowerShell files, 0 parser errors |
| Candidate/source pin and lineage check | `PASS_PRELOCK_SOURCE_CHAIN`, exit 0 |
| `git diff --check` | Pass, exit 0 |
| Hosted Windows CI | Run result and immutable URL are attached to this draft PR after publication. |

The per-suite assertions are Protocol 152, Corroboration 118, Runtime 41, Entrypoint 18, Protected updater 136, Native helper 20, and Diagnostic channel 57. All synthetic filesystem fixtures were temporary and removed by their tests. No installer/updater entrypoint was run.

Iteration notes: one initial direct test invocation used the default `pwsh.exe` 7.6 shell and reported a synthetic recovery-journal mismatch; checking `$PSVersionTable` showed that this was not the requested Windows PowerShell 5.1 runtime. The same updater suite passed 136/0 when launched with the explicit Windows PowerShell 5.1 executable, and the full runner below pins that executable. The first malformed-candidate regression expectation was corrected to the actual allowlisted `UPDATE_MANIFEST_JSON_INVALID` code. The source-chain fixture's optional review-root default was moved out of parameter-default evaluation after a no-argument PS5.1 probe showed `$PSScriptRoot` was not available there; the no-argument path then passed. None of these harness corrections changed the production updater behavior.

During this final evidence refresh, the first aggregate Windows PowerShell 5.1 runner invocation exited 1 while launching the corroboration suite and did not retain a more specific nested-child failure code. The corroboration suite was then run directly and passed 118/0; a fresh full aggregate run passed all seven suites (542/0). The first aggregate failure was not reproduced, so its underlying transient cause remains **UNKNOWN**. The successful aggregate log and standalone corroboration log are included verbatim. The failed aggregate log is published as `WINDOWS_PS51_REGRESSION_ATTEMPT1.log.b64` because its captured PowerShell error lines contain trailing spaces; decoding it reproduces the original bytes exactly, SHA-256 `f5274928452fac78e081f58841ae7f9f118ed450e7f3e38bc0a89fd87a18e628`.

To recover that original failed-run log without changing its bytes:

```powershell
[IO.File]::WriteAllBytes('WINDOWS_PS51_REGRESSION_ATTEMPT1.log', [Convert]::FromBase64String([IO.File]::ReadAllText('WINDOWS_PS51_REGRESSION_ATTEMPT1.log.b64')))
```

Exact local validation commands:

```powershell
$ps51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2ProtectedReleaseDiagnosticSuites.ps1
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2ProtectedReleaseDiagnosticParser.ps1
$reviewRoot = (git rev-parse --show-toplevel).Trim()
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\docs\reviews\f2-g1-prelock-failure-localization\evidence\Test-F2PrelockSourceChain.ps1 -SourceRoot 'C:\Dev\f2-g1-protected-updater-source' -ReviewRoot $reviewRoot
git diff --check
```

## Future hash-bound command — NOT EXECUTED

This is a review artifact only. It requires a new independent exact-SHA review and fresh owner authorization. It must not be run from this handoff. Any later execution remains subject to the existing cmd.exe process-topology requirement and all source/identity/installed-state preflights. The two previous UAC attempts are consumed; this correction authorizes no further attempt.

After a future reviewer checks out the final review commit under `C:\Dev\f2-g1-protected-updater`, a fresh `cmd.exe /d /k` started directly from Explorer's **Win+R** dialog would use this exact line:

```cmd
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& { $path='C:\Dev\f2-g1-protected-updater-source\scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'; $expected='9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9'; $bytes=[IO.File]::ReadAllBytes($path); $sha=[Security.Cryptography.SHA256]::Create(); try { $actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }; if($actual -cne $expected){throw 'UPDATE_BOOTSTRAP_HASH_MISMATCH'}; $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes); . ([scriptblock]::Create($text)); $rc=Invoke-F2ProtectedReleaseUpdateLauncher -ExpectedSourceCommit 396c44965c90c08292ad2835f8317e81b6b9daaf -ExpectedLauncherSha256 9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9 -ExpectedUpdaterSha256 d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2 -ExpectedCandidateManifestSha256 b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022; exit [int]$rc }"
```

The next CMD line is `echo F2_UPDATE_EXITCODE=%ERRORLEVEL%`. The command was **not** executed here. No third UAC authorization exists.

## Files and limitations

The production source commit changes the updater diagnostic context and safe-code allowlist, updates the launcher pin for the protocol file, and extends updater/diagnostic regressions. The candidate manifest changes only its reviewed source commit and versioned package-root suffix; the seven runtime member hashes and retained baseline identifiers/digests are unchanged.

No source-only test can determine the precise cause of the prior elevated exit 1. This work also does not validate actual Administrator UAC identity, elevated Git/module availability, live Program Files/ProgramData ACLs, protected path collisions, live transaction behavior, or protected filesystem attestation. A later attempt requires another exact-SHA independent review and fresh owner authorization.
