# DM15 — análise de `release_scope` e compactação da telemetria dormant

**Base:** `exp/dm14-lazy-route-qualification`, mantendo a DM13 (worker de água nativo), DM12 (cache SDF parcelado) e DM11 (canônico B4 rápido). **Data:** 13/11/2026. **Status:** otimização opt-in, main intocada.

## Instrumentação por subetapa

Branch `exp/dm15-release-scope-hotpath`, workflow [43462689273](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43462689273), **PASS**. Em `release_scope`, `SANDBOX_DM15_RELEASE_TRACE=1` mede separadamente:
- enumeração e ordenação de chaves reversas de chunks;
- remoção efetiva de vínculos;
- enfileiramento de limpeza DM14;
- exclusão dos mapas de escopos residentes/índices/revisão;
- manutenção da LRU `_dormant_scopes` e `_dormant_scope_order` (incluindo as emissões diagnósticas);
- atualização dos contadores.

Mesma seed 424242, janela 9×9, percurso determinístico `outback-18` de 960 frames, dois braços com a DM14 lazy OFF/ON. Cada braço removeu **142 escopos**.

| Fase (soma em 142 releases) | Lazy OFF | Lazy ON |
|---|---:|---:|
| Total de release | 145,501ms | 142,274ms |
| Rotas reversas | 6,113ms | 0ms no release |
| Fila lazy | 0ms | 1,161ms |
| Exclusão dos mapas | 0,487ms | 0,715ms |
| **Dormant / telemetria** | **138,331ms** | **139,852ms** |
| Contadores | 0,381ms | 0,359ms |

A fase dormant representa cerca de **95,1%** do custo medido com Lazy OFF e **98,3%** com Lazy ON. O maior release foi 3,401ms (OFF) e 5,971ms (ON), praticamente todo concentrado na etapa dormant. O log original produziu **142 mensagens** `effect_scope_dormant_store` em cada braço. A instrumentação tem overhead e esses números não são um A/B de FPS sem tracing.

**Interpretação:** adiar a limpeza de rotas não elimina o hotpath observado. A emissão de JSON para stdout dentro de `_remember_dormant_scope` é a principal hipótese, a ser isolada da manutenção real de cache com medição adicional. A melhoria potencial ocorre **com SANDBOX_PERF_TRACE=1**: com tracing desligado, a emissão já é desativada.

## Intervenção opt-in

Branch `exp/dm15-dormant-telemetry-rollup`. Flag **`SANDBOX_DM15_DORMANT_ROLLUP=1`**, padrão OFF.

- Preserva `release_scope`, `_dormant_scopes`, `_dormant_scope_order`, `MAX_DORMANT_SCOPES=256`, índices de efeito, revisões, publicação e cache persistente.
- Substitui cada `effect_scope_dormant_store` individual por contador de escopos e efeitos, emitido como `dm15_dormant_store_rollup` **uma vez por janela que efetivamente liberou fontes**. Conserva a contagem e ocupação, mas não inclui ID por fonte (disponível com rollup desligado).
- Publicação do rollup acontece **após** `update_resident_target_regions`, no thread principal, sem novos workers, mutações de autoridade ou alteração na ordem de efeitos.
- Inclui medição própria da etapa dormant em `dormant_cache_mutation_usec` versus `dormant_event_emit_usec`, com `SANDBOX_DM15_RELEASE_TRACE=1`.
- `take_dormant_store_rollup` consome somente os contadores diagnósticos uma vez, não o conteúdo da LRU.
- O modo antigo permanece disponível via `SANDBOX_DM15_DORMANT_ROLLUP=0`.

### Contratos

Testes `dm15_dormant_rollup_contract.gd`: nove escopos com efeitos, mesmas entradas e saídas; comparação de snapshots, LRU, contadores, limite, identidade e reativação de todos; soma exata das nove emissões em um rollup e consumo apenas uma vez. Regressões: DM14 rotas/tombstone, DM14 halo ordenado, D4.1 dormant, D7.3 source cache.

Workflow [43464613938](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43464613938) cobre contratos, A/B parado e em movimento, microperf detalhado e smoke GPU interativo (job dependente de runner). **Aguardar veredito no próprio run**, sem presumir aceitação ou fusão na main.

### Execução PowerShell

```powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin
git switch exp/dm15-dormant-telemetry-rollup
git pull --ff-only origin exp/dm15-dormant-telemetry-rollup

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
$env:SANDBOX_DM13_WATER_WORKERS = "1"
$env:SANDBOX_DM13_WATER_NATIVE = "1"
$env:SANDBOX_DM14_DENSE_REQUIRED = "1"
$env:SANDBOX_DM14_LAZY_ROUTES = "0"
$env:SANDBOX_DM15_DORMANT_ROLLUP = "1"
$env:SANDBOX_DM15_RELEASE_TRACE = "0"
$env:SANDBOX_PERF_TRACE = "1"
$env:SANDBOX_PERF_TRACE_MIN_MS = "2"

& "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --path .\game
```

**Controle A/B:** manter o mesmo branch e os mesmos parâmetros, alterar apenas `SANDBOX_DM15_DORMANT_ROLLUP=0`. Para gameplay sem instrumentação, `SANDBOX_PERF_TRACE=0`; nesse modo a otimização de emissão de logs não traz ganho significativo esperado.

## Critério de aceitação

Exigir regressões PASS, nenhuma diferença semântica em edição e LRU, redução de emissões e de CPU da própria etapa, ausência de piora consistente no core canônico/visual HIGH e idealmente melhora de p95/p99 de frame nas rotas repetidas. **Não fazer merge na main ou ativar por padrão antes de evidência e QA visual.**
