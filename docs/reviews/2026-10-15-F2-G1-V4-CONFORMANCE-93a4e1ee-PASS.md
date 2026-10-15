# F2 G1 — transaction V4 pure-conformance correction independent review PASS

**Recorded:** 2026-10-15 (America/Sao_Paulo).  
**Independent reviewer verdict:** `V4_CONFORMANCE_INDEPENDENT_REVIEW_PASS` — **source-only abstraction only**.  
**Reviewer:** Codex on Windows, owner-provided exact review report.  
**Author:** ChatGPT on an isolated GitHub branch, not an independent executor of Windows tests.  
**Repository:** https://github.com/publiomcko-cloud/procedural-sandbox-simulation  
**Reviewed branch:** `fix/f2-g1-v4-pure-conformance-failclosed-r1`  
**Reviewed HEAD:** `93a4e1ee094dbaeb932c2117040c0bf4ecc30c15`  
**Direct parent:** `cbad0524ccd8a54bcf8d0c1abfc0c08c4bea0f24`  
**Design oracle:** R3 `c15b6440f91fe363b7bc1be7bf24b59229c3e402`.

## Scope, evidence, provenance

Codex fetched the exact remote HEAD into fresh clean detached worktree `C:\Dev\review-f2-g1-v4-failclosed-r1-93a4e1e`, independently checked origin, branch ref, parent and source diff. Windows review worktree remained clean. Only these two tracked files changed:

- `scripts/f2-acl/F2TransactionConformance.V4.SourceOnly.psm1`
- `scripts/f2-acl/Test-F2TransactionConformance.V4.SourceOnly.ps1`

ChatGPT independently checked GitHub branch HEAD, direct parent, exact two-path commit diff and Git blob identities; it did **not** execute the Windows PowerShell test, inspect the local Windows worktree firsthand or attest checkout SHA-256 from Windows.

## Windows PowerShell 5.1 test (Codex-executed, owner-relayed)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2TransactionConformance.V4.SourceOnly.ps1
```

- Version: Windows PowerShell `5.1.22621.6133`.
- **712 passed, 0 failed, exit code 0**.
- All 92 original R3 matrix cases against an independent design oracle, 19 closed inspection states, zero operational permission flags and in-memory replay/checkpoint invariants passed.
- **11 new negative regression assertions:** five possible-write contradictions and six unsupported predecessor schema cases.
- Rollback remained rejected; v2/v3 production cutover remained unsupported; proof-only finalization never performed a second active-pointer switch.
- Codex independently audited source for production imports, filesystem mutation, child-process launch, elevation, protected operations and updater/recovery calls; none found.

## Resolution of prior blockers

1. The resolver now replaces nominal `REJECT_BEFORE_WRITE` with `PRECONDITION_UNMET / HOLD_PRESERVE` where `LocalWritePossible=true`. The five new scenarios verify no mutation permissions.
2. The fake approval authority permits only the exact `PredecessorSchema='synthetic'` marker. Other schemas reject as `UNSUPPORTED_PREDECESSOR` without changing generation or in-memory approval/transaction/checkpoint maps.

**Codex-reported post-test Windows checkout SHA-256:**

| File | Windows SHA-256 | Verified Git blob SHA-1 |
|---|---|---|
| `F2TransactionConformance.V4.SourceOnly.psm1` | `5A7C2EEA83F21627389769D30C95905AF5CDBB57449DB10657194E3AEA1B6821` | `6d2e4fc1b6096bbbaa0d9b94903f31cd2d249f26` |
| `Test-F2TransactionConformance.V4.SourceOnly.ps1` | `3FB89B3F459A541593C3A0B4F2D749EBDE0630192E377142A95B702036776972` | `2f428b1151a64d1c7cf63951a323ce877c7de6d2` |

Codex reported the R3 ADR, CONTRACT, 92-case matrix, synthetic facts, harness documentation and four historical pin files unchanged from parent; exact commit diff independently confirms only two modified source files. Git and Windows byte identities are different classes and are not interchangeable.

## Limitations, unchanged owner gates and next decision

This PASS validates **only** a closed, purely synthetic PowerShell classification/state-machine model with an in-memory fake authority. It does not validate signed receipts, external anti-replay, byte-level journal parsing, persistent transaction durability, OS-enforced launch inhibition, late-reader quiescence, File.ReplaceW error/crash semantics, live v2/v3 migration or production execution. The older candidate's `BLOCKED_WITH_EVIDENCE` review at `cbad0524ccd8a54bcf8d0c1abfc0c08c4bea0f24` remains a distinct preserved record.

**Closed subtask:** the bounded source-only harness correction and independent retest are technically complete. **NOT CLOSED:** the parent F2 G1 diagnostics/protected-release cycle, the original full-sequence timeout and release hold. No owner authorization for PR, CI, merge, privileged execution, protected operations, v5 release or deployment follows.

**Recommended next gate (design/decision only):** determine whether an installed v2/v3 production cutover is necessary for the P0.1 F2 Voxel Tools feasibility experiment. If not, defer production v4/v5 deployment engineering and return to properly isolated G1 capability testing. If necessary, require a **new owner-approved cutover feasibility/ADR** proving launch inhibition, complete legacy reader/process/handle inventory, safe maintenance entry/exit, volume/identity and trust requirements, and negative/failure cases before implementation. R3 has **NO supported production predecessor**; do not infer migration authority from this review.

**Disposition:** `V4_CONFORMANCE_INDEPENDENT_REVIEW_PASS / SOURCE_ONLY_CORRECTION_COMPLETE / F2_G1_RELEASE_HOLD / NO_PRODUCTION_CUTOVER`.
