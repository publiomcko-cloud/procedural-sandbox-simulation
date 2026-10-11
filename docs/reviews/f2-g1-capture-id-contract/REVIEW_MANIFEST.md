# Review package manifest

PR #53 branch: `fix/f2-baseline-capture-identity-issue48`. Base: PR #50 source commit `2c967661163fc157b638fa4f76da86c48aa57ff2` (unchanged). Production source commit: `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, parent `4c53f6dd03c6ddc564a45f8c203286595385c46b`.

This manifest covers every PR #53 changed path and the supporting seven-file package. SHA-256 values are raw file bytes; the final report and PR body publish the manifest's own SHA-256 because the manifest is self-excluded. GitHub retrievability is verified at the final review HEAD.

| File | SHA-256 | Purpose |
| --- | --- | --- |
| `.gitattributes` | `42416703328589db506d1446f480db64fec7f24d3f79d267cd48c9527122edc5` | Preserves published test log bytes |
| `docs/reviews/f2-g1-capture-id-contract/F2_G1_INSTALL_REVIEW_UPDATE.md` | `d7a5b067107a99201a0fed18a24abe3e308ff62c6116264e4f5b88e249d8b6e2` | Full installation command, pins and scope limits |
| `docs/reviews/f2-g1-capture-id-contract/HANDOFF.md` | `3517fafb9245a9064da4da0a22eeeacda6395769ca02f3d017d31a8d52b157f6` | Developer handoff |
| `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1` | `ca4d5a213615b1ce74d8fc7df17e7bb65ccfbcacd9dd7de2c9a6c36d42842d2d` | Seven-file protected installer and v2 release manifest producer |
| `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1` | `cf480bf047f9d38e21e11e75cd4f30ddd487bbb4af6c9474464b7596e675baf5` | One-read verified-byte UAC bootstrap |
| `docs/reviews/f2-g1-capture-id-contract/TEST_EVIDENCE.md` | `b627dcf224adbd656c904b249178a41d4ee9cc73c3473d72a53ebcfe51f015dd` | Exact local commands and validation evidence |
| `docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1` | `67851441b9196d6b95338a2a704363157b27d3a73e0afd8d0e2345b8030ae3ee` | Windows PowerShell 5.1 installer tests |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_CORROBORATION_TEST.log` | `c631f9353e41d6ef1b53579de3cd2ded6418d916a2145fdbbc95a60cebc632c7` | Complete successful 118-assertion output |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_CORROBORATION_TRANSIENT_FAILURE.log` | `787ba98ba009da7330e709e3f39350245d2bb3b88e74a6dfa7e3dbc14cad7ef3` | Initial failed assertion and unchanged successful rerun record |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_INSTALL_TEST.log` | `a2ea6ea7d805d9330e2e7c991b87b5196c81824f3ea1d23ba08fca35d15c2f81` | Complete 31-assertion installer output |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_PARSER.log` | `d6fc1c8535fd8ea38c2b3e8662644581a238ba695e6796e583b3f6af9977e48c` | PowerShell parser sweep output |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_PROTOCOL_TEST.log` | `6c1f9bf830939755a19eb077d000364bfca9c5ae0ac21421d60fb216f956450b` | Complete 152-assertion protocol output |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_RUNTIME_TEST.log` | `94b3554526963b7755b1ad32cafbb27a87ddfedc8df8ba918beab7fa179e2664` | Complete 35-assertion runtime output |
| `scripts/f2-acl/F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` | Protocol package module |
| `scripts/f2-acl/F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` | Baseline loader and corroboration implementation |
| `scripts/f2-acl/F2AclIcacls.Runtime.psm1` | `950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5` | Runtime release-manifest v2 loader and contract |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` | Seven-file package pin manifest |
| `scripts/f2-acl/Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` | Read-only capture entrypoint |
| `scripts/f2-acl/Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` | Host launcher |
| `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` | Protected elevated coordinator |
| `scripts/f2-acl/Test-F2AclCapture.Protocol.ps1` | `0556e15a9b3cdfee625dc762a7087b8e96a4ce0dddde1a23213fa6da64a6666f` | Protocol synthetic tests |
| `scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1` | `84d0194707ae9497f20c112973b028d2e9907b8e923f0cea11e7a7fe662250aa` | Corroboration synthetic tests |
| `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | `f9ac3762a8e310f67490a4a441437e3e881178cb1876867985ce032bd08eeb7f` | Disk-loader v2 regression tests |

`TEST_EVIDENCE.md` identifies the exact Windows Actions run when available. Review artifacts contain no protected live ACL/SDDL evidence.
