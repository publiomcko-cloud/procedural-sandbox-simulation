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

P1.0 proposed order: **P1.0A** [#84](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/84) fixed 3×3 region geometry and seam ownership (**integrated at `7f87c1e9`**) → **P1.0B** bounded dynamic load/unload (**owner-authorized for implementation on 2026-10-17; source review and owner GUI pending**) → **P1.0C** globally ordered edits across regions (**deferred**), tracked in [#83](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/83). Each requires its own independent review, owner GUI gate where relevant and separate merge authorization.

See [CURRENT_STATUS](../status/CURRENT_STATUS.md) and [DECISION_REGISTER](../decisions/DECISION_REGISTER.md) for current accepted/proposed distinctions, and [AGENT_RECOVERY](../workflow/AGENT_RECOVERY.md) for a new chat/agent.


## Next prepared P1.0C slice (2026-10-17)

P1.0A regions (#86), P1.0B streaming (#88) and lighting (#90) are integrated into `main` `2f86c42503cfa3a334215b1ff5b9bf9658263440`. [Issue #91](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/91) plans globally ordered canonical sphere edits crossing loaded/unloaded region boundaries and corners with atomic mesh staging and in-memory replay. **Do not implement until separate owner authorization.** No change to phase acceptance criteria, final backend ADR, persistence or initial-release multiplayer non-goal.
