# ADR-0003 — Temporary F2 G1 GitHub-first / Windows-validation workflow

**Status:** Owner-approved temporary process exception, 2026-10-14. **Scope:** the currently blocked F2 G1 protected-release / ACL and diagnostics remediation cycle ONLY. **Not** a general replacement for ADR-0001, the product architecture, or the default development workflow.

## Context and decision

Repeated F2 G1 diagnosis, Windows PowerShell 5.1 harness regressions and CI ambiguity have required short, separately reviewed source corrections. The owner explicitly approved a temporary division of work on 2026-10-14:

- **ChatGPT — GitHub author for this cycle:** inspect real repository source and exact Git refs; prepare minimal source/tests/docs changes via the connected GitHub integration in isolated topic branches; verify ancestry, changed paths, Git objects, pins and source invariants. This is **static inspection, not Windows test execution**, and it is not an independent review of code authored by ChatGPT.
- **Codex — independent Windows verifier for this cycle:** fetch the exact published HEAD into a separate clean detached worktree; run explicitly permitted scoped Windows PowerShell 5.1 parser and synthetic tests; verify Windows checkout byte hashes, EOL and negative cases; report complete PASS or BLOCKED_WITH_EVIDENCE without changing the reviewed source.
- **Owner — sole scope and release authority:** authorizes each bounded stage and any broadened action; decides architectural or security-sensitive matters and eventual PR/CI/merge/deployment approval. A ChatGPT-authored change is never self-approved; Codex local PASS is not a merge or release decision.

Workflow for this exception: **owner-scoped authorization → ChatGPT GitHub patch + static identity/diff gates → immutable source HEAD on isolated branch → Codex Windows independent validation → evidence / corrections → explicit owner decision**. A failed test must stay recorded. Corrections get a *new* commit/branch from the exact blocked HEAD, not an overwrite or misleading retroactive PASS. The owner may re-scope work explicitly.

## Nonnegotiable safety and provenance

1. No force-push, main rewrite, surprise PR, manual CI rerun, merge, UAC/RunAs, protected ACL changes, protected updater installation, VM/Hyper-V/G: interaction, deployment or release without separate owner authority. A past one-time CI authorization does not renew itself.
2. Keep historical v1/v2 source pins, baseline integrity and historical v2/v3 release manifests unchanged. Distinguish **retained historical provenance** from **active source identity**. Never relax fail-closed checks to obtain a green result.
3. Independently verify exact branch HEAD, parent, three-way diff/changed paths, Git blob IDs and checkout SHA-256; annotate whether values are Git bytes, Windows checkout bytes or historical receipts.
4. The GitHub-side author **must not** claim tests executed on the owner's Windows host. The Codex verifier **must not** mutate reviewed source as part of the same validation verdict. Distinguish asserted test output from direct repository inspection.
5. Every significant review round needs a durable record referencing exact SHA, evidence, unresolved blockers, changed permissions and the next authorized step. Update the active F2 G1 handoff, preserving prior failures. Until docs are merged, identify their **documentation branch** explicitly and do not call them canonical main.
6. Source-only v4 inspection modules and synthetic recovery observations **do not** authorize executable v4 dispatch, installation or actual protected recovery. Independent authentication of actual Git HEAD and externally approved digest/receipt remains a separate release gate.

## Expiration and return to the standard workflow

This is an **exception for the current blocked F2 G1 remediation loop**, not a new permanent team structure. It ends **only when the owner expressly records that this F2 G1 blocked cycle is resolved/closed**, with the outcome, latest accepted SHA, any merged PR/CI evidence, residual risks and handoff status documented. Passing one local test, closing a draft PR, or merely changing conversation does not imply closure.

After that owner-recorded closure, the normal process in docs/workflow/ROLES_AND_GATES.md resumes without additional blanket permission: **Codex implements and commits; ChatGPT independently evaluates the resulting exact Git diff/evidence; the owner decides important architecture/security choices and final merges/releases.** No permanent GitHub-author privileges should be inferred. Record the expiration in a follow-up dated review/status note or superseding ADR; retain this ADR as historical evidence.

## Scope boundary and source of truth

This decision temporarily qualifies the older role descriptions in AGENTS.md and docs/workflow/PROJECT_MEMORY_PROTOCOL.md **only** for the specific F2 G1 cycle. All other project work follows the standard model. For the concrete current refs, Windows test outcomes, failures and next task, read docs/status/F2_G1_ACTIVE_HANDOFF.md and **verify live GitHub refs before acting**.

**Owner decision:** explicit instruction in project conversation, 2026-10-14, to preserve ChatGPT–GitHub authoring and Codex–Windows verification until the blocked cycle is solved, then restore Codex-author / ChatGPT-review / human-decision roles. This ADR records that authorization; it does not grant unlimited future modifications.
