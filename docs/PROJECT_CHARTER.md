# Procedural Sandbox Simulation — Permanent Project Charter
Accepted product scope dated 2026-10-08. Owner decisions control scope; implementation remains unverified until tested.

## Goal
Build a Godot 3D procedurally generated, endlessly expandable sandbox with persistent editable terrain, cave systems, procedural objects, modding, environmental simulation (V1) and ecology (V2). Both editor/observer and playable character use one authoritative world model.

## Accepted decisions
- Godot 4.7.2 stable initially; seeded versioned and region-order-independent generation.
- Smooth volumetric SDF/voxel terrain; caves and overhangs integral to the world; add/remove/sculpt/material editing; arbitrary selected-volume transform supported as future contract, not an immediate implementation commitment.
- Hybrid 3D geometry from primitive composition, procedural mesh algorithms and deformation; material definitions shared with terrain.
- Identifiable persistent entities with component/capability model; interaction may promote virtual/batched representations to dynamic; no universal live physics objects.
- Hybrid localized destruction; free placement/rotation with optional snapping.
- Finite active simulation region in expandable world; fixed logical ticks; active, aggregate, dormant tiers; persistent dynamic environment states; scenes and meshes not authoritative.
- Declarative mods and trusted scripted mods; first-party content uses the same public interfaces where possible; scripts are privileged, not sandboxed.
- V1: time/day-night, temperature, weather, precipitation/evaporation, moisture, accumulation and approximate surface/underground water flow.
- V2: organism definitions and geometry, resource and energy budgets, growth, reproduction, mortality, populations, interaction networks and environmental feedback.

## Phases
P0 environment baseline + comparative terrain, persistence, mods and simulation spikes. P1 streamed volumetric world. P2 procedural entities. P3 modification and building. P4 multi-resolution scheduler/material simulation. P5 V1 environment. P6 V1 integration/player/editor release. P7 organisms. P8 V2 ecosystem. Detailed exit criteria: docs/roadmap/MILESTONES.md and docs/specs/PHASE_0.md.

## Non-goals for initial releases
Multiplayer; civilizations; crafting/combat; photorealism; fully realistic CFD; unrestricted granular physics; safe execution of hostile script mods; full-fidelity infinite simulation.

## Invariants
Authoritative domain state independent of Godot nodes; validated revisioned commands for mutations; precision-safe spatial addressing; deterministic/versioned generators; explicit mod dependencies and material units; crash-consistent persistence with migration strategy; stale background-result rejection; bounded simulation budgets; tests and evidence before acceptance.

## Open technical decisions
Voxel Tools versus custom adapter, voxel/chunk resolution, identifier format, save journal/checkpoint protocol, hydrological numerics, reproducibility limits, precise threading, numerical/performance budgets, mod scripting privileges, geometry batching. Resolve via benchmarks and new ADRs rather than assumptions.

## Release authority
Codex develops on isolated feature branch; ChatGPT independently reviews remote commits/PRs; owner performs visual tests, approves architectural changes/dependencies, and alone authorizes merges. See docs/workflow/PROJECT_MEMORY_PROTOCOL.md.
