# P5.0F — Derived Environmental Visual Presentation

Status: IMPLEMENTED / SELF-HOSTED QUALIFICATION PENDING / OWNER GUI ACCEPTANCE PENDING

## Scope and authority

P5.0F presents the existing P5.0A–E hydrology authority and SDF-derived terrain cache. No simulation authority, water persistence or runtime schema is changed. The presentation is an intentionally stylized V1, not volumetric CFD or physically accurate water-surface reconstruction.

- A new EnvironmentVisualPresentation Node3D belongs to the playable terrain scene. One MeshInstance3D per resident region renders an SDF-clipped ArrayMesh sourced from the existing 8x6 environmental authority grid; it has no per-cell nodes. The presentation uses a bounded 17x13 SDF height grid (1 m spacing, up to 2,304 vertices per region). Rain retains its independent bounded MultiMesh.
- Finite water depth derives only from `surface_water_ul` divided by cell area and the current SDF surface height. A *presentation-only* minimum physical depth of 10 mm is required to render a finite puddle. Smaller positive volumes remain fully authoritative but invisible; there is no artificial 25 mm water column. A 12 mm draw offset avoids z-fighting and is never fed back to water authority.
- Rivers and oceans use their persisted fixed reservoir_level_mm. Visual height does not change with unlimited incoming/outgoing reservoir exchange. Colors distinguish finite/river/ocean.
- Missing or stale surface cache, or a mismatched derived shoreline grid, hides water instead of displaying an uncut or terrain-stale surface. SDF topography is sampled from immutable region/chunk snapshots in the existing P5.0C worker and is not added to any authoritative/persisted record. Refresh checks environment revision, logical tick, world seed/generator, terrain revision, cache identity and terrain effect revision.
- A single camera-local rain MultiMesh (at most 64 streaks) derives visibility from the pinned climate profile's positive precipitation rate. The environment scope's profile ID and SHA must match. The V1 rate is static; rain animation is cosmetic, with no simulation writes.

## Performance and lifecycle

- Poll at most 3 resident region records per frame, and upload at most one clipped water ArrayMesh per frame. Unchanged revision tokens are reused. Derived SDF shoreline samples are built asynchronously in the existing capped cache worker (2 in-flight, 1 dispatch per frame), only when climate hydrology is actually configured.
- Update bounded rain streak transforms at most every 100 ms.
- Publishing a region registers one hidden visual node. Streaming unload removes only its derived node, terrain samples and token. Terrain edits invalidate and hide the old mesh immediately; revisits regenerate from persistent environment authority and fresh SDF surface-cache products.
- SANDBOX_PERF_TRACE=1 emits p5_environment_visual_rebuild duration and instance count. get_visual_metrics() exposes poll, rebuild, stale-hide, and peak-duration counters.

## Qualification and acceptance gates

Focused headless tests cover finite volume-derived levels, fixed river/ocean levels, negative region coordinates, deterministic pure plans, invalid records, dry cells, cache invalidation, revision refresh, rain profile SHA guard, unload/revisit and source immutability. The P5.0F Windows runner invokes Godot 4.7.2 import and focused tests, then inherits the complete P5.0E through P4 cumulative envelope.

Owner GUI acceptance is required before P5.0F can be called complete. Inspect rivers/oceans, rainfall, finite runoff, terrain edits and cache rebuilds, region crossings/revisits, save/restart/load, LOD and frame smoothness. Headless tests do not assess rendered pixels, transparency sorting or perceptual hitching.

## Explicit limitations

Water is now clipped to a 1 m SDF-derived shoreline lattice with deterministic marching-triangle interpolation, instead of flat 2 m-wide cell quads covering partially dry land. Shorelines are still an approximation of the higher-resolution canonical terrain, rain is a camera-local cosmetic effect rather than weather particles with collision, and water has no collision surface. Integrated conservation/performance/replay and final owner signoff are reserved for P5.0G.

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

A focused integration test now discovers the real first-party mod, binds it into the real climate/runoff/hydrology runtime, commits generated ocean reservoir cells, and checks that the live authoritative state creates water surfaces. Starting with `-- --start-water=ocean` prints `P5_WATER_DIAG` every two seconds while water remains absent (up to thirty samples), then `P5_WATER_READY` when the focused region has authoritative ocean cells and visible shoreline mesh triangles. This diagnoses profile discovery, hydrology activation, surface cache, binding, and rendering separately. Visual/GUI acceptance remains required.

## R1 — Mod compatibility and P4 performance gate

Root cause: adding a climate content record under the original `res://mods/first-party` root made legacy P4 registry consumers fail closed with `unsupported_content_record_type`; cascading object, placement and M4.0 tests failed. The P4H trace gate also recorded `simulation_scheduler_frame` p99 23,318 µs against the inherited 5,000 µs budget when P5 hydrology was unintentionally enabled during P4 performance tests.

R1 isolates the default climate profile under `res://mods/environment-presets` and opts in only the playable scene's no-override bootstrap. Explicit package root overrides remain unchanged, ensuring existing P4 test isolation. No P4 performance threshold is raised, no unknown content is silently accepted, and the authority schema is unchanged. Focused P5.0F tests assert that legacy registry discovery works without a climate handler, and that the real playable registry with both roots binds climate, runoff and ocean hydrology.

The cost of hydrology-enabled gameplay must be measured by dedicated P5 performance traces during P5.0G; restoring the P4-only baseline is not proof that mixed P5 performance already satisfies the budgets.

## P5.0F-R2 — SDF shoreline refinement

**Implementation:** the 8x6 grid and all P5.0A–E hydro/persistence contracts remain unchanged. The P5.0C worker accepts an optional R2 `build_visual_shoreline` flag and produces a **transient** 17x13 height/validity lattice from the exact same brush-edit and terrain-object-effect chunk snapshots. This output is never passed into the EnvironmentStateStore or persistence schema. The flag is enabled only in a playable scene with configured hydrology; P4-only fixtures are not forced to pay for it.

The presenter receives the 1 m terrain lattice only after the environment surface-cache record passes its existing revision gate. The water plane from the authoritative water/reservoir state is clipped against interpolated fine topography using marching triangles. Invalid/missing/stale samples fail closed (no whole-cell fallback). A region has one `MeshInstance3D` with capped vertex count, no per-water-cell nodes, and one main-thread mesh upload per frame. Stream unload drops derived samples; terrain invalidation hides the previous mesh until an updated worker product arrives.

**Acceptance gates:** focused tests cover clipped wet area, fully dry terrain suppressing otherwise wet hydro cells, sample provenance rejection, bounded mesh lifecycle, and actual SDF edit-to-coast causality. Keep owner GUI inspection of underwater appearance, shoreline quality and hitches as explicit prerequisites. The higher-resolution sampling increases worker cost; measure it with P5.0G representative workloads before treating P5 as qualified.

## R2 local visual feedback — rainfall shallows

On the owner's ocean-start screenshot, the shoreline was generated (392 visible triangles), while turquoise patchwork remained over nearby terrain. The original finite-cell presenter treated any positive rainfall (as little as 1,000 µL in a 4 m² cell) as a 25 mm visually deep sheet. R2 now suppresses visible finite puddles below a true 10 mm depth and renders larger accumulations at their derived physical depth. This is **presentation-only**, and never discards, rounds, or modifies stored water. Fixed-level ocean and river visuals are unchanged. Focused tests cover the one-milliliter case and a 40-liter/4 m² one-centimeter puddle.


## P5.0F-R3 — Adaptive SDF shoreline (implemented; qualification pending)

Problem: R2 eliminated spurious thin-rainfall sheets and coarse 2 m full-cell water quads, but the shoreline still followed 1 m terrain samples and an 8×6 hydrology center-classification, creating a jagged coastal silhouette.

Implementation:

- The existing P5.0C worker still emits the same 17×13, 1 m transient top-surface grid. It additionally derives **true 0.5 m SDF samples only near active water levels**, using the same immutable brush-edit/effect snapshots and provenance. At most 96 coast tiles and 512 sparse sample sites per region are admitted. Every interior tile stays at the original 1 m sampling cost.
- Before ocean bindings are committed, the worker uses the already-defined core ocean level (4,000 mm) in the ocean band. If river bindings are available, their pinned reservoir levels are added to the bounded selection. No content schema, water volume, sea level or solver rule changes.
- A coastal 1 m tile is refined to 0.5 m triangles **only if both submerged and dry top-SDF corners exist**. Fully submerged interior quads remain unchanged. The renderer uses sparse true-SDF sites when present; for a newly changed water level, it uses bounded bilinear interpolation of the already-derived SDF heights rather than requesting synchronous SDF work on the main thread.
- **Dry-centered coastal fringe**: where an authoritative ocean cell is directly adjacent to a finite cell whose 2 m center is above the ocean plane but whose shoreline SDF samples show submerged area, the water plane extends one cell only and is clipped to the SDF. This closes an appearance gap caused by the coarse center-based hydrology binding; it never converts the finite cell into a reservoir, generates/injects simulation water, or extends beyond the immediately neighboring cell. This remains a presentation-only ocean shoreline approximation, not a change in simulation coverage.
- One derived `MeshInstance3D` per region; at most 96 coastal tiles refined and 5,760 region vertices. No per-cell SceneTree nodes, no extra water authority, and no per-frame synchronous terrain-density sampling. The one-region rebuild/frame and existing two-worker / one-dispatch constraints remain.
- An optional refinement sampling failure suppresses the derived shoreline and is **not** allowed to block publication of the canonical P5.0C surface cache. Mesh, sample and edit-revision gates continue to fail closed. `p5_environment_visual_rebuild` includes `refined_coast_quads` and `coastal_halo_cells`; SDF worker diagnostics include counts of refined sites and tiles.

Acceptance: focused tests cover real sparse worker samples, immutable water authority, reduction of mesh area for a truly dry 0.5 m sample, dry-centered ocean fringe, no false inland expansion, exact repeatability, 5,760-vertex budget, and the previously required streaming/unload/revisit invariants. Cumulative P4/P5 tests and GUI validation are still mandatory. **Known limitation:** across a region border, a coast where the only authoritative ocean cell is in the neighboring unloaded region is not yet guaranteed to have a matching one-cell visual fringe. Evaluate this as an explicit P5.0G visual-boundary gate, not an assumed solved case.

Lava and oil remain exclusively on the future post-P5 generic fluids roadmap; R3 touches no fluid-generalization code.

## R3 visual diagnosis (owner report: little perceived improvement)

The absence of thin-water artifacts confirms the R2 minimum 10 mm finite display threshold. The original full-cell water quads have been removed since R2. However, the 8x6 center-based hydrology mask and the one-neighbor coastal halo remain presentation inputs. The visible green shoreline may also inherit 0.5m terrain mesh tessellation. Thus further increasing water-only sample density without A/B evidence is not approved.

Three mutually exclusive, **render-only** diagnostic user arguments are available (default mode is unchanged):

- `--p5-water-debug=off`: hide derived water MeshInstance3D surfaces, leaving the terrain and all authoritative hydrology running unchanged.
- `--p5-water-debug=ocean-only`: render only authoritative ocean and its clipped one-cell coastal fringe; hide finite surface water and rivers.
- `--p5-water-debug=sources`: show ocean in blue, finite water in bright cyan, rivers in green, and synthetic *visual-only* coastal halo in magenta. This reveals whether a coarse hydro mask/halo or the triangulated terrain is responsible for the visible coastline steps.

Example: `& $godot --path .\\game -- --start-water=ocean --p5-water-debug=sources`. The modes never edit water volumes, reservoir kinds, source snapshots, or save schema. The presenter exposes `visible_coastal_halo_cells`, `visible_refined_coast_quads`, and `water_debug_mode` through `get_visual_metrics()` for reproducible evidence. Diagnostic mode toggles rebuild only derived mesh products; no increase in scheduler or density-sampling frequency is introduced.

Acceptance: compare screenshots at identical seed, camera, and world coordinates in normal, ocean-only, and sources modes before choosing a physically justified change. Leave final GUI approval pending.
