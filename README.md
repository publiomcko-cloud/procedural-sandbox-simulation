# Procedural Sandbox Simulation

Godot 4.7.2 procedural 3D sandbox: versioned SDF terrain, caves, additive/subtractive brushes and localized chunk remeshing. **Functional finite prototypes exist; a production-ready endless world, persistent saves, multiplayer, LOD, collision, mods and simulation do not.**

## Start here — authoritative continuity

1. [Current status](docs/status/CURRENT_STATUS.md) — last recorded integrated SHA, active work, risks and next owner gate. **Compare with live GitHub refs**; this file is a snapshot, not real-time state.
2. [Checkpoint index and latest dated snapshot](docs/checkpoints/2026-10-17-P1-0A-KICKOFF.md) — reconstructible baseline and acceptance history.
3. [Decision register](docs/decisions/DECISION_REGISTER.md) and [accepted charter](docs/PROJECT_CHARTER.md) — accepted vs experimental vs deferred decisions.
4. [Agent recovery runbook](docs/workflow/AGENT_RECOVERY.md) and [memory protocol](docs/workflow/PROJECT_MEMORY_PROTOCOL.md) — resume safely in a fresh chat/agent, preserve evidence and update checkpoints.
5. [Developer contract](AGENTS.md), [workflow gates](docs/workflow/ROLES_AND_GATES.md), [architecture](docs/architecture/ARCHITECTURE.md), [contracts](docs/architecture/CONTRACTS.md), [roadmap](docs/roadmap/MILESTONES.md), and **current GitHub issue**.

A new agent **must not** infer completed work from an issue title or old chat. Reconcile the latest `main`/PR HEAD and the owner's acceptance gate first. [Issue #83](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/83) is the P1.0 plan; [Issue #84](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/84) is the authorized, in-progress P1.0A slice at the 2026-10-17 checkpoint.

## Open the current prototype (Windows)

Working development directory designated by owner: `C:\Dev\sandbox-sim-dev` (not a requirement to clone into a new worktree).

```powershell
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\Dev\sandbox-sim-dev\game'
# In editor: open res://scenes/terrain_demo.tscn; F6 to run that scene.
# Tests:
$env:GODOT_BIN='C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& 'C:\Dev\sandbox-sim-dev\scripts\validate.ps1'
```

Check exact executable paths and engine version on the machine. Before P1.0A is accepted, the integrated prototype is **one logical region divided into 16 chunks**, with left-click carve, Shift+left fill, right-drag orbit, wheel zoom, C section, R regenerate and X reset. PR #78, #80 and #82 were independently source-reviewed, visually accepted by the owner and merged. The P1.0A 3×3 region grid is **not yet integrated** at this checkpoint.

## Product goal vs current deliverable

The [charter](docs/PROJECT_CHARTER.md) targets a persistent expandable SDF world, procedural entities, modding, environmental systems (V1) and ecology (V2). The custom GDScript terrain is a **prototype**, not a final decision to reject Voxel Tools: ADR-0002 remains proposed/deferred. Multiplayer is **not planned for initial releases**, but keep deterministic/versioned region and ordered-operation data suitable for a future server-authoritative design; no networking is implemented.

Older setup/bootstrap instructions and F2-G1 research are historical; consult [current status](docs/status/CURRENT_STATUS.md) before treating them as active tasks. No implicit permission to perform protected host/VM work or adopt native dependencies.
