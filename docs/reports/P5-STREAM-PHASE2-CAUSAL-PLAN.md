# P5 Phase 2 — dependency/queue/CPU causal measurement

Base: exact GPU-qualified commit `270fc6c4e10b2a428e4ef7a641d795e185028b8b`.
Branch: `exp/p5-stream-phase2-causal` — EXPERIMENT ONLY, DO NOT MERGE.

## Hypotheses

1. Effect source/projection readiness for the moving 3x3 focus window dominates the delay before definitive meshing.
2. Mesh scheduler repeatedly scans unready corners, consuming main-thread frame time without admitting work.
3. Once a job is admitted, worker CPU costs for SDF/meshing and environment cache dominate the remaining latency.

## Controlled method
- Keep original mechanics, authority, editing, hydrology, rendering and worker budgets unchanged; new code is an observer/wrapper only.
- GitHub Actions Windows service runner, Godot 4.7.2, headless, fixed seed 424242, empty per-trial APPDATA.
- Exact trajectories in engine at 60 movement steps/s: idle, straight at 18m/s, straight at 54m/s, 54m/s out-and-back. 720 movement frames plus telemetry flush.
- Per-route A/B/B/A order: adaptive-skip, adaptive-skip-coarse, adaptive-skip-coarse, adaptive-skip. The coarse strategy affects visual coverage but must not be interpreted as a CPU-optimized definitive terrain.
- Report worker queue vs stage pre-dispatch waiting separately, per-job CPU p50/p95, effect pending p50/p95, blocked-dispatch counts, stage CPU milliseconds/frame, definitive and provisional region completion, frame >20ms and >33ms.
- All results keyed by exact commit, run, profile, route, seed and frame count. No uncontrolled operator inputs.
- Keep graphics acceptance from the independent GPU runner: 360 rendered frames at 960x540, real NVIDIA adapter. Headless timing cannot substitute for GPU FPS.
- Fail closed for missing routes, incomplete 721-frame coverage, profile mismatch, missing evidence, or unavailable worker receipt.

## Acceptance
- Complete 16-trial cold-state diagnostic matrix and validated stage/worker breakdown.
- Distinguish whether effect readiness, main scheduler scan, or actual meshing worker execution is the principal delay in each route.
- Identify next opt-in architecture hypothesis and its safe rollback/test gate. Do not promote code to main or interpret the presence of preview as definitive region readiness.

## Limitations
- This is a correlation/trace decomposition rather than a manipulated causal experiment. A later isolated opt-in dependency scheduling variant is necessary to establish a controlled causal speedup.
- All A/B runs are cold starts; out-and-back approximates a revisit but is not equivalent to a separately prewarmed save.
- Blocking event counts reflect failed admissions (not elapsed wait duration); stage_work_usec represents accumulated per-frame wall-clock duration, not exclusive CPU-core utilization.
- Only two repetitions/profile/route. Do not claim confidence intervals or generality across machines/seeds.
