# P4.0F — world-scope streaming lifecycle

Status: **IMPLEMENTED / SELF_HOSTED_QUALIFICATION_PENDING / NOT MERGED**.

Dependency chain: P4.0D PR #269 -> P4.0E PR #270 -> P4.0F stacked branch.

## Goal

Connect the P4.0A–E simulation foundation to the existing terrain streaming lifecycle without introducing global world scans, unbounded catch-up or renderer-owned simulation authority.

P4.0F consumes the explicit region events that already exist in `terrain_demo.gd`: region publication, focus-region change and region unload. A stable terrain region maps to exactly one simulation scope:

```text
Vector2i(x, z) -> region:x,z
```

The mapping is deterministic and independent of SceneTree node identity.

## Event-driven working set

`SimulationWorldScopeLifecycle` owns only a **derived resident index**. It never enumerates terrain nodes, all P4.0B scopes, world history or unloaded regions.

Default/hard bounds:

- resident scopes: 25 / 4,096;
- due decisions per scheduler frame: 128 / 4,096;
- terrain demo region size input: 16,000 × 12,000 mm;
- due-decision budget must be at least the resident cap so stable-ID ordering cannot starve later residents.

The demo uses `MAX_ACTIVE_REGIONS=25`, so the lifecycle working set is contractually no larger than the existing terrain residency envelope.

## Publication

After terrain publication commits its existing `active_regions` index, the demo emits `publish_world_region_scope(region_key)`.

For a never-seen region:

1. one P4.0B scope is synchronously registered as dormant;
2. the region enters the bounded derived resident set;
3. one P4.0C distance observation is submitted;
4. when a material profile is configured, P4.0D initialization is enqueued through the existing bounded material FIFO.

Registration is O(1) against P4.0B's indexed scope dictionary and occurs only on an already bounded terrain publication event. No bulk registration loop is added to the frame path.

For a resident terrain republish (LOD/edit/rebuild), the lifecycle preserves the existing logical due cursor and does not register or reinitialize the scope.

For a revisit after unload, the same deterministic scope is reused. Material state already present in P4.0B is not reinitialized.

## Focus and tier routing

Focus-region changes are forwarded explicitly by `terrain_demo.gd`.

The lifecycle recomputes observations only for its bounded resident set. Distance is an integer L-infinity region-grid distance derived from the configured region dimensions. P4.0C remains the sole automatic distance-tier policy.

Each scheduler frame performs one P4.0C routing batch before material publication. This ensures unload/focus observations affect tier authority before pending material work is committed.

## Unload

Terrain unload emits `unload_world_region_scope(region_key)`.

The lifecycle submits the P4.0C maximum-distance sentinel, removes the region from the derived resident set, and leaves its P4.0B scope/state intact. The next bounded router batch transitions that scope to dormant. Already-queued material updates therefore resolve against dormant authority and become no-ops rather than mutating an unloaded region.

No authoritative simulation scope is deleted in this slice.

## Due work and catch-up

When material simulation is enabled, each resident scope keeps a derived `next_tick` cursor.

On each P4.0A scheduler frame:

1. P4.0C pending routes are processed;
2. the lifecycle considers at most `due_decision_budget` scope/tick decisions;
3. only due decisions are enqueued into the existing P4.0D material FIFO;
4. queue-capacity backpressure does not advance the affected scope cursor, so the due tick remains retryable;
5. P4.0D then commits at most its configured cumulative material budget for that frame.

This is bounded catch-up: missed logical work is deferred by per-resident cursors rather than simulated without limit.

## Mod-first material activation

The terrain demo registers the P4.0D `material_environment_profile` handler with the same shared M4.0 registry used by procedural objects.

No engine-only fallback profile is invented.

- zero discovered profiles: world-scope lifecycle/tiering runs with material simulation disabled;
- exactly one profile: the profile is bound and material simulation is enabled;
- more than one profile: automatic material selection is disabled because selection policy belongs to explicit world/content configuration.

The handler owner remains alive for the lifetime of the terrain demo because M4.0 handler callbacks are weak-targeted.

## Restore boundary

World-scope residency, due cursors, material queue contents and bound profile caches are derived/transient. Runtime/scheduler/tier restore clears them. Authoritative P4.0B scope state survives through the existing runtime snapshot. The streaming owner must re-emit current publication/focus events after a restore; automatic resident reconstruction is intentionally not introduced here.

## Telemetry

Opt-in PERF_TRACE adds `simulation_world_scope_frame` with:

- resident count;
- router processed/pending counts;
- due decisions;
- due updates queued/deferred;
- frame index and measured duration.

Lifecycle metrics additionally expose publication/unload/focus events, registrations/revisits, material initializations, route observations, due decisions, due updates and peak residency.

The terrain debug HUD displays the core lifecycle counters.

## Qualification gates

- Godot 4.7.2 import/parser pass.
- Focused P4.0F tests cover stable identity, publish, bounded initialization, tier routing, due backlog, unload -> dormant, revisit state preservation, resident-cap rejection, resident republish and restore invalidation.
- Inherited P4.0E/D/C/B/A qualification must pass.
- Historical procedural-object baseline is interpreted under the existing qualification envelope; P4.0F must not introduce a new regression.
- No final visual/FPS acceptance is claimed in this slice.

## Deferred to later P4 work

- scalable compaction/retirement of the bounded-but-growing authoritative P4.0B/P4.0C historical scope registry;
- explicit world configuration when multiple material profiles exist;
- simulation persistence policy beyond the current runtime snapshot envelope;
- inter-region material exchange, water/climate/organism systems;
- final cold/warm/revisit/invalidation/high-speed streaming GUI performance campaign.
