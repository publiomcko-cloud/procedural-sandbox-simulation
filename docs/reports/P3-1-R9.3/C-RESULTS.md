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

## Final frozen E2E campaigns (2026-10-28)

The measured implementation commit is `0ea449b005c472ed7b9d68362551eb5a9671c21f` (parent `ac5f23512fb399cb313eacee472904bb7c656a3b`); the campaign branch head, including later report/probe evidence commits, was `a48c3849450cc35cebbe82998cdd62a5511116ff`. Both campaign records pin that exact branch head as source identity and the frozen input manifest SHA-256 remains `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.

Two independent Godot processes were captured and independently audited: `R9.3.C.1.21de21896bca44b7a6e7f759c7f3180a` and `R9.3.C.2.7a79340241654d58abd7bb3d9d20dab8`. Each produced 44 ordered JSONL records; 20 C-scope cases were `COMPLETE`, the D-only corruption case was `NOT_RUN`, and there were zero failures/censored runs. Both process exits were 0 with no stop reason. Sampled process-tree peaks were 105,062,400 and 105,152,512 bytes; elapsed time was 4,670.50 and 4,673.99 ms. Independent audit status was `PASS_EVIDENCE_STRUCTURE_AND_EXECUTION` for both runs.

| Scenario | C1 p50 / nearest-rank p95 µs | C2 p50 / nearest-rank p95 µs | Topology and quality observations |
|---|---:|---:|---|
| zero | 14,568 / 18,792 | 14,672 / 14,911 | 17 internal openings; sampled surface residual p95 0.05597 units |
| CARVE | 15,306 / 17,139 | 14,983 / 15,195 | 22 openings; residual p95 0.12473 units |
| ordered FILL-CARVE | 16,227 / 23,010 | 16,712 / 21,537 | 26 openings and 2 nonmanifold edges; residual p95 0.19493 units; normal deviation p95 92.39° |
| neighbor pair | 31,917 / 32,288 | 31,828 / 32,059 | 3 internal openings and 3 nonmanifold edges; this is not a net topology acceptance over the R9.2 4/0 observation |
| X+ equal seam | 29,057 / 29,461 | 29,670 / 30,483 | 26 internal openings remain |
| local edit rebuild | 35,411 / 35,934 | 34,786 / 38,366 | 42 internal openings / 10 nonmanifold; the previous report's R9.2 comparison was 60 / 10 |

Each listed distribution contains five within-process samples; p95 is nearest-rank, not pooled across runs. The CPU ray proxy reports 9/25 hit/miss disagreements in R9.3 versus 16/25 in the R9.2 C row, but the maximum absolute position discrepancy remains about 2.09 world units. This is a narrow proxy improvement, not production-picker parity. Results remain diagnostic and no product geometry tolerance is approved.

The complete Godot 4.7.2 validation on implementation source `0ea449b005c472ed7b9d68362551eb5a9671c21f` exited 0: 21 suites, 21,464 assertions, zero failures, 510.3 s; three nonfatal existing camera-vector warnings, no parser/script errors. Campaign raw JSONL/stdout/stderr, process records and independent audits are in `evidence/campaigns/`; the full validation log is in `evidence/validation/`. SHA-256 manifests are included.

**Disposition remains `PARTIAL_CORRECTION`.** Zero/CARVE/FILL-CARVE openings decrease relative to the R9.2 C observations, and the finite CPU ray proxy has fewer disagreements. The remaining cracks, nonmanifold edges, X+ defect, large normal/residual observations and unrun smoothing gate block geometry acceptance. No production, rendered/GPU, PhysicsServer, or cave-connectivity claim is made.
