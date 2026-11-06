# Issue #108 — Phase A Grounding Characterization

Status: experimental characterization only. No terrain runtime integration is authorized by this branch.

Base: `main@6b018412d992d37dbe4f4d526214fd6cde464849`.

## Questions

1. Confirm the canonical SDF sign convention and `subtract_solid_v1` direction.
2. Confirm the procedural rock mesh anchor contract (`local minY = 0`) across profiles and seeds.
3. Measure how far deterministic wear/roughness can exceed nominal recipe half-extents.
4. At the declared `embed_depth_mm`, compare the actual CPU-geometry contact section with recipe-only analytic candidates:
   - L2 ellipsoid;
   - L4 superellipsoid;
   - L8 superellipsoid;
   - nominal recipe box.
5. Exercise yaw and non-uniform scale transforms while retaining the same persisted placement anchor.
6. Decide whether a simple recipe-only envelope is defensible before any runtime SDF integration.

## Matrix

Profiles:
- first-party granite;
- repository external basalt example loaded explicitly as test data;
- independent synthetic geological profile with no first-party dependency.

Seeds: 1, 17, 101, 31337, 91234, 777777.

Transforms:
- identity;
- yaw 45°, scale 0.9/1.1/1.2;
- yaw 173°, scale 1.3/0.8/0.95.

## Candidate criterion

A simple envelope is only marked as geometrically qualified when its contact-section point coverage is at least 99.5% for every sampled profile/seed. Among qualified candidates, lower mean candidate-area / actual-convex-hull-area is preferred.

This is intentionally conservative. Passing does not authorize runtime integration; failing means Phase A must continue with a half-space-derived analytic envelope experiment.

## Non-goals

- no terrain edits;
- no effect store;
- no `terrain_interaction_applied=true`;
- no runtime SDF composition changes;
- no persistence/schema changes;
- no entity lifecycle changes.

## Baseline

The workflow also executes canonical validation, procedural-object regression and three repetitions of the existing runtime performance baseline so Phase B, if later authorized, has an exact pre-integration reference.
