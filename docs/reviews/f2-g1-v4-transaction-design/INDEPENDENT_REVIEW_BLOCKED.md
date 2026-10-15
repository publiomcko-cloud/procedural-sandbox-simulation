# F2 G1 — Independent architecture review: original proposal BLOCKED

**Review scope:** original immutable HEAD `bbf001bc5a91c7b38289b31e2725aabde46a9499` at `design/f2-g1-v4-transaction-contract-source-only`; parent `b044e517c46e8f8d95bb5d8d4bc1225f6459fe84`.
**Disposition:** **BLOCKED_WITH_EVIDENCE** from owner-supplied independent Codex architectural review. This is not a Windows test verdict or approval to implement.
**Recorded by:** ChatGPT in design-only GitHub change; did not execute any protected source or CI.

## Source identity and exact reviewed artifact evidence

Codex reported a new detached clean checkout of `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`, exact HEAD `bbf001bc5a91c7b38289b31e2725aabde46a9499`, parent and three-document-only diff. `git diff --check` passed; no source files were modified and no updater, recovery, protected filesystem or CI ran.

| Reviewed path | Git blob SHA-1 | Codex Windows checkout SHA-256 |
|---|---|---|
| `docs/decisions/ADR-0004-F2-G1-V4-TRANSACTION-BOUNDARY.md` | `67d9a8a68260562920600c7a21014181a07d4053` | `a4a243b6982672a01ad6cc954018426dcfd61cb1b5673051b0e8f4c69bfa439e` |
| `docs/reviews/f2-g1-v4-transaction-design/CONTRACT.md` | `d9e9286ca9c500842be5a3311a86c5e307652386` | `c31c86e0d7f3235fdda1fd3e2c4b1b28cea68676cdc1ca9bd420c556a585d8d5` |
| `docs/reviews/f2-g1-v4-transaction-design/ACCEPTANCE_MATRIX.json` | `7893992628a861c218f8b8bf0e006f6979fe111b` | `1f11a45561711c7b175508e49d00b67d8fdc58f587bc64e0b3bd8057fd3a1b77` |

## Accepted strategic direction; not an architecture pass

Keep historical v1/v2 pins and historical v2/v3 receipts immutable. Source-only v4 remains the accepted ten-file noninstallable contract. A separately versioned installable manifest (v5 proposed), new pin generation and independently signed receipt avoid source-commit self-hash cycles. Existing updater only recognizes v2/v3 seven-member manifests and uses a legacy journal; historical v2 runtime has no shared lease, whereas reviewed v3 runtime introduced lease use. A live v2-to-new cutover needs an independently proven launch-inhibition mechanism and cannot be justified by merely reusing v3 updater locking.

## Blocking findings and bounded design response (not independently reviewed yet)

1. **Trust bootstrap incomplete.** The original receipt referred to verifier hashes without an independent way to trust the verifier/bootstrap, key provisioning/rotation, revocation or offline time. **R2 proposal:** independently enforced OS code integrity and preprovisioned pinned bootstrap/verifier/config (outside the candidate), plus online authority as the trusted time/revocation/replay source. **Unapproved:** operator-supplied initial key/policy provision, signer/certificate wire format, Windows enforcement evidence and authority ownership. Receipt never self-attests.
2. **Replay not bound to transaction.** Original ApprovalId/epoch did not bind exact TxId or durable one-time consumption. **R2:** signed (ApprovalId, TxId, environment, predecessor, target, operation, expected generation), atomic external reservation before ANY local write, externally anchored monotonic ledger/checkpoints, no offline mutation; identical retry observation-only, new signed operation-specific receipts for recovery.
3. **Journal ordering incomplete.** No publish intent before directory rename, predecessor backup pre-switch state or remote-reservation/genesis gap. **R2:** explicit REMOTE_RESERVED_NO_LOCAL, GENESIS, STAGE_INTENT, PUBLISH_INTENT, PACKAGE_PUBLISHED, BACKUP_INTENT, BACKUP_DURABLE, SWITCH_INTENT, active readback and durable postcheck/commit; two independent backup artifacts and same-volume GUID check. OS/power-loss durability tier remains an owner design gate.
4. **Post-switch transaction cannot finish.** R1 had target-active with missing switch marker but no completion operation. **R2:** inspection yields NEW_ACTIVE_VERIFY_ONLY_CANDIDATE; new signed/ledger-reserved FINALIZE_POST_SWITCH can only append missing evidence after exact target/dual backup checks, with **no second File.Replace**.
5. **Quiescence under-specified.** Historical v2 no lease and late direct PowerShell launches remain possible. **R2:** default NO LIVE v2->new cutover; verified OS-enforced maintenance/launch inhibition required. v3 online migration only after independent discovery and OS-enforced broker gate. Unknown process metadata, late launches, stale handle or cached manifest ⇒ HOLD_PRESERVE.
6. **38-case matrix incomplete and inconsistent.** R1 T25/T26 mixed candidate descriptors with dispositions. **R2:** distinct inspection_state versus default expected_classification fields (only REJECT_BEFORE_WRITE/HOLD_PRESERVE/OBSERVE_ONLY), normalized T25/T26/T31, expanded to 85 zero-mutation scenarios including signature, replay, journal-prefix rollback, backup, finalize, late readers and crash fault boundaries.

## Remaining not-yet-approved design decisions

**Do not label R2 architecture reviewed or accepted.** Independent review is required at its own exact SHA. Before implementation the owner must explicitly approve or revise: (a) platform trust bootstrap and signer/key provisioning, (b) online replay authority and recovery during outage, (c) exact approved storage crash tier and atomic filesystem primitives, (d) feasible Windows v2 maintenance isolation and v3 broker coverage, (e) v5 package schema/cardinality/new pins and supported predecessors. No keys, signer, OS policy, authority, installed v5 package, transaction executor or backup/recovery code exist through this design.

The unchanged original blocked verdict remains historical evidence. Keep `F2_G1_RELEASE_HOLD`; no CI, PR, merge, UAC, installer, protected writes, VM/G: access or production activation.
