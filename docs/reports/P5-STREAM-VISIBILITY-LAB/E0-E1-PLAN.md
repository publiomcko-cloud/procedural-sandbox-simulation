# P5 streaming visibility laboratory — E0/E1

Base: `f6fbfa844ebf283ad9ff83684e4018f0c3faf1bd` (experimental PR #281).
Branch: `exp/p5-stream-visibility-lab`.
This is a **DO NOT MERGE** experimental line. Do not mutate P5.0F #280, P4/P5 authority, mod schemas, collider, saves, or hydrology.

## E0 — passive readiness and milestone instrumentation

- `terrain_stream_budget_window` adds all-frame 3x3 **committed terrain region** coverage, including stationary frames, and preserves prior F10-movement-only counters.
- `terrain_region_visual_ready` records queue-to-first-dispatch, first-mesh and final-scene-commit latency for LOAD stages. This is **not pixel coverage or first drawable proxy**; after E2 it must distinguish provisional and definitive visuals.
- Existing 1s aggregated timing, cap and stage checks remain unchanged. Runner outputs `terrain_unpublished_region_pct`, first visual p50/p95, and keeps full logs for audit.
- A cold startup, mixed loaded area, revisit, normal F10 and Ctrl+F10 must be profiled separately; mix of routes cannot be interpreted as A/B speedup.

## E1 — opt-in dependency-aware queue scheduling

E1 builds on E0; it must preserve all existing profiles unchanged and use a separate `adaptive-skip-dependency` mode with no extra worker/upload budgets or authority modifications.
Prioritize ready-to-mesh regions and the required projection sources for currently waiting stages, bounded by the existing 9x9 protected effects footprint. Urgent edit/transaction work must never be displaced by speculative LOADs.
Only promote after same-route forward/reverse-order controls, exact-HEAD Windows Godot qualification and owner GUI acceptance.

## Acceptance

1. E0 baseline tracing has no behavioral change and no material frame regression.
2. E1 reduces p50/p95 or missing requested regions without >=1 percentage point higher >20ms frame proportion, stutter, visual gaps, or persistence/authority regression.
3. All existing P4/P5 CI workflows plus focused new headless tests pass at exact SHA.
4. No CI PASS alone is evidence of GUI improvement or an authorization to merge.

## E1 implementation checkpoint (source-only pending CI)

- `adaptive-skip-dependency` adds readiness ranking **only within the visible 3x3 LOAD stages**. Edit, partial and full priorities remain unchanged. A ready source set only changes stage ordering; the canonical snapshot check still gates work.
- Source prefetch reorders nonurgent **already enqueued** scopes by earliest waiting stage that needs them (2-region-radius dependency), preserving urgent FIFO, exact 9x9 protection and 2+2 effect worker caps.
- E1 does not change F10 predictive targets, protected scope membership, source generation, mesh worker cap (8), snapshot/upload budgets, surface/river/ocean code, persistence or transaction publishing.
- `dependency_prefetch_reorders`, `dependency_ready_mesh_dispatches`, `dependency_ready_target_pct` and region availability/visual latency are exposed in the existing PowerShell A/B runner.
- E1 readiness is per-region source-halo completeness; a shared boundary may need additional adjacent targets, so original fail-closed snapshot validation remains the **only authoritative** admission gate.

Test `p5_stream_dependency_tests.gd` exercises selector prioritization, edit precedence, queue membership, urgent FIFO, exact 25-source halo, ready vs cold and invalidated-scope rejection. All new behavior is opt-in and **UNQUALIFIED** until exact-HEAD CI, followed by reproducible GUI A/B with seed 424242 and 18/54m/s traversals.

## E1.1 — event-invalidated readiness cache (2026-11-11)

The first owner A/B at `fa58f289`, 18m/s F10 (not Ctrl) measured baseline/E1 median visual-ready 2626/2312 ms, >20ms frames 1.86%/3.20% and process average 4.19/5.40ms. E1 is **performance rejected pending optimization**; CI PASS does not overrule that result.

E1.1 preserves profile `adaptive-skip-dependency` and its canonical snapshot checks, with no worker-budget change. Changes:

1. In the presentation owner, mark scheduling demand dirty on focus/window/stage creation, deletion, full reset and final chunk dispatch. Stable frames reuse the target list and cache without a source walk.
2. The effects runtime exposes a monotonic readiness epoch, bumped on projection publication, synchronous reconcile, invalidation, refresh, eviction and scope release. Halo readiness is recomputed only when that epoch or the demand changes; queue ordering changes only with demand, preserving urgent FIFO and queue membership. A source completion is processed on the subsequent frame.
3. One-second telemetry now includes `dependency_scheduler_usec`, `dependency_scheduler_refreshes`, `dependency_scheduler_cache_hit_frames` and `dependency_scheduler_stage_rebuilds`; the runner reports CPU ms/frame and cached-frame percentage.
4. Focused negative tests reject stale cache after invalidation and verify zero source-probe work during unchanged demand. Other profiles still bypass this machinery.

CI and owner GUI/benchmark at exact new HEAD are required. Do not infer improved F10 performance until repeated ABBA trials under the same seed, route, startup state and 18/54 m/s speeds. **DO NOT MERGE.**
