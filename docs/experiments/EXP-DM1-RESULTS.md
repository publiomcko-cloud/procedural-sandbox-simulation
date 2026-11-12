# EXP-DM1 — Resultados medidos (2026-11-12)

**Estado:** experimento **qualificado em CI** para o escopo de microbenchmark; **não aprovado para integração** no runtime.
**Fonte:** Godot 4.7.2 headless, runner físico Windows `sandbox-gpu-interactive`, branch `exp/discrete-terrain-matrix-benchmark`.
**Runs:** [43212412605](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43212412605) (A/B1/B2/B3, SUCCESS) e [43214203568](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43214203568) (A/B1/B2/B3/B4, SUCCESS).
**SHA B4 testado:** `ad63f01c80c551808fe40224b27f8882bdd42a83`.
**Artefato da rodada final:** `discrete-terrain-matrix-evidence`, id `13942513791`, inclui logs brutos e dois resumos JSON.

## Síntese da rodada final

Média de **dois resumos medianos de processo** (cada processo mede duas repetições ABBA por caso); medições originais preservadas no artefato. Não é uma inferência estatística de confiança e não mede FPS, GPU, colisão ou a cena completa.

| Backend | Cold, ms | Warm, ms | Oito edições, ms | Triângulos | Bytes do estado candidato |
|---|---:|---:|---:|---:|---:|
| A — SDF + Marching Tetrahedra 0,50 m | 317,12 | 321,53 | 930,93 | 9.585 | Não medido |
| B1 — ocupação + Greedy 0,50 m | 159,15 | 122,06 | 217,47 | 692 | 19.448 |
| B2 — ocupação + Greedy 0,25 m | 1.194,27 | 931,14 | 1.619,08 | 2.420 | 138.600 |
| B3 — ocupação + Greedy 0,125 m | 9.354,36 | 7.153,91 | 12.574,19 | 8.894 | 1.044.680 |
| **B4 — Q8.8 + Surface Nets 0,50 m** | **304,93** | **98,47** | **403,08** | **3.570** | **339.764** |

B4 contra o SDF:

- Cold: ~1,04× (ganho ~3,8%, **sem evidência suficiente de vantagem material**).
- Warm: ~3,27× mais rápido (redução ~69,4%).
- Edições: ~2,31× mais rápido (redução ~56,7%).
- Triângulos: ~62,8% menos, mas topologia/normal diferente.
- A memória de A não foi medida: **0 no JSON do controle significa N/A, não uso zero**. Bytes B1–B4 são estado de dados, sem buffers de malha/engine/GPU.

## Fidelidade após oito edições

| Backend | Divergência em 384 pontos aleatórios | Divergência em 384 centros | p95 da magnitude do SDF em vértices |
|---|---:|---:|---:|
| B1 | 5/384 (1,30%) | 0/384 | 0,348 m |
| B2 | 3/384 (0,78%) | 0/384 | 0,176 m |
| B3 | 2/384 (0,52%) | 0/384 | 0,088 m |
| **B4** | **2/384 (0,52%)** | **1/384** | **0,064 m** |

A magnitude do SDF é métrica substituta de qualidade geométrica, não a distância de Hausdorff. Os 384 pontos não garantem qualidade para todas as cavernas e alterações. B4 tem normas de face calculadas por quad, não normais suaves equivalentes ao SDF.

## Veredito técnico

1. **B1 demonstra vantagem real de CPU para geometria blocada**, mas não atende ao limiar exploratório de p95 ≤ 0,25 m.
2. **B2 e B3 são rejeitadas como matriz densa global:** multiplicar a resolução por eixo eleva desproporcionalmente o custo cold/warm/edit; a fidelidade melhora, mas o desempenho fica pior que A.
3. **B4 é o melhor candidato para investigação seguinte**: forte ganho em remesh e edits mantendo p95 ≤ 0,25 m e divergência de sinal ≤ 2%, mas cold praticamente neutro e o cache ocupa ~340 KB por região antes de mesh/GPU.
4. **Nenhuma variante está pronta para substituir a arquitetura principal.** Ausentes: teste de topologia/manifold, bitwise determinism multi-plataforma, bordas entre regiões, LOD, streaming/visibilidade, preparação de colisão, material blending, persistência/undo, mods, água e custos de projeção de fontes dos objetos.
5. O gargalo conhecido no pipeline P5 de **projeção de fontes de objetos** é independente de B4. O resultado não implica aceleração da cena ou carregamento em F10.

## Próxima experiência recomendada — DM2

Construir um *adapter* B4 apenas para `TerrainMeshJob`, preservando snapshots/revisões e deixando o runtime normal como A (A/B feature flag). Primeiro qualificar seams X/Z/corner, brush CSG, LOD e colisões; depois medir a mesma rota F10 em A/B/B/A no mesmo runner, com rastreamento separado de tempo de campo, mesher, preparação de fontes, projeção, upload e frame hitch.

Se o cold ainda permanecer neutro, testar **blocos homogêneos esparsos e materialização paralela** / `PackedByteArray` Q8.8 para reduzir custo de build e memória, sem aumentar a resolução base do mundo inteiro. Promover o candidato apenas com evidência end-to-end e sem regressão visual.

**Não foi feito merge na main.**
