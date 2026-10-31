# P3.1 R12-CXR R3 Attempt 02 Result and Attempt 03 Pre-Target Freeze

Date: 2026-10-31

## Disposition and scope

Attempt `R3_TARGET_20261031_02` started and produced a durable result, but the campaign emitted `R12CXR_PRE_GEOMETRY_TOOLING_FAILURE` with `consumes_cx_hypothesis=false`, `cx_algorithm_started=false`, and no support-candidate generation or search nodes. It is preserved and will not be rerun. It did not test the field-constrained support hypothesis. The narrowly corrected boundary-orientation implementation and exact-source gates now freeze a distinct one-shot attempt, `R3_TARGET_20261031_03`, which remains **NOT_STARTED** at this checkpoint. No downstream qualification gate has passed or run.

This remains test-only R12-CXR research. No production integration, merge, release, schema/save change, Issue #108/#154 work, or protected F2-G1 operation is authorized. Preserve all five holds: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

## Attempt 02 result and causal evidence

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Branch: `exp/p3-1-r12-cxr-per-cavity-continuation`; PR #214 remains open/draft/unmerged, stacked on PR #213, which remains open/draft/unmerged.
- Scenario: `R9.2.SEAM.XPLUS_EQUAL.v1`; attempt `R3_TARGET_20261031_02`.
- Measured source: `fdab3b8f16b615077aa44a7901b9555aebd3d80d`; execution checkout: `55562aec07c546f918b3dfdf67d770f92e5418b5`.
- Godot PID 29672, parent dispatcher PID 42576, start `2026-10-31T21:08:05.0098196Z`, exit 2 at `2026-10-31T21:08:08.8451942Z`, no timeout, stderr empty. The target-start marker is present, followed by a pre-geometry failure receipt.
- Terminal classification: `R12_CXR_PRE_GEOMETRY_TOOLING_FAILURE`; reason `cx_bounded_patch_search_failed`; `consumes_cx_hypothesis=false`. Both cavities were processed, but no candidate generation, support selection, triangulation search, or search node occurred. `UNKNOWN_NOT_CAPTURED` counters are therefore correctly not interpreted as zero.

The frozen report shows that removed-face winding had incorrectly been treated as boundary authority. At a 1:1 removed/surviving C6 edge, the cavity replacement boundary is oriented from the surviving C6 owner; the removed face is being replaced and its winding cannot decide that interface direction. The prior attempt also exposed independent invalid boundary conditions: 1:2 edge incidence and patch edges with no surviving owner. Attempt 02 remains a pre-geometry result and does not establish either feasibility or infeasibility of the support-vertex hypothesis.

The bounded correction is committed as `c1dce7e2a410e439dbf82e5252a8e333d0621642` (parent `55562aec07c546f918b3dfdf67d770f92e5418b5`, tree `e1ab7ca07629cdd1989c62d64a2582c5d0b82349`). In `_r3_derive_remaining_boundary`, surviving C6 owners now determine directed replacement edges; a same-direction removed-source edge is retained as a diagnostic rather than rejected. Existing incidence checks, boundary cycle validation, final whole-mesh orientation/manifold checks, exact topology authority, and the strict degeneracy cutoff remain in force.

Regression tests include a reversed removed face, which must retain the surviving-owner signature and emit a diagnostic, and an inconsistent surviving-owner winding, which must still fail the oriented-cycle check. The focused suite passes **143 assertions, zero failures**. The source change is limited to the R12-CXR test-only realizer and its contract tests. The complete attempt 02 JSON, process receipts and raw streams are committed under [`r3_target_attempt_02`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_target_attempt_02/); source-correction and attempt-02 evidence hashes are indexed by [`correction-evidence-sha256-index.txt`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_boundary_correction_01/correction-evidence-sha256-index.txt).

## Exact-source gates for attempt 03

The measured code source for attempt 03 is `c1dce7e2a410e439dbf82e5252a8e333d0621642`, parent `55562aec07c546f918b3dfdf67d770f92e5418b5`, tree `e1ab7ca07629cdd1989c62d64a2582c5d0b82349`. Physical SHA-256 pins:

| Artifact | SHA-256 |
| --- | --- |
| Godot `4.7.2.stable.official.ed1daf0bf` executable | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |
| R12-CXR campaign | `1b3a73845ef5bafec6d16fe2a7928ee3599c5e70ba5310070cb845af3687145b` |
| R12-CXR R3 field-support realizer | `cf57013623d0e86952ab6aa1a8d7a9d2eee6c2ecfeb76b80d71f0f75a4e48591` |
| R12-CXR contract tests | `ccd29810ffcc4caaeced60f49cdf816a174b576c64f19ee1a58cbd8674eb9384` |
| C6 campaign | `9a695705c47ad6473b773bbfaeaf35d88306cee6804113a0b1a71c6faca2f348` |
| C6 realizer | `31947e1944a017442ad14cc4f098e67db800d4f5e196d07e047b93dc0fe9d2ac` |
| Stage-0 topology fixture | `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d` |
| Residual fixture | `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23` |
| Frozen Candidate D | `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a` |
| Frozen volume | `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` |
| Frozen payload | `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0` |
| Canonical manifest | `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` |

On the committed source, isolated Godot editor import passed (PID 28040, exit 0); the R12-CXR contract suite passed 143/143 (PID 36260, exit 0); campaign check-only passed with the exact frozen hashes and topology preflight (attempt `R3_CHECK_20261031_07`, PID 44936, exit 0). The preceding check-only `R3_CHECK_20261031_06` exited 2 because the launcher supplied the wrong environment-variable name for the residual hash; it did not emit a target marker or start geometry. The corrected check-only uses `R12CXR_EXPECTED_RESIDUAL_FIXTURE_SHA256`, and both preflight records are preserved. Raw source-gate output, stderr, process records, and hashes are under [`r3_pretarget_03/source_gates`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_03/source_gates/).

## Dispatcher and one-shot attempt 03 freeze

The versioned attempt-03 dispatcher is [`r3_target_dispatcher.ps1`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_03/r3_target_dispatcher.ps1), SHA-256 `713df38f7f32abd152b17daa28448d2fdd09f996a4f0e89d81d746cb7f49e8dc`. It pins the source commit and physical hashes for campaign, realizer and tests, verifies the frozen fixtures, manifest, Godot binary, origin and execution-checkout source identity, requires a fresh empty evidence root, reserves output without overwrite, captures process identity/stdout/stderr, and applies the frozen 45-second timeout.

Unlike the prior dispatcher, this version durably samples Windows commit usage every 500 ms during a target. It aborts below 2 GiB free commit and also terminates the child if telemetry or sample persistence fails. The resource-sampling stream is created before `Process.Start`; after a target may have started it is never retried. The exact dispatcher passed a controlled-child test (child PID 32728, dispatcher PID 44928, expected child exit 23, exact stdout/stderr, duplicate reservation denied, overwrite denied, resource telemetry captured and process termination confirmed). A prior controlled-child run before enabling in-process sampling is retained separately. The PowerShell parser reported zero errors. Dispatcher/control artifacts are included in the pre-target evidence inventory.

Attempt 03 is frozen as follows:

- Scenario: `R9.2.SEAM.XPLUS_EQUAL.v1`.
- Phase: `r3`.
- Attempt ID: `R3_TARGET_20261031_03`.
- Code source: `c1dce7e2a410e439dbf82e5252a8e333d0621642`.
- Exact execution-checkout HEAD is pinned in the immediately following immutable execution-checkout addendum, before the target is launched. At this checkpoint, **attempt 03 is NOT_STARTED**.
- The two original residual cavities, L0-L3 patch expansion, boundary rule, field-derived support method, caps, Candidate D, frozen topology/volume/payload, controls, ROI ray oracle and exact thresholds remain unchanged from the accepted R3 preregistration. `cross_squared > 1e-12` remains strict. No `MAX_*` geometric/search limit is increased or altered.
- The target must be invoked once only, through the frozen dispatcher, after the checkout addendum, exact path/hash check, fresh isolated profile, empty evidence root, and live free-commit guard. Any started attempt is never retried.

If the target reaches support generation, preserve all candidate/provenance/rejection rows, per-cavity level results, actual counters, search completion/exhaustiveness and solution selection. Invalid boundaries, caps, timeouts, missing measurements or incomplete search remain `PARTIAL`; no domain infeasibility claim is allowed unless the declared valid finite domain is fully exhausted. Downstream gates run only after complete equal-LOD acceptance and stop at the first failed gate.

The source-gate and dispatcher evidence is indexed at [`r3_pretarget_03/evidence-sha256-index.txt`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_03/evidence-sha256-index.txt). No source from production paths, frozen inputs, schemas, saves, PRs #207–#213, or protected F2-G1 state changed. PR #214 remains draft and unmerged.
