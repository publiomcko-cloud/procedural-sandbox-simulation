# F2 G1 — Independent transaction architecture R2 review: BLOCKED_WITH_EVIDENCE

**Independent reviewer:** Codex on Windows, owner-provided report. Recorded as a source-only review note by ChatGPT on 2026-10-15. No executable tests, protected filesystem operations, GitHub CI, production releases or Windows UAC were run for this architecture review.

**Repository origin:** `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`  
**Reviewed HEAD:** `d47970d89ad002d206639bbf3cf7acc088ac7127`  
**Direct parent:** `bbf001bc5a91c7b38289b31e2725aabde46a9499`  
**Branch:** `design/f2-g1-v4-transaction-architecture-r2`  
**Evidence:** clean detached Windows checkout; exactly four documentation paths in diff, parent ancestry and `git diff --check` PASS.

| Artifact | Git blob ID | Codex Windows checkout SHA-256 |
|---|---|---|
| `docs/decisions/ADR-0004-F2-G1-V4-TRANSACTION-BOUNDARY.md` | `fba4da3d31caebbf205da3186554940bbc66143a` | `7cb58cf2857b922dd7680dd62fff6d1df672c3e16c2271eacd811f0952f1061f` |
| `docs/reviews/f2-g1-v4-transaction-design/CONTRACT.md` | `1389667405930b5205c1a53cedf50c2ed5573146` | `8be00da50b25388b5c39f56aa2aebea25cacb520b8e6c5a9ad46e23221c164cb` |
| `docs/reviews/f2-g1-v4-transaction-design/ACCEPTANCE_MATRIX.json` | `1c57f577a4111d50b0fcf076be9c31512d89ed85` | `04e1a3370cc5ef846041a54df9923fc85c992eca96be12ba66b7cdcb752b26c8` |
| `docs/reviews/f2-g1-v4-transaction-design/INDEPENDENT_REVIEW_BLOCKED.md` (R1 historic evidence) | `e76058272f24d56c1316a122a87a18ee13c9bbfa` | `0ba310688e90ecbfcc5b2df3a5ac12ae6019e6e48b2e1ae16f8c2565f588cd7b` |

## Accepted direction, distinct from approval

The reviewer recognized: the ten-member v4 source-only manifest remains noninstallable; historical v1/v2 pin bytes are immutable; a proposed separately pinned installable v5 manifest avoids the old manifest/hash conflict; the external signed receipt avoids self-hash cycles. Trust bootstrap, ApprovalId/TxId replay reservation, publish/backups/switch journaling, and non-switching FINALIZE_POST_SWITCH improved substantially at specification level. **None of this is production approval.**

## Four design blockers

1. **No provable supported legacy cutover.** v2 does not cooperate with the v3 lease; direct/late readers and inaccessible process metadata can bypass an inventory. R2 described a possible maintenance environment but no closed, enforceable entry/exit and launch-inhibition procedure. Safe decision: either define/prove one or explicitly exclude all production v2/v3 cutovers.
2. **Matrix inspection_state not closed.** `PRECONDITION_UNMET` and `OBSERVATION_ONLY` existed in the 85-case matrix but not the contract's allowed-state table; `REJECTED_RECEIPT` was overloaded with bootstrap-policy and authority-unavailable failures.
3. **T56 mislabeled partial genesis.** R2 `REMOTE_RESERVED_NO_LOCAL` also described a **present** transaction root with absent/torn genesis. These must be distinct states even though both default to HOLD_PRESERVE.
4. **ROLLBACK operation listed but unsupported.** Signed operation enum included ROLLBACK, although no transaction-v4 rollback semantics existed; there was no explicit reject-only positive-looking signed rollback test.

## Other review concerns, deliberately preserved

- **Threat model & proportionality:** an external online mTLS authority for time/revocation/replay and nonrollback ledger is feasible but substantial for a single host. Owner must decide whether privileged local journal restore/rollback attacks are in scope. If excluded, a lower-complexity model may be considered under a new weaker assurance statement.
- **Windows App Control:** machine-wide policy applies to all users; signed policy tamper protection includes Secure Boot/reboot and RSA policy signatures, separate from candidate ECDSA receipt signing. PowerShell 5.1 App Control script enforcement/ConstrainedLanguage vs FullLanguage must be reviewed for bootstrap/verifier modules.
- **ReplaceFileW:** same-volume replacement does not imply universal all-or-nothing behavior under every API failure; documented errors may alter final file names and REPLACEFILE_WRITE_THROUGH is unsupported. Exhaustive actual readback and crash-tier guarantees are unproved.
- **Journal:** canonical bytes, hash domain, bound values, authority idempotence and recovery-forward sequence remain future coding decisions after architecture gates.

## Proposed bounded R3 response (NOT INDEPENDENTLY REVIEWED)

A new isolated design-only branch `design/f2-g1-v4-transaction-architecture-r3` proposes (a) **NO production v2/v3 cutover**, with later separate cutover ADR; (b) complete closed `inspection_state` enum and one-to-one mapping to nonmutating `expected_classification`; (c) distinct `LOCAL_ROOT_GENESIS_INCOMPLETE` state; (d) **ROLLBACK reject-only** even with otherwise valid signed-looking receipt; (e) explicit threat model and synthetic-only process-crash tier A; (f) normalized and expanded acceptance matrix from **85 to 92 scenarios** with zero default mutation.

No owner decisions are presumed: real signer/bootstrap/key policy, online authority, trusted time, antirollback threat scope, device enforcement, a production supported storage crash tier, and a future launch-inhibited v2/v3 cutover require separate approval and tests.

**Review disposition:** `R2_BLOCKED_WITH_EVIDENCE / R3_DESIGN_REVIEW_PENDING / RELEASE_HOLD`. The R1 `INDEPENDENT_REVIEW_BLOCKED.md` and original R2 source commit remain unchanged.
