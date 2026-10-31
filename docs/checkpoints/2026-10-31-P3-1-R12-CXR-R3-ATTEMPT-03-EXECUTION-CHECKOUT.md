# P3.1 R12-CXR R3 Attempt 03 Execution-Checkout Addendum

Date: 2026-10-31

## Exact execution checkout and current disposition

This addendum pins the byte-verified execution checkout for the attempt frozen in [the preceding R3 pre-target checkpoint](2026-10-31-P3-1-R12-CXR-R3-ATTEMPT-02-RESULT-ATTEMPT-03-PRETARGET.md).

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Branch: `exp/p3-1-r12-cxr-per-cavity-continuation`.
- Measured code source: `c1dce7e2a410e439dbf82e5252a8e333d0621642`.
- Execution checkout HEAD: `aa9a6dc5c562cd707cacde3e95364941ded076d9`.
- Direct parent: `c1dce7e2a410e439dbf82e5252a8e333d0621642`.
- Tree: `a7eeb56fcd35dd0f6434fab9b04d351715bde18e`.
- The three executable R12-CXR paths (campaign, field-support realizer, contract tests) are byte-identical between measured source and execution checkout. The only difference is the committed documentation/evidence freeze.
- Versioned dispatcher physical SHA-256: `713df38f7f32abd152b17daa28448d2fdd09f996a4f0e89d81d746cb7f49e8dc`.
- One-shot target: `R9.2.SEAM.XPLUS_EQUAL.v1`, phase `r3`, attempt `R3_TARGET_20261031_03`.

The target remains **NOT_STARTED** as of this addendum. This record is committed before process creation. No scenario result is inferred from the preflight or controlled-child test.

## Launch preconditions

Immediately before launch, the dispatcher must confirm the exact origin and execution HEAD above, no tracked source difference from measured source across all three R12-CXR files, exact physical hashes for campaign, realizer, contract tests, Stage-0 fixture, residual fixture and Godot executable, and the manifest/C6/Candidate-D/volume/authority checks performed by campaign `check-only`. It also requires at least 2 GiB free commit, a fresh initially empty target evidence root, exclusive durable reservation, a fresh Godot profile, and the unchanged 45-second process timeout.

The dispatcher writes a durable process-start intent before `Process.Start`, captures the child PID immediately, drains both output streams, and samples `Win32_PerfRawData_PerfOS_Memory` every 500 ms. It terminates the process and returns a resource hard-stop if free commit falls below 2 GiB or if in-run telemetry/evidence writing fails. The controlled-child test verified the sampling path, exit/stdout/stderr, duplicate-reservation rejection, overwrite rejection, no target marker, and confirmed child termination. The exact dispatcher/parser/control evidence and source-gate inventory are in [`r3_pretarget_03`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_03/).

The only target command is the versioned dispatcher in that archive with `-RunFrozenTarget`, `-RepoRoot C:\r12cxr-convergence-20261031`, `-ExecutionCheckoutHead aa9a6dc5c562cd707cacde3e95364941ded076d9`, `-SourceSha c1dce7e2a410e439dbf82e5252a8e333d0621642`, `-AttemptId R3_TARGET_20261031_03`, and the source/input hashes in the preceding checkpoint. The evidence root is newly created, empty, and outside the repository. A launched/uncertain process is never rerun.

After launch, classify only the archived campaign artifact and process record. A pre-geometry failure with `consumes_cx_hypothesis=false` does not establish support-vertex feasibility. Once support candidates/search run, preserve the complete per-cavity and per-level diagnostics; a cap, invalid boundary, incomplete level/search, timeout or missing metric is `PARTIAL`, not finite infeasibility. Continue downstream gates only if the equal-LOD gate fully passes, in the order already frozen by the R12-CXR preregistration. All five F2-G1 holds remain unchanged.
