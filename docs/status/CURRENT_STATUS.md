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

## 2026-10-18 — P1.0C PR #92 exact-SHA independent source review

Codex opened [draft PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) for Issue #91, exact reviewed HEAD `608b7d6d621d0b340454f84c00a9ad7bb0379317` based on current `main` `2f86c42503cfa3a334215b1ff5b9bf9658263440`. Codex reports 8,042 Godot 4.7.2 assertions PASS; hosted CI static only. [Independent source review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5562602003) found one source acceptance blocker: **mesh dirty fanout omits adjacent regions whose surface normals sample across the region boundary even when the accepted sphere's physical support remains on the near side**. Verdict `CHANGES_REQUIRED_FOR_ACCEPTANCE / OWNER_GUI_PENDING / NOT_MERGED`. See the [dated checkpoint](../checkpoints/2026-10-18-P1-0C-INDEPENDENT-SOURCE-REVIEW-PR92.md). PR #92 and documentation PR #87 remain draft/unmerged and overlap on status/index files; do not auto-merge either. Codex should fix the region-level normal-dependency halo on the same PR, re-run tests and request new exact-SHA review. Older P1.0C planning-only lines above are historical and superseded by this actual draft implementation handoff; **no merge approval** is implied. All five F2-G1 holds remain unchanged.

## 2026-10-18 — P1.0C PR #92 correction source rereview PASS

On [draft/unmerged PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92), exact feature HEAD `163ef37a1ec0aab33dfea773a4176fae470161d8`, source correction `ad9997b2deaf285d01e360bb7f7adb9d0f03ba41` closed the previous normal dependency fanout blocker. [Independent SHA-specific rereview #5563949929](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5563949929) verdict: `PASS_SOURCE_REREVIEW / OWNER_GUI_PENDING / NO_MERGE`. Canonical `support_regions`, conservative normal-sampling `dependency_regions` and `rebuild_regions` are distinct. Codex reports pinned Windows Godot 4.7.2 full suite 8,083 assertions/zero failures and import/startup; hosted CI static only, independent reviewer did not execute Windows Godot. Owner next tests seams/near-seam one-sided edits, streaming unload/reentry and focused X, then separately decides merge. Both PR #92 (functional) and [#87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87) (docs only) remain draft/unmerged; reconcile overlapping docs before merges. [Recovery checkpoint](../checkpoints/2026-10-18-P1-0C-PR92-NORMAL-DEPENDENCY-REREVIEW-PASS.md). All F2-G1 protected holds remain.

## 2026-10-18 — P1.0C owner GUI performance FAIL supersedes source-only PASS

The owner reports carve/fill clicks are unacceptably slow and initial/new region streaming takes too long on Godot GUI. On source-reviewed feature [PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) at `163ef37a1ec0aab33dfea773a4176fae470161d8`, the fixed one two-cell Y slice/frame across ten slices/chunk imposes a large schedule delay even without CPU processing. Owner now requires near-instant edits and meaningful streaming speedup **before acceptance/merge**. [Issue #93](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/93) was created to profile and optimize on the **same PR**, retaining all P1.0C geometry correctness/ledger/seam and residency safety contracts. The earlier source rereview PASS is unchanged as evidence of correctness but GUI gate is `OWNER_GUI_PERF_FAIL / PERFORMANCE_CORRECTION_REQUIRED / NO_MERGE`. See [dated checkpoint](../checkpoints/2026-10-18-P1-0C-OWNER-GUI-PERFORMANCE-BLOCKER-PR92.md) and [PR #92 comment](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#issuecomment-6252754343). Docs-only PR #87 and feature PR #92 remain draft/unmerged; do not launch P1.0D or protected F2-G1 operations under this scope.

## 2026-10-18 — P1.0C Issue #93 worker optimization source review PASS, owner GUI pending

[Draft/unmerged PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) advanced to reviewed HEAD `6d128e3d231aa0456c42cf06e9e60f5a861d59df`; implementation commit `69a168eb6fe2a42f3fd6cb40024f86ed50634c2b` replaces one main-thread slice/frame with max four bounded CPU-only worker chunk jobs and max two ArrayMesh constructions/frame. [Independent exact-SHA review #5564956018](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5564956018): `PASS_SOURCE_REVIEW_WITH_PERFORMANCE_CAVEATS / OWNER_GUI_PERF_RETEST_PENDING / NO_MERGE`. Codex reports Godot 4.7.2 8,133 assertions PASS; hosted GitHub CI is static only. Developer reports ~9.93→1.08sec cold nine-region load (~9.2×), interior click p50/p95 54.9/61.8ms and seam click 54.7/75.5ms **to scene commit only**, not rendered pixels. Bulk same-frame mesh publication and GPU/hitch performance remain unconfirmed. [Issue #93](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/93) remains open pending owner interactive acceptance. [Documentary checkpoint](../checkpoints/2026-10-18-P1-0C-PR92-PERFORMANCE-SOURCE-REVIEW-PASS.md). Previous owner GUI performance FAIL remains historical and is **not superseded by source-only PASS**. Both PRs #92 and #87 remain draft/unmerged; all F2-G1 holds unchanged.
