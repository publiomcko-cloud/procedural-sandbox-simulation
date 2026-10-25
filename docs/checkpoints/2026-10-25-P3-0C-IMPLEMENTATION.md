# P3.0C Transactional Persistent Undo/Redo — 2026-10-25

## Identity and disposition

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Verified `main` and integration baseline: `d391e09c1a7aac2116de2004c80d7f58bdb54986`
- Baseline includes merged Issue #118 PR #119; #119 merge commit has parents `fd431dbcad18685a3aa2c86c3c9b25fbd81303c9` and `a00c9c31a972e36f194c38d38ac44d68323fd7b8`.
- Feature branch: `feat/p3-0c-transactional-undo-redo`
- Implementation commit: `90313961352d1fe5216b5cd9efa342bbbb3c6378` (direct parent: `d391e09c1a7aac2116de2004c80d7f58bdb54986`)
- Implementation work reused `C:\Dev\sandbox-sim-dev`; local P3.0C modifications were snapshotted before safely fast-forwarding to main and reapplied without conflicts. Original stash `5eff3e94ceba7bffbbc19a081b43139f72b4905e` and preservation snapshot `ab2c3c612221722b3da70843117ac240e9769c3a` remain in the stash list. Three pre-existing benchmark `.gd.uid` files were preserved.
- The implementation commit changes 15 source/test/validation paths; this checkpoint and status/specification changes are a separate documentation commit. The resulting draft PR is the single P3.0C implementation PR.
- No merge is authorized. PRs #115, #117, #120 and Issue #108 are untouched.

## Implementation

Added explicit object-state schema 3 with a bounded persistent history/cursor. Source entity commands and their inverse metadata, revisions, history entry, and receipt are committed through the existing P2.0B state store as one candidate snapshot. Undo and redo are revision-checked/idempotent entity commands, preserve entity identity, and persist across service/process-style restart and streamed-region unload/revisit.

Delete receipts preserve the exact pre-delete sparse component overrides. Undoing DELETE after F7 therefore restores the same entity with its pre-delete transform and appearance; redo tombstones that same identity. F9 remains `ENTITY_RESTORE` to procedural baseline; its new receipt records whether the prior state was deleted and any prior overrides, so undo/redo of F9 restores the exact state on either side. Already-baseline restore rejects without effects. A source command after undo truncates the redo tail. History is capped at 256 entries, command receipts at 4096, and the persisted document at 4 MiB. Legacy schema 1/2 history is not invented: migration requires explicit preflight and user-triggered commit; existing schema-2 command receipts are preserved.

The full implementation contract and owner retest steps are in [P3.0C spec](../specs/P3-0C-TRANSACTIONAL-PERSISTENT-UNDO-REDO.md); proposed decision is [ADR-0006](../decisions/ADR-0006-PERSISTENT-ENTITY-UNDO-REDO.md). The focused history test includes migration, inverse command semantics, exact delete/F7 restoration, F9 reversibility, branch/capacity behavior, restart, storage failures, and visual/identity integration. Existing terrain, world-save schema 1, streaming/LOD/population, and production SDF algorithms are preserved.

## Validation

- Engine: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, `4.7.2.stable.official.ed1daf0bf`.
- Command: `./scripts/validate.ps1` from `C:\Dev\sandbox-sim-dev`, exit code 0.
- Result: `VALIDATION_PASS: L0-L2`; 20 assertion-marker suites, **18,153 assertions, 0 failed assertions**, and configured main-scene startup passed. The run included terrain/SDF, brush, chunk, multiregion, terrain history/persistence, declarative and procedural objects, entity commands/history, playable entity scene, picker, LOD transition/runtime, end-to-end and concurrency suites.
- Full raw log: `C:\Users\PUBLI\AppData\Local\Temp\p3c-full-validation-20261025-141423\validate.log`.
- The full log contains three Godot “Target and up vectors are colinear” warnings during procedural-object tests; those tests passed. No `SCRIPT ERROR` or parse error occurred. The declarative suite reports the expected environment limitation `ISSUE118_REPARSE_FIXTURE_UNAVAILABLE` because junction creation is unavailable in this host.
- Focused runs after the corrections passed `entity_history_tests.gd` 101/101 and `procedural_object_tests.gd` 638/638. The first complete run before these narrow corrections exposed four procedural-object expectation failures (stale HUD wording, an exact optional-folder count assumption, and asynchronous F9 publication observation). The affected tests were made robust to pre-existing user mods and bounded publication timing; production package discovery was not changed. Its original log remains at `C:\Users\PUBLI\AppData\Local\Temp\p3c-full-validation-20261025-140250\validate.log`.
- Measurements in validation output are headless exploratory data, not owner-approved performance budgets or presented-frame/GPU evidence.

## Limits and gates

This candidate has not had independent exact-SHA source review or owner GUI retest. Headless viewport tests do not establish physical OS focus, owner visual approval, GPU completion, multi-process locking, or power-loss durability. Explicit migration must only be tested against disposable/copied object state. No actual user save was intentionally migrated. All five F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. Issue #108 remains deferred.

## Owner retest

On a disposable world/object-state root, launch `res://scenes/main.tscn` under Godot 4.7.2; use M/M only when intentionally migrating a disposable schema-1/2 state. Place or select an object, use F7 to change transform/appearance, F8 to delete, then Ctrl+Z. Verify that the identical object and both pre-delete F7 changes return. Ctrl+Y must delete that same ID again. Then undo and use F9 to restore procedural baseline; Ctrl+Z should recover the exact state preceding F9. Check the HUD history cursor/revisions, stale/rejected command behavior, and persistence after region unload/revisit and process restart. Record GUI outcomes separately; do not infer them from this headless result.
