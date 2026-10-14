# F2 G1 — Active handoff and continuity checkpoint

**Snapshot:** 2026-10-14 (America/Sao_Paulo). **Status:** F2 G1 diagnostic / protected release cycle BLOCKED and release held; v4 development is **source-only, non-integrated**. This record is a **snapshot**, not an assertion that GitHub refs can never move. Verify live state before any change.

**Repository:** https://github.com/publiomcko-cloud/procedural-sandbox-simulation

**Documentation scope:** This file is introduced on a **docs-only branch** named docs/f2-g1-temporary-github-first-handoff, based on main at snapshot SHA 0b3e69cec1bd0eeb6da5ff19b50f410acf33129b. Until explicitly merged by the owner, it is **not present on main**; a new agent must fetch this branch to recover context. No PR, merge or workflow run is authorized by this record.

## Active temporary operating method

See docs/decisions/ADR-0003-GITHUB-FIRST-WORKFLOW.md. For this F2 G1 blocked loop ONLY, the owner authorized ChatGPT to author minimal GitHub topic branches and perform static Git/source/diff/pin verification; Codex independently executes scoped tests on Windows in clean detached worktrees; the owner approves scope and any security-sensitive integration. **On explicit owner-recorded resolution of the blocked cycle**, revert to the normal **Codex implements/commits → ChatGPT evaluates → owner decides** process. A chat reset does not terminate or extend authorization.

No unilateral CI, PR, merge, UAC, protected ACL modification, release/update, real recovery, VM/Hyper-V/G: activity or deployment. Never interpret an earlier one-time CI experiment as general CI authorization.

## Current refs and review checkpoints — verify each live

| Purpose | Branch or reference | Exact review HEAD / status at snapshot |
|---|---|---|
| Integrated canonical source | main | 0b3e69cec1bd0eeb6da5ff19b50f410acf33129b; does **not** contain these experimental v4 changes |
| Original full-sequence experiment | PR #73, draft, open | 73425d50d8d4ff53281d2937c5fd22ddbaee391d; unmerged |
| Exact-pinned diagnostics manifest delta | PR #74, draft, open | 03066f8aaddb6c7d0db62a5aa51f76eb2785780a; unmerged |
| Raw ACL generic-mask correction | diagnostics/f2-raw-acl-mask-source-candidate | 6520528971bf9d2f7028c89319b660a13c538b55; Codex source-only PASS, 20 in-memory assertions |
| Separated v1/v2 source-pin roles | diagnostics/f2-versioned-source-pin-migration | 676301fdd6b1ce6c6eda161d1c5e1b2be753feb2; Codex source-only PASS, production verifier 7/7 |
| New v4 release contract source-only | diagnostics/f2-v4-release-contract-source-only | 52ed1258f1500830e970c4f13d81722b4ffd0465; **initial harness BLOCKED** on read-only $HOME |
| v4 harness reserved-variable fix | diagnostics/f2-v4-harness-home-fix | 722e428c6bcdd27d8849d07ff023effa036059ad; Codex Windows PS 5.1 **24/24 PASS** |
| Six-role inspect-only v4 integration design | diagnostics/f2-v4-integration-contracts-source-only | d29f5d5a10e1b16147a3638c0545d13dcf12c39d; Codex **BLOCKED**, 2 PASS then dependency function not visible |
| Fix v4 integration harness import order | diagnostics/f2-v4-integration-import-fix | cb0bdddf278da51be4e2acaea0d80141b7b4bbc4; **Codex Windows PS 5.1 49/49 PASS**, exit 0, three files parsed with zero errors; source-only only |
| V4 read-only pre-dispatch original review | diagnostics/f2-v4-production-contract-gates | 7d66de1037cf5e895c4128c5211e163a7d8c0ff4; Codex Windows PS 5.1 **30/30 tests PASS, but BLOCKED_WITH_EVIDENCE** (Git executable/config/timeout/path trust boundary) |
| V4 pre-dispatch bounded-process review | diagnostics/f2-v4-predispatch-process-boundary | 98fe40bd7e5ecf8afa3f5b02b1ba7ff3d479619f; Codex Windows **44/44 PASS, exit 0, but BLOCKED_WITH_EVIDENCE** on error-classification false-positive risk |
| V4 exact process-error assertion correction | diagnostics/f2-v4-predispatch-exact-error-assertions | b044e517c46e8f8d95bb5d8d4bc1225f6459fe84; one harness-only correction; **Windows review PENDING**, production source unchanged |

**Pre-dispatch blocked reviews:** docs/reviews/2026-10-14-F2-G1-V4-PREDISPATCH-7d66de1-BLOCKED.md (30/30 PASS; earlier security blockers), and docs/reviews/2026-10-14-F2-G1-V4-PREDISPATCH-98fe40-BLOCKED.md (44/44 PASS but test false-positive risk). Latest harness correction b044e517c46e8f8d95bb5d8d4bc1225f6459fe84 remains **UNVALIDATED**.

**Latest durable exact-SHA review:** docs/reviews/2026-10-14-F2-G1-V4-INTEGRATION-cb0bdddf.md. It records the Codex-reported 49/49 Windows PowerShell 5.1 result, exact Git blob/checkout hashes, earlier blocked attempt and unresolved release gates. This is a source-only verification record, not a signed release receipt or merge authority.

**Important:** source-only PASS is limited to those exact snapshots; it is not a reviewed production release. Each next correction must have a new exact SHA, explicit scope and new validation. Do not combine differently reviewed Git identities, treat SHA abbreviations as independent trust pins, or imply unmerged branches are already integrated.

## CI experiment and unresolved root cause

The owner previously authorized **one** first automatically triggered non-elevated Windows F2 CI run from draft PR #74: run **#85**, GitHub Actions run ID **38608659340**, Windows job **116006010674**, attempt 1. Its final outcome is FAILURE / FULL_SEQUENCE_INCONCLUSIVE, not evidence of a passing full sequence.

Observed in that run: TEMP preflight PASS; reviewed manifest / 29-entry inventory verification PASS; ACL protocol synthetic checks **152 assertions, 0 failures**. The icacls corroboration suite failed because raw ACL mask 268435456 (GENERIC_ALL, 0x10000000) was converted to the FileSystemRights enum, which rejected that mask. The diagnostics suite independently reported **67/68** assertions, with intermittent cross-process ChildBootstrapInitialization receiver CHANNEL_FAILED despite observing child exit 1; the same case passed in the prior run. Later suites were skipped after the icacls gate. The historical diagnostic child timeout root cause remains **UNKNOWN**; neither the raw-mask correction nor the source-only v4 work proves its resolution. **No automatic or manual CI retest authorized.**

Evidence links: https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/73 , https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/74 , https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38608659340 .

## v4 source-only technical boundaries

- The raw-mask correction preserves unsigned 32-bit ACE AccessMask bits; owner/Codex-reviewed tests include GENERIC_ALL/WRITE, generic read and deny/trusted-principal distinctions.
- The new v2 pin manifests independently pin current corrected source and the retained historical baseline. Old v1 manifests and v2/v3 receipts stay byte-for-byte intact.
- The v4 source-only release verifier validates exact ten-member source package, expected commit as a **caller-provided** value, externally anchored manifest/pin digests, baseline identities and Windows checkout bytes; returns InstallAuthorized=false.
- The v4 integration module is not imported by production. Its six actor contracts allow only Inspect and deny Capture/Run/Launch/Install/Activate/Rollback/ResumeForward. Its recovery model validates **synthetic observations**, NOT the historical hash-chained production journal.
- Actual collector/runtime/coordinator/launcher/updater remain v1/v2/v3-bound, and runtime v4 / recovery / install are blocked. **Actual Git commit and approval-receipt authentication, production release contract migration, full protected recovery fault injection and owner release approval have NOT occurred.**
- Git blob content, LF repository content and Windows CRLF checkout SHA-256 are different provenance classes where .gitattributes applies. For pinning use the exact byte representation required by the consumer; never guess hashes from normalized text.

## Immediate next action — no hidden background work

1. **Validate latest one-file harness correction:** Codex independently review exact branch diagnostics/f2-v4-predispatch-exact-error-assertions, HEAD **b044e517c46e8f8d95bb5d8d4bc1225f6459fe84**, direct parent **98fe40bd7e5ecf8afa3f5b02b1ba7ff3d479619f**. Confirm a single changed test script, unchanged bounded process module/historical production, fresh detached Windows PowerShell 5.1 parse and only Test-F2ReleasePreDispatch.V4.SourceOnly.ps1 run. Require exact captured `ErrorRecord.Exception.Message` classification and four explicit negative controls for unrelated marker text and cross-code confusion; report assertions, exit, hashes and cleanup. **WINDOWS RETEST PENDING / RELEASE_HOLD**.
2. **Retained evidence:** cb0bdddf278da51be4e2acaea0d80141b7b4bbc4 source-only integration **49/49 PASS**; pre-dispatch 7d66de1037cf5e895c4128c5211e163a7d8c0ff4 **30/30 PASS yet BLOCKED** on Git/process security; pre-dispatch 98fe40bd7e5ecf8afa3f5b02b1ba7ff3d479619f **44/44 PASS yet BLOCKED** on exact error classification. Do not transfer any verdict to b044e517.
3. **Next owner decision required:** determine whether to authorize a bounded **production v4 integration design/implementation** (collector, runtime, coordinator, launcher, updater, exact ten-member package and release trust roots). No such broader production implementation is granted by this source-only PASS.
4. **Separate security gates remain:** independently authenticate actual Git HEAD and external release receipt, version journal/transaction/recovery with rollback and fault injection, test installed-state compatibility and Windows EOL pinning, resolve or safely isolate the historical diagnostic full-sequence timeout and intermittent receiver failure. Preserve all historical v1/v2/v3 artifacts, no protected operations until separately authorized.
5. **No implicit continuation:** keep PRs #73/#74 draft/unmerged, CI not rerun, v4 runtime and installation disabled, and `F2_G1_RELEASE_HOLD`. Require explicit owner approval for new production/CI/PR/merge/elevated operations. After owner-recorded closure of the blocked cycle, restore Codex-author / ChatGPT-independent-reviewer / human-decision roles.

## Onboarding after a chat-context reset

1. Fetch **main** plus the named **docs-only continuity branch** and all active topic branches; verify remote refs/PRs, pending Codex result and latest relevant CI runs. A newer GitHub source of truth overrides stale snapshots.
2. Read README.md, AGENTS.md, docs/workflow/PROJECT_MEMORY_PROTOCOL.md, docs/workflow/ROLES_AND_GATES.md, docs/decisions/ADR-0003-GITHUB-FIRST-WORKFLOW.md and this handoff **from the docs branch**, plus project charter, ADR-0001, relevant reviews and architecture.
3. Distinguish *integrated on main*, *source candidate*, *Windows independently validated*, *blocked*, and *not authorized*. Reconstruct parent → HEAD per branch, and check untouched protected/historical paths.
4. Ask only for missing current test evidence or permissions; do not re-ask known scope. Before writing, state the exact intended patch, parent SHA, branch and forbidden actions.
5. At the end of a meaningful review loop, persist SHA-specific evidence and refresh this handoff. If no docs write is authorized/available, clearly mark evidence UNCOMMITTED, not falsely persisted.

## Exit from this temporary arrangement

Only the owner can mark the stuck F2 G1 cycle **RESOLVED/CLOSED** after verifying the actual diagnostic outcome, integration status, residual risks and permissions. Record the closure with exact commits and independent tests, then explicitly return to the canonical flow: Codex implements and commits, ChatGPT is an independent evaluator, and the human decides architectural/security choices and merge/release. Do not continue GitHub-first authoring by default after closure.
