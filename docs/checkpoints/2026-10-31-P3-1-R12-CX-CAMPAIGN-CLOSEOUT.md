# P3.1 R12-CX Campaign Closeout

Evidence PR: [#211](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/211), draft and unmerged, stacked on [#210](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/210).

Date: 2026-10-31
Campaign status: `P3_1_R12_C_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`
Measured source: `a9c1353db49a7bb5607ce8eaf91d8032c7dc4bea`

The owner-authorized final R12-C hypothesis, `R12CX_RESIDUAL_FIELD_CONSTRAINED_MICROPATCH`, ran once as `CX_GEOMETRY_FINAL04`. Its exact-source P1–P8 gates passed, including the 44-assertion realizer contract suite. The target passed frozen topology-authority and volume preflight, began the bounded local patch search for two merged cavities, then emitted terminal `FAILED_TARGET` with `cx_bounded_patch_search_failed`. CX is consumed. The result does not establish mathematical infeasibility. Nested search failure details and the actual search-state count were not propagated into the terminal artifact; do not treat its default `local_search_nodes: 0` as a measured count.

Because equal-LOD did not pass, the six controls, ROI rays, mixed LOD, deterministic repeat, full E2E, and full validation were correctly not run. Performance remains UNSCORED. The frozen volume identity passed. See [final campaign results](../reports/P3-1-R12-CX-CAMPAIGN/RESULTS.md), [source identities](../reports/P3-1-R12-CX-CAMPAIGN/source-identities.json), and the [raw evidence archive](../reports/P3-1-R12-CX-CAMPAIGN/evidence/P3.1-R12CX-FINAL-EVIDENCE.zip).

The three earlier target attempts were pregeometry tooling failures and did not consume CX: FINAL01 array-to-Vector3 reconstruction; FINAL02 C6 rejection-field mismatch; FINAL03 rounded residual annotation mismatch. Their receipts and logs are retained. Corrections were confined to the experimental fixture adapter, its contract tests, and preregistration/result documentation; the frozen residual fixture and its SHA were unchanged.

No production source, save/schema, user save, PR #210, native component, protected path, or F2-G1 state changed. No production adoption, merge, GUI acceptance, release, mixed-LOD result, or full validation is authorized or claimed. All five protected-state holds remain active.
