# DM19 — Investigação causal de regiões canônicas inéditas a 18 m/s

**Base:** `exp/dm18-canonical-region-revisit-cache`, cache canônico DM18 permanece disponível e ON nas duas condições de benchmark. **Não alterar a `main`.**

## Problema

O DM18 demonstrou reutilização real de malhas de 16 chunks em revisitas, mas não acelera regiões inéditas. O conjunto DM17-A+B não reproduziu ganhos relevantes de disponibilidade canônica. Diagnóstico prévio DM12 indicou efeitos e snapshots como candidatos, mas eventos de trace completo distorcem a velocidade e a cobertura observadas.

**Pergunta:** no trajeto novo a 18 m/s, o tempo de falta canônica é causado principalmente por (a) esperas na projeção de fontes de efeitos, (b) espera pelo orçamento de despacho de chunks, (c) fila e CPU dos workers, (d) confirmação/publicação dos 16 meshes, ou (e) reconciliação das fontes no main thread?

## Alterações experimentais

Branch `exp/dm19-cold-canonical-attribution`, arquivos:
- `game/scripts/diagnostics/dm19_cold_attribution.gd`: coleta limitada em memória, sem console ou arquivos por frame.
- `game/scripts/terrain/terrain_demo.gd`: hook de estágio canônico, preparação de efeitos, despacho e conclusão de jobs, descartes e estados de foco; medição de reconciliação do efeito e estágios do main thread. As decisões de geração, LOD, prioridade, orçamento, revisão, renderização, publicação e retenção DM18 não são alteradas.
- `game/tests/experiments/dm19_cold_attribution_contract.gd`: contrato de cálculo dos tempos, first_visit vs cache, states e cancellation.
- `scripts/perf/run-dm19-cold-attribution-abba.ps1`: movimento a 18m/s baseado em relógio real, 720 frames *straight-18* (4 pares) e 2400 frames *outback-18* (2 pares); cada par compara exatamente mesmo commit/seed 424242, cache DM18 ON e tracing pesado OFF; só `SANDBOX_DM19_COLD_DIAGNOSTIC` ON/OFF varia; APPDATA isolado, ordem ABBA.

No benchmark, variáveis `SANDBOX_DM19_COLD_DIAGNOSTIC=1` e `SANDBOX_DM18_CANONICAL_CACHE=1`; flags DM17-A/B OFF. Fora do benchmark a instrumentação não é instanciada.

## Medições

- Motivos de bloqueio: `effect_pending_chunk/x_boundary/z_boundary/corner`, `effect_skip_not_allowed_or_budget`, `worker_capacity`, `dispatch_cap`, `snapshot_time_budget`, `no_eligible_stage`.
- Tempo por estágio **inédito versus revisit sem cache versus cache HIT**: até o primeiro job, primeiro ao último despacho, último despacho até região publicada, e end-to-end; p50/p95, contador de chunks efetivamente submetidos e concluídos.
- Custos de snapshots aceitos, fila WorkerThreadPool, execução CPU, upload de ArrayMesh, além do tempo agregado da projeção de efeitos, sucesso e tentativas pendentes.
- Tempo de main thread na reconciliação da janela de efeitos; processamento de prefetch, submissão+upload, HIGH visual, cache de superfície e publicações de objetos.
- Frames com foco canônico ausente separados em estado: nenhum estágio solicitado, antes do primeiro despacho, despachando, aguardando jobs/upload e cache aguardando publicação.
- Contadores de erros e descartes por mudança de janela ou token.

**Interpretação:** os tempos CPU por worker são acumulados e podem sobrepor entre threads; não somar esses valores como se fossem elapsed wall clock. Contar `no_eligible_stage` como ociosidade do dispatcher, não necessariamente como bloqueio de dependência.

## Gates e próxima intervenção

A primeira execução compara ON/OFF para observar overhead e exigir que a ausência do foco e frame p99 não sejam alterados sensivelmente pela instrumentação. A causalidade será avaliada apenas em ensaios de movimento novo com **zero hits do DM18**, para não misturar o ganho de revisita.

Somente após receber resultados qualificados, escolher **uma** intervenção:

1. Se `effect_pending` domina e `effect_window_reconcile` é alto, antecipar scopes/projeções da faixa atual sem alterar tokens, revisões ou geometria; testar A/B.
2. Se primeira submissão/intervalo entre submits domina e pré-requisitos estão prontos, experimentar prioridade/limite de despacho do foco com orçamento rígido por frame, isolado por flag; provar não regressão p99/efeitos.
3. Se espera em WorkerThreadPool domina, testar segmentação de capacidade canônica versus HIGH visual ou limitação adaptativa, preservando o HIGH em repouso.
4. Se `drain_after_last_submit` domina, medir p95 do trabalhador mais lento, publication gate e upload; preservar a publicação atômica de 16 chunks.
5. Se nenhum fator domina consistentemente, **não alterar a arquitetura**, ampliar ensaios pareados e instrumentar a causa ainda não atribuída.

Segurança obrigatória: seed/revisões, modificações, caves, seams, colisões, objetos mod-first, hidratação da simulação, DM18 cache e publicação `revision-gated` permanecem iguais. Não usar velocidades 54m/s; não confundir visual HIGH disponível com foco canônico autoritativo.
