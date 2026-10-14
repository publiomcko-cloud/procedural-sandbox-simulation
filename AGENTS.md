# Developer contract — Codex

Read `docs/specs/PHASE_0.md`, `docs/architecture/ARCHITECTURE.md`, `docs/architecture/CONTRACTS.md`, and the current task ticket before coding. Treat the user as release authority; ChatGPT is independent evaluator, not executor.

**Temporary F2 G1 exception (owner-approved 2026-10-14):** During the specifically blocked F2 G1 diagnostics/protected-release cycle, ChatGPT is the GitHub-side source author/static provenance reviewer, Codex independently validates exact candidate commits under Windows PowerShell 5.1, and the owner retains all important decisions. Codex must not modify the reviewed source during independent validation. This does **not** transfer merge, CI, UAC or release authority. See docs/decisions/ADR-0003-GITHUB-FIRST-WORKFLOW.md and docs/status/F2_G1_ACTIVE_HANDOFF.md on the docs-only branch docs/f2-g1-temporary-github-first-handoff until merged. **On explicit owner-recorded closure**, return to the normal rule below: Codex implements/commits, ChatGPT independently evaluates, owner decides. Other project work is unchanged.

## Non-negotiables
- Work only in assigned topic branch/worktree. Do not merge, force-push, change remote settings or rewrite history without explicit human approval.
- State assumptions and risks. A green smoke test never proves full correctness.
- Small, reviewable increments. Preserve stable public interfaces; write tests for every accepted behavior.
- Never silently add network dependencies, engine plugins, native extensions or external binaries. Propose and obtain approval first.
- Do not edit `docs/decisions/ADR-0001-BASELINE.md` to resolve a contradiction; open a new ADR proposal.
- Keep engine-authoritative world state independent from scene nodes; never represent every distant entity by a live Node.
- Generated data must be stable for fixed seed + generator version; do not use unseeded RNG or traversal-order-dependent generation.
- Do not treat GDScript mods as sandboxed. Trusted executable mods only unless a genuine sandbox is designed.
- Respect chunk boundaries, async publication, revision guards, save versions and material IDs.
- Scripts should emit useful exit codes. Include exact test commands and results; report tests not run.

## Required developer handoff
Use `docs/templates/DEVELOPER_HANDOFF.md`. Provide commit SHA, parent SHA, branch, paths changed, rationale, commands and results, limitations, risks, and visual test steps. End with **READY_FOR_INDEPENDENT_REVIEW**, **BLOCKED**, or **NEEDS_DESIGN_DECISION**.

## Definition of done
A change is not accepted until independent evaluator review and user visual test (when applicable). No self-approval. Follow `docs/workflow/ROLES_AND_GATES.md`.
