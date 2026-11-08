# P4.0A — Fixed-tick scheduler foundation

- **Issue:** #257
- **Status:** implementation candidate
- **Depends on:** M4.0 / ADR-0007, ADR-0008
- **Godot baseline:** 4.7.2 stable

## Purpose

P4.0A establishes the engine-owned logical clock and bounded tick admission layer required by P4 before simulation tiers, materials or environmental state are introduced.

The scheduler is infrastructure. It does not execute mod code and it does not define gameplay content.

## Architecture

### Pure scheduler core

`FixedTickScheduler` is a `RefCounted` deterministic core driven by integer elapsed microseconds.

It owns:

- fixed tick duration;
- logical tick index;
- sub-tick accumulator;
- deferred tick backlog;
- maximum ticks admitted per frame;
- paused state;
- bounded manual-step queue;
- authoritative scheduler snapshot;
- non-authoritative telemetry counters.

It does **not** own:

- SceneTree nodes;
- world/entity state;
- render resources;
- WorkerThreadPool tasks;
- mod callbacks;
- material/environment simulation.

### Scene adapter

`SimulationRuntime` is the playable SceneTree adapter.

It converts Godot frame `delta` to integer microseconds while retaining fractional microseconds across frames, invokes the pure scheduler, and emits opt-in `PERF_TRACE` records.

The playable terrain scene mounts one `SimulationRuntime`.

No gameplay system consumes ticks in P4.0A.

## Fixed cadence

The initial runtime defaults are:

- tick duration: `100_000 usec` (10 Hz);
- maximum admitted ticks per frame: `4`.

These are engine configuration defaults for the foundation, not final gameplay tuning.

The scheduler API accepts explicit values for deterministic tests and later engine configuration.

## Bounded catch-up

Missed logical time is converted into a scalar deferred backlog.

Each frame can admit at most `max_ticks_per_frame`.

A large backlog therefore changes an integer counter, not the amount of same-frame loop work.

Zero-elapsed later frames may drain the backlog incrementally.

No missed tick is silently dropped by the scheduler core.

## Pause and step

Paused simulation:

- does not accumulate real elapsed time;
- preserves the existing sub-tick accumulator and deferred backlog;
- may accept a bounded manual-step queue;
- admits manual steps under the same per-frame tick budget.

Resume is rejected while requested manual steps are still queued.

## Snapshot contract

Authoritative scheduler snapshot schema 1 contains exactly:

- `schema_version`;
- `tick_usec`;
- `max_ticks_per_frame`;
- `current_tick`;
- `accumulator_usec`;
- `backlog_ticks`;
- `manual_step_ticks`;
- `paused`.

Telemetry counters are deliberately excluded from authoritative state.

Snapshot restore resets telemetry and preserves logical evolution.

P4.0A does not persist this snapshot into the world save schema yet. Persistence integration belongs to a later P4 slice once simulation state authority is defined.

## Determinism boundary

The canonical deterministic API is integer `process_elapsed_usec()`.

The runtime adapter's floating frame `delta` is presentation/runtime input and is converted with fractional carry.

Replay qualification compares authoritative logical state, not wall-clock timing or telemetry counters.

## Bounds

Engine hard bounds include:

- maximum tick duration: 60 seconds;
- maximum ticks admitted per frame: 64;
- maximum queued manual steps: 1024;
- maximum elapsed interval accepted by one scheduler call: 24 hours.

These are defensive work/input bounds, not gameplay design values.

## Performance observability

With `SANDBOX_PERF_TRACE=1`, tick-bearing/backlogged runtime frames emit:

`simulation_scheduler_frame`

Fields include:

- elapsed microseconds;
- scheduler frame index;
- source (`elapsed` or `manual_step`);
- first/last admitted tick;
- admitted tick count;
- newly due tick count;
- deferred backlog;
- pending manual steps;
- paused state;
- scheduler processing duration.

Tracing remains quiet by default.

## Acceptance requirements

P4.0A is qualified only if:

1. invalid scheduler configuration fails closed;
2. exact tick boundaries advance deterministic logical IDs;
3. sub-tick elapsed time is retained exactly;
4. per-frame admitted ticks never exceed the configured bound;
5. large catch-up becomes deferred scalar backlog;
6. deferred backlog drains without dropped ticks;
7. equivalent elapsed time converges to the same authoritative state independent of frame slicing;
8. pause ignores real elapsed time;
9. manual steps require pause and obey queue/admission bounds;
10. snapshot/restore reproduces the same next admitted batch and later authoritative state;
11. rejected elapsed/snapshot inputs do not mutate authoritative state;
12. the playable scene mounts one engine-owned `SimulationRuntime`;
13. M4.0/P3/Issue #108 regression envelopes remain unchanged.

## Explicit non-goals

P4.0A does not implement:

- active/aggregate/dormant tiers;
- simulation system registration;
- material/environment state;
- climate, rain, moisture or water;
- gameplay-facing pause/step UI;
- scheduler persistence in world saves;
- worker simulation jobs;
- scripted mods;
- mod-controlled scheduler mechanics.

Future data-driven simulation definitions must enter through M4.0 content handlers. Scheduler mechanics remain engine-owned.
