# P3.1 R9.6-A — Candidate A Corrective Disposition

Date: 2026-10-29

Issue: [#196](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/196)

Status: **P3_1_R9_6_BLOCKED_WITH_EVIDENCE**

## Exact candidate and scope

- R9.6 branch baseline / prior Candidate A evidence HEAD: `b41dc7207fae3911ecd7b082850535b7e965db5b`.
- Measured Candidate A source commit: `f0c93415dd56886a1c05ff2e6a1340e420f22c59`; its candidate implementation parent is `d5903242e41642a2633e18dc181c4389188c65b2`.
- Candidate implementation blob: `5a19b05d3f39108e53c8b7ff47d28303ee7bfbb0`.
- Physical SHA-256: `970fe99f192ea2a3fea3e682072ed3562e6f57c843561dd4440e46381a384d8a`.
- Frozen R9.2 manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.
- Cutoff unchanged: `cross_squared > 1e-12`.

This R9.6 branch changes no Candidate A implementation, field, root identity, exact-zero endpoint behavior, frozen input, cutoff, production source, or user data. It records why the corrective campaign could not safely start.

## Attempt ledger

**Implemented geometry attempts: 0/3.** No candidate correction hypothesis was executed or consumed. The shared topology-ledger artifact is in the separate R9.6 oracle worktree/PR and is diagnostic-only; it is not an A correction.

| Attempt | Pinned candidate source | Hypothesis / implementation | Result |
|---|---|---|---|
| None | N/A | No A source revision was made. The engine import gate failed in the shared R9.6 environment before candidate geometry execution. | `CENSORED` before Attempt 1; 0 attempts used |

## R9.5 evidence carried forward (not a new R9.6 run)

The independent R9.5 oracle attributed A's X+ internal openings to seven triangles rejected at the frozen cutoff. The 6-edge cutoff-created loop has diameter `0.0038049191`; exhaustive triangulation over the existing loop vertices had best achievable minimum cross² `1.18455592557076e-14`, below `1e-12`. Therefore a cap using only those vertices cannot meet the cutoff. This does not rule out a larger local patch, subdivision, SDF-derived Steiner points, or a separately owned interface.

R9.5 reported equal-LOD X+ contours matching as segment sets, but the candidate's full ROI still had 8 internal opens. The mixed-LOD proxy remained mismatched (10 candidate segments vs 22 expected on the respective faces); it had no actual transition surface. The corrected 25-ray ROI oracle was 0/25 hit/miss disagreements. Ray distance remains descriptive and unscored.

No R9.6 before/after geometry, root residual, normal, winding, CPU, ray-distance, or validation result exists because no A attempt began. R9.4 full validation is not a validation of an R9.6 correction.

## Gate and next action

Godot 4.7.2 editor import crashed three times on the shared topology-contract source with `-1073741819` and `Parameter "mem" is null`; a subsequent focused-script launch could not capture a process because PowerShell reported memory exhaustion. The host snapshot showed only 89,908 KB free virtual-memory commit, with `vmmemWSL` at 26.19 GB private bytes. See the shared R9.6 oracle report and raw logs for exact PIDs, command identities, hashes, and the environment correction.

Do not classify A as `EXPERIMENTAL_GEOMETRY_TARGET_PASS`. It remains `BLOCKED_WITH_EVIDENCE` on inherited X+ geometry and mixed-LOD targets, with its R9.6 corrective campaign censored by the host gate. Resume only after the owner environment has adequate commit headroom: run the shared oracle tests, then pin and execute A Attempt 1 topology-first. If it records connectivity but cannot emit valid geometry, classify `PARTIAL` and proceed to SDF-constrained local refinement only under a preregistered numerical residual rule. Never relax the cutoff.

No production integration or approval is requested. The five F2-G1 holds remain unchanged.
