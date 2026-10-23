# P0.3 canonical terrain test isolation correction

**Date:** 2026-10-23  
**Repository:** `publiomcko-cloud/procedural-sandbox-simulation`  
**Branch / PR:** `feat/p0-3-declarative-mod-foundation`, [draft PR #105](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/105)  
**Baseline main:** `66263baeef2f628c91a6a271dad04e7cd86659e4`  
**P0.3 candidate before correction:** `1d00305d3539989ab862b9f6591af0946e9324c2`  
**Source correction:** `fc3677ce16f65b34825b3678214e9fb5250081cd` (parent `1d00305d3539989ab862b9f6591af0946e9324c2`)  
**Evidence grade:** L4 local Godot 4.7.2 execution on detached source snapshots and the designated development workspace. No owner visual result or independent rereview is implied.

## Finding and reproduction

The failure hypothesis was confirmed. `terrain_demo.gd::_ready()` restores `user://worlds/sandbox-default/` when a valid save exists. The four affected test suites instantiate that scene while assuming a new seed and empty ledger. The owner profile contained a valid schema-1 save with 17 operations, revision 17, seed 424242 and generator v1. It was inspected read-only; its SHA-256 was `09569DB6A6ABC3BF35676DC202BFBA33D8E49D85CCD97656FFBC8300D6CA9393`.

Snapshots were produced from exact `main` and candidate SHAs, with separate fresh Godot user-data profiles for clean comparisons. In the clean profiles, both baseline and candidate passed the same four suites:

| Suite | main | PR #105 candidate |
| --- | --- | --- |
| Brush | 611/611 | 611/611 |
| Multiregion | 7,637/7,637 | 7,637/7,637 |
| History | 842/842 | 842/842 |
| End-to-end performance | 251/251 | 251/251 |

An isolated copy of the pre-existing 17-command save seeded the baseline profile. This reproduced the reported 27 failures: brush 5, multiregion 4, history 17, and end-to-end 1. Representative observed values were:

- Brush click sequence started at 17; after the carve the ledger was 18 (revision 18, last sequence 17), and after Shift-fill it was 19 (revision 19, last sequence 18). The HUD therefore showed 19/256 instead of the test's expected 2/256.
- Multiregion initialization produced 88,661 triangles instead of the pristine 87,077. After the test's added operation the ledger read 18/256, so assertions inspecting the first stored command observed the persisted command instead of the command under test.
- History began with 17 accepted commands. It accepted 239 of the new sequential edits, reached the 256-command cap, then rejected test command indices 239–255 (17 failures); only 239 latency samples were recorded.
- End-to-end accepted the five clicks, but observed 22 edits, revision 22 and last sequence 21 instead of the expected count of five.

These are persisted-user-state test-contamination failures, not P0.3 regressions. The clean baseline and clean candidate both passed; the P0.3 change did not modify terrain behavior. The save was never deleted or overwritten.

## Correction

`terrain_demo.gd` now preserves a `world_save_store` injected before the scene enters the tree. When no store is injected, `_ready()` still creates `TerrainWorldSaveStore.new()` and loads the normal `user://` world exactly as before.

The brush, multiregion, history and end-to-end suites now inject a fresh `TerrainWorldSaveStore` pointed at a unique, absent directory under the system temporary directory before adding each demo scene to the tree. No test disables persistence assertions, changes the ledger, or writes to the user's world slot.

## Validation

Godot: `4.7.2.stable.official.ed1daf0bf`; binary SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.

- Four affected suites, run directly while the real 17-command profile existed: 9,341/9,341 assertions, zero failures.
- Declarative P0.3 suite: 42/42; persistence suite: 321/321.
- One complete `scripts/validate.ps1` run: exit 0, 17,258 assertions across 15 assertion-bearing groups, zero failures, stderr empty. `VALIDATION_PASS: L0-L2`; visual acceptance remains a separate owner task.
- Real save SHA-256 before and after the complete validation was identical: `09569DB6A6ABC3BF35676DC202BFBA33D8E49D85CCD97656FFBC8300D6CA9393`.
- `git diff --check` passed. Existing `stash@{0}` and the three unrelated untracked P1.1B `.gd.uid` files remained present.

Raw comparison and validation logs are retained under the local temporary evidence root `p0_3_canonical_clean_compare_883d8659318e4013911e3be916b98801`; they are not repository artifacts. The exploratory seeded profile was a byte-identical copy of the existing save and was separate from the owner profile.

## Status and limits

The fix covers the four canonical suites named in the review. Future scene-instantiating tests that require pristine state should inject an isolated store as well. Normal production auto-load remains active. The complete validation is headless source/runtime evidence; it does not establish GUI acceptance.

PR #105 remains open, draft and unmerged pending independent exact-SHA review. All five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
