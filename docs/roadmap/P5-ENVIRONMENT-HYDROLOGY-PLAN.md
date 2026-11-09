# P5 — Environment and Hydrology Plan

Status: **OWNER-DEFINED EXECUTION PLAN / P5.0A IMPLEMENTED / P5.0B IMPLEMENTED-PENDING-QUALIFICATION / P5.0C IMPLEMENTED-PENDING-QUALIFICATION / P5.0D-G NOT YET IMPLEMENTED**

This document freezes the P5 scope previously defined during architecture planning. It is the roadmap-level source of truth for P5 sequencing. Slice specifications may refine implementation details, but must not silently widen or reorder this scope.

## Goal

P5 delivers the V1 environmental and hydrology layer on top of the integrated P4 simulation runtime.

The phase must make climate and water deterministic, persistent, bounded and terrain-aware without turning Godot scene nodes or rendered water into authority.

P5 reuses the existing P4 architecture:

- fixed logical ticks and bounded catch-up;
- stable simulation scope IDs `region:x,z`;
- active / aggregate / dormant simulation tiers;
- streamed world-scope lifecycle;
- exact runtime sidecar persistence and deterministic replay;
- canonical terrain SDF as terrain authority;
- bounded worker products with revision-gated publication;
- mod-first profile/content pinning.

The environment subsystem owns authoritative environmental state separately from terrain geometry, material-domain state and render nodes.

## Architectural invariants

1. **Integer authority.** Authoritative hydrology state uses deterministic integer quantities. Floating-point data may exist in derived worker/render products but must not become persistent water authority.

2. **Terrain remains authoritative through the SDF.** Hydrology consumes a derived terrain-surface cache. It does not persist a second competing terrain model.

3. **Bounded work.** Every P5 slice must preserve bounded per-frame/tick work and integrate with scheduler admission/backpressure rather than creating an unbounded simulation loop.

4. **Revision-gated commits.** Worker calculations use immutable snapshots and commit only against the revisions they were derived from.

5. **Atomic cross-scope transfer.** A water transfer that affects more than one environment scope must either commit completely or not commit at all.

6. **Finite-water conservation is explicit.** Rain, evaporation, external drainage and infinite-reservoir exchange are explicit boundary terms. They must not be hidden as unexplained creation/destruction.

7. **Rivers and oceans are infinite fixed-level reservoirs.** They may provide or receive unlimited modeled water while their authoritative level and modeled stored volume remain unchanged. Exchange remains explicitly accounted.

8. **Streaming does not destroy authority.** Unloading a region may discard derived/transient products, but authoritative environment state survives and is reused when the region returns.

9. **Simulation tiers change fidelity, not identity.** Active, aggregate and dormant scopes share the same stable environment scope and persistence identity.

10. **Rendering is derived only.** Water surfaces, rain visuals and similar presentation are consumers of authoritative state, never the source of truth.

## Execution order

The approved execution sequence is:

`P5.0A -> P5.0B -> P5.0C -> P5.0D -> P5.0E -> P5.0F -> P5.0G`

A later slice may start only after its required upstream contracts are integrated and qualified.

---

## P5.0A — Environment authority core, persistence and infinite-reservoir contract

Purpose: establish the data and transaction foundation before any climate or flow solver exists.

Deliverables:

- authoritative `EnvironmentStateStore` keyed by existing P4 scope IDs;
- engine-owned default 8x6 environment grid per region;
- packed deterministic integer surface-water and soil-water state;
- explicit finite / river / ocean cell kinds;
- authoritative fixed reservoir level;
- river/ocean source/sink semantics with unlimited exchange and unchanged level/volume;
- deterministic saturating lifetime exchange telemetry that never limits reservoir capacity;
- atomic multi-scope commits with optimistic state revisions;
- strict logical-tick mutation ordering with same-tick idempotent no-op support;
- runtime snapshot schema 3 containing environment authority;
- migration from runtime schemas 1 and 2;
- streamed-scope binding and unload persistence;
- transient scheduler admission backpressure for future environment workers;
- focused qualification plus cumulative P4 regression.

Acceptance gate:

- finite and infinite reservoir invariants pass;
- river/ocean level remains fixed under arbitrarily large modeled exchange;
- malformed/stale multi-scope commit rejects the whole batch;
- valid multi-scope commit applies atomically;
- scheduler backpressure defers ticks without dropping logical time;
- schema 1 and schema 2 migrate deterministically to schema 3;
- stream publish/unload preserves the environment record;
- save/restart/load preserves packed environment authority exactly;
- cumulative P4 qualification remains green.

Explicitly excluded from P5.0A: climate, precipitation, infiltration, evaporation, runoff, terrain surface cache, river/ocean placement, cross-region flow solving and visuals.

---

## P5.0B — Climate, precipitation, soil moisture and evaporation

Purpose: introduce deterministic environmental forcing without terrain-driven lateral flow yet.

Deliverables:

- deterministic climate/environment profiles bound through stable profile ID/SHA pins;
- temperature and precipitation forcing expressed in fixed logical ticks;
- precipitation input into finite surface/soil water;
- bounded infiltration from surface water into soil water;
- bounded evaporation from eligible finite water stores;
- tier-aware update policy using existing active / aggregate / dormant authority;
- deterministic aggregate behavior that preserves required water accounting;
- explicit per-step source/sink accounting suitable for later conservation proofs.

Dependencies: P5.0A environment authority, persistence and scheduler contracts.

Acceptance gate:

- identical seed/profile/tick history produces identical climate and water state;
- rain increases finite water according to the bound profile;
- infiltration cannot create water or produce negative stores;
- evaporation is bounded by available finite water;
- tier transitions preserve authoritative totals and deterministic replay;
- save/reload resumes from the same authoritative state.

---

## P5.0C — SDF-derived terrain surface cache and invalidation

Purpose: provide hydrology with a bounded terrain representation without duplicating terrain authority.

Deliverables:

- derived per-environment-cell surface samples from the canonical terrain SDF;
- slope/height/neighborhood data sufficient for P5 runoff decisions;
- source terrain revision/provenance attached to every cache product;
- bounded asynchronous cache generation using existing worker architecture;
- invalidation after terrain edits that affect contributing samples;
- revision-gated publication so stale surface products cannot overwrite newer terrain;
- stream unload may discard cache products while preserving environment authority.

Dependencies: P5.0A. P5.0B may exist independently, but P5.0D requires both B and C.

Acceptance gate:

- unchanged SDF produces deterministic identical surface cache;
- relevant terrain edits invalidate/rebuild affected cache;
- stale worker output is rejected;
- unload/reload reconstructs the same derived surface data from unchanged terrain;
- cache ownership never becomes an alternate persisted terrain source.

---

## P5.0D — Finite runoff and local water redistribution

Purpose: make finite accumulated water move according to terrain.

Deliverables:

- deterministic local runoff using the P5.0C surface cache;
- bounded finite-water redistribution between environment cells;
- no negative water and no transfer above available source volume;
- local infiltration/evaporation integration from P5.0B;
- revision-gated worker snapshot -> solve -> atomic commit flow;
- terrain edits influence subsequent runoff through surface-cache invalidation;
- tier-aware active/aggregate execution with dormant scopes retaining state.

Dependencies: P5.0A, P5.0B and P5.0C.

Acceptance gate:

- rain can accumulate and subsequently move downhill;
- digging or otherwise changing terrain can alter later runoff paths;
- closed finite fixtures conserve water to exact integer accounting except declared boundary terms;
- replay is deterministic;
- workload remains bounded under scheduler backpressure.

---

## P5.0E — Rivers, oceans and cross-region hydrology

Purpose: connect local finite runoff to world-scale region boundaries and the infinite reservoir contract defined in P5.0A.

Deliverables:

- deterministic river/ocean placement or binding to generated world content;
- conversion/binding of selected environment cells to `RESERVOIR_RIVER` or `RESERVOIR_OCEAN`;
- fixed authoritative reservoir water-surface levels;
- reservoir-to-finite and finite-to-reservoir exchange without reservoir depletion/filling;
- cross-region finite flow across environment-scope boundaries;
- atomic multi-scope commits for cross-region transfer;
- bounded neighbor scheduling and revision conflict handling;
- streaming-safe behavior when adjacent scopes are not simultaneously resident;
- explicit boundary exchange terms for conservation accounting.

Dependencies: P5.0A and P5.0D; consumes P5.0C terrain data and P5.0B forcing.

Acceptance gate:

- river/ocean withdrawal can continue indefinitely without lowering the reservoir;
- arbitrary inflow into a river/ocean does not raise its authoritative level;
- exchange remains explicitly counted;
- cross-region finite transfer cannot partially apply;
- region unload/reload does not duplicate or lose committed water;
- deterministic replay across region boundaries is exact.

---

## P5.0F — Derived environmental rendering

Purpose: make P5 state visible without changing simulation authority.

Deliverables:

- derived visible finite surface-water representation;
- derived river/ocean surface representation from fixed reservoir level;
- rain/weather presentation driven by authoritative climate state;
- streaming/LOD-aware creation and removal of visual products;
- bounded publication and no per-cell scene-node explosion;
- visual refresh on authoritative environment or terrain-surface revision changes.

Dependencies: P5.0B through P5.0E as applicable to the presented effect.

Acceptance gate:

- authoritative water changes are reflected visually;
- unloading removes derived visuals but not state;
- reloading reconstructs visuals from authority;
- visual state cannot mutate water authority;
- owner GUI acceptance is required for visual stability and smoothness.

---

## P5.0G — Final P5 qualification, conservation, replay and performance

Purpose: qualify P5 as an integrated V1 environment/hydrology milestone.

Deliverables:

- deterministic end-to-end replay fixtures;
- exact finite-water conservation ledgers with explicit rain, evaporation, drainage and reservoir boundary terms;
- save/restart/load coverage across climate and hydrology state;
- streaming/unload/revisit coverage;
- terrain-edit-to-runoff causality coverage;
- tier transition coverage;
- cross-region transfer coverage;
- river/ocean infinite-reservoir invariants;
- `PERF_TRACE` instrumentation for material P5 work queues/commit/publication paths;
- representative performance runs and regression review;
- final human visual acceptance for P5.0F presentation.

Dependencies: P5.0A through P5.0F.

Acceptance gate:

- deterministic replay has no unexplained state divergence;
- finite-water conservation closes exactly within declared integer boundary terms;
- save/reload and streaming do not duplicate or lose authority;
- terrain edits demonstrably influence later runoff;
- no critical P4 regression;
- bounded work/backpressure remains effective;
- no material visual hitching attributable to P5 in the accepted owner scenario.

## Tier policy

P5 uses P4 tier authority rather than defining a parallel system.

- **Active:** full local environmental fidelity and frequent hydrology updates.
- **Aggregate:** reduced-frequency/coarser environmental evolution while preserving authoritative accounting and deterministic transitions.
- **Dormant:** no continuous simulation work; authoritative state is retained for deterministic resume.

Exact cadence and aggregation formulas belong to the slice that introduces them and must be tested before integration.

## Worker/commit flow

The intended P5 execution model is:

```text
authoritative scheduler/tier/environment/terrain revisions
        |
        v
immutable bounded work snapshot
        |
        v
worker calculation / derived terrain sampling
        |
        v
revision validation
        |
        v
atomic authoritative environment commit
        |
        +--> persistence/replay authority
        |
        +--> derived visual/cache invalidation
```

A worker result derived from stale terrain, environment or relevant profile authority must be discarded/recomputed rather than force-applied.

## Conservation model

Finite water is the conserved simulated quantity. Infinite rivers/oceans are explicit external boundary reservoirs.

For a closed accounting interval:

```text
finite_final
= finite_initial
+ precipitation
+ reservoir_outflow
- reservoir_inflow
- evaporation
- modeled_external_drainage
```

Internal cell-to-cell and region-to-region transfers cancel from the global finite-water balance.

## Non-goals for P5

P5 does not attempt:

- general CFD;
- physically complete groundwater;
- erosion or sediment transport;
- snow/ice simulation;
- organism/ecosystem simulation;
- photorealistic water;
- multiplayer synchronization.

Those are outside the V1 environmental/hydrology milestone unless a later owner decision explicitly changes the roadmap.
