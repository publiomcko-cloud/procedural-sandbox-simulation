# P1.0C PR #92 — owner GUI performance blocker, 2026-10-18

**Checkpoint ID:** `CHK-2026-10-18-P1-0C-OWNER-PERFORMANCE-BLOCKER-PR92`  
**Event:** owner reported severe latency for sculpting and region load/movement after independent source rereview accepted code correctness.  
**Status:** `OWNER_GUI_PERF_FAIL / PERFORMANCE_CORRECTION_REQUIRED / NO_MERGE`; recorded on **open draft** documentation [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87), **not integrated on main**.

## Owner observation and new priority

Owner wrote: **"esse tempo de adicao e remocao de terreno ficoumuito alto mesmo, quando clico tenho que esperar, deveria se instantaneo ou quase imperceptivel, o tempo de geracao dos chucks quando inicio ou movo tbm ta muito lento, se tiver algum limitador deveriamos remover, ou executar melhorias de performace"**.

This is a **user GUI usability FAIL**, not an observed geometry crack. The earlier [exact-SHA source rereview PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5563949929) still supports normal dependency/canonical edit correctness, but does **not** override the separate GUI performance acceptance gate. Do not merge PR #92 until performance work is independently reviewed and the owner finds it responsive enough.

## Verified GitHub identity / evidence limits

- Repo [publiomcko-cloud/procedural-sandbox-simulation](https://github.com/publiomcko-cloud/procedural-sandbox-simulation); remote `main` verified `2f86c42503cfa3a334215b1ff5b9bf9658263440`; feature [PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) still **OPEN/DRAFT/UNMERGED** at exact observed `163ef37a1ec0aab33dfea773a4176fae470161d8`.
- Local Codex reportedly validated Windows Godot 4.7.2 8,083 assertions before this complaint; reviewer did not run owner-host Godot; hosted GitHub check was **static-only**.
- [Issue #93](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/93) captures this performance acceptance blocker and a bounded **same-PR #92** optimization plan. PR [comment](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#issuecomment-6252754343) records owner feedback, targeted hotspots and no-merge gate.
- No new source commit, altered SDF, modified Windows worktree or feature merge was performed in this documentation event.

## Source-grounded initial performance diagnosis, not measured speedup

- `terrain_demo.gd:15` configures `MAX_MESH_SLICES_PER_FRAME=1`; the mesher processes `CELLS_PER_MESH_SLICE=2` of 20 Y cells, 10 slices/chunk. Hence **40 process frames minimum** to rebuild four chunks; **160** per new complete region; **1440** to complete a new nine-region / 144 chunk window. At exactly 60 FPS those are *respectively 0.667s, 2.667s, 24s*, **before** CPU time and UI stalls. These figures are bounds on schedule steps, not measured throughput or total elapsed time.
- All slices currently execute synchronously on the **main rendering thread**; even a single slice cost exceeds a 16.67ms 60Hz frame in the developer's previous report. `marching_tetrahedra.gd` builds temporary `ArrayMesh` per vertical slice and then reads and concatenates them into another chunk mesh; lattice planes/gradients are resampled and short-lived corner arrays are constructed. A full global command scan per density query and per-frame HUD plus 512-item percentile sort are additional potential costs, **not yet individually profiled**.
- Last developer local headless global brush ~3,315ms for two regions/four chunks/40 slices, slice peak ~30.3ms and `_process` peak ~67.5ms; earlier ~281ms was a different benchmark and should not be treated as a stable baseline. Owner's actual GUI confirms an unacceptable delay.

## Bounded optimization and evidence gates

1. Profile identical pre/post scenarios for cold nine-region fill, new-region movement and return, 1/2/4 chunk/region carve and fill, reset X and C/R, with 0/1/32 existing commands. Capture click→visible commit latency, queue waiting, CPU field/polygonization/normal/mesh-upload breakdown, frame p50/p95/p99, memory and queue peaks. Do not rely on a single headless measurement.
2. Optimize CPU-side density sample and mesh extraction paths; eliminate intermediate `ArrayMesh`/readback for slices, repeated sample planes/gradient queries and expensive per-frame instrumentation, without changing canonical SDF semantics or full mesh normal/seam equivalence. Index ordered commands carefully; do not ignore operations outside geometric sphere if the current SDF algebra can still be affected.
3. Prioritize interactive edits over speculative streaming and replace **fixed one-slice-per-frame** with a measured bounded work budget or safe background CPU generation, **not** an unbounded multi-chunk synchronous main-thread freeze. Keep all MeshInstance3D/scene modifications and final mesh upload safe on the main thread. Verify revision, cancellation, coherent multi-region publication and no stale staging under rapid navigation/C/R/X.
4. Aspirational typical click→visible target ~100ms for interior, ~200ms for ordinary border; try to reduce cold window by ≥3×. These are targets for real repeatable profiling, **not promises**. If unattainable in pure GDScript, report measured bottlenecks and alternatives for separate owner backend/native authorization; do not silently reduce geometry or claim instant responsiveness via a fake preview.
5. Preserve Godot 4.7.2 baseline, global 32-command ledger, correct region/sample halos, positive/negative seams, in-memory replay, exact ownership, existing lighting and safe F2-G1 holds; all existing/new tests must pass and owner must run GUI and accept new responsiveness.

**Next authorized action:** continue existing `feat/p1-0c-global-cross-region-brushes` and **same PR #92** in only `C:\Dev\sandbox-sim-dev`. Preserve `stash@{0}`, no clean/reset/new worktree, no separate feature PR or automatic merge; new exact-SHA code review and owner GUI performance PASS required. Docs-only PR #87 remains separate; reconcile overlapping status/index later. No persistent saves, multiplayer/networking or protected host work is authorized.
