# P3.1 R8.3-A — bounded X+ seam experiment

Test-only experiment for Issue #163, measured on source commit `94b2d68d5292d2aa9db7586df7ad58266fd1ff36` (direct parent `4f08b67522507bd196a74a1089c773f272235343`). The report and evidence are published through draft PR [#165](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/165), based on the R8.2 branch. No production geometry or acceptance threshold was changed.

- [Results and bounded causal analysis](RESULTS.md)
- [Measured source and tool hashes](SOURCE_SHA256SUMS.txt)
- [Raw evidence inventory](evidence/SHA256SUMS.txt)
- [Immutable checkpoint](../../checkpoints/2026-10-28-P3-1-R8.3-A-XPLUS-SEAM-EXPERIMENT.md)

The `evidence/profile/**` directory is preserved locally as the isolated Godot user-data profile and excluded from the published checksum inventory. The evidence inventory excludes itself. Attempt 001 is retained as a failed parser check for the first diagnostic-script revision; no frozen acceptance scenario was executed in that attempt.

This experiment's `MINIMAL_FIXTURE_REPRODUCED` means the fault and bounded candidate limitations were reproduced. It does not mean a seam repair passed. The track is blocked at the first sequential gate; the mixed-LOD repair, same-LOD, neighboring interfaces and inherited R7.3 regressions were not run on a repaired implementation.
