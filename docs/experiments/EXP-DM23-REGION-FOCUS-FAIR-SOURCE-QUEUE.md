# DM23 — Região vizinha → foco e justiça temporal na fila de efeitos

Data: 2026-11-14. Origem: branch `exp/dm22-effect-scope-critical-path`. Código: `exp/dm23-region-lifecycle-fair-source-queue`. [Workflow DM23](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43595190616).

## Hipóteses

DM22 mediu ~854ms entre admissão e despacho da geração de fonte durante `cold-forward` e ~80ms de CPU de projeção, mas não atribuiu corretamente a dependência crítica de estágios `LOAD` iniciados como vizinhos e depois promovidos ao foco. Registrou ~10.412 promoções urgentes para 1.629 admissões em oito execuções frias. Reordenar a fila por direção (DM19-B) anteriormente falhou em reproduzir ganho após pré-aquecimento; isto **não** autoriza aumentar concorrência ou promover nova política sem A/B.

## DM23 — instrumentação contínua de estágio (igual no controle)

`DM23RegionLifecycleProbe` registra cada estágio LOAD normal desde `begin`, guarda token por região, hora da primeira tentativa de snapshot e das dependências de origem pendentes, hora do primeiro despacho, entrada do jogador no foco (antes/depois do primeiro despacho), publicação ou cancelamento, e último scope pendente publicado. Os eventos de publicação vêm da mesma sonda DM22 por fonte: fila, geração, projeção, publicação. Stages já publicados antes de virarem foco possuem histórico recente limitado (320). Arrays de medidas são limitadas a 2.048 registros e não há logs por frame.

No caso em que uma região começa como vizinha, o probe diferencia: entrou no foco ainda esperando o primeiro chunk, primeiro chunk despachado como vizinha, publicação antes de virar foco e cancelamento antes/depois da entrada no foco. O rastreio mede `stage created → focus entered`, `first snapshot attempt → first dispatch`, `last dependency publication → first dispatch`, `focus entry → first dispatch` e `focus entry → canonical publication`. Não altera SDF, meshes, edit/effect revision, autoridade, objetos, ou a geometria.

## DM23-F — única intervenção isolada

Flag `SANDBOX_DM23_FAIR_SOURCE_QUEUE=1`, OFF por padrão.

1. Urgência existente continua prevalecendo nos dois primeiros despachos de cada grupo de três. No terceiro despacho, se houver source enfileirado há 700ms ou mais, escolher o mais antigo (dentro da janela protegida atual).
2. Solicitações urgentes repetidas do mesmo scope na fila só podem re-promovê-lo uma vez a cada 100ms; nenhum novo worker, etapa de projeção, scope ou snapshot é produzido.
3. Publicação, revisão, invalidação, worker slots (2 de geração e 2 de projeção) e raio de fontes permanecem inalterados.
4. **Controle com custo equivalente:** `SANDBOX_DM23_STAGE_TRACE=1`, `SANDBOX_DM22_SCOPE_TRACE=1`, `SANDBOX_DM19_COLD_DIAGNOSTIC=1` nos dois braços. O controle executa os mesmos cálculos de antiguidade, possibilidade de re-promoção e limites, atualizando os mesmos metadados de fila, mas preserva a ordem original. Somente o braço `fair` aplica as decisões. Recibos obrigatoriamente verificam esses flags; trace pesado desligado em ambos. O custo extra de instrumentação da baseline **não é menor** que o do tratamento.
5. O trabalho remoto usa o mesmo commit, perfil `adaptive-skip-progressive`, Godot 4.7.2, B4, seed 424242, 18m/s wall-clock, APPDATA isolado, cache DM18 ON e DM17, DM19-B, DM20-A/B e DM21-A/B OFF.

## Plano de medição

Script `scripts/perf/run-dm23-fair-queue-ab.ps1`, alternância A/B/BA de pares consecutivos.

- Smoke 8 corridas: 2 pares cold-forward (720 frames), 1 warm-forward (900 prewarm + 720) e 1 warm-long (900 prewarm + 2400).
- Replicação 36 corridas: 6 pares cold-forward, 4 pares warm-forward, 6 pares warm-long, 2 pares idle (2400).
- Principal: diferença pareada de frames sem foco canônico e p99/frames>33ms nos cenários **warm-long** (regiões virgens surgem durante viagem). Complementares: atraso do primeiro chunk, publicação da última fonte, número de regiões iniciadas vizinhas que entraram no foco, stale stages, HIGH visual, ocupação do WorkerThreadPool e cache DM18. Além disso, verificar se efetivamente houve despachos envelhecidos e reordenações urgentes suprimidas.
- Todos os pares devem ter o mesmo custo de instrumentação. Intervalos de confiança são sobre pares independentes, não sobre frames correlacionados. Os resultados headless não substituem teste visual GPU, edits/undo ou equivalência de simulação.

## Critérios de decisão

Promover **somente** com ganho consistente, intervalos de confiança que sustentem o efeito desejado nos percursos relevantes, ausência de regressão relevante de tail/HIGH e paridade de edição/efeitos/objetos/DM18. Caso a justiça temporal reduza os gargalos de fila mas não reduza a ausência canônica, manter OFF e investigar o custo de processamento/ordem da última projeção. A/B não pode virar um experimento ON-vs-OFF de telemetria.

**Estado inicial:** código e testes exatos aprovados no runner Windows; benchmark smoke em execução. A `main` não foi alterada.


## Smoke concluído — 8 execuções A/B (PASS)

[GitHub Actions run 43595190616](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43595190616), commit `edbf2f88fe1267161fcfda3e5356088ed46b7417`, job `exact` PASS, `smoke` PASS. Contratos da DM23 e regressões DM22/DM18/DM19, geometria e fonte de efeitos PASS. São 2 pares frios, 1 warm-forward e 1 warm-long; n é insuficiente para qualquer promoção.

| Cenário | Indicador | Controle | Fair |
|---|---|---:|---:|
| Cold-forward | Ausência canônica | 38,889% | 38,889% |
| Cold-forward | p99 frame | 20,732ms | 18,056ms |
| Cold-forward | Tempo médio source em fila | 886,107ms | 850,943ms |
| Cold-forward | Repriorizações urgentes/execução | 1.472 | **287,5** |
| Cold-forward | Reordenações bloqueadas pelo cooldown/execução | 0 | **1.939** |
| Cold-forward | Despachos envelhecidos aplicados/execução | 0 | **12** |
| Warm-forward | Ausência canônica | 0% | 0% |
| Warm-forward | Reordenações bloqueadas | 0 | 0 |
| Warm-long | Ausência canônica | 23,625% | 24,583% |
| Warm-long | Reordenações bloqueadas e despachos envelhecidos | 0 | 0 |
| Warm-long | Hits DM18 | 51 | 50 |

Os dois pares cold diferiram em **+9,305 p.p.** e **−9,306 p.p.** (fair−controle), cancelando-se em média; não atribuir o p99 menor à intervenção sem replicação. A política realmente atuou na fase fria, mas **não se ativou no warm-long**: fontes já esperavam ~111ms na fila, abaixo do limiar de 700ms, e nenhuma fonte exigiu repetida repriorização urgente. Portanto, não é plausível usar esse tratamento como solução do problema warm-long sem mudar o desenho do algoritmo; a replicação deve confirmar.

### Nova capacidade de acompanhamento vizinho → foco

No único par warm-long, ambos os braços iniciaram **132 LOAD stages** como vizinhos. O controle observou 13 promoções vizinho→foco; **11 dessas 13 regiões ainda não tinham primeiro chunk despachado ao entrar no foco**. O braço fair também observou **11 de 14** nessa condição. Nos estágios cujo primeiro chunk chegou a ser submetido, o tempo médio entre a primeira tentativa de snapshot e despacho foi apenas **0,075ms (controle)** e **0,082ms (fair)**. Já o intervalo criação→primeiro chunk foi aproximadamente **559ms** e **614ms**; vários estágios foram cancelados antes de emitir o primeiro chunk (30 no controle, 30 no fair).

**Interpretação provisória:** a DM22 não conseguia classificar dependências warm-long porque o estágio é iniciado como vizinho; DM23 recuperou a trajetória e apontou uma espera longa **antes mesmo da primeira tentativa** de preparação de efeitos. O gargalo sustentado pode estar na elegibilidade/prioridade do dispatcher canônico ou na competição de etapas, não necessariamente no worker de projeções. A emissão de `prepare_targets_snapshot` para o primeiro chunk é praticamente imediata nos poucos estágios efetivamente submetidos. Isso ainda exige replicação e rastreamento de todos os 16 chunks para diagnosticar publicação completa.

A `main` permanece sem alterações. Não promover policy DM23-F antes dos resultados replicados, da análise pareada e do teste visual GPU.


## Avaliação terminal — 36 ensaios replicados (2026-11-14)

[GitHub Actions run 43595190616](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43595190616): \`completed / success\`, conclusão em 2026-11-14 12:59 UTC (09:59 Brasília), SHA do teste \`edbf2f88fe1267161fcfda3e5356088ed46b7417\`. Jobs \`exact\`, \`smoke\` e \`factorial\` **PASS**. O benchmark replicado contém **36 corridas, 18 pares**, separados do smoke de 8 corridas: 6 pares cold-forward, 4 warm-forward, 6 warm-long e 2 idle. Todos os recibos qualificados confirmaram \`trace_enabled=true\` em ambos os braços, DM22 e DM23 probes habilitados, mesmo perfil e instrumentos, DM18 ON, sem DM20/DM21 e sem heavy perf trace. Não houve merge em \`main\`.

### Cobertura e cauda de frame (A/B pareado)

Diferenças \`fair - control\`; valores negativos são menores em ambas métricas. Intervalos de confiança 95% t de Student calculados **sobre diferenças entre pares**, não sobre os 720/2400 frames correlacionados.

| Regime | n pares | Foco ausente, controle → fair | Δ ausência, p.p. [IC95%] | p99 controle → fair | Δ p99 [IC95%] |
|---|---:|---|---|---|---|
| Cold-forward | 6 | **33,2175% → 36,9675%** | **+3,750 [−2,221; +9,721]** | 21,624 → 18,914ms | −2,710 [−6,124; +0,704]ms |
| Warm-forward | 4 | **0,000% → 1,4235%** | **+1,424 [−2,276; +5,123]** | 25,177 → 21,750ms | −3,427 [−8,956; +2,101]ms |
| Warm-long | 6 | **24,2013% → 23,7918%** | **−0,4095 [−0,931; +0,112]** | 17,904 → 18,056ms | +0,1525 [−0,240; +0,545]ms |
| Idle | 2 | N/A | N/A | 16,667 → 16,667ms | 0ms (limite de FPS; não demonstra equivalência) |

Nenhum dos IC95% de ausência canônica ou p99 exclui zero. A amostra, apesar das repetições, **não demonstra ganho estatístico de cobertura** nem garante ausência de regressões de cauda. O sinal de melhora p99 em cold não valida uma política que entrega menos chunks canônicos: \`worker_jobs\` caiu de **517,17 para 494,50** por corrida, diferença pareada −22,67 [−42,03; −3,31]. A comparação de vários indicadores é exploratória; não foi aplicada correção de múltiplos testes.

### Mecanismo de justiça temporal: realmente aplicado onde havia disputa

No cold-forward, por corrida:
- Repriorizações urgentes realizadas: **1.266,67 controle → 285,00 fair** (−77,5%).
- Reordenações suprimidas no tratamento por cooldown: **1.950,33**; 14 slots de geração para fontes envelhecidas por corrida. O controle registrou apenas a decisão shadow, sem modificar despacho.
- **Latência total por fonte publicada:** 1.005,71ms controle → **1.073,41ms fair**, diferença pareada **+67,70ms [IC95% +33,61; +101,79]**. Esta é uma piora nominal robusta nesse dataset, mas envolve apenas fontes que publicaram e faz parte de uma família maior de comparações exploratórias.
- Tempo médio na fila de fontes publicadas: **799,12ms → 867,60ms**; \`effect.pending\` 256,5 → 332,0 por execução. É plausível que suprimir promoções urgentes deslocou scopes indispensáveis para a região focal, apesar de evitar churn.
- \`over33%\` 0,278 → 0,255, diferença pareada −0,023 p.p. [−0,257; +0,210]; sem ganho comprovado.

No **warm-forward** e **warm-long**, controle e fair tiveram **zero** slots envelhecidos aplicados, zero cooldowns aplicados, zero repriorizações urgentes. Portanto a intervenção **não foi exercitada nesses dois regimes**; as diferenças de cobertura observadas são variação de ordem/tempo do runner e não evidência de ganho de uma política inativa. O idle teve apenas 6 slots envelhecidos aplicados em média e 268 HIGH concluídos em ambas variantes; tempo para HIGH total 13,085s controle e 12,770s fair, com n=2 insuficiente para aprovação.

DM18: warm-long registrou 50,17 vs 51 hits médios por corrida; não há sinal inequívoco de violação dos contratos. Nenhuma alteração na revisão de edição, source authority, worker slots (2+2), radius ou layout do mundo. Contudo, os testes são headless e não substituem qualificação visual GPU, edits/undo, objetos e colisões.

### Descoberta mais relevante: regiões que se tornam focais antes do primeiro chunk

O novo probe acompanha o estágio desde o \`LOAD\` como vizinho até a entrada no foco. No warm-long:

| Indicador médio por corrida | Controle | Fair |
|---|---:|---:|
| Estágios LOAD iniciados | 132 | 132 |
| Vizinhos que entraram no foco | 14,00 | 12,83 |
| Desses, ainda aguardando o 1º chunk ao entrar no foco | **11,00** | **10,83** |
| Cancelados antes de despachar o 1º chunk | **30,00** | **30,00** |
| Criação do LOAD → 1º chunk despachado, entre submetidos | **638,14ms** | **613,20ms** |
| Primeira tentativa efetiva de snapshot → 1º despacho, entre submetidos | **0,073ms** | **0,074ms** |
| Ausência da região focal | **24,20%** | **23,79%** |

**Interpretação:** no movimento sustentado a maioria dos vizinhos que passam a foco ainda não recebeu o primeiro chunk, e cerca de 30 estágios/execução deixam a janela antes de despachar um único chunk. O tempo da primeira tentativa de snapshot até o despacho é quase zero **apenas na população que conseguiu despachar**: é uma amostra seletiva, portanto não prova ausência de espera por efeitos nos estágios bloqueados/cancelados. Porém, a política DM23 para fontes não se ativou e não explica o ~24% de foco ausente. O próximo ponto de investigação mais defensável é o ciclo completo \`created → eligible → selected → snapshot first attempted → first dispatch → 16 chunks complete → published / cancelled\` de cada estágio canônico e sua distância do foco, além de medir o efeito de prioridade canônica com **justiça temporal** em todos os estágios LOAD, mantendo despesas do probe idênticas nos dois braços e worker budgets fixos. Um foco exclusivo em scopes/projeções tem baixo poder para explicar o regime warm-long observado.

### Decisão final

**\`DM23_FAIR_SOURCE_QUEUE_NOT_QUALIFIED_FOR_PROMOTION\`.** O CI validou a execução do tratamento e a integridade sintática/regressões, **não um ganho de desempenho**. Não habilitar \`SANDBOX_DM23_FAIR_SOURCE_QUEUE\` no perfil padrão e não integrar a política no \`main\`. Preservar o DM18 e documentação de DM22/DM23. A próxima campanha deve medir o motivo exato de espera do estágio antes da primeira tentativa de snapshot e distinguir seleção da fila canônica, bloqueios de workers, budget por frame, LOD, effects e cancelamentos, inclusive o estágio que já começou como vizinho. Só então experimentar prioridade temporal canônica com baseline **igualmente instrumentado**, evitando repetir experimentos de pura reordenação (DM20-B) sem uma explicação causal.

Relatório final publicado após leitura dos 36 recibos e 18 pares. Evidência auditável no artifact do [run 43595190616](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43595190616). **\`main\` inalterada.**
