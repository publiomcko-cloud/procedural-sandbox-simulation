# CHK-2026-10-22-P1-1B-B1-1-N256-UNSCORED-CAPACITY-REVIEW

**Date recorded:** 2026-10-22, America/Sao_Paulo. Exact host execution timestamp not independently attested.
**Milestone:** maximum-capacity 256-operation UNSCORED ledger qualification and completion of the six frozen INTERIOR depth scenarios.
**Publication:** existing docs-only draft PR #101, unmerged at creation.
**Disposition:** `N256_UNSCORED_CONTRACT_REVIEW_PASS / CODEX_REPORTED_EXECUTION_PASS / INTERIOR_DEPTH_SERIES_COMPLETE_AS_REPORTED / NO_SCORED_PERFORMANCE_OR_MERGE`.

## Verified source and frozen contract

Repo `publiomcko-cloud/procedural-sandbox-simulation`, remote main `ea4422d90726d3f2fe6d5cef097126268f93685a`. [Feature PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) remains draft/unmerged at R7 exact HEAD `2b4355363a43b73476715cf4002e31575bf9828d`, direct parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`. [PR #100](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/100) independent roadmap draft. This documentation is placed on separate [PR #101](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/101) without touching historical checkpoint files.

Frozen manifest `game/tests/fixtures/p1_1b_b0_manifest.json`, Git blob `fde2ff84e2754cfef48052b32998903f45276aa1`, expected SHA-256 `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd`, matches R7 fixture identity. `B0A.INTERIOR.N256.v1` is FROZEN, ledger_replay with `operation_count=256`, `INTERIOR` recipe, support [0,0] and seven parity probe offsets. `SdfBrushEditState.MAX_EDITS=256`; the admission guard rejects only if current `_operations.size() >= MAX_EDITS`, so the 256th operation is valid if other admission criteria are satisfied. **No 257th operation was attempted.**

## Independent source and digest calculation

Using reviewed `Contract.build_commands()`, `_command()` and sorted-key `canonical_json()`, the reviewer reconstructed all 256 commands with 0-based `sequence=0..255`, alternating CARVE/FILL, radius 580 mm and canonical centers `[8000+(i%4)*100,3200,6000+(floor(i/4)%4)*100]` mm.

SHA-256 of this exact canonical JSON command array:

`33bae9714720dd343e2bcf464f73750fec6fad50a7e1c07dacbcc3b2848e840c`.

Independently calculated and verified to equal the Codex-reported final replay digest. Source implies `last_sequence=255`, revision/count=256, and 256×7=1,792 full-vs-filtered SDF probe positions.

## Codex-reported single N256 Windows execution

| Stage | Report |
| --- | --- |
| A — fresh isolated editor import | PASS, exit 0, 10.687s |
| B — harness --check-only | PASS, exit 0, 4.070s |
| C — R7 contract suite | PASS, exit 0, 3.924s, 2,586 assertions, 0 failures, 11 groups |
| D — one frozen N256 | PASS, exit 0, 5.025s, zero failures |

Codex reported **260 JSONL records**: one scenario start, 256 accepted-command events, one replay result, one terminal PASS, one logger-overhead record. All 256 cumulative digest prefixes reportedly matched independently reconstructed command prefixes; replay final digest matched the value above; all **1,792/1,792** full-vs-filtered SDF probes passed by exact float equality, correct region fanout and event clocks/identities. A live launcher-to-Godot parent-child process relationship was reportedly captured; specific PID values were not provided in the reporting message. There were no stderr/error/warning markers.

The host's post-run summary first read digest fields from the wrong JSONL event and was corrected **without any second N256 scenario execution**. Codex reports 22/22 captured evidence artifact hashes matched; all prior N000/N001/N032/N128/N255 evidence paths were preserved, and the development workspace, existing three untracked `.gd.uid` files and `stash@{0}` remained intact. No source, manifest, tests, CI, PR status, native tool or F2-G1 protected operation changed.

Raw host-local evidence, not independently mounted by this GitHub reviewer: `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_n256_8a3edf328b5f46908f6eae02dc1c7d9e_evidence`.

**Independent-review limitation:** the reviewer verified remote exact-SHA source, frozen manifest, capacity semantics and canonical full-list SHA-256. The Godot runtime, 2,586 assertions, individual 256 prefix digests, parity and 22 host-file hash checks are **Codex-reported** and were not independently replayed from local Windows logs here. No scored performance, OS RSS, VRAM, presented FPS, GPU completion, visual GUI acceptance or owner release gate follows from this single result.

## Cumulative qualification and forward boundary

The six frozen `INTERIOR` scenario depths **N000, N001, N032, N128, N255 and N256** have each been **reported PASS UNSCORED** at the same R7 SHA with distinct preserved evidence, independently reconciled source and canonical final digest checks. This qualifies the baseline same-region ledger history through its maximum capacity **within the experimental test harness**, not full P1.1B, production backend/LOD or the other frozen scenarios.

Next recommended bounded task: a single separate frozen `B0A.EDGE.POS_X.N032.v1` UNSCORED run (32 edits across the +X region border) after clean import, parser check and contract suite. Source-derived expected sequences 0..31, revision/count=32, last_sequence=31; region support/rebuild [0,0] and [1,0] per frozen scenario, 224 parity probes; canonical digest `fde68db5ad3248d6a155cc9e54fb6cda664e274348968219c95f151a33a5b305`. Do not assume dependency-region emptiness without inspection of actual fanout; preserve all regions and verify exact contract. No broad scenario sweep, scored threshold, 257th admission, native Voxel Tools, production change or merge without separate authorization.

The five protected F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. [PR #99 N256 review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6341487701).
