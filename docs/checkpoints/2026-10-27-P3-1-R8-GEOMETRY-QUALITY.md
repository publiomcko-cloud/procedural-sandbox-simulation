# 2026-10-27 — P3.1 R8 geometry quality and spatial conformance

## Identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Evidence branch: `bench/p3-1-r8-geometry-quality`
- Measured source: R7.3 tested SHA `7ad45d8c817ecb0f54a8eec058babce65af287db`, parent `c54f337cb1f2b1e6d1f61de5c1b9d9f3031e892d`
- R7.3 evidence HEAD: `87c9c6f30c613e73ad572670cadb253ab06483eb`
- Production reference: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable hash `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`

## Event

Issue #157 authorized an isolated, test-only R8 geometry diagnostic. A new harness was added under `game/tests/prototypes/`; no production terrain, persistence, scene or schema source was changed. The six ordered phases completed on pinned R7.3 source. All three input manifest digests matched. The existing R7.3 inventories were rehashed independently with 50/50 and 37/37 files matching. R7.3's later external FILL/CARVE recipe summary passes after reproducing Godot binary32 coordinate arithmetic; the earlier derived checker that reported false remains preserved, as do the raw 21/21 zero-failure Godot scenario results and independent R7.3 review.

## Findings

- FILL accounts for centerline indices 1–4 as solid: these lie inside the frozen radius-0.58 fill. Indices 5–31 are open in canonical and A/B/C. A 0.125-grid field flood finds the seeded open centerline samples in one component and the seeded component connected to +X, not the intentionally filled −X probe; exterior air remains a separate component. The extracted mesh agrees on the sampled centerline slice, but no 3D flood through mesh triangles was performed. Across 27 open slices with 32 radial directions each, the narrowest sampled candidate radial diameter is 1.820563 units (canonical 1.839999); this is not a certified continuous minimum-clearance bound.
- Normal endpoint-angle maxima remain 33.621° for CARVE and 87.736° for FILL/CARVE after repair. A FILL/CARVE triangle in cell 712 has face winding opposite the canonical outward gradient (`dot=-0.468217`), unchanged by repair. These are unresolved geometry observations, not accepted tolerance failures.
- All 9,512 shared-face scalar samples match bitwise. Twelve of sixteen actual chunk contour comparisons match; four X+ interfaces with LOD1 on the negative-side chunk have two unmatched segments (33 vs 35). All hit/miss probes agree, but X− hit locations differ by up to 0.366092 world units.
- Resolution sweeps show reduced canonical-SDF residual proxies at finer spacing with sharply higher build time and mesh storage. A coarse 0.5 FILL/CARVE mesh centerline probe differs from the canonical sampled sign at index 4. All resolution and geometric-error data remain exploratory.
- Computational two-sided ray oracle matches 72/72 hits; 36 sphere-contact probes retain up to 0.013811 world-unit discrepancy. No PhysicsServer, rendered or GUI measurement was made.

The first full Godot validation passed 21 suites / 21,464 assertions / zero failures; after adding a sampled minimum-ray-width output, the final full validation also passed 21 suites / 21,464 assertions / zero failures, exit 0, in 648.216 seconds. The final focused R8 diagnostic exited 0 in 139.588 seconds and emitted six valid exploratory phase records; assertion count was zero by design. Three non-fatal colinear camera warnings occurred in procedural object tests.

## Evidence and disposition

Raw attempts 001–020 and both full validation runs (validation-001 and validation-002) are preserved in `docs/reports/P3-1-R8/evidence/evidence-bundle.zip`, with nested artifact hashes. The isolated Godot user-data profile was not included in the published archive and contains only disposable validation data. Detailed source identity, metrics, limitations and next questions are in [R8 results](../reports/P3-1-R8/RESULTS.md); the diagnostic rules are in the [R8 spec](../specs/P3-1-R8-GEOMETRY-QUALITY-DIAGNOSTICS.md).

**Disposition:** `P3_1_R8_READY_FOR_INDEPENDENT_REVIEW` of the diagnostic evidence only. The observed winding/contour/normal/picker differences prevent any inference of production geometry acceptance. No tolerance, production adoption, Issue #108/#154 work, merge or release is approved. All five F2-G1 holds remain unchanged.
