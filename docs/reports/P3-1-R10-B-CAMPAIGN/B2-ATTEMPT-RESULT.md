# R10-B2 attempt result — local cavity did not resolve the fixed A6 defect

Attempt: `B2-CAVITY-20261030-F32193A`
Source SHA: `823b76111c46d7f640a59c70059c2838d7182b22`
Result: `FAILED_TARGET`; no script error, process exit 0. The result is a geometry failure, not an execution failure.

The exact frozen volume and root graph passed their identity checks. B2 exhausted each of the five frozen face-adjacency cavities (rings 0–4) from the original A6 triangulation. The face counts were 3, 10, 18, 23, and 25. Each ring visited only its initial state; total 5 unique states, 910 edge keys examined (182 per state), and 65 ms solver time. No legal flip state was generated within any allowed cavity; 3 sub-cutoff triangles remained. The result only excludes the registered internal diagonal-flip move family within these five bounded cavities. It does not establish global infeasibility.

| Gate | Observed |
|---|---|
| Source topology | valid; 369 roots, 502 polygons, 870 arcs |
| Volume identity | pass; volume `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`, revision 2 |
| Equal-LOD mesh | fail; 655 triangles, 10 internal open edges, 73 ROI-boundary open edges, 0 nonmanifold, 0 degenerate, 0 winding errors |
| Required adjacency | 21 missing |
| Frozen cutoff | 7 rejected required triangles; strict `cross_squared > 1e-12` unchanged |
| Ray control | 25/25 ROI outcomes agree (0 disagreements); R10-A ray mesh `04c6ceb842b964caba4e254f94c9f4b32881dae79994b961ac01029a48f64553` |
| Other controls | 6/6 |
| Mixed LOD | skipped because the equal-LOD gate failed |

The failed result did not qualify any geometry. No R10-B2 search is repeated. Raw evidence remains at `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B2-CAVITY-20261030-F32193A\B2-CAVITY-20261030-F32193A_geometry`.

| Raw artifact | SHA-256 |
|---|---|
| Attempt JSON | `dc53a960a6cd58d6fae1f2dad4b4ee34122cc946e6ece6f55df017c1928c2ca4` |
| Stdout | `85e0065bedad38eb8314ac06742fcc68103a6343296ccee684c855b1c9a7df27` |
| Stderr | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Process record | `3e8a6f5dddc4d2a5f9f2ce2252452b1643989c277e89b3ff6348d18d8d43010b` |

## What the result does not claim

This experiment does not show that no exact triangulation exists. It shows only that the specified 2-2 flips wholly inside rings 0–4, with the original root positions, boundary, root set, and all topology/winding/cutoff guards, generated no alternate state. R10-B3 evaluates a distinct constrained-Delaunay local flip rule.
