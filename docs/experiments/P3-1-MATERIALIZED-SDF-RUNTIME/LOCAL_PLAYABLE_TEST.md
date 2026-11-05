# Local playable unload/reload test

Qualified implementation: `e550f4d08d8966af4f5922aace5afdb71c184e0d`

## Update the existing local branch

```powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin
git status
git merge --ff-only origin/exp/p3-1-shared-surface-e2e-success
git rev-parse HEAD
```

Documentation commits may place the branch HEAD after the qualified implementation commit.

## Launch

```powershell
$godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"

& $godot --path C:\Dev\sandbox-sim-dev\game
```

The normal main scene is the playable `terrain_demo.tscn`.

## Recommended first manual test

Wait for the initial terrain window to settle. Then press **F5** once.

F5 injects the configured pre-edit batch and schedules:
- coherent mesh rebuilding;
- shared X-boundary regeneration;
- asynchronous materialized-SDF checkpointing.

The previous visible meshes remain until replacement publication is coherent.

Watch the HUD for:
- `Materialized SDF: archived ... | hot tail ... | generation ...`
- checkpoint running / committed state
- `Runtime timing`
- frame p50/p95/p99
- current focus region.

For a first visual run use the default 512 edits.

Move with **D / Right Arrow** until the HUD focus is region `(3, 0)` or farther. The original region `(0, 0)` is then outside the retention radius and should unload.

Move back with **A / Left Arrow** until the focus returns to `(0, 0)`.

Check:
- the edited terrain reappears unchanged;
- no X-boundary crack appears;
- movement/input remains responsive while loading;
- HUD time for the streaming operation is acceptable;
- archived edit count is preserved and hot tail returns to 0 after checkpoint.

Hosted headless reference for 256 edits and a 64 m jump:
- focus region visible again: ~1.77 s
- whole 3x3 window settled: ~11.72 s
- frame p95: ~6.94 ms
- frame p99: ~9.52 ms
- checkpoint worker: ~1.95 s
- archived journal reads during region reload: 0

Your desktop result is the relevant gameplay measurement.

## Larger pre-edit batch

```powershell
& $godot --path C:\Dev\sandbox-sim-dev\game -- --preedit-count=2000
```

Then press **F5**.

The argument sets the batch size; it does not inject automatically.

You can repeat with another count after the previous terrain staging has completed. Automatic checkpointing occurs when the live tail reaches 128 operations.

## Input file

Create, for example, `C:\Dev\sandbox-sim-dev\test-edits.json`:

```json
{
  "operations": [
    {"mode": "CARVE", "center": [15.5, 2.0, 7.0], "radius": 0.8},
    {"mode": "FILL", "center": [16.2, 2.1, 7.2], "radius": 0.7},
    {"mode": "CARVE", "center": [16.0, 1.4, 6.4], "radius": 1.0}
  ]
}
```

Launch:

```powershell
& $godot --path C:\Dev\sandbox-sim-dev\game -- --preedit-path="C:\Dev\sandbox-sim-dev\test-edits.json"
```

Press **F5** to inject the file.

## Other controls relevant to this test

- WASD / arrows: move focus
- right-drag: orbit camera
- mouse wheel: zoom
- left click: carve
- Shift+left click: fill
- L: toggle LOD
- P: request async materialized checkpoint
- O: coherently reload latest committed materialized generation
- F5: inject pre-edit fixture/file

Focused reset `X` is intentionally unavailable for already-materialized history in this candidate because durable reset/tombstone semantics are a separate transaction design.

## Known scope boundary

The shared-surface runtime currently owns X-region boundaries. Do not interpret this build as final proof for Z-region seams or four-region X/Z corners. Those remain a subsequent geometry-ownership gate.
