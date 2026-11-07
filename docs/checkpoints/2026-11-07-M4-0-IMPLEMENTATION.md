# 2026-11-07 — M4.0 mod-first content-core implementation candidate

## Status

`M4_0_IMPLEMENTED / QUALIFICATION_PENDING / P4_NOT_STARTED`

Base:

- `main@bda2968d914ff899f2dbb5407808b0cbeeb7ed14`
- documentation/architecture baseline includes accepted ADR-0007 and ADR-0008.

Implementation branch:

- `feat/m4-0-mod-first-content-core`
- draft PR #256.

This checkpoint records the implementation candidate only. Godot 4.7.2 qualification and owner merge authorization remain separate gates.

## Implemented architecture

### Type-agnostic declarative discovery

`DeclarativeModLoader` now emits a canonical `content_records` collection for every JSON record in declared content roots.

Discovery still provides the three historical compatibility views:

- `definitions`;
- `population_rules`;
- `terrain_interactions`.

Unknown/new content types are no longer rejected by loader discovery solely because the loader does not know their semantics. The registry remains fail-closed unless the engine registered a handler for that type.

### Engine-owned content handlers

New:

`game/scripts/modding/content_type_handler.gd`

A handler defines:

- content type ID;
- deterministic registration priority;
- strict validation callback;
- optional canonical normalization callback;
- duplicate-record failure reason;
- optional per-type record bound.

Callback targets are held through `WeakRef` so built-in registry callbacks do not create a `RefCounted` ownership cycle.

Handlers can be registered only before content registration begins. Data-only mods cannot install executable handlers.

Built-in handlers preserve the existing semantics for:

- `procedural_rock`;
- `static_population_rule`;
- `terrain_interaction_rule`.

### Generic registry storage

`ContentDefinitionRegistry` now owns records by content type and exposes generic APIs:

- `get_registered_content_type_ids()`;
- `get_content_record(type, id)`;
- `get_content_record_ids(type)`;
- `pin_content_record(type, id)`;
- `validate_content_fingerprint(fingerprint)`;
- `register_engine_content_type_handler(handler)`.

Existing P2/P3 APIs remain compatibility views and are not removed.


### Shared runtime handler bootstrap

`ProceduralObjectStream.initialize()` now accepts an optional engine-owned handler list as its final argument. Handlers are installed on the same registry **before** discovered first-party/user content is committed.

Existing callers pass no handlers and retain identical behavior.

This closes the pre-P4 bootstrap gap: a future P4/P5 content family can join the existing world registry and the existing `res://mods/first-party` + `user://mods` discovery path without introducing a second mod/content system.

The M4.0 focused suite creates a synthetic package and proves that this actual runtime initialization path can load it only when the engine provides the matching handler.

### Canonical content fingerprint

New content fingerprint fields:

- `content_id`;
- `content_type`;
- `mod_id`;
- `mod_version`;
- `schema_version`;
- `content_sha256`.

SHA-256 is computed from canonical normalized JSON.

This detects content drift even when a package incorrectly retains the same semantic version.

Existing persisted definition pins intentionally remain unchanged at four fields in M4.0. No object-state migration is introduced.

Existing population and terrain-interaction pins keep their external schema but now source their SHA-256 from the uniform fingerprint path.

### Backward compatibility

Loader-generated packages still expose the historical typed views.

When those typed views are present, the registry intentionally treats them as the compatibility source for the three pre-M4.0 types. This preserves existing tests/tools that amend a discovery record before registration.

New content types flow through `content_records` without any loader modification.

### Bounds and authority

The registry independently enforces:

- at most 64 engine content handlers;
- the loader/global content-record bound;
- existing population and terrain-interaction per-type bounds;
- exact namespace/schema identity;
- duplicate rejection;
- handler identity stability across normalization.

Handlers receive copies of candidate context and may not change `type`, `id` or `schema_version` during normalization.

## Focused qualification added

`game/tests/m4_0_mod_first_core_tests.gd`

The focused suite verifies:

1. built-in handler registration order;
2. first-party content registration;
3. generic/legacy loader view equivalence;
4. unchanged four-field persisted definition pins;
5. uniform SHA-256 fingerprints for all current families;
6. legacy population/terrain hashes match the uniform fingerprint;
7. fingerprint drift detection;
8. handler registration closes after content load;
9. procedural generation remains deterministic;
10. built-in handler callbacks do not leak registry lifetime;
11. mutated legacy discovery views remain effective;
12. a synthetic new content type passes loader discovery without loader changes;
13. unknown type fails closed without an engine handler;
14. synthetic handler registration enables the package;
15. handler normalization is applied;
16. same-version content mutation changes SHA-256;
17. normalized records are revalidated before commit;
18. normalization cannot bypass record semantics;
19. the shared runtime registry accepts an engine-owned future content handler before package commit.

## Regression envelope

The M4.0 workflow requests:

- import/parser gate;
- focused M4.0;
- declarative mod regression;
- entity command regression;
- Issue #108 D8 regression;
- P3.0D placement;
- procedural-object exact known baseline;
- canonical `scripts/validate.sh`.

The procedural regression is allowed only the already-recorded exact historical envelope:

- one camera-driven revisit failure;
- zero `SCRIPT ERROR`;
- no additional assertion failures.


## Hosted CI status at implementation handoff

GitHub Actions repeatedly returned workflow/job `failure` before any step was allocated or executed. For the observed M4.0 runs, the selected jobs report `steps=[]`; attempting to fetch job logs returned no job-log blob.

This matches the runner-allocation/infrastructure failure mode already observed during D.7/D.8. It is **not** treated as either a code PASS or code FAIL.

Owner-local Godot 4.7.2 qualification remains the authoritative implementation gate.

## Non-goals

M4.0 does not:

- begin P4;
- add scheduler/ticks;
- authorize scripted mods;
- make base terrain generation moddable;
- migrate object-state persistence;
- change entity authority;
- change terrain-object effects;
- change streaming/LOD;
- add gameplay content.

## Next gate

Run Godot 4.7.2 qualification on the exact PR head.

If focused/regression gates pass, perform final diff review, record evidence, mark PR #256 ready and merge only with owner authorization.
