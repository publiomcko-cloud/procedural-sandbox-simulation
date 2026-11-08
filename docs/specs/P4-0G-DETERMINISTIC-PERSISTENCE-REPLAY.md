# P4.0G — deterministic persistence, replay and tier invariants

Status: **IMPLEMENTED / SELF_HOSTED_QUALIFICATION_PENDING / NOT MERGED**.

Dependency chain: P4.0D PR #269 -> P4.0E PR #270 -> P4.0F PR #271 -> P4.0G stacked branch.

## Goal

Close the remaining P4 architecture requirements before the final qualification campaign:

- deterministic constrained replay;
- pause/manual-step/bounded catch-up with real material state;
- active/aggregate/dormant roundtrip invariants;
- durable authoritative simulation snapshots;
- fail-closed content-pin validation after reload;
- coherent pairing between terrain save generations and simulation sidecars.

P4.0G does not add climate, rain, moisture, water or organisms. Those remain later phases.

## Authoritative persistence boundary

The existing `SimulationRuntime.get_runtime_snapshot()` remains the sole persisted simulation authority. Its schema remains runtime snapshot v2 and contains:

- fixed-tick scheduler state, including pause/manual-step/backlog;
- P4.0B scope/tier/domain state;
- P4.0C observations and pending router authority.

The following remain derived/transient and are deliberately **not** persisted:

- material profile binding cache;
- material FIFO contents;
- streamed resident-scope index;
- lifecycle `next_tick` cursors;
- performance counters.

Therefore a durable snapshot may only be committed at a quiescent boundary.

## Persistence preflight

`SimulationRuntime.get_persistence_preflight()` fails closed while any non-persisted work would be lost:

1. P4.0C router dirty queue must be empty.
2. P4.0D material queue must be empty.
3. Every P4.0F resident scope must have `next_tick > scheduler.current_tick`.

Scheduler backlog and queued manual steps are authoritative and may remain nonzero because they are part of the scheduler snapshot.

Terrain save integration may defer the simulation sidecar until this gate passes; it never serializes transient queues merely to make save succeed.

## Durable sidecar

`SimulationRuntimeStore` writes immutable generations under a simulation-specific directory. Each document contains:

- format/schema;
- simulation-storage generation;
- world ID/seed/generator version;
- terrain generation;
- runtime snapshot schema version;
- base64 encoded Godot Variant bytes;
- SHA-256 of those exact bytes.

Godot Variant encoding is intentional: unlike JSON, it preserves integer, float and vector type identity used by P4 state contracts.

Commit sequence:

```text
validate runtime snapshot
-> Variant bytes
-> SHA-256
-> temporary file
-> flush
-> byte-for-byte temporary readback
-> atomic rename
-> byte-for-byte committed readback
```

At most four finalized simulation generations are retained. File and payload sizes are hard bounded.

## Terrain-generation coherence

A simulation generation records the terrain generation it accompanies.

Load requests an **exact terrain generation**. If simulation sidecars exist but none matches that terrain generation, load fails closed rather than selecting another generation.

A world created before P4 simulation sidecars is a permitted legacy baseline: when no simulation sidecar exists at all, the runtime starts from a deterministic empty simulation authority. Once sidecars exist, generation mismatch is an error.

For asynchronous materialized-terrain checkpointing, the simulation sidecar is queued after the terrain generation is committed and is written when simulation preflight becomes quiescent. World load is blocked while such a sidecar commit remains pending.

## Content pin validation

Restoring the structural snapshot is not enough.

Every persisted `material_environment` record is validated before simulation resumes:

- exact material-state fields and types;
- bounded temperature and monotonic tick metadata;
- persisted profile ID must exist in the current M4.0 registry;
- current content fingerprint SHA-256 must equal the persisted `profile_sha256`.

Missing content or same-ID content drift fails closed. The engine does not silently adopt changed environment parameters.

The gameplay runtime still does **not** invent a default environment profile. Zero profiles means tier lifecycle only; exactly one discovered profile is auto-bound; multiple profiles require explicit world/content selection.

## Replay contract

The focused P4.0G campaign executes the same event script twice against independent runtimes:

1. register/discover one data-only user mod profile;
2. publish two streamed regions;
3. drain bounded initialization;
4. pause;
5. request exactly two manual steps;
6. resume;
7. submit five elapsed ticks with scheduler max two admitted ticks/frame;
8. drain bounded catch-up;
9. route active -> aggregate;
10. unload -> dormant;
11. revisit -> active without advancing logical time.

Both runs must finish with identical authoritative snapshots and identical SHA-256 runtime fingerprints.

Tier-only transitions must preserve domain state revision and material temperature when no logical tick is admitted.

## Durable roundtrip contract

A quiescent replay snapshot is persisted, loaded by exact terrain generation, restored into fresh runtime authority, and must preserve:

- exact snapshot equality;
- exact integer/float Variant types;
- exact runtime SHA-256 fingerprint;
- material profile content pin compatibility.

A fixture with the same profile ID but changed profile bytes must be rejected before runtime simulation resumes.

## Actual terrain runtime integration

`terrain_demo.gd` now:

- owns the simulation sidecar store;
- restores a matching sidecar after mod discovery;
- validates sidecar/content compatibility before load transactions;
- pairs simulation saves with committed terrain generations;
- defers sidecar writes until simulation quiescence;
- blocks world load while a sidecar save is pending;
- restores/reset simulation authority before coherent region republish;
- exposes simulation generation/pending/persistence status in the debug HUD.

Region republish then reconstructs only derived P4.0F residency and profile bindings from the already restored authority.

## Acceptance boundary

P4.0G is an architecture/functional qualification slice. It does not by itself close P4.

The remaining P4.0H closing campaign must still exercise:

- cold startup;
- steady and high-speed streaming;
- warm revisit;
- unload/reload;
- real save/restart/load;
- content invalidation;
- maximum resident set;
- scheduler/router/lifecycle/material PERF_TRACE decomposition;
- full canonical regression;
- owner GUI/perceived-hitch acceptance;
- corrective pass for issues discovered there.

Only after that campaign and ordered integration of the stacked P4.0D-G PRs should P4 be marked complete.
