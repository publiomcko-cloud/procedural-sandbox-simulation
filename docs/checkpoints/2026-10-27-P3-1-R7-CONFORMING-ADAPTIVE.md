# P3.1 R7 conforming adaptive refinement — blocked diagnostic checkpoint

**Checkpoint ID/date and timezone:** `CHK-2026-10-27-P3-1-R7-CONFORMING-ADAPTIVE`; 2026-10-27, America/Sao_Paulo (`-03:00`).
**Event type:** consequential experimental topology/collider blocker.
**Publication state:** recorded on draft PR #149; not integrated.
**Immutable once integrated:** yes. Later source corrections require a new checkpoint.

## Verified repository identity

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Live `origin/main` observed at task start: `5997a76d345f45bf86edfe83f690336391e8be27`.
- R7 isolated worktree: `C:\r7`, branch `bench/p3-1-r7-conforming-adaptive`.
- Prototype source commit: `ae184e9253f052401d54ae107b4428fe315f7c69`, direct parent `0867c0c04b857fae1c71b274b8eac44c6e7dba4f` (R6-V final documentation HEAD). Validated R6-V source is `aef090871a7582ee5254511f55624d60882fa00d`.
- Evidence commit observed before adding this checkpoint: `a871d8900fdbd7f89409cd5a84be6a39db116394`, parent `ae184e9253f052401d54ae107b4428fe315f7c69`.
- PR #149: open, draft, base `bench/p3-1-r6v-cave` at `0867c0c04b857fae1c71b274b8eac44c6e7dba4f`; observed head before this checkpoint commit `a871d8900fdbd7f89409cd5a84be6a39db116394`. This checkpoint is an additive commit on that same PR.
- Related PRs #129, #141, #143, #144, #146, #147 were verified open/draft/unmerged; no merge occurred.
- Other worktrees, `C:\Dev\sandbox-sim-dev`, both stash entries, the three pre-existing untracked P1.1B UID files, and previous R6/R7 evidence were preserved.

## Decision and approval ledger

- Issue #148 authorizes isolated R7 test-only A/B/C research. It does not authorize production changes, geometry-contract adoption, schema modification, merge, Issue #108, or F2-G1 operations.
- No product architecture or tolerance was accepted by this event. Production remains anchored to reference SHA `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- No owner GUI claim or merge authorization is made.

## Evidence ledger

- **L1 parser:** Godot `4.7.2.stable.official.ed1daf0bf`, binary SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`. Both test-only scripts passed separate `--check-only` runs with exit 0 and empty stderr.
- **L2 focused test:** exactly one final zero-edit preflight; exit 1, 7,086 ms, 8 assertions, 4 failures. The canonical opening was 1.75; all three A/B/C meshes had 14 internal open edges; the disposable concave proxy had 33 directional ray hit/miss mismatches. Full metrics and raw logs are in [R7 report](../reports/P3-1-R7/RESULTS.md) and `docs/reports/P3-1-R7/evidence/`.
- The run also reports 31/31 canonical centerline field probes open and 31/31 picker classifications equal, but does not measure mesh cave connectivity or separate shared-interface scalar/finite-difference gradient jumps. These properties remain unverified.
- **L2 full validation:** `scripts/validate.ps1` on an isolated tracked-source archive at `0867c0c04b857fae1c71b274b8eac44c6e7dba4f`, with a temporary project-name change solely to isolate Godot user data: exit 1, 21,458 assertion-marker checks, 5 failures in `P3_0D_PLACEMENT_FAIL`; other 20 suites passed. This was not an R7 prototype suite and no user saves were accessed.
- **Inherited R6-V evidence:** the parent report documents coarse interpolation widening the cave to 4.875 and canonical fine-boundary sampling producing a 0.153837 shared-density gap. The frozen source and logs are preserved in the R6-V report; they are not replaced by this zero-edit R7 preflight.
- No GUI, presented-frame/GPU, production collider, streaming/restart, edited-cave, persistence, or broad performance campaign ran under R7.

## Architecture and recovery

- A: uniform refinement closure over the bounded connected patch; 1,920 cells, propagation radius 9.
- B: 771 initially selected fine cells and 480 transition cells using shared canonical fine-face samples.
- C: one-cell face-neighbor halo, 1,251 fine cells and 126 transition cells.
- All have explicit caps: 64-cell radius, 12,000 refined cells, 16 MiB fine payload, 250,000 triangles.
- All three outputs contain 7,118 triangles and identical position/normal digest, but each has 14 internal open edges in cell IDs 1101, 1149, 1150, 1199. No cause in tetrahedron extraction or near-zero ownership has yet been proven.
- Collider proxy results do not establish a production collision behavior. Its reverse-direction misses and sphere-contact offset remain unresolved.
- Edited scenarios `cave_wall_carve` and `center_fill_then_wall_carve` were not started because the zero-edit topology/collider gate failed. The R7 driver now defaults to the zero-edit preflight and requires explicit opt-in for edited scenarios; it stops after a failing preflight.
- Next authorized engineering step: isolate the four near-zero open-edge cells and the directional proxy discrepancy in bounded test-only fixtures, then rerun only zero-edit gates. Edited cases can be considered only after a fresh zero-edit pass. No production change or R7 adoption is implied.
- Checkpoint, status, index, report, specification, prototype sources, raw logs, and their checksum inventory are included on the draft PR. `CHANGELOG.md` and `DECISION_REGISTER.md` are unchanged because no merge or accepted decision occurred.

## Event significance and disposition

The experiment answered the gate question with a reproducible failure: the three refinement policies do not currently satisfy extracted-mesh topology and collider-proxy preflight requirements. This materially stops the planned edited-cave and broad measurement phases. Verdict: `P3_1_R7_BLOCKED_WITH_EVIDENCE`.

Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
