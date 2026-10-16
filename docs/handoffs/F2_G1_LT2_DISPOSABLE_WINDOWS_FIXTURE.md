# F2 G1 — LT-2: real Windows observation on disposable hosted CI fixtures only

**Status:** IMPLEMENTED CANDIDATE, PENDING INDEPENDENT EXACT-SHA SOURCE REVIEW. **NO PROTECTED HOST CAPABILITY**.

## Authorized scope, frozen inputs and purpose

- Explicit owner authorization: LT-2 source-only implementation and tests against **disposable Windows CI fixture trees**, not the protected Windows host.
- Base approved LT-1 commit: `ff97bfd4c5d13cbe03bd6a0d5de3c37113b31e4e`. Approved local-trust ADR ancestor: `29f90ef9b2310044e64d3acd775534559a404425`.
- R2 historical V2 policy and its fail-closed Live route remain unchanged. R3.3 synthetic-only policy remains unchanged.
- Objective: graduate from LT-1 in-memory labels to **actual read-only NTFS fixture file reads, real Windows ACL descriptor observations, independent GetTokenInformation readout, bounded SHA-256 and cross-file synthetic baseline/manifest/frame integrity comparisons**, without allowing inspection of real protected C:/G: paths.
- No changes to `main`, installed scripts, deployment, ACLs, protected updater or Hyper-V.

## Deliverables

1. `scripts/f2-acl/lt2/F2G1LT2.Fixture.psm1` implements a fixed mapping of the **23 historical C: object labels** to a **new unique fixture directory under the GitHub-hosted Windows runner's RUNNER_TEMP**. The names are literal policy labels; every real file read uses a path nested under `$env:RUNNER_TEMP\F2G1-LT2-<guid>\C\...`, never the host's actual `C:\Program Files\...` or `C:\ProgramData\...`.
2. The observer explicitly does NOT provide a live switch, arbitrary path mapping, package installation, elevated fallback, mutating command or protected host provider. Its fixture-root validation checks the direct temporary-directory child, literal GUID leaf, no reparse at parent/fixture root, and strict hosted-CI metadata. **CI metadata is spoofable and is not security-grade authentication.** It is an operational fence under the owner's *trusted-host/no hostile local actor* assumption.
3. With `Get-Item`, `Get-Acl -LiteralPath`, read-only `FileStream` (`FileShare.Read`) and `Get-ChildItem`, it checks 8 directories, 15 files, five exact immediate inventories, reparse/type mismatch, owner/SDDL visibility, bounded file size, and before/after basic metadata/ACL stability. It reads the 15 files with a bounded same-stream loop and checks hashes against a synthetic manifest plus cross-file payload, integrity, stream and frame linkages. This is **not** full R2 historical V2 acceptance: package member bytes are deterministic CI fixture data; known historical source/manifest/mailbox IDs are only policy fields in synthetic evidence. It does not prove Windows effective token access, stable 128-bit file IDs, atomic snapshots or absence of named ADS/hard links.
4. Real `GetTokenInformation` queries the current Windows **process token** for `TokenElevationType`, `TokenElevation`, and mandatory integrity level. Actual WindowsIdentity/WindowsPrincipal checks impersonation, SYSTEM/guest/anonymous and effective Administrators role. Non-elevated default or UAC limited-token + Medium integrity and inactive Administrator role are accepted. All elevated, full, high-integrity or ambiguous states are classified `BLOCKED`. This real policy is evaluated when `-RequireStandardToken` is selected.
5. **Important CI constraint:** hosted Windows Actions may run elevated. The only entrypoint in LT-2 is the CI test script. The observer therefore offers a *CI fixture measurement mode* without `-RequireStandardToken`; this measures disposable fixture bytes/ACL but **does not establish that the elevated runner is acceptable for protected-host inspection**. The strict token option blocks before physical reads when the actual token is disallowed. Reports disclose `TokenEnforced` and `TokenClass`. No synthetic or CI-fixture report may be treated as a real C: attestation.
6. `scripts/f2-acl/lt2/Test-F2G1LT2.Fixture.ps1` alone creates/deletes test fixture trees. It constructs fifteen public synthetic files under the fixed subtree, captures pre/post fingerprints for **zero mutation by the observer**, and tests successful physical fixture observations and wrong-package hashes, altered payload/frame, missing/extra child, reparse, and invalid fixture root. All writes/deletes occur **only within newly created fixture trees**; no production or protected host operation.
7. `.github/workflows/f2-g1-lt2-source-only.yml` uses GitHub-hosted `windows-latest`, Windows PowerShell 5.1, `contents: read`, `persist-credentials: false`, bounded job execution and retained LT-1 and R2 regression suites.

**Intentionally deferred:** LT-2 does not implement a production Windows host package reader, real R2 historical installed bytes/pins comparison, complete real owner/DACL-policy matching to historical V2, privileged attacker resistance, cryptographic launcher trust or hard-link/ADS absence guarantees. These unresolved **implementation capabilities** must be reviewed and tested before any future real protected-host read; a successful synthetic frame/manifest check alone is not an operational PASS.

## Outcome and limits

Expected positive report: `SYNTHETIC_FIXTURE_PASS` with `Mode=DISPOSABLE_WINDOWS_CI_FIXTURE_ONLY`, `ProtectedReads=0`, `HistoricalV2=NOT_ATTESTED_SYNTHETIC_BYTES`, and `LinkAndAds=LINK_ADS_NOT_ATTESTED`. Negative reports: bounded `BLOCKED_WITH_EVIDENCE` and sanitized classification. Errors never trigger UAC or alternate target fallback.

LT-2 acceptance requires a single independent exact-SHA review of the concrete code and Windows CI evidence, focused on scope containment, actual process-token semantics, read-only file/ACL capture, fail-closed fixture integrity, cleanup safety and unchanged R2/R3.3. No repeat of accepted architecture-level high-assurance gates absent a relevant safety defect.

**Future LT-3 (NOT AUTHORIZED):** separately design, review and authorize any proposed narrowly scoped read-only host access with explicit owner grant naming exact source revision, target machine and C: allowlist. **No LT-4 host reading is authorized here.**

All five holds continue: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
