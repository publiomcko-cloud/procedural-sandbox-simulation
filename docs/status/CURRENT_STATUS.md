# Project current status — checkpoint 2026-10-17

**Snapshot, not a live branch monitor.** Evidence baseline: repository `publiomcko-cloud/procedural-sandbox-simulation`, verified `main` at `817fc72cd85d5de66932d2aa722d1b077d55bf92` on 2026-10-17 after authorized PR #82 merge. **Always check live GitHub `main`, feature PR, issue and working tree before acting.** The dated [checkpoint](../checkpoints/2026-10-17-P1-0A-KICKOFF.md) is intentionally frozen at this gate.

## Accepted integrated functional results

| PR | Owner decision and independently reviewed deliverable | Exact merge commit | Evidence boundary |
| --- | --- | --- | --- |
| [#78](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/78) | SDF single-region terrain, cave section, orbit/zoom, green lighting; visual PASS | `ff6eae5407321261a59d47ab0151230ded0993bb` | Corrective head `44d920c9bcbdf9d602512a48f83e1c8fa4f3643a`; local Godot tests reported; hosted CI static |
| [#80](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/80) | Ordered transient carve/fill, viewport picker, C/R/X, mesh regeneration; visual PASS | `455fe9e7eecce0fd365b4c7da5eefa6f26fbf18f` | Reviewed head `f2a16d7fe9dc6e564e91bc6c4b4dee3bfb8ec774`; **186** developer-reported assertions |
| [#82](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/82) | 4×4 = 16 finite-region chunks, localized rebuild, boundary tests; visual PASS | `817fc72cd85d5de66932d2aa722d1b077d55bf92` | Reviewed head `be5ac506e4ac4a10f8fd683a72a766cac7134b07`; **375** developer-reported assertions |

[SHA-specific source-review and owner GUI evidence index](../reviews/2026-10-17-P0-1-FUNCTIONAL-ACCEPTANCE-EVIDENCE-INDEX.md) records the exact GitHub review/comment links for PRs #78, #80 and #82.

Owner explicitly authorized each merge after source and GUI approval. Runtime counts and timing are developer-provided; ChatGPT inspected source and reports, **not** an independent Godot Windows execution. GitHub "Starter checks" only checks project structure. At PR #82 local benchmark, seven-run median full mesh ~525–537 ms and localized ~44/88/194 ms for 1/2/4 affected chunks; not a full-frame or scaling guarantee.

## Active, authorized — not yet accepted

- **P1.0A only:** [Issue #84](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/84), fixed static 3×3 adjoining logical regions, unique cell ownership, cross-region seam proofs, central-safe controls. Owner authorized 2026-10-17; Codex executing in **`C:\Dev\sandbox-sim-dev`** on `feat/p1-0a-multiregion-spatial-ownership`, created from `817fc72cd85d5de66932d2aa722d1b077d55bf92`.
- This checkpoint does **not** assert an implementation SHA, a PR, passing tests or visual acceptance for P1.0A. Obtain the latest developer handoff and independently review the actual GitHub commit when Codex finishes; owner performs GUI test before a separate merge decision.
- **Plan only:** [Issue #83](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/83), P1.0B bounded dynamic region loading/unloading and P1.0C globally ordered cross-region edits. Neither slice is authorized for coding by the P1.0A instruction.
- **Independent parallel documentation repair:** `docs/recovery-checkpoint-2026-10-17` branch, separate from the active Codex branch. This snapshot must not be assumed integrated until its docs PR is reviewed and actually merged.

## Spatial issue currently being corrected by P1.0A

Version 1 `SdfWorld` logical region size 16×12, but PR #82 demo mesher covers X -1..17, Z -1..13 (18×14). Copying it to neighbor regions would duplicate render cells. P1.0A is tasked with half-open logical-region cell ownership, shared samples, aligned transforms and seam/corner tests, **without changing the authoritative generator contract silently**. P1.0A is not yet a demonstrated 3×3 feature.

## Decisions and deferrals

- Binding product scope: [PROJECT_CHARTER](../PROJECT_CHARTER.md), [ADR-0001](../decisions/ADR-0001-BASELINE.md). [ADR-0002](../decisions/ADR-0002-TERRAIN-BACKEND-PROPOSED.md) is **proposed**, not adopted. No final terrain backend has been selected and full Phase 0 gates (comparative backend, durable save, mods, simulation) have not passed.
- Multiplayer: future architectural compatibility desired (stable region keys, canonical ordered edits, rendering not authoritative), but multiplayer **not part of initial release or active slice**. No networking is implemented.
- Persistence, LOD, collision, async streaming, entity/simulation/mod contracts and cross-platform bit-identical replay remain unproven.
- F2-G1 protected-host/native-addon operations remain **on hold** pending independent environment/protected-state validation; no implied elevation, ACL updates or VM access from this functional track. PRs [#75](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/75), [#76](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/76), [#77](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/77) were not part of any of these merges. The 2026-10-08 F2 report is archived at [historical snapshot](archive/2026-10-08-F2-PREPARATION-STATUS.md), **not** current live environment certification.

## Next authorized action and handoff

**Codex:** finish Issue #84 in the existing workspace/branch, open one draft PR, report exact parent/head, tests, limitations and owner GUI steps; **do not merge**. **ChatGPT:** source-review new HEAD against charter/specs and verify GitHub refs; distinguish headless from GUI evidence. **Owner:** visually validate 3×3 continuity and decide whether to merge. Do not initiate P1.0B or P1.0C without new explicit authorization.

For any new agent: [recovery runbook](../workflow/AGENT_RECOVERY.md), [decision register](../decisions/DECISION_REGISTER.md), [dated checkpoint](../checkpoints/2026-10-17-P1-0A-KICKOFF.md).

## Additional documentation decision, 2026-10-17 — checkpoint cadence

The owner explicitly requires **a documentary checkpoint after every merge or other significant project interaction**. Consequential approvals/changes of scope, source/GUI review verdicts, blockers, architecture changes and major handoffs count even when there is no merge. See [event checkpoint](../checkpoints/2026-10-17-CHECKPOINT-CADENCE-DECISION.md), [index](../checkpoints/INDEX.md) and [revised protocol](../workflow/PROJECT_MEMORY_PROTOCOL.md). These additions are recorded on **open draft PR #85, not yet merged**; they do not authorize merging #85 or the P1.0A work.
