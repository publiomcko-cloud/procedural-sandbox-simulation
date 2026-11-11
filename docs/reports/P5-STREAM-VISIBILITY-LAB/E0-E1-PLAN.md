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
