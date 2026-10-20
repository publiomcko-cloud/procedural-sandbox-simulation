# P1.0C PR #92 — optimization independent source review (2026-10-18)

**Checkpoint ID:** `CHK-2026-10-18-P1-0C-PR92-PERF-SOURCE-PASS`  
**Event:** independent review of performance Issue #93 after owner GUI latency rejection; exact source SHA, tests, metrics and review posted on GitHub.  
**Verdict:** `PASS_SOURCE_REVIEW_WITH_PERFORMANCE_CAVEATS / OWNER_GUI_PERF_RETEST_PENDING / NO_MERGE`.  
**Publication status:** recorded in open draft docs-only [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87). This document, like PR #92 source, **has not been merged into main**.

## Immutable SHA and acceptance identity

- Repository [publiomcko-cloud/procedural-sandbox-simulation](https://github.com/publiomcko-cloud/procedural-sandbox-simulation), verified `main` `2f86c42503cfa3a334215b1ff5b9bf9658263440`.
- [Issue #93](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/93) opened after owner's complaint that carve/fill and region startup/travel were unacceptably delayed. Issue remains open until actual owner GUI acceptance.
- [Feature PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) remains OPEN/DRAFT/UNMERGED, reviewed HEAD **`6d128e3d231aa0456c42cf06e9e60f5a861d59df`**, direct parent implementation `69a168eb6fe2a42f3fd6cb40024f86ed50634c2b`; implementation direct parent was previous source-reviewed candidate `163ef37a1ec0aab33dfea773a4176fae470161d8`. Delta: two commits, 17 paths changed since prior review.
- [Independent SHA-specific review #5564956018](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5564956018) published after inspecting GitHub source, test scripts, git metadata and hosted static CI logs. **No owner-host Godot or actual GUI renderer was run by this reviewer.**

## Code design audit and evidence

- Previous one 2-cell-high chunk mesh slice/frame fixed scheduling is removed. `terrain_demo.gd` uses up to **four concurrent WorkerThreadPool chunk CPU jobs**, prioritizing edits over full stages and region streaming, with **two final ArrayMesh creations per process frame**. Workers return only CPU packed vertex/normal data, not scene nodes or Mesh resources.
- `SdfBrushEditState.get_meshing_snapshot()` creates packed centers/radii/modes from the global 32-command ordered ledger, then workers use read-only input. Stage tokens and revision validation discard canceled or obsolete results after movement, C/R/X and edit operations, with old meshes retained until full selected multi-region target validation and coherent same-frame commit. An accepted command can remain in memory while visible mesh awaits manual R if bounded retries are exhausted: **not full transaction durability**.
- `marching_tetrahedra.gd` now generates one CPU chunk mesh directly, skipping uniform-sign cells, removing intermediate slice ArrayMesh/readback and using shared normal caching and fewer short-lived allocations. Serial vs worker geometry and normals (0/1/32 ledger commands) are checked for exact equality in focused tests; all canonical SDF v1, region ownership, near-seam normal dependency halo, chunk resolution, X reset semantics, and existing lighting remain.
- A ring buffer records frame timings; expensive HUD formatting/stats update is reduced to 4Hz. Review notes **publication can replace multiple previously built meshes on the same frame**. The cap of two mesh *creations* per frame does not guarantee a bound on all scene mesh replacements; `_replace_node_mesh` reads Mesh arrays to maintain triangle totals. GUI p99 hitches, four-region commit and global C/R should be checked.
- Rapid focus oscillation while a four-region transaction publishes is not exhaustively tested. Worker pool slots may remain held by stale running jobs until completion, safely bounded but potentially delaying new requests. The source review found **no concrete new correctness blocker**; these are explicit acceptance caveats, not measured new user failures.

## Timings and independent validation boundary

- Codex reports pinned Godot `4.7.2.stable.official.ed1daf0bf` import/startup and `scripts/validate.ps1` **8,133 assertions PASS, zero failures**: smoke 52, SDF 44, brush 156, chunks 179, multiregion 7,634, perf/kernel 12, end-to-end 27, concurrent cancellation 11, bootstrap 18. Actual Godot execution and local clean worktree are **developer-reported**, not independently verified through GitHub.
- [Hosted Starter CI #39151428671](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/39151428671) successful: its `static` log explicitly states **Godot runtime validation is NOT performed**.
- Developer's local cold 9-region window 9,929ms baseline → 1,080ms optimized (about 9.2× faster); direct chunk kernel p50 0/1/32 global commands 38.7→21.9ms, 45.7→27.5ms, 132.7→74.1ms respectively; same-machine samples, five repeats and warm-up.
- Five headless viewport input clicks: interior **54.9ms p50/61.8ms p95**; near seam **54.7/75.5ms**; 32nd accepted seam command 62.0ms. New 5-camera-region crossings ~379.5/393.2ms p50/p95; edited 3x3 32-command window return 1.54s. **No same-harness pre-change viewport or crossing baseline**; old accepted brush ~3.3s is indicative but not a controlled direct comparison.
- "Click-to-visible" instrumented metric ends at coherent scene MeshInstance commit, **not pixels shown or GPU upload/scanout**. Headless frame p95/p99 ~6.9–8.3ms in representative reported scenarios is not interactive rendered FPS evidence; a separate synchronous reference/integration test measured a ~118.9ms frame p99. GUI GPU/renderer tests remain required.

## Next gate and protected state

- **Owner performance GUI retest:** launch exact PR #92 candidate from existing `C:\Dev\sandbox-sim-dev` in Godot 4.7.2, wait until 9 requested regions/144 chunks complete, carve/fill repeatedly at interior, seam and four-way corner, including near-but-noncrossing border normals, and verify visual speed/cracks/lighting. Navigate positive/negative regions and return to edited ones; test rapid movement, C/R/X, responsiveness, region queue and global 32-command cap. Report renderer/GPU and any visible p99 stall/popping; only owner can decide whether this is now usable.
- Current PR #92 may proceed to owner GUI **but no merge** without separate explicit permission. If GUI fails, revise same PR with pinned new SHA and repeat independent review.
- Docs-only PR #87 and feature PR #92 overlap on checkpoint index/current status/README; preserve immutable evidence and consciously reconcile final merge order, do not merge either automatically.
- No persistent save, multiplayer/network, LOD, collision, production native/backend selection or protected F2-G1 operation. Five holds: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. Reported `stash@{0}` was not touched by this GitHub-only review.

**Next decision:** user interactive performance/pixel validation, then record its own checkpoint and request explicit merge authorization for PR #92 if accepted. Keep Issue #93 open pending that gate.
