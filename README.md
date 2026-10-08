# Procedural Sandbox Simulation — Starter Worktree

**Status:** Architecture baseline v1.0; Phase 0 only. **No completed terrain, simulation, ecosystem, or mod runtime is claimed.**

## Read in this order
1. `docs/setup/WINDOWS_SETUP.md` — Windows 11 / PowerShell / VS Code / Godot.
2. `docs/workflow/ROLES_AND_GATES.md` — Codex developer, ChatGPT evaluator, human bridge and visual tester.
3. `AGENTS.md` — developer operating contract.
4. `docs/architecture/ARCHITECTURE.md` and `docs/architecture/CONTRACTS.md`.
5. `docs/roadmap/MILESTONES.md` and `docs/specs/PHASE_0.md`.
6. `docs/workflow/FIRST_TASK.md` — first developer assignment.

## Quick commands
```powershell
pwsh -File scripts/check-env.ps1
pwsh -File scripts/validate.ps1
```
Set `GODOT_BIN` if Godot is not available as `godot` in PATH. A minimal startup scene and headless smoke test are included. The test suite is a starter smoke check, not a proof of architecture correctness.

**Important:** A ZIP is not a Git worktree: extract it, `git init` and commit, then create linked worktrees as described in setup. No Git history or third-party binaries are bundled.

## Project goals
- Expandable deterministic 3D world with smooth SDF/voxel terrain, caves, persistent edits and hybrid procedural objects.
- Capability-based interaction, shared material properties, hybrid destruction and free placement with optional snapping.
- Fixed-step, multi-resolution simulation and data + trusted scripting mod API.
- V1 environment simulation; V2 ecosystem simulation; both observer/editor and player modes.

See `docs/research/SOURCES.md` for verified documentation links and version assumptions (checked 2026-10-08).
