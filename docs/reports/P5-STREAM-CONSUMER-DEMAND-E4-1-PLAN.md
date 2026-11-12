# P5 E4.1 — eliminate demand scheduler's measured CPU overhead

Branch `exp/p5-stream-consumer-demand-e4-1`. Do not merge; keep E4 original and E2 baseline unchanged.

## Measured E4 observation
E4 A/B/B/A (16 trials on GitHub runner at SHA `74fcfe8cbb0ba638a937d2fba9a59f54b73bf85d`) improved definitive LOADs at 18 m/s 15 -> 16 on average but **zero -> zero** at 54 m/s. On 54 m/s out-and-back, frames >20ms rose 1.179% -> 2.358%, mean process 6.448 -> 7.048 ms. E4 `consumer_demand_scheduler` cost averaged ~0.31–0.33ms/frame for straight-18 and outback-54 due to repeated rebuilds of the 25–36 source-rank dictionary for new chunk indices.

## E4.1 hypothesis
The complete source-priority rank depends only on a chunk's left/interior/right and top/interior/bottom topology, *relative* to its owning visible region, not on absolute world position. Precompute at most **nine immutable rank templates**, and use the active region as origin for source/projection comparisons.

## Controls
- Assert all nine templates are strictly identical to E4's absolute rank values, for every source in the canonical radius-2 halo.
- Each consumer stage remains keyed by focus, stage token, submit index, brush revision and effect authority revision; the saved templates contain **no readiness, terrain, save, edit, or mod data**.
- Keep the same WorkerThreadPool priority, 2 source-generation jobs, 2 projection jobs, 1 projection publication, snapshot authority and E2 previews. Disable optimization when edit/partial/full rebuild work is pending.
- Re-run original E2 `adaptive-skip-coarse` against optimized `adaptive-skip-coarse-demand` in 16 ABBA cold starts on exactly one SHA/runner/seed/frame trajectory. The original E4 SHA remains a separate reference, not an unsafe mixed-SHA baseline.
- Reject on the predeclared E4 frame-spike, process-mean, visual-hole, or definitive-regression gates. Candidate only if authoritative region load completions improve aggregate without guardrail failures.

Do not run inherited long P4/P5 regression or GUI qualification for a rejected candidate; perform both before any accepted merge.
