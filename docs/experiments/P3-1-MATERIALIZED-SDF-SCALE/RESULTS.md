# P3.1 — Materialized SDF scalable-world qualification

Status: **LOAD_AND_FIDELITY_CANDIDATE_READY_FOR_STRESS_TESTING**

Qualified implementation HEAD before this report: 638e69e0948bb61952cac5ea358446d241b7c03d

## Goal

Remove historical edit count from the normal gameplay recovery path while preserving the current rendered terrain surface and the shared regional boundary.

Architecture:

~~~
append-only ordered edit journal
        |
        +--> audit / rebuild history (cold path)
        |
live bounded edit tail
        |
checkpoint / spatial compaction
        v
float64 materialized SDF tiles at production 0.5 m lattice
        |
lazy spatial tile load
        |
shared-surface boundary authority + region meshers
~~~

The mesh is disposable output, not world authority.

## Qualified evidence

GitHub Actions run: 42028437203
Job: 127248417971
Godot: 4.7.2.stable.official.ed1daf0bf

Frozen shared-surface E2E was rerun first and passed: **48 assertions, 0 failures**.

The materialized-SDF qualification then ran **4,096 deterministic edits** with a checkpoint every 128 edits and passed:

MATERIALIZED_SDF_SCALE_PASS: assertions=45 failures=0

Observed hosted-run evidence:

- 4,096 accepted edits
- 32 journal/checkpoint segments
- lifetime count after reload: 4,096
- hot tail after checkpoint/reload: 0
- hot world open: **253 us**
- hot open journal reads: **0**
- hot open tile/pointer reads: **0**
- first cold chunk snapshot: **2,217 us**
- warm chunk snapshot: **123 us**
- cold chunk lookup: at most local 3x3 pointers/tiles; **0 journal reads**
- LOD0 materialized vs complete-ledger oracle: **0.0 max vertex-position error**
- LOD1 materialized vs complete-ledger oracle: **0.0 max vertex-position error**
- shared-boundary oracle/materialized signature: 5c64afa7ec47cf5a
- seam bad incidence: **0**
- seam T-junctions: **0**
- duplicate triangles: **0**
- geometrically crossing seam edges: **71/71 cross-owned**
- valid tangent contacts: **2**, incidence 2, no topology defect
- archive audit: **4,096/4,096 edits accounted for**
- generated world storage in this bounded stress fixture: **10,756,642 bytes**
- resume at the former 65,536-edit boundary succeeds
- edit **65,537** is accepted
- sequence space is limited by the safe integer representation, not by the old 65,536 ledger cap

## Scalability property

Normal world open is independent of historical journal replay. It reads one bounded head record and lazily resolves materialized tiles only when a chunk is requested.

Chunk recovery cost therefore depends on local materialized data plus the bounded uncheckpointed tail, rather than on total world age.

Historical journal segments remain append-only for audit/rebuild but are not part of normal gameplay loading.

## Fidelity contract

The materialized store keeps float64 SDF samples on the current production lattice (TerrainChunkGrid.SAMPLE_STEP = 0.5).

The tested rendered LOD0 and LOD1 geometry is position-identical to the uncompacted complete-ledger oracle after repeated checkpointing and fresh-store reload.

Shared-surface boundary geometry is also identical between compacted and uncompacted paths.

Off-lattice historical SDF samples are reconstructed by trilinear interpolation. Therefore this qualification guarantees the current gameplay-lattice/rendered-surface contract; it does **not** claim bit-identical continuous historical SDF at every arbitrary sub-lattice coordinate.

## Exact-zero topology correction

The 4,096-edit stress exposed an exact-zero lattice degeneracy that did not exist in the smaller fixture.

The final policy is half-open: SDF == 0 is classified on the empty side inside the shared-surface tetrahedral authority. Coincident triangles are deduplicated by canonical world-space geometry rather than by lattice-edge root ID.

Diagnostics distinguish true region-boundary crossings from manifold tangent contacts. Bilateral ownership is required for geometric crossings; a tangent contact is valid with incidence 2 and no T-junction.

## Performance boundary

The load path is qualified for gameplay-scale latency on hosted CI, but checkpoint/compaction is currently a synchronous API. The 4,096-edit qualification spent about 22.0 s total in 32 checkpoints (~5.37 ms amortized per edit). Individual checkpoint calls can be much larger than the amortized value.

Before this store is wired into the interactive scene, checkpoint preparation/write/commit must be scheduled outside the main gameplay frame or under an explicit frame-time budget.

This result therefore qualifies the **storage/recovery/fidelity candidate**, not final interactive runtime integration.

## Stress invocation

The qualification reads SCALABLE_EDIT_COUNT and currently accepts values up to 20,000 in the checked-in harness.

PowerShell example:

~~~powershell
$env:SCALABLE_EDIT_COUNT = "4096"
& "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path game --script res://tests/experiments/materialized_sdf_scalability_qualification.gd
~~~

Raise the count for stress runs without changing acceptance gates. The machine CPU, RAM, storage and test duration are the practical limits; a finite test count is not the architectural edit limit.

## Next gate

Before playable adoption:

1. move checkpoint/compaction off the gameplay critical path;
2. integrate TerrainScalableSdfState and the materialized store into the world lifecycle;
3. integrate shared boundary scheduling into terrain_demo.gd;
4. run long edit/load/unload/restart stress on target hardware;
5. run world-fidelity probes after repeated compaction generations;
6. measure frame-time impact while edits and streaming occur concurrently.
