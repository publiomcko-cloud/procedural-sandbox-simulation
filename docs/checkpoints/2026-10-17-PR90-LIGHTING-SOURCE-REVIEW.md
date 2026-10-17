# Checkpoint — Independent source & image review PR #90 / Issue #89

**ID:** `CHK-2026-10-17-PR90-LIGHTING-SOURCE-REVIEW`  
**Event:** consequential independent GitHub source review of lighting-only PR #90, including reading before/after PNG image bytes and capture JSONs.  
**Date:** 2026-10-17; local timezone UTC−03.  
**Publication:** `RECORDED_IN_DRAFT_PR / NOT_INTEGRATED` on documentation-only [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87), after existing post-merge checkpoints. Owner GUI acceptance and merge authorization remain outstanding.

## Exact candidate and acceptance stage

- Repository: [publiomcko-cloud/procedural-sandbox-simulation](https://github.com/publiomcko-cloud/procedural-sandbox-simulation).
- GitHub `main` verified at `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb` (approved P1.0B [PR #88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88) merge).
- Lighting follow-up [Issue #89](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/89), implementation branch `fix/p1-0b-terrain-depth-lighting`, [draft PR #90](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/90) **OPEN / UNMERGED**, head `9a5cb4f36c2066c8aabb031cf10c1c5ca41489b2`, its parent `2b29498baf1a4a329b8332d5585167b43f8dbc07`, and implementation parent `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`. Two commits, 0 behind `main`.
- [Independent exact-SHA review `PASS_SOURCE_REVIEW_WITH_VISUAL_CAVEATS / OWNER_GUI_PENDING`](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/90#pullrequestreview-5560130899). This is **source+repository image examination**, not reviewer Godot execution and not owner's interactive acceptance.

## Verified source, images and evidence

- **Only production change:** `game/scenes/terrain_demo.tscn` — colored ambient energy 1.5→1.2, existing directional energy 1.3 rotated X −48°→+48° with Y −28° retained, camera SpotLight3D energy 0.42→16, range 72/angle 58, both directional/spot shadows disabled; shaded green material unchanged.
- SDF/streaming/chunk/brush/control/network/collision behavior not modified. Focused tests assert lighting scene configuration, directional downwards orientation, shadow-off policy and shaded material. Local capture script `terrain_lighting_capture.gd` is for visual evidence, not called in ordinary headless `validate.ps1`.
- Independent reviewer retrieved and viewed PNGs **for close exterior and cave, before vs after, with directional shadows off**. Terrain close exterior was nearly uniformly dark green before and visibly exhibits diffuse slope variation afterward; cave contrast grows but overall darkens. Cave surface exhibits screen-space stippling/striping **both before and after**, not evidently introduced by the light fix. This visual artifact is not diagnosed or fixed here; if intrusive on owner GUI, open a separately bounded rasterization/geometry issue.
- Before/after JSONs show identical world seed 424242, renderer/version 4.7.2, viewport 1152×648, region/target/camera poses, scene material and SDF normal stats. Baseline evidence used the **candidate scene with old lighting values overridden at runtime**, valid for a light-only diff but not a separately launched old source branch.
- Developer numeric reports (8-bit green-classified terrain pixels): close exterior luminance mean/std **88.00/0.00 → 133.84/7.70**; cave **91.15/10.22 → 82.82/14.09**. These are image-statistics not a perceptual proof of readability; effect of camera spotlight appears local (10,306 of ~434,455 cave classified pixels differ by >1% RGB). Wide camera-fill case shows no contribution.
- Developer shadow-on close-exterior test: 537,221/537,311 classified terrain pixels changed; mean luma 133.84→112.69, visible cave shadow artifacts; 180 post-warmup CPU-side frame intervals mean 1.047ms shadow-off vs 1.489ms shadow-on for exterior; not GPU-frame or guaranteed FPS performance. Both shadows remain disabled.
- Developer reports pinned Godot `4.7.2.stable.official.ed1daf0bf` import/headless startup and **7,947 assertions / zero failures** (52 smoke, 44 SDF, 89 brush, 179 chunk, 7,565 multiregion, 18 bootstrap). Reviewer inspected test/validator sources but **did not run Godot Windows independently**. [GitHub Starter checks 39069884228](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/39069884228) passed **static-only** expected-file checks (logs say Godot runtime was not run).
- Codex reports preexisting CRLF-only modification to `game/project.godot` and untracked experimental captures on Windows, excluded from PR #90. GitHub review cannot attest the local worktree or authorize forced cleanup. No changes to F2-G1 protected state.

## Open risks and explicit next gate

1. **OWNER GUI PENDING** at exact PR #90 head: Godot 4.7.2 F6, wait `Ready`, compare wide/close terrain slope illumination, orbit/zoom to test whether energy-16 camera fill washes very close surfaces, use `C` and inspect readable cave walls and the pre-existing stippling, verify `R`/streaming still work. Cave can be darker despite higher contrast.
2. PR #90 remains open/draft/unmerged; owner acceptance and later separate merge authorization needed. Do **not** infer merge from source PASS. If correction changes head, repeat independent exact-SHA review.
3. Concurrent [docs-only PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87) and PR #90 both touch `docs/checkpoints/INDEX.md` and `docs/status/CURRENT_STATUS.md`. Future authorized merge requires deliberate reconciliation against live `main`, preserving all immutable checkpoints and event histories.
4. Residual streaming stage-failure retry, partial-edit transaction and slow slice issues remain separate P1.0B source-review caveats; no action under lighting-only Issue #89. P1.0C, multiplayer, persistence, final native backend, and all five F2-G1 protected holds stay unchanged.

**Next authorized action:** owner's interactive exterior/cave visual test and decision; reviewer records owner GUI as a fresh dated checkpoint, no auto-merge. All live refs must be verified before acting.
