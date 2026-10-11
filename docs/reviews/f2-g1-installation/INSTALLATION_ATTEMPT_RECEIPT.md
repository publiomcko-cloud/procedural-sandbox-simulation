# F2 G1 protected installation attempt receipt

**Outcome: BLOCKED_WITH_EVIDENCE — installation did not run.**

This receipt records the authorized one-time installation attempt preflight. It contains no raw ACL/SDDL data, account SID, credentials, or live VM data.

## Reviewed inputs

- PR #50 production source: `2c967661163fc157b638fa4f76da86c48aa57ff2` (clean worktree; expected origin).
- PR #51 installer review: `cdf689ba30896a00dc1008713330b085e4b7c92c` (clean review worktree).
- Approved bootstrap SHA-256: `5d6615dafc6608bb8777703eeb4909e796034f66eb2f2e16bc7f868cb885d965`.
- Approved installer SHA-256: `a6a130edf307341032200b88b68f719fc8a3540830d09bb2d26631993524a5c8`.
- Reviewed test script SHA-256: `e0b80d6a178c4a9b3c8d4bdbff10e5f91e2d320435ff8293f576a340fa14b543`.

The outdated preparation bootstrap was verified at its known prior SHA-256 `c783f319b88f647cc8decd98d7d716b419d06994eb960a2c6be524fd4a43bb98`, then replaced with the exact reviewed bootstrap bytes. The replacement hash was verified as `5d6615dafc6608bb8777703eeb4909e796034f66eb2f2e16bc7f868cb885d965`. The installer file was unchanged and matched its approved SHA-256.

## Preflight results

| Gate | Result | Evidence |
| --- | --- | --- |
| PR #50 exact HEAD, clean worktree, expected origin | PASS | HEAD `2c967661163fc157b638fa4f76da86c48aa57ff2`; no worktree changes; origin `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git` |
| PR #51 exact reviewed HEAD, clean worktree | PASS | HEAD `cdf689ba30896a00dc1008713330b085e4b7c92c`; no worktree changes |
| Bootstrap and installer pins | PASS | Exact approved SHA-256 values above |
| Seven PR #50 package pins | PASS | All seven values listed below matched the installer pins |
| Baseline files' outer SHA-256 pins | PASS | `acl-baseline.json`: `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`; `integrity.json`: `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34` |
| Baseline internal capture identity/completeness | **FAIL** | The pinned evidence directory is `F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df`, while its payload's `CaptureId` is `489e7fec-0300-467c-bfbd-a46fb8cf7211`. The installer requires an exact match to `ecb6deeb424e40feb5354d18908986df`. |
| Original requester account | PASS | Current standard-token account matched an ACE in the retained baseline mailbox. The SID and ACL details are intentionally not published. |
| Protected destinations and staging | PASS | Both final destinations were absent; no matching staging directories were found. |

The internal capture identity mismatch was the fail-closed gate. No attempt was made to alter or reinterpret the baseline.

## Process and installation status

- Preflight validation process exit code: **1** (`BASELINE_CONTENT_GATE_FAILED`).
- Reviewed UAC installation command executed: **No**.
- UAC prompts / elevated attempts: **0**.
- Elevated installer process exit code: **Not applicable; process was not started**.
- Installer JSON status: **Not produced**.
- Installation stage reached: **Preflight only; no staging creation**.
- Protected package destination `C:\Program Files\F2-G1-Icacls`: **Absent**.
- Release destination `C:\ProgramData\F2-G1-Icacls`: **Absent**.
- Leftover staging directories: **None observed**.
- Installed directories/files/manifest: **None**.
- Installed-object ACL, owner, reparse, or manifest attestations: **Not applicable; nothing was installed**.
- Release manifest SHA-256: **Not applicable; manifest was not created**.
- No retry, cleanup, overwrite, ACL change, or protected destination write occurred.

## Seven production package SHA-256 values

| File | SHA-256 |
| --- | --- |
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `06acb1d2eee45abcf1531a9b7113e342320b239bbc32aae1a10d114b55eaa13e` |
| `F2AclIcacls.Runtime.psm1` | `e6751179d2a36abea65527c260fb0f1d1cc81bdccf867172befba4e9f5dffddc` |
| `Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` |
| `F2_ICACLS_SOURCE_PINS.json` | `19043bbea7fa42bae6320046524c1920174fea543559c83fc5630c0b35b4fa78` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

## Approved command (not executed)

The exact reviewed command from PR #51 was not executed because the baseline content gate failed:

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

## Next gate

Do not proceed with installation using this baseline. The capture identity inconsistency requires independent review and resolution under the established evidence rules. This receipt does not authorize a retry, baseline modification, ACL collection, or any other privileged action.
