# P0.3 Declarative Mod Foundation

## Scope

P0.3 adds a small data-only package loader and shared content registry. It registers validated definition data; it does not instantiate scene nodes, execute package code, create entities, or change terrain, streaming, the edit ledger, or persistence schema 1.

## Package contract

Each package has one `manifest.json` and one or more declared content roots. The schema-1 manifest has exactly these fields:

- `id`: lowercase dotted namespace such as `official.example.procedural_rock`.
- `version`: exact `MAJOR.MINOR.PATCH` semantic version.
- `schema_version`: integer `1`.
- `requires_engine`: exact `4.7.2` for this first contract version.
- `dependencies`: array of `{ "id", "version" }` exact-version requirements.
- `content_roots`: unique safe relative directory names ending in `/`.
- `script_policy`: exactly `data_only`.

The loader only discovers immediate package directories under explicitly supplied roots within the bundled `game/mods`, repository `mods`, or `user://mods` locations. It does not search arbitrary disk locations. Package content roots contain immediate JSON definition files only; nested content directories, path traversal, links/junctions encountered along inspected paths, malformed JSON, unknown manifest fields, missing dependencies, version conflicts, duplicate package IDs and dependency cycles fail closed. Script policy never loads or evaluates scripts. Package and definition counts and byte sizes are bounded.

Dependencies are resolved with a deterministic topological order. Among currently eligible packages, IDs are ordered lexically. Discovery root order and filesystem enumeration order do not change the resulting registration order.

## Content registry

`ContentDefinitionRegistry.register_discovered()` uses the same validation and registration path for bundled first-party packages and external packages. Registration is transactional: an invalid or duplicate definition leaves the previous registry unchanged. Definition IDs use `<package-id>:<local-id>`.

Schema-1 `procedural_rock` definitions carry a display name, unique tags and a `stacked_spheres_v1` recipe in integer millimeters. `evaluate_rock_recipe(id, seed)` uses only the supplied seed and integer arithmetic to return ordered lobe centers/radii as data. It does not use global random state, scene nodes or an implicit world seed.

The registry can create sorted content pins containing content ID, package ID/version and definition schema version. A later caller can persist those pins and require `validate_content_pins()` to succeed before resolving content. Missing content, changed package versions or changed definition schemas are rejected rather than substituted. These pin helpers are preparatory only: schema-1 world saves remain unchanged and do not yet store entity or mod state.

## Included packages and verification

- `game/mods/first-party/core-rocks` is the bundled first-party package.
- `mods/examples/procedural-rock` is the external example package and declares the first-party package as an exact dependency.
- External packages intended for a running user installation belong under `user://mods`.

Run the demonstration and focused checks with Godot 4.7.2:

```powershell
godot --headless --path .\game --script res://tests/declarative_mod_tests.gd
```

The test discovers both included packages, validates dependency order, registers and looks up both definitions through the same registry, evaluates the external rock recipe from explicit seeds, and checks controlled failure and save-file preservation. The normal `scripts/validate.ps1` suite also runs these tests and the existing terrain persistence suite.

## Limits and follow-up

This is a source-tree prototype. It does not define package signatures, downloads, an installer, hot reload, arbitrary script support, entity instantiation, content migration, or production save integration. Engine compatibility is exact-match only. No owner-approved performance thresholds or visual acceptance are claimed.
