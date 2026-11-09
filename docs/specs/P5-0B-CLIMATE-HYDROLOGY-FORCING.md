# P5.0B — climate forcing, precipitation, infiltration and evaporation

Status: **IMPLEMENTED / QUALIFICATION PENDING / STACKED ON P5.0A / NOT MERGED**.

## Purpose

P5.0B introduces deterministic climate forcing over the P5.0A environment authority.

It adds climate profiles, precipitation, bounded infiltration, evaporation and tier-aware execution. It does **not** implement lateral runoff, terrain-surface sampling, cross-region water flow or visuals.

The phase-level sequence and invariants are defined in [P5 Environment and Hydrology Plan](../roadmap/P5-ENVIRONMENT-HYDROLOGY-PLAN.md).

## Mod-first climate profile

Climate is engine-owned behavior configured by declarative mod data.

Content type:

`environment_climate_profile`

Schema 1 fields:

- `schema_version`
- `type`
- `id`
- `air_temperature_milli_c`
- `precipitation_ul_per_cell_per_tick`
- `infiltration_ul_per_cell_per_tick`
- `soil_capacity_ul_per_cell`
- `evaporation_ul_per_cell_per_tick`

The engine registers a `ContentTypeHandler`; mods remain data-only.

The selected profile is pinned through the existing `ContentDefinitionRegistry` fingerprint. The profile ID and canonical SHA-256 are persisted in the P5 environment scope.

A runtime restore preserves the authoritative profile pin but deliberately discards the transient registry binding. The caller must rebind the same content before climate execution resumes. A conflicting profile pin is rejected.

When P5.0B first binds climate to an older unpinned P5.0A scope, the climate baseline is advanced to the current scheduler tick. Historical ticks that predate the climate system are therefore not replayed as retroactive precipitation.

## Deterministic forcing

`EnvironmentClimateDomain` processes one explicit scope and logical tick.

The existing P4 tier authority decides whether a scope is due:

- active: due every logical tick;
- aggregate: due according to the existing deterministic aggregate cadence;
- dormant: no climate mutation.

For a due update, elapsed logical ticks are derived from:

`logical_tick - last_environment_tick`

This allows reduced-frequency aggregate updates to represent multiple logical ticks without per-tick loops.

The elapsed interval is bounded.

## Water update order

For each finite cell:

1. precipitation is applied to finite surface water;
2. precipitation beyond the P5.0A per-cell bound is reported as explicit overflow;
3. infiltration transfers surface water into soil water up to:
   - available surface water;
   - configured infiltration amount;
   - configured soil capacity;
4. evaporation removes finite water from surface first and then soil.

River and ocean cells are skipped entirely by climate finite-water forcing. Their finite water remains zero and their fixed authoritative level remains unchanged.

## Accounting

Every committed climate step returns exact integer terms:

- precipitation applied;
- precipitation overflow;
- infiltration;
- evaporation;
- air-temperature forcing;
- elapsed logical ticks.

Infiltration is internal redistribution and therefore cancels in global finite-water conservation.

For the P5.0B step:

```text
finite_final
= finite_initial
+ precipitation_applied
- evaporation
```

Precipitation overflow is an explicit unretained boundary term. P5.0D may later replace/consume this behavior through terrain-aware runoff policy; P5.0B does not invent lateral storage.

## Runtime integration

`SimulationRuntime.configure_environment_climate()`:

- binds the selected profile through the mod registry;
- validates existing persisted scope pins;
- binds unpinned legacy P5.0A scopes to the selected profile;
- stores only the transient domain binding in runtime memory.

`register_environment_scope()` automatically applies the configured climate profile pin when no explicit profile pin is supplied.

`SimulationWorldScopeLifecycle` executes climate work using the same:

- resident scope set;
- route decisions;
- due decisions;
- per-scope logical cursor;
- bounded due-decision budget

already used by P4 material-environment scheduling.

When climate is enabled, the lifecycle also derives a conservative scheduler admission limit from `due_decision_budget / resident_scope_count`. This limit is combined with any explicit P5.0A admission limit, so logical ticks cannot outrun the bounded climate decision capacity. Excess due time remains deterministic scheduler backlog.

No second world scan or independent climate loop is introduced.

## Streaming and persistence

Environment authority remains owned by `EnvironmentStateStore`.

Region unload discards only transient residency. Climate-pinned water authority persists.

Runtime snapshots continue using runtime schema 3 because P5.0B does not add a new runtime snapshot component; its durable data is already contained in the existing environment scope record.

Transient climate registry bindings are intentionally not persisted.

Both save and candidate-load paths validate every persisted climate profile ID/SHA against the current content registry before accepting the snapshot. Same-ID content changed behind the persisted SHA is rejected.

## Bounds

P5.0B remains bounded by:

- P5.0A fixed environment cell count;
- P4 resident scope limit;
- P4 due-decision budget;
- maximum per-cell climate rate;
- maximum elapsed ticks accepted by one climate update;
- existing scheduler admission/backpressure architecture.

There is no unbounded catch-up loop.

## Qualification

Focused P5.0B tests must prove:

- profile schema validation;
- real mod registry handler/record/fingerprint path;
- persisted profile ID/SHA pin;
- exact precipitation accounting;
- exact infiltration accounting;
- exact evaporation accounting;
- finite-water conservation for the climate step;
- same-tick idempotence;
- dormant no-work behavior;
- reduced-frequency aggregate behavior;
- infinite river/ocean exclusion from finite climate stores;
- fixed reservoir level preservation;
- world-lifecycle climate execution;
- resident-budget scheduler backpressure without lost ticks;
- snapshot restore plus safe registry rebind;
- no retroactive forcing when binding legacy unpinned P5.0A scopes;
- save/load content-pin validation;
- same-ID changed climate content rejection;
- conflicting restored profile pin rejection.

P5.0A focused qualification and cumulative P4.0H qualification remain inherited gates.

## Explicit non-goals

P5.0B does not implement:

- runoff;
- terrain-derived height/slope cache;
- cross-region water transfer;
- river/ocean placement or generation;
- visual rain;
- water rendering;
- erosion or sediment;
- groundwater;
- snow/ice;
- organisms.
