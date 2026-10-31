# P3.1 R12-CXR R3 Pre-Target Freeze

Date: 2026-10-31

## Disposition and boundary

The R3 implementation and its pre-target gates are frozen. The single R3 geometry target has **NOT_STARTED**. This checkpoint authorizes no second target, no production adoption, no persistence/schema change, no Issue #108/#154 work, no merge, and no release. PR #213 remains an open draft. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

## Exact source and repository identity

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Experimental branch: `exp/p3-1-r12-cxr-r1-architecture-convergence`.
- Frozen R3 source: `64ce92c909c0b5871303a787baeba84e28477c77`, parent `35c12b76403a54886f33fa07c9335241a318637c`, tree `4cdc09d5b1bce93b00c99c8a8f8fe81d233dee68`.
- The source files measured by the campaign are exactly those at `64ce92c`; the execution checkout may be a documentation-only descendant created by this freeze. Before launch, verify that these three R3 source paths have no diff from the frozen source: `game/tests/prototypes/p3_1_r12_cxr_campaign.gd`, `game/tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd`, and `game/tests/prototypes/p3_1_r12_cxr_contract_tests.gd`.
- PR [#213](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/213) was live-verified OPEN, draft, unmerged, head `64ce92c`, base branch `exp/p3-1-r12-cxr-field-support-micropatch`. `origin/main` was `5997a76d345f45bf86edfe83f690336391e8be27`; the experiment is not based on or integrated into production main.

## R2 evidence that enables R3

The R2 target `R9.2.SEAM.XPLUS_EQUAL.v1` ran once and produced `FAILED_TARGET` with campaign disposition `R12_CXR_R2_COMPLETE_NO_SOLUTION_R3_ELIGIBLE`. It exhausted only the two valid L0 candidate domains: cavity `e89d7e6444ead8c6` had 492 attempts, 43 unique supports, 45 candidate triangles and 5 nodes; cavity `aefae75e246e6d28` had 66 attempts, 15 unique supports, 16 candidate triangles and 5 nodes. Across them: 558 attempts, 58 unique supports, 61 triangles and 10 nodes. No cap was hit. Both cavities' L1-L3 boundaries were invalid (`cx_patch_nonmanifold_edge`) and were not triangulated. Therefore the finite result is not a proof of global geometric infeasibility. R2 controls, rays, volume reconfirmation, mixed LOD, repeat determinism, full E2E, and `scripts/validate.ps1` were not run after the failed equal-LOD gate. The full R2 result is preserved in [the preceding result checkpoint](2026-10-31-P3-1-R12-CXR-R2-RESULT-R3-IMPLEMENTATION.md).

## R3 implementation and frozen search domain

R3 implements the originally authorized field-constrained support hypothesis. It joins all three frozen C6 residual faces into one joint cavity. For each deterministic dual-graph radius layer L0-L3 (maximum patch size 64 source triangles), it removes the joint patch from the frozen C6 mesh and derives the replacement boundary from edge incidences in the actual surviving mesh. A level is eligible for triangulation only when the patch is connected and has one valid oriented boundary cycle; every interface edge must have one removed and one surviving owner with opposite source winding. Invalid levels retain their incidence diagnostics and do not prevent later levels from being checked.

Support candidates are generated only from the original three frozen residual faces and their canonical frozen field samples. Candidate positions are exact-binary32 deduplicated and deterministically ordered. The support vertices are geometric realization only; topology roots, arcs, source-face ownership, topology round-trip, Candidate D, frozen volume, ROI ray oracle, control cases, and strict degeneracy cutoff remain authoritative and unchanged. The constrained triangulator receives the entire joint patch and boundary derived from the surviving C6 mesh. It does not reuse invalid R2 cavity boundaries.

The preregistered R3 limits are:

- One joint cavity containing exactly three residual faces; levels L0 through L3; maximum patch size 64 triangles.
- 8,192 candidate-generation attempts per cavity; at most 256 retained support candidates; at most four selected support vertices.
- At most 65,536 candidate triangles per cavity and 131,072 total; at most 32,768 search states per cavity and 65,536 total.
- 10 seconds per cavity, 20 seconds total search, and 30 seconds for the whole realization.
- At most 32 retained solutions; support distance at most 0.5 world units; barycentric and frozen-field residual epsilon `1e-7`; strict `cross_squared > 1e-12`.

Any cap, invalid provenance, missing measurement, incomplete level, or incomplete search yields `PARTIAL`, never finite infeasibility. A local no-solution claim is permitted only if the declared finite domain is complete and exhaustive. If no valid joint boundary exists at any level, report a boundary/domain-construction failure and stop; do not call that a triangulation no-solution proof.

## Exact one-shot target

- Scenario: `R9.2.SEAM.XPLUS_EQUAL.v1`.
- Phase: `R12CXR_PHASE=r3`.
- Attempt ID: `R3_TARGET_20261031_01`.
- Source identity passed to the campaign: `64ce92c909c0b5871303a787baeba84e28477c77`.
- Result filename: `r12cxr_R3_TARGET_20261031_01.json` under a fresh, unique, initially empty TEMP evidence directory.
- The target must be launched once only. Do not retry if process creation may have occurred or if `R12CXR_TARGET_INVOCATION_BEGIN` is present. An ordinary launcher failure before a child exists is operational evidence, not a geometry result; retain it and use a new attempt identity only if a separately authorized continuation permits it.

The R3 campaign itself validates the frozen manifest, target identity, topology authority, exact source pins, C6 volume/payload, and residual fixture before emitting `R12CXR_TARGET_INVOCATION_BEGIN`. Exit code alone is not the geometry verdict. Preserve stdout, stderr, result JSON, process records, resource samples, command line, source IDs, all per-cavity/per-level candidate and search evidence, and SHA-256 inventories.

## Source and input identities

The source and frozen input pins used at the target gate are:

| Artifact | SHA-256 |
| --- | --- |
| R3 campaign source | `1b3a73845ef5bafec6d16fe2a7928ee3599c5e70ba5310070cb845af3687145b` |
| R3 field-support realizer | `0b4e63abbc7821568196ac9a8efc6da6c39dff1cde486a512a145be028b5ec6c` |
| R3 contract tests | `978b575bc3e7ce7e4360624be3bf160605df911addb0e88fd154c42694be321a` |
| C6 campaign | `9a695705c47ad6473b773bbfaeaf35d88306cee6804113a0b1a71c6faca2f348` |
| C6 realizer | `31947e1944a017442ad14cc4f098e67db800d4f5e196d07e047b93dc0fe9d2ac` |
| Candidate D | `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a` |
| C6 topology fixture | `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d` |
| Residual cutoff fixture | `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23` |
| Topology fixture source | `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95` |
| C6 graph fingerprint | `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9` |
| Frozen volume | `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` |
| Frozen payload | `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0` |
| Canonical manifest | `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` |
| Godot executable | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |

## Exact-source preflight and launch controls

Godot is `4.7.2.stable.official.ed1daf0bf`. At source commit `64ce92c`, editor import passed (exit 0, PID 24596, 7.59 s), campaign check-only passed (exit 0, attempt `R3_CHECK_20261031_04`, PID 13940, 2.14 s), and the contract suite passed 131 assertions/0 failures (exit 0, PID 44676, 1.77 s). The test suite was not rerun after the documentation-only changes in this freeze.

The external, versioned PowerShell dispatcher is archived at `../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_01/r3_target_dispatcher.ps1`, SHA-256 `a452f1ce09125a2886881725b4edd9e8b97face06800050d09396be2c3267033`. It writes a durable exclusive reservation, launch intent, and immediate pre-start intent using `CreateNew`/`Flush(true)`, then captures the child PID immediately, drains stdout/stderr concurrently, records timeout/exit and hashes, and does not retry a started process. Its disposable controlled child test passed: expected exit 23, exact stdout and stderr, duplicate reservation denied, output overwrite denied, and no target marker. The recorded child PID was 40144 with parent PID 25772. All control artifacts and the 59-entry SHA-256 inventory are in the R3 pre-target evidence directory; the inventory has zero mismatches.

The pinned Godot executable is under `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`. The pre-launch guard requires at least 2 GiB free commit; the last preflight sample was 10,506,653,696 bytes free commit. Re-measure immediately before the target. The dispatcher creates a fresh TEMP Godot profile and a new evidence root. It has a 45-second process timeout; the solver has lower preregistered 20/30-second internal bounds. A timeout is censored `BLOCKED_TIMEOUT`, never a no-solution result.

The exact-source preflight evidence, earlier failed operational attempts, corrected launcher control, raw outputs, and source hashes are retained under `../reports/P3-1-R12-CXR-R2-R3/evidence/r3_pretarget_01/`. The launcher-collision attempt is preserved as an operational incident; source SHA was verified and no scenario began in that attempt.

## Sequential result gates

The single equal-LOD target must preserve exact topology round-trip and all frozen authority; missing obligations, internal opens, nonmanifold edges, winding errors, degenerates, and cutoff rejects must all be zero; minimum `cross_squared` must remain strictly greater than `1e-12`; and frozen volume must pass. Only if equal-LOD passes, continue automatically through controls 6/6, ROI rays 0/25, volume reconfirmation, mixed-LOD conforming realization, deterministic repeat, full E2E, then `scripts/validate.ps1`. A failure at any gate stops later gates; preserve candidate and raw evidence. Headless timings are not presented FPS or GPU completion.

No target execution, downstream geometry gate, full E2E, or full validation has occurred as of this checkpoint. Results will be recorded in a new immutable checkpoint before the campaign advances or closes.
