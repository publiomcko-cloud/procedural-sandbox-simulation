# F2 G1 v2 release-manifest loader correction and install review

Status: source-only correction prepared for independent review. No protected installation, UAC, live `icacls`, ACL/VM query, G: operation, or native workload was performed.

## Correction

`Get-F2RuntimeReleaseManifest` now requires `f2-icacls-runtime-release-v2`, matching the protected installer and `Test-F2RuntimeReleasePackage`. The Windows PowerShell 5.1 regression writes synthetic manifests to temporary files and calls the actual disk-loading function with `F2RuntimeReleaseProvider` set to `$null`. It verifies valid v2 load and the downstream seven-file package contract, rejects v1 and malformed JSON, and rejects missing `BaselineMailboxId` or `BaselinePayloadCaptureId` through the downstream contract.

## Source lineage and clean SourceRoot

- PR #53 review branch: `fix/f2-baseline-capture-identity-issue48`.
- Production source commit: `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`.
- Production source parent: `4c53f6dd03c6ddc564a45f8c203286595385c46b`.
- SourceRoot: `C:\Dev\f2-g1-capture-id-contract-source`.
- Verified checkout: exact HEAD `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, clean worktree, and expected repository origin. The installer embeds this exact SourceRoot.
- Historical PR #50 source baseline remains `2c967661163fc157b638fa4f76da86c48aa57ff2`; PR #50 was not modified.

## Seven-file package pins

| Package file | SHA-256 |
| --- | --- |
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `F2AclIcacls.Runtime.psm1` | `950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5` |
| `Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` |
| `F2_ICACLS_SOURCE_PINS.json` | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

The seven-file installer package contains the six executable/module files plus the source-pin manifest. Each pin was recomputed from the clean SourceRoot checkout; the pin manifest hashes the six executable/module files.

## Installer and bootstrap

- Installer: `Install-F2IcaclsProtectedPackage.ps1`, SHA-256 `ca4d5a213615b1ce74d8fc7df17e7bb65ccfbcacd9dd7de2c9a6c36d42842d2d`.
- One-read verified-byte bootstrap: `Invoke-F2VerifiedInstaller.ps1`, SHA-256 `cf480bf047f9d38e21e11e75cd4f30ddd487bbb4af6c9474464b7596e675baf5`.
- Installer synthetic test: `Test-Install-F2IcaclsProtectedPackage.ps1`, SHA-256 `67851441b9196d6b95338a2a704363157b27d3a73e0afd8d0e2345b8030ae3ee`.
- Bootstrap preparation path: `C:\Dev\f2-g1-protected-install-prep\Invoke-F2VerifiedInstaller.ps1`.
- Installer preparation path: `C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1`; this matches the fixed path embedded in the bootstrap.
- The bootstrap pins the installer SHA-256 above and reads, verifies, and executes the same in-memory bytes. The installer pins the source commit and all seven package hashes above.

## Exact future installation command (not run)

After independent review and fresh owner authorization, run from the original requester account in Windows PowerShell 5.1. The bootstrap and installer must first be placed unchanged at the preparation paths above.

```powershell
$bootstrapPath = 'C:\Dev\f2-g1-protected-install-prep\Invoke-F2VerifiedInstaller.ps1'
$expectedBootstrapSha = 'cf480bf047f9d38e21e11e75cd4f30ddd487bbb4af6c9474464b7596e675baf5'
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

This command is documentation only. This task did not execute it. The previous installation authorization does not cover these changed executable bytes; independent review and fresh authorization remain required.

## Retained baseline contract

Mailbox ID `ecb6deeb424e40feb5354d18908986df` and payload CaptureId `489e7fec-0300-467c-bfbd-a46fb8cf7211` remain separate, independently pinned identities. The unchanged baseline payload SHA-256 is `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`; integrity SHA-256 is `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`. Baseline bytes were not modified or recaptured.

See `TEST_EVIDENCE.md` and `REVIEW_MANIFEST.md` for exact commands, results, CI run, and raw file hashes.
