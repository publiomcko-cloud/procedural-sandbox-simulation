# P3.1 R9.6R1 — Controlled Recovery and Geometry Attempt 1 Results

**Disposition: `P3_1_R9_6R1_BLOCKED_WITH_EVIDENCE`**  
**Scope:** test-only; no production, persistence schema, user-save, release, Issue #108/#154, or protected-host changes.

## Executive result

The runtime gate recovered on pinned Godot 4.7.2. The corrected shared topology suite executed 50 assertions with zero failures. Candidate A and D each completed one topology-first geometry attempt, but neither met the frozen geometry target. Both retained internal open edges and cutoff-rejected triangles; their mixed-LOD contours remain disjoint. No second geometry attempt was made because a bounded SDF-constrained refinement that preserves the existing cutoff and conforms to neighboring interfaces was not established. Full E2E and `scripts/validate.ps1` are therefore not reported as passes and were not run on a surviving candidate.

## Provenance and scope

Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.

| Work | Base / tested source | Published head | Notes |
|---|---|---|---|
| R1 recovery | PR #197 head `db748c8b987bf0007610daa9120697211bace46b` | `0f8cfcdc64ef43096ff9f6166d17605bb1c13aec` | Parent `ef728877b2fe3899fde0b233fe0a94bb8f88b2ec`; two topology helper/test paths only; PR #202 |
| Candidate A execution | `bf230c4916c66e2150f8725480d8ce3ca589b353` | `224f2e9ef650f103736f84451dc849f3ab3e94e6` | Parent `0f8cfcdc64ef43096ff9f6166d17605bb1c13aec`; tracked tree matches execution tree `74a865e4fc6e11fa7cba4b8a9c8a073d04207bae`; PR #203 |
| Candidate D execution | `7115166067b7f6e9c68dd9425981259ae065c5bc` | `731033f37b44414e17202e73457e9584a99364d8` | Parent `0f8cfcdc64ef43096ff9f6166d17605bb1c13aec`; tracked tree matches execution tree `7ddb998dd487bba3010717ce75646b5255c0b8b5`; PR #204 |
| Consolidated report | PR #200 head `1f7a9a575df42add40a38e65d3e1ecfb88ceba31` | See this report PR | Docs and evidence only; PR #205 |

The executed source commits and published candidate PR heads differ as commit objects, but each published commit has the same complete tracked tree as its measured source. No `UNPINNED_WORKTREE` run is claimed. Candidate C stayed frozen; Candidate B stayed out of scope.

Frozen manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`. Godot binary SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`; version output: `4.7.2.stable.official.ed1daf0bf`.

Physical source SHA-256 values are in [SOURCE-SHA256SUMS.txt](SOURCE-SHA256SUMS.txt); selected raw process logs and candidate topology JSON are in `evidence/`. For D, the executed LF worktree file hashes to `37CF20740511EC6ECB927850F182BC333173F2F1771449E484427EFE6D8E8A98`, while the published worktree file hashes to `A0A5001422C95EEA7D1B323C48F79FEE3A8815D3309EA19E602404F296AE748F` because `core.autocrlf=true` checked out CRLF there. Both commits resolve the candidate path to the same Git blob `9a10fbb6cf979c35e51677f4106c2f193a2f9a24`, and LF-normalized bytes compare equal. Thus Git source identity and semantics reconcile; the raw working-tree byte hashes are explicitly distinct. The complete 525-file local evidence-root inventory is in [LOCAL_EVIDENCE_ROOT_SHA256SUMS.txt](LOCAL_EVIDENCE_ROOT_SHA256SUMS.txt). The original root remains at `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R96R1_20261029_1217Z_0fbfecd9baea4e8ba9bbf4cee419a3d2` and is retained unchanged apart from this report being stored elsewhere.

## Memory discrepancy and host evidence

The prior comparison report says approximately **89,908 KB** free virtual memory. No retained authoritative source for that number was found; classify it as `UNSUPPORTED_HISTORICAL_RESOURCE_VALUE` and do not repeat it as a measurement. The committed R9.6 `resource-snapshot.json` reports WMI `FreeVirtualMemory=8,702,612 KB` and `TotalVirtualMemory=74,037,908 KB`. Those WMI values are not Windows commit charge/limit measurements. The discrepancy is reconciled as a reporting error/unsupported historical value, not evidence of commit exhaustion.

A retained Windows Resource Exhaustion Detector Event 2004 at `2026-10-29 08:14:40 -03:00` reports a low-virtual-memory warning and high consumption by `vmmemWSL` and other applications. It does not identify the cause of the earlier whole-PC freeze. The owner-reported freeze remains exactly `HOST_FREEZE_OBSERVED_UNKNOWN_ATTRIBUTION`. No process, WSL instance, pagefile, service, or owner application was terminated, restarted, suspended, or reconfigured. A later bounded-event query found no System 41/6008 record in the queried 12-hour window; this does not prove that no other event exists.

Immediately before A at `2026-10-29T13:24:56Z`, the captured OS-native snapshot showed 24.26/63.84 GiB physical RAM available, 83.82% commit use, 11.83/73.11 GiB commit headroom, 120.58 GiB free on both project and TEMP volumes, and WSL running. Before D at `13:17:18Z`, it showed 23.85/63.84 GiB available, 84.17% commit use, 11.58 GiB headroom, and 120.88 GiB disk/TEMP free. The recorded pagefile was not automatic-managed: `C:\pagefile.sys`, configured 1,000–10,000 MB, allocated 9,487 MB; current use was 1,243 MB before A and 1,135 MB before D. These snapshots met the runner's bounded launch gates. They do not establish the cause of the earlier freeze or any historical commit exhaustion.

The A and D runs were serial, with no concurrent candidate campaign. No new freeze occurred during these bounded runs.

## Engine and topology gate

The executable hash and `--version` output were verified. The standalone version probe's process PID was not captured in its process record; its binary identity is independently verified by SHA-256. The known-good source import at `895dbca3c6dd58bb9adacd63fb39c3ad524226ff` completed with exit 0. The corrected R9.6 source import at `0f8cfcdc64ef43096ff9f6166d17605bb1c13aec` completed with exit 0 (process 28748). The direct topology test completed with exit 0 (process 41492) and printed:

```text
R96_TOPOLOGY_TESTS {"assertions":50,"failure_reasons":[],"failures":0}
R96_TOPOLOGY_TESTS_PASS
```

The executed count is 50, not the older static site count of 38. Test corrections include explicit typed arrays, the correct ROI boundary perimeter, and a delimiter-safe root-edge key separator so root IDs containing `|` do not collide. Helper and test file hashes are pinned in the source checksum inventory. The topology gate is `TOPOLOGY_GATE_PASS`.

## Candidate outcomes

| Candidate | Preflight | Geometry process | Controls / ray oracle | X+ equal LOD | X+ mixed LOD | Disposition |
|---|---|---|---|---|---|---|
| A | Import 0; `--check-only` 0 | PID 8808; exit 0; 5.97 s; stderr empty | 6/6 controls pass; root identity pass; 0/25 ROI hit/miss disagreements | Full/left ROI: 8 internal open edges, 7 triangles rejected by unchanged cutoff, 15 required adjacencies missing | 10 left / 22 right segments, no shared segments | `PARTIAL`; target fails |
| D | Import 0; `--check-only` 0 | PID 32072; exit 1; 5.60 s; stderr empty | 5/6 controls pass; negative-region X strict mesh-hash control fails; 0/25 ROI hit/miss disagreements | Full ROI: 13 internal open edges, 8 triangles rejected by unchanged cutoff, 19 required adjacencies missing | 10 left / 22 right segments, no shared segments | Target fails |

Both runs preserved `cross_squared > 1e-12`. The independent root identity probes passed. The ray result is ROI-scoped only and makes no PhysicsServer claim. A's process exit 0 and `failure_count=0` mean the harness completed without counted assertion failures; the emitted status was `ATTEMPT_1_TOPOLOGY_FIRST`, and the geometry artifacts explicitly say realization is incomplete. This is not a geometry PASS. D's exit 1 and seven failures are retained as candidate failures.

Frozen prior cave and neighbor controls passed on A. D preserved those controls except the negative-region X strict hash case. Neither result satisfies the experimental target because equal-LOD topology is incomplete and mixed-LOD boundaries mismatch.

## Attempts, validation and stop decision

- `A_ATTEMPTS_USED=1/3` — topology-first attempt 1 was actually executed. Earlier parser/diagnostic failures produced no geometry and are retained as non-geometry recovery records.
- `D_ATTEMPTS_USED=1/3` — topology-first attempt 1 was actually executed. Earlier root-identity/delimiter diagnostic failures produced no geometry and are retained as non-geometry recovery records.
- A2/D2 SDF-constrained local refinement and A3/D3 face-owned interface patches: `NOT_RUN`.
- Full frozen E2E and `scripts/validate.ps1`: `NOT_RUN`. The contract runs these only for a final surviving candidate; neither candidate survived attempt 1. No validation PASS is implied.

The next technical step is to extract the actual failing cell/face patch and design bounded SDF-constrained refinement with conforming ownership at its coarse/fine boundary. It must preserve the current degeneracy cutoff, existing passing controls, exact-zero root identity, and the 0/25 ray oracle. No such correction was source-implemented or measured in this recovery, so continuing to another geometry run would be speculative. The candidates are blocked, not accepted; remaining attempts are available for a separately reviewed correction.

## Evidence completeness and protections

- Evidence root: 525 files, 117,277,198 bytes; full local SHA-256 inventory is provided. 65 selected raw output/process/artifact files (8.03 MiB) are included here; host snapshots and the full historical package remain in the owner-local root and are hash-listed, not publicly duplicated.
- Exact stdout SHA-256: topology test `4b5f49a96064b6d1c4a445ed3871cd100901d65ac3df8d2655621b6053b36271`; A run `13b75eb994a730f2260c45b9258b99434f434cff162454117e950765ba737fa5`; D run `23705bb259e0995fa431818099750593265aabfb63f047558b7ed0f77b4dab4c`. All three stderr files are empty (SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).
- Owner worktree `C:\Dev\sandbox-sim-dev` remains at `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` on `feat/p3-1-scalable-terrain-storage`; exactly three pre-existing untracked `.gd.uid` files remain; `stash@{0}` and `stash@{1}` remain unchanged.
- PRs #197–#200 remain open, draft and unmerged. New PRs #202–#205 are separate drafts. No production, schema, save, merge, release, Issue #108/#154, or F2-G1 action occurred. The five F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

**Final status:** `P3_1_R9_6R1_BLOCKED_WITH_EVIDENCE`.