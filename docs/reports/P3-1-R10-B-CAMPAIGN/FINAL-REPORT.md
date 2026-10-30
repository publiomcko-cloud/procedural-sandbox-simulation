# P3.1 R10-B — Final constrained-realization and ray-causality report

**Campaign status:** `P3_1_R10_B_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`

**Branch:** `exp/p3-1-r10-b-constrained-realization`

**Measured source:** B6 execution HEAD `b1dd90ca7adb6ef941f3dc933008648fd1a91de6` (B6 code commit `abe1d54dc8986fec2513b8ce261197867f4b8095`, parent `f622468dd750775c51394ae595fa5019114e7a1c`).

**R10-A baseline:** final R10-A publication source and frozen R9.2 inputs as pinned in `PREREGISTRATION.md`; source branch remains separate from production.

**PR base:** `exp/p3-1-r10-a-topology-authority` at `f6f4a47bcb9f98ee7b8648f88a4db2ccf8317294`; this is a stacked evidence PR and leaves PR #207 unchanged. The R10-B draft PR URL is recorded after publication; no production integration or merge.

## Result

No candidate qualified the frozen equal-LOD mesh. B2–B6 each executed one distinct, pinned geometry hypothesis and returned `FAILED_TARGET`. B1 was launched once but its script error occurred before a valid geometry result; it is retained as `BLOCKED_HARNESS_ERROR`, not counted as a geometric failure and not rerun under the preserved continuation boundary. Thus five geometry hypotheses produced valid terminal results; all six numbered B1–B6 slots are closed, and no B7 is authorized.

R10-B did **not** prove global exact-root infeasibility. It only tested the bounded move/search domains below. The final A6 equal-LOD state still has 10 internal open edges, 21 missing required adjacencies, and 7 required faces rejected by the unchanged `cross_squared > 1e-12` cutoff. There is no production-ready constrained realization.

## R10-B hypothesis disposition

| Attempt | Run source / parent | Hypothesis and bounded domain | Result/search | Equal-LOD and required adjacency | Internal opens / nonmanifold / winding | Minimum cross² / final sub-cutoff faces | Controls / ROI ray | Volume / mixed LOD / abort |
|---|---|---|---|---|---|---|---|---|
| B1 | `eae562eb310d44cd6b5208eaee744d893a4139e7` / `21c461a57af90e0fb661c47f66b75466de1f34d2` | Non-monotonic constrained flip BFS; intended bounded exact-root search | `BLOCKED_HARNESS_ERROR`; script errors prevented valid solver evidence; no state count is admissible | Partial artifact excluded | Partial counters excluded | Not admissible | Partial 6-control output; ray wiring failed | Not admissible; no resource abort |
| B2 | `823b76111c46d7f640a59c70059c2838d7182b22` / `f32193acb2cf550832a121391243c3364b2ddd22` | Exact local cavity retriangulation, face-adjacency rings 0–4 | `FAILED_TARGET`; bounded search complete: 5 states, 910 edge keys; no successor | Fail; 21 adjacencies missing | 10 / 0 / 0 | `1.67075673894024e-16`; 3 faces | 6/6; 0/25 disagreements | Original volume identity pass; mixed skipped; no abort |
| B3 | `c4d60e93e38a17d4b27be8e2f86e61ddf67481a1` / `e4ba97ce071670ecdd064d51ae12bad50703aebd` | Strict constrained-Delaunay/Lawson local flips | `FAILED_TARGET`; 1 initial state, 182 edges, 0 flips; bounded local optimum | Fail; 21 missing | 10 / 0 / 0 | `1.67075673894024e-16`; 3 faces | 6/6; 0/25 | Volume pass; mixed skipped; no abort |
| B4 | `0aa6295cb2864767819e8de268c1e7af7b32f1eb` / `146033336f343f6ad5489ebbe8879d1822b01dcd` | Canonical-field Steiner subdivision of 8 selected parent polygons; 24 child faces | `FAILED_TARGET`; field projection ran; all 24 child faces remained below fixed cutoff | Fail; 72 adjacencies missing | 13 / 0 / 0 | Minimum child cross² `9.69596215898221e-18`; 24 children rejected | 6/6; 0/25 | Volume pass; mixed skipped; no abort |
| B5 | `15955fb3742390fc4bc2f7409fdc82e3a5021eac` / `310c53f0a250cc16449f52ec8d10497ac5c1af35` | Derived 0.125 local field over the same 2×2×2-world-unit ROI; 16³ cells; all six outer contour checks | `FAILED_TARGET`; 729 nested samples matched exactly, but four nonempty faces mismatched | Fail; 48 adjacencies missing | 27 / 0 / 0 | `7.96887604160111e-17`; 16 faces | 6/6; 0/25 | Original and derived volume integrity pass; mixed skipped; no abort |
| B6 | `b1dd90ca7adb6ef941f3dc933008648fd1a91de6` / `abe1d54dc8986fec2513b8ce261197867f4b8095` | Cutoff-directed deterministic beam over exact-root internal 2–2 flips; width 32, 1,024 states, 12,000 candidates, 30 s | `FAILED_TARGET`; search exhausted after 1 state / 182 edges without a legal successor; limits not hit | Fail; 21 missing | 10 / 0 / 0 | `1.67075673894024e-16`; 3 faces | 6/6; 0/25 | Original volume identity pass; mixed skipped; no abort |

The B4 projected points had maximum observed displacement `0.000102956255432218` world units, maximum source-plane residual `0.000101522644399665`, and maximum absolute final canonical density `4.8112869263095e-06`. Those values are observations under the pinned experimental projector, not accepted geometric tolerances. B5’s four mismatching nonempty faces were X− (20 vs 38 segments), X+ (20 vs 42), Y− (16 vs 32), and Z− (17 vs 35); Y+ and Z+ were both empty in both meshes. The B5 fine mesh had 2,560 triangles, 27 internal open edges, 147 ROI boundary edges, 48 missing adjacency obligations and 16 cutoff rejections. Fine sampling at shared nodes alone did not preserve extracted interface contours.

B5 compared nested scalar samples and outer mesh contours, but did not establish a complete one-to-one identity mapping from every refined zero root to the frozen source topology. The contour/topology failures already reject B5, and this missing mapping is an additional reason it cannot qualify.

### Attempt accounting

`ATTEMPTS_USED=5 valid geometry hypotheses (B2–B6); B1 was one launched pre-geometry tooling attempt and is recorded separately as BLOCKED_HARNESS_ERROR.` The preserved continuation boundary did not permit rerunning B1. No additional hypothesis slot or B7 was created. This disposition is not a claim that the written solver-consumption rule would count the B1 script-error run as a geometry hypothesis; it records both the invalid B1 run and the five valid geometry runs explicitly.

## Ray-causality classification

`RAY_CAUSALITY_CLASSIFICATION=ORACLE_SCOPE_MISMATCH_NOT_MESH_REGRESSION`.

The same frozen mesh SHA `04c6ceb842b964caba4e254f94c9f4b32881dae79994b961ac01029a48f64553` produced 0/25 under R9.7’s closed-ROI root filtering that excludes cropped Y end-face roots, and 9/25 under a full finite-ray scan that includes out-of-ROI roots. The nine global-scan indices were `[2,8,9,13,14,18,19,23,24]`, matching R10-A’s full-scan oracle. R10-B’s corrected ROI comparison remained 0/25. This explains the apparent numeric difference without asserting that either scope is universally preferable; the campaign uses the matching frozen ROI scope.

## Required final fields

- `FINAL_TOPOLOGY_ARCHITECTURE`: topology graph/root obligations remain authoritative; no downstream geometry realization met them.
- `FINAL_CONSTRAINED_REALIZATION`: no qualified realization.
- `FINAL_EXACT_ROOT_FEASIBILITY`: globally inconclusive. B2 excludes only rings 0–4; B3 found no strictly improving Lawson edge; B6 exhausted the fixed initial-state legal 2–2 edge-flip graph after one state; none proves global impossibility.
- `FINAL_EQUAL_LOD`: FAIL; the best retained A6/B2/B3/B6 mesh has 10 internal opens, 21 missing adjacencies and 7 cutoff rejections.
- `FINAL_REQUIRED_ADJACENCY`: 21 missing on the retained baseline mesh.
- `FINAL_INTERNAL_OPEN_EDGES`: 10.
- `FINAL_NONMANIFOLD`: 0.
- `FINAL_WINDING`: 0 recorded inconsistencies on the retained mesh; this does not compensate for open topology.
- `FINAL_RAY`: PASS in the frozen ROI scope, 0/25; separate global full-scan diagnostic is 9/25 because it uses a different root scope.
- `FINAL_CONTROLS`: 6/6.
- `FINAL_VOLUME`: PASS; original revision-2 volume SHA `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`, payload SHA `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`.
- `FINAL_MIXED_LOD`: not run; equal-LOD gates never passed.
- `FINAL_DETERMINISM`: not run; there was no passing geometry candidate to repeat.
- `FINAL_PERFORMANCE`: failed-candidate diagnostic timings only; no performance acceptance claim.
- `FULL_E2E_RESULT`: `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE`.
- `FULL_VALIDATION_RESULT`: `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE`; per the preregistered sequential gate, no full-project validator ran without an equal-LOD, ray and mixed-LOD passing candidate.
- `EVIDENCE_INTEGRITY`: 314 non-profile raw evidence files are preserved in the final ZIP and independently hash-verified against the adjacent index. No prior attempt was overwritten.
- `FINAL_ARCHITECTURAL_RECOMMENDATION`: do not integrate. Retain canonical roots/topology as authority and develop a new, separately authorized constrained-realization design that can satisfy the unchanged cutoff and exact interfaces. Do not infer global infeasibility or adopt a tolerance from these bounded experiments.

## Source pins and raw evidence

Pinned executable experiment sources at B6 include campaign physical SHA-256 `1ff5a653099e2661af44d5e95fcf777f5f66936d7a2beebb6277f5ba3f96a636` (Git blob `a68df73ae77a3b0868fd636f4eabc9012acb85b9`), B6 realizer physical SHA-256 `794024b4c886857fd718aec6b2a2443122920838c436c14a39a1bcde3ed31a91` (blob `7a0a8efb42a2595e6c1f8a680730e81cb897917c`), unchanged R10-A authority `feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216`, Candidate D `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`, manifest `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`, ray fixture `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7`, and Godot executable `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

- Raw evidence ZIP (314 files; isolated `.godot` profiles excluded): [`R10B_RAW_EVIDENCE_FINAL_20261030.zip`](evidence/R10B_RAW_EVIDENCE_FINAL_20261030.zip), SHA-256 `24803f5858dd54cd27034162e7ebbc95e2044fbe8675b2f9330350193169c4b7`, 1,028,076 bytes.
- Per-file SHA-256 index: [`R10B_RAW_EVIDENCE_FINAL_SHA256.json`](evidence/R10B_RAW_EVIDENCE_FINAL_SHA256.json), SHA-256 `94e7ba58072c220f2584d9eeb50abbb2caa9180c0d48c5b45d81afee45998966`.
- Original evidence root: `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0`.
- B1–B6 attempt reports and preregistrations remain separate files in this directory. B1–B4 raw hashes are in their original reports; B5/B6 raw hashes are in their result reports.

Full frozen E2E, repeat runs, mixed-LOD qualification and `scripts/validate.ps1` remain unrun by design because no geometry candidate cleared the sequential gates. This R10-B evidence authorizes only independent review, not production adoption, merge, release, Issue #108/#154, schema changes, or changes to the five F2-G1 holds.
