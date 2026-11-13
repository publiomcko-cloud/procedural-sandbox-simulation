# DM17 — checkpoint wall-clock e experimento Sparse Surface Nets / Shared Lattice

Data: 2026-11-13. **Status: experimental, NÃO MESCLAR NA MAIN.**
Base: `exp/dm16-trace-independent-frame-evidence`, commit `63d3329b577c1c0b07556dee7eabd7ec28e6bd87`.
Código DM17 testado: `13c6b4b9ec8113c6451299fb691eabb727349b3c`.
As mudanças estão em `exp/dm17-sparse-shared-lattice`, com flags desligadas por padrão.

## 1. Checkpoint independente, antes de otimizar

Branch `exp/dm17-wallclock-checkpoint`, commit `abbcdab70220fb01fae1818f8279545a574dca86`.
[CI checkpoint, PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43479859318).

A rota `straight-18` move a câmera com `Time.get_ticks_usec()` e registra distância real percorrida. Evita o viés DM16 de 1/60s de deslocamento por frame independentemente da duração real do frame. O coletor DM16 permanece em memória, não emite `PERF_TRACE` no modo OFF/LIGHT. `SANDBOX_DM17_WALLCLOCK_ROUTE=1` só funciona no benchmark.

Quatro corridas móveis (duas OFF, duas LIGHT), duas paradas (OFF e LIGHT), seed 424242, Godot 4.7.2 Windows headless e `adaptive-skip-progressive`. Checkpoint OFF móvel (média de duas corridas): p99 20,850ms; >33ms 0,348%; >20ms 1,180%; foco canônico ausente 39,722%; HIGH externas concluídas 53,5; média frame 16,919ms. Parado OFF: 268/268 HIGH, 13,040s até completar. LIGHT é indicativo de estágios, não substitui OFF para FPS.

## 2. Implementação

**DM17-A**: `SANDBOX_DM17_SPARSE_BLOCK=1`, em `discrete_surface_nets_backend.gd`. Após materializar a matriz Q8.8 exata, percorre blocos de até 3x3x3 células, verifica **todos** os nós da grade expandida (+1 amostra por eixo) e ignora reconstrução por célula quando todos têm o mesmo sinal. Blocos mistos seguem o `_rebuild_cell_fast_uniform_gate` DM11. Não é classificação contínua de SDF nem suprime amostragem: é otimização **somente da extração de geometria**.

**DM17-B**: `SANDBOX_DM17_SHARED_LATTICE=1`. `dm17_shared_region_lattice.gd` materializa a densidade base pristine Q8.8 uma vez por região e reutiliza nós coincidentes nos 16 chunks, incluindo halos. Cache single-flight com mutex/semaphore, máximo de 64 regiões (~5,6MB para 21.735 nós int32/região, antes de overhead). Chave inclui seed, versão do gerador e região. Usa o caminho compartilhado apenas para snapshots pristine, sem brushes, tiles materializados, efeitos ou cave cutaway. Não altera autoridade, revisões, snapshots nem persistência. Chunks de mundo editado sem qualquer operação relevante continuam pristine por definição.

A matriz regional tem 35x23x27 = 21.735 nós, comparada com 16x(11x23x9) = 36.432 nós computados independentemente. O compartilhamento evita trabalho redundante de densidade, mas continua copiando valores aos arrays individuais dos chunks; não equivale a redução de 40% do tempo de frame.

## 3. Exatidão

[CI DM17 A/B, PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43481705572).
Contrato `dm17_sparse_lattice_contract.gd` (401 checks), todas as coordenadas dos 16 chunks em duas regiões, mais snapshots editados e cave. Compara arrays Q8.8, atividade, vértices, posições e normais exatamente. Regressões DM11, DM14, DM15, DM16 PASS. Um erro na primeira execução foi corrigido **apenas no teste**, para reconhecer chunks fora da influência espacial da edição como pristine; o código de geometria nunca apresentou divergência nesses testes.

## 4. ABBA headless, mesmo commit e rota por tempo real

[Execução DM17 10 ensaios, PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43481705572). Mesmo seed 424242, 720 frames móveis por ensaio, `PERF_TRACE=0` e `SANDBOX_DM16_LIGHT_STAGES=0`. Cada variante tem 2 corridas. Valores médios:

| Variante | Foco ausente | Frame p99 | >33 ms | >20 ms | HIGH em movimento |
|---|---:|---:|---:|---:|---:|
| Controle (A=0 B=0) | 39,444% | 21,715ms | 0,278% | 1,250% | 56,0 |
| DM17-A (A=1 B=0) | 45,972% | 22,937ms | 0,348% | 1,320% | 53,5 |
| DM17-B (A=0 B=1) | 45,972% | 20,735ms | 0,417% | 1,320% | 55,0 |
| A+B (A=1 B=1) | 31,806% | 21,712ms | 0,278% | 1,320% | 55,5 |

A+B mostrou -7,638 pontos percentuais de ausência canônica e praticamente igual p99 / >33ms no A/B pequeno. Execuções individuais: foco ausente controle 34,444/44,444%; A+B 25,139/38,472%. A grande variabilidade inviabiliza afirmação de ganho causal ou significância. Isoladas A e B não melhoraram o foco.

Parado (3600 frames): controle HIGH 268/268 em 13,273s e A+B HIGH 268/268 em 13,451s (+0,178s / +1,34%). Ambos concluíram todas as regiões.

## 5. Gates pendentes

- GPU Windows **interativa** com trace OFF, screenshot e A/B por relógio real. O branch `exp/dm17-gpu-validation` contém harness próprio; a execução deve ser verificada, não presumida.
- Repetir mais pares móveis a partir de uma origem isolada, com movimento real e comparar também latência canônica por ID/região, qualidade de borda, água e edições.
- Examinar hit-rate **real** de DM17-B no cenário mod-first. O contrato sintético demonstra cache hit, mas não mede sua prevalência no percurso com efeitos.
- Decidir se a melhoria de foco é robusta antes de promover A+B. A/B em headless não mede frame de GPU e não justifica merge na main.

## 6. Reproduzir

No GitHub, mudar para `exp/dm17-sparse-shared-lattice` e executar `scripts/perf/run-dm17-sparse-shared-abba.ps1` no runner Windows Godot 4.7.2. Flags de produção seguem `0` por padrão. Para teste de A+B, manter DM9/DM11/DM12/DM13/DM14/DM15 conforme o workflow e definir `SANDBOX_DM17_SPARSE_BLOCK=1` e `SANDBOX_DM17_SHARED_LATTICE=1`. Reversão: ambas `0`.

**Veredito:** `DM17_EXACT_PASS_HEADLESS_ABBA_PASS_ROLLOUT_BLOCKED_GPU_AND_REPLICATION`. Não inferir ganho de FPS por reduzir células ou amostras sem medição end-to-end.
