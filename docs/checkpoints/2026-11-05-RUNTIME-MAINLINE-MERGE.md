# 2026-11-05 — Runtime mainline merge and R6/R12 closure receipt

## Verified integration

Owner-authorized runtime mainline PR #228 was merged into `main` on 2026-11-05.

- PR: #228 — `Promote accepted runtime line to main`
- accepted runtime source HEAD: `314edceb618e537b6d7a249330a854aca3113010`
- reconciled PR HEAD: `843f7603d88c1492c2a4bb96e4567c5b98be1831`
- pre-merge `main`: `5997a76d345f45bf86edfe83f690336391e8be27`
- verified merge commit: `f646a3b1b5d22ee443adb12d7b77634ef4528f17`

The candidate was 209 commits ahead of the pre-merge `main`, 0 behind, with that exact `main` SHA as merge base.

## Merge gates

Before merge, GitHub reported PR #228 as mergeable and clean. The following HEAD-specific checks passed:

- Starter checks push run `42129570989`: SUCCESS.
- Free exploration qualification push run `42129570845`: SUCCESS.
- Starter checks pull-request run `42129617089`: SUCCESS.
- P2 GDScript allocation benchmark pull-request run `42129617222`: SUCCESS.
- `FREE_EXPLORATION_MODE_PASS: assertions=17 failures=0`.
- `TERRAIN_LOD_RUNTIME_PASS: assertions=55 failures=0`.
- `RUNTIME_SCALABLE_PLAYABLE_PASS: assertions=33 failures=0`.
- canonical `scripts/validate.sh`: PASS.

Owner GUI acceptance immediately preceding integration reported free exploration, simultaneous terrain editing and no perceptible lag.

## Active mainline

The runtime/performance line is now the active project baseline. New functional work must start from live `main`.

This mainline includes the scalable/materialized SDF runtime, persistence, shared-surface playable integration, localized revision-safe remeshing, runtime hardening, asynchronous procedural-object generation/geometry preparation, entity command/history fixes, event-driven LOD work and F10 free exploration.

Current canonical validation remains Godot 4.7.2 through `scripts/validate.sh`.

## R12-CXR R1–R6 disposition

After the merge was verified, the obsolete active research chain was closed as superseded, not rejected:

- PR #213 — R12-CXR R1 architecture-convergence controls
- PR #214 — R12-CXR R3 per-cavity continuation
- PR #215 — R12-CXR R3-A/R3-B partial implementation evidence
- PR #216 — R12-CXR R4 boundary-first realizer evidence
- PR #217 — R12-CXR R5 constraint-guided field support synthesis
- PR #219 — R12-CXR R6 realization-map cavity search
- PR #220 — R6 D finite-search evidence
- PR #221 — R6-06 finite graph result and raw evidence
- PR #222 — R6-X6 partial result and raw evidence

Each closure records that the branch, commits, reports and raw scientific evidence remain preserved. No branch or evidence was deleted.

The R6/R12 line must not be treated as active work or merged into the runtime mainline unless the owner explicitly reopens that research direction.

## Continuity rule

The repository, current live `main`, this receipt and the current status documents supersede older “candidate”, “hold”, or “do not merge” instructions when those instructions refer to earlier functional/runtime baselines. Historical records remain valid only for the state and scope they describe.

Protected F2-G1 security/host-operation constraints remain separate and are not changed by this runtime merge.
