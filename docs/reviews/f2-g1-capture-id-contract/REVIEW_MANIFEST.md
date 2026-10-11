# Consolidated F2 G1 review manifest

Repository: `publiomcko-cloud/procedural-sandbox-simulation`. Draft PR #53 branch `fix/f2-baseline-capture-identity-issue48`, based on PR #50 production source. This manifest inventories all files changed in PR #53 at the final reviewed tip, except itself; its own raw SHA-256 is published in the PR handoff comment. Hashes below are SHA-256 over exact GitHub file bytes. Review scripts use LF bytes in GitHub; Windows checked-out package files follow the repository's line-ending rules.

## Changed review/source files and evidence

| File | SHA-256 | Purpose |
| --- | --- | --- |
| `.gitattributes` | `a7718781bfc3e84e35321e8a7d73c34d8264303b1591d793a849fa80e30698a7` | Keeps test logs byte-preserved. |
| `.github/workflows/f2-acl-source-only.yml` | `7b96771c28f1b85f5db1c163bd1449727d08265a5deab76a67f0e995b6028a14` | Adds review-path triggering and PS 5.1 installer regression execution. |
| `docs/reviews/f2-g1-capture-id-contract/CONSOLIDATED_INSTALL_READINESS.md` | `60c0d40e6044c668ec6246018b7b46fffb4c9aa72c8b53c028ac2e769b3a8059` | Complete gate matrix and sanitized root ACL assessment. |
| `docs/reviews/f2-g1-capture-id-contract/F2_G1_INSTALL_REVIEW_UPDATE.md` | `4bfb84d74afb0c43d390b4c6876acc2e3074db68b87994fffd165afdec1a203b` | Exact post-review installation preparation/command and boundaries. |
| `docs/reviews/f2-g1-capture-id-contract/HANDOFF.md` | `91d9dd8d9f655e02fff9ff66dba419518eda690c9744a01f0c718f4b0a4e8de6` | Developer handoff, implementation scope, limits and reviewer focus. |
| `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1` | `be622923a5931a1cc1ce8cfff18c72952b836f8f84e403a419254c6c2c778b0e` | Protected installer with exact `C:\`-only parent ACL exception and PSDrive-independent path strings. |
| `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1` | `3ae8fee4cfa7c809110a3233f9df2ad8f1fe877c91f1a4067e08541c5e893060` | One-read hash-bound bootstrap that executes the verified in-memory installer bytes. |
| `docs/reviews/f2-g1-capture-id-contract/TEST_EVIDENCE.md` | `9af25a649d20f5358eb929bd2d982171b914e510e9519906c34c3570cecad3bb` | Exact local commands, assertion results, logs and hosted CI reference. |
| `docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1` | `96e8af5f3eba2733e35ac3f4ab722a8b83e16c64a1feb2fd7fc87ac55bace053` | Windows PowerShell 5.1 installer/bootstrap synthetic regressions. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_CONSOLIDATED_PARSER.log` | `bf78636077f0fa87a92af36cb84d1668cc88c166440b6814e23da172fe4b59eb` | Fresh exact local parser command, file/error counts and exit. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_CORROBORATION_CONSOLIDATED.log` | `75a583004a8a929f1969cc0fd1fb0307ea9ef89683fa70aa89750eab0f11346a` | Fresh 118-assertion Windows PowerShell 5.1 corroboration output. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_CORROBORATION_TEST.log` | `c631f9353e41d6ef1b53579de3cd2ded6418d916a2145fdbbc95a60cebc632c7` | Earlier complete corroboration run evidence. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_CORROBORATION_TRANSIENT_FAILURE.log` | `787ba98ba009da7330e709e3f39350245d2bb3b88e74a6dfa7e3dbc14cad7ef3` | Preserves an earlier transient synthetic child-process assertion failure and unchanged rerun. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_INSTALL_CONSOLIDATED.log` | `7116e1d8d1db24342a101b7d892d2d47bbe83c52fab0fefffc2dc5edfd5661a9` | Fresh 47-assertion installer/bootstrap output. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_INSTALL_TEST.log` | `a2ea6ea7d805d9330e2e7c991b87b5196c81824f3ea1d23ba08fca35d15c2f81` | Earlier installer test output. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_PARSER.log` | `cfca2700023f58d5f765e9351d8f3a971c7e004b5cf98e98b736478391a09633` | Earlier local parser result. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_PROTOCOL_CONSOLIDATED.log` | `c58f91083a47ce166f8066c302e318ce4bfdb63389835525dec6c5feea6a5c55` | Fresh 152-assertion protocol output. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_PROTOCOL_TEST.log` | `6c1f9bf830939755a19eb077d000364bfca9c5ae0ac21421d60fb216f956450b` | Earlier protocol test output. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_RUNTIME_CONSOLIDATED.log` | `cc03bf5621595fb3888d7183668defcf224da03152c30fee2d4bd930604d3247` | Fresh 35-assertion runtime output. |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_RUNTIME_TEST.log` | `94b3554526963b7755b1ad32cafbb27a87ddfedc8df8ba918beab7fa179e2664` | Earlier runtime test output. |
| `scripts/f2-acl/F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` | Retained baseline loader and icacls comparison module. |
| `scripts/f2-acl/F2AclIcacls.Runtime.psm1` | `950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5` | Runtime v2 release-manifest loader and package contract. |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` | Pinned source-package manifest. |
| `scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1` | `8e744aad65e0f43326572f86564dbea0a6452e525fee62ef7c35cdd80a8fcc8a` | Synthetic corroboration and production-boundary integration tests. |
| `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | `f9ac3762a8e310f67490a4a441437e3e881178cb1876867985ce032bd08eeb7f` | Real disk-loader v2 and runtime contract tests. |

There are 26 changed paths including this manifest. Its own SHA-256 is intentionally self-excluded; the exact value is reported in the PR comment after the containing commit exists.

## Seven-file production package pins

The installer reads the following seven exact SourceRoot files. Windows PowerShell 5.1 package validation passed against checkout bytes at source commit `5741ffe90a3abd02a08563e6431e8a0a9b63eeb1`; source-pin manifest SHA-256 is `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7`.

| Package file | Windows checkout SHA-256 |
| --- | --- |
| `scripts/f2-acl/F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `scripts/f2-acl/F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `scripts/f2-acl/F2AclIcacls.Runtime.psm1` | `950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5` |
| `scripts/f2-acl/Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` |
| `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` |
| `scripts/f2-acl/Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

Review evidence is sanitized; it contains no retained raw ACL/SDDL, private requester SID, capability SID, credential, or baseline payload bytes.
