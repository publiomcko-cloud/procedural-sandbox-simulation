# Master de arquitetura e descobertas — experimento DM1–DM7 (Godot Sandbox)

**Escopo:** registro consolidado da linhagem experimental B4, streaming de regiões, retenção HIGH, rochas e água visuais. A branch atual é `exp/dm7-b4-high-rock-radius4`, descendente das experiências DM1→DM6. **A `main` não foi modificada.** As conclusões de uma fase anterior permanecem históricas; regras atuais são as especificadas aqui.

**Estado documental:** resultados DM1–DM6 confirmados por Actions e inspeção local do autor (DM6 aprovado visualmente com ressalva sobre rochas LOW); DM7 requer seu próprio resultado de qualificação no Actions e validação visual local. Nenhuma equivalência de conteúdo mutável fora da janela autoritativa foi demonstrada.

## 1. Problema e premissas

O gerador original utiliza SDF com malhas por chunk, dados de brushes/edições, objetos procedural/mod-first, interação de objetos com SDF, simulação hidrológica e persistência. O custo de geração de regiões e a necessidade de um visual contínuo durante o movimento motivaram um backend B4 experimental e uma camada de regiões derivadas. **O objetivo não é estender automaticamente o estado lógico de gameplay ao mundo inteiro**: a camada ampla é somente renderização.

O autor verificou na DM6 um processo com **menos de 300 MB de RAM** e variação pequena de VRAM na sessão local. É uma **observação informal**, não uma medição padronizada de pico RSS/VRAM. A demanda atual é antecipar a malha HIGH das rochas até o raio 4, sem alterar prefetch de terrain/chunks nesta etapa. Movimento F10 **normal = 18 m/s**, acelerado = 54 m/s; o segundo deixou de ser critério de produto.

## 2. Pipeline atual — o que está e não está em HIGH

| Componente | Cobertura no foco atual | Geometria | Estado/autoridade |
|---|---|---|---|
| Terreno central | 3×3 regiões (raio 1) | 16 chunks por região, B4 0,5 m | Estado SDF original, brushes, geração/colisão, objetos e simulação no runtime existente |
| Terreno exterior | Raios 2–6 inclusive; grade HIGH de 13×13 = **169 posições totais** | B4 Q8.8 Surface Nets, malha única derivada de 16 chunks | Apenas visual, gerado do campo pristine; sem editabilidade/colisão/simulação |
| Rochas centrais | Região publicada no `ProceduralObjectStream` | Rocha geológica real + aparência/estado da instância | Autoridade original; pode ter modificações persistentes |
| Rochas HIGH exteriores **DM7** | Raios 2–4; grade 9×9 = **81 posições totais, 72 exteriores** | **Mesma receita geológica, mesmas posições, escala, rotação e triangulação pristine** do renderer canônico, agrupadas em ArrayMesh regional | Apenas visual; sem comandos, alterações persistentes ou lógica |
| Rochas LOW exteriores | Regiões ainda não promovidas a HIGH e as de raio 5–6 e outras retidas | Proxy `SphereMesh` de baixa resolução compartilhado, `MultiMesh` por região | Apenas visual, regras e identidade mod-first |
| Água exterior | Regiões derivadas com disponibilidade de malha | LOW: costa/nível de oceano estático e rio procedurais, recortados pelo SDF superior | Não inclui reservatórios finitos dinâmicos ou volumes/correntes |
| HIGH mantido no cache | Todas as regiões HIGH já construídas e ainda elegíveis | **Mantém a resolução adquirida; não faz downgrade HIGH→LOW** ao sair dos raios de geração | Descarregar apenas fora do raio 10 **e** 20 s após a última visita dentro do raio, salvo mudança de mundo/invalidação legítima |

Os raios são Chebyshev de regiões no plano X/Z, **não chunks nem metros**. Cada região mede **16×12 m**, com **4×4 chunks**. A camada visual não aumenta as regiões autoritativas e preserva os limites de fontes de projeção de objetos e efeitos. A retenção do runtime canônico de 5×5 e o horizonte histórico de 9×9 fontes não foram alterados pelo experimento.

### Sequência operacional real

1. A câmera define o foco regional; estados SDF do núcleo e edição conservam prioridade no scheduler original.
2. Regiões visuais exteriores são selecionadas por **distância menor primeiro**, depois alinhamento horizontal com a direção da câmera e desempate estável. Worker B4 gera campo Q8.8 em CPU e malha completa, publica no main thread em ordem incremental.
3. Para regiões com B4 HIGH pronto, um worker de decoração resolve o registro mod-first e monta rochas LOW leves e água LOW. Esses dados não instanciam `world_state`, armazenamento, objetos lógicos nem reservatórios.
4. **DM7:** quando um registro de decoração está pronto e a região entra no raio 4, outro worker usa `ProceduralObjectWorld.build_region_instances`, `ProceduralRockMeshAdapter.build_cpu_data` (núcleo `ProceduralRockShapeDescriptor`) e `ProceduralObjectStaticBatch.prepare`. O resultado é geometria real das rochas em um batch regional, sem criação de recursos Godot no worker. O main thread chama `ProceduralObjectStaticBatch.commit` para uma `ArrayMesh`, instala HIGH e **só então oculta `LowRocks`**, deixando `LowWater` intocado.
5. O HIGH das rochas **permanece HIGH** depois de ultrapassar raio 4 enquanto o registro visual estiver no cache. Novas regiões ainda não geradas mostram LOW; falhas do HIGH ficam em LOW com telemetria e cooldown de retry, nunca promovidas parcialmente.
6. Quando o terreno canônico substitui seu visual derivado, as rochas visuais podem permanecer até `object_stream.has_published_region` confirmar a geometria real dos objetos. A camada LOW/HIGH derivada é então descartada, evitando desaparecer rochas apenas porque os 16 chunks do terreno terminaram antes do renderer de objetos.
7. Expiração do cache exterior elimina terreno e decoração vinculada somente por TTL+raio. Água LOW, rochas HIGH e rochas LOW usam o mesmo ciclo de vida do registro visual. Alterações de seed/mundo e invalidações legítimas são exceções à retenção.

**Importante:** o preparo externo não aplica `instance_components` mutáveis e estado persistido de exclusão/movimento/tint, nem efeitos de deformação causados por rochas no SDF. O critério de igualdade geométrica vale apenas para a população **pristine** com o mesmo seed/mod. Não há garantia de costura perfeita em terreno editado, rochas removidas pelo jogador ou água finita alterada.

## 3. Registro histórico das decisões (o que motivou cada fase)

| Fase | Hipótese / implementação | Conclusão e mudança incorporada |
|---|---|---|
| **DM1** | Benchmark isolado de SDF original A versus B1/B2/B3 ocupação+greedy e B4 Q8.8+Surface Nets, incluindo cold/warm/edits | B4 obteve **304,93 ms cold**, **98,47 ms warm**, **403,08 ms em oito edições**, 3.570 triângulos e 339.764 B de estado matricial temporário; escolhido para runtime experimental, não produção |
| **DM2** | Backend alternativo B4 em 16 chunks locais, import/teste, ABBA SDF/B4 e GUI Windows | Paridade por chunk e teste gráfico inicial; autoridade SDF não foi substituída; resultado não prova ausência de cracks ou compatibilidade plena com edições |
| **DM3** | Shell visual de **raio 5**, heightfield HIGH 1 m até raio 4 e LOW 2 m no anel 5; look-forward e retenção 10/20s | Cobertura visual ampliada, mas *seams* HIGH/LOW e diferença topológica da malha real persistiram; em 54 m/s o foco canônico podia continuar ausente |
| **DM4** | Eliminar terreno LOW no halo: todas as **121** posições do raio 5 em B4 verdadeiro de 0,5 m, 112 externas; fila de distância→direção | Paridade pristine de vértices/normais; **121/121 HIGH** preenchidas em idle, aproximadamente 41,72 s até a confirmação do raio; custo de geração ainda relevante |
| **DM5** | Retorno a HIGH piscava após publicar primeiro chunk provisional; manter HIGH durante staging e suprimir preview E7 LOW; incluir rochas e água LOW externas | **65 reutilizações HIGH** com cache aquecido; rochas posicionadas via registro de mods, água LOW de oceano/rios; objetos ainda eram simplificados fora do núcleo |
| **DM6** | Ampliar terreno HIGH de 5 para **6 regiões**; corrigir cache e calcular RAM | Removidas evicções precoces por limites rígidos de 48/512; retenção agora requer fora do raio 10 **e** pelo menos 20 s; **169/169 HIGH**; **74 reutilizações HIGH** em percursos aquecidos; medidos bytes das malhas |
| **DM7** | Resolver `LowRocks`→`HIGH` somente quando próximo do núcleo (raios 1–2), mantendo terreno HIGH a 6. Adotar HIGH de rochas **raio 4** com mesma geometria do mod, job separado, promoção atômica e retenção | Implementação em branch isolada, sem alterações nos raios de terreno/autoridade/água, a qualificar em Windows e visualmente pelo autor |

### Causas raiz documentadas

- **Bordas visíveis DM3:** misturar superfícies de heightfield 1/2 m com B4/SDF completo provocava incompatibilidade real, não apenas baixa densidade de polígonos. DM4 removeu a banda LOW do terreno.
- **Piscada DM4/DM5:** ao iniciar o estágio de chunks canônicos o renderer descartava prematuramente a malha HIGH retida; a publicação provisória oferecia oportunidade ao E7 LOW. DM5 manteve o HIGH até o commit.
- **Evicção prematura DM5:** limites rígidos de 48 meshes definitivas aposentadas/512 shells removiam recursos ainda protegidos por raio/TTL. DM6 converteu os limites em alerta, sem evicção forçada.
- **Rochas low perto da câmera DM6:** o raio visual HIGH do **terreno** não implicava resolução HIGH de **objetos**, cuja malha exata só era publicada no núcleo autoritativo. DM7 separa os raios e introduz HIGH visual de rochas no raio 4.
- **Transição rocha HIGH→canônica:** a publicação dos chunks do terreno e dos objetos é assíncrona; DM7 retarda a liberação do proxy até a publicação efetiva pelo serviço de objetos, sem adicionar autoridade externa.

## 4. Contratos técnicos, testes e arquivos

**Principais scripts:** `game/scripts/experiments/discrete_surface_nets_backend.gd` (B4), `b4_region_visual_job.gd` (mesh HIGH 16 chunks/região), `b4_region_stream_policy.gd` (raios/prioridade/TTL), `b4_low_detail_decor_job.gd` (rochas LOW e água LOW), `b4_high_detail_rock_job.gd` (DM7 geometria geológica HIGH), `game/scripts/terrain/terrain_demo.gd` (streaming/publicação/retention), `game/scripts/objects/procedural_object_world.gd` (população original), `procedural_rock_mesh_adapter.gd` e `procedural_object_static_batch.gd` (geometria/agrupamento originales).

**Testes de regressão:** `game/tests/experiments/discrete_terrain_matrix_benchmark.gd`, `dm2_b4_chunk_contract.gd`, `dm3_region_stream_policy_tests.gd` (agora DM6), `dm5_low_decor_contract.gd`, `dm6_high_retention_policy_tests.gd`, `dm6_region_memory_benchmark.gd`, `dm7_high_rock_parity_tests.gd`. Workflows nas pastas `.github/workflows/dm2-...yml` até `dm7-b4-high-rock-radius4.yml`. `scripts/perf/run-p5-deterministic-stream-benchmark.ps1` suporta `-WarmupFrames` e rotas determinísticas `straight-18`, `outback-18`, `outback-54`, `idle`.

**Prova esperada DM7:** paridade exata dos vértices/normais/identidades do batch HIGH com os dados do mesmo algoritmo canônico, incluindo coordenadas negativas; `LowRocks` escondido **depois** do HIGH estar pronto, `LowWater` preservado; 81 regiões cobertas com HIGH de rochas após idle (72 externas + 9 centrais), 169 regiões HIGH de terreno; GPU real; retorno aquecido com rochas HIGH residentes além do raio 4, mesmo após sua saída.

**Eventos:** `DM6_REGION_STREAM`, `dm4_region_b4_high_visible`, `dm4_region_b4_high_window` (métricas DM6 e DM7), `DM6_HIGH_RADIUS_COMPLETE`, `dm5_low_decor_visible`, `dm5_retained_high_revisit`, `DM7_ROCK_STREAM`, `dm7_rock_high_visible`, `dm7_rock_high_failed`, `DM7_ROCK_HIGH_RADIUS_COMPLETE`. As nomenclaturas DM3/DM4 preservadas são marcas históricas; não devem ser interpretadas como o raio ativo.

## 5. Memória — custos medidos, estimativas e limites

Na DM6 (Godot 4.7.2, seed 424242, oito regiões):
- Terreno B4 HIGH: **258.768 bytes de payload de vértices/normais por região (mediana; 252,7 KiB)**, faixa **250.128–321.696 bytes**.
- Terreno E7 LOW: **6.912 B (6,75 KiB)** por região de 96 triângulos.
- Rochas LOW: até **3.072 B** de transformações por 64 objetos + `SphereMesh` compartilhada e overhead de nós/recursos.
- Água LOW oceânica: exemplo de **26.712 B** com 318 triângulos; água inexistente custa zero payload.
- Campo Q8.8 B4 durante trabalho: **339.764 B** temporários. Não é um cache de campo residente por região.
- Apenas arrays de terreno HIGH em 169 regiões: **43.731.792 B (41,7 MiB)**; 441 (raio 10): **114.116.688 B (108,8 MiB)**; histórico de 20 s fora do raio pode superar isso.
- **DM7 adiciona** arrays de vértices/normais das rochas HIGH (24 B por vértice, quantidade dependente do número de instâncias e da receita, **100–500 triângulos por rocha**), uma `ArrayMesh` por região HIGH externa e memória temporária para preparar os batches. Não somar o payload do worker à RAM persistente sem medição de pico.
- Esses valores não incluem buffers/cópias internas da `ArrayMesh`, indexação de nós, geometria da GPU, overhead do Godot, estado autoritativo ou recursos temporários concorrentes. Monitorar RSS **e** VRAM efetivos antes de dimensionar agressivamente a distância de prefetch.

O user report da DM6 (**RSS sub-300 MB e VRAM pouco alterada**) sugere margem para experimentação, mas é insuficiente para concluir que o gargalo restante não é CPU/latência de publicação.

## 6. Evidências já confirmadas e status

- [DM1 — benchmarks](./EXP-DM1-RESULTS.md) · [DM2 — B4 no runtime](./EXP-DM2-B4-RUNTIME-LOCAL-GUI.md) · [DM3 — shell original](./EXP-DM3-B4-REGION-STREAM.md).
- [DM4 — uniform HIGH](./EXP-DM4-B4-UNIFORM-HIGH-REGIONS.md): [Actions 43280360919](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43280360919) **4/4 jobs PASS**; 121/121 HIGH e paridade pristine.
- [DM5 — retenção e decoração LOW](./EXP-DM5-B4-VISUAL-CACHE-LOW-DECOR.md): [Actions 43285992853](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43285992853) **5/5 jobs PASS**; 65 HIGH reutilizados em retornos.
- [DM6 — raio 6 e memória](./EXP-DM6-B4-HIGH-RETENTION-MEMORY.md): [Actions 43291315495](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43291315495) **5/5 jobs PASS**; 169/169 HIGH, 74 HIGH reutilizados. **Inspeção visual local do autor aprovada**, com ressalva sobre LOW das rochas próximo à câmera.
- **DM7:** documentação de resultado em `EXP-DM7-HIGH-ROCKS-RADIUS4.md` e evidências Actions devem ser consultadas antes de considerar a mudança qualificada. Não houve merge na main.

Os documentos DM3–DM5 preservam **parâmetros históricos** (raio 5, anel LOW, limite 48/512), que foram sucessivamente superados por DM6/DM7. Não devem ser usados como configuração atual.

## 7. Riscos e pendências expressamente não resolvidos

1. **A representação visual não é a autoridade.** Mundos editados, rochas deletadas/transformadas, modding com estado dinâmico e cortes de terreno podem apresentar inconsistências nas camadas derivadas. É preciso revision-gating e materialização por snapshots para paridade completa.
2. **Água exterior é LOW**, não simulação de volumes finitos, reservatórios de jogador ou rios/oceanos completos; apenas apresentação determinística de fontes fixas.
3. **Custo de prefetch:** toda região exterior ainda depende de geração/meshing em CPU; o streaming determinístico F10 acelerado apresenta foco ausente. Não foi implementado prefetch direcional antecipado de chunks/snapshots nesta série.
4. **GPU e RAM a longo prazo:** limite de capacidade da cache foi convertido em alerta para cumprir o TTL, logo crescimento durante deslocamentos longos não tem teto estrito. Testar RSS, VRAM, FPS e pico de worker, sobretudo após múltiplas revisitas.
5. **Escopo de mods:** o HIGH derivado suporta rochas com algoritmo `geological_halfspace_v1`, sem aplicar estado lógico/mutável. Novas classes de objetos precisam de renderizador visual específico.
6. **Paridade topológica entre regiões editadas:** identidade B4 pristine não é prova de continuidade visual em superfície alterada. O modelo retido de região central pode diferir do campo base quando há efeitos/projeções.

## 8. Recomendação técnica para a próxima fase (não implementada)

**Prioridade P1: prefetch orientado à velocidade normal do jogador (18 m/s), sem otimizar F10 rápido 54 m/s.** Instrumentar intervalos de tempo entre chegada ao raio e conclusão da publicação canônica; usar `lookahead_distance = speed * percentile_latency + safety_margin`, com limite explícito de filas/workers e prioridade sempre superior para o raio de ação imediata. Prefetch deve ser sobre **dados, snapshots e preparação de chunks canônicos**, sem conceder autoridade antecipada nem quebrar regras de edição. Testar deterministicamente deslocamento normal, revisitas e paradas contra a DM7, incluindo gastos CPU/GPU/RAM. Cuidar para não ampliar sem planejamento o orçamento de fontes de efeitos de objetos.

**Prioridade P2:** medir custo marginal do HIGH de rochas (worker, commits, vértices, VRAM, FPS) em 81 regiões, sobretudo com mods adicionais; só então comparar HIGH raio 4 versus 5/6.

**Prioridade P3:** estudar snapshots por revisão para os visuais exteriores de terreno, objetos editados e água finita. Não migrar autoridade nem persistência neste experimento.

**Gate antes da integração:** testes E2E reais no Windows, inspeção visual no computador do autor, benchmark normal reproduzível e orçamento explícito de CPU/RAM/VRAM; somente então planejar integração gradual em `main`.

## 9. Teste isolado no Windows

```powershell
$repo = "C:\Dev\sandbox-sim-dev"
$test = "C:\Dev\sandbox-dm7-b4"
$branch = "exp/dm7-b4-high-rock-radius4"
$godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
git -C $repo fetch origin $branch
if (-not (Test-Path $test)) {
  git -C $repo worktree add --detach $test "origin/$branch"
} else {
  git -C $test fetch origin $branch
  git -C $test switch --detach "origin/$branch"
}
Set-Location $test
$priorAppData = $env:APPDATA
try {
  $env:APPDATA = "$env:TEMP\sandbox-dm7-isolated-saves"
  New-Item -Force -ItemType Directory $env:APPDATA | Out-Null
  $env:SANDBOX_TERRAIN_BACKEND = "b4"
  $env:SANDBOX_STREAM_PROFILE = "adaptive-skip-progressive"
  $env:SANDBOX_PERF_TRACE = "1"
  & $godot --headless --editor --path .\game --import
  if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }
  & $godot --windowed --rendering-method gl_compatibility --path .\game
} finally {
  $env:APPDATA = $priorAppData
  Remove-Item Env:SANDBOX_TERRAIN_BACKEND,Env:SANDBOX_STREAM_PROFILE,Env:SANDBOX_PERF_TRACE -ErrorAction SilentlyContinue
}
```

Critério visual: terreno HIGH até 6; rochas geológicas HIGH já visíveis no raio 4 e retidas quando passam para além de 4; LOW apenas nos objetos ainda não gerados e no anel externo; LOW water permanece; nenhuma piscada na troca LOW→HIGH ou HIGH→canônico, e ausência de alterações no gameplay/edições do núcleo.
