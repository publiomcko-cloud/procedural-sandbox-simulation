# ADR-0004 — F2 G1 transactional v4 boundary and immutable source-pin generations

**Status: PROPOSED — DESIGN ONLY / NOT APPROVED FOR IMPLEMENTATION OR RELEASE.**
**Proposed on:** 2026-10-15 (America/Sao_Paulo).
**Decision owner:** project owner; requires an explicit future approval of this architecture.
**Source parent:** `b044e517c46e8f8d95bb5d8d4bc1225f6459fe84`.
**Related:** ADR-0003 (temporary workflow), `docs/reviews/f2-g1-release-v4-source-contract/README.md`, `docs/status/F2_G1_ACTIVE_HANDOFF.md`.

## Problem discovered in the actual source

The historic installed v2 release is pinned to commit `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1`, active manifest SHA-256 `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9`, and seven exact installed files. The current production updater's `Get-F2UpdateManifestObject` accepts only `v2`/`v3` with an exact seven-member set; `Test-F2UpdateInstalledOldRelease` verifies the historical old state; its recovery logic recognizes the old manifest, candidate v3 and a legacy journal. The runtime, coordinator and launcher still dispatch v3. Draft PRs #73/#74 are unmerged and v3 must not be presumed installed.

The accepted source-only `f2-icacls-runtime-release-v4` contract is **ten** exact package files, including the immutable historical v1 and independently reviewed v2 pin manifests, and `Status=SOURCE_ONLY_NOT_RELEASE_APPROVED`. Those v2 manifests bind the **existing** source module hashes. If we edit production runtime/coordinator/collector but keep these v2 manifests byte-for-byte immutable, a new internally consistent package cannot pass its own nested pins. Reusing the source-only v4 contract as an installable manifest would falsely imply approval and produce identity contradictions.

## Proposed resolution

1. **Freeze the present ten-member v4 as SOURCE_ONLY.** Keep its exact reviewed source/manifest/pins separate from anything installable. Never mutate the old v1/v2 manifest bytes, retained v2/v3 receipts, or signed source history.
2. **Version the new installable runtime contract independently.** Preferred schema: `f2-icacls-runtime-release-v5` after new production code and a new source-pin generation (`*_V3.json` if names are approved). Its exact inventory and cardinality are **not yet frozen** and cannot be assumed to equal the current ten-member v4 set. The version name is a proposal, not an approved schema or an attempt to silently change the existing v4 meaning.
3. **Version the transactional protocol separately:** `f2-protected-update-transaction-v4`. It can describe authorized transitions to an approved future installable manifest without reinterpreting legacy `transaction.ndjson`. State machine, receipt, sealed package and recovery must agree on *one* immutable manifest digest and exact predecessor identity.
4. **No trust-inference from self-generated fixture hashes.** Install authorization must be an independently authenticated signature/approval over exact manifest bytes, allowed predecessor, installed executable hashes and transaction-protocol version. Select and independently review a concrete offline signature suite, pinned verifier implementation, trusted key and rotation/revocation policy before implementation; do not claim a signature scheme exists today.
5. **Privilege boundary: no Git execution in an elevated installer.** Complete Git/source inspection in a separate non-elevated stage; seal and hash exact package bytes and pass only an independently approved signed receipt plus a trusted, already verified fixed package. Under elevation, independently recheck package bytes, identity, ACL, process quiescence and locks. The source-only pre-dispatch runner's residual `Process.Start()` and descendant-process limitations are not inherited as production guarantees.
6. **Never auto-repair ambiguous post-switch states.** Recovery begins in read-only inventory. Only exact permitted states with matching durable evidence may be considered for explicit, separately authorized forward or rollback actions. Default is HOLD/PRESERVE with no deletion or mutation.

## Alternatives evaluated

- **A: add `v4` to updater `ValidateSet` and raise 7→10. Rejected.** Breaks historical installed-state validation, source pin generation, journal recovery states and the v3 pinned dispatch; falsely treats source-only approval as release approval.
- **B: rewrite old v1/v2 manifests to include changed runtime bytes. Rejected.** Destroys original historical evidence and contradicts frozen pin provenance.
- **C: keep the v4 source-only contract and introduce separately versioned production manifest + transaction protocol. Preferred.** Makes migration explicit, preserves old releases, allows source-only review and owner-gated release authorization.
- **D: bypass the manifest/pin checks for an initial v4 install. Rejected.** Weakens the very protection being tested and opens silent mixed-version states.

## Formal approval gates before the next operational stage

The specification `docs/reviews/f2-g1-v4-transaction-design/CONTRACT.md` details the interface and state transitions. The proposed source-only scenario matrix is `ACCEPTANCE_MATRIX.json`; it is **an oracle for future reviewers**, not an executed test or approved installer. Required future owner decisions: (a) choose final installable manifest schema and exact source-pin inventory; (b) select independently verifiable signature/key scheme and release signer; (c) approve the intended predecessor(s) by exact manifest digest (v2 known; v3 only after verified installed evidence); (d) independently validate journal/recovery/fault injection; (e) separately authorize any production mutation, PR, CI, UAC or deployment.

The current ChatGPT–GitHub author / Codex–Windows independent-verifier arrangement under ADR-0003 remains **temporary for this blocked F2 G1 cycle**. On explicit owner-recorded closure the original Codex implement+commit → ChatGPT independent review → owner decision model resumes.

**Disposition:** `PROPOSED_V4_TRANSACTION_DESIGN / NO_INSTALLER / NO_RELEASE_APPROVAL / F2_G1_RELEASE_HOLD`.
