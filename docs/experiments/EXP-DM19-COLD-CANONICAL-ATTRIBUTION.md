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


## Resultado da campanha DM19 original — 12 execuções (PASS)

**Código qualificado:** `3b3a7f377bab9e66d597c52adb9ecb086d9bd835`. [GitHub Actions DM19](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43513521113) PASS. Contratos de atribuição 23/23 e geometria DM18, DM17, DM11 PASS. Todos os ensaios possuem DM18 ON, perfil `adaptive-skip-progressive`, seed 424242, 18 m/s wall-clock e tracing pesado OFF.

**Controle do overhead de instrumentação:** quatro pares `straight-18` com DM19 OFF/ON:
- foco canônico ausente: OFF **38,507%**, ON **38,785%**, diferença +0,278 p.p.
- frame p99: OFF **24,215ms**, ON **22,149ms**, diferença −2,067ms, não interpretar como ganho causal (o DM19 não muda o algoritmo);
- frames >33ms OFF **0,417%**, ON **0,348%**, diferença −0,069 p.p.
- cache hits OFF/ON 0, por construção do percurso de regiões inéditas.

A variabilidade entre runs é relevante; os números não indicam grande perturbação sistemática por DM19, mas não provam overhead nulo.

### Etapas canônicas de regiões inéditas a 18m/s

Em quatro execuções ON, as regiões inéditas publicadas tiveram médias (média das médias por execução):

| Etapa | Média |
|---|---:|
| Estágio solicitado até primeiro despacho | **857,936ms** |
| Intervalo do primeiro ao último despacho | 289,355ms |
| Último despacho até publicação definitiva | 144,536ms |
| **Total por região publicada** | **1291,826ms** |

Portanto, ~66,4% da latência da região foi **anterior ao primeiro despacho**; não é explicável por SDF ou Surface Nets desse job. Observar que as regiões canceladas não entram nas médias de tempo de regiões publicadas; as razões de cancelamento são medidas separadamente.

Médias por execução de 720 frames:
- preparação de efeitos: **229** chamadas `pending` em **730,25** tentativas (~31,4%).
- `dispatch_cap`: **368** ocorrências;
- `effect_skip_not_allowed_or_budget`: **155,25** ocorrências;
- `worker_capacity`: **196,75** ocorrências;
- orçamento de **um despacho** em **692/720 frames** (~96,1%); dois em 28/720.
- foco canônico ausente classificado: **113,75 frames** antes do primeiro despacho; **91,5** enquanto ainda submete chunks; **74** aguardando conclusão ou upload. O restante varia conforme carga e fase; não extrapolar esses buckets como tempo contínuo de uma única região.
- `first_visit.left_window`: 18 a 21 estágios cancelados por execução; outras regiões em progresso completaram normalmente.
- reconciliação da janela de efeitos somou apenas ~21 a 27ms por corrida; não é a causa direta dominante. Custo acumulado de `effect_prefetch` e workers de projeção deve ser comparado com a demora na disponibilidade de fontes.

**Diagnóstico:** o gargalo principal está no caminho **estágio enfileirado → primeiro job canônico**. A causa tem contribuição de (i) pré-requisitos de efeitos ainda pendentes, (ii) limite de despacho quase sempre 1/frame e (iii) concorrência dos workers. Não concluir exclusivamente pelo volume de `dispatch_cap` que basta duplicar o orçamento: houve ~197 bloqueios por capacidade em paralelo.

### Próximo ensaio registrado: DM19-B

[Branch experimental](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/tree/exp/dm19-effect-motion-priority) ativa, apenas sob `SANDBOX_DM19_EFFECT_MOTION_PRIORITY=1`, a **priorização por movimento dos itens já presentes na fila de fontes de efeitos**. Ela:
- mantém cache DM18 ON, SDF, Surface Nets, 16 chunks, autoridade de efeitos, radius, objetos, geometria, revisões, worker pool e limites de despacho inalterados;
- não habilita `_lookahead_stage_targets` nem novos carregamentos canônicos; apenas invoca `prioritize_prefetch_for_motion` para reordenar fontes já protegidas;
- compara A/B em `straight-18` como cenário principal e `outback-18` como regressão, em ordem ABBA, com DM19 instrumentation ON em ambos.
- `main` permanece intacta; sem promoção antes de equivalência e ganho consistente do foco canônico sem piora de p99.

Se a priorização for neutra, a intervenção seguinte tecnicamente justificada será testar *oportunidade de primeiro despacho com orçamento adaptativo adicional estritamente limitado*, monitorando saturação de workers, p99 e HIGH estável, não aumentar a capacidade de maneira indiscriminada.
