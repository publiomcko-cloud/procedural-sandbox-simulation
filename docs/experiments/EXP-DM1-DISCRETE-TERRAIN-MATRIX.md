# EXP-DM1 — terreno matricial discreto / benchmark isolado

**Estado:** protótipo experimental, não integrar nem substituir o SDF do jogo.
**Ramo:** `exp/discrete-terrain-matrix-benchmark`.
**Base:** ramo experimental P5 E7 (`exp/p5-stream-progressive-chunks-e7`), sem alterar seus sistemas de streaming, mods, objetos, água, colisão ou salvamento.
**Hardware:** mesmo runner físico Windows `sandbox-gpu-interactive` e Godot 4.7.2 para todas as variantes.

## Hipótese testável

Reduzir cálculos de superfície mediante ocupação 3D discreta e uma biblioteca implícita de seis orientações de face, agrupadas por *greedy meshing*. A configuração de cada microcélula é binária (sólido/vazio), com operações de preenchimento/escavação limitadas à célula. A superfície é derivada de máscaras de vizinhança; não há soma de brushes na fase de meshing.

A implementação **não** tenta preservar a topologia contínua nem a suavidade do SDF, e deliberadamente ignora os contratos do backend principal. Isso expõe o máximo potencial de simplificação sem mascarar perdas geométricas.

## Candidatos

1. **A (controle):** `MarchingTetrahedra.build_chunk_cpu_data` real do projeto, resolução de 0,5 m, gradientes nas bordas, amostragem de campo SDF e `SdfBrushEditState` após as edições.
2. **B1:** matriz densa de ocupação com um byte por célula de 0,5 m e halo; faces visíveis agrupadas por retângulos.
3. **B2:** mesma lógica, microcélulas de 0,25 m.
4. **B3:** microcélulas de 0,125 m (divisão de cada metro em 8 partes por eixo = 512 subcélulas/m³).

O backend usa amostras SDF **apenas na primeira materialização** do terreno. Cada alteração posterior modifica o volume discreto localmente. A triangulação consulta exclusivamente a ocupação. Regiões completas de ar ou sólido são processadas sem faces internas. O protótipo é denso para quantificar custo bruto; octree, RLE, bitpacking, meshlets, CPU SIMD e GPU ficam para a próxima rodada, caso valham a pena.

## Trabalho equivalente e limitações explícitas

- Seed `424242`, região `(1,-1)`, os mesmos **16 chunks** de 4 × 10 × 3 m, a mesma sequência fixa de **8 brushes** CSG e as mesmas regiões afetadas.
- **Cold:** novo backend, materialização do campo quando aplicável, extração dos 16 chunks.
- **Warm:** nova extração dos mesmos 16 chunks, reutilizando a matriz discreta.
- **Edits:** atualização da representação e remesh dos mesmos chunks afetados após cada brush, incluindo o custo do ledger no controle SDF.
- Duas repetições de cada variante no mesmo processo, ordem alternada A–B1–B2–B3–B3–B2–B1–A. O workflow executa o processo duas vezes; arquivos de saída incluem evidência bruta.
- Vértices, triângulos, bytes residentes e amostragens qualitativas são registrados. A geometria produzida **não é equivalente**: B é blocada, não compartilha triângulos ou normais com A, e não reconstitui colisões, seam mesh autoritativo, LOD, persistência ou simulação.
- Edições de ocupação equivalem à classificação de sólido/vazio do CSG **nos centros das células**, mas não em posições arbitrárias; os testes exigem divergência zero em 384 centros amostrados e registram a divergência em 384 posições contínuas.
- Erro da superfície: p95 da magnitude do SDF de referência amostrada em vértices da malha blocada. É uma **aproximação de fidelidade**, não uma distância de Hausdorff nem uma métrica de aparência.
- Métricas em milissegundos `cold`, `warm` e `edits` não equivalem a FPS ou latência visual da cena completa. Mesmo que sejam rápidas, o gargalo atual de fontes/projeção de objetos pode permanecer.
- A memória reportada contém **só os bytes brutos de ocupação com halo**, não inclui buffers de mesh, hashes, arrays temporários, engine/GPU ou caches internos.

## Critérios de julgamento

Não aceitar a variante apenas porque ela é mais rápida. Reportar para cada uma: aceleração a frio, aquecido e durante edições; uso de memória; triângulos; divergência da classificação e desvio de superfície.

Prosseguir para experimento de integração apenas se houver vantagem repetível em pelo menos dois caminhos relevantes **e** uma qualidade aceitável para a direção artística do jogo. Inicialmente testar ≤ 2% de divergência em pontos aleatórios e p95 de superfície ≤ 0,25 m; estes são limiares exploratórios, não aprovações funcionais ou garantias de fidelidade. Se nenhuma resolução atender, testar arquitetura híbrida (SDF quantizado e superfície interpolada) antes de considerar migração.

## Execução e evidência

```powershell
$godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --editor --path .\game --import
& $godot --headless --path .\game --script res://tests/experiments/discrete_terrain_matrix_benchmark.gd
```

Workflow: `.github/workflows/exp-discrete-terrain-matrix.yml`.
Artefatos: `discrete-terrain-matrix-evidence` com logs e resumos JSON por processo.
Marcadores: `DISCRETE_TERRAIN_TRIAL=`, `DISCRETE_TERRAIN_SUMMARY=` e `DISCRETE_TERRAIN_BENCH_PASS`.

## Próximas decisões

1. Se B1 vencer apenas em remesh, experimentar blocos compactados com cache de patches e triangulação suavizada.
2. Se B2/B3 piorarem no cold, separar geração/base SDF de armazenamento esparso (octree ou blocos homogêneos) e benchmarkar cache/materialização.
3. Se a métrica de qualidade reprovar, testar estados discretos de **densidade quantizada** (e não só sólido/vazio), com tabelas de casos e interpolação de arestas.
4. Se meshing for irrelevante para o tempo total, priorizar o pipeline de projeção de fontes de objetos já medido pela série P5.
5. Nunca comparar ganhos entre runner Linux e runner Windows ou entre commits diferentes sem um A/B pareado na mesma máquina.
