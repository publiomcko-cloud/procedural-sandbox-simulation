# P1.1A — experimental LOD 0/1 transition fixture

**Status:** experimental source/test fixture; not production LOD, not a backend decision, and not performance acceptance.
**Approved architecture:** [P1.1 R2](../roadmap/P1-1-APPROVED-PLAN-R2.md).
**Implementation branch:** `feat/p1-1a-lod01-transition-fixture`, based on `f42f9dbdd54809df202a81b4aa59ed0d1f377a2e`.

## Scope boundary

This fixture is pure GDScript CPU data. It is not connected to `terrain_demo.tscn`, the production region streamer, production mesher publication, collision, or a scheduler. It reads the existing SDF v1 and an immutable snapshot of the existing ordered brush ledger. The fixture neither changes that field/ledger nor accepts histories larger than the canonical 256-command cap. Its request identity carries seed, generator version, ledger revision, global LOD0 lattice origin, and selected transition faces; stale revision identity is rejected by the test contract.

No LOD 2 is implemented. Although `h(L)=0.5·2^L`, the current chunk Z span is 3 world units, so an LOD2 step of 2 does not tile a chunk by an integer number of cells. Grouping/retiling needs its own contract.

## Grid and sample authority

- Region span remains 16×12 in XZ; chunks remain 4×3; vertical bounds remain [-2, 8].
- LOD0 step is 0.5 and LOD1 step is 1.0. Positions come from global integer lattice indices, never chunk-local rounding. `floori` gives the same half-open ownership semantics at negative coordinates.
- An LOD1 cell origin represented in LOD0 lattice indices must be even in X, Y, and Z, including negative indices. Transition and LOD1 reference builders reject any odd component before sampling; the public coarse-interface helper returns an empty array for that invalid request. LOD0 reference cells remain valid at any LOD0 lattice origin.
- At shared lattice positions both resolutions call the same SDF v1 sampler. Edited samples replay the same global carve/fill snapshot in sequence order. The fixture validates snapshot seed/version/types/array lengths and the 256-operation cap.
- Compact edit snapshots require integer seed/version/revision metadata, a nonnegative revision at least as large as the retained command count, equal packed-array lengths, finite centers inside the canonical world-coordinate bound, finite radii within the ledger's canonical min/max, and only CARVE/FILL mode bytes. Invalid metadata or commands fail with a stable reason; production ledger semantics are unchanged.
- Surface normals are sampled from that same canonical field using a fixed 0.25-world-unit central-difference offset, equal to the current production LOD0 normal probe distance.
- Nonfinite density from the SDF or an experimental override fails the whole fixture build with `valid=false`. This includes field evaluations made by the central-difference normal probes; no partial vertex, normal, or timing payload is returned as a successful mesh.

## Transition construction

One transition volume is one LOD1 cube (1×1×1 world units) anchored at an even LOD0 lattice index. One to three non-opposing faces can be selected in either orientation. Each selected face is divided into four LOD0 quads and split using the face diagonal induced by the production six-tetrahedron cube decomposition. Its opposite face uses the single LOD1 quad and the same production diagonal. The test derives the production boundary triangles from `MarchingTetrahedra.TETRAHEDRA` and compares them against both interface resolutions in all six orientations.

The lateral polygon boundaries include any midpoint required by a selected LOD0 face. Each lateral face is triangulated with a face-center fan. A cell-center vertex is then joined to each boundary triangle, producing a conforming tetrahedral complex. The SDF is evaluated at those shared boundary points and the cell center; marching tetrahedra over that complex generates the transition surface. This changes only the derived transition tessellation, not the SDF samples/ledger. The finite fixture's exterior boundary remains open by design.

The proof combines complementary checks rather than treating sample equality as seam proof:

- Internal transition surface edges that do not touch the exterior cell boundary have incidence exactly two; degenerate and duplicate triangles are rejected.
- On every supported internal fine/coarse interface, the isosurface segment set from the transition surface exactly matches the segment set generated directly from the adjacent LOD face triangles.
- Independent seam tests also construct neighboring uniform LOD0 and LOD1 reference meshes with a nonlinear synthetic field at signed X/Y/Z coordinates. They compare contour segments extracted from those generated mesh boundaries and compare endpoint normals against the transition cell for a face, edge, and corner. The expected result comes from separate neighboring meshes, not only from the transition fixture's interface-triangle helper.
- Tests cover negative-orientation face/edge/corner junctions and their positive-orientation corner mirror, signed-world origins, winding toward the empty side, duplicate-position normal equality, canonical finite-difference normals, a canonical SDF tunnel wall, a synthetic cave-like cross-section, and a deterministic sub-grid feature that disappears as expected.
- A matched LOD0 (2×2×2 cells) and LOD1 (one cell) six-tetrahedron reference is produced for the same unit domain and seed. Canonical density residuals at generated vertices are reported as exploratory geometry measurements; they have no approved acceptance tolerance.

These tests prove the bounded single transition-cell templates and their supported face/edge/corner interfaces. They do not prove an arbitrary large mosaic of independently selected LOD cells, a production streamer, edit invalidation, worker publication, GPU behavior, or an atomic world snapshot.

## Tests and benchmark method

Run the experiment through the project validation command with the pinned engine:

```powershell
$env:GODOT_BIN = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& '.\scripts\validate.ps1'
```

The fixture test adds deterministic LOD0/LOD1 sample parity, invalid request/snapshot rejection, face/edge/corner topology, cave/narrow-feature, revision identity, and 0/1/32/128/256 concentrated plus 256 distributed ledger replay cases. The benchmark uses seed `424242`, warmup 2, 12 measured repetitions per case, one CPU transition/reference cell, and a disposable `ArrayMesh` construction per measured repetition. It separately reports transition-boundary setup, SDF/ledger vertex sampling, tetrahedral triangulation, normals (including their six canonical SDF probes per vertex), `ArrayMesh.add_surface_from_arrays`, packed-array payload estimate, triangles, and build p50/p95/p99/max. With 12 samples, p99 is effectively a near-maximum order statistic and is exploratory only.

Packed-array bytes estimate counts only vertex+normal payload plus a small per-sample estimate; it excludes Dictionary/Array/object overhead and allocator peaks. No frame percentile, GPU time, upload completion, peak allocation, or target-hardware comparison is claimed. The environment used for the recorded run is Windows 11 Pro build 22631, Godot `4.7.2.stable.official.ed1daf0bf`, Intel Xeon E5-2690 v4 @ 2.60 GHz, 14 cores / 28 logical CPUs, about 64 GiB physical RAM. Renderer/GPU profiling is not exercised by headless validation.

The owner has not approved FPS, memory, geometric-error, normal-angle, or fine-feature preservation thresholds. All measured timings and density residuals are exploratory; final performance/geometric acceptance remains pending.

## Explicitly not claimed

- This is not production LOD selection, streaming, persistence, collision, or visual/GUI acceptance.
- No Voxel Tools binary, GDExtension, third-party dependency, P1.1B/C, ADR-0002, or F2-G1 operation is used or authorized.
- The source-reviewed P1.0C feature remains intact; no gameplay scene, canonical SDF, ordered ledger semantics, or P1.0C production mesh path is changed.
- All F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
