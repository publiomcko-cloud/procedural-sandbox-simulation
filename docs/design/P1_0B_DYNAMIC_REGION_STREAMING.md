# P1.0B dynamic region streaming

## Scope

P1.0B replaces the P1.0A fixed 3×3 preview with a moving active window while keeping the existing version-1 SDF, 16×12 region lattice, half-open cell ownership, 4×4 chunks per region, global Z=6 cave-section plane, and stable region/chunk identities. `orbit_target` is the view focus; its floor-mapped region key drives the stream window. WASD or arrow keys move that focus by four world units. Right-drag, wheel zoom, left carve, Shift+left fill, C, R and X remain available.

## Residency and work bounds

- Request the 3×3 Chebyshev-radius-1 window around the focused region.
- Retain already completed regions through Chebyshev radius 2 to avoid churn; regions outside that radius unload. The region lattice therefore bounds active rendering to 25 regions / 400 chunk nodes.
- Normal load staging contains at most the nine requested regions / 144 chunks / 1,440 slice jobs. A C/R/X global rebuild stages all currently resident and requested regions atomically; its hard upper bound is 25×16 = 400 pending chunks / 4,000 slice jobs.
- Generate at most one vertical mesh slice per `_process` frame. Each chunk is partitioned into ten deterministic two-cell-high slices, then concatenated in the original vertical order. A region stays unpublished until its complete 16-mesh set is ready, so a newly loaded region cannot appear as a partial patch. Existing regions remain visible during staging.
- C/R/X full rebuilds hold new meshes until every target region is ready, then replace the visible set within one frame. A focused-region brush edit stages only its affected chunks and publishes them together; existing region-edge safety rejection prevents cross-region edits.
- A slice is synchronous and cannot be interrupted internally, so its measured peak duration remains the indivisible work unit; no 60 FPS or latency guarantee is claimed. Runtime diagnostics report last/peak slice, frame delta, controller work duration, resident regions, queue depth, loads and unloads.

## Domain state and unload/reload

`TerrainWorldState` remains independent of scene nodes. Active and staged regions reference it; when an edited region unloads, its bounded ordered transient edit state is retained in memory, up to 16 edited regions. A further new edited region is rejected once that cap is reached. Unedited unloaded states are recreated from the same seed, generator version and stable key. X clears only the focused region's transient edits. Nothing survives process restart; persistence is deferred.

## Failure and scope limits

Invalid or incomplete chunk generation does not publish its stage. For a global rebuild the previous visible mesh set remains, and the cave-section mode reverts to the last completely rendered mode. A loading region outside the current request window is canceled before it can publish later. This is a main-thread prototype, not an asynchronous worker system.

Cross-region edits, persistence, networking/multiplayer, LOD, collision expansion, background workers and production backend selection remain out of scope. The test suite checks deterministic streamed meshes, requested-window movement, positive and negative seams, unloading, bounded queues/node counts, edit-state re-entry and subtle camera-aligned lighting. The headless lighting checks verify scene configuration and lit material settings, not rendered pixels.

## Owner GUI retest

Open `game/project.godot` in Godot 4.7.2, open `res://scenes/terrain_demo.tscn`, and run the scene (F6). Wait until the HUD reports 9 active regions and no queued chunks. Use D twice to cross into region `(1,0)` and A five times to cross into `(-1,0)`. Watch the terrain populate one region at a time without a visible partial-region flash or boundary gap; let the queue drain after each move. Continue moving beyond the old window and back to see regions unload and return. Check the negative-coordinate boundaries, existing carve/fill and boundary rejection, C's global cut, R regeneration, X clearing of the focused region, right-drag orbit, wheel zoom, and the subtle front-facing light in cavities. The HUD exposes focus, resident/loading/queued counts, last/peak chunk build duration and peak frame duration. Capture any visible crack, missing region, edit loss, or persistent queue and include those readings in the GUI report.
