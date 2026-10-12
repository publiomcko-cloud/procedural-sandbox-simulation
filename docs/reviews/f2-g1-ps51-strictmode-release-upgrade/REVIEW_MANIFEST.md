# Immutable review package manifest

Production correction commit: `e5a66a7558c027e54b1510e7197d6e3a331cff19`
Production correction parent: `bd14a1908085065f08d3c62e4dd17fa3203a53ff`
Branch: `fix/f2-g1-ps51-entrypoint-release`

The GitHub raw-byte SHA-256 values below were recomputed from the contents API at the published review commit. Git blob object IDs are also shown to bind each file to the commit tree. Windows checkout SHA-256 values in `README.md` and the release manifest are separately identified; text files may have CRLF checkout bytes and LF GitHub blob bytes.

## Published changed paths and exact GitHub content

| Path | Purpose | Git blob ID | GitHub raw-byte SHA-256 |
|---|---|---|---|
| `.github/workflows/f2-acl-source-only.yml` | Windows PowerShell 5.1 tests and parser CI | `610729e2c02bbb7d60945e223f02457d02737caa` | `c12f41e8f6895528a1fe850c5056117eff69417fdeed306599ea9b5e7bc6ee06` |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | Refreshed launcher/coordinator pins | `e4345451fa7e9ae76c68ab62fbeaf41f395a9317` | `0caa7a421a190f11351abadb2f78e3569f1287a1b38f09d62932a0caa8c3b5bb` |
| `scripts/f2-acl/Invoke-F2IcaclsCapture.ps1` | StrictMode-safe launcher argument check | `1b7e345ee16f6100af0ddef02ab3e1816cf65791` | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1` | StrictMode-safe protected coordinator argument check | `4147eba94117a8355febeddcf26c2ff5199b8643` | `e965823752518edfcac7ed50bd49bf489f6d924fa404e41138266857ea41b624` |
| `scripts/f2-acl/Test-F2AclEntrypointArguments.ps1` | Inert PS 5.1 invocation regression test | `268166c87a1298bb7a2ce348d4d0a72820656aea` | `79c5622f1cb2283abc0892a57e94cec3fe1778d7abe3e1ba404f9e78fa1eb477` |
| `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | Runtime boundary assertions without production entrypoint execution | `2833f757792b0b7486a3cbcc825d98c60476bba3` | `d1e140f22bfdf2e024ca727e56423f865e8f7c876eac66683e1838095344caf7` |
| `docs/reviews/f2-g1-ps51-strictmode-release-upgrade/README.md` | Full handoff, evidence, release comparison, design and gates | `938692670ac80d5f2cf43314a0f3c5601b957164` | `499b15f1b14393c5b09abc8dd3b889c3ad47cfd4139e79d784ca93f0c5c3020f` |
| `docs/reviews/f2-g1-ps51-strictmode-release-upgrade/Test-CandidateReleaseManifest.ps1` | Reproducible actual module disk-loader/source validator | `1dc8411ebd4c70a5efbfba6d0d3b4e43f0907633` | `2fc6759733f9d48a91ff70675207acdf458908ef9702b2b3002be600b2337c3b` |
| `docs/reviews/f2-g1-ps51-strictmode-release-upgrade/Test-TrackedPowerShellParse.ps1` | Reproducible PS 5.1 parser sweep | `37a23652b27ac84614b45cffe0493012598c6101` | `61522bc13eb67c7b9fe8ea6e37b2a50f61b65ac1201eb6f4005b1d383ecda503` |
| `docs/reviews/f2-g1-ps51-strictmode-release-upgrade/approved-release-v2-candidate.json` | Candidate external release contract; not installed or trusted | `4e644322f2ad1fda78028a2ccffe17bb89fee510` | `8ef5920f3c3c3c789b0c9af7314843437dbb57741ad29f78d57beabb43050d96` |
| `docs/reviews/f2-g1-ps51-strictmode-release-upgrade/candidate-manifest-validation-ps51.log.txt` | Actual module disk-loader and seven-file source result | `275bf048c304376fff7b85849a3216fafc68ece9` | `645ca2610557307def68e3fe891b72628762c13a29ce34f3e3114a04aba50112` |
| `docs/reviews/f2-g1-ps51-strictmode-release-upgrade/legacy-create-only-installer-synthetic.log.txt` | Historical synthetic installer preflight failure | `95a8a35ae6f4213f02c7efb7af0b3a6400314f45` | `45638900e9bc665b609f82ce9e83a0989de9470a36c35caffc1c930e6d97aa45` |
| `docs/reviews/f2-g1-ps51-strictmode-release-upgrade/parser-ps51.log.txt` | Independent Windows PS 5.1 parser result | `71ab36f494170a5ec2c0a3e683a9558f45215dbc` | `e23bf40e9328f5a57ea315d992b71f73e3c59ba0951572f4c2665c058e3a6137` |
| `docs/reviews/f2-g1-ps51-strictmode-release-upgrade/validation-ps51.log.txt` | Full source-only suites and local diff-check output | `faba307e338c9e29a1a97dddd6ab2a3ab0417e42` | `5637f2fe9b3fb320e70b15b713c52a00aef1cc2cb96d018768e5b7c07d447ef8` |

This manifest does not include its own digest. Its exact Git blob ID and raw-byte SHA-256 are available from the same immutable commit. The candidate package's seven Windows-checkout hashes and unchanged baseline identities are listed in `README.md` and `approved-release-v2-candidate.json`.
