# F2 G1 — Active handoff and continuity checkpoint

**Snapshot:** 2026-10-14 (America/Sao_Paulo); **last review update:** 2026-10-15 (V4 pure-conformance PASS recorded). **Status:** F2 G1 diagnostic / protected release cycle BLOCKED and release held; v4 development is **source-only, non-integrated**. This record is a **snapshot**, not an assertion that GitHub refs can never move. Verify live state before any change.

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
| V4 exact process-error assertion correction | diagnostics/f2-v4-predispatch-exact-error-assertions | b044e517c46e8f8d95bb5d8d4bc1225f6459fe84; Codex Windows PS 5.1 **48/48 PASS, exit 0, 9 scripts parsed (0 errors)**; source-only review accepted; production source unchanged |
| V4 transaction architecture R1 — blocked | design/f2-g1-v4-transaction-contract-source-only | bbf001bc5a91c7b38289b31e2725aabde46a9499; **Codex BLOCKED_WITH_EVIDENCE**, five trust/replay/journal/finalization/quiescence findings; 38 design scenarios, no execution |
| V4 transaction architecture R2 — blocked | design/f2-g1-v4-transaction-architecture-r2 | d47970d89ad002d206639bbf3cf7acc088ac7127; **Codex BLOCKED_WITH_EVIDENCE**, four cutover/state/genesis/rollback findings; 85 design cases, no executable tests |
| V4 transaction architecture R3 — independent design review PASS | design/f2-g1-v4-transaction-architecture-r3 | c15b6440f91fe363b7bc1be7bf24b59229c3e402; **Codex V4_TRANSACTION_DESIGN_REVIEW_PASS** on exact SHA; 92 cases, 19 closed states, rollback reject-only and no production v2/v3 cutover; implementation NOT authorized |
| Transaction-v4 pure conformance harness — original independent review BLOCKED | diagnostics/f2-g1-v4-transaction-pure-conformance | cbad0524ccd8a54bcf8d0c1abfc0c08c4bea0f24; **Codex 701/701 assertions PASS but BLOCKED_WITH_EVIDENCE** on possible-write classification and unknown predecessor schema; retain review unchanged |
| Transaction-v4 pure conformance fail-closed correction — independent PASS | fix/f2-g1-v4-pure-conformance-failclosed-r1 | 93a4e1ee094dbaeb932c2117040c0bf4ecc30c15; **Codex Windows PS 5.1 712/712 PASS**, 11 negative regressions, exit 0, clean detached review; source-only correction complete, no release authorization |

**Pre-dispatch review chain:** docs/reviews/2026-10-14-F2-G1-V4-PREDISPATCH-7d66de1-BLOCKED.md (30/30 PASS but security BLOCKED); docs/reviews/2026-10-14-F2-G1-V4-PREDISPATCH-98fe40-BLOCKED.md (44/44 PASS but classification BLOCKED); **docs/reviews/2026-10-15-F2-G1-V4-PREDISPATCH-b044e5-PASS.md** (Codex 48/48 PASS on exact current source HEAD; source-only approval). Previous failed verdicts remain retained.

**Latest durable exact-SHA review:** `docs/reviews/2026-10-15-F2-G1-V4-CONFORMANCE-93a4e1ee-PASS.md` (Codex-reported 712/712 PS 5.1; ChatGPT GitHub static identity/diff checks). The prior `docs/reviews/2026-10-15-F2-G1-V4-CONFORMANCE-cbad0524-BLOCKED.md` preserves the 701/701-but-BLOCKED result. Earlier source-only integration evidence remains at docs/reviews/2026-10-14-F2-G1-V4-INTEGRATION-cb0bdddf.md. These are non-integrated source-only review records, not release receipts or merge authority.

**Important:** source-only PASS is limited to those exact snapshots; it is not a reviewed production release. Each next correction must have a new exact SHA, explicit scope and new validation. Do not combine differently reviewed Git identities, treat SHA abbreviations as independent trust pins, or imply unmerged branches are already integrated.

**Architecture lineage (separate unmerged branches):** R1 `bbf001bc5a91c7b38289b31e2725aabde46a9499` BLOCKED_WITH_EVIDENCE (5 findings, 38 cases); R2 `d47970d89ad002d206639bbf3cf7acc088ac7127` BLOCKED_WITH_EVIDENCE (4 findings, 85 cases); R3 `c15b6440f91fe363b7bc1be7bf24b59229c3e402` **V4_TRANSACTION_DESIGN_REVIEW_PASS (SPECIFICATION ONLY)**, 92 cases/19 closed states/zero mutations. Source report recorded in `docs/reviews/2026-10-15-F2-G1-TRANSACTION-R3-c15b644-PASS.md` on this docs branch. The R1/R2 blocked reports remain under the R3 design branch. Review PASS does not approve production v2/v3 cutover or any implementation; T86 'correctly signed-looking' wording should be tightened in future executable test vectors to 'cryptographically valid', without silently rewriting reviewed R3 bytes.

**Correction loop disposition (2026-10-15):** The isolated V4 pure-conformance *correction subtask* is technically complete at `93a4e1ee094dbaeb932c2117040c0bf4ecc30c15`. This does **not** close the entire F2 G1 blocked cycle, terminate ADR-0003 temporary roles or select the future migration/security architecture. Owner's authorization was limited to documentation/assessment; no protected or production action followed.

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

## Minimum viable path to resume F2 — source-only feasibility decision (2026-10-15)

The owner directed a *minimum viable* assessment rather than completing the protected v2/v3-to-v4/v5 migration. The resulting **independent-review-pending** design candidate is `docs/decisions/F2_G1_MINIMUM_VIABLE_RUNTIME_PATH.md`, on a separate docs-only branch `docs/f2-g1-minimum-viable-g1-route-r1` derived from this handoff SHA `d6887464c8fdcf153a2cbd9b8c037464049dd7a9`. It reuses the already independently `PASS_DESIGN` Issue #44 supervision architecture (draft PR #45 HEAD `5a5ba68350d316a2626c3c1a3598d45d1498804c`, reviewer PR #47), plus Issue #48's provisioned but OFF Hyper-V VM.

**Recommendation (not an approved runtime state):** no protected C: updater or v2/v3-to-v5 migration is required for the isolated Voxel Tools P0.1-F2 experiment. Next blocker is independent **VM/G: ACL evidence acceptance**, followed by host/guest watchdog and inert enforcement qualification and only later exact Godot/native probes. The source-only decision document authorizes NO live `icacls`, VM/G: read/write/start, UAC, protected update, Godot, vendor ZIP/DLL, CI, PR, merge or release. F2 G1 `RELEASE_HOLD` persists, and actual guest readiness remains `BLOCKED_ENVIRONMENT`.

**Independent decision-review finding (R1):** Codex reviewed `5d818f0ccb220e4ef11ff7c85527a959a1713b01` and returned `BLOCKED_WITH_EVIDENCE` solely because the decision text asserted retained production v2 without a fresh post-third-UAC read-only attestation. The smallest compliant route itself was judged conditionally feasible. The preserved historical review is `docs/reviews/2026-10-15-F2-G1-MINIMUM-PATH-5d818f0-BLOCKED.md`; this R2 branch corrects the installed-state provenance, leaving `CURRENT_PROTECTED_STATE_UNKNOWN / V3_NOT_ATTESTED` independent of the guest experiment. New R2 design review remains **PENDING**. All F2 G1 safety and release holds remain.

## Latest conformance review and next owner decision — no hidden background work

1. **Retain both immutable independent outcomes:** `cbad0524ccd8a54bcf8d0c1abfc0c08c4bea0f24` passed 701 tests but was **BLOCKED_WITH_EVIDENCE** on two fail-closed gaps. Corrected `93a4e1ee094dbaeb932c2117040c0bf4ecc30c15` passed **712/712 Windows PowerShell 5.1 assertions**, zero failures, exit 0; 92 R3 scenarios and 11 new negative tests passed. The original failed verdict is not retroactively changed. See `docs/reviews/2026-10-15-F2-G1-V4-CONFORMANCE-cbad0524-BLOCKED.md` and `docs/reviews/2026-10-15-F2-G1-V4-CONFORMANCE-93a4e1ee-PASS.md` on this documentation-only branch.
2. **Source-only subtask completed, F2 G1 NOT closed:** the two-file correction has passed independent review at the exact SHA. No source-only PASS proves production release transaction, protected updater, Windows storage durability, real signing/authority or an installed v2/v3 cutover. Original F2 full-sequence CI failure/timeout remains unresolved. Production status: **`F2_G1_RELEASE_HOLD`**.
3. **Next bounded decision gate, NO implementation authorized:** assess whether a protected v2/v3-to-future-v5 cutover is actually required for the P0.1 F2 Voxel Tools isolated feasibility objective. **Recommended:** do not implement a production cutover unless a real use-case justifies it; prioritize safe, independently authorized isolated native G1 feasibility when environment conditions can be demonstrated. If a production migration is required, obtain a separate owner-approved, design-only cutover ADR proving enforceable prevention of new/late v2/v3 readers, process/handle coverage, safe maintenance entry/exit, fixed volume, failure classifications and separately defined trust and durability decisions. R3 explicitly supports **no** production v2/v3 predecessor.
4. **Preserve current gates:** PRs #73/#74 draft/unmerged; no CI run/rerun, PR, merge, UAC, protected changes, Windows VM/G:, installer, production recovery, deployment or authorization implied by this documentary closure. Temporary ADR-0003 GitHub-author/Codex-Windows-validator roles remain until owner explicitly closes the **entire** blocked F2 G1 cycle.

## Onboarding after a chat-context reset

1. Fetch **main** plus the named **docs-only continuity branch** and all active topic branches; verify remote refs/PRs, latest Codex evidence and relevant CI runs. A newer GitHub source of truth overrides stale snapshots.
2. Read README.md, AGENTS.md, docs/workflow/PROJECT_MEMORY_PROTOCOL.md, docs/workflow/ROLES_AND_GATES.md, docs/decisions/ADR-0003-GITHUB-FIRST-WORKFLOW.md and this handoff **from the docs branch**, plus project charter, ADR-0001, relevant reviews and architecture.
3. Distinguish *integrated on main*, *source candidate*, *Windows independently validated*, *blocked*, and *not authorized*. Reconstruct parent → HEAD per branch, and check untouched protected/historical paths.
4. Ask only for missing current test evidence or permissions; do not re-ask known scope. Before writing, state the exact intended patch, parent SHA, branch and forbidden actions.
5. At the end of a meaningful review loop, persist SHA-specific evidence and refresh this handoff. If no docs write is authorized/available, clearly mark evidence UNCOMMITTED, not falsely persisted.

## Exit from this temporary arrangement

Only the owner can mark the stuck F2 G1 cycle **RESOLVED/CLOSED** after verifying the actual diagnostic outcome, integration status, residual risks and permissions. Record the closure with exact commits and independent tests, then explicitly return to the canonical flow: Codex implements and commits, ChatGPT is an independent evaluator, and the human decides architectural/security choices and merge/release. Do not continue GitHub-first authoring by default after closure.
