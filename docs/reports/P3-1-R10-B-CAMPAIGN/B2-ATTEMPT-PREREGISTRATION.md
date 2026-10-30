# R10-B2 attempt preregistration — expanding local cavity

Status: frozen before the B2 geometry invocation. This is one experimental hypothesis; it does not adopt a geometry tolerance or production design.

## Attempt and source pin

- Attempt ID: `B2-CAVITY-20261030-F32193A`.
- Hypothesis string: `R10B2_EXPANDING_LOCAL_CAVITY_EXACT_RETRIANGULATION`.
- Implementation commit: `f32193acb2cf550832a121391243c3364b2ddd22`; parent `eae562eb310d44cd6b5208eaee744d893a4139e7`; tree `fca6244aa5ff7a8a485756b14fb6cedac7a2729a`.
- B2 realizer Git blob `49ce15779f07331a17de8b4fc2a10f69456cb52b`, physical SHA-256 `5ecadfbefeb3f3fa4c6aae831b3cbd1ef4b1fd4e6ce576c2c79abb8e8098a823`.
- Shared B1 realizer Git blob `100ea9bee0644d879e8197ea5b063ea1df64a46d`, physical SHA-256 `3601d45652efc420429b5306b1c1102af1e2d008e9d5d73b3004c44bd1667eb9`.
- Campaign physical SHA-256 `d9d1090e8dc1ffc1f4de4816b62231b5314746253f5e92471c46d94eb59e7e94`; runner SHA-256 `a10ed1d064f1ee75ea91752cf8d16d1d0a50d8a5a895c586502f110a7344bb13`.
- Candidate D, manifest, R10-A authority, corrected ray source and fixture pins remain exactly as in B1 preregistration. Their physical SHA-256 values are: `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`, `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`, `feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216`, `b61dab953ee3048e1e1a666daf32ddb21d964b3ccd44c3616825b13360097af1`, `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7`.
- Godot binary SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

The corrected source has passed standalone `--check-only` and graph-only contract at implementation SHA `f32193acb2cf550832a121391243c3364b2ddd22`, with exit 0 and no script errors. Graph contract preserved the frozen A6 source-graph counts and the baseline output still has 10 internal opens. The following documentation-only preregistration commit does not change GDScript. Before launch, repeat `check-only` and `graph-contract` on the final preregistration HEAD; runner `process.json` is the authority for actual execution SHA and all physical pins.

## Frozen case and seed state

B2 uses the exact `R9.2.SEAM.XPLUS_EQUAL.v1` manifest row and source A6 volume. No command, center, radius, seed, generator version, ROI, scalar sample, root coordinate, root identity, or canonical threshold is modified. Input identity remains the A6 source topology graph SHA `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`, volume SHA `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`, payload SHA `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`, revision 2, component `60,8,25|tet:0`, 73 source roots, 34-edge fixed boundary and 110 faces. The immutable control set remains six cases; the ray gate is rebuilt from `R9.2.RAY.CANONICAL_PICKER.v1` and its own `CAVE_SMALL` volume rather than borrowing the seam row's ROI.

## Strategy and bounds

B2 performs deterministic breadth-first edge-flip search only in an expanding face cavity seeded by the A6 sub-cutoff faces. The allowed face set grows by shared-triangle adjacency at rings 0, 1, 2, 3, and 4. A flip is legal only when both incident faces are inside the current cavity. The 34-root outer boundary is therefore preserved by construction. Each move is still a 2-2 diagonal flip over a strictly convex projected quad, with the same nonlocal projected-crossing check, orientation, root-set, full mesh incidence, winding and strict 3D cutoff checks as B1. Every ring restarts from the exact A6 source triangulation; no partially searched state is used as a later ring's input.

Global campaign caps across all rings: 4,096 unique states counted across ring searches (including each ring's initial state), 4,096 maximum frontier, 15,000 edge keys examined (including illegal/rejected keys), and 90 seconds solver wall time. The runner adds its existing process timeout/resource stop. Any cap reached yields `EXACT_ROOT_CAVITY_SEARCH_INCONCLUSIVE`, not infeasibility. A fully exhausted result proves only no qualifying realization within this exact flip family and rings 0–4. B1 is not rerun.

## Required result gates

Keep `cross_squared > 1e-12` unchanged. Require exact A6 input/root/boundary/volume identity, no internal open or nonmanifold edges, no degenerates, no winding defects, no missing required adjacencies, all 25/25 frozen ROI ray outcomes, six controls, and the separately executed mixed-LOD interface check if equal/ray gates pass. The mixed check must report a generated face-owned transition and zero unmatched independent interface segments; a message saying it is merely ready is insufficient. No deterministic-repeat/E2E/full validation is started unless every geometry gate passes.

## Invocation

Run exact-source `check-only` and `graph-contract` using unique evidence folders. Only if both pass, invoke exactly once:

```powershell
pwsh -NoProfile -File scripts/experiments/run_r10b_stage.ps1 `
  -Stage geometry `
  -AttemptId B2-CAVITY-20261030-F32193A `
  -Hypothesis R10B2_EXPANDING_LOCAL_CAVITY_EXACT_RETRIANGULATION `
  -EvidenceRoot 'C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B2-CAVITY-20261030-F32193A'
```

Store stdout, stderr, process/monitor records and JSON output immutably. No automatic rerun after the geometry process starts. Results are UNSCORED and have no production authority.
