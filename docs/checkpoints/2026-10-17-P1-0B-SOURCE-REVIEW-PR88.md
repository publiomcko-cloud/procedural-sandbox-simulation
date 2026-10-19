# Checkpoint — P1.0B PR #88 independent source review (2026-10-17)

**ID:** `CHK-2026-10-17-P1-0B-SOURCE-REVIEW-PR88`  
**Event:** owner-authorized P1.0B streaming + camera-aligned auxiliary light implementation handoff, independently reviewed at an exact GitHub commit.  
**Publication:** `RECORDED_IN_DRAFT_PR / NOT_INTEGRATED` on docs-only [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87), separate from Codex workspace and feature [PR #88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88).

## Verified Git refs and scope

- Repo: [publiomcko-cloud/procedural-sandbox-simulation](https://github.com/publiomcko-cloud/procedural-sandbox-simulation); `main` verified at `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0` (owner-authorized P1.0A merge of #86).
- Feature [PR #88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88) **open/draft/unmerged** with reviewed exact head `2e0ecd04aba3bbd1a8c2ba8f915f0c3402ff6a26`, sole parent `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0`, 18 changed paths. Codex worked in owner-designated `C:\Dev\sandbox-sim-dev`; source reviewer did not alter this workspace.
- Review evidence: [PR #88 SHA-specific review 5559876793](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88#pullrequestreview-5559876793). Verdict `PASS_SOURCE_REVIEW_WITH_CAVEATS / OWNER_GUI_PENDING`.
- Owner directly authorized **P1.0B only**, including a moderate camera-aligned light; prior Issue #83 status that called P1.0B plan-only was superseded by this owner instruction. P1.0C cross-region edits remain unapproved. Documentation PR #87 remains independent, also unmerged.

## Source and test evidence

- Camera focus maps by half-open signed floor to requested Chebyshev-radius-1 window (3×3); retain completed region meshes through radius 2 (max 25 visible regions/400 chunk meshes). Out-of-window loads are canceled when focus region changes. Partial edits and full C/R/X staging wait for required meshes before publication.
- `terrain_demo.gd`: processes up to one main-thread 2-Y-cell mesh slice per rendered process frame; ten slices per chunk, each 16-chunk region published as one complete set. The feature preserves region ownership/negative coordinates, SDF v1, global cave section, safe focused-region transient edits and bounded 16 edited states across unload/reload.
- `terrain_demo.tscn` adds low-energy camera-child `SpotLight3D` (0.42 energy, 72 range, 58 angle, no shadow), retaining existing directional, ambient and lit green material. Lighting assertions are **scene-configuration checks**, not pixels.
- Developer reports Godot 4.7.2 stable `ed1daf0bf` import/headless/main startup, total **7,943 assertions, zero failures**: 52 smoke + 40 SDF + 89 brush + 179 chunks + 7,565 multi-region/streaming + 18 bootstrap. Reviewer source-inspected the suites and validator; **did not independently run Windows Godot**. [Starter CI run 39056495590](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/39056495590) PASS is **static only**, with logs expressly stating runtime is not executed.
- Local developer measurements: initial 9-region fill ~9.96s headless, 144 chunks and 87,077 triangles; worst indivisible slice ~20.551ms and controller process ~20.676ms, exceeding 16.67ms budget for 60Hz. Slicing bounds *work count per frame*, not frame time. Mesh combination and publication are also synchronous.

## Caveats, missing evidence, owner gate

1. **Failure recovery gap (potential, not reproduced):** when `_fail_region_stage` drops an incomplete load, unchanged `focus_region_key` makes `_reconcile_region_window` return early and does not automatically retry. A visible stream error is shown, but a moved focus is necessary to restart unless another operation intervenes. Add injected-failure regression and decide finite retry policy.
2. **Partial-edit transactionality (potential, not reproduced):** `state.apply_sphere` modifies canonical edit list before staging the partial remesh; if mesh generation fails, it keeps the old visible mesh while canonical data has changed. Define rollback or bounded retry and add failure-injection tests before claiming fault-tolerant streaming.
3. **Untested fast travel/global refresh:** ordinary traversal, queue caps and seam checks passed developer-reported tests; repeated focus oscillation during global C/R/X and injected failures are not explicitly covered. A 25-region global commit can also create a frame spike despite single-slice scheduling.
4. Current handoff says one *mesh* per frame; actual bound is one **vertical slice** per frame. Correct documentation when reconciling PR #88 before final acceptance.
5. Owner **GUI/pixel test PENDING**: wait for 9 active and zero queued, D twice -> region (1,0), A five times -> (-1,0), leave/return, watch new region appearance, seams and queue, inspect carve/fill, boundary rejects, C/R/X, orbit/zoom and spotlight/depth readability. Watch GUI filling time, frame hitches and errors.

**Next authorized action:** owner performs GUI acceptance on exact PR #88 SHA and reports visible behavior; any correction on #88 requires another SHA-specific review. PR #88 remains draft/unmerged and is not authorized for merge. Concurrent docs-only PR #87 and feature PR #88 both modify `docs/status/CURRENT_STATUS.md` and `docs/checkpoints/INDEX.md`; explicitly reconcile branch order/diff before either future merge. All five F2-G1 protected holds unchanged; no native/ACL/VM/credential work or P1.0C/networking scope implied.

A checkpoint records decisions and verifiable references; it cannot restore private runtime environment or unsaved local work.
