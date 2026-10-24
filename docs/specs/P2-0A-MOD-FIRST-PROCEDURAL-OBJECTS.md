# P2.0A Mod-First Procedural Objects

## Scope and authority

This slice adds two deterministic, static procedural-rock instances per successfully published terrain region to the playable terrain demo. Definitions remain data-only packages loaded by `DeclarativeModLoader` and registered by `ContentDefinitionRegistry`. Both package sources use the same registry, recipe evaluator, placement-record builder and geometry adapter. The mod system does not load scripts.

This is a bounded first vertical slice. It does not add entity persistence, physics, collision, destruction, networking, biome hooks, arbitrary mod scripts, or a generalized ECS. ADR-0002 remains proposed; the custom SDF and the new mesh adapter are not a final backend selection.

## Package discovery

Runtime discovery always includes the bundled `res://mods/first-party` root and the authorized `user://mods` installation root. The source-tree example root at `<repository>/mods/examples` supplies the external example for source checkouts. If a valid `official.example.procedural_rock` package is already registered from `user://mods`, the repository example root is omitted for that run so the same namespaced package is not discovered twice. Other user-installed data-only packages are registered in the same deterministic P0.3 order.

The runtime requires `firstparty.core_rocks:granite` and `official.example.procedural_rock:basalt_stack`. Discovery, schema, dependency, duplicate-ID and engine-version failures are surfaced in the terrain HUD; a required definition is never silently substituted. The existing P0.3 loader remains the sole package validator and does not execute package content.

## Domain records and deterministic placement

`ProceduralObjectWorld` is a node-independent builder. It produces exactly two slot records for a region, one for each required definition. Placement and recipe seeds are derived from the saved world seed, SDF generator v1 and signed region coordinates using bounded integer arithmetic; region traversal order and global random state are not inputs.

Each record contains a stable object ID, definition ID, content pin (package version and definition schema), world ID and seed, generator version, signed region key, integer-millimeter region-local position, explicit placement and recipe seeds, `geological_halfspace_v1` recipe version, four independently derived geometry seeds (`structure`, `fracture`, `wear`, `detail`), the validated declarative geometry profile, and an empty optional `instance_state` boundary. The base recipe seed remains derived exactly as before. The region-local X ranges are separated by slot and remain inside the 16-unit region; Z candidates remain inside the 12-unit region. Each slot has at most 12 deterministic candidate attempts.

For each candidate, the builder samples the canonical `SdfWorld.sample_density` v1 field from above the terrain and finds the first positive-solid crossing in the bounded vertical interval. It refines that crossing with 16 bisections, then rounds the region-local anchor to integer millimeters. Nonfinite or unavailable samples fail region object publication. These placement checks use base SDF v1 only; they do not claim placement against persisted terrain edits.

## Versioned recipe compatibility

P0.3 definition schema 1 plus `stacked_spheres_v1` remains accepted by the registry with its original exact field set and legacy lobe evaluation. It is not fed into the new mesh adapter. The playable required definitions now use definition schema 2 plus `geological_halfspace_v1`; the runtime fails initialization explicitly if a required installed package still supplies an older geometry version. There is no silent reinterpretation or implicit migration. Content pins include definition schema, and the registered recipe algorithm/profile are included in runtime records. Package manifest schema and world-save schema remain unchanged.

The schema-2 recipe has a strict exact-key allowlist: `algorithm`, `profile`, three half extents in integer millimeters, primary/fracture/bevel plane counts, anisotropy axis and milli-scale, weathering milli-scale, and macro/meso/fine roughness amplitudes. The registry and adapter reject unknown/missing fields, invalid bounds, unsafe/nonintegral values and profile/parameter mismatches. Supported profile IDs are `granite_massive_weathered_v1` and `basalt_fractured_anisotropic_v1`.

## Geometry and visual representation

`ProceduralRockMeshAdapter` v3 (`geological_halfspace_v1`) starts with a bounded cuboid and successively clips it by deterministic oriented half-spaces. The resulting primary volume is the intersection of the box and asymmetric structural planes; separately seeded fracture planes make further oriented facets. Each plane normal and support-relative offset is generated from the recipe's respective deterministic integer stream. Basalt fracture normals are biased away from the declared preferred axis, producing strong directionality. Wear planes selectively truncate corners. Polygons are clipped and capped, triangulated, then uniformly subdivided once with a shared-edge midpoint cache. Coherent selective vertex relaxation softens high-curvature edges/corners according to weathering strength; local 3D value noise at three fixed frequencies adds bounded macro/meso/fine roughness. The noise is sampled in local coordinates, shared by position, and capped relative to shortest incident edges. No independent per-vertex random displacement or radial sphere mapping is used.

The granite recipe is a massive, shorter body (`half extents 720/610/680 mm`) with nine primary planes, two fracture planes, four wear planes, weathering 920/1000 and lower roughness. The basalt recipe is taller (`590/820/610 mm`) with eight primary planes, five anisotropic fracture planes, two wear planes, weathering 270/1000 and higher multiscale roughness. These values are exploratory visual profiles, not geology claims or owner-approved art budgets. Every generated mesh must remain a single closed connected shell, have exactly two incident triangles per shared edge, finite outward flat normals, nondegenerate triangles, positive volume, and 100–500 triangles. Its contact base is normalized to region-local `y=0` after deformation. Build failures are surfaced; no corrupt or empty substitute mesh is published.

The seed contracts are independently derived from `recipe_seed` as `posmod(recipe_seed*48271 + discriminator*69621 + 104729, 2147483646) + 1`, using discriminators `0x13579` (structure), `0x2468B` (fracture), `0x3579D` (wear) and `0x468AF` (detail). Primary plane offsets are 0.64–0.84 of directional support; fracture offsets are 0.62–0.82; selected bevel cuts remove 5.5–12% of directional support at seeded corners. Three local-coordinate noise frequencies are fixed at 1.6, 4.7 and 10.2; configured amplitudes are clamped to 7% of the shortest incident edge. This separates deterministic variation domains without claiming cross-platform bit-identical floating-point meshes. Both package sources still use the same registry and adapter; the playable material remains the shared neutral stone material.

`ProceduralObjectStream` owns one visual root per actually published region, with two object nodes beneath it. It keeps no authority over terrain chunks, the edit ledger or save storage. Publication builds the full region's object set before replacing an existing set; repeated same-seed publication is idempotent. Terrain unload frees the region's object root. Reload rebuilds matching identities, pins, placements and mesh data.

The terrain HUD reports visible object count, object-region count, loaded namespaced definition IDs and initialization/publication errors. `V` toggles object rendering without changing records. No collision body is created.

## Terrain edits and persistence

Procedural objects are derived from world seed, generator version, region coordinate, definition pins and recipe. They are not written to schema-1 world saves. The object layer receives no save-store or brush-ledger reference. A later terrain carve/fill does not move, delete or persistently modify an already placed object. It may leave an object floating, partially buried or intersecting edited terrain; unload/reload returns the deterministic base placement. Dynamic terrain following and entity-state migration require a separate authorized slice.

## Verification

Focused command:

```powershell
& $env:GODOT_BIN --headless --path .\game --script res://tests/procedural_object_tests.gd
```

The suite covers shared first-party/external registry and recipe use, strict v1/v2 schema separation, legacy non-reinterpretation, unsupported-profile rejection, installed `user://mods` discovery and duplicate-source avoidance, independent deterministic seed stages, 12-seed variation per family, mesh closure/manifold edges/winding/finite normals/degeneracy/contact base/triangle bounds, signed-region placement and order independence, canonical surface anchoring, stable IDs and content pins, actual terrain scene publication/eviction/revisit, duplicate prevention, visibility toggling, missing/incompatible/legacy required-package failures, unchanged terrain edits and unchanged disposable schema-1 save bytes. `scripts/validate.ps1` includes the focused suite and all existing canonical regression groups.

Initial P2.0A implementation validation on Godot `4.7.2.stable.official.ed1daf0bf`: focused object suite 117 assertions/0 failures; full `scripts/validate.ps1` 17,375 assertions/0 failures across 16 assertion groups. After the owner reported the sphere-like appearance, the adapter v2 geometry correction passed 135 focused assertions and the complete suite at 17,393 assertions/0 failures across 16 assertion groups, exit 0. The correction evidence is recorded in the 2026-10-24 checkpoint. These are headless/source-runtime results; owner GUI visual acceptance remains pending.

The repository test `res://tests/procedural_rock_gallery_capture.gd` produces 12 granite and 12 basalt samples with recorded recipe and stage seeds, three camera projections, fixed light parameters, per-mesh triangle/area/volume/bounds/build-time metrics, and PNGs. The recorded gallery on this implementation produced 312–408 triangles per object (granite median 360; basalt median 384). The CPU adapter build-time median/p95 over 12 samples was 13.955/19.650 ms for granite and 14.711/17.052 ms for basalt on the developer host; these figures are exploratory and do not include engine resource upload, scene publication, renderer/GPU, or gameplay frame cost. The isolated deterministic CPU triangle preview is useful for comparing silhouettes and facets; it is not a Godot renderer screenshot, shadow/GPU measurement, or artistic approval. The images are identified by filename/view and the complete sample/seed map is in `gallery_metrics.json`.

Headless results establish source/runtime behavior only. Owner GUI acceptance is still needed to assess rock scale, silhouette, grounding, granite weathering, basalt anisotropy and readability while moving through regions. No scored performance target is defined.

### Geological geometry replacement — 2026-10-24

The schema-2 `geological_halfspace_v1` generator replaces the earlier fixed-topology radial/lobe mesh with a variable-topology clipped half-space solid. The complete implementation and data-only schema checks are on the existing draft PR #106; this specification update does not change the production world, SDF, persistence, streaming, placement, or object IDs. Schema-1 `stacked_spheres_v1` remains evaluable with its historical meaning but is rejected by the current required runtime adapter until an explicit migration/version update is authored.

Current Godot `4.7.2.stable.official.ed1daf0bf` evidence: focused procedural-object tests 208/208; isolated gallery capture 57/57; full `scripts/validate.ps1` 17,468 assertions/0 failures, exit 0. The validation log is retained outside the repository at `C:\Users\PUBLI\AppData\Local\Temp\p2-0a-validation-rerun-d809be7e4b864265aa7acfceeedfcde8.log` (SHA-256 `EC17831DB727C043BD0F9EE30D9C2D37107E738989AC85F0E5DF3CDBBE68416E`). No assertion failures, parser errors, or script errors occurred in the passing run. The separate declarative registry suite now checks schema-2 output, declared profile/parameters, and independent stage seeds (44/44); this replaces obsolete test expectations for the prior example's `lobes` field.

The gallery contains 12 granite and 12 basalt samples at one shared deterministic seed range and three fixed CPU-preview views. The captured meshes span 312–408 triangles (granite median 360; basalt median 384). CPU adapter construction median/p95 was 13.955/19.650 ms for granite and 14.711/17.052 ms for basalt on the development machine. These are exploratory values, not acceptance budgets; they exclude Godot renderer upload, GPU work, gameplay frame cost and user-perceived performance. The sidecar and PNGs live in `docs/artifacts/p2-0a-geological-rock-gallery/`; their SHA-256 values are recorded in the matching implementation checkpoint. The preview is a deterministic software rasterizer, not an engine-rendered image or owner GUI approval. Owner visual retest and independent source review remain required.
