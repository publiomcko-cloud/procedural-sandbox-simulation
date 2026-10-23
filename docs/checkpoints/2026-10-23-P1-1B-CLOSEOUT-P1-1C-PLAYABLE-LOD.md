# P1.1B technical closeout and P1.1C playable LOD candidate

**Date:** 2026-10-23 (America/Sao_Paulo).
**Event:** major milestone handoff / functional implementation.
**Publication:** recorded on feature draft PR; not integrated.
**Last verified main:** `ea4422d90726d3f2fe6d5cef097126268f93685a`.
**P1.1C source commit:** `1f79784b487ef59b932894fcb657bb0f127a8b36`, parent `ea4422d90726d3f2fe6d5cef097126268f93685a`; source review and owner GUI gates are pending.
**Branch:** `feat/p1-1c-playable-lod01`; draft PR publication is part of this handoff.

## Decision and scope

The owner authorized a technical P1.1B closeout, readiness analysis of PRs #99–#102, and an initial playable custom GDScript LOD0/LOD1 slice. This checkpoint records implementation evidence only. It does not authorize merging, release, final backend selection, native Voxel Tools, or protected-host work. No frozen P1.1B scenario was rerun in this development task.

All F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

## P1.1B closeout — historical outcomes retained

PR [#99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) remains open/draft/unmerged at the R7 harness source `2b4355363a43b73476715cf4002e31575bf9828d`. Its final frozen-catalog report recorded **40/44 UNSCORED scenarios reported passing**, with **2 historical B0G +Z failures** and **2 B0G X-axis cases blocked by process/evidence attribution**. The two +Z cases were `B0G.LOD01.FACE.Z_POS.v1` and `B0G.LOD01.CORNER.ALL_POS.v1`; both originally failed the LOD0 adjacent seam T-junction oracle. Their historical FAIL records are not rewritten.

The independent source review of [PR #102](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/102), head `e313ed70724eebef0b91cd770a2da9f5e960344d`, passed the narrow numerical-consistency correction: canonical endpoint ordering in interpolation and explicit boundary-oracle validity checks, without relaxing tolerances. Codex reported the two original +Z cases and two regression controls passing after correction. Raw Windows campaign artifacts were not independently replayed here; these remain reported UNSCORED executions. The two X-axis attribution cases remain **BLOCKED**, were not rerun, and do not become passes. The other 38 catalog results retain their prior reported classification.

PR #99's B0S streaming/reload requalification report records 11/11 UNSCORED scenario PASS after the earlier evidence-custody incident; it explicitly distinguishes the earlier 2 blocked/9 not-run campaign and notes raw evidence and process ancestry were not independently replayed/attested. B0A/B0E ledger and seam results are likewise experimental UNSCORED results. The B0G tunnel cases test sampled density connectivity, not gameplay collision. Across P1.1B, no target-hardware score, accepted geometric/performance budget, GPU completion, presented FPS, VRAM/RSS, GUI acceptance, production-backend decision, or release acceptance is established.

## Pending PR readiness and proposed integration order

Live GitHub readback at this checkpoint: #99, #100, #101, and #102 are open draft PRs; no state was changed.

| PR | Content / relation | Recommendation |
|---|---|---|
| #99 | B1-1 frozen experimental harness, contract, manifest, tests; based on `main` | Review exact final source and evidence package, then owner decides independently. Preserve all historical failures, blocks, and exclusions. |
| #102 | Narrow +Z interpolation correction plus fixture regressions; based on #99 and depends on its contract/tests | If accepted, integrate after #99, then independently verify resulting main. Its modified fixture overlaps the P1.1C feature's copied correction; reconcile/retest P1.1C against the resulting main rather than assuming branch compatibility. |
| #100 | Engine-goals/roadmap documentation; overlaps README, checkpoint index, decisions, milestones, and CURRENT_STATUS | Reconcile its snapshot with current main and P1.1C before any owner-authorized integration. |
| #101 | P1.1B checkpoint/status documentation; overlaps index, decision register, and CURRENT_STATUS, and includes incident history | Preserve chronology and reconcile after #100 or explicitly resolve both from verified live main. Do not overwrite the newer P1.1C event or erase incident records. |

Suggested sequence is #99, then #102, then rebase/review P1.1C against that resulting main; reconcile #100/#101 against the accepted source/docs state one at a time. This is a recommendation, not merge authorization. For any later integration regression, use a new revert commit for the specific accepted commit; do not reset or rewrite history.

## P1.1C implementation and evidence

The feature commit is based directly on verified `main` `ea4422d...` and reuses the P1.1A transition-cell code, including PR #102's canonical endpoint-order correction. New camera-distance selection uses 56/46 hysteresis and L toggle; LOD defaults off. LOD1 meshes compose a complete 4×10×3 coarse-cell chunk with one shared sample/normal builder, retaining per-cell composition as an independent test oracle. A same-chunk synthetic comparison reports 384 LOD0 triangles and 244 LOD1 triangles; this count is one geometry sample, not an acceptance budget. Shared-builder/per-cell elapsed samples in the focused test were 62.769/68.013 ms in the full validation run's adjacent focused run; they are single-run exploratory CPU timings.

Streaming/edit invariants remain delegated to the existing transaction pipeline: seed/generator and ledger snapshots, signed ownership, edit revisions, four CPU workers, two ArrayMesh constructions per frame, maximum 25 active/resident region policy and 400 active chunks remain unchanged. LOD changes stage at most one region's replacement at a time; old meshes remain visible until partial-region commit. A stale camera-level selection is superseded; invalid LOD1 output falls back to LOD0.

### Changed implementation and test paths

- `game/scripts/experiments/lod01_transition_fixture.gd` — reuse the reviewed deterministic edge interpolation; add data-only shared-cache LOD1 chunk construction.
- `game/scripts/terrain/terrain_lod_policy.gd` — new bounded LOD0/1 selection/hysteresis.
- `game/scripts/terrain/lod01_chunk_mesher.gd` and `.uid` — new fixed-grid coarse chunk assembly and independent per-cell equivalence oracle.
- `game/scripts/terrain/marching_tetrahedra.gd` — optional density callback for synthetic seam tests; default production sampling path is unchanged.
- `game/scripts/terrain/terrain_mesh_job.gd` — immutable-snapshot LOD1 worker path and LOD0 fallback.
- `game/scripts/terrain/terrain_demo.gd` — opt-in selection, staged stale-safe publication, per-chunk level/fallback diagnostics, L toggle.
- `game/tests/terrain_lod_runtime_tests.gd` and `.uid` — policy, seam, edit/rebuild, geometry equivalence, triangle-count, stale-result, fallback tests.
- `game/tests/terrain_multiregion_tests.gd` — actual scene-stage LOD1 publication and LOD0 rollback.
- `scripts/validate.ps1` — includes the new LOD runtime suite and required source files.

### Godot and validation evidence

Engine: `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`. The completed `scripts/validate.ps1` run ended `VALIDATION_PASS: L0-L2`; all suites passed. Assertion sum from the emitted suite markers: **16,863 assertions, zero failures across 13 suites**. Import and configured main-scene startup passed. Newly relevant results: transition fixture 6,441/6,441; playable LOD runtime 53/53; multi-region runtime 7,637/7,637. The runtime test reported same-coordinate synthetic triangle counts 384→244, LOD test build aggregate 190.382 ms, shared builder 62.769 ms, per-cell reference 68.013 ms; one run only, exploratory. Existing full validation also reported headless 144-chunk initial scene and edit/stream measures; they are not attributable to LOD acceptance. No B0 frozen scenarios, scored benchmarks, GPU tests, or visual pixels were assessed.

## Owner and independent gates

1. Independent exact-SHA source review of the final draft head.
2. Owner GUI retest in the actual main scene using the procedure in [P1.1C slice spec](../specs/P1-1C-PLAYABLE-LOD01-SLICE.md): toggle LOD with L, inspect mixed-LOD seams, traverse signed regions, edit/cut/rebuild/reset, observe fallback and errors.
3. Separate owner integration decision; this source/validation checkpoint grants no merge authority.

No acceptance threshold exists for geometric/screen error, thin-cave preservation, main-thread stall, FPS, RAM, or VRAM. LOD1 may remove sub-cell features. LOD2+, collision changes, persistence, networking, Voxel Tools, ADR-0002 adoption, and F2-G1 operations remain outside scope.

## Repository and workspace recovery

The existing designated `C:\Dev\sandbox-sim-dev` workspace was used. The three pre-existing untracked B1 `.gd.uid` files and `stash@{0}` were preserved; the three new P1.1C `.uid` files for the policy, chunk mesher, and runtime test are part of the feature. No other worktree was created. Source and documentation commits are to remain on `feat/p1-1c-playable-lod01`; checkpoint publication is pending PR creation/readback. The index entry records this event; CURRENT_STATUS/CHANGELOG were not rewritten because no merge occurred and concurrent docs PRs #100/#101 remain open.

**Current disposition:** P1.1B catalog remains **40/44 historically reported UNSCORED PASS**, 2 reported +Z failures with a source-reviewed correction and reported focused retest, and 2 X-axis attribution BLOCKED. P1.1C is an initial integrated playable source candidate with LOD0 fallback; independent source review and owner GUI validation are pending. All five F2-G1 holds remain.
