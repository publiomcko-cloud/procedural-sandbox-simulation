# R10-B6 attempt preregistration — cutoff-directed bounded beam

Status: preregistered before B6's single geometry invocation. This is the sixth and final registered R10-B hypothesis. B1 is not repeated; its only launch ended in a script error before a valid geometry verdict. B2–B5 are preserved with terminal failures.

## Exact source and inputs

- Attempt ID: `B6-BEAM-20261030-ABE1D54`.
- Hypothesis: `R10B6_CUTOFF_DIRECTED_BOUNDED_BEAM`.
- Implementation commit: `abe1d54dc8986fec2513b8ce261197867f4b8095`; parent `f622468dd750775c51394ae595fa5019114e7a1c`.
- Campaign Git blob `a68df73ae77a3b0868fd636f4eabc9012acb85b9`, physical SHA-256 `1ff5a653099e2661af44d5e95fcf777f5f66936d7a2beebb6277f5ba3f96a636`.
- B6 realizer Git blob `7a0a8efb42a2595e6c1f8a680730e81cb897917c`, physical SHA-256 `794024b4c886857fd718aec6b2a2443122920838c436c14a39a1bcde3ed31a91`.
- Inputs remain the frozen `R9.2.SEAM.XPLUS_EQUAL.v1` 0.25-step A6 volume, source-root triangulation, 73 exact roots, fixed 34-root boundary and the exact ordered snapshot. The original A6 topology authority, Candidate D, manifest, ray fixture, and Godot pins are unchanged and revalidated by the stage runner.

## Candidate strategy

B6 targets the measured failure directly: triangles whose squared cross product is at or below the unchanged `1e-12` cutoff. It searches legal internal 2–2 edge flips over the existing exact root set. It does not move roots, add Steiner vertices, alter scalar samples, change the boundary edge set, or relax winding, planarity, manifold, degeneracy, adjacency, or cutoff requirements.

Unlike the invalid B1 run, this is a deterministic bounded beam, not breadth-first traversal. A state is ranked first by fewer sub-cutoff triangles, then by larger minimum squared cross product, then by lexicographic canonical state hash. Bounds are fixed before execution: width 32, at most 1,024 unique states, 12,000 candidate edges and 30,000 ms solver time. A found state still must pass the complete independent geometry, exact-root, ray and mixed-LOD gates. A bounded-search exhaustion means only that this registered search found no solution; it does not prove geometric infeasibility.

## Single-run gates

Run exact-source `check-only` and graph-contract first. If either fails, do not start B6 geometry. Otherwise invoke B6 once with the registered attempt ID. Preserve all result/diagnostic records. No automatic rerun is allowed. A successful equal-LOD result proceeds to the existing frozen ROI ray gate; mixed LOD runs only if both equal-LOD and ray gates pass. Mixed-LOD acceptance still requires independently matching boundary contours and face-owned transition geometry. Do not run `scripts/validate.ps1`, a broad campaign, or any production path unless every required geometry gate passes.

B6 is experimental, UNSCORED and non-authoritative. No production integration, merge, save/schema change, Issue #108/#154, geometric-contract adoption or change to any F2-G1 hold is authorized.
