# DM10: movement-sensitive visual HIGH scheduling, preserve canonical 3×3

**Status:** opt-in experiment; `main` unchanged. **Design goal:** retain DM9's 16s stationary full HIGH radius where possible, restore canonical latency during directional movement while still covering the route in front of velocity.

## Starting evidence, DM9 B4 fast SDF+Surface Nets

At 18m/s, DM9 fully enabled B4 achieved ~48 visual HIGH region completions per 720 frames versus ~15 slow reference, but canonical p95 and frame spikes regressed. The earlier DM9 repeated A/B: reference 1.99% frames >33ms and 2.35s average canonical region p95; full-speed fast B4 3.42% and ~2.93s. Stationary full HIGH fill improved from ~52.6s to ~16.1s.

## Implemented opt-in policy

`SANDBOX_DM10_VISUAL_QOS=balanced` or `guarded`, empty/off disables entirely. `game/scripts/terrain/dm10_motion_aware_visual_policy.gd` and `terrain_demo.gd` provide:

- **Idle:** when canonical core and queue ready, up to four high-density derived B4 visual workers. While core missing or canonical workload active, defer new visual submissions.
- **Slow (0.05–3m/s):** with canonical ready and idle, up to four workers with a short 160ms minimum interval between completed submissions; when canonical jobs are active, one worker with >=650ms spacing; missing core always wins.
- **Directional (>3m/s):** a single visual worker max; while core missing, `balanced` allows one start per >=1000ms and `guarded` pauses all new visual starts. With canonical core ready, submission interval 320ms and 700ms if canonical work active. Elevated frame/process pressure stretches intervals to >=1250ms or blocks new submissions.
- Direction is derived from actual player XZ displacement per frame, **not camera orientation**. The same existing radial HIGH region set is sorted into forward, side and behind priority tiers with distance ordering within each tier. The preserved density/geometry, 130m radius, 210m TTL, rock semantics, core 3×3 authority and revision gates do not change.
- Work already submitted is allowed to complete, not canceled or transformed into authority. Completed visual CPU meshes still obey the existing single GPU upload/frame cap.
- New structured `dm10_visual_qos_sample` events record speed, state, reason, core readiness, canonical load/mesh work, visual workers, permitted start and admission interval. Existing `dm8_radial_gap_sample` now also emits `dm10_velocity_front_gap` on **both baseline and candidate** runs, for an apples-to-apples motion cone gap metric. Benchmark metrics aggregate admission-block samples and this gap p95.

## Validation

Godot 4.7.2 Windows headless import, script checks and standalone policy tests: **26/26 assertions passed**, including stationary/slow/normal speed, canonical pressure guard, cooldown, frame pressure, direction reversal and region set preservation.

Automated campaign: <https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43411208359>, sequential contract → paired A/B nine deterministic trials → interactive GTX 1050 Ti GPU smoke. The nine trials cover original (QoS off) versus balanced idle/2m/s/18m/s and a guarded 18m/s sample with duplicate A/B motion trials. Data is recorded into artifacts and GitHub job logs, plus seeded isolated world and process CPU/RSS counters.

**Do not claim validated performance or merge into `main` until the nine-trial comparisons and GPU smoke conclude.** The best candidate should reduce canonical missing/core p95 and frame spikes while keeping sufficient forward HIGH completion and near-baseline idle full-HIGH readiness. If neither balances objectives, isolate the canonical SDF/materialized/brush-effect sampler as a separate next experiment, not a silent fallback.

## Closed qualification receipt

Workflow <https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43411208359> finished **PASS/PASS/PASS** for policy contracts (26/26), A/B, and GPU smoke. Stationary full HIGH 15.578s baseline vs 15.705s balanced. At 2m/s visual shells completed 81 baseline vs 116 balanced, canonical focus missing 13.61%→12.22%. At normal 18m/s (two trials each) canonical missing was 71.67% baseline vs 60.83% balanced, but visual HIGH completions fell 46.5→13 and >33ms frames increased 2.57%→3.95%. Guarded allowed **zero** outer visual HIGH during the trial. **Verdict: directional policy not qualified; do not enable by default.** A second corridor-focused trial and final decision are documented at [EXP-DM10 directional corridor report](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/exp/dm10-directional-corridor-qos/docs/experiments/EXP-DM10-MOTION-AWARE-VISUAL-QOS.md). Remain on existing DM9 default for actual use while investigating canonical meshing and worker isolation.
