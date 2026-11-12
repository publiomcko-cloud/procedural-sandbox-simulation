# P5 E4 — consumer-driven effect source/projection scheduling

**Experiment only. DO NOT MERGE.** Based on `exp/p5-stream-phase2-causal`, not on the rejected E3 cache.

## Hypothesis

The current moving LOAD window repeatedly requests 25–36 source scopes for the next chunk, but source generation (2 workers max), projection building (2 workers max) and per-frame projection publication (1) can prioritize work for other queued regions first. The load's effect snapshot remains blocked at `effect_pending_corner`.

Focus the existing source queue and completed generation/projection outputs on the **next chunk of the focused visible LOAD**. Leave every authoritative source/projection requested, preserve revision gates, worker caps, edit/partial/full precedence, source generation, and the 9x9 halo.

## Intervention

- Optional profile `adaptive-skip-coarse-demand`. Ordinary baseline/E2 profiles retain original queue order and all existing behavior.
- Pure, bounded source rank derived from the same radius-2 source footprints. Next shared corner has 36 scopes; face has 30; interior has 25. Ranking is advisory, never a cache of readiness or canonical data.
- Rank computations only when the current LOAD's stage token, chunk index, edit revision, effect revision, or camera region change.
- Source generation chooses the highest-priority queued member (without changing queue membership), and completed source and projection jobs are finalized/published with consumer priority when several are ready. Do not preempt in-flight jobs or add jobs.
- Disable demand priority when edit, partial or full rebuild work is pending. No effect on geometry, mods, SDF, hydrology, world save/load or publication authority.
- Trace demand updates and which source generation selections actually prioritize the visible consumer.

## Acceptance gates

1. Godot 4.7.2 import/parse, pure halo and queue-order tests, inherited E2 preview/stream tests, and real-scene smoke confirming the opt-in profile and actual source-demand priority.
2. Sixteen cold-state ABBA 720-frame runs on one pinned Windows runner: idle, 18 m/s, 54 m/s, and out-and-back 54 m/s, with seed 424242. Contrast `adaptive-skip-coarse` and `adaptive-skip-coarse-demand` on identical HEAD. Preserve raw traces and strict route/profile/frame checks.
3. Reject if frames >20 ms increase at least 1pp, mean process cost increases >0.5ms, perceived focus missing rises at least 1pp, or definitive LOAD completions fall >1 per 720-frame scenario. Require a positive aggregate increase in authoritative LOAD completions to qualify as a candidate.
4. Only after comparative success: inherited P4/P5 qualification and GPU/GUI run. Do not merge automatically.

The 54 m/s route may be inherently faster than the 25–36 source dependency halo can be generated, so reduced blocked dispatch attempts alone are **not** sufficient for success. Report observed limits rather than inventing performance claims.
