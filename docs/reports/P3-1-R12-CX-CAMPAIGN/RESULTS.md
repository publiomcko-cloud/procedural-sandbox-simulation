# P3.1 R12-CX Final Campaign Results

Evidence PR: [#211](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/211), draft and unmerged, stacked on [#210](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/210).

Date: 2026-10-31
Disposition: `P3_1_R12_C_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`
Measured source: `a9c1353db49a7bb5607ce8eaf91d8032c7dc4bea`
Direct parent: `07c93797fa3f26d3c9143433638f193e7c5cef00`
Measured tree: `c270eb914ebd8d1a2248505bbc6f59fefdff529a`

## Result

The authorized final R12-C hypothesis, `R12CX_RESIDUAL_FIELD_CONSTRAINED_MICROPATCH`, was invoked once as `CX_GEOMETRY_FINAL04`. The campaign passed its pinned source, topology, volume and fixture preflight, emitted `R12CX_LOCAL_PATCH_SEARCH_BEGIN`, and returned one terminal `FAILED_TARGET` result with invariant `cx_bounded_patch_search_failed`. This valid target result consumes the last R12-C hypothesis. There is no surviving equal-LOD geometry candidate. No retry, CX2, mixed-LOD run, deterministic repeat, full E2E, or full project validation was performed.

The final result JSON is `CX_GEOMETRY_FINAL04/r12cx_CX_GEOMETRY_FINAL04.json`, SHA-256 `9c5b4ef8611bb1a91aa3d9e2deaa8f2fcca06bc5246d362b515fe8f9d10b2d10`. The terminal stdout SHA-256 is `57e7033477626da0cba821ebafb087a93b99412eacb902ea4b9794e72de6d15f`; stderr was empty (SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`). Exit code was 0 because the campaign successfully serialized a failed-target result; it is not a geometry PASS.

The search-start record reported two merged residual cavities for three residual faces and the frozen limits. The result wrapper did not preserve the nested search failure details. Consequently, the JSON's `local_search_nodes: 0` is not treated as evidence that zero states were explored, and `local_search_complete: false` is not promoted to proof of complete bounded-domain exhaustion. The valid geometry outcome is `FAILED_TARGET`; the precise inner search cause and node count remain unavailable. This experiment is not proof of mathematical infeasibility.

## Required CX fields

| Field | Observed disposition |
|---|---|
| `CX_SOURCE_SHA` / parent / tree | `a9c1353db49a7bb5607ce8eaf91d8032c7dc4bea` / `07c93797fa3f26d3c9143433638f193e7c5cef00` / `c270eb914ebd8d1a2248505bbc6f59fefdff529a` |
| `CX_HYPOTHESIS` | `R12CX_RESIDUAL_FIELD_CONSTRAINED_MICROPATCH` |
| C6 source / topology fixture / residual fixture | `4535f4c965db67adab7c93e448492c54be916c92` / `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95` / `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23` |
| Residual faces / merged cavities | 3 / 2 |
| Cavity levels | No complete patch result; unavailable |
| Support candidates / selected | 0 / 0 |
| Support provenance SHA | Not produced |
| Limits | L0–L3, 64 triangles/cavity and patch, 4,096 search states/cavity, 12,288 total, 32 retained solutions/cavity, 10,000,000 µs search, 30,000,000 µs total realization; unchanged `cross_squared > 1e-12` |
| Search | Started; terminal wrapper reason `cx_bounded_patch_search_failed`; nested cause and actual node count not captured |
| Changed triangles / final triangles / realization map | No surviving candidate; not produced |
| Topology round-trip / signature | Not evaluated on a final candidate |
| Minimum final cross-squared / final cutoff rejects | Not produced; no final candidate |
| Missing obligations / opens / nonmanifold / winding | Not evaluated on a final candidate |
| Controls | `NOT_RUN_EQUAL_LOD_GATE_FAILED` (6 controls not run) |
| ROI ray / global diagnostic | `NOT_RUN_EQUAL_LOD_GATE_FAILED` / not run |
| Volume | PASS, SHA-256 `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`; payload `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`; revision 2 |
| Surface deviation | Not measured; no approved geometry tolerance |
| Mixed LOD / determinism / full E2E / full validation | `NOT_RUN_EQUAL_LOD_GATE_FAILED` / same / `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE` / same |
| Resource aborts | 0 |
| Result class | `FAILED_TARGET`; CX consumed |

## Final R12-C campaign fields

- `FINAL_CAMPAIGN_STATUS`: `P3_1_R12_C_ATTEMPTS_EXHAUSTED_WITH_EVIDENCE`.
- `VALID_GEOMETRY_HYPOTHESES_USED`: six (C2–C6 and CX); C1 remains `NOT_APPLICABLE` and unconsumed.
- `C1_DISPOSITION`: `NOT_APPLICABLE_UNCONSUMED`.
- `C2_DISPOSITION`–`C6_DISPOSITION`: each consumed with its preserved `FAILED_TARGET` result. C6 retained its previously passing topology, incidence, controls, ROI-ray and volume gates but left three fixed-cutoff residuals, so its equal-LOD gate failed.
- `CX_DISPOSITION`: consumed once, `FAILED_TARGET`, no candidate. No additional hypothesis is authorized or started.
- `FINAL_TOPOLOGY_ARCHITECTURE`: frozen C6 authority reproduction passed (369 roots, 870 arcs, 502 polygons); no final CX realization map was produced.
- `FINAL_REALIZATION_ARCHITECTURE` / map / round-trip: no surviving realization; no final map or round-trip result.
- `FINAL_EQUAL_LOD`: failed at bounded patch realization (`cx_bounded_patch_search_failed`).
- Required obligations, internal opens, nonmanifold, winding, minimum final cross-squared and final cutoff rejects: not measured for a candidate.
- `FINAL_CONTROLS`, `FINAL_RAY`, `FINAL_MIXED_LOD`, `FINAL_DETERMINISM`: not run after equal-LOD failed.
- `FINAL_VOLUME`: passed; frozen volume and payload identities remain unchanged.
- `FINAL_PERFORMANCE`: `UNSCORED`; no presented-frame or GPU evidence.
- `FULL_E2E_RESULT` / `FULL_VALIDATION_RESULT`: not run by the sequential gate.
- `EVIDENCE_INTEGRITY`: 42 indexed raw files plus the index were re-hashed after extraction; zero mismatches. Archive SHA-256 `62740d552875ba2af6b6e59eb678323461d53405e11f4ba3788481f88872cfe6`; index SHA-256 `7c3158cf1a052b04f7b1a5cda6c1787ec59f95abe05267730f21a754d37cf6da`.
- `FINAL_ARCHITECTURAL_RECOMMENDATION`: do not adopt this prototype in production. R12-C's authorized hypothesis budget is exhausted with evidence; any later work requires a separately authorized campaign and must not claim this bounded search proves no valid mesh exists.

## Pregeometry recoveries and exact-source gates

Three target invocations stopped before local patch search and did not consume CX:

1. `CX_GEOMETRY_FINAL01` on `a2a01b2…`: JSON root-position arrays were assigned directly to `Vector3`; no search marker or states.
2. `CX_GEOMETRY_FINAL02` on `949ceed…`: the adapter expected fields absent from the C6 rejection schema; no search marker or states.
3. `CX_GEOMETRY_FINAL03` on `07c9379…`: pinned residual diagnostic scalars were rounded, while the adapter required near-bitwise equality; no search marker or states.

Corrections were limited to fixture reconstruction and validation. The C6 rejection identity now uses its actual `triangle_id`, `source_polygon_ids`, and `root_ids`; exact reconstructed area is checked against C6's precise `cross_squared`, while the pinned rounded annotation is separately bounded to 0.5%, finite, positive, and below the unchanged cutoff. The residual fixture bytes and SHA remain unchanged. The final contract suite added JSON position, C6 schema, mismatch, rounded-metadata, nonfinite and start-classification regressions.

On exact measured source `a9c1353…`, P1–P8 passed: P5 cold import exit 0; P6 campaign check-only exit 0; P7 realizer check-only exit 0; P8 contract suite exit 0, 44 assertions, zero failures. The Godot binary was `4.7.2.stable.official.ed1daf0bf`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. The earlier incorrect P6 check-only invocation, launcher syntax failure and incorrect stage-0 path are retained and did not start geometry.

The final target process was PID 22464, launched by PowerShell PID 33756. It exited 0 after 3,411 ms. Three commit-memory samples showed 11.374–11.406 GiB free commit, above the 3 GiB warning and 2 GiB abort thresholds; no resource abort occurred. The sampled process working set is retained as raw diagnostic only and is not treated as a reliable application memory measurement.

## Evidence and safety

The raw evidence bundle is [P3.1-R12CX-FINAL-EVIDENCE.zip](evidence/P3.1-R12CX-FINAL-EVIDENCE.zip), with [evidence index](evidence-index.json) and source identity record in this report directory. Raw attempt directories remain under `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r12cx_a9c1353_validation_20261031` and the prior immutable evidence roots. Earlier failures were preserved; no attempt directory was reused or overwritten.

No production terrain, save, schema, user save, PR #210, native dependency, protected path, ACL, VM, or F2-G1 state was changed. No mixed-LOD, E2E, `scripts/validate.ps1`, or GUI acceptance is claimed. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
