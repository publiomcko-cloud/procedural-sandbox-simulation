# P3.1 R12-C topology-to-geometry campaign results

Date: 2026-10-30
Repository: `publiomcko-cloud/procedural-sandbox-simulation`
Origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
Branch: `exp/p3-1-r12-c-topology-geometry-realization`
Evidence root: `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r12c_20261030_0a53ac9c6d5245f4a4faffb14089c8be`
Evidence archive: `docs/reports/P3-1-R12-C-CAMPAIGN/evidence/r12c_raw_campaign_evidence.zip`

## Disposition

`CAMPAIGN_STATUS=P3_1_R12_C_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`

Stage 0 was reproduced. C1 was `NOT_APPLICABLE_NO_ELIGIBLE_INTERIOR_DEGREE2_ROOTS` and remains unconsumed. C2 through C6 each reached the frozen realization algorithm, emitted a complete classified target artifact, and were consumed as `FAILED_TARGET`. No authorized C slot remains. This is a finite experimental result; it does **not** prove mathematical impossibility or authorize production adoption.

The frozen qualification cutoff remained `cross_squared > 1e-12`. C6 improved the topology mapping and reduced remaining cutoff rejects from eight (C4) to three, but still fails the cutoff. No mixed-LOD, deterministic repeat, full E2E, gameplay, GPU, or `scripts/validate.ps1` campaign ran because the equal-LOD gate did not pass. This is the required fail-closed gate order, not missing execution after a passing candidate.

## Frozen source and execution environment

| Input | Verified identity |
|---|---|
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| Godot executable SHA-256 | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |
| Candidate D source SHA-256 | `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a` |
| Frozen R9.2 manifest SHA-256 | `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` |
| Stage 0 topology fixture SHA-256 | `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d` |
| Frozen target | `R9.2.SEAM.XPLUS_EQUAL.v1`, seed `131102026` |
| Frozen topology SHA-256 | `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95` |
| Frozen graph fingerprint SHA-256 | `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9` |
| Frozen Candidate D volume SHA-256 | `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` |
| Frozen payload SHA-256 / revision | `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0` / `2` |
| Cutoff | `cross_squared > 1e-12` |

The campaign used the isolated worktree `C:\r12c-20261030`, branch `exp/p3-1-r12-c-topology-geometry-realization`. The original development worktree, R10-BX worktree, user saves and protected F2-G1 state were not modified. Godot user data was redirected into the evidence root's `profile` directory. Stage monitoring recorded the launcher and Godot PIDs separately and sampled global free commit.

## Stage 0 and C1

Stage 0 contained 369 roots, 870 arcs, 502 source polygons, and reproduced the exact frozen topology/graph hashes above. The target component contained 73 roots, 84 polygons and 156 arcs; its boundary had 34 roots and interior had 39. The only degree-2 roots were boundary roots, so the preregistered C1 eligible interior degree-2 set was empty. C1 is `NOT_APPLICABLE`, not a failed or passed geometry realization, and was not consumed.

## Attempt matrix

All physical source SHA-256 values below were independently recomputed from Git blob bytes at the recorded commit and match the runtime self-report. Blob identities are recorded in `source-identities.json`.

| Slot / attempt | Source / parent / tree | Realization | Source SHA-256: campaign / realizer | Map / round-trip SHA | Geometry and required gates | Disposition |
|---|---|---|---|---|---|---|
| C1 | Stage 0 | Degree-2 interior path events | — | Stage 0 graph `a5dd1182…` | No eligible interior degree-2 roots; no geometry run | `NOT_APPLICABLE`, unconsumed |
| C2 / `C2GEO006` | `f5b421a0f0e4a020a7fc1a8d00847a8e32f93234` / `d936203c5b769c0c022699d6ad5fad12a85b6e40` / `27f21a7279bde20f08a7141ff03f729e4599bb29` | Graph-face anchor-cycle | `36a7ae8e…` / `656e558e…` | Map `64cddc36dce07dc71fe09f7eaab12909c6140ba956a1bc1fc35c44f645b6a236`; topology round-trip `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9` | 369 anchors, 870 arcs, 502 faces, 654 triangles; 8 cutoff rejects; 19 missing arc obligations; 13 internal opens; nonmanifold/winding/degenerate 0/0/0; controls 4/6; ROI rays 0/25; volume PASS | `FAILED_TARGET`, fixed cutoff/topology |
| C3 / `C3GEO001` | `e9bc9637a9aeadefc4385959c7ff2cf786c35997` / `1edb73316876e20a20367c4c88de8b20689eb8f5` / `ffc460cf507f083ce8cd6f62e39074ac2f6973ee` | Per-face field-constrained support fan | `e2981b34…` / `8b8e818f…` | Map `fbe6e385…`; round-trip `a5dd1182…` | 369 anchors, 502 support vertices, 870 arcs, 502 faces, 1,621 triangles; 45 cutoff rejects; 33 missing obligations; 20 internal opens; nonmanifold/winding/emitted-degenerate 0/0/0; controls 4/6; ROI rays 0/25; volume PASS | `FAILED_TARGET`; cutoff/topology, controls |
| C4 / `C4GEO001` | `01856f529df0a0f8c0bf62be5684d86fd923d071` / `db130481d79b5ad88fc3e705695bb1530cfadd61` / `1b361cd8ab0fc4502605956710560abc81939d6e` | Exact-coplanar local 2–2 flip | `a904b9ac…` / `1dcdf7d1…` | Map `7c713782…`; round-trip `a5dd1182…` | 369 anchors, 870 arcs, 502 faces, 662 triangles; 18 candidates all rejected as noncoplanar; 0 flips; 8 cutoff/degenerate faces; internal opens/missing/nonmanifold/winding 0/0/0/0; controls 6/6; ROI rays 0/25; volume PASS | `FAILED_TARGET`, fixed cutoff |
| C5 / `C5GEO001` | `40ee966d1cda2ccf5ef42f5e747083d022849fbc` / `95d8477cd180fd760571643859d024f63361b41d` / `59d18abac9aa69d592c816028d35f790521e50d3` | Face-owned noncoplanar local 2–2 patch | `c2ea5a8b…` / `0c053bee…` | Map `96d71021…`; round-trip `a5dd1182…` | 369 anchors, 870 arcs, 502 faces, 662 triangles; 4 flips; 4 cutoff/degenerate faces; internal opens/missing/nonmanifold/winding 0/0/0/0; controls 6/6; ROI rays 0/25; volume PASS | `FAILED_TARGET`, fixed cutoff |
| C6 / `C6GEO001` | `4535f4c965db67adab7c93e448492c54be916c92` / `289feddccc5a71bd8f9d1f5ff66051d8d4140657` / `1c8af8c4050a7b89976331fa1ad20c666d67e3a8` | Multi-face noncoplanar local 2–2 patch with independent arc-owner mapping | `9a695705…` / `31947e19…` | Map `e7cf00e1…`; round-trip `a5dd1182…` | 369 anchors, 870 arcs, 502 faces, 662 triangles; 5 flips; 3 cutoff/degenerate faces; internal opens/missing/nonmanifold/winding 0/0/0/0; controls 6/6; ROI rays 0/25; volume PASS | `FAILED_TARGET`, fixed cutoff |

The abbreviated hashes in the summary table are expanded in `source-identities.json`. [`attempt-matrix.json`](attempt-matrix.json) provides the complete per-attempt field set required by the R12-C report contract, including control case results, process IDs/exit status/log hashes, cutoff rejection details, ray scope, frozen volume identity, mixed-LOD/determinism dispositions, resource/timeout records, and next-hypothesis rationale. Each row carries the SHA-256 of its immutable raw geometry artifact.

### C2 pre-geometry recovery attempts

`C2GEO001`–`C2GEO005` did not consume C2 because the frozen realization path was blocked before the target geometry could be classified. The preserved causes were, in order: topology signature/serialization revalidation, false volume identity status, authority graph exact serialization mismatch, semantic graph comparison mismatch, and JSON numeric type mismatch despite equal displayed values. C2GEO006 ran only after these preflight corrections and supplied the valid C2 target result. No successful target scenario was repeated.

### C4 check-only correction

The first C4 import on source `db130481d79b5ad88fc3e705695bb1530cfadd61` passed but check-only found duplicate inherited constants before the geometry attempt; this was an unconsumed source/parser defect. The declarations were removed in `01856f529df0a0f8c0bf62be5684d86fd923d071`; import/check-only then passed, followed by the single valid C4 target attempt.

### C2 runtime logging limitation

C2's geometry process returned exit 0 and the then-current runner marked the process record `PASS`, but its captured output contains one `SCRIPT ERROR` from the two negative-region control executions. The C2 campaign correctly recorded those controls as failed (4/6), because the C2 helper passed the parent ROI rather than each variant ROI. C2's target still independently failed its cutoff/topology gate; the runtime control error is not hidden or counted as a passing control. C3 corrected ROI wiring and the runner's runtime-error classification.

## C5/C6 local deviation diagnostics

C5 applied four noncoplanar flips. The rejected-candidate reasons were 22 replacement-cutoff failures, 9 patches with more than two source owners, and 4 orientation disagreements. Its four remaining cutoff `cross_squared` values were `8.90332212726756e-17`, `2.77538984903934e-15`, `1.11996851137781e-13`, and `6.55420975739091e-13`. The largest old-versus-new diagonal-midpoint displacement among its applied flips was `0.131427302956581` world units.

C6 addressed the two-owner bound with full patch-owner sets distinct from exact topology-arc owner sets and incidence. It applied five flips and left three cutoff values: `2.77538984903934e-15`, `1.11996851137781e-13`, and `6.55420975739091e-13`. It rejected 27 candidates: 18 replacement-cutoff failures, 5 source-face orientation disagreements, and 4 opposite-side tests. Largest diagonal-midpoint displacement was `0.125083565711975` world units. These midpoint values are only local diagnostics. Neither C5 nor C6 measured a canonical maximum surface-distance bound or established an owner-approved geometry tolerance.

## Timing and resource observations (UNSCORED)

| Hypothesis | Realizer `build_usec` | Whole geometry process ms | Volume materialization usec |
|---|---:|---:|---:|
| C2 | 277,411 | 5,110 | 13,546 |
| C3 | 360,392 | 6,316 | 8,295 |
| C4 | 678,019 | 9,132 | 8,443 |
| C5 | 768,877 | 9,118 | 8,508 |
| C6 | 741,380 | 8,623 | 8,417 |

These are single-run headless diagnostics, not performance acceptance. The monitor reports working sets around 6.1–6.4 MiB, which is implausibly small for Godot and is treated as unreliable/unverified. Minimum sampled global free commit ranged from approximately 10.1 GiB to 13.5 GiB; no resource abort or timeout occurred. No presented FPS, GPU completion, or windowed gameplay claim is made.

## Gate disposition

- `FINAL_TOPOLOGY_ARCHITECTURE`: unchanged R10-A authoritative topology graph; 369 roots / 870 arcs / 502 faces.
- `FINAL_REALIZATION_ARCHITECTURE`: C6 derived multi-face noncoplanar 2–2 patches; topology-arc ownership kept separate from broader patch ownership.
- `FINAL_ANCHOR_POLICY`: all 369 frozen roots remain anchors.
- `FINAL_PATH_EVENT_POLICY`: 0 path-event roots.
- `FINAL_SUPPORT_VERTEX_POLICY`: 0 support vertices in C6.
- `FINAL_REALIZATION_MAP`: SHA-256 `e7cf00e11cde52e7dd29810a16542aaa7fd20fa3a74ff185c7e8a159158f96dc`; 5 realized paths.
- `FINAL_TOPOLOGY_ROUNDTRIP`: exact SHA-256 `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9`.
- `FINAL_EQUAL_LOD`: `FAILED_TARGET`; 3 final faces remain at/below the frozen cutoff.
- `FINAL_REQUIRED_OBLIGATIONS`: 870 topology arcs, 0 missing; exact topology signature match.
- `FINAL_INTERNAL_OPEN_EDGES`: 0.
- `FINAL_NONMANIFOLD`: 0.
- `FINAL_WINDING`: 0 inconsistencies.
- `FINAL_MIN_CROSS_SQUARED`: `2.77538984903934e-15`.
- `FINAL_CUTOFF_REJECTIONS`: 3; fixed threshold remains `1e-12`.
- `FINAL_CONTROLS`: 6/6 PASS.
- `FINAL_RAY`: ROI 0/25 disagreements; global 9/25 remains diagnostic only under the frozen oracle scope.
- `FINAL_VOLUME`: frozen volume/payload/revision 2 and reload identity PASS.
- `FINAL_MIXED_LOD`: `NOT_RUN_EQUAL_LOD_FAILED`.
- `FINAL_DETERMINISM`: `NOT_RUN_EQUAL_LOD_FAILED`.
- `FINAL_PERFORMANCE`: UNSCORED; single headless build timings above.
- `FULL_E2E_RESULT`: `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE`.
- `FULL_VALIDATION_RESULT`: `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE`.

## Source history and publication

The C6 measured source is `4535f4c965db67adab7c93e448492c54be916c92` with parent `289feddccc5a71bd8f9d1f5ff66051d8d4140657` and tree `1c8af8c4050a7b89976331fa1ad20c666d67e3a8`. The later final report/docs/archive commits will advance repository HEAD without changing that measured-source attribution. The experimental C4 helper's owner map was extended from a boolean marker to carry frozen polygon-owner/incidence metadata; C4/C5 still use only key membership, while C6 uses the explicit metadata. The original C4 and C5 source hashes/commits remain recorded above and are not rewritten.

No production source, persistence schema, user save, PR #207–#209, R10 worktree, or F2-G1 protected state was modified. The five F2-G1 holds remain unchanged. PR publication status is recorded in the final checkpoint after remote verification.
