# Developer handoff — P1.0B dynamic region streaming

Status: `READY_FOR_INDEPENDENT_SOURCE_REVIEW_AND_OWNER_GUI`

Ticket / acceptance criteria: P1.0B slice directly authorized by owner on 2026-10-17; bounded camera-focus region streaming and a subtle view-aligned auxiliary light. P1.0C is not in scope.

Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation` / `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`

Worktree / branch: `C:\Dev\sandbox-sim-dev` / `feat/p1-0b-dynamic-region-streaming`

Base SHA: `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0`

Candidate SHA / direct parent / PR: see the exact final commit, its parent, and draft PR recorded in the implementation checkpoint and PR metadata. No merge is authorized.

Changed paths are limited to the P1.0B implementation, tests and handoff/design/status documentation listed by `git diff --name-status` against the base.

## Implementation summary

Camera view focus maps through the existing floor-based spatial owner. The controller requests a radius-1 region window, retains loaded neighbors through radius 2, and bounds resident content at 25 regions / 400 chunks. New regions stage all 16 chunk meshes and publish as one complete region. One mesh is built per process frame. Full C/R/X rebuilds stage the complete current set and publish atomically after all chunk work; focused brush edits stage only affected chunks. Up to 16 edited region states are retained in memory across unload/reload. A low-energy spotlight child of the camera improves forward depth readability while preserving the existing green lit material, ambient light and directional light.

Architectural impact: no change to the SDF/generator, region ownership, chunk grid, spatial coordinate contract or domain-state ownership. No dependency or native addon added. No cross-region edits, persistence, networking, LOD, new collision behavior or background meshing workers.

## Validation

Engine: Godot 4.7.2 stable official `ed1daf0bf`.

Commands:

```powershell
$env:GODOT_BIN = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& .\scripts\validate.ps1
```

Results from the final full local run: import passed; smoke 52/52; SDF 40/40; brush 89/89; chunk 179/179; multiregion/streaming 7,565/7,565; bootstrap 18/18; configured main-scene startup passed. Total: 7,943 assertions, zero failures. The streaming tests report the initial nine-region window at 9 regions / 144 chunks / 87,077 triangles, maximum 1 mesh slice per process frame, a peak resident count of 12 during traversals, and observed loads/unloads of 21/9. Initial headless window completion was 9,964 ms; total mesh work 5,231 ms; peak slice 20.551 ms; peak controller process work 20.676 ms. These are measurements from this local Godot 4.7.2 run, not a frame-time guarantee. `git diff --check` passed. Owner GUI/pixel review is not performed by the headless suite.

## Metrics and limitations

Each frame processes one synchronous two-cell-high vertical mesh slice; the slice itself cannot be interrupted. Its measured 20.551 ms peak (with 20.676 ms peak controller work) exceeds a 16.7 ms frame budget on this machine, so the progressive scheduler bounds work count but does not guarantee 60 FPS or eliminate hitches. The initial 3×3 window took about 10 seconds headlessly; GUI time is machine and frame-rate dependent, while the focused region appears first. Edited state is transient and capped at 16 distinct edited regions. Tests do not claim visual equivalence to a rendered-pixel baseline. No owner GUI/pixel retest has yet occurred.

## Owner visual retest

Follow [P1.0B dynamic-region visual procedure](../design/P1_0B_DYNAMIC_REGION_STREAMING.md#owner-gui-retest). In short, run the terrain scene with F6, wait for the 3×3 window, use D twice and A five times to cross positive and negative region boundaries, then leave/return to observe unload/reload. Confirm continuous seams and preserved edits, controls C/R/X and orbit/zoom, and inspect the terrain under the subtle camera-aligned light. Report HUD queue/resident/timing values and screenshots if a seam or transition defect appears.

## Independent review prompt

> Independently review exact candidate SHA `<candidate>` in PR `<link>` against parent `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0`. Focus on queue cancellation and stale-region publication; 9-region request/radius-2 hysteresis/25-region cap; no more than one chunk mesh build per process frame; complete-region publication and atomic C/R/X rebuild; negative region ownership and actual streamed seam normals/positions; transient edited-state retention and its cap; unchanged global cut and no cross-region edits; spotlight subtlety and preserved lit material; Godot 4.7.2 tests and exact assertion logs. Distinguish headless configuration checks from owner pixel/GUI validation. Do not access F2 protected paths, elevate, operate a VM, merge or release. No P1.0C or persistence approval is implied.
