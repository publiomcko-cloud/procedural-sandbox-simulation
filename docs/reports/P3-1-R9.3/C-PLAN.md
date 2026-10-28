# R9.3-C preregistration — bounded Surface Nets correction and smoothing study

Baseline evidence head: 074177074e7888018f52c96073587967c823b6ed; measured candidate source: 3e314f927cff5ca8a52c853bc5b504b8b3d86109. Frozen R9.2 manifest SHA-256: 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972. Candidate is test-only.

## Hypothesis order
1. Missing/internal open edges arise when primal-edge quads are omitted because one neighboring sign-active dual cell has no vertex. Trace ownership and every missing dual cell; correct cell/quad ownership only.
2. If H1 is insufficient, one triangle of a quad is rejected at the unchanged 1e-12 squared-cross-product cutoff, leaving a topological hole. Test deterministic alternate diagonal selection only when both candidate triangles meet the unchanged cutoff and winding invariants.
3. If topology passes, compare three smoothing arms without arbitrary crack hiding: none; normal-only averaging (positions unchanged); bounded SDF-constrained movement with explicit displacement report and no acceptance threshold. Do not modify the frozen manifest; use the four exact frozen fixtures as a separately identified 12-arm study.

## Frozen limits before execution
Reuse R9.2 frozen rows/ROIs. One warmup plus five samples per frozen row; at most two independent campaign processes. Smoothing study: 3 variants × 4 fixtures = 12 arms, one warmup and five samples each, at most two processes. Per arm/scenario 60 s; aggregate process 600 s; grid nodes 10,000; triangles 20,000; external process-tree peak 512 MiB. Stop immediately at limits. Keep the production degeneracy threshold and all geometry oracles unchanged. Report cave throat/connectivity only where an independently validated extracted-mesh oracle exists; otherwise NOT_IMPLEMENTED.