# Checkpoint — P1.0C owner GUI: responsiveness improved, global edit cap blocks continued sculpting

**Event date:** 2026-10-18 (UTC−03).  
**ID:** `CHK-2026-10-18-P1-0C-OWNER-GUI-LEDGER-LIMIT`  
**Status:** `OWNER_GUI_SPEED_POSITIVE / SUSTAINED_EDIT_BLOCKED / NO_MERGE`.  
**Publication:** recorded on separate docs-only draft [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87); **not yet merged**. This checkpoint supersedes neither the actual source/performance test reports nor the requirement for full owner acceptance.

## Evidence and exact repository state

Owner said: **"a velocidade de execucao ta boa, aconteceu esse erro que esta no log, descricao depois de editar e mover um pouco o jogo nao aceita mais modificacoes"**. Owner provided a screenshot of a Godot 4.7.2 prototype in a 1152×648 viewport on 2026-10-18. The screenshot is discussed in the owner chat and transcribed in [Issue #94](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/94), not directly committed as an image to this branch.

- Live repo `publiomcko-cloud/procedural-sandbox-simulation`; verified `main` **`2f86c42503cfa3a334215b1ff5b9bf9658263440`**. [PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) feature branch `feat/p1-0c-global-cross-region-brushes`, reviewed GUI candidate **`6d128e3d231aa0456c42cf06e9e60f5a861d59df`**, remains **OPEN/DRAFT/UNMERGED**. Independent [source review #5564956018](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5564956018) found acceptable worker meshing source, with GUI performance pending.
- Screenshot HUD: `Focus region: (-12,-1)`; `resident/active: 15/25`; `queued regions: 0`; `queued chunks/jobs: 0/0`; `Worker jobs: 0/4`. Global ledger `Global edits: 32/32`, `seq/rev: 31/32`. `Last edit: 2 support / 2 rebuild regions, 6 chunks, 6 uploads`; `commit: idle`. `peak frame: 142.7ms`.
- HUD displays `STREAM ERROR: Edit revision changed before CPU mesh job submission` and `Global edit ledger full or operation invalid; terrain unchanged`. No evidence of GPU kernel deadlock or ongoing worker queue in that screenshot. A single max-frame value is not a general FPS statistic.

## Confirmed root cause and separate revision/error issue

- `game/scripts/terrain/sdf_brush_edit_state.gd` implements `MAX_EDITS=32`; `add_sphere()` rejects the next command when the **single shared world ledger** reaches 32. Moving the focus does not reset it. `terrain_demo.gd::_accept_brush_at_world` coalesces full-ledger and invalid-input rejection into a single HUD message. This **definitively explains why new carve/fill does not proceed** at the shown 32/32 state. Worker concurrency did not cause this rejection.
- The separate `revision changed before CPU mesh job submission` error is emitted when a region stage snapshot has an older global revision. `_fail_region_stage` stores this as `last_stream_error`; the same path increments load retry counts. Changes in ledger while other regions are loading can make this an **expected supersession** rather than a genuine mesh failure, and that banner may remain after work is complete. The screenshot alone does not prove which requested regions loaded or failed; requires independent focused reproduction and no-stale-mesh tests.
- Owner reported interactive speed now satisfactory with CPU worker optimization. Earlier ~9.93→1.08sec cold window and <76ms measured p95 headless scene commit are developer-attested evidence, not direct GUI GPU measurements. Performance [Issue #93](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/93) remains relevant for preservation, but the new functional blocker is [Issue #94](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/94).

## Corrective work gate before P1.0C merge

- **Issue #94** directs Codex to preserve existing worker speed and improve sustained editing. Target >=256 valid global commands across >=10 regions in the same process (or independently report measured architecture ceiling) with no silent eviction or loss of global min/max order, no weakening seam/negative/normal correctness, and no O(N) regression that destroys click latency. Arbitrarily increasing `MAX_EDITS` without performance and equivalence evidence is insufficient.
- Handle expected revision obsolescence as reschedulable cancellation, not an unrecoverable streaming error/retry-budget exhaustion. Clear resolved errors after successful current-revision completion, preserving true failed-stage diagnosis. Stress 33rd and higher commands, C/R/X, rapid focus reversals, loading neighbor cancellation, 32/64/128/256-command snapshots, unload/reload correctness, and GPU-owner GUI usability.
- Implement in the **existing** PR #92 and Windows workspace `C:\Dev\sandbox-sim-dev`; no extra branch/worktree, no reset/clean and preserve reported `stash@{0}`. Rerun pinned Godot 4.7.2 all tests plus new performance/edge/fault cases, then independent exact-SHA review and owner GUI. **Do not merge PR #92 or PR #87 without separate explicit owner authorization**. Existing docs overlap must be reconciled.
- No disk persistence, networking, multiplayer, native code/backend switch, LOD or protected Hyper-V/ACL/F2-G1 work; five protected holds unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

**Next handoff:** `P1_0C_SUSTAINED_EDIT_CORRECTION_PENDING`.
