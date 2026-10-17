# Documentary checkpoint index — project recovery

**Verify live GitHub `main` and PR heads before action.** Each checkpoint is a historical SHA-specific snapshot, not live status or automatic authority. Original checkpoints retain their original "draft" status as the factual publication status at time of creation.

| Date | Checkpoint | Event | Publication state at creation |
| --- | --- | --- | --- |
| 2026-10-17 | [CHK-2026-10-17-CHECKPOINT-CADENCE-DECISION](2026-10-17-CHECKPOINT-CADENCE-DECISION.md) | Owner mandates post-merge and **other significant-interaction** checkpoints | Draft docs PR #85, not yet integrated |
| 2026-10-17 | [CHK-2026-10-17-P1-0A-KICKOFF](2026-10-17-P1-0A-KICKOFF.md) | Merged functional PRs #78/#80/#82; authorized ongoing P1.0A #84 | Draft docs PR #85, not yet integrated |
| 2026-10-17 | [CHK-2026-10-17-P1-0A-SOURCE-REVIEW-PR86](2026-10-17-P1-0A-SOURCE-REVIEW-PR86.md) | PR #86 SHA-specific source review PASS; user GUI still pending | Recorded in docs PR #85, unmerged |
| 2026-10-17 | [CHK-2026-10-17-P1-0A-OWNER-GUI-OBSERVATION-PR86](2026-10-17-P1-0A-OWNER-GUI-OBSERVATION-PR86.md) | Owner reports "parece tudo ok"; no apparent GUI defect, **no merge authorization** | Recorded in draft docs PR #85, unmerged |
| 2026-10-17 | [CHK-2026-10-17-PR85-MERGE](2026-10-17-PR85-MERGE.md) | Docs/recovery PR #85 verified merged; actual SHA `a7391fa7eafe55c9b38888249b3eaafbf03da9a9` | New docs-only draft PR (post-merge checkpoint) |
| 2026-10-17 | [CHK-2026-10-17-PR86-MERGE](2026-10-17-PR86-MERGE.md) | P1.0A PR #86 verified merged; actual `main` SHA `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0` | New docs-only draft PR (post-merge checkpoint) |
| 2026-10-17 | [CHK-2026-10-17-P1-0B-AUTHORIZATION](2026-10-17-P1-0B-AUTHORIZATION.md) | Owner authorizes P1.0B dynamic region streaming and camera-aligned visibility correction | Recorded on P1.0B feature branch; not integrated |
| 2026-10-17 | [CHK-2026-10-17-P1-0B-IMPLEMENTATION](2026-10-17-P1-0B-IMPLEMENTATION.md) | P1.0B implementation and local Godot 4.7.2 validation recorded; independent review and owner GUI retest pending | Recorded on P1.0B feature branch; draft PR publication pending |
| 2026-10-17 | [CHK-2026-10-17-P1-0B-SOURCE-REVIEW-PR88](2026-10-17-P1-0B-SOURCE-REVIEW-PR88.md) | PR #88 source review PASS with failure-recovery/performance caveats; GUI pending | Recorded in draft docs PR #87, unmerged |
| 2026-10-17 | [CHK-2026-10-17-P1-0B-OWNER-GUI-LIGHTING-CORRECTION](2026-10-17-P1-0B-OWNER-GUI-LIGHTING-CORRECTION.md) | Owner observed streaming works progressively but depth lighting has no noticeable improvement; bounded correction required before GUI acceptance | Draft docs PR #87 / not integrated |
| 2026-10-17 | [CHK-2026-10-17-PR88-MERGE-LIGHTING-DEFERRED](2026-10-17-PR88-MERGE-LIGHTING-DEFERRED.md) | P1.0B PR #88 merged SHA `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb` with failed lighting goal explicitly deferred to Issue #89 | New post-merge checkpoint in draft PR #87 |

| 2026-10-17 | [CHK-2026-10-17-PR90-LIGHTING-SOURCE-REVIEW](2026-10-17-PR90-LIGHTING-SOURCE-REVIEW.md) | PR #90 exact-SHA lighting source/image review passed with cave and stippling caveats; owner GUI pending | Open docs PR #87; not integrated |

New checkpoint after each verified merge and consequential owner decision, source-review/GUI gate, blocker and agent handoff. A checkpoint in an open docs PR **has not been integrated** merely because the associated code was merged. Read [current status](../status/CURRENT_STATUS.md), [agent recovery](../workflow/AGENT_RECOVERY.md) and [template](../templates/CHECKPOINT_TEMPLATE.md).
