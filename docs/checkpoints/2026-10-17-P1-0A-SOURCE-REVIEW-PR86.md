# Checkpoint — P1.0A PR #86 independent source review, 2026-10-17

**ID:** `CHK-2026-10-17-P1-0A-SOURCE-REVIEW-PR86`  
**Event:** Codex code handoff and independent GitHub source review of exact P1.0A candidate; no GUI acceptance yet.  
**Publication:** `RECORDED_IN_DRAFT_PR / NOT_INTEGRATED` until docs PR #85 is merged with explicit owner authorization.

## Verified GitHub identity

- Repo: [publiomcko-cloud/procedural-sandbox-simulation](https://github.com/publiomcko-cloud/procedural-sandbox-simulation).
- Latest confirmed `main` at review: `817fc72cd85d5de66932d2aa722d1b077d55bf92` (owner-accepted merge of PR #82); no newer main source accepted by this event.
- Scoped source ticket: [Issue #84](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/84), static 3×3 region preview only; [parent plan #83](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/83) P1.0B streaming and P1.0C cross-region edits not yet authorized.
- Feature PR: [#86](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/86), branch `feat/p1-0a-multiregion-spatial-ownership`, exact reviewed head `27b911e32ea396be6c66436542473093123e1b54`, direct parent `817fc72cd85d5de66932d2aa722d1b077d55bf92`, 18 changed paths; PR was **open/draft/unmerged** at review.
- Independent reviewer record: [PR #86 review 5558985964](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/86#pullrequestreview-5558985964), verdict **`PASS_SOURCE_REVIEW / OWNER_GUI_VISUAL_PENDING`**. Review assessed source, not Godot executable firsthand.
- Parallel docs PR: [#85](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/85), `docs/recovery-checkpoint-2026-10-17`, open/draft/unmerged and updated by this checkpoint; no local Codex worktree changed.

## Source-reviewed implementation and evidence

- Nine *fixed*, adjacent logical 16×12 SDF regions; each owns half-open X/Z cells `[0,16)×[0,12)`, 32×24 at 0.5 step and a 4×4 chunk grid of 8×6 cells. Total **144 chunk render nodes**. Signed floor mapping covers negative positions/region keys.
- Extraction evaluates pure versioned SDF on canonical world coordinates before converting world mesh vertices to chunk-local coordinates; full mono-world reference and chunk union are compared. Original global cave placement is preserved; `C` renders one world-space cut plane at Z=6.
- Center-region only, transient, ordered brushes; neighboring-region and boundary-crossing brush clicks reject without mutation. `R` rebuilds and retains edits; `X` resets. Camera orbit and wheel preserved; no streaming, save, collision, LOD, network or multiplayer.
- Codex developer reports Godot `4.7.2.stable.official.ed1daf0bf`, L0–L2 import/headless startup and **7,917 successful assertions**, 0 failures: 52 smoke + 37 SDF + 89 brush + 179 chunk + 7,542 multiregion + 18 bootstrap. Source inspection confirmed these suites and validator call paths. **Reviewer did not independently execute Windows Godot.** Hosted [Starter checks 39034403497](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/39034403497) PASSED but checks only static file presence, not runtime.
- Specific source test proofs: unique ownership of **6,912 horizontal cells**, **87,077** reference/combined mesh triangles and **264** adjacent seams including region boundaries. These are developer-reported results of source-reviewed test logic, not a full GUI-pixel proof.
- Local Windows Xeon developer measurement: initial synchronous 144-chunk build ~4.67s; position/normal array bytes estimated 6,269,544 only, not process RSS or GPU memory. Local 7-run remesh medians: inside 33.117 vs full 417.328 ms; edge 64.959 vs 404.508 ms; corner 145.509 vs 415.825 ms.

## Residual risks, required GUI gate, next authorized action

1. **OWNER GUI PENDING:** open the pinned Godot 4.7.2 scene in `C:\Dev\sandbox-sim-dev\game` and verify contiguous shaded 3×3 region view, negative/positive seams, no walls/cracks/z-fighting, camera orbit/zoom, global C cut, center carve/fill, rejection of neighbor and unsafe edge clicks, R preservation and X reset. Report startup freeze/slow frame and mis-picks.
2. Long synchronous startup (~4.7s) is accepted as demo limitation, not a P1.0B streaming/frametime claim. Picker samples canonical SDF even outside visible mesh/cut (potential edge/selectability surprises); still must be checked by owner.
3. Geometric full reference and 264 seam tests run against **unedited** global SDF; later cross-region editing will require post-edit region-border/corner parity. Region dimensions exist in both `SdfWorld` and `TerrainSpatialOwnership`; they agree now, but should be protected from drift when generalized.
4. No acceptance of *all P1* or final production terrain backend; ADR-0002 remains proposed/deferred. No protected F2-G1 host/VM/ACL work or release authority is inferred.
5. Owner GUI PASS/FAIL is a **new significant interaction requiring another dated checkpoint**. PR #86 must remain unmerged pending separate, explicit owner merge authorization. PR #85 docs integration is also separately owner-authorized, never automatic.

This checkpoint reconstructs the evidence and exact next decision, not the developer's uncommitted files, environment or credentials. For live current state, verify `main`, PR #86 and PR #85 again.
