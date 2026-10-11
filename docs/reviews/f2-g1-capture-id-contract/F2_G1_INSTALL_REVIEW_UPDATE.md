# F2 G1 consolidated protected-install review

Status: consolidated source correction and read-only host audit prepared for independent review. No protected installation, UAC, live `icacls`, VM/Hyper-V query, G: operation, ACL change, or native workload was performed.

## Correction

`Get-F2RuntimeReleaseManifest` now requires `f2-icacls-runtime-release-v2`, matching the protected installer and `Test-F2RuntimeReleasePackage`. The Windows PowerShell 5.1 regression writes synthetic manifests to temporary files and calls the actual disk-loading function with `F2RuntimeReleaseProvider` set to `$null`. It verifies valid v2 load and the downstream seven-file package contract, rejects v1 and malformed JSON, and rejects missing `BaselineMailboxId` or `BaselinePayloadCaptureId` through the downstream contract.

The consolidated audit also fixed the only live deterministic parent-ACL rejection. `C:\` grants Authenticated Users the exact directory mask `0x00000004` with no inheritance flags. The validator accepts it only while walking the exact canonical `C:\` root and only with the previously observed protected root DACL profile. It separately verifies the one exact inherit-only root `0xE0010000` ACE, and requires protected DACLs on all destination parents. Program Files and ProgramData receive no root-mask exception. The ProgramData `0x116` allowance is also limited to one exact ContainerInherit ACE. See `CONSOLIDATED_INSTALL_READINESS.md` for the sanitized live ACE inventory, full gate matrix, test evidence, and risks.

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

- Installer: `Install-F2IcaclsProtectedPackage.ps1`, SHA-256 `be622923a5931a1cc1ce8cfff18c72952b836f8f84e403a419254c6c2c778b0e`.
- One-read verified-byte bootstrap: `Invoke-F2VerifiedInstaller.ps1`, SHA-256 `3ae8fee4cfa7c809110a3233f9df2ad8f1fe877c91f1a4067e08541c5e893060`.
- Installer synthetic test: `Test-Install-F2IcaclsProtectedPackage.ps1`, SHA-256 `a1967eff0627d3bbb3bd4be2a52c9acfa40f401e216e9988ab0b837e9cf967df`.
- Bootstrap preparation path: `C:\Dev\f2-g1-protected-install-prep\Invoke-F2VerifiedInstaller.ps1`.
- Installer preparation path: `C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1`; this matches the fixed path embedded in the bootstrap.
- The bootstrap pins the installer SHA-256 above and reads, verifies, and executes the same in-memory bytes. The installer pins the unchanged production source commit and all seven package hashes above.

## Exact future installation command (not run)

After independent review and fresh owner authorization, first replace only the two known prior preparation files at the paths above with the accepted exact bytes, checking their old SHA-256 values (`cf480bf047f9d38e21e11e75cd4f30ddd487bbb4af6c9474464b7596e675baf5` bootstrap and `ca4d5a213615b1ce74d8fc7df17e7bb65ccfbcacd9dd7de2c9a6c36d42842d2d` installer) and confirming they are regular non-reparse files. Then verify new hashes `3ae8fee4cfa7c809110a3233f9df2ad8f1fe877c91f1a4067e08541c5e893060` and `be622923a5931a1cc1ce8cfff18c72952b836f8f84e403a419254c6c2c778b0e`. Do not overwrite any unexpected file. Run the following from the original requester account in Windows PowerShell 5.1; the command displays the normal human-consented UAC prompt.

```powershell
$bootstrapPath = 'C:\Dev\f2-g1-protected-install-prep\Invoke-F2VerifiedInstaller.ps1'
$expectedBootstrapSha = '3ae8fee4cfa7c809110a3233f9df2ad8f1fe877c91f1a4067e08541c5e893060'
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

This command is documentation only and was not executed. The previous installation authorization does not cover these changed executable bytes; independent review and fresh authorization remain required. The current local preparation copies still have the known previous hashes and were intentionally left untouched pending that gate.

## Retained baseline contract

Mailbox ID `ecb6deeb424e40feb5354d18908986df` and payload CaptureId `489e7fec-0300-467c-bfbd-a46fb8cf7211` remain separate, independently pinned identities. The unchanged baseline payload SHA-256 is `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`; integrity SHA-256 is `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`. Baseline bytes were not modified or recaptured.

See `CONSOLIDATED_INSTALL_READINESS.md`, `TEST_EVIDENCE.md`, and `REVIEW_MANIFEST.md` for the exact readiness matrix, sanitized root-ACL analysis, test commands/results, CI run, and file hashes.
