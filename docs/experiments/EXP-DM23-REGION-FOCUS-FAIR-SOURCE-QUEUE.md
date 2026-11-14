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
