# P3.0D — Precise Entity Placement Candidate

**Checkpoint date:** 2026-10-25 (America/Sao_Paulo)
**Event:** implementation and validation handoff for Issue #123
**Publication:** draft PR #124, not merged
**Immutable:** yes; later review/GUI outcomes require a separate checkpoint.

## Repository identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Verified `origin/main` and implementation baseline: `c08267caea3d4c092574c8b4fb1f1e59883923dc`
- Source commit: `63c4bd4fc30e8ad655cd98f01292b9cf112be9fb`
- Source parent: `c08267caea3d4c092574c8b4fb1f1e59883923dc`
- Branch: `feat/p3-0d-precise-entity-placement`
- Draft PR: [#124](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/124)
- Source paths: `game/scripts/terrain/terrain_demo.gd`, `game/tests/p3_0d_entity_placement_tests.gd`, its `.uid`, `game/tests/procedural_object_tests.gd`, and `scripts/validate.ps1`.

## Finding and correction

The pre-change `terrain_demo.gd::_place_entity_under_crosshair()` always selected `viewport_size * 0.5`. The center-crosshair behavior was intentional in the earlier P3.0B design, so the initial evidence did not indicate a coordinate-conversion defect. A synthetic viewport reproduction sent distinct left/right pointer positions; their SDF hits were `(8000,3851,29061)` mm and `(8000,3024,-17921)` mm, while both pre-change placement commands recorded the center hit `(8000,3821,6000)` mm. The mismatch arose at screen-point selection.

The implementation now uses the visible pointer and falls back to viewport-center aim when the cursor is hidden/captured or the pointer is unavailable. A placement indicator shares the exact picking function used by `B`. Placement is rejected for no surface, unsupported coordinates, or an unpublished target region. The hit is rounded once to millimeters before deriving floor-based region ownership, avoiding a boundary disagreement between the rounded persisted point and an unrounded region calculation.

The position is explicitly the current rock root/base-plane center (`local y = 0`), coincident with the SDF surface hit. There is no random offset, no overlap avoidance that would change intentional repeated placement, and no slope conformation; Issue #108 remains deferred.

## Validation evidence

- Godot: `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.
- Focused placement suite: `P3_0D_PLACEMENT_PASS`, 51 assertions, zero failures.
- Existing procedural-object regression: `PROCEDURAL_OBJECT_PASS`, 638 assertions, zero failures. The old fixture was updated to send a real pointer-motion event before `B`; its obsolete center-crosshair-only expectation caused the first integrated run to fail even though it had no coordinate-conversion failure. The retained test now verifies the new visible-pointer contract.
- Full `scripts/validate.ps1`: `VALIDATION_PASS: L0-L2`; 18,204 assertions across 21 assertion-marker suites, zero failures. Main-scene startup passed. Full raw log: `%TEMP%\p3_0d_full_validation_r2_20261025\validate.log`.
- Earlier full attempt retained at `%TEMP%\p3_0d_full_validation_5e5d792b5e404f1a8b940b5f96451d64\validate.log`; it exposed the outdated crosshair assertion and was not counted as a passing validation.
- Headless validation does not verify visual appearance, real OS cursor state/focus, or GUI usability. Owner retest remains pending.

## Scope and holds

P3.0C schema-3 history, identities, content pins, receipts, persistence, region streaming and existing controls are preserved. No SDF or ledger semantics, save data, production terrain mesher, Issue #108 behavior, mod pipeline, or dependencies changed. PRs #115, #117, #120, and #122 were observed open/draft and were not modified. `stash@{0}`, `stash@{1}`, and the three pre-existing untracked `.gd.uid` files were preserved.

All five F2-G1 markers remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

## Next gate

Independent source review of exact PR #124 HEAD and owner GUI retest. GUI steps: run `res://scenes/terrain_demo.tscn` (F5 launches this configured playable scene; `main.tscn` is bootstrap only); move the visible pointer between two exposed terrain locations and press `B` at each; observe the cyan/green placement marker, distinct persisted placements, and HUD aim/region state; hide/capture the cursor and verify center fallback; aim outside terrain and at an unpublished region and verify rejection; repeat placement at one point and confirm overlap is allowed; test Undo/Redo, F8/F9, leave/revisit a region and restart to verify identity and position persist without duplicate visuals. No merge or release is authorized by this checkpoint.
