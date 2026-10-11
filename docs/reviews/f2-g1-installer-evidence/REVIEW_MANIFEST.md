# F2 G1 installer review package manifest

Publication-only package for Issue #48 review blocker `6108135458`.

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Parent/base commit: `2c967661163fc157b638fa4f76da86c48aa57ff2`
- Base branch (PR #50): `security/f2-icacls-corroboration-issue48`
- Review-only branch: `review/f2-g1-installer-evidence-issue48`
- All package paths are under `docs/reviews/f2-g1-installer-evidence/`.
- The original PR #50 production files are not modified by this package.

## Files, hashes, purposes, and dependencies

| File | SHA-256 | Purpose | Dependencies |
|---|---|---|---|
| `Invoke-F2VerifiedInstaller.ps1` | `5d6615dafc6608bb8777703eeb4909e796034f66eb2f2e16bc7f868cb885d965` | Elevated bootstrap; verifies the fixed installer digest and executes the verified byte snapshot. | Windows PowerShell 5.1; approved installer at `C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1`. |
| `Test-Install-F2IcaclsProtectedPackage.ps1` | `d061d63ec9cec756ca1d8f9dede335dcf92af329f202f572475abc0212a37b2b` | Synthetic installation/bootstrap regression suite; asserts the actual production installer path and digest. | Windows PowerShell 5.1; installer/bootstrap beside it; clean PR #50 checkout at the pinned commit for seven package fixtures; temporary directories only. |
| `Install-F2IcaclsProtectedPackage.ps1` | `a6a130edf307341032200b88b68f719fc8a3540830d09bb2d26631993524a5c8` | Reviewed, unchanged seven-file protected package installer. | Windows PowerShell 5.1; pinned PR #50 source; fixed baseline evidence paths and hashes; Windows filesystem/security APIs. |
| `F2_G1_PROTECTED_INSTALL_REVIEW.md` | `932ff653433dd03ca94e3e089602d895a6f1c0de2e067747055056aaa36ccaa0` | Original handoff preserved byte-for-byte for provenance. Its 17-assertion result and direct `-File` command are historical and superseded by the current update below. | None. |
| `F2_G1_INSTALL_REVIEW_UPDATE.md` | `2f8db35cc222411b6e6595f83968f8dd25f8283510e173ccd5a773584f592504` | Current handoff with exact safe bootstrap invocation, corrected source path, current hashes, current SID behavior, and test results. | References the three scripts and test evidence in this package. |
| `TEST_EVIDENCE.md` | `f10174ae188c0f37d3b2ac27a2092110b55f695fa191738f219ec217bab9988d` | Captured complete Windows PowerShell 5.1 assertion output, parser results, commands, and exit codes. | None. |
| `.gitattributes` | `7db6a4594ca028c9756c1c6f838e247424a086289bc4516147589efdaf27380c` | Disables line-ending conversion within this review-only evidence directory so GitHub blobs retain exact source bytes. | Git attribute handling only. |
| `REVIEW_MANIFEST.md` | See SHA-256 in the draft PR description and completion report. | Package index and exact per-file digests. A manifest cannot contain its own digest without changing that digest. | None. |

## Test results

- Windows PowerShell 5.1 synthetic suite: **23 assertions, 0 failures, exit code 0**.
- Windows PowerShell 5.1 parser: three scripts parsed, **0 errors, exit code 0**.
- Full test output and command lines: `TEST_EVIDENCE.md`.

All ACL fixtures in the tests are synthetic. No secrets, credentials, or live host ACL/SDDL records are included. No live UAC, install, `icacls`, VM operation, G: write, ACL query, or native workload was performed.

## Source preservation

The three published scripts are copied as raw bytes and must match the digests above. PR #50 source HEAD remains `2c967661163fc157b638fa4f76da86c48aa57ff2` on its existing branch. The seven reviewed package files are still pinned by `F2_ICACLS_SOURCE_PINS.json`; the 22-assertion synthetic install validates those seven hashes against the installer pins.
