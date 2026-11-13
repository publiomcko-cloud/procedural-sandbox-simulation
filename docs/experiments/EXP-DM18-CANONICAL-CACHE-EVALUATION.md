# DM18 — Cache canônico de regiões completas

**Data:** 2026-11-13. **Estado:** código e contratos qualificados; benchmark integrado em execução. **Não mesclar na main.**

## Hipótese e diagnóstico

DM17-A/B reduziu CPU por chunk, mas 32 pares normais não reproduziram o ganho de foco esperado: diferença de −0,998 p.p. [IC95% −3,515; +1,518]. Isso indica que custo de SDF isoladamente não explica os gaps. Em DM16, o cache DM6/DM8 já retém HIGH visual em até 210m e 20s além de seu alcance; entretanto, o pipeline canônico de 16 chunks continua montando novos jobs ao voltar a uma região descarregada.

**Tese DM18:** guardar os 16 `ArrayMesh` canônicos completos de regiões que já foram geradas pode acelerar revisitas sem recálculo do SDF, preservando edição, objeto, simulação e autoridade via validação rígida de identidade. Não acelera regiões nunca visitadas.

## Implementação experimental

Branch `exp/dm18-canonical-region-revisit-cache`. Código:
- `game/scripts/terrain/dm18_canonical_region_cache.gd`: LRU de até 192 regiões / 128 MiB **estimados**, limite individual 16 MiB, cache de referências `ArrayMesh`, 16 coordenadas, LOD/fallback, contagens de vértices/triângulos.
- `game/scripts/terrain/terrain_demo.gd`: armazena no descarregamento, usa apenas estágios completos de LOAD, recupera em uma região por frame e reinsere pela publicação canônica original; não altera o caminho edit/partial/full, nem os serviços de objects/simulation/hydrology. Condicionado a `SANDBOX_DM18_CANONICAL_CACHE=1` com backend B4.
- Identidade publicada exige mesma seed, versão do gerador, `brush_edits.get_instance_id()`, revisão de edits, revisão mundial dos efeitos, flag de cavernas e backend B4. Captura compara a identidade *no momento da publicação* com o estado atual; edições parciais invalidam cache; world rebuild limpa registros.
- Os resources retidos podem ocupar RAM nativa **e VRAM**, além do contador estimado. O limite não equivale a um teto real de RSS ou VRAM; benchmark GPU e medições locais necessárias.

**Regra de segurança:** o cache só guarda o resultado visual canônico imutável já calculado. Ele **não é** cache da autoridade de edição, persistência, eventos, simulação, estado de mods ou escopos. Recria-se o `TerrainWorldState` a partir do ledger atual; após validação, `_publish_region` refaz os escopos de objeto/simulação e superfície. Um cache de todo o estado vivo seria semanticamente incorreto sem invalidar fontes, objetos, efeitos e saves.

## Evidências de qualificação

GitHub Actions [run 43509145460](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43509145460): etapa `exact` PASS no runner Windows Godot 4.7.2 (e PS 5.1). `DM18_CANONICAL_CACHE_RESULT`: 112 verificações, 0 falhas. Exercícios: presença de 16 meshes mesmo sem superfície, igualdade de referência, isolamento de dicionários devolvidos, sete identidades obsoletas, limite de memória estimada e LRU (35 expulsões no caso sintético). Regressões DM17 e DM11 passaram.

**Benchmark integrado:** workflow `.github/workflows/dm18-canonical-cache-factorial.yml`, script `scripts/perf/run-dm18-canonical-cache-factorial.ps1`. Matriz ABBA em 18m/s, seed fixa e `PERF_TRACE=0`, perfis de input iguais:
- `outback-long` 2400 frames × 8 pares (ida e volta de ~360m);
- `outback-short` 720 frames × 8 pares;
- `straight` 720 frames × 4 pares (controle frio sem revisita);
- `idle` 3600 frames × 2 pares (controle de preenchimento HIGH parado).
Total: 44 execuções (22 pares), precedidas de smoke 16 execuções.

Métricas: foco canônico ausente, p99, >20/33ms, HIGH visuais, misses do foco apesar de HIGH em cache, número de hits/stores/evictions, custo estimado das malhas retidas, número de jobs canônicos, worker queue/run, snapshot e tempo de upload. IC95% sobre diferenças pareadas, não frames correlacionados. Critério registrado: menos ≥5 p.p. de ausência do foco com CI acima ainda negativa na rota longa, sem regressão material de frame.

## Interpretação e próximos gates

Até o recebimento dos resultados integrados, **não afirmar que o cache acelerou o carregamento**. Mesmo que revise uma malha sem recomputar, publicação, efeitos e objetos ainda precisam ser refeitos com revisão atual. Um ganho isolado de cache hit não prova redução de lacuna nem consumo seguro de memória.

Após evidência headless, testar Windows GPU interativa real, colisões/brush em regiões revisitadas, edit/undo, mudança de world/seed, efeitos de objetos, hidrologia e persistência; medir RSS/VRAM e aumentar orçamento somente se houver benefício comprovado e uso seguro.

## Resultado integrado do smoke (16 execuções, 2 pares por cenário)

[GitHub Actions DM18 smoke](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43509145460), job smoke PASS. Valores são **médias de apenas dois pares**, não prova estatística para promoção.

| Cenário | Core ausente sem cache | Core ausente com cache | Diferença | Cache hits por corrida | Jobs canônicos sem cache | Jobs com cache | Cache retido estimado |
|---|---:|---:|---:|---:|---:|---:|---:|
| 18 m/s outback-long (2400 frames) | 38,375% | 34,292% | **−4,084 p.p.** | **32,5** | 1457,5 | 996,0 | 25,29 MiB |
| 18 m/s outback-short (720 frames) | 31,459% | 29,375% | −2,084 p.p. | 3,5 | 494,5 | 438,0 | 8,60 MiB |
| 18 m/s straight-18 (720 frames) | 38,611% | 41,667% | +3,056 p.p. | **0** | 491,0 | 482,5 | 11,50 MiB |
| Parado (3600 frames) | — | — | — | 0 | 144 | 144 | 0 MiB |

Outback-long p99 18,056ms sem cache contra 17,362ms com cache; frames >33ms 0,0625% vs 0,1665% (**pequena regressão nessa amostra**). Visual HIGH completadas não foi o objetivo primário. Tempo de conclusão HIGH parado controle 13,052s, cache 13,572s (+0,52s, IC muito amplo).

**Evidência do mecanismo:** em outback-long, restauração de uma região de cache levou em média **13,656ms desde o estágio até publicação**, enquanto regiões não cacheadas demoraram 1.227ms no braço controle (1.104ms no braço cache). Custo de cada chamada de publicação de cache: pico de 2,309ms, total ~47,826ms por corrida. Os **32,5 acertos por corrida** eliminaram ~461,5 jobs CPU canônicos, queda de 31,7%. Trabalho acumulado dos workers caiu de ~93,72s para ~62,75s e espera acumulada de ~32,24s para ~25,59s; são somas concorrentes, não tempo de parede. Frames sem foco canônico apesar de HIGH visual caíram de 744,5 para 688,5 no percurso longo.

O efeito em movimento contínuo foi **zero cache hits**, portanto a otimização não resolve regiões novas. Não extrapolar os 25,29 MiB de bytes estimados como uso efetivo de RAM/VRAM: `ArrayMesh` é `Resource` com alocação gráfica.

**Conclusão provisória:** cache correto e efetivamente usado, benefício plausível de cobertura em revisitas, ainda sem comprovação estatística de melhora do p99 ou de 5 p.p. de ausência canônica. O CI de replicação com 44 ensaios independentes está rodando nesse mesmo workflow; não registrar veredito de replicação antes da conclusão.
