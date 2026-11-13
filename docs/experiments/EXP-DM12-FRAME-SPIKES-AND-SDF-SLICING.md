# DM12 — Picos de frame após DM11: diagnóstico e redução experimental

**Base:** DM11 canônico otimizado (B4 + Surface Nets), visual HIGH compartilhado. **Data:** 2026-11-13. **Status:** testes de paridade e A/B aprovados; smoke GPU interativo aguardando runner quando este relatório foi escrito. **Main e branch DM11 de referência permanecem intactas.**

## 1. Instrumentação causal

Instrumentação opt-in `SANDBOX_DM12_FRAME_TRACE=1`, workflow [43427719706](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43427719706), PASSED. Distingue o `delta` da frame **anterior** do custo CPU da `_process` atual, e armazena durações e publicações do frame anterior para atribuição temporal correta.

Dois percursos de 720 frames a 18m/s capturaram 69 `delta >=33ms` (incluindo 2 de inicialização sem frame anterior). Em 65/69 houve trabalho no `_process` anterior >=14ms. Etapas dominantes do frame anterior: SDF surface cache **25**, água **15**, reconciliação da janela **13**, visual HIGH **12**, mesh dispatch **1**, effect prefetch **1** e inicialização **2**. Esses valores são *frequência de etapa dominante*, não duração agregada. O custo de instrumentação elevou os >33ms de ~3.05% (OFF) a 4.58–4.99% (ON), então só comparar desempenho **com trace OFF**.

A publicação atômica de 16 chunks em uma região canônica frequentemente custa <3ms e isoladamente não explica os spikes mais longos. Não reduzir qualidade da malha ou distância HIGH sem evidência.

## 2. Localização interna adicional

Workflow [43429769132](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43429769132), Windows headless PASS; branch `exp/dm12-focus-water-attribution`.

Nos nove eventos de reconciliação com >5ms de janela de foco, somas das subfases: **124.62ms** em `terrain_effect_runtime.update_resident_target_regions()` (máx 17.25ms), **51.62ms** em estágio/obtenção de novas regiões (máx 7.86ms), **12.02ms** em unload, menos de 2ms em diagnóstico, menos de 1ms em index/focus. Esses totais foram medidos apenas nesses nove eventos, não são frações do tempo total de execução.

Das **57** reconstruções de água com >8ms, `derive_shoreline_geometry` custou **543.67ms** no agregado (máx 19.08ms), versus **2.87ms** para criar `ArrayMesh` (máx 0.08ms) e 56.06ms de manutenção após o swap. Portanto o próximo gargalo hídrico é **triangulação/derivação CPU**, não upload GPU.

## 3. Intervenção experimental: snapshots de cache SDF em lotes

Branch `exp/dm12-surface-snapshot-slicing`; ativação opt-in `SANDBOX_DM12_SURFACE_SLICE=1`. `DM12SurfaceSnapshotBatch` prepara as 16 snapshots imutáveis sequencialmente em lotes de até 3 chunks/frame, soft budget de 2.5ms, e só submete o job de cache após verificar os 16 chunks, a identidade do escopo e a revisão; a composição de efeitos, snapshots finais, revisões, workers e publicação permanecem no código original.

**Exatidão:** 306/306 asserts em 6 casos (três regiões, pristino + editado) para igualdade exata dos 16 dicionários de snapshots, ordem dos targets, anchor, integridade de revisão e escopo. Regressões P5.0C surface cache 53/53 e DM11 geometria canônica 374/374. CI paridade PASS.

**A/B (mesma seed 424242 e rota outback-18, 720 frames, duas execuções por opção, instrumentação detalhada OFF):**

| Métrica | DM11 sem lote | DM12 lote |
|---|---:|---:|
| Frames >33ms | 3.1205% | **1.942%** |
| Frames >20ms | 12.7605% | **9.9865%** |
| Média frame | 18.0585ms | **17.7235ms** |
| Ausência do core canônico no foco | **24.375%** | 26.8055% |
| p95 carregamento canônico (média dos p95) | 1587.77ms | 1595.775ms |
| Regiões visuais HIGH concluídas | **80** | 77 |
| CPU média total capacidade | 15.63% | 14.085% |

**Parado (3600 frames, um teste por opção):** raio HIGH inteiro 13.327869s vs 13.228952s (lote), 268 regiões externas em ambos, nenhuma lacuna final. O lote não amplia o raio, reduz LOD, simplifica o SDF ou descarta efeitos.

**Veredito de engenharia:** `DM12_SURFACE_SLICE_CANDIDATE_WITH_TRADEOFF`. Queda relativa aproximada de **37.8% nos frames >33ms**, mas aumento médio de **2.43 pontos percentuais** na ausência do core canônico e redução de 3/80 regiões visuais HIGH durante o deslocamento. Precisa de QA local e GPU antes de integração geral. A evidência A/B não prova significância estatística: apenas dois pares com múltiplos subsistemas em concorrência.

Workflow original teve erro de tipagem da inicialização do array no caminho OFF; corrigido antes da campanha completa. Campanha correta: [43429301805](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43429301805) contrato PASS e A/B PASS; GPU enfileirado na última consulta.

## 4. Modo de execução local

```powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin
git switch exp/dm12-surface-snapshot-slicing
git pull --ff-only origin exp/dm12-surface-snapshot-slicing

$env:SANDBOX_TERRAIN_BACKEND = "b4"
$env:SANDBOX_STREAM_PROFILE = "adaptive-skip-progressive"
$env:SANDBOX_DM9_FAST_B4 = "1"
$env:SANDBOX_DM9_PREFETCH = "0"
$env:SANDBOX_DM9_VISUAL_ADAPTIVE = "1"
$env:SANDBOX_DM9_VISUAL_WORKERS = "4"
$env:SANDBOX_DM11_CANONICAL_FAST_B4 = "1"
$env:SANDBOX_DM11_VISUAL_LANE = "0"
$env:SANDBOX_DM12_SURFACE_SLICE = "1"
$env:SANDBOX_DM12_FRAME_TRACE = "0"
$env:SANDBOX_PERF_TRACE = "1"

& "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --path .\game
```

Para controle DM11 em mesmo branch, alterar apenas `SANDBOX_DM12_SURFACE_SLICE="0"`.

## 5. Próximas intervenções fundamentadas

- O cache de superfície ainda concentra preparação completa dos frames de efeito e duplicações na submissão final: estudar orçamento separado para etapa de efeito com revisão-gate, preservando seus contratos.
- **Água:** experimentar pré-cálculo da geometria costeira em job CPU dedicado imutável, com troca de malha revision-gated e retained-old visual, equivalência de posições/cores/tokens/SDF e métricas de latência.
- **Troca de regiões:** decompor `terrain_effect_runtime.update_resident_target_regions` em etapas/prefetch validados, sem alterar fonte autoritativa nem ordem de efeitos.
- Investigar p95/p99 da frame **GPU real** e efeitos de instrumentação sem trace detalhado. Manter `main` e DM11 de referência sem mudanças por enquanto.
