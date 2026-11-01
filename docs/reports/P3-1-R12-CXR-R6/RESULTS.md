# P3.1 R12-CXR R6 results

**Issue:** [#218](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/218)  
**State:** D0 complete; R6-A–F implementation and target attempts pending.  
**Target attempts consumed:** 0 of 5.

## D0 — frozen R5 baseline diagnosis

Corrected D0 ran on source `b09c3b552246aa49cc27189b3756981683a067aa` in the owner workspace using Godot 4.7.2 binary SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. The process exited 0; stderr was empty. It wrote its result with `target_attempt_consumed=false`.

The frozen inputs passed all hash and materialized-volume checks. D0 visited 3,072 tetrahedra and recorded 1,666 zero-facet vertex occurrences, 370 binary32 world positions, and 662 triangulated zero facets. Independent barycentric residual recomputation classified 144 residuals at or below `1e-8`, 952 above `1e-8` through `1e-7`, and 570 above `1e-7`. A further 524 occurrences failed the unchanged barycentric gate. R6-A's representability correction is required; the epsilon is unchanged.

The frozen cavity projected area is `0.0000118685684531578`; it has zero positive-area overlap with either of its seed owner triangles. D0 found these five cavity boundary edges unrealizable above the unchanged strict cutoff `cross_squared > 1e-12`: `1-2`, `2-3`, `3-4`, `4-5`, `0-5`. Direct topology arcs `1-4` and `2-4` also have continuous maxima below cutoff in their adjacent subregions. This blocks the frozen R5 cavity only. No global infeasibility claim is made.

The corrected D0 result is [result.json](evidence/d0/corrected/result.json), 2,487,941 bytes, SHA-256 `a9c2d7e5ba96437f7f470e278141d53e98194ab6720a3591e5b9fe67d66a691e`. The corresponding process capture is [process.json](evidence/d0/corrected/process.json); raw stdout and stderr are preserved beside it. The complete D0/preflight evidence inventory contains 26 files and is pinned by [SHA256SUMS.txt](evidence/d0/SHA256SUMS.txt), hash `a150f8634fd0d2e96232fc43a720356b2e416127df2531057d6a1a8090d56fc2`. The first D0 process/result are preserved under `superseded-instrumentation`: its instrumentation looked up `field_residual` while the frozen validator returned `residual`, and so misclassified failures. It is excluded from the corrected scientific result.

## Gates and limitations

On the corrected source, isolated cold import, R6 campaign/check-only, R6 contract/check-only, and the R6 contract suite passed; the suite reported 23 assertions and zero failures. The R5 suite (348 assertions) and R12-CXR suite (216 assertions) passed earlier on the immediately preceding source. Every gate is implementation-agent evidence; no independent source review or owner GUI result is implied. Full project validation and all downstream geometry gates have not run.

R6-A must first correct each representable zero-set point using the bounded same-tetra search and unchanged field/barycentric gates. Continue with R6-B geometry-owner selection, R6-C ordered topology paths, R6-D finite manifold/boundary-realizable cavity search, R6-E support synthesis and R6-F constrained triangulation. Cavity search caps remain 12 removed faces, 10,000 visited states, queue size 2,000 and 30,000 ms; hitting a cap is `PARTIAL`. The next target attempt requires new source and exact-SHA preflight. No production integration, architecture adoption, merge, release, Issue #108/#154, or F2-G1 activity is authorized.
