# P5.0F Stream A/B R2 — bounded head-of-line bypass for pending effect snapshots

Status: **IMPLEMENTED ON EXPERIMENTAL BRANCH — CI AND OWNER A/B NOT YET QUALIFIED.** Date: 2026-11-11. Base: `exp/p5-0f-adaptive-stream-budget`, PR #281. Do not merge into `feat/p5-0f-environment-visuals` or `main` without qualification and measured benefit. The sea coast R5.3 is the already owner-tested visual baseline; this experiment must not modify it.

## Why R2 exists (data, not assumption)

R1 experiment is documented in `AB-R1-RESULTS.md` and was **INCONCLUSIVE_FOR_THROUGHPUT**. Same commit `aa3ede689`:
- Baseline 25.6s/30 published regions; adaptive 26.8s/33 published regions; routes diverged after initial nine regions.
- Median terrain snapshot 2.6ms; median mesh worker 145ms; median GPU upload 0.25ms; large queue waits 1.4–1.9s.
- Adaptive unlocked 2 dispatches during 364 frames, but actually sent a second job during only **seven** frames. Increasing worker/upload limits or maximum dispatch to 3 is not evidence-backed.
- The dispatcher short-circuits `_dispatch_mesh_jobs()` whenever `_prepare_terrain_effect_snapshot(...)` reports `pending=true`, even when a later load region might be ready. Whether this causes measurable delay remains an **experimental hypothesis**.

## R2 design / invariants

New **opt-in third mode** `adaptive-skip`. Modes `baseline` and `adaptive` retain the previous stop-on-pending behavior and worker/queue caps. `adaptive-skip` shares R1's 1/2 frame-safe dispatch budget but may move to a different candidate only when:
1. The currently selected stage has purpose **`load`** and its terrain/object effect snapshot reports `pending=true`. Edit transactions, LOD partial and full rebuild stages MUST NOT be skipped; failures other than pending follow unchanged error/retry semantics.
2. No spike/cooldown: last frame below 20ms, previous main-thread work below 14ms, stream-policy state is neither `frame_spike` nor `cooldown`.
3. Fewer than **3 unique blocked load regions** have been skipped within the current invocation; total time since the start of this dispatch invocation remains below existing **3,500 µs** snapshot soft budget. A costly initial attempt may exceed the soft cap (work already done cannot be preempted) but MUST NOT initiate further attempts in that frame.
4. Shared max 8 mesh jobs in flight, max 4 uploads and 3,500µs upload budget, source checks and bounded region residency all remain unchanged. No parallelism or GPU-upload increase.

On pending, the region ID is placed in an **invocation-local exclusion map**. The pure selector `TerrainStreamDispatchSelector.next` applies the original stage priority `edit_transaction > partial > full > load`, distance and deterministic coordinate tie-breaker, while selecting a different nonexcluded region. The skipped stage's `submit_index`, `pending_count`, token, canonical SDF, persistence and worker state remain unchanged; it can retry on the next frame. Each successful submit increments only its selected region's original `submit_index`. If all remaining candidates are blocked, or a cap is reached, exit for that frame.

**No retry spin / no starvation by design:** at most three skips per dispatch invocation and one time window; exclusions are local to a frame, so blocked priority stages retry as normal next frame. Repeated permanent effect pendency remains a separate prefetch-health issue and is surfaced in diagnostics. A staging failure is not converted into a successful publish.

## Files touched in R2

- `game/scripts/terrain/terrain_stream_dispatch_selector.gd`: pure deterministic next-ready selector, load-only skip permission and caps.
- `game/scripts/terrain/terrain_demo.gd`: `adaptive-skip` argument/env support; bounded skip on all four pending-effect branches (regular chunk, X-boundary, Z-boundary, corner). Existing edit/checkpoint/mesh-publish code unchanged.
- `game/tests/p5_0f_stream_budget_tests.gd`: priority, exclusion, within-region order, retry next frame, malformed/blocked conditions, cap/cooldown and legacy policy.
- `scripts/perf/run-p5-stream-profile.ps1`: allows `-Profile adaptive-skip`; reports per-second dispatch-blocker histograms, skip count, successful dispatch after skip and time budget exhaustion.
- Existing `scripts/ci/run-p5-0f-qualification.ps1` already invokes the stream-policy headless tests, then cumulative P5/P4 chain.

## Instrumentation

With `SANDBOX_PERF_TRACE=1`, each `terrain_stream_budget_window` (aggregated about once/sec) reports:
- `mesh_dispatch_blockers`: counts split into `effect_pending_chunk`, `effect_pending_x_boundary`, `effect_pending_z_boundary`, `effect_pending_corner`, `effect_skip_not_allowed_or_budget`, `worker_capacity`, `dispatch_cap`, `snapshot_time_budget`, `no_eligible_stage` and `no_eligible_stage_after_skips`.
- `effect_pending_load_skips`: attempted exclusions of blocked load regions; `successful_dispatch_after_skip`: at least one actual next-ready mesh dispatch following an exclusion; `skip_time_budget_exhausted`: frame exits after spending the snapshot time budget on pending/skipped work.
- Existing `frames_over_20_ms`, `frames_over_33_ms`, `process_frames_over_16_ms`, `mesh_dispatches`, `mesh_uploads`, `effect_prefetch_pending`, `stage_work_usec`, `terrain_region_load_complete` remain comparable.

Full logs and normalized `.metrics.json` come from `scripts/perf/run-p5-stream-profile.ps1`, which strips native PowerShell interleaved NULs before parsing embedded JSON. A/B metrics measure observed implementation behavior; a larger `effect_pending_load_skips` alone is NOT a performance win.

## Local Windows reproduction, same machine, same seed and branch

```powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin exp/p5-0f-adaptive-stream-budget
git switch exp/p5-0f-adaptive-stream-budget
git pull --ff-only origin exp/p5-0f-adaptive-stream-budget

$godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --editor --path .\game --import
& $godot --headless --path .\game --script res://tests/p5_0f_stream_budget_tests.gd

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\perf\run-p5-stream-profile.ps1 -Profile baseline
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\perf\run-p5-stream-profile.ps1 -Profile adaptive
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\perf\run-p5-stream-profile.ps1 -Profile adaptive-skip
```

For each GUI run, follow approximately the same route, traveling through and revisiting the same 3×3 loaded window for ~90s without saving/editing. Repeat in reversed order if time allows to reduce warmed-cache bias. Capture full `P5-stream-{profile}-*.log`, `.metrics.json`, visually observed hitches, and exact Git commit. The script sets PERF_TRACE and the profile itself.

## Qualification and stop conditions

1. Verify `P5_0F_STREAM_BUDGET_PASS` and full P5.0F focused and P5.0A–E / P4 CI success on the **exact experimental HEAD**, not merely ancestor commits; Windows self-hosted runner is the authoritative Godot 4.7.2 environment.
2. In logs, confirm `terrain_stream_profile` has the correct profile and `adaptive-skip` yields nonzero `successful_dispatch_after_skip` **only if** effect blockers actually occur. Zero recoveries may mean there are no simultaneously ready regions, not a logic defect.
3. Compare *matched-region* load p50/p95 and stage queue waits. Do not compare unpaired total region count or raw dispatched jobs across different routes.
4. Reject if frames over 20ms increase by ≥1 absolute percentage point versus baseline, if frames over 33ms rise markedly, if visual hitches/black chunks/repeated stale water occur, or if any P4/P5 regression fails.
5. If gain is absent despite recovery, retain baseline and investigate effect prefetch itself. If gain is repeatable with acceptable frame stability, consider a reviewed promotion into the P5.0F branch (never merge experimental PR #281 into main directly).

The current code is **an experiment, not an approved performance improvement**. No new screenshot or owner A/B R2 log has been received. The original hydrology infinite-reservoir classification caveat remains outside this experiment.
