# 2026-11-08 — P4.0C bounded automatic tier routing qualified

## Terminal status

`P4_0C_QUALIFIED / READY_FOR_INTEGRATION / MATERIAL_ENVIRONMENT_NOT_STARTED`

Qualified source:

- branch: `feat/p4-0c-tier-routing-policy`;
- runtime/source HEAD: `e43893505924cdf0557222193d03eb7ec0dfd933`;
- issue: #266;
- integration base: `5810a5f8b3cad19d90b3e11789b9f4186f92b7d7`;
- Godot: `4.7.2.stable.official.ed1daf0bf`;
- self-hosted runner: `sandbox`, Windows/X64.

Commits after the qualified source are limited to workflow-trigger retirement and documentary qualification records.

## Delivered architecture

P4.0C adds an engine-owned `SimulationTierRouter` above the integrated P4.0B tier authority.

Callers explicitly submit:

- stable `scope_id`;
- deterministic non-negative integer `distance_mm`.

The router does not derive distance from camera/player/world state and does not scan SceneTree, terrain, chunks, entities or history.

## Hysteresis and routing

Default provisional bands:

- active enter: 32,000 mm;
- active exit: 40,000 mm;
- aggregate enter: 96,000 mm;
- aggregate exit: 112,000 mm.

Rules provide hysteresis around both active and aggregate boundaries. This prevents oscillation when distance moves slightly around a threshold.

Tier authority remains exclusively in P4.0B. P4.0C reads the current authoritative tier/revision and commits through revision-gated P4.0B transitions.

Domain state and `state_revision` remain unchanged by routing.

## Bounded dirty queue

Observations are direct-indexed by scope ID.

Changed observations enter one deduplicated FIFO queue. Identical observations are idempotent and do not create duplicate work.

Defaults:

- max routing decisions per call: 32;
- max tracked observations: 65,536.

Hard engine ceilings:

- decisions per call: 4,096;
- tracked observations: 1,000,000;
- distance: 9e15 mm;
- scope ID length: 256.

A caller may request a smaller budget but cannot exceed the configured maximum.

Each batch preflights the selected FIFO head before consuming queue entries. Missing tier scopes reject the batch without draining pending work.

There is no hot-path global scope/world scan.

## Determinism

Qualification proves that equivalent:

- initial tier authority;
- router configuration;
- ordered observation stream;
- logical ticks;
- routing budgets;

produce identical ordered transition receipts and final tier state.

Integer distance inputs avoid float-boundary ambiguity in the routing policy.

## Snapshot evolution

P4.0C router snapshot schema 1 preserves:

- configuration;
- observations sorted by scope identity;
- exact pending FIFO order.

`SimulationRuntime` advances from snapshot schema 1 to schema 2 by adding the router snapshot.

Combined schema-2 restore validates router observation IDs against the candidate P4.0B tier registry before swapping live authority.

P4.0B runtime schema 1 remains accepted and migrates to schema 2 with an empty default router.

## Runtime surface

`SimulationRuntime` now exposes:

- `submit_simulation_scope_observation`;
- `process_simulation_tier_routes`;
- observation lookup;
- router metrics/snapshot;
- router snapshot restore.

Routing is explicit and bounded. P4.0C deliberately does not add an implicit world/camera scan to `_process`.

With `SANDBOX_PERF_TRACE=1`, routing batches emit `simulation_tier_routing_batch`.

## Qualification evidence

Final source qualification:

- workflow run: `42500313354`;
- job: `128791430490`;
- conclusion: SUCCESS;
- source: `e43893505924cdf0557222193d03eb7ec0dfd933`.

Exact markers:

- P4.0C focused: `P4_0C_ROUTER_PASS: assertions=110 failures=0`;
- P4.0B focused: `P4_0B_TIER_PASS: assertions=67 failures=0`;
- P4.0A focused: `P4_0A_FIXED_TICK_PASS: assertions=74 failures=0`;
- M4.0 focused: `M4_0_MOD_FIRST_CORE_PASS: assertions=31 failures=0`;
- declarative mods: `DECLARATIVE_MOD_PASS: assertions=79 failures=0`;
- entity commands: `ENTITY_COMMAND_PASS: assertions=67 failures=0`;
- Issue #108 D8: `ISSUE108_D8_LOD1_EFFECT_PASS: assertions=34 failures=0`;
- placement: `P3_0D_PLACEMENT_PASS: assertions=53 failures=0`;
- smoke: `SMOKE_PASS: assertions=52 failures=0`;
- terrain SDF: `TERRAIN_SDF_PASS: assertions=46 failures=0`;
- LOD0/1: `LOD01_TRANSITION_PASS: assertions=6474 failures=0`;
- bootstrap: `BOOTSTRAP_STRUCTURE_PASS: assertions=18 failures=0`;
- terminal: `SELF_HOSTED_P4_0C_QUALIFICATION_PASS`.

Accepted procedural-object envelope remains exact:

- `PROCEDURAL_OBJECT_FAIL: assertions=671 failures=1`;
- one camera-revisit failure;
- nine same-revision fingerprint conflicts;
- zero `SCRIPT ERROR`.

## Canonical validation

`scripts/validate.sh` now includes:

- P4.0C router source/test presence at L0;
- the focused P4.0C router suite at L2.

P4.0B's automatic workflow trigger is retired in favor of the cumulative P4.0C workflow; P4.0B remains manually dispatchable.

## Visual acceptance

No owner visual test is required for P4.0C itself.

This slice changes no rendering, visible world behavior, input controls or user-facing simulation output. Visual/interactive acceptance becomes mandatory when a subsequent P4 slice introduces an observable material/environment simulation or otherwise changes visible gameplay behavior.

## Explicit non-goals retained

P4.0C does not implement:

- camera/player distance derivation;
- loaded-world enumeration;
- material/environment state;
- climate/rain/moisture/water;
- domain-specific simulation;
- world-save simulation persistence;
- worker simulation jobs;
- multiplayer/network synchronization;
- executable mod callbacks.

## Handoff

P4.0C is qualified and ready for integration review.

After P4.0C integration, the architecture is ready for the first mod-first material/environment state domain without retrofitting scheduler/tier/routing mechanics.
