# F2 G1 — R3 transaction architecture independent source-only review PASS

**Independent review disposition:** `V4_TRANSACTION_DESIGN_REVIEW_PASS` at the **specification level only**.  
**Recorded:** 2026-10-15 (America/Sao_Paulo) from the owner's Codex Windows review report.  
**Source repository:** `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`  
**Reviewed branch:** `design/f2-g1-v4-transaction-architecture-r3`  
**Immutable reviewed HEAD:** `c15b6440f91fe363b7bc1be7bf24b59229c3e402`  
**Direct parent:** `d47970d89ad002d206639bbf3cf7acc088ac7127`  
**Earlier lineage:** `bbf001bc5a91c7b38289b31e2725aabde46a9499` → `b044e517c46e8f8d95bb5d8d4bc1225f6459fe84`.

The independent reviewer used a fresh, clean detached Windows worktree at the exact Git HEAD. ChatGPT separately confirmed on GitHub the branch ref, direct parent, the four-path documentation-only diff and relevant source blob identities; ChatGPT did not execute the Windows validation. No production code, historical pin or v4 source-only contract changed in this review.

## Codex-reported provenance

| Exact artifact | Git blob SHA-1 | Windows checkout SHA-256 |
|---|---|---|
| `docs/decisions/ADR-0004-F2-G1-V4-TRANSACTION-BOUNDARY.md` | `77e7f79860421860e3c6a206edf402acfefa42d8` | `bf7bad041485012840d7f2b42f2d61dafcd07ec7b2e4da5a1afe08e1e6d25a4e` |
| `docs/reviews/f2-g1-v4-transaction-design/CONTRACT.md` | `e1ad553ea41a71e8ba33e37433fe857810b8b0c2` | `569dbadc4e887b2d635cc255ab74604694103b9f8c2d5feee497cad55c56cbda` |
| `docs/reviews/f2-g1-v4-transaction-design/ACCEPTANCE_MATRIX.json` | `382e2014fc080dcf927c83be3e9e08b0467912bc` | `1a082fc5958e9a38defde3db91f1499f77e6dab6e82ae107b771f5c07d87c85f` |
| `docs/reviews/f2-g1-v4-transaction-design/INDEPENDENT_REVIEW_R2_BLOCKED.md` | `aa223d41cf74c33e8405171f4f2ccda9c7ee703b` | `c458c55a221e0e225e2fbc647c00b234e0fc1a4ccabe2ea2ab729961a2521fe4` |

The retained R1 blocked report remains unchanged: blob `e76058272f24d56c1316a122a87a18ee13c9bbfa`, Windows checkout SHA-256 `0ba310688e90ecbfcc5b2df3a5ac12ae6019e6e48b2e1ae16f8c2565f588cd7b`. The R2 blocked report remains historical evidence, not a retroactive PASS.

## Exact R2 blocker closure in R3

1. **No supported real cutover.** ADR-0004 and CONTRACT explicitly exclude live and maintenance-mode v2/v3 migration, including when an apparent signed receipt is present. No supported production predecessor or operational operation is declared. Real cutover requires a new, owner-approved ADR and verified launch inhibition / quiescence. This is a correct fail-closed restriction, **not an implemented migration path**.
2. **Closed inspection-state taxonomy.** The independent Windows PowerShell JSON parse and checks found all `T01`–`T92` exactly once, **92** cases, **19** mapped inspection states, exact contract/matrix agreement, classification only among `REJECT_BEFORE_WRITE`, `HOLD_PRESERVE`, `OBSERVE_ONLY`, and all `default_mutation_allowed=false`. T25/T26/T31 are consistent.
3. **Genesis states separated.** T54 is `REMOTE_RESERVED_NO_LOCAL` when remote reservation exists but no local root exists. T56 and T88 are `LOCAL_ROOT_GENESIS_INCOMPLETE` when a local root exists but genesis is absent/torn/partial. Both hold; their different observations cannot be conflated.
4. **Rollback reject-only.** `ROLLBACK` is absent from accepted transaction-v4 operation set. T84 rejects INSTALL-receipt misuse. T86 rejects ROLLBACK even with otherwise authentic receipt; classification `UNSUPPORTED_OPERATION / REJECT_BEFORE_WRITE` before any write.

**Nonblocking implementation-oracle wording improvement:** T86 currently says "Correctly signed-looking". Before turning the matrix into executable tests, make it explicitly say the signature has been **cryptographically verified and all other receipt fields are valid**. This suggestion does not change the reviewed R3 SHA, the PASS disposition, or the invariant that rollback is always rejected. Do not silently edit the reviewed R3 blobs.

## Remaining unimplemented owner-controlled prerequisites

The architecture PASS does NOT choose or provision Windows App Control / Secure Boot / key custody / independent verifier bootstrap. Signed App Control policy and candidate receipt signatures use distinct identities and roles; Windows PowerShell 5.1 policy/script enforcement and ConstrainedLanguage/FullLanguage must be tested with the eventual modules. The proposed online authority for revocation, trusted time, monotonic reservation and replay prevention is coherent but not built; it may leave safe-but-stranded reservations. Whether privileged local-state rollback is in scope, or a weaker local-only design may be accepted, remains the owner's security decision.

Only simulated process-exception/termination tier A on nonprotected temporary/in-memory fixtures is in scope for the first contract harness. No OS crash/reboot (tier B), power/storage failure (tier C) or production File.ReplaceW guarantee is established. The design requires exact file name/backup readback and HOLD_PRESERVE for ambiguous API outcomes. No independently authenticated source/release receipt, future v5 package pin generation, supported production predecessor, installer, recovery or cutover exists as a consequence of this review.

**Minor formatting observation:** Codex reported `git diff --check` whitespace warnings at lines 5–8 of the R2 report due to Markdown hard-break formatting. This is not a transaction-design defect; preserve the exact reviewed report bytes until a separately scoped docs formatting correction, if desired.

## Next safe execution boundary and explicit authorization

The review permits recommending a **new separately authorized**, bounded implementation milestone: a source-only pure contract/state-machine conformance harness and a fake approval authority, using only in-memory and temporary **nonprotected** fixtures. Exercise T01–T92 and classify errors through the closed enum, with zero real filesystem transaction/manifest switch authority. Do **not** call File.ReplaceW, access protected roots, launch updater/recovery, alter ACLs, execute CI, use VM/G:, or declare Windows crash durability.

Owner approval of this implementation milestone is **not supplied by an independent design PASS**. The separate decisions about trust policy, external authority, storage tier, installable v5 identity and any future supported v2/v3 cutover remain pending. Existing temporary workflow (ChatGPT–GitHub bounded source author, Codex–Windows independent review, owner for protected/architectural decisions) remains in force until explicitly closed.

**Status:** `R3_ARCHITECTURE_REVIEW_PASS / PRODUCTION_CUTOVER_UNSUPPORTED / PURE_HARNESS_OWNER_AUTHORIZATION_PENDING / F2_G1_RELEASE_HOLD`. No CI, PR, merge or elevated operation has been authorized by this document.
