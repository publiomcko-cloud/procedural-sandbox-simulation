# Project current status — checkpoint 2026-10-19

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

- **P1.0C / Issue #94:** source correction `f632f7cc06066b690ad7574fe7b92bb306851893` (parent reviewed HEAD `dd1b2d75569444a49200c996873a86e81479767f`) is prepared on `feat/p1-0c-global-cross-region-brushes` in the same draft PR [#92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92). It adds concentrated same-region mouse histories and a bounded SdfWorld v1 adaptive empty-space picker that resumes the legacy fixed grid before the first surface crossing; the generic picker API remains fixed-step. Full-vs-filtered sample values and legacy-vs-adaptive surface checks passed. In five-repeat headless local profiles, worst-layout picker end-to-end p50/p95 improved from 28.989/51.618 ms to 1.598/3.034 ms at 255 operations; at 128 it improved from 17.730/22.391 to 1.046/1.186 ms. The local mesh transaction remains slower and variable: p95 reached 244.319 ms and visible publication p95 248.249 ms at 255 operations, with frame p99/peak up to 95.864 ms in that level. Full `scripts/validate.ps1` passed 10,366 assertions on Godot `4.7.2.stable.official.ed1daf0bf`. See the [long-history checkpoint](../checkpoints/2026-10-19-P1-0C-ISSUE94-LONG-HISTORY.md), [review-correction checkpoint](../checkpoints/2026-10-19-P1-0C-ISSUE94-REVIEW-CORRECTIONS.md), and [local-history picker checkpoint](../checkpoints/2026-10-19-P1-0C-ISSUE94-LOCAL-PICKING.md). Independent exact-SHA review and owner GUI acceptance remain pending; no visual acceptance, merge or release is implied.

**Documentation reconciliation:** docs-only PR [#87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87) was rechecked on 2026-10-19 and remains open/draft/unmerged at head `6fad428a22a149624da245e88a5e608d09ed7dd3`. This P1.0C checkpoint is on PR #92's branch; PR #87 was not modified. Its overlapping status/index snapshot must be reconciled deliberately before either branch is integrated.

## Spatial contract retained after P1.0A

Version 1 `SdfWorld` logical regions are 16×12 world units, divided into 4×4 chunks with half-open cell ownership and shared sampling planes. P1.0A is merged in PR #86; the generator contract and global Z=6 visualization cut remain unchanged. P1.0B supplies bounded streaming; P1.0C adds one globally ordered in-memory edit ledger whose commands replay in any affected resident region. No disk persistence or networking is part of P1.0C.

## Decisions and deferrals

- Binding product scope: [PROJECT_CHARTER](../PROJECT_CHARTER.md), [ADR-0001](../decisions/ADR-0001-BASELINE.md). [ADR-0002](../decisions/ADR-0002-TERRAIN-BACKEND-PROPOSED.md) is **proposed**, not adopted. No final terrain backend has been selected and full Phase 0 gates (comparative backend, durable save, mods, simulation) have not passed.
- Multiplayer: future architectural compatibility desired (stable region keys, canonical ordered edits, rendering not authoritative), but multiplayer **not part of initial release or active slice**. No networking is implemented.
- Persistence, LOD, collision, entity/simulation/mod contracts and cross-platform bit-identical replay remain unproven. P1.0C now uses bounded CPU worker meshing with main-thread-only ArrayMesh construction/publication; this does not claim a GPU upload completion time or a frame-time guarantee.
- F2-G1 protected-host/native-addon operations remain **on hold** pending independent environment/protected-state validation; no implied elevation, ACL updates or VM access from this functional track. PRs [#75](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/75), [#76](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/76), [#77](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/77) were not part of any of these merges. The 2026-10-08 F2 report is archived at [historical snapshot](archive/2026-10-08-F2-PREPARATION-STATUS.md), **not** current live environment certification.

## Next authorized action and handoff

**Independent reviewer:** inspect the final exact PR #92 SHA, particularly ordered-operation equivalence, the chunk no-op bound, reset semantics, supersession handling, test coverage and the full Godot validation report. **Owner:** then retest sustained edits up to 256, positive/negative and seam/corner edits, rapid region movement, unload/reentry, X/C/R, visible error behavior, lighting and frame hitches in Godot GUI. A source PASS does not certify pixels or owner acceptance. Only a separate explicit owner decision authorizes merge. Persistence/networking remain deferred.

For any new agent: [recovery runbook](../workflow/AGENT_RECOVERY.md), [decision register](../decisions/DECISION_REGISTER.md), and the dated [P1.0C implementation checkpoint](../checkpoints/2026-10-17-P1-0C-IMPLEMENTATION.md).

## Additional documentation decision, 2026-10-17 — checkpoint cadence

The owner explicitly requires **a documentary checkpoint after every merge or other significant project interaction**. The protocol was merged in PR #85 (`a7391fa7eafe55c9b38888249b3eaafbf03da9a9`). The later P1.0A merge and P1.0B authorization are recorded in the [P1.0B checkpoint](../checkpoints/2026-10-17-P1-0B-AUTHORIZATION.md) and [checkpoint index](../checkpoints/INDEX.md).
