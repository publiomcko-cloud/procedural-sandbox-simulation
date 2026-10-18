# P1.0C PR #92 — independent normal-dependency correction rereview PASS

**ID:** `CHK-2026-10-18-P1-0C-PR92-REREVIEW-PASS`  
**Date:** 2026-10-18 (UTC−03).  
**Event:** independently verified correction of source acceptance blocker at prior [review 5562602003](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5562602003).  
**Verdict:** `PASS_SOURCE_REREVIEW / OWNER_GUI_PENDING / NO_MERGE`. Source acceptance for this correction **is not owner GUI acceptance nor permission to merge**.
**Publication:** written to separate draft documentation [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87); unmerged snapshot, not integrated in main.

## Exact source and GitHub identity

- Repository: [publiomcko-cloud/procedural-sandbox-simulation](https://github.com/publiomcko-cloud/procedural-sandbox-simulation), verified live `main` `2f86c42503cfa3a334215b1ff5b9bf9658263440`, prior accepted lighting PR #90 merge.
- [Issue #91](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/91), [feature PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92), open/draft/unmerged, head **`163ef37a1ec0aab33dfea773a4176fae470161d8`**, direct parent `ff36c78e65635c06b70c344e5128a4f0eb55d77e`.
- Functional fix commit **`ad9997b2deaf285d01e360bb7f7adb9d0f03ba41`** is direct child of previously reviewed `608b7d6d621d0b340454f84c00a9ad7bb0379317`. Later two commits change documentation only.
- [GitHub independent review #5563949929](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5563949929) explicitly certifies source review at the above exact head, not Godot GUI/pixel results.

## Blocker closed by source-level examination

- `sdf_brush_edit_state.gd`: each canonical command distinguishes `support_regions` (actual sphere-intersecting regions, canonical ownership, spatial support, focused `X`), `dependency_regions` (neighbor regions whose gradients may read modified SDF samples), and `rebuild_regions` (union of support + dependency). Conservative dependency radius includes `GRID.SAMPLE_STEP=0.5` around physical radius, exceeding ±0.25 probe in marching-tetrahedra shared-vertex normals. Limits (max four regions each and 32 commands) and rejection-before-append remain enforced.
- `terrain_demo.gd` cross-region edit scheduler and pending-loading neighbor reconciliation now iterate `rebuild_regions` rather than only physical-support regions, select chunk/sample halos and preserve revision-pinned staged multi-region publishing. Unloaded dependent regions are reconstructed from the global ledger on load.
- Focused `X` removes commands **only if region belongs to `support_regions`**, never just because a normal gradient depends on it; returned remesh list includes dependency regions after deletion. Original cave toggle C, R, shading, v1 SDF and streaming limits preserved.
- New unit and scene tests exercise one-sided near-X borders on both sides of zero and a negative region, positive/negative near-corner fanout, negative ownership, reset that preserves dependency-only edits, seam normal equality after rebuilding both sides, and a deliberate stale-neighbor normal mismatch. Integration tests inject a stage failure, keep old meshes until both sides commit, stream a dependency-only region out and back and check the reloaded mesh's vertices/normals against a newly generated reference.

## Validation evidence boundary

- Codex reports local Windows Godot `4.7.2.stable.official.ed1daf0bf`, import and main scene startup, `scripts/validate.ps1`: **8,083 assertions PASS, 0 failures** (52 smoke + 44 SDF + 156 brush/viewport + 179 chunk + 7,634 multiregion + 18 bootstrap). The independent reviewer inspected source/test logic but **did not execute Godot on Windows**.
- [Hosted Starter CI #39123863207](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/39123863207) passed **static file checks only**; the job's log explicitly says Godot runtime validation is not performed.
- Developer-reported local global-edit measurement was about 3,315ms for 2 regions, 4 chunks, 40 mesh slices; mesh-slice peak ~30.3ms, controller process peak ~67.5ms. Earlier ~281ms measurements are not a stable baseline, and neither measurement proves guaranteed frame rate. The overhead merits later performance review, but it is not a new source correctness blocker.
- Reviewer cannot verify Codex's reported clean local Windows worktree or `stash@{0}`; do not reset/clean/discard.

## Remaining owner gate and risks

1. **Owner GUI REQUIRED at exact reviewed feature head:** Godot 4.7.2 F6; wait for Ready/queue settling, carve/fill across region seam and four-region corner, then place a brush just *inside* the border without crossing it. Orbit/zoom and inspect normals/lighting on both sides. Stream dependent-only neighbor out and back, inspect seam; test negative regions, C during rebuild, R and focused X removal. Record acceptance as a new event/checkpoint, not a reinterpretation of this source PASS.
2. Four-region rapid focus oscillation during in-flight commit is not exhaustively stress tested; prior `failed_pending_retry`/manual-R contract is retained, no full power-failure durability claimed. Global 32-operation cap, 25 resident-region/400-chunk cap, RAM-only edits; no disk persistence or actual networking/multiplayer.
3. PR #92 and separate docs-only [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87) **both draft and unmerged** and both change README/current status/checkpoint index/decision roadmap material. Preserve historical checkpoints and reconcile any overlapping docs against the exact live main at the eventual separately owner-authorized merge.
4. F2-G1 protected state/Hyper-V/ACL work remains on five holds: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. PRs #75–#77 untouched.

**Authorized next action:** owner GUI validation of PR #92. Then record the result and request **separate explicit merge permission**. Do not merge automatically based solely on this source review.
