# P3.1 R4 — Experimental Preregistration

Date: 2026-10-26. This experiment is isolated from production at baseline
`92b442d7f5b605c7bc9c48fac2aceea9d71813aa`. No production integration,
schema change, save access, merge, or Issue #108 work is authorized.

## Questions and arms

This compares three test-only derived representations while the schema-v2
ordered ledger remains the sole authority:

* **A — chunk subledger:** derive a revisioned, sequence-preserving chunk
  projection from the canonical ledger using the production conservative
  min/max density-interval rule and full normal-sampling halo. Persist it as a
  verifiable disposable artifact, then compare cold build, warm read, append,
  restart, corruption fallback, density probes and CPU mesh builds.
* **B — voxel snapshot:** materialize float32 density samples over the complete
  chunk plus sampling halo. Apply appended commands in original sequence to
  every voxel sample; never filter by brush-radius support. Interpolate only as
  an explicitly approximate query/mesh source. Compare resolutions 0.5, 0.25,
  and 0.125 where the frozen workload matrix below allows bounded execution.
* **C — combined:** use A's local operation projection as the source for B,
  with a derived CPU-mesh cache keyed by world/generator identity, chunk/LOD,
  local projection content, snapshot revision/resolution, mesher version and
  halo contract. Validate local invalidation, remote reuse, restart and
  corruption fallback. No derived file becomes authoritative.

## Inputs and scenario identity

The immutable Issue #131/R3B fixtures are copied byte-for-byte from the R3B
experiment and retain their source manifest and checksum inventory. Seed is
`131102026`, generator v1, radius 580 mm, and authored CARVE/FILL sequence is
unchanged. Frozen cases are 0, 256, 640, 2048 and 8192 operations, concentrated
and distributed. The distinct nonperiodic R3C cases use their separately
hashed R3C fixture manifest and exact commands. Each campaign row is keyed by
`scenario_id + architecture_arm + resolution + process_repeat`; no results
from distinct scenarios, resolutions, or processes are pooled into one
percentile.

The selected chunk is `(0,0)` in region `(0,0)` for concentrated workloads and
chunk `(2,2)` in region `(-31,-64)` for distributed workloads. Sampling and
mesh inputs cover the selected chunk's complete horizontal bounds, full
vertical grid bounds, and the production normal-query margin. Global signed
operation sequence and mode are retained exactly.

The R3B frozen set has eight workload IDs (two layouts × 256/640/2048/8192),
with a separate zero-operation control per layout. The R3C nonperiodic set has
eight distinct command-list IDs at the same two layouts/counts. Each ID has
five independent process repeats unless stopped by the timeout rule. Snapshot
spacing is `0.5` for every scenario; `0.25` is additionally measured for
counts through 2048; `0.125` is measured for counts through 256. This avoids
unbounded sample-count × history-count growth while still comparing three
resolutions. The executable manifest will enumerate every scenario/arm/repeat
before launch.

## Run plan and stop-loss

Each measured row runs in a fresh Godot process with a new profile/output
directory. Five repetitions are the target. Run one smoke process per
architecture first. Then measure smaller counts before larger counts. If any
8192 concentrated arm exceeds 600 seconds, retain its output as a right-censored
timeout and do not repeat that arm. If a row exceeds 600 seconds, stop that
row's remaining repetitions; do not remove or replace the attempt. A parse,
integrity, geometry, or recovery failure is retained and does not advance to a
performance claim for that arm. The stop-loss is an operational campaign
limit, not an acceptance threshold.

The benchmark order is counterbalanced by process repeat. Each process reports
its own sample distributions and exactness counts. Campaign summaries report
per-process values, median and range across process medians; they do not pool
all raw samples across processes. Missing/timed-out measurements remain
`null`/right-censored and are not imputed. A scenario is invalid if source,
input hash, process exit, completion marker, expected output cardinality,
ledger ordering, or required exactness/recovery checks fail.

## Preregistered experimental decision criteria

These are prototype-selection criteria only, not owner-approved product
budgets:

1. A and C exact operation projections must preserve sequence and produce zero
   bitwise density mismatches against full canonical replay for all in-domain
   fixed/adversarial probes. LOD0/LOD1 output from the exact canonical path or
   exact cache must match vertex positions, normals and topology exactly.
2. Snapshot B/C must report float32 quantization, surface displacement, normal
   angular deviation, cave/tunnel connectivity, and LOD boundary effects for
   every completed resolution. Snapshot arms are never called exact. Without
   owner-approved geometry tolerances, no snapshot geometry can be accepted for
   production regardless of measured quality.
3. A derived representation is called a useful local-work prototype only if
   at least four of five independent processes complete and its median warm
   retrieval or local incremental update is at least 20% faster than rebuilding
   the same derived representation from the canonical ledger, with no more than
   10% p95 regression in canonical density or CPU meshing on the same row.
   This is an exploratory screen chosen before final runs, not a gameplay goal.
4. Any exactness, ordering, stale-revision, corruption-fallback, or cross-chunk
   revision inconsistency rejects the relevant arm regardless of speed.
5. Hardware FPS, presented frames, GPU completion, VRAM, accepted geometry
   error, shipped RAM/disk, and user latency remain `OWNER_TO_DEFINE` or
   `NOT_MEASURED` unless the available harness measures them directly.

## Metrics

Use Godot monotonic microseconds and process-local elapsed time. Record cold
projection/snapshot/cache construction; warm retrieve; query p50/p95/p99;
operation candidates/visits; snapshot voxel count and bytes; delta update time;
LOD0/LOD1 CPU mesh-build times; serialization, bytes read/written, cache hit
layer, corruption fallback; process memory counter deltas and OS-sampled RSS
when the runner supplies it. These are headless CPU/filesystem data, not GPU or
presented-frame results.

Snapshot geometry comparison uses the canonical continuous SDF and its exact
mesh as reference. For matched surfaces, report symmetric point-to-triangle
distance (both directions), maximum and p50/p95, vertex-normal angular error,
and contour/cave connectivity diagnostics. Resolution-matched results use the
same extraction resolution; quality-matched comparisons are `NOT_COMPARABLE`
until a shared error budget is owner-approved. Voxel grids do not directly
consume immutable production density buffers; any comparison involving a
different field/extraction path is labeled with that limitation.

## Input/artifact hashing

Scenario files are hashed as their exact physical UTF-8 bytes with SHA-256.
The copied R3B/R3C fixture manifests and `SHA256SUMS.txt` are checked against
their recorded source digests before use. Canonical command-list hashes are
SHA-256 over the exact pinned fixture bytes; no reserialization is used as a
substitute. The final evidence inventory is created only after the final
campaign so no future artifact digest is fabricated.

## Owner decision gates

No architecture is adopted by this preregistration. The experiment can
recommend continuing, rejecting, or narrowing an arm. Geometry-error budgets,
frame/FPS goals, production disk and RAM quotas, target hardware, multi-writer
durability requirements, and any product acceptance thresholds remain
`OWNER_TO_DEFINE`. Independent source/evidence review and a separate owner
decision are required before any production work.
