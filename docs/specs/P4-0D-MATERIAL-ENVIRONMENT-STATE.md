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

## Qualification gates
- Godot 4.7.2 import/parser must pass.
- Focused `game/tests/p4_0d_material_environment_tests.gd` must pass with `P4_0D_MATERIAL_PASS`.
- Existing P4.0C cumulative CI must pass, preserving its accepted historical procedural-object baseline.
- Independent review must confirm handler validation, exact pins, revision safety and absence of implicit world scans.
- Do not merge until gates pass and owner integration approval is available.

## Visual boundary and future work
This slice has no playable wiring or rendered effects, so no visual acceptance can honestly be claimed. The next slice that introduces renderer/world interaction must have a dedicated GUI acceptance gate. Future work includes content package fixtures through end-to-end discovery, runtime scope routing orchestration, integration with world identity and persistence, heat exchange/material simulation, water, climate and organisms. None are implied here.
