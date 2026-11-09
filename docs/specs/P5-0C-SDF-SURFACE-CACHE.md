# P5.0C — SDF-derived terrain surface cache

Status: **IMPLEMENTED / QUALIFICATION PENDING / STACKED ON P5.0B / NOT MERGED**.

## Purpose

P5.0C provides hydrology with a bounded, deterministic terrain-surface representation derived from the canonical terrain SDF.

It does not create a second terrain authority. Terrain geometry, brush edits, materialized SDF history and terrain-object effects remain authoritative in the existing terrain system. The P5.0C cache is disposable and reconstructible.

The phase-level sequence and invariants are defined in [P5 Environment and Hydrology Plan](../roadmap/P5-ENVIRONMENT-HYDROLOGY-PLAN.md).

## Cache geometry

Each streamed environment scope uses the existing P5 environment grid:

- 8 cells in X;
- 6 cells in Z;
- 48 cells per region;
- 2000 mm × 2000 mm per environment cell.

For every cell, P5.0C derives:

- surface-valid flag;
- top surface height in millimetres;
- maximum local slope ratio in fixed-point milli-units;
- four-neighbor validity mask;
- signed height delta to north/east/south/west neighbors;
- deterministic steepest downhill neighbor index;
- downhill drop in millimetres.

Cross-region neighbors remain out of scope for P5.0C and are handled by P5.0E.

## Canonical SDF input

Surface jobs reuse the same immutable terrain snapshots used by meshing.

For each region cache job, the main thread prepares the 16 existing render-chunk SDF snapshots through:

- the current brush/materialized SDF authority;
- the same terrain-effect snapshot composition used by mesh jobs.

The worker never scans the SceneTree and never reads mutable terrain state.

Each cache product carries provenance:

- world seed;
- generator version;
- terrain ledger revision;
- terrain cache-scope identity;
- terrain-object-effect authority revision;
- region key.

## Surface sampling

For each environment-cell center, the worker selects the containing render-chunk snapshot and probes vertically from above the terrain bounds downward.

The algorithm finds the first air-to-solid crossing from the top, then refines the crossing by bounded binary search.

This intentionally derives the highest hydrologically exposed terrain surface rather than cave floors beneath it.

All authoritative hydrology-facing values are converted to deterministic integer millimetres before publication.

## Derived neighborhood data

After all cell heights are derived, the worker computes local four-neighbor relationships.

For each valid neighbor:

```text
neighbor_delta_mm = current_height_mm - neighbor_height_mm
```

A positive delta is downhill from the current cell.

The steepest positive drop becomes the cell's deterministic downhill neighbor. Ties preserve fixed direction iteration order:

1. north;
2. east;
3. south;
4. west.

The local slope value is the largest absolute neighbor height difference divided by the 2000 mm environment-cell spacing, stored in milli-units.

## Transient cache authority

`EnvironmentSurfaceCache` is owned transiently by `SimulationRuntime`.

It is deliberately excluded from runtime snapshot schema 3.

A full runtime restore therefore restores authoritative environment state but starts with an empty derived terrain cache.

Region unload discards its cache while preserving the corresponding P5 environment state.

## Revision gate

Before a worker is dispatched, the terrain runtime registers the exact source token expected for the region.

Publishing succeeds only when the worker result exactly matches:

- scope ID;
- region key;
- seed;
- generator version;
- terrain revision;
- terrain cache-scope identity;
- terrain-effect revision.

Changing an expected token immediately invalidates the previously published cache.

A completed worker derived from an older token is rejected as stale and cannot overwrite a newer expectation.

The terrain runtime additionally rechecks live terrain/effect revisions before publication.

## Invalidation

A surface cache is queued/rebuilt when:

- a region is published;
- an authoritative brush edit affects one of the operation's rebuild-dependent regions;
- focused edit reset changes contributing terrain history;
- terrain-object-effect authority revision changes while a region is resident.

Object-effect revision invalidation is intentionally conservative across resident regions in P5.0C.

## Bounded asynchronous execution

P5.0C uses `WorkerThreadPool` for CPU surface derivation.

Runtime bounds:

- at most 2 surface-cache jobs in flight;
- at most 1 new surface-cache dispatch per frame;
- exactly 16 immutable chunk snapshots maximum per region job;
- exactly 48 environment cells per worker;
- fixed vertical probe bounds;
- fixed binary refinement count.

Snapshot preparation remains on the main thread because existing SDF/materialized state sources are resolved there. Heavy repeated density evaluation occurs in the worker.

If terrain-effect snapshot data is still prefetching, dispatch is deferred rather than publishing incomplete terrain input.

## Streaming behavior

Publication flow:

```text
region publication
  -> simulation/environment scope exists
  -> expected surface token registered
  -> immutable chunk snapshots prepared
  -> bounded worker job
  -> live revision recheck
  -> revision-gated cache publication
```

Unload flow:

```text
region unload
  -> discard derived cache expectation/record
  -> preserve authoritative environment scope
  -> ignore any later completion from the old worker
```

## Performance diagnostics

When performance tracing is enabled, P5.0C emits:

- `environment_surface_cache_snapshot`;
- `environment_surface_cache_job`.

The diagnostics expose snapshot duration, worker queue/runtime, region identity and source revisions.

## Qualification

Focused P5.0C tests must prove:

- unchanged SDF snapshots derive byte-for-byte identical cache records;
- all baseline environment cells produce valid exposed top surfaces;
- neighbor and downhill data are present;
- a real authoritative SDF fill edit changes the affected surface height;
- derived records carry source revision and cache identity;
- changing the expected terrain revision invalidates the old cache;
- stale worker output is rejected;
- terrain-effect revision changes also invalidate the old cache;
- surface jobs execute through `WorkerThreadPool`;
- runtime snapshots do not persist derived cache state;
- runtime restore begins without a derived cache;
- stream unload discards cache but preserves environment authority;
- job-in-flight and per-frame dispatch bounds remain explicit.

P5.0B focused qualification and all inherited P5.0A/P4 gates remain required.

## Explicit non-goals

P5.0C does not implement:

- precipitation or evaporation policy beyond P5.0B;
- lateral runoff;
- finite-water transfer between cells;
- cross-region water flow;
- river/ocean placement;
- water rendering;
- erosion or sediment;
- groundwater.
