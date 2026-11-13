# DM17 — replicated wall-clock inference (88 trials)

**Data:** 2026-11-13. **Veredito:** `DM17_PRACTICAL_5PP_GAIN_NOT_SUPPORTED_IN_TESTED_CASES`; CI automatic: `INCONCLUSIVE` for any nonzero benefit. **Não promover à `main`.** As flags DM17 permanecem opt-in/desligadas por padrão.

## Proveniência

- Branch de benchmark: `exp/dm17-replicated-inference`.
- Commit fixo dos 88 ensaios: `d28088eb650f4b013e00d7348ed7519aa65c82fd`.
- [GitHub Actions: PASS, preflight + 88 trials + análise](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43485023427).
- Artefato GitHub Actions: `dm17-replication-full-evidence` (id `14067923740`; contém stdout/stderr, receipts individuais, `trials.json`, `pairs.json` e `dm17-replication-analysis.json`; retido até 2026-12-04).
- Scripts: `scripts/perf/run-dm17-replicated-inference.ps1` e workflow `.github/workflows/dm17-replicated-inference.yml`.
- Qualificação: Godot 4.7.2 e PowerShell 5.1 parse PASS; DM17 401 checks de Q8.8/Surface Nets, DM11 regressão, PASS.
- `main` não foi alterada.

## Protocolo

Comparação **controle vs DM17-A+B**, com flags `SANDBOX_DM17_SPARSE_BLOCK` e `SANDBOX_DM17_SHARED_LATTICE` apenas na variante B da comparação (A+B); as outras flags DM9/DM11/DM12/DM13/DM14/DM15 e a seed `424242` permanecem iguais. `SANDBOX_PERF_TRACE=0`, `SANDBOX_DM16_LIGHT_STAGES=0`, recolha mínima DM16 independente em memória, `SANDBOX_DM17_WALLCLOCK_ROUTE=1`. Movimento por `Time.get_ticks_usec()`, não por delta fixo por frame; distância comprovada em cada receipt.

Cada par executa controle e A+B em processos separados, com `APPDATA` isolado; pares adjacentes alternam ordem AB/BA (ABBA), nunca rodando em paralelo para evitar disputar CPU.

- 16 pares `straight-18` × 720 frames (32 execuções);
- 16 pares `outback-18` × 720 frames (32 execuções);
- 8 pares `straight-54` × 720 frames (16 execuções);
- 4 pares `idle` × 2400 frames (8 execuções).

Total **44 pares / 88 execuções**, mesmas revisões e dados autorizados. As estimativas e os IC 95% são de diferenças *por execução pareada*, não de milhares de frames correlacionados. IC de Student aproximado, sem garantir independência entre pares no mesmo runner/seed. Gates pré-definidos: foco canônico médio melhora ao menos 5 p.p. com IC superior abaixo de zero; sem >+2ms p99, >+0,35 p.p. >33ms, ou >+1s de demora HIGH, e todas as 268 regiões completas parado.

## Resultados — ausências do foco canônico (A+B menos controle)

| Rota | n pares | Controle médio | A+B médio | Diferença | IC 95% |
|---|---:|---:|---:|---:|---:|
| straight-18 | 16 | 43,802% | 41,728% | **−2,075 p.p.** | [−6,402; +2,253] |
| outback-18 | 16 | 34,375% | 34,453% | **+0,078 p.p.** | [−2,948; +3,105] |
| **18 m/s, combinado** | **32** | **39,089%** | **38,090%** | **−0,998 p.p.** | **[−3,515; +1,518]** |
| straight-54 | 8 | **100,000%** | **100,000%** | 0 | degenerado: sem informação sobre ganho relativo |

Nos 32 pares normais, 17 favoreceram A+B e 15 favoreceram controle. A estimativa de −0,998 p.p. é pequena e compatível com zero. O IC 95% exclui uma melhoria de pelo menos 5 p.p. nas condições testadas. Isso invalida a hipótese prática levantada pela primeira campanha de apenas dois pares (que estimara −7,638 p.p.) como *ganho reproduzível com magnitude ≥5 p.p.*; não demonstra equivalência exata ou inexistência de qualquer ganho menor.

Como checagem de autocorrelação/ordem ABBA, agrupando cada par adjacente AB/BA em um único bloco, n=16 blocos e a diferença combinada permanece −0,998 p.p., IC 95% [−3,122; +1,126]. O resultado qualitativo não muda.

## Fluidez, throughput e repouso

Diferenças A+B − controle no conjunto 18 m/s (n=32 pares):

| Métrica | Diferença média | IC 95% |
|---|---:|---:|
| Frame p99 | **−0,288 ms** | [−1,776; +1,199] ms |
| Frames >33ms | **+0,0347 p.p.** | [−0,0326; +0,1020] p.p. |
| HIGH visuais concluídas na rota | **+0,313 região** | [−1,047; +1,672] regiões |

Não há ganho reproduzível de frame ou throughput. As diferenças são pequenas frente à variabilidade. O controle p99 médio varia entre as duas rotas (straight 22,064ms e outback 18,878ms) e A+B varia de modo oposto (straight 20,523ms e outback 19,843ms), reforçando a ausência de benefício estável.

**Parado:** 4 pares, todas as **268/268** regiões HIGH concluídas em cada braço. Controle em média 13,635s; A+B 13,480s; diferença −155ms, IC 95% [−812ms; +502ms]. Sem evidência de aceleração robusta nem regressão material.

**54m/s:** todos os 8 pares apresentaram **100% dos frames com a região canônica focal ausente** em ambos os braços; a métrica saturou. O p99 foi 16,667ms e a taxa >33ms foi 0,139% nos dois braços, mas isso não valida streaming canônico: alta velocidade pode manter o centro sem publicação. O número de HIGH visual externo concluído foi ~98,6 controle e ~98,3 A+B, não fornecendo evidência de ganho. Priorizar investigação da priorização/latência canônica em deslocamento rápido.

## Decisão

O harness emitiu `INCONCLUSIVE` porque seu critério muito conservador de rejeição requer limite inferior do IC acima de −2 p.p.; observou-se −3,515 p.p. Isso **não contradiz** a decisão de engenharia: o intervalo já exclui ganho de 5 p.p. ou maior, objetivo definido antes dos testes. Não promover A+B para o perfil padrão, não gastar campanha de GPU para fundamentar ganhos headless não reproduzidos e manter os códigos em branch opt-in para eventual investigação.

Interpretação específica:
- **DM17-A** atua só na reconstrução Surface Nets *após* materializar todos os nós Q8.8; não é sparse SDF antes de amostrar e não valida/refuta otimização verdadeira de sampling narrow-band.
- **DM17-B** faz single-flight/cópia de nó Q8.8 somente no caminho pristine; a serialização de uma região completa e a competição de workers podem eliminar o ganho de trigonometria compartilhada. Não foi demonstrada aceleração end-to-end.
- **Claybook/GPU:** classificação conservadora de volumes antes de avaliar a densidade e extração em GPU permanecem **hipóteses novas**, não testadas por DM17. Exigem estimativa rigorosa de limites e fallback para edições/efeitos/tiles, preservando paridade.
- **Próxima intervenção justificada:** instrumentação leve para latência canônica e razão de descarte de jobs durante F10 a 18/54 m/s, especialmente os 100% de falta do centro a 54; selecionar nova intervenção só com causalidade medida. Não confundir HIGH visual externo com presença de região autoritativa.

## Limitações

Mesmo hardware/runner, mesma seed, Godot headless, sem GPU gráfica real; pares correlacionados por carga do host e condições temporais não permitem inferência universal para outras seeds ou PCs. O benchmark GPU interativo original [está enfileirado](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43482804872) na última verificação; não presumir aprovação. Os resultados **rejeitam adoção de DM17-A+B pelos ganhos prometidos neste cenário**, não todos os princípios de Claybook nem toda otimização do SDF.
