# P3.0B Playable World Transactional Entity Integration — 2026-10-25

## Identity and scope

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Required baseline/main at start: `5b8cf36108ce48476095f14b35426e7e8ab4bfe8`
- Source implementation commit: `6ce65bbe2f1a54bd1436416b5cb6102c75a09769` (direct parent: required baseline)
- Work branch: `feat/p3-0b-playable-world-entity-commands`
- Draft PR: pending publication; no merge authorized.
- Separate documentation PR #115 was not modified.

P3.0B connects the P3.0A transaction dispatcher to the playable terrain scene while keeping authoritative entity state in the existing P2.0B state service and declarative P0.3 registry. Explicitly placed objects use their own stable identity kind. Procedural IDs, definition pins, seeds, population rules, and terrain save schema 1 remain separate and unchanged.

## Implementation

The scene provides `B` placement under the camera crosshair at a terrain surface, Ctrl+left selection, `F6` selection cycling, `F7` transform and appearance commands, `F8` logical delete, `F9` exact restore, and a deliberate two-step `M` schema migration (preflight, then commit). Commands use expected world/entity revisions and the existing persistent receipt/idempotency policy. Schema-1 object state is not upgraded automatically; commands remain gated until explicit migration and resident representations have been rebuilt. Visual publication is asynchronous and bounded by existing region/publication limits; committed authoritative state is reported separately from visual publication status.

The correction also rejects transforms that would transfer an entity across canonical region ownership, handles world-space placement anchors separately from region-local scene coordinates, and retains the previous complete visual root when a post-commit visual publication fails. HUD output exposes selection, identity kind, revisions, schema readiness, command result, and separated headless timings.

## Validation evidence

Godot executable: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, version `4.7.2.stable.official.ed1daf0bf`, SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.

The complete `scripts/validate.ps1` run passed with exit code 0: **18,022 assertions across 19 assertion-marker suites**, zero failures; all 20 L2 groups (including startup) passed. No `FAIL`, `SCRIPT ERROR`, or `ERROR` appeared in the final run. Full raw log and isolated profile: `C:\Users\PUBLI\AppData\Local\Temp\p3-0b-full-final-5448b8172ff84da8a4ae932d25a840fc\validate.log`.

Focused new disposable-fixture suite: 44/44. Playable scene/object regression: 630 assertions, including viewport-routed schema migration, placement, selection, transform/appearance, delete, rejected repeat, exact restore, and no-duplicate checks. Focused brush regression: 613/613. The first full validation attempt found a legacy HUD text expectation mismatch; the compatible `Selected:` label was restored and the complete validation then passed. The earlier failed log remains preserved separately at `C:\Users\PUBLI\AppData\Local\Temp\p3-0b-full-576d03b0359b4a85b123a84367866da5\validate.log`.

Exploratory timings from the final headless fixture run (microseconds; not product budgets): validation/preparation p50/p95 398/675; persistence 19,022/22,410; visual queue 18/19; command total 20,567/25,603; logical reconstruction 1,489/1,562; mesh build 42,821/43,108; batch build 228/276; publication 44,635/45,039. These synthetic headless timings do not establish GPU completion, presented-frame latency, visual quality, or performance acceptance.

## Limits and remaining gates

- Independent exact-SHA source review and owner GUI retest remain pending.
- Schema migration is explicit and has a retained prior generation, but this is not a power-loss durability or concurrent-writer guarantee.
- Entity transform transfer across region boundaries is deliberately rejected; cross-region object movement is not implemented.
- Headless input routing does not prove physical OS focus/device behavior or visual acceptance.
- No physics, collision, networking, multiplayer, full undo/redo, terrain conformation (Issue #108), or native dependencies were added.
- F2-G1 remains held: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

## Reproduction

From repository root with the pinned Godot 4.7.2 executable:

```powershell
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game --editor --import
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game --script res://tests/playable_entity_command_tests.gd
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game --script res://tests/procedural_object_tests.gd
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path ./game --script res://tests/terrain_brush_tests.gd
./scripts/validate.ps1
```

Owner GUI retest: open the project in Godot 4.7.2 and run `res://scenes/main.tscn`. Press `M` twice within six seconds to explicitly migrate the disposable/current test world state and wait for the HUD to show command readiness. Aim at a visible terrain surface and press `B`; Ctrl+left-click the placed object; use `F6` to cycle selection; press `F7` to apply transform and appearance; press `F8` to delete and verify only that object disappears; press `F9` to restore the same ID exactly once. Repeat `F8` while already deleted and verify the HUD reports rejection and the scene does not change. This is a retest procedure, not an assertion that GUI acceptance has occurred.
