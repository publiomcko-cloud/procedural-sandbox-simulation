# F2 G1 — Contratos de integração v4 (source-only)

**Status: SOURCE_ONLY / RELEASE_HOLD / NO PRODUCTION DISPATCH**

Parent de implementação: `722e428c6bcdd27d8849d07ff023effa036059ad`.

Este candidato acrescenta um módulo independente de **contratos de interface** para seis papéis: Collector, Runtime, Coordinator, Launcher, Updater e Recovery. O módulo novo **não é importado por nenhum componente de produção** e não fornece instalação, UAC, leitura do ambiente protegido, execução de tarefas ou recuperação real.

## Fronteiras de confiança

- Cada papel permite somente `Inspect`, após a validação v4 dos dez arquivos reais do checkout. `Capture`, `Run`, `Launch`, `Install`, `Activate`, `Rollback` e `ResumeForward` sempre são rejeitados; nenhum retorno autoriza operações protegidas.
- Os campos `ExpectedCommitSha`, `ActualCommitSha`, `ExpectedManifestSha256` e `ExpectedActivePinsSha256` devem vir de uma fonte confiável independente. **Este módulo apenas compara valores fornecidos pelo chamador; não autentica Git HEAD ou uma aprovação externa.** O harness calcula hashes sintéticos para testar a interface, não para liberar uma release.
- O modelo de recovery verifica somente um **envelope sintético de observação**, não o journal de produção `transaction.ndjson`, sua cadeia de hashes, locks, barriers, ACLs ou transições reais. Mesmo uma observação válida mantém `MayRollback=false` e `MayResumeForward=false`.
- As identidades históricas instaladas v2 permanecem fixadas: commit `5741ffe90a3abd02a08563e6431e8a0b9b63eeb1` e manifest SHA-256 `b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9`. Não reinterpretar esse pacote como v4.

## Matriz de compatibilidade

| Papel | Produção atual | Contrato de proposta v4 |
|---|---|---|
| Collector | Pins v1; identidade original | Inspecionar dez membros; captura bloqueada |
| Runtime | Manifest v3; pacote de sete membros | Inspeção, sem `Run` ou ativação |
| Coordinator | Manifest v3, caminho aprovado, identidade/UAC | Inspeção, sem lançamento |
| Launcher | Candidato v3, hash e canal diagnóstico | Inspeção, sem UAC |
| Updater | Instalado v2 retido; candidato v3 de sete arquivos | Inspeção, sem instalação |
| Recovery | Journal encadeado, backup v2, locks/barriers | Envelope sintético; sem rollback/forward |

## Escopo dos testes

O harness `Test-F2ReleaseIntegration.V4.SourceOnly.ps1` realiza: inspeção por papel de dez arquivos do checkout Windows; impedimento de ações protegidas; rejeição de manifests/hashes/commit divergentes; testes negativos de ordem, ausência e adulteração de observações sintéticas de recuperação; guardas estáticos dos despachantes históricos v3.

**Não se deve inferir segurança de recovery real desses testes.** Antes de integrar produção, é necessário fixar e autenticar commit real e recibo externo, desenhar o pacote v4 instalável, versionar explicitamente transações, journal, persistência e rollback, fazer fault injection sintético e obter aprovação de segurança independente. A falha histórica do timeout de diagnóstico e a falha intermitente do receiver continuam pendentes.

Não autoriza PR, CI, merge, UAC, instalação, alteração de ACLs, acesso à VM/G:, deploy ou execução de rollback.
