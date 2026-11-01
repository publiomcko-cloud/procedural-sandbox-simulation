# 2026-11-01 — R12-CXR R5-4 synthesis result

## Disposition

`R12_CXR_R5_SUPPORT_SYNTHESIS_PARTIAL_WITH_EVIDENCE`

The one frozen target execution completed normally but emitted no support candidates. The R5 candidate graph and D3 were correctly skipped. The result is neither an analytic support-domain exhaustion proof nor a structural incompatibility proof. No fifth target execution was made: current diagnostics suggest field-residual rejection may merit localized investigation, but do not yet identify a specific implementation defect or establish that every declared feasible-region construction is empty. Another attempt must first have a new evidence-backed source correction and a fresh pinned preflight.

## Source, execution, and frozen inputs

- Measured source: `8e5211e0665b6f57839d5c7eeae51c28c64325f6`; parent `0543cd1ca3c438b68f58799e1eb5f49963bbf09f`; tree `1531f2e5c2085f500437f38e0c8be22e63376e0b`.
- Detached execution checkout: `C:\r12cxr-r5-target-8e5211e-20261101`; tracked worktree remained clean.
- Execution ID: `r5target2026110104a91e4f3e7c8f4f8f9a`.
- Scenario: `R9.2.SEAM.XPLUS_EQUAL.v1`.
- Godot `4.7.2.stable.official.ed1daf0bf`, binary SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.
- Manifest SHA-256 `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`; frozen cavity SHA-256 `a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6`.
- Candidate D SHA-256 `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`; topology fixture `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d`; topology `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`; graph fingerprint `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9`; residual fixture `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23`; volume `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`; payload `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`; revision 2; ray fixture `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7`.

Exact source inventory (Git blob / physical SHA-256) was captured by the dispatcher and independently rechecked against the detached source; all seven entries matched:

| Path | Git blob | Physical SHA-256 |
|---|---|---|
| `.gitattributes` | `6329574393b4c3244efa79a15fc4c231e4dd3efc` | `273399d8eda394155672f583cb7fe0e537b7a71ee6b8d3737662e77b78f1ee8f` |
| `docs/specs/P3-1-R12-CXR-R5-CONSTRAINT-GUIDED-SYNTHESIS.md` | `1c32c67c7339092d0391a40b8c22324d42bb265c` | `e9cc3d46c6d807ac7ecc461f997603d55cf703a9d1b2eafbbc58a40f67d1ec0f` |
| `game/tests/prototypes/fixtures/r12_cxr_r5/frozen-cavity.json` | `645bef08c35d25864751e1fce5a4a2e37e7b0cde` | `a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6` |
| `game/tests/prototypes/fixtures/r12_cxr_r5/r4-d1-result.json` | `dd783b5a77fba1e881a8f8c0f35fe6ddbee46e67` | `927ec58f8f4e7821d9acb27a46068a4fa5fccf4f354f22b24be9cf88f90970c4` |
| `game/tests/prototypes/p3_1_r12_cxr_r5_campaign.gd` | `df1321c333ec3503cd71d9e84552bf048db70eac` | `9c362b77c1c30d895d61050f63d810d8cb22cb236919485815cbfe8630d87ec3` |
| `game/tests/prototypes/p3_1_r12_cxr_r5_contract_tests.gd` | `c36c142c01708a9b7bd2f21ddc9d4f0c11b6c3da` | `4b4f563340e32f447ad4744fc9daf2a778e43c751636fad6a4a158de6d118d28` |
| `game/tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd` | `001f5d51b168e099822469f94e2891ef135cb6ce` | `da10e96968a5c93c273c8a0125277edc0fb911d73cb8e9df57c568bb354db94e` |

## Target execution evidence

The dispatcher started one Godot process after writing the launch-intent record. It emitted exactly one `R5_SYNTHESIS_ENUMERATION_BEGIN` with the frozen execution ID and source. Marker, launch intent, start record, terminal record, result path and process command line agree. Godot PID was `34224`; launcher PID and captured parent PID were both `41284`. Command was `--headless --path ./game --script res://tests/prototypes/p3_1_r12_cxr_r5_campaign.gd`. Exit code 0; duration 5,688.894 ms; stderr 0 bytes. No retry occurred.

Resource terminal summary: max captured process working set `6,434,816` bytes; minimum free commit `7,819.6 MiB`; minimum available physical memory `30,481.3 MiB`; warning threshold not crossed; hard-stop not reached; resource monitor reported no error. These are host/process observations only, not performance acceptance.

## Synthesis and required closeout fields

```text
CAMPAIGN_STATUS=R12_CXR_R5_SUPPORT_SYNTHESIS_PARTIAL_WITH_EVIDENCE
MEASURED_SOURCE_SHA=8e5211e0665b6f57839d5c7eeae51c28c64325f6
PUBLICATION_HEAD_SHA=see commit containing this checkpoint (source remains the measured SHA above)
VALID_R5_EXECUTIONS_USED=4 of 5; fifth not run
FROZEN_CAVITY_HASH=a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6
ELIGIBLE_SOURCE_PAIR_COUNT=15
ZERO_SET_PRIMITIVE_COUNT=502 nonempty tetra primitives (342 triangle, 160 quad); 662 zero facets emitted
FEASIBLE_REGION_COUNT=392 bounded arrangement regions processed; exact genuinely feasible-region count UNKNOWN_NOT_CAPTURED
EMPTY_FEASIBLE_REGION_COUNT=UNKNOWN_NOT_CAPTURED
SUPPORT_CANDIDATE_COUNT=2416 critical candidates
SUPPORTS_WITH_LEGAL_EDGE=NOT_RUN_NO_RETAINED_SUPPORTS
SUPPORTS_WITH_LEGAL_TRIANGLE=0 accepted single-support candidates
LEGAL_CANDIDATE_EDGE_COUNT=NOT_RUN_NO_SYNTHESIZED_SUPPORTS
LEGAL_CANDIDATE_TRIANGLE_COUNT=0 single-support feasible candidates; graph gate NOT_RUN
MIN_LEGAL_TRIANGLE_CROSS_SQUARED=UNKNOWN_NOT_CAPTURED (no legal triangle)
MAX_LEGAL_TRIANGLE_CROSS_SQUARED=UNKNOWN_NOT_CAPTURED (no legal triangle)
CANDIDATE_GRAPH_SHA=NOT_RUN
D3_SEARCH_NODES=NOT_RUN
D3_SOLUTIONS=NOT_RUN
D3_TERMINAL_REASON=NOT_RUN_NO_LEGAL_TRIANGLES
FINAL_EQUAL_LOD=NOT_RUN
FINAL_TOPOLOGY_ROUNDTRIP=NOT_RUN
FINAL_INTERNAL_OPENS=NOT_RUN
FINAL_NONMANIFOLD=NOT_RUN
FINAL_WINDING=NOT_RUN
FINAL_CUTOFF_REJECTIONS=NOT_RUN
FINAL_CONTROLS=NOT_RUN_PENDING_EQUAL_LOD_PASS
FINAL_RAY=NOT_RUN_PENDING_EQUAL_LOD_PASS
FINAL_VOLUME=NOT_RUN_PENDING_EQUAL_LOD_PASS
FINAL_MIXED_LOD=NOT_RUN_PENDING_EQUAL_LOD_PASS
FINAL_DETERMINISM=NOT_RUN_PENDING_EQUAL_LOD_PASS
FULL_E2E_RESULT=NOT_RUN_PENDING_EQUAL_LOD_PASS
FULL_VALIDATION_RESULT=NOT_RUN_PENDING_EQUAL_LOD_PASS
EVIDENCE_INTEGRITY=PASS for indexed copies and source inventory; resource CSV has locale delimiter defect described below
FINAL_ARCHITECTURAL_DISPOSITION=architecture remains selected; R5 has not closed the field-derived support-placement gap; no continuum or structural infeasibility claim
```

Additional synthesis facts: 3,072 tetrahedra scanned; 662 facets; 1,665 constraint lines; 392 arrangement regions; no cap reason and no cap hit; finite critical-candidate enumeration completed, but `analytic_feasible_support_domain_exhausted=false`. Raw/retained support counts were 0. Rejection histogram: field-residual invalid 1,140; at/below frozen cross² cutoff 753; edge outside/crosses boundary 280; crosses required topology arc 108; duplicates topology root 91; no residual owner 33; required arc endpoint inside candidate triangle 6; vertex outside boundary 5. Existing cutoff stayed `1e-12`. Graph gate reason `NOT_RUN_NO_SYNTHESIZED_SUPPORTS`; D3 reason `NOT_RUN_NO_LEGAL_TRIANGLES`.

The 1,140 residual rejections are a diagnostic lead, not a proven defect: the target output does not retain per-candidate coordinates, barycentric weights, or residual magnitudes, so the cause cannot be distinguished from valid frozen-gate rejection from this run alone. The fifth execution remains unused until a bounded correction is justified by source-level cause analysis (for example, preserving a bounded set of exact residual-rejection witnesses) and receives a fresh source pin/preflight. Do not rerun attempt 4.

## Evidence packaging and limitations

Raw attempt artifacts were copied with `CreateNew` and independently hash-compared into [`attempt-04-scientific-20261101`](../reports/P3-1-R12-CXR-R5/evidence/attempt-04-scientific-20261101/). Twelve raw artifact hashes are listed in its `artifact-index.json`; index SHA-256 is `4769fa42e77ff3fe5f91e7c3d9ae76710cb7c59667db0f5b029dd1c1b2e06a75`. Result SHA-256 is `019607e1d3c4f980a31b8104b16d1263d687ff6c88ddb5731b83cefe2681d094`, matching the terminal record. Stdout SHA-256 is `8e7687bea0f09e8b59ae029d1fb4c683ea23e9ba766cce61d034e602469cbbe7`; stderr is empty (`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`). Raw resource CSV SHA-256 is `cd3c2d1bb5642834240e3b9d3198385da8ae23e87f95258564368997579312d9`.

The resource CSV is not valid four-column CSV on this locale: decimal commas emitted by PowerShell's current-culture `-f` formatting create rows with 4, 5, or 6 comma-separated fields. Raw bytes are preserved; do not parse it as a valid CSV or infer point samples from it. The dispatcher's terminal JSON separately captured min/max resource summary, and its CIM resource monitor completed without error. A supplementary `Get-Counter` probe was unsupported on this host; it did not launch a process. A first evidence-index writer invocation also stopped before index creation due to a PowerShell boolean-literal typo; raw copies were preserved without overwrite, the index was then written with `CreateNew`, and all 12 copied hashes verified. Neither host-side issue altered the scientific execution.

No D3, equal-LOD, downstream gates, full E2E, or `scripts/validate.ps1` ran because no legal candidate triangle existed. R5-4 is not a PASS. The R5 branch remains draft/unmerged; PR #216 is unchanged. Production source, saves, schemas, native dependencies, and protected state were untouched. All five F2-G1 holds remain unchanged.
