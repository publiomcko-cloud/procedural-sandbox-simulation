# 2026-11-11 — P5 streaming E2 coarse-first experimental candidate

**Significant interaction:** owner explicitly authorized "execute e2" after E1.1 cached dependency scheduling yielded 83.1% cache-hit frames and still did not conclusively improve median definitive loading. E1.1 remains unaccepted. E2 is a separate branch from the optimized `adaptive-skip` parent, not from E1.1.

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Verified-at-creation `main`: `2dca19d125309f3b70c858df1acdf22324c31c17`
- Exact experimental base: `f6fbfa844ebf283ad9ff83684e4018f0c3faf1bd` on `exp/p5-0f-adaptive-stream-budget`
- Feature: `exp/p5-stream-coarse-first-e2`; [draft PR #284](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/284)
- Candidate after initial PowerShell qualification syntax correction: `266ee118a64ee07b0853b78d043ad9d6289ccbf2`
- First test workflow at `00970e470d761dce8ceb6d8bc6c5d522791480ef`: [run 43103381367](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43103381367), **FAIL** due to PowerShell 5.1 multiline `if` statement parse, before Godot; no claim about runtime correctness
- Corrected workflow: [run 43103571456](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43103571456), **IN_PROGRESS at record creation**, not a PASS

## E2 architecture and limits

Dedicated opt-in `adaptive-skip-coarse` profile retains adaptive-skip's definitive 16-chunk stage, worker budgets, SDF-effect snapshot checks, object publication and water/simulation authority without alterations. A single lower-priority worker computes a deterministic 8×6 heightfield (96 triangles) for *pristine* visible LOAD regions; no preview mesh/node is created on worker. Each preview is strictly presentation-only, not active terrain, not collision, not pickup/placement, not object/physics/simulation state, not persisted. Source world seed, version, stage token, brush revision, object authority revision and current 3×3 membership gate both initial view and retention. A stale preview is revoked; a definitive 16-chunk publication replaces it only after canonical mesh commit.

E2 intentionally **does not** display preview for any world containing brush edits, during edit transaction/full rebuild/cave cutaway, or for active/partial stages. Its visual surface may not match caves, procedural SDF object effects, water shorelines or other non-base geometry until definitive load. This is a review gate, not a fidelity guarantee.

Separate metrics for provisional first visual, provisional replacements/revocations, provisional CPU time and perceived F10 gaps are recorded. Historical F10 missing-region metrics remain *definitive-only*. User must compare aligned A/B routes with `adaptive-skip` and `adaptive-skip-coarse` at 18 m/s and 54 m/s, including visual underwater/ocean checks.

## Evidence state and next action

Published source and tests are GitHub-verifiable (L0/L1); candidate Windows self-hosted Godot 4.7.2 CI is pending (not L3 PASS). No GUI test or benchmark at E2 head has been performed or reported. No merge into `main` or the parent is authorized. Acceptance requires valid main-scene parse, focused 96-triangle/revision negative tests, **real-scene** coarse publication smoke, complete P5/P4 inherited qualification and owner's visual comparison. If a correction is needed, preserve this immutable checkpoint and append another dated record rather than editing it.
