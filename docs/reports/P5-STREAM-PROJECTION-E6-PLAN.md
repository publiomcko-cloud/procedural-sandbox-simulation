# P5 E6 — bounded projection pipeline throughput test (DO NOT MERGE)

From unchanged E2 coarse-first `exp/p5-stream-phase2-causal`; the rejected E3/E4/E5 variants are not included.

## Measured bottleneck

- Last 16-run E5 A/B: source generation p50 ~1.6ms; projection build p50 ~59–65ms; E5 pair-cross only 1–2% worker improvement and zero definitive regions at 54m/s.
- E5.1 stage profiler (12 equivalent rock geometries) isolated 7.10ms preparation/wear + 6.25ms roughness + 2.74ms intersections. E5.1 local noise reuse lowered standalone shape time 16.31→15.57ms (~4.5%) without materially changing overall throughput.
- Two projection workers can remain saturated by expensive worker tasks; the current per-frame publication cap is 1. Worker construction and source scope publication must both be complete before a new LOAD chunk can sample canonical effects.

## E6 intervention

Opt-in profile `adaptive-skip-coarse-pipeline` increases **projection worker capacity from 2 to 4** and **canonical source projection publication cap from 1 to 2 per frame**, keeping **source generation workers at 2**, all mesh workers, meshes, object sources, mod rules, project/caches, SDF, world revisions, effect generation, snapshot authority, edit transactions and coarse-first visuals unchanged.

No new workers are spawned on startup; the existing Godot WorkerThreadPool admits up to 4 projection tasks. All source/projection result validation, revision checks and cancellation retain the same rules. The parameter is opt-in and baseline profile remains untouched.

## Acceptance

1. Import, GDScript parser, E2 preview and adaptive budget unit tests, direct runtime cap tests, original issue108 effect projection/worker-prevalidation tests, real-scene profile proof with `source_worker_limit=2`, `projection_worker_limit=4`, `publish_limit_per_frame=2`.
2. Sixteen 720-frame cold-world A/B/B/A trials at idle, 18m/s, 54m/s and outback54m/s, seed 424242, same exact Godot 4.7.2 SHA and physical runner. Capture original and variant effect publication counts, projection worker timing, LOAD completions, frame >20ms and perceived coverage. No cross-SHA comparison accepted as causal proof.
3. Reject if >20ms frames rise ≥1 percentage point in any route, process mean rises >0.5ms, perceived focus holes rise ≥1pp, or authoritative LOAD count drops >1. A performance candidate requires observable increase in total authoritative LOAD completions and no guardrail failures.
4. Qualify inherited P4/P5 contracts and real GUI 360-frame run before any merge. No automatic merge/deploy. If rejected, document and disable automatic workflow dispatch.

Possible bottleneck after this intervention: 16-chunk complete-region publication barrier, or cold 9x9 source halo. More worker concurrency cannot alone remove those semantics.
