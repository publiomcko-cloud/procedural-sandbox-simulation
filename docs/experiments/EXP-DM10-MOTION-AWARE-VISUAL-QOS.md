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

## FINAL BENCHMARK VERDICT — 13 November 2026

The complete DM10 campaign **43411208359** passed headless policy checks (26/26), nine isolated A/B trials and interactive Windows GTX 1050 Ti GPU smoke. Validation is a **technical test pass**, NOT an endorsement of the workload policy.

**Stationary (3600 frames, fast B4 enabled, identical seed):** 277-region HIGH fill finished in 15.578s with existing DM9 scheduler and 15.705s with balanced QoS, a difference of only 0.127s (0.8%). Both completed all 268 outer region meshes.

**Slow motion (straight 2m/s, 720 frames):** outer HIGH completions 81 (baseline) vs 116 (balanced; +43.2%), canonical focus missing 13.61% vs 12.22%, canonical region p95 4319.9ms vs 3585.5ms. Frame spikes >33ms 1.39% vs 1.66%, a small regression.

**Normal directional 18m/s (outback route, two baseline/balanced repeats):**
- DM9 fast B4 without QoS: mean 46.5 visual outer HIGH regions, canonical focus missing 71.67%, >33ms frames 2.57%, canonical region p95 ~2565ms (mean of per-run p95).
- Balanced QoS: mean 13 visual regions, canonical missing 60.83%, >33ms frames 3.95%, region p95 ~2769ms.
- Guarded QoS: visual HIGH **zero** and canonical missing 48.06% in one run, but violates the user's desired directional visual coverage.
- This is a fundamental tradeoff in admission-only throttling: lower visual compute load helps canonical *missing focus*, but does not preserve front visual coverage or frame tails.

A second directional-only corridor proposal reduced missing-core dispatch intervals from 1000ms to 500ms, with a 450ms interval when canonical jobs are active, alongside a new **true velocity-forward near corridor** metric (0–48m ahead, 20m each side). Full tests **43412625094** passed policy contracts, six paired movement runs and interactive GPU smoke.

| Average over paired 18m/s runs | DM9 fast off QoS | Balanced 1s | Corridor 0.5s |
|---|---:|---:|---:|
| Outer HIGH regions completed | 49.5 | 12.5 | 21.0 |
| Canonical missing focus frames | 64.72% | 60.28% | 64.86% |
| **HIGH coverage in near-forward velocity corridor** | **39.64%** | **7.85%** | **9.02%** |
| Frames >33ms | 3.12% | 3.74% | 3.40% |
| Canonical load p95, mean of per-run p95 (ms) | 2812 | 2776 | 2888 |

**Decision:** `DM10_DIRECTIONAL_QOS_NOT_QUALIFIED`. Admission throttling alone cannot maintain both quick canonical and fast directional HIGH fill. The `corridor` variant is NOT recommended for local default use; `guarded` is rejected because it starves the visual outer ring. The idle/slow `balanced` policy offers a limited measurable benefit, but automatic production activation still requires a viable directional mode. Keep `SANDBOX_DM10_VISUAL_QOS` empty/off by default. `main` remains unchanged.

**Next targeted intervention (new isolated phase, no assumptions of success):** accelerate pristine/partially edited canonical `generate_chunk` by applying the exactly proven Surface Nets uniform-cell gate to canonical chunks, guarded by exact edited/brush/effect/cave/materialized-tile mesh parity tests. Also measure dedicated visual worker lane versus Godot's shared `WorkerThreadPool` to separate canonical queue contention. Investigate canonical `sample_density_snapshot` field, immutable snapshot preparation, per-chunk meshing, and effect dependency stalls with independent timing. Do NOT silently change authoritative edit or save semantics.

### Reproduction flags

Baseline:
```powershell
$env:SANDBOX_DM9_FAST_B4 = "1"
$env:SANDBOX_DM9_VISUAL_ADAPTIVE = "1"
$env:SANDBOX_DM9_VISUAL_WORKERS = "4"
$env:SANDBOX_DM10_VISUAL_QOS = "off"
```

Isolated tests may temporarily select `balanced`, `guarded`, or `corridor`. These policies are experimental and not the recommended movement default.
