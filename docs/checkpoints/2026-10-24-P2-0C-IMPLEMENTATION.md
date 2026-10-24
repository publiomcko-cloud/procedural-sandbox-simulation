# 2026-10-24 — P2.0C modular static population implementation

## Verified repository identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation` (`origin` verified).
- Base `main` and feature branch at preflight: `84bb7c3e573e7aa5a07608aac7834735aeb2c84f`.
- Feature branch: `feat/p2-0c-modular-static-population`.
- Source commit: `057536f1680d5118e9c9990c137e1812f8cc8244`; direct parent `84bb7c3e573e7aa5a07608aac7834735aeb2c84f`.
- Draft PR: [#112](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/112), base `main`; no merge.
- Concurrent docs PR #111 was independently checked and remains open/draft at `26ec183684453ae14dfb87fd7ea421c9df8d7e48`, touching only the P2.0B merge checkpoint, checkpoint index, and current status. Its branch was not changed or copied into this branch; this PR adds separate locations in the shared index/status documents.
- `stash@{0}` preserved. Three pre-existing untracked P1.1B `.gd.uid` files were preserved and excluded from commits. The new static-batch script UID is committed with its script.

## Scope delivered

P2.0C adds schema-1 declarative population rules, a data-only `objects/` and `populations/` package contract, deterministic candidate-grid density placement for signed regions, identity pins that include rule content, explicit compatibility rules preserving both P2.0B IDs/seeds/state, and per-region immutable mesh batching. Stateful objects remain separate Node3D representatives. Rule and region generation have explicit caps; streaming publication has bounded queues, cache, residency and per-frame publication limits.

Not implemented: physics/collision changes, multiplayer, time simulation, undo/redo, terrain/rock conformance issue #108, arbitrary script mods, save migration, or performance target acceptance. The legacy two objects remain alongside the generic additive population because preserving their saved identity without a migration is required.

## Evidence

- Engine: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, `4.7.2.stable.official.ed1daf0bf`.
- Full command: set `GODOT_BIN` to that executable and run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1` from the workspace. Exit 0, `VALIDATION_PASS`, 17,883 assertions in 16 groups, zero failures. Log: `C:\Users\PUBLI\AppData\Local\Temp\p2c-full-validation-final3-041dc86894c240a0bf0f4e05b824a76a.log`; SHA-256 `FA2BD299324A098D5AD111868019B18DD28880E98F07F14F42B5F5353D2F8C7A`.
- Focused object suite: `godot --headless --path game --script res://tests/procedural_object_tests.gd`, 621 assertions, zero failures.
- Focused brush suite: `godot --headless --path game --script res://tests/terrain_brush_tests.gd`, 613 assertions, zero failures.
- Three full-suite runs before the final diagnostic correction exposed the brush test mismatch: asynchronous region-load results were attributed to the concurrent global brush operation, so the test compared dirty IDs outside its initial mesh snapshot. The operation telemetry now filters completed worker results by active operation purpose; the brush check distinguishes preexisting chunks from newly published chunks and verifies both correctly. All failed logs remain in TEMP and were not overwritten: `p2c-full-validation-53799593c7d9442fa5fd415e0b7b89d0.log` (SHA-256 `BB34EA57048CB6FA6F7C18A4AB781191373E64804BE6EAD8DB18A2AC8F4F6406`), `p2c-full-validation-final-27a885d125d14277acf74d5d4c80e6e3.log` (SHA-256 `0C7C2171A9C8212B6CB9E9D056E034E87B7BAEF8F9302B4553615E949231D7C1`), and `p2c-full-validation-final2-f0eae4514e044e6b86f17406229c0c76.log` (SHA-256 `DE550E152CADA42E152900ABE28BC260749F66D1B1EBFC5266F8C7B1A11C1990`). Final full validation after this correction passed.
- `git diff --check` passed. Import generated no tracked project-setting changes. No F2-G1 scripts or protected state were touched.
- Performance values in the specification are exploratory headless measurements only; no GUI, GPU, presented-frame, OS memory, or performance-acceptance claim is made.

## Recovery and owner gates

- Reproduce with Godot 4.7.2: `scripts\validate.ps1`; focused suites are `procedural_object_tests.gd` and `terrain_brush_tests.gd`.
- GUI retest: launch the main scene, observe both object families and variable counts, move through positive/negative regions, revisit, toggle `V`, and use P2.0B F6–F9 only in a disposable world.
- Independent exact-SHA source review and owner GUI retest remain pending. PR #112 remains draft/unmerged. This checkpoint does not authorize merge or release.
- F2-G1 holds remain exactly: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
- Related owner decisions, status and entrypoint documentation updated: this specification, `README.md`, `docs/status/CURRENT_STATUS.md`, `docs/decisions/DECISION_REGISTER.md`, `docs/roadmap/MILESTONES.md`, and `docs/checkpoints/INDEX.md`. Historical checkpoints and PR #111 branch remain unchanged.

## Decision and limitations

This is an authorized implementation candidate, not technical independent acceptance or visual acceptance. Compatibility slots are deliberately retained; generic rules add populations without rewriting persisted IDs. Exact density/performance settings remain implementation defaults rather than owner-approved product budgets. A fresh review must inspect code and tests at the final PR head. Owner GUI retest is the next product evidence gate; separate merge authorization is still required.
