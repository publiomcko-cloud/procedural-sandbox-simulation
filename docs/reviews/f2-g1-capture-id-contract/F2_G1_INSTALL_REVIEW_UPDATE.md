# F2 G1 capture identity correction and install review update

Status: `READY_FOR_INDEPENDENT_CAPTURE_ID_CONTRACT_REVIEW`. This is source and synthetic-test evidence only. The protected installation and live ACL corroboration have not been performed.

## Corrected identity contract

The retained producer uses two independent identifiers. `ecb6deeb424e40feb5354d18908986df` is the N-format mailbox/directory ID. `489e7fec-0300-467c-bfbd-a46fb8cf7211` is the D-format payload `CaptureId`. They are independently pinned, validated against their respective values, and never compared to each other. The mailbox ID continues to select the mailbox path and four-ACE mailbox verification.

The unchanged local retained files were rehashed and parsed read-only:

- `acl-baseline.json`: `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`; embedded payload CaptureId matched; 11 records and Complete=true.
- `integrity.json`: `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`.

No baseline bytes were changed, renamed, or recaptured.

## Source lineage

- Production source commit: `54b1d0c7a9865d710c19b59cd38c0da670a12536`.
- Parent: `a0edf58a75c4ff947defc05acf723a1be0f1c34c`.
- Initial correction parent: reviewed PR #50 source `2c967661163fc157b638fa4f76da86c48aa57ff2`.
- The runtime release contract is now schema `f2-icacls-runtime-release-v2`, requiring both independent identity fields. The installer pins this commit and the seven-file package. The source worktree referenced by the installer must be a clean checkout at the exact source commit above.

## Seven-file package pins

| Package file | SHA-256 |
| --- | --- |
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `F2AclIcacls.Runtime.psm1` | `eecec7b86a4bfee7773e73b537ed74ae573ff3d5bfaaa44b9d1bc42c4e1953a7` |
| `Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` |
| `F2_ICACLS_SOURCE_PINS.json` | `cee4322fdc4603cdebeccfe3411303a0ea92db946aa920b8ad60cb3152cae3c5` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

The pin manifest binds the six executable/module package members and remains included as the seventh file. All six manifest values were rehashed and matched.

## Installer review artifacts

- Installer `Install-F2IcaclsProtectedPackage.ps1`: `235aea7748c2c67b6c52996d5de4dd02a88709b46b96fff1710bd671b4fac0e4`.
- One-read SHA-bound bootstrap `Invoke-F2VerifiedInstaller.ps1`: `a466e347843d74e5474021a852e886aceb9e4e8b4d3c71c6db4857d861d92e82`.
- Synthetic installer test: `796dc3fb7d392dc68ed9fd0453a260eee310a8372dce5590d50145f07efab694`.
- `approved-release.json` uses schema `f2-icacls-runtime-release-v2` and binds reviewed source commit, mailbox ID, payload CaptureId, both baseline file hashes, source-pin manifest hash, and exactly seven `{Name,Sha256}` entries.

## Validation results

Windows PowerShell 5.1 synthetic suites passed: corroboration **118 assertions, 0 failures, exit 0**; runtime **29 assertions, 0 failures, exit 0**; installer **31 assertions, 0 failures, exit 0**. The parser sweep checked **12 PowerShell files, 0 parser errors**. Exact commands and full bounded test output are in the adjacent `WINDOWS_POWERSHELL_5_1_*.log` files; their hashes are in `REVIEW_MANIFEST.md`. Windows GitHub CI is reported in `TEST_EVIDENCE.md` after publication.

All fixtures are synthetic/local temporary data. These results do not establish protected installation, live ACL state, UAC behavior, VM state, or security acceptance.

## Future installation command (not run)

The source change alters executable bytes. The earlier installation authorization does not cover these bytes; a new independent review and fresh owner authorization are required before any UAC or installation. After those gates, this is the reviewed command shape, from the original requester account:

```powershell
$bootstrapPath = 'C:\Dev\f2-g1-protected-install-prep\Invoke-F2VerifiedInstaller.ps1'
$expectedBootstrapSha = 'a466e347843d74e5474021a852e886aceb9e4e8b4d3c71c6db4857d861d92e82'
$bootstrapBytes = [IO.File]::ReadAllBytes($bootstrapPath)
$sha = [Security.Cryptography.SHA256]::Create()
try { $actualBootstrapSha = ([BitConverter]::ToString($sha.ComputeHash($bootstrapBytes))).Replace('-', '').ToLowerInvariant() }
finally { $sha.Dispose() }
if ($actualBootstrapSha -cne $expectedBootstrapSha) { throw 'Bootstrap SHA-256 mismatch; refusing UAC launch.' }
$source = [Text.UTF8Encoding]::new($false, $true).GetString($bootstrapBytes)
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
$child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
if ($child.ExitCode -ne 0) { throw "Elevated installer failed with exit code $($child.ExitCode)." }
```

This task did not run UAC, install protected files, execute `icacls`, inspect live ACLs or VM/Hyper-V state, write to G:, change permissions, or merge any PR.
