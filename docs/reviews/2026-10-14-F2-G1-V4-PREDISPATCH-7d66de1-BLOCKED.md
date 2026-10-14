# F2 G1 — Independent Windows pre-dispatch review, blocked

**Date:** 2026-10-14 (owner-supplied Codex result; documentation recorded by ChatGPT).  
**Verdict:** BLOCKED_WITH_EVIDENCE, despite local test PASS. **RELEASE_HOLD.**  
**Repository:** publiomcko-cloud/procedural-sandbox-simulation  
**Branch:** diagnostics/f2-v4-production-contract-gates  
**Reviewed HEAD:** 7d66de1037cf5e895c4128c5211e163a7d8c0ff4  
**Parent:** cb0bdddf278da51be4e2acaea0d80141b7b4bbc4

## Identity and evidence

Codex independently fetched the exact branch to a clean detached Windows worktree. Origin, HEAD/parent, exactly three added source-only files, untouched historical/production Git blobs, and git diff --check passed. Windows PowerShell 5.1.22621.6133 parsed all four module/test/dependency files with 0 errors. The requested source-only test returned **30 assertions, zero failures, process exit 0**.

The 30 passing assertions covered all six role inspections over ten actual checkout files, rejected malformed digests/manifest/commit/path/status, preserved disabled dispatch/install/recovery flags and static v1/v2/v3 production identity. They do **not** prove an arbitrary configured Git process has no side effects, bounded execution or valid provenance.

### Codex-reported Windows checkout SHA-256

| File | Git blob ID | Windows checkout SHA-256 |
|---|---|---|
| docs/reviews/f2-g1-v4-predispatch-source-only/README.md | 0ed64d473535d8d728bbb68f5a01675a1120f82f | d554cad16bbdcf8b07a88284ae196773662d77a078f18f95cef5504bf80a2103 |
| scripts/f2-acl/F2ReleasePreDispatch.V4.SourceOnly.psm1 | 16176374416cbac9500128a2c41baeb8fcd3ac32 | 25484266f640f5a7ddf7d9120b2491b94b1f754dbb24df99a10e5e6d9ce3347a |
| scripts/f2-acl/Test-F2ReleasePreDispatch.V4.SourceOnly.ps1 | afffefdfed056e31140358ef5f7ccb9c863fae2e | b485d2157ea6da2d786cc6617fa475580de329c952e4b080c6ad9ac430b9e190 |

## Findings that block approval

1. Resolved `git.exe` from PATH without authenticating executable bytes or reparse ancestry; no independent executable/toolchain proof.
2. `git status` could invoke configured `core.fsmonitor` (daemon or hook), so `--no-optional-locks` was insufficient to justify source-inspection-only claims.
3. `@(& git ...)` accumulated all output before limiting it to 10,000 array elements; no deadline or streaming output cap.
4. UNC, canonicalized and mapped/network volumes and reparse ancestry were incompletely validated; no specific bypass was reproduced.
5. Dirty-worktree negative was not actually executed in the old suite.

## Bounded correction underway, not yet accepted

The temporary owner-authorized ChatGPT–GitHub author proposed corrections in isolated branch diagnostics/f2-v4-predispatch-process-boundary. Current correction HEAD: **98fe40bd7e5ecf8afa3f5b02b1ba7ff3d479619f**, based on reviewed parent 7d66de1037cf5e895c4128c5211e163a7d8c0ff4 via two commits.

Changes are limited to the same source-only module, its synthetic harness, and its README: an explicit expected SHA-256 for a fixed-local non-reparse Git executable; Git version >=2.36; controlled configuration disabling fsmonitor; deadline-bound process handling with concurrent byte-capped stdout/stderr; canonicalized fixed-volume restriction; and new negative tests including temporary dirty file, synthetic process time/output controls, FSMonitor environment and junction/UNC paths. All tool/receipt/checkout hashes computed by tests are **test fixtures, not independently approved identities**.

**Independent Windows parser/test and source-security verdict on the corrected HEAD are PENDING.** The exact output type of the process runner, cleanup semantics and synthetic negatives must be independently inspected and validated. An executable hash match is **not** a complete independently attested Git toolchain, and no real v4 release receipt exists. `HasSideEffects=false` is not a guarantee about an external process; the revised interface explicitly reports residual uncertainty. Preserve this blocked review, even if the corrected code passes.

No existing collector, runtime, coordinator, updater, launcher, ACL pin, release manifest, VM/G:, protected state, CI, PR or main branch was modified by the correction. CI #85 remains inconclusive/failed. There is no release authorization.

## Next permitted action

Have Codex independently validate the exact corrected source HEAD 98fe40bd7e5ecf8afa3f5b02b1ba7ff3d479619f in a new detached Windows worktree; verify all PowerShell parsing and bounded synthetic tests, first failure, no protected execution, Git and Windows bytes, EOL, clean final worktree. If blocked, retain the failure and scope another narrowly justified source-only change. No production v4 integration, CI, PR, merge or elevation without explicit owner approval.
