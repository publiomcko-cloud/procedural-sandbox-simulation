# CHK-2026-10-22-P1-1B-B1-1-CROSS-REGION-LEDGER-BATCH-11-UNSCORED-REVIEW

**Date recorded:** 2026-10-22, America/Sao_Paulo (exact host execution timestamp not independently attested).
**Event:** one consolidated cross-region ledger/seam UNSCORED qualification of 11 frozen scenarios.
**Published as:** proposed immutable evidence checkpoint on separate docs-only draft PR #101; not merged.
**Disposition:** `BATCH_11_UNSCORED_CONTRACT_REVIEW_PASS / CODEX_HOST_RUN_11_REPORTED_PASS / INDEPENDENT_CANONICAL_DIGEST_11_MATCH / RAW_WIN_LOGS_NOT_INDEPENDENTLY_REPLAYED / NO_SCORED_ACCEPTANCE`.

## Verified GitHub source provenance

Repository `publiomcko-cloud/procedural-sandbox-simulation`, verified main `ea4422d90726d3f2fe6d5cef097126268f93685a`. [Feature PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) remains open/draft/unmerged at exact R7 SHA `2b4355363a43b73476715cf4002e31575bf9828d`, parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`. Frozen manifest Git blob `fde2ff84e2754cfef48052b32998903f45276aa1`, reported manifest + sidecar physical pin `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd`; Godot 4.7.2 console binary SHA `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. Child-engine binary distinct reported physical SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`; two physical executables must not be conflated. No source or manifest edits.

## Independent canonical SHA-256 verification

Rebuilt all 11 scenarios independently from reviewed R7 `Contract.build_commands`, 16 signed distributed region keys, `_command` shape, explicit B0E manifest commands and sorted-key `canonical_json`. All 11 exact full-list digests match the reported Codex replay:

| Frozen scenario | Commands | Independently computed SHA-256 |
| --- | ---: | --- |
| B0A.CORNER.NEG_XZ.N032.v1 | 32 | `40e432b56c14e82d6993076470c9800da142961b8c16a20ec06ab9d35c2efc0f` |
| B0A.DISTRIBUTED.N032.v1 | 32 | `1e3a39eb7a96b1d73623589d2ca546cc4e6f4e3e94c636824ab6513c954d6cc8` |
| B0E.SEAM.POS_X.CARVE_FILL.v1 | 2 | `b8575cb850df372c9f53b76e5094fc4f2c6a08d9414be531e104cb819283b581` |
| B0E.SEAM.POS_XZ.CARVE_FILL.v1 | 2 | `fa50ba8c098ffd6f6df3db6eda28e28b56fcf5ffa65960973663db646050590e` |
| B0E.SEAM.NEG_XZ.CARVE_FILL.v1 | 2 | `2d8e483b1c8cdb9eaf408d813d57666d3ef856c689e5b688927975bf09a0d2c7` |
| B0A.EDGE.POS_X.N128.v1 | 128 | `89e5fc94f9188e0b41ab37385b529ba8faa25de829846fb6f4e1ade38abd3ec5` |
| B0A.DISTRIBUTED.N128.v1 | 128 | `2fc60119ff74e24a03caf92a74ecd542fb0f8a74bbac2ada0326310083e7b6e5` |
| B0A.EDGE.POS_X.N256.v1 | 256 | `e201c0c9b9bd7ebc20a17672779ae480bd25742aee6391635a251d3c38eb75e2` |
| B0A.CORNER.POS_XZ.N256.v1 | 256 | `a07e10d5769fcb87c95ae3e0961b27f69336682a1a292401c28c05e4aae8e2d7` |
| B0A.CORNER.NEG_XZ.N256.v1 | 256 | `26f277cb092dde991fb13bbb1b2e1914c11bde452c403aa9a2c926cc3eb105de` |
| B0A.DISTRIBUTED.N256.v1 | 256 | `7c18adedc5589c0414e81f711dabaa30d886e94feeaae8dfe2e1a6a5f781ff90` |

Aggregates from the exact frozen scenario operation counts: **1,350 accepted operations, 9,450 SDF parity probes (7 per operation), and 1,394 JSONL records if each scenario has 4 framing records**. All values match the developer report.

## Codex-reported Windows execution

Codex reports one shared cold editor import PASS, harness check-only PASS and R7 contracts **2,586 assertions across 11 groups, zero failures**. Then 11 independent Godot processes ran serially, each exactly once, with terminal PASS/exit 0; all 1,350 accepted command sequences/revisions and prefix SHA-256 digests, region fanouts and 9,450 exact full-vs-filtered SDF probes reportedly passed; 1,394 JSONL records passed event/run/parent/clock integrity tests. Reported all per-scenario parent-child runtime PIDs observed; console launcher and child engine binary SHA pins recorded by Codex.

**Recoveries without scenario rerun:** original external validation falsely marked all 11 FAIL by exact equality between human-readable `4.7.2-stable (official)` and the product's dotted version; post-run validator corrected to compare structured version identity and full engine commit hash, and independently reprocessed original raw capture while preserving initial failed validator records. This correction is consistent with source R7 version validation semantics and does not create 11 new scenario launches.

**Raw custody:** `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_crossregion_ledger_4afd08d65ca94af8b9c573f17189a40f\evidence`. Codex reports 239 artifacts with matching hashes, index SHA-256 `4d1d203255ad0e8a973cce3dc395602ab663caaf3bbdfc9d603acb0406bba18b` and sidecar SHA `8628d5c784991befc7e361cd9ffa560bf5d815cd63b00dd9b879b5313791dec7`. **Documentary pointer discrepancy:** reported `operational_recovery_ledger.json` hyperlink uses shortened root `...4afd08d65ca94af8b9c573f`, unlike all other evidence paths; the correct physical path must be confirmed against the existing index, not guessed. Raw host files were not available to GitHub reviewer: 239 local file digests, prefix digests, event payloads, PID attribution and parity are **Codex-reported, not independently replayed**. GitHub SHA/source and all 11 final canonical command digests were independently reviewed.

**B0E exclusion:** frozen `geometric_scoring=EXCLUDED_UNTIL_NONEMPTY_EDITED_CONTOUR_PREFLIGHT` for three seam tests; ledger replay PASS is **not** edited geometric-contour or mesh-seam LOD acceptance. No displayed FPS, GPU completion, RSS, VRAM, target budgets, GUI, production code integration or release/merge approval.

## Next milestone and protected boundaries

All **19** frozen B0A ledger_replay plus B0E ledger_commands cases have now been **reported PASS UNSCORED** at the exact R7 commit (previous six INTERIOR, EDGE.POS_X.N032, CORNER.POS_XZ.N032, plus this 11-case batch). The remaining frozen scenario catalog contains exactly **25** cases: 10 B0S streaming, 10 B0G LOD transitions, 4 B0G tunnel-connectivity cases and 1 B0S edited reload. At owner request, propose **one 11-case streaming-state mission** (10 streaming + 1 edited reload) followed by **one 14-case geometry/tunnel mission**, each with independent per-process evidence and one consolidated reviewer gate. No automatic source edits/manifest changes, no broad scored benchmark, no protected access or merge. [Reviewer disposition on PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6343882847).

The 5 F2-G1 holds remain `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. PRs #99/#100/#101 remain draft and unmerged.
