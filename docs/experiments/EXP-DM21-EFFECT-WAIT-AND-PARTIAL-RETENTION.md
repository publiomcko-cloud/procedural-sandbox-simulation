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

Implementation + contracts qualified. Benchmarks smoke e replicação concluídos; resultados e veredito terminal abaixo. **Default remains DM21 A/B OFF, DM18 preserved as user-approved experimental baseline, `main` unchanged.**


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


## Resultado terminal — campanha replicada de 56 execuções

[GitHub Actions DM21 run 43586067986](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43586067986) — **success**, em **2026-11-14 11:13 UTC**, SHA `7ed9170866184135b43556a66b765c8c7a8e134d`. Três jobs `exact`, `smoke`, `factorial` PASS. Dataset replicado: **56 corridas**, 14 blocos de quatro braços, 42 diferenças pareadas; 6 blocos `cold-straight`, 4 `warm-straight`, 2 `warm-outback`, 2 `idle`. O smoke anterior contém 16 execuções adicionais e não é misturado ao conjunto inferencial de 56. Todas as variantes mantiveram DM18 ON, DM19 diagnostic ON, DM20 e DM17-A/B OFF, 18m/s (exceto idle), mesma seed 424242, e trace pesado OFF. Logs e recibos preservados no artifact do workflow.

### Cobertura canônica, média absoluta por cenário

| Cenário | Controle | A | B | A+B |
|---|---:|---:|---:|---:|
| Cold-straight, 6 blocos | 38,819% | 38,773% | 37,338% | 38,797% |
| Warm-straight, 4 blocos | 3,160% | 0,659% | 1,250% | 0,000% |
| Warm-outback, 2 blocos | 23,750% | 23,688% | 23,709% | 23,875% |

### Diferenças pareadas: intervenção menos controle, com IC 95%

| Cenário | Braço | Foco ausente, p.p. [IC95%] | Frame p99, ms [IC95%] |
|---|---|---|---|
| Cold, n=6 | A | −0,046 [−6,603; +6,511] | +0,767 [−2,770; +4,304] |
| Cold, n=6 | B | −1,481 [−12,023; +9,060] | +1,402 [−0,887; +3,691] |
| Cold, n=6 | A+B | −0,023 [−9,362; +9,316] | +2,371 [−3,239; +7,982] |
| Warm, n=4 | A | −2,500 [−6,118; +1,117] | −0,760 [−11,017; +9,497] |
| Warm, n=4 | B | −1,910 [−5,918; +2,099] | **+6,710 [−0,981; +14,400]** |
| Warm, n=4 | A+B | −3,160 [−6,989; +0,670] | +2,892 [−4,037; +9,820] |
| Warm long, n=2 | A | −0,063 [−0,323; +0,198] | +0,558 [−17,060; +18,175] |
| Warm long, n=2 | B | −0,042 [−0,569; +0,486] | +0,228 [−2,669; +3,125] |
| Warm long, n=2 | A+B | +0,125 [−0,930; +1,180] | −0,415 [−5,681; +4,852] |

Nenhum IC95% de *foco ausente* exclui zero; tampouco está demonstrada não regressão de p99. Warm-B elevou numericamente p99 em **6,71ms** e piorou os quatro pares, embora seu IC95% inclua zero. As 2 execuções de cada braço no cenário longo/idle são exploratórias; não são evidência de equivalência. A comparação de 9 cenários/braços simultâneos não tem correção de multiplicidade, portanto não promover sinais isolados como conquistas causais.

### Mecanismos testados — efeito observado vs resultado útil

**A. Event-driven snapshot wait.** Em `cold-straight`, as chamadas `prepare_targets_snapshot` retornando `pending` caíram de média **284,67 para 23,17** (−91,9%); a espera DM21 foi registrada em **22,17 estágios/execução**, suprimiu **364,83 tentativas** e observou **152,5 notificações**, com **9,5 watchdogs**. Em `warm-outback`, contagens `pending` caíram de **886 para 50,5** (−94,3%), enquanto as fontes únicas continuam sendo produzidas pelo mesmo single-flight. Apesar disso, regiões canônicas ausentes permaneceram praticamente iguais: cold 38,819% → 38,773%; warm long 23,750% → 23,688%. Worker jobs cold 498,5 → 496,67; warm long 954 → 958,5 (sem economia substancial). **Supressão de rechecagens é redução de telemetria/calls, não evidência de avanço de dependências ou melhora de publicação.** Uma espera mais longa também pode diminuir a frequência da urgência e a chance de despachar chunks prontos.

**B. Retenção de LOAD parcialmente concluído.** Em cold, foram preservados em média **2,83** estágios/execução (B) ou **3,0** (A+B), porém **zero** estágios marcados como `dm21_retained` foram publicados integralmente em **todos os cenários**. Cancelamentos LOAD no percurso cold: controle **17**, B **16,33** (diferença não relevante); chunks concluídos em estágios cancelados: controle **44,17**, B **35,67**. Esses contadores não autorizam afirmar reaproveitamento efetivo: podem variar com interleaving e avanço da janela. No longo, cancelamentos LOAD foram **31** em todos os braços, retenção B ~1 sem conclusão. O custo de conservar esses estágios pode competir com foco canônico/visual em vez de melhorá-los.

**DM18 + HIGH.** `warm-outback`: todos os braços registraram **51 cache hits DM18** por execução, sem perda demonstrada de reutilização. `idle`: todos concluíram exatamente **268 HIGH visuais**, em média 12,942s (controle), 13,165s (A), 13,153s (B), 13,167s (A+B). Diferença descritiva de +~0,21–0,23s, mas IC95% largo com apenas 2 pares; não comprova regressão nem equivalência. Idle p99 igual a 16,667ms em todos os braços por limite de 60FPS.

### Veredito final: DM21_A_B_NO_PROVEN_PERFORMANCE_GAIN

1. **DM21-A e DM21-B devem permanecer OFF por padrão.** Não fazer merge de nenhum dos dois na `main`; não há ganho de cobertura canônica estatisticamente reproduzível e o tail de frame após pré-aquecimento merece cautela.
2. **Preservar o DM18**, validado visualmente pelo usuário, sem alteração em residência/revisão/effects; branch experimental isolado.
3. **Não confundir consumer-side dedup com single-flight novo.** O single-flight de geração/projeção já existia; DM21-A apenas adicionou sinais de prontidão ao consumidor.
4. **Próxima investigação** mais justificada: atribuição *por scope* dos eventos `queued → generation-inflight → projection-inflight → published`, custo por fase, prioridade de scopes requisitados por região focal, latência até todos os 25 scopes exigidos para uma primeira submissão, e número de scopes que são reusados entre chamadas. Avaliar detecção de indisponibilidade exata por scope antes de gerar snapshots e política de publicação mais cedo, sem ampliar o pool ou remover validação de edits/efeitos.
5. **Retenção alternativa só após medir janela temporal de retorno**, integridade de stage e orçamento de slots. DM21-B não mostrou publicações reaproveitadas; não expandir janela canônica com base no baixo uso de RAM sem medir custo CPU e revalidação.
6. No futuro, exigir teste longo de movimento contínuo em regiões virgens, seeds adicionais, replay determinístico e equivalência GPU/objetos/colisão/editar/undo. Os testes headless atuais não validam visualmente nem demonstram causalidade suficiente para promoção.

`main` permanece inalterada. Evidência [GitHub Actions DM21](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43586067986). Status da campanha **COMPLETED_PASS**; veredito técnico **NO_PROVEN_GAIN**.
