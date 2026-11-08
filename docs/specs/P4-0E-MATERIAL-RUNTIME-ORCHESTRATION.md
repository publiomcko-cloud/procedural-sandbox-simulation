# P4.0E — opt-in material runtime orchestration

Status: **IMPLEMENTED / QUALIFICATION_PENDING / NOT_MERGED**.
Dependency: P4.0D draft PR #269; branch P4.0E is based on its qualified HEAD `1a4aab148f0e905ebcbfef6690a9db042af04d3f`.

## Scope and safety

P4.0E connects the P4.0D material-domain and bounded FIFO queue to the existing P4.0A scheduler/P4.0B tier state/P4.0C runtime without introducing automatic world scans or renderer changes. It is opt-in and does not change the v2 runtime snapshot envelope: authoritative material state is already represented inside P4.0B scopes.

Engine-owned M4.0 registry profiles must be validated and bound before material work. Only **one** material queue belongs to each `SimulationRuntime`, ensuring registration, initialization, and due work share one cumulative per-frame maximum. The default budget remains 32 admitted operations; explicit accepted scope IDs are required. Registration and material initialization are separate bounded stages.

## Runtime contract

1. `configure_material_environment(registry, profile_id, budget, capacity)` validates the registry-derived pin and creates one bounded bridge. Reconfiguration in the same world is denied.
2. `enqueue_material_scope_registration(scope_id, tier)` accepts a new P4.0B scope into the same FIFO budget; scope registration is not performed synchronously. A caller must not enqueue material initialization until the registration has committed.
3. `enqueue_material_scope_initialization(scope_id, profile_id, temperature)` schedules material state creation, preserving the exact profile ID and SHA.
4. `enqueue_material_due_step(scope_id, profile_id, logical_tick)` accepts only scheduler-admitted ticks. A caller must provide relevant scope IDs explicitly; the bridge never enumerates all active/aggregate/dormant scopes.
5. `process_elapsed_usec` processes exactly one queue batch using the scheduler `frame_index`. Duplicate calls cannot exceed the queue's frame budget. `get_material_environment_metrics()` exposes queue/binding counters.

On full runtime restore, scheduler restore or tier-state restore, the material bridge is cleared and all pending transient queue work is discarded. Rebind against a validated registry before submitting additional work. Canonical material state remains in P4.0B authoritative snapshot and cannot be inferred from the transient queue.

## Remaining P4 integration work

This stage intentionally does not discover which world regions should map to simulation scopes, automatically create relevant scope feeds from terrain stream changes, persist FIFO backlog, commit renderer materials, or implement inter-scope heat transfer. Those require explicit world-identity mapping and a policy for resubmitting work after restore, rather than scanning all resident/world entities. Full cold/warm/invalidated/streaming/GUI qualification remains reserved for P4 final campaign, per ADR-0008.

## Qualification

Godot 4.7.2 import/parse, focused P4.0E runtime lifecycle tests, inherited P4.0D benchmark and P4.0A–C cumulative regression in isolated Windows self-hosted runner. No GUI/visual acceptance is claimed.
