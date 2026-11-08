# Roadmap with implementation gates

## 2026-11-08 — M4.0 integrated; P4.0A fixed-tick candidate

M4.0 PR #256 is integrated at `ca13d91a4917e8061528736e5b6d808dc9b85576`.

P4.0A issue #257 is implemented on `feat/p4-0a-fixed-tick-scheduler` as a qualification candidate.

P4.0A scope is deliberately limited to the engine-owned scheduler foundation:

- deterministic logical tick identity;
- integer-microsecond cadence;
- bounded ticks admitted per frame;
- scalar deferred catch-up backlog;
- pause/resume;
- bounded manual step;
- authoritative scheduler snapshot/restore;
- playable `SimulationRuntime` scene mount;
- opt-in `simulation_scheduler_frame` PERF_TRACE evidence.

No material/environment state, active/aggregate/dormant tiers or gameplay simulation systems are introduced in this slice.

The scheduler preserves ADR-0007's engine/content boundary and ADR-0008's bounded-work rule. Future simulation data must use M4.0 content handlers when such data is introduced.

**Current gate:** P4.0A owner-local Godot 4.7.2 qualification.

**Blocked until P4.0A qualification/integration:** later P4 tier/state slices.


## 2026-10-25 — P3.0C persistent transactional entity history candidate

The P3.0C candidate on `feat/p3-0c-transactional-undo-redo`, draft PR [#121](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/121), adds explicit schema-3 persistent history and revision-checked `ENTITY_UNDO`/`ENTITY_REDO` through the existing P2.0B state store. It preserves exact pre-delete overrides (including F7), keeps F9 as baseline restore with reversible prior state, and requires explicit schema migration. Full Godot 4.7.2 validation passed 18,153 assertions/0 failures; developer headless evidence only. See [spec](../specs/P3-0C-TRANSACTIONAL-PERSISTENT-UNDO-REDO.md), [ADR-0006](../decisions/ADR-0006-PERSISTENT-ENTITY-UNDO-REDO.md), and [checkpoint](../checkpoints/2026-10-25-P3-0C-IMPLEMENTATION.md). Independent source review and owner GUI retest remain gates; do not merge. All five F2-G1 holds remain.

## 2026-10-25 — Issue #118 R1 optional-root API hardening

Source `f0164b140009bb797951aa4085bb36001889bc57` on the existing Issue #118 branch enforces optional-root eligibility inside the loader. Only the exact canonical `user://mods` root can receive undeclared-child handling; caller-provided first-party, example, descendant and prefix roots are rejected. The pre-fix downgrade was reproduced on an isolated fixture. Focused and full Godot 4.7.2 validation passed 18,047 assertions/0 failures. PR #119 remains open/draft; exact-HEAD Starter checks pass (static only); independent R1 review and owner GUI retest remain pending. See [R1 checkpoint](../checkpoints/2026-10-25-ISSUE-118-OPTIONAL-ROOT-API-HARDENING.md). No merge or schema change is authorized; F2-G1 holds remain.

## 2026-10-25 — Issue #118 mod discovery correction candidate

On branch `fix/issue-118-mod-discovery-initialization`, source commit `f8edbff0a7bab3ea733b4903611a9e6a5904613c` (parent verified main `fd431dbcad18685a3aa2c86c3c9b25fbd81303c9`) corrects initialization failure when undeclared immediate folders exist under the optional user package root. It preserves strict validation of required roots, declared packages and path safety. Full Godot 4.7.2 headless validation passed 18,040 assertions/0 failures with isolated user data. This is not visual/save acceptance; independent source review and owner GUI retest remain pending. No merge is authorized. See [Issue #118 spec](../specs/ISSUE-118-MOD-DISCOVERY.md) and [checkpoint](../checkpoints/2026-10-25-ISSUE-118-MOD-DISCOVERY-FIX.md). All five F2-G1 holds remain unchanged.

## 2026-10-25 — P3.0B playable transactional entity integration candidate

On branch `feat/p3-0b-playable-world-entity-commands`, source commit `6ce65bbe2f1a54bd1436416b5cb6102c75a09769` connects the P3.0A dispatcher to playable placement, selection, transform/appearance, logical delete and exact restore. It reuses P2.0B persistence and P0.3 definitions; schema-1 object snapshots require explicit two-step migration. Full Godot 4.7.2 validation passed 18,022 assertions with no failures. This remains a draft candidate pending independent source review and owner GUI retest; no merge is authorized. Cross-region object transform, issue #108 terrain conformation, physics/collision, networking, multiplayer, full undo/redo and native dependencies are excluded. See [spec](../specs/P3-0B-PLAYABLE-WORLD-ENTITY-INTEGRATION.md) and [checkpoint](../checkpoints/2026-10-25-P3-0B-IMPLEMENTATION.md).

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

## P2.0C integrated implementation — 2026-10-24

P2.0C modular static population was implemented through PR #112 from main baseline `84bb7c3e573e7aa5a07608aac7834735aeb2c84` and is now integrated; the merge and owner GUI/source acceptance are recorded in [the PR #112 integration checkpoint](../checkpoints/2026-10-24-PR112-P2-0C-MERGE.md). The original candidate validation reported 17,883 assertions/0 failures. It adds data-only population rules, deterministic signed-region generation and bounded rendering/publication. No numeric geometry/performance budget was established. P2.0B identities remain compatible; issue #108, physics/collision, networking and all F2-G1 operations remain outside this slice. See [P2.0C specification](../specs/P2-0C-MODULAR-STATIC-POPULATION.md) and [implementation checkpoint](../checkpoints/2026-10-24-P2-0C-IMPLEMENTATION.md).

## P2 exit assessment / P3.0A candidate — 2026-10-24

Live `main` is `b874991bb0f2cc698e41dd8709f3b0325d73c855`, with P2.0C integrated by PR #112 and its post-merge record in PR #113. P2 now has deterministic declarative procedural object definitions, persistent instance overrides/exclusions and modular static population with bounded streaming publication. This records the state of the implemented foundation, **not a claim that all P2 acceptance criteria or visual quality gates are closed**; terrain/object conformation remains deferred as Issue #108.

P3.0A is an authorized implementation candidate on `feat/p3-0a-entity-command-contract`: strict renderer-independent entity commands, explicit placement identities, optimistic world/entity revisions, durable idempotency receipts and inverse metadata over the P2.0B store, plus an isolated harness. The proposed payload schema upgrade is explicit and does not alter terrain schema-1 saves. Full P3, authenticated permissions, multiplayer, advanced tools and undo/redo remain unimplemented. Source review and owner GUI evaluation are the next gates; no merge is authorized. See the [P3.0A specification](../specs/P3-0A-TRANSACTIONAL-ENTITY-COMMAND-CONTRACT.md), [ADR-0003](../decisions/ADR-0003-TRANSACTIONAL-ENTITY-COMMANDS.md), and [implementation checkpoint](../checkpoints/2026-10-24-P3-0A-IMPLEMENTATION.md). Five F2-G1 holds remain unchanged.

## P3.0A Delete GUI correction — 2026-10-25

Owner-reported GUI failure on PR #114: Delete did not hide the selected explicit entity. A headless `Viewport.push_input` reproduction showed `keycode=KEY_DELETE` was handled and committed the tombstone, while a physical-only `KEY_DELETE` event (`keycode=0`) was ignored by the previous handler. The correction matches either logical or physical key codes, starts the harness empty so two P presses create exactly two objects, and synchronizes visibility from the committed P2.0B state. A rejected repeated Delete preserves both the tombstone and hidden node and reports `entity_already_deleted`. The new scene regression and full suite pass headlessly; the actual OS-window focus and visual interaction still require owner retest. Exact evidence and limits are in the [2026-10-25 correction checkpoint](../checkpoints/2026-10-25-P3-0A-ENTITY-DELETE-GUI-CORRECTION.md). PR #114 remains draft/unmerged; all F2-G1 holds remain unchanged.

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
