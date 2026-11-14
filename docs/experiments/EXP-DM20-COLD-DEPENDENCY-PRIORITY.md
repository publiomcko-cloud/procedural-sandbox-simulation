# DM20 — Antecipação canônica e prioridade do foco a 18 m/s

Data: 2026-11-13/14. **Não promover à main antes de benchmark A/B, equivalência de gameplay e qualificação GPU.** Base DM19 diagnostic, DM18 canonical region cache preservado e opt-in, flags anteriores DM17-A/B e DM19-B OFF.

## Origem da hipótese

DM19 mostrou em regiões novas (curso a frio a 18m/s) cerca de **858 ms** entre estágio enfileirado e primeiro dispatch, **289 ms** entre primeiro e último dos 16 chunks, **145 ms** para últimos jobs/publicação. 96% dos frames permitiam apenas 1 dispatch. Efeitos ainda pendentes: ~229 tentativas por corrida. A priorização DM19-B melhorou só cold-start; após pré-aquecimento não reproduziu ganho.

DM20 testa duas mudanças independentemente, sem aumentar o número máximo de workers, despacho global ou janela de efeitos. Evidência de DM19: [conclusões](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/docs/dm19-cold-warm-assessment/docs/experiments/EXP-DM19-COLD-WARM-ASSESSMENT.md).

## Implementações

Branch `exp/dm20-cold-dependency-priority`.

- `SANDBOX_DM20_SNAPSHOT_PRIMER=1` — **DM20-A:** em um frame com headroom, antes de `process_prefetch_step`, avalia o próximo chunk normal da fila de LOAD e constrói antecipadamente exatamente um snapshot de edição+efeitos, ou provoca a antecipação da demanda de fontes pendentes. Mantém somente o snapshot na instância do estágio que o gerou; utiliza no `TerrainMeshJob` somente quando a próxima submissão corresponde ao mesmo chunk, token, identidade do objeto de edição, revisão das edições e revisão das autoridades de efeitos. Corner/boundary shared jobs não são primados e mantêm a implementação existente. O snapshot é descartado depois da submissão ou junto do estágio, sem alterar world authority. Não altera a janela protegida de fontes nem inicia jobs extras de geração.
- `SANDBOX_DM20_FOCUS_FIRST=1` — **DM20-B:** reordena somente estágios LOAD elegíveis: primeiro o estágio do foco, depois por anel Chebyshev canônico, depois distância mundo X/Z; mantém ordem original dos chunks dentro do estágio, `can_skip_pending`, budgets, máximo de workers e precedência estrita dos estágios `edit_transaction`, `partial` e `full`. Estágios DM9 especulativos não ganham prioridade sobre LOAD real.
- Pode combinar A+B, mas não presumir aditividade: testar possíveis interações e picos de frame no mesmo benchmark.

**Segurança:** as verificações de `DM20SnapshotGuard.valid` cobrem identidade do snapshot, scope de brush, revisão do estado de edição, revisão dos efeitos, token do estágio e chunk. Todas as decisões do estado canônico definitivo, publicação de objeto/simulação e validação de revisão continuam no pipeline existente. O cache DM18 mantém seus limites de 128 MiB estimados e contratos de invalidação.

## Qualificação inicial

[GitHub Actions workflow DM20](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43535376318), Godot 4.7.2 + PowerShell 5.1 Windows: **exact PASS**. DM20 25 verificações / 0 falhas; DM19 profile 23/23; DM18 cache 112/112; DM17 e DM11 regressão geométrica PASS. Nenhum teste de equivalência GPU foi executado até aqui.

## Benchmark pré-registrado

Script `scripts/perf/run-dm20-factorial.ps1`. Quatro condições por bloco **controle**, **A**, **B**, **A+B**, alternância em quadrado latino (reduz viés de ordem, não elimina correlação de carga). Fila canônica normal, 18m/s real baseado em wall-clock, seed 424242, `SANDBOX_PERF_TRACE=0`, perfil `adaptive-skip-progressive`, DM18 ON, DM19 diagnose ON, DM17-A/B OFF. APPDATA isolado por tentativa. Sem 54m/s.

- Smoke: 2 blocos cold straight 720 frames + 2 blocos warm straight 720 frames após 900 frames estacionário = **16 execuções**.
- Replicação: 6 blocos cold 720 + 4 blocos warm 720 + 2 blocos warm outback 2400 = **48 execuções**.
- Foco canônico ausente (%), frame p99, >33ms, HIGH visual, número de jobs canônicos, efeito `pending`, frames focal esperando 1º job, tempo de primeiro dispatch, acertos do cache DM18 e dos primed snapshots, overrides de prioridade e variação de RSS/VRAM (esta última exige medição local adicional).
- IC 95% sobre diferenças pareadas entre cada variante e controle por cenário; não converter 720/2400 frames correlacionados em amostras independentes.
- Não inferir automaticamente ganho de CI headless como equivalência GPU ou ausência de regressões em estados editados, colisões, cavernas, objetos e efeitos. Nenhum auto-merge.

## Gate de decisão

1. Exigir que DM20-A consiga preparar e reutilizar snapshots reais sem rejeição de revisão, que DM20-B realmente altere decisões quando há disputa de prioridade.
2. Candidato funcional só quando mostrar redução reprodutível do foco canônico ausente no cenário pertinente **sem regressão relevante em p99/frames>33ms/HIGH**. Em warm straight o foco pode estar próximo do piso (efeito de saturação), nesse caso considerar também warm outback e métricas de estado causal.
3. Se só há ganho cold, tratar como *startup* adaptativo, sem ligar sempre no jogo.
4. Se nenhum ganho persiste, preservar DM18 e reorientar para latência e dependências de projeção/outros jobs antes de elevar a concorrência.
5. Antes de promover, testes de paridade dinâmica de edits/undo, efeitos e revisões de objetos, colisões e GUI GPU.

**Estado provisório:** implementação + contratos qualificados. Smoke e replicação ainda pendentes no momento da criação deste registro. Nenhuma alteração na `main`.
