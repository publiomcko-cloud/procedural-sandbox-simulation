# DM6 — Raio visual HIGH 6, retenção HIGH 10 + 20 s e custo de memória

**Branch isolada:** `exp/dm6-b4-high-radius6-retention-memory` (derivada de DM5; `main` não alterada).

## Comportamento e causa raiz

- O raio visual HIGH B4 passa de **5 para 6 regiões**: grade 13 × 13, **169 posições**, com **160 regiões exteriores** além do núcleo autoritativo de nove.
- A prioridade permanece **menor distância Chebyshev em regiões, e depois alinhamento frontal à câmera**. Todas as malhas de terreno externas são B4 Q8.8 Surface Nets a 0,5 m. Não há transição automática para LOW ao cruzar raio 6.
- As regiões HIGH já residentes, inclusive as que atravessaram o raio 6, permanecem renderizadas no cache. Um eventual recarregamento autoritativo usa os meshes HIGH retidos até a publicação definitiva, sem sobreposição E7 LOW.
- **Evicção normal somente quando a região estiver fora do raio 10 E houverem transcorrido 20 s desde sua última passagem dentro dele**. Os limites DM5 de 48 regiões definitivas aposentadas e 512 shells externas causavam evicções antecipadas, responsáveis pelo reaparecimento de previews LOW nas revisitas. Agora são somente limites de **aviso**, sem expulsão por contagem; o consumo cresce conforme o trajeto recente. Reinicialização/mudança de mundo, invalidação por edição e conteúdo diferente continuam exigindo invalidação legítima.
- A função de poda reafirma a visibilidade HIGH fora do raio de geração e emite contadores de retenção, reparos, evicções expiradas e tamanho da cache.
- Proxies **LOW apenas para rochas e água** acompanham HIGH retido inclusive quando a região ultrapassa raio 6. São derivados de regras da população mod-first e hidrologia do mundo; não autorizam objetos simulados, edições, colisões, save nem água finita dinâmica fora da janela autoritativa.

## Medição de memória por região — Godot 4.7.2 / Windows

Resultado do teste `game/tests/experiments/dm6_region_memory_benchmark.gd`, seed 424242, oito regiões de coordenadas negativas, interiores e oceânicas. Memória **bruta dos arrays** calculada a partir dos PackedVector3Array (12 B/elemento), PackedColorArray (16 B/elemento) e matrizes MultiMesh 3D (48 B/transformação); não representa a RAM total do processo, cópias internas da ArrayMesh, overhead dos Nodes, VRAM ou estados autoritativos.

| Componente | Custo por região |
|---|---:|
| HIGH B4 — mediana de 8 regiões | **258.768 B = 252,7 KiB** |
| HIGH B4 — mínimo/máximo medidos | 250.128–321.696 B = 244,3–314,2 KiB |
| LOW E7 — preview de 96 triângulos | **6.912 B = 6,75 KiB** |
| Rochas LOW — até 64 instâncias, buffers de transformação | até 3.072 B = 3 KiB + geometria compartilhada |
| Água LOW oceânica — exemplo com 318 triângulos | 26.712 B = 26,1 KiB |
| Campo Q8.8 HIGH durante a geração | **339.764 B = 331,8 KiB temporários** |

O campo HIGH é criado para meshing e descartado após a conclusão do job. A malha HIGH retida consome os buffers geométricos, não todo o campo SDF do worker. A contagem exata de vértices HIGH varia com a região e com a densidade geométrica/edições. Rochas renderizadas via MultiMesh compartilham uma única SphereMesh, mas cada região mantém nós, buffers e metadados próprios.

**Projeções de payload HIGH (mediana):** 169 regiões × 258.768 B = **43.731.792 B (41,7 MiB)**; 441 regiões (quadrado do raio 10) = **114.116.688 B (108,8 MiB)**. A expansão de 121 para 169 regiões adiciona 48 × 258.768 B = **~11,8 MiB de arrays HIGH**, fora overhead. O período adicional de 20 segundos permite reter ainda mais regiões fora do quadrado de 441 posições; portanto, cache não tem limite estrito de RAM nesta experiência. A carga GPU/VRAM deve ser medida separadamente em cenário estável.

**Comparação LOW:** preview de terreno de 6,75 KiB + até 3 KiB de transformações de rochas = ~9,75 KiB sem água, ou ~35,8 KiB com oceano típico de 318 triângulos. A topologia do terreno HIGH puro custa aproximadamente 37,4× a do preview LOW; no DM6 a malha de terreno visível **nunca é rebaixada para LOW para economizar RAM**.

## Qualificação de execução — 12/11/2026

Workflow completo [DM6 #43291315495](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43291315495), commit de código `73e47553d19faf9d15882fea629da6fe770a9a34`: **5/5 jobs PASS**.

- **Contract:** 540 asserções de B4 HIGH, 575 asserções do raio/TTL, 35 do conteúdo LOW e oito regiões de memória (nenhuma falha).
- **F10 frio:** percursos outback 18 e 54 m/s + idle, 720 frames cada, qualificados. A cobertura visual/autoridade F10 a alta velocidade ainda é um gargalo independente.
- **GPU interativa GTX 1050 Ti:** sessão Windows real qualificada e screenshot.
- **Full-fill de 9.000 frames idle:** **169/169** regiões HIGH (160 externas), com 160 eventos de LOW rochas e 121 eventos LOW oceano. Frame médio headless 16,711 ms; processamento médio headless 2,387 ms; 0,333% acima de 20 ms. Não extrapolar estes números para GPU com todas as 169 regiões.
- **Retorno aquecido:** pré-carregamento de 4.800 frames por percurso, seguido de outback F10 a 18 e 54 m/s (720 frames); **35 + 39 = 74 reutilizações HIGH confirmadas**. Pico de regiões HIGH visíveis fora do raio 6: **91** e **178**, respectivamente. **Zero** eventos de expiração antecipada e **zero** reparos de visibilidade, preservando o cache em HIGH.

Evidências: [contrato e memória](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43291315495/artifacts/13977291705), [F10 frio](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43291315495/artifacts/13976439210), [GPU](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43291315495/artifacts/13976713895), [full-fill](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43291315495/artifacts/13978375517) e [ida e volta aquecida](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43291315495/artifacts/13978326122).

### Limitações e decisões seguintes

O foco real da simulação/edições permanece na janela autoritativa original. O custo extra é de renderização e processamento de malhas; a retenção sem expulsão por capacidade exige monitoramento de **RSS e VRAM em trajetos extensos**, além de resolução de edições/rochas/água fora da janela autoritativa. No percurso frio de 18 m/s o percentual de foco visual ausente foi 7,917%, versus 0,417% no DM5 de referência; ambas são execuções isoladas, não pares estatísticos. Tratar como possível regressão de streaming a ser investigada antes de merge, e não como melhoria global de FPS.

## Testar localmente

```powershell
git -C C:\Dev\sandbox-sim-dev fetch origin exp/dm6-b4-high-radius6-retention-memory
git -C C:\Dev\sandbox-sim-dev worktree add --detach C:\Dev\sandbox-dm6-b4 origin/exp/dm6-b4-high-radius6-retention-memory
cd C:\Dev\sandbox-dm6-b4
$godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
$oldAppData = $env:APPDATA
$env:APPDATA = "$env:TEMP\sandbox-dm6-saves"
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$env:SANDBOX_TERRAIN_BACKEND = "b4"
$env:SANDBOX_STREAM_PROFILE = "adaptive-skip-progressive"
$env:SANDBOX_PERF_TRACE = "1"
& $godot --headless --editor --path .\game --import
& $godot --windowed --rendering-method gl_compatibility --path .\game
$env:APPDATA = $oldAppData
```

Mover com F10 além do raio 6, permanecer dentro do raio 10, retornar; depois sair além do raio 10 e retornar antes/depois de 20 s para observar TTL. A troca de `APPDATA` isola os saves do projeto principal.
