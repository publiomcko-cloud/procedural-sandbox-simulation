# P3.1 R10-B — Campaign preregistration and Stage 0 causal freeze

**Final status:** `P3_1_R10_B_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`. B1 is `BLOCKED_HARNESS_ERROR`; the intended solver did not yield a valid geometry result and was not rerun under the preserved continuation boundary. B2 exhausted only its registered ring-0-to-4 cavities; B3 made zero Lawson flips; B4's 8 Steiner projections generated 24 child faces rejected by the unchanged cutoff and worsened topology; B5's nested 0.125 field matched all 729 shared scalar samples but failed topology and four nonempty outer contours; B6 exhausted its bounded beam after examining the 182 initial internal edge candidates without a legal successor. B2–B6 all returned `FAILED_TARGET`. No candidate qualified equal LOD, so mixed-LOD qualification, deterministic repeat, full frozen E2E, and `scripts/validate.ps1` were not run. Global exact-root infeasibility is not proven. This report is experimental evidence only.

## Authority boundary

The owner request authorizes the attached R10-B procedure. This branch is a separate test-only research branch based on the final R10-A evidence tree. It does not modify production SDF, terrain streaming, persistence, saves or schemas; it does not alter PR #207; it does not implement Issue #108 or #154; it does not authorize integration or merge. All five F2-G1 holds remain unchanged.

## Source and environment identity

| Item | Verified identity |
|---|---|
| Repository origin | `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git` |
| R10-A remote PR head | `f6f4a47bcb9f98ee7b8648f88a4db2ccf8317294` |
| R10-A remote tree | `09b3eb8ac59e77e0dfa44c82175b4180c3629d21` |
| R10-A local mirror parent used for this worktree | `4b7b0ea58c125da2365033440d04003fb31a2ba1` |
| R10-B worktree parent | `4b7b0ea58c125da2365033440d04003fb31a2ba1` |
| R10-B local mirror tree | `09b3eb8ac59e77e0dfa44c82175b4180c3629d21` |
| R10-A measured local source | `da55e6e97bd56c31034b2d84c68a245a2f0973a1` |
| R10-A topology-authority source blob | `732f143939ac6980e1c7e77703dd7ee549206c0e` |
| R10-A measured worktree physical SHA-256 | `bdc4b40a3f3ebd3bb37bf0510449b34d279bd3c85632f13323c5eee9bfc2c5db` |
| R10-B checkout topology-authority physical SHA-256 | `feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216` |
| Candidate D source SHA-256 | `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a` |
| Frozen R9.2 input manifest SHA-256 | `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` |
| Godot binary SHA-256 | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |
| Qualification cutoff | `cross_squared > 1e-12` |

The R10-A authority file is the same Git blob in both worktrees. The historical R10-A measured worktree had physical CRLF bytes (`bdc4…`); the new checkout follows the committed `.gitattributes` and has LF bytes (`feea…`). The code blob is identical; R10-B pins and records its own physical source bytes and does not claim to have re-executed the R10-A physical file. R10-A raw evidence remains unmodified.

The R10-A raw archive in the parent tree is 7,305,964 bytes and SHA-256 `ac630bd3b6b8be3494b33367e1896030de541a88ae16e8fdcf8bc7ac83ac58e6`. The separately preserved R10-A raw directory remains at `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10A_20261029_ebc6f0b3b2d44761b988561524bdd50b`; R9.7 raw comparison data remains at `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R97_D3_20261029_5eab760d7ce6486eaef7fb210741416e`.

## Stage 0 — frozen A6 causal fixture

`tools/r10b/extract_a6_causal_fixture.py` hashes the preserved R10-A gate/ray files before parsing. Those files contain raw U+001F bytes that are invalid JSON. The extractor replaces only byte `0x1f` with the equivalent JSON escape in an in-memory parse view. The original files are not rewritten. The derived fixture is `fixtures/a6_causal_fixture.json`, SHA-256 `f5a5fe0e98cab91777e44af7c3313f5285d0c36615f80efdef27b90462fe8ac3`.

The extraction asserted the source topology SHA-256 `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`, component `60,8,25|tet:0`, 84 component source polygons, 73 roots, one 34-root ordered boundary, 39 interior roots, 156 incident source arcs, 27 neighboring polygons, 110 A6 triangulation faces, 182 triangulation edge records, and 33 A6 flips. It preserved all source-root coordinates and authority, cell/tetra incidence, orientation rows, boundary/component arcs, the full flip and final-triangle states, all edge incidences, and neighboring polygon records.

The exact remaining sub-cutoff faces are:

| A6 face index | `cross_squared` | binary64 little-endian |
|---:|---:|---|
| 40 | `1.67075673894024e-16` | `eeffff1f0114a83c` |
| 41 | `1.6572500479133299e-13` | `13000060df52473d` |

Frozen Candidate D volume identity is SHA-256 `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`, payload SHA-256 `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`, revision `2`. These are the A6 equal-LOD input volume values, not an R10-B-generated replacement.

The fixture's extraction script fails closed on any mismatch in raw hash, scenario, source topology, component, polygon/root counts, root partition, boundary arc lookup, flip count, inserted-root count or the two expected sub-cutoff faces. A mismatch blocks the experiment before a geometry hypothesis is counted.

## Mandatory ray diagnostic preregistration

The 25 fixed rays are generated from the frozen manifest row `R9.2.RAY.CANONICAL_PICKER.v1` in `x_major_z_minor` order. Initial fixture `fixtures/ray_reference_fixture.json` (SHA-256 `33f9e1e15ef3e868efcd9c97d56490e0728bc7822791b7516eb32c7c2360e314`) is retained as the first diagnostic attempt; its D0 evidence classification was incomplete. Corrected fixture `fixtures/ray_reference_fixture_r2.json` (SHA-256 `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7`) includes the preserved R9.7 per-ray stdout and separate ROI/global semantics. `RAY-CAUSE-CORRECTION.md` documents why R2 supersedes the initial interpretation.

| Track | Frozen evidence / execution | Interpretation limit |
|---|---|---|
| D0 | R9.7 D3.5 preserved stdout contains 25 per-ray `R95_RAY` rows; ROI-scoped result 0/25 and legacy global finite-scan result 9/25. Candidate artifact SHA `87623cd4a55f27a0677d522056b02f847e24409755eb4a227cbde57c77d579ec`; mesh SHA `04c6ceb842b964caba4e254f94c9f4b32881dae79994b961ac01029a48f64553` | The two counts use different root-scope rules. See `RAY-CAUSE-CORRECTION.md`; that correction supersedes the original scope interpretation below. |
| D1 | Re-run R10-A6 final emitted topology on the same zero-edit ray input; expected captured result 9/25 and mesh SHA `04c6…` | Geometry remains unqualified. |
| D2 | Add the complete unresolved A6 patch triangles, including sub-cutoff faces, to a separate diagnostic-only mesh | `DIAGNOSTIC_ONLY_SUBCUTOFF_GEOMETRY_NOT_QUALIFIED`; never a candidate. |
| D3 | Rebuild Candidate D from frozen source/manifest and execute the same ray grid; require mesh SHA `04c6…` to match preserved D3.5 artifact | This is the live reproducibility check of D0, not a new qualification. |

For each ray, the script records input origin/direction/length, finite canonical scan/bisection roots, first mesh-hit triangle, triangle root IDs, source polygons/patch/component, distance, density at the hit, distance to a canonical ray root and two separate hit/miss results: global full-ray scan and ROI-filtered roots excluding cropped Y end faces. It cross-checks the custom first-hit routine against the existing Core oracle. The historical R9.7 ROI rows are compared with the R10-B replay; the R10-A full-ray rows are compared separately. See `RAY-CAUSE-CORRECTION.md` for the raw-evidence basis.

## R10-B1 hypothesis preregistration

**Hypothesis:** a deterministic breadth-first non-monotonic edge-flip feasibility search may find a legal exact-root triangulation that A6's greedy monotonic minimum-area objective never visited.

**Input and domain:** the Stage-0 frozen A6 triangulation, 73 exact source roots, 34-root fixed boundary, 39 interior roots, and 110 faces for component `60,8,25|tet:0`. Only internal diagonal flips of a projected convex quadrilateral are allowed. Boundary arcs, root identities, source root positions and the component's triangle count/Euler characteristic are invariant. No scalar sample or root is moved/deleted. Temporary sub-cutoff faces are allowed only in un-emitted search states.

**Deterministic solver:** breadth-first queue; candidate internal edges sorted by canonical root-edge key; two new oriented triangles derived from the adjacent oriented pair; reject repeated diagonals, non-convex projected quads, projected crossings, invalid manifold incidence, wrong boundary cycle or wrong source-root set. State identity hashes sorted unoriented triangle-root triplets. A final state is accepted only after full 3D area cutoff, exact boundary, all roots represented, manifold incidence and component winding checks.

**Predeclared bounds:** at most 4,096 unique states, queue peak 4,096, 90 seconds solver wall time, and 15,000 edge keys examined. The implementation increments the last counter before checking legality, so it counts every encountered edge key, including boundary and rejected edges; it is not a count of legal flips. Hitting any bound is `PARTIAL / EXACT_ROOT_REALIZATION_INCONCLUSIVE`, not proof of infeasibility. A completed finite search may claim only bounded-domain infeasibility if every state was enumerated. All gates and the `1e-12` cutoff remain unchanged.

## Remaining hypothesis sequence (not yet consumed)

These are strategy families, not permission for parameter sweeps. Each will be fully pinned with source SHA/parent/tree, physical hashes, exact solver limits and input identities in its own attempt record before it executes.

| Slot | Distinct strategy | Fixed correctness domain |
|---|---|---|
| B2 | Expanding local cavity exact retriangulation, rings 0–4, boundary preserved | Existing roots only; deterministic state enumeration; bounded cavity/search/time/memory; complete exhaustion is local-only evidence. |
| B3 | Deterministic constrained-Delaunay-like or max-min-area solver, not the A6 greedy loop | Existing roots only; boundary fixed; all obligations/manifold/winding/cutoff mandatory. |
| B4 | Deterministic field-constrained geometry-only Steiner realization | Topology roots/obligations remain authoritative; every added point has parent provenance and zero-set residual evidence; no scalar mutation. |
| B5 | Derived local field refinement | Original volume bytes/values unchanged; exact outer interface and mappings back to source topology required. |
| B6 | Evidence-directed bounded solver based on prior failure evidence | No arbitrary parameter sweep; may not relax any frozen gate. |

No mixed-LOD work, deterministic repeat, frozen full E2E, or `scripts/validate.ps1` runs until an equal-LOD candidate passes topology and the ray oracle reaches 0/25. If B1–B6 are exhausted without such a candidate, E2E and full validation remain `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE`.

## Ray-scope correction (superseding the original D0 interpretation)

`RAY-CAUSE-CORRECTION.md` records the verified raw R9.7 D3.5 per-ray source, exact outputs and matching R10-A global-scope indices. The preserved D0 records establish 0/25 for the ROI-scoped oracle and 9/25 for the separate global full-ray finite scan. R10-B retains both metrics; only ROI-scoped matching is the comparison to the R9.7 gate. The R10-A `Core.compare_mesh_rays` 9/25 value remains a valid global-scope measurement, but is not a contradiction to the R9.7 0/25 ROI result.

## Resource and evidence rules

Every Godot run uses a unique external evidence folder and fresh isolated `APPDATA`. The process monitor samples host commit/free commit, available RAM and only the launched Godot process at 350 ms intervals. `free_commit <= 3 GiB` is a warning; `<= 2 GiB` kills only that launched Godot process. A resource abort is not a geometry result and does not consume a slot unless a complete geometry terminal result existed first. No pagefile/WSL change or unrelated process termination is allowed.

Raw R10-A/R9.7 evidence is immutable. R10-B logs, generated source hashes, machine-readable fixtures, failed states and output hashes are kept separately. No production implementation, user save, schema or F2-G1 state is modified.
