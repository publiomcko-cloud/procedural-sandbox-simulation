# Documentary checkpoint — significant-interaction cadence decision

**Checkpoint ID:** `CHK-2026-10-17-CHECKPOINT-CADENCE-DECISION`  
**Event date:** 2026-10-17; local timezone UTC−03.  
**Event type:** owner workflow and documentary-continuity decision.  
**State:** `RECORDED_IN_DRAFT_PR / NOT_INTEGRATED` on PR #85, pending explicit owner authorization for merge.

## Decision

Exact owner's instruction: **"sempre pos merge ou outras interacoes significativas faça checkpoints documentais"**.

Accepted requirement: create immutable dated and discoverable documentary checkpoints after **each verified merge** and after **consequential interactions without code merge**, including authorizations/rejections, changed scope, significant source-review and GUI PASS/FAIL results, architectural decisions, major blockers/corrections and developer handoffs. Distinguish a reviewed or owner-accepted feature from an integrated PR, and an observed new SHA from tested/approved source. Routine conversational acknowledgments need no new document.

## Verified source state at recording

- Repo: `publiomcko-cloud/procedural-sandbox-simulation`.
- Last verified remote `main`: `817fc72cd85d5de66932d2aa722d1b077d55bf92` (merged and owner-approved PR #82).
- Documentation PR [#85](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/85): **draft/open/unmerged** at this recording; working branch `docs/recovery-checkpoint-2026-10-17`, last observed prior head `76650629d163812f5f78f03b64922353724422f1`. Final amended head must be checked live.
- Parallel Codex P1.0A: [Issue #84](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/84), branch `feat/p1-0a-multiregion-spatial-ownership` **observed** at `27b911e32ea396be6c66436542473093123e1b54`, potentially advancing. No source-review acceptance, GUI verification, merge, or new authorization is inferred from this observation.
- No Godot tests were run to validate this documentation-policy decision; all referenced code/test results retain their previous evidence classification.

## Operational consequences and next authorized action

Checkpoint each significant event using the [template](../templates/CHECKPOINT_TEMPLATE.md) and [index](INDEX.md); update `docs/status/CURRENT_STATUS.md` and the decision register when scope changes, and append the changelog for actual merges. Record exact reviewed/merged SHAs, evidence, known limitations and next authorization gate. Preserve prior immutable records.

Do not modify the active Codex workspace (`C:\Dev\sandbox-sim-dev`). Do not merge docs PR #85 or the P1.0A feature without separate explicit authorization; do not start P1.0B/C, network/multiplayer, native addons or F2-G1 host/VM operations under this instruction.

A checkpoint supports reconstruction of *documented logical project state* by a new chat or agent, not restoration of unsaved local changes, credentials or runtime environments. Work continues only when a connected agent is actively engaged; no background automation is created by this policy.
