# F2 G1 — v4 bounded-process negative test validity review (2026-10-14)

**Independent Codex verdict:** `BLOCKED_WITH_EVIDENCE` despite **44/44 assertions PASS, 0 failures, exit 0**. This is a test-validity blocker, NOT a production release or source-only acceptance.

**Reviewed branch:** `diagnostics/f2-v4-predispatch-process-boundary`  
**Reviewed HEAD:** `98fe40bd7e5ecf8afa3f5b02b1ba7ff3d479619f`  
**Direct parent:** `6f4813d3b2a02cebcffcb44cb69acfea56b9401a`  
**Earlier blocked base:** `7d66de1037cf5e895c4128c5211e163a7d8c0ff4`

## Codex-reported execution and provenance

The Codex reviewer fetched the exact remote HEAD into a fresh clean detached worktree at `C:\Dev\f2-g1-v4-predispatch-review-98fe40`, confirmed repository origin, two-commit ancestry and an exact three-path cumulative source-only diff, plus `git diff --check` and clean final worktree. Ten relevant PowerShell files parsed with **zero errors**. The requested non-elevated Windows PowerShell 5.1 test completed **44/44 assertions, zero failures, exit 0**. It verified the six read-only role paths, ten physical Windows-checkout member hashes, error/path/digest and Git-boundary negatives, dirty state, FSMonitor, output-cap and timeout cases. The test left no matching dirty sentinel, junction or fixture process. TEMP was a fixed C: volume without reparse ancestry. No CI, UAC, protected ACL operation, updater/recovery, VM/G:, merge or deployment occurred.

**Changed source files — Git blob ID / Windows checkout SHA-256, Codex reported**

| File | Git blob SHA-1 | Windows checkout SHA-256 |
|---|---|---|
| `docs/reviews/f2-g1-v4-predispatch-source-only/README.md` | `11cfe3a7233af74c9a47bee2b47f52bb05c04f69` | `639cace405ee2c4a62544dbc8bf6779151ecc6e7a5083230d9b84a097b33ec48` |
| `scripts/f2-acl/F2ReleasePreDispatch.V4.SourceOnly.psm1` | `1094f59ad7d6129b8d9b98a71ffcc8446e985c9d` | `f0d302a8cb48b4a18ec3641fd4aea4eb25b39f5faf0bd96395ccccd6a2371e6b` |
| `scripts/f2-acl/Test-F2ReleasePreDispatch.V4.SourceOnly.ps1` | `bb2647f69733ccd2ea3ea380a45f87c399753aa5` | `4d17770fbf94078368f75cd6ee4f95713dc331f147944eaedaf61fd7fed0d19a` |

**Ten-member Windows checkout SHA-256 inventory, Codex independently read**

| Package member | SHA-256 |
|---|---|
| `F2AclCapture.Protocol.psm1` | `cbeb608ccc4395f7944cca4fb84a7095219930de7a9bd4643fe4b0240dfd3cce` |
| `F2AclIcacls.Corroboration.psm1` | `12232e77b8b88638b6ef20e3d8bfd652a891277c715e40ec75c554074de60f1e` |
| `F2AclIcacls.Runtime.psm1` | `d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4` |
| `Invoke-F2IcaclsCapture.ps1` | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |
| `F2_ICACLS_SOURCE_PINS.json` | `7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce` |
| `F2_ICACLS_SOURCE_PINS_V2.json` | `df0b874ef206d347294422b869304046a9f68c8f5f7e692f645cf6a089c77529` |
| `F2_ACL_SOURCE_PINS.json` | `5f205cecd497d16ff2e07a7c029e7bbec440fa5deb30c5b05fb302651b7b28d8` |
| `F2_ACL_SOURCE_PINS_V2.json` | `e66e9c293946d254f832a1374b5d28ebbcde6bcc3a9f0eaccd538996985b5d2d` |

## Why review remains BLOCKED

The only new explicit review-gate failure: the synthetic timeout and oversized-output test catches used `$_.ToString() -match 'F2_V4_PROCESS_TIMEOUT'` and `$_.ToString() -match 'F2_V4_OUTPUT_LIMIT'`. A semantically unrelated error containing one of those substrings could make the test pass. There was no negative control proving such an unrelated exception is rejected. The flaw is in the **test classification**, not an observed failed process-runner assertion; 44/44 PASS cannot close this review.

Other residual, **not newly cleared** boundaries: the Git SHA-256 is locally computed in the test, not independent Git-toolchain approval. In .NET Framework 4.7.2 the synchronous `Process.Start()` is not subject to the later loop deadline; termination suppresses cleanup errors and `Kill()` does not guarantee stopping descendants. These limitations need a distinct production gate and must never be hidden by this harness correction.

## Bounded source-only correction prepared, separate from reviewed SHA

New branch `diagnostics/f2-v4-predispatch-exact-error-assertions`, HEAD **`b044e517c46e8f8d95bb5d8d4bc1225f6459fe84`**, parent `98fe40bd7e5ecf8afa3f5b02b1ba7ff3d479619f`. Exactly **one test harness** changed; the process runner, pinned source verifier/integration, historical source pins and installed production files were untouched.

The corrected harness captures the `ErrorRecord` **inside** module scope and requires exact `ErrorRecord.Exception.Message` equality against the expected stable error code, not a substring search of formatted exception text. Four new negative checks cover unrelated messages containing each marker and cross-code confusion. The new SHA is **PENDING** independent Windows PowerShell 5.1 parser/test review and must not inherit the 44/44 verdict from its parent.

## Next allowed action

Have Codex fetch the exact new HEAD in a fresh detached clean Windows worktree, verify one-file source-only diff, parse all dependencies, run only `Test-F2ReleasePreDispatch.V4.SourceOnly.ps1`, and validate both correct exact-code catches and unrelated-marker negative controls. Report first failed assertion, exit status, checkout SHA-256 and side-effect checks if blocked. Preserve `F2_G1_RELEASE_HOLD`; no CI, PR, merge, actual recovery, UAC, protected operations or deployment. Record the next result under its own exact SHA.

This documentation is sourced from the owner's Codex report and ChatGPT's independent GitHub source/diff verification; ChatGPT did **not** execute the Windows tests.
