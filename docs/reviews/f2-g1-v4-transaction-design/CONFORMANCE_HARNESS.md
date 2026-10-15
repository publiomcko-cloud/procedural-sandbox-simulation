# F2 G1 — Transaction v4 pure conformance prototype

**Status:** SOURCE_ONLY_IMPLEMENTATION_CANDIDATE / INDEPENDENT_WINDOWS_REVIEW_PENDING / F2_G1_RELEASE_HOLD.

**Approved design basis (read-only):** `design/f2-g1-v4-transaction-architecture-r3` at `c15b6440f91fe363b7bc1be7bf24b59229c3e402`, independently classified `V4_TRANSACTION_DESIGN_REVIEW_PASS` **for architecture only**. This prototype is newly implemented under separate owner authorization for an in-memory source-only conformance harness. A design PASS does not imply these scripts pass PowerShell or provide release authority.

## New source-only artifacts

- `scripts/f2-acl/F2TransactionConformance.V4.SourceOnly.psm1`: **pure synthetic decision function** taking structured facts `Domain`, `Condition`, optional simulated authority/root/write flags (fixed closed input schema) and returning `InspectionState` and `Classification`, plus always-disabled `CanInstall`, `CanRollback`, `CanRecoverForward`, `CanFinalizePostSwitch`, `CanMutate` and `HasProductionAuthority`. Invalid/missing/unknown fact fields fail closed as `PRECONDITION_UNMET/HOLD_PRESERVE`. No production imports, filesystem functions, script execution, Git or real authority calls.
- `Test-F2V4ConformanceTransition` in the same module models the closed normal journal progression from remote reservation through genesis, stage, publish intent, verified backup, switch intent, readback and terminal proof, plus a separate proof-only `FINALIZE_POST_SWITCH` route. It rejects skipped/backward/duplicate edges, failed synthetic prerequisites, missing backup verification, a second finalization switch, and all rollback edges. `AllowedInModel=true` is **not** an operational authorization and every result keeps all six permission flags disabled.
- In the same module: `New-F2V4FakeAuthority`, `Invoke-F2V4FakeReservation`, `Set-F2V4FakeCheckpoint` and `Compare-F2V4FakeCheckpoint`. These are **mutations of a newly allocated PowerShell hashtable in process memory only**; they have no trusted clock, signatures, persistent storage, atomic cross-process CAS, external replay protection or credentials. They model one simulated initial INSTALL, an independently approved finalization/recovery operation sharing the transaction ID, idempotent same approval, rejection of conflicting receipts and detection of a locally restored older checkpoint prefix. Their outputs always say `CanMutate=false` and `Durable=false`, including reservation success.
- `docs/reviews/f2-g1-v4-transaction-design/CONFORMANCE_FACTS.SourceOnly.json`: **92 manually authored synthetic input fixtures** `T01`–`T92`, with only domain/condition/boolean facts, **no expected state or classification and no executable command**. Scenarios T54/T56/T88 explicitly distinguish absent vs present local transaction root; T86 asserts `SignatureValidated=true` as a hypothetical simulated fact but does NOT perform cryptographic verification.
- `scripts/f2-acl/Test-F2TransactionConformance.V4.SourceOnly.ps1`: Windows PowerShell 5.1 harness which reads the reviewed `ACCEPTANCE_MATRIX.json` as an **independent output oracle**, reads the synthetic facts, imports ONLY the new model, and asserts exactly 92 covered IDs, each state/disposition match, zero operational permission flags, exact 19-state map, and immutable fixtures. Adds negative checks against injected verdict fields, missing/unknown facts, contradictory local root, spoofed signature-as-rollback authorization, postwrite authority failure, replayed IDs/transaction/environment/target, stale generations, separate finalization and restored journal checkpoint. It independently checks all normal modeled journal edges and the three finalization-evidence edges, plus regressions/skip/duplicate/no-approval/rollback failures.
- This README and the parent-to-head Git diff document the new isolated harness.

## Review/test command (non-elevated, read-only)

Use a **fresh clean detached worktree** on the exact new branch SHA, Windows PowerShell 5.1, with no production release installed or touched by this harness. Only this command is permitted for the immediate Codex review:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2TransactionConformance.V4.SourceOnly.ps1
```

Audit parsing of the module and harness first. Reviewer must count/assert every T01–T92; inspect that no case is hardcoded by ID inside the evaluator and the expected fields come from the independently approved design matrix, not the synthetic facts. Check every fake authority outcome, legacy v2/v3 production-cutover exclusion, rollback rejection even when `SignatureValidated=true`, and zero real filesystem writes, child processes, ACL/UAC, protected manifests, `File.Replace`, updater/recovery, CI or VM/G: accesses. Document any PowerShell 5.1 exception and the first falsifying case. Output of the test is **NOT YET EXECUTED on Windows**.

## Scope and integrity caveats

This is an **abstract classifier**, not a JSON signature verifier, parser for journal bytes, installed package inventory attestation, executable bootstrap, storage operation, recovery agent or filesystem fault-injection harness. A fixture `Condition` such as `DuplicateField` or `NoncanonicalBytes` **asserts** those failures; it does not reproduce raw bytes or challenge a real parser. A fake authority reservation/checkpoint is not a signed receipt, independently monotonic or crash-durable. That distinction is intentional for the first small milestone and must not be represented as full production contract validation.

There is no supported v2/v3 production cutover, installer or rollback in the R3 architecture. The ten-member v4 contract and historical v1/v2 pins must remain byte-identical. The proposed separately versioned installable v5 manifest and real bootstrap/keys/remote authority/storage crash tier require separate future approval and independent tests.

**Acceptance boundary:** A passing Windows review can accept only this abstraction's taxonomy/fixture coverage/in-memory replay semantics. It cannot establish package integrity, signed receipt authorization, real state-machine journal durability, late reader quiescence, Windows crash safety, or production release readiness. Keep `F2_G1_RELEASE_HOLD`, PRs #73/#74 draft and no CI/merge/protected operations.
