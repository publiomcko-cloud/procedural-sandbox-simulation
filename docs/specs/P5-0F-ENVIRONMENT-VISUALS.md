# P5.0F — Derived Environmental Visual Presentation

Status: IMPLEMENTED / SELF-HOSTED QUALIFICATION PENDING / OWNER GUI ACCEPTANCE PENDING

## Scope and authority

P5.0F presents the existing P5.0A–E hydrology authority and SDF-derived terrain cache. No simulation authority, water persistence or runtime schema is changed. The presentation is an intentionally stylized V1, not volumetric CFD or physically accurate water-surface reconstruction.

- A new EnvironmentVisualPresentation Node3D belongs to the playable terrain scene. One MultiMeshInstance3D per resident region renders at most 48 surface quads from the existing 8x6 environmental grid, without per-cell nodes.
- Finite water quad height derives only from surface_water_ul divided by cell area and the current SDF surface height. A cosmetic 25 mm minimum visible depth and 12 mm offset avoid z-fighting. Neither is fed back to water authority.
- Rivers and oceans use their persisted fixed reservoir_level_mm. Visual height does not change with unlimited incoming/outgoing reservoir exchange. Colors distinguish finite/river/ocean.
- Missing or stale surface cache hides water instead of displaying a stale terrain-relative plane. Refresh checks exact environment revision, logical tick, world seed/generator, terrain revision, cache identity and terrain effect revision.
- A single camera-local rain MultiMesh (at most 64 streaks) derives visibility from the pinned climate profile's positive precipitation rate. The environment scope's profile ID and SHA must match. The V1 rate is static; rain animation is cosmetic, with no simulation writes.

## Performance and lifecycle

- Poll at most 3 resident region records per frame, and rebuild at most one water MultiMesh per frame. Unchanged revision tokens are reused.
- Update bounded rain streak transforms at most every 100 ms.
- Publishing a region registers one hidden visual node. Streaming unload removes only the derived node and token; loading recreates it from persistent environment authority and regenerated SDF surface data.
- SANDBOX_PERF_TRACE=1 emits p5_environment_visual_rebuild duration and instance count. get_visual_metrics() exposes poll, rebuild, stale-hide, and peak-duration counters.

## Qualification and acceptance gates

Focused headless tests cover finite volume-derived levels, fixed river/ocean levels, negative region coordinates, deterministic pure plans, invalid records, dry cells, cache invalidation, revision refresh, rain profile SHA guard, unload/revisit and source immutability. The P5.0F Windows runner invokes Godot 4.7.2 import and focused tests, then inherits the complete P5.0E through P4 cumulative envelope.

Owner GUI acceptance is required before P5.0F can be called complete. Inspect rivers/oceans, rainfall, finite runoff, terrain edits and cache rebuilds, region crossings/revisits, save/restart/load, LOD and frame smoothness. Headless tests do not assess rendered pixels, transparency sorting or perceptual hitching.

## Explicit limitations

Flat environment-grid quads do not conform to exact bank outlines, rain is a camera-local cosmetic effect rather than weather particles with collision, and water has no collision surface. Integrated conservation/performance/replay and final owner signoff are reserved for P5.0G.

## Files

- game/scripts/simulation/environment_visual_presentation.gd
- game/scripts/terrain/terrain_demo.gd
- game/tests/p5_0f_environment_visuals_tests.gd
- scripts/ci/run-p5-0f-qualification.ps1
- .github/workflows/p5-0f-environment-visuals.yml

## Startup location controls (P5.0F owner visual testing)

Pass one of the following Godot user arguments **after** the standalone `--` separator:

- `--start-water=ocean`: searches a bounded base-SDF ocean band (region Z 10..16, region X -6..6) for the most submersible 8x6 environment grid and starts at that region's center. Uses the current loaded world seed, including a saved world's seed.
- `--start-region=-2,13`: starts focused on the specified integer world region, with its center at world (-24, 162) meters.
- `--start-position=-27.5,161.25`: starts focused on precise X/Z world coordinates in meters.

Example Windows PowerShell: `& "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --path .\game -- --start-water=ocean`.

No option preserves the original starting focus. Multiple location options, malformed coordinate pairs, unknown presets or out-of-range values are rejected with a startup console warning without modifying simulation state. The console reports `P5_START_LOCATION` with selected region and estimated candidate base-SDF ocean cells.

**Important:** Potential water eligibility from base SDF does not prove live reservoir binding or successful rendering; saved terrain edits, profile initialization, scene cache and render qualification may change the live observation. No test fixture injects water into gameplay authority.

## Diagnosed ocean-visibility bootstrap defect (P5.0F)

The original playable build provided only the first-party core-rocks package. The environment runtime requires exactly one selected `environment_climate_profile` before configuring climate → runoff → hydrology, so an ocean-start camera position could be correct while no authoritative ocean cells were ever generated. The earlier P5.0F tests used an injected fake registry and therefore did not catch missing default mod content.

Correction (R1): bundle `firstparty.core_climate:temperate` as declarative, data-only content at `game/mods/environment-presets/core-climate`. The playable scene opts into this second bundled package root in addition to the original first-party and user roots; generic object-stream consumers and P4 fixtures continue to discover only the original `res://mods/first-party` root unless they explicitly opt in. The strict unknown-content-type rejection contract is preserved; no fallback or silent filtering. The playable single-profile selection pins the canonical SHA and configures hydrology without a parallel simulation. Multiple climate profiles still require explicit selection.

A focused integration test now discovers the real first-party mod, binds it into the real climate/runoff/hydrology runtime, commits generated ocean reservoir cells, and checks that the live authoritative state creates water quads. Starting with `-- --start-water=ocean` prints `P5_WATER_DIAG` every two seconds while water remains absent (up to thirty samples), then `P5_WATER_READY` when the focused region has authoritative ocean cells and visible water quads. This diagnoses profile discovery, hydrology activation, surface cache, binding, and rendering separately. Visual/GUI acceptance remains required.

## R1 — Mod compatibility and P4 performance gate

Root cause: adding a climate content record under the original `res://mods/first-party` root made legacy P4 registry consumers fail closed with `unsupported_content_record_type`; cascading object, placement and M4.0 tests failed. The P4H trace gate also recorded `simulation_scheduler_frame` p99 23,318 µs against the inherited 5,000 µs budget when P5 hydrology was unintentionally enabled during P4 performance tests.

R1 isolates the default climate profile under `res://mods/environment-presets` and opts in only the playable scene's no-override bootstrap. Explicit package root overrides remain unchanged, ensuring existing P4 test isolation. No P4 performance threshold is raised, no unknown content is silently accepted, and the authority schema is unchanged. Focused P5.0F tests assert that legacy registry discovery works without a climate handler, and that the real playable registry with both roots binds climate, runoff and ocean hydrology.

The cost of hydrology-enabled gameplay must be measured by dedicated P5 performance traces during P5.0G; restoring the P4-only baseline is not proof that mixed P5 performance already satisfies the budgets.
