# Documentary checkpoint index — project recovery

**Check live GitHub refs before action**; each checkpoint is a dated immutable evidence snapshot, never a real-time claim. A draft document is not merged or approved.

| Date | Checkpoint | Event | Publication state at creation |
| --- | --- | --- | --- |
| 2026-10-17 | [CHK-2026-10-17-P1-0A-KICKOFF](2026-10-17-P1-0A-KICKOFF.md) | Merged functional PRs #78/#80/#82; authorized ongoing P1.0A #84 | Draft docs PR #85, not yet integrated |
| 2026-10-17 | [CHK-2026-10-17-CHECKPOINT-CADENCE-DECISION](2026-10-17-CHECKPOINT-CADENCE-DECISION.md) | Owner mandates post-merge and **other significant-interaction** checkpoints | Draft docs PR #85, not yet integrated |
| 2026-10-17 | [CHK-2026-10-17-P1-0A-SOURCE-REVIEW-PR86](2026-10-17-P1-0A-SOURCE-REVIEW-PR86.md) | PR #86 SHA-specific source review PASS; user GUI still pending | Recorded in docs PR #85, unmerged |
| 2026-10-17 | [CHK-2026-10-17-P1-0A-OWNER-GUI-OBSERVATION-PR86](2026-10-17-P1-0A-OWNER-GUI-OBSERVATION-PR86.md) | Owner reports "parece tudo ok"; no apparent GUI defect, **no merge authorization** | Recorded in draft docs PR #85, unmerged |
| 2026-10-17 | [CHK-2026-10-17-PR85-MERGE](2026-10-17-PR85-MERGE.md) | Docs/recovery PR #85 verified merged; actual SHA `a7391fa7eafe55c9b38888249b3eaafbf03da9a9` | New docs-only draft PR (post-merge checkpoint) |
| 2026-10-17 | [CHK-2026-10-17-PR86-MERGE](2026-10-17-PR86-MERGE.md) | P1.0A PR #86 verified merged; actual `main` SHA `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0` | New docs-only draft PR (post-merge checkpoint) |
| 2026-10-17 | [CHK-2026-10-17-P1-0B-SOURCE-REVIEW-PR88](2026-10-17-P1-0B-SOURCE-REVIEW-PR88.md) | PR #88 source review PASS with failure-recovery/performance caveats; GUI pending | Recorded in draft docs PR #87, unmerged |

| 2026-10-17 | [CHK-2026-10-17-P1-0B-OWNER-GUI-LIGHTING-CORRECTION](2026-10-17-P1-0B-OWNER-GUI-LIGHTING-CORRECTION.md) | Owner observed streaming works progressively but depth lighting has no noticeable improvement; bounded correction required before GUI acceptance | Draft docs PR #87 / not integrated |

Every verified merge, material review/GUI verdict, scope authorization or revision, blocker, architecture decision or major handoff gets a **new file** and a row here. Keep past checkpoints unchanged after integration. For historical evidence and recovery, start with [CURRENT_STATUS](../status/CURRENT_STATUS.md), [AGENT_RECOVERY](../workflow/AGENT_RECOVERY.md), and [template](../templates/CHECKPOINT_TEMPLATE.md).
