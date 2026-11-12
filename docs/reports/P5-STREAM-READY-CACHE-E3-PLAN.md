# P5 streaming E3 — revision-gated negative readiness cache

Experimental only, do not merge. Starts from phase-2 causal branch, with deterministic benchmark and separately qualified GPU runner.

## Hypothesis
A blocked LOAD stage's next chunk repeatedly probes the same unavailable effect scopes. An event-invalidation keyed by source projection readiness plus stage token, stage submit index, edit revision and effect authority revision can suppress redundant preparations until something changes, without a full 25-source read for each target or reordering every source queue per frame.

## Design
- New opt-in runtime profile: adaptive-skip-coarse-ready. Existing profiles remain unchanged. Keep E2 preview rules and geometry exactly.
- Only negative results from canonical pending effect snapshots for LOAD stages are cached. Edit, partial and full stages are never cached or excluded.
- A readiness epoch advances on projection publish, synchronous source reconcile, invalidation, refresh, eviction, and release. Cache is also invalidated if stage token/chunk index/revisions change; live brush/effect authority is checked before exclusion.
- A 30-frame retry TTL ensures liveness even if an epoch event is missed. Cache bound 64 stage IDs. No changes to worker count, upload cap, mesh resolution, hard revision validation, simulation, persistence or source halo.
- Cached exclusions do not consume the existing three fresh-skip budget. The existing canonical snapshot is mandatory before mesh worker dispatch.
- Telemetry: ready_cache_hits, ready_cache_pending_probes, ready_cache_epoch_invalidations, ready_cache_entries.

## Qualification
1. Godot parser/import, source-coarse and stream selector tests, new negative cache unit tests, headless runtime smoke with effective profile proof, preview publication, and real cache hits.
2. Existing P4/P5 qualification suites on exact SHA (service runner).
3. 16 exact 720-frame cold world ABBA trials over idle, 18m/s, 54m/s and out/back 54m/s, comparing adaptive-skip-coarse vs adaptive-skip-coarse-ready. Treat sampled >20ms change >=1pp, mean process >0.5ms slower, or perceived focus holes >=1pp worse as performance rejection; additionally require a real dispatch CPU gain.
4. Rejected or unqualified experiment is not promoted, even if unit tests pass. GPU performance validation only after controlled headless evidence is promising; one GUI screenshot alone cannot prove faster mesh readiness.

## Exclusions
Prior E1.1 (full halo readiness and queue sorting) had a frame-time regression; it is not copied. This E3 remains a minimal negative cache. It cannot by itself accelerate object-source worker generation, so zero definitive regions at 54m/s may persist even if scheduler CPU improves.
