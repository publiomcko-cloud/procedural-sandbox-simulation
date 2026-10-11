# F2 G1 protected package installation procedure — review handoff

**Disposition:** READY_FOR_INDEPENDENT_INSTALL_PROCEDURE_REVIEW. Do not execute until review of the exact installer SHA below.

## Pinned source reviewed for installation

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- PR #50: draft/open; no changes made to it during this preparation
- Branch: `security/f2-icacls-corroboration-issue48`
- Exact clean source HEAD: `2c967661163fc157b638fa4f76da86c48aa57ff2`
- Remote: `origin https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Source pin manifest SHA-256: `19043bbea7fa42bae6320046524c1920174fea543559c83fc5630c0b35b4fa78`
- Retained capture: `ecb6deeb424e40feb5354d18908986df`
- Baseline payload SHA-256: `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`
- `integrity.json` SHA-256: `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`

The procedure copies exactly these seven files into the protected package; every digest is checked before staging and rechecked after publication:

| File | SHA-256 |
|---|---|
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `06acb1d2eee45abcf1531a9b7113e342320b239bbc32aae1a10d114b55eaa13e` |
| `F2AclIcacls.Runtime.psm1` | `e6751179d2a36abea65527c260fb0f1d1cc81bdccf867172befba4e9f5dffddc` |
| `Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` |
| `F2_ICACLS_SOURCE_PINS.json` | `19043bbea7fa42bae6320046524c1920174fea543559c83fc5630c0b35b4fa78` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

## Reviewed standalone procedure

- Installer: `Install-F2IcaclsProtectedPackage.ps1`
- Installer SHA-256: `a6a130edf307341032200b88b68f719fc8a3540830d09bb2d26631993524a5c8`
- Synthetic test: `Test-Install-F2IcaclsProtectedPackage.ps1`
- Test SHA-256: `8ab26b728efc2ec43b94c22fe1031d38cdf754a6d54e13181857d6d3fa27f8f5`
- Runtime: Windows PowerShell 5.1 only; no parameters are accepted by the installer entrypoint.

## Installation contract

The administrator-owned package is published at:

- Package root: `C:\Program Files\F2-G1-Icacls`
- Seven files: `C:\Program Files\F2-G1-Icacls\scripts\f2-acl\`
- External release manifest: `C:\ProgramData\F2-G1-Icacls\approved-release.json`

The generated release manifest has schema `f2-icacls-runtime-release-v1` and binds the reviewed commit, capture ID, payload SHA-256, raw `integrity.json` SHA-256, source-pin manifest SHA-256, and exact seven file names and hashes.

Every created directory is owned by `BUILTIN\Administrators` (SID `S-1-5-32-544`), protected from inheritance, and has exactly these Allow ACEs: SYSTEM Full Control; Administrators Full Control; Authenticated Users Read & Execute (`0x001200A9`). Directory ACE flags are Object Inherit + Container Inherit. Every installed file and the release manifest are also administrator-owned and DACL-protected, with the same three principals and masks but no inheritance flags. No other ACE, owner, inherited grant, reparse point, or ordinary-user write grant passes verification.

The existing parents are never modified. The installer reads and rejects unsafe parent DACLs on the C: ancestry and baseline mailbox. It accepts the known `BUILTIN\Users` ProgramData mask `0x116` only on the ProgramData parent; newly created children receive a protected DACL at creation. All final destinations must be absent. Seven package files and the manifest use `FileMode.CreateNew`; randomized stage directories are published with same-volume no-overwrite directory moves. If publication fails after one final move, the procedure reports an incomplete partial install and leaves it for review; it does not overwrite, silently clean up, or retry.

On success, the sanitized JSON attestation covers four final directories, seven package files, and the release manifest: canonical paths, owner SID, DACL protection, every ACE's SID/category/type/mask/inheritance/propagation, reparse result, file size, and SHA-256. It emits no raw baseline SDDL or ACL capture payload.

## Synthetic validation

Command:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\Test-Install-F2IcaclsProtectedPackage.ps1
```

Result: **17 assertions, 0 failures**. The test exercised the actual installation core against temporary source, Program Files-like, ProgramData-like, and baseline directories, without elevation. Cases include successful publication and full ACL/hash attestation, exact seven-file manifest binding, accepted ProgramData child-create rights, rejected DELETE_CHILD/WRITE_DAC/WRITE_OWNER/GENERIC_ALL and unknown parent masks, unprotected DACL rejection, simulated reparse ancestry, existing destination preservation, source tampering, and baseline tampering. Both PS1 files parsed with zero errors.

No protected installation was attempted; no UAC was requested; no live `icacls`, VM, G: write, or native workload was performed. The synthetic test does not prove the live parent ACLs or installed host state.

## Deferred privileged operations

After independent review of the exact installer SHA, the authorized administrator run would:

1. Read the exact baseline mailbox DACL and the two pinned baseline files; read parent DACLs for `C:\`, `C:\Program Files`, and `C:\ProgramData`; verify source/baseline identities and hashes.
2. Create randomized protected staging directories below `C:\Program Files` and `C:\ProgramData`, plus `scripts` and `f2-acl` beneath the package staging directory.
3. Set the exact protected DACLs on those newly created directories and on each of the seven newly created files and `approved-release.json`.
4. Copy the seven pinned files from the reviewed checkout, create the release JSON, reverify hashes/ACLs/reparse status, then move the two staging directories into the exact final paths above without overwrite.
5. Query the final parent and installed-object state and emit the sanitized attestation.

It does **not** change existing ACLs, parent directories, source files, baseline evidence, G:, VM/Hyper-V settings, networking, Windows features, or PR state. It does not run the installed launcher or coordinator. Any failed prerequisite stops before publishing; a mid-publication failure is reported with the exact final/staging state and requires review before any cleanup.

Suggested post-review UAC invocation (not executed):

```powershell
Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1"' -Wait -PassThru
```

Verify the installer SHA with `Get-FileHash` immediately before the independently authorized run. A later live ACL collection remains a separate action and is not part of installation authorization.
