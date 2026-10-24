# P2.0C — Modular Deterministic Static Population

Status: feature candidate on draft PR #112; independent source review and owner GUI retest pending. This specification records the implementation on source commit `057536f1680d5118e9c9990c137e1812f8cc8244`, parent `84bb7c3e573e7aa5a07608aac7834735aeb2c84f`. It is not merge, art, or release acceptance.

## Scope and authority

P2.0C adds data-only, versioned static-population rules to the P0.3 package loader and deterministic region generator. Package discovery supplies declarative records; no package script, callback, dynamic code, or executable payload is loaded. First-party granite and the external example basalt use the same rule and publication path.

The P2.0B instance-state service remains authoritative for sparse overrides, tombstones, restoration, and seed/generator partitions. Unmodified instances remain derived from world seed, rule pin, region, candidate index, and recipe seed. Terrain world-save schema 1 is unchanged; object state remains in the separate P2.0B store. Issue #108 terrain/object conformance is not implemented.

## Population rule contract

Each `static_population_rule` is schema version 1 and identifies a namespaced rule ID plus a namespaced object `definition_id`. The registry validates the exact field set, referenced definition and package namespace, supported algorithm, integral bounds, transform, distribution and surface subcontracts before atomically registering the package set. Rule IDs are enumerated ordinally and content-pinned by SHA-256 for instance identity.

Supported algorithms:

- `region_grid_density_v1`: extensible deterministic grid population.
- `p2a_compatibility_slot_v1`: narrowly frozen P2.0B compatibility identity/placement records. Its definition, slot, density, transform, distribution and surface fields must match the compatibility contract; changing an ignored field is rejected.

For the generic algorithm, `density_milli_per_region` is an expected-count density in thousandths. Each candidate cell receives a deterministic 0..999,999 ticket; the acceptance threshold is `floor(density_milli_per_region * 1000 / candidate_cell_count)`. This yields approximately the declared expected count without interpreting `2000` as a 100% acceptance threshold. Candidate cells are generated within the declared edge margin at `grid_spacing_mm`, with bounded deterministic jitter. A candidate must meet the rule's minimum separation and conservative object-clearance distance from prior accepted placements. It then must satisfy the declared `top_surface_v1` vertical range and slope constraint using the canonical terrain density surface.

The schema carries `geometry_variant_count`, per-axis minimum/maximum scale in milli-units, and versioned `yaw_uniform_v1` orientation bounds. Granite and basalt rules are data records with distinct scale/slope settings; object geometry remains the already registered versioned recipe and is not reinterpreted by the population contract.

The registry accepts at most 128 population rules. Region generation enforces at most 16 rules per region, 256 candidate cells, 64 surface-anchor samples, and 64 total objects including compatibility instances. Exceeding a cap fails the region result explicitly. Candidate generation and overlap checks use stable sorted rule order and deterministic seed mixing, not package discovery order, region visitation order, a global mutable RNG, or Node3D state.

The distribution reserves a positive edge margin, and tests compare generated footprints in adjacent signed regions. This prevents this slice's sampled placements from straddling half-open region ownership boundaries or overlapping across neighboring regions; it may leave intentionally empty border bands.

## Identity and compatibility

P2.0B compatibility slots preserve their existing instance IDs, placement seeds, recipe seeds, and persisted state resolution. These two legacy representatives remain as a compatibility population while the new generic rule path adds scalable populations. Removing or converting them requires an explicit future migration contract; P2.0C performs no silent migration.

Generic identities use the world/seed domain, namespaced definition, region key, pinned rule identity/schema/algorithm and candidate index. Persistent identity validation rejects a changed or missing rule pin instead of silently resolving a different object. Candidate IDs are checked for collisions across generated signed-region fixtures. Region keys use the existing signed spatial-ownership and half-open ownership contract.

## Rendering and streaming

Immutable, unmodified generic population meshes are combined into one static `ArrayMesh` surface per published region. The builder sorts instances by stable ID, applies each deterministic transform to vertices and inverse-transpose transforms to normals, and rejects invalid arrays, nonfinite transforms or budget overflow. Mutated instances and compatibility objects remain individual representatives so saved per-instance state is not folded into an opaque batch. The batch is presentation only; canonical identity and state stay in the P2.0B service.

Object streaming queues complete region publications and replaces pending work for the same region. It rejects stale publication tokens, removes queued work on unload, preserves hidden-object visibility across visits, and applies the same sparse state resolution to batched and individual instances. Explicit limits are 25 resident regions, 25 pending region publications, one object-region publication/process tick, and a cache of at most 32 immutable geometry variants. A region is built transactionally before its object root replaces the prior root. The terrain streamer remains the owner of region lifetime and terrain state.

## Performance evidence (exploratory)

Godot 4.7.2 headless tests sampled 16 region-generation trials per density and three object-region publications per density. The fixture includes the two preserved compatibility instances, so the mean object count includes them. Measurements are host- and headless-specific and are not approved budgets, rendered-frame timings, GPU completion, VRAM use, or art acceptance.

| Generic density (milli/rule/region) | Generation p50/p95 | Mean / max objects | Mean surface anchors | Publication p50/p95 (3 samples) | Batch build p50 | Peak batch vertices | Static memory before → after |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0.612 / 0.710 ms | 2.00 / 2 | 2.00 | 32.763 / 32.763 ms | 0.041 ms | 0 | 28.575 → 28.588 MB |
| 1,000 | 1.111 / 3.630 ms | 2.88 / 5 | 4.38 | 36.616 / 36.616 ms | 0.040 ms | 2,304 | 28.580 → 28.615 MB |
| 5,000 | 4.342 / 6.095 ms | 6.75 / 8 | 11.63 | 54.431 / 54.431 ms | 2.343 ms | 6,984 | 28.580 → 28.637 MB |
| 10,000 | 8.969 / 12.067 ms | 10.88 / 12 | 21.75 | 59.787 / 59.787 ms | 3.997 ms | 11,592 | 28.580 → 28.666 MB |

These publication samples include geometry build and are too few to estimate a reliable tail. Static memory is the test process's Godot static-memory counter, not operating-system resident memory. No owner-approved density, frame, RAM, VRAM or latency threshold exists.

## Validation and GUI procedure

The exact source commit passed the complete `scripts/validate.ps1` run on Godot `4.7.2.stable.official.ed1daf0bf`: 17,883 assertions in 16 groups, zero failures. The focused object suite is 621/621 and the terrain brush suite is 613/613. Headless tests cover declarative package validation, malformed rules, package/root/region order, positive and negative ownership, density variation, spacing, identity pins, P2.0B persistence/tombstone/restore, batch geometry and bounds, publication queues/stale tokens, seed changes, and terrain regressions. Full raw validation was captured outside the repository; see the implementation checkpoint.

Owner visual retest (not performed by this implementation):

1. Open `game/project.godot` in Godot 4.7.2 and run the main scene (F6/F5 as configured).
2. Verify both granite and basalt appear as multiple static rocks, with visibly varied counts across regions; status should report the object/rule counts and no procedural-object error.
3. Use WASD/arrows to cross several positive and negative region boundaries. Observe rocks arrive with the terrain; revisit a region and verify deterministic identities/placements without duplicates.
4. Press `V` to hide the object layer and again to restore it. This must not change domain state or region placement.
5. Optionally exercise P2.0B F6–F9 on a disposable world to confirm a changed/deleted/restored object remains an individual representative. Do not treat headless persistence assertions as GUI approval.

## Deferred work and limits

There is no physics, collision expansion, multiplayer, persistence migration, time simulation, undo/redo, terrain conformance, or arbitrary executable mod support. The two P2.0B compatibility identities remain fixed by necessity until an explicitly reviewed migration can preserve existing saved records. The per-region generation work is bounded but synchronous; its measured publication cost can produce frame stalls and has no product acceptance budget. GPU completion, rendered image quality, actual memory pressure and owner GUI behavior remain unverified.
