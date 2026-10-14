# F2 G1 — Independent local v4 integration source-only review (2026-10-14)

**Disposition:** LOCAL_V4_INTEGRATION_REVIEW_PASS, Windows PowerShell 5.1 scope only. **NOT** production, CI, install, recovery, security or release approval.

**Repository:** publiomcko-cloud/procedural-sandbox-simulation  
**Authoring branch:** diagnostics/f2-v4-integration-import-fix  
**Reviewed HEAD:** `cb0bdddf278da51be4e2acaea0d80141b7b4bbc4`  
**Parent:** `d29f5d5a10e1b16147a3638c0545d13dcf12c39d`  
**Reviewed change:** one tracked path, `scripts/f2-acl/Test-F2ReleaseIntegration.V4.SourceOnly.ps1`, import ordering correction only (integration module imported first, v4 verifier second), plus a clarifying comment.

## Attribution and evidence boundary

- **Codex independent local Windows verifier reported** this result in a detached clean worktree, Windows PowerShell `5.1.22621.6133`. These are reported test results, **not** tests performed by the ChatGPT GitHub author.
- **ChatGPT independently confirmed from live GitHub** that the remote branch HEAD is exactly `cb0bdddf...`, parent is `d29f5d5...`, and the parent→HEAD diff contains one file (+3/−1). The integration/verifier module source was not changed by the correction. PRs #73 and #74 remain draft/open/unmerged. GitHub Actions for this exact commit: zero runs as checked on 2026-10-14.
- Codex reported all four v1/v2 source-pin manifests, both historical release manifests, the existing v4 source verifier, runtime, updater, coordinator, launcher and collector unchanged at this exact parent comparison; `git diff --check` passed and the detached worktree was clean.

## Windows PowerShell validation (Codex-reported)

Command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2ReleaseIntegration.V4.SourceOnly.ps1
```

**Parser:** 0 errors in each of the v4 integration module, v4 verifier and integration harness.  
**Execution:** exit code **0**, **49 assertions**, **0 failures**.

Covered positive/negative gates:
- Six distinct role descriptors (Collector, Runtime, Coordinator, Launcher, Updater, Recovery), only four read-only integration-module exported functions.
- Each role accepted read-only `Inspect` over the exact ten Windows-checkout source files while never authorizing capture, launch, install, activation, rollback or resume-forward. Each role rejected its prohibited action.
- Source digest, external manifest digest, supplied commit mismatch, missing exact-byte switch, G: source path, release-approved status spoof, cross-version v3/v4 substitution, and modified package-member hashes rejected.
- Synthetic recovery observation accepted without recovery permission; Rollback/ResumeForward/Activate denied. Mismatched old manifest/commit/active manifest, false claim of preserved backup, claimed protected operation, altered/duplicate/out-of-order/incomplete phases, forged approval, changed transaction ID/manifest/commit rejected.
- Static source guards confirmed production runtime and coordinator remain v3-only, updater v2/v3-only, launcher cannot dispatch v4 and collector remains on v1 pins.

## Git blob IDs vs exact Windows checkout SHA-256

| File | Git blob ID | Windows checkout SHA-256 |
|---|---|---|
| `scripts/f2-acl/Test-F2ReleaseIntegration.V4.SourceOnly.ps1` | `dd25bd9d4f1a3a973c5df5cdcaf3abb789d12773` | `be57b45476a8c8217bb16c3b488e08a44c4fe7520e506e3442a5bcb0a17844db` |
| `scripts/f2-acl/F2ReleaseIntegration.V4.SourceOnly.psm1` | `b970dcfdfc9adef1fd3a51ac5cd52b40f659e298` | `250849fb5c0c1542c9a75e69ca924cfc21bb12b41b64637ceb2d32d41dca1b07` |
| `scripts/f2-acl/F2ReleaseContract.V4.SourceOnly.psm1` | `1fa619feb231d2ad35f84a944300959d8befa59c` | `ff06edf1e0fb640e3e76f4a172b61c16ce39054064f75c19583b705ff8fcfe41` |
| `docs/reviews/f2-g1-v4-integration-source-only/README.md` | `aca570a1740e225f630951eeae49371a6509c83c` | `efafba25567d2fbbdba2f63e9061acb3b42d45233d8e9d9740732763be6d9981` |

These Windows digests are Codex-reported from its detached checkout; they must not be assumed identical to the Git-byte hashes where EOL transformations apply.

## Previous blocked attempt and correction history

1. Branch `diagnostics/f2-v4-integration-contracts-source-only`, HEAD `d29f5d5a10e1b16147a3638c0545d13dcf12c39d`: Codex reported 2 assertions PASS, then hard failure at the `Get-F2V4PackageNames` visibility/import boundary, exit 1. Positive source/negative/recovery tests **not executed**.
2. ChatGPT authored a separate one-file import-order correction on new branch `diagnostics/f2-v4-integration-import-fix`, HEAD `cb0bdddf278da51be4e2acaea0d80141b7b4bbc4`; no runtime or source-verifier code changed.
3. Codex independently retested the exact corrected SHA: 49/49 assertions PASS, exit 0. The prior failure remains retained as evidence, not overwritten.

## Remaining blockers and review limitations

- **NO V4 PRODUCTION INTEGRATION:** the current production collector, runtime, coordinator, launcher, updater, packaging and transaction machinery still use historical v1/v2/v3 contracts. v4 inspection-only contracts are never imported by those entrypoints.
- **NO REAL RECOVERY PROOF:** the synthetic observation envelope is not production `transaction.ndjson` chain validation, lock/barrier behavior, protected DACL verification, process quiescence, atomic replacement, fault injection or rollback/resume-forward.
- No independent authentication of actual checkout Git HEAD by the v4 verifier, no externally approved final package/manifest digest/receipt, no reviewed installer migration, no full F2 regression, no CI, no elevation/UAC, no protected operation, no VM/G: activity or deployment.
- The earlier CI run #85 remains FAILURE/FULL_SEQUENCE_INCONCLUSIVE, including an intermittent diagnostic receiver failure; the original full-sequence timeout root cause remains unknown.
- **Owner authorization:** independent PASS permits recording the source-only validation. It does NOT independently authorize the next production implementation, new CI, PR, merge, elevated execution or release. Keep `RELEASE_HOLD`.

## Next decision and continuity

Preserve ADR-0003 temporary GitHub-author / Codex-Windows-validator roles **only** while the owner keeps the blocked F2 G1 remediation cycle open. Update `docs/status/F2_G1_ACTIVE_HANDOFF.md` and obtain explicitly scoped owner permission before starting any production v4 integration. After owner-recorded closure, revert to standard Codex implement/commit → ChatGPT independent evaluation → owner decides.

Recorded by ChatGPT as a **repository review note reporting Codex-run evidence**; not an independently rerun Windows test and not a user release approval.
