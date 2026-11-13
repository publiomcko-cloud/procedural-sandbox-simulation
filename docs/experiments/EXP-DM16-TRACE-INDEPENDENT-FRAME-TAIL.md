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

**Status final:** contrato e compilação PASS; segunda matriz de nove ensaios PASS. Primeira matriz de nove ensaios produziu dados válidos, mas a etapa de agregação PowerShell falhou porque `Measure-Object -Property` não reconheceu uma hashtable; correção para `[pscustomobject]` foi aplicada antes da segunda execução. Resultados de ambos os grupos são auditáveis nos logs e artefatos de CI.


## Resultado final — quatro repetições móveis por modo

- [Primeira execução, dados completos / agregador falhou](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43469762099): **9/9 ensaios geraram receipts íntegros**, artefato preservado. Falhou somente a conversão das hashtables para `Measure-Object` após os nove testes.
- [Execução qualificada](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43471240089): **exact PASS, factorial PASS**, scripts PowerShell 5.1 corrigidos, 9/9 ensaios com todas as invariantes. É o veredito de CI da DM16.
- Ao combinar os dois grupos válidos temos **4×720 frames móveis por modo (2.880)** e **2×3600 frames estacionários por modo (7.200)**. Instrumentação, terreno, seed e configuração de workers idênticos; alteração entre commits restrita a agregação pós-processamento PowerShell. São apenas quatro repetições, sem garantia de significância estatística.

| Métrica móvel média | OFF (0 eventos PERF) | LIGHT (0 eventos PERF) | FULL (tracing DM15 agregado) |
|---|---:|---:|---:|
| Frames >33ms | **0,278%** | 0,417% | 1,979% |
| Frames >20ms | **0,973%** | 1,250% | 8,333% |
| Frame p99 | **19,391ms** | 22,532ms | 51,933ms |
| Frame médio | **16,872ms** | 16,908ms | 17,862ms |
| Duração média completa de `_process` | 5,994ms | **5,943ms** | 10,115ms |
| Foco canônico ausente | 32,951% | 33,056% | **26,215%** |
| Regiões HIGH visuais concluídas | 65,0 | 66,25 | 72,75 |
| Eventos `PERF_TRACE` nos quatro testes | **0** | **0** | 14.309 |

**Overhead:** o FULL apresentou cerca de **7,1×** a taxa de frames >33ms e p99 de **2,68×** frente ao OFF. Os quatro ensaios FULL apresentaram >33ms variando de 0,556% a 4,861%, refletindo grande variabilidade do scheduler/console. As métricas representam **instrumentação + logging** combinados; não atribuir todo o incremento exclusivamente à serialização de JSON. No OFF, a taxa >33ms variou de 0,139% a 0,417%. São headless, não medem frame de GPU real.

**Viés de movimento:** com FULL, o core ausente cai artificialmente de ~33% a ~26%, e HIGH visuais concluídas aumentam (65→73), apesar da execução mais lenta. O benchmark move a câmera por `STREAM_BENCH_STEP_SEC` por frame, e não pelo tempo real decorrido. Um frame atrasado por log permite aos workers avançarem mais no tempo real antes de o jogador progredir na distância simulada; **isso não deve ser chamado de melhoria canônica**. O novo baseline para otimizações de movimento deve ser o modo OFF e a próxima fase deve ter uma rota a **velocidade por tempo de parede**.

**Parado:** em ambos os ensaios, todas as **268 regiões HIGH externas** e o núcleo canônico 3×3 foram concluídos nos três modos. Tempo médio até HIGH completo: OFF **13,652s**, LIGHT **13,379s**, FULL **14,469s**. Frames >33ms parado: OFF **0,084%**, LIGHT **0,083%**, FULL **0,778%**. O console completo piora a cauda também sem movimento.

**Picos residuais:** na coleta LIGHT de quatro percursos, foram apenas **12 frames >33ms** em 2.880 frames; classificações da etapa dominante do **`_process` anterior**: `sdf_cache` **5**, `mesh_dispatch_and_upload` **1**, `effect_prefetch` **1**, `focus_window_lookahead` **1** e sem etapa atribuída **4** (incluindo potenciais frames de inicialização). Picos de etapa em LIGHT: `sdf_cache` **22,793ms**, visual HIGH **14,852ms**, foco **9,791ms**, dispatch **8,541ms**, effect prefetch **8,273ms**, water visual **2,956ms**. Esses valores são correlações temporais e máximos individuais, não provas de causalidade do delta.

### Veredito

**`DM16_TRACE_INDEPENDENT_QUALIFIED_OVERHEAD_CONFIRMED`**. A nova instrumentação leve e independente foi validada, os dois conjuntos de medições mostram forte contaminação de cauda e cobertura pelo tracing completo, e o problema residual de frames lentos no headless sem tracing é raro. **Não alterar mesh, SDF, água ou LOD com base nos picos com PERF_TRACE=1**. Usar OFF para taxa de gaps/FPS e LIGHT para localizar estágios, mantendo os dados iguais no laboratório.

O trace OFF ainda conserva um coletor O(1) em memória no modo benchmark; fora do benchmark DM16 não existe overhead. Sem renderização interativa GPU, nenhum desses números valida a experiência visual real. `main` permanece intocada.

**Próxima direção fundamentada:** criar teste F10 a **18m/s por tempo decorrido real**, com logs OFF e LIGHT, verificando a disponibilidade canônica sob carga sem distorção temporal. Somente depois otimizar os picos remanescentes do SDF cache/snapshots de efeitos e a publicação de meshes. O teste GPU/local permanece necessário para p99 de frame renderizado.
