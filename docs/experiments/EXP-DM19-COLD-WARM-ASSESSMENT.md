# DM19 — Avaliação de priorização de efeitos: partida a frio e mundo pré-aquecido

Data: 2026-11-13. Escopo: Godot 4.7.2, Windows runner headless, 18 m/s (54 m/s excluídos), seed 424242, `adaptive-skip-progressive`, tracing pesado OFF. `SANDBOX_DM18_CANONICAL_CACHE=1` em todos os braços; DM17-A/B OFF. **Não alterar `main` sem qualificação visual.**

## Campanhas e evidências

1. [DM19 attribution, 12 execuções, PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43513521113): atribuição de tempo do estágio e teste do overhead dos diagnósticos.
2. [DM19-B cold A/B, 24 execuções, PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43515643551): 8 pares straight-18, 4 pares outback-long-18, DM19-B ON/OFF; mesmas condições/flags DM18 ON.
3. [DM19 stationary warmup vs cold, 12 execuções, PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43529033568): 6 pares com/sem 900 frames de pré-aquecimento estacionário, 720 frames de movimento a 18 m/s; flag DM19-B OFF, DM18 ON.
4. [DM19-B direct A/B after 900-frame prewarm](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43529578614): 8 pares straight-18, 2 pares outback-long-18, em execução no momento da primeira redação deste relatório. O diagnóstico é reiniciado após pré-aquecimento, cache e world state persistem.

## Diagnóstico do gargalo (DM19)

Médias sobre quatro corridas `straight-18` com diagnóstico ligado:

- Latência de regiões *first_visit* efetivamente publicadas: **1.292 ms**, incluindo **858 ms até o primeiro despacho**, **289 ms do primeiro ao último despacho** e **145 ms de conclusão/publicação**.
- Tentativas pendentes na preparação de efeitos por corrida: **229**; `dispatch_cap`: **368**; `worker_capacity`: **197**. A maior parte dos frames (692/720) permite um único despacho canônico.
- Hipótese de efeitos e priorização: antecipar a ordem da fila de projeções já protegidas, sem alterar autoritatividade, raio, budgets, chunks ou cálculo SDF.

## DM19-B: partida a frio

| Medida | Controle | DM19-B |
|---|---:|---:|
| Foco canônico ausente | 34,896% | **30,260%** |
| p99 de frame | 20,739 ms | 20,291 ms |
| Frames > 33ms | 0,243% | 0,348% |
| Jobs canônicos por corrida | 508,875 | 536,375 |
| Preparações de efeito pendentes por corrida | 265,125 | **197,500** |
| Frames com foco aguardando primeiro despacho | 126,125 | **100,375** |
| Média até primeiro despacho, somente regiões publicadas | 841,327 ms | 847,388 ms |

A diferença pareada de ausência canônica (DM19-B menos controle) foi **−4,6355 p.p.**, IC95% [−8,3251; −0,9459], 7 de 8 pares favoráveis. Frame p99 −0,4476 ms, IC95% [−2,2192; +1,3239]. Frames >33ms +0,1042 p.p., IC95% [−0,0160; +0,2245], **possível regressão não excluída**. DM19-B melhora em princípio a prontidão de dependências e a cobertura durante partida a frio, mas não reduz a latência média até o primeiro job para as regiões que completaram (populações distintas), e não permite ainda promoção.

Revisita longa (4 pares): cobertura −1,635 p.p., IC95% [−9,769; +6,498], inconclusivo.

## 900 frames de pré-aquecimento estacionário vs partida a frio

Campanha concluída com **6 pares** do mesmo `straight-18`. 900 frames a ~60fps são ~15s estacionário antes dos 720 frames de movimento (~12s); a telemetria prévia é reiniciada no começo do movimento sem alterar as malhas e projeções residentes.

| Medida | Partida a frio | Após 900 frames |
|---|---:|---:|
| Foco canônico ausente | 35,996% | **0,903%** |
| Média até primeiro despacho (regiões publicadas) | 862,688 ms | **504,059 ms** |
| Preparações de efeitos pendentes durante movimento | 261,833 | **0** |
| Frame p99 | 22,138 ms | 24,499 ms |
| Jobs canônicos na medição | 504,167 | 744,833 |

Diferença pareada de disponibilidade **−35,0927 p.p.** de ausência canônica, IC95% [−38,996; −31,190], 6/6 pares. p99 aumentou nominalmente 2,361ms, IC95% [−4,352; +9,074], efeito inconclusivo.

**Interpretação:** o estágio inicial (projeção de fontes, residência canônica e backlog inicial) influencia drasticamente o benchmark curto. Estes números não comprovam por si só que a ordenação DM19-B melhora o streaming contínuo depois do pré-aquecimento. O pré-aquecimento prepara também muitas regiões vizinhas; portanto não atribuir os 35,09 pontos apenas à projeção de efeitos. É necessário avaliar trajetos longos fora da residência previamente preparada.

## Gate para DM19-B em mundo pré-aquecido

Critérios antes de examinar o teste direto de pós-aquecimento:

1. Teste curto com controle de ausência ~0,9% tem **efeito de piso**: qualquer melhoria absoluta é ≤0,9 ponto. Não exigir ganho de 4,6 pontos nesta condição.
2. Teste outback-long captura regiões inéditas além do raio de residência inicial, mas com apenas 2 pares não suporta promoção por significância estatística. Mesmo um efeito positivo precisa de replicação maior.
3. Para promover futuramente, evidenciar ganho persistente do foco canônico em corrida longa e sem aumento do p99/frames>33ms, regressões de efeitos e cachê DM18; teste interativo GPU requerido.
4. Se teste pós-aquecimento for neutro, preservar DM18 e **não ativar DM19-B por padrão**. A próxima intervenção mais justificável seria preparação incremental de fontes e chunks durante os primeiros segundos, preservando prioridades do foco e budgets, com nova campanha A/B.
5. Não mudar o perfil HIGH, o cache DM18, as revisões/snapshots de efeitos, colisões, objetos ou a `main`.

Limites: mesma máquina, headless, uma seed e janelas de 12s/40s; intervalos de confiança sobre pares com autocorrelação possível do runner; testes de integridade e paridade aprovados, mas sem equivalência visual GPU validada.
