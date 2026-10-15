# F2 G1 — v4 exact-error pre-dispatch independent Windows review

**Recorded:** 2026-10-15 (America/Sao_Paulo) from owner-supplied independent Codex report. The exact execution date was not separately established.  
**Disposition:** `LOCAL_V4_PREDISPATCH_REVIEW_PASS` — **source-only harness and bounded-process negative classification, not production release approval**.  
**Release state:** `F2_G1_RELEASE_HOLD`.

## Immutable source identity and review attribution

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Source branch: `diagnostics/f2-v4-predispatch-exact-error-assertions`
- Reviewed HEAD: `b044e517c46e8f8d95bb5d8d4bc1225f6459fe84`
- Direct parent: `98fe40bd7e5ecf8afa3f5b02b1ba7ff3d479619f`
- Exact changed path: `scripts/f2-acl/Test-F2ReleasePreDispatch.V4.SourceOnly.ps1` (**one harness-only change**)
- Detached clean Windows worktree reported: `C:\Dev\f2-g1-v4-predispatch-exact-review-b044e5`
- ChatGPT independently verified live GitHub branch HEAD/parent, exactly one-file diff (+46/−16), exact error-message comparison and unrelated-marker test controls; ChatGPT did **not** execute the Windows suite.
- Codex reported unchanged v4 pre-dispatch process module, v4 contract/integration modules, four historical source-pin manifests, release manifests and 22 checked historical/pin/entrypoint paths.

## Windows PowerShell 5.1 evidence — Codex-reported

- Version: `5.1.22621.6133`.
- Parser sweep: **9 scripts, 0 errors**. A preparatory parser wrapper initially received a null repository argument and failed before parsing; after correcting the wrapper, the intended parsing completed successfully. This was a reviewer harness invocation issue, not an observed source parser error.
- Authorized executed test: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2ReleasePreDispatch.V4.SourceOnly.ps1`.
- Test result: **48 assertions, 0 failures, process exit code 0**.
- The test captures the runner exception inside its module invocation and classifies the captured `ErrorRecord` only when `Exception.Message` equals exactly and case-sensitively `F2_V4_PROCESS_TIMEOUT` or `F2_V4_OUTPUT_LIMIT` as appropriate.
- Both unrelated errors with embedded markers and both wrong-code cross-comparisons were rejected. Previous tests for six role-positive paths, exact ten checkout members, dirty checkout, local Git tool hash, configured FSMonitor, bounded timeout/output and forbidden paths still passed.
- Post-run: no matching dirty sentinel, temporary junction or fixture child process. `git diff --check` and clean detached worktree passed. No CI, PR, merge, protected execution, UAC, ACL changes, VM/G:, updater/recovery or deployment.

## Source and checkout hashes

| File | Git blob ID (SHA-1) | Git bytes SHA-256 | Windows checkout SHA-256 |
|---|---|---|---|
| `scripts/f2-acl/Test-F2ReleasePreDispatch.V4.SourceOnly.ps1` | `cfd7603a90cf8181b20a1d0d11fab35a2e5c9652` | `1f094755b6c4b0177e232eb911f9f4f109fc38bbd2e554225bb3b25ccc45c57b` | `524a11a5a577a27ab1af4f6953b01849aa032574b22a1732545a4a5c56017b41` |
| `scripts/f2-acl/F2ReleasePreDispatch.V4.SourceOnly.psm1` | `1094f59ad7d6129b8d9b98a71ffcc8446e985c9d` | Not reported in this review | `f0d302a8cb48b4a18ec3641fd4aea4eb25b39f5faf0bd96395ccccd6a2371e6b` |

The changed test file had `i/lf w/crlf`, consistent with its Git `eol=crlf` handling. Do not substitute Git-byte SHA-256 for Windows checkout-byte SHA-256.

## Review lineage: failures must remain visible

1. `7d66de1037cf5e895c4128c5211e163a7d8c0ff4`: **30/30 tests PASS, but BLOCKED_WITH_EVIDENCE** (untrusted Git executable/configuration, unbounded output/time and incomplete canonical path restrictions).
2. `98fe40bd7e5ecf8afa3f5b02b1ba7ff3d479619f`: **44/44 tests PASS, but BLOCKED_WITH_EVIDENCE** (timeout/output-cap test classifications accepted unrelated errors containing marker substrings). See `docs/reviews/2026-10-14-F2-G1-V4-PREDISPATCH-98fe40-BLOCKED.md`.
3. `b044e517c46e8f8d95bb5d8d4bc1225f6459fe84`: **48/48 tests PASS and source-only review accepted**, following a new isolated harness-only fix. The runner module itself was not changed in this final commit.

## What remains unproved and unauthorized

This validation does **not** establish independently approved Git executable/toolchain provenance; signed source or release-receipt authorization; an interruptible synchronous `Process.Start()`; guaranteed cleanup/termination of arbitrary descendants; real v4 runtime, install or recovery/rollback safety; or a full F2 sequence/CI acceptance. The original historical diagnostic receiver/timeout cause remains unresolved. Existing production paths remain v1/v2/v3 and the two draft PRs #73/#74 remain unmerged.

`LOCAL_V4_PREDISPATCH_REVIEW_PASS` must not become a claim of `F2_G1_RELEASE_READY`. The next actual production v4 package/dispatch/updater/transaction/recovery implementation, independent security gate, CI and protected operations each require explicit bounded owner approval. Continue the owner-approved temporary ChatGPT–GitHub author / Codex–Windows independent verifier process solely until the owner explicitly closes this blocked F2 G1 cycle; then return to Codex implements/commits → ChatGPT independent review → human decision.

**Prepared as durable documentation by ChatGPT from the Codex report and independent GitHub identity verification; it is not a new execution or release receipt.**
