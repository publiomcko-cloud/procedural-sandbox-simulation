> **Latest 2026-10-25 live override:** required main baseline `b874991bb0f2cc698e41dd8709f3b0325d73c855`; P2.0C is integrated through PR #112. P3.0A Delete correction source `3da4bc6f7272ed838da7438c43312227e32ae59e` (parent `c8a91eb387f037beb7c8db7670aed4186d37c496`) is on `feat/p3-0a-entity-command-contract`, draft PR #114. Full Godot 4.7.2 validation passes 17,969 assertions across 18 groups, including viewport Delete/restore regression; independent source review and owner GUI retest remain pending; do not merge. See [P3.0A implementation checkpoint](../checkpoints/2026-10-24-P3-0A-IMPLEMENTATION.md), [Delete correction checkpoint](../checkpoints/2026-10-25-P3-0A-ENTITY-DELETE-GUI-CORRECTION.md), [spec](../specs/P3-0A-TRANSACTIONAL-ENTITY-COMMAND-CONTRACT.md), [proposed ADR-0003](../decisions/ADR-0003-TRANSACTIONAL-ENTITY-COMMANDS.md) and [CURRENT_STATUS](../status/CURRENT_STATUS.md). Issue #108 and all five F2-G1 holds remain unchanged. Earlier status snapshots below are historical.

# Fresh-agent / new-chat recovery runbook

> **Latest 2026-10-25 Issue #118 R1 correction candidate:** main `fd431dbcad18685a3aa2c86c3c9b25fbd81303c9`; source `f0164b140009bb797951aa4085bb36001889bc57` on `fix/issue-118-mod-discovery-initialization` enforces the exact canonical `user://mods` allowlist in the loader; a pre-fix caller downgrade was reproduced and R1 full Godot validation passed 18,047 assertions/0 failures. PR #119 remains draft; R1 independent review, hosted CI and owner GUI are pending. Do not merge without explicit owner authorization. PRs #115/#117, P3.0C workspace and all five F2-G1 holds remain unchanged. See [R1 checkpoint](../checkpoints/2026-10-25-ISSUE-118-OPTIONAL-ROOT-API-HARDENING.md), [spec](../specs/ISSUE-118-MOD-DISCOVERY.md), and [ADR-0005](../decisions/ADR-0005-MOD-DISCOVERY-OPTIONAL-USER-ROOT.md).

> **Latest 2026-10-25 feature candidate override:** verified implementation baseline `5b8cf36108ce48476095f14b35426e7e8ab4bfe8`; P3.0B source commit `6ce65bbe2f1a54bd1436416b5cb6102c75a09769` is on `feat/p3-0b-playable-world-entity-commands`, with full Godot 4.7.2 validation 18,022 assertions/0 failures. Draft PR publication, independent source review and owner GUI retest are pending; no merge. Separate PR #115 remains untouched. Start with the [P3.0B checkpoint](../checkpoints/2026-10-25-P3-0B-IMPLEMENTATION.md), [spec](../specs/P3-0B-PLAYABLE-WORLD-ENTITY-INTEGRATION.md), and [ADR-0004](../decisions/ADR-0004-P3-0B-PLAYABLE-ENTITY-INTEGRATION.md), then verify live refs and workspace before any action. All five F2-G1 holds remain.

**Objective:** make the repository, not conversation history, the durable source of project decisions, approved evidence, open work and next action. A complete safe *logical reconstruction* requires Git refs + accepted docs + tickets + independent reviews + owner authority. A checkpoint is not a clone/VM backup and cannot restore unsaved local changes or credentials.

## 1. Verify real current state before acting

Identify repo `publiomcko-cloud/procedural-sandbox-simulation`. Read [CURRENT_STATUS](../status/CURRENT_STATUS.md) for the last checkpoint and [checkpoint index](../checkpoints/INDEX.md). **Check actual GitHub `main` SHA, current PRs, changed paths, comments/owner approvals**; the snapshot may be outdated. Never use a checkpoint branch's HEAD as if it were `main`.

On owner's existing Windows workspace (read-only first):

```powershell
$repo = 'C:\Dev\sandbox-sim-dev'
git -C $repo status --short --branch
git -C $repo remote -v
git -C $repo branch -vv
git -C $repo rev-parse HEAD
git -C $repo ls-remote origin refs/heads/main
git -C $repo worktree list --porcelain
```

Do **not** fetch/switch/reset/clean this directory while another Codex/agent is actively editing unless work ownership has been coordinated. Never silently overwrite dirty/untracked files or create another permanent worktree. If original workstation is absent, ask owner to provide approved new environment; do not assume the pinned Windows path is portable.

## 2. Read authoritative documents in order

1. [PROJECT_CHARTER](../PROJECT_CHARTER.md), [ADR-0001](../decisions/ADR-0001-BASELINE.md), [ADR-0002 proposed](../decisions/ADR-0002-TERRAIN-BACKEND-PROPOSED.md), [DECISION_REGISTER](../decisions/DECISION_REGISTER.md).
2. [CURRENT_STATUS](../status/CURRENT_STATUS.md), [integration ledger](../status/CHANGELOG.md), newest `docs/checkpoints/YYYY-MM-DD-*.md`.
3. [AGENTS.md](../../AGENTS.md), [PROJECT_MEMORY_PROTOCOL](PROJECT_MEMORY_PROTOCOL.md), [ROLES_AND_GATES](ROLES_AND_GATES.md).
4. [ARCHITECTURE](../architecture/ARCHITECTURE.md), [CONTRACTS](../architecture/CONTRACTS.md), [ROADMAP](../roadmap/MILESTONES.md), [PHASE_0](../specs/PHASE_0.md).
5. The **currently authorized GitHub Issue** and existing PR(s), exact base/head, source diff, test files, comment/review chronology.

Disagreement resolution: **live Git history proves implementation/merge**, accepted ADR and owner scope determine requirements, reviews describe evidence at their exact SHAs, status documents are dated snapshots. If conflict remains, **report and ask**, not infer authorization.

## 3. Produce mandatory recovery receipt before changing code

Report in one concise block:
- Repository, verified live main SHA, current feature branch/worktree status, active issue/PR/head SHA.
- Last merged accepted milestone and its actual source/GUI/test evidence classes (source-reviewed vs developer reported vs independently reproduced).
- Accepted architecture/constraints vs **proposed**, **deferred**, **blocked** and **active** scopes.
- The precise next user-authorized action; missing permissions, credentials, tool binaries or files; known hazards.
- Whether another agent is actively working and why your proposed edits are disjoint. **No action until conflict resolved.**

## 4. Resume an authorized ticket and review it

Code agent: stay on an assigned existing branch/workspace; verify clean/ownership, pinned parent/base, test with Godot 4.7.2, deliver exact commit and draft PR, never merge without owner approval. Evaluator: fetch exact remote source, assess diff/contracts/tests, clearly separate observed evidence classes and reserve GUI to owner. Owner: visual test and explicit merge decision.

Earlier P1.0 snapshot: P1.0A [#84](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/84) is integrated at main `7f87c1e9c0cc1e85dd5c5fb612ebf2cd40aeffb0`; P1.0B streaming and depth lighting are integrated at `2f86c42503cfa3a334215b1ff5b9bf9658263440`. P1.0C global cross-region transient edits were later integrated; its old draft/pending language above is historical. Use the current live override and `CURRENT_STATUS`, then verify current refs and checkpoints before acting. P2 object state/population are now integrated. P3.0A is only the draft candidate described above. Full P3, networking and F2 protected operations remain outside this authorization.

## 5. Create the next durable checkpoint

Following **each verified merged milestone** (and before handing work to a new chat), update CURRENT_STATUS, append CHANGELOG, add a *new immutable* dated checkpoint, and update DECISION_REGISTER when a scope/architecture decision changes. Include verified repo/ref tree/merge SHA; PR and issue; decisions and provenance; tests L0–L5 with who ran them; owner GUI outcome; open risks and next authorized scope; worktree/branch and reproducible verification commands. Open a separate docs-only PR if developer feature branch is busy; **do not mutate main without owner-approved merge**.

Template: [CHECKPOINT_TEMPLATE](../templates/CHECKPOINT_TEMPLATE.md). Checkpoint docs should be updated *after* source integration, not only before, so their verified `main` SHA is correct. If docs lag behind code, explicitly record the discrepancy in the next status update. Keep old snapshots intact and discoverable.

## Disallowed assumptions

- Green static CI means Godot runtime PASSED; a review means GUI visually passed; an owner says "passou" means merge authorized; a proposed ADR means accepted.
- A 16×12 logical region can be tiled with its 18×14 demo render skirt without overlap.
- GDScript custom prototype is the final chosen production backend.
- Open F2 security branches may be used during unrelated gameplay development.
- A new chat inherits local files, permissions, API connections or Codex process state just because the docs exist.

## Significant interaction recovery gate (2026-10-17)

Follow [PROJECT_MEMORY_PROTOCOL](PROJECT_MEMORY_PROTOCOL.md): every verified merge **and** meaningful authorization/architecture decision, source review outcome, owner visual PASS/FAIL, blocker or major handoff triggers a separate timestamped checkpoint. Update the [checkpoint index](../checkpoints/INDEX.md) even when no source code was merged. Mark PR drafts/observed branch heads pending and verify live refs again when resuming. Do not treat a newer documentation record as proof a feature was integrated. Keep historical checkpoint files immutable after integration.
