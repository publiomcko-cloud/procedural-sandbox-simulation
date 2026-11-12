# DM7 — Geometria HIGH de rochas no raio 4 (terreno HIGH raio 6)

**Branch:** `exp/dm7-b4-high-rock-radius4` (derivada da DM6, sem merge em `main`). O escopo desta fase é **somente HIGH dos objetos/rochas**, preservando terreno, água, retenção e simulação de DM6. O autor validou visualmente DM6, ressalvando que rochas ainda ficavam LOW além do núcleo e faziam `pop` quando a câmera se aproximava.

**Índice consolidado e precedência:** [DM1–DM7 — Arquitetura, descobertas e decisões](./DM1-DM7-EXPERIMENTAL-ARCHITECTURE-AND-FINDINGS.md).

## Implementação

- **Raio de terreno HIGH:** 6 regiões, grid 13×13 = **169 regiões**, malha B4 0,5 m. **Não mudou na DM7**.
- **Raio de rochas HIGH:** 4 regiões, grid 9×9 = **81 posições**, sendo 9 centrais autoritativas e **72 exteriores** com render derivado. Todas as outras rochas da camada exterior continuam como LOW (instância `MultiMesh` de `SphereMesh` leve), até entrarem na fila HIGH.
- **Mesmo algoritmo do jogo:** `b4_high_detail_rock_job.gd` resolve `ProceduralObjectWorld.build_region_instances` usando o `ContentDefinitionRegistry` mod-first já carregado, monta as geometrias originais `ProceduralRockMeshAdapter.build_cpu_data` → `ProceduralRockShapeDescriptor`, e combina as transformações em `ProceduralObjectStaticBatch.prepare`. O main thread publica via `ProceduralObjectStaticBatch.commit`. Geometria, escala, yaw, posições e identidades são as mesmas do terreno *pristine*, inclusive em coordenadas negativas. Nenhum componente mutável/estado persistido é consultado fora da autoridade.
- **Agendamento:** um job HIGH de rochas de cada vez no `WorkerThreadPool`, priorizado pela fila existente (distância Chebyshev crescente e direção da visão). O high job só inicia quando a região já tem terreno HIGH visual e `DM5` criou seu registro de rochas LOW/água LOW; a publicação fica dentro das condições de orçamento de CPU/frame existentes. A água não precisa ser recalculada ou publicada outra vez na transição.
- **Promoção sem buraco:** a nova `ArrayMesh` HIGH de rochas é adicionada ao mesmo nó regional, **depois** `LowRocks` é ocultado, com `LowWater` preservado. O registro passa a `rock_high=true`; retrabalho para a mesma região é idempotente. Se o worker falhar, LOW permanece, e o retry é bloqueado durante cinco segundos (registro `dm7_rock_high_failed`).
- **Retenção:** o high adquirido persiste fora do raio 4 enquanto o terreno HIGH que o suporta estiver sob a retenção da DM6: dentro do raio 10 ou até decorrerem 20 segundos fora dele. **Não faz downgrade HIGH→LOW por distância**; só é descartado quando o registro da região expira, é invalidado legitimamente, ou o serviço de objetos canônico assumiu.
- **Handoff central:** o proxy de rochas externas não é descartado no instante em que os 16 chunks de terreno são confirmados; aguarda publicação de objetos por `ProceduralObjectStream.has_published_region`. A remoção é feita pela varredura de decoração, atualmente com periodicidade de até 200 ms; durante esse intervalo podem coexistir meshes do proxy e da autoridade.
- **Estado de gameplay:** o usuário não pode manipular/colidir com as rochas HIGH derivadas; somente os objetos canônicos têm lógica, efeitos SDF, estado de deleção ou transformação persistida. O sistema também não fornece render HIGH para uma classe de mod desconhecida; o suporte HIGH testado é para a receita geológica de rocha, enquanto LOW exterior continua quando indisponível.

## Cobertura e testes de integridade

- `game/tests/experiments/dm7_high_rock_parity_tests.gd`: registry real `res://mods/first-party`, 6 regiões (incluindo negativas), 18 rochas e **82 asserções sem falhas**: posições/normais/ordem/instâncias correspondem **exatamente** à construção por `ObjectWorld` + `RockMeshAdapter` + `StaticBatch`. Um fixture verifica instalação da malha HIGH, ocultação de LOW apenas após o commit, água LOW visível e ausência de duplicação por commit repetido.
- Na primeira execução Windows real, todas as **72 regiões externas** produziram evento `dm7_rock_high_visible`, com zero falhas de job, e o terreno manteve **160 regiões exteriores HIGH**. O job `full-fill` inicial falhou apenas na condição de receipt que exigia objeto canônico publicado mesmo numa região central com **zero instâncias de rocha**. Esse bloqueio documental/qualificativo foi corrigido: o receipt passa a exigir terreno canônico nas nove regiões do núcleo e HIGH de rochas em 72 exteriores; o número de regiões canônicas com objetos publicados é informado separadamente. Código de geometria não precisou ser alterado.
- O teste GPU real no Windows GTX 1050 Ti (360 frames, normal 18 m/s) identificou `dm7_rock_high_visible` junto com publicação de terreno HIGH e água/rochas LOW. Ele é um smoke gráfico, não inspeção humana de aparência final.

## Custo incremental medido na primeira execução idle de 9.000 frames

No seed determinístico do benchmark com mods first-party e 72 regiões externas:
- **194 rochas** em 72 regiões: 1–6 rochas por região, mediana de 3.
- **72.792 triângulos** HIGH de rocha; mediana **1.104 triângulos/região**, p95 1.920, máximo 2.304.
- **5.241.024 bytes = 5,00 MiB de payload geométrico bruto** em todas as 72 regiões; mediana **79.488 B = 77,6 KiB/região**, p95 138.240 B e máximo 165.888 B. Isso corresponde a `PackedVector3Array` + normais, sem `ArrayMesh`/driver/cópias internas.
- Worker CPU das rochas HIGH: mediana **56,36 ms por região** (p95 **113,4 ms**); soma dos 72 workers **4,13 s** de CPU em toda a sessão, distribuídos na fila, não uma pausa única.
- Benchmark headless completo na execução qualificada: frame médio **16,733 ms**, processamento médio **2,661 ms**, **0,50%** dos quadros acima de 20 ms, **0,178%** acima de 33 ms. Sem inferência de FPS GPU a partir dos valores headless.
- DM6 (sem HIGH de rochas): benchmark idle comparável reportou frame médio **16,711 ms**, process médio **2,387 ms**. A diferença é observacional de corridas não pareadas; não é prova estatística de regressão ou equivalência.
- O autor observou no DM6 **RAM inferior a 300 MB e VRAM pouco alterada**; DM7 não mediu RSS/VRAM total da sessão. O custo adicional das malhas é pequeno no payload, mas o pico de processamento/recursos continua a depender dos mods instalados.

## O que permanece fora do escopo

Não modificamos o raio 6 do terreno, TTL/raio 10, simulação, água, colisão, estado dos objetos, cache persistente, lookahead/prefetch de chunks, prioridade de jobs canônicos ou modo F10 rápido. O material do objeto pode variar por estado de aparência do jogador; o HIGH derivado usa apenas aparência padrão pristine, com mesmo material base da rocha. Edições, exclusões ou efeitos de objeto não são reexecutados fora da janela autoritativa.

## Resultado de qualificação

Workflow: [DM7 B4 HIGH rochas no raio 4](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/workflows/dm7-b4-high-rock-radius4.yml).

A execução inicial [#43298696013](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43298696013) passou contract, F10 e GPU, mas o `full-fill` rejeitou a ausência do receipt por exigir nove eventos de publicação de objetos canônicos; logs de geometria mostraram os **72/72** batches HIGH exteriores. Critério corrigido no commit `0bbe3d27ef601e3d1f9baa9391f1cee5670f1d8f`.

**Qualificação final: WINDOWS_QUALIFIED, NOT_MAINLINE_MERGED.** [GitHub Actions #43300134756](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43300134756), commit de código `0bbe3d27ef601e3d1f9baa9391f1cee5670f1d8f`, **5/5 jobs PASS**.

- `contract`: scripts import/check-only e paridade exata em seis regiões com 18 rochas, **82 asserções / 0 falhas**; suites DM6/DM5 de memória, TTL e prioridade permanecem passando.
- `f10`: rotas determinísticas outback-18, outback-54 e idle, todas PASS; **57 publicações de HIGH de rochas** registradas em conjunto na primeira campanha e publicação confirmada na repetição. É smoke de integridade, não garantia de ausência perceptível em alta velocidade.
- `gpu`: GTX 1050 Ti em sessão Windows real, 360 frames no percurso normal 18 m/s, `dm7_rock_high_visible`, `dm4_region_b4_high_visible` e `dm5_low_decor_visible` presentes; imagem anexada.
- `full-fill`: **169/169 regiões de terreno HIGH** (160 exteriores); **81/81 posições cobertas por HIGH de rochas** (72 externas + 9 canônicas), comprovante `DM7_ROCK_HIGH_RADIUS_COMPLETE` emitido uma vez; 160 eventos LOW de rochas e 121 eventos LOW de oceano. A recepção declarou **8 das 9 regiões canônicas com publicação de objetos**, pois uma delas tinha zero instâncias no benchmark. Frame médio **16,733 ms** e process médio **2,661 ms** headless, 0,50% de frames acima de 20 ms, 0,178% acima de 33 ms.
- `warm-return`: 4.800 frames de aquecimento em cada processo, mais trajetos ida e volta de 720 frames a 18/54 m/s; **34 + 39 = 73 reutilizações de terreno HIGH**, todas `superseded_by_low=false`. **126 registros telemétricos** confirmaram rochas HIGH retidas visualmente *fora do raio 4*, sem expiração prematura no intervalo do teste. Marcador `DM7_WARM_RETURN_PASS` emitido.

Artefatos oficiais do run: [contratos e memórias](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43300134756/artifacts/13979969669), [F10](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43300134756/artifacts/13980124563), [GPU](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43300134756/artifacts/13980493749), [full-fill](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43300134756/artifacts/13982015911), [retorno aquecido](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43300134756/artifacts/13981089379).

**Limite da aprovação:** os testes garantem geometria exata pristine no conteúdo testado e comportamento automatizado de streaming; não representam inspeção humana da DM7 na máquina do autor nem paridade com objetos editados/mods desconhecidos. Exigem validação visual local antes de integração.

## Próxima direção técnica sugerida — NÃO executada

Após aprovação visual local de DM7, priorizar **prefetch canônico com antecedência à câmera no movimento F10 normal de 18 m/s**: medir p50/p95 de enfileiramento, worker SDF/B4, compilação dos 16 chunks e commit, calcular horizonte adaptativo em metros/regiões baseado em velocidade e latência, validar sem regressão no núcleo e sem extrapolar a fonte de efeitos (81 scopes). Não otimizar o F10 acelerado de 54 m/s como objetivo de produto. Testar crescimento de RSS e VRAM, além de frame time real, em deslocamento longo. Só depois considerar aumentar o HIGH de rochas de 4 para 5–6 ou processar malhas na GPU.

**Status:** branch isolada para validação; sem merge em `main`.
