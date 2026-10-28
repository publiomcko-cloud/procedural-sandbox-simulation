# R9.3-C — Surface Nets correction findings

Measured experimental source: `0ea449b005c472ed7b9d68362551eb5a9671c21f` (candidate implementation), with the R9.3 targeted diagnostic probe finalized in the following evidence commit. Parent of the implementation commit: `ac5f23512fb399cb313eacee472904bb7c656a3b`. Frozen input manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.

## Correction and evidence

The prototype samples one scalar-cell halo around the frozen ROI and emits quads only for primal edges on the frozen core lattice. This addresses missing incident dual-cell data at ROI boundaries. Quad triangulation now considers both diagonals and emits only a diagonal whose two triangles meet the unchanged squared-cross-product cutoff `1e-12`. This is a test-only change; it does not alter canonical density, production terrain or acceptance thresholds.

Godot 4.7.2 focused run: the R9.2 contract suite reported 160 assertions, zero failures. The R9.3 probe completed four frozen cases with zero harness failures. Results:

| Frozen case | R9.2 internal open edges | R9.3 internal open edges | R9.3 nonmanifold | R9.3 triangles |
|---|---:|---:|---:|---:|
| zero edit | 28 | 17 | 0 | 154 |
| single CARVE | 30 | 22 | 0 | 156 |
| ordered FILL/CARVE | 32 | 26 | 2 | 190 |
| X+ equal-resolution seam | baseline report retained separately | 26 | 0 | 234 |

For the first three rows, the change reduces measured internal openings by 11, 8 and 6, respectively. It does not meet the zero-open-edge invariant; ordered FILL/CARVE still has two nonmanifold edges. The X+ result remains defective. `failed_quads=0` means all attempted frozen primal-edge quads were triangulated under the unchanged cutoff; it does not establish closed topology.

The topology classifier now includes the half-cell halo envelope when separating ROI boundary edges from internal edges. Boundary-open counts are therefore not directly comparable to the R9.2 classifier. No smoothing was executed: the preregistered smoothing stage is gated on the topology stage passing, and that gate failed. No displacement/tolerance acceptance is claimed.

## Disposition

`PARTIAL_CORRECTION`. The ROI-boundary halo and valid-diagonal selection improve the frozen zero/CARVE/FILL-CARVE counts, but remaining openings and nonmanifold geometry block topology acceptance. Smoothing study, extracted cave connectivity, physics collider parity and full frozen E2E campaign remain unperformed. Headless measurements do not assess rendered pixels or GPU behavior. Keep this prototype experimental and unpromoted.
