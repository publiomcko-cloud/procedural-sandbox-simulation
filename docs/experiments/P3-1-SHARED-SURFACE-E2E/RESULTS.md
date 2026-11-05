# P3.1 shared-surface authority — E2E results

Status: **E2E_PASS_FOR_QUALIFIED_MESHING_AND_PERSISTENCE_PATH**

## Identity

- Parent success commit: `4de772ecaa86639e98be41ed031447e82ba5851c`
- E2E branch: `exp/p3-1-shared-surface-e2e-integration`
- Successful code HEAD: `65f362f9f6110a5341077d9c7ea15832f66d675d`
- Draft PR: #224
- Godot: 4.7.2 stable
- Successful GitHub Actions run: `42015547893`
- Job: `127205069959`
- Evidence artifact: `shared-surface-e2e-evidence`
- Artifact id: `13408758062`
- Artifact SHA-256: `1d27fdd067591c4f7f91c89bb4fdc5cfa08b308df8418b4cb22b3d1c902c3fe8`

The R6 branch was not modified.

## Verdict

The shared-surface boundary-authority architecture is **proven E2E for the qualified meshing/data path**.

Final campaign: **48 assertions, 0 failures**.

This is stronger than the prior isolated proof. The reusable service now survives production-resolution chunk generation, worker execution, real ArrayMesh publication, mixed LOD through an explicit boundary-collar policy, schema-v2 persistence, process-style unload/reload, and a cross-region edit.

## Proven properties

### Exact R6 replay

The exact R9.2/R6 frozen input at 0.25 resolution passed:

- 659 triangles
- 369 global root identities
- incidence 2 across the x=16 seam
- zero T-junctions
- zero duplicate emitted triangles
- zero emitted degenerate triangles
- deterministic/global root identity preserved

Scientific signature: `-1281931ba97ed3f3`.

### Production regional seam

All four X+ boundary chunk pairs between regions `(0,0)` and `(1,0)` were generated at the production 0.5 sample step by worker-compatible jobs.

Before the cross-region edit:

- total regional seam edges: 102
- bad incidence: 0
- T-junctions: 0
- every seam edge had contributors from both region sides
- complete boundary signature: `-198271e4e12eb8ad`

CPU results for both sides successfully published to real Godot `ArrayMesh` resources.

### Mixed LOD

The qualified policy is:

> Region-edge chunks are forced to LOD0. LOD1 begins one chunk inward, so the existing LOD transition mesher meets the shared fine boundary collar away from the regional seam.

Eight internal LOD1→LOD0 seams were exercised across the four z chunk rows, on both regions.

Before and after the cross-region edit:

- total mixed-LOD seam edges: 204
- bad incidence: 0
- T-junctions: 0
- cross-owned edges: 204/204

The first E2E attempt exposed four one-sided edges caused by a ~1e-6 root-position discrepancy. The LOD transition mesher canonicalized crossed-edge endpoint order before interpolation while the new boundary authority did not. After making the shared authority use the same endpoint ordering before `lerp`, all eight mixed-LOD seams closed exactly.

This is an important architectural invariant: **root interpolation order is part of the boundary contract**, not an implementation detail.

### Persistence and unload/reload

Schema-v2 persistence was exercised twice.

Generation 1:

1. save frozen ledger;
2. drop live ledger/store objects;
3. create a fresh store;
4. restore the ledger;
5. rebuild all four boundary pairs.

The complete boundary signature reproduced exactly.

A fixed cross-region FILL edit at `(16,1.75,7)`, radius `1.25`, was then applied:

- one ordered command appended;
- revision incremented once;
- boundary geometry signature changed to `03581ab4cb2ca3d6`;
- regional seam remained closed;
- mixed-LOD collars remained closed.

Generation 2 was saved, unloaded and restored through another fresh store. The final rebuilt signature was again exactly `03581ab4cb2ca3d6`.

A persistence integration defect was discovered during the campaign: `get_meshing_snapshot()` contains only in-memory overlay operations and is therefore not suitable for a restored storage-backed ledger. The boundary authority now creates immutable pair snapshots by merging the existing per-chunk persisted-query snapshots, preserving ordered operations after reload.

## Architecture demonstrated

The viable architecture is now:

```text
canonical SDF + ordered global edit ledger
        |
        v
per-chunk persisted-query snapshots
        |
        v
SharedSurfaceBoundaryAuthority
  one sample volume for adjacent region-edge chunk pair
  one global lattice-edge root cache
  one polygonization authority
        |
        +--> left region boundary chunk CPU mesh
        +--> right region boundary chunk CPU mesh
        |
        v
existing ArrayMesh publication / region lifetime infrastructure
```

For LOD:

```text
LOD1 interior -> existing transition cells -> LOD0 boundary collar
                                             ||
                                  shared regional seam
                                             ||
                                      LOD0 boundary collar
                          <- existing transition cells <- LOD1 interior
```

## Scope boundary

This PASS does **not** yet mean the default interactive `terrain_demo.gd` scheduler uses the new pair authority. The E2E exercises the actual SDF, ledger, persisted chunk snapshots, worker pool, mesh CPU data and ArrayMesh publication, but the live scene still schedules ordinary chunks independently.

Therefore:

- algorithmic/meshing E2E: PASS
- persistence/rebuild E2E: PASS
- mixed-LOD policy: PASS
- live interactive scene integration: NOT YET ADOPTED

The next step for a playable manual test is to add an experimental runtime coordinator that schedules adjacent boundary chunks as one pair job and forces participating edge chunks to LOD0, while retaining the old path behind a switch.
