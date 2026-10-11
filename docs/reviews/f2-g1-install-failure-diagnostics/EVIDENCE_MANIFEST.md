# Review evidence manifest

Immutable source base: `bd14a1908085065f08d3c62e4dd17fa3203a53ff`

Production source: `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`

Parent of this review-only evidence branch: `bd14a1908085065f08d3c62e4dd17fa3203a53ff`

SHA-256 values below were computed over staged Git blob bytes and matched the worktree bytes. Source scripts are linked at the immutable base commit in the report.

| File | SHA-256 | Purpose |
|---|---|---|
| `F2_G1_FAILURE_DIAGNOSTICS_REPORT.md` | `a4df796cdee1ea5578cb03cb4ea5fe7470b69255c508262e2ed144cb237fb2af` | Sanitized event findings, source exit-path matrix, diagnosis, and narrowly scoped future correction design. |
| `Test-F2InstallDiagnosticTransport.ps1` | `d9a905b2636987cfd5f274d486513493808c2f2b83721508fe6ddc48826fb6c2` | Windows PowerShell 5.1 synthetic root-cause and diagnostic transport tests. |
| `validation.log` | `3f1e05ee9c817ec9ae3c6b90a15989e3bb09c243f8b02e0c9726e3fd8a218eab` | Exact test assertions/results and sanitized requester-side event record references. |
| `.gitattributes` | `6a300ad66ba8cbb277820fcda72397f9d31bd528077347fc07b0eaa97684777f` | LF checkout rules so published text-byte hashes reproduce on Windows. |

The parent commit contains the complete reviewed production bootstrap and installer at:

- `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1` (SHA-256 `3ae8fee4cfa7c809110a3233f9df2ad8f1fe877c91f1a4067e08541c5e893060`).
- `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1` (SHA-256 `be622923a5931a1cc1ce8cfff18c72952b836f8f84e403a419254c6c2c778b0e`).

No raw event XML, SDDL, private SID, credential, baseline payload, or installation output is published. No production source was changed. CI was not run for this review-only evidence package; the documented test was run on Windows PowerShell 5.1.22621.6133 with 20 assertions and zero failures.
