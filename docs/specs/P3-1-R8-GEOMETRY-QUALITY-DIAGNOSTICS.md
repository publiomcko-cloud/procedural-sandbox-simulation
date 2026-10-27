# P3.1 R8 Geometry Quality Diagnostic Contract

**Status:** bounded experimental diagnostic for Issue #157; no production geometry contract is adopted.

## Source boundary

- Pin the test-only experiment to R7.3 tested source `7ad45d8c817ecb0f54a8eec058babce65af287db` and preserve its frozen gates.
- Compare canonical SDF v1 values and immutable ordered edit recipes against isolated A/B/C experimental fields and meshes.
- Use only disposable CPU fixtures. Do not instantiate production terrain nodes, mutate canonical source, modify saves or change established acceptance rules.
- Record hashes of executable, input manifests and relevant source files before measurements.

## Diagnostic observations

1. **Cave:** compare all 31 frozen centerline samples and cross-sections with canonical density; classify FILL-solid samples separately from open samples. Flood-fill the bounded sampled volume with documented six-neighbor connectivity. Track the seeded tunnel component, both signed-X boundary probes and exterior-air component separately. Also query the extracted mesh centerline; do not infer 3D mesh connectivity from field voxels or a line alone.
2. **Normals/winding:** compare neighboring-cell endpoint normals before/after repair, canonical finite-difference outward gradients, winding, degeneracy at the fixed `1e-12` squared-cross rule and repair ownership. Report distributions and locations; no pass threshold is defined here.
3. **Chunks:** construct explicit signed-coordinate adjacent actual chunks at same and mixed LOD, with and without a frozen boundary edit. Compare bitwise canonical field samples, extracted plane-contour segments, T-junctions, normals and picker hit/miss plus hit positions. Distinguish adaptive-cell interfaces from chunk interfaces.
4. **Resolution:** sweep uniform spacing `0.5`, `0.25`, `0.125` in a bounded field region. Report sample/mesh counts, attribute bytes, CPU construction time, SDF residual proxy, normal angles and finite crop topology. These are not acceptance thresholds and do not assert GPU/frame performance.
5. **Collision:** compare a two-sided triangle-ray oracle against canonical SDF ray intersections and compare sphere-center contact using point-to-triangle distance. Label this computational geometry only; do not represent it as Godot PhysicsServer or production collider evidence.

## Failure and interpretation rules

- A fully emitted diagnostic record can be `DIAGNOSTIC_COMPLETE` with zero assertion count; this means measurements completed, not that geometry passed.
- Preserve raw failures and prior attempts. Do not change frozen inputs, thresholds or geometry to improve the report.
- Scalar equality is insufficient to claim matching extracted topology; hit/miss equality is insufficient to claim hit-position parity; finite crop boundaries are not evidence of a watertight closed object.
- Any performance, displacement or normal values remain unscored pending owner-approved hardware, geometry tolerances and runtime methodology.

See [R8 results](../reports/P3-1-R8/RESULTS.md) and the [dated checkpoint](../checkpoints/2026-10-27-P3-1-R8-GEOMETRY-QUALITY.md).
