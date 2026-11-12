# DM3 — B4 adaptive-skip-progressive, região 5/4/10

**Branch experimental:** `exp/dm3-b4-region-radius5`, derivada da DM2 B4; `main` não é alterada.

## Correção de unidade

Os limites abaixo são **regiões**, não chunks. Cada região mantém 4 × 4 chunks (16 m × 12 m), e a distância radial é Chebyshev em coordenadas de regiões.

- **Raio visual 5 regiões** (11 × 11 = 121 posições, incluindo o centro). A geração incremental das regiões exteriores não bloqueia carregamento próximo.
- **Até raio 4:** camada HIGH *visual*, top surface base com amostragem horizontal de 1 m, 16 × 12 quads por região. Se for uma região já carregada pelo runtime central, mantém o B4 completo 0,5 m e a geometria original.
- **Anel 5:** camada LOW, top surface base com amostragem de 2 m, 8 × 6 quads. Quando uma região passa de 5 para 4, publica HIGH assim que a tarefa termina, sem remover LOW até a substituição.
- **Prioridade:** regiões diretamente no campo à frente (dot >= 0,75) passam à frente das laterais/traseiras, com região central sempre urgente. O seletor de jobs definitivos aplica a mesma preferência somente a estágios `load`, sem tirar prioridade de edição ou rebuild.
- **Retenção:** visual anteriormente carregado permanece dentro do raio 10 ou por até 20 s após sair dele. Limite explícito de 512 shells e 48 regiões detalhadas aposentadas, com despejo do registro mais antigo/distante se a capacidade for atingida.
- **Autoridade:** a janela central de terreno, objeto, simulação e efeitos mantém seus raios atuais; a nova camada de 11 × 11 é **somente visual**. A janela autoritativa não é expandida porque o serviço de efeitos tem 81 source scopes máximos e uma expansão ingênua para 121 regiões ultrapassaria o limite.

## Escopo de validade

As regiões exteriores não são chunks B4 editáveis nem uma expansão da simulação: são malhas derivadas de altura, sem cavernas, brush salvo, formas de objetos, colisão ou hidrologia autoritativa. Sua geometria pode diferir da definitiva ao se aproximar. Transições HIGH/LOW podem mostrar pequenos desníveis/seams. Tudo isso é intencionalmente experimental; não confundir `dm3_region_shell_visible` com a publicação de um `terrain_region_load_complete`.

Os dados de mundo persistidos e o comportamento padrão `sdf` não são modificados. A cache de malhas definitivas aposentadas só é visual e perde as referências de autoridade, é limpa quando o mundo muda e não concede objeto/simulação.

## Executar no Windows

Execute a partir de PowerShell com o projeto principal em `C:\Dev\sandbox-sim-dev`, usando uma worktree independente:

```powershell
git -C C:\Dev\sandbox-sim-dev fetch origin exp/dm3-b4-region-radius5
git -C C:\Dev\sandbox-sim-dev worktree add --detach C:\Dev\sandbox-dm3-b4 origin/exp/dm3-b4-region-radius5
cd C:\Dev\sandbox-dm3-b4
$godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
$oldAppData = $env:APPDATA
$env:APPDATA = "$env:TEMP\sandbox-dm3-region-saves"
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$env:SANDBOX_TERRAIN_BACKEND = "b4"
$env:SANDBOX_STREAM_PROFILE = "adaptive-skip-progressive"
$env:SANDBOX_PERF_TRACE = "1"
$env:SANDBOX_PERF_TRACE_MIN_MS = "2.0"
& $godot --headless --editor --path .\game --import
& $godot --windowed --rendering-method gl_compatibility --path .\game
$env:APPDATA = $oldAppData
```

Usar F10 para movimento e observar especialmente o anel 5/4, prioridade à frente, retenção ao retroceder, lacunas e microseams. O log `DM3_REGION_STREAM` deve aparecer no startup com B4+adaptive-skip-progressive. Os eventos `dm3_region_shell_window` e `dm3_region_shell_visible` permitem medir quantidade visível, LOW/HIGH, worker, cache e evicções.

## Evidências / testes

`game/tests/experiments/dm3_region_stream_policy_tests.gd` valida o conjunto 112 das regiões extras, LOW apenas no anel 5, prioridade à frente, retenção por raio/tempo e custo de topologia de dois níveis. CI executa import/check-only, esse teste, F10 determinístico em 18 e 54 m/s com perfil B4, e GUI Windows/OpenGL interativa. As evidências ficam em Actions no workflow `DM3 B4 region radius 5`.
