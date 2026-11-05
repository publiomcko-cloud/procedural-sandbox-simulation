# P3.1 — Playable scalable materialized-SDF runtime

Status: **PLAYABLE_RUNTIME_READY_FOR_OWNER_LOAD_AND_FIDELITY_TEST**

Qualified implementation HEAD: `e550f4d08d8966af4f5922aace5afdb71c184e0d`

GitHub Actions:
- run: `42033376337`
- job: `127265161890`
- Godot: `4.7.2.stable.official.ed1daf0bf`

## Runtime architecture

The normal `terrain_demo.tscn` now uses the scalable terrain path by default:

```
ordered edit commands
      |
      v
TerrainScalableSdfState
  |             |
  | live tail   +---- async immutable checkpoint snapshot
  |                         |
  |                         v
  |                 worker checkpoint job
  |                         |
  |                         v
  |                 float64 materialized SDF tiles
  |                         |
  +-------------------------+
              |
              v
    local spatial snapshots
              |
      +-------+--------+
      |                |
interior mesh      X-region collar
TerrainMeshJob     SharedSurfaceBoundaryMeshJob
      |                |
      +-------+--------+
              |
        coherent publication
```

Historical journal segments are retained for audit/rebuild but are not replayed during normal streaming or region reload.

## Async checkpoint semantics

A checkpoint never mutates the live state from the worker thread.

The main thread freezes an immutable prefix of the live edit tail. The worker opens an isolated materialized store, replays only that frozen prefix over the last committed materialized generation, writes a new generation, and returns the committed head.

On completion the main thread atomically advances the materialized base. Any edits accepted after the frozen prefix remain in the live tail and are re-marked dirty for a later checkpoint.

The worker does not recursively submit materialization tasks to the same worker pool; tile materialization is performed inside the checkpoint worker.

Automatic checkpoint target: **128 live edits**.

`P` requests the same asynchronous checkpoint manually.

## Shared boundary runtime

X-region edge chunks are generated through `SharedSurfaceBoundaryAuthority` and are forced to LOD0. LOD1 begins one chunk inward.

The runtime qualification observed:
- bad seam incidence: 0
- T-junctions: 0
- duplicate triangles: 0
- crossing seam edges: 18
- cross-owned crossing seam edges: 18

Scope: this runtime integration currently owns **X regional boundaries**. Z regional boundaries and X/Z corner authority are not yet promoted to the shared-boundary architecture. Cave-section display also falls back to the pre-existing meshing path.

## Regression qualification

On the same HEAD:

- frozen shared-surface E2E: **48 assertions, 0 failures**
- materialized-SDF scalability/fidelity: **45 assertions, 0 failures**
- playable runtime unload/reload: **21 assertions, 0 failures**

The 4,096-edit scalability test still preserves:
- zero journal reads on hot gameplay load
- exact LOD0 and LOD1 vertex positions versus full ordered-history oracle
- exact materialized/shared-boundary signature versus oracle
- zero bad incidence and zero T-junctions

## Playable runtime qualification

The scene test instantiated the real `terrain_demo.tscn`, injected 256 deterministic edits, ran checkpoint and terrain rebuild concurrently, moved 64 m away so the edited origin region unloaded, settled the distant window, returned, and waited for the edited region to republish.

Evidence:

- pre-edits: 256
- checkpoint generation: 1
- checkpoint worker time: **1,944.541 ms**
- checkpoint overlapped terrain rebuild: PASS
- edited origin region unload: PASS
- edited focus-region reload: **1,766.146 ms**
- complete 3x3 window settle after 64 m return jump: **11,718.647 ms**
- post-focus remaining window settle: **9,952.446 ms**
- journal reads during unload/reload: **0**
- materialized lifetime count after reload: 256
- live tail after checkpoint/reload: 0
- streamed region loads/unloads: 36 / 18

Hosted-headless frame evidence:
- frame p50: **6.896 ms**
- frame p95: **6.944 ms**
- frame p99: **9.524 ms**
- peak frame: **142.388 ms**
- peak measured process work: **69.396 ms**

These hosted headless timings are evidence, not a desktop FPS certification. The important architectural result is that the ~1.95 s checkpoint work executes outside the gameplay frame and region reload does not replay historical edits.

## Pre-edit fixture

Press `F5` when terrain staging is idle.

Default batch: 512 deterministic edits around the current focus, including edits close to/crossing the X regional boundary.

Configure count:

```
-- --preedit-count=2000
```

Maximum accepted by this test input: 20,000.

Configure a file:

```
-- --preedit-path="C:\path\edits.json"
```

Accepted JSON forms are either a top-level array or an object containing `operations`.

Example:

```json
{
  "operations": [
    {"mode": "CARVE", "center": [15.5, 2.0, 7.0], "radius": 0.8},
    {"mode": "FILL",  "center": [16.2, 2.1, 7.2], "radius": 0.7}
  ]
}
```

Coordinates are canonical world coordinates.

## Owner manual test objective

1. start the game and wait until the initial 3x3 streaming window settles;
2. press F5 once;
3. keep interacting while the HUD reports checkpoint/rebuild activity;
4. wait until the HUD reports a committed materialized generation and hot tail 0;
5. move the focus far enough that the edited origin region leaves the unload radius;
6. return to the edited region;
7. judge time-to-visible, frame behavior, edit fidelity and X seam fidelity;
8. record HUD timing values and any visible crack, lost edit, stall or stale mesh.

The full 3x3 window is not required to finish before the player can see/use the focus region. Time-to-focus-ready is the primary responsiveness metric.
