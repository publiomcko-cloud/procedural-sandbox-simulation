# Conceptual contracts — not yet implementation API

**Warning:** Pseudocode below is normative behavior description, NOT implemented GDScript signatures.

## Terrain backend
```
query_density(world_position) -> density
query_material(world_position) -> material_id
ensure_edit_region_loaded(bounds, priority) -> ready | pending | error
apply_terrain_command(command_id, bounds, operation, actor, expected_revision)
  -> receipt | conflict | invalid
read_region_snapshot(region_key) -> immutable state
generate_region(seed, generator_version, region_key) -> immutable base data
```
Operations: add, subtract, smooth/sculpt, paint material; reserved transform selection includes clip, resample and relocation policies. A successful command increments revision and invalidates affected rendering/collision/nav/hydrology data, including neighbors.

## Entity and interaction
```
Definition { id, schema_version, recipe, materials, placement_rules, capabilities }
EntityState { stable_id, definition_id, recipe_seed, transform, components, revision }
query_capabilities(stable_id, context) -> named capabilities
execute_capability(stable_id, capability, parameters, actor, revision) -> receipt
```
Creation must not depend on discovery order. Promotion of a batched instance to stateful entity must preserve identity and location.

## Shared materials
Each material has namespaced stable ID plus optional density, hardness, permeability, thermal conductivity, heat capacity, cohesion, combustion and visual mapping. Units must be explicit. Systems use supported properties only; missing properties have schema-defined defaults or errors, never silently arbitrary values.

## Simulation
```
step(world_tick, active_region_set, read_snapshot) -> proposed_changes/events
commit(changes, expected_revisions) -> committed | rejected
```
System dependency graph resolves update order; invalid cycles fail at mod registration. Ownership is explicit for mutable fields. Initial recommended logical tick 20 Hz is provisional and measured, not guaranteed.

## Mod manifest
Minimum future fields: `id`, `version`, `schema_version`, `requires_engine`, `dependencies`, `content_roots`, `script_policy`, and optional generator compatibility declarations. Duplicate IDs fail closed. The example JSON in `mods/examples` is format illustration only, NOT currently loadable by the bootstrap.

## Persistence invariants
- World UUID/seed, pinned generator and mod manifest, schema versions.
- Stable chunk/region indices, edits/snapshots and dynamic simulation state.
- Crash consistency with checkpoint marker or durable transaction record.
- Backups/rollback before migrations. Missing required mods yields a safe error/read-only recovery, never silent deletion.
