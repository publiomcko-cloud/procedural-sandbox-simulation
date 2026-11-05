# Developer operating contract — Codex and other coding agents

> **2026-11-05 runtime-mainline override:** PR #228 merged the owner-accepted runtime/performance line into `main` as `f646a3b1b5d22ee443adb12d7b77634ef4528f17`. New functional work starts from live `main`. The P3.1 R12-CXR R1–R6 research chain is historical/superseded as active work; its PRs were closed unmerged with evidence preserved unless the owner explicitly reopens that direction. Current validation entrypoint is `scripts/validate.sh` with Godot 4.7.2; historical `validate.ps1` references are not current instructions.

**Always bootstrap from live repository state, not previous chat.** Read [README](README.md), [CURRENT_STATUS](docs/status/CURRENT_STATUS.md), the latest [checkpoint](docs/checkpoints/2026-11-05-RUNTIME-MAINLINE-MERGE.md), [DECISION_REGISTER](docs/decisions/DECISION_REGISTER.md), [AGENT_RECOVERY](docs/workflow/AGENT_RECOVERY.md), charter/accepted ADRs, architecture/contracts and the **exact current authorized GitHub issue** before editing. Check `main` and all active PR heads. Historical `docs/workflow/FIRST_TASK.md` concerns P0.0 and must not replace the live issue.

## Non-negotiables
- Work only on the assigned topic branch in the **owner-designated existing workspace `C:\Dev\sandbox-sim-dev`** for current functional increments. **No new permanent worktree** unless owner explicitly changes policy. Check for concurrent Codex runs and dirty/unpushed work before switching branch.
- Never self-accept, merge, force-push, delete assets/branches, modify remote settings or rewrite history without the owner's explicit decision. A visual PASS is not merge authorization.
- State assumptions and risks. A green hosted "Starter checks" is static only; a developer-reported Godot test is not an independently reproduced test. Record evidence grades L0–L5.
- Small reviewable increments, stable interfaces and negative tests for accepted behavior. Do not silently introduce external dependencies, native extensions, Godot plugins, network services or binary downloads.
- Keep accepted `docs/decisions/ADR-0001-BASELINE.md` immutable; propose new ADRs for architectural changes. `ADR-0002` is not approved. GDScript SDF is a prototype, not final backend selection.
- World/domain state and ordered mutations remain independent of Godot scene nodes. Preserve seed+generator version, region/chunk coordinate semantics, deterministic ownership and revisions. Avoid traversal-order-dependent RNG and cross-platform bitwise guarantees without proof.
- First-party/external scripted mods are trusted privileged code unless a real sandbox exists; avoid running unknown scripts/installers.
- Protected F2-G1/Hyper-V/host ACL activity is **not** authorized under ordinary P0/P1 functional tickets; its separate holds remain in force.
- No implementation of deferred issue slices (at checkpoint P1.0B/P1.0C, multiplayer, persistence or networking) without explicit new owner authorization.

## Developer handoff and owner gates
Use [developer handoff template](docs/templates/DEVELOPER_HANDOFF.md): exact SHA and parent, branch/PR, changed paths, rationale and limits, Godot 4.7.2 command results (or tests not run), failing cases, reproducible GUI steps. End with `READY_FOR_INDEPENDENT_SOURCE_REVIEW_AND_OWNER_GUI` or `BLOCKED_WITH_EVIDENCE`. ChatGPT evaluates exact remote source; owner does GUI and authorizes any merge.

Every verified accepted merge needs an updated status ledger and a dated documentary checkpoint, following [PROJECT_MEMORY_PROTOCOL](docs/workflow/PROJECT_MEMORY_PROTOCOL.md). Do not touch concurrent docs-only branch/PR without coordinating changes.

## Significant-interaction checkpoints (owner requirement)
After **every verified merge** and **every materially significant interaction** (owner decision/authorization, substantial source-review or GUI verdict, blocker, architectural change, critical correction or major handoff), create a dated immutable checkpoint and update the [checkpoint index](docs/checkpoints/INDEX.md). Preserve approved vs merely reported/blocked statuses and exact Git SHAs. This requirement does **not** authorize auto-merging documentation. During Codex work, use a separate remote docs-only branch; do not touch its Windows workspace.
