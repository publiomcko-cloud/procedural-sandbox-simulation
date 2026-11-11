# CONTEXT CHECKPOINT — Sandbox P5.0F streaming performance A/B R2
**Updated 2026-11-11. Prepared for interruption, new conversation, new AI agent or local Codex session.**

This checkpoint is an authoritative *navigation and decision record* for the **experimental streaming branch**; source code and exact Git HEAD remain the actual authority. A new agent must read this file AND `docs/reports/P5-0F-STREAM-ADAPTIVE/EXPERIMENT.md`, `AB-R1-RESULTS.md`, `AB-R2-HEAD-OF-LINE.md`, the active PR, and the changed files before acting.

## 0. Repo / branches / do-not-merge guardrail

Repository: `publiomcko-cloud/procedural-sandbox-simulation` (GitHub; private).
Engine: pinned `Godot_v4.7.2-stable_win64_console.exe` on Windows self-hosted runner and owner's PC.
Owner local path: `C:\Dev\sandbox-sim-dev`.
- `main`: release/stable target, **must not merge the experiment directly**.
- `feat/p5-0f-environment-visuals`, PR **#280**: base functional P5.0F, includes R5.2 visual retention/swap and R5.3 cross-region coastline repair. Owner inspected coast across many regions and found no new cut after R5.3; local P5.0F focused qualification **210 assertions/0 failures** at `a818b65b5f7b8ac2d8b1b93f21dc63d8d8cd9e3f`. Other CI/performance gates can remain open.
- `exp/p5-0f-adaptive-stream-budget`, **draft PR #281 targeting main ONLY to activate test workflows**, derived from above feature branch at R5.3 `a818b65b...`. This branch MUST NOT be merged as-is; it is an isolated experiment. The head will advance as documentation/tests are committed; resolve its current SHA from GitHub, do not trust an old short hash in chat.

## 1. Why P5.0F is organized this way

Architecture: mod-first content, canonical SDF terrain, deterministic simulation with P5.0A–E finite/infinite hydrology, region-streamed lifecycle, workers over immutable source snapshots, main-thread revision-gated visual publication. Hydrology authority and render caches have separate responsibilities; P5.0F is derived visual-only presentation (ocean/finite water/rain), not a second authority. R5.2 retains the last complete water `ArrayMesh` during terrain edits and swaps only when a revision-matched replacement exists. R5.3 solves a class of coastal cuts using validated neighboring SDF seam admission. Do not undo those visual fixes to accelerate loading.

Development protocol: contracts/specs first, targeted branches, fail-closed gates, isolated headless tests + cumulative P4/P5 CI, owner local PERF_TRACE test and screenshots, evidence-based acceptance, then guarded merge. Never declare a pending/queued CI as PASS.

## 2. A/B R1 result (measured, not estimated)

At exact commit `aa3ede689a969518f0327e20d923d29d4447d112`, owner attached:
- `P5-stream-baseline-20261111-102738.log`, 25.60s, 30 region load completions, 480 terrain jobs, frame >20ms 4.57%, frame >33ms 1.30%.
- `P5-stream-adaptive-20261111-102838.log`, 26.81s, 33 region load completions, 528 jobs, frame >20ms 3.74%, frame >33ms 0.85%.
- Each passed `P5_0F_STREAM_BUDGET_PASS: assertions=152 failures=0`.
- GPU upload p50 ~0.25ms and terrain worker run p50 ~145ms; terrain queue wait p50 1.4–1.9s. The adaptive 2nd-dispatch opportunity was unlocked on 364 frames but **only actually used 7 times**.
- Routes after the initial 9 regions were different; unmatched totals and medians cannot prove a benefit. Initial 3×3 region mean load time was only ~1.6% faster adaptive. Verdict **AB_R1_INCONCLUSIVE_FOR_THROUGHPUT**.
Full details and quantitative table: `docs/reports/P5-0F-STREAM-ADAPTIVE/AB-R1-RESULTS.md`.

Hypothesis for R2: `terrain_demo.gd::_dispatch_mesh_jobs()` returns immediately on `_terrain_effect_snapshot_pending()`, even if an independent later load stage is ready. Distinguish blocked dependency versus worker saturation before raising capacity.

## 3. R2 implementation — what is changed

**New optional `adaptive-skip` profile**. `baseline` remains fixed 1 dispatch/frame and `adaptive` retains the R1 adaptive policy; neither performs skip. `adaptive-skip` has the R1 1-to-2 hysteretic budget and allows bounded per-frame skip past pending **load-only** effect snapshots:
- Limit 3 unique skipped load regions within a dispatcher invocation; no duplicate retries for that region on that frame.
- Existing shared 3.5ms snapshot budget applies after first attempt/skip; a single expensive call is not preemptible. On frame spike or policy cooldown, no skip.
- On a pending effect for chunk, shared X, shared Z or shared corner, exclude the region only for that invocation, choose next eligible region deterministically. Skip only pending load; **do not bypass edit transactions, partial LOD stages, full rebuilds or genuine failures**.
- Region submit_index/pending_count remain untouched on skip. Source revisions, SDF authority, object world revision and mesh publication/commit gates remain unchanged. Skipped region is retried naturally next frame.
- Worker in-flight hard cap 8; GPU uploads hard cap 4 and 3.5ms per frame; water SDF cache 2 in-flight and 1 dispatch/frame; P4 persistence and simulation unaffected.

Changed code:
- `game/scripts/terrain/terrain_stream_dispatch_selector.gd` pure deterministic stage selection, stage priority and bounded skip guard.
- `game/scripts/terrain/terrain_demo.gd`: new profile parsed from environment `SANDBOX_STREAM_PROFILE` or CLI `--stream-profile=`; four effect-pending branches instrumented; `_next_mesh_job_request` uses pure selector; per-second blocker counters and skip recovery metrics.
- `game/tests/p5_0f_stream_budget_tests.gd`: legacy policy and new selection/exclusion/priority/limits tests.
- `scripts/perf/run-p5-stream-profile.ps1`: three modes, PERF_TRACE, full logs/events/`.metrics.json`, NUL removal for Windows native console output, region load p50/p95 and blocker histogram.
- `scripts/ci/run-p5-0f-qualification.ps1`: already runs new policy test alongside focused P5.0F and inherited P5.0E→A/P4 qualification.

New `terrain_stream_budget_window` JSON:
`mesh_dispatch_blockers` histogram (`effect_pending_chunk`, `effect_pending_x_boundary`, `effect_pending_z_boundary`, `effect_pending_corner`, `worker_capacity`, `dispatch_cap`, `snapshot_time_budget`, `effect_skip_not_allowed_or_budget`, `no_eligible_stage*`);
`effect_pending_load_skips`, `successful_dispatch_after_skip`, `skip_time_budget_exhausted` counts; existing FPS and per-subsystem stage timers retained. Total skips alone are NOT evidence of reduced latency.

## 4. Qualification state at checkpoint

**Code and tests published, but R2 not yet qualified.** At the time of this checkpoint the exact-head Windows GitHub Action queue was pending/queued. No R2 owner A/B data exists, no measured speedup is claimed; no acceptance/merge authorized. Use GitHub PR #281 Actions page and verify exact HEAD. This file may remain unchanged after CI completes; always query live status instead of assuming it is current.

No Godot binary is installed in the model's Linux container; the authoritative test executor is the Windows self-hosted runner or owner's local pinned Godot. If CI fails, read failed **job logs**, distinguish actual code errors from runner issues, repair only within experimental branch, and requalify at its new HEAD.

## 5. How to resume on user's machine

```powershell
cd C:\Dev\sandbox-sim-dev

git fetch origin exp/p5-0f-adaptive-stream-budget
git branch --show-current
# If already locally created, use git switch exp/p5-0f-adaptive-stream-budget.
# Otherwise:
git switch -c exp/p5-0f-adaptive-stream-budget --track origin/exp/p5-0f-adaptive-stream-budget
git pull --ff-only origin exp/p5-0f-adaptive-stream-budget
git rev-parse HEAD

$godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --editor --path .\game --import
& $godot --headless --path .\game --script res://tests/p5_0f_stream_budget_tests.gd

# Each runner enables PERF_TRACE and creates per-profile logs automatically.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\perf\run-p5-stream-profile.ps1 -Profile baseline
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\perf\run-p5-stream-profile.ps1 -Profile adaptive
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\perf\run-p5-stream-profile.ps1 -Profile adaptive-skip
```

The same local branch/HEAD must be used for all 3 tests, no resets/edits/saves between runs. Navigate the same route for ~90s. Log destination `C:\Dev\p5-0f-evidence`; upload full logs + `.metrics.json` + report any visible hitch. For baseline/adaptive comparability, if prior `aa3ede...` logs are consulted, remember they represent a different code revision than current head. New control runs are necessary.

## 6. What the next agent must do, in order

1. Verify current PR #281 HEAD and branch, file diffs and exact-head qualification; **do not change PR #280 or main**.
2. If headless test/CI fails, inspect first failing output and make a small fix; no unsafe cap increases or hydrology changes.
3. If qualification passes, send owner the 3 commands above and request comparable logs; preserve the ongoing PERF_TRACE requirement for all GUI commands.
4. Analyze `mesh_dispatch_blockers`, effective skip-to-ready conversions, queue waits, per-region load p50/p95, and FPS long-frame distribution across matched regions; compare skip mode against BOTH baseline and adaptive.
5. Reject candidate for ≥1 point absolute increase in >20ms frames, regression in >33ms frames, visual stutter, new water/shore seam, or any P4/P5 contract failure. Prefer not adding worker concurrency because GPU upload is cheap and workers already run ~145ms.
6. If successful, document AB-R2 quantified result, revise acceptance gates, propose **selective promotion** into P5.0F branch only; do not merge experimental PR #281 into main. If no benefit, preserve R5.3 baseline and investigate prefetch/worker pipeline rather than raising limits.

## 7. Source navigation / links

- GitHub repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation`
- Qualified visual branch PR #280: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/280`
- Isolated streaming experiment draft PR #281: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/281`
- R1 design: `docs/reports/P5-0F-STREAM-ADAPTIVE/EXPERIMENT.md`
- R1 evidence: `docs/reports/P5-0F-STREAM-ADAPTIVE/AB-R1-RESULTS.md`
- R2 design/test plan: `docs/reports/P5-0F-STREAM-ADAPTIVE/AB-R2-HEAD-OF-LINE.md`
- P5.0F rendering contracts: `docs/specs/P5-0F-ENVIRONMENT-VISUALS.md`
- P5 hydrology / authority: `docs/roadmap/P5-ENVIRONMENT-HYDROLOGY-PLAN.md`

If new conversation lacks logs, never pretend a local benchmark was performed; use only the proven R1 evidence until R2 logs arrive. Whenever publishing a new commit, record SHA and CI/GUI results in this checkpoint or successor report. 

## 8. NEW RESULT — owner's first R2 A/B/C on 2026-11-11 12:22–12:24 (-03:00)

**IMPORTANT: the first R2 performance trial is INVALID due to actual runtime profile remapping. This section supersedes prior "no owner A/B" status.** Uploaded `P5-stream-baseline-20261111-122250.log`, `P5-stream-adaptive-20261111-122327.log`, `P5-stream-adaptive-skip-20261111-122409.log` with matching events/metrics, all on `b56131e66bc83398e5183693b8d736646a7f528d`; 173 policy assertions PASS per GUI runner.

Decisive evidence: the third report **requests** `adaptive-skip` and its metrics JSON is labeled that way, but in-game `PERF_TRACE terrain_stream_profile` says `profile:"baseline"`. The old `terrain_demo.gd::_ready` guard `if _stream_profile != "adaptive": _stream_profile = "baseline"` silently downgraded the third new mode before CLI parsing. Therefore **0 actual skips, 0 recoveries, 0 boosted frames** and no R2 speedup/slowdown was measured. Baseline and adaptive remain valid R1 modes, but trajectories/sample lengths differ so their relative data cannot prove causality. Distinct runs: baseline 27 load regions, 5.91% frames >20ms; adaptive 27, 4.59%; misconfigured skip run 24, 3.50%. Three-session p50 unpaired 1,780 / 1,802 / 1,657ms, not proof of improvement. All are original as-run measurements, not fixed-code data.

**Corrective code published after these logs:** `TerrainStreamBudgetPolicy.resolve_profile` handles three modes and CLI override, real `_ready()` invokes it, the trace declares requested/effective/mismatch, 10 new pure resolver regressions, and the PowerShell reporter now FAILS if observed effective mode mismatches. The first-run source-backed postmortem is `docs/reports/P5-0F-STREAM-ADAPTIVE/AB-R2-FIRST-RUN-RESULTS.md`; read it before changing code.

**Current next step:** check latest exact-head CI; if green (or manual headless PASS), run three identical-path experiments again from the new head with the pinned Windows Godot and the built-in PERF_TRACE runner; verify effective `adaptive-skip` is actually active **before** interpreting FPS/throughput. Update this checkpoint's current HEAD/gates based on live GitHub, not its stale checkpoint time. Keep PR #281 draft, leave R5.3 PR #280 untouched and never direct-merge experiment to main.

## 9. NEW VERIFIED RETEST — owner's second R2 A/B/C on 2026-11-11 13:20–13:22 (-03:00)

**This section supersedes §8's "R2 not measured" verdict.** The user repeated all three profiles on the *fixed* exact commit `0661e1b9fc32286cce429ecafdd2ffc7e83cfc84`, with the pinned Windows Godot and the tool-generated PERF_TRACE logs. All three reported **183 assertions/0 failures**, exited 0, and showed `requested_profile == profile` with `profile_mismatch:false`.

Artifacts (user uploads in the 2026-11-11 13:22 session):
- `P5-stream-baseline-20261111-132035.log` / `.events.txt` / `.metrics.json`
- `P5-stream-adaptive-20261111-132101.log` / `.events.txt` / `.metrics.json`
- `P5-stream-adaptive-skip-20261111-132130.log` / `.events.txt` / `.metrics.json`

**R2 bypass is FUNCTIONALLY CONFIRMED, but not ready to promote.** Adaptive-skip actually executed **135** skip events; **33** successful dispatch-after-skip events; **18** skip-time-budget exits. 27 regions loaded vs baseline 27 and adaptive 24. Unpaired load p50 baseline 1,754ms, adaptive 1,577ms, skip 1,495ms; p95 baseline 5,176ms, adaptive 5,551ms, skip 5,076ms. Slow frames >20ms baseline 6.09%, adaptive 3.21%, skip 2.01% (frames >33ms: 1.08%, 0.40%, 0.32%). Mean frame ~17.37 / 17.11 / 17.21ms.

Matched **21 regions**: mean load baseline **2,724.94ms**, adaptive **2,680.09ms**, skip **2,589.51ms**. Skip ~5.0% mean improvement vs baseline, faster in 14/21; on initial shared 3×3, means 4,376.73 / 4,576.18 / 4,269.07ms. The origin region (5,13) alone was slower in skip (3,342ms vs 2,494ms baseline), so no universal speedup. These are 19–22s non-randomized sequential tests, **not a controlled or statistically conclusive acceleration guarantee**. Longer same-route reverse-order tests are recommended.

Complete machine-readable numbers, parsed event counts, matched cohort methodology, constraints and verdict: `docs/reports/P5-0F-STREAM-ADAPTIVE/AB-R2-VALID-RESULTS.md`. The earlier invalid first-run report remains evidence of the profile selection bug, not of R2 throughput.

### CI caution

For EXACT tested SHA `0661e1b9...`, GitHub reports successful P5.0F, P5.0A/B/C/E, P4.0F/G/H and Starter checks, **but P5.0D cumulative workflow FAILED** on nested P4.0H perf gate: `terrain_window_reconcile` p99 **30,524µs > 25,000µs**. The underlying `P5_0D_FINITE_RUNOFF_PASS: 130/0` and `P4_0H_FINAL_PASS: 81/0` were successful; the sampled perf bound was not. The independent P4.0H workflow succeeded on the same SHA. Do not call cumulative CI green or loosen the 25ms threshold. Compare repeat traces, understand runner interference/variance vs actual code regression, and keep the hard gate until qualified. Later documentation-only commits may produce new CI runs; always verify **current HEAD and exact-head status** before promotion.

### Mandatory next agent actions

1. Read `AB-R2-VALID-RESULTS.md`, this checkpoint, PR #281, source and CI. Verify current experimental branch HEAD, not just the tested `0661...` ancestor.
2. Preserve baseline and all P4/P5 authority, R5.2 water retention, R5.3 coastline. PR #281 remains a DRAFT **DO NOT MERGE**.
3. Investigate nested P4.0H p99 gate failure and rerun controlled CI with no gate relaxation. Source snapshot/workload/order variance is a **hypothesis**, not an excuse.
4. If CI clear, repeat 60–90s same-route baseline/adaptive/adaptive-skip, ideally reverse-order (skip/adaptive/baseline). The built-in PowerShell script instruments and writes logs+metrics automatically, with profile fail-closed check.
5. Compare per-region matched latency, first 3×3 loaded, frame >20/33ms, successful skip conversions, remaining effect-corner pending and worker-capacity stalls, plus subjective visual hitches. Require reproducibility before selective promotion into P5.0F.
6. If actual skip gains disappear, preserve baseline and target effect-preparation readiness, not arbitrary worker count increases.

**Current R2 verdict: FUNCTIONAL_PASS, THROUGHPUT_PROMISING, CI_PARTIAL, NO_MERGE.**
