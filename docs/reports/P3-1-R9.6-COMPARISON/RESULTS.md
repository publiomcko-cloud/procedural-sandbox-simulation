# P3.1 R9.6 — Consolidated A/D Campaign Disposition

Date: 2026-10-29

Issue: [#196](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/196)

Final disposition: **P3_1_R9_6_BLOCKED_WITH_EVIDENCE**

## Source and campaign identity

The four R9.6 worktrees were created independently from their exact R9.5/source evidence parents. No R9.6 source was integrated into production.

| Workstream | Base / measured source | Measured implementation blob | Physical SHA-256 | R9.6 correction attempts |
|---|---|---|---|---:|
| Shared topology/oracle | R9.5 oracle `895dbca3c6dd58bb9adacd63fb39c3ad524226ff` | current topology helper `a585941a19d5477e4b45f3c01d9730946489401a` | `b7cac8b0c11cc57b4272ae6e105ff676fffe2cfb8621484b60a62218f27d3d29` | Diagnostic contract only; not an A/D attempt |
| Candidate A | baseline HEAD `b41dc7207fae3911ecd7b082850535b7e965db5b`; measured source `f0c93415dd56886a1c05ff2e6a1340e420f22c59` | `5a19b05d3f39108e53c8b7ff47d28303ee7bfbb0` | `970fe99f192ea2a3fea3e682072ed3562e6f57c843561dd4440e46381a384d8a` | 0/3 |
| Candidate D | baseline HEAD `464087947da00a45090a289ade4917882ce0ada5`; measured source `6ea04229b5ff06090f346c8749c1f5a53994227c` | `33ac8bd1f7942ddd71610bd2e2b66f583fdbf3fd` | `a33b464ea569f54fb39b72d2198fa971796c0cb5370a64a9696362cd0313f2a6` | 0/3 |
| Comparison | R9.5 comparison `2c8e9f621ee1b7e38da3cf34887c9d7cbd783657` | docs-only | see local checksum sidecar | N/A |

Frozen manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`. Godot binary SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. The triangle cutoff remains `cross_squared > 1e-12`.

## Causal state: inherited R9.5 findings

The 9/25 historic ray hit/miss differences were a domain-comparison error: the old checker compared full-field roots with a mesh cropped to the Y ROI. In the corrected 25 frozen zero-edit vertical rays, analytic and adaptive root isolation agreed and the ROI-scoped hit/miss result was A/C/D = 0/25 disagreements. This is specific to those frozen rays; it is not a general root-completeness claim. Ray distance remains diagnostic and unscored.

The X+ mesh defect remains real:

| Candidate | Equal-LOD contour segments | Equal-LOD full ROI internal opens | Mixed-LOD separate ROI segments | Mixed-LOD unmatched | Cutoff drops |
|---|---:|---:|---:|---:|---:|
| A | 22 vs 22, segment delta 0 | 8 | 10 vs 22 | 10/22 | 7 |
| C (unchanged control) | 28 vs 28, but control topology differs | 42 | 12 vs 28 | 12/28 | not traced |
| D | 22 vs 22, segment delta 0 | 13 | 10 vs 22 | 10/22 | 8 |

These are R9.5 proxy results, not R9.6 runs or real chunk transitions. A's six-edge interior loop has diameter `0.0038049191`; the best minimum cross² over its existing-vertex triangulations is `1.18455592557076e-14`. D's 7- and 3-edge loop bounds are `4.86268358953069e-15` and `9.40420376120688e-13`. All are below `1e-12`, so existing-vertex caps cannot satisfy the frozen cutoff. The R9.6 goal was to go beyond diagonal selection and vertex-only capping, but that experiment did not start.

## R9.6 attempt ledger and validation

| Candidate | Attempts implemented | Attempts executed | Result |
|---|---:|---:|---|
| A | 0 | 0 | `CENSORED` before Attempt 1; still has inherited X+ openings and mixed-LOD mismatch |
| D | 0 | 0 | `CENSORED` before Attempt 1; still has inherited X+ openings and mixed-LOD mismatch |

No candidate source revision, geometry measurement, new/moved vertex, SDF residual, before/after topology result, ray result, CPU measurement, or full validation result is claimed. Candidate C remains unchanged. B remains excluded.

The shared topology graph/test source was committed before its attempted runtime use. Three Godot editor-import processes on that source crashed with `-1073741819` and `Parameter "mem" is null` (PIDs 36184, 14664, 50016). The `--script` test wrapper then emitted a PowerShell `OutOfMemoryException` and stack overflow with no captured PID or exit code. Windows showed 89,908 KB free virtual-memory commit; `vmmemWSL` had approximately 26.19 GB private bytes. No process or VM was terminated. The exact import logs, process JSON and hash inventory are in the shared oracle evidence package. Thus the 38 authored assertion call sites were not executed. Full `scripts/validate.ps1` and candidate focused/E2E tests were not run.

Historical R9.4 results (not R9.6 correction validation): A and D each passed 21 suites / 21,464 assertions / zero failures on their unchanged source. Their R9.4 E2E runs covered 21 variants (A 12.994 s, D 13.182 s). The R9.4 five-sample headless build context was A equal X+ p50/p95 105.00/109.07 ms and mixed 100.38/102.88 ms; D equal 106.99/110.10 ms and mixed 97.33/99.08 ms. No R9.6 timings exist and none are presented as FPS/GPU data.

## Literature input (not a selected architecture)

- Baktash, Gillespie, Crane, “Subgrid Marching Tetrahedra,” ACM TOG/SIGGRAPH 2026: https://www.markjgillespie.com/Research/SubgridMarchingTets/index.html. Motivates preserving root-connectivity information before geometry realization; no code was imported.
- Schaefer, Ju, Warren, “Manifold Dual Contouring,” IEEE TVCG 13(3), 2007: https://doi.org/10.1109/TVCG.2007.1012. Relevant to manifold-aware topology, but not evidence that dual contouring is a safe local patch for these A/D meshes.
- Lengyel, “Transition Cells for Dynamic Multiresolution Marching Cubes,” 2011: https://doi.org/10.1080/2151237X.2011.563682. A possible interface-owned hypothesis, not implemented here.

## Recommendation and protections

Keep A and D blocked research candidates. Do not lower the cutoff or claim geometry acceptance. Resume only after host commit headroom is available: run the oracle import and topology tests first; then pin A/D Attempt 1 separately, record complete root/face/edge topology before cutoff, and proceed to local SDF-derived refinement only after a preregistered numerical residual rule. Attempt 3 requires an actual shared interface patch and separate equal/mixed-LOD evidence.

All prior PRs #187–#195 remain unmodified, open/draft/unmerged. No production, schema, save, release, or Issue #108/#154 change occurred. Existing worktrees, user saves, two stashes and pre-existing `.gd.uid` files were preserved. The five holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
