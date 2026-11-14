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


## First integrated results — 6-trial instrumented A/A smoke (PASS)

[Workflow run 43591999912](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43591999912), branch commit `40e5ddf8a488cd2b2a2bbf90a0008bcedec90194`: Godot 4.7.2 parser PASS, 22 DM22 assertions / zero failures, DM18 112/112, DM19 23/23, DM11 canonical parity, D7.3 source cache PASS; smoke PASS. Previous run failed a **harness-only invariant**: in a 900-frame warmed route, zero first focal chunk dispatches is valid because the focal region may already be loaded before measurement; this assertion was corrected, code and instrumentation unchanged.

Four cold runs (2 A/A pairs), each 720 measured frames at 18m/s, shared full DM22 trace:

| Measure | Mean over four cold runs |
|---|---:|
| Focus canonical missing frames | **40.764%** |
| Source scope enqueue → generator dispatch queue wall time | **904.627ms** |
| Generation worker CPU | **2.174ms** |
| Projection worker CPU | **84.270ms** |
| Scope publication main-thread CPU | **0.476ms** |
| Critical last source queue delay (from original enqueue) | **1,693.040ms** |
| Focus first-chunk blocked from first attempt | **350.357ms** |
| Urgent source reorders per run | **1,288.25** |
| Scope publications per run | **178.5** |

All 16 first-chunk focal dependencies that were successfully linked in the four cold runs were dominated by the **pre-generation queue** phase; this does not imply those entire 1.69s were spent blocking the focus (many scopes were originally enqueued before the focus's first attempt). The gap from the last missing source publication to first focus chunk job dispatch is only ~4–5ms. The actual focus wait is measured separately.

The two warmed runs had a shorter average source queue delay **166.819ms**, projection worker **94.5ms**, and **zero new first-focus initial dispatches** during their 720 measured frames. This is a *sampling limitation*, not proof of zero effect dependencies: work can start on a neighboring region before that region becomes focal. Further research must correlate the first chunk of a `LOAD` stage initiated as a neighbor with later focus entry.

**Equal cost:** both arms report `trace_enabled=true`, same DM19 diagnostics and full lifecycle hooks. Their cold A/A differences in focus absence were +0.972 and −9.305 p.p. despite no code behavior difference; this demonstrates meaningful **runner/scheduling noise** and why uninstrumented-to-instrumented comparison would be invalid. An intervention must outperform this noise in a larger paired study.

The 24-run replication **completed successfully**. Its terminal results and decision are recorded below; no source scheduling change was made.


## Replication final — 24 execuções A/A com custo equivalente de instrumentação

[GitHub Actions run 43591999912](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43591999912): **COMPLETED / success** em 2026-11-14 12:09 UTC, commit do teste `40e5ddf8a488cd2b2a2bbf90a0008bcedec90194`. Jobs `exact`, `smoke`, `factorial` PASS. **24 execuções replicadas**: 8 cold-forward (4 pares), 8 warm-forward (4 pares), 4 warm-long (2 pares) e 4 idle (2 pares), 12 pares A/A nulos. As 6 corridas smoke são separadas e não integradas à inferência pareada replicada.

**Paridade experimental:** todos os 24 receipts: `trace_enabled=true`, `dm22_scope_trace_enabled=true`, `dm19_cold_diagnostic_enabled=true`, DM18 cache ON, DM20/DM21 OFF, perf trace pesado OFF. O controle `reference` e o `repeat` executam **o mesmo código de coleta, armazenamento, agregação e emissão de recibos**; nenhuma mudança de algoritmo ou worker entre braços. A/A não mede overhead absoluto relativamente a jogo sem DM22, apenas remove o viés diferencial de instrumentação entre braços. Mantenha esse mesmo overhead no baseline de qualquer experimento futuro.

### Decomposição das fontes por cenário (médias de cada execução)

| Medida | Cold-forward, 8 | Warm-forward, 8 | Warm-long, 4 | Idle, 4 |
|---|---:|---:|---:|---:|
| Entrada na fila → despacho da geração, wall-clock | **854,22ms** | 151,23ms | 105,01ms | 1.597,00ms |
| Worker de geração, CPU | 2,13ms | 2,19ms | 2,08ms | 1,95ms |
| Finalização fonte, CPU main | 0,74ms | 0,77ms | 0,70ms | 0,66ms |
| Worker de projeção, CPU | **82,67ms** | 89,58ms | 79,51ms | 74,66ms |
| Publicação scope, CPU main | **0,48ms** | 0,47ms | 0,29ms | 0,45ms |
| Tempo completo source fila→publicação, wall-clock | **1.065,68ms** | 389,04ms | 243,47ms | 1.784,72ms |
| Chamadas effect snapshot pendentes / corrida | 257,38 | 0 | **700,25** | 194,00 |

As médias `scope_queue_ms` consideram somente scopes efetivamente publicados; scopes descartados e enfileirados que não publicaram devem ser analisados separadamente. Tempo de worker CPU é concorrente e **não deve ser somado como latência serial de regiões**. A fila da fonte em `cold-forward` corresponde a ~80% do intervalo completo médio observado, mas a decomposição não implica que 854ms de todo source sejam tempo de bloqueio direto da região focal.

### Correlação de *primeiro chunk focal* — alcance e limitação

- Cold-forward: **33/33 últimas fontes críticas vinculadas** tiveram a fila como fase dominante; ~**1.555,07ms** de fila por última fonte, incluindo **espera antes da primeira tentativa focal**.
- Primeira tentativa de chunk focal → primeiro despacho: **402,00ms** em média das corridas com vínculo. Última dependência publicada → despacho: aproximadamente **4,90ms**. Preparação de efeitos bloqueou a maior parte do período entre primeira tentativa e despacho.
- Fila `scope_queue_events`: **1.629** admissões em oito corridas frias, **10.412** repriorizações urgentes da fila (média **1.301,5**/run), e **150** descartes de scopes ainda enfileirados ao sair da janela protegida. O método `_enqueue_prefetch_regions(..., high_priority=true)` move uma fonte já enfileirada ao início novamente quando outra tentativa de snapshot requer suas dependências, mesmo que a fonte já seja conhecida: **possível churn/falta de justiça**, hipótese ainda não provada por causalidade.
- Warm-forward: **zero** primeiras submissões de região focal vinculadas durante a medição; regiões próximas já estavam preparadas antes de se tornarem foco. Não interpretar como ausência de dependências.
- Warm-long: apenas **3** primeiras submissões focais entre quatro corridas, porém **nenhuma última fonte crítica publicada foi vinculada**; houve **2.131 tentativas pendentes**, e a ausência canônica segue ~24%. O probe atual liga a lista de fontes somente ao estágio iniciado quando **já era foco**, e perde a história de uma região que começou como vizinha e depois se tornou foco. Consequentemente, **não permite atribuir causalmente a espera sustentada warm-long** a um scope específico.
- Idle: quatro primeiros chunks vinculados, todos também com dominância de fila; o cenário é startup parado, não movimento contínuo.

**Próxima intervenção metodológica necessária:** registrar dependências e timestamps do primeiro chunk para **todos os estágios LOAD iniciados na janela**, acompanhar promoções *vizinho → foco* e medir `stage_start → first_dispatch`, `focus_entry → first_dispatch`, `last_scope_publish → first_dispatch`, e cancelamentos pela janela. Em uma segunda campanha causal, experimentar justiça/deduplicação de prioridades na fila de scopes ou prioridade protegida das dependências do foco, **com a mesma instrumentação em controle e tratamento**, sem aumentar worker slots ou modificar revisões/projeção/DM18.

### Ruído e capacidade de detectar melhoria: pares A/A nulos

| Cenário | Δ ausência foco (repeat−reference) | IC95% pareado | Δ frame p99 | IC95% pareado |
|---|---:|---:|---:|---:|
| Cold-forward (4 pares) | **+0,347 p.p.** | [−2,853; +3,547] | −0,261ms | [−10,290; +9,767] |
| Warm-forward (4 pares) | −1,042 p.p. | [−4,357; +2,274] | −0,680ms | [−7,590; +6,230] |
| Warm-long (2 pares) | −0,271 p.p. | [−3,714; +3,172] | 0,000ms | [0,000; 0,000]* |
| Idle (2 pares) | N/A | N/A | 0,000ms | [0,000; 0,000]* |

*Os zeroes em p99 do warm-long/idle refletem o quantil discretizado/limitado pela taxa de frames neste conjunto; não estabelecem igualdade de cauda entre execuções. Nos quatro pares frios, HIGH completos foram 57 (controle) vs 54,5 (repeat) em média, com jobs canônicos 11,5 menores no repeat embora ambos braços tenham exatamente o mesmo código: **sinal de ruído temporal/ordem**. Não reinterpretar diferenças A/A como melhoria causal.

### Veredito terminal

`DM22_DIAGNOSTIC_QUALIFIED_QUEUE_DOMINATES_COLD_FOCUS_BUT_WARM_LONG_LINKAGE_INCOMPLETE`.

1. **Forte evidência descritiva:** espera na fila das fontes é a fase dominante das dependências críticas vinculadas na partida a frio, enquanto a CPU de geração é pequena; projeção em worker ainda tem custo material (~80ms/scope).
2. **Sem otimização ou promoção:** A/A mede, não altera execução, e não demonstra melhoria de disponibilidade. A variação natural medida precisa fazer parte do gate de qualquer novo experimento.
3. **Lacuna de instrumentação identificada:** no trajeto longo após pré-aquecimento, a atribuição de último source crítico da região que se torna focal continua incompleta; é necessária instrumentação de estágio iniciando como vizinho.
4. **Próximo alvo possível:** justiça e idade na fila de fontes, com foco dependente de região canônica, mas a avaliação deve medir se o último source realmente publica mais cedo e se a disponibilidade/p99 melhoram; meramente trocar ordenação não basta (DM19-B foi rejeitado).
5. Preservar **DM18** e os contratos de edits, efeitos, revisão, objetos, simulação e HIGH. A `main` permanece intacta. Não há qualificação visual interativa da DM22; é instrumentação headless somente.
