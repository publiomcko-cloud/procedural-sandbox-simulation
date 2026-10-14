# F2 G1 — First production-facing v4 pre-dispatch seam (source-only)

**Status:** SOURCE_ONLY / INSPECTION_ONLY / RELEASE_HOLD. **Not installed, imported, deployed or activated by protected production entrypoints.**

Reviewed source parent: `cb0bdddf278da51be4e2acaea0d80141b7b4bbc4`. Source-only role and release contract modules are unchanged; all existing v1/v2 source pins, legacy v2/v3 release candidate manifests, collector/runtime/coordinator/updater/launcher and protected recovery logic remain byte-for-byte unchanged. This step adds a **new** entrypoint, not a modification to a previously pinned release member.

## Purpose and meaningful new behavior

`F2ReleasePreDispatch.V4.SourceOnly.psm1` supplies a single exported `Test-F2V4ReadOnlyPreDispatch` function, a production-facing **pre-dispatch inspection gate**, accepting a role and supplied external-reviewed identity/digests. It:

1. Rejects G: and UNC roots, missing roots and reparse-point ancestors, then normalizes and validates a physical source directory.
2. Requires an explicit fixed-local, non-reparse `TrustedGitExecutablePath` and an externally supplied `ExternallyPinnedGitExecutableSha256`; rejects a wrong SHA **before launching Git**. Validates Git version at least 2.36 and obtains actual checkout top-level, worktree state and Git HEAD using the pinned executable. The exact root and expected reviewed commit must match. The SHA is computed locally in synthetic tests only, so a passing test does not authenticate a future external receipt.
3. Invokes fixed Git commands through a .NET `Process` runner with concurrent bounded stdout/stderr draining (16 KiB combined), per-command deadline (4 s), bounded process-kill wait, `--no-optional-locks`, `--no-pager`, `-c core.fsmonitor=false`, `-c core.untrackedCache=false`, `-c core.hooksPath=NUL` and environment scrubbing of inherited `GIT_*` variables. Requires `status --porcelain=v1 --untracked-files=normal --ignore-submodules=all` clean. The hook and optional-write controls reduce side-effect risks but **do not guarantee an independently trusted Git executable or all child processes**.
4. Invokes the previously reviewed v4 integration validator with `Inspect`, the real observed checkout HEAD, caller-supplied externally reviewed manifest/active-pin SHA-256 and exact ten Windows checkout file bytes.
5. Returns a sanitized `SOURCE_ONLY_INSPECTION_ACCEPTED` or `REJECTED` result with **all** action permissions false. It NEVER calls protected updater/coordinator/collector/launcher, never grants `ReleaseApproved` or `CanDispatch`, and explicitly reports `ExternalReceiptIndependentlyAuthenticated=false`.

The new function narrows the gap where the older v4 helper accepted an unauthenticated caller-provided `ActualCommitSha`. It **no longer resolves the production Git executable from PATH**, but still does not independently attest the **entire Git toolchain** (e.g., launcher executables and native DLL dependencies) or signed source/release approval. Its output explicitly includes `GitToolchainIndependentlyAttested=false` and `ExternalProcessSideEffectsUnprovable=true`. No approved receipt is included; self-calculated test-fixture digests are NOT release authority.

## Local Windows source-only validation

Run **only after confirming the exact pinned Git SHA in an isolated clean detached worktree**, Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2ReleasePreDispatch.V4.SourceOnly.ps1
```

The harness reads ten real checkout files and verifies the fixed pinned executable against a **self-generated test-only hash**, builds an unapproved synthetic manifest, and tests six role preflights, denied actions, wrong executable/commit/manifest/pin digests, G:/UNC/device/drive-relative and missing paths, a temporary junction/reparse fixture, an ephemeral untracked checkout-file dirty-state fixture (removed in `finally`), a synthetic inherited FSMonitor configuration, and bounded timeout/oversized-output behavior using a non-elevated `powershell.exe` fixture. All new tests are **PENDING** independent Codex Windows execution. They do not execute protected update, recovery, ACL mutation, UAC or VM/G: operations. An abrupt crash may leave a temporary test fixture; the reviewer must check and clean its known name without touching unrelated paths.

## Blockers and next approval

The v4 source-only preflight is **not** a signed trust root, versioned production dispatcher, installer, package migration or recovery implementation. A future separate stage must establish an independent reviewed checkout/commit and release receipt, trusted Git tool chain, safely repin the exact v4 installed package, explicitly version coordinator/runtime/launcher/updater transaction and rollback/recovery state, and obtain owner authorization for each expanded operation. Editing legacy pinned production files in place would invalidate historical manifests and is deliberately avoided here.

Keep PR #73/#74 draft, prior CI #85 inconclusive and no rerun, unresolved child receiver failure, and `F2_G1_RELEASE_HOLD`. Any independent Windows PASS accepts **only this source-only scope**, not production release or F2 G1 cycle closure. Document exact Windows hashes and the Codex verdict before further changes.


## 2026-10-14 independent review blocker and bounded correction

Original HEAD `7d66de1037cf5e895c4128c5211e163a7d8c0ff4` passed 30/30 local Windows PowerShell 5.1 assertions but returned **BLOCKED_WITH_EVIDENCE** on four static issues: unpinned Git resolved via PATH; configured FSMonitor helper side effects; output accumulation without deadline; incomplete canonical path/volume cases.

This source-only correction is intended to address those four risks without modifying any protected production source, historical manifest or old-installed-release pin. **Windows PowerShell 5.1 parse/test execution on the corrected HEAD remains PENDING.** Retain the prior blocked report and use a fresh clean detached worktree for this new revision.

The revised gate is still a **source-only inspection seam**. `HasSideEffects=false` reports that no side effects are requested by the gate's own application logic, **not** an absolute assertion about arbitrary executable behavior. The result includes `ExternalProcessSideEffectsUnprovable=true` and never returns dispatch/installation/recovery authority. The Git executable's locally computed test SHA-256 is not an independently approved executable receipt. Real production enablement still requires a trusted executable/toolchain provenance, signed manifest approval, secure v4 transactional migration and independent review.
