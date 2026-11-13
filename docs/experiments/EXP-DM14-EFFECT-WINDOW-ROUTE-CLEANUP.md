# DM14 — Efeito de terreno: fonte do pico, halo denso e limpeza de rotas inativas

**Base:** DM13 water native low-priority, DM12 surface SDF sliced, DM11 canonical B4 fast, DM9 visual HIGH fast. **Data:** 13/11/2026. **Main:** intacta. Flags experimentais opt-in.

## Diagnóstico reproduzível

Workflow [43444499538](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43444499538) (Windows Godot 4.7.2) passou contratos existentes de D4.1 / D7.3 e completou um percurso `outback-18` com 960 frames. Em 19 transições de janela protegida 9×9: custo acumulado **205,207ms**, máximo **14,396ms**. Distribuição:
- `eviction_release_usec` **140,285ms (~68,4%)**, max **11,456ms** por transição. Uma transição removeu nove escopos.
- `required_usec` **33,890ms (~16,5%)**, max 3,259ms.
- `priority_sort_usec` **9,635ms (~4,7%)**, max 1,395ms.
- `prefetch_enqueue_usec` 9,413ms, mais 1,226ms em filtro e tempos menores em enumeração/parsing/proteção.

O gargalo dos picos era remoção **síncrona de roteamento derivado** de fontes antigas, não a atualização de volumes da água nem a simples contagem de fontes neste subcaminho.

## Experimento A — halo denso sem recomputação

Branch `exp/dm14-dense-window-fast`, flag `SANDBOX_DM14_DENSE_REQUIRED=1`. Para um conjunto **exatamente completo de 25 posições 5×5**, produz diretamente 81 regiões fonte 9×9 usando offsets pré-ordenados por Chebyshev, Manhattan, y e x, inclusive coordenadas negativas. Nunca altera dados autoritativos, revisão ou ordem de publicação. Todas as janelas irregulares, duplicadas, incompletas ou fora da forma 5×5 usam o algoritmo original.

Contrato: 65/65 verificações em 12 janelas pares, igualdade exata de **todos os 81 elementos e ordem**, fallback validado. Workflow [43445854682](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43445854682) PASS. Em 15 transições por opção, custo de `required+priority` **33,401ms → 0,964ms**. Custo total da janela **145,671ms→118,335ms** (~18,8% menor), porém picos individuais de até ~14,7ms persistem por causa de liberação síncrona (~101ms acumulados).

A/B sem instrumentação detalhada, duas execuções 18m/s: benefício canônico misto e **frames >33ms piores** na amostra (baseline 0,902% vs halo direto 1,734%). Não qualificado como intervenção isolada para fluidez, apesar da redução determinística do custo de cálculo. Parado, 268 regiões visuais HIGH concluídas em ambos.

## Experimento B — separar invalidação imediata de limpeza auxiliar

Branch `exp/dm14-lazy-route-cleanup`, flag `SANDBOX_DM14_LAZY_ROUTES=1` (opt-in, padrão 0). Mantém o halo denso `SANDBOX_DM14_DENSE_REQUIRED=1` em ambos os braços para testar apenas a mudança de liberação.

Original: `ProjectionService.release_scope` remove rotas reversas por todos os chunks **antes** de remover a fonte do mapa de escopos. Nova hipótese:
- **Mesmo frame:** remove a fonte de `_scopes`, `_scope_indexes`, `_storage_generations`, preserva o snapshot apenas no cache derivado `dormant` com o mesmo limite. O objeto autoritativo e a capacidade de residentes obedecem a semântica antiga.
- **Frames subsequentes:** remove somente strings de roteamento dos escopos já inativos, em até 24 chaves/frame ou orçamento suave de 1200µs. Consultas `get_frames_for_chunk` já verificam `_scope_indexes.has(scope_id)`; `snapshot_for_chunk` agora conta apenas as rotas de escopos ativos quando a flag está habilitada.
- **Reentrada:** `_install_scope_index` drena antes os vínculos pendentes do mesmo ID. Não pode remover a rota nova por uma limpeza atrasada.
- **Fail-closed no limite:** máximo 64 registros pendentes de limpeza; após esse limite, release volta automaticamente ao caminho síncrono original.
- `process_route_cleanup_step` só é chamado pelo `terrain_demo` no thread principal, antes de `process_prefetch_step`; nenhum worker acessa os dicionários mutáveis e nenhuma fonte inativa é considerada válida.
- Não altera SDF de terreno, localização de objetos, revisões, índices de authority, nem footprints.

Contrato `dm14_lazy_route_cleanup_contract.gd` testa identidade de escopo, invisibilidade de fonte inativa antes do GC, máximo de remoções por frame, limpeza completa, reentrada em índice com keys diferentes e legado OFF. Regressões D4.1/D7.3 e A/B no workflow [43447705475](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43447705475), em execução ao redigir.

## Critério de qualificação

Aprovar somente se:
- Godot 4.7.2 compilar, contratos e regressões de efeitos, objetos, revisões e roteamento passarem.
- Frames >33ms e >20ms diminuírem em rota pareada 18m/s, sem regressão relevante na ausência canônica, latência p95, HIGH visual à frente ou tempo de preenchimento parado.
- Após reentrada e GC, quantidade de escopos residentes permanecer <=81, contagem ativa de efeitos e `snapshot_sha256` iguais ao legado; sem backlog crescente ou crescimento de memória indefinido.
- Validação GPU real e visual local antes de qualquer merge na `main`.

## Variáveis e restauração

`SANDBOX_DM14_EFFECT_TRACE=1` — instrumentação por fase; não usar como benchmark sem overhead.

`SANDBOX_DM14_DENSE_REQUIRED=1` — halo 9×9 pré-ordenado para janela 5×5 exata.

`SANDBOX_DM14_LAZY_ROUTES=1` — limpeza incremental derivada, padrão OFF.

Controle: ambas DM14 flags como `0`, preservando DM13/12/11. Para teste somente de GC, manter `DENSE_REQUIRED=1` nos dois braços.

**Pendência:** benchmark de limpeza gradual ainda não concluído neste registro. Não presumir qualificação ou fazer merge por executar testes headless.
