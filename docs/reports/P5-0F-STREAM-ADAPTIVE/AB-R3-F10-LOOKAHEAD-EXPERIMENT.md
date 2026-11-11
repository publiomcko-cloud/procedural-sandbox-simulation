# P5.0F streaming R3 — F10 movement-matched predictive terrain staging

Date: 2026-11-11. Status: **EXPERIMENT IMPLEMENTED; QUALIFICATION AND OWNER GUI BENCHMARK PENDING**. Owner wishes to retain the best-performing R2 profile (`adaptive-skip`) but achieve visual terrain streaming that can keep pace with the F10 free-exploration camera, including Ctrl-boosted travel. **R3 is a separate opt-in profile, not a silent promotion or a production guarantee.** Parent GitHub draft PR #281 remains **DO NOT MERGE**. The accepted P5.0F coastal water repair in PR #280 and authoritative P4/P5 simulation state are unchanged.

## 1. Why another bottleneck is expected

Code facts: `terrain_demo.gd` sets F10 `FREE_EXPLORE_SPEED = 18.0` m/s and Ctrl multiplier `3.0` (54m/s). Each terrain region is **16×12 meters** and has **16 chunk coordinates**. The requested visual window is 3×3 regions; the retained region window is 5×5 (MAX_ACTIVE_REGIONS=25). Terrain/object source requirements have radius **2** per target region; thus the protected source footprint of the 5×5 window is 9×9 (max 81 source scopes). A current 3×3 visible window needs a 7×7 source footprint. The existing R2 mesh stage selector requests only the current 3×3 and does not start terrain jobs for the next region until focus changes. Its `adaptive-skip` allows up to 2 mesh snapshots/frame under headroom, 8 worker jobs in flight, 4 GPU uploads/frame and a 3.5ms snapshot/upload soft budget; it cannot produce 16-chunk detailed regions instantaneously.

The owner's valid R2 short trials (2026-11-11 13:20) showed `adaptive-skip` was best among measured modes: 135 real bypass attempts, 33 actual dispatch-after-skip, matched 21-region average ~2,590ms vs baseline 2,725ms, unpaired median ~1,495ms vs baseline ~1,754ms, frames >20ms 2.01% vs baseline 6.09%. These short sequential trials and unequal routes do **not** prove a stable causal gain. See `AB-R2-VALID-RESULTS.md`. At 54m/s, camera covers **81m in 1.5s**; a single 12m region takes only ~0.22s to traverse. Targeting boost-speed visual continuity will likely ultimately require a coarser proxy/LOD-first publication or a wider predictive architecture; that major change is **not** authorized by R3.

## 2. What the isolated R3 code does

New profile `adaptive-skip-lookahead` combines all R2 protections and the following only when **F10 is enabled and camera actually moves**:

1. **Predict ahead 0.75s**, capped independently at ±2 region coordinates from the current focus. Does not use approximate frame times if the camera did not move. The camera's actual current-frame world displacement is measured before projection.
2. **Protect immediate effects first.** `TerrainStreamLookaheadPolicy.ordered_queue` reorders only **already queued**, still-required terrain-object source regions. Urgent missing-effect prerequisites from actively waiting mesh stages retain their existing FIFO priority. No new source scopes, extra generation/projection workers, increased source residency, edits to caches, or changed global authority. Current source footprint ranks before ahead-only footprint; tie breaks are deterministic. `TerrainObjectEffectRuntime.prioritize_prefetch_for_motion` only reorders when focus/ahead pair changes and emits `effect_motion_prefetch_priority`.
3. **Speculatively initiate up to 6 forward terrain load stages** at distance 2: a 3-region strip on the forward X boundary plus one on Z for diagonal movement. They are always contained by the existing terrain 5×5 retained window and by the existing 9×9 object-source protected set. Normal region stage selector keeps current visible 3×3 as higher priority by distance. Do not skip or reprioritize edit/partial/full transaction work, commit gates, terrain effects, LOD seam authority or P5 water. When motion turns and a speculative stage is no longer requested, original residency logic can discard stale work. Nothing changes for non-F10 or `baseline`, `adaptive`, `adaptive-skip` modes.
4. **Record F10-specific visible lag**, not just total region load duration: `terrain_stream_budget_window` now includes `f10_movement_frames`, `f10_focus_missing_frames`, `f10_missing_regions_in_window_total`, `f10_peak_speed_mps`, `f10_distance_m`, `f10_predictive_stages_started`, alongside frame >20/33ms, skipped regions, worker queue and GPU timings. F10 counters accrue only on frames where the free camera is actually moving. The existing region scope `terrain_window_reconcile` trace includes predictive targets/stage totals.

New files:
- `game/scripts/terrain/terrain_stream_lookahead_policy.gd`: pure horizon clamping, bounded forward strip, deterministic queue ordering and urgent FIFO preservation.
- `game/tests/p5_0f_stream_lookahead_tests.gd`: source-set stability, no duplicates, urgent-priority invariant, lead cap and 5×5 stage confinement.

Edited files:
- `game/scripts/terrain/terrain_object_effect_runtime.gd`: explicit urgent-tags for existing pending-effect queue entries and isolated F10 reordering API; no persistence/authority changes.
- `game/scripts/terrain/terrain_demo.gd`: one opt-in F10 motion prediction, ahead stage strip union with desired window, same hard bounds, F10 lag telemetry; the previously selected `adaptive-skip` profile is still available and unchanged.
- `game/scripts/terrain/terrain_stream_budget_policy.gd`, `terrain_stream_dispatch_selector.gd`, `game/tests/p5_0f_stream_budget_tests.gd`: fourth profile selection/guard regression, with identical skip limits.
- `scripts/ci/run-p5-0f-qualification.ps1`: added headless lookahead test to P5.0F inherited gate.
- `scripts/perf/run-p5-stream-profile.ps1`: four-profile instrumentation and `.metrics.json` F10 lag metrics, authoritative runtime-profile check, engine/import/trace file metadata.

## 3. Acceptance / controls

**Functional:** Exact-head Windows Godot 4.7.2 import, `P5_0F_STREAM_BUDGET_PASS`, `P5_0F_STREAM_LOOKAHEAD_PASS`, `P5_0F_ENVIRONMENT_VISUALS_PASS`, P5.0A–E/P4 inherited CI and R5.2/R5.3 owner visual scene remain valid. Do not relax or ignore inherited performance thresholds. The R2 exact tested SHA `0661e1b9` had a P5.0D cumulative P4.0H `terrain_window_reconcile` p99 **30.524ms >25ms**, even though standalone P4.0H passed. This must still be resolved; no green cumulative claim is warranted from passing a new focused test alone.

**Performance:** Benchmark `adaptive-skip` (preserved preferred control) against `adaptive-skip-lookahead` on the **same route and exact branch HEAD**, with F10 walking 18m/s and then Ctrl boost 54m/s. Use 60–90 seconds moving continuously for each, repeat reverse order where practical. Start from the same position/seed, avoid saves and terrain/object edits. Compare:
- `f10_focus_missing_pct` (lower is better, most direct user objective).
- `f10_missing_regions_per_frame` and `f10_predictive_stages_started` (lower gaps and nonzero staging, provided the route actually moves).
- Match region IDs for latencies, P50/P95 and initial 3×3 time.
- FPS frame >20ms / >33ms percentages; reject if >20ms rate increases ≥1 absolute percentage point, if F10 movement has observable stutter or water/terrain seams, or CI gates regress.
- Number of wasted speculative stages, source-reorder events, and effect prefetch worker saturation; a higher raw number of jobs is NOT a performance win.

R3 **must not** be promoted merely because first trials appear faster: the predictive strip could increase CPU/backlog and worsen focus readiness, so it is deliberately optional.

## 4. Owner Windows commands (auto performance tracing and saved logs)

```powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin exp/p5-0f-adaptive-stream-budget
git switch exp/p5-0f-adaptive-stream-budget
git pull --ff-only origin exp/p5-0f-adaptive-stream-budget
git rev-parse HEAD

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\perf\run-p5-stream-profile.ps1 -Profile adaptive-skip

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\perf\run-p5-stream-profile.ps1 -Profile adaptive-skip-lookahead
```

Press F10 and move the same route (normal WASD and then Ctrl+W) in both GUI sessions; close Godot after recording. Each runner automatically enables `SANDBOX_PERF_TRACE=1` and min threshold 2ms, runs headless policy tests, verifies actual runtime profile, writes console+commit/time, `.events.txt`, and `.metrics.json` into `C:\Dev\p5-0f-evidence`. If the trace has zero F10 movement frames, that session **is not** a valid F10 performance comparison. Upload both **full logs and metrics JSON**.

## 5. Next architectural phase if R3 is not enough

F10 at 54m/s can outpace the expensive complete 16-chunk region/derived-object/hydrology chain even with accurate prediction. Evaluate **region coarse-first visual proxy**, then revision-matched detailed/LOD0/1 terrain replacement **without any visible blank frame or topology cracks**, under existing SDF authority and deterministic mod-first effects. Such an architecture requires a separate RFC, perf evidence, shared-seam/collision/raycast tests, and the rule that the old GPU mesh remains until replacement is ready. Do NOT quietly implement it as part of R3.

Current verdict: **R3 implementation published on draft PR #281; owner F10 benchmark and exact-head CI not yet qualified**. New agents should read `docs/checkpoints/P5-0F-STREAM-R2-CONTEXT.md` and this document for exact steps, then verify GitHub current HEAD before work.
