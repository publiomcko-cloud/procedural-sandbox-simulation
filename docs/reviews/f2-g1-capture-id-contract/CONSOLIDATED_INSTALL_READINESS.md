# F2 G1 consolidated protected-install readiness audit

Status: **READY_FOR_CONSOLIDATED_INSTALL_REVIEW**. This is a source and read-only host audit. It is not installation acceptance or authorization to run UAC.

## Scope and immutable inputs

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`.
- Existing draft PR: #53, branch `fix/f2-baseline-capture-identity-issue48`. The audited starting head was `9c2e6db22c433d736eff9358e62f20eb8f6b2071`; the production package source remains pinned to `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1` (parent `4c53f6dd03c6ddc564a45f8c203286595385c46b`).
- SourceRoot: `C:\Dev\f2-g1-capture-id-contract-source`, exact production commit, clean, expected GitHub origin.
- Seven-file source-pin manifest SHA-256: `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7`.
- Baseline mailbox ID: `ecb6deeb424e40feb5354d18908986df`.
- Baseline payload CaptureId: `489e7fec-0300-467c-bfbd-a46fb8cf7211`.
- Retained payload SHA-256: `1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014`.
- Retained integrity SHA-256: `02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34`.

The baseline mailbox and payload are separate identities. The original payload files were read and hash-checked in place; neither file nor its four-ACE mailbox DACL was modified.

## Consolidated gate matrix

| Gate | Result | Evidence / limits |
| --- | --- | --- |
| Review checkout lineage and remote | PASS | Review branch was clean at the reviewed starting SHA before this correction; expected repository origin. The production SourceRoot is still clean at the pinned source commit. |
| SourceRoot package files and pins | PASS | The installer’s actual `Get-F2InstallPackageBytes` function read and verified exactly seven files against the pin manifest. Checkout line endings were included in the byte hashes. |
| Installer, bootstrap, and release contract | PASS | Installer pins source commit `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, seven files, the separate baseline IDs, and schema `f2-icacls-runtime-release-v2`. The bootstrap pins the installer bytes and still reads, hashes, and executes the same in-memory bytes once. |
| Baseline integrity and completeness | PASS | The actual installer baseline reader accepted the pinned payload/integrity hashes, distinct IDs, exactly 11 unique canonical paths, complete status, expected VM identity, and volume provenance. |
| Requester and mailbox | PASS | The current non-administrator identity matched the requester bound to the existing mailbox. The actual baseline reader accepted the Administrator-owned, DACL-protected, four-ACE mailbox. No raw SDDL or requester SID is included here. |
| `C:\` root DACL | PASS | Read-only Windows PowerShell 5.1 inspection found a protected, non-reparse root owned by TrustedInstaller. The single effective Authenticated Users write-related grant is mask `0x00000004`, flags `None`. The production parent checker now accepts only that exact root ACE plus the exact observed inherit-only root ACE described below. |
| `C:\Program Files` parent | PASS | DACL protected, owned by TrustedInstaller, not a reparse point. The production parent checker passed this live parent chain. Ordinary-user effective permissions are read/execute; inherit-only ACEs do not apply to this parent. |
| `C:\ProgramData` parent | PASS | DACL protected, owned by SYSTEM, not a reparse point. Its one BUILTIN Users create/attribute grant is exactly `0x00000116` with `ContainerInherit`; no delete, delete-child, WRITE_DAC, or WRITE_OWNER bits are present. The production parent checker passed this live parent chain. |
| Path aliases and reparse points | PASS | Read-only ancestor checks passed for the source package directory, retained mailbox, and both installation parent chains. Parent ACL validation also rejected unprotected DACLs. The installer checks every destination ancestor again immediately before staging and after publication. |
| Final destination and staging collisions | PASS | `C:\Program Files\F2-G1-Icacls` and `C:\ProgramData\F2-G1-Icacls` were absent. No `.F2-G1-Icacls-stage-*` entries existed under either parent. Synthetic package and release collisions preserve existing content and fail closed. |
| Runtime prerequisites checkable without elevation | PASS | Windows PowerShell `5.1.22621.6133`, the pinned SourceRoot, input files, pin manifest, and baseline are readable under the current standard token. Current token is not an Administrator token. |
| Administrator UAC identity and consent | UNKNOWN / NOT RUN | No UAC prompt or elevated process was started. Installer code still requires an Administrator token and compares that token’s requester identity to the exact mailbox requester; mismatch fails before staging. Human consent is required later. |
| Publication and post-install attestation paths | PASS (synthetic) | Tests exercise create-new staging, both destination collisions, a release-stage creation failure, installed package ACL attestation failure, manifest ACL attestation failure, and the structured no-success/partial-state result. No protected destination was created on the host. |
| Independent review and owner authorization | PENDING | The changed bytes require exact-SHA independent review. The previous installation authorization does not cover these bytes; request fresh owner authorization only after independent review accepts them. |

## C:\ root ACL analysis

No raw SDDL or SID is published. The live root ACEs were parsed in memory and reduced to principal classes, unsigned masks, and flags:

| Principal class | Type and mask | Flags | Meaning at `C:\` | Assessment |
| --- | --- | --- | --- | --- |
| Authenticated Users | Allow `0x00000004` | None | On a directory, `FILE_ADD_SUBDIRECTORY`; effective on the root but grants no right to add files, delete children, delete the root, change its DACL, or take ownership. | ACCEPTABLE only under the exact `C:\` rule. |
| Authenticated Users | Allow `0xE0010000` | ObjectInherit, ContainerInherit, InheritOnly | Not effective on the root. It can be inherited by an unprotected child, so child DACL protection is material. | ACCEPTABLE only as the exact observed root ACE. The target parents are both DACL-protected, and new staging directories are created with protected DACLs. |
| SYSTEM and Administrators | Allow `0x001F01FF` | ObjectInherit, ContainerInherit | Full control for trusted system administrators. | ACCEPTABLE. |
| BUILTIN Users | Allow `0x001200A9` | ObjectInherit, ContainerInherit | Read/execute. | ACCEPTABLE. |
| Unresolved Windows capability-style principal | Allow `0x001000A1` | None | Read/traverse/attribute synchronization rights; no write, delete, or ACL-control bit. | UNKNOWN identity; mask is read-only and does not enable installation-path modification. |

Microsoft defines directory mask `0x4` as `FILE_ADD_SUBDIRECTORY` and distinguishes it from `FILE_ADD_FILE` (`0x2`) and `FILE_DELETE_CHILD` (`0x40`). See [Microsoft Learn: Directory Access Mask](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-smb2/0a5934b1-80f1-4da0-b1bf-5e021c309b71) and [Microsoft Learn: Access Mask](https://learn.microsoft.com/en-us/windows-hardware/drivers/ifs/access-mask).

The `0x00000004` ACE itself has no inheritance flags, so that create-subdirectory grant does not flow to children. The separate `0xE0010000` ACE is inherit-only and is treated as a real inheritance risk: the source validator requires its exact observed mask, principal class, and flags, exactly once. It also requires the root and each immediate destination parent to have protected DACLs. Program Files and ProgramData both passed the live protected-DACL check. Every new package, release, staging directory and installed file is assigned and checked against its own protected DACL before use/publication.

ProgramData separately allows BUILTIN Users mask `0x116` with `ContainerInherit`. Its component bits are file creation, subdirectory creation, extended-attribute write, and attribute write. This allows name pre-creation/denial of service in ProgramData, but does not grant delete, DELETE_CHILD, WRITE_DAC, or WRITE_OWNER. Final-directory and random staging-name collisions fail closed without overwriting content. The ProgramData exception requires exactly one ACE with the observed mask and exact `ContainerInherit` flag; the same mask with different flags or duplicates fails closed.

Program Files and ProgramData each contain other unresolved inherit-only broad ACEs. Those ACEs do not apply to the parent objects. The intended child directories are created with protected DACLs, immediately verified before files are written, and verified again before/after publication. The synthetic failure tests exercise that exact DACL verification path. No token-specific Authz/AccessCheck computation was run; the live review classified raw ACE masks and flags and verified the current standard token is not an Administrator token.

## Minimal source correction

`Test-F2InstallParentChain` enables the new exception only when its current canonical path is exactly `C:\` and exactly the drive root. No exception is enabled for Program Files or ProgramData. `Test-F2InstallSafeParentSddl` requires an allowed owner, a present and protected DACL, exactly one non-inheritable Authenticated Users `0x4` ACE, and exactly one observed inherit-only Authenticated Users `0xE0010000` ACE with the observed flags. Mixed/extra masks, duplicates, wrong principals, changed flags, unprotected DACLs, wrong owners, reparse points, delete rights, FILE_ADD_FILE, WRITE_DAC, WRITE_OWNER, GENERIC_ALL, and untrusted inherited write ACEs fail closed.

The preexisting ProgramData create-mask exception is also tied to the exact observed `0x116`/ContainerInherit ACE and rejects duplicates. The installer now returns a fixed uppercase internal failure code when available; non-code exception text is replaced with `INSTALL_OPERATION_FAILED`, avoiding path or exception-detail disclosure.

## Source and executable hashes

| File | SHA-256 of exact published bytes |
| --- | --- |
| `Install-F2IcaclsProtectedPackage.ps1` | `be622923a5931a1cc1ce8cfff18c72952b836f8f84e403a419254c6c2c778b0e` |
| `Invoke-F2VerifiedInstaller.ps1` | `3ae8fee4cfa7c809110a3233f9df2ad8f1fe877c91f1a4067e08541c5e893060` |
| `Test-Install-F2IcaclsProtectedPackage.ps1` | `e8aaa2d926c4d7c80518d0c98d1a13092b7345594407d4f3d991127081d79588` |
| `F2_ICACLS_SOURCE_PINS.json` (production package) | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` |

No production package source or package pin changed. The installer’s production source commit remains `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`; the new SHA propagation is limited to the installer hash in the bootstrap and the bootstrap hash in the documented command.

The local preparation copies still match the *previous* reviewed bytes (`ca4d5a213615b1ce74d8fc7df17e7bb65ccfbcacd9dd7de2c9a6c36d42842d2d` installer and `cf480bf047f9d38e21e11e75cd4f30ddd487bbb4af6c9474464b7596e675baf5` bootstrap). They were not replaced before independent review. After review accepts this release, a fresh owner authorization is required; then replace only those known prior preparation files with the accepted exact bytes, verify the new hashes, and run the documented one-consent command. No installation is ready until that post-review staging and fresh authorization gate pass.

## Validation and limits

Fresh Windows PowerShell 5.1 synthetic suites passed with zero failures:

- Protocol: 152 assertions.
- Corroboration: 118 assertions.
- Runtime: 35 assertions.
- Protected installer/bootstrap: 47 assertions.
- Total: 352 assertions, zero failures.
- Parser sweep: 12 PowerShell files, zero errors.
- `git diff --check`: recorded in the final handoff after publication.
- Hosted runs `38167667264`, `38167926562`, and `38168148807` exposed three test fixture portability issues: the runner has no G: PowerShell drive, strict target-path validation needs explicitly canonical fixture destinations, and the reparse test callback must capture the immutable target path rather than a mutable fixture object. Corrections remain in synthetic setup/tests; production G: identity, canonical-path rejection and reparse checks were not relaxed. Exact failed runs: [38167667264](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38167667264), [38167926562](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38167926562), [38168148807](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38168148807). Final-head CI result will be recorded after rerun.

Complete stdout logs and exact commands are in the adjacent `WINDOWS_POWERSHELL_5_1_*_CONSOLIDATED.log` files. These are synthetic/source-only tests. They do not establish the elevated UAC identity, consent, post-install ACLs, or a protected installation result.

No UAC/elevation, protected installation, `icacls`, VM/Hyper-V query or operation, G: operation, ACL change, baseline rewrite, native workload, or PR merge was performed. PR #53 remains draft; PR #50 and its seven package files remain unchanged.
