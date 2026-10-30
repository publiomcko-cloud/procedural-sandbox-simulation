# R10-B4 attempt result — canonical Steiner projection worsened topology

Attempt `B4-STEINER-20261030-1460333`; source SHA `0aa6295cb2864767819e8de268c1e7af7b32f1eb`. Result `FAILED_TARGET`, process exit 0, no script errors.

The pinned A3 method selected 8 parent polygons for canonical-field Steiner subdivision. All 8 projections were finite and returned valid under the method's existing, non-owner-approved `1e-5` convergence parameter. Maximum observed displacement was `0.000102956255432218` world units; maximum source-triangle-plane residual was `0.000101522644399665`; maximum absolute final canonical density was `4.8112869263095e-06`. The largest observed residuals are evidence only, not accepted tolerances. All 24 child triangles had `cross_squared <= 1e-12`, so the fixed cutoff rejected all children. The scalar volume bytes remained unchanged.

The output mesh had 654 triangles, 13 internal open edges, 73 ROI-boundary edges, zero nonmanifold edges, zero emitted degenerates and zero winding errors; 72 required adjacencies were missing and 24 cutoff rejections remained. The 24 child squared-cross values ranged from `9.69596215898221e-18` to `1.26863282249104e-13`, all below `1e-12`. This is worse topology than the A6 baseline (655 triangles, 10 internal open edges, 21 missing adjacencies, 7 rejections). The frozen ray control remained 0/25 disagreements; controls were 6/6. Mixed LOD was skipped because the equal-LOD gate failed.

Evidence root: `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B4-STEINER-20261030-1460333\B4-STEINER-20261030-1460333_geometry`.

| Raw item | SHA-256 |
|---|---|
| Attempt JSON | `8b46696508753868ebbebc4deb6f234090396629b5285ecadf528cd0fe0877ca` |
| Stdout | `670c16756466f67114ce9f372303add28ba1167846348c08a4a60fac219d9ba1` |
| Stderr | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Process record | `e3838d8282b646703dde3ce8c8b4fb96b4cc25b572e37ecb046634214544f6fd` |

The attempt rejects this specific centroid-plus-canonical-SDF projection strategy for the frozen defect: splitting the narrow faces generated smaller rejected children and additional missing adjacency. It does not invalidate other geometry or topology strategies.
