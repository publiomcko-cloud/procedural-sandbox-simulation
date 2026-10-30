# R10-B ray-causality scope correction

This correction supersedes the initial D0 interpretation in `PREREGISTRATION.md` and the first derived `ray_reference_fixture.json`. It does not alter the frozen 25-ray input, SDF, Candidate D, R10-A, R9.7 raw evidence, topology cutoff or any geometry threshold.

## Exact original evidence

| Evidence | Identity |
|---|---|
| R9.7 D3.5 captured stdout | `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R97_D3_20261029_5eab760d7ce6486eaef7fb210741416e\D3.5_GEOMETRY_RUN1\stdout.txt` |
| Physical SHA-256 | `343753e424bce61edf764f4fe634f917789739f6565999bd0616a7223580fefa` |
| R95 per-ray records | 25, ray indices 0–24, one run ID `R97-D3.5-b139a38aaa6e4bbeb40e8b6635b63f77`, candidate D, source `ca48ecdd6c1608118e9f9c6bbac7e2129f5c669a` |
| R95 summary | 25 rays; `roi_scoped_hit_miss_disagreements=0`; mesh SHA `04c6ceb842b964caba4e254f94c9f4b32881dae79994b961ac01029a48f64553` |
| R95 legacy scan summary | 25 rays; `finite_scan_hit_miss_disagreements=9`; indices `[2,8,9,13,14,18,19,23,24]` |
| Preserved D3.5 candidate artifact | `D3.5-artifacts-run1\D_R9.2.RAY.CANONICAL_PICKER.v1_default_topology.json`, SHA-256 `87623cd4a55f27a0677d522056b02f847e24409755eb4a227cbde57c77d579ec`, mesh SHA `04c6ceb842b964caba4e254f94c9f4b32881dae79994b961ac01029a48f64553` |
| R10-A6 full-scan oracle output | SHA-256 `327a87ee0608eb95a8b9492c98ff7a7038b88d7aba20be0bc833f32dae738a9d`; 9/25 at the same indices; mesh SHA `04c6…` |
| Corrected derived fixture | `fixtures\ray_reference_fixture_r2.json`, SHA-256 `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7` |

The extractor checked the raw stdout hash, exactly 25 `R95_RAY` rows, one summary and one legacy-summary record, ordered ray indices, a common run ID, candidate/source identity, exact manifest coordinates/directions/lengths, all 25 ROI disagreement flags false, and the summary/legacy totals. Raw stdout and the initial fixture were not overwritten. The R2 fixture carries the complete raw per-ray objects plus both metric summaries.

## Why 0/25 and 9/25 are compatible

R9.7 `p3_1_r9_5_probe.gd` computes the canonical zero-edit roots, filters roots to the closed mesh ROI with `1e-6` bounds tolerance, and excludes roots on the Y end faces because those are cropped ray-axis endpoints. It compares whether any remaining in-ROI root exists with a two-sided triangle hit. This produces 0/25. The 25 `R95_RAY` stdout rows preserve that result, each filtered root set and every mesh hit.

The same R9.7 stdout separately reports a global finite 256-step scan plus 32 bisections against the mesh. That comparison counts roots outside the clipped ROI and reports 9/25 at indices `[2,8,9,13,14,18,19,23,24]`. R10-A `Core.compare_mesh_rays` uses that full-ray root scope and reports the same nine indices. Its final emitted mesh SHA exactly matches both R9.7's Candidate D ray mesh and Candidate D's R10-B replay. This is a scope/oracle-contract difference, not evidence that A6 changed the ray mesh or regressed the ROI-scoped geometry.

## R10-B treatment

The corrected `p3_1_r10_b_ray_causality.gd` now records for each D0/D1/D2/D3 ray:

- global finite-scan roots and full-ray hit/miss result;
- ROI-filtered roots and hit/miss result under the R9.7 closed-ROI/Y-end crop rule;
- first triangle, exact hit distance/position, candidate root identities, reconstructed source-tetra IDs, mesh component, A6 patch/source polygons, density at the hit and distance to an in-ROI root;
- a per-ray match against the existing Core full-ray intersection implementation;
- separate aggregate counts for ROI-scoped and full-ray comparisons.

The frozen R9.7 ROI rows are compared to D3 Candidate D replay; the R10-A rows are compared to D1 full-ray replay. The diagnostic-only D2 patch stays unqualified and does not change the original cutoff. This scope correction is not a geometry hypothesis and consumes no B1–B6 attempt.

## Causal conclusion

The original apparent 0/25 versus 9/25 contradiction was caused by comparing different ray-root scopes. Current evidence verifies the R10-A full-scan count and the R9.7 ROI-scoped count independently, with matching mesh SHA and identical full-scan disagreement indices. No ray geometry correction is indicated by this discrepancy. The separate R10-A equal-LOD open-edge and sub-cutoff failures remain unresolved and still require R10-B geometry hypotheses.
