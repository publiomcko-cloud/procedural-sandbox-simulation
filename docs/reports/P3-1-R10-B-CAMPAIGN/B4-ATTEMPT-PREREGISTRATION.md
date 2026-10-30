# R10-B4 attempt preregistration — canonical-field Steiner subdivision

Status: preregistered before B4's single geometry invocation. B1 is blocked by script errors and not repeated; B2 and B3 completed their registered geometry strategies and failed the fixed topology gate.

## Exact source and inputs

- Attempt ID: `B4-STEINER-20261030-1460333`.
- Hypothesis: `R10B4_CANONICAL_FIELD_STEINER_SUBDIVISION`.
- Implementation commit `146033336f343f6ad5489ebbe8879d1822b01dcd`; direct parent `c4d60e93e38a17d4b27be8e2f86e61ddf67481a1`; tree `75c9cb05471b09eb34192d5eaa1377dbebdc591d`.
- Campaign Git blob `0654e6a2550a01e3c20bcf8ccbe2f1c06d1451a5`; physical SHA-256 `35f77cebc32e3b91368a63c9d6be5bf2bf4321a16cf1047235ef8f18e6ac8a92`.
- Canonical-field projection is pinned to unchanged R10-A authority Git blob `732f143939ac6980e1c7e77703dd7ee549206c0e`, physical SHA-256 `feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216`.
- Frozen R9.2 manifest, Candidate D, A6 volume, source topology, ray fixture/source and Godot pins remain as recorded in B1. Runner launch records revalidate and log them.

## Candidate method

B4 invokes the existing experimental `R10A3_CANONICAL_FIELD_STEINER` path on the frozen `R9.2.SEAM.XPLUS_EQUAL.v1` volume. Only the four fixed source cells `60,8,25`, `61,8,25`, `62,9,24`, `66,7,29` are eligible for subdivision, and only source triangles rejected by the existing `cross_squared > 1e-12` emitter are candidates. Each Steiner point is initialized at the source triangle centroid, projected against the canonical SDF v1 plus the exact ordered snapshot by the pinned finite-difference/line-search method, and recorded with parent polygon, root IDs, source plane residual, displacement, iteration count, canonical density before/after, and child areas. The immutable input volume bytes/values are not modified. This is a geometry-changing experiment; new Steiner points have provenance and are not asserted to preserve the original root-only mesh.

The preexisting projector uses at most 12 iterations, finite-difference step `max(STEP*0.01, 0.0001)`, convergence epsilon `1e-5`, and maximum displacement `STEP`. These are implementation bounds in the pinned experimental source, not owner-approved geometric tolerances. The report must expose measured residuals/displacements and must not turn those parameters into an accepted product error budget. There is no arbitrary iteration, cell, seed, or tolerance sweep.

## Gates and one invocation

Run exact-source `check-only` and graph contract first. If either fails, do not start B4 geometry. Otherwise execute once:

```powershell
pwsh -NoProfile -File scripts/experiments/run_r10b_stage.ps1 `
  -Stage geometry `
  -AttemptId B4-STEINER-20261030-1460333 `
  -Hypothesis R10B4_CANONICAL_FIELD_STEINER_SUBDIVISION `
  -EvidenceRoot 'C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B4-STEINER-20261030-1460333'
```

Acceptance remains unchanged: complete mesh; zero unexplained internal opens, nonmanifold/degenerate triangles, winding defects, missing adjacency or fixed-cutoff rejections; exact source volume identity; 25/25 ROI ray parity; six controls. If those pass, the separately executed mixed LOD interface must have face-owned transition geometry and zero unmatched independent contour segments. A low residual alone cannot satisfy any geometry gate. No full E2E or `scripts/validate.ps1` unless every geometry gate passes.

B4 is one experiment, UNSCORED. No production adoption, approved geometric tolerance, integration, merge, storage/schema change, Issue #108/#154, or change to F2-G1 holds.
