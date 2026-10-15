# F2 G1 — transaction V4 pure-conformance first independent review BLOCKED

**Recorded:** 2026-10-15 (America/Sao_Paulo).  
**Verdict:** `BLOCKED_WITH_EVIDENCE`, retained as immutable historical review; passing harness assertions did not close semantic gaps.  
**Reviewer:** Codex, independent Windows verifier; report relayed by owner.  
**Repository:** https://github.com/publiomcko-cloud/procedural-sandbox-simulation  
**Reviewed branch:** `diagnostics/f2-g1-v4-transaction-pure-conformance`  
**Exact HEAD:** `cbad0524ccd8a54bcf8d0c1abfc0c08c4bea0f24`  
**Direct parent:** `c15b6440f91fe363b7bc1be7bf24b59229c3e402`.

## Provenance and execution

Codex reported a clean detached Windows review worktree, matching origin and branch ref, correct parent and exactly four new source-only files: `CONFORMANCE_FACTS.SourceOnly.json`, `CONFORMANCE_HARNESS.md`, `F2TransactionConformance.V4.SourceOnly.psm1` and `Test-F2TransactionConformance.V4.SourceOnly.ps1`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2TransactionConformance.V4.SourceOnly.ps1
```

**Codex-reported result:** Windows build 22631, Windows PowerShell 5.1.22621.6133; **701 assertions PASS, 0 FAIL, exit 0**. The 92 independently specified matrix IDs and 19-state mapping passed, all production permission flags were false, and synthetic rollback, replay, legacy v2/v3 exclusion and non-switching finalization checks passed. Source audit found no production imports, filesystem mutation, child-process execution, protected path operation, elevation or active updater invocation.

## Two independently identified blocking counterexamples

1. **Possible local write misclassified as pre-write rejection.** `Resolve-F2V4ConformanceObservation` extracted `LocalWritePossible` but the receipt branch could return `REJECTED_RECEIPT / REJECT_BEFORE_WRITE` with `LocalWritePossible=true`. Example: `Domain=Receipt`, `Condition=Missing`, `LocalWritePossible=true`. R3 CONTRACT §5 requires evidence-preserving `HOLD_PRESERVE` for contradictory/uncertain observations.
2. **Unknown predecessor schema accepted by fake authority.** `Invoke-F2V4FakeReservation` rejected only `v2` and `v3`; an arbitrary other `PredecessorSchema` could yield `RESERVED_SIMULATED` for `INSTALL`. Unrecognized input must fail closed, without updating fake authority state.

These are concrete review defects **despite** the zero-failure harness result. No source was altered in the detached review.

## Codex-reported Windows checkout SHA-256

| Source | SHA-256 |
|---|---|
| V4 model module | `D09F2BD1EDBCD99856160B18EE5D24ACF4E93B3208BB15E2C1A23B9F55399D89` |
| V4 test harness | `38AE5E1DC2C76BD8636B49F832344FBF6285FF6ED88C3BE1196CED7417EAF6C5` |
| R3 acceptance matrix | `1A082FC5958E9A38DEFDE3DB91F1499F77E6DAB6E82AE107B771F5C07D87C85F` |
| Synthetic facts | `32C6CF8A0CF0BC6AC816F829E0801FB840B4D1BE336BFFA3357E7653FBDFDC79` |
| R3 CONTRACT | `569DBADC4E887B2D635CC255AB74604694103B9F8C2D5FEEE497CAD55C56CBDA` |
| Conformance harness document | `F0776649D687108A4E546BE8A939BF395E9D922417BE32D7C959901B52F7DF0F` |
| ADR-0004 | `BF7BAD041485012840D7F2B42F2D61DAFCD07EC7B2E4DA5A1AFE08E1E6D25A4E` |

These values are **Codex-reported Windows checkout byte digests**, not independent ChatGPT Windows calculations or necessarily the same as Git blob identities.

**Disposition:** `BLOCKED_WITH_EVIDENCE`; new isolated correction and fresh independent review required. No CI, PR, merge, release, v2/v3 cutover, real journal, signature verification, protected operations or storage crash-safety claim.

**Follow-up:** Correction at `93a4e1ee094dbaeb932c2117040c0bf4ecc30c15` is recorded in a separate PASS report. This original blocking outcome remains unchanged.
