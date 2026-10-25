# Issue #118 — Mod discovery and object initialization correction

Date: 2026-10-25
Repository: `publiomcko-cloud/procedural-sandbox-simulation`
Verified main/baseline: `fd431dbcad18685a3aa2c86c3c9b25fbd81303c9`
Source correction commit: `f8edbff0a7bab3ea733b4903611a9e6a5904613c`
Source commit parent: `fd431dbcad18685a3aa2c86c3c9b25fbd81303c9`
Feature branch: `fix/issue-118-mod-discovery-initialization`
Issue: [#118](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/118)

## Starting state and preservation

The verified main baseline was clean in a separate worktree before edits. The designated `C:\Dev\sandbox-sim-dev` worktree contained pre-existing P3.0C changes, three untracked `.gd.uid` files and `stash@{0}`. It was not modified or switched. Work was isolated in `C:\Dev\sandbox-sim-issue-118`; the stash, owner files and PR #115/#117 branches were left unchanged. The existing `origin` is `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`. PR #115 and #117 were observed open/draft/unmerged and were not modified.

## Symptom and reproduced cause

Owner reported that the terrain loaded while procedural objects did not, with `package_discovery_failed:missing_manifest` and downstream object/state services locked. The owner's reported read-only checks established manifests for two searched repository packages but did not inspect `user://mods`.

Before the fix, a temporary reproduction added a synthetic immediate child folder without `manifest.json` under an isolated Godot `user://mods`. The actual `ProceduralObjectStream.initialize` returned `ok=false`, reason `package_discovery_failed:missing_manifest`; the error summary was `package_discovery_failed:missing_manifest`. This demonstrated that discovery treated any immediate child directory as a package. It did not establish which folder exists in the owner's profile. No real user save or actual protected path was accessed.

Pre-fix reproduction log: `C:\Users\PUBLI\AppData\Local\Temp\issue118-repro-315a20434efb4f4db126a091cb58d92d\repro-pre-fix.log`
SHA-256: `A76CBA65A3FCAB42B9ED543EF98AADE055773A37AAA759C7980E004B79EB5395`.

## Correction

Only immediate children in the exact optional `user://mods` root that lack `manifest.json` are now classified as undeclared folders, counted and skipped with structured diagnostics. Required roots still fail on a missing manifest. A present malformed manifest, invalid content, missing/incompatible dependency, duplicate identity, unavailable root, traversal/reparse or other path-safety rejection remains fatal. Discovery is non-recursive and deterministic. No package scripts execute; no user folders or save data are changed. The HUD displays a short warning without personal absolute paths. Full policy is in [spec](../specs/ISSUE-118-MOD-DISCOVERY.md); ADR-0005 is proposed pending review and GUI retest.

Changed source/test paths in the source commit:

- `game/scripts/modding/declarative_mod_loader.gd`
- `game/scripts/modding/content_definition_registry.gd`
- `game/scripts/objects/procedural_object_stream.gd`
- `game/scripts/terrain/terrain_demo.gd`
- `game/tests/declarative_mod_tests.gd`
- `game/tests/procedural_object_tests.gd`

## Validation

Engine: Godot `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.

- Isolated editor import: exit 0; no parsing errors.
- Focused declarative mod suite: 58 assertions / 0 failures (ordinary fallback path); the complete suite included a prepared reparse-point fixture and reported 59 for this group.
- Focused procedural object suite: 633 assertions / 0 failures.
- Full `scripts/validate.ps1`: exit 0, 19 assertion-marker suites, 18,040 assertions / 0 failures; `VALIDATION_PASS: L0-L2`. Full log: `C:\Users\PUBLI\AppData\Local\Temp\issue118-full-2a0a8cb96ff44bc5a395d0e27efd3a4a\validate-full.log`
  SHA-256: `4F820C6847F2F42BDECA2102FF7DD4B183BCAF47EEDC86D61EAE40F8515E300E`.
- Full validation ran with isolated `APPDATA`/Godot user data. A temporary junction inside that isolated profile was rejected as `reparse_package_path_forbidden`, then the junction was removed without following its target.
- Three non-failing `Target and up vectors are colinear` warnings were emitted by existing test camera setup. No parser error, `SCRIPT ERROR`, failed assertion, or validation error was found.

The validation proves synthetic behavior and headless regressions only. It does not prove visual object appearance, OS window focus, real owner save compatibility in the user's profile, or GUI acceptance. No benchmark, migration, F2-G1 operation, protected state access or merge was performed.

## Next gate

Independent exact-SHA source review, hosted checks, and owner GUI retest remain pending. GUI procedure: launch `res://scenes/terrain_demo.tscn`; confirm granito and basalto definitions load, declarative population is nonzero, no package-discovery error appears, and schema status is understood; aim at terrain and press B; test F6/F7/F8/F9 and visibility V; stream away and back; restart and confirm state. Use a disposable world/profile for any explicit entity-state schema migration. Do not treat the existing headless result as GUI or save-migration acceptance.

All five F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
