# PR #87 and PR #92 — online documentation reconciliation

**Date:** 2026-10-19. **Event:** owner-authorized documentary consolidation and exact-SHA integration preflight; no merge authorization.

## Starting identity and scope
- Verified `main`: `2f86c42503cfa3a334215b1ff5b9bf9658263440` (after accepted PR #90).
- [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87): documentation-only, `6fad428a22a149624da245e88a5e608d09ed7dd3`, open/draft/unmerged; leave its branch unchanged.
- [PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92): P1.0C code + documents, source-reviewed HEAD `531bae3d5d5770b67e4b7fa4c5c44a8c13249284`, open/draft/unmerged. Extend the **existing PR #92** with a strictly documentation-only commit; do not rewrite the reviewed source commit `f632f7cc06066b690ad7574fe7b92bb306851893`.
- Review evidence: [SHA-specific independent source review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5578386601) and [owner GUI acceptance checkpoint](2026-10-19-P1-0C-OWNER-GUI-ACCEPTANCE-AND-PREFLIGHT.md).

## Reconciliation performed
1. Transplant all **13 distinct immutable checkpoint Markdown files** that exist on #87 but were absent from #92 by reusing their exact Git blobs, byte-for-byte, including the unfavorable historical GUI and independent review findings. No historical receipt is rewritten or erased. The earlier history remains visibly labeled as created on draft PR #87.
2. Preserve all more recent #92 checkpoint documents (P1.0C implementation, normal dependency, worker performance, 256-command history and picker corrections).
3. Union the checkpoint-index rows by target file, with chronological ordering and no lost historical links. Historical “publication state at creation” text remains a historical statement.
4. Preserve the verified #85/#86 merge, earlier P0/F2 source and status ledger. Add the missing PR #88/#90 **actual merged** records from #87 to `docs/status/CHANGELOG.md`. Do **not** insert a #92 integration receipt before an actual merge.
5. Resolve overlap in `README.md`, `docs/status/CURRENT_STATUS.md`, `docs/decisions/DECISION_REGISTER.md` and `docs/roadmap/MILESTONES.md` in favor of newly verified, higher-priority source and owner acceptance facts. Old milestones/checkpoints remain immutable snapshots.
6. Record the source-reviewed, owner GUI PASS handoff separately in `docs/reviews/` and as a new checkpoint. The next source code SHA remains the reviewed `f632f7cc06066b690ad7574fe7b92bb306851893`; no gameplay, Godot resource, test, protected host or P1.1 code changes are included.

## Safe integration order and remaining owner decisions
- **First:** review this documentation-only consolidation, confirm branch fast-forward ancestry and that PR #92 remains draft/open/mergeable, rerun/verify any required checks, then request explicit owner **merge authorization for #92**. Do not infer that this request grants it.
- **After owner-authorized #92 merge:** verify the actual `main` merge SHA, document it in a fresh post-merge checkpoint and `CHANGELOG`, update status and issue disposition only when authorized.
- **Then:** re-evaluate #87. Its unique historical documents will already be present after #92 integrates. #87's shared files contain stale snapshots that must not overwrite newer `CURRENT_STATUS`, roadmap or decisions. Recommend marking #87 superseded/closing **only after separate owner approval**, without merging the obsolete competing versions or deleting its preserved Git history. If a genuine unique delta remains, reconcile it explicitly.
- No GitHub PR, branch or issue closure, PR #87 update, F2-G1 action, Git history rewrite, or `main` mutation occurs in this documentary preparation.

**Disposition before owner integration decision:** `DOCUMENTATION_RECONCILED_ON_DRAFT_PR92 / HISTORICAL_RECEIPTS_PRESERVED / NO_MERGE`. Verification must be based on the actual published document commit and SHA, not this preparatory wording alone.
