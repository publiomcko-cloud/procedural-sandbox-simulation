# Architecture v1.0 — authoritative design

## Principles
1. The authoritative domain model is independent from `Node3D` and rendering assets.
2. World generation is pure/versioned where possible: `(world_seed, generator_version, region_key, parameters) -> base fields + placements`.
3. Mutations pass through commands with validation, revision checks, invalidation, persistence and events.
4. World is spatially unbounded but only a finite working set is simulated in full fidelity.
5. Physical and visual representation are separate: not every generated stone needs a scene node or rigid body.
6. First-party content exercises the same registry/mod contracts as external mods.
7. An executable mod is trusted code, not a security sandbox.

## Domain layers
- **Storage/identity:** 64-bit or wider chunk coordinates; stable world seed, world UUID, entity IDs; persistent material registry and version identifiers. Avoid precision loss: chunk-relative float transforms for visual rendering, integer domain positions.
- **Terrain:** smooth signed distance field with material channels. `density > 0` solid is the proposed sign convention; document adapter conversion if backend uses opposite sign. Chunks possess revision numbers; caves are simply voids of the same terrain representation.
- **Entities:** definition ID, recipe seed, persistent transform, sparse component state and capability identifiers. Instances can be virtual, batched, active or dynamic.
- **Geometry:** primitive composition, generated meshes and deformable subparts; recipes are derived artifacts, not authority.
- **Commands:** selected volumes or entity IDs, actor/permissions, inputs, preconditions, affected regions, atomicity rules and completion receipts.
- **Simulation:** fixed logical tick, region schedulers, dependency graph, bounded catch-up, explicit conservation/invariant budgets.
- **Persistence:** generator manifest + per-region snapshots/dirty state + append-only edit/event log where useful, checkpoint/compaction, migration gate. Seed+edits alone insufficient for evolving environment.
- **Mod registry:** namespaced IDs, schemas, declared hooks, dependency ordering, version negotiation, install security policy. Native scripts are privileged.
- **Presentation:** Godot scene nodes spawned only for active/visible representatives; editor and player invoke identical mutation API.

## Resolution of architectural tensions
- **Infinite vs stateful:** generate beyond horizon on demand; simulate nearby details, distant aggregates, dormant region snapshots. Quantify mass/energy conservation errors at tier boundaries.
- **Transform terrain volumes:** brush translation is not the same as arbitrary solid selection transformation; full cut/copy/paste and resampling are later advanced operations. Reserve contract now.
- **Every object interactable:** all entities can report capabilities, but may report none. Virtual instances can be promoted to persistent entities when interacted with.
- **Hybrid destruction:** whole-object state changes first; optional precomputed procedural fragments and localized physics as a capability; avoid perpetual debris simulation.
- **Save determinism:** deterministic base generation + versioned, saved dynamic state; cross-platform bitwise reproducibility is a research target, not a blanket guarantee.
- **Caves & water:** underground space is integrated; V1 hydrology approximate and bounded, not full computational fluid dynamics.

## Threading ownership
Background workers compute immutable data and buffers; main thread integrates scene nodes and relevant Godot resources safely. Tag results with region revision and discard obsolete publications after edits/unloads.

## Open engineering decisions
Voxel Tools vs custom terrain adapter; chunk span/voxel resolution; SDF quantization; stable ID encoding; hydrology numerical scheme; snapshot/event policy; GDScript script mod scope; geometry rendering backend. Resolve with ADR + prototype evidence, not intuition.
