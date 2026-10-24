# 2026-10-24 — P2.0B persistent procedural object state implementation

## Event and identity

Owner-authorized implementation candidate for P2.0B in `publiomcko-cloud/procedural-sandbox-simulation`. Required baseline and direct parent: `d23f5ee37f8e13b3bb5c6b7b5dbbe16997a0b499`. Existing branch: `feat/p2-0b-persistent-object-state`. Draft PR: [#110](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/110), open/draft/unmerged when checked. Source implementation commit: `f090cf50fd32d6c9b8497a1d9fe3c1a659593577`, parent `d23f5ee37f8e13b3bb5c6b7b5dbbe16997a0b499`. The branch also carries this checkpoint/status documentation reconciliation; no product code changed after the source commit. Verify the final PR head from live GitHub before review.

Remote origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`. At pre-push verification, `origin/main` and the pre-existing feature branch were both at the required baseline. No new worktree or branch was created. The existing `stash@{0}` and three pre-existing untracked benchmark `.gd.uid` files remained untouched and unstaged.

## Implementation

- Added Node-independent version-1 contracts for transform, appearance and extensible logical components. Strict schemas constrain types, coordinates/angles/scales, color, text and logical key/value counts; no script or executable values can enter state.
- Added a separate versioned object-state store with canonical JSON payloads, SHA-256 corruption detection, immutable generations, bounded size/record counts, write/readback/rename verification, incomplete-temp recovery and fail-closed corrupt-final handling. Terrain world-save schema 1 and files remain outside this store.
- The default path separates state by world ID, world seed and generator version. Untouched objects remain derived from their pinned P2.0A recipes/seeds; no per-object disk record is required until a change or logical deletion is committed.
- The model service validates deterministic identity and exact content pins before resolving, mutating, deleting or restoring. Stream publication applies overlays only after baseline regeneration and rejects stale publication tokens. A seed-domain switch releases prior visual roots before the new seed is published.
- Added F6 object selection, F7 transform/appearance override, F8 logical deletion, F9 baseline restoration, revision/status HUD feedback and test-only injection points for isolated roots. First-party and external definitions continue through the same P0.3 declarative registry.
- Added a separate-process restart probe and regressions for negative regions, ID/pin identity, sparse baseline, component and snapshot bounds, schema incompatibility, corruption, interrupted writes, complete-temp recovery, storage failure, seed separation, unload/revisit, stale results, terrain schema-1 byte preservation and playable scene mutation/restoration.

Full contract and limitations: [P2.0B persistent object state spec](../specs/P2-0B-PERSISTENT-OBJECT-STATE.md).

## Validation evidence

Godot executable: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`; version `4.7.2.stable.official.ed1daf0bf`.

- Import: exit 0.
- Focused `res://tests/procedural_object_tests.gd`: **267 assertions, 0 failures**, exit 0.
- Full `scripts/validate.ps1`: **17,527 assertions across 16 groups, 0 failures**, `VALIDATION_PASS: L0-L2`, exit 0. Groups: smoke 52; SDF 44; brush 611; chunk 179; multiregion 7,637; terrain perf 11; history 842; terrain persistence 321; declarative mods 44; procedural objects 267; viewport picker history 713; LOD fixture 6,473; LOD runtime 53; end-to-end perf 251; concurrency 11; bootstrap structure 18. Main-scene startup exited 0. Final stderr was empty.
- First full attempt exited 1 with ten repeated failures in one placement fixture because the edited assertion read `instance_components` from baseline records, while P2.0A still exposes the intentionally empty legacy `instance_state` field and the new sparse components live in the separate state snapshot. The assertion was corrected to check that unchanged baseline field; no production behavior or expected persistence semantics were weakened. The focused test and complete suite were rerun afterward and passed.
- Evidence logs retained locally under `C:\Users\PUBLI\AppData\Local\Temp\p2-0b-validation-7edd5db2bf34403494a4ccea32a09c6d\`: `import.stdout.log`, `import.stderr.log`, `objects-r3.stdout.log`, `objects-r3.stderr.log`, `objects-final.stdout.log`, `objects-final.stderr.log`, `full-validation.stdout.log`, `full-validation.stderr.log`, `full-validation-final.stdout.log`, `full-validation-final.stderr.log`.

`git diff --check` passes for the final documentation changes and no terrain source, P0.3 loader, native dependencies or protected F2-G1 files were changed. Headless validation is not owner GUI acceptance or visual pixel review.

## Scope boundaries and residual limitations

State is local to the current demo world and the two P2.0A object slots. SHA-256 is corruption detection, not keyed authenticity. The implementation does not claim fsync/power-loss durability, malicious-local-user protection or concurrent multi-process writer locking. Filesystem commit and visual republish are not one atomic transaction; if a post-commit visual rebuild fails, state remains committed, the error is reported and a later region publish resolves the saved model. Component schema version 1 has no migration. Issue #108 terrain/object conformance, collision/physics, networking, multiplayer, general ECS and native dependencies remain excluded. F2-G1 holds are unchanged.

## Owner GUI gate and next action

Owner should run Godot 4.7.2 from a fresh or disposable local demo profile, wait for the focused region and verify two objects at state revision 0, then press F6, F7, F8 and F9 in order. Confirm transform/tint changes, revision increments, delete/restore visibility, move far enough for region unload and return, then restart and confirm persisted state without duplicate objects. Press V to hide/show only presentation. Record GUI PASS/FAIL separately. Next gate is independent source review of the exact final PR #110 head and owner GUI retest; no merge is requested. All five F2-G1 holds remain.
