# Review package manifest

Branch: `fix/f2-baseline-capture-identity-issue48`. Base: PR #50 source `2c967661163fc157b638fa4f76da86c48aa57ff2`. Production source tip: `54b1d0c7a9865d710c19b59cd38c0da670a12536`.

Every listed file is committed in this review package. Hashes are raw SHA-256 of exact committed bytes. `REVIEW_MANIFEST.md` is self-excluded; its exact digest is supplied in the PR description and final handoff.

| File | SHA-256 | Purpose |
| --- | --- | --- |
| `scripts/f2-acl/F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` | Consumer baseline loader; mailbox and payload identities are independently pinned |
| `scripts/f2-acl/F2AclIcacls.Runtime.psm1` | `eecec7b86a4bfee7773e73b537ed74ae573ff3d5bfaaa44b9d1bc42c4e1953a7` | Runtime release-manifest v2 identity validation and caller wiring |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `cee4322fdc4603cdebeccfe3411303a0ea92db946aa920b8ad60cb3152cae3c5` | Six source-package hashes; seventh package member |
| `scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1` | `8e744aad65e0f43326572f86564dbea0a6452e525fee62ef7c35cdd80a8fcc8a` | Synthetic distinct-ID, wrong-ID, tamper, missing, malformed and duplicate baseline regressions |
| `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | `eb061012ff4e6b522deb29fd4ff6a468c4f9701e7364bc51d0d6b327b1ff197e` | Synthetic runtime release contract and legacy schema rejection |
| `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1` | `235aea7748c2c67b6c52996d5de4dd02a88709b46b96fff1710bd671b4fac0e4` | Protected installer baseline preflight and v2 release manifest |
| `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1` | `a466e347843d74e5474021a852e886aceb9e4e8b4d3c71c6db4857d861d92e82` | One-read hash-verified bootstrap executing the verified bytes |
| `docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1` | `796dc3fb7d392dc68ed9fd0453a260eee310a8372dce5590d50145f07efab694` | Windows PowerShell 5.1 synthetic installer regressions |
| `docs/reviews/f2-g1-capture-id-contract/F2_G1_INSTALL_REVIEW_UPDATE.md` | `8ba0048358bc1ffc47297f9108c46bc0a12447ebdb8c65c1dc9ca00c62b91950` | Installation handoff, exact future command, pins, limitations |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_CORROBORATION_TEST.log` | `371e7904d1624eb2ffc26936d44cbb2e318e89dc76df37f210476dc8dd36ff8c` | Complete synthetic suite output and process exit |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_RUNTIME_TEST.log` | `48366e1a4a9937add53d4974a92459851a93697cbd81c0b0f25792a796f27e20` | Complete synthetic suite output and process exit |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_INSTALL_TEST.log` | `93e162e02ffcad24365284bcc1ddcad28f6598f4daa7c626ba1521b9f886d0e8` | Complete synthetic suite output and process exit |
| `docs/reviews/f2-g1-capture-id-contract/WINDOWS_POWERSHELL_5_1_PARSER.log` | `6fb0fd66129fad4f2ecc4edeb4d0fa7c3b3268bad3acd32303d4d2488089f4bc` | Parser sweep summary |
| `docs/reviews/f2-g1-capture-id-contract/TEST_EVIDENCE.md` | `5eb7b79bbc666e2aa7914cd9039c6123026ab942ed0320a57ad98048fd00181c` | Exact validation commands and result summary |
| `docs/reviews/f2-g1-capture-id-contract/HANDOFF.md` | `53a80b9e0f3a934e7f1420b445a34511acff23ef338f8e64538a305ee14a6af0` | Developer handoff and limits |
