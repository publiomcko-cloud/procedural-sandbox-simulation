# P3.1 R3A — Ledger, Derived Mesh Cache, and Density Snapshot Prototype

Date: 2026-10-26  
Classification: disposable, test-only experiment; not a production decision.

## Authority and scope

The schema-2 ordered terrain ledger is the sole authority for accepted CARVE/FILL operations. Every cache or snapshot in this experiment is disposable derived state. A missing, stale, corrupt, or mismatched derived artifact must be rebuilt from the ledger or rejected; it must never hide, reorder, delete, or replace ledger operations. No production files, schemas, user saves, PR #129/#134, or Issue #108 implementation are changed.

This prototype compares:

* **A — exact replay pruning + LOD1:** a test-only conservative squared-distance no-op bound around the existing ordered `min`/`max` replay and the existing LOD0/LOD1 CPU mesh builders. The command order and each operation's mathematical result are retained. It is not a candidate production patch.
* **B — persistent derived CPU mesh arrays:** a test-only content-keyed file cache for generated vertex/normal arrays. The key binds source world/seed/generator, complete ordered ledger identity, region/chunk, LOD, mesher/normal dependency and settings; payload integrity is checked. It does not cache `ArrayMesh`, GPU state, renderer publication, or gameplay state.
* **C — incremental volumetric density lattice:** a test-only `Float64` density lattice at 0.5 world-unit spacing. Initial grid nodes and each accepted ordered delta are evaluated with the same CARVE/FILL min/max operation. The grid itself is exact at stored nodes, but trilinear values between nodes are an approximation to the continuous canonical SDF and are explicitly **not equivalent**.

No alternative was integrated into production. No thresholds or acceptance budgets were invented. All numbers are exploratory CPU/filesystem measurements from one machine and one campaign process.

## Frozen input contract

The harness consumes byte-identical input artifacts from Issue #131 / PR #134. Their source manifest SHA-256 is `2dff9ccd5b98e1ea722051b25f961ff8f64c3ae698f3bc12102826e04ec3088d`; the source `SHA256SUMS.txt` digest is `ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1`. A verified local copy of all 23 referenced files is under `game/tests/fixtures/p3_1_r3a/issue131/`. The campaign's expanded manifest is retained with the raw results.

The edit matrix is 256, 640, 2,048, and 8,192 operations for both concentrated `(region 0,0; chunk 0,0)` and distributed histories. Seed `131102026`, generator v1, 580 mm radius, even sequence CARVE and odd sequence FILL. LOD samples use region `(-31,-64)`, chunk `(2,2)`, levels 0 and 1, three candidate repetitions. The separate cave control uses the canonical SDF and ledger evaluator in region `(0,0)`, chunk `(0,2)`, nine fixed centerline probes. Exact ordered command bytes and their SHA-256 values remain in each frozen input artifact; no regenerated or substituted workload is used.

## Reproduction

With Godot `4.7.2.stable.official.ed1daf0bf` and an isolated disposable profile, from the repository root:

```powershell
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path .\game --editor --import
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path .\game --check-only --script res://tests/prototypes/p3_1_r3a_benchmark.gd
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path .\game --script res://tests/prototypes/p3_1_r3a_benchmark.gd
```

The last command runs the full 9-row prototype matrix; it is not part of `scripts/validate.ps1`. Output roots must be unique and must not point at a user world. The retained campaign manifest and source hashes should be checked before comparing a later run. Use separate runs and report distributions per scenario/machine for statistically stronger conclusions; this campaign's 3 mesh repetitions and single campaign are not a multi-process p95/p99 qualification.

## Interpretation limits

* Times are Godot headless CPU work and disposable local filesystem activity. No `ArrayMesh` publication, GPU completion, presented-frame timestamps, gameplay FPS, VRAM, or visual acceptance is measured.
* The SDF grid C is exact only at its stored nodes. Interpolation, polygonized vertex normals and tunnel connectivity differ from the continuous SDF; node-level or selected-mesh coincidences do not prove geometric equivalence.
* The mesh-cache warm path is only useful when its full content key hits. This prototype's whole ordered-ledger key causes global invalidation after edits, so locality is not achieved. Cache files consume additional disk and require quotas/eviction policy, versioning, atomic writes, crash recovery and dependency-halo correctness before production use.
* The exact replay optimization in A tests every operation and only conditionally avoids a square root. It is equivalent in tested probes and mesh vertices, but adds substantial per-operation test overhead for concentrated histories. It is rejected as implemented.
* The snapshot incremental update proves exact grid-node replay for the tested single delta and restart; it does not make continuous interpolation exact, preserve all off-grid SDF queries, or prove exact cave/seam/picker behavior. No lossy compaction is approved.

## Recommendation

Do not promote this prototype to production. Reject C as a replacement for continuous canonical SDF evaluation. Do not adopt A in its tested form. B is the only potentially useful bounded direction, but only as a disposable cache that remains subordinate to the ledger and uses chunk-local dependency-complete keys, quotas, durable invalidation, and exact rebuild fallback. First profile a more efficient exact ordered replay for concentrated local histories; retain full-ledger parity as the oracle. A separate owner-approved implementation ticket and independent review are required before any production change.
