# Current status — 2026-10-17

**Last verified GitHub `main`: `2f86c42503cfa3a334215b1ff5b9bf9658263440`**, source-reviewed and owner-approved PR #90 lighting merge. This status is prepared in docs-only PR #87 (DRAFT / NOT MERGED) and may be superseded by live GitHub data. See [checkpoint index](../checkpoints/INDEX.md) and [recovery runbook](../workflow/AGENT_RECOVERY.md).

## Accepted integrations

- PR #78 SDF terrain/caves `ff6eae5407321261a59d47ab0151230ded0993bb`.
- PR #80 ordered transient carve/fill `455fe9e7eecce0fd365b4c7da5eefa6f26fbf18f`.
- PR #82 localized 16-chunk remeshing `817fc72cd85d5de66932d2aa722d1b077d55bf92`.
- PR #85 memory/recovery docs `a7391fa7eafe55c9b38888249b3eaafbf03da9a9`.
- PR #86 P1.0A static 3×3 regions `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0`.
- PR #88 P1.0B dynamic bounded region loading `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`.
- PR [#90](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/90) lighting corrected, `2f86c42503cfa3a334215b1ff5b9bf9658263440`, reviewed head `9a5cb4f36c2066c8aabb031cf10c1c5ca41489b2`; owner GUI accepted **for visual prototype**. Developer Godot 4.7.2 reports 7,947 assertions; reviewer did not execute Godot, GitHub hosted CI static-only.

## Prepared next (not yet implemented)

[P1.0C Issue #91](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/91) — globally ordered edits crossing adjacent and unloaded regions, loss-free bounded memory replay, atomic multi-region rebuild and edited seam tests. Prepared feature branch `feat/p1-0c-global-cross-region-brushes` from `2f86c42503cfa3a334215b1ff5b9bf9658263440`. **No implementation authorization yet, no CodeX started in this step.** Owner next decides whether to approve this scope or adjust global operation ledger/reset policy.

## Remaining risks and holds

- Lighting [Issue #89](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/89) completed/closed; scene still has cave stippling and darker average cave luminance in submitted capture; shadows disabled.
- P1.0B possible retry stall when failed load has unchanged focus and canonical edit/mesh divergence on failed partial remesh; synchronous slice peak >16.67 ms. Not demonstrated fixed by lighting.
- Future multiplayer-compatible data structure is a design constraint, not networking; persistence, LOD, collision, simulation, phase P0 backend decision unresolved; ADR-0002 proposed only.
- F2-G1 holds remain `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`, unrelated PRs #75/#76/#77 untouched.
- Single Windows workspace `C:\Dev\sandbox-sim-dev`, inspect status before any branch change; keep prior local CRLF/untracked screenshot state intact unless user approves cleanup. Documentation PR #87 is still draft, not authorized to merge.

Read [PR #90 checkpoint](../checkpoints/2026-10-17-PR90-MERGE.md), [next planning checkpoint](../checkpoints/2026-10-17-P1-0C-PREPARED-ISSUE91.md), [decision register](../decisions/DECISION_REGISTER.md) and live GitHub refs before resuming.
