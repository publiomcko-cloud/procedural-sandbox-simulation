# Review package manifest

Branch: `fix/f2-baseline-capture-identity-issue48`. Base: reviewed PR #50 source `2c967661163fc157b638fa4f76da86c48aa57ff2`. Production source tip: `54b1d0c7a9865d710c19b59cd38c0da670a12536`.

Every listed file is committed in this review package. Hashes are raw SHA-256 of exact file bytes. Test logs are LF-normalized for text diff checks, with every output line and exit status preserved. `REVIEW_MANIFEST.md` is self-excluded; its exact digest is supplied in the PR description and final handoff.

| File | SHA-256 | Purpose |
| --- | --- | --- |
| `.gitattributes` | `a7718781bfc3e84e35321e8a7d73c34d8264303b1591d793a849fa80e30698a7` | Preserves exact bytes of published validation logs |
| `scripts/f2-acl/F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` | Consumer baseline loader; mailbox and payload identities are independently pinned |
| `scripts/f2-acl/F2AclIcacls.Runtime.psm1` | `eecec7b86a4bfee7773e73b537ed74ae573ff3d5bfaaa44b9d1bc42c4e1953a7` | Runtime release-manifest v2 identity validation and caller wiring |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `cee4322fdc4603cdebeccfe3411303a0ea92db946aa920b8ad60cb3152cae3c5` | Six source-package hashes; seventh package member |
| `scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1` | `8e744aad65e0f43326572f86564dbea0a6452e525fee62ef7c35cdd80a8fcc8a` | Synthetic distinct-ID, wrong-ID, tamper, missing, malformed and duplicate baseline regressions |
| `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | `eb061012ff4e6b522deb29fd4ff6a468c4f9701e7364bc51d0d6b327b1ff197e` | Synthetic runtime release contract and legacy schema rejection |
| `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1` | `235aea7748c2c67b6c52996d5de4dd02a88709b46b96fff1710bd671b4fac0e4` | Protected installer baseline preflight and v2 release manifest |
| `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1` | `a466e347843d74e5474021a852e886aceb9e4e8b4d3c71c6db4857d861d92e82` | One-read hash-verified bootstrap executing the verified bytes |
| `docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1` | `796dc3fb7d392dc68ed9fd0453a260eee310a8372dce5590d50145f07efab694` | Windows PowerShell 5.1 synthetic installer regressions |
| `docs/reviews/f2-g1-capture-id-contract/F2_G1_INSTALL_REVIEW_UPDATE.md` | `3e6be2c72aff616bd1a8102787805dc3f4016550bde83e1d0633f142644c0a59` | Installation handoff, exact future command, pins, limitations |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_CORROBORATION_TEST.log` | `1808478eddd3bfe7a8908ac8cac6b4448323aa08a8d7adbc8f8099125058c898` | Complete synthetic suite output and process exit |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_RUNTIME_TEST.log` | `35fb74fdee9b31ae60bfd80f930cfb886127c3ebe35dc1a17132d5297b888a87` | Complete synthetic suite output and process exit |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_INSTALL_TEST.log` | `e519a087a0e5dbf0bd25e4a38b46c42f9f931b1358fc7567f96d86e9193525c9` | Complete synthetic suite output and process exit |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_PARSER.log` | `d6fc1c8535fd8ea38c2b3e8662644581a238ba695e6796e583b3f6af9977e48c` | Parser sweep summary |
| `docs/reviews/f2-g1-capture-id-contract/TEST_EVIDENCE.md` | `e70e84f947136a550b6c4bebf574b6064d94c1d5ccd01f3c1e5571f0e67c86ec` | Exact commands and local/hosted validation results |
| `docs/reviews/f2-g1-capture-id-contract/HANDOFF.md` | `8b737de72f76b30fcd28c18338dc84f36d0912d08eaf9d42680d9fcc753bdbf2` | Developer handoff and limits |