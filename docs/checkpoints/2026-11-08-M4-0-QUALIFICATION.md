# 2026-11-08 — M4.0 mod-first content core qualified

## Terminal status

`M4_0_QUALIFIED / READY_FOR_INTEGRATION / P4_NOT_STARTED`

Qualified runtime source:

- branch: `feat/m4-0-mod-first-content-core`
- source HEAD: `a7faa6f10421ec2e0acffb9bfcc4efe201901b6d`
- PR: #256
- base architecture: ADR-0007 and ADR-0008
- Godot: `4.7.2.stable.official.ed1daf0bf`

This checkpoint is the qualification receipt for M4.0. It supersedes the earlier implementation-candidate status without rewriting that historical checkpoint.

## Delivered architecture

M4.0 closes the pre-P4 mod-first architecture gate with:

- type-agnostic JSON content discovery through `DeclarativeModLoader.content_records`;
- engine-owned `ContentTypeHandler` contracts;
- built-in handlers preserving the existing procedural-rock, static-population and terrain-interaction behavior;
- generic content storage/lookup by type;
- uniform canonical SHA-256 content fingerprints;
- legacy P2/P3 persisted definition-pin compatibility without an implicit save migration;
- canonical population/terrain interaction hashes sourced through the uniform fingerprint path;
- strict fail-closed unknown-type behavior;
- bounded handler/record registration;
- canonical normalization followed by revalidation;
- immutable content identity across normalization;
- weak callback targets preventing registry/handler `RefCounted` cycles;
- shared runtime handler bootstrap before first-party/`user://mods` package commit;
- no executable mod code.

The same runtime registry and discovery path can therefore accept future P4/P5 data-only content families through engine-owned handlers without adding a second mod system.

## Qualification evidence

Owner-local Godot 4.7.2 evidence on the qualified source HEAD:

- import/parser gate: PASS;
- focused M4.0: `M4_0_MOD_FIRST_CORE_PASS: assertions=31 failures=0`;
- declarative mods: `DECLARATIVE_MOD_PASS: assertions=79 failures=0`;
- entity commands: `ENTITY_COMMAND_PASS: assertions=67 failures=0`;
- Issue #108 D8: `ISSUE108_D8_LOD1_EFFECT_PASS: assertions=34 failures=0`;
- P3.0D placement: `P3_0D_PLACEMENT_PASS: assertions=53 failures=0`;
- canonical smoke: `SMOKE_PASS: assertions=52 failures=0`;
- canonical terrain SDF: `TERRAIN_SDF_PASS: assertions=46 failures=0`;
- canonical LOD0/1 transition: `LOD01_TRANSITION_PASS: assertions=6474 failures=0`;
- canonical bootstrap structure: `BOOTSTRAP_STRUCTURE_PASS: assertions=18 failures=0`;
- main-scene startup: `STARTUP_EXIT=0`;
- canonical translated validation terminal marker: `VALIDATION_PASS: L0-L2; GUI visual test remains an owner task`.

Procedural-object regression retained the exact accepted pre-M4.0 baseline:

- `PROCEDURAL_OBJECT_FAIL: assertions=671 failures=1`;
- exactly one `camera-driven revisit republishes the original region`;
- exactly nine `effect_projection_same_revision_fingerprint_conflict`;
- zero `SCRIPT ERROR`;
- exactly one `ERROR: FAIL:`.

No additional procedural regression was introduced.

## Qualification corrections encountered

Qualification exposed and corrected three classes of implementation/test defect before this terminal verdict:

1. strict GDScript warning-as-error rejected Variant-inferred weak-reference locals;
2. the synthetic qualification fixture initially treated JSON integer-like numbers as `TYPE_INT` only;
3. stale disposable packages in the shared `user://mods` directory could contaminate older tests with `duplicate_mod_id`.

The final source:

- uses explicit strict types;
- accepts exact integer-like JSON values then canonicalizes to `int`;
- revalidates normalized content;
- isolates entity-command package fixtures;
- removes only known disposable test residue before optional-root policy tests;
- leaves production duplicate-mod-ID rejection unchanged.

## Hosted CI

GitHub Actions jobs for this branch repeatedly failed before any step allocation/execution and reported empty step sets. This is recorded as infrastructure failure only, not a code verdict.

Owner-local Godot evidence is the authoritative M4.0 qualification source.

## Non-goals retained

M4.0 does not:

- implement P4 fixed ticks or simulation tiers;
- authorize scripted mods;
- make base terrain generation mod-controlled;
- migrate existing object-state persistence;
- change terrain/object effect semantics;
- change streaming/LOD authority;
- add gameplay content.

## Handoff

M4.0 has satisfied the mandatory architecture/qualification gate defined by ADR-0007.

PR #256 is ready for integration review. Merge still requires explicit owner authorization.

After integration, the next development slice is **P4.0A — fixed-tick scheduler foundation**, using the generalized M4.0 content registry for any new data-driven simulation definitions while keeping scheduler mechanics engine-owned and obeying ADR-0008 bounded-work/performance rules.
