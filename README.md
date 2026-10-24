# Procedural Sandbox Simulation

Godot 4.7.2-based **extensible procedural 3D sandbox and environmental simulation engine**: canonical world data, procedural objects/components and future public mod interfaces, persistent environmental state (V1) and eventual ecology (V2). Terrain is the **current foundational prototype**, not the product goal. Versioned SDF terrain, caves, additive/subtractive editing, bounded streaming and a detached LOD0/LOD1 CPU fixture are integrated; production LOD, persistent saves, collisions, a working mod loader, world/environment simulation and multiplayer are **not** delivered.

For continuity after terrain optimization, read the [proposed engine-wide post-terrain handoff](docs/roadmap/ENGINE-CONTINUITY-AND-POST-TERRAIN-HANDOFF-PROPOSED.md). It maps the still-pending P0.2/P0.3/P0.4 persistence/mod/simulation experiments into future owner-gated P2–P6 work without changing the accepted charter or accelerating multiplayer.

**2026-10-21 integration snapshot:** PR #98 documented the owner-approved B0 R4/R4a experimental *input/methodology* contract on `main` at `ea4422d90726d3f2fe6d5cef097126268f93685a`. Separately, limited test-only B1-1 implementation was initiated and is on [draft PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99), awaiting independent source review; no Godot/benchmark execution or merge is approved. Check live GitHub refs; this is a dated snapshot.

## Start here — authoritative continuity

1. [Current status](docs/status/CURRENT_STATUS.md) — last recorded integrated SHA, active work, risks and next owner gate. **Compare with live GitHub refs**; this file is a snapshot, not real-time state.
2. [Checkpoint index and latest dated snapshot](docs/checkpoints/INDEX.md) — reconstructible baseline and acceptance history.
3. [Decision register](docs/decisions/DECISION_REGISTER.md) and [accepted charter](docs/PROJECT_CHARTER.md) — accepted vs experimental vs deferred decisions.
4. [Agent recovery runbook](docs/workflow/AGENT_RECOVERY.md) and [memory protocol](docs/workflow/PROJECT_MEMORY_PROTOCOL.md) — resume safely in a fresh chat/agent, preserve evidence and update checkpoints.
5. [Developer contract](AGENTS.md), [workflow gates](docs/workflow/ROLES_AND_GATES.md), [architecture](docs/architecture/ARCHITECTURE.md), [contracts](docs/architecture/CONTRACTS.md), [roadmap](docs/roadmap/MILESTONES.md), [proposed engine-wide handoff](docs/roadmap/ENGINE-CONTINUITY-AND-POST-TERRAIN-HANDOFF-PROPOSED.md), and **current GitHub issue**.

A new agent **must not** infer completed work from an issue title or old chat. Reconcile the latest `main`/PR HEAD and the owner's acceptance gate first. P1.0A and P1.0B are integrated through PR #90 at `2f86c42503cfa3a334215b1ff5b9bf9658263440`. P1.0C global cross-region editing was owner-authorized and merged through [PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) as `9452cefe5788bbbd3a38fedb55773d10ebafb0d2`, following exact-SHA independent source review and owner-reported GUI PASS. Its 13 inherited PR #87 historical checkpoints were preserved. [P1.0C post-merge checkpoint](docs/checkpoints/2026-10-20-PR92-P1-0C-MERGE.md) was integrated in [PR #95](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/95). The detached P1.1A LOD0/LOD1 CPU experiment subsequently merged through [PR #96](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96) at `aca6b6403c455708cacda01c8fbf0bf980d813a2`, after exact-SHA independent source PASS; [P1.1B planning](docs/roadmap/P1-1B-PLANNING-HANDOFF-PROPOSED.md) is proposed only, not execution-authorized. See [current status](docs/status/CURRENT_STATUS.md) and [the P1.0C checkpoint](docs/checkpoints/2026-10-17-P1-0C-IMPLEMENTATION.md).

## Open the current prototype (Windows)

Working development directory designated by owner: `C:\Dev\sandbox-sim-dev` (not a requirement to clone into a new worktree).

```powershell
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\Dev\sandbox-sim-dev\game'
# In editor: open res://scenes/terrain_demo.tscn; F6 to run that scene.
# Tests:
$env:GODOT_BIN='C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& 'C:\Dev\sandbox-sim-dev\scripts\validate.ps1'
```

Check exact executable paths and engine version on the machine. The integrated prototype has versioned 16×12 logical regions, each divided into 16 chunks, camera-driven bounded streaming (PR #88) and the accepted P1.0B lighting correction (PR #90). Controls are left-click carve, Shift+left fill, right-drag orbit, wheel zoom, C section, R regenerate and X focused reset. P1.0C's bounded 256-command in-memory global edit ledger, cross-region remeshing and adaptive v1 picker are now **merged on `main`**, with owner GUI PASS and remaining performance caveats documented. [Owner GUI checkpoint](docs/checkpoints/2026-10-19-P1-0C-OWNER-GUI-ACCEPTANCE-AND-PREFLIGHT.md).

## Product goal vs current deliverable

The [charter](docs/PROJECT_CHARTER.md) targets a persistent expandable SDF world, procedural entities, modding, environmental systems (V1) and ecology (V2). The custom GDScript terrain is a **prototype**, not a final decision to reject Voxel Tools: ADR-0002 remains proposed/deferred. Multiplayer is **not planned for initial releases**, but keep deterministic/versioned region and ordered-operation data suitable for a future server-authoritative design; no networking is implemented.

Older setup/bootstrap instructions and F2-G1 research are historical; consult [current status](docs/status/CURRENT_STATUS.md) before treating them as active tasks. No implicit permission to perform protected host/VM work or adopt native dependencies.
