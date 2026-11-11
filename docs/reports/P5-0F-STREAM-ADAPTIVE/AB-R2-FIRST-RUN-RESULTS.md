# P5.0F Streaming R2 — owner A/B/C 2026-11-11, invalid adaptive-skip activation

Status: **R2_PERFORMANCE_COMPARISON_INVALID — PROFILE_ACTIVATION_BUG CONFIRMED AND PATCHED / RETEST REQUIRED**. Do not promote the optimization to P5.0F. Branch remains `exp/p5-0f-adaptive-stream-budget`, draft PR #281.

## Evidence submitted

All three original user GUI runs were on **identical commit** `b56131e66bc83398e5183693b8d736646a7f528d` and pinned Godot 4.7.2, GTX 1050 Ti, seed 424242, PERF_TRACE. The local pure headless tests passed `P5_0F_STREAM_BUDGET_PASS: assertions=173 failures=0` in all three runs, but these tests did not previously exercise the **actual runtime profile parsing**.

Files (names as uploaded, do not assume their availability in another session):
- `P5-stream-baseline-20261111-122250.log`, `.events.txt`, `.metrics.json`
- `P5-stream-adaptive-20261111-122327.log`, `.events.txt`, `.metrics.json`
- `P5-stream-adaptive-skip-20261111-122409.log`, `.events.txt`, `.metrics.json`

The PowerShell report header and `.metrics.json` label for the third run say **adaptive-skip**, but the **in-process Godot `PERF_TRACE terrain_stream_profile` event says `profile:"baseline"`**. This is the decisive finding. In `game/scripts/terrain/terrain_demo.gd::_ready()`, after reading `SANDBOX_STREAM_PROFILE`, the legacy guard `if _stream_profile != "adaptive": _stream_profile = "baseline"` ran **before** the now-three-mode validation, silently remapping `adaptive-skip` to baseline. The CLI was not specified in the runner, so nothing overrode the remap. Thus `effect_pending_load_skips=0`, `successful_dispatch_after_skip=0`, `boosted_frames=0` were expected; NO R2 skip algorithm was exercised. **Do not interpret the apparent smoother R2 session as an optimization effect.**

## Recorded values (as run; not a valid 3-mode causal comparison)

| Metric | baseline | adaptive | requested adaptive-skip, ACTUAL baseline |
|---|---:|---:|---:|
| Window-accounted frames | 1,219 | 1,219 | 1,113 |
| Terrain region load completions | 27 | 27 | 24 |
| Mesh dispatches / uploads | 432 / 432 | 432 / 432 | 384 / 384 |
| Boosted frames | 0 | 235 | 0 |
| Head-of-line skips / success after skip | 0 / 0 | 0 / 0 | 0 / 0 |
| Frame mean (ms) | 17.52 | 17.55 | 17.38 |
| Main process mean (ms) | 4.05 | 3.82 | 3.75 |
| Frames >20ms | 5.91% | 4.59% | 3.50% |
| Frames >33ms | 1.56% | 1.39% | 0.81% |
| Region load p50/p95 (ms, unpaired) | 1,779.57 / 5,897.67 | 1,801.90 / 5,321.98 | 1,657.43 / 5,590.77 |
| Effect pending shared-corner blockers | 233 | 218 | 211 |
| Worker capacity blockers | 278 | 309 | 191 |
| Dispatch cap blockers | 306 | 244 | 297 |

There are **21 matched region IDs** across all three sessions (not the complete same trajectory). Their elapsed load p50 and mean (ms): baseline p50 1,921.12 / mean 2,962.20; adaptive p50 1,801.90 / mean 2,785.63; requested skip-but-baseline p50 1,960.35 / mean 2,920.20. The initial shared 3×3 cohort (9 regions) mean (ms): baseline 4,889.31, adaptive 4,447.71, mislabeled skip 4,767.15. These numbers can describe the runs but **cannot evaluate bypass** because it was disabled. Sequential ordering, warm-cache effects, different session lengths/routes, GPU/CPU load and limited samples also prevent causal conclusions.

## Post-run corrective code and safeguards (not present in uploaded runs)

1. `TerrainStreamBudgetPolicy.resolve_profile(env_value, cli_args)` now explicitly recognizes `baseline`, `adaptive` and `adaptive-skip`, with CLI overriding environment and safe fallback to baseline.
2. `terrain_demo.gd` calls that pure resolver instead of the stale `!= adaptive` gate. `terrain_stream_profile` now includes `requested_profile`, `profile` (effective) and `profile_mismatch`.
3. `p5_0f_stream_budget_tests.gd` adds **10** profile resolution assertions (environment, case, CLI override and invalid values), in addition to the existing 173.
4. `scripts/perf/run-p5-stream-profile.ps1` now **fails closed after the GUI** unless `terrain_stream_profile.profile` exactly matches the requested `-Profile`. Merely printing a requested profile or writing `.metrics.json` is no longer accepted as evidence.

Do not assume the fix is qualified until exact-head CI and/or the owner's pinned Godot verify it. Work only in experimental PR #281.

## Required next steps

1. Verify the latest experimental branch HEAD, exact-HEAD Godot headless + cumulative CI (P5.0F and P4), and keep the draft PR unmerged.
2. Owner runs new **same-head** `baseline`, `adaptive`, `adaptive-skip` profiles, preferably same route with a longer 60–90s movement period and repeated run in inverse order. Use only `scripts/perf/run-p5-stream-profile.ps1` with PERF_TRACE. The script will refuse invalid profile traces.
3. Confirm `terrain_stream_profile.profile="adaptive-skip"` and `requested_profile="adaptive-skip"`. Then examine nonzero `effect_pending_load_skips` and `successful_dispatch_after_skip`; if both remain zero despite effect pending, analyze caps/cooldown/readiness rather than assume speedup.
4. Compare matched-region p50/p95, time to first displayed 3×3, queue wait, FPS >20/33ms, visual water/terrain correctness, and profiler blocker reasons. No worker/upload cap increases before an evidenced benefit.
5. Update this evidence document, recovery checkpoint, PR #281. If no measurable improvement or smoothness regresses, leave baseline as canonical and investigate effect-source prefetch itself.

Verdict: **R2_ALGORITHM_NOT_MEASURED due to runtime profile remapping.** The uploaded A/B/C artifacts are useful proof of the defect, but not proof that `adaptive-skip` improves streaming.
