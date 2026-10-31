# P3.1 R12-CXR R1 Result and R2 Preregistration

Date: 2026-10-31

## Identity and scope

R1 ran once on source HEAD 6e872316d205d3c1de7fca28453aa96a07379ca3, parent 01b6f0f06dc7bb0cf28592c46741b54ae9e78c03, tree 419d6a674488eb1fac89e079141f95ddc1b9e924. The worktree was detached, and no tracked source was modified. Target was R9.2.SEAM.XPLUS_EQUAL.v1; frozen Candidate D, scalar volume, topology fixture, roots, ROI oracle and cutoff were unchanged.

## R1 evidence

Godot was 4.7.2.stable.official.ed1daf0bf; executable SHA-256 C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643.

- Fresh editor import: exit 0, class cache generated, no parser/script errors or warnings.
- Campaign check-only: passed after a recoverable wrapper correction to lowercase SHA-256 environment pins. The first preflight attempt correctly failed closed because uppercase hex did not equal the lowercase GDScript pin. No geometry was run by that preflight.
- CXR contract suite: 91 assertions, 0 failures, exit 0.
- R1 target was invoked once as attempt r1_archconv_20261031_r2; both R12CXR_TARGET_INVOCATION_BEGIN and R12CXR_LOCAL_PATCH_SEARCH_BEGIN are present. The complete terminal result JSON was flushed and its output marker digest matches the file.
- The target result is R12_CXR_FAILED_TARGET_WITH_EVIDENCE, with campaign disposition R12_CXR_R1_COMPLETE_NO_SOLUTION_R2_ELIGIBLE, failed invariant cx_bounded_patch_search_failed, and result SHA-256 3777BC3E5900613CB17067D164D17F4F2A02CF286CA44750200916229C9C4600.
- Independently parsed result: two cavities processed; each reports search_complete=true, search_exhaustive=true, and all_levels_exhausted. Each cavity has explicit L0-L3 records. L0 candidate generation completed (558 attempts total, 99 retained support candidates, 177 candidate fan triangles; no retained solution). Invalid L1-L3 boundaries were recorded with complete signatures/incidence diagnostics and NOT_RUN_INVALID_BOUNDARY values, then the search continued. No preregistered cavity, attempt, support, candidate triangle, state, or time limit was reached. The target volume identity passed. Controls, rays, mixed LOD, deterministic repeat and full E2E correctly remain not run because equal-LOD geometry did not pass.
- R1 therefore satisfies the attachment's completion/exhaustion precondition for R2; this does not mean geometry passed.

## Process-capture limitation

The external PowerShell monitor's CSV formatter threw after Godot had started. The Godot process nevertheless reached the terminal marker and wrote the complete result artifact; the process PID and parent PID were captured at launch, but its exit code and during-run memory samples were not captured. The output and result are preserved; do not infer or claim an exit code or peak memory. The process has exited. This orchestration gap is recorded as a limitation and is corrected before R2 launch. The scenario is not rerun.

## R2 preregistered finite domain

R2 will preserve the exact field-derived support candidate records regenerated from the frozen field for each valid L0 cavity. It will replace the fixed one-support-per-residual fan with deterministic candidate-triangle generation and constrained incidence search over the cavity boundary vertices plus those candidates. It may select 0-4 supports; it may not add or move roots, change Candidate D, samples, volume, residual identity, ROI, cutoff, or boundary ownership. Final candidates must preserve the directed cavity boundary, topology arcs/owners and winding; reject cutoff, crossings, T-junctions and nonmanifold outcomes.

Before R2 geometry execution, implementation and contract tests will freeze these additional limits: 65,536 candidate triangles per cavity / 131,072 total; 32,768 search states per cavity / 65,536 total; existing 8,192 field attempts, 256 retained candidates, 4 selected supports, 10-second cavity search, 20-second total search and 30-second realizer wall deadline. Any reached limit, incomplete evidence, memory stop or timeout yields PARTIAL; it cannot qualify R2 no-solution or enable R3. The candidate triangle/state limits apply only to R2's generalized search and are reported separately from R1's limits.

The solver's search domain, canonical ordering, generated triangle predicates, incidence obligations and tests must be frozen in source and this checkpoint before its target attempt. A result may advance to R3 only when every R2 cavity is complete and exhaustive over that declared finite domain and no solution exists. A valid equal-LOD solution immediately advances to the required downstream gates.

## Evidence location

Raw R1 evidence is retained outside the repository at:

C:\Users\PUBLI\AppData\Local\Temp\r12cxr_convergence_20261031_f4b2f543b81448be8a9c024a15ab3cb1

The R1 reservation-error, process-launch, stdout/stderr, target JSON, extracted fixture, source identities and hash records are append-only evidence. The failed earlier check-only attempt and formatter failures are preserved. No prior CXR target was repeated.

## Holds

This is test-only experimental evidence. No production adoption, merge or release is authorized. Preserve CURRENT_PROTECTED_STATE_UNKNOWN, V3_NOT_ATTESTED, ACL_REVIEW_REQUIRED, G1_BLOCKED_ENVIRONMENT, and F2_G1_RELEASE_HOLD.