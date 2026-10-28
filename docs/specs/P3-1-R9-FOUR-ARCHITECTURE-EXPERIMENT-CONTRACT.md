# P3.1 R9 — Four Architecture Prototypes: Frozen Experiment Contract

**Contract version:** `P3.1.R9.contract.v1`\
**Frozen from:** common R8.2 geometry baseline `4f08b67522507bd196a74a1089c773f272235343`\
**Measured canonical source:** R8.1 source `d81f29237d47361139b02849a8215c30424be873`\
**R8.4 is not a source parent of this contract.** Its evidence is considered only as historical evidence, not as an implementation dependency.

This is a research contract for four isolated, test-only prototypes. It does not approve production geometry, a product tolerance, a save schema, Issue #108, release, or merge. The immutable scenario records are in [`p3_1_r9_frozen_inputs.jsonl`](../../game/tests/prototypes/p3_1_r9_frozen_inputs.jsonl); its physical SHA-256 is recorded in `p3_1_r9_frozen_inputs.sha256`.

## 1. Source and evidence baseline

The R8.2 report identifies the following exact prior input hashes, which are retained as cross-checks rather than substituted for the R9 manifest pin:

| Input | SHA-256 |
|---|---|
| Zero edit | `24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b` |
| Single `cave_wall_carve` | `47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411` |
| Ordered `center_fill_then_wall_carve` | `55d45d387bd19829bb38c4e988da25a886765f26cc34e19dd07ed808faa1bd46` |

The following reference files are pinned at the common baseline `4f08b67522507bd196a74a1089c773f272235343` by Git blob identity and physical bytes. They are reference/oracle sources, not candidate output:

| Path | Git blob | Physical SHA-256 |
|---|---|---|
| `game/scripts/terrain/sdf_world.gd` | `80d8e86989dfa3262062f7345e6ab5d4a7ae4abe` | `a878e06d83652559c603e3e75bc3f704f1fe9222bb5f31bf6711d21b5612ac06` |
| `game/scripts/terrain/sdf_brush_edit_state.gd` | `f8225a825c3392fc293823bf40df4afc49025e00` | `9c715174770725fa0a45cfeab0b2e3c442e25eab8ef87b423f0de51d6ecedb44` |
| `game/scripts/terrain/terrain_spatial_ownership.gd` | `d8d3b79693815489a644772ef415e4cb18f5dd35` | `b90e356c333d4e9eb12d7c50cd4ae5dfe1c7b34239a149f6d19deaa1f1d6ee0e` |
| `game/scripts/terrain/terrain_chunk_grid.gd` | `8d4ca964a29e1baa6546d2ed8003c86efa3f9e67` | `d23e882be578c5b063cdff6ad2cff5660feeff121623003e46826aeefc5dc4d8` |
| `game/scripts/terrain/marching_tetrahedra.gd` | `116c38dd2c36df18d3f8d84e106e0f6168f347f8` | `23fbc6f94ba37d070d34924e85e9bbf1bdbbb26666aba32345c0140dfc6dffe3` |
| `game/scripts/terrain/lod01_chunk_mesher.gd` | `3ffc0bbbfacea0e2bed2962ce96903e585fd5c57` | `e8b844a56a70ed1b0769682d8a76ffdcba9ed7aceac7d0fbca685514f49f7792` |
| `game/scripts/experiments/lod01_transition_fixture.gd` | `8f3eb4fb5384d440ed79f2814c371b104caea805` | `26660008d576604546cf098c54ddc0b381b579b779b993e93a1f3c467209ed0f` |
| `game/tests/prototypes/p3_1_r8_2_geometry_provenance.gd` | `cda3470cad0553da16f98d8478b16527b8b96c43` | `bf822392035825f8b825162a2111508ea62325635e8b536046cb39ece69f6795` |
| `game/tests/prototypes/p3_1_r8_2_xplus_face_oracle.gd` | `1bf58b30eff0a77938464808f9eda426b8faaba5` | `3f84d2f7c26da66cfdb3f8260ab9af6ad727e02a07f59c15373f3188659a495e` |

The canonical field is `SdfWorld.sample_density`, generator version 1, seed `131102026`; positive density is solid and negative density is empty. World coordinates are in world units. Region dimensions are 16 × 12 in X/Z. The canonical cave center at world X is:

```text
phase = posmod(seed, 100003) * 0.000173
center_y(x) = 1.15 + 0.24 * sin(x * 0.25 + phase)
center_z(x) = 6.0 + 1.05 * sin(x * 0.17 + phase * 0.6)
```

The frozen R7/R8 bounded geometry ROI is `PATCH_MIN=(8,-2,3)`, dimensions `(8,20,12)` cells, base spacing `0.5`, hence world bounds `[8,12] × [-2,8] × [3,9]`. Mesh, collider proxy and picking remain experimental values. Production region/chunk controls are separately frozen in each seam record. No candidate may silently substitute another seed, command history, coordinate convention, region owner, chunk pair, LOD or ROI.

### Frozen records

The JSONL is the authoritative byte-level manifest. It defines stable IDs/versions and explicit inputs for zero-edit, CARVE, ordered FILL/CARVE, X+ contour mismatch, X− ray displacement, triangle 3103, the negative-region chunk boundary, mixed LOD interfaces, and a bounded four-command local CARVE/FILL sequence. Each record is an independent case; the same case definitions and manifest bytes are used by A/B/C/D. The X+ baseline records the observed `33/35` transition contour count; it is a reproduction value, not acceptance. The X− baseline records the ray `(0,8,6) + t(0,-1,0), 0≤t≤12` and prior R8.2 displacement observation without promoting it to a tolerance. Triangle 3103 is cell 712 in the ordered FILL/CARVE input. The negative seam is world `x=0`, region `(-1,0)` chunk `(3,2)` against region `(0,0)` chunk `(0,2)`. The mixed-resolution X+ and Z− pairs and their world planes are explicit in the records.

The bounded edit sequence is exactly four ordered commands in region `(0,0)`: CARVE `(9.0,2.0,4.0), r=0.58`; FILL `(9.2,2.1,4.2), r=0.58`; CARVE `(9.4,2.2,4.4), r=0.58`; FILL `(9.6,2.3,4.6), r=0.58`. All centers lie in the frozen ROI. These are research inputs, not a representative player workload claim.

### Hashing and determinism

1. Verify the JSONL file's exact physical bytes against its SHA-256 sidecar before any prototype runs. No BOM; UTF-8; LF line endings; one compact UTF-8 JSON object per line; terminal LF required.
2. Per-case identity is `SHA256(UTF8 bytes of that exact JSONL line, excluding its LF)`. Do not parse and reserialize before verifying the byte pin.
3. Ordered command identity is the SHA-256 of the exact `commands` array bytes as embedded in the line. A helper must locate the exact byte range while parsing/validating the line; if it cannot, it must report unavailable instead of using a runtime-specific serializer.
4. Mesh identity includes explicit algorithm/version, positions, normals, indices, LOD, region/chunk keys and source revision. Float arrays are hashed in their actual serialized little-endian IEEE-754 representation; JSON summaries do not replace binary artifact hashes.
5. All four candidates run serially from isolated checkouts with the same pinned Godot binary, executable SHA, OS/hardware profile, environment profile, manifest bytes, canonical source identities and commands. If a source or environment differs, results are a separate experiment and cannot be pooled.

## 2. Candidate definitions

### A — Conforming Marching Tetrahedra

Test-only candidate based on the production tetrahedral extraction, with a materially different seam mechanism than R8.4's failed four-ring refinement closure: deterministic shared-face contour ownership plus explicit transition templates. Root-aware interpolation may be used only where the exact canonical field is sampled at the same global edge endpoints and a bounded sign bracket is recorded. Preserve the reference squared-cross omission threshold `1e-12`; do not lower it. Keep canonical production extraction as the fallback/control. A candidate is not conforming merely because both sides share scalar samples: extracted contour segments, edge incidence, winding, T-junctions, and chunk/cell boundaries are measured.

### B — Adaptive Dual Contouring

Use canonical field samples and bounded edge-root brackets, gradients, a constrained QEF vertex and deterministic cell ownership. Include a uniform-resolution control plus an adaptive 2:1-balance candidate. Cells with multiple components, ambiguous sign patterns, or more than one relevant root must subdivide within limits or fail closed as unsupported; one vertex per cell must not erase topology. Bound interfaces with explicit transition connectivity; report unresolved adaptive boundaries as failures, not as acceptable approximations.

### C — Surface Nets

Classify canonical sampled cells, place a representative vertex from edge roots, and connect neighboring active cells under deterministic ownership. Include uniform and mixed-LOD seam cases. Optional vertex relaxation must remain SDF-constrained and separately measured; geometric relaxation and normal smoothing are independent switches and independent hashes. A relaxation result cannot repair topology by hiding cracks, closing tunnels or changing connectivity.

### D — Revisioned Materialized Volume

The canonical globally ordered edit ledger remains the reconstructible historical reference. A bounded revisioned sample volume is the test-only operational geometry authority after deterministic initialization/rebuild; accepted edits update relevant samples in global command order, dirty-cell/chunk sets and a coherent revision. Picking queries and the experimental collider proxy query the same materialized density revision. Declare one extraction algorithm/version in D's source metadata. Compare D's materialization and update/restart costs against direct sampling using the *same* extraction algorithm and grid. Compare extraction algorithms separately against the same materialized nodal values. Do not conflate volume authority gains with mesher changes, and do not edit Issue #154.

## 3. Frozen gates and result semantics

Every case emits PASS, FAIL, BLOCKED, or NOT_RUN with a reason, source SHA, manifest/case digest, elapsed time, peak measured resource data when available, and complete raw evidence. Candidate execution stops at its first mandatory gate failure. A/B/C/D proceed independently.

Mandatory research invariants, where applicable:

- Deterministic repeated construction from the same inputs; ledger order/revision preserved.
- No nonfinite sample, vertex, normal or timing accepted.
- Exact equality for shared canonical samples at identical world coordinates.
- No unexplained internal open edges, nonmanifold edges, inverted duplicate interfaces, strict T-junctions or unowned boundary contour segments in a case whose mesh gate is run. Candidate A additionally reports the unchanged `1e-12` cutoff outcome.
- For seam cases, compare actual extracted contours independently on both sides and against a separately sampled piecewise-linear/canonical root oracle. A scalar-only match is not a seam PASS.
- Report continuous-SDF root counts as finite-scan observations with the scan method and completeness limits; a finite scan does not certify absence of tangent/narrow roots. Report sampled-density and extracted-mesh cave connectivity separately.
- Preserve the frozen zero-edit 1.75-world-unit vertical cave opening measurement as an observation. It is not an owner-approved diameter tolerance.
- Compare mesh ray hits with an independent two-sided triangle-ray oracle and the canonical picker; report hit/miss and position error. PhysicsServer/GUI behavior is NOT_RUN unless separately exercised and must never be inferred from CPU mesh/proxy evidence.
- Geometry displacement and normal-angle distributions are reported (p50/p95/max) without a product acceptance threshold. Fail only frozen exact structural/connectivity invariants or an explicitly predeclared research threshold; otherwise label quality `UNSCORED`.

## 4. Resource stop-loss and timing contract

Per candidate and bounded ROI: maximum 4 propagation rings, 10,000 unique sampled nodes, 20,000 emitted triangles, and 600 seconds wall-clock for a focused run. Hitting any limit produces `BLOCKED`/`STOP_LOSS`, retains partial diagnostics, and prevents further work on that candidate's current gate. Each implementation must check budgets before allocating/emitting the next block; post hoc truncation is invalid. D additionally reports volume byte size and refuses allocation above the same node ceiling. No product-level memory/latency limit is inferred from these experimental stop-losses.

Use a monotonic process-local clock. Record separate sample/build/extract/topology/serialization phases and total scenario elapsed time; do not call headless durations frame or GPU measurements. Candidate order is A, B, C, D, each on an isolated checkout from the same preregistration parent. Repeat geometry determinism twice per frozen case; performance is exploratory with at least five repetitions for bounded build/edit cases if the 600-second gate permits. Report each run and distributions separately; no candidate ranking from mixed scenarios or machines.

## 5. Required evidence per candidate

Focused tests and the full `scripts/validate.ps1` under Godot `4.7.2.stable.official.ed1daf0bf`; full stdout/stderr, exit codes, assertion totals, process metadata, source parent/SHA, candidate source hashes and evidence hashes. Report topology, seams, displacement, normal angles, root counts, sample-vs-mesh cave connectivity, picker/ray agreement, build/edit cost, memory and limits. Preserve failed and superseded runs. `READY_FOR_INDEPENDENT_REVIEW` means evidence package complete, not geometric acceptance.

## 6. Historical discrepancy and restrictions

The R8.4 checkpoint text at its measured commit reports 20 suites / 14,990 assertions. Independent review #5686141541 inspected the full raw validation log, which contains `LOD01_TRANSITION_PASS: assertions=6474 failures=0`; corrected total is **21 suites / 21,464 assertions / 0 failures**. This R9 contract records the reconciled raw-log total. PR #168 remains unchanged. R8.4 still failed its bounded X+ transition gate with nine unmatched interfaces and 58 internal open edges; downstream tests were NOT_RUN. This does not establish that every conforming-transition mechanism is impossible.

No candidate source changes production paths, canonical SDF/ledger behavior, schemas, saves, gameplay, dependencies, GUI/PhysicsServer, Issue #108 or F2-G1 state. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD` unchanged.
