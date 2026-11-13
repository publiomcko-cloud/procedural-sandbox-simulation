# DM16 — benchmark independente de telemetria e picos reais

**Base:** `exp/dm15-dormant-telemetry-rollup`, com DM11 canônico B4 rápido, DM12 cache SDF parcelado, DM13 água em thread nativa baixa prioridade, DM14 halo denso e limpeza de rotas legacy; `main` intacta.

## Problema metodológico

O benchmark histórico `run-p5-deterministic-stream-benchmark.ps1` **força `SANDBOX_PERF_TRACE=1`** para coletar indicadores por eventos `terrain_stream_budget_window`, `terrain_region_load_complete`, `dm8_high_radial_complete` etc. Desligar o trace nesse benchmark invalidaria os próprios cálculos do harness. Além disso, a DM15 demonstrou que serializar/emitir 104 mensagens individuais do cache dormant podia ocupar 103,84ms de CPU acumulados durante uma rota 18m/s. Portanto, comparar apenas variantes **com** tracing não respondia ao custo real dos picos sem instrumentação.

## Nova medição independente

- `game/scripts/diagnostics/dm16_benchmark_probe.gd`: coletor **em memória**, apenas para benchmarks determinísticos, de amostras individuais de frame, percentis p95/p99, contagens >20/>33/>50ms, duração total de `_process`, faltas canônicas no foco, progresso HIGH externo e primeiro preenchimento HIGH parado. Não usa `PerformanceTrace.emit` e não escreve logs em cada frame.
- `game/scripts/terrain/terrain_demo.gd`: cria o coletor somente quando **ambas** `SANDBOX_STREAM_BENCHMARK=1` e `SANDBOX_DM16_BENCH_METRICS=1`; emite **um único** `DM16_BENCH_SUMMARY` antes do receipt final `P5_STREAM_BENCH_COMPLETE`. Fora desse modo não há mudança funcional no jogo. `SANDBOX_DM16_LIGHT_STAGES=1` registra adicionalmente as durações dos estágios de `_stream_stage_measure` em memória, não em console.
- Atribuição de spikes do Godot: `delta` representa tempo desde o frame **anterior**; `spike_prior_dominant_stage_counts` usa sempre os estágios do `_process` anterior. Não atribuir como causa comprovada, apenas indicação temporal.
- `scripts/perf/run-dm16-trace-factorial.ps1`: **novo harness, independente do P5 antigo**. Valida seed 424242, rota, distância, perfil, número de frames, ausência absoluta de `PERF_TRACE` nos modos OFF/light e presença dos eventos no modo full; mede quantidade de mensagens/bytes, mesmo coletor terminal nos três braços, e isola `APPDATA` por trial.
- `game/tests/experiments/dm16_benchmark_probe_contract.gd`: contrato de alinhamento temporal, delta e estágios anteriores, p95/p99, cobertura, conversão de porcentagens, modo sem trace e preenchimento HIGH.

## Matriz A/B

Mesmo commit, seed, F10 `outback-18` 720 frames, Godot 4.7.2 headless e `adaptive-skip-progressive`. Dois ensaios por modo em ordem alternada para reduzir viés de aquecimento e concorrência:

| Modo | `SANDBOX_PERF_TRACE` | `SANDBOX_DM16_LIGHT_STAGES` | Evidência |
|---|---|---|---|
| OFF | `0` | `0` | Resumo básico em memória, sem evento PERF_TRACE |
| LIGHT | `0` | `1` | Resumo básico + estágios agregados e etapa dominante do frame anterior; sem evento PERF_TRACE |
| FULL | `1` | `0` | Eventos normais completos, com rollup dormant DM15 habilitado, mais o mesmo resumo básico independente |

O segundo grupo compara os três modos parados durante 3600 frames e observa conclusão HIGH. A ordem é `a-off, a-light, a-full, b-full, b-light, b-off, idle-off, idle-light, idle-full`. Cada teste inicia um `user://` independente, sem acessar mundos/mods do usuário. Todos mantêm as mesmas flags de geração, renderização e worker.

**Risco de medição:** OFF ainda executa um coletor mínimo de uma amostra por frame, não equivale a um processo comercial sem qualquer observabilidade; o custo está limitado e é o mesmo nos três braços. LIGHT mede mais relógios/rotas e pode ter overhead. FULL produz logs de muitos subsistemas e altera escalonamento; diferenças entre condições indicam overhead de diagnóstico, mas duas repetições não garantem significância estatística ou causalidade determinística dos spikes.

## Qualificação e rollout

Workflow [DM16 trace-independent factorial](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/workflows/dm16-trace-independent-factorial.yml). Verificar status antes de confiar nas métricas. Contratos executam parsing completo do Godot, probe de frame anterior e regressões DM15/DM14.

Não foram alteradas malhas, SDF, efeito autoritativo, hydrology, escopos, filas ou distâncias de streaming. **Não mesclar na main por sucesso apenas do benchmark**; o objetivo da DM16 é localizar o gargalo real e impedir falsas conclusões com instrumentação pesada.

### Comando PowerShell de reprodução

```powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin
git switch exp/dm16-trace-independent-frame-evidence
git pull --ff-only origin exp/dm16-trace-independent-frame-evidence

$env:SANDBOX_TERRAIN_BACKEND = "b4"
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

& .\scripts\perf\run-dm16-trace-factorial.ps1 -GodotBin "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" -EvidenceDir ".\dm16-evidence"
```

**Status técnico no momento do checkpoint:** novo coletor e sua validação de sintaxe e contrato passaram, bem como as regressões DM15/DM14. A matriz nove ensaios prossegue; veredito de desempenho deve ser baseado nos resultados finais da CI e não estimado.
