# P1.1B-B0 R4a — independent exact-baseline documentary/source review

**Review date:** 2026-10-21, America/Sao_Paulo.  
**Repository:** `publiomcko-cloud/procedural-sandbox-simulation`.  
**Reviewed base:** remote `main` `665c5c883ae88b949f4030f7affc786064999f61` (PR #97 integrated).  
**Reviewer:** ChatGPT, GitHub remote source/documentary comparison.  
**Reviewed artifacts:** owner-provided R4 (381 Markdown file lines) and R4a (104 Markdown file lines), `terrain_demo.gd`, `sdf_world.gd`, `terrain_spatial_ownership.gd`, canonical brush ledger, existing LOD0/LOD1 fixture/test source, owner-approved P1.1 R2. The Codex reports were delivered as chat Markdown attachments, **not** pre-existing Git commits. These exact texts are registered in this docs PR as separate source records.  
**Primary GitHub review:** [PR #97 comment #6314241218](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/97#issuecomment-6314241218).

**Verdict:** `P1_1B_B0_R4A_INDEPENDENT_SOURCE_REVIEW_PASS / OWNER_INPUT_DECISION_PENDING_AT_REVIEW`. Subsequent owner decision explicitly **approved the limited input/methodology subset** and is documented separately in the [2026-10-21 checkpoint](../checkpoints/2026-10-21-P1-1B-B0-R4A-OWNER-INPUT-APPROVAL.md).

## Methodology and confirmed findings

1. Independently read source focus update/reconciliation code: one `_move_focus(Vector3(1,0,1))` from target (15.5,3.2,11.5) maps (0,0)→(1,1) atomically and there is no simulated intermediate region. Verified exact 9→14 active key cardinality **only after** all required publications, with a fully settled initial 9; multi-stage loops yield 9→12→15→16. Former R4 diagonal (+8,+8 units/s) allowed intermediate key (0,1), invalidating a fixed 14 expectation. Historical failed review retained [#6314132611](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/97#issuecomment-6314132611).
2. Verified `active_regions` vs `loading_regions` semantics in `terrain_demo.gd`. R4 and R4a maintain explicit requested, pending, successful publication, cancellation, failure, retained and conditional settled classes. Requested regions are not active before `_publish_region`.
3. Confirmed production viewport brush uses radius **1.25**, canonical `SdfBrushEditState` accepts radius **0.58**, and repeated viewport click effects remain unverified. R4a correctly excludes edited revisit from future executable suite until one fixed-input hit/publication preflight succeeds.
4. Verified source SDF v1 positive-solid semantics: bounded seeded ground and sinusoidal YZ cross-section cave. R4 specifies complete synthetic 0.5/1/2-world-unit tunnel variants and 1.84-world-unit canonical radius-control. R4a refines the disconnected-air ambiguity by selecting a centerline-seeded void component with endpoint connectivity, separately tracking exterior top/bottom components.
5. Source-review implementation qualification: a future tunnel oracle must ensure continuity **through centerline slices**, not merely connectivity through exterior air. Do not claim an executable result before implementation. Six signed LOD faces and corner/edge masks follow source tests.

## Limits and gates

Review is **static**: no Godot runtime, GUI, GPU, benchmark result, measurement sample, final manifest digest, source-change tests or performance acceptance. Existing Codex-reported P1.1A full Godot 4.7.2 16,807 assertions/0 failures are historical and were not rerun here. Source scene/terrain/ledger unchanged by the documentation decision. Stages B1-1 implementation, runtime execution and PR merge require separate owner decisions. No Voxel Tools native operations, backend ADR-0002 adoption, P1.1C, production LOD, or F2-G1 change.

**Owner visual verification:** not applicable to documentary-only planning approval; a later executable GUI/GPU claim requires an owner visual gate.

**Next:** versioned doc-only approval checkpoint and contract (this review, unchanged R4/R4a source attachments, owner scope), separate owner criteria decisions. All five F2-G1 holds unchanged.
