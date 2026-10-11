# F2 G1 final installer review update

This publication supplements the unchanged historical `F2_G1_PROTECTED_INSTALL_REVIEW.md`. Use this update for the current bootstrap and regression evidence; the historical handoff's 17-assertion result and direct `-File` suggestion are superseded.

## Reviewed source files

- Bootstrap: `Invoke-F2VerifiedInstaller.ps1`, SHA-256 `5d6615dafc6608bb8777703eeb4909e796034f66eb2f2e16bc7f868cb885d965`.
- Installer: `Install-F2IcaclsProtectedPackage.ps1`, SHA-256 `a6a130edf307341032200b88b68f719fc8a3540830d09bb2d26631993524a5c8` (unchanged from the independently inspected installer).
- Synthetic suite: `Test-Install-F2IcaclsProtectedPackage.ps1`, SHA-256 `e0b80d6a178c4a9b3c8d4bdbff10e5f91e2d320435ff8293f576a340fa14b543`.

The bootstrap's fixed installer input is `C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1`, the reviewed source file available before installation. It reads that file once, checks those bytes against the exact approved installer SHA-256, decodes the same byte array as strict UTF-8, creates a script block from that verified text, and invokes it. It does not reopen the installer path to execute it. The approved installer SHA remains unchanged. Its production target and expected installer hash are fixed in the bootstrap. A regression checks the actual production path and digest constants. The outer command below similarly hashes one bootstrap byte snapshot and sends that same source as `-EncodedCommand`.

## Different Administrator SID behavior

The installer derives `RequesterSid` from the effective Windows identity and retains the reviewed exact four-ACE mailbox contract. A same-account UAC elevation retains the same account SID. If UAC instead runs under a different Administrator account, the requester's expected ACE will not match the captured mailbox; baseline validation fails in preflight, before staging directories or package/release files are created. The contract is not relaxed to admit another SID. The regression uses a synthetic four-ACE mailbox fixture and does not claim a live UAC test.

## Safe installation command (not executed)

Run only after independent review and the separately required installation authorization. Start from the original baseline-requester account so ordinary UAC consent elevates that account. The command checks the bootstrap hash before opening UAC, then passes only the already-verified bytes to elevated Windows PowerShell 5.1:

```powershell
$bootstrapPath = 'C:\Dev\f2-g1-protected-install-prep\Invoke-F2VerifiedInstaller.ps1'
$expectedBootstrapSha = '5d6615dafc6608bb8777703eeb4909e796034f66eb2f2e16bc7f868cb885d965'
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

This command was not executed. UAC cancellation, protected installation, live host inspection, and subsequent ACL collection remain unperformed.

## Current validation

Windows PowerShell 5.1 synthetic suite command:

```powershell
& $env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\docs\reviews\f2-g1-installer-evidence\Test-Install-F2IcaclsProtectedPackage.ps1
```

Result: **23 assertions, 0 failures, process exit code 0**. Three files passed Windows PowerShell 5.1 parser validation with zero errors. The tests use temporary synthetic directories only. They include a check of the fixed production installer input path and approved digest, successful package attestation, source/evidence tampering, collision and reparse rejection, and a different-requester-SID preflight failure with no package, release, or staging writes. The full assertion output and parser command are in `TEST_EVIDENCE.md`.

No installer/bootstrap execution, UAC, protected installation, live `icacls`, live ACL/token query, VM operation, G: write, or native workload was performed.
