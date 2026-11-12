# DM2 — B4 Surface Nets integrado ao runtime experimental

**Status: QUALIFIED_FOR_LOCAL_VISUAL_EXPERIMENT; NOT FOR MAINLINE MERGE.**
**Branch:** `exp/dm2-b4-runtime-windows`
**Código qualificado:** `784e6a50fede0b6798bfb0edc0070f6d894dc69f`
**CI:** [GitHub Actions #43246755055](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43246755055) — jobs `contract`, `abba` e `gui`: SUCCESS em 2026-11-12.

## Como o caminho B4 funciona

Ativado exclusivamente por `SANDBOX_TERRAIN_BACKEND=b4`. Sem esta variável ou com `sdf`, executa o mesher original.

O `TerrainDemo` prepara o mesmo snapshot de dados autoritativos, incluindo terreno base, ledger de edições e efeito projetado de objetos. Envia o snapshot imutável ao `TerrainMeshJob`. Quando B4 está selecionado, o worker usa `ExperimentalDiscreteSurfaceNets.generate_chunk` para produzir grades Q8.8 locais de 0,5 m, com halo. Em seguida extrai as faces Surface Nets com vértices derivados. O retorno continua no mesmo pipeline de publicação `ArrayMesh` em main thread, com validação de stage/revision e descarte de resultados obsoletos.

O estado de terreno, as edições, a simulação, a hidrologia e o salvamento continuam SDF. A malha B4 é derivada, não autoridade. B4 força LOD0 e desabilita temporariamente o mesher de bordas compartilhadas do backend atual; há risco de inconsistência visual/colisão nos limites e no terreno modificado. Ainda **não** foram comprovados adequação a produção, waterline, seleção de superfície, LOD, normais suaves, material, costura topológica entre chunks/regiões nem gameplay de colisão.

## Reproduzir no Windows sem alterar a cópia principal nem os saves

No PowerShell, com Git instalado:

```powershell
# Preparar uma cópia descartável, separada da main:
git -C C:\Dev\sandbox-sim-dev fetch origin exp/dm2-b4-runtime-windows
git -C C:\Dev\sandbox-sim-dev worktree add --detach C:\Dev\sandbox-dm2-b4 origin/exp/dm2-b4-runtime-windows
Set-Location C:\Dev\sandbox-dm2-b4

$godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$oldAppData = $env:APPDATA
$env:APPDATA = Join-Path $env:TEMP 'sandbox-dm2-b4-saves-isolados'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
$env:SANDBOX_TERRAIN_BACKEND = 'b4'
$env:SANDBOX_STREAM_PROFILE = 'baseline'
$env:SANDBOX_PERF_TRACE = '1'
$env:SANDBOX_PERF_TRACE_MIN_MS = '2.0'
& $godot --headless --editor --path .\game --import
& $godot --windowed --rendering-method gl_compatibility --path .\game

# Após fechar, comparar a mesma cena com o SDF original:
$env:SANDBOX_TERRAIN_BACKEND = 'sdf'
& $godot --windowed --rendering-method gl_compatibility --path .\game

# Opcional: repetir nos dois backends com preview coarse/progressive
# para testar velocidade de streaming F10:
$env:SANDBOX_TERRAIN_BACKEND = 'b4'
$env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
& $godot --windowed --rendering-method gl_compatibility --path .\game

# Restaurar variáveis no mesmo terminal:
$env:APPDATA = $oldAppData
Remove-Item Env:SANDBOX_TERRAIN_BACKEND -ErrorAction SilentlyContinue
Remove-Item Env:SANDBOX_STREAM_PROFILE -ErrorAction SilentlyContinue
Remove-Item Env:SANDBOX_PERF_TRACE -ErrorAction SilentlyContinue
Remove-Item Env:SANDBOX_PERF_TRACE_MIN_MS -ErrorAction SilentlyContinue
```

Evitar abrir simultaneamente instâncias SDF/B4 no **mesmo** diretório isolado de saves. O diretório de `APPDATA` acima só se destina ao teste. Não pressione P (salvar) por engano; os saves de produção já estão isolados, mas a compatibilidade do novo mesher com a jogabilidade ainda não foi qualificada.

No jogo: pressione **F10** para movimentação livre; teste a navegação, observe as bordas de chunks, aproximação da água, cavernas e edição com mouse. **C** alterna o corte de caverna. **L** alterna LOD no backend original; B4 mantém o LOD0 por segurança. Se houver discrepância, compare a mesma posição com o backend `sdf` e capture a tela, junto com o console de log.

## Evidência reproduzível

- **Contrato:** `game/tests/experiments/dm2_b4_chunk_contract.gd`; comparação de posições de vértices por chunk contra o B4 de região inteira, antes/depois de uma edição e com coordenadas negativas. Qualificação de geometria local, **não** prova ausência de cracks ou manifold entre regiões.
- **ABBA full runtime:** `scripts/perf/run-dm2-b4-abba.ps1`; 480 frames F10 cada em SDF/B4/B4/SDF, mesmos runner/seed/rota, APPDATA temporário. Teste qualificado com [run #43243860098](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43243860098) e novamente no run final.
- **GPU Windows real:** `scripts/perf/run-dm2-b4-gui-ab.ps1`, NVIDIA GeForce GTX 1050 Ti: 2 rotas gráficas com 300 frames + idle baseline de 900 frames com 9 regiões carregadas por backend; seis capturas totais. Os screenshots idle são diferentes. Comparação de imagens é evidência visual preliminar, sem inspeção humana conclusiva de cracks ou artefatos.

## Resultado e decisão

Na primeira campanha ABBA, a mediana de carregamento de regiões caiu de ~2053 ms para ~1692 ms (~17,6% de redução) na média de duas execuções cada; média de quadros sem ganho consistente; as lacunas percebidas já eram mitigadas pelo preview coarse. Não interpretar como melhoria de FPS nem solução completa para os custos de projeção de objetos. B4 está **disponível para teste visual manual**, não aprovado para substituir o pipeline atual.

Próximo trabalho: garantir costura de região/chunk, normais suaves e compatibilidade de colisão/brush com o campo SDF; depois repetir A/B com métricas por estágio e igual carga de GPU.
