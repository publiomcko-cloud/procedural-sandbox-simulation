# P5.0F streaming throughput experiment — adaptive frame budget (isolated)

Status: **EXPERIMENT / NOT QUALIFIED / NOT MERGED**. Derived from R5.3 `a818b65b5f7b8ac2d8b1b93f21dc63d8d8cd9e3f`. No edits to authoritative terrain, hydrology, simulation or persistence are authorized by this experiment.

## Evidence and bottleneck hypothesis

Owner reports normal but improvable chunk load time and requests throughput increases without visible lag. From owner `P5-R5.3-verify-20261111-095128.log` (performance tracing enabled, on GTX 1050 Ti):

- 1,013 terrain mesh snapshots: 2.474ms median, 4.073ms P95, 7.124ms max; queue wait 755ms median and 3,315ms P95.
- 2,221 completed mesh jobs: 140ms median worker execution, 472ms P95; GPU upload only 0.249ms median, 0.335ms P95.
- 175 process spikes with process work over 16ms (median 19.8ms in those spikes; up to 41.67ms).
- Main pipeline hard limits: **1** mesh job snapshot dispatch/frame, **8** mesh jobs in flight, **4** uploads/frame with **3.5ms** upload budget, **1** surface-cache dispatch/frame with 2 jobs in flight, **1** effect projection publication/step, and **1** water remesh/frame.

The primary tested lever is per-frame *snapshot dispatch*, not worker concurrency or GPU uploads. These counts identify opportunities but do NOT establish measurable improvement in advance.

## Experiment, safety and controlled comparisons

The new `TerrainStreamBudgetPolicy` is opt-in via `SANDBOX_STREAM_PROFILE=adaptive` or `--stream-profile=adaptive`. No flag and `baseline` preserve 1 mesh dispatch/frame. Adaptive starts at baseline and permits **2** dispatches/frame only after 12 frames at <=17.2ms frame delta and <=10.5ms prior process work. Any >=20ms frame or >=14ms previous process work immediately restores 1 dispatch and starts a 45-frame cooldown. The existing snapshot soft budget of 3.5ms, max 8 in-flight jobs, and all GPU upload and surface-cache limits remain unchanged. The policy is frame-load heuristic, not a guaranteed 60FPS contract; a heavy individual snapshot can still cause a spike.

With PERF_TRACE enabled, `terrain_stream_profile`, `terrain_stream_budget_transition`, and one `terrain_stream_budget_window` per second record profile, promotion/rollback, frame mean/peak, counts over 20ms and 33ms, process-work mean/peak, number of snapshots and uploads, stages' accumulated main-thread work and pending background queues. This is purposefully low-frequency to avoid self-inflicted trace load. `terrain_process_spike`, `terrain_mesh_snapshot`, `terrain_mesh_job_complete`, `effect_prefetch_tick`, `environment_surface_cache_job` remain available for attribution.

The script `scripts/perf/run-p5-stream-profile.ps1` runs deterministic policy tests and a GUI session in the selected profile, and saves full logs, filtered events and derived `.metrics.json` with baseline/adaptive comparisons in `C:\Dev\p5-0f-evidence`.

### A/B protocol on the owner's PC

1. Update and checkout **`exp/p5-0f-adaptive-stream-budget`**, not the qualified R5.3 branch. Confirm exact HEAD before every comparison.
2. Run `./scripts/perf/run-p5-stream-profile.ps1 -Profile baseline`. Travel a repeatable route across several adjacent ocean/land regions for ~90 seconds. Do not edit or save the world; close normally.
3. Run the identical route with `./scripts/perf/run-p5-stream-profile.ps1 -Profile adaptive`, same conditions.
4. Compare the emitted `.metrics.json` normalized by 100 frames, and the full log for stages, worker queue wait, terrain publication, water publication and anomalies. Upload **both** logs and metrics. Also note any visible hitch.
5. **Candidate acceptance** (not automatic): higher throughput or shorter measured region wait without material increase in frames >20ms or >33ms, no visual hitch, no new water/terrain seam bug, all focused/P4/P5 regression gates green. A >=1 percentage point increase in frames >20ms or any reproducible visible stutter triggers rollback to baseline / lower boost ceiling for investigation.
6. If a speedup is measured and accepted, move the guarded policy into the main P5.0F branch via review; otherwise keep baseline. Never merge this experimental branch to main independent of P5.0F qualification.

## Regression gates

- `res://tests/p5_0f_stream_budget_tests.gd` verifies baseline immutability, stable promotion, frame-spike rollback, cooldown, recovery and explicit reset.
- The experimental P5.0F qualification runner includes the new test and inherited P5/P4 suites; this branch needs an independent CI result before promotion.
- Cross-region ocean classification and retain-then-swap behavior are intentionally unchanged.

Outstanding: comparative owner A/B telemetry and a completed exact-HEAD GitHub runner qualification. This experiment does not claim that the terrain streaming rate is optimized or that other stage bottlenecks have been fixed merely because they are instrumented.
