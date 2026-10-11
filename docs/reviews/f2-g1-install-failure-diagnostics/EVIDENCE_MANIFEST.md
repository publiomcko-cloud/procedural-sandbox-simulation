# PR #54 F2 G1 failure diagnosis and diagnostic-correction evidence

The original forensic evidence remains at base `56b4e3c0132436a4b2c918572078fe4d687fb25c`, whose parent is `bd14a1908085065f08d3c62e4dd17fa3203a53ff`. This commit adds the bounded source correction and complete validation package. Current file hashes below are SHA-256 over Windows checkout bytes in this worktree. Git normalizes/rehydrates line endings according to `.gitattributes`; CI runs the corresponding Windows checkout.

## Current correction package

| File | SHA-256 | Purpose |
|---|---|---|
| `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1` | `6f47d802a2cd5d7deb65083c546829de6a71d26356dcf2b71f6cc6f14d81a4a9` | Production bootstrap argument guard, verified in-memory installer execution, sanitized diagnostic producer. |
| `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1` | `cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118` | Reviewed installer; seven-file production package and source pins unchanged. |
| `docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1` | `75cc1c252183f24cf0ca96a1677bc52c028c3d9d5bc1ab95d6fbac84057f8080` | Windows PowerShell 5.1 installer/bootstrap behavior regressions. |
| `docs/reviews/f2-g1-install-failure-diagnostics/Start-F2VerifiedInstall.ps1` | `a27c315b196c1179eb10fba80867829aeac2b333e07415cc13a1326c0c3ad38d` | Standard-token launcher, exact bootstrap/installer pins, one normal UAC request, requester-owned mailbox, actual child exit. |
| `docs/reviews/f2-g1-install-failure-diagnostics/Test-F2InstallDiagnosticTransport.ps1` | `729b4f1e4b7ed4e700777908cbda93fedbf836a51cb861cadb6c664ce081889c` | 38 synthetic PowerShell 5.1 diagnostic transport and failure-path assertions, with sanitized file-DACL failure trace. |
| `docs/reviews/f2-g1-install-failure-diagnostics/F2_G1_DIAGNOSTIC_INSTALL_REVIEW_UPDATE.md` | `a8d624677d574c8d8cb8f0836571524593a9af9d9a366a4c258c6112a175b0b5` | Complete implementation explanation, security boundaries, exact future invocation, test totals, and elevated-only unknowns. |
| `docs/reviews/f2-g1-install-failure-diagnostics/validation.log` | `7f65d7ae94ba2d29d7c27b5803633be254f49f3f86da3a7899664a860510a600` | Five-suite commands/results/exits, sanitized hosted failure diagnosis, parser result, and local diff-check result. |
| `.github/workflows/f2-acl-source-only.yml` | `7edb3f3bd4a21fa5b12d0c7bf214fd4fef6f750c584fa768f300eb1fdcb91b28` | Windows CI coverage for all five suites, parser sweep and diff check. |

## Unchanged provenance/supporting files

| File | SHA-256 | Purpose |
|---|---|---|
| `docs/reviews/f2-g1-install-failure-diagnostics/F2_G1_FAILURE_DIAGNOSTICS_REPORT.md` | `a4df796cdee1ea5578cb03cb4ea5fe7470b69255c508262e2ed144cb237fb2af` | Historical sanitized failure forensics; unchanged from the forensic base. |
| `docs/reviews/f2-g1-install-failure-diagnostics/.gitattributes` | `6a300ad66ba8cbb277820fcda72397f9d31bd528077347fc07b0eaa97684777f` | Review subtree checkout line-ending rules; unchanged. |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` | Existing seven-file production source pin manifest; unchanged. |

The SHA-256 of this manifest itself is intentionally not embedded in itself; it is provided in the final PR handoff and can be recomputed from the immutable commit. All listed current source, tests and reports are present in the same commit. No raw event XML, baseline content, SDDL, private SID, credentials or host security evidence is included.

## Validation evidence

- Windows PowerShell 5.1.22621.6133: five suites, 390 assertions, zero final failures, every child exit code 0. Per-suite results and exact commands are in `validation.log`.
- PowerShell parser: 14 `.ps1`/`.psm1` files, zero parse errors, exit 0.
- `git diff --check`: exit 0 locally; final commit check and GitHub workflow result are reported in the PR conversation handoff.
- GitHub Windows CI runs this same five-suite and parser workflow for the final PR commit. The exact workflow run URL/result is added to the PR conversation after completion.

No UAC, installation, live `icacls`, VM/Hyper-V/G:, ACL modification, native workload, or PR merge occurred. The diagnostic path still requires independent source review and a fresh owner authorization before any use that could request UAC.
