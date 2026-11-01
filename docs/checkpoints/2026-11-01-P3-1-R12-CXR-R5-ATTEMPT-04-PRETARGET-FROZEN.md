# 2026-11-01 — R12-CXR R5-4 pretarget freeze

## State and authority

This is a preregistration for one test-only execution of `R9.2.SEAM.XPLUS_EQUAL.v1`. The target is **NOT_STARTED** as of this checkpoint. No production implementation, save/schema, geometry contract, Issue #108/#154, merge, or F2-G1 state is changed. PR #216 remains open, draft, and unmerged at `6407572f1ee9c57e2c530e0f021490d5a90ba8e3`; its base remains the R3AB experiment branch. R5 is a child experiment, not a replacement of R4.

The measured source is commit `8e5211e0665b6f57839d5c7eeae51c28c64325f6`, parent `0543cd1ca3c438b68f58799e1eb5f49963bbf09f`, tree `1531f2e5c2085f500437f38e0c8be22e63376e0b`. It is pushed to `exp/p3-1-r12-cxr-r5-constraint-guided-supports`; origin is `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`. At freeze, the remote feature head equals the measured source. The source is descended from PR #216's observed head. Tracked worktree state is clean; only preserved untracked `.gd.uid` files are present. Two existing stashes remain unchanged.

The separate evidence PR has not yet been created. After the one-shot result is archived, publish R5 as a draft PR based on PR #216's head branch; do not modify or merge PRs #207–#216.

## R4 facts and frozen inputs

R4 retains its 115-support pool, 18 legal edges, five supports with at least one and at least two legal edges, zero legal triangles, 329 D3 rows, five D3 branches, complete finite D3 search, and zero D3 solutions. Its D2 cavity remains frozen: connected six-face cavity, one boundary component, one CCW outer loop, no holes, and 15-state boundary-first search. R5 changes only support synthesis and does not alter the R4 cavity extractor, topology authority, roots/arcs, Candidate D, scalar samples, volume, ROI, or cutoff.

Exact pins rechecked for this source:

- Candidate D: `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`.
- Manifest: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` (sidecar bytes match).
- R4 topology fixture: `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`.
- Frozen topology identity: `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`.
- Graph fingerprint: `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9`.
- Residual fixture: `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23`.
- Materialized volume / payload: `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` / `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`; revision 2.
- Ray fixture: `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7`.
- Regenerated R5 cavity: `a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6`, byte-identical to the frozen fixture.

The unchanged geometric cutoff is `cross_squared > 1e-12`. No tolerance, root, field, cavity, or acceptance gate is relaxed.

## Bounded R5-4 method and limits

Earlier valid attempts emitted finite point witnesses but did not construct the preregistered triangle-first support regions. R5-4 now intersects each clipped piecewise-linear zero facet with a finite line arrangement formed from the selected boundary-root pair, cavity edges/vertices, and localized R4 required-arc root segments/endpoints. Deterministic arrangement cells emit no more than seven role-labelled critical points each. Exact binary32 support identity and the existing field, cavity, ownership, arc, winding, domain, T-junction, and cutoff gates remain authoritative. The candidate triangle is checked through the unchanged R4 triangle gates before graph publication.

The method is finite and bounded. It does **not** prove that an arrangement cell is entirely feasible or infeasible; owner-distance and field-residual predicates are point checks. Unpartitioned continuous constraints and all caps remain explicit. A zero-legal-triangle result will be `PARTIAL`, will skip D3, and will not imply support-domain exhaustion or structural infeasibility.

Caps frozen before target execution:

| Work item | Limit | On limit |
|---|---:|---|
| Source root pairs | 15 | Input mismatch blocks preflight |
| Tetrahedra | 3,072 | `PARTIAL` |
| Zero facets | 6,144 | `PARTIAL` |
| Projected clipping fragments | 32,768 | `PARTIAL` |
| Constraint lines per pair/fragment arrangement | 256 | `PARTIAL` |
| Arrangement region components, cumulative | 4,096 | `PARTIAL` |
| Critical points per arrangement region | 7 | `PARTIAL` |
| Critical candidates, cumulative | 4,096 | `PARTIAL` |
| Unique raw supports | 4,096 | `PARTIAL` |
| Retained supports | 64 | `PARTIAL` |
| Candidate triangle probes | Existing R2 preregistered cap | `PARTIAL` |
| Synthesis elapsed | 30,000,000 μs | `PARTIAL` |

No D3 limit is increased. If the complete finite graph has zero legal triangles, D3 is skipped. If a legal graph exists, the unchanged D3 solver runs; only an equal-LOD PASS advances automatically through controls, ROI rays, volume, mixed LOD, deterministic repeat, full E2E and `scripts/validate.ps1`.

## Preserved attempt accounting

Three of the five valid R5 execution slots have already been consumed; none is rerun:

| Slot | Source | Execution | Outcome |
|---|---|---|---|
| 1 | `3366998b7a7961cba5249038368b36e67fa147db` | `433ee89a337140b0ac3de608deda21c2` | Enumeration marker emitted; GDScript typed-array runtime error before result; remains consumed and preserved. |
| 2 | `01e8d55d4686ac763c93af0509b4a76a68411582` | `6763045101c04ea19052f0b8c58bed5d` | 220 finite triplets, zero legal triangles; `R5_SUPPORT_SYNTHESIS_PARTIAL`; result SHA `cc1e3c506215ef332006c41974defcb08ef84208a10ea99eca2e6b4ead103c88`; exit code unavailable. |
| 3 | `0543cd1ca3c438b68f58799e1eb5f49963bbf09f` | `22ddd559e83b42a98bd8550fd513b34e` | 364 triplets, zero legal triangles; `R5_SUPPORT_SYNTHESIS_PARTIAL`; result SHA `cfef18866dffc90f9d07f0f2fe4268bfbf5d1be99788ea6d4891f7451b829695`; exit 0. |

The earlier `scientific-01` failure occurred before the enumeration marker and is not counted as a valid target execution. Its evidence remains preserved. The valid budget is five total, leaving slots 4 and 5. Slot 5 is not a parameter sweep and is reserved only for a separately evidence-directed correction.

## Exact-source preflight

Preflight ran against measured source `8e5211e0665b6f57839d5c7eeae51c28c64325f6` using Godot `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`, with isolated `APPDATA` and `LOCALAPPDATA` under the temporary evidence root.

| Gate | Exit | Duration | Result |
|---|---:|---:|---|
| Godot version | 0 | 153 ms | Exact pinned version |
| Cold editor import | 0 | 7.436 s | Empty stderr; no error/warning/script-error markers in stdout |
| R4 realizer `--check-only` | 0 | 1.525 s | Passed |
| R5 campaign `--check-only` | 0 | 1.710 s | Passed |
| R5 synthesizer `--check-only` | 0 | 691 ms | Passed |
| R5 contract script `--check-only` | 0 | 1.705 s | Passed |
| R5 contracts | 0 | 1.903 s | 348 assertions, zero failures |
| R12-CXR contracts | 0 | 1.896 s | 216 assertions, zero failures |
| R5 cavity freeze/regeneration | 0 | 3.845 s | SHA matches frozen cavity fixture |

Manifest and sidecar pins passed. The CreateNew evidence probe rejected a duplicate reservation and preserved the original hash. Resource sample at `2026-11-01T14:54:59Z`: free commit 8,216.8 MiB, available physical memory 31,176.3 MiB, C: free 114.26 GiB, no Godot processes. Policy remains warn at 3,072 MiB free commit and stop at 2,048 MiB; the target dispatcher samples every two seconds, has a 180-second outer timeout, and may terminate only its own launched Godot process. A failed initial preflight-driver guard stopped before any Godot process; that record is preserved separately.

All 128 observed `.gd.uid` files and both stashes remain preserved. The exact preflight artifacts and copied raw logs are indexed under [`docs/reports/P3-1-R12-CXR-R5/evidence/pretarget-20261101/`](../reports/P3-1-R12-CXR-R5/evidence/pretarget-20261101/). Original external evidence remains at `C:\Users\PUBLI\AppData\Local\Temp\r12cxr_r5_20261101_a1` and was not overwritten.

## One-shot target reservation

- Target: `R9.2.SEAM.XPLUS_EQUAL.v1`.
- R5 slot: 4 of 5; exactly one invocation.
- Execution ID: `r5target2026110104a91e4f3e7c8f4f8f9a`.
- Measured source: `8e5211e0665b6f57839d5c7eeae51c28c64325f6`.
- Dispatcher: `docs/reports/P3-1-R12-CXR-R5/evidence/pretarget-20261101/launch_scientific_05.ps1`, SHA-256 `f5da10a242f79e870280ec2b11562ee68399321770e6337017bca2923bd66680`; PowerShell parser reports zero errors.
- Unique no-overwrite target root: `C:\Users\PUBLI\AppData\Local\Temp\r12cxr_r5_20261101_a1\scientific-05` (absent at freeze).
- Command vector: `--headless --path ./game --script res://tests/prototypes/p3_1_r12_cxr_r5_campaign.gd`; mode `synthesize`.
- Durable launch intent is written before process creation. The dispatcher captures the process, marker, terminal result, stdout/stderr, exit code, memory samples, and attribution. If a target process may have started, it will not be rerun.

After this checkpoint is pushed, invoke the dispatcher once. A successful legal graph does not itself pass equal-LOD. If equal-LOD passes, run all downstream gates in the same campaign progression. No result is claimed by this preregistration.

## Holds

`CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD` remain unchanged. No protected host path, save, ACL, VM, release, or production code was accessed or modified.
