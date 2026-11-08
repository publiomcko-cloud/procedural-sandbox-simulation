# P4.0D — Material/environment state domain (candidate)

Status: **IMPLEMENTED / SELF_HOSTED_QUALIFICATION_PENDING / NOT MERGED**.
Issue: #268. Base: `main` after P4.0C integration.

## Goal
Introduce a first bounded and deterministic environment domain without modifying P4.0A–C engine authority, procedural terrain, rendering, save formats or general mod discovery. It is not a complete material simulation system.

## Data-only schema 1
Engine-registered M4.0 type handler: `material_environment_profile`. Strict record fields:
- `schema_version: 1`
- `type: "material_environment_profile"`
- `id: "<mod_id>:<local_id>"`
- `ambient_temperature_milli_c: int`, bounded to ±1,000,000
- `relaxation_milli_per_due_step: int`, range 0–1,000

M4.0 generic registry must register the handler **before** loading the mod packages, as for every non-builtin type. Keep the `MaterialEnvironmentDomain` owner alive: M4.0 handlers use weak callback targets. First-party and external mods are to use identical handler and discovery semantics. No scripts in content records.

## State contract
State is stored within the existing authoritative P4.0B scope `state["material_environment"]`, containing the exact four fields `profile_id`, `profile_sha256`, `temperature_milli_c` and `last_due_tick`. State changes use `replace_scope_state` with expected `state_revision`; unrelated scope state and tier revision remain unchanged.

The environment domain checks the canonical SHA-256 against the passed data-only profile. The caller is responsible for resolving/version-validating the full pin via M4.0. Profiles are not tied to an executable mod callback.

`process_due_scope` asks the tier authority for the specified scope and logical tick. Active scopes are due each tick, aggregate scopes only on configured cadence, dormant scopes never advance. On due steps, the integer temperature moves by `floor(abs(ambient-current)*relaxation_milli/1000)` toward the ambient value, never overshooting. Only one step is applied per due decision; aggregate behavior is deliberately per-due-step rather than per-elapsed-time integration. The last applied tick prevents duplicate advances. Callers schedule a bounded set of scope IDs themselves; **this domain does not enumerate all scopes, derive distances or mutate ticks**.

## P4.0D bounded performance correction

The original `process_due_scope` API remains a checked one-off/legacy route and still recomputes the fingerprint to protect callers passing mutable profile dictionaries. It is not intended for per-frame use.

The preferred hot path is explicit:

1. Register the engine-owned profile handler before M4.0 package discovery.
2. Cold-bind each profile through `bind_registry_profile(registry, profile_id)`. The registry validates the six-field content fingerprint, then the domain recomputes canonical SHA-256 only once per binding. This derived binding is **not authority** and can be discarded with `clear_profile_bindings` on package reload.
3. Initialize scope state with `initialize_bound_scope_state`, preserving the authoritative profile SHA in the scope.
4. Enqueue new-scope cold initialization via `MaterialEnvironmentWorkQueue.enqueue_initialization`, then enqueue explicit `scope_id + profile_id + logical_tick` due work through `MaterialEnvironmentWorkQueue.enqueue`. Both item types consume the same global per-frame admission budget; initialization is not automatically performed during sampling.
5. Invoke `process_pending(tier_state, frame_index, requested_budget)` with a monotonic explicit frame identifier. The ring buffer admits at most 32 items **in total across all calls in one frame** by default, at most 4,096 configured hard ceiling, and tracks at most 8,192 pending items by default (65,536 hard maximum). Repeating a call within the same frame cannot bypass the budget, and out-of-order frame identifiers fail closed. Pending work remains deferred, never silently drained. Duplicate scope/profile/tick observations are idempotent.
6. Every commit still compares the scope's pinned SHA and performs state revision-gated replacement; profile drift fails closed. Queue results preserve FIFO order. Failure leaves the failing work item pending; recovery requires an explicit corrective action. The queue is transient and not persisted as world authority.

Queue metrics expose accepted/deduplicated/processed/deferred counts; opt-in `material_environment_batch` PERF_TRACE reports processed count, pending count and the configured budget. No implicit `_process` loop, world scan, worker join, hash or profile JSON normalization is introduced into the bound due-update path. State copies and tier authority calls remain bounded per scope and require dense-scene performance measurements before gameplay integration.

Cold/warm binding behavior, bounded cold initialization, a 20-scope dense batch, backlog saturation, FIFO delivery and snapshot-driven state recovery are exercised in the focused suite. The dedicated 100/1,000/10,000-scope headless benchmark reports registration separately from frame-bounded initialization and due-update P50/P95/P99/max; it is not a gameplay FPS certification. These are functional/structural checks, **not** measured frame-time certification. Bindings must be rebuilt against a validated registry after content reload or world restore.

## Qualification gates
- Godot 4.7.2 import/parser must pass.
- Focused `game/tests/p4_0d_material_environment_tests.gd` must pass with `P4_0D_MATERIAL_PASS`.
- Existing P4.0C cumulative CI must pass, preserving its accepted historical procedural-object baseline.
- Independent review must confirm handler validation, exact pins, revision safety and absence of implicit world scans.
- Do not merge until gates pass and owner integration approval is available.

## Visual boundary and future work
This slice has no playable wiring or rendered effects, so no visual acceptance can honestly be claimed. The next slice that introduces renderer/world interaction must have a dedicated GUI acceptance gate. Future work includes content package fixtures through end-to-end discovery, runtime scope routing orchestration, integration with world identity and persistence, heat exchange/material simulation, water, climate and organisms. None are implied here.
