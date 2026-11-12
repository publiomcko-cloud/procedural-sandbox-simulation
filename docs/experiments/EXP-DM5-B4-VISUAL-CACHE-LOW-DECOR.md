# DM5 — B4 HIGH 5 regiões + cache real + decoração LOW

**Branch isolada:** `exp/dm5-b4-retained-visual-decor` (descendente de DM4). Sem merge na `main`.

## Causa do reload LOW e correção

O fluxo DM4 descartava a malha B4 HIGH de uma região retida quando o primeiro chunk provisório era publicado no retorno. Como o commit autoritativo exige 16 chunks, um preview E7 LOW podia substituir temporariamente uma região que já estava carregada na memória.

Agora o mesh HIGH em GPU de cada `_dm3_shell_nodes` ou `_dm3_retired_region_nodes` permanece visível enquanto a região é novamente carregada. Os chunks provisórios B4 são publicados em nós invisíveis sob a visualização HIGH já retida. Somente o commit atômico da região inteira remove o HIGH retido. O trabalho de preview LOW é suprimido para qualquer região com HIGH válido em memória. O chunk de template de cena (região 0,0) é clonado ao se aposentar, preservando também essa geometria. A retenção se mantém dentro de **10 regiões**, ou **20 segundos depois da saída do raio**, sujeita aos limites de cache visual (512 regiões externas e 48 definitivas aposentadas).

Esse cache é de recursos de renderização; não concede autoridade ou reutilização de state/simulation/projection.

## Rochas e água LOW externas

Uma tarefa independente em worker chamada `b4_low_detail_decor_job.gd` calcula:
- **Rochas:** instâncias nas mesmas posições da população mod-first gerada por `ProceduralObjectWorld.build_region_instances` usando o `ContentDefinitionRegistry` já instalado. Geometria proxy barata com MultiMesh/SphereMesh de baixa contagem de segmentos; usa extents, escala e rotação correspondentes às receitas. Não instancia o estado lógico de objetos, colisões ou modificações de comando.
- **Água:** malhas transparentes LOW com clipping ao perfil do SDF superior; oceano fixo no nível oficial 4.000 mm e região de origem oficial, e rio determinístico de meandro, largura ambiental de 2m e deslocamento do nível de 250mm. Usa cores e estilo próximos aos materiais originais, mas nenhum reservatório ou fonte de volume autoritativa é criado.
- **Transição:** elementos LOW persistem com o visual HIGH no cache e desaparecem ao acontecer o commit definitivo da região, cedendo espaço à renderização de objetos e água originais; recursos já invisíveis são liberados.

**Limitação:** corpos d'água finitos dinâmicos, rochas modificadas/removidas, efeitos SDF de objetos e outros estados mutáveis não podem ser reproduzidos com exatidão fora da janela autoritativa. A cobertura externa é de apresentação e pode diferir perto de fronteiras e em saves editados. O perfil `baseline` e o backend `sdf` não mudam.

## Teste local independente, Windows

```powershell
git -C C:\Dev\sandbox-sim-dev fetch origin exp/dm5-b4-retained-visual-decor
git -C C:\Dev\sandbox-sim-dev worktree add --detach C:\Dev\sandbox-dm5-b4 origin/exp/dm5-b4-retained-visual-decor
cd C:\Dev\sandbox-dm5-b4

$godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
$oldAppData = $env:APPDATA
$env:APPDATA = "$env:TEMP\sandbox-dm5-independent-saves"
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$env:SANDBOX_TERRAIN_BACKEND = "b4"
$env:SANDBOX_STREAM_PROFILE = "adaptive-skip-progressive"
$env:SANDBOX_PERF_TRACE = "1"
& $godot --headless --editor --path .\game --import
& $godot --windowed --rendering-method gl_compatibility --path .\game
$env:APPDATA = $oldAppData
```

F10: avançar, parar para carregar HIGH, afastar e retornar. Observar mesmo terreno sem troca por LOW, a presença de rochas e água ao fundo e o retorno das instâncias autoritativas ao chegar perto.

## Qualificação

[GitHub Actions #43285992853](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43285992853), código testado `4eb936b75c3472ac1879af4e31ef524cdc276537`, **5/5 jobs PASS**:

| Etapa | Evidência |
|---|---|
| Contract | 396 asserções DM4 de malha B4 HIGH + 35 asserções DM5 água/cache, sem falhas |
| F10 frio | rotas outback 18, 54 m/s e idle de 720 frames, **64 publicações DM5 LOW** |
| GUI real | captura gráfica no Windows em GTX 1050 Ti, eventos reais de B4 HIGH e decoração LOW |
| Full-fill | **121/121** regiões HIGH em 9.000 frames, com **112 publicações LOW de rochas** e **90 de oceano**; frame médio **16,766 ms** e process médio **2,404 ms**, headless |
| Warm-return | pré-carregamento de **3.600 frames parado**, então ida e volta de **720 frames** a 18 e 54 m/s no mesmo processo: **32 + 33 = 65** eventos `dm5_retained_high_revisit`, todos `superseded_by_low=false` |

Artifacts: [contract](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43285992853/artifacts/13975490508), [F10](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43285992853/artifacts/13976220034), [GPU](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43285992853/artifacts/13976155115), [full-fill](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43285992853/artifacts/13976350393), [warm-return](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43285992853/artifacts/13974938458).

**Veredito:** `DM5_VISUAL_CACHE_AND_DECOR_WINDOWS_QUALIFIED`. Ainda depende de inspeção local de costuras, memória GPU e qualidade de visualização. Sem merge para `main`.
