# Issue #108 — Phase A Grounding Characterization Results

Status: **PHASE_A_COMPLETE / GATE_A_PASS / PHASE_B_READY_NOT_STARTED**

Base main: `6b018412d992d37dbe4f4d526214fd6cde464849`

Qualified experimental HEAD before this results-only commit: `38b21ca05b8b2bc8be4e5107c8b0f9ce7e59587b`

No production runtime file was modified in Phase A.

## Qualification

Exact-head GitHub Actions:

- Starter checks #42203926411: SUCCESS
- Issue 108 Phase A characterization #42203926415: SUCCESS
- Canonical validation: PASS
- Procedural object regression: `PROCEDURAL_OBJECT_PASS: assertions=673 failures=0`
- Grounding characterization: `ISSUE108_PHASE_A_PASS: assertions=79 failures=0`
- Half-space characterization: `ISSUE108_PHASE_A_HALFSPACE_PASS: assertions=77 failures=0`
- Contact formula characterization: `ISSUE108_PHASE_A_CONTACT_FORMULA_PASS: assertions=27 failures=0`

## SDF convention

Characterization confirms the current canonical convention:

- positive density = solid;
- negative density = empty;
- terrain subtraction/carve uses the minimum of terrain density and cutter density.

At the sampled terrain surface, density changed from approximately +0.10 below the surface to -0.10 above it. A cutter center with density -0.25 therefore produces empty space under `subtract_solid_v1`.

## Placement anchor and embed

Across first-party granite, external basalt and an independent synthetic geological profile, each with six deterministic seeds:

- generated CPU geometry retained `local minY = 0`;
- the persisted placement anchor remains the base/contact anchor;
- terrain interaction does not require identity or position migration;
- `embed_depth_mm` is an effect-space downward offset from that anchor.

The transform matrix also exercised identity plus two yaw/non-uniform-scale combinations. Phase B must apply the resolved object transform to the same pure shape descriptor used for the terrain effect.

## Simple-envelope rejection

The following recipe-only contact envelopes were compared against the actual deterministic CPU-geometry section at the declared embed plane:

| Candidate | Mean coverage | Minimum coverage | Mean candidate/actual area | Maximum candidate/actual area |
| --- | ---: | ---: | ---: | ---: |
| L2 ellipsoid | 2.44% | 0.00% | 0.532 | 0.616 |
| L4 superellipsoid | 31.42% | 8.51% | 1.002 | 1.123 |
| L8 superellipsoid | 65.90% | 32.26% | 1.165 | 1.317 |
| nominal recipe box | 79.12% | 45.16% | 1.202 | 1.363 |

No simple candidate reached the required 99.5% minimum coverage.

**Decision:** `recipe_envelope_v1` must not be implemented as AABB, ellipsoid or fixed superellipsoid.

## Half-space-derived envelope

The second probe reconstructed the deterministic convex half-space core directly from:

- recipe parameters;
- structure seed;
- fracture seed;
- wear/bevel seed.

It uses the same box, primary-plane, fracture-plane and bevel-plane construction rules as `geological_halfspace_v1`, but remains a pure analytic/domain representation rather than a renderer mesh.

Across 18 profile/seed samples:

- mean uninflated contact-point coverage: 57.19%;
- mean minimum inflation required for complete observed contact coverage: **10.648 mm**;
- maximum minimum inflation required: **16.981 mm**;
- mean area ratio with the minimum observed inflation: **1.0384**;
- maximum area ratio with the minimum observed inflation: **1.0562**.

This is substantially tighter than generic recipe envelopes.

## Roughness guard

Inflating every plane by the full configured roughness-amplitude sum is conservative but too broad:

- granite configured amplitude: 72 mm;
- basalt: 101 mm;
- synthetic profile: 60 mm;
- coverage: 100% across all 18 samples;
- mean area ratio: **1.2830**;
- maximum area ratio: **1.4393**.

That policy could carve 28–44% more contact area than the measured geometry and is rejected.

The generator already caps per-vertex coherent roughness displacement by:

`min(configured_amplitude, shortest_incident_edge * 0.07)`

A characterization proxy for this existing cap produced:

| Profile | Mean guard proxy | Maximum guard proxy |
| --- | ---: | ---: |
| granite | 26.47 mm | 29.48 mm |
| basalt | 27.02 mm | 32.02 mm |
| synthetic | 27.21 mm | 31.41 mm |

These values remain above the measured 16.981 mm worst observed contact deviation while being far tighter than the configured-amplitude sums.

**Frozen Phase-B policy:** build a shared pure recipe-shape descriptor that derives the exact conservative roughness guard from the same pre-render geometry/topology and existing `shortest_edge * 0.07` safety rule. The terrain system must consume that descriptor; it must not inspect `Mesh`, `MeshInstance3D` or rendered triangles as authority.

## Blend semantics

Phase A freezes the contact blend as `interior_eased_subtract_v1`.

For terrain density `T`, cutter density `C` and blend radius `R`:

1. if `C >= 0`, return `T` unchanged;
2. otherwise compute hard subtraction `H = min(T, C)`;
3. if `-C >= R` or `R == 0`, return `H`;
4. otherwise compute `w = smoothstep(0, R, -C)` and return `lerp(T, H, w)`.

The 80-case characterization proved:

- exactly zero influence outside the cutter;
- continuity at the cutter boundary;
- exact hard subtraction once cutter depth reaches the blend radius;
- output always remains between original terrain and hard subtraction.

This intentionally places the blend transition **inside the object volume**, not outside it. Therefore `blend_radius_mm` cannot create an exterior carved ring/moat by construction.

Current interaction data also satisfies `blend_radius_mm <= embed_depth_mm` for the three characterized profiles.

## Phase-B frozen geometric contract

`sdf_ground_imprint_v1 / recipe_envelope_v1` shall mean:

1. reconstruct a deterministic analytic convex half-space core from the same versioned recipe and geometry seeds;
2. ground the descriptor to the same local base contract used by geometry generation;
3. add a deterministic conservative guard derived from the generator's existing safe roughness-displacement cap, through a shared pure descriptor;
4. apply the resolved object transform and `embed_depth_mm`;
5. evaluate the cutter analytically in effect space;
6. compose it with terrain through `interior_eased_subtract_v1`;
7. apply it after ordered/materialized player CARVE/FILL as required by `terrain_edits_then_imprint_v1`.

Renderer nodes and meshes remain derived outputs and are never terrain authority.

## Baseline performance

Three repetitions were executed on the final qualified experimental HEAD. Median headless values:

- initial 3x3 window: **5507.941 ms**
- unedited full-window reload: **5639.557 ms**
- edited/materialized full-window reload: **6758.442 ms**
- interior visible edit: **151.167 ms**
- X seam visible edit: **186.136 ms**
- XZ corner visible edit: **186.152 ms**
- Z seam visible edit: **130.916 ms**
- 12-edit same-area burst: **227.310 ms**
- picker total: **1.987 ms**

The Phase A branch changes no runtime source, so these values are characterization/reference data rather than evidence of a Phase-A runtime regression. Earlier exact-runner repetitions on the same experimental source showed materially lower values; CI runner load is therefore a significant source of variance. Phase B performance comparisons must use repeated same-runner measurements and owner GUI latency checks rather than a single CI sample.

## Gate A verdict

**PASS.**

The following uncertainties are resolved sufficiently to begin Phase B:

- SDF sign/subtract direction;
- anchor and embed semantics;
- rejection of AABB/Lp simple envelopes;
- analytic half-space core;
- conservative roughness-guard policy;
- no-exterior-moat blend semantics;
- mod-first independence from concrete content IDs.

Phase B may implement the pure effect schema/evaluator and shared recipe-shape descriptor.

Phase B has **not** been started by this experiment. No effect store, terrain composition, persistence change, entity lifecycle change or `terrain_interaction_applied=true` behavior exists yet.
