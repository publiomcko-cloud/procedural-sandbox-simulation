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
