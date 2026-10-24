# Procedural Sandbox Simulation

**2026-10-24 live status:** `main` at `0ea2ad834db5dc2de1110cf0388ea06604cc7715`. PRs #99 (test-only P1.1B harness), #103 (playable LOD0/1), #104 (local single-slot world save), and #105 (declarative mod registry) are integrated. [PR #106](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/106) is an unmerged draft: owner GUI reports unnatural spherical procedural rocks; correction and repeat GUI review required before merge. [Verified reconciliation checkpoint](docs/checkpoints/2026-10-24-P1-1C-P0-2-P0-3-MERGE-RECEIPTS-P2-0A-GUI.md). Older text below is historical where inconsistent; prefer the live verified SHA and [CURRENT_STATUS](docs/status/CURRENT_STATUS.md). Document every significant event with an immutable checkpoint and update index/status, without self-merging.


Godot 4.7.2 procedural 3D sandbox: versioned SDF terrain, caves, additive/subtractive brushes and localized chunk remeshing. **Functional finite prototypes exist; a production-ready endless world, persistent saves, multiplayer, LOD, collision, mods and simulation do not.**

## Start here — authoritative continuity

1. [Current status](docs/status/CURRENT_STATUS.md) — last recorded integrated SHA, active work, risks and next owner gate. **Compare with live GitHub refs**; this file is a snapshot, not real-time state.
2. [Checkpoint index and latest dated snapshot](docs/checkpoints/INDEX.md) — reconstructible baseline and acceptance history.
3. [Decision register](docs/decisions/DECISION_REGISTER.md) and [accepted charter](docs/PROJECT_CHARTER.md) — accepted vs experimental vs deferred decisions.
4. [Agent recovery runbook](docs/workflow/AGENT_RECOVERY.md) and [memory protocol](docs/workflow/PROJECT_MEMORY_PROTOCOL.md) — resume safely in a fresh chat/agent, preserve evidence and update checkpoints.
5. [Developer contract](AGENTS.md), [workflow gates](docs/workflow/ROLES_AND_GATES.md), [architecture](docs/architecture/ARCHITECTURE.md), [contracts](docs/architecture/CONTRACTS.md), [roadmap](docs/roadmap/MILESTONES.md), and **current GitHub issue**.

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
