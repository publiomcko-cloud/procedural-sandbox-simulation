# Project status — P1.0B merged, lighting correction deferred

**Verified GitHub source snapshot:** `publiomcko-cloud/procedural-sandbox-simulation`, `main` `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb` after owner-approved merge of [PR #88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88) on 2026-10-17. **This file is drafted on open docs PR #87, not yet integrated into `main`.** Reverify GitHub live SHA, issues and active Codex workspace before acting.

## Integrated functional and documentary milestones

| PR | Merged SHA | Accepted bounded result |
| --- | --- | --- |
| [#78](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/78) | `ff6eae5407321261a59d47ab0151230ded0993bb` | Finite versioned SDF terrain, caves, camera and section |
| [#80](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/80) | `455fe9e7eecce0fd365b4c7da5eefa6f26fbf18f` | Ordered transient carve/fill |
| [#82](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/82) | `817fc72cd85d5de66932d2aa722d1b077d55bf92` | 16-chunk localized remeshing |
| [#85](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/85) | `a7391fa7eafe55c9b38888249b3eaafbf03da9a9` | Project documentation, recovery protocol, checkpoint policy |
| [#86](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/86) | `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0` | P1.0A static 3×3 world regions, unique ownership and seams |
| [#88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88) | `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb` | **P1.0B dynamic region loading/unloading** with bounds, incremental slice work, limited transient edit retention |

PR #88 reviewed feature head `2e0ecd04aba3bbd1a8c2ba8f915f0c3402ff6a26`; [source review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88#pullrequestreview-5559876793) `PASS_SOURCE_REVIEW_WITH_CAVEATS`; owner GUI [streaming behaved progressively, light visibly ineffective](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88#issuecomment-6240529628). Owner specifically **authorized merge with the lighting issue deferred**, not a full visual PASS. Godot 4.7.2 tests **7,943/7,943** developer reported, GitHub Starter CI static only.

## Active/pending scope and immediate next interaction

- **[Issue #89](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/89) — lighting contrast correction**, prepared remote branch `fix/p1-0b-terrain-depth-lighting` created at `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`. Next interaction only, **not started yet**. Balance high ambient vs oblique directional/key and weak camera spotlight; owner evaluates actual same-pose before/after screenshots. No streaming rewrite.
- **P1.0B robustness caveats:** if a load stage fails with unchanged focus, automatic retry absent; if an edited partial remesh fails, logical edit may temporarily diverge from displayed mesh. These are review risks, not reproduced GUI failures; keep as separately scoped follow-up and explicitly test fault paths before claiming resilient fault handling.
- **[PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87)** draft docs-only checkpoint reconciliation, not authorized to merge merely because #88 merged. Its older branch was reconciled to latest `main` with a Git merge commit preserving all older event records; exact status must be checked live.
- **P1.0C cross-region edits** planned in [Issue #83](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/83), **not implemented or authorized**. No persistence, LOD, collision, multiplayer or final backend ADR-0002 acceptance.
- **F2-G1 holds** continue: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. Never use a lighting/streaming ticket to modify protected VM/ACL/native operations.

## Evidence and performance limits

SDF logical region 16×12; chunk 4×4 per region; requested 3×3 window, completed residency at most 25 regions/400 chunk nodes, vertical slice per frame. Headless initial fill ~9.96s; peak synchronous slice 20.551ms (>16.67ms frame target). No assertion of smooth 60 FPS or total GPU/RAM metric. Reviewers independently inspected source/CI but did not execute owner-host Godot. Check [post-merge checkpoint](../checkpoints/2026-10-17-PR88-MERGE-LIGHTING-DEFERRED.md) for exact owner decision/limits.

## Safe handoff

New agent: read [recovery runbook](../workflow/AGENT_RECOVERY.md), [checkpoint index](../checkpoints/INDEX.md), [decision register](../decisions/DECISION_REGISTER.md), and the current Issue #89. Before using `C:\Dev\sandbox-sim-dev`, inspect its Git status, active Codex ownership, and synchronize with the latest `origin/main` **without discarding changes**. Await owner-mediated start of next lighting interaction; new lighting PR needs source + GUI review and separately authorized merge.
