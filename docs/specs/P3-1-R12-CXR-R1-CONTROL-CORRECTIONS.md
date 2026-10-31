# P3.1 R12-CXR R1 control correction addendum

Date: 2026-10-31
State: preregistered source correction; target geometry not started.

This addendum records control-flow and evidence-capture corrections to the already frozen R12-CXR R1 field-support micro-patch method. It does not alter Candidate D, source scalar samples, topology authority, roots, cutoff, ROI ray oracle, volume, candidate ordering, acceptance gates, or any preregistered limit in [the original contract](P3-1-R12-CXR-FIELD-SUPPORT-PREREGISTRATION.md).

## R1 continuation contract

- For each cavity, evaluate levels L0 through L3. An invalid patch boundary is a recorded invalid level with complete edge-incidence diagnostics; it does not suppress later levels. A real preregistered cap, source-integrity failure, incomplete evidence, or deadline stops that cavity fail-closed and marks skipped work explicitly.
- A completed cavity with no solution does not suppress subsequent cavities. Every cavity receives an explicit result unless the global 20-second or 32,768-state cap has been reached; then all skipped cavities are emitted as `NOT_RUN_GLOBAL_LIMIT`.
- A solution found before a cap is retained for geometric gates, but the terminal search remains `PARTIAL`. A subsequent interface failure cannot overwrite that partial classification.
- Invalid-boundary and unrun work uses explicit `NOT_RUN_*` values; numeric zero is reserved for measured zero or a completed search that actually examined zero items.
- Candidate-generation schema validation is fail-closed. On malformed/incomplete evidence, captured attempts, candidate rows, supports, elapsed time and the original unvalidated generation result are retained; later residuals and levels are marked unrun. Evidence loss is not converted into a geometric no-solution result.
- The 30,000,000-microsecond realizer deadline applies to every return path. An over-deadline candidate may remain available for diagnostics/gates, but cannot be marked geometry-complete; prior failure evidence is retained and the terminal classification is `PARTIAL`.
- Only `complete=true`, `search_exhaustive=true`, and reason `cxr_no_valid_field_support_solution` across all frozen cavities makes R1 eligible to advance to R2. A cap, malformed result, overlap, timeout, or missing evidence does not establish infeasibility.

## Unchanged frozen limits and gates

The original fixed values remain controlling: 3 cavities; L0-L3; 64 source triangles per cavity; 8,192 candidate attempts per cavity; 256 retained field supports per cavity; 4 selected supports total; 2,048 candidate fan triangles per cavity; 16,384 search states per cavity and 32,768 total; 32 retained solutions per cavity; 10 s per cavity and 20 s total search; 30 s complete realizer; support distance 0.5; barycentric and field residual bounds `1e-7`; and strict `cross_squared > 1e-12`.

The sequence remains equal-LOD topology/geometry, controls 6/6, ROI rays 0/25, volume identity, then frozen mixed LOD. No downstream gate is claimed before it runs. The mixed-LOD row is expected to fail closed if the frozen inputs still omit a shared owner/path; a blocked interface result does not invalidate an otherwise-qualified equal-LOD result and does not authorize production use.

## Source and test checkpoint

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Last verified `main`: `5997a76d345f45bf86edfe83f690336391e8be27`.
- Existing PR #212 remains open/draft/unmerged at `bed9f1d176148e8ec256ad37777c9ba9899dc487`.
- R1 correction source commit: `e42f309c263a441f026b2c8dec91524dcc6bb45a`; parent: `bed9f1d176148e8ec256ad37777c9ba9899dc487`.
- Exact changed code paths: `game/tests/prototypes/p3_1_r12_cxr_campaign.gd`, `game/tests/prototypes/p3_1_r12_cxr_contract_tests.gd`, and `game/tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd`.
- Godot: `4.7.2.stable.official.ed1daf0bf`. The bounded CXR contract suite passed 91 assertions with zero failures on the correction source. The suite is L2 test evidence only; it is not target geometry evidence.
- No R12-CXR local-patch search or frozen target geometry has started on this source. The prior CX/CXR target attempt and evidence remain preserved and are not reused as this attempt.

## Next authorized step

After committing this addendum and obtaining an exact clean detached checkout, perform the frozen R1 source, fixture, profile, parser, and resource preflight. Then execute the R1 target once with a new attempt ID and isolated artifact directory. Monitor free commit continuously and abort before or at 2 GiB. Do not rerun a target after its search-start marker. Advance to R2 only on the exact complete/exhaustive R1 no-solution state above; preregister and pin any R2 implementation/limits before its target execution.

No production code, save/schema, PR #212, Issues #108/#154, release state, or protected F2-G1 state was changed. Preserve all five holds: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
