# Project current status — checkpoint 2026-10-17

**Snapshot, not a live branch monitor.** Evidence baseline: repository `publiomcko-cloud/procedural-sandbox-simulation`, verified `main` at `2f86c42503cfa3a334215b1ff5b9bf9658263440` on 2026-10-17 after PRs #85, #86, #88 and #90 merged. **Always check live GitHub `main`, feature PR, issue and working tree before acting.** Earlier P1.0A and P1.0B checkpoints remain frozen; the [P1.0C implementation checkpoint](../checkpoints/2026-10-17-P1-0C-IMPLEMENTATION.md) records this authorized slice.

## Accepted integrated functional results

| PR | Owner decision and independently reviewed deliverable | Exact merge commit | Evidence boundary |
| --- | --- | --- | --- |
| [#78](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/78) | SDF single-region terrain, cave section, orbit/zoom, green lighting; visual PASS | `ff6eae5407321261a59d47ab0151230ded0993bb` | Corrective head `44d920c9bcbdf9d602512a48f83e1c8fa4f3643a`; local Godot tests reported; hosted CI static |
| [#80](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/80) | Ordered transient carve/fill, viewport picker, C/R/X, mesh regeneration; visual PASS | `455fe9e7eecce0fd365b4c7da5eefa6f26fbf18f` | Reviewed head `f2a16d7fe9dc6e564e91bc6c4b4dee3bfb8ec774`; **186** developer-reported assertions |
| [#82](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/82) | 4×4 = 16 finite-region chunks, localized rebuild, boundary tests; visual PASS | `817fc72cd85d5de66932d2aa722d1b077d55bf92` | Reviewed head `be5ac506e4ac4a10f8fd683a72a766cac7134b07`; **375** developer-reported assertions |
| [#85](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/85) | Durable status/checkpoint/recovery documentation | `a7391fa7eafe55c9b38888249b3eaafbf03da9a9` | Documentation-only merge; no product runtime evidence |
| [#86](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/86) | P1.0A 3×3 region ownership, 144 chunks, negative coordinates and seam tests | `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0` | Reviewed feature head `27b911e32ea396be6c66436542473093123e1b54`; 7,917 developer-reported Godot assertions; owner GUI/merge evidence is recorded in its PR/checkpoints |
| [#88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88) | P1.0B bounded camera-driven region streaming | `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb` | Source reviewed and owner GUI gate recorded separately |
| [#90](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/90) | P1.0B terrain depth lighting correction | `2f86c42503cfa3a334215b1ff5b9bf9658263440` | Lighting checkpoint is integrated; visual result applies to its recorded owner retest |

[SHA-specific source-review and owner GUI evidence index](../reviews/2026-10-17-P0-1-FUNCTIONAL-ACCEPTANCE-EVIDENCE-INDEX.md) records the exact GitHub review/comment links for PRs #78, #80 and #82.

Owner explicitly authorized each merge after source and GUI approval. Runtime counts and timing are developer-provided; ChatGPT inspected source and reports, **not** an independent Godot Windows execution. GitHub "Starter checks" only checks project structure. At PR #82 local benchmark, seven-run median full mesh ~525–537 ms and localized ~44/88/194 ms for 1/2/4 affected chunks; not a full-frame or scaling guarantee.

## Active, authorized — implementation prepared, pending review and owner GUI

- **P1.0C / Issue #91:** owner explicitly authorized globally ordered transient carve/fill across streamed region seams on `feat/p1-0c-global-cross-region-brushes`, based on `2f86c42503cfa3a334215b1ff5b9bf9658263440`. Source commits `33710924db224cf63dbb54b5aba378956be8c45a` and `71fbe678c7f6a24b2aa0f0b7813d30e154a2f9bc` are in draft PR [#92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92); local Godot 4.7.2 validation passed 8,042 assertions. Independent source review and owner GUI acceptance remain pending. See the [P1.0C checkpoint](../checkpoints/2026-10-17-P1-0C-IMPLEMENTATION.md). No merge or release is implied.

## Spatial contract retained after P1.0A

Version 1 `SdfWorld` logical regions are 16×12 world units, divided into 4×4 chunks with half-open cell ownership and shared sampling planes. P1.0A is merged in PR #86; the generator contract and global Z=6 visualization cut remain unchanged. P1.0B supplies bounded streaming; P1.0C adds one globally ordered in-memory edit ledger whose commands replay in any affected resident region. No disk persistence or networking is part of P1.0C.

## Decisions and deferrals

- Binding product scope: [PROJECT_CHARTER](../PROJECT_CHARTER.md), [ADR-0001](../decisions/ADR-0001-BASELINE.md). [ADR-0002](../decisions/ADR-0002-TERRAIN-BACKEND-PROPOSED.md) is **proposed**, not adopted. No final terrain backend has been selected and full Phase 0 gates (comparative backend, durable save, mods, simulation) have not passed.
- Multiplayer: future architectural compatibility desired (stable region keys, canonical ordered edits, rendering not authoritative), but multiplayer **not part of initial release or active slice**. No networking is implemented.
- Persistence, LOD, collision, background worker execution, entity/simulation/mod contracts and cross-platform bit-identical replay remain unproven. P1.0B/P1.0C use bounded incremental main-thread work; they do not claim asynchronous meshing or a frame-time guarantee.
- F2-G1 protected-host/native-addon operations remain **on hold** pending independent environment/protected-state validation; no implied elevation, ACL updates or VM access from this functional track. PRs [#75](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/75), [#76](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/76), [#77](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/77) were not part of any of these merges. The 2026-10-08 F2 report is archived at [historical snapshot](archive/2026-10-08-F2-PREPARATION-STATUS.md), **not** current live environment certification.

## Next authorized action and handoff

**Owner:** after source review, visually test seam/corner edits, stream-out/reentry, reset, and preserved lighting; separately authorize any merge. **Independent reviewer:** inspect the exact P1.0C PR HEAD and test evidence. **Codex:** no further implementation is authorized by the current P1.0C scope; leave persistence/networking deferred.

For any new agent: [recovery runbook](../workflow/AGENT_RECOVERY.md), [decision register](../decisions/DECISION_REGISTER.md), and the dated [P1.0C implementation checkpoint](../checkpoints/2026-10-17-P1-0C-IMPLEMENTATION.md).

## Additional documentation decision, 2026-10-17 — checkpoint cadence

The owner explicitly requires **a documentary checkpoint after every merge or other significant project interaction**. The protocol was merged in PR #85 (`a7391fa7eafe55c9b38888249b3eaafbf03da9a9`). The later P1.0A merge and P1.0B authorization are recorded in the [P1.0B checkpoint](../checkpoints/2026-10-17-P1-0B-AUTHORIZATION.md) and [checkpoint index](../checkpoints/INDEX.md).
