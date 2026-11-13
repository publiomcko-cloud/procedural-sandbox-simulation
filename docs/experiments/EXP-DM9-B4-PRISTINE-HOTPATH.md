# DM9 — B4 pristine SDF + Surface Nets microprofile and lossless hotpath

**Branch:** `exp/dm9-sdf-surface-nets-hotpath` (isolated from `main`). **Status:** initial exact parity and microbench PASS; integrated A/B/GPU qualification pending. All modifications are opt-in behind `SANDBOX_DM9_FAST_B4=1`, valid only with B4 + `adaptive-skip-progressive`. This intentionally does not alter world seed authority, edit snapshot generation, collision, saves, or mod-first rock geometry.

## Hypothesis and implementation

Before changes, `ExperimentalDiscreteSurfaceNets.generate()` sampled `SdfWorld.sample_density` for each of **21,735 lattice nodes** at step 0.5m. The trigonometric surface and cave terms depend solely on X and Z, yet were reevaluated across every Y plane. Also `_rebuild_cell()` allocated an 8-value `PackedFloat32Array` even for uniform cells that do not produce a surface vertex. There are **19,448** candidate cells in the full region, of which approximately **16,957–17,392** (87–89%) were uniform in the first four representative test cases.

New `generate_pristine_fast` caches double-precision per-XZ `surface_y`, `cave_center_y`, and `world_z - cave_center_z` terms, preserving `roundi(density*256.0)` exactly. Uniform-cell gate reads eight lattice signs directly from the integer lattice and sets the cell inactive; mixed cells invoke the original unmodified `_rebuild_cell` for exact vertex math. Baseline `generate` and all `generate_chunk` (including edited/brush/cave snapshots) remain untouched except passive timing. Canonical edit paths cannot route through this optimization.

The worker trace `dm9_visual_shell_complete` now exports `precompute_usec`, `lattice_usec`, `cell_rebuild_usec`, `uniform_cells_skipped`, `chunk_build_usec`, `chunk_combine_usec`, plus previously available worker queue, run, mesh and main-thread publication durations. These are also aggregated as p50/p95 in the deterministic benchmark.

## Exact parity and microbenchmark (Windows Godot 4.7.2; workflow 43405272170)

`game/tests/experiments/dm9_b4_hotpath_parity_benchmark.gd` ran **281 assertions, 0 failures** over seeds `424242`, `0`, `-16384`, `741` and regions `(0,0)`, `(-7,9)`, `(12,-8)`, `(-1,-1)`. Comparisons are exact on **all Q8.8 density samples**, **cell activity**, **cell vertices**, and **positions, normals, quad counts and validity of all 16 chunks**, not merely visually approximate.

| Region | Baseline generation (ms) | Fast generation (ms) | Baseline lattice (ms) | Fast lattice (ms) | Baseline rebuild (ms) | Fast rebuild (ms) |
|---|---:|---:|---:|---:|---:|---:|
| (0,0) | 215.787 | 74.008 | 44.595 | 6.284 | 171.032 | 66.849 |
| (-7,9) | 220.504 | 62.164 | 53.546 | 5.800 | 166.920 | 55.709 |
| (12,-8) | 229.766 | 63.399 | 45.981 | 5.725 | 183.737 | 56.992 |
| (-1,-1) | 208.501 | 61.797 | 45.327 | 5.752 | 163.132 | 55.380 |
| **Total** | **874.558** | **261.368** | | | | |

Generation speedup in this isolated test: **3.346×**, approximately **70.1% lower generation time**. The **16 chunk surface build** remains ~88–124 ms per region and did not improve in this first change. These are NOT end-to-end game loading times; CPU contention, camera movement, and visual queue pressure require integrated A/B.

## Qualification and decision

The CI pipeline `.github/workflows/dm9-b4-sdf-hotpath.yml` validates exact geometry, compares 3,600-frame stationary and 720-frame outback-18 baseline/optimized tests under identical seed, worker limits, budget and source isolation, tracks CPU/RSS/gap ages/frame spikes, then executes a real interactive Windows GPU smoke. The fast path must not be recommended by default before all lanes pass and comparative throughput/frame outcomes are acceptable.

**Candidate to run locally if qualified:**

```powershell
$env:SANDBOX_TERRAIN_BACKEND = 'b4'
$env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
$env:SANDBOX_DM9_FAST_B4 = '1'
$env:SANDBOX_DM9_PREFETCH = '0'
$env:SANDBOX_DM9_VISUAL_ADAPTIVE = '1'
$env:SANDBOX_DM9_VISUAL_WORKERS = '4'
```

Revert instantly by setting `SANDBOX_DM9_FAST_B4=0`; the original algorithm is untouched and remains the default. Future candidate optimization: reduce `build_chunk` edge/Vector3i allocation overhead, with a separate exact 16-chunk parity gate and A/B run.
