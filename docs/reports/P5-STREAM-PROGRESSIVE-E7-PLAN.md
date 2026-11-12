# P5 E7 — revision-gated progressive authoritative chunk visibility (experiment)

**Isolation:** `exp/p5-stream-progressive-chunks-e7` from proven `exp/p5-stream-phase2-causal`; do not merge until test evidence and full P4/P5 + GPU visual qualification pass. No changes to `main`.

## Current barrier

The 4×4 (16 chunk) LOAD stage buffers each completed canonical ArrayMesh in `stage["meshes"]` but calls `_publish_region` only after all 16 meshes finish. At 54 m/s, no whole region completed in the prior 720-frame ABBA series despite hundreds of source projection publications. This does not prove zero *chunks* were built; they were hidden behind the region-level publication barrier.

## E7 intervention and boundaries

- Opt-in `adaptive-skip-progressive` profile. For pristine, unedited and non-rebuilding `purpose=="load"` stages only, submit the four interior chunks first, then faces, then shared corners. All 16 original chunk tasks, full 9x9 source authority and shared seam/sampling code are retained.
- Every fully uploaded ArrayMesh is verified against current stage token, brush revision, effect authority revision, LOD selection and global edit/rebuild gate. Bounded to at most 2 provisional chunk-node publications per frame and 2.2ms elapsed budget; frame spike veto at 20ms. The nodes appear visually only and are **not entered in `active_regions`**.
- Region, object, simulation, placement and environmental source publication remain governed exclusively by the original `_complete_region_stage -> _publish_region` 16-chunk commit. The final publisher **adopts** any stage-token-matched preview nodes without duplicate GPU mesh replacement.
- The coarse-first derived overlay is partitioned into the existing 16 chunk rectangles on the preview worker from the **same** 96 triangles. Each patch can be hidden when its matching definitive chunk becomes visible, without Z-fighting or a hole in the remaining coarse terrain. The original E2 preview remains unchanged.
- Stage invalidation, brush/edit command scheduling, failure/retry, full rebuild, unloading and normal streaming-window changes discard provisional nodes. Stale async completions are rejected by the existing stage token and revisions; all edits/full rebuild transactions retain atomic publication.
- Trace `terrain_chunk_progressive_visible` with stage token, revisions, elapsed time and count. Keep existing `terrain_region_load_complete` unchanged for complete authoritative publication.

## Acceptance gates

1. Godot 4.7.2 parser and scene import. Pure policy tests verify interior-first order without changing coverage, source/brush revision gates, all atomic-purpose vetoes, and exactly clipped coarse patch area (sum == original region). Original E2 preview, stream budget, D6 effect worker contracts must still pass. Real scene must emit both coarse and progressive events. Fail closed on *any* Godot `ERROR:` or `SCRIPT ERROR:`.
2. Original 16 cold-world ABBA 720-frame trials on one Windows runner, seed 424242, profiles `adaptive-skip-coarse` and `adaptive-skip-progressive`, idle, straight 18/54 m/s and out-back 54 m/s. Use the same source SHA and isolated world per run; preserve stdout/stderr/metrics.
3. Evaluate progressive visible chunk count and latency, completed full LOAD regions, mesh dispatches, actual coverage with coarse patches, process mean and frames >20ms. Reject if frames >20ms rise >=1pp, mean processing rises >0.5ms, perceived region gaps rise >=1pp or definitive full region completions fall >1. A candidate must show material earlier definitive chunk visibility (especially at 54m/s) without guardrail violations. Report zero if none, do not infer from coarse coverage.
4. If accepted, run inherited P4/P5 and Windows GPU *graphical* smoke with visual edge checks before any merge. No automatic integration.

**Known limitation:** Progressive publication cannot advance a chunk blocked on its effect-source halo. At 54m/s, interior-first 25-source scopes may still be too expensive. All measurements must distinguish source readiness from the finalization barrier.
