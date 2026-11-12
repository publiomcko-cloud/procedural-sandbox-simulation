# DM8 — cobertura radial por distância real do jogador (terreno, rochas e retenção)

**Estado:** experimento derivado de [DM7](./EXP-DM7-HIGH-ROCKS-RADIUS4.md), isolado na branch `exp/dm8-world-distance-radial-stream`. `main` e conteúdo persistido não foram modificados.

## Motivação e decisão geométrica

Na DM7 a camada de regiões HIGH usava **distância Chebyshev** em coordenadas regionais: um quadrado de 13×13, raio 6 em cada eixo. Na diagonal, a posição visual coberta estava significativamente mais distante do jogador do que ao longo de uma direção reta. A solicitação desta fase é manter **todo** o alcance diagonal previamente alcançado e **estender** as direções retas, com uma regra radial verdadeira em unidades do mundo.

Cada região mede **16 m (X) × 12 m (Z)**, logo uma diagonal regional completa mede **20 m**. Para preservar todas as antigas regiões de canto mesmo com o jogador em qualquer ponto da região central, o raio seguro é:

`raio_m = (raio_quadrado_antigo + 0,5) × sqrt(16² + 12²)`

O `+0,5` corresponde ao deslocamento máximo do jogador do centro de sua região atual em cada coordenada. Sem essa margem, a antiga região de canto poderia sumir ao caminhar dentro da mesma região, contrariando o requisito de preservar as diagonais.

| Camada | DM7 (quadrado Chebyshev) | DM8 (círculo radial) | Cobertura de referência no centro |
|---|---|---|---|
| Terreno HIGH B4 | raio regional 6; 13×13 = 169 | **130 m** horizontais do jogador/foco | **277 regiões totais**, 268 externas |
| Rochas HIGH mod-first | raio regional 4; 9×9 = 81 | **90 m** | **137 regiões totais**, 128 externas |
| Retenção HIGH (terreno e decoração) | raio regional 10; 21×21 = 441 | **210 m + 20 s de graça ao sair** | **725 regiões possíveis na circunferência estacionária**, além do histórico por 20 s |
| Terreno e objeto canônicos | núcleos originais | **Inalterados** | 3×3 regiões centrais de terreno autoritativo |

**Os números são da posição do jogador no centro geométrico de uma região.** Em outra posição, o número exato de centros regionais dentro do círculo pode variar ligeiramente. O raio físico e o requisito de preservar a antiga diagonal permanecem constantes.

**Distância utilizada:** distância euclidiana do **ponto real de foco do jogador no plano horizontal XZ** até o **centro de cada região em coordenadas do mundo**. No modo F10, esse foco coincide com a câmera; no modo orbital, é o `orbit_target`, de forma que zoom/órbita não move indevidamente o raio. A coordenada Y é intencionalmente ignorada porque a indexação regional de terreno é X/Z e voar verticalmente não deve descarregar a superfície sob o jogador. É uma esfera de influência horizontal projetada em XZ, não um volume 3D cortado por altitude.

O raio de referência exige testar centros de regiões reais em metros, não distância euclidiana de índices de regiões, pois uma coluna X possui 16 m e uma linha Z possui 12 m.

## Alterações de implementação

- `game/scripts/experiments/b4_region_stream_policy.gd`: funções puras de `radial_radius_m`, `center_world`, `world_distance_squared`, `world_distance_m`, `within_high`, `within_rock_high`, `within_retention` e `keep_radial`; geração da fila de visual exterior por disco, usando janela retangular apenas como limite barato da busca. Distância real é a prioridade primária, alinhamento com a visão é desempate e coordenadas fornecem ordem estável.
- `game/scripts/terrain/terrain_demo.gd`: todos os gates de publicação B4 externa, saída de worker, fila de HIGH de rochas, expiração e visibilidade dos caches agora usam raio **em metros a partir de `orbit_target`**. As malhas antes geradas mantêm a resolução HIGH enquanto protegidas pelo cache — não são rebaixadas por transição de distância. A publicação de chunks autoritativos e objetos originais continua separada.
- `DM8_HIGH_RADIAL_COMPLETE` e `DM8_ROCK_HIGH_RADIAL_COMPLETE`: comprovantes exatos de preenchimento da lista atual, com raio físico, posição, contagem externa/canônica, em vez de pressupor sempre 169 ou 81 regiões. Os recibos são associados a uma assinatura do conjunto de centros regionais para detectar alterações do disco quando o jogador se move **sem mudar o índice de região**.
- A hierarquia HIGH B4 0,5m, rochas exatas pristine no raio de HIGH, rochas LOW além e água LOW permanecem como na DM7. A autoridade, colisão, edição, saves, mod-first e os limites de fontes de efeitos **não são ampliados**.
- **Sem implementação de prefetch de chunks canônicos, GPU compute ou nova política de jobs** nesta fase: a intenção é qualificar a geometria radial primeiro, medindo a pressão adicional antes de reduzir latências.

## Instrumentação para reduzir lacunas de carregamento

Evento novo de trace: `dm8_radial_gap_sample`, amostrado a cada varredura de regiões (nominalmente 200 ms). Contém:

- Quantidade de regiões exteriores de terreno HIGH exigidas, prontas e faltantes; distância da lacuna visual mais próxima, lacunas no cone frontal (`dot > 0,5`).
- P95 de idade do gap (ms desde a primeira observação de ausência), novas demandas desde a última amostragem.
- Regiões de rochas HIGH exigidas/prontas/faltantes, sem contar estado de água LOW como objeto HIGH.
- Jobs em andamento/pending de terreno HIGH, rochas HIGH, decoração LOW; carga de regiões autoritativas pendentes e workers de malha.
- A telemetria `dm4_region_b4_high_window` incorpora contagem de alvos atuais, raios 130/90/210 m, posição XZ, média e pico de tempo de varredura, além dos contadores históricos de retenção TTL.

Esses dados permitem separar **ausência por fila pendente**, **latência da geração B4**, **preparação de rochas** e **tempo de publicação visual**, sem atribuir automaticamente todas as falhas à GPU. O evento requer `SANDBOX_PERF_TRACE=1`.

## Regressões e contratos

- `game/tests/experiments/dm8_radial_world_distance_tests.gd`: compara grid físico 16×12m, raios físicos, 277/137 posições, mostra extensão frontal X/Z, percorre **todos os centros do quadrado antigo** para cinco posições reais diferentes do jogador (incluindo quase nas quinas da região central) e prova que nenhum diagonal antes visível perde cobertura; verifica mudança de cobertura dentro da mesma região e TTL de 20 s.
- Atualizadas as assertions das suites originais DM3/DM6 para aceitar janela radial sem modificar comparação geométrica B4 ou contrato de TTL histórico.
- `.github/workflows/dm8-world-distance-radial-stream.yml` valida import/check-only, contratos, trajeto normal determinístico **18 m/s** e idle (sem F10 54 m/s como meta), GPU real Windows, preenchimento HIGH 277/137 em idle prolongado e revisita aquecida normal com prova de retenção; artifacts incluem logs e métricas para diagnóstico.

## Memória e custo esperado

DM6 mediu mediana **258.768 B** de payload bruto da malha de terreno HIGH por região (vértices + normais, não RSS/VRAM totais). Assim, a expansão de 169 para 277 posições aumenta nominalmente o conjunto de payload geométrico de **~41,7 MiB para ~68,4 MiB**, um delta **~26,7 MiB**. DM7 mediu mediana **79.488 B** por batch externo de rochas HIGH; a expansão de 72 para 128 externos corresponde a **56 batches HIGH a mais** e adicionaria **~4,25 MiB** de payload se a distribuição de rochas for semelhante. Essas são **projeções**, não nova medição de consumo total, GPU ou peak CPU.

Retenção radial de 210 m contém aproximadamente 725 centros na referência central; a região histórica percorrida nos últimos 20 s pode elevar esse número ainda mais. Não existe limite rígido que sobrescreva a promessa de retenção; avaliar RSS e VRAM em percursos longos antes de integrar.

## Próxima fase recomendada (não implementada aqui)

**DM9: reduzir lacunas no movimento normal de 18 m/s com prefetch canônico revision-gated.** Primeiro, medir p50/p95 dos tempos reais por etapa: enfileiramento, geração SDF/efeitos, 16 chunks B4, upload de ArrayMesh, publicação de objetos e prontidão para movimento. Cruzar com `dm8_radial_gap_sample` e `dm4_region_b4_high_window` para identificar a etapa limitante.

Implementar prefetch em janela direcional em **metros = velocidade real × p95 de latência + margem de segurança**, priorizar o foco/colisão, preparar snapshots/meshes em background com validação de revisão antes da publicação, evitar efeitos/edições no worker, cancelar trabalho obsoleto, controlar in-flight e orçamento por quadro. Validação A/B determinística no runner a 18 m/s, comparando percentual de gaps, p95/p99 de frame time, latência de região, tempo de CPU, RSS/VRAM e ausência de regressão de edições/revisitas. **Não otimizar F10 acelerado 54 m/s**; não ampliar estados autoritativos sem rever os limites de projeção.

## Teste local (worktree e APPDATA isolados)

```powershell
$repo = "C:\Dev\sandbox-sim-dev"
$test = "C:\Dev\sandbox-dm8-b4"
$branch = "exp/dm8-world-distance-radial-stream"
$godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
git -C $repo fetch origin $branch
if (-not (Test-Path $test)) {
    git -C $repo worktree add --detach $test "origin/$branch"
} else {
    git -C $test fetch origin $branch
    git -C $test switch --detach "origin/$branch"
}
Set-Location $test
$originalAppData = $env:APPDATA
try {
    $env:APPDATA = "$env:TEMP\sandbox-dm8-isolated-saves"
    New-Item -Force -ItemType Directory $env:APPDATA | Out-Null
    $env:SANDBOX_TERRAIN_BACKEND = "b4"
    $env:SANDBOX_STREAM_PROFILE = "adaptive-skip-progressive"
    $env:SANDBOX_PERF_TRACE = "1"
    & $godot --headless --editor --path .\game --import
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }
    & $godot --windowed --rendering-method gl_compatibility --path .\game
} finally {
    $env:APPDATA = $originalAppData
    Remove-Item Env:SANDBOX_TERRAIN_BACKEND,Env:SANDBOX_STREAM_PROFILE,Env:SANDBOX_PERF_TRACE -ErrorAction SilentlyContinue
}
```

**Critério visual:** deslocar nas direções X, Z e diagonais. A cobertura HIGH deve terminar a aproximadamente 130 m horizontais, não no antigo quadrado de 13×13; rochas HIGH até ~90 m. Os cantos antigos continuam cobertos, os eixos retos ganham cobertura. A origem do raio acompanha o jogador dentro da região, e os HIGH já obtidos continuam visíveis na retenção de 210m + 20s (mesmo após sair do raio de geração). Água/objetos canônicos sem alteração.
