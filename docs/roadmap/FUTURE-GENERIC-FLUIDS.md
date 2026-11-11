# Future — Generic Fluids Architecture (post-P5 backlog)

Status: **BACKLOG / DESIGN INTENT ONLY / NOT AUTHORIZED FOR IMPLEMENTATION IN P5**

## Intent

The P5 environment/hydrology milestone is exclusively for water and climate. Lava, oil, fuels, slurries and other fluids are future candidates. Their presence in this backlog **does not enlarge P5.0F, P5.0G, or current test/acceptance gates**. No existing water authority, save schema, replay hash, content fingerprint, scheduler policy, or mod discovery contract may be silently changed on account of this note.

## Reuse candidates (core)

- Fixed-tick scheduler, tiered update policy, bounded worker admission and backpressure
- Stable region/scope IDs, streamed lifecycle, revision-gated snapshot/commit
- Terrain SDF derived samples, provenance and edit invalidation
- Optimistic multi-region atomic transactions and deterministic integer accounting
- Declarative content registry and canonical profile pinning
- Transient visualization allocation, render mesh clipping and performance tracing

## Water-specific contracts that are NOT generic today

- EnvironmentStateStore schema-3 field names `surface_water_ul`, `soil_water_ul`, `reservoir_kind`, `reservoir_level_mm`
- Hydrology's finite/river/ocean rules, precipitation, infiltration, evaporation and runoff
- Fixed-level infinite river/ocean reservoirs
- Terrain runoff and soil absorption equations, plus water-color presentation

A mod alone cannot add lava or oil under the current code. Water's simulation logic is core; a mod supplies climate content and can influence declared rates without replacing the solver.

## Future architecture study — explicit non-goals in P5

1. Draft a versioned FluidDefinition contract: stable namespaced ID, units, density, viscosity class, phase behavior and optional material/thermal interactions. Add only validated data-first properties; no executable mod scripts.
2. Separate reusable transaction/scheduling/terrain abstractions from specific fluid solvers. Preserve integer authority and deterministic replay; consider per-fluid species stores instead of repurposing water's existing schema fields.
3. Decide interaction rules: water+oil stratification, fluid mixing, lava thermal energy and solidification, sources/sinks and cross-boundary accounting. Each algorithm is an engine-owned capability selected by declarative mod data.
4. Require dedicated schema migration, storage quotas, conservation/energy ledger, streaming/LOD performance budget, visual rendering tests and owner GUI acceptance **before** implementing a second fluid.

## Architectural decision

Do **not** prematurely rename water records, introduce a generic fluid engine in P5, or loosen strict mod content-type validation to support hypothetical content. Finish P5.0F R2 shoreline and P5.0G acceptance on the existing water pipeline. Revisit as a separately approved roadmap phase.
