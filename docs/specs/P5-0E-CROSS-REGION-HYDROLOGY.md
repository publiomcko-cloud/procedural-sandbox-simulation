# P5.0E — Rivers, Oceans and Cross-Region Hydrology

Status: **IMPLEMENTED / QUALIFIED / STACKED ON P5.0D**

## Scope

P5.0E extends P5.0D from local finite runoff to world-scale hydrology boundaries.

It adds deterministic generated river/ocean binding, persistent fixed-level infinite reservoirs, finite/reservoir exchange, finite transfer across adjacent environment scopes, atomic multi-scope commits, bounded same-tick batching, and streaming-safe deferral.

P5.0E does not add water rendering. Presentation remains P5.0F+.

## Authority

Environment authority remains `EnvironmentStateStore` schema 1. Runtime persistence remains schema 3.

No second terrain model is introduced. Cross-region direction and reservoir placement consume P5.0C surface records, which remain transient and revision-gated.

Rivers and oceans use the existing P5.0A `RESERVOIR_RIVER` and `RESERVOIR_OCEAN` kinds. Reservoir cells store zero finite surface/soil water and their authoritative `reservoir_level_mm` remains fixed after binding.

## Deterministic world binding

P5.0E uses an engine-owned deterministic V1 placement rule tied to exact world seed and terrain generator version.

Global environment-cell coordinates are derived from stable region coordinates plus the fixed 8x6 environment grid.

Ocean binding begins at a fixed global-cell Z boundary; only cells at or below the fixed sea level bind; ocean level is fixed at 4000 mm.

River binding follows a one-cell-wide integer meander computed from global cell Z and world seed. Eligible terrain remains below the V1 bank ceiling. First binding pins a fixed river level 250 mm above the then-current derived terrain surface.

Existing reservoir bindings are never silently removed by later terrain edits.

When a finite cell first becomes a reservoir, any finite surface/soil water already present is removed from finite authority and recorded as reservoir inflow. This is an explicit conservation boundary term.

## One-commit same-tick batching

P5.0A permits only one state-changing environment commit per scope/logical tick. When P5.0E is enabled, the lifecycle batches scopes due at the same logical tick instead of independently committing P5.0D first.

For each available due scope:

1. build the immutable P5.0D climate/runoff snapshot;
2. apply deterministic reservoir bindings;
3. solve local P5.0D forcing/runoff;
4. assemble immutable boundary-state entries;
5. solve reservoir exchange and cross-region boundary flow;
6. verify all environment revisions and P5.0C provenance tokens;
7. commit all participating scope updates using one `EnvironmentStateStore.commit_batch()`.

If any participating scope becomes stale, the whole multi-scope batch is rejected before mutation.

## Cross-region finite flow

Only directly adjacent X/Z scope boundaries are connected. Matching boundary cells are paired deterministically.

For finite-to-finite pairs, the higher derived terrain surface is the source; equal-height pairs do not transfer; request volume follows the same deterministic quarter-volume rule used by P5.0D; source availability and destination capacity are reserved from immutable post-local-runoff state; transfers do not cascade through newly received water in the same solve.

All boundary edges are traversed in canonical region/cell order.

## Infinite reservoir exchange

For a finite/reservoir adjacent pair, finite water may flow into a lower reservoir, or a higher reservoir may supply the finite cell. Reservoir supply uses a bounded per-tick exchange rate. Reservoir volume/level never changes; inflow/outflow counters explicitly account each exchange.

Repeated withdrawals therefore continue indefinitely as modeled boundary supply without depletion.

## Conservation

`finite_final = finite_initial + precipitation + reservoir_outflow - reservoir_inflow - evaporation`

Internal local runoff and finite cross-region transfers cancel exactly. Reservoir binding conversion is included in `reservoir_inflow`.

## Streaming and tiers

A scope with no current P5.0C cache is deferred without mutation or logical-tick advancement. Other available scopes in the same bounded sweep may still progress. No cross-boundary transfer is attempted through a missing neighbor.

When both adjacent scopes later have current derived caches and share a due tick, boundary transfer resumes. No deferred water is duplicated or discarded.

Active/aggregate/dormant due decisions remain owned by the existing P4 tier state.

## Bounded scheduling

The existing lifecycle due-decision budget remains the hard per-frame scheduling bound. Scopes sharing the earliest pending logical tick are grouped only within the remaining decision budget. The pre-existing non-P5.0E scheduling path remains unchanged when world hydrology is disabled.

## Runtime integration

New runtime API:

- `configure_environment_hydrology(world_seed, generator_version)`
- `has_environment_hydrology()`
- `process_environment_hydrology_batch(scope_ids, logical_tick, max_scope_count)`
- `get_environment_hydrology_metrics()`

World hydrology requires P5.0D runoff to already be configured and binds to its exact climate profile. The playable terrain runtime enables P5.0E after successful climate + runoff configuration.

## Qualification

Focused tests cover deterministic river/ocean binding, fixed reservoir levels, repeated withdrawal, explicit inflow accounting, atomic cross-region transfer, stale conflict with zero partial commit, missing-neighbor deferral, unload/reload authority retention, WorkerThreadPool-compatible batch solve, deterministic replay, and lifecycle backpressure.

Pass markers:

`P5_0E_CROSS_REGION_HYDROLOGY_PASS: assertions=<n> failures=0`

`SELF_HOSTED_P5_0E_QUALIFICATION_PASS`

The cumulative runner executes P5.0E followed by P5.0D -> P5.0C -> P5.0B -> P5.0A -> P4 regression coverage.
