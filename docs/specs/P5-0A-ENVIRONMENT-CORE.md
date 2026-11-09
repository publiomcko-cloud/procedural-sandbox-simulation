# P5.0A — environment authority core and infinite reservoirs

Status: **IMPLEMENTED / QUALIFICATION PENDING / NOT MERGED**.

## Purpose

P5.0A introduces the authoritative environmental state foundation used by later P5 climate and hydrology slices. The phase-level sequence and invariants are frozen in [P5 Environment and Hydrology Plan](../roadmap/P5-ENVIRONMENT-HYDROLOGY-PLAN.md). It deliberately does **not** implement rain, infiltration, runoff, terrain-surface sampling or rendering.

P5.0A reuses the integrated P4 contracts:

- the same stable simulation scope IDs (`region:x,z`);
- the existing fixed-tick scheduler and active/aggregate/dormant lifecycle;
- the existing runtime sidecar and exact Variant persistence;
- the existing terrain-generation pairing and save/restart contract;
- the same bounded-work and revision-gated architecture.

## Authoritative environment store

`environment_state_store.gd` owns environmental authority separately from the compact P4 material/environment state. The default engine-owned grid is 8x6 cells per region (48 cells), but this is a P5.0A implementation default, not a mod-controlled resolution and not a permanent physical-fidelity promise.

Each scope stores:

- scope ID and environment state revision;
- optional environment profile ID/SHA pin reserved for later P5 content binding;
- last environment logical tick;
- finite surface-water volume per cell in integer microliters;
- finite soil-water volume per cell in integer microliters;
- reservoir kind per cell;
- fixed reservoir water-surface elevation in millimeters;
- cumulative finite-to-reservoir and reservoir-to-finite exchange totals.

Packed integer arrays are used so the environment store is not constrained by the generic Dictionary node-count limit in P4 tier state.

Dry finite scopes use an implicit-zero representation internally and in snapshots: all four per-cell arrays are empty until water or a reservoir cell exists. Public scope reads expand that representation back to the fixed engine grid. This keeps historical dry-region state compact without changing solver-facing semantics.

## Infinite river/ocean contract

Each cell is exactly one of:

- `RESERVOIR_FINITE`;
- `RESERVOIR_RIVER`;
- `RESERVOIR_OCEAN`.

River and ocean cells are infinite fixed-level boundary reservoirs:

- their water-surface elevation is authoritative and fixed;
- they may receive unlimited modeled water without level/volume increase;
- they may provide unlimited modeled water without level/volume decrease;
- they may not contain finite surface or soil water in the environment arrays;
- exchange is explicitly accounted through cumulative integer diagnostic counters;
- those lifetime counters saturate at a large deterministic ceiling and **never reject or limit reservoir exchange**.

Therefore later conservation checks use:

```text
finite_final
= finite_initial
+ precipitation
+ reservoir_outflow
- reservoir_inflow
- evaporation
- modeled_external_drainage
```

Reservoir exchange is not hidden creation/destruction; it is an explicit boundary term. Conservation tests use the exact per-step exchange deltas; saturated lifetime diagnostics are not used as a physical capacity.

## Atomic multi-scope commits

`EnvironmentStateStore.commit_batch()` preflights the complete update set before mutating any scope.

Every update carries:

- stable scope ID;
- expected state revision;
- monotonic environment tick;
- complete fixed-size state arrays;
- reservoir exchange deltas.

Duplicate scopes, stale revisions, malformed arrays, invalid reservoir state or negative exchange deltas reject the entire batch. Lifetime reservoir counters saturate deterministically and never reject otherwise valid exchange. A state-changing commit must advance `last_environment_tick` strictly; an exact same-tick no-op remains idempotent. This prevents a future rain/runoff step from being applied twice at one logical tick. This is the future cross-region flow transaction boundary.

No partial cross-region water transfer is permitted.

## Scheduler backpressure

P5.0A extends the existing fixed-tick scheduler with an optional per-call admission limit. Default `-1` preserves the P4 behavior exactly.

The P5 runtime can set:

- `-1`: no environment backpressure beyond the scheduler's normal bound;
- `0`: admit no logical ticks this frame;
- positive bounded value: admit at most that many ticks.

Elapsed time still becomes deterministic scheduler backlog. Logical time does not advance beyond environment capacity. Future P5 worker queues will drive this limit from available capacity.

Backpressure state is transient scheduling control and is intentionally not authoritative/persisted; backlog itself remains persisted by the scheduler snapshot.

## Runtime snapshot schema 3

P5.0A advances `SimulationRuntime` snapshot schema from 2 to 3:

```text
schema 3
  scheduler
  tier_state
  tier_router
  environment_state
```

Schema 1 and schema 2 remain valid migration inputs.

Migration behavior:

- schema 1 -> restore scheduler/tier, initialize default empty router and empty environment store;
- schema 2 -> restore scheduler/tier/router, initialize empty environment store;
- schema 3 -> restore all four authoritative components exactly.

Environment records in schema 3 may reference only simulation scopes that exist in the accompanying P4 tier snapshot.

The durable `SimulationRuntimeStore` envelope remains schema 1 because it already stores opaque exact runtime Variant payloads and records the embedded runtime schema version.

## Streaming lifecycle

When the existing P4 world lifecycle publishes a region:

1. it resolves/creates the stable P4 scope;
2. it registers the same scope in the P5 environment store;
3. routing/material work proceeds normally.

On unload, the derived resident entry is removed but environment authority remains. Revisit reuses the environment record.

P5.0A does not scan historical/environment scopes during publication.

## Performance and bounds

P5.0A adds no per-tick hydrology work. Environment registration is O(1) keyed work on publication and environment snapshots are bounded by the existing simulation-scope capacity.

Default limits:

- grid: 8x6 = 48 cells/scope;
- maximum grid axis: 64;
- maximum cells/scope: 4096;
- default scope capacity: 65,536;
- hard scope capacity: 1,000,000.

These are engine-owned safety limits.

## Qualification

Focused P5.0A tests must prove:

- finite and infinite reservoir invariants;
- river/ocean fixed-level representation;
- reservoir exchange accounting;
- whole-batch rejection on stale cross-scope revision;
- successful atomic multi-scope commit;
- scheduler backpressure without lost ticks;
- schema 1 -> schema 3 and schema 2 -> schema 3 migration;
- streamed-region environment registration and unload persistence;
- exact runtime sidecar save/load with packed environmental state.

The complete P4.0H qualification remains cumulative.

## Explicit non-goals

P5.0A does not implement:

- climate profiles;
- rain;
- infiltration or evaporation;
- runoff;
- SDF surface cache;
- cross-region flow solver;
- river/ocean placement/generation;
- visual water or rain;
- erosion, sediment, snow/ice, groundwater or organisms.

Those remain later P5 slices.
