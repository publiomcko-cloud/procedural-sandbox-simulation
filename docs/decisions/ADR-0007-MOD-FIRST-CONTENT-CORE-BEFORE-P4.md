# ADR-0007 — Generalize the mod-first content core before P4

- **Status:** accepted by owner on 2026-11-07.
- **Date:** 2026-11-07.
- **Decision scope:** pre-P4 architecture gate M4.0.
- **Builds on:** P0.3 declarative mod loader/registry, P2.0A/B/C procedural content and state, P3 entity commands, Issue #108 terrain-object integration.
- **Supersedes:** no accepted behavior. Existing content IDs, pins, save semantics and runtime behavior remain authoritative until an explicit migration says otherwise.

## Context

The project already has a working mod-first foundation for procedural objects:

- bundled first-party packages and installed `user://mods` packages enter through the same declarative discovery path;
- manifests provide namespaced IDs, exact versions, dependencies, content roots and `script_policy=data_only`;
- dependency order, path safety and bounded package/content counts are validated before registration;
- deterministic object definitions, static population rules and terrain-interaction rules are registered and version-pinned;
- first-party and external content use the same procedural world generation, persistence, entity command and terrain-effect pipelines;
- entity state remains authoritative and render/terrain-effect representations are derived.

The current `ContentDefinitionRegistry`, however, is still domain-specific. It directly knows the schemas and validation logic for:

1. `procedural_rock`;
2. `static_population_rule`;
3. `terrain_interaction_rule`.

That is acceptable for P2/P3, but P4/P5 will introduce additional content families for simulation, materials and environmental behavior. Extending the current registry by hard-coding every new family would turn it into a monolithic switchboard and force later retrofits across persistence, pinning and simulation.

The base terrain generator, streaming, LOD, persistence machinery and concurrency policy are engine infrastructure. They are not required to become mod-owned. Mod-first means that content and declarative behavior use public versioned contracts, not that mods control engine scheduling or world authority.

## Decision

### 1. M4.0 is a mandatory architecture gate before P4

P4 implementation does not begin until M4.0 generalizes the content core without changing current gameplay behavior.

M4.0 is an architectural refactor, not a new gameplay feature.

### 2. Preserve one discovery path for first-party and external packages

The existing manifest/discovery contract remains the common entry point:

```text
res://mods/first-party/ ─┐
                         ├─ DeclarativeModLoader ─ Content Registry
user://mods/ ────────────┘
```

First-party content must not gain privileged hidden loaders or alternate schema paths.

The existing data-only policy remains in force for M4.0. Trusted scripted mods remain a future charter capability and require a separate security/authority design.

### 3. Replace the monolithic content registry with extensible engine-owned type handlers

The content core shall support registered content-type handlers. Each handler owns:

- its content type identifier;
- supported schema versions;
- strict validation;
- canonical normalization;
- dependency/reference validation where applicable;
- content hashing/pinning;
- optional typed lookup/evaluation interfaces.

The loader remains generic and does not need to understand the semantics of every future content type.

Conceptually:

```text
DeclarativeModLoader
        │
        ▼
ContentRegistry
        │
        ├─ handler: procedural_rock
        ├─ handler: static_population_rule
        ├─ handler: terrain_interaction_rule
        └─ future handlers: simulation/material/environment definitions
```

Handlers are engine code. Mods provide data conforming to registered schemas; a data-only mod cannot inject arbitrary executable validators or algorithms.

### 4. Existing content contracts keep their semantics

M4.0 must preserve the current behavior and identities of:

- `procedural_rock`;
- `static_population_rule`;
- `terrain_interaction_rule`;
- deterministic procedural placement;
- object/content IDs;
- population IDs;
- terrain-effect IDs;
- entity identities and revisions;
- existing object-state persistence;
- Issue #108 terrain-object behavior.

A generic registry is not permission to reinterpret existing schema versions.

### 5. Use a uniform content fingerprint

Every registered content record exposed to persistent identity or deterministic simulation must have a canonical content fingerprint.

The target pin contract is conceptually:

```text
content_id
mod_id
mod_version
schema_version
content_sha256
```

The canonical SHA-256 supplements, rather than replaces, semantic versioning.

Changing bytes/meaning while retaining the same package version must no longer be able to silently masquerade as the same persistent content. Compatibility/migration policy remains explicit.

### 6. Keep infrastructure engine-owned

The following remain engine infrastructure unless a later ADR explicitly changes that boundary:

- world/region addressing;
- canonical authority and revision rules;
- save/journal/checkpoint machinery;
- streaming and residency;
- LOD and mesh publication;
- WorkerThreadPool/concurrency policy;
- fixed-tick scheduler and budgets;
- tier transitions;
- stale-result rejection;
- resource/SceneTree publication.

Mods define data and supported declarative behavior; they do not own these mechanisms.

### 7. Make future simulation content mod-first from its first implementation

P4 scheduler mechanics are engine-owned, but the state/configuration that the scheduler processes should be represented through versioned content contracts where appropriate.

Expected future families may include, without freezing their final schemas:

- simulation parameter sets;
- material/environment definitions;
- climate or biome profiles;
- later organism/species definitions.

P4/P5 must not introduce first-party-only data paths that later need conversion into mod contracts.

## Consequences

### Positive

- P4/P5 can add content families without growing a monolithic registry.
- First-party and external content remain structurally equivalent.
- Persistent worlds can detect silent content drift through canonical hashes.
- Simulation infrastructure can remain deterministic and bounded while content remains extensible.
- Future mod capabilities can be added by explicit handlers and schema versions instead of ad hoc conditionals.

### Costs

- M4.0 adds a pre-P4 refactor and migration-sensitive test work.
- Existing registry APIs need compatibility adapters or controlled replacement.
- Content pin schemas may require explicit storage migration if hashes become persisted into existing records.
- Genericity must not become an unbounded plugin execution surface.

## M4.0 acceptance requirements

M4.0 is complete only when all of the following hold:

1. current first-party and external object fixtures load through the generalized registry;
2. current procedural generation is byte/identity equivalent where the existing contract requires it;
3. population and terrain-interaction behavior remain unchanged;
4. existing object/entity persistence either remains compatible or uses an explicit tested migration;
5. canonical content SHA-256 is available through a uniform pin/fingerprint API;
6. adding a synthetic new data-only content type requires a new handler, not edits to loader discovery logic;
7. malformed/unknown types and unsupported schemas fail closed;
8. dependency ordering, path safety and bounded limits remain enforced;
9. no executable mod code is introduced;
10. canonical regression and owner-visible gameplay remain unchanged.

## Explicit non-decisions

This ADR does not:

- make the base terrain generator moddable;
- authorize scripted mods;
- define P4/P5 simulation schemas;
- choose a terrain backend;
- add physics/collision/networking;
- remove engine control over scheduling, persistence, streaming or LOD.
