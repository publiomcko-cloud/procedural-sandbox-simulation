# F2 G1 — First production-facing v4 pre-dispatch seam (source-only)

**Status:** SOURCE_ONLY / INSPECTION_ONLY / RELEASE_HOLD. **Not installed, imported, deployed or activated by protected production entrypoints.**

Reviewed source parent: `cb0bdddf278da51be4e2acaea0d80141b7b4bbc4`. Source-only role and release contract modules are unchanged; all existing v1/v2 source pins, legacy v2/v3 release candidate manifests, collector/runtime/coordinator/updater/launcher and protected recovery logic remain byte-for-byte unchanged. This step adds a **new** entrypoint, not a modification to a previously pinned release member.

## Purpose and meaningful new behavior

`F2ReleasePreDispatch.V4.SourceOnly.psm1` supplies a single exported `Test-F2V4ReadOnlyPreDispatch` function, a production-facing **pre-dispatch inspection gate**, accepting a role and supplied external-reviewed identity/digests. It:

1. Rejects G: and UNC roots, missing roots and reparse-point ancestors, then normalizes and validates a physical source directory.
2. Invokes **read-only** `git.exe -C <source>` queries to obtain the checkout top-level, worktree state and **actual Git HEAD** rather than trusting a second caller-provided commit. Requires the physical root to equal the exact Git top-level and HEAD to equal `ExternallyReviewedCommitSha`.
3. Requires `git --no-optional-locks -C <source> status --porcelain=v1 --untracked-files=normal` to return clean, including visible untracked files. The global `--no-optional-locks` option prevents Git's optional index/lock writes during read-only identity checks. It is a clean-checkout gate, **not** a Git-signature or trusted-tool binary attestation.
4. Invokes the previously reviewed v4 integration validator with `Inspect`, the real observed checkout HEAD, caller-supplied externally reviewed manifest/active-pin SHA-256 and exact ten Windows checkout file bytes.
5. Returns a sanitized `SOURCE_ONLY_INSPECTION_ACCEPTED` or `REJECTED` result with **all** action permissions false. It NEVER calls protected updater/coordinator/collector/launcher, never grants `ReleaseApproved` or `CanDispatch`, and explicitly reports `ExternalReceiptIndependentlyAuthenticated=false`.

The new function narrows the gap where the older v4 helper accepted an unauthenticated caller-provided `ActualCommitSha`. It still does **not** prove that `git.exe` on PATH is independently trusted or that a reviewed commit/digest came from an authoritative signer. No approved receipt is included, and self-calculated test-fixture digests must not be accepted for a real release.

## Local Windows source-only validation

Run **only after confirming the exact pinned Git SHA in an isolated clean detached worktree**, Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2ReleasePreDispatch.V4.SourceOnly.ps1
```

The harness reads ten real checkout files, performs read-only `git.exe rev-parse` and status calls, builds a synthetic non-approved manifest in memory, and checks six role preflights, denied action flags, wrong commit/digests, a forbidden G: root (rejected without accessing it), incorrect repository/package root, v3/v4 mixing, forged release status and altered file/baseline hashes. All tests are **PENDING** independent Codex Windows execution. It does not execute any production runtime path or operation.

## Blockers and next approval

The v4 source-only preflight is **not** a signed trust root, versioned production dispatcher, installer, package migration or recovery implementation. A future separate stage must establish an independent reviewed checkout/commit and release receipt, trusted Git tool chain, safely repin the exact v4 installed package, explicitly version coordinator/runtime/launcher/updater transaction and rollback/recovery state, and obtain owner authorization for each expanded operation. Editing legacy pinned production files in place would invalidate historical manifests and is deliberately avoided here.

Keep PR #73/#74 draft, prior CI #85 inconclusive and no rerun, unresolved child receiver failure, and `F2_G1_RELEASE_HOLD`. Any independent Windows PASS accepts **only this source-only scope**, not production release or F2 G1 cycle closure. Document exact Windows hashes and the Codex verdict before further changes.
