# R10-B1 attempt preregistration — constrained non-monotonic flips

Status: preregistered before any B1 geometry invocation. This document defines one bounded hypothesis attempt, not a product geometry contract or performance acceptance.

## Frozen input and target

- Hypothesis: `R10B1_NONMONOTONIC_CONSTRAINED_FLIP_BFS`.
- Frozen case: `R9.2.SEAM.XPLUS_EQUAL.v1`, loaded from the immutable R9.2 JSONL manifest; no input row or expectation is changed.
- Candidate D implementation SHA-256: `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`.
- Manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.
- A6 volume SHA-256: `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`; payload SHA-256: `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`; revision 2.
- A6 source graph: 369 roots, 502 source polygons, 870 arcs. Target component `60,8,25|tet:0`: 84 source polygons, 73 immutable roots (34 ordered boundary, 39 interior), 110 faces, 182 edge records, 33 source A6 flips. The unchanged A6 output has 10 internal open edges and two faces below `cross_squared > 1e-12` (`1.67075673894024e-16`, `1.6572500479133299e-13`).
- The mesh-generation domain, ROI, seed and the 25-ray grid are exactly those in the frozen manifest and R10-B campaign source. Ray comparison is ROI-scoped with the frozen closed-ROI and cropped-Y-end-face rule; global full-ray counts remain diagnostic and are not substituted for the acceptance oracle.

## Pinned implementation and toolchain before geometry

The implementation was committed before this preregistration:

| Item | Identity |
|---|---|
| Code commit | `21c461a57af90e0fb661c47f66b75466de1f34d2` |
| Direct parent | `7f7bfbc126c6cc85f1e4066f44fc449ac4ef966d` |
| Code-tree SHA-1 | `d92b00c4c2f15772b841cd4227b4484360852211` |
| Realizer Git blob / physical SHA-256 | `100ea9bee0644d879e8197ea5b063ea1df64a46d` / `af93708355bfbd3911b246d14df8b135724bc9ddf245b54b4937b70ee6f468af` |
| Campaign Git blob / physical SHA-256 | `d91c8bd034b6dbb9035602a40a0ff698f00c2885` / `0f5b28465d3b5e425e42a7fb0d8ef510c11ed635293b9092f044539a6d9c66ce` |
| Runner Git blob / physical SHA-256 | `a0b1687af5d4c6ee3740d45b27d0b030eadfbdaa` / `a10ed1d064f1ee75ea91752cf8d16d1d0a50d8a5a895c586502f110a7344bb13` |
| Authority physical SHA-256 | `feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216` |
| Ray source / corrected fixture SHA-256 | `b61dab953ee3048e1e1a666daf32ddb21d964b3ccd44c3616825b13360097af1` / `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7` |
| Godot binary SHA-256 | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |

The following documentation-only commit records this preregistration; the runner's durable launch intent records the exact execution `source_sha` and rechecks each physical source pin. No GDScript or frozen input changes are permitted between this pin and the invocation. The final source SHA must be copied from `process.json` into the result record.

Before this preregistration, `--check-only` passed on the pinned implementation commit with exit 0, no parser/script errors, and campaign/candidate/manifest/source hashes matching the values above. The graph-only contract passed on parent code commit `d00d037bc0c16c2551e4e88d4fcc1bfc7ee9b8de`: source graph valid, A6 mesh still had 10 internal opens, 0 nonmanifold edges and 0 winding inconsistencies. This was a graph/fixture check, not a geometry hypothesis run. The preregistration commit must pass a fresh check-only and graph-only contract before B1 geometry starts.

## B1 algorithm and invariants

B1 runs deterministic breadth-first search over internal diagonal flips of the frozen 110-triangle A6 component. Each state's edge keys are sorted; a flip requires a two-owner internal edge, a strictly convex projected quadrilateral, an absent replacement diagonal, no unrelated projected edge crossing, valid orientation, unchanged 73-root set, unchanged 34-edge ordered boundary, exactly 110 distinct triangles, and valid edge incidence. A state hash is formed from sorted unoriented triangle-root triplets. Search does not move roots, alter scalar samples, change the mesh area cutoff, or emit an intermediate invalid state. Final mesh and ray checks still apply.

Hard stop limits: 4,096 unique states; queue/frontier peak 4,096; 15,000 edge keys examined (the counter increments before legality checks and therefore includes boundary and rejected edges); 90,000 ms inside the solver. A bound produces `PARTIAL / EXACT_ROOT_REALIZATION_INCONCLUSIVE`, never infeasibility or PASS. A complete search can claim only infeasibility within this finite flip graph.

Required B1 completion gates: zero sub-cutoff faces under the unchanged strict `cross_squared > 1e-12`; zero unexplained internal open, nonmanifold, degenerate, winding or required-adjacency defects; exact source-root/boundary/volume identity; 25/25 ROI ray hit/miss agreement; all six frozen controls pass. If these pass, the campaign must execute—not merely mark ready—the frozen mixed LOD1/L0 interface gate. A missing face-owned transition or any unmatched interface segment fails that gate. Deterministic repeat, frozen end-to-end, and full validation remain blocked until all preceding geometry gates pass.

## Preflight and single invocation

Unique attempt ID: `B1-BFS-20261030-21C461A`.

1. Run the exact-source `check-only` stage, then `graph-contract`, with unique evidence subdirectories and the same hypothesis string.
2. Only if both return PASS with exact pins and no script errors, invoke the geometry stage exactly once:

```powershell
pwsh -NoProfile -File scripts/experiments/run_r10b_stage.ps1 `
  -Stage geometry `
  -AttemptId B1-BFS-20261030-21C461A `
  -Hypothesis R10B1_NONMONOTONIC_CONSTRAINED_FLIP_BFS `
  -EvidenceRoot 'C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B1-BFS-20261030-21C461A'
```

The runner uses the SHA-pinned Godot 4.7.2 executable, a unique isolated profile, CreateNew evidence records and bounded host-resource monitoring. A host-side launch/preflight failure before scenario start may be corrected and retried only with a new attempt ID/evidence folder. Once `R10B_ATTEMPT_STARTED` is emitted, this B1 geometry scenario is never rerun automatically. Preserve all raw stdout/stderr, process/monitor JSON, artifact JSON and hashes.

## Continuation and authority limits

B1 failure or inconclusive bounded search consumes only B1 and permits the preregistered distinct B2–B6 hypotheses. An isolated candidate geometry failure does not authorize changing the frozen gate, source roots, scalar volume or ray scope. No broad E2E or `scripts/validate.ps1` run is authorized unless a candidate passes all geometry, ray, controls, volume, mixed-LOD and deterministic-repeat gates. Everything remains experimental and UNSCORED; no production integration, merge, geometry-contract adoption, save/schema change, Issue #108/#154 work, or alteration of any F2-G1 hold is authorized.
