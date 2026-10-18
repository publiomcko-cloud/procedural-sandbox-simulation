# Checkpoint — P1.0C PR #92 independent source review (2026-10-18)

**Checkpoint ID:** `CHK-2026-10-18-P1-0C-SOURCE-REVIEW-PR92`  
**Event type:** independent repository source/test review of new globally ordered streamed cross-region SDF edits.  
**Outcome:** `CHANGES_REQUIRED_FOR_ACCEPTANCE / OWNER_GUI_PENDING / NOT_MERGED`.  
**Publication:** in [open draft documentation PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87); **not integrated on main**. This independent review does not authorize any PR merge or production release.

## Verified state and evidence

- GitHub repo [publiomcko-cloud/procedural-sandbox-simulation](https://github.com/publiomcko-cloud/procedural-sandbox-simulation), `main` verified at `2f86c42503cfa3a334215b1ff5b9bf9658263440`.
- [Issue #91](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/91), [draft PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92), exact reviewed head `608b7d6d621d0b340454f84c00a9ad7bb0379317`, parent `71fbe678c7f6a24b2aa0f0b7813d30e154a2f9bc`, direct implementation base `2f86c42503cfa3a334215b1ff5b9bf9658263440`; compare 3 commits ahead/0 behind; 13 changed paths.
- [Independent SHA-specific review 5562602003](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5562602003). Reviewer inspected actual GDScript, tests, PR changed paths, Git metadata and CI run logs; reviewer did **not** independently execute Godot on owner Windows host or inspect the reported stash.
- Codex reported pinned Godot `4.7.2.stable.official.ed1daf0bf`: 8,042 assertions/zero failures (smoke 52, SDF 44, brush 140, chunk 179, multiregion 7,609, bootstrap 18) + import/startup. Reviewed source/test paths, but Godot counts remain developer-attested only. [GitHub #39076447104](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/39076447104) and [#39076450286](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/39076450286) each only validated static file presence; logs expressly say Godot runtime validation was NOT performed.
- Codex-reported local headless global-edit transaction ~281ms for 2 regions/4 chunks/40 slices, not representative of GUI latency distribution or frame budget. Developer reports prior exploratory P1.0B state in `stash@{0}` and clean feature branch; the reviewer cannot remotely inspect or authorize deleting the local stash.

## Positive source-review findings

- `sdf_brush_edit_state.gd`: single globally shared in-memory ledger, up to 32 canonical ordered operations, monotonic operation sequence/revision, world-space centers with finite/radius/world bounds, region support index and defensive copies; rejected operation does not increment counters or mutate log.
- All streamed regions sample one global command stream; unloaded regions recreate derived geometry from the ledger without duplicating command copies. Supports negative mathematical-floor regions and on-boundary two/four-region fanout. `X` deliberately deletes commands *whose actual sphere support touches the focused region*, then rebuilds active meshes; it is not single-operation undo. `C`, `R`, camera, lighting, v1 field and transient-only memory remain in scope.
- Resident/global edit mesh preparation is revision-pinned; all currently selected target stages and meshes are checked before committing together in the same process frame. A failed stage triggers bounded retries and after exhaustion retains canonical operation while old meshes remain with an explicit `failed_pending_retry`/manual-R contract; this is not full transactional rollback.
- Tests directly exercise actual viewport event path, support seam/corner keys, positive/negative ownership, edited two-region monolithic triangle/winding equivalence, C toggle during edit, unloaded reentry and injected edit/load failures.

## Source acceptance blocker: missing region-level normal dependency halo

Canonical `affected_regions` in `sdf_brush_edit_state.gd::_regions_intersecting_sphere()` is the list of regions whose bounding boxes intersect the exact **sphere support**. `terrain_demo.gd::_schedule_edit_transaction()` stages resident regions selected from only those keys. Yet `marching_tetrahedra.gd::_sample_outward_normal()` computes seam normals from SDF evaluations ±`STEP*0.5` (0.25 units) beyond the vertex, and `terrain_chunk_grid.gd::affected_chunks_for_sphere()` already includes a one-sample-step dirty halo for this reason.

**Specific source-level dependency:** at the region X=16 plane, a center X=15.0 radius 0.9 ends at X=15.9, so the physical support does not include the right region. A normal on the shared X=16 plane reads X=15.75, potentially inside the sphere; a left mesh update can recalculate that normal while an active right-side mesh remains baked with its former normal. This risks a visible shading seam without mismatched triangle positions. The exact visual defect was **not reproduced in Godot GUI**, but the missing dirty fanout follows from reviewed code. Existing edited seam tests place their brushes on the seam, so the neighbor is already in the support set; they do not prove this one-sided dependency case.

**Required bounded correction** in the same PR #92: separate exact support regions for canonical edit identity/reset from conservative dirty regions/chunks for mesh and normal dependencies, including X/Z and negative near-corner cases. Add tests at valid terrain-surface heights proving shared seam normals and neighboring mesh revision update, plus unload/reload and focused X effect; include normal comparison, not only triangle position/winding. Maintain single ledger command, 32-cap, streaming bounds and SHA-specific review cycle. Do not add persistence, multiplayer or unrelated native work.

## Other qualification and next gates

- Existing 8,042 developer-reported tests do not establish fast-focus oscillation during an unfinished four-region mesh transaction. Keep this as a separate focused regression suggestion if the dirty-region fix touches cancellation code.
- [Docs-only draft PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87) and [feature draft PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) overlap on checkpoint index, current status, README and decision/roadmap files; preserve both history branches and reconcile after later owner decisions, not through an unauthorized merge.
- Owner GUI is **not yet an accepted PASS**. After the correction and another exact-head source review, owner should test seam/corner edits, neighboring shading, unload/reentry, X/C/R, stream queue and lighting; no merge without separate explicit owner authorization.
- No claims of durability across app restart, networking/server authority, production backend adoption, or 60FPS. F2-G1 five protected holds and protected draft PRs #75/#76/#77 remain unchanged.

**Next authorized action:** bounded Codex correction on the existing branch/workspace of PR #92, then rerun pinned Godot 4.7.2 L0–L2 suite and independent re-review; no new worktree and no automatic merge.
