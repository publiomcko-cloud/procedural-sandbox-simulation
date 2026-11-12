# P5 E5 — optimize pure effect projection geometry critical path

Branch `exp/p5-stream-projection-core-e5`; **DO NOT MERGE** until validated.

## Evidence/hypothesis
The last E4.1 cold-world traces show source generation p50 ~1.6–1.8ms, source finalization ~0.6ms, and projection build p50 ~47–73ms per scope, dominated by `effect_frame_build`. The convex shape descriptor's `_intersection_vertices` recomputes three oriented plane cross-products for each candidate plane triple. Cache oriented plane-pair cross-products inside an **experimental worker-only** method. Complexity changes the number of cross-products from O(P³) to O(P²); all triple candidates, numeric operation ordering, containment checks, duplicate filters, source revisions, world source digest, and snapshot validation remain identical.

## Safety
- Existing `adaptive-skip-coarse` uses unchanged `Shape.build` and `Effect.build_from_instance` defaults. New profile `adaptive-skip-coarse-projection` sets the worker flag.
- Keep 2 source workers, 2 projection workers and 1 publication per frame, and current coarse-first revision-gated visuals.
- Preflight rejects non-identical *exact* descriptor fields, vertices, prevalidated snapshots and source SHA digests for 12 mod-derived geometry seeds plus generated effect instances in 3 world regions.
- Only then run original 16 cold-world ABBA 720-frame trials, seed 424242, on pinned Windows runner against E2 coarse-first on same HEAD. Compare projection worker p50/p95 and authoritative LOAD completion count, frame >20ms, main processing cost and visual holes. A pass in the harness is not evidence of performance gain.
- Fail closed and leave main untouched for any parity mismatch, regression, or missing telemetry. Full P4/P5/GPU visual gates are necessary before promoting any promising candidate.

This experiment speeds one bounded pure worker stage. At 54m/s, the 25–36 source halo may still exceed the time between moving region windows; 0 definitive regions may persist.
