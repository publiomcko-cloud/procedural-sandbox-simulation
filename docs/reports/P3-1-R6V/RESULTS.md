# P3.1 R6-V — Cave-shape and adaptive-refinement causal investigation

## Disposition

P3_1_R6V_BLOCKED_WITH_EVIDENCE. The focused experiment and full project validation completed successfully, and they identify a repeatable tradeoff between cave-shape fidelity and scalar-field continuity. The requested collision-proxy discrepancy and a complete extracted-mesh crack/T-junction oracle were not measured. The evidence therefore does not close every required geometry observation and does not approve any geometry tolerance or production representation.

## Source identity and scope

Physical source hashes and base blob identities are listed in evidence/source-identity.txt; the complete changed/evidence file SHA-256 inventory is SHA256SUMS.txt.

- Repository origin: https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git
- Isolated branch: bench/p3-1-r6v-cave
- Experiment base / starting HEAD: 234e73d0e39504559c4df6869ae302c74e58d8a5 (R5-V)
- Direct parent of that base: 051249642611a7fa9cd2006be450bad0e184e4ee (R4)
- Production reference: 92b442d7f5b605c7bc9c48fac2aceea9d71813aa
- Godot: 4.7.2.stable.official.ed1daf0bf; executable SHA-256 c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643
- Modified code is limited to the experimental adaptive snapshot prototype under game/tests/prototypes and a new test-only diagnostic. Production SDF, ledger, saves, schemas, playable scenes and production mesher are unchanged.
- All timing is headless and exploratory. No owner-approved geometric or performance tolerance is asserted.

## Question and method

The experiment separates two policies in each dimension. A is the inherited coarse-boundary / center-residual behavior. B substitutes canonical continuous-SDF samples at fine nodes on the boundary of each selected refined cell. C retains coarse boundaries but selects cells using center plus six face-center residual probes. BC combines B and C. All variants retain sign-crossing refinement, target spacing 0.125 world units, coarse spacing 0.5, and the existing 0.02 residual selection threshold; 0.02 is only a refinement-selection input, not a geometry tolerance.

Each of three deterministic field snapshots was materialized over a 4 by 4 set of 16 chunks, covering the 16-world-unit tunnel length: (1) zero edits; (2) one CARVE sphere of radius 0.58 at the seeded cave center shifted +0.80 on world Z; (3) FILL at the center then CARVE at +0.82 world Z, both radius 0.58, in canonical order. Seed is 131102026 and the cave is the canonical SDF-v1 region-zero cave. The original control's vertical opening is 1.75 world units and the seeded cave radius is 0.92 world units.

Cross-sections sample an 81 by 81 grid at 0.0625-unit spacing around the cave centerline at eight X positions, with 127 centerline samples across the full cave. Surface displacement and normal differences are sampled on radial cross-section roots. Chunk interfaces compare shared scalar probes and finite-difference normals. Refined-cell interfaces compare canonical samples on both sides. Zero-edit LOD0 and LOD1 meshes are compared by sampled vertex-to-triangle distances in both directions. This is not certified Hausdorff distance, a full manifold test, or a complete contour/T-junction proof.

## Causal findings

1. Coarse boundary interpolation is the main measured source of the excessive opening. A preserves near-identical scalar values at refined-cell interfaces, but the zero-edit vertical diameter reaches 4.875 units while the canonical control is exactly 1.75. The radial diameter spans 1.808 to 2.314 instead of the approximately 1.84 opening indicated by the canonical-root samples. Its radial surface-displacement p95 is 0.03361 units and normal-angle p95 is 11.80 degrees. The edited center-FILL case also differs by one sampled centerline slice: candidate 119/127 open versus canonical 118/127.
2. Canonical boundary anchoring improves the measured cave section: B and BC retain the 1.75-unit vertical diameter; on the zero-edit case their radial diameter is 1.837–1.867, radial displacement p95 is 0.002109 units and radial normal-angle p95 is 2.85 degrees. But changing only the boundary samples within selected cells creates a nonconforming scalar field where a refined cell meets an unrefined neighbor. The maximum shared-interface density gap is 0.11509 in the control, 0.15384 after the wall carve and 0.14845 after the ordered fill/carve pair; there are up to 23,932 shared probes above 1e-5. BC reduces but does not remove the discontinuity: max gap 0.040883 and up to 21,646 probes above 1e-5. Those discontinuities are concrete crack risk, not an accepted mesh seam.
3. The center-plus-face curvature/residual selector does not repair the shape while coarse boundary interpolation remains. It increases refined-cell counts from 5,035–5,073 to 5,343–5,378 (about 6.1% in the zero-edit case), and three-scenario median build time rises from 4,032 ms (A) to 5,163 ms (C), about 28.1%. The observed cave diameters remain the A values. Combining the policies yields a three-scenario median of 5,487 ms versus B's 4,372 ms, about 25.5% higher, while leaving a 0.040883 interface gap.
4. The evidence points to boundary interpolation/anchoring and insufficient coarse boundary samples as the primary cause, not a demonstrated defect in the tetrahedral extraction algorithm: the deformation is already visible in sampled scalar cross-sections before mesh interpretation, and chunk-face scalar gaps are zero in all four policies. However, the diagnostic does not rule extraction topology out: it lacks full interface contour-segment equality, T-junction/manifold checks and a collider comparison.

## Measurements

| Variant | 16-chunk build median across 3 fields | Refined cells | Zero-edit radial diameter | Zero-edit vertical max (canonical 1.75) | Max intra-chunk interface density gap across fields | Interpretation |
|---|---:|---:|---:|---:|---:|---|
| A coarse boundary + center residual | 4,032 ms | 5,035–5,073 | 1.808–2.314 | 4.875 | 0.000000119 | Continuous sampled macro interfaces, cave over-expanded |
| B canonical refined boundary + center residual | 4,372 ms | 5,035–5,073 | 1.837–1.867 | 1.750 | 0.153837 | Better cross-section; unacceptable observed scalar discontinuity |
| C coarse boundary + center/face residual | 5,163 ms | 5,343–5,378 | 1.808–2.314 | 4.875 | 0.000000119 | About 28.1% slower median than A; shape unchanged |
| BC canonical boundary + center/face residual | 5,487 ms | 5,343–5,378 | 1.837–1.867 | 1.750 | 0.040883 | About 25.5% slower than B; discontinuity remains |

All 12 scenario/variant records, including edited diameters, area, displacement, normals, picker outcomes, payload estimates, chunk gaps and build times, are in evidence/variant-summary.csv and evidence/focused-cases.jsonl. The full raw logs are retained. Payload estimates are approximately 2.72 MB for A/B and 2.88 MB for C/BC in the zero-edit 16-chunk case; these are serialized-payload estimates, not process RSS. Chunk shared-face gap was 0 for all variants, and maximum near-surface chunk-face normal angle was at most 0.000265 degrees. The much larger intra-chunk refined/unrefined gaps above remain.

For zero-edit mesh samples, LOD0 sampled symmetric vertex-to-triangle distance p95/max was 0.000099/0.003511 units in B and LOD1 was 0.001354/0.005868. Sampled normal-angle p95/max was 33.42/54.66 degrees for LOD0 and 28.88/72.98 degrees for LOD1. These sparse samples do not prove full-surface fidelity. Candidate mesh construction was slower than reference in these measured cases: roughly 46–53 ms vs 25–27 ms for LOD0 and 264–295 ms vs 150–180 ms for LOD1. The five ray-picker rays preserved hit/miss classification in the tested cases, but all hit locations differed numerically (four hit rays in the center-fill case); no owner tolerance exists, so differences are reported, not passed against a threshold.

The synthetic diagnostic has no collision provider. Collision discrepancy is explicitly NOT_MEASURED, not zero. It also reports sampled density continuity rather than proving absence of rendered cracks or T-junctions.

## Attempts and validation

- Initial --check-only attempt failed on test-harness parse errors (out-of-scope identifiers variant, cross_sections, chunk_seams, macro_seams and stats, plus inferred next_cell type). These errors were corrected only in the new diagnostic harness; subsequent check-only attempts passed.
- First focused run was invalid setup: sub-minimum brush radii were rejected and mesh-normal warnings were emitted. It is retained as failed evidence and excluded from results.
- Second focused run accepted the two edits and passed 117 assertions but covered only 8 chunks; cross-section sampling fell back to canonical calls, so it was incomplete and excluded from final geometry comparisons.
- Final focused R6-V run covered all 16 chunks with zero canonical fallback during candidate mesh sampling. Exit 0; R6V_RESULT PASS, 213 assertions, 3 snapshots x 4 variants, approximately 124.8 seconds process duration; stderr empty.
- Godot import: exit 0. Final harness check-only: exit 0, clean. Full scripts/validate.ps1: exit 0, 21,464 assertions, zero failures, 507,647 ms. Three existing colinear camera look_at warnings occurred; there were no parser, script or runtime errors. The validator states that GUI pixels are not assessed. Full combined output and the isolated profile/environment record are under evidence/. A final check-only was run after removal of one trailing blank line from the diagnostic source; the full suite had run immediately before that whitespace-only normalization.

## Recommendation and required next gate

Do not adopt A–D into production. A preserves scalar continuity but demonstrably distorts a narrow cave; B improves the section but violates scalar continuity; C spends more CPU without changing the cave section; BC still has a large nonzero interface gap. A future design must define one globally conforming sampled field across refined and unrefined neighbors (for example, shared canonical interface data with compatible neighboring interpolation or explicit conforming refinement propagation), then validate extracted contour topology. Re-run the independent centerline/cave tests after that correction.

Before any production or geometry decision, owner-approved limits are required for maximum/p95 surface displacement, normal angle, preserved opening diameter, cave connectivity, picker deviation, collision-proxy deviation, build/memory budgets and transition-topology defects. No thresholds are inferred here. Keep ledger authority and exact continuous SDF unchanged.

## Holds and proof boundary

No production paths, schemas, user saves, native dependencies, PR #129/#141/#143/#144 or F2-G1 data were modified. No merge, production adoption, GUI acceptance, presented FPS/GPU result or collider correctness is claimed. Preserve CURRENT_PROTECTED_STATE_UNKNOWN, V3_NOT_ATTESTED, ACL_REVIEW_REQUIRED, G1_BLOCKED_ENVIRONMENT and F2_G1_RELEASE_HOLD.
