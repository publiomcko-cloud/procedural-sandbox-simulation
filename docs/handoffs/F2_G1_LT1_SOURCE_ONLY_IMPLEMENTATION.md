# F2 G1 — LT-1 trusted-local source-only synthetic prototype

**Status:** IMPLEMENTED IN ISOLATED BRANCH / PENDING SOURCE REVIEW / MOCK-ONLY. NOT READY FOR LIVE C: ACCESS.

**Owner authorization:** LT-1 source-only implementation and disposable Windows CI synthetic tests only, following independently accepted local-trust ADR at `29f90ef9b2310044e64d3acd775534559a404425`. No authorization for host C:/G:, VM, UAC, icacls, installation, ACL changes, deployment, PR, merge or release.

## What was implemented

- `scripts/f2-acl/lt1/F2G1LT1.Synthetic.psm1`: pure in-memory mock validation of the frozen **23 C: object names as strings** (8 directories and 15 files), all **five exact immediate-child inventories**, seven package file names, seven mailbox evidence names, synthetic public test bytes and digests, mocked ACL/profile, object type, reparse and identity drift. Its "contents" are `LT1-SYNTHETIC-ONLY|<path-as-string>`, NOT the historical V2 contents. The seven historical package SHA-256 pins and V2 mailbox evidence remain governed by unchanged R2, not this test generator.
- `scripts/f2-acl/lt1/Invoke-F2G1LT1.SourceOnly.ps1`: an **explicitly mock-only entrypoint**, with no `-Live`, no arbitrary C:/G: path, no filesystem mutation and no protected-path provider. Requires Windows PowerShell 5.1 and disposable GitHub-hosted Windows CI metadata (an **operational, spoofable check only**, never authorization), constructs a synthetic fixture entirely in memory and issues a bounded sanitized report or blocked verdict.
- `scripts/f2-acl/lt1/Test-F2G1LT1.SourceOnly.ps1`: Windows PS5.1 parser checks, fixed-scope and synthetic positive/negative tests including wrong case, missing/duplicate entries, changed mock contents, mocked ACL/reparse/identity drift and denied mock tokens.
- `.github/workflows/f2-g1-lt1-source-only.yml`: Windows hosted CI, permissions `contents: read`, `persist-credentials: false`. Executes focused LT-1 suite, positive/negative CLI and unchanged R2 historical synthetic fixture regression. No host or VM access.

**UAC token policy at this stage:** deterministic mock profiles `Standard` and `FilteredLimited` are accepted only as **simulated non-elevated snapshots**; mock elevated/full-admin/system/high-integrity/impersonation/forbidden privilege states are blocked. This is not a real Windows token security decision. No `GetTokenInformation` interrogation, linked-token privilege validation or actual standard-token-enforcement claim exists yet. The ultimate LT-2 implementation contract must add a real Windows token check (or reject filtered tokens conservatively), test denied/elevated/ambiguous conditions and undergo independent source review before any on-host authorization.

**Evidence limitations:** passing in-memory expected mock bodies is only `SYNTHETIC_FIXTURE_PASS`; the 23 paths are **policy labels** and are never opened by LT-1. Reports always contain `ProtectedReads=0`, `HistoricalV2=NOT_ATTESTED_MOCK_BYTES_ONLY` and `LinkAndAds=LINK_ADS_NOT_ATTESTED`. This is NOT an implementation of physical Windows C: capture, true object ACL reads, full historical V2 cross-file evidence verification or Windows anti-TOCTOU hardening. The legacy R2 fixture suite separately tests many historical-policy rules but also provides no protected-host evidence.

**No loosening of existing protection:** R2 `New-F2G1LiveProvider` still throws; the owner-authentication hook always denies; R2 `-Live` returns a blocked result before protected reads. R3.3 scope remains `LivePermitted:false`. LT-1 cannot call either live path and supplies no new live path.

## Proportionate acceptance gates

**LT-1 candidate:** the focused Windows CI must pass the finite positive and fail-closed negative fixtures, CLI invocations and unchanged R2 source-only regression. A separate independent source review should focus on accidental host-path access, all 23 string labels, strict five inventory mock checks, PowerShell parser/CI 5.1 compatibility, token-profile mock honesty, fixed/limited report contents and unchanged live barriers.

**LT-2 (new separate authorization required):** implement and test real Windows token qualification, read-only opened-file/ACL observations, bounded file hashes and cross-file historical policy checks **against disposable synthetic Windows fixture trees only**. Do not report an actual protected-host PASS. Only after separate independent exact-SHA code acceptance can LT-3 seek a new single-use *procedural* owner grant for an exact one-time host-read scope. LT-4 is a hypothetical subsequent protected read, not approved now.

**Mandatory persistent holds:** `CURRENT_PROTECTED_STATE_UNKNOWN`; `V3_NOT_ATTESTED`; `ACL_REVIEW_REQUIRED`; `G1_BLOCKED_ENVIRONMENT`; `F2_G1_RELEASE_HOLD`.
