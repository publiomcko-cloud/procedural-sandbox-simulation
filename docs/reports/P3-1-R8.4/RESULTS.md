# P3.1 R8.4 — Conforming Geometry and Root-Aware SDF Extraction

**Disposition:** `P3_1_R8_4_READY_FOR_INDEPENDENT_REVIEW`
**Geometry gate:** `BLOCKED_WITH_EVIDENCE` at the first minimal X+ conforming-refinement gate.
**Scope:** isolated, test-only research. No production geometry acceptance, integration, schema change, merge, GUI approval, Issue #108/#154 work, or release authorization.

## Identity and provenance

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- R8.4 branch: `bench/p3-1-r8-4-conforming-root-aware`.
- Common R8.2 baseline: `4f08b67522507bd196a74a1089c773f272235343`.
- Measured diagnostic source: `f6bfef10f6be0f903980123f7cbb9073bda98184`, direct parent `7545e94e896f867795b2ec978668d64a953f692d` (pre-registration commit `3403b3b009016be6907e2bd5bc34f14fadaf69e3` is the earlier branch parent).
- R8.4 measured diff against baseline adds exactly two paths: `docs/specs/P3-1-R8.4-EXPERIMENT-PREREGISTRATION.md` and `game/tests/prototypes/p3_1_r8_4_conforming_root_aware.gd`. No production path changed.
- Git blob IDs at the measured source: preregistration `587d2b89d64566f9ace910ca0bce571811a3b52b`; diagnostic `77ac8430966f8e71c6073613448ab1afb809ba71`.
- Diagnostic physical SHA-256: `92C2B6FAF8B3339CAFF82EBF0D40FFC25C823483F90599F313C994A5946CB8BB`.
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.
- Frozen B0 manifest SHA-256: `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd`.
- Exact frozen input digests revalidated by the harness: zero edits `24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b`; CARVE `47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411`; ordered FILL→CARVE `55d45d387bd19829bb38c4e988da25a886765f26cc34e19dd07ed808faa1bd46`.
- The R8.2 source contract pin matched. The harness records the source SHA-256 values for the R8.2 canonical source/diagnostic dependencies in `01-source_and_frozen_input_preflight.json`.
- R8.3-A PR #165 remains open/draft/unmerged at `ae09c279124cc1239f4bf93f0e2ebd9441b8c36b`; R8.3-B PR #166 remains open/draft/unmerged at `546150465fa6b2813db5d9251056a8bf20bd83ae`. Neither branch implementation was imported. R8.2 PR #162 remains open/draft/unmerged at its pinned baseline.
- Evidence PR [#168](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/168) is open, draft and unmerged, based on `bench/p3-1-r8-2-exact-geometry-provenance` at the common R8.2 commit. It contains the measured R8.4 source and the report/checkpoint follow-ups; all commits after measured source `f6bfef10…` are documentation/evidence only.
- The pre-existing R8.2, R8.3-A and R8.3-B evidence inventories were independently rehashed before the candidate: respectively 140/140, 24/24 and 74/74 files matched; their source inventories matched 12/12, 13/13 and 12/12. Earlier worktrees, stashes and user saves were preserved.

## Frozen method and research limits

The preregistration was committed before the only candidate execution. It freezes seed `131102026`, canonical SDF v1, world-space samples, the R8.2 X+ interface oracle and its `1e-5` point key, the unchanged `cross² <= 1e-12` omission rule, and the root-scan algorithm. The candidate was canonical LOD0-cell refinement closure from the failing X+ transition cell; it was not a replacement mesher. No R8.3 implementation was copied into the worktree.

The stop-loss limits were research controls only: four face-neighbor rings, 10,000 unique canonical sample nodes, 20,000 emitted ROI triangles, and 600,000,000 microseconds. No product geometric tolerance was invented or approved.

## Root-oracle findings

The single focused run scanned each of three frozen X− vertical rays (zero edit, one CARVE, and ordered FILL/CARVE) at 4,096 intervals/4,097 samples, and scanned each of triangle 3103's three source edges at the same interval count. The ray direction, origin `(0,8,6)`, and length 12 were fixed. Across all three ray snapshots the scanner detected the same three interior sign-change roots at approximately `y=1.8870053291`, `y=1.4920911789`, and `y=0.3505201340`, plus an exact-zero sample at the lower scan endpoint `(0,-1,6)`. Each ray reported two CSG branch transitions and four possible tangent/near-root candidates. The detected positions did not differ across these three snapshots at the scan's recorded precision; this does not establish that edits are globally irrelevant.

Triangle 3103 edge scans detected 2 sign-bracket roots on edge 0, 1 on edge 1, and 1 on edge 2; possible tangent candidates were 2/1/1. The root records include source `Vector3` bits, active-branch traces, bisection intervals and residuals. The largest displayed residual is about `2.55e-7`; final t brackets are recorded per root. These are finite-scan observations, not a proof of root completeness. Tangent roots, roots narrower than the scan spacing and branch-corner roots without a sign change remain uncertified. Godot did not report a separate precision metadata field; source samples are engine `Vector3` values, so the bisection record must not be interpreted as binary64 positional certainty.

Root-oracle runtime was `1,420,208 µs`. The complete 5.1 MB raw sample record is retained and checksummed. No R8.4 mesh/root displacement was measured: later displacement gates were conditional on the X+ conforming gate.

## X+ reproduction and first candidate gate

The frozen X+ reproduction used world plane `x=16` and 533 common scalar samples at 0.25 spacing. Shared samples were bitwise equal (maximum density difference 0). The negative-side LOD1/positive-side LOD0 reference emitted 33 vs 35 interface segments (2 unmatched); LOD1/LOD1 likewise emitted 33 vs 35 (2 unmatched). The mirrored LOD0/LOD1 control emitted 35/35 and matched. Mesh SHA-256s and unmatched segment identities are in `03-xplus_frozen_reproduction.json`. The two passing reproduction controls do not substitute for the later conditional candidate-control stage.

The one and only conforming-refinement candidate failed to close by the frozen four-ring limit. It reached ring 4, promoted 22 cells and retained 23 fine cells; it inspected 70 interfaces and ended with 9 unmatched active interfaces. It had 420 unique sample lattice nodes, 490 emitted fine-ROI triangles, peak resident reference-plus-candidate triangles 630, estimated mesh-attribute bytes 45,360, and candidate runtime 209,901 µs. Research resource ceilings were not exceeded; the ring stop-loss was reached without closure.

The unchanged topology diagnostics reported 58 internal open edges and 16 finite-crop boundary edges, 0 degenerate retained triangles, 0 nonmanifold edges, 0 nonfinite triangles and 0 winding-neutral/opposed triangles. The 16 crop edges are separately classified; the 58 internal opens remain a mandatory failure. Thus the candidate violates both the zero-unmatched-interface and zero-unexplained-internal-open-edge advance invariants. It is not an acceptable surface and was not published or promoted as a solution.

**Gate result:** X+ conforming transition `FAIL/BLOCKED`. No retry was made. Mirrored/same-LOD candidate controls, X− root-aware extraction, triangle 3103 root-aware extraction, ordered FILL/CARVE extraction, and uniform 0.25/0.125 comparisons are `NOT_RUN_AFTER_PREDECESSOR_GATE`. In particular, no candidate surface-displacement comparison exists. R8.2's historical X− mesh/root displacement of about 0.36611 world units is cited only as prior baseline evidence, not as a remeasurement or R8.4 result.

## Validation

Focused execution used one Godot process only, PID 53048, at source `f6bfef10…`, with isolated profile `C:\Users\PUBLI\AppData\Local\Temp\P31-R84-run-001-profile`. Exact command:

```text
C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path C:\r84\game --script res://tests/prototypes/p3_1_r8_4_conforming_root_aware.gd
```

Exit code was 1, as expected for the blocked geometry candidate. The script emitted four phase records, four assertions, no harness assertion failures, and terminal `status=BLOCKED`, reason `minimal_xplus_conforming_gate_failed_or_stop_loss_reached`. Stderr was empty; stdout had no parser or `SCRIPT ERROR`. This records a candidate gate failure, not a test harness PASS.

The full `scripts/validate.ps1` was then run once, against the unchanged measured source, with Godot 4.7.2 and isolated `APPDATA`/`LOCALAPPDATA` under `C:\Users\PUBLI\AppData\Local\Temp\P31-R84-validation-001-profile`. It completed in 545.753 seconds with exit code 0 and `VALIDATION_PASS: L0-L2`. Twenty assertion-bearing suites totaled **14,990 assertions, zero failures**; import, source-presence and main-scene startup gates also passed. The suite lines and exact per-suite counts are retained in the full log. Three nonfatal warnings reported colinear camera target/up vectors; no parser, `SCRIPT ERROR`, or other error was found. The validator says rendered pixels are not assessed. This regression PASS does not override the R8.4 geometry gate failure.

Headless validation includes CPU-generated performance output but does not establish presented FPS, GPU completion, renderer appearance, physics/collider behavior or owner GUI acceptance. Process working-set/RSS was not captured for the R8.4 candidate; the report gives bounded sample/triangle and estimated attribute counts only.

## Evidence map and integrity

All attempts are preserved in `docs/reports/P3-1-R8.4/evidence/`:

- `parse-001` through `parse-004`: initial parser diagnostics and corrected final import/check-only evidence. Early harness parse failures are retained; parse-004 passed.
- `run-001`: the single source/frozen-input preflight, complete root scan, X+ reproduction, candidate progress, terminal result, process metadata and stdout/stderr.
- `validation-001`: complete raw full-validator output and process/profile metadata.
- `SHA256SUMS.txt`: SHA-256 for every evidence file except the checksum file itself. It is generated only after raw evidence is complete.

`evidence/README.md` lists the count and aggregate bytes. No raw evidence was overwritten. The new generated `.gd.uid` files remain untracked and were not staged. The development worktree and all prior PRs/evidence remain unchanged.

## Conclusion and next gate

The bounded experiment is complete and ready for independent source/evidence review, but the proposed conforming propagation strategy failed its first mandatory geometry gate. The correct technical conclusion is **no accepted R8.4 combined pipeline**. Before any future geometry attempt, independently review this evidence and decide whether to authorize a different bounded conforming-transition strategy. Do not proceed directly to root-aware extraction or widen propagation beyond the registered research limit without a new decision. No geometry acceptance tolerance is approved.

No production path, save, schema, gameplay, dependency, native component, merge, Issue #108/#154 action, PR #162/#165/#166, or protected F2-G1 state was changed. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
