# P3.1 R10-A Topology Authority Campaign Closeout

**Campaign disposition:** `P3_1_R10_A_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`  
**Scope:** isolated test-only research; no production adoption or geometry contract approval.  
**Date:** 2026-10-29

## Identity and frozen inputs

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Isolated worktree: `C:\r10a-20261029`
- Branch: `exp/p3-1-r10-a-topology-authority`
- Campaign base: R9.7 evidence PR #206 head `2cc2ccc933c4676dd281fce9aa4fc4a31d9f0719` (parent `7d058899abc1663ff7d4175b5a508532367cd5da`); production baseline `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` is an ancestor.
- Final code-measurement source: `da55e6e97bd56c31034b2d84c68a245a2f0973a1`; parent `78efe295c686661330f0f5ec7593e21bb6bbe6b3`.
- Frozen R9.2 manifest: SHA-256 `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.
- Candidate D source: SHA-256 `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`.
- Godot: `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Frozen degeneracy rule remained `cross_squared > 1e-12`; no sample, root, cutoff, topology obligation, or acceptance oracle was weakened.

The final local campaign HEAD is `da55e6e97bd56c31034b2d84c68a245a2f0973a1`. The source patch at that commit adds one bounded hypothesis to the topology-authority test module. The three R10 prototype/runner files are the only source paths added relative to the R9.7 base. This campaign does not modify playable scenes, production SDF, ledger, persistence, saves, dependencies, or CI.

## Result summary

Each of the six materially distinct equal-LOD geometry hypotheses executed on its pinned source and ended `FAILED_TARGET`. Failed tooling attempts are retained in the raw bundle, but are not counted as hypotheses. Hypotheses 2 and 4 were rerun only after correcting harness/compiler defects; only their successful reruns below count. The R10-A5 face-owned mixed-LOD strategy was not run: the mandatory equal-LOD gate had not passed. Based on that gate, A5's slot was used for a distinct equal-LOD root-preserving realization; this deviation is explicit and did not run or claim any mixed interface.

| Hypothesis / source | Equal-LOD outcome | Controls | ROI rays | Volume | Geometry process |
|---|---|---:|---:|---|---|
| A1 alternate diagonal / `f2faa9e48bbaa8c8985e101ffc0412f1887ca9b4` | 654 triangles; 8 cutoff rejections; 24 required adjacencies missing; 13 internal opens; nonmanifold 0; winding valid | 6/6 | 9/25 hit/miss disagreements | Preserved | PID 34896; exit 0; 3,589.7714 ms; min free commit 3,825,278,976 B; no abort |
| A2 centroid subdivision / `a333ebf0cce5162e44d7f92a365c609330f843cc` | 654 triangles; 24 cutoff rejections; 72 required adjacencies missing; 13 opens; nonmanifold 0; winding valid | 6/6 | 9/25 | Preserved | PID 55836; exit 0; 3,191.0815 ms; min free commit 3,755,503,616 B; no abort |
| A3 canonical-SDF assisted projection / `797047f591b47bad3ab7635df73980c04da43849` | 654 triangles; 24 cutoff rejections; 72 adjacencies missing; 13 opens; nonmanifold 0; winding valid | 6/6 | 9/25 | Preserved | PID 50280; exit 0; 3,166.8878 ms; min free commit 3,758,374,912 B; no abort |
| A4 bounded multi-cell boundary reconstruction / `c0b4f5028deb772d7e4892696a6a0766cd70114d` | 654 triangles; 8 cutoff rejections; 24 adjacencies missing; 13 opens; nonmanifold 0; winding valid; 2 components had 39 and 33 interior roots unsupported by boundary-only reconstruction | 6/6 | 9/25 | Preserved | PID 11952; exit 0; 4,751.0675 ms; min free commit 28,305,494,016 B; no abort |
| A5 interior-root preservation / `78efe295c686661330f0f5ec7593e21bb6bbe6b3` | 655 triangles; 7 cutoff rejections; 21 adjacencies missing; 10 opens; nonmanifold 0; winding valid. One 39-root component remained unresolved: insertion children had cross-squared `1.400302e-12`, `6.914512e-08`, and `2.516768e-15`; another component reconstructed | 6/6 | 9/25 | Preserved | PID 44768; exit 0; 4,728.6671 ms; min free commit 28,171,108,352 B; no abort |
| A6 bounded internal edge flips / `da55e6e97bd56c31034b2d84c68a245a2f0973a1` | 655 triangles; 7 cutoff rejections; 21 adjacencies missing; 10 opens; nonmanifold 0; winding valid. For the unresolved 73-root component, all 39 interior roots were inserted and 33 bounded flips attempted, but two triangles remained at `1.670757e-16` and `1.657250e-13`; the other component reconstructed after 19 flips | 6/6 | 9/25 | Preserved | PID 18608; exit 0; 5,133.9347 ms; min free commit 28,255,064,064 B; no abort |

All six attempts preserve materialized-volume identity. The topology graph remained independently valid for the source extraction (A6 source graph: 369 roots, 502 polygons, 870 arcs, zero unresolved/nonmanifold required source arcs). That source-graph validity did not make the realized mesh complete. A6 still has 21 missing realization adjacencies and 10 internal opens. The 9/25 ROI ray disagreements remain a separate failed observation and do not override the geometry gate.

## A6 details and causal conclusion

A5 demonstrated that root-preserving retriangulation can improve one connected component, but a deterministic root insertion may create child triangles below the frozen cutoff. A6 therefore constructed the complete root set while retaining sub-cutoff triangles only as unpublished intermediate candidates, then considered at most 512 deterministic flips of internal diagonals. A flip was eligible only when its projected diagonals properly intersected, the replacement edge was not already present or on the boundary, and the minimum 3D cross-squared area of the pair strictly improved. The frozen cutoff was still enforced before a patch could be emitted.

A3 separately projected each of the eight A1 rejected triangle centroids toward the canonical SDF zero set using its ordered edit snapshot. The projections were finite and moved by at most about `0.000103` world units, but did not resolve the materialized-field topology: 24 triangles were still rejected and the equal-LOD output retained 13 open edges. The scalar volume was not modified.

This bounded local improvement is not a complete constrained triangulation solver. The unresolved component ended with two sub-cutoff triangles and no further locally improving eligible flip. The algorithm returned unresolved and the candidate retained missing obligations rather than silently claiming completion. No additional hypothesis is authorized by the R10-A contract; do not start R10-A7 without new owner authorization.

The evidence supports this limited conclusion: the topology graph can retain/report required incidence that the current geometry realization rejects, but A1–A6 did not realize the equal-LOD obligations under the unchanged cutoff and frozen source roots. It does not establish that no legal realization exists in general.

## Stage and gate results

On final source A6, isolated Godot stages passed:

- editor import: exit 0, `IMPORT_PROCESS_PASS`;
- campaign `--check-only`: exit 0, no parser/script error;
- authority `--check-only`: exit 0, no parser/script error;
- standalone topology graph contract: exit 0, `GRAPH_CONTRACT_PASS`;
- one A6 geometry invocation: exit 0, exactly one preflight and one completion marker, terminal `FAILED_TARGET`, no script error, empty stderr.

Each equal-LOD gate failed, so mixed-LOD geometry was skipped as `SKIPPED_EQUAL_LOD_GATE_FAILED`. Frozen controls were 6/6 for the final valid attempts. No candidate qualified for a repeat-determinism gate. Therefore:

- `FINAL_TOPOLOGY_ARCHITECTURE`: partial diagnostic architecture; not a successful mesher.
- `FINAL_EQUAL_LOD`: FAIL — 10 internal opens and 21 missing required adjacencies on A6.
- `FINAL_MIXED_LOD`: NOT_RUN — blocked by equal-LOD gate.
- `FINAL_REQUIRED_ADJACENCY`: FAIL — 21 missing realized adjacencies.
- `FINAL_INTERNAL_OPEN_EDGES`: FAIL — 10.
- `FINAL_NONMANIFOLD`: PASS for measured equal-LOD output — 0.
- `FINAL_WINDING`: PASS for measured equal-LOD output.
- `FINAL_CONTROLS`: PASS — 6/6.
- `FINAL_RAY`: FAIL — 9/25 hit/miss disagreements; finite ROI oracle only.
- `FINAL_VOLUME`: PASS — identity preserved by the test fixture.
- `FINAL_DETERMINISM`: NOT_RUN for a target-passing candidate.
- `FINAL_PERFORMANCE`: diagnostic process duration only; no performance acceptance.
- `FULL_E2E_RESULT`: `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE`.
- `FULL_VALIDATION_RESULT`: `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE` (`scripts/validate.ps1` was not run).
- `EVIDENCE_INTEGRITY`: raw root retained and inventoried; final archive SHA-256 is recorded below.

No process reached the 2-GiB hard abort or the 3-GiB warning threshold. There was no resource-safety abort. Earlier R10 harness/parser failures and failed source attempts remain in the raw evidence archive and are not erased or misclassified as geometry results.

## Evidence package

Original raw evidence root (preserved locally):

`C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10A_20261029_ebc6f0b3b2d44761b988561524bdd50b`

It contains 688 files / 105,210,037 bytes; the sorted path/size/SHA-256 inventory is [`evidence/raw-evidence-inventory.csv`](evidence/raw-evidence-inventory.csv), SHA-256 `28102a70c69b2a6e098a857d49896e3e8a44d2ba007f91e8a30abfdb3bd65ba4`. The compressed full raw bundle is [`evidence/R10-A-raw-evidence.zip`](evidence/R10-A-raw-evidence.zip), 7,305,964 bytes, SHA-256 `ac630bd3b6b8be3494b33367e1896030de541a88ae16e8fdcf8b7ac83ac58e6`. The inventory is over the raw files before compression; the archive itself is separately pinned here.

Final-source physical SHA-256 values:

| File | Git blob at measured source | Physical SHA-256 |
|---|---|---|
| `game/tests/prototypes/p3_1_r10_a_topology_authority.gd` | `732f143939ac6980e1c7e77703dd7ee549206c0e` | `bdc4b40a3f3ebd3bb37bf0510449b34d279bd3c85632f13323c5eee9bfc2c5db` |
| `game/tests/prototypes/p3_1_r10_a_campaign.gd` | `65795aabb7a345b719ba1e0969a96b06f23b946d` | `6230cff18d759201a5b52d0a9658c369f8c5ba77ccbd43ad9c6d0a65545d6a9f` |
| `scripts/experiments/run_r10a_stage.ps1` | `9b94d98d2802861ebba35fc68f93f8f0f3d58722` | `4a511812cb497c21d1c5135ded05bafcb1b22d78f2ee798f52a4bbb53c7a3f1c` |
| Frozen Candidate D source | `93afe39cb03383f2f18503e517abdd2d97a14159` | `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a` |
| Frozen input manifest | `05a74de876ea2f062737980017f1b71b7c0711a6` | `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` |

The machine-readable Git-blob and physical source hash list is [`evidence/source-inventory.csv`](evidence/source-inventory.csv), SHA-256 `c8a38f5d3bf08063d014d839a74729c64d7dc3d4f80f9d9e5e437537a435491e`.

The Godot binary SHA-256 is `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. Exact commands, stage records, JSON outputs, stdout/stderr hashes, resource monitor samples, failed attempts, and preflight recoveries are in the archive.

## Recommendation and limits

Do not adopt this prototype in production and do not start Issue #108. Retain the topology graph as a useful test/evidence layer only. A future geometry effort needs a newly authorized, independently reviewed realization approach capable of handling the unresolved interior-root components while preserving all source boundary arcs and the frozen cutoff; it must pass equal LOD, the 0/25 ray requirement, then mixed LOD, repeat determinism, full frozen E2E, and full Godot validation in that order.

The experiment does not measure rendered frame rate, GPU completion, physics/collision correctness, owner visual acceptance, or a product geometry tolerance. It makes no change to the five F2-G1 holds: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
