# Review package manifest

Branch: `fix/f2-baseline-capture-identity-issue48`. Base: reviewed PR #50 source `2c967661163fc157b638fa4f76da86c48aa57ff2`. Production source tip: `54b1d0c7a9865d710c19b59cd38c0da670a12536`.

SHA-256 values below were computed from the exact GitHub API content bytes at review commit `b596d8d0dcb3e313101df547e97368a3678f634e`. `REVIEW_MANIFEST.md` is self-excluded; its exact digest is published in the PR description and final report.

| File | SHA-256 | Purpose |
| --- | --- | --- |
| `.gitattributes` | `42416703328589db506d1446f480db64fec7f24d3f79d267cd48c9527122edc5` | Preserves exact bytes of published validation logs |
| `docs/reviews/f2-g1-capture-id-contract/F2_G1_INSTALL_REVIEW_UPDATE.md` | `50b11bd31d4d1ec80f49bafe5edd69304b4448f5a4d79bd92894fa4a49ab4ee8` | Installation handoff, safe command, hashes and limits |
| `docs/reviews/f2-g1-capture-id-contract/HANDOFF.md` | `e2747ce5c23b4297cbdbae2177b8b53cd38266e92c26e21ccd6219fa0030b415` | Developer handoff and limitations |
| `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1` | `235aea7748c2c67b6c52996d5de4dd02a88709b46b96fff1710bd671b4fac0e4` | Protected installer baseline preflight and v2 release manifest |
| `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1` | `a466e347843d74e5474021a852e886aceb9e4e8b4d3c71c6db4857d861d92e82` | One-read hash-verified bootstrap |
| `docs/reviews/f2-g1-capture-id-contract/TEST_EVIDENCE.md` | `c1072e662d977472b9938f0d171e910e6b784bcf56125b130949214a592a8e94` | Exact commands and local/hosted validation results |
| `docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1` | `796dc3fb7d392dc68ed9fd0453a260eee310a8372dce5590d50145f07efab694` | Windows PowerShell 5.1 synthetic installer tests |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_CORROBORATION_TEST.log` | `1808478eddd3bfe7a8908ac8cac6b4448323aa08a8d7adbc8f8099125058c898` | Complete local synthetic output and exit |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_INSTALL_TEST.log` | `e519a087a0e5dbf0bd25e4a38b46c42f9f931b1358fc7567f96d86e9193525c9` | Complete local synthetic output and exit |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_PARSER.log` | `d6fc1c8535fd8ea38c2b3e8662644581a238ba695e6796e583b3f6af9977e48c` | Local parser sweep output |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_RUNTIME_TEST.log` | `35fb74fdee9b31ae60bfd80f930cfb886127c3ebe35dc1a17132d5297b888a87` | Complete local synthetic output and exit |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `cee4322fdc4603cdebeccfe3411303a0ea92db946aa920b8ad60cb3152cae3c5` | Six source-package hashes; seventh package member |
| `scripts/f2-acl/F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` | Consumer baseline loader; independently pinned mailbox and payload identities |
| `scripts/f2-acl/F2AclIcacls.Runtime.psm1` | `eecec7b86a4bfee7773e73b537ed74ae573ff3d5bfaaa44b9d1bc42c4e1953a7` | Runtime release-manifest v2 identity validation and caller wiring |
| `scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1` | `84d0194707ae9497f20c112973b028d2e9907b8e923f0cea11e7a7fe662250aa` | Synthetic distinct-ID and invalid baseline regressions |
| `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | `c7762dc2ba846d2563a2a385f0a8b72c8101d6d9ebd8b204ce908108877784f7` | Synthetic runtime release contract and legacy-schema regression |