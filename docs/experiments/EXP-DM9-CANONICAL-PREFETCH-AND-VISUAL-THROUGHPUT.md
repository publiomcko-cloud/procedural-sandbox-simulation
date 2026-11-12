# DM9 — canonical prefetch + CPU visual throughput / gap attribution

Status: **experimental, CI pending**. Derived from qualified DM8 commit `10bc0d717c386657f42aed94bb45044241645bce`. No merge into `main`.

## Problem

DM8 observed **p95 canonical region load ~3.07 s** at 18m/s, despite full stationary HIGH terrain eventually reaching 277 regions. The B4 visual halo is a separate path: `_dm3_process_shells` formerly ran only one independent CPU visual job at a time, with one main-thread mesh publication/frame. The user's reported ~50% processor occupancy when exploring and ~20% after nearby publication is not by itself evidence of spare *core-local* capacity; measure CPU, job queue/run and frame budgets before selecting concurrency.

## Changes (opt-in, independently comparable)

1. `SANDBOX_DM9_PREFETCH=1`: predict up to 3.1s along actual normal F10 motion (18m/s); only stage at most six perimeter regions within existing retained 5×5. Overlong horizons are clamped to the existing radius two; **do not extend authoritative state or 9×9 terrain-effect source projection**. Preparation is full 16-chunk B4 but commits neither terrain nor objects, collisions, simulation, progressive preview, or saves until it enters the visible core 3×3. Seed/brush edit revision/object-effect revision/cave-mode and LOD validity must still match at promotion; stale work is discarded/restarted. Boosted F10 54m/s is excluded. World/rebuild/edit transactions retain priority. This is bounded *preparation*, not a proven physical 55m canonical prefetch: existing footprint caps directional reach.
2. `SANDBOX_DM9_VISUAL_WORKERS=4`: allow up to four **independent visual-only** B4 jobs (1 by default), but retain a maximum of one main-thread visual HIGH upload/frame, the existing radial queue, distance gates, seed/world checks, and TTL. The independent visual path is pristine/immutable and not SDF authority. Test rather than assume speedup or frame stability.
3. Passive telemetry `dm9_prefetch_stage` actions (begin,ready,promote,discard,stale), `dm9_visual_shell_complete` (worker queue/run/main thread publication) plus per-second stream fields for inflight, ready, promoted, worker limit, dispatch blockers. The deterministic benchmark optionally captures half-second normalized process CPU percent (percentage of **all logical cores**), process working set, and snapshot/worker/upload p50/p95.

## Validation matrix

Windows Godot 4.7.2 self-hosted runner, same machine/seed/route:

- A: DM8-equivalent flags off, one visual worker
- B: DM9 canonical speculative prefetch on, one visual worker
- C: DM9 canonical speculative prefetch on, four visual workers

Two reversed-order trials per variant (A-B-C-C-B-A), route `outback-18`, 720 frames, pristine isolated APPDATA. Additional idle trial with C to characterize HIGH fill/CPU saturation. Compare focus gaps, visual HIGH gap age/front missing, canonical p50/p95 load latency, worker/snapshot/upload p50/p95, process CPU mean/peak, memory and >20/>33ms frame shares. No F10 54m/s optimization criterion.

## Safety & evaluation

No dynamic or edited geometry equivalence is asserted for derived HIGH; this is DM8's pristine-only contract. Promotion is fail-closed on revision mismatch. Inspect GPU screenshots and local visual transitions before integrating. Increase concurrency only if it improves gap clearance without unacceptable frame spikes/memory. Do not treat headless frame time as rendered GPU FPS.

## Local experimental run

```powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin
git switch exp/dm9-canonical-prefetch-gaps
git pull --ff-only origin exp/dm9-canonical-prefetch-gaps
$godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$env:SANDBOX_TERRAIN_BACKEND='b4'
$env:SANDBOX_STREAM_PROFILE='adaptive-skip-progressive'
$env:SANDBOX_PERF_TRACE='1'
$env:SANDBOX_DM9_PREFETCH='1'
$env:SANDBOX_DM9_VISUAL_WORKERS='4'
& $godot --headless --editor --path .\game --import
& $godot --windowed --rendering-method gl_compatibility --path .\game
```

**Important:** local world/mod isolation is recommended as in DM8; the above block is for a pre-existing experimental worktree only.
