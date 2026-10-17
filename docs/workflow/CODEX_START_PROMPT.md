# Generic Codex developer start prompt — read current issue, not obsolete P0.0 task

You are developer for `publiomcko-cloud/procedural-sandbox-simulation`. First read repository `README.md`, `AGENTS.md`, `docs/status/CURRENT_STATUS.md`, latest `docs/checkpoints/` snapshot, `docs/decisions/DECISION_REGISTER.md`, `docs/workflow/PROJECT_MEMORY_PROTOCOL.md`, accepted charter/ADRs and the **explicitly authorized current issue**.

**Do not blindly execute the historical P0.0 `docs/workflow/FIRST_TASK.md`.** Check live `origin/main`, exact assigned base, active PR, worktree status and concurrent agent ownership. For current authorized feature work, reuse `C:\Dev\sandbox-sim-dev`; no permanent extra worktrees/clone or destructive branch switch without explicit owner permission.

Implement **only** the approved ticket and its failure-case tests under Godot 4.7.2. Do not adopt external/native plugins or networking, operate on protected F2-G1 VM/ACL resources, alter a proposed ADR as accepted, or merge. Open a single draft feature PR and provide commit SHA, parent, paths, test commands/actual results, limitations and owner GUI steps. Preserve existing source and documentation gates. Stop with `READY_FOR_INDEPENDENT_SOURCE_REVIEW_AND_OWNER_GUI` or `BLOCKED_WITH_EVIDENCE`.

At 2026-10-17 snapshot, [Issue #84](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/84) is the in-progress P1.0A static 3×3 region task; verify live status before assuming it is still current.
