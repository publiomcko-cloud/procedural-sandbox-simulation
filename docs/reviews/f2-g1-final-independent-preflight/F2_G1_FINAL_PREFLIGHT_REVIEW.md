# F2 G1 final independent preflight receipt

**Disposition:** `READY_FOR_FINAL_INDEPENDENT_PREFLIGHT_REVIEW`
**Review target:** PR #65, exact reviewed HEAD `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`
**Production source commit:** `396c44965c90c08292ad2835f8317e81b6b9daaf`
**Scope:** Fixed-path reconciliation, standard-token read-only host preflight, and bounded non-elevated synthetic regression investigation. This receipt does not authorize protected execution.

## Safety boundary

Both prior one-time UAC authorizations are consumed. No UAC prompt was opened in this work. No protected installation file, ACL, source baseline, VM, G: volume, or process state was changed. No live `icacls.exe`, elevated updater, rollback, recovery, native collector, or PR merge was performed.

The only checkout change was a fast-forward of the already detached candidate worktree at the launcher’s fixed candidate path. The PR #65 branch and production SourceRoot were not changed. This receipt and its read-only audit script are on a separate documentation branch based on PR #65.

## Fixed paths and Git identity

Both roots resolve canonically with no reparse-point path component. Both use origin `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`; the fetched `refs/remotes/origin/pr/65` resolves to the reviewed PR #65 HEAD.

| Role | Fixed path | HEAD | Parent | Worktree |
|---|---|---|---|---|
| Production SourceRoot | `C:\Dev\f2-g1-protected-updater-source` | `396c44965c90c08292ad2835f8317e81b6b9daaf` | `f58b7fdfaf71e212213d559480e1913ae6c210f8` | Clean, detached |
| Launcher candidate root | `C:\Dev\f2-g1-protected-updater` | `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d` | `396c44965c90c08292ad2835f8317e81b6b9daaf` | Clean, detached |

The candidate worktree began at `923c7d39d7fbfe106dea404c386efd4b5844654e`, an ancestor of PR #65. It was advanced with a fast-forward-only update to `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`. No named branch was checked out, reset, deleted, or moved. The production SourceRoot stayed at the reviewed production commit.

## Physical Windows checkout hashes

The following SHA-256 values were computed from the files at the fixed paths on this Windows host. These are checkout-byte hashes.

### Production SourceRoot

| File | SHA-256 |
|---|---|
| `scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1` | `9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9` |
| `scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1` | `d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2` |
| `scripts/f2-acl/F2ProtectedRelease.Diagnostics.ps1` | `66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7` |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |

### Candidate checkout and release manifest

| File | SHA-256 |
|---|---|
| `docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json` | `b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022` |
| `scripts/f2-acl/F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `scripts/f2-acl/F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `scripts/f2-acl/F2AclIcacls.Runtime.psm1` | `d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4` |
| `scripts/f2-acl/Invoke-F2IcaclsCapture.ps1` | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1` | `9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515` |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |
| `scripts/f2-acl/Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

The candidate JSON parses as `f2-icacls-runtime-release-v3`, pins `ReviewedCommitSha` to `396c44965c90c08292ad2835f8317e81b6b9daaf`, uses the matching versioned release `PackageRoot`, carries the two distinct retained-baseline identities and hashes, and lists seven release files. Its source pin manifest hash is `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce`.

## Fresh standard-token preflight

The exact command executed under Windows PowerShell 5.1 was:

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\Dev\f2-g1-final-independent-preflight\docs\reviews\f2-g1-final-independent-preflight\preflight\Invoke-F2G1StandardReadOnlyPreflight.ps1'
```

**Child exit code:** `0`
**PowerShell:** `5.1.22621.6133`
**Token:** standard user; Administrator role not enabled
**Result:** `PASS_READ_ONLY_PREFLIGHT`; all six gates passed.

| Gate | Result | Sanitized finding |
|---|---|---|
| Windows PowerShell and token | PASS | PowerShell 5.1; non-administrator token |
| Fixed Git checkouts and PR ref | PASS | Both roots, exact commits/parents, expected origin, clean worktrees, and PR #65 ref verified |
| Reviewed source/candidate hashes | PASS | Production executables, candidate manifest, source pin manifest, and seven package members match full hashes above |
| C: root and protected parents | PASS | Reviewed C: root, Program Files, and ProgramData ACL policies pass |
| Existing v2 installation | PASS | Active v2 manifest SHA-256 `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9`; four protected directories and seven original package hashes/owners/DACL profiles pass; no reparse paths or transaction, lock, backup, staging, or v3-release objects found |
| Retained baseline | PASS | Four-ACE mailbox profile, two distinct identities, pinned payload/integrity hashes, 11 unique authorized records, and required evidence-file integrity pass |

The original baseline mailbox contains the producer’s seven expected evidence files. The first audit attempt had an incorrect two-file content-set expectation and stopped with `BASELINE_MAILBOX_CONTENT_SET_INVALID`; no baseline file was changed. After checking the original producer’s output contract, the read-only audit was corrected to validate the seven artifacts and their hashes. The second run passed. Both attempt logs are included. The first attempt was an audit-script expectation error, not a protected-host mismatch.

The baseline identifiers verified were mailbox `ecb6deeb424e40feb5354d18908986df` and payload `CaptureId` `489e7fec-0300-467c-bfbd-a46fb8cf7211`. Payload SHA-256 is `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`; integrity SHA-256 is `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`. The mailbox’s five additional expected artifact hashes are recorded in `READ_ONLY_PREFLIGHT_ATTEMPT2.log`. Raw SDDL and private SIDs are omitted.

The preflight queried ACLs using `Get-Acl` and read-only file, path, hash, and Git APIs. It did not run `icacls.exe`, query VM/Hyper-V or G:, or modify protected files. The preflight script contains no mutating filesystem, ACL, VM, or `icacls.exe` command.

Sanitized machine result: readable LF view [`READ_ONLY_PREFLIGHT_ATTEMPT2.log`](evidence/READ_ONLY_PREFLIGHT_ATTEMPT2.log); lossless original capture [`READ_ONLY_PREFLIGHT_ATTEMPT2.log.raw.b64`](evidence/READ_ONLY_PREFLIGHT_ATTEMPT2.log.raw.b64), decoded SHA-256 `3f59fe2970646c883aef37750f63706257d5f3e268898342b976fa508d3cb147`.

## Aggregate-run failure investigation

### Preserved original failure

The PR #65 evidence artifact [`WINDOWS_PS51_REGRESSION_ATTEMPT1.log.b64`](../f2-g1-prelock-failure-localization/evidence/WINDOWS_PS51_REGRESSION_ATTEMPT1.log.b64) decodes to SHA-256 `f5274928452fac78e081f58841ae7f9f118ed450e7f3e38bc0a89fd87a18e628`. It records the protocol suite passing `152` assertions, followed by a `Test-F2AclIcacls.Corroboration.ps1 : nonzero child exit` and aggregate `RUNNER_PROCESS_EXIT=1`. It does not preserve the nested child’s underlying diagnostic. Therefore the original aggregate failure cause remains **UNKNOWN**.

### Bounded non-elevated reproduction

The corroboration suite was run directly in a fresh Windows PowerShell process: `Test-F2AclIcacls.Corroboration.ps1` completed with `118` assertions, `0` failures, exit `0`. Its readable output is [`CORROBORATION_REPRO2.combined.txt`](evidence/CORROBORATION_REPRO2.combined.txt); the lossless raw capture is [`CORROBORATION_REPRO2.combined.txt.raw.b64`](evidence/CORROBORATION_REPRO2.combined.txt.raw.b64), decoded SHA-256 `8e4ad6cf8c3a8fa7ef6c92be1295d978cafefa52feeb19b50d5cdad2a65a5d64`.

The exact PR #65 aggregate runner was then run in a fresh Windows PowerShell 5.1 process:

```text
"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Dev\f2-g1-final-independent-preflight\scripts\f2-acl\Test-F2ProtectedReleaseDiagnosticSuites.ps1"
```

It completed with `SUITES=7;FAILED=0`, total `542` assertions and `0` failures, child exit `0`. Per-suite counts were 152, 118, 41, 18, 136, 20 and 57. The runner’s output file was preserved into the evidence folder and the original tracked log bytes were restored; the receipt verifies `RestoredByteExact=True`, restored SHA-256 `d9e9bd2be8f7c7ed8c10097431ed628a91b2984b3033c5894feac6b23ec0d4f9`, and child-runner output SHA-256 `6dc232c67c36a989d157863ec9f35195d26d1cd8ea1a9c5549e6389a9699928a`. The human-readable log is [`AGGREGATE_REGRESSION_REPRO.log`](evidence/AGGREGATE_REGRESSION_REPRO.log); the lossless raw capture is [`AGGREGATE_REGRESSION_REPRO.log.raw.b64`](evidence/AGGREGATE_REGRESSION_REPRO.log.raw.b64).

One earlier diagnostic wrapper using `Start-Process` redirection produced `Get-FileHash`-not-recognized in its child. That result was wrapper-context-specific: the standalone fresh-process rerun and the exact aggregate runner both passed. Its exact stderr bytes are retained as base64 in `CORROBORATION_REPRO.stderr.b64` (decoded SHA-256 `0fffc2cb2390661fcdf709bc8fd90d7cfa59b97b369d2bd3ff2157fc864678fd`) and are not evidence that the preserved aggregate failure’s cause was found.

**Conclusion:** The earlier aggregate failure was **not reproduced** under the faithful Windows PowerShell 5.1 aggregate runner. The original failure’s cause remains **UNKNOWN**; passing reproduction attempts do not explain the historical child exit.

## Validation and evidence files

Parser command for the new read-only audit script:

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -Command '$p="C:\Dev\f2-g1-final-independent-preflight\docs\reviews\f2-g1-final-independent-preflight\preflight\Invoke-F2G1StandardReadOnlyPreflight.ps1"; $t=$null; $e=$null; [System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e) | Out-Null; Write-Output ("ParserErrors={0}" -f $e.Count); if($e.Count -gt 0){$e | ForEach-Object { Write-Output $_.Message }; exit 1}; exit 0'
```

Result: `ParserErrors=0`, exit `0`. The live preflight emits only allowlisted gate outcomes and approved hashes; it does not emit raw SDDL or the requester SID. The regression logs are synthetic test output. The inherited PR #65 encoded attempt log is preserved unchanged and linked above.

The reviewed PR #65 source HEAD also has successful hosted checks: [F2 ACL source-only validation run 38386916406](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38386916406) and [Starter checks run 38386916425](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38386916425). These runs validate PR #65 HEAD, not this separate receipt branch; the receipt PR’s own checks must be evaluated from its GitHub status after publication.

| Artifact | Purpose |
|---|---|
| `preflight/Invoke-F2G1StandardReadOnlyPreflight.ps1` | Read-only, sanitized host/path/source audit; no elevation or writes |
| `evidence/READ_ONLY_PREFLIGHT_ATTEMPT1.log` and `.raw.b64` | Readable and lossless copies of first audit-script failure and gate results |
| `evidence/READ_ONLY_PREFLIGHT_ATTEMPT2.log` and `.raw.b64` | Readable and lossless copies of the complete six-gate PASS receipt |
| `evidence/PREFLIGHT_PARSER_PS51.log` and `.raw.b64` | Readable and lossless Windows PowerShell 5.1 parser result |
| `evidence/AGGREGATE_REGRESSION_REPRO.log` and `.raw.b64` | Readable and lossless seven-suite output |
| `evidence/AGGREGATE_REGRESSION_REPRO_STATUS.txt` and `.raw.b64` | Readable and lossless exact child command, exit, log digest and original-log restoration check |
| `evidence/CORROBORATION_REPRO2.combined.txt` and `.raw.b64` | Readable and lossless direct corroboration suite output |
| `evidence/CORROBORATION_REPRO.stdout.txt`, `evidence/CORROBORATION_REPRO.stderr.b64` | Preserved wrapper-specific attempt output; stderr is losslessly base64 encoded |
| `evidence/SHA256_MANIFEST.txt` | SHA-256 values for all package artifacts |

## Remaining uncertainty and next gate

- The actual cause inside the prior aggregate-test child has not been recovered or reproduced.
- The elevated updater must not be run from this receipt, and no third UAC is authorized. A future run requires fresh independent preflight review and a new explicit owner authorization.
- This read-only pass is time-sensitive host evidence. Revalidate fixed paths, source/file hashes, protected state, and transaction absence before any separately authorized execution.
- The receipt is not ACL acceptance, not an update receipt, and not proof of elevated behavior.

## Changed paths in this receipt branch

Only `docs/reviews/f2-g1-final-independent-preflight/` is added. PR #65 production source, tests, and branch are unchanged.
