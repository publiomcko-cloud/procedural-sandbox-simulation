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
