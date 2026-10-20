# P1.0C implementation checkpoint — Issue #91

**State:** implementation committed and locally validated; draft PR #92 open. Independent source review and owner GUI validation are pending. This checkpoint does not authorize merge, release, persistence, networking, or multiplayer work.

## Repository identity

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Workspace: `C:\Dev\sandbox-sim-dev` (the existing functional-development checkout; no additional worktree created)
- Branch: `feat/p1-0c-global-cross-region-brushes`
- Base and direct parent: `2f86c42503cfa3a334215b1ff5b9bf9658263440` (P1.0B lighting integration)
- Source implementation commit: `33710924db224cf63dbb54b5aba378956be8c45a` (direct parent `2f86c42503cfa3a334215b1ff5b9bf9658263440`)
- Source hardening commit: `71fbe678c7f6a24b2aa0f0b7813d30e154a2f9bc` (returns deep copies from the regional command view; tested against accidental mutation)
- Draft PR: [#92 — P1.0C: global cross-region terrain brushes](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92)
- Related scope authorization: [Issue #91](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/91)

The branch started clean at the owner-specified remote commit. Existing P1.0B local exploratory state was preserved in a stash before switching; no files were discarded. Main remains at the stated base in this checkpoint.

## Changes

The terrain edit model now uses one shared in-memory ledger for all region world states. Every accepted carve/fill command stores a world-space center, SDF generator version and seed, monotonic sequence and revision, stable operation ID, radius, and the exact intersected region keys. The 32-command cap, radius range 0.45–2.0, finite world coordinate bound, and at-most-four-region fanout are checked before admission; rejection does not consume a sequence or alter the ledger.

All samples replay the same ordered command stream in canonical world coordinates, including samples queried through a neighboring region at a shared plane. The support index limits mesh fanout but does not change SDF values. Unloaded regions retain no copied edit state; their meshes replay the shared ledger when loaded again.

Resident affected regions stage dirty chunks and required chunk-grid halos incrementally. A cross-region edit commits its complete set of staged meshes only after every target mesh is valid and the ledger revision still matches. A failed staging attempt leaves the old visible mesh set in place, preserves the accepted command in the ledger, retries a bounded number of times, and surfaces a retry-required status. New brush input while a global transaction is pending is explicitly rejected with HUD feedback. Failed loads and full rebuilds also retry within fixed limits and report exhaustion.

`C` remains a global visualization cut plane. Changing it cancels obsolete staged geometry but retains accepted edits and rebuilds the current window. `R` regenerates without discarding ledger commands. `X` keeps the existing focused reset interaction: it removes all commands whose spherical support intersects the focused region, keeps sequence numbers monotonic, and rebuilds all resident regions affected by those removals. Generator v1, spatial ownership, negative coordinate floor behavior, streaming limits, lighting, and camera/brush controls are preserved.

## Files in the source implementation commit

- `game/scripts/terrain/marching_tetrahedra.gd`
- `game/scripts/terrain/sdf_brush_edit_state.gd`
- `game/scripts/terrain/terrain_demo.gd`
- `game/scripts/terrain/terrain_world_state.gd`
- `game/tests/terrain_brush_tests.gd`
- `game/tests/terrain_multiregion_tests.gd`

The checkpoint and current-state references are documentation-only additions in the subsequent PR commit. No F2-G1 code or protected-state source was changed.

## Validation evidence

Executed locally on Windows using `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe` (`4.7.2.stable.official.ed1daf0bf`) and `scripts/validate.ps1`:

| Suite | Assertions | Result |
| --- | ---: | --- |
| Smoke | 52 | PASS |
| SDF generator and mesh | 44 | PASS |
| Brush and viewport | 140 | PASS |
| Chunk partition and local rebuild | 179 | PASS |
| Multi-region streaming, editing, failure injection | 7,609 | PASS |
| Bootstrap structure | 18 | PASS |
| **Total** | **8,042** | **0 failures** |

Godot import and configured main-scene startup both passed. The multiregion checks cover positive and negative seam/corner admission, actual viewport brush routing, ownership after movement, bounded region residency, exact shared SDF samples with edits and `C`, edit and load stage failure/retry, `C` during pending work, X reset semantics, accepted operations while affected regions are unloaded, replay on load, and edited chunk-union equivalence to a monolithic reference. No F2 ACL suite was run.

The local headless run reported a global two-region edit transaction affecting 2 regions, 4 chunks, and 40 mesh slices at about 281 ms measured elapsed. The 7-repeat chunk benchmark in the same validation reported full-mesh medians around 419–430 ms and localized interior/border/corner medians around 35.7/73.6/156.5 ms. These are single-machine development measurements; the machine configuration was not pinned and no frame-time or cross-machine guarantee is claimed.

## Limits and open validation

- Edits are transient RAM state and disappear when the process exits.
- The ledger holds at most 32 accepted operations; a full ledger rejects the next operation explicitly. Only one global edit transaction stages at once.
- X has focused-region semantics, not per-command undo. It removes each command whose sphere support touches the focused region.
- Meshing and publication are incremental on the main thread; this is not asynchronous work and does not promise a frame budget.
- Cross-region editing is implemented for the existing finite terrain streaming prototype. Persistence, networking, multiplayer replay, conflict resolution, and durable command IDs are not implemented.
- Automated mesh and SDF checks do not replace visual inspection. Owner GUI retest remains pending.
- All F2-G1 operational holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

## Owner visual retest

In Godot 4.7.2, run the project main scene or press F6 on `game/scenes/terrain_demo.tscn`:

1. Orbit/zoom until a region boundary is visible. Left-click carve and Shift+left-click fill while the cursor ray lands across a seam; repeat at a four-region corner. Confirm each accepted edit appears on all sides without visible cracks.
2. Move at least three regions away so edited regions leave residency, wait for streaming to settle, then return. Confirm both edits reappear.
3. Toggle `C` while a mesh transaction is staging, then toggle it back after the rebuild. Confirm the cut plane remains global and accepted edits remain.
4. Use `X` while focused on one edited region. Confirm intersecting commands disappear on all touched regions, unrelated edits remain, and the HUD reports progress/errors instead of showing a partial cross-region update.
5. Confirm green terrain readability, caves, right-drag orbit, wheel zoom, `R`, and streaming behavior remain intact.

Record the result separately. A visual pass is not merge authorization.

## Next gate

Independent review the current exact PR #92 HEAD and source/test diff. After that, the owner can perform the GUI procedure above. Keep the PR draft until those gates and a separate merge decision are complete.
