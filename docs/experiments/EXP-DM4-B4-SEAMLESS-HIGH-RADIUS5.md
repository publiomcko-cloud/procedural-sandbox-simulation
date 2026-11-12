# DM4 — B4 high em todo raio de 5 regiões; emendas e prioridade

**Branch:** `exp/dm4-b4-seamless-high-radius5` (derivada da DM3). Não integrar em `main` sem validação visual no PC.

## Diagnóstico da borda

DM3 construiu as regiões externas por um **heightfield 2,0 m (LOW) ou 1,0 m (HIGH)**, com triangulação própria. A região definitiva usa **B4 Q8.8 Surface Nets em 0,5 m**, inclusive terreno volumétrico e cavernas. Não há garantia de a superfície do heightfield coincidir com a malha Surface Nets no limite de regiões, mesmo quando HIGH.

## Mudança

- **Todas as 112 regiões adicionais** no raio Chebyshev 5 (além das 9 centrais) usam exclusivamente `ExperimentalDiscreteSurfaceNets.generate(seed, region, 0.5)` e `build_chunk()` para cada um dos 16 chunks. O resultado é concatenado em uma malha por região, preservando os triângulos, vértices e normais originais, sem gerar heightfield LOW. O mesmo Surface Nets é usado no B4 definitivo, com halo de amostras idêntico.
- **Fila:** prioridade absoluta do centro para a janela autoritativa existente. Entre as regiões visuais, anel 2 antes de 3, 3 antes de 4, 4 antes de 5. Dentro de um anel, maior alinhamento do vetor câmera→região com o olhar da câmera primeiro. Ordenação determinística. Enquanto o jogador não se mover, a fila drena até todas as 112 regiões visuais terem malha B4 HIGH.
- **Passagem de controle sem buraco:** se uma região já tem a malha HIGH visual ou chunks carregados da janela anterior, o E7 não publica chunks provisórios por cima dela; conserva o visual anterior até o `_publish_region` atômico completo. O preview heightfield E7 foi desligado apenas na combinação `B4 + adaptive-skip-progressive`.
- **Cache:** após sair da janela autoritativa, as malhas anteriores permanecem visualmente até distância 10 ou 20 s depois de sair do raio, limitadas por 512 registros de região e 48 conjuntos de chunks definitivos aposentados. Não expande efeitos, colisões, entidades ou simulação.
- **Carga:** Surface Nets completo em todas as regiões é mais caro que o heightfield DM3. O processamento ocorre em tarefas CPU com no máximo 2 jobs visuais em voo, uma publicação por frame e veto em frames lentos. A prioridade dos jobs definitivos permanece. Testar em movimento é indispensável; não presumir melhoria automática de FPS.

## Limites

A **janela definitiva continua 3×3 regiões solicitadas / 5×5 retidas**, pois expandir a autoridade para 11×11 ultrapassaria o limite de 81 escopos de efeitos. As outras 112 são **somente visuais** mas geometricamente equivalentes à base B4 pristina. **Edições ou efeitos de objetos existentes** não são reproduzidos pela casca visual derivada, então emendas entre mundos alterados ainda precisam de um caminho revisionado de snapshot e devem ser tratadas como não qualificadas. Hidrologia também é separada.

## Testes de engenharia

- `dm3_region_stream_policy_tests.gd` agora exige HIGH em todos os anéis, 0,5 m, 16 chunks e ordenação proximidade+visão. LOW retorna inválido.
- `dm4_b4_region_seam_contract.gd` compara **vértices e normais da malha visual** com os 16 chunks B4 canônicos (mesmo seed, sem edits) e compara células Surface Nets sobrepostas nas bordas de duas regiões contíguas em X e Z, usando o espaço global.
- `.github/workflows/dm4-b4-seamless-high-radius5.yml` valida compilação Godot 4.7.2, contratos, benchmark F10 determinístico 18 e 54 m/s, e captura de GPU real no runner Windows. O resultado de idle/drenagem também é coletado.

## Teste local Windows, sem alterar o clone principal

```powershell
git -C C:\Dev\sandbox-sim-dev fetch origin exp/dm4-b4-seamless-high-radius5
git -C C:\Dev\sandbox-sim-dev worktree add --detach C:\Dev\sandbox-dm4-b4 origin/exp/dm4-b4-seamless-high-radius5
cd C:\Dev\sandbox-dm4-b4
$godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
$oldAppData = $env:APPDATA
$env:APPDATA = "$env:TEMP\sandbox-dm4-high-visual"
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$env:SANDBOX_TERRAIN_BACKEND = "b4"
$env:SANDBOX_STREAM_PROFILE = "adaptive-skip-progressive"
$env:SANDBOX_PERF_TRACE = "1"
& $godot --headless --editor --path .\game --import
& $godot --windowed --rendering-method gl_compatibility --path .\game
$env:APPDATA = $oldAppData
```

No log conferir `DM4_REGION_STREAM` e o evento `dm4_b4_high_region_visible` (backend=`b4_surface_nets`, sample_step_m=`0.5`). Inspecionar visualmente emendas entre região definitiva e visual, sem edição e após edição separadamente. A fila HIGH completa após permanecer parado o suficiente; não é garantida em F10 a 54 m/s.
