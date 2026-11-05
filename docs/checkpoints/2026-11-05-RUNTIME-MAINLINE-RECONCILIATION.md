# 2026-11-05 — Runtime mainline reconciliation and owner merge authorization

## Scope

This checkpoint records the owner's decision to stop treating the older P3.1 R12-CXR/R6 research line as the active development path and to promote the current playable runtime line as the project mainline candidate.

Repository: `publiomcko-cloud/procedural-sandbox-simulation`

Pre-merge live refs verified on 2026-11-05:

- `main`: `5997a76d345f45bf86edfe83f690336391e8be27`
- candidate branch: `feat/free-exploration-mode`
- accepted runtime source HEAD: `314edceb618e537b6d7a249330a854aca3113010`
- previous runtime-hardening source HEAD: `20c3745cbe1d4349841d8ce14b240926303e0c40`
- comparison: candidate is 203 commits ahead of `main`, 0 behind; merge base is exactly the verified `main` SHA.

This checkpoint is created on the candidate branch before integration. The actual merge SHA must be verified from GitHub after the merge and recorded by the post-merge receipt.

## Accepted runtime state

The candidate line consolidates the playable/runtime work that replaced the old practical bottlenecks:

- scalable materialized SDF terrain editing and persistence;
- shared-surface boundary runtime work used by the playable candidate;
- localized and revision-safe terrain remeshing;
- runtime hardening for immutable mesh CPU data, allocation-reduced materialized sampling, bounded worker publication and persistence;
- event-driven LOD selection;
- asynchronous procedural-object generation/geometry preparation;
- entity command/history persistence and visual publication fixes;
- edit tracing disabled by default and opt-in for profiling;
- F10 free-exploration mode with captured mouse look, WASD/arrow flight, Space ascent, Shift descent, Ctrl boost and complete HUD/placement-marker suppression while active.

The free-exploration mode does not disable terrain editing. Left-click editing remains available through center aim while the cursor is captured.

## Automated evidence at accepted source HEAD

GitHub Actions run `42117264773` completed successfully on `314edceb618e537b6d7a249330a854aca3113010`:

- `FREE_EXPLORATION_MODE_PASS: assertions=17 failures=0`
- `TERRAIN_LOD_RUNTIME_PASS: assertions=55 failures=0`
- `RUNTIME_SCALABLE_PLAYABLE_PASS: assertions=33 failures=0`
- `VALIDATION_PASS: L0-L2; GUI visual test remains an owner task`

Starter checks run `42117264811` also completed successfully.

The canonical repository validation entrypoint for current work is `scripts/validate.sh` with Godot 4.7.2. Historical references to `scripts/validate.ps1` remain historical evidence only and must not be used as current instructions.

## Owner GUI acceptance and decision

On 2026-11-05 the owner tested the candidate locally and reported:

- free exploration works;
- terrain can be edited while exploring;
- no perceptible lag was observed in that test.

The owner then explicitly directed that the older branch/research line that stopped at R6 be abandoned as the active path, that this runtime candidate become the principal development line, that the documentation be reconciled, and that the candidate be merged into `main`.

This is explicit merge authorization for the reconciled candidate. It does not retroactively convert old experimental R6/R12 results into production acceptance.

## R6/R12 disposition

The P3.1 R12-CXR experimental chain is superseded as an active development path. Its branches, commits, reports and evidence remain historical research artifacts and must not be deleted or rewritten.

After the runtime mainline merge is verified, the still-open draft PRs belonging to the R12-CXR R1–R6 chain should be closed as superseded rather than merged. Closing them is repository hygiene, not a rejection or erasure of their recorded scientific evidence.

Do not resume the R6/R12 campaign unless the owner explicitly reopens that research direction.

## Current operating rule

After integration, new functional work starts from live `main`, not from the R6/R12 experimental chain or the pre-integration storage baseline.

Always verify live refs before acting. Historical checkpoint text below the new 2026-11-05 status layer remains immutable evidence for the state that existed when it was written.
