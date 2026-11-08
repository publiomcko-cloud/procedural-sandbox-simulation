# 2026-11-08 — P4.0A fixed-tick scheduler qualified

## Terminal status

`P4_0A_QUALIFIED / READY_FOR_INTEGRATION / P4_TIERS_NOT_STARTED`

Qualified runtime source:

- branch: `feat/p4-0a-fixed-tick-scheduler`
- source HEAD: `f9318644da1458a8b7633f3bd3a0fd81c51288f5`
- PR: #258
- issue: #257
- integration base: M4.0 merge `ca13d91a4917e8061528736e5b6d808dc9b85576`
- Godot: `4.7.2.stable.official.ed1daf0bf`

This checkpoint is the final qualification receipt for P4.0A.

## Delivered foundation

P4.0A establishes the engine-owned fixed-tick scheduler layer required before simulation tiers or material/environment state.

Qualified behavior includes:

- deterministic integer-microsecond fixed cadence;
- monotonic logical tick identity;
- exact sub-tick accumulation;
- bounded ticks admitted per frame;
- scalar deferred catch-up backlog;
- hard backlog bound with atomic overflow rejection;
- pause/resume;
- bounded manual-step queue;
- exact schema-1 scheduler snapshot/restore;
- replay continuation independent of telemetry counters;
- runtime `delta` conversion with fractional microsecond carry;
- atomic adapter carry on rejected scheduler input;
- opt-in `simulation_scheduler_frame` PERF_TRACE telemetry;
- exactly one `SimulationRuntime` mounted in the playable terrain scene.

No gameplay simulation system consumes ticks in this slice.

## Owner-local qualification evidence

Godot 4.7.2 owner-local evidence on the qualified source HEAD:

- import/parser: PASS;
- global class registration: `FixedTickScheduler`, `SimulationRuntime`;
- focused P4.0A: `P4_0A_FIXED_TICK_PASS: assertions=74 failures=0`;
- M4.0 focused: `M4_0_MOD_FIRST_CORE_PASS: assertions=31 failures=0`;
- declarative mods: `DECLARATIVE_MOD_PASS: assertions=79 failures=0`;
- entity commands: `ENTITY_COMMAND_PASS: assertions=67 failures=0`;
- Issue #108 D8: `ISSUE108_D8_LOD1_EFFECT_PASS: assertions=34 failures=0`;
- P3.0D placement: `P3_0D_PLACEMENT_PASS: assertions=53 failures=0`;
- smoke: `SMOKE_PASS: assertions=52 failures=0`;
- terrain SDF: `TERRAIN_SDF_PASS: assertions=46 failures=0`;
- focused P4.0A repeated inside canonical Windows-equivalent validation: 74/74;
- LOD0/1 transition: `LOD01_TRANSITION_PASS: assertions=6474 failures=0`;
- bootstrap structure: `BOOTSTRAP_STRUCTURE_PASS: assertions=18 failures=0`;
- main-scene startup: `STARTUP_EXIT=0`.

Procedural-object regression preserved the exact accepted historical envelope:

- `PROCEDURAL_OBJECT_FAIL: assertions=671 failures=1`;
- exactly one `ERROR: FAIL: camera-driven revisit republishes the original region`;
- exactly nine `effect_projection_same_revision_fingerprint_conflict`;
- zero `SCRIPT ERROR`.

No new procedural regression was introduced.

## Determinism and bounded-work conclusions

Qualification proves:

- equivalent elapsed logical time converges to the same authoritative scheduler state independent of frame slicing after backlog drain;
- one frame never admits more than the configured tick budget;
- large catch-up is represented as scalar deferred backlog rather than same-frame work proportional to missed ticks;
- pause excludes real elapsed time from logical simulation progress;
- manual steps obey the same admission bound;
- scheduler restore reproduces the same next admitted batch and later authoritative state;
- invalid configuration, snapshot, elapsed and backlog-overflow inputs fail closed without partial authoritative mutation.

These satisfy the P4.0A portions of ADR-0008's bounded catch-up and observability requirements.

## Hosted CI

GitHub Actions on PR #258 repeatedly failed before step allocation/execution.

Latest observed P4.0A run on the qualified source:

- run: `42488754547`;
- job: `128756276782`;
- conclusion: failure;
- steps: `null`;
- logs: unavailable.

Other repository workflows failed at the same commit in the same mode. This remains classified as hosted runner infrastructure failure, not a code verdict.

Owner-local Godot evidence is therefore authoritative for this qualification.

## Architecture boundaries retained

ADR-0007 remains satisfied:

- scheduler mechanics are engine-owned;
- no executable mod callback surface exists;
- no simulation/material/environment first-party-only data path was introduced.

ADR-0008 remains satisfied:

- catch-up admission is bounded;
- backlog work is incremental;
- there are no world/history scans;
- there are no gameplay-frame worker joins;
- scheduler pressure is observable through stage-level telemetry.

## Explicit non-goals retained

P4.0A does not implement:

- active/aggregate/dormant tiers;
- material/environment state;
- climate, rain, moisture or water;
- gameplay simulation systems;
- world-save scheduler persistence;
- simulation worker jobs;
- user-facing pause/step controls;
- scripted mods.

## Handoff

P4.0A is qualified and PR #258 is ready for integration.

Merge still requires explicit owner authorization.

After integration, the next P4 slice should introduce the bounded tier/state framework on top of this scheduler without changing the scheduler's deterministic/bounded contract.
