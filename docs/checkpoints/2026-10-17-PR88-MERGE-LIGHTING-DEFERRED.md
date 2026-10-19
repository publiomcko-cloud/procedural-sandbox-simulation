# Post-merge checkpoint — PR #88 P1.0B, lighting deferred

**ID:** `CHK-2026-10-17-PR88-MERGE-LIGHTING-DEFERRED`  
**Event:** explicit owner-approved integration of P1.0B with known unsatisfied lighting requirement intentionally postponed to the *next interaction*.  
**Created:** 2026-10-17. **Document publication:** prepared in separate draft [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87); the post-merge checkpoint itself is not merged until explicitly accepted. No feature changes or merges are authorized by this document.

## Verified repository and owner decision

- Repository: [`publiomcko-cloud/procedural-sandbox-simulation`](https://github.com/publiomcko-cloud/procedural-sandbox-simulation).
- [PR #88](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88) merged and closed; reviewed feature head `2e0ecd04aba3bbd1a8c2ba8f915f0c3402ff6a26` direct parent `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0`, actual merge SHA **`13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`** with first parent `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0` and second parent the reviewed head. Verified GitHub `main` at `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`.
- Exact owner decision: **"faça o merge e deixe para corrigir a luz na proxima interacao, ja produza o proximo passo pos merge"**. This explicitly accepts deferring the **known visual defect**, not a statement that lighting was repaired.
- Independent exact SHA [source review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88#pullrequestreview-5559876793): `PASS_SOURCE_REVIEW_WITH_CAVEATS`. [Owner GUI report](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/88#issuecomment-6240529628): load/unload behavior progressive and responsive to navigation, **auxiliary lighting made no perceptible difference**; no final all-controls GUI proof.
- Separate prior docs post-merge/GUI records from draft PR #87 remain part of the document tree; their historical publication states are not retroactively rewritten.

## Integrated functional scope and bounds

- Requested Chebyshev radius 1 (3×3) around focus; completed region residency through radius 2; cap 25 visible regions/400 chunk nodes. Incremental one two-cell-high SDF mesh slice per `_process` frame, ten slices/chunk, region published when 16 meshes complete. Edited region data persists **only in memory** up to 16 edited regions, each capped to existing brush limits.
- Canonical region ownership, negative coordinates, deterministic generator v1, seams and global cave section, focused-region bounded carve/fill, C/R/X and camera controls retained.
- Camera-child `SpotLight3D` is installed but **visual depth improvement is NOT accepted**; scene contains ambient 1.5, oblique directional 1.3 and weak camera spot 0.42/range 72. Lighting is the bounded next follow-up.
- Developer reported Godot 4.7.2 `ed1daf0bf` import/startup/headless **7,943 assertions and zero failures**; reviewer inspected source but did **not** independently execute Godot. Hosted [Starter checks #39056495590](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/39056495590) PASS is static only. Reported initial fill ~9.96 seconds headless, peak synchronous slice 20.551 ms, peak controller 20.676 ms; one slice/frame does not guarantee 60 FPS.

## Known residual risks, separate from lighting

- A failed load stage has no automatic same-focus retry after removal from queue.
- Canonical edit can be accepted before a partial remesh that later fails, leaving temporary logical/render divergence.
- Missing injected error and rapid C/R/X focus oscillation regression coverage. These are documented risk hypotheses, **not** reproduced ordinary-path failures and not silently resolved by merge.
- No cross-region brushes/P1.0C, persistence, LOD, collisions, networking, server authority or Voxel Tools production acceptance. Five F2-G1 protected operational holds unchanged.

## Next action — prepared, no implementation started

- [Issue #89](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/89): lighting contrast correction only; exact existing remote branch `fix/p1-0b-terrain-depth-lighting` created at `13d08b828553df4a3b2bb9d3eb783b4cc3f45beb`.
- Owner requested **defer implementation until next interaction**. Use only `C:\Dev\sandbox-sim-dev`; inspect clean/dirty state and fetch latest `origin/main` before switching. Do not modify the ongoing Windows workspace now.
- Improve exterior slope/cavity depth with empirical ambient/key/fill balancing and before/after same-pose GUI screenshots; preserve SDF, streaming, gameplay, Godot 4.7.2 and performance observability.
- After Codex makes a new candidate draft PR, independently review new SHA; owner checks actual light effect and separately authorizes any future merge. P1.0C is not authorized by this issue.
- This documentation PR #87 also remains **unmerged**; the merge receipt and new state will be integrated only through a separate owner-approved documentary merge.

**Recovery:** inspect live refs and [CURRENT_STATUS](../status/CURRENT_STATUS.md), [checkpoint index](INDEX.md), and [AGENT_RECOVERY](../workflow/AGENT_RECOVERY.md). This record does not restore unsaved changes or credentials.
