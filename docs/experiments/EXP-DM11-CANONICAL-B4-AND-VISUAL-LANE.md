# DM11 — Canonical B4 hotpath + independent visual lane

**Project:** Procedural Sandbox Simulation. **Base:** DM9 experimentally qualified `exp/dm9-canonical-prefetch-gaps`. **Branches:** `exp/dm11-canonical-b4-and-visual-lane` (initial conservative hotpath); `exp/dm11-prepared-sdf-snapshots` (further snapshot optimization). **Main:** untouched. Both changes opt-in, not default.

## Hypothesis and actual interventions

DM9 accelerated the visual-only outer B4 HIGH region to approximately 130ms, revealing that CPU-intensive canonical 16-chunk `generate_chunk` and its snapshot evaluation can monopolize the Godot worker pool while moving. A derived visual-only worker lane can avoid the canonical **shared queue** but not the physical CPU contention.

1. `SANDBOX_DM11_CANONICAL_FAST_B4=1` in `terrain_mesh_job.gd` routes B4 canonical worker generation to a fast variant. Uniform cells are rejected by inspecting eight Q8.8 node signs without allocating an 8-element float array, and owned-edge Surface Nets traversal uses local packed-array strides without creating corner arrays or Vector3i objects. Mixed cell reconstruction, normalized surface normals, winding, topology, revision tagged snapshots, collision and save paths retain exact math and ownership.
2. **DM11 initial conservative variant:** caches base SDF XZ values for pristine canonical chunks only; edited/materialized/effect/cave chunks call the original `sample_density_snapshot`. All chunks use the exact fast Surface Nets geometry.
3. **DM11 prepared snapshot variant:** for valid immutable snapshots, hoists centers/radii/modes, materialized tiles/index and anchored effect frames **once per chunk**. Per-XZ SDF trigonometry is cached across Y, and `BrushState.sample_density_snapshot_from_base` composes in the same original order: materialized override → ordered CARVE/FILL brush operations → anchored-object effects → cave clip. Invalid typed/shape snapshots fall back to the original evaluator. No snapshot or authoritative state is mutated.
4. `SANDBOX_DM11_VISUAL_LANE=1` launches visual-only B4 jobs as bounded `Thread.PRIORITY_LOW` native threads, instead of placing them into the canonical `WorkerThreadPool`. Existing adaptive 1-moving/4-idle visual job budget applies. Per-task records track native Thread handles and virtual negative task IDs; result is consumed on main thread after `is_alive() == false` and `wait_to_finish()`. `_exit_tree` joins both native and legacy pool tasks to prevent dangling workers.
5. Instrumentation: `terrain_mesh_job_complete` includes actual canonical SDF sampling, cell reconstruction, meshing timings, Q8.8 uniform-cell counts and pristine/prepared-cache usage. `dm9_visual_shell_complete` logs visual lane type `native_low` or `worker_pool`, and its actual thread caller ID. The deterministic benchmark aggregates p50/p95, CPU/RSS and main thread frame spikes.

## Exact parity (Windows Godot 4.7.2)

Tests `dm11_canonical_b4_parity.gd`, `dm2_b4_chunk_contract.gd`, and DM9 pristine visual oracle run before integrated trials.

Thirty exact cases: six region/chunk combinations across pristine, cave-section, ordered CARVE+FILL brush, brush+validated object effect frame, and brush+materialized density tile. Each compares complete Q8.8 nodes, active cells, cached cell vertices, all mesh positions/normals, skipped faces and sample sites **by exact array equality**.

**Initial conservative candidate, run 43420460123:** 374/374 parity assertions, zero failures; aggregate 30-case baseline 1373.675 ms vs fast 802.584 ms = **1.71×** faster.

**Prepared snapshot candidate, run 43421101767:** 374/374 parity assertions, zero failures; aggregate 30-case baseline 1386.284 ms vs fast 604.290 ms = **2.29×** faster. Individual combined generation/mesh totals (baseline→fast, six cases each): pristine 227.2→43.7ms, cave 224.6→79.0ms, brush 276.5→98.8ms, brush+effect 318.9→181.0ms, brush+materialized tile 339.1→201.9ms. This verifies preservation of edited/effected materialized field, not merely pristine appearance. Isolated and sequential microbench measurements do not guarantee equivalent end-to-end load.

## Initial integrated 2×2 A/B (run 43420460123)

Same seed 424242, original DM9 fast visual B4 enabled, adaptive maximum four visual workers, no speculative prefetch, 720 frames of 18m/s out-and-back, isolated user storage. Two baseline vs both-optimized repeats:

| Metric | DM9 fast baseline (2 runs mean) | Initial DM11 canonical + native visual lane (2 runs mean) |
|---|---:|---:|
| Canonical 3x3 focus missing | 63.47% | **27.71%** |
| Canonical region latency p95 (mean of per-run p95) | 2750.9 ms | **1669.5 ms** |
| Outer visual HIGH jobs completed | 50.5 | **73.5** |
| Frames over 33 ms | 2.982% | **4.716%** |
| Mean headless frame time | 17.858 ms | 18.345 ms |

Canonical only (first run) also achieved focus missing **31.53%**, region p95 **1734ms**, and **74** outer HIGH completions. Native visual lane *alone* regressed canonical focus missing to **81.39%**. Therefore **do not attribute the canonical improvement to native threads alone** or turn that lane on without faster canonical work.

Idle test baseline initial full HIGH fill 15.837s, canonical+native 13.883s, but no duplicated idle pair yet. Both completed 268 outer visual HIGH regions with zero final outer gaps. The native lane eliminates visual scheduling queue delay but still consumes CPU; frame spikes increase as more canonical regions are published. Low-priority threads are not physical CPU isolation.

**Initial run result:** parity PASS, factorial A/B PASS, real Windows GUI GPU smoke PASS. **Prepared snapshot integrated qualification:** pending benchmark and GPU; see [workflow run 43421101767](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43421101767). Do not merge to main or enable by default based solely on microbench parity.

## Candidate command after qualification

```powershell
$env:SANDBOX_TERRAIN_BACKEND = 'b4'
$env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
$env:SANDBOX_DM9_FAST_B4 = '1'
$env:SANDBOX_DM9_PREFETCH = '0'
$env:SANDBOX_DM9_VISUAL_ADAPTIVE = '1'
$env:SANDBOX_DM9_VISUAL_WORKERS = '4'
$env:SANDBOX_DM11_CANONICAL_FAST_B4 = '1'
$env:SANDBOX_DM11_VISUAL_LANE = '1'
$env:SANDBOX_PERF_TRACE = '1'
```

A separate safe comparison can disable `SANDBOX_DM11_VISUAL_LANE` without disabling canonical acceleration. The next bottleneck may be main-thread region publication, effect dependency projection, and progressive mesh presentation. The average `mesh_dispatch_and_upload` stage was around 3.2–3.5ms/frame in the initial headless movement trace; targeted per-frame tail tracing is needed before altering publication caps.

## DM11 final candidate — canonical-only fast path

**Chosen candidate:** `SANDBOX_DM11_CANONICAL_FAST_B4=1`, `SANDBOX_DM11_VISUAL_LANE=0`. The shared visual worker pool remains in place, with the DM9 fast B4 visual path and adaptive budget. Native threads are retained as a tested *opt-in* experimental alternate, not enabled by default: the prepared-snapshot factorial test showed no compelling core/visual or frame-tail advantage of native threads.

**Prepared snapshot run 43421101767: exact parity 374/374 PASS, factorial 5-trial PASS, interactive Windows GTX 1050 Ti GPU PASS.** In the 720-frame 18m/s motion comparison, baseline vs canonical-only fast: canonical focus missing **76.806%→26.389%**, canonical region p95 **2107ms→1566ms**, HIGH exterior visual publications **46→80**, and frame spikes >33ms **3.190%→3.051%**. The native-lane combined candidate achieved 25.972% focus missing, 1612ms canonical p95, 75 exterior regions and 3.883% slow frames, less attractive overall. This was one trial per arm in that workflow.

**Additional replicated A/B and GPU qualification is running on workflow 43421950396**: <https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43421950396>. Six trials (A/B motion repeated twice and A/B idle) with canonical-only fast, and real GUI/GPU smoke. This isolates the candidate from native-lane scheduling effects.

**Local command after final qualification:**
```powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin
git switch exp/dm11-canonical-fast-qualification
git pull --ff-only origin exp/dm11-canonical-fast-qualification
$env:SANDBOX_TERRAIN_BACKEND = "b4"
$env:SANDBOX_STREAM_PROFILE = "adaptive-skip-progressive"
$env:SANDBOX_DM9_FAST_B4 = "1"
$env:SANDBOX_DM9_PREFETCH = "0"
$env:SANDBOX_DM9_VISUAL_ADAPTIVE = "1"
$env:SANDBOX_DM9_VISUAL_WORKERS = "4"
$env:SANDBOX_DM11_CANONICAL_FAST_B4 = "1"
$env:SANDBOX_DM11_VISUAL_LANE = "0"
$env:SANDBOX_PERF_TRACE = "1"
& "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --path .\game
```

**Fail-safe:** set `SANDBOX_DM11_CANONICAL_FAST_B4=0`; original canonical snapshot and geometry code remains accessible unchanged. `main` is untouched. Do not merge to main until visual/edited local QA and repeated A/B are accepted.

## Final candidate qualification — DM11 canonical fast, shared visual pool

**Workflow 43421950396:** exact canonical/DM2/DM9 mesh contracts PASS, six-trial same-seed A/B PASS, Windows interactive GTX 1050 Ti GPU smoke PASS. This tested `SANDBOX_DM11_CANONICAL_FAST_B4=1` with `SANDBOX_DM11_VISUAL_LANE=0`. It is the candidate recommended for **local visual QA**, but NOT a main merge or default rollout.

The final repeated A/B (two new 18m/s runs each arm) reported:
- Missing canonical 3×3 focus **69.375% baseline → 31.458% fast**.
- Canonical region p95 **2471.97ms → 1698.16ms** (mean of per-run p95).
- Visual HIGH exterior regions completed **47 → 72**, approximately **53% more**.
- Frames >33ms **2.774% → 3.260%**, a small but measurable frame-tail regression in this specific pair, so no claim of smoother frame times.
- Idle full 277-region HIGH coverage **15.998s → 14.607s**, with all 268 exterior regions completed, 0 gaps; idle CPU avg **4.36% → 3.30%**.

Across the one prepared-snapshot factorial A/B in workflow 43421101767 plus two new repeated pairs in 43421950396 (three matching headless motion trials per arm, not an independent statistical performance guarantee):
| Metric, mean across runs | Original canonical | Prepared canonical fast, shared visual pool |
|---|---:|---:|
| Missing canonical focus | 71.852% | **29.768%** |
| Canonical region p95 | 2350.4ms | **1654.0ms** |
| Visual HIGH exterior regions completed | 46.7 | **74.7** |
| Frames >33ms | 2.913% | **3.190%** |

**Decision:** `DM11_CANONICAL_FAST_VISUAL_QA_CANDIDATE`: major consistent improvement in canonical and visual region throughput, verified exact edited/effected/materialized/cave geometry and real GPU smoke, but an average +0.277 percentage-point regression in >33ms frames. Retain default `SANDBOX_DM11_CANONICAL_FAST_B4=0` until a local user-run visual test accepts it. Native visual `Thread.PRIORITY_LOW` lane stays `0` (experiment functional but not overall superior). Future work: instrument the exact source of main-thread frame spikes and optimize region/chunk publication pacing without starving canonical stages.

The code is entirely opt-in; no authoritative layout, cache key, ledger revision, save format, mod-first content, B4 sample step, radial HIGH distance, or object geometry was changed.
