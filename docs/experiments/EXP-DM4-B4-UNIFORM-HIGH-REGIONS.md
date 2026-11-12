# DM4 — 5 regiões completas em B4 HIGH, fila por distância e direção

**Branch:** `exp/dm4-b4-uniform-high-region-stream` (experimental; sem merge na `main`).

## Problema da DM3

A borda marcada entre regiões carregadas e regiões de cobertura é consequência de malhas com **algoritmos diferentes**: B4 Q8.8 Surface Nets a 0,5 m no runtime central versus heightfield 1 m/2 m na camada visual externa. Apenas elevar a resolução do heightfield não eliminaria a diferença de topologia, especialmente onde existem cavernas.

## Correção DM4

- Todo o raio visual **5 regiões** (até 121 regiões no total, incluindo as nove posições centrais autoritativas) usa representação **B4 Q8.8 / Surface Nets, 0,5 m**, sem anel LOW. A região exterior emprega o gerador B4 por região, cujo resultado combina os mesmos 16 chunks do backend DM1, com halo de amostragem e propriedade das faces mantidos.
- **Fila incremental:** primeiro a menor distância Chebyshev em regiões; dentro de cada anel, prioridade ao alinhamento com o vetor horizontal à frente da câmera. Desempate estável por coordenadas. A fila continua a gerar regiões pendentes até cobrir a janela completa, desde que haja orçamento de CPU e o jogador permaneça na área.
- **Orçamento:** um único job B4 visual em background; no máximo uma publicação de mesh por frame, com veto de quadros muito lentos. A prioridade do trabalho autoritativo permanece maior que a da camada visual.
- **Retenção:** regiões previamente visíveis ficam no raio 10 ou durante 20 s após sair dele, limitadas ao cache visual de até 512 shells e 48 regiões com malhas definitivas aposentadas.
- **Compatibilidade:** os estados de edição, simulação, objetos, hidrologia, projeção de efeitos e persistência permanecem no subsistema autoritativo. A janela extra, apesar de ter **geometria B4 integral**, é visual e não oferece edição ou colisão fora das regiões autoritativas.
- **Limitação de borda:** em mundo *pristine* sem efeitos procedurais ou edições, visual e definitiva usam o mesmo campo-base B4 e a mesma topologia. Onde há edições ou efeitos aplicados apenas à malha autoritativa, a continuidade ainda não está garantida; é necessário compartilhar os snapshots autoritativos para resolver totalmente.

## Teste Windows (worktree isolada)

```powershell
git -C C:\Dev\sandbox-sim-dev fetch origin exp/dm4-b4-uniform-high-region-stream
git -C C:\Dev\sandbox-sim-dev worktree add --detach C:\Dev\sandbox-dm4-b4 origin/exp/dm4-b4-uniform-high-region-stream
cd C:\Dev\sandbox-dm4-b4
$godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
$oldAppData = $env:APPDATA
$env:APPDATA = "$env:TEMP\sandbox-dm4-saves"
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$env:SANDBOX_TERRAIN_BACKEND = "b4"
$env:SANDBOX_STREAM_PROFILE = "adaptive-skip-progressive"
$env:SANDBOX_PERF_TRACE = "1"
& $godot --headless --editor --path .\game --import
& $godot --windowed --rendering-method gl_compatibility --path .\game
$env:APPDATA = $oldAppData
```

Verificar no console `DM4_REGION_STREAM`, `dm4_region_b4_high_visible` e `dm4_region_b4_high_window`. O último identifica número de malhas HIGH visíveis, jobs pendentes e contadores da fila. A percepção de eventuais junções entre regiões deve ser validada em sessão gráfica com F10 e câmera parada após o preenchimento completo.

## Validação

Workflow `DM4 B4 uniform HIGH region radius 5 (EXPERIMENT)` executa check-only Godot 4.7.2, política da fila, paridade exata (vertices e normais) da malha externa com o oracle B4 DM1 em regiões de sinal positivo e negativo, F10 determinístico com movimentos a 18 e 54 m/s e idle, e captura GPU interativa em Windows.

## Resultado qualificado — Windows / GTX 1050 Ti

**Veredito:** `DM4_UNIFORM_B4_HIGH_RADIUS5_QUALIFIED_FOR_OWNER_VISUAL_TEST`. Workflow [#43280360919](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43280360919): `contract`, `f10`, `gpu`, `full-fill` **PASS** (código `4285ace8a2ad71998d1c0ff6723e9561dc5fedd5`).

- **396 asserções** de política, prioridade, retenção e comparação exata de posições/normais do Surface Nets com o oracle DM1: zero falhas.
- **F10 18 m/s, 54 m/s e idle**, cada um com 480 frames determinísticos: passam e contêm recepções reais do evento `dm4_region_b4_high_visible`.
- **GPU Windows interativa**: renderização e screenshot aprovados na GTX 1050 Ti.
- **Teste prolongado parado:** 9.000 frames em 150,34 s de tempo real; o recebimento `DM4_HIGH_RADIUS_COMPLETE` foi emitido **uma única vez** aproximadamente **41,72 s após início de trace**. Regiões centrais autoritativas = **9**; regiões externas HIGH B4 publicadas = **112**; total visual HIGH = **121/121**; amostragem 0,5 m; nenhuma região externa LOW.
- Desempenho ao longo dos 9.000 frames: **16,718 ms** de frame médio; **2,208 ms** de processamento médio; **0,444%** dos frames acima de 20 ms; **0,133%** acima de 33 ms. Esses valores são do benchmark headless, não FPS gráfico real, e não devem ser usados como aprovação de GPU em 121 regiões.

Evidências: [contrato e import](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43280360919/artifacts/13972461886), [F10](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43280360919/artifacts/13972397290), [GPU/screenshot](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43280360919/artifacts/13972033622), [9.000 frames e confirmação 121/121](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43280360919/artifacts/13972168412).

**Limite de aceitação:** a continuidade visual B4-base está comprovada por paridade geométrica, mas não há veredito para costuras após edição, efeitos de objetos, reflexos e carga gráfica do conjunto 121 regiões. O F10 a 54 m/s ainda pode ficar sem regiões autoritativas publicadas. Sem merge na `main`.
