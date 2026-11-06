# Mod-first Runtime Contract — pre-Issue #108

Status: implementation contract for Issue #230, owner-authorized 2026-11-05.

## Purpose

Make first-party and external content peers before terrain-object SDF integration or additional content is added. Engine/runtime code may know supported content *types, schemas and algorithms*; it must not require a concrete package, definition or art/profile identity to operate.

Issue #108 may consume this contract but must not bypass it.

## Invariants

1. **One discovery path.** Normal runtime discovers bundled `res://mods/first-party` and installed `user://mods`. Repository `mods/examples` is documentation/test content and is not a hidden runtime dependency.
2. **One registry path.** First-party and external packages are validated and registered by `DeclarativeModLoader` + `ContentDefinitionRegistry`.
3. **No content-ID dependency in core runtime.** Object streaming and world generation operate on registered rules/definitions. Concrete package IDs, definition IDs and geological profile names belong to package data/tests, not runtime branching.
4. **Algorithms are engine contracts; profiles are data.** `geological_halfspace_v1` is an engine-supported algorithm with bounded parameters. A valid versioned profile identifier does not require a source-code allowlist.
5. **Compatibility is data, not content branching.** Historical P2 compatibility instances are represented by `p2a_compatibility_slot_v1` rules. Existing slot values preserve the historical identity/seed formula when those rules are present; the engine does not require a fixed granite/basalt set.
6. **Missing optional content is not substituted.** Removing an external package removes its derived content. The runtime must not silently replace it with first-party content or load a repository example.
7. **Persistent references remain pinned.** Entity placement and procedural instances resolve namespaced definitions through the registry and carry content/rule pins. Invalid or unavailable referenced content fails explicitly.
8. **No package code execution.** This contract remains data-only. Trusted scripted mods are a separate future contract.
9. **Gameplay selection is capability-driven.** Player/editor placement enumerates registered definitions compatible with the supported geometry algorithm and selects deterministically from that registry result. Gameplay code must not prefer a first-party package or definition ID.

## Terrain-interaction capability

A new data-only content record type, `terrain_interaction_rule`, declares a definition-owned future terrain interaction without changing object definition schemas or entity save schemas.

Schema version 1 exact fields:

- `schema_version`: `1`
- `type`: `terrain_interaction_rule`
- `id`: namespaced rule ID owned by the same package as the target definition
- `definition_id`: namespaced procedural-object definition in that package
- `algorithm`: `sdf_ground_imprint_v1`
- `shape_source`: `recipe_envelope_v1`
- `operation`: `subtract_solid_v1`
- `embed_depth_mm`: integer 0..3000
- `blend_radius_mm`: integer 0..2000
- `edit_order`: `terrain_edits_then_imprint_v1`

A package cannot attach or override a terrain interaction for another package's definition. At most one terrain-interaction rule may bind a definition.

The registry resolves the rule by `definition_id` and returns a deterministic pin containing rule ID, definition ID, package ID/version, rule schema/algorithm and SHA-256 of the canonical rule.

## Pre-#108 behavior

Generated procedural instances and explicitly placed entities carry:

- `terrain_interaction`
- `terrain_interaction_pin`
- `terrain_interaction_applied = false`

No terrain density, edit ledger, materialized tile, mesh or persistence state is modified by this issue. The descriptor is deliberately inert. Issue #108 must consume the pinned descriptor rather than inspect granite/basalt/package IDs.

This separation prevents the future imprint implementation from requiring object schema migration merely to express terrain contact.

## Geological profile contract

For `geological_halfspace_v1`, `profile` is a bounded versioned data identifier matching:

`^[a-z][a-z0-9_]*_v[1-9][0-9]*$`

The adapter validates algorithm parameters and geometry safety bounds, not granite/basalt profile names. Existing granite/basalt values retain their data and deterministic behavior; future valid profiles can use the same adapter without engine edits.

## Runtime package policy

Normal runtime roots are:

- `res://mods/first-party`
- `user://mods`

`mods/examples` may be copied into `user://mods` by tests/developers to exercise a true external installation path. It is never auto-loaded as fallback production content.

A first-party-only installation is valid.

## Issue #108 requirement

Terrain-object SDF integration must:

- enumerate/resolve terrain interaction through the registry;
- use only the versioned rule/algorithm fields and instance transform/seed data;
- preserve content pin validation and deterministic order;
- make no branch on package ID, definition ID, display name, tag or profile name;
- keep the rule's effect separate from renderer mesh authority;
- persist the exact terrain-interaction pin in the terrain-side imprint/effect operation when the effect becomes authoritative, rather than migrating entity identity solely to remember the rule;
- define replay/recovery/ordering against player CARVE/FILL before enabling `terrain_interaction_applied`.

## Verification

Required qualification:

- first-party-only runtime initialization;
- first-party + installed external package through the same root/registry path;
- generic third geological profile accepted and meshable without engine changes;
- deterministic terrain-interaction resolution/pinning;
- cross-package interaction override rejected;
- historical compatibility IDs/seeds unchanged when old rules are present;
- entity placement carries the same capability metadata;
- procedural object/population, entity-command and canonical regressions;
- repeated runtime performance baseline plus existing object density/publication metrics.

Godot version: 4.7.2 stable. Canonical repository validation entrypoint remains `scripts/validate.sh`.
