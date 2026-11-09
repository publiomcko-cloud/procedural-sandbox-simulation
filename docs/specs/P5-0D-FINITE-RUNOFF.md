# P5.0D — Finite Runoff and Local Water Redistribution

Status: **IMPLEMENTED / QUALIFICATION PENDING / STACKED ON P5.0C**

## Scope

P5.0D makes finite surface water move deterministically inside one environment scope using the transient P5.0C SDF-derived surface cache.

This slice does not add cross-region transfer, river/ocean exchange, groundwater, rendering or a second terrain authority.

## Authoritative contracts

- Environment authority remains \`EnvironmentStateStore\` schema 1.
- Runtime snapshot remains schema 3.
- Water authority remains integer microliters.
- Terrain authority remains the canonical SDF/edit ledger.
- \`EnvironmentSurfaceCache\` is transient and derived.
- Rivers and oceans remain infinite fixed-level reservoirs and do not participate in P5.0D finite-to-finite runoff.
- Climate identity remains the P5.0B \`environment_climate_profile\` ID + SHA-256 pin.

## One-commit environment tick

P5.0A rejects multiple state-changing commits at the same logical environment tick. P5.0D therefore composes climate forcing and runoff into one mutation.

Order:

1. precipitation on finite cells;
2. infiltration from surface to soil;
3. evaporation from surface, then soil;
4. local finite-to-finite runoff using the P5.0C downhill relation;
5. one revision-gated atomic environment commit.

The standalone P5.0B path remains available when runoff is not configured.

## Local runoff rule

Each valid finite cell may transfer only to its single deterministic local \`downhill_neighbor\` from P5.0C when \`downhill_drop_mm > 0\`.

For one elapsed logical tick, requested runoff is one quarter of available post-climate surface water, rounded upward. Multiple elapsed ticks scale that request and remain capped by source volume.

Transfers are solved simultaneously from the post-climate surface snapshot. Incoming capacity is reserved deterministically in ascending source-cell order. Transfers are capped by source availability and destination capacity.

This guarantees no negative water, no cell above \`MAX_WATER_UL_PER_CELL\`, no same-solve cascade, deterministic integer behavior and exact internal conservation.

P5.0D does not transfer across scope boundaries and skips river/ocean destinations; those exchanges belong to later slices.

## Conservation

For one solve:

\`finite_final = finite_initial + precipitation_applied - evaporation\`

Infiltration and local runoff are internal transfers and cancel from the balance. Precipitation overflow is reported separately.

## Revision-gated solve

\`EnvironmentRunoffDomain\` builds an immutable snapshot containing the environment state revision, logical tick, exact climate pin/rates, water arrays, P5.0C downhill arrays and exact surface-cache provenance.

\`EnvironmentRunoffJob\` owns the pure solve and has no SceneTree access. Before commit, the domain rechecks the exact environment state revision and P5.0C provenance token. Stale results are deferred and cannot mutate authority.

## Tier and streaming behavior

The existing P4 due policy remains authoritative:

- active: every logical tick;
- aggregate: existing deterministic aggregate cadence;
- dormant: no mutation.

If a due scope has no current P5.0C cache, the scope is deferred without advancing its environment tick or changing water. Streaming unload may discard derived cache while retaining authoritative water state.

## Runtime integration

New runtime API:

- \`configure_environment_runoff(registry, profile_id)\`
- \`has_environment_runoff()\`
- \`process_environment_runoff_scope(scope_id, logical_tick)\`
- \`get_environment_runoff_metrics()\`

Runoff requires the already-bound P5.0B climate profile and the exact same content pin. The playable terrain runtime enables runoff automatically when exactly one climate profile is selected successfully.

## Bounded work

One solve operates over the fixed V1 environment grid. The lifecycle reuses the existing due-decision budget and scheduler environment admission limit, so no unbounded catch-up loop is introduced.

The pure job is WorkerThreadPool-compatible and focused qualification verifies off-thread execution compatibility.

## Qualification

Focused tests cover rain-to-runoff, climate composition, terrain-path revision, exact conservation, stale state/cache gates, tier behavior, missing-cache deferral, worker compatibility, deterministic replay and lifecycle backpressure.

Pass markers:

\`P5_0D_FINITE_RUNOFF_PASS: assertions=<n> failures=0\`

\`SELF_HOSTED_P5_0D_QUALIFICATION_PASS\`

The cumulative runner executes P5.0D followed by P5.0C -> P5.0B -> P5.0A -> P4 regressions.
