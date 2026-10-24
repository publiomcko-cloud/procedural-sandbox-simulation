# Roadmap with implementation gates

**Gating:** Each phase needs developer evidence, independent evaluator ACCEPT, and human visual acceptance if interactive. Numeric budgets are provisional until Phase 0 benchmarking. Order can be split into tickets but dependencies must hold.

| Phase | Core deliverable | Representative acceptance gate |
|---|---|---|
| P0 | Reproducible environment, terrain spike, mod prototype, sim spike and ADRs | Seed+version reproduces base region; edit/load cycle; sample mod extension; measured alternatives and headless smoke |
| P1 | Infinite chunking, caves, materials, stable coordinate model, LOD | No seams at loaded chunk borders; fixed seed independent of visit order; bounded steady-state RAM under benchmark walk |
| P2 | Procedural geometry recipe registry, entities, capabilities | Third-party content defines a deterministic object; stable persistent ID; batched static population |
| P3 | Terrain/entity editing, placements, transformations, destruction | Across-boundary dig/save/restore; same commands via player/editor/mod; revisions reject stale edits; undo/redo |
| P4 | Tick scheduler, tier transitions, materials, environmental state | Deterministic constrained replay; pause/step/catch-up; tier roundtrip conserves required invariants |
| P5 | **V1 environment**: climate, temperature, rain, moisture, water accumulation/flow | Rain changes moisture and flow, digging influences runoff, state survives reload, bounded conservation drift |
| P6 | **V1 release**: both modes, UX, diagnostics, packaging, regression/perf | End-to-end exploratory scenario and external mod smoke; no critical regressions; human signoff |
| P7 | Organism components, geometry, metabolism, sensing and reproduction | Resource- and temperature-sensitive survival; repeatable growth/death; persistence after tier transitions |
| P8 | **V2 ecosystem**: populations, trophic relationships, feedback | Measurable downstream impacts from removing species/resource; no unbounded growth; modded species coexist |

## Milestone exit artifact
For each phase: architecture change summary; exact commit and tests; result log and benchmark configuration; screenshots/video for visuals; known limitations; migration notes; independent evaluator judgment; owner acceptance record.

## Initial non-goals
Multiplayer synchronization, NPC civilizations, crafting/combat loops, photorealism, arbitrarily realistic CFD, full granular fracture physics, unrestricted safe untrusted code execution. Future extensibility is a design constraint, not a promise of implementing all these now.

## Execution checkpoint — 2026-10-17 (does not change phase exit criteria)

The functional P0.1 GDScript SDF prototypes are accepted/merged (PRs #78, #80, #82): one finite region, transient brushes and 16-chunk localized remeshing. Their successful review is **not** acceptance of the complete P0 terrain backend comparison, durable save/mod/simulation spikes, or the full P1 streaming milestone.

P1.0 execution sequence: **P1.0A** [#84](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/84) spatial ownership (**integrated at `7f87c1e9`**) → **P1.0B** bounded streaming and lighting (**integrated at `13d08b8` and `2f86c42`**) → **P1.0C** globally ordered transient cross-region edits (**independent source review and owner GUI PASS at feature HEAD `531bae3d5d5770b67e4b7fa4c5c44a8c13249284`; existing [PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) still draft/unmerged, explicit owner merge decision pending**). This is **not** full P1/P0 completion. Each slice requires source evidence, human interaction signoff where relevant, and separate merge authorization.

See [CURRENT_STATUS](../status/CURRENT_STATUS.md) and [DECISION_REGISTER](../decisions/DECISION_REGISTER.md) for current accepted/proposed distinctions, and [AGENT_RECOVERY](../workflow/AGENT_RECOVERY.md) for a new chat/agent.

## P2.0C candidate — 2026-10-24 (implementation review pending)

P2.0C modular static population is implemented on draft PR #112 from verified main baseline `84bb7c3e573e7aa5a07608aac7834735aeb2c84f`. It adds data-only population rules, deterministic signed-region generation and bounded rendering/publication. Godot 4.7.2 full validation reports 17,883 assertions/0 failures. This is a feature candidate only: independent source review and owner GUI retest remain pending, and no geometry/performance acceptance thresholds were established. P2.0B compatibility identities remain; issue #108, physics/collision, networking and all F2-G1 operations remain out of scope. See [P2.0C specification](../specs/P2-0C-MODULAR-STATIC-POPULATION.md) and [implementation checkpoint](../checkpoints/2026-10-24-P2-0C-IMPLEMENTATION.md).

## P1.1 candidate planning handoff — 2026-10-19 (not implementation authorization)

After an expressly authorized #92 merge and post-merge documentary checkpoint, **propose a scoped P1.1 design/benchmark gate** before new coding. Prioritize objective LOD/multi-resolution streaming, chunk residency and CPU/GPU/scene-publication frame spikes, while preserving canonical SDF ownership, bounded memory, signed seams and exact ordered edits. Separately evaluate materials/terrain representation and the still-proposed ADR-0002 custom-vs-Voxel-Tools backend comparison against original P0/P1 gates. Persistence, collision, material detail and production backend choice remain open; avoid treating full P1 as delivered. Present ranked candidate slices and measured acceptance budgets to the owner for **separate authorization**.

## Owner-approved P1.1 R2 direction — 2026-10-20

The owner approved the [P1.1 R2 plan](P1-1-APPROVED-PLAN-R2.md), including experimental custom LOD 0/1 transition fixtures (P1.1A), independent benchmark/backend comparison (P1.1B), and separately gated potential integration (P1.1C). R2 corrects higher-LOD chunk-grid non-divisibility, requires watertight transition topology not just SDF sample parity, keeps native Voxel Tools subject to F2-G1/ADR-0002 gates and introduces statistically separated benchmark scenarios with pre-agreed budgets. **P1.1A implementation is BLOCKED on an owner-authorized #92 merge/main readback/checkpoint; P1.1B/C and external backend runtime are not authorized** by this decision. See [owner decision checkpoint](../checkpoints/2026-10-20-P1-1-OWNER-PLAN-APPROVAL.md).

## Verified P1.0C completion — 2026-10-20

**Source and owner GUI accepted / merged into `main`:** PR [#92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92), actual merge `9452cefe5788bbbd3a38fedb55773d10ebafb0d2`, parent feature HEAD `7e484c2912de04448726d0a63fbaed39d4fd7b3c`. The older P1.0C “draft/pending” statements above are **historical checkpoint wording**, superseded by this GitHub-verified integration. P1.1 R2 plan was included; the separately prepared [post-merge record](../checkpoints/2026-10-20-PR92-P1-0C-MERGE.md) must be integrated before marking the post-merge handoff complete. Next candidate implementation P1.1A: isolated custom GDScript LOD 0/1 transition fixture only, subject to repository/owner budgets and gates. Do not extrapolate to LOD production, material/collision/persistence approval, P1.1B/C or native backend execution.

## P1.1A verified integration / P1.1B proposed handoff — 2026-10-20

After independent exact-SHA source review [#5588342762](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96#pullrequestreview-5588342762) and explicit owner merge authorization, the bounded P1.1A **CPU-only detached LOD0/LOD1 transition fixture** [PR #96](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96) was integrated into `main` at `aca6b6403c455708cacda01c8fbf0bf980d813a2`. This later verified event supersedes earlier “draft/pending” status statements above without editing their historical meaning. Godot 4.7.2 full-suite results 16,807/0 are **Codex-reported**; hosted CI is static only. See [post-merge checkpoint](../checkpoints/2026-10-20-P1-1A-OWNER-AUTHORIZED-INTEGRATION.md) (docs-only PR until separately merged).

The [P1.1B benchmark/backend feasibility handoff](P1-1B-PLANNING-HANDOFF-PROPOSED.md) is **proposed for owner review only**. It does not authorize installation/execution of Voxel Tools, experimental code, production LOD, P1.1C, or modification of F2-G1 holds. `ADR-0002` remains PROPOSED and all numerical performance/geometry acceptance targets remain unapproved.

## 2026-10-21 — P1.1B-B0 methodology/input scope approved; implementation still gated

Following independent source-only [B0 R4a PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/97#issuecomment-6314241218), the owner approved R4+R4a as **experimental input definitions and proposed benchmark measurement methodology**. [Binding decision](../specs/P1-1B-B0-OWNER-APPROVED-CONTRACT.md) specifies R4a override precedence, source limits, `NOT_FROZEN` exclusions, and owner decisions still `OWNER_TO_DEFINE`. [Checkpoint](../checkpoints/2026-10-21-P1-1B-B0-R4A-OWNER-INPUT-APPROVAL.md).

This is **not** permission to implement B1-1 or run an `UNSCORED` baseline; those each require new explicit authorization. P1.1C, production LOD, native Voxel Tools/ADR-0002 and all protected F2-G1 operations remain blocked. Only further documentary owner-target decisions or a proposed separate scoped B1-1 ticket are presently allowed.
