# P2.0A Mod-First Procedural Objects

## Scope and authority

This slice adds two deterministic, static procedural-rock instances per successfully published terrain region to the playable terrain demo. Definitions remain data-only packages loaded by `DeclarativeModLoader` and registered by `ContentDefinitionRegistry`. Both package sources use the same registry, recipe evaluator, placement-record builder and geometry adapter. The mod system does not load scripts.

This is a bounded first vertical slice. It does not add entity persistence, physics, collision, destruction, networking, biome hooks, arbitrary mod scripts, or a generalized ECS. ADR-0002 remains proposed; the custom SDF and the new mesh adapter are not a final backend selection.

## Package discovery

Runtime discovery always includes the bundled `res://mods/first-party` root and the authorized `user://mods` installation root. The source-tree example root at `<repository>/mods/examples` supplies the external example for source checkouts. If a valid `official.example.procedural_rock` package is already registered from `user://mods`, the repository example root is omitted for that run so the same namespaced package is not discovered twice. Other user-installed data-only packages are registered in the same deterministic P0.3 order.

The runtime requires `firstparty.core_rocks:granite` and `official.example.procedural_rock:basalt_stack`. Discovery, schema, dependency, duplicate-ID and engine-version failures are surfaced in the terrain HUD; a required definition is never silently substituted. The existing P0.3 loader remains the sole package validator and does not execute package content.

## Domain records and deterministic placement

`ProceduralObjectWorld` is a node-independent builder. It produces exactly two slot records for a region, one for each required definition. Placement and recipe seeds are derived from the saved world seed, SDF generator v1 and signed region coordinates using bounded integer arithmetic; region traversal order and global random state are not inputs.

Each record contains a stable object ID, definition ID, content pin (package version and definition schema), world ID and seed, generator version, signed region key, integer-millimeter region-local position, explicit placement and recipe seeds, `stacked_spheres_v1` recipe version, and an empty optional `instance_state` boundary. The region-local X ranges are separated by slot and remain inside the 16-unit region; Z candidates remain inside the 12-unit region. Each slot has at most 12 deterministic candidate attempts.

For each candidate, the builder samples the canonical `SdfWorld.sample_density` v1 field from above the terrain and finds the first positive-solid crossing in the bounded vertical interval. It refines that crossing with 16 bisections, then rounds the region-local anchor to integer millimeters. Nonfinite or unavailable samples fail region object publication. These placement checks use base SDF v1 only; they do not claim placement against persisted terrain edits.

## Geometry and visual representation

`ProceduralRockMeshAdapter` converts the registry's ordered integer-millimeter lobe centers and radii into a single low-poly triangle mesh per object. Each lobe is a 10-segment by 6-segment UV sphere with radial normals. All definitions share the same adapter and stone material; the adapter has no first-party/external special case. Geometry and transforms are derived from the registered recipe and deterministic seeds.

`ProceduralObjectStream` owns one visual root per actually published region, with two object nodes beneath it. It keeps no authority over terrain chunks, the edit ledger or save storage. Publication builds the full region's object set before replacing an existing set; repeated same-seed publication is idempotent. Terrain unload frees the region's object root. Reload rebuilds matching identities, pins, placements and mesh data.

The terrain HUD reports visible object count, object-region count, loaded namespaced definition IDs and initialization/publication errors. `V` toggles object rendering without changing records. No collision body is created.

## Terrain edits and persistence

Procedural objects are derived from world seed, generator version, region coordinate, definition pins and recipe. They are not written to schema-1 world saves. The object layer receives no save-store or brush-ledger reference. A later terrain carve/fill does not move, delete or persistently modify an already placed object. It may leave an object floating, partially buried or intersecting edited terrain; unload/reload returns the deterministic base placement. Dynamic terrain following and entity-state migration require a separate authorized slice.

## Verification

Focused command:

```powershell
& $env:GODOT_BIN --headless --path .\game --script res://tests/procedural_object_tests.gd
```

The suite covers shared first-party/external registry and recipe use, installed `user://mods` discovery and duplicate-source avoidance, deterministic mesh conversion, signed-region placement and order independence, canonical surface anchoring, stable IDs and content pins, actual terrain scene publication/eviction/revisit, duplicate prevention, visibility toggling, missing/incompatible package failures, unchanged terrain edits and unchanged disposable schema-1 save bytes. `scripts/validate.ps1` includes the focused suite and all existing canonical regression groups.

Headless results establish source/runtime behavior only. Owner GUI acceptance is still needed to assess rock scale, silhouette, grounding and readability while moving through regions. No scored performance target is defined.
