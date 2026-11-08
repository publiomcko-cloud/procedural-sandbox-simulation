# 2026-11-08 — P4.0B bounded simulation tier framework qualified

## Terminal status

`P4_0B_QUALIFIED / READY_FOR_INTEGRATION / DOMAIN_SIMULATION_NOT_STARTED`

Qualified source:

- branch: `feat/p4-0b-simulation-tier-framework`;
- runtime/source HEAD: `d741d1fa0711034a46ac4d57450310a365114f8b`;
- issue: #263;
- PR: #264;
- integration base: `8fbffbde03f61050f32cac41767925566be0f98a`;
- Godot: `4.7.2.stable.official.ed1daf0bf`;
- self-hosted runner: `sandbox`, Windows/X64, runner 2.338.2.

Commits after the qualified source are limited to workflow trigger retirement and documentary qualification records.

## Delivered architecture

P4.0B adds an engine-owned `SimulationTierState` beside the P4.0A `FixedTickScheduler`.

The framework defines stable simulation scopes with three explicit fidelity tiers:

- `active`: due every logical tick;
- `aggregate`: due on a deterministic coarser per-scope phase;
- `dormant`: never automatically due.

Each scope stores independent:

- `tier_revision`;
- `state_revision`;
- `last_transition_tick`;
- bounded data-only state.

Tier transitions therefore do not masquerade as domain-state mutation.

## Bounded-work properties

Hot tier APIs route directly by exact scope ID.

They do not:

- scan resident regions;
- scan entities;
- scan world history;
- enumerate all scopes each tick;
- join worker jobs;
- perform synchronous derived-world repair.

Configured engine bounds include:

- default 65,536 registered scopes;
- hard scope ceiling 1,000,000;
- aggregate interval 2..1,000,000 ticks;
- scope ID length 256;
- state depth 16;
- state node count 4,096.

Snapshot sorting is explicitly a lifecycle/persistence-style operation, not a gameplay tick path.

## State and transition semantics

Qualification proves:

- duplicate/invalid scope registration fails closed;
- non-data/executable payloads are rejected;
- caller state is deep-copied;
- returned scope records cannot mutate authority;
- same-tier transition is an idempotent no-op;
- stale tier revision rejects without mutation;
- stale state revision rejects without mutation;
- state replacement increments only `state_revision`;
- tier transition increments only `tier_revision`;
- `active -> aggregate -> dormant -> active` preserves state payload and state revision exactly.

## Deterministic cadence

Aggregate cadence uses a stable engine-owned 32-bit FNV-1a-style hash of exact scope ID to derive a phase within the configured aggregate interval.

Qualification proves that aggregate phase and future due decisions are independent of registration order.

Dormant scopes preserve authority while producing no automatic due cadence.

P4.0B does not scan all registered scopes to discover due work. Future domain systems must already have a bounded routed scope set and ask for due decisions by identity.

## Runtime snapshot

`SimulationRuntime` now owns:

- one P4.0A scheduler;
- one P4.0B tier-state registry.

Combined runtime snapshot schema 1 captures:

- fractional microsecond adapter carry;
- scheduler authority;
- tier/state authority.

Restore validates independent candidate scheduler and tier registries before either is committed to live runtime state.

## Observability

With `SANDBOX_PERF_TRACE=1`, committed runtime tier transitions emit:

`simulation_tier_transition`

including scope ID, logical tick, source/target tier, tier revision, state revision and duration.

Tier metrics expose bounded registration/transition/due counters and tier counts without exposing mutable authority.

## Qualification evidence

Final self-hosted Actions run:

- workflow run: `42498105014`;
- job: `128784719484`;
- conclusion: SUCCESS;
- source: `d741d1fa0711034a46ac4d57450310a365114f8b`.

Exact markers:

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
- P4.0B envelope: `SELF_HOSTED_P4_0B_QUALIFICATION_PASS`.

Procedural-object suite preserved the exact accepted historical envelope:

- `PROCEDURAL_OBJECT_FAIL: assertions=671 failures=1`;
- exactly one `ERROR: FAIL: camera-driven revisit republishes the original region`;
- exactly nine `effect_projection_same_revision_fingerprint_conflict`;
- zero `SCRIPT ERROR`.

No new regression was introduced.

## Self-hosted CI hardening discovered during qualification

After the runner was converted from an interactive process to a Windows service under `NT AUTHORITY\NetworkService`, two user-profile assumptions were exposed:

1. `pwsh` was not on the service account PATH;
2. Windows PowerShell execution policy rejected temporary scripts generated by an Actions `shell: powershell` step.

The repository no longer depends on either assumption.

Active Windows workflows now:

- use `cmd` for inline steps;
- invoke versioned PowerShell scripts explicitly with `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ...`;
- keep fork PRs off the owner's self-hosted machine;
- use clean checkout without persisted credentials;
- isolate Godot `APPDATA` under runner temp;
- capture native Godot stderr without treating the accepted historical procedural failure as a PowerShell terminating error.

This was validated by the final P4.0B run above.

## Architecture boundaries retained

ADR-0007 remains satisfied:

- tier mechanics are engine-owned;
- no executable mod callbacks were introduced;
- no first-party-only simulation data path was created.

ADR-0008 remains satisfied:

- tier operations are bounded/direct-routed;
- no global simulation scan exists;
- no gameplay-frame join exists;
- cadence does not imply unbounded catch-up;
- transition telemetry is stage-specific.

P4.0A scheduler behavior remains unchanged.

## Explicit non-goals retained

P4.0B does not implement:

- domain-specific aggregation/reduction;
- automatic distance/radius tier assignment;
- materials or environmental state;
- climate/rain/moisture/water;
- organism/entity simulation systems;
- world-save tier persistence;
- simulation worker jobs;
- multiplayer/network synchronization;
- executable mod callbacks.

## Handoff

P4.0B is qualified and PR #264 is ready for source/integration review.

Merge remains an explicit owner decision.

After integration, the next P4 slice should be selected explicitly between:

- bounded automatic tier-assignment/routing policy; or
- the first mod-first material/environment state domain using this scheduler+tier foundation.

Neither is part of P4.0B.
