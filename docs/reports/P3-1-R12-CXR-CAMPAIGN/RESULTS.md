# P3.1 R12-CXR Field-Support Campaign

## Disposition

**`R12_CXR_PARTIAL_WITH_EVIDENCE`**

The single frozen target began CXR local candidate generation, so the one-shot geometry attempt is consumed. It returned `PARTIAL`, not an equal-LOD result and not a finite-domain infeasibility finding. The implementation stopped before completing the declared L0–L3 domain and before processing the second expected cavity. The target must not be rerun under this campaign authorization.

## Identity and preserved scope

- Measured source: `0a967c996476e9bf4376b1e55dbb835cf5a31ee6`
- Direct parent: `ebb4e990b71df0ded64939152b273ea092f07e4f`
- Measured tree: `34fc37357a60a1adfd3e2e5fbd43dbdfc47dc8c5`
- Branch: `exp/p3-1-r12-cxr-field-support-micropatch`
- Parent evidence branch: `exp/p3-1-r12-cx-residual-micropatch`, PR #211, then open/draft/unmerged
- Frozen C6 measured source: `4535f4c965db67adab7c93e448492c54be916c92`
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`
- Target: `R9.2.SEAM.XPLUS_EQUAL.v1`; attempt ID `r12cxr-target-20261031-01`

The test-only change preserves the frozen C6 root/arc/face authority, root coordinates, Candidate D volume, original cutoff `cross_squared > 1e-12`, controls, and ROI ray oracle. No production path, save, schema, native dependency, Issue #108/#154 work, or protected F2-G1 state was changed.

## Frozen input and source verification

The Stage 0 fixture was extracted from the prior R12-C evidence archive only after verifying archive SHA-256 `6550788363d1e0ea23df7ed2f560dbf0558fb6c45d769dc642661516c39b4dcb`. Its archive entry was `r12c_stage0_topology_fixture.json`, SHA-256 `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`. The pinned R12-CX residual fixture SHA-256 is `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23`; the canonical R9.2 manifest SHA-256 is `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.

Before target execution, the exact-source cold editor import, realizer `--check-only`, campaign class `--check-only`, contract class `--check-only`, campaign check-only, and CXR contract tests all passed. The campaign check-only emitted its topology preflight and `R12CXR_CAMPAIGN_CHECK_ONLY_PASS` without target or local-search markers. The contract suite passed **56 assertions, zero failures**. The original development test failure and launcher/preflight recovery notes are retained in the raw bundle as non-acceptance history.

## One-shot target result

The launcher validated source, manifest, fixtures, and executable identity before creating exactly one Godot process. The process record reports PID `42364`, parent PID `37584`, Godot exit code `0`, duration `4029.8958 ms`, one `R12CXR_TARGET_INVOCATION_BEGIN`, and one `R12CXR_LOCAL_PATCH_SEARCH_BEGIN`. Stdout SHA-256 is `40fffef05c7cf8df1f58b653583458f92c50fba4f6c40375d9a1cd3b2bb8c841`; stderr was empty. The result JSON SHA-256 is `c7db29fa1fbd42e9bf48f9c2bd24cae8b724e1c74ac0814773507308756df664`.

The process monitor sampled free Windows commit eight times. Minimum observed free commit was `11006529536` bytes; the 2 GiB abort guard did not trigger, and the 3 GiB warning threshold was not crossed. This is system commit telemetry, not process RSS or a performance acceptance result.

The three frozen residual faces were reported by the input fixture. The first processed cavity contained these two residual triangles:

- `60,8,25|tet:1|c4-source:0`
- `60,8,25|tet:2|c4-source:0`

The fixture's third residual face is `62,9,24|tet:2|c4-source:0`; it does not appear in the emitted cavity result. The campaign returned on the first failed cavity before capturing a terminal result for the other frozen cavity.

At L0, the source patch had 2 triangles. Candidate generation recorded 492 attempts: 121 accepted field-derived candidates, 314 outside-tetrahedron rejections, 30 topology-root coincidences, and 27 frozen-field residual rejections. It retained 84 unique support candidates. Their fan checks emitted 150 candidate triangle rows: 28 failed the unchanged cutoff and 56 failed winding; no complete valid fan option remained for the residual faces. No support vertex was selected. Search nodes and branches were both 0.

At L1, the expanded 8-triangle patch was rejected by `_boundary_state` with `cx_patch_nonmanifold_edge`, incidence 3, on the edge diagnosed in the target JSON. The realizer returns immediately at [p3_1_r12_cxr_field_support_realizer.gd:205](../../../game/tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd#L205) instead of recording that level and trying L2/L3. `realize_cxr` also returns after the first unsuccessful cavity, so no result was captured for the second expected cavity.

No preregistered numerical cap was reached. Nevertheless, `search_complete=false` and `search_exhaustive=false`: the failure is **incomplete search**, not proof that CXR support vertices cannot realize the frozen geometry. The minimum correction for any separately authorized future attempt is to retain the invalid-boundary diagnostics and continue to the next allowed cavity level, while preserving fail-closed acceptance; collect diagnostics for all frozen cavities when bounded resources permit.

## Sequential gates

The target did not produce a complete equal-LOD mesh, so equal-LOD acceptance failed closed. Consequently, controls 6/6, ROI rays 0/25, volume reconfirmation, mixed LOD, deterministic target repeat, full E2E, and `scripts/validate.ps1` were **not run**. This follows the preregistered stop-on-failed-gate rule. No downstream or visual acceptance is claimed. Performance is UNSCORED.

## Evidence archive

The raw evidence archive is [r12cxr_partial_evidence.zip](evidence/r12cxr_partial_evidence.zip), SHA-256 `3a7b5d810fa260abf94975ff098e05c3e7bff6587eee9fdc7fd5376950e0c837`, containing 39 hash-indexed members. [evidence-index.json](evidence/evidence-index.json) lists member sizes and hashes; `evidence-archive.sha256` pins the archive. The archive was reopened and every member independently rehashed against the index.

## Protected state and next boundary

PRs #207–#211 remain untouched; #207–#211 were verified open, draft, and unmerged before the new CXR publication. No merge or production adoption is authorized. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

Because local candidate generation started, this target cannot be retried in this campaign. The source-level correction and any new target run require independent review of the exact resulting source and separate authorization; do not treat this partial attempt as a failed-valid or exhausted R12-C line.
