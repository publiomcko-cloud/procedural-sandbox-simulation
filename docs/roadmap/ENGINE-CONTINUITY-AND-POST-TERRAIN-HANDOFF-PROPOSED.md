# Engine modularity and post-terrain handoff — continuity guardrails (PROPOSED)

**Date:** 2026-10-21 (America/Sao_Paulo).  
**Status:** `PROPOSED_SEQUENCING / NOT_IMPLEMENTATION_AUTHORIZATION`.  
**Reviewed remote baseline:** `main` `ea4422d90726d3f2fe6d5cef097126268f93685a` (verified PR #98 documentation merge).  
**Governing sources:** [PROJECT_CHARTER](../PROJECT_CHARTER.md), accepted [ADR-0001](../decisions/ADR-0001-BASELINE.md), [architecture](../architecture/ARCHITECTURE.md), [conceptual contracts](../architecture/CONTRACTS.md), [P0 spikes](../specs/PHASE_0.md), [milestones](MILESTONES.md), [P1.1 R2](P1-1-APPROVED-PLAN-R2.md), [B0 owner experiment contract](../specs/P1-1B-B0-OWNER-APPROVED-CONTRACT.md). This document adds explicit continuity criteria, **not** new charter features, an accepted ADR, a final backend decision, a phase-exit declaration, or an owner approval to execute.

## Product identity — guard against a terrain-only detour

The product is an **extensible procedural 3D world and environmental simulation framework** built on Godot, with an authoritative domain model and a graphical player/editor as two clients of the same mutation/interaction rules. Terrain is the first foundational subsystem, **not the product endpoint**. Planned extension domains include procedural entities, physical/material capabilities, user-generated mods, climate/hydrology and later organisms/ecology. Production networking is out of initial scope; **future server-authoritative multiplayer compatibility** is a non-functional design constraint, not a promise of eventual release.

Godot `Node3D`, meshes, colliders, GUI, native terrain backends and asset caches are derived representations, never the sole canonical owner of procedural world identity, modification history, simulation variables or durable state.

## Five interface boundaries that later subsystems must inherit

| Boundary | Preserve / prove later | Not yet implemented |
| --- | --- | --- |
| World identity and durability | Stable wide signed region/entity keys, world ID, seed+generator+schema versions, independent chunk/region ordering; journal+snapshot/transaction recovery and safe migration/missing-mod behavior | Durable multi-session saves, crash/fault-injection guarantees, shared world identity protocol |
| Domain mutations | One validated/versioned command and receipt pipeline with actor, permissions, expected revisions, affected regions, dependency invalidation and replay; controller/editor/mod eventually share this facade | Production-wide command coordinator and permissions; current SDF edit ledger is bounded and transient, **not** a general transaction or server log |
| Procedural objects and mods | Namespaced schema/version registries for object recipes, materials, components/capabilities and hooks; same public facade for first-party content and external declarative mods, privileged-script policy explicit; no terrain vendor APIs in mod contracts | Loadable mod manager, capability registry, arbitrary scripts sandbox, procedural-entity production system |
| Simulation and presentation | Logical fixed ticks, deterministic constrained ordering, active/aggregate/dormant tiers, region snapshot/catch-up, authoritative state independent of rendering, bounded CPU/memory, separately versioned derived GPU/physics caches | Environment V1, ecosystem V2, tiered scheduler/serialization and physics/material coupling |
| Future multiplayer compatibility | Stable actor and command IDs, revisions/conflict semantics, authoritative state-query/read-model, serialization and deterministic boundaries; document where floating-point and cross-platform determinism **cannot** be assumed | Networking, interest management, rollback, replication, hosting, security/anti-cheat, exact cross-platform sync |

**Implementation caution:** current 256-command SDF ledger and transient loaded region snapshots are a **terrain prototype**. They must not be promoted to general-purpose durability, full entity authority, secure mod execution or multiplayer capability without new bounded designs/tests. Mod scripts remain trusted privileged code; the sandbox is a gameplay/world concept, not a security boundary.

## Finish terrain optimization with a bounded exit, not indefinite tuning

The terrain optimization path is **P1.1B benchmarking/architectural decision → separately gated P1.1C integration/optimization → release-quality validation where authorized**. It is not reasonable to claim full P1 completion merely from an isolated LOD cell or one fast CPU benchmark.

Required evidence for a later **owner-defined terrain-stability handoff**:

1. A *reviewed and independently authorized* opt-in B1-1 benchmark harness, then a distinct approved B1-2 run of custom-only scenarios. Current B1-1 [draft PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) is **code awaiting independent source review**; no Godot run or merge is accepted at the time of this document.
2. Reproducible scenarios, input integrity, cold/warm separation, frame/CPU worker queue/ArrayMesh/streaming/edit latencies, distribution sizes and censoring. `UNSCORED` is exploratory evidence only. Do not count CPU scene publication as actual GPU completion or a presented frame.
3. LOD0/LOD1 internal/neighbor watertight seams across signed boundaries and edits; continuity and preservation of required caves and thin features, as judged by an owner-approved geometry oracle. LOD≥2 remains separately gated by region/chunk retiling and geometry needs.
4. Bounded active regions, worker/job caps and memory; stale-result cancellation, command order and replay intact while moving/editing/unloading/reloading. No changes in canonical terrain truth or unexpected playability regressions.
5. Comparative feasibility of Voxel Tools stays separate from installing/running a native component. `ADR-0002` **remains PROPOSED** until evidence and an explicit owner decision. No automatic backend selection based on an isolated benchmark or public docs.
6. Owner-defined hardware/platform/renderer, numerical budgets (FPS/frame p95/p99/max; editor latency; streaming; RSS/VRAM; geometry/normal/cave widths), tests, any GUI owner gate and rollback plan **before claiming optimization acceptance**. No current product thresholds have been approved.

This is a **proposed future exit checklist**, not permission to start P1.1C or claim that LOD is integrated in the playable terrain.

## Next vertical slice: demonstrate the engine, not just the renderer

After the owner accepts an appropriately bounded terrain-stability gate, the **recommended next planning priority** is a small, end-to-end engine-core vertical slice that covers originally planned P0.2/P0.3/P0.4 prerequisites **without renumbering P2–P8** or pretending the still-open Phase 0 exit is complete.

| Bounded proof, in order | Objective and minimum demonstration | Reference / explicit future gate |
| --- | --- | --- |
| **A — Domain persistence and commands** | Save a versioned world/region state plus accepted edit log, close and reopen, verify stable IDs, deterministic restore with reordered region visits, collision on stale revision, and crash-interruption recovery policy | [P0.2](../specs/PHASE_0.md); require independent authorization and fault-injection before durability claims |
| **B — Public mods/definition registry** | Load one genuinely external, namespaced declarative mod defining a procedural object/material using only project-owned facade types, verify dependencies/version mismatches and no silent data loss when absent | [P0.3](../specs/PHASE_0.md), later P2/P3; privileged scripts cannot be called secure/sandboxed |
| **C — First environmental system** | Fixed-tick temperature + soil moisture across two regions, active/aggregate/dormant conversion, save/reopen/catch-up and measured conservation or discontinuity constraints | [P0.4](../specs/PHASE_0.md), later P4/P5; no unrestricted simulation claims |
| **D — End-to-end modularity demonstration** | Edit via player/editor-facing command facade, load declarative external object/material and observe a simulation consequence that survives unload and process restart, with one canonical read/write authority | P2–P6 integrator, to be scoped and budgeted separately |

**Architecture guard:** the terrain adapter must remain swappable beneath stable world/domain/mod interfaces. A networking future should be possible via a server authoritative command/receipt layer; do **not** build network transport, synchronous lockstep, rollback or public hostile-mod sandbox merely because the architecture reserves those boundaries.

## Decision gates and precedence

- Accepted original charter/ADR-0001 and phase exit gates remain binding and **unchanged**.
- P1.1B B0 is owner-approved as **experimental inputs and methodology only**; `NOT_FROZEN` real-click/remote-history/edited-revisit/edited-LOD scoring cases remain excluded.
- Conversation-level owner go-ahead led to **limited B1-1 test-only implementation**, represented by the developer's open, draft [PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) at reported `81392229d93d2829a4a606a8b347baa849df573b`. That does not supply independent code validation, Godot execution, approval of an `UNSCORED` run, merge approval, production terrain change or new dependency authority. Verify actual remote PR SHA before further work.
- P1.1C, selected terrain backend, native Voxel Tools, full P0/P1 completion, production networking and later entity/mod/simulation code each require **separate** owner scope, evidence and review. Protect all five F2-G1 holds.
- This **documentation-only proposal does not freeze priority changes as owner-approved phase exits**; any substantive scheduling change will receive a later owner decision and checkpoint.

**Status:** `ENGINE_VISION_ALIGNED / TERRAIN_STABILITY_GATE_PROPOSED / POST_TERRAIN_VERTICAL_SLICE_PROPOSED / B1_1_SOURCE_REVIEW_PENDING`.
