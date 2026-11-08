# P4.0C — bounded automatic simulation tier routing

## Status

Implementation candidate for Issue #266.

P4.0C builds on integrated P4.0A/P4.0B. It automatically classifies already-known simulation scopes into fidelity tiers from explicit deterministic distance observations. It does not derive distance from the world and does not implement a domain simulation.

## Ownership boundary

The router is engine-owned.

Callers provide:

- stable `scope_id`;
- non-negative integer `distance_mm`.

The router does not access:

- SceneTree;
- cameras/players;
- terrain/chunks;
- entities;
- world history;
- mod callbacks.

Distance derivation remains a host/routing concern. Tier authority remains exclusively in `SimulationTierState`.

## Hysteresis policy

Default provisional thresholds:

- active enter: 32,000 mm;
- active exit: 40,000 mm;
- aggregate enter: 96,000 mm;
- aggregate exit: 112,000 mm.

Required ordering:

`active_enter <= active_exit <= aggregate_enter <= aggregate_exit`

Tier behavior:

- dormant -> active at/below active-enter;
- dormant -> aggregate at/below aggregate-enter;
- aggregate -> active at/below active-enter;
- aggregate remains aggregate through aggregate-exit;
- active remains active through active-exit;
- active beyond active-exit but within aggregate-exit -> aggregate;
- any active/aggregate scope beyond aggregate-exit -> dormant.

This creates deterministic hysteresis and avoids boundary thrashing.

## Dirty observation queue

Observations are direct-indexed by exact scope ID.

A new or changed distance:

1. updates one observation record;
2. increments its observation revision when replacing an existing distance;
3. enqueues the scope once if it is not already pending.

Submitting the identical distance is idempotent and does not duplicate queue work.

The queue is FIFO and deduplicated.

Defaults:

- maximum routing decisions per call: 32;
- maximum tracked observations: 65,536.

Hard engine ceilings:

- decisions per call: 4,096;
- tracked observations: 1,000,000;
- distance: 9e15 mm;
- scope ID length: 256.

A caller may request a smaller routing budget but cannot exceed the configured maximum.

## Processing

`process_pending`:

1. selects at most the bounded budget from the FIFO head;
2. preflights that all selected observations and tier scopes exist;
3. reads the current authoritative tier/revision;
4. computes the hysteretic target tier;
5. uses P4.0B revision-gated transition authority;
6. records ordered decision receipts.

There is no global scope/world scan.

A missing scope during preflight rejects the batch without consuming pending queue entries.

Routing preserves domain state and `state_revision`.

## Determinism

Given the same:

- router configuration;
- initial tier state;
- ordered observation stream;
- logical ticks;
- routing budgets;

the router produces the same ordered transition receipts and final tier authority.

All routing inputs use integer distances.

## Snapshot

Router snapshot schema 1 stores:

- configuration;
- observations sorted by scope ID;
- exact FIFO pending-scope order.

Restore validates duplicate/missing pending identities and bounds before committing.

## Runtime snapshot

P4.0C advances `SimulationRuntime` snapshot schema from 1 to 2.

Schema 2 contains:

- fractional microsecond carry;
- P4.0A scheduler snapshot;
- P4.0B tier snapshot;
- P4.0C router snapshot.

Combined restore validates router observation identities against the candidate tier registry before replacing live authority.

P4.0B runtime snapshot schema 1 remains accepted. Restoring schema 1 initializes an empty default router and returns a schema-2 runtime snapshot.

## Runtime APIs

`SimulationRuntime` exposes:

- `submit_simulation_scope_observation(scope_id, distance_mm)`;
- `process_simulation_tier_routes(requested_budget)`;
- observation lookup;
- router snapshot/metrics;
- router snapshot restore.

Processing is explicit and bounded. P4.0C does not implicitly scan or derive observations during `_process`.

## Observability

With `SANDBOX_PERF_TRACE=1`, runtime routing batches emit:

`simulation_tier_routing_batch`

with:

- logical tick;
- processed count;
- remaining pending count;
- applied budget;
- duration.

P4.0B transition telemetry remains authoritative for individual tier transitions.

## Non-goals

P4.0C does not implement:

- automatic camera/player distance measurement;
- loaded-world enumeration;
- material/environment/climate/water state;
- domain simulation;
- world-save persistence;
- worker jobs;
- multiplayer;
- executable mod callbacks;
- visible behavior.

No separate visual acceptance is required unless implementation unexpectedly changes rendered or interactive behavior.
