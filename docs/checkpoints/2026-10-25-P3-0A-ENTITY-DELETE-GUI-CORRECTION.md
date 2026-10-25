# P3.0A — ENTITY_DELETE owner-GUI failure correction

**Event:** owner GUI failure, reproduction and bounded correction candidate  
**Date:** 2026-10-25  
**Repository:** `publiomcko-cloud/procedural-sandbox-simulation`  
**Workspace:** `C:\Dev\sandbox-sim-dev`  
**Branch / PR:** `feat/p3-0a-entity-command-contract`, draft PR [#114](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/114)  
**Verified main/base:** `b874991bb0f2cc698e41dd8709f3b0325d73c855`  
**Failure source:** `c8a91eb387f037beb7c8db7670aed4186d37c496`  
**Correction source:** `3da4bc6f7272ed838da7438c43312227e32ae59e` (direct parent `c8a91eb387f037beb7c8db7670aed4186d37c496`)

## Reported failure and reproduction

The owner reported that pressing Delete in `res://scenes/entity_command_harness.tscn` did not make the last selected entity disappear. The scene handler matched only `InputEventKey.keycode` in `_unhandled_input`. A temporary headless scene reproduction used `Viewport.push_input` and observed:

- The harness created its automatic startup entity; two P events then produced three nodes. This did not meet the requested “two P presses create two distinct entities” demonstration setup.
- A logical Delete event (`keycode=KEY_DELETE`) was received, committed the tombstone, advanced world/entity revisions, set the selected `Node3D.visible` false, and showed a success HUD message.
- A physical-key-only Delete event (`keycode=0`, `physical_keycode=KEY_DELETE`) did not reach the operation branch; the tombstone, revisions, visibility and HUD stayed unchanged.

This reproduces a real input-contract defect without implicating the command service's logical-delete transaction or `Node3D.visible` behavior. Headless viewport input does not establish actual Windows window focus or prove the owner's exact OS-generated event fields; those remain part of the GUI retest.

## Correction

- Match P, E, Delete and R against both logical and physical key codes. The HUD tells the operator to focus the harness window.
- Start the isolated scene empty so two P presses create exactly two independently identified explicit placements.
- After a successful command, resolve the committed entity state and apply the resulting visual state. A committed tombstone hides only the selected existing node; restore resolves the same entity and reuses its node. A missing node or failed resolve is reported as a synchronization failure rather than an unqualified visual success.
- Rejected commands return before visual synchronization. The HUD retains the exact rejection reason.

No command contract, revision rule, receipt/idempotency policy, identity scheme, P2.0B store or terrain save changed.

## Validation evidence

Engine: Godot `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`; isolated `APPDATA` used for full suite.

- Pre-correction `Viewport.push_input` reproduction: logical Delete hid the entity after persisted tombstone; physical-only Delete was ignored.
- Focused post-correction scene regression: `ENTITY_COMMAND_HARNESS_PASS: assertions=19 failures=0`. It sends events through the actual scene viewport; verifies two placements, independent identities, only-second deletion, persistent tombstone/revisions, duplicate-delete rejection without visual/state changes, same-node restoration, HUD messages and disposable-directory cleanup.
- Full `scripts/validate.ps1`: exit 0, `VALIDATION_PASS: L0-L2`; **17,969 assertions, 18 groups, zero failures**. No `SCRIPT ERROR`, `ERROR:` or `WARNING:` lines were found. Log: `C:\Users\PUBLI\AppData\Local\Temp\p3-0a-delete-validation-20261025.log`.
- `git diff --check`: passed.

Evidence grade: developer-run Godot/headless (L2) plus owner-reported GUI failure. No post-correction owner GUI PASS is claimed.

## Workspace and scope

Only the existing PR #114 branch was used; PR remains open, draft and unmerged. `stash@{0}` and the three pre-existing untracked benchmark `.gd.uid` files were preserved. P2 state and terrain behavior, PR #111 and all F2-G1 protected-state holds are unchanged. No protected operation, merge or release action occurred.

## Limitations and next gate

The automated input route verifies Godot viewport dispatch but cannot test whether the OS focuses the game window. The owner should run the isolated scene after the independent source review: click the game window, press P twice and verify two distinct visible objects; press Delete and verify only the second disappears and the HUD reports logical deletion; press Delete again and verify rejection without a visual change; press R and verify the same second object returns without duplication. Also test E once on the selected object. Record actual GUI result separately. PR #114 must remain draft/unmerged pending source review and owner retest.
