# DM21 — Event-driven effect readiness and bounded unfinished-load retention

**Scope:** normal 18 m/s wall-clock movement, idle and prewarmed/long routes, Godot 4.7.2 on Windows. Preserve **DM18 16-chunk cache** in every experiment. Reject DM20 A/B and keep their flags OFF. No main promotion without headless and interactive GPU validation.

## Source finding and two independent hypotheses

The existing TerrainObjectEffectRuntime already provides *single-flight generation* per source scope through `_prefetch_task_by_scope`, `_prefetch_projection_task_by_scope` and `_prefetch_scope_ids`; there is also a 256-entry projection-source cache and projection-build cache. The missing feature is an event-driven **canonical consumer rendezvous**. Previously, a stage whose effects were not ready repeatedly built its base snapshot, enumerated required scopes and called `_enqueue_prefetch_regions` on each dispatch attempt.

DM19/DM20 measured ~290 effect pending prepares per 720-frame cold run; and DM19 canceled 18–21 `first_visit.left_window` stages in some runs. This suggests two distinct opportunities:

- A — reduce repeated *consumer* snapshot preparation while effect projection source work is already single-flight.
- B — finish already substantially generated **LOAD** stages inside the existing retained 5×5 after the desired 3×3 window moves. Never enlarge effect protected halo or authoritative retention radius.

## DM21-A: scope-published notifications, revision-gated wait

Flag `SANDBOX_DM21_EFFECT_GATE=1` (OFF by default).

`terrain_object_effect_runtime.gd` now emits a monotonically increasing readiness generation on successful source-scope publication, refresh and invalidation; pending returns exact missing `Vector2i` source regions. A per-stage wait is recorded only after the first *real* pending result and the existing urgent enqueue has already happened. Subsequent dispatch attempts do not construct a base snapshot or enumerate source dependencies again until (i) a publication/invalidation event occurs and the originally missing scopes are available, (ii) the current stage token / chunk / brush identity / edit revision / effect revision changes, or (iii) a 500ms watchdog expires to safely recover from canceled/reprioritized work.

Only `purpose=load` participates. Existing edit transactions, shared-surface corner/boundary snapshot logic, revision checks, original skip policy and WorkerThreadPool concurrency remain intact. This does **not** start another source-generation job. It coordinates with the *existing* single-flight system and does not alter authoritative projection semantics.

**Telemetry:** registered waits, suppressed redundant attempts, notification checks, watchdog recoveries and invalidated waits, plus the existing `dm19_effect_runtime` projection count and wait cause metrics.

## DM21-B: bounded partial-stage reuse

Flag `SANDBOX_DM21_RETAIN_PARTIAL_STAGES=1` (OFF by default).

When an existing 16-chunk LOAD leaves the 3×3 desired window, retain it **only** if still in the original 5×5 retained window, at least 8/16 jobs have been submitted and at least 4 have completed. Limit to two such stages per window. Disallow speculation, edit/partial/full stages and already ready DM18-cache stages. All existing submit-worker-publish revision and edit checks still run. Jobs outside the retained 5×5 remain discardable. Publishing a retained stage is allowed only within the original authoritative retained window; objects and simulation continue through the normal publication path. The policy is a test, not a claim that retention saves CPU: retained stages may also create competition with urgent work.

**Telemetry:** retained candidates, retained stages that reached full publication, canceled LOAD stages, and submitted/completed/pending chunks associated with cancellation. DM19 per-reason `first_visit.left_window` and stale-job counters remain available.

## Qualification and factorial test

Branch `exp/dm21-effect-readiness-and-stage-retention`, workflow [DM21 Actions](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43586067986). First preflight result: Godot parse + DM21 28 contract assertions PASS, DM19 23 PASS, DM18 112 PASS, DM11/DM17 geometry parity PASS, existing D7.3 projection source-cache tests PASS. The first CI attempt was a harness-only string mismatch: expected `DM21_EXACT_PASS`, test printed `DM21_CONTRACT_PASS`; corrected in new run.

`scripts/perf/run-dm21-factorial.ps1` uses four groups per Latin-square block: **control, A, B, A+B**, same seed 424242, `adaptive-skip-progressive`, `SANDBOX_TERRAIN_BACKEND=b4`, DM18 ON, 18m/s actual wall-clock; tracing heavy OFF, DM19 low-overhead diagnosis ON. Two 720-frame 18m/s courses (no prewarm / 900-frame prewarm), a 2400-frame prewarmed out-and-back course to expose true new dependencies and revisits, and an idle fill control. Every trial isolates APPDATA. No 54m/s tests.

- Smoke: 16 trials, 2 blocks per cold/warm, all four conditions.
- Replication: 56 trials, 6 blocks cold, 4 blocks warm, 2 blocks long and 2 blocks idle (4 conditions/block).
- Assess **paired** focus missing %, frame p99, percentage >33ms, HIGH count/fill timing, worker jobs, pending effect count, cancelled stages/wasted work, retained stage reuse, DM18 cache hits, notification suppressions; 95% paired CIs. Only 2 long/idle blocks so intervals are exploratory and cannot establish equivalence.
- Worker workload and effects are not meant to differ from baseline except as an indirect result of A and B. No claim of performance win based solely on suppressions/retained counts.
- No promotion unless throughput and gap coverage improve without meaningful tail/visual regressions, plus interaction-level validation of edits, undo, caves, collision and object effects.

## Status

Implementation + contracts qualified. Benchmark smoke and replication in progress as of the initial document; results must be appended from real GitHub Actions job logs. **Default remains DM21 A/B OFF, DM18 preserved as user-approved experimental baseline, `main` unchanged.**


## Evidência do smoke integrado — 16 execuções, PASS

GitHub Actions [43586067986](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43586067986), commit qualificado `7ed9170866184135b43556a66b765c8c7a8e134d`. `exact` PASS, `smoke` PASS. Duas repetições por cenário de 720 frames, mesmos 18m/s, DM18 ON.

| Cenário | Braço | Foco canônico ausente | Frame p99 | Preparações efeitos pending | Retenções / completas |
|---|---|---:|---:|---:|---:|
| Cold straight | Controle | 32,986% | 19,639ms | 278,5 | 0 / 0 |
| Cold straight | A | 41,042% | 20,074ms | 20,5 | 0 / 0 |
| Cold straight | B | 34,514% | 20,761ms | 274,5 | 2 / 0 |
| Cold straight | A+B | 38,820% | 21,950ms | 26,0 | 2,5 / 0 |
| Warm straight | Controle | 0,000% | 24,663ms | 182,0 | 0 / 0 |
| Warm straight | A | 1,875% | 28,444ms | 10,0 | 0 / 0 |
| Warm straight | B | 1,875% | 21,486ms | 173,0 | 0 / 0 |
| Warm straight | A+B | 5,486% | 25,676ms | 12,5 | 0 / 0 |

A efetivamente registrou 19,5 esperas, suprimiu 306,5 repetidas tentativas e observou 127 notificações por cold run; apenas 6,5 rechecks se deram pelo watchdog, zero token/revisão rejeitados. Em warm: 9 registros, 180,5 tentativas suprimidas, 81,5 notificações e 5 watchdogs por run.

B efetivamente conservou 2 estágios cold, mas **zero publicação de estágio conservado** antes do término da rota curta. Cancelamentos LOAD variaram controle 16,0 vs A 18,5, B 16,0, A+B 15,5 por cold run. **Não inferir redução de desperdício do simples contador de retenção.**

**Leitura provisória:** A elimina a checagem repetida, mas aparentemente deixa alguns estágios mais tempo bloqueados; o custo reduzido de `prepare_targets_snapshot` não foi convertido em melhor cobertura. B não exerceu a hipótese de conclusão de trabalhos reaproveitados no percurso curto. Doze pares adicionais em diferentes regimes e 56 ensaios replicados estão no job `factorial` em execução; não promover.

### Gate

Se a replicação não mostrar ganho reproduzível de cobertura e p99, deixar A e B OFF. Uma variante de A com notificação **por escopo efetivamente pendente**, que preserve prioridade urgente sem reenfileirar repetidamente 25 fontes, pode merecer teste separado; não alterar esta campanha durante a replicação.
