# P3.1 R5-E — Exact Local Projection Experiment

Status: experimental, not production. Base source is R4 final
`051249642611a7fa9cd2006be450bad0e184e4ee`, which itself carries the R4
research prototype. Production authority remains `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.

## Hypothesis and bounded candidate

R4 chunk subledgers preserve exact ordered commands, but concentrated 8,192
history retains all 8,192 terms. This experiment tests a guarded axis-dominance
short circuit inside the canonical ordered CARVE/FILL replay. It skips a
distance square root only when one component exceeds the current scalar cutoff
by a conservative 0.1% guard; otherwise it executes the canonical Vector3
distance and min/max. No operation is omitted by brush radius, no command is
reordered, and the global schema-v2 ledger remains the sole authority.

The 0.1% guard and comparison methodology are experimental implementation
details, not a cross-platform floating-point proof. Every accepted exactness
claim is limited to the pinned Godot 4.7.2 runtime and tested fixture.

## Frozen workload and comparison

Use R4 frozen command bytes and R4 source measurements, especially
`P31.R4.EDIT.CONCENTRATED.N8192.v1` (8,192 distinct alternating CARVE/FILL
operations). No inputs or R4 evidence are regenerated. Exact prototype
measurements include 789 deterministic density probes, chunk LOD0/LOD1 meshes,
normals, topology, region-boundary probes and cave-field probes. Existing R4
five-process results remain the canonical/subledger/uniform-voxel/cache
comparison. New R5-E runs are exploratory, single-process instrumentation and
are not pooled with the R4 five-run series.

## Preregistered decision rules

1. Any density, normal, position, topology, picking, ordering, signed-boundary,
   or cave mismatch rejects the exact candidate.
2. A useful acceleration candidate must reduce same-scenario query p95 by at
   least 20% against the R4 canonical full replay and must not regress LOD0 or
   LOD1 p95 by more than 10%. It must also complete the same cache/restart and
   invalidation checks as R4. This is an exploratory selection screen, not an
   owner-approved product budget.
3. No number of locally indexed terms is represented as a speedup when all
   8,192 operations remain mathematically relevant to the queried chunk.
4. At most one final process per frozen scenario is run unless a source defect
   makes the result invalid; no result is rerun to erase a failure.

## Metrics and stop-loss

Capture R4 projection build/filter, append, serialize/reload, cache-key/cache
lookup, density query p50/p95/p99, LOD0/LOD1 CPU construction, picker and
operation candidate counts. Capture the R5 candidate's no-op-axis skip count,
exact-distance evaluation count and CPU mesh callback timings. The R4 CSV has
five independent process repeats for the source baseline; this R5-E prototype
has a single focused 8,192-operation process. A run over 600 seconds is kept as
right-censored and is not repeated. Headless time is never called presented FPS
or GPU completion.

## Explicit limitations

The exact-distance short circuit has not been shown to accelerate meshing; the
full R4 candidate list is still replayed in original order. The 8,192 concentrated
history remains a worst-case linear replay. Cache restart/corruption and remote
invalidation are covered only by inherited R4 evidence unless a new R5-E test
explicitly records them. No production path, schema, save, or Issue #108 code is
changed.
