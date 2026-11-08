# 2026-11-08 — P4.0A fixed-tick scheduler implementation candidate

## Status

`P4_0A_IMPLEMENTED / QUALIFICATION_PENDING / P4_TIERS_NOT_STARTED`

Issue:

- #257 — P4.0A fixed-tick scheduler foundation.

Integration base:

- M4.0 PR #256 merged into `main`;
- merge commit: `ca13d91a4917e8061528736e5b6d808dc9b85576`.

Implementation branch:

- `feat/p4-0a-fixed-tick-scheduler`.

## Implemented architecture

### Pure fixed-tick core

New:

`game/scripts/simulation/fixed_tick_scheduler.gd`

The scheduler is engine-owned and stores only logical scheduler authority:

- fixed tick duration;
- current logical tick;
- sub-tick integer-microsecond accumulator;
- scalar deferred backlog;
- bounded per-frame admission;
- paused state;
- bounded manual-step queue;
- schema-1 scheduler snapshot;
- non-authoritative telemetry counters.

The core does not:

- access SceneTree;
- inspect world/entity state;
- execute mod callbacks;
- run WorkerThreadPool jobs;
- publish render resources;
- own material/environment state.

### Playable runtime adapter

New:

`game/scripts/simulation/simulation_runtime.gd`

The adapter:

- converts Godot frame `delta` to integer microseconds;
- carries fractional microseconds between frames;
- drives the pure scheduler;
- exposes pause/resume/manual-step/snapshot APIs;
- emits opt-in `simulation_scheduler_frame` PERF_TRACE records.

The playable terrain scene now mounts exactly one `SimulationRuntime` node.

No gameplay simulation system consumes ticks in P4.0A.

### Catch-up policy

Default foundation configuration:

- tick: 100,000 usec / 10 Hz;
- maximum admitted ticks per frame: 4.

Missed ticks become scalar backlog. One frame never loops over the entire missed interval.

Backlog drains incrementally on later frames, including zero-elapsed drain calls.

No due tick is silently dropped by the scheduler core.

### Pause and manual step

Paused mode ignores real elapsed time while preserving:

- sub-tick accumulator;
- deferred backlog.

Manual steps:

- require pause;
- are bounded to 1,024 queued requests;
- obey the same per-frame admission ceiling;
- must drain before resume.

### Snapshot/replay contract

Scheduler snapshot schema 1 is exact and fail-closed.

It captures logical scheduler authority but excludes telemetry.

Restore is qualified by continuation equivalence rather than telemetry identity.

P4.0A does not yet persist scheduler snapshots into world saves.

## Focused qualification

New:

`game/tests/p4_0a_fixed_tick_scheduler_tests.gd`

The focused suite covers:

- invalid configuration bounds;
- exact fixed-tick cadence;
- sub-tick accumulation;
- input rejection atomicity;
- bounded catch-up;
- deferred backlog drain;
- frame-slicing convergence;
- large backlog as scalar deferred state;
- pause semantics;
- bounded manual step;
- resume gate;
- snapshot validation;
- snapshot restore and deterministic continuation;
- runtime delta adapter;
- one-shot runtime result consumption;
- playable scene mount.

## Canonical validation

`scripts/validate.sh` now:

- requires both simulation scripts and the focused P4.0A test at L0;
- runs the P4.0A focused scheduler suite at L2.

The P4.0A workflow also requires:

- import/parser;
- focused P4.0A;
- M4.0 focused;
- declarative mods;
- entity commands;
- Issue #108 D8;
- placement;
- exact procedural-object known baseline;
- canonical validation;
- main-scene startup.

## Architecture boundaries retained

ADR-0007 remains binding:

- scheduler mechanics are engine-owned;
- P4/P5 data definitions must use M4.0 content handlers when introduced;
- no executable mod scheduler callbacks.

ADR-0008 remains binding:

- catch-up work is bounded per frame;
- no world/history scans;
- no gameplay-frame worker joins;
- telemetry exposes backlog/admission pressure.

## Explicit non-goals

P4.0A does not implement:

- active/aggregate/dormant tiers;
- material or environment state;
- climate/water;
- gameplay simulation systems;
- world-save scheduler persistence;
- simulation worker jobs;
- user-facing pause/step controls;
- scripted mods.

## Next gate

Run exact Godot 4.7.2 owner-local qualification on the final PR source.

If the focused scheduler and regression envelope pass, P4.0A can be marked ready for integration. P4.0B tier/state work remains blocked until that qualification and owner merge decision.
