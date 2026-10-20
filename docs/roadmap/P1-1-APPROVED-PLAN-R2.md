# P1.1 — Plano R2 aprovado: LOD experimental, transições e avaliação de arquitetura

**Decisão do proprietário:** APPROVED_PLAN — 2026-10-20 (America/Sao_Paulo).  
**Natureza:** plano normativo para a futura P1.1; não é registro de implementação, teste executado, seleção de backend nem autorização de merge.  
**Fonte:** relatório Codex “P1.1 — relatório de planejamento” (`P1_1_PLAN_READY_FOR_OWNER_REVIEW`) apresentado pelo proprietário e aprovado, com as quatro correções arquiteturais da revisão de planejamento incluídas nesta versão R2.  
**Repositório:** `publiomcko-cloud/procedural-sandbox-simulation`  
**Baseline da decisão:** `main` `2f86c42503cfa3a334215b1ff5b9bf9658263440`, ainda sem P1.0C. PR #92 `f2a46433eed914223a6b39409d1e3865357f105e` (draft, não integrado na verificação); PR #87 `6fad428a22a149624da245e88a5e608d09ed7dd3` (draft documental, não integrado). Antes de qualquer implementação, reconfirmar os refs vivos.

## 1. Objetivo e limites vinculantes

Construir e avaliar **LOD espacial multi-resolução no terreno SDF**, com topologia de transição demonstrável e orçamentos explícitos de CPU, GPU, RAM e publicação. Preservar exatamente as operações canônicas de edição e a autoridade separada de nós e malhas. Seleção do backend final ocorre **somente por decisão/ADR própria**, após evidência adequada.

**Não é conclusão integral de P0 ou P1.** Continuam pendentes: escolha de backend/ADR-0002; persistência e durabilidade; colisão e política de recook; materiais físicos e renderização por material; LOD de produção e testes multiplataforma. Multiplayer não integra a primeira versão.

**Gate 0 obrigatório:** P1.0C PR #92 deve ser **expressamente autorizado para merge pelo proprietário**, integrado e verificado no `main` real, com checkpoint pós-merge, antes de iniciar código P1.1A. O PASS de source review e de GUI não constitui autorização de merge. PR #87 permanece historicamente preservado e não deve aplicar versões obsoletas de `CURRENT_STATUS`/roadmap sobre a documentação reconciliada. Uma autorização para planejar e preparar prompt não autoriza merge, código nativo ou execução F2-G1.

## 2. Contratos de autoridade e amostragem

1. **Campo/estado canônico**: `SdfWorld` v1 + seed e versão + ledger único de carve/fill ordenado (até 256 operações) são autoritativos. LOD/mesh/cache não alteram densidade, sequência, operações aceitas, identidade espacial ou semântica de `X/C/R`.
2. **Topologia espacial atual**: regiões 16×12 em XZ; 4×4 chunks por região, dimensões 4×3; células LOD 0 com passo 0,5; 32×20×24 células por região; limites Y [-2,8]; amostragem e propriedade half-open; coordenadas negativas por floor matemático. Meshing atual custom utiliza marching tetrahedra.
3. **Contrato de grade LOD 0/1**: tamanho de célula `h(L)=0,5·2^L`, amostra ancorada em **índices inteiros do espaço global**, sem arredondar por chunk; comum a regiões e sinais. LOD 0→1 cabe em chunks atuais de 4×3, com 8×6 e 4×3 células em X/Z.
4. **Escala L≥2 não implícita**: em L2, `h=2` e um chunk atual de profundidade Z=3 ocuparia 1,5 célula. Não emitir malhas de resolução incompatível com essa partição. Especificar agrupamento de chunks/tiles para múltiplos de 2 em Z, retiling compatível ou contrato equivalente, com coordenadas globais, ownership e testes antes de ampliar além de LOD 1. L≥2 **fora do fixture inicial**.
5. **Campo compartilhado**: amostras canônicas em coordenadas globais coincidentes são iguais para LODs/regiões; visualizador de corte C permanece derivado/não autoritativo. Normais nos contatos consultam o mesmo SDF global e epsilon físico comum, sem assumir igualdade de posições de vértices entre níveis.
6. **LOD não é autorização de perda geométrica**: faces, arestas e cantos internos precisam de topologia watertight sob as configurações LOD suportadas. Igualdade dos valores SDF nos pontos comuns, isoladamente, NÃO demonstra ausência de fissuras: provar interseções, células de transição, winding, T-junctions, normais e continuidade entre células adjacentes.
7. **Feições finas**: cavernas/túneis e detalhes menores que o passo de grade podem desaparecer em LOD 1. Definir antes dos testes métrica de erro geométrico, qualidade aceitável e quais feições devem persistir. Não prometer preservação irrealista sem oversampling ou política adicional.
8. **Invalidação, revisions e concorrência**: brush invalida chunks e células de transição com dependência no domínio de amostragem/gradiente; o recorte de comandos não usa somente suporte da esfera, mas prova no-op de todas as consultas. Jobs carregam seed/generator, ledger revision, region/chunk/LOD, request token, vizinhanças e dependências, com cancelamento de obsoletos e publicação coerente (sem mistura de revisões/LOD incompatíveis).
9. **Restrições iniciais de recursos**: 4 CPU workers no máximo, 2 construções de `ArrayMesh`/frame, máximo de 25 regiões/400 chunks residentes na baseline. Medir separadamente arrays CPU, malhas no processo e memória GPU; não duplicar malhas de vários LODs sem orçamento aprovado. Edição ocorre na autoridade única mesmo quando a área está descarregada; a reconstrução ao retornar não depende de cache ou malhas.
10. **Transições inicialmente experimentais**: permitir escolher método (costura geométrica, triangulação adaptada, células de transição etc.) com prova objetiva e rollback. Não copiar algoritmo de Transvoxel automaticamente para marching tetrahedra sem validar compatibilidade e regras de propriedade.

## 3. Sequência de slices e autoridade

| Slice | Status aprovado | Escopo / dependências | Aceite | Limites |
| --- | --- | --- | --- | --- |
| **P1.1A — contrato e fixture LOD 0/1** | Próximo escopo proposto para execução **somente após Gate 0** | Fixture custom GDScript independente da cena principal; amostragem global, uma ou mais interfaces LOD0/1, signed seams, células de transição, testes e telemetria; comparar com malha de referência. | Mesmos samples comuns; ausência de fissuras nas **interfaces internas** (não exigir fechamento artificial das bordas externas do fixture); winding/topologia/normais coerentes; erros dentro da tolerância pré-fixada; parity do ledger de até 256 ops; testes automatizados e limites observados. | Nenhuma alteração de `SdfWorld` v1, do terreno funcional principal, streaming de produção, persistência, terceiros ou API pública de mods. |
| **P1.1B — bench e comparação de candidatos** | PLANEJAMENTO, não autoriza execução nativa | Identificar desempenho do fixture custom e avaliar Voxel Tools por evidência pública, provenance/licenças, compatibilidade, manutenção e eventuais testes isolados autorizados em etapa futura. | Workload/seeds/hardware/equivalência de comandos definidos; CPU/GPU/memória/latência, riscos e cobertura de plataforma comparáveis; limites de dados explicitados. | Sem download/instalação/execução nativa nem decisão final até autorização nova e satisfação de F2-G1 e gates jurídicos. |
| **P1.1C — eventual integração de LOD** | FUTURA, não autorizada | Seleção/histerese, transições e publicação de LOD na cena, após prova de P1.1A, avaliação suficiente de alternativas e ADR do proprietário. | Coerência temporal e geométrica durante load/unload/edits; GPU/CPU/RAM, seams, downgrade/rollback, comportamento GUI e revisão independente. | Não pressupor aprovação de backend pelo sucesso do fixture. |

A nomenclatura é uma proposta de sequência; PR, contrato final, budgets de produção e escalada de escopo continuam sujeitos à decisão explícita do proprietário.

## 4. Comparação de backend — linha independente

- **Custom GDScript:** candidato de referência implantado no protótipo; permite controlar amostras/CSG/identidade, mas meshing, transições, render upload, LOD, colisão e manutenção ficam a cargo do projeto. Um protótipo LOD 0/1 **não prova** escalabilidade final.
- **Voxel Tools:** documentação pública relata SDF, `VoxelLodTerrain`, múltiplos LODs e edições concentradas no LOD 0, com restrições quando blocos não estão carregados; GDExtension é componente nativo e não compartilha automaticamente o ledger canônico. URLs de referência apresentadas no relatório: https://github.com/Zylann/godot_voxel/releases e https://voxel-tools.readthedocs.io/en/latest/api/VoxelLodTerrain/ .
- **Gate legal/técnico**: ADR-0002 segue **PROPOSED**; nenhum binário foi legitimado pela aprovação deste plano. Não quebrar `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. Se a via nativa estiver indisponível, registrar `NOT_RUN / BLOCKED`, jamais substituir por execução não autorizada ou declarar equivalência de desempenho.

## 5. Metodologia de medição e aceitação

**Antes de medir uma alternativa contra outra:** registrar hardware-alvo e contexto: OS, CPU, RAM, GPU/VRAM/driver, tela/resolução/renderer, Godot build, seed/versão, perfil, cache, warmup, configuração dos workers e ferramentas. Fixar ou obter aprovação prévia para FPS/frame target, memória máxima, latência de edição/publicação, erro geométrico em unidades de mundo/tela, tolerância de normais e tratamento de detalhe fino.

**Workloads independentes (não misturar para estatísticas de um cenário):**
1. Travessia determinística de 3×3, movimento frio e quente, múltiplas inversões de foco, histerese, descarregar e retornar a região editada.
2. Edição de 0/1/32/128/256 operações, histórica local concentrada e remota distribuída; interior, borda e cantos positivos/negativos; alternância carve/fill.
3. Contatos LOD0/1: face, aresta e canto; gradientes e corte, cavernas estreitas, interseção do isosurface, T-junction, patologia da triangulação, atualização de revisão e rollback.
4. Prova de equivalência SDF e semântica de domínio; paridade antes e depois de trocar LOD; seleção independente da ordem de visita.

**Instrumentação:** latência de escolha/prepare/snapshot, tempo de SDF/ledger, triangulação, normais, custo de célula de transição, fila/worker, criação/publicação `ArrayMesh`, main-thread, RAM pico/steady, malha bytes/candidatos, GPU quando suportado. Medir p50/p95/p99/pico **por tipo de evento** e séries de frames, repetindo execuções. Referência inicial: 10.000 frames por cenário podem ajudar estimar p99, **mas não garantem** estabilidade estatística; reportar n, warmup, distribuição, variação entre runs e overhead do profiler. Medições headless não substituem apresentação GPU nem o GUI do proprietário. Não inventar números-alvo depois de ver vencedor.

**Fail-closed:** fixture que não comprovar transições sem fissuras, regressão determinística ou segurança de revisão é `BLOCKED_WITH_EVIDENCE`, não fundamento para integrar LOD ao demo. Registrar raw metrics e limites/casos não testados.

## 6. Primeiro ticket de implementação — P1.1A

**Nome:** `P1.1A — LOD 0/1: contrato de amostragem global e fixture determinístico de transição`.

**Base obrigatória:** `main` real após PR #92 owner-approved merge e checkpoint pós-integração. Godot v4.7.2 estável `ed1daf0bf`. Usar o mesmo workspace Windows `C:Devsandbox-sim-dev` após verificar e preservar status/stash e qualquer trabalho em andamento; nenhuma branch/projeto extra sem acordo. Um novo branch/PR ordinário para P1.1A é aceitável **após Gate 0**, com draft/unmerged e revisão exata do SHA.

**Implementação limitada**: tipos puros para global lattice integer indices, transformação LOD 0/1, seleção de propriedades de amostras, fixture/célula de transição com saída de CPU/mesh para testes, um mecanismo escolhido de costura e medição. Não tocar no fluxo de produção `terrain_demo.tscn` nem permitir que protótipos de LOD mudem o ledger. Provar por testes casos de cavernas e regiões X/Z negativas, operação 256, reload derivado, transição face/edge/corner, normals e invariantes de namespace/revisão. Explicitar que o grafo/células de transição podem exigir um segundo ticket se a prova de qualidade não couber no escopo.

**Entrega**: spec/ADR proposto (sem adotar ADR-0002), testes deterministicamente reproduzíveis, benchmarks CPU/memória/publicação e limitações de GPU, diff, SHA/parent, documentos e evidência de que o `main` demo está inalterado. Reexecução integral `scripts/validate.ps1` com Godot pin; snapshot/review independente; GUI apenas onde há algo visível, sem assumir que headless prova pixels.

**Gates finais**: `P1_1A_READY_FOR_INDEPENDENT_SOURCE_REVIEW` ou `P1_1A_BLOCKED_WITH_EVIDENCE`. PR draft/unmerged, sem execução de P1.1B/C nem dependências nativas, sem salto sobre o Gate 0.

## 7. Ordem operacional depois da decisão

1. Verificar a aprovação deste plano versionado e seu SHA remoto.
2. **Sem alteração automática de P1.0C:** proprietário decide expressamente o merge do PR #92 e depois confirma `main` + checkpoint de integração.
3. Tratar separadamente a destinação do PR #87, que possui histórico preservado, sem sobrescrever arquivos de status atualizados.
4. Fixar budgets/tolerâncias/hardware-alvo e iniciar apenas P1.1A, se Gate 0 e autorização específica estiverem satisfeitos.
5. Independent exact-SHA review + GUI owner gate do fixture; P1.1B e P1.1C permanecem independentes.

**Status:** `P1_1_PLAN_R2_OWNER_APPROVED / P1_1A_PENDING_GATE_0 / PR92_UNMERGED_AT_DECISION`.
