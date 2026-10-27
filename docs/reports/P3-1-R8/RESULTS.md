# P3.1 R8 — Geometry Quality and Spatial Conformance

**Disposition:** `P3_1_R8_READY_FOR_INDEPENDENT_REVIEW` — diagnostic evidence package only. This is not production geometry approval, a geometry-contract decision, or merge authorization.

## Identity and scope

| Item | Verified identity |
|---|---|
| Repository origin | `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git` |
| Branch | `bench/p3-1-r8-geometry-quality` |
| Measured R7.3 source HEAD | `7ad45d8c817ecb0f54a8eec058babce65af287db` |
| Measured source parent | `c54f337cb1f2b1e6d1f61de5c1b9d9f3031e892d` |
| R7.3 evidence HEAD | `87c9c6f30c613e73ad572670cadb253ab06483eb` |
| Production reference only | `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` |
| Diagnostic harness | `game/tests/prototypes/p3_1_r8_geometry_quality_diagnostic.gd` |
| Harness SHA-256 | `73B446889271C38A1A62DE94382CFB5C5D371BB2981D9E7176A64B0CC225D1EA` |
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| Godot executable | `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe` |
| Executable SHA-256 | `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643` |

R8 is test-only and extends the pinned R7.2 diagnostic fixture. It does not instantiate the playable production terrain, change production files, access user saves, or change any historical R7.3 gate. The R8 measurements were executed against the exact R7.3 tested source SHA above; the final R8 evidence commit only packages the harness, reports and raw evidence.

PR #156 was rechecked through GitHub: open, draft and unmerged; head `87c9c6f30c613e73ad572670cadb253ab06483eb`, base `bench/p3-1-r7-2-topology-retriangulation`. The second independent R7.3 review records both edited topology gates as 21/21 with zero topology mismatches, while explicitly holding geometry quality open. Its reviewed head is later documentation/evidence over the tested source `7ad45d8...`.

## Frozen inputs and provenance reconciliation

The R7.3 evidence inventories were independently rehashed before R8: 50 entries in the main R7.3 inventory and 37 entries in the full edited-gates attempt inventory, with no mismatches. The three canonical input manifests were reconstructed and hashed by R8 preflight:

| Frozen scenario | Operations / revision | SHA-256 | Pin |
|---|---:|---|---|
| `P3.1.R7.ZERO_EDIT.v1` | 0 / 0 | `24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b` | match |
| `P3.1.R7.CAVE_WALL_CARVE.v1` | 1 / 1 | `47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411` | match |
| `P3.1.R7.CENTER_FILL_THEN_WALL_CARVE.v1` | 2 / 2 | `55d45d387bd19829bb38c4e988da25a886765f26cc34e19dd07ed808faa1bd46` | match |

One historical R7.3 derived summary needs a transparent qualification. `fill.acceptance-summary-verified.json` retains `all_gates_pass=false` because its `ordered_fill_then_carve_recipe` check compared a decimal delta in binary64 against coordinates serialized from Godot `Vector3` binary32. The same evidence directory contains the later `fill.acceptance-summary-f32-verified.json`: it reproduces the source addition in binary32, reports that recipe check true, and all gates true. The original JSONL/stdout data were not changed; the raw Godot scenario result is PASS, 21 assertions, zero failures, with the pinned input digest. The independent R7.3 edited-gates review also records both frozen edited runs as PASS. R8 preserves both summaries and this discrepancy; it does not treat the stale false check as a geometry failure or erase it.

## Execution and validation

### Focused R8 diagnostic

Command:

```powershell
& 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path 'C:\r8\game' `
  --script res://tests/prototypes/p3_1_r8_geometry_quality_diagnostic.gd
```

Final immutable attempt: `docs/reports/P3-1-R8/evidence/run-020/`.

- Source HEAD: `7ad45d8c817ecb0f54a8eec058babce65af287db`; final harness SHA matches the table above.
- Exit code 0; PID 6280; 139.588 seconds; stdout 10,248,505 bytes; stderr 0 bytes.
- Terminal status `DIAGNOSTIC_COMPLETE`, six phases, `assertions=0`, reason `exploratory_geometry_only_no_tolerance_adopted`.
- All six phase records are marked valid. This is a diagnostic completion marker, not a geometry acceptance PASS.
- Attempts `run-001` through `run-020`, including failed, interrupted and superseded attempts, are retained. No R7.3 scenario was repeated.

### Full canonical validation

Command:

```powershell
$env:GODOT_BIN = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& 'C:\r8\scripts\validate.ps1'
```

The validator's first recorded engine command was the headless editor import (`--headless --editor --path C:\r8\game --import`); it then ran all canonical suites.

Two complete validation runs are retained. The first completed in 580.005 seconds against the same pinned R7.3 production/test sources but the earlier R8 summary harness. After adding the sampled minimum-ray-width metric, the final validation completed in 648.216 seconds on the final R8 harness source and unchanged R7.3 source, exit 0, 21 suites, **21,464 assertions, zero failures**, and emitted `VALIDATION_PASS: L0-L2; GUI visual test remains an owner task`. The final run used an isolated user-data profile under `docs/reports/P3-1-R8/evidence/validation-002/profile`; neither validation used the normal Godot user profile or real saves. Both complete `validation-001/full-suite` and `validation-002/full-suite` logs and process records are included in the evidence bundle; `validation-002` is the final exact-harness run.

The final run had zero parser or `SCRIPT ERROR` failures. Stderr contains three non-fatal `Target and up vectors are colinear` warnings from `_update_camera` during `procedural_object_tests.gd` at test call sites 991, 1060 and 1069. They do not invalidate this validation result and were not changed here.

| Suite | Assertions | Suite | Assertions |
|---|---:|---|---:|
| SMOKE | 52 | SDF | 44 |
| BRUSH | 612 | CHUNK | 179 |
| MULTI_REGION | 7,637 | PERF | 11 |
| HISTORY | 907 | WORLD_V2_STORAGE | 3,516 |
| DECLARATIVE_MOD | 66 | PROCEDURAL_OBJECT | 638 |
| ENTITY_COMMAND | 67 | ENTITY_HISTORY | 101 |
| ENTITY_COMMAND_HARNESS | 19 | PLAYABLE_ENTITY_COMMAND | 44 |
| P3.0D_PLACEMENT | 51 | PICK_HISTORY | 713 |
| LOD_TRANSITION | 6,474 | LOD_RUNTIME | 53 |
| E2E_PERF | 251 | CONCURRENCY | 11 |
| BOOTSTRAP_STRUCTURE | 18 | **Total** | **21,464** |

The R8 focused diagnostic is not part of those 21 suites and reports zero assertion-style tests by design. Its exploratory records must be reviewed independently.

## Results

### 1. Ordered FILL → CARVE cave connectivity

The 31 centerline sample positions are compared against canonical SDF v1 and each experimental representation using the identical ordered ledger. Indices 1–4 have positive canonical and experimental density and are solid in every field. They lie inside the radius-0.58 FILL centered at `(8.0, 1.1789815426, 5.1030921936)`; index 4 is about 0.503 world units from that center. These four non-open samples are therefore the intended FILL volume, not a voxel-only obstruction. Indices 5–31 (27 samples) are negative/open in canonical and A/B/C, and the extracted mesh centerline slice agrees at those 27 samples.

At 0.125-unit voxel-center spacing, the 3D six-neighbor field flood covers `[7.5,-2,3.5]` through `[12.5,8,8.5]`, dimensions `41×81×41` (136,161 samples). Canonical has 77,566 empty samples; each experimental field has 77,527, a difference of 39 classifications. All open centerline samples form one component in all four fields. The seeded tunnel component connects to the positive-X boundary probe, not the negative-X probe; the latter is solid (`density=+0.0772532`) because of FILL. The exterior-air component is separate (component 2 versus seeded tunnel component 1); the cave was not incorrectly required to connect to all exterior air.

Each open centerline section is probed along 32 radial directions. Rays advance in 0.0625-unit steps until a solid bracket is found, then use 18 bisection steps. The existing per-section median-diameter distribution (27 sections) is canonical `min/p50/p95/max = 1.8399999/1.8399999/1.8399999/1.8399999`; A/B/C are `1.8254807/1.8277919/1.8288925/1.8291185` world units. The additional narrowest sampled ray diameter per section, summarized across the same 27 sections, is canonical `1.8399990/1.8399994/1.8399999/1.8399999`; A/B/C are `1.8205626/1.8227684/1.8232782/1.8234837`. Thus the minimum sampled radial width is about 1.82056 units for the candidate fields. This is a bounded directional/sample estimate, not a certified continuous minimum clearance; a narrower feature between angular rays or centerline slices can be missed. These R8 radial measurements use a different plane/convention from the historical 1.75-unit vertical opening fixture and are not replacement acceptance thresholds.

The analyzed repaired FILL/CARVE mesh has 7,436 triangles, zero internal open edges, zero nonmanifold edges and zero degenerate triangles at the unchanged cutoff. It has 386 finite crop-boundary open edges, which are expected for this cropped diagnostic and do not establish watertightness. The harness compares mesh centerline slice classifications, but does not perform a volumetric flood through triangles; full extracted-mesh 3D cave connectivity remains unverified. The 39-sample field-classification difference and structures narrower than 0.125 units or connected only diagonally remain unresolved.

### 2. Surface normals and winding

The table compares adjacent-cell normals at shared contour endpoints before and after the R7.3 repair. No product angle tolerance exists.

| Scenario | Pair observations | p50 | p95 | max |
|---|---:|---:|---:|---:|
| CARVE, original | 4,068 | 0.503° | 15.041° | 33.621° |
| CARVE, repaired | 4,060 | 0.504° | 15.041° | 33.621° |
| FILL/CARVE, original | 4,190 | 0.534° | 15.724° | 87.736° |
| FILL/CARVE, repaired | 4,184 | 0.534° | 15.724° | 87.736° |

The worst CARVE pair is between cells 528 `[0,5,6]` and 624 `[0,6,6]` at `(8.456458,1.0,6.206458)`. The two normals are `(-0.653575,0.630638,-0.418492)` and `(-0.837652,0.095430,-0.537803)`, 33.621° apart; both cells are untouched by repair. Their maximum angle to the canonical outward gradient is 21.030°. The local gradient-turn proxy is `0.0000526`; this proxy is not a differential-curvature measurement.

The worst FILL/CARVE pair is between cells 408 `[0,4,3]` and 504 `[0,5,3]` at `(8.109478,0.5,4.5)`. Normals `(-0.108951,0.802945,0.586011)` and `(-0.150959,-0.563865,0.811953)` differ by 87.736°; neither cell is repaired. The maximum angle to the sampled canonical outward gradient is 82.139°, while the local gradient-turn proxy is 0.004123. Other high-angle pairs also occur in untouched cells. These observations do not support attributing the maxima to the retriangulated patch alone; they warrant investigation of per-cell normal generation/averaging and local field behavior, but do not prove one root cause.

Winding diagnostics found **one FILL/CARVE triangle opposite the canonical outward gradient**, before and after repair: owner cell 712, coordinate `(0,7,5)`, triangle 3103, centroid `(8.239575,1.509851,5.50634)`, face normal `(-0.293971,0.872855,-0.389493)`, outward gradient `(-0.151556,-0.151609,0.976753)`, dot `-0.468217`. This is a concrete unresolved orientation defect in the experimental mesh. R8 does not correct it. CARVE had no such opposing triangle. The unchanged degeneracy diagnostic count falls from 10 to 0 for CARVE and 8 to 0 for FILL/CARVE, but the large normal angles remain.

### 3. Chunk and LOD interfaces

Sixteen adjoining chunk pairs were built from actual meshes: 12 ordered FILL/CARVE configurations and four boundary-edit configurations. They cover X+/X−/Z+/Z−, same LOD and mixed LOD, including negative region coordinates `(-1,0)` and `(0,-1)`. The four boundary-edit pairs are on +X.

All **9,512 shared-face canonical SDF samples** match bitwise (maximum absolute density difference 0). This establishes scalar sampling agreement only. Extracted contour comparison passes 12/16 pairs. All four mismatches are on X+ when chunk A (region `(0,0)`, the negative side) is LOD1: FILL/CARVE LOD `1/1` and `1/0`, and boundary-edit LOD `1/1` and `1/0`. Each has 33 segments on A versus 35 on B, with two unmatched B segments and no T-junctions reported. The unmatched points differ by roughly 0.0007 world units around `(16,2.0,7.0)`. The opposite `0/1` orientation matches; all tested X− and Z interfaces match. This is an actual extracted-contour inconsistency, despite matching face samples; it is not silently rounded into a pass.

All 16 picker probes agree on hit versus miss. Position error is not uniformly small: median `0.0000219`, p95 `0.366082`, maximum `0.366092` world units. The large values are the X− pairs and represent a material location discrepancy for follow-up; no approved positional tolerance exists, and hit/miss agreement alone is not picker parity.

The harness distinguishes actual chunk boundaries from R7 adaptive-cell interfaces. It does not establish full-region watertightness, physical collision behavior or every possible LOD arrangement.

### 4. Uniform resolution sweep

All values are exploratory CPU diagnostic measurements, not production budgets. The “surface residual” is the harness's canonical-SDF residual proxy evaluated at generated surface vertices, not a symmetric Hausdorff/surface-distance metric. Build time is headless CPU construction, not GPU upload, scene publication or presented frame time. “Crop opens” are finite-domain edges and are expected.

| Field | Spacing | Samples | Triangles | Build ms | Mesh attribute bytes | Residual p50 / p95 / max (world) | Normal angle p50 / p95 / max | Crop open edges |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Zero edit | 0.5 | 1,694 | 1,822 | 256.037 | 131,184 | 0.002962 / 0.034578 / 0.062990 | 1.397° / 12.420° / 23.649° | 142 |
| Zero edit | 0.25 | 11,907 | 7,239 | 1,050.447 | 521,208 | 0.000788 / 0.009123 / 0.015861 | 0.780° / 6.640° / 11.541° | 289 |
| Zero edit | 0.125 | 89,093 | 28,827 | 5,136.005 | 2,075,544 | 0.000196 / 0.002191 / 0.004136 | 0.362° / 3.252° / 6.040° | 747 |
| FILL/CARVE | 0.5 | 1,694 | 1,908 | 288.627 | 137,376 | 0.004930 / 0.088274 / 0.229836 | 1.952° / 30.161° / 164.597° | 150 |
| FILL/CARVE | 0.25 | 11,907 | 7,844 | 1,231.504 | 564,768 | 0.001534 / 0.018636 / 0.110073 | 1.233° / 13.493° / 120.532° | 308 |
| FILL/CARVE | 0.125 | 89,093 | 31,504 | 6,011.397 | 2,268,288 | 0.000389 / 0.004152 / 0.045087 | 0.580° / 4.962° / 85.649° | 818 |

The mesh-centerline check found one coarse FILL/CARVE discrepancy at spacing 0.5: the mesh classified slice index 4 as open although the canonical sampled centerline classifies it solid. At 0.25 and 0.125 the selected mesh centerline probes match the sampled canonical probe list. This supports sensitivity to coarse interpolation, but does not establish a universal minimum feature size. Triangle/sample/attribute counts increase sharply with refinement, and no owner-approved geometric error or resource budget is available.

### 5. Collision and contact consistency

The independent Möller–Trumbore oracle used two-sided triangle intersections for the frozen 72 rays. Hit/miss outcomes matched 72/72; distance error p50/p95/max is `0.004474 / 0.013284 / 0.013284` world units. For 36 sphere/contact probes (radius 0.1), point-to-triangle distance with binary refinement after a 0.01-unit bracket scan yields error p50/p95/max `0.005830 / 0.013811 / 0.013811`.

Status is `COMPUTATIONAL_TRIANGLE_AND_CANONICAL_SDF_ORACLE_ONLY`. There was no Godot `PhysicsServer`, production collider, continuous collision, GPU, rendered-frame or GUI measurement. The 0.01 sweep bracket can contribute contact bias. These are mathematical proxy comparisons, not production collision qualification.

## Evidence and integrity

`docs/reports/P3-1-R8/evidence/evidence-bundle.zip` contains raw attempts `run-001` through `run-020` and complete `validation-001/full-suite` and `validation-002/full-suite` logs/records. It excludes only the disposable Godot profiles/caches and profile-probe artifacts; profiles were isolated and preserved locally. The archive contains 307 raw files with a nested SHA-256 list, all independently rehashed after packaging. `docs/reports/P3-1-R8/SOURCE_SHA256SUMS.txt` records physical hashes for the 12 pinned R7.3 source dependencies and final R8 harness. `docs/reports/P3-1-R8/SHA256SUMS.txt` pins the published archive, source inventory, harness and report artifacts. R7.3 source/evidence files and PR #156 were not modified.

R8 focused outputs and full-suite raw artifacts are immutable evidence, not synthetic acceptance thresholds. No renderer/GPU or owner GUI run was performed. No performance metric is scored.

## Conclusion and next gate

R8 delivered the requested bounded diagnostics and canonical regression validation. Independent review should focus on the raw records and the confirmed mismatches. Before any production geometry decision, resolve or formally disposition: (1) the FILL/CARVE triangle with opposite gradient winding; (2) the four X+ LOD1 contour mismatches; (3) large shared-normal discontinuities; (4) the X− picker location error; and (5) the difference between sampled-field and extracted-mesh 3D connectivity, if cave traversability is to be claimed. Define any geometric tolerances prospectively with the owner; none are approved here.

Issue #154 volumetric-authority work, Issue #108 terrain/object conformation, production adoption, merge and release were not performed or authorized. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT` and `F2_G1_RELEASE_HOLD`.
