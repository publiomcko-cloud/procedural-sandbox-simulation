# P3.1 R9 — Immutable preregistration checkpoint

**Checkpoint ID/date:** `CHK-2026-10-28-P3-1-R9-PREREGISTRATION`, 2026-10-28

**Repository:** `publiomcko-cloud/procedural-sandbox-simulation`

**Common source base:** `4f08b67522507bd196a74a1089c773f272235343`

**Contract branch:** `bench/p3-1-r9-preregistration`

**Issue:** #169

## State at preregistration

The R9 experiment contract was frozen before any R9 candidate implementation or execution. The authoritative contract is [P3.1 R9 Four Architecture Prototypes](../specs/P3-1-R9-FOUR-ARCHITECTURE-EXPERIMENT-CONTRACT.md). The frozen nine-case JSONL manifest is `game/tests/prototypes/p3_1_r9_frozen_inputs.jsonl`; SHA-256 `2b44cb52ef091c2527fa2f8b06859752cc7cfaa14bcafe94d4a4c55b0cdd908f`. It is pinned as physical bytes, UTF-8 without BOM, LF, with `-text` in `.gitattributes`. Historical R8.2 zero/CARVE/FILL-CARVE input hashes and the baseline source file blob/physical SHA pins are embedded in the contract.

The contract defines the same canonical SDF v1 source, seed, operation order, coordinates, region/chunk/LOD fixtures, geometry measurements, deterministic local edit recipe, per-candidate gates, and bounded stop-loss for A/B/C/D. It keeps geometry quality descriptive unless an exact structural/connectivity invariant applies; it does not invent a product tolerance. PhysicsServer, rendered GUI, GPU and presented-frame results are not implied by CPU prototypes.

The candidate implementations and results had **not** begun at this checkpoint. This checkpoint is a design/input freeze, not a candidate PASS or geometric acceptance.

## Independent evidence reconciliation

R8.4 PR #168 is preserved unchanged. Its report/checkpoint text says 20 suites / 14,990 assertions, but independent review #5686141541 found the raw full-validation marker `LOD01_TRANSITION_PASS: assertions=6474 failures=0`; the reconciled total is 21 suites / 21,464 assertions / zero failures. R8.4's own bounded X+ candidate nevertheless failed with nine unmatched interfaces and 58 internal open edges, and downstream gates were not run. This does not establish impossibility of all conforming-transition methods. The R9 report must use the corrected test total and retain the R8.4 geometry failure as historical evidence.

## Repository preservation and authorization boundary

At preflight, `C:\r84` remained on R8.4 HEAD `ddcdfb2f3c8c7527b8d712d76e333efdd4497732` with only its existing untracked `.gd.uid` files. `C:\w82` remained on the common source baseline with prior untracked generated profiles and `.gd.uid` files. Both stashes were preserved: stash@{0} P3.0C work and stash@{1} P1.0B work. The functional development worktree `C:\Dev\sandbox-sim-dev` was not modified. PRs #162/#165/#166/#168 and their branches were not modified. No user save, production code, schema, Issue #108, native dependency or protected F2-G1 state was accessed.

All five holds remain exactly: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
