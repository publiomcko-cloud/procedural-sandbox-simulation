# R10-B3 attempt result — constrained-Delaunay local optimum retains the defect

Attempt: `B3-LAWSON-20261030-E4BA97C`  
Source SHA: `c4d60e93e38a17d4b27be8e2f86e61ddf67481a1`  
Result: `FAILED_TARGET`; process exit 0, no script errors.

B3's frozen 25-ray control and all six controls passed, but the equal-LOD target did not change: the deterministic Lawson scan examined 182 edge keys, made zero flips, and stopped at `CONSTRAINED_DELAUNAY_LOCAL_OPTIMUM_RETAINS_SUBCUTOFF` in 33 ms. The emitted target mesh was 655 triangles with 10 internal open edges, 73 ROI-boundary edges, no nonmanifold edges, no degenerate emitted triangles and no winding errors; 21 required adjacencies were missing and 7 fixed-cutoff required triangles were rejected. The minimum cross-squared remained `1.67075673894024e-16`, below the unchanged `1e-12` cutoff. The source graph and revision-2 A6 volume identities passed. The mixed-LOD gate was correctly skipped because the equal-LOD gate failed.

This establishes only that the registered constrained-Delaunay Lawson rule selected no strictly non-Delaunay internal edge in this source triangulation. It does not show that another triangulation or topology can satisfy the frozen geometry contract.

Evidence: `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B3-LAWSON-20261030-E4BA97C\B3-LAWSON-20261030-E4BA97C_geometry`.

| Raw item | SHA-256 |
|---|---|
| Attempt JSON | `49b1e39a8cdf3886ceda5a0900fbdc0a2fee954a106a0573b25b2fad641cb76c` |
| Stdout | `e979ad2008b044ea5f4ac3ff11e17f5684b81f9f139fd5be7e4d6756bde8bebf` |
| Stderr | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Process record | `43f96bfe827c547e724b45265e55f2c13daa00278be695b22230319ec6087538` |
