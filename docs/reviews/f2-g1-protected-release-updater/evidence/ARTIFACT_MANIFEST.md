# Source and evidence SHA-256 manifest

This manifest covers the complete production source delta from base `0a4d98ecad4c50ba2f749e4fafe6d28e35794804` and review evidence files, except this manifest and `WINDOWS_CI.txt` (the latter is completed after the PR run). Hashes are SHA-256 over Git blob bytes after the repository's declared text normalization, except the explicitly identified Windows checkout hashes. Git commit/tree hashes bind all listed and excluded files in the immutable review commit.

## Production source at `0bda8f6437ad2ddb7ce24d3bf905a18f363df9df`

The following are Git-content SHA-256 values unless two forms are shown. Windows checkout SHA values are included where the hash-bound command executes the CRLF checkout bytes.

| Path | SHA-256 | Purpose |
|---|---|---|
| `.github/workflows/f2-acl-source-only.yml` | `ffdf12130af3b43b6149cfae813433c5ddb573991356c275bef31e433bfcbf84` | Windows PowerShell 5.1 source-only CI |
| `scripts/f2-acl/F2AclIcacls.Runtime.psm1` | `d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4` | v3 runtime validation and shared release lease |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` | Seven-file source pin manifest |
| `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1` | `9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515` | v3 installed coordinator and exact versioned path gate |
| `scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1` | Git content `4564d714c1e97ff8406265261226aac215446f7393d9e0a7e32a1777b09d366e`; Windows checkout `7f070a724caf7fce5cfc72ada39518e8f83701fe0667becfb27a8b6b4ceb49b8` | Elevated fail-closed updater |
| `scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1` | Git content `d5141345c4131673206b9679464a4e1e4ebf872fb42213015f32052e474b0f17`; Windows checkout `dc342139f4168e624d8554017a560c4c9243767847aaa411bdc6fb349693dfd3` | Hash-bound standard-token/UAC boundary |
| `scripts/f2-acl/Test-F2AclEntrypointArguments.ps1` | `c8e9a126d6124fe3067a7ee228eaa897d56b4c66853124aee10f72aca038690d` | PS5.1 entrypoint contract regressions |
| `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | `cb22431c813d6c1a09c8ca04e270c9b1f316e365990e32d9c751cd00d9f3e152` | Runtime manifest/installed-file/UAC gate regressions |
| `scripts/f2-acl/Test-F2AclProtectedReleaseUpdater.ps1` | Git content `1425a572649f4d3c605c330e4f2f724afa752354acbd66219877f9efadc6506c`; Windows checkout `9b64b853e9bf742bf6b1ec007bfd70d9f1cdfea5558da729d3d4d9d3631d78a0` | Updater synthetic, fault-injection and boundary tests |

Seven candidate package files:

| Path | SHA-256 |
|---|---|
| `scripts/f2-acl/F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `scripts/f2-acl/F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `scripts/f2-acl/F2AclIcacls.Runtime.psm1` | `d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4` |
| `scripts/f2-acl/Invoke-F2IcaclsCapture.ps1` | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1` | `9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515` |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |
| `scripts/f2-acl/Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

## Candidate manifest and review evidence

| Path | Raw SHA-256 | Purpose |
|---|---|---|
| `docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json` | `a86acf105b005c5a0a34e586ca7b068e421659891640861e5a4b3cadd8b1f888` | Exact external candidate manifest bytes |
| `evidence/WINDOWS_PS51_PROTOCOL.log` | `6c1f9bf830939755a19eb077d000364bfca9c5ae0ac21421d60fb216f956450b` | Complete protocol suite output |
| `evidence/WINDOWS_PS51_CORROBORATION.log` | `c631f9353e41d6ef1b53579de3cd2ded6418d916a2145fdbbc95a60cebc632c7` | Complete corroboration suite output |
| `evidence/WINDOWS_PS51_RUNTIME.log` | `ed707b9a1d45061005c4d3c15da64c307ae0117efda3d2f00f0e81864d807b18` | Complete runtime suite output |
| `evidence/WINDOWS_PS51_ENTRYPOINT.log` | `516b847cc7a22a88d764f63f1b5ec63b0c4744fcb0ebcec173fc662bd58d2376` | Complete entrypoint suite output |
| `evidence/WINDOWS_PS51_UPDATER.log` | `80662c4c4b12e2db1c1da6195d302555cbaccdc71cc5f05d897d7436d9674349` | Complete updater suite output |
| `evidence/POWERSHELL_PARSER.txt` | `14da4bfcc6d91ee6763ea89ba0e4344b025f5bedf9c645c0a1ec263b374aa22c` | Parser sweep result |
| `evidence/LOCAL_VALIDATION.txt` | `6e8702817a9a81692c07dc2416f28ab8ce42b3c1dd760ea55a94eb2529842f54` | Commands, assertion counts and local result summary |
| `evidence/GIT_DIFF_CHECK.txt` | `8fb5b6cd42886214786e7dedeb2e83dc566c6b5bf0df52b1f5f17ed27e723b3b` | Diff check result |
| `DEVELOPER_HANDOFF.md` | `ce6a486c4f7832875ca2fae2fb768f8e7b3aa11a6d2481c0a732fb67f4d4622e` | Required developer handoff |
| `F2_G1_PROTECTED_RELEASE_UPDATER_REVIEW.md` | `9942b479cf80f35521a8cbde1d3dc0b287bea6fdc0c4c7f55cd983d917e59b7d` | Full design, transaction, recovery and future command review |

GitHub CI evidence is recorded separately after the immutable PR head's run completes. No raw ACL/SDDL, private SID, credential or baseline payload was included.
