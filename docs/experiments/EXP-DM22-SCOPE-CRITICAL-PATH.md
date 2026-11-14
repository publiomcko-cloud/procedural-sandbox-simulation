# DM22 — Per-scope effect source critical path with instrumented A/A control

## Goal and baseline-equivalence constraint

Measure **per source region** the lifecycle `queue → generation worker → source finalize → projection worker or cache → main-thread scope publication`. Link each blocked `first_focus_chunk` to the exact original list of missing source scopes and the *last source that becomes ready*, including wall-clock waiting, phase breakdown and success/cancel events.

**Non-negotiable:** unlike DM17/DM19 exploratory trace OFF/ON comparisons, both DM22 benchmark arms run **the same trace hooks** with `SANDBOX_DM22_SCOPE_TRACE=1`, `SANDBOX_DM19_COLD_DIAGNOSTIC=1`, `SANDBOX_DM18_DIAGNOSTIC=1`, `SANDBOX_PERF_TRACE=0` and the same full receipt format. An A/A pair varies only the run label and execution order. There is no treatment algorithm yet. This measures runner noise and discovers a grounded target before proposing an A/B optimization. Any eventual A/B DM22 treatment must preserve **identical observer code, scope bookkeeping, aggregation and sampling in both arms**; only one scheduler behavior may differ. Thus no uninstrumented baseline advantages or instrumentation-induced false negatives.

## Observability and safeguards

Branch `exp/dm22-effect-scope-critical-path`, based on `exp/dm19-cold-canonical-attribution` (DM18 cache preserved; DM20/DM21 rejected optimizations OFF).

- `game/scripts/diagnostics/dm22_scope_lifecycle_probe.gd`: no per-frame prints or files, bounded active scopes (640), focus request entries (192), per-latency samples (2048). Decomposes wall-clock source time into queue wait, generation queue/worker, source finalize, projection wait/worker, main-thread publication. Tracks cancellations due to window changes, urgent reorders, cache hits. Stores recent publication details for last-dependency critical attribution. Worker CPU times are **not** to be summed as nonoverlapping wall time.
- `game/scripts/terrain/terrain_object_effect_runtime.gd`: observer-only hooks at unique scope admission, source generation dispatch/completion, source cache path, projection queue/completion (or cache bypass), authoritative publication and discarded work. Returns missing source-region identities **only with observer enabled**. No work-concurrency, projection routing or source priority changed.
- `game/scripts/terrain/terrain_demo.gd`: wrapper captures first attempted chunk of the currently focal `LOAD` region, assigns the exact pending source set, and marks first successfully dispatched canonical chunk or cancelled stage. Only the benchmark activates this code. Warm runs clear diagnostic counters at the end of 900 stationary frames while retaining in-flight source identity/age and DM18 resources.
- `game/tests/experiments/dm22_scope_lifecycle_contract.gd`: synthetic ordered event lifecycle and scope-ID correctness, first-focus 42ms blocking, critical last source, dominant queue phase, cancellation, and bounded ledger.
- `scripts/perf/run-dm22-scope-aa.ps1` and `.github/workflows/dm22-scope-critical-path.yml`: identical diagnostic baseline and repeat conditions, ABBA order with isolated APPDATA, deterministic seed 424242, exact route 18m/s wall clock, no heavy per-frame trace, Windows Godot 4.7.2 parser and old DM11/DM18/DM19 regression gates.

### Test matrix

Smoke: 2 A/A cold-straight pairs, 1 warm-straight pair (6 trials).

Replication: 4 cold-straight pairs (8 runs), 4 warm-straight pairs (8), 2 2400-frame prewarmed outback pairs (4), 2 idle pairs (4) = **24 runs**. All keep `SANDBOX_DM18_CANONICAL_CACHE=1` and all flags DM17-A/B, DM19-B, DM20-A/B and DM21-A/B **OFF**.

Captures paired null-control differences in canonical focus absence, p99, >33ms, HIGH full-fill and worker totals to characterize machine variation; per-scope p50/p95/p99 queue, generation, projection and publish; last dependency before first focus chunk; cache hit and cancellation counts. The A/A comparison **must not be misrepresented as a candidate improvement**. It is the required equal-cost performance baseline for subsequent intervention.

### Possible next decisions (not preapproved)

If last critical source is queue-bound, experiment with scheduling that scope first **but retain exact same observer in both A/B arms**. If generation CPU dominates, inspect source generation cost and caching before increasing worker parallelism. If projection or publication dominates, isolate pure builder vs main-thread reconcile budgets. If many sources are canceled and requeued, inspect window churn/positive cache without expanding the authoritative radius. Preserve revision-gated publication, object mod-first authority, DM18 cache, full HIGH and 18m/s benchmark; test GPU and edits/undo/caves before promotion.

**Status at initial publication:** code integrated in experimental branch, CI exact + A/A smoke and replication launched, `main` untouched.
