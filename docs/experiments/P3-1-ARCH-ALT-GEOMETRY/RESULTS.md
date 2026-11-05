# P3.1 architecture-alternative geometry experiment — results

Status: SHARED_SURFACE_PASS__TRANSVOXEL_PARTIAL_TEST_HELPER_BLOCKED

## Frozen scope

- Base: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` (`feat/p3-1-scalable-terrain-storage`)
- Experimental line: `exp/p3-1-arch-alt-transvoxel-shared-surface`
- R6 line: `exp/p3-1-r12-cxr-r6-realization-map-cavity` — untouched
- PR executor: #223, draft, no merge authorized
- Authoritative input and gates: `PROTOCOL.md`
- Final geometry run used for adjudication: GitHub Actions run `42010850538`, head `3d1cdc3e366f11fca4a599faea036ef8c42cfbc9`

The frozen input is the exact R6 target family: seed 131102026, generator v1, X+ seam at x=16, and the ordered FILL/CARVE radius-0.58 commands recorded in R9.2.

## Alternative B — shared-surface seam authority

Verdict: **PASS / HIGH VIABILITY**

Environment: stock Godot 4.7.2.

Job: `127189200347`.

Pre-registered gates: **12 assertions, 0 failures**.

Observed result:

- mesh triangles: 659
- unique global lattice-edge roots: 369
- seam edges on x=16 after finite-ROI exterior exclusion: 22
- seam edges with invalid incidence: 0
- seam edges contributed by both region sides: 22/22
- T-junctions on the seam: 0
- duplicate emitted triangles: 0
- emitted degenerate triangles: 0
- degenerate polygonization candidates rejected before emission: 3
- root identity consistency: PASS
- deterministic second-build signature: PASS
- mesh signature: `-397fb42b15775d93`

Evidence artifact: `shared-surface-evidence`, artifact id `13406174525`, SHA-256 `03bb457b8e0002ed1b25e9656e4c98fd19706570ad95ca3eb7b5eca857b286f4`.

### Interpretation

The current R6 problem is not an unavoidable consequence of the canonical SDF or the ordered edit ledger. The exact failing-family edits can be polygonized across the region boundary without a crack when boundary root identity and boundary triangles are owned by one world-space geometry authority instead of reconstructed independently by adjacent regions.

This is architectural evidence, not merely a new cavity candidate. It removes the region seam as an independent triangulation agreement problem for the frozen target.

The successful prototype keeps the existing domain model intact:

1. canonical world-space SDF remains authoritative;
2. ordered edit ledger remains authoritative;
3. persistence remains command/data based rather than mesh based;
4. region streaming remains a publication/lifetime concern;
5. **boundary geometry ownership moves above individual regions**;
6. region interiors may still be generated independently, but a seam/slab authority generates shared boundary roots and triangles once and publishes/partitions them to the neighboring region renderers.

## Alternative A — canonical SDF into Voxel Tools 1.7 Transvoxel

Verdict: **PARTIAL WITH POSITIVE INTERNAL GEOMETRY EVIDENCE / PUBLIC TEST HELPER BLOCKED**

Environment: Voxel Tools 1.7 custom Godot build reporting Godot 4.7.2.

Job: `127189200854`.

The project SDF and exact edit snapshot were successfully copied to a float32 `VoxelBuffer` with the sign inversion required by the Voxel Tools SDF convention.

Observed regular mesh:

- vertices: 147
- triangles: 198
- finite: PASS
- degenerates: 0
- deterministic repeat: PASS
- signature: `-3c4aeb85bcdd219d`

The exact +X face at x=16 had 14 sign-changing lattice edges, so the frozen field genuinely intersects the requested transition face.

The public `VoxelMesherTransvoxel.build_transition_mesh()` test helper did not yield an inspectable ArrayMesh. The runtime log shows Godot 4.7 rejecting the helper's custom vertex array while `add_surface_from_arrays` executes:

- `PACKED_BYTE_ARRAY` type condition failure
- `Invalid array format for surface`
- `add_surface_from_arrays` failure

Pinned Voxel Tools 1.7 source explains why this is **not evidence of an empty Transvoxel transition**:

- the method is explicitly marked `Only exists for testing`;
- it returns before creating an ArrayMesh when internal transition vertex count is zero;
- the observed failure occurs later, at `mesh->add_surface_from_arrays(...)`;
- therefore the native Transvoxel builder had produced a non-empty internal transition vertex set;
- its helper converts `LodAttrib` into `PackedFloat32Array` and places it in `Mesh::ARRAY_CUSTOM0`; Godot 4.7 rejects that custom-array representation at the helper boundary in this run.

Because the final transition ArrayMesh could not be inspected, the pre-registered requirements for non-empty **final** transition mesh, finite output, and zero emitted degenerates are not all independently demonstrated. Alternative A is therefore not promoted to PASS.

Evidence artifact: `transvoxel-evidence`, artifact id `13407430253`, SHA-256 `973237296ef452c166e075d7200234a8182433fa491f4c03b8665a9af4c7e418`.

## Tooling corrections retained as evidence

Earlier runs are not used as scientific failures:

- run 42010343686: direct script execution lacked the Godot script-class import cache; shared probe also had an explicit typing parse error;
- run 42010512186: project import fixed class resolution; shared geometry passed all topological gates but the harness mislabeled three rejected degenerate candidates as emitted degenerates; Transvoxel's requested transition face was mapped one sample away from x=16;
- run 42010696469: text-only harness corrections introduced parse errors and did not reach geometry;
- run 42010850538: clean adjudication run.

None of these corrections changed the frozen seed, ordered edits, seam plane, acceptance topology, or R6 branch.

## Decision

**Adopt the shared-surface boundary-authority architecture as the lead path for the next integration experiment.**

Do not merge this experimental PR into the R6 line. Do not rewrite or delete the R6 evidence. The R6 campaign remains useful as evidence that independent per-region boundary realization is expensive and brittle for this target family.

Recommended next integration sequence:

1. Extract the successful seam/slab authority from the probe into a data-only terrain service.
2. Make adjacent region meshes consume boundary roots/triangles by immutable boundary snapshot/revision rather than recomputing them.
3. Re-run the exact R9.2/R6 target plus cross-region edit/reload/unload cases.
4. Add mixed-LOD qualification. Prefer either:
   - a shared high-resolution boundary collar with LOD transition owned by the same authority; or
   - a production Voxel Tools/Transvoxel adapter after bypassing/fixing the test-only ArrayMesh helper.
5. Benchmark remesh latency, memory, worker contention, and determinism before production adoption.

No production architecture is changed by this experiment. The successful version is preserved on an isolated success branch.
