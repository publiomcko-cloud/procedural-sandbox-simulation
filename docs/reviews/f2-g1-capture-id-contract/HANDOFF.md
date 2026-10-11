# Developer handoff — F2 G1 release-manifest v2 loader

Status: **READY_FOR_INDEPENDENT_REVIEW**. Source-only implementation; no privileged installation or live host operations were performed.

## Commit and branch

- PR: #53 (draft, unmerged).
- Review branch: `fix/f2-baseline-capture-identity-issue48`.
- Production source commit: `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`; parent `4c53f6dd03c6ddc564a45f8c203286595385c46b`.
- The documentation/evidence commit and final review HEAD are recorded in the pull request and `REVIEW_MANIFEST.md`.

## Change

Aligned the actual on-disk runtime release-manifest loader with the v2 schema already emitted by the installer and required downstream. Added Windows PowerShell 5.1 coverage that loads synthetic temporary manifest files through the real loader without a release-provider mock, checks the seven-file package contract, and fails closed on legacy v1, malformed JSON, and missing identity fields. Refreshed the source pin manifest and carried the resulting pins through the installer and SHA-bound bootstrap.

## Changed paths

- `scripts/f2-acl/F2AclIcacls.Runtime.psm1`
- `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1`
- `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json`
- `docs/reviews/f2-g1-capture-id-contract/Install-F2IcaclsProtectedPackage.ps1`
- `docs/reviews/f2-g1-capture-id-contract/Invoke-F2VerifiedInstaller.ps1`
- `docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1`
- Review command, test evidence, parser output, handoff and manifest files in `docs/reviews/f2-g1-capture-id-contract/`.

## Validation

Exact Windows PowerShell 5.1 commands and results are in `TEST_EVIDENCE.md`; complete test logs are included adjacent. GitHub Actions run identity and result are recorded there after CI completes. `git diff --check` is required at the final published HEAD.

## Risks and limits

Synthetic tests verify source behavior only. They do not verify UAC, protected installation, live ACLs, live `icacls`, VM/Hyper-V state, G: storage, or runtime ACL acceptance. A fresh owner authorization is required for any future installation after independent review. PR #50 remains unchanged.
