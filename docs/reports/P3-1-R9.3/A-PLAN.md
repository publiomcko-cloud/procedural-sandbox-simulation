# R9.3-A preregistration — bounded corrective hypotheses

Baseline evidence head: 9c2b187abc93b155a2546d66035b8075390bd451; measured candidate source: 8b59f32a854a89826fbe2ecd7998ed2e6347ba0c. Frozen R9.2 manifest SHA-256: 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972. Candidate is test-only.

## Hypothesis order
1. Shared-face open-edge failures arise from inconsistent ownership/caching of roots that are mathematically the same global lattice edge. Test canonical unordered endpoint identity plus independent oracle comparison; do not change the 1e-12 squared-cross-product cutoff.
2. If H1 is insufficient, exact-zero and near-zero classifications create inconsistent root inclusion at adjacent cells. Test endpoint ownership and exact-zero rules without changing the SDF.
3. If H2 is insufficient, the cropped-ROI topology oracle is counting/omitting the wrong edges. Validate with explicit ROI boundary classification and an independently enumerated contour.
At most two implementation revisions per hypothesis; preserve every failed result.

## Frozen limits before execution
Reuse only R9.2 frozen workload rows and ROI dimensions. One warmup and five measured samples per row; at most two independent campaign processes. Per scenario 60 s; aggregate campaign 600 s; grid nodes 10,000; unique samples 10,000; triangles 20,000; external process-tree peak 512 MiB. Stop immediately at any limit. No geometry tolerance or degeneracy-threshold changes. Exact source identity recorded per process.

Required comparison: neighbor pair, equal X+ seam, known X+ defect, historical X- displacement, triangle 3103 probe, canonical CPU ray grid, zero/CARVE/FILL-CARVE and local rebuild. Cave mesh connectivity remains NOT_IMPLEMENTED unless an actual extracted-mesh empty-space oracle is added and independently validated. No GUI/GPU/presented-frame claims.