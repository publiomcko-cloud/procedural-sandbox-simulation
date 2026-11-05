# P3.1 architecture-alternative geometry experiment

Status: PREREGISTERED / EXPERIMENTAL / NO PRODUCTION ADOPTION

## Isolation

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Experimental branch: `exp/p3-1-arch-alt-transvoxel-shared-surface`
- Frozen base: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` (`feat/p3-1-scalable-terrain-storage`)
- The R6 line `exp/p3-1-r12-cxr-r6-realization-map-cavity` is not modified, rebased, merged, or used as the implementation base.
- This base is the direct ancestor of the R6 line before the later R7-R12/R6 geometry campaigns.

## Frozen failing-family input

Both alternatives replay the exact project SDF and ordered edit ledger identity used by the R6 target family:

- seed `131102026`
- generator version `1`
- seam plane `x=16`
- region pair `(0,0) -> (1,0)`
- ROI `min=(15,1,6), cells=(8,8,8), step=0.25`
- edit 0: `FILL center=(8,1.17898154258728,5.10309219360352), radius=0.58`
- edit 1: `CARVE center=(8,1.17898154258728,5.92309236526489), radius=0.58`
- equal-LOD target: `R9.2.SEAM.XPLUS_EQUAL.v1`
- mixed-LOD target family: `R9.2.SEAM.XPLUS_MIXED_LOD.v1`

No synthetic replacement field is permitted as acceptance evidence.

## Alternative A — canonical SDF -> Voxel Tools Transvoxel

The project remains the authority for SDF and ordered edits. Samples are copied to a float32 `VoxelBuffer`; sign is inverted only at the adapter boundary because the project uses positive-solid while Voxel Tools uses negative-inside. `VoxelMesherTransvoxel` then builds the regular fine mesh and the +X transition mesh.

Pre-registered PASS gates:

1. Voxel Tools classes are present in the pinned Godot 4.7.2 + Voxel Tools 1.7 build.
2. The exact frozen field has at least one zero crossing on the +X transition face.
3. Regular mesh is non-empty, finite, and has no degenerate triangles.
4. +X transition mesh is non-empty, finite, and has no degenerate triangles.
5. A second construction from the same frozen input produces the same regular and transition signatures.

A pass establishes representability and deterministic construction for the frozen mixed-LOD interface. It does not by itself authorize replacing the production backend.

## Alternative B — shared-surface seam authority

A single geometry authority samples and polygonizes a global slab crossing `x=16`. Root identity is keyed by global lattice edges and cached once. Region ownership is attached after construction rather than permitting each region to reconstruct the seam independently.

Pre-registered PASS gates:

1. Exact frozen edit snapshot is accepted.
2. The surface intersects `x=16`.
3. Every non-exterior surface edge lying on `x=16` has total triangle incidence exactly 2.
4. Every such edge has contributors from both sides of the region seam.
5. No root on the seam lies in the interior of another seam edge (T-junction gate).
6. No duplicate or degenerate triangle is emitted.
7. Each global root identity maps to exactly one quantized position identity.
8. Deterministic repeat produces the same mesh signature.

A pass proves that changing boundary ownership can eliminate the region seam for the exact frozen target while retaining the existing canonical SDF/ledger. It is not yet proof of arbitrary mixed-LOD mosaics; if it passes, the next stage must combine this seam authority with an explicit LOD collar/transition policy.

## Decision rule

- If Alternative A passes and B fails: retain the project domain/storage/command architecture and investigate a Voxel Tools/Transvoxel terrain adapter.
- If B passes and A fails: retain the custom mesher path but move boundary geometry authority above individual regions and continue with an LOD-collar experiment.
- If both pass: prefer the option that closes the mixed-LOD seam with fewer new invariants; run a second integration/performance campaign before architecture adoption.
- If both fail: preserve evidence and do not modify R6; the architectural hypothesis is not supported.

All results, including tooling failures, must be recorded. No experimental branch is merged by this campaign.
