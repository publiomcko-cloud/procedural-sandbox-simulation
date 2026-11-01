# P3.1 R12-CXR R6-06 finite support graph result

Date: 2026-11-01, America/Sao_Paulo (execution evidence timestamp: 2026-11-01 UTC).

## Disposition

`R6-06-20261101-aa16d87` is the fifth and final authorized R6 scientific target (`5/5`). The corrected continuation completed R6-D, R6-E, and the finite R6-F triangulation search for the selected cavity/support graph. D3 exhausted that finite graph without a solution. The result is **scoped to this synthesized 23-support graph and selected cavity**; `continuum_domain_exhausted=false`. It does not establish global infeasibility or exhaust all possible cavity/support representations. Equal-LOD and its downstream gates did not run because R6-F produced no candidate mesh. Terminal classification: `R12_CXR_R6_REALIZATION_PARTIAL_WITH_EVIDENCE`.

The full repository validator ran to completion and exited 1 on five unrelated suites. This record does not call the full validation gate PASS.

## Identity and authorization

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation`.
- Functional branch: `exp/p3-1-r12-cxr-r6-realization-map-cavity`.
- Functional PR: [#219](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/219), draft/open, not merged.
- Authorized issue: [#218](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/218), open.
- Functional source SHA: `946dfa23683554c2828bff549c40bbefb2c1f92d`; parent `0cebc9c70524b62993c6f90299d81a7b68c09843`.
- Docs-only checkpoint branch base: `origin/main` at `5997a76d345f45bf86edfe83f690336391e8be27`; this checkpoint is not a merge receipt.
- Concurrent docs PR #220 was not edited. No merge, release, owner GUI acceptance, protected-state action, or change to F2-G1 holds occurred.
- All five authorized targets are consumed. Pre-geometry diagnostics and corrections below did not add scientific attempts. The continuation runs kept the original target ID and record `additional_target_attempts_consumed=0`.

## Frozen inputs and invariants

The run reconstructed and byte-checked the frozen cavity. Candidate-D, topology authority, field/volume, roots/arcs, ROI, controls, cutoff and epsilons remained pinned. Relevant identities:

- cavity SHA-256: `a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6`;
- volume SHA-256: `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`;
- payload SHA-256: `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`;
- strict cross-squared cutoff: `1e-12`;
- field residual and barycentric epsilons: `1e-7`;
- legal candidate triangle cap: unchanged `2048` (read from the authoritative per-cavity limit).

The R6-A representability audit remains partial: eight coordinates remain unresolved within the frozen ±2-ULP correction bound. This status is retained in the raw audit, not converted to PASS.

## Attempt and diagnostic history

- Attempts R6-02 through R6-05 were already consumed in the prior ledger. Preserve the prior corrections/addenda; in particular the early R6-02 raw result was corrected because D had run into its time cap.
- The earlier finite boundary sampler's `5/6 impossible` observation was not a valid proof. The analytic strict-domain witness audit constructs valid witnesses for all `6/6` boundary edges (zero unknown), and the selected D cavity is `FOUND` with deterministic repeat PASS.
- The original R6-06 target result at source `aa16d87d674e2af35a1b445203a82497ab049831` completed D and E but incorrectly stopped before D3 because it compared 3,654 possible triplets directly against the 2,048 legal-triangle cap. This was a tooling/cap-semantics failure, not a geometry result.
- Continuation at `a0a7ed80396ba96a79381dfe6d46c9684d08d3a1` exposed JSON round-trip precision/type noise in support-set identity. The continuation check was corrected to preserve exact support IDs, binary32 position identity, and provenance while normalizing only serialized diagnostic floats/integers; a regression test covers the round-trip.
- Continuation at `0cebc9c70524b62993c6f90299d81a7b68c09843` exposed that the R6 driver queried a nonexistent `max_candidate_triangles_total` limit, producing cap `0`. It now reads the existing per-cavity cap without increasing it.
- That run then exposed an invalid `String(int)` cast in the candidate-graph diagnostic. It was changed to `str(int)` and regression-tested. The failed intermediate outputs remain archived; none was overwritten or reclassified as a scientific result.

## Corrected R6-D / R6-E / R6-F result

Final continuation source SHA: `946dfa23683554c2828bff549c40bbefb2c1f92d`.

- R6-D: `FOUND`; 6-face selected cavity; 1 state examined/generated; queue depth 0; deterministic repeat PASS. All 6/6 selected boundary edges have analytic feasible witnesses; no unknown boundary edge.
- R6-E: valid; 23 unique supports retained; support cap not hit; finite candidate enumeration complete; 3,072 tetrahedra scanned; 566 zero facets and 421 zero tetrahedra recorded.
- Graph: complete lexicographic scan of all 3,654 possible triplets; 1,058 legal candidate triangles; unchanged cap 2,048; graph audit SHA-256 `3fd0cd4db9c8ec088857c73c54475313c06ea549f2fef8ea83b0ccb7df294afd`; candidate graph summary SHA-256 `de2f1121c60052324717c8d326536fc63890aacd5cc39f9a192a5f4ec4382e87`.
- R6-F/D3: started; search complete and exhaustive on this finite graph; 848 branches; 0 solutions; terminal reason `r2_finite_triangulation_domain_exhausted`.
- Corrected result JSON SHA-256: `5fce4adbe6b1cda1e712e53eb6d5fbc9d5225b16ee33dda77974374c82830728`.
- `continuum_domain_exhausted=false`. This bounded result is not a structural proof over the continuous field or all cavities/supports.

## Gate disposition

- R6 campaign check-only: PASS.
- R6 contracts: 62 assertions, 0 failures.
- Corrected D0 witness audit and D cavity diagnostic: PASS as recorded above.
- Equal-LOD, topology round-trip on a mesh, controls 6/6, ROI rays 0/25, volume reconfirmation, mixed LOD, R6 deterministic mesh repeat, and R6 full E2E: `NOT_RUN_EQUAL_LOD_GATE_FAILED` (no valid D3 mesh exists to supply these gates).
- `scripts/validate.ps1`: exit 1; full output SHA-256 `243383785ab9472a107fc92830fbe1de1e7ad230045cdc266112f88a9231fd21`. Passing suites: SDF 44, brush 612, chunk 179, multiregion 7,637, perf benchmark 11, history 907, world storage 3,516, picker history 713, LOD runtime 53, terrain E2E perf 251, concurrency 11. Five suites failed outside the R6 files: declarative mods (66 assertions/3 failures), procedural objects (92/27), entity commands (2/2), playable entity command (1 failure), and P3.0D entity placement (1 failure). GUI visual checks are not performed by `validate.ps1`.

## Raw evidence

All captured raw D0, R6-A, original-target, failed-continuation, corrected-continuation and validation artifacts are under [`evidence/r6_target_06_20261101`](../reports/P3-1-R12-CXR-R6/evidence/r6_target_06_20261101/). The physical-byte SHA-256/size index covers 28 raw artifacts totaling 8,266,312 bytes; its SHA-256 is `46af37b9bf4c5432b5887997f56e1a00e3068d80fb7082f5fbc9f4e4d850442e`. Raw intermediate tooling failures are preserved separately from the final scientific result.

## Scope and next step

Do not claim `R12_CXR_R6_ARCHITECTURE_QUALIFIED`, global impossibility, equal-LOD PASS, or owner GUI PASS. Do not rerun R6-06 as a new attempt. The finite 23-support/selected-cavity graph has been exhausted; alternate cavity/support domains remain untested and would require a new owner-authorized target budget or a separately preregistered continuation decision. R6 PR #219 remains draft/unmerged; source review and owner GUI actions remain separate.

`BLOCKED_WITH_EVIDENCE`
