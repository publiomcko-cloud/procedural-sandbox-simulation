# P4.0B — bounded simulation tier/state framework

## Status

Implementation candidate for Issue #263.

P4.0B builds on the integrated P4.0A fixed-tick scheduler. It defines simulation fidelity authority but does not implement a material, climate, water, organism or gameplay simulation system.

## Goals

Provide an engine-owned deterministic foundation for three simulation fidelity tiers:

- `active`: eligible every logical tick;
- `aggregate`: eligible on a deterministic coarser cadence;
- `dormant`: never automatically due.

The framework must preserve authoritative state across tier changes and remain bounded under ADR-0008.

## Non-goals

P4.0B does not implement:

- domain-specific reduction/aggregation algorithms;
- automatic distance/radius-based tier assignment;
- materials or environmental simulation;
- climate, rain, moisture or water;
- organisms/entities as simulation systems;
- worker jobs;
- world-save persistence;
- multiplayer/network synchronization;
- executable mod callbacks.

## Engine ownership

Tier mechanics are engine-owned.

Mods and future first-party simulation definitions remain subject to ADR-0007's data-only content path. No mod callback or script can define transition behavior in this slice.

The framework is identity-routed by stable `scope_id`. It does not scan world regions, resident chunks or entities to find relevant state.

## Simulation scope record

Each registered simulation scope has:

- `scope_id`: stable exact string identity;
- `tier`: `active | aggregate | dormant`;
- `tier_revision`: increments only when the tier actually changes;
- `state_revision`: increments only when the data-only state payload actually changes;
- `last_transition_tick`: logical scheduler tick of the last committed tier transition;
- `state`: bounded data-only dictionary;
- derived `aggregate_phase`: stable phase from scope identity and aggregate cadence.

Separating tier and state revisions is required so fidelity changes do not pretend to mutate conserved domain state.

## State payload contract

The P4.0B registry owns a generic data-only state envelope. It deliberately does not interpret domain semantics.

Allowed payload values are bounded recursively and may contain:

- nil/bool/int/float/string;
- Godot value types such as vectors, transforms, color, basis and AABB;
- arrays;
- dictionaries with string keys.

Rejected payload content includes:

- Object/RefCounted/Node references;
- Callables/signals/RIDs;
- non-string dictionary keys;
- data deeper than 16 levels;
- more than 4096 visited state nodes.

This keeps the generic authority serializable/data-only and prevents executable state from entering the tier layer.

## Bounds

Default configuration:

- aggregate interval: 10 logical ticks;
- maximum registered scopes: 65,536.

Hard engine bounds:

- aggregate interval: 2..1,000,000 ticks;
- maximum scopes: 1,000,000;
- scope ID length: 256 characters;
- state depth: 16;
- state nodes: 4096.

These are engine safety bounds, not product tuning values.

## Registration

Registration is direct by exact scope ID.

A registration:

1. validates ID, tier, capacity and data-only state;
2. canonicalizes nested dictionary ordering;
3. deep-copies caller state;
4. commits one record and one tier-count increment.

Duplicate IDs fail closed.

Reads return isolated copies; callers cannot mutate authoritative records through a returned dictionary.

## Tier transitions

`transition_scope(scope_id, target_tier, logical_tick, expected_tier_revision)` is an O(1) identity-routed mutation.

Rules:

- target tier must be legal;
- logical tick must be non-negative;
- optional expected revision gates stale callers;
- same-tier transition is an idempotent no-op;
- committed transition increments only `tier_revision`;
- `state` and `state_revision` remain unchanged;
- tier counts are adjusted without scanning other scopes.

A roundtrip:

`active -> aggregate -> dormant -> active`

must preserve the state payload and state revision exactly.

## State replacement

`replace_scope_state` is independently revision gated.

Rules:

- validated/canonical data only;
- expected state revision may reject stale mutation;
- identical replacement is an idempotent no-op;
- committed replacement increments only `state_revision`;
- tier and tier revision remain unchanged.

P4.0B does not define domain meaning for the payload. Future material/environment systems will own that semantic layer.

## Cadence

### Active

Every non-negative logical tick is due.

### Aggregate

Each scope gets a deterministic phase derived from its exact scope ID using an engine-owned stable FNV-1a-style 32-bit hash.

A scope is due when:

`logical_tick % aggregate_interval_ticks == aggregate_phase`

The phase is independent of registration order and visit order.

P4.0B does not enumerate all aggregate scopes each tick. A simulation system asks for the due decision of an already-routed scope ID.

### Dormant

Never automatically due.

Dormant state is preserved but incurs no automatic simulation cadence in this layer.

## Snapshot

Tier snapshot schema 1 contains:

- schema version;
- aggregate interval;
- maximum scope capacity;
- scope records sorted by scope ID.

Derived aggregate phase is not serialized; it is reproduced from scope ID and configuration.

Restore validates the complete candidate before committing authority.

## Runtime integration

The existing `SimulationRuntime` owns:

- one `FixedTickScheduler`;
- one `SimulationTierState`.

New runtime APIs expose:

- scope registration;
- revision-gated tier transition;
- revision-gated state replacement;
- scope lookup;
- due decision;
- tier snapshot/metrics;
- combined runtime snapshot/restore.

The combined runtime snapshot schema also preserves the fractional microsecond carry used by P4.0A's frame-delta adapter.

Combined restore validates scheduler and tier candidates before swapping either into live runtime state.

## Performance and observability

Hot APIs use direct scope lookup and bounded payload work. There is no resident-world scan or history scan.

Snapshot creation is explicitly a lifecycle/persistence-style operation and may sort registered IDs; it is not a gameplay tick path.

When `SANDBOX_PERF_TRACE=1`, committed runtime tier transitions emit:

`simulation_tier_transition`

with:

- scope ID;
- logical tick;
- source/target tier;
- tier revision;
- state revision;
- duration.

## Security / self-hosted CI

The self-hosted Windows workflow is restricted to pull requests whose head repository is the same repository, so fork PR code is not executed on the owner's machine.

Qualification uses Godot 4.7.2 from:

`C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`

and runs the P4.0B focused suite followed by the full accepted P4.0A regression envelope.

## Acceptance

P4.0B is qualified only when:

- focused tier tests pass;
- P4.0A focused tests remain green;
- M4/declarative/entity/D8/placement regressions remain green;
- procedural-object exact historical envelope remains unchanged;
- smoke/SDF/LOD/bootstrap/startup remain green;
- self-hosted Windows Actions completes successfully.
