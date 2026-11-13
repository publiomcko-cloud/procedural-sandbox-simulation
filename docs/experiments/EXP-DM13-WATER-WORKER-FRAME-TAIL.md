# DM13 — Geometria costeira em worker CPU revision-gated

**Base:** DM12, SDF em lotes (`SANDBOX_DM12_SURFACE_SLICE=1`), DM11 `CANONICAL_FAST_B4=1`, DM9 visual B4 rápido/adaptativo. **Branch:** `exp/dm13-water-low-priority-native`. `main` permanece inalterada. **Data:** 13/11/2026.

## Gargalo demonstrado

A instrumentação anterior isolou 57 reconstruções de água lentas, com **543,67 ms de CPU acumulado** em `derive_shoreline_geometry` e apenas **2,87 ms** na criação do `ArrayMesh`. A triangulação/clipping SDF estava no `_process` principal e participava dos picos >33 ms. A geometria da água é derivada: não é autoridade de volume, edição ou simulação.

## Implementação

- `game/scripts/simulation/dm13_water_geometry_job.gd`: worker CPU-only que captura cópias profundas dos registros imutáveis de ambiente, superfície SDF, shoreline esparsa e máscaras oceânicas, e invoca **a mesma função pura** `EnvironmentVisualPresentation.derive_shoreline_geometry` sem fazer qualquer operação de SceneTree, Mesh, RenderingServer, persistência ou alteração autoritativa.
- `game/scripts/simulation/environment_visual_presentation.gd`: o publisher original de malha e metadados foi extraído para um único método compartilhado por sync e async. Antes da troca, o resultado é rejeitado se divergir o epoch do mundo/modo, o objeto visual da cena, token de revisão do SDF/efeitos/brush, shoreline token, assinatura quantizada da água, disponibilidade hidrológica ou máscaras de vizinhos oceânicos. Rebuilds obsoletos são descartados e refeitos; malha anterior fica retida enquanto aguardamos fonte nova. Join de todos os workers em `_exit_tree`, inclusive em unload/reconfigure.
- `SANDBOX_DM13_WATER_WORKERS=1` habilita a experiência; por padrão `0` mantém o cálculo síncrono original. A variante inicial usa `WorkerThreadPool` (até 2 tarefas simultâneas e 1 submissão/1 publicação por frame). `SANDBOX_DM13_WATER_NATIVE=1` escolhe **uma thread nativa `Thread.PRIORITY_LOW` simultânea** para evitar competição pela mesma fila dos jobs canônicos. Nenhuma mudança em LOD, geometria, volume ou edição.
- Eventos de rastreamento: `dm13_water_job_submitted` e `dm13_water_job_completed` registram fila, cálculo CPU, publicação, lane e identidade do thread. `get_visual_metrics` informa jobs, stale discards, picos e completions.

## Contratos e regressões

Workflow [43433955564](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43433955564): 61/61 checks worker compartilhado, 210/210 P5.0F visuais, 306/306 DM12 snapshots SDF, 374/374 DM11 geometria; 6-trial A/B headless passou; GPU interativo aguardando runner.

Workflow [43435174206](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43435174206): 88/88 checks worker + thread nativa com igualdade exata de todos os arrays e metadados em nove casos (pristino, rivular/finito/oceânico, modos normal/sources/ocean-only), invalidação por água, revisão do terreno, modo e unload. Regressões P5.0F, DM12, DM11 e P5.0C passaram. 6-trial A/B headless passou; GPU interativo aguarda runner separado.

## A/B 18 m/s, seed 424242, 720 frames, 2 repetições por braço

Comparações pareadas dentro de cada campanha, **sem** o rastreamento detalhado `SANDBOX_DM12_FRAME_TRACE` (evita overhead da instrumentação); trace básico preservado igual nos dois braços.

| Métrica | DM12 (baseline da campanha nativa) | DM13 nativa, 1 thread baixa prioridade |
|---|---:|---:|
| Frames >33ms | 2,011% | **0,833%** |
| Frames >20ms | 9,154% | **6,311%** |
| Tempo médio frame | 17,651ms | **17,292ms** |
| Falta do foco canônico | **25,972%** | 27,987% |
| p95 latência canônica (média dos p95) | **1574,755ms** | 1589,806ms |
| HIGH visual regiões concluídas | **78** | 74,5 |

Redução relativa **58,6%** nos frames >33ms, **31,1%** nos >20ms. Latência canônica p95 aumentou **~1%** e falta do foco canônico **2,0 pontos percentuais**; throughput visual HIGH caiu 3,5 regiões (4,5%). São apenas dois pares, não garantir significância estatística. O primeiro par teve core missing 24,722%→31,806%, o segundo 27,222%→24,167%; há variabilidade importante.

**Parado (3600 frames, 1 execução por braço):** 277 regiões HIGH concluídas, 268 regiões externas visual HIGH, sem gaps finais; tempo total 13,188s baseline → **13,052s nativa**. Nesse teste, o >33ms foi 0,139% em ambos.

**Comparação com lane compartilhada (workflow 43433955564, outros seeds percursos idênticos):** quedas >33ms 2,636%→1,803% (31,6%); falta canônica 26,180%→29,792%, p95 1541,7→1702,2ms; HIGH concluídas 74,5→71,5. Uma thread nativa baixa prioridade reduziu significativamente a regressão de latência canônica em relação ao uso da fila compartilhada; não removeu completamente a variação de missing focus.

**Veredito:** `DM13_NATIVE_LOW_VISUAL_QA_CANDIDATE`. Contratos e headless A/B qualificados, ganho expressivo na cauda de frame, pequena regressão canônica/visual em movimento; **não ativar por padrão nem fazer merge na main** antes do GPU smoke e aprovação visual local. O GPU interativo está enfileirado por disponibilidade do runner; não inferir validação gráfica a partir do headless.

## Execução local (PowerShell)

```powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin
git switch exp/dm13-water-low-priority-native
git pull --ff-only origin exp/dm13-water-low-priority-native

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
$env:SANDBOX_PERF_TRACE = "1"
$env:SANDBOX_PERF_TRACE_MIN_MS = "2"

& "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --path .\game
```

Comparação controle no mesmo branch: desligar `SANDBOX_DM13_WATER_WORKERS=0`. Comparar percurso a 18m/s, raio HIGH estacionário e fidelidade da água ao editar e atravessar o oceano.

## Próximo gargalo

A instrumentação DM12 de nove eventos pesados de reconciliação atribuiu **124,62ms acumulados** a `terrain_object_effect_runtime.update_resident_target_regions`, máx 17,25ms. O caminho ainda ordena regiões, altera conjunto protegido, libera escopos obsoletos e enfileira prefetch em uma única transição. Próxima fase deve instrumentar internamente ordenação, escopos liberados e enfileiramento, para depois distribuir trabalho apenas onde provas de equivalência permitirem. Manter a ordem de efeitos e a semântica de revisões/escopos.
