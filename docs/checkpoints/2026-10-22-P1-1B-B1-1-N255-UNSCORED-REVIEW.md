# CHK-2026-10-22-P1-1B-B1-1-N255-UNSCORED-REVIEW

**Date:** 2026-10-22, America/Sao_Paulo. Host-run exact timestamp not independently verified.
**Event:** consequential 255-operation near-capacity UNSCORED qualification; independent GitHub source and canonical command SHA-256 review.
**Publication:** separate docs-only draft PR #101, not merged at creation.
**Disposition:** `N255_UNSCORED_CONTRACT_REVIEW_PASS / CODEX_EXECUTION_REPORTED_PASS / DIGEST_INDEPENDENTLY_MATCHED / NO_BENCHMARK_ACCEPTANCE`.

## Verified source and frozen scenario

Repo `publiomcko-cloud/procedural-sandbox-simulation`; remote main `ea4422d90726d3f2fe6d5cef097126268f93685a`. [PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) remains open/draft/unmerged at R7 SHA `2b4355363a43b73476715cf4002e31575bf9828d`, parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`. PR #100 remains a separate draft; this checkpoint belongs only on docs PR #101. No source or manifest modification.

Manifest `game/tests/fixtures/p1_1b_b0_manifest.json`, Git blob `fde2ff84e2754cfef48052b32998903f45276aa1`, frozen scenario `B0A.INTERIOR.N255.v1`: type `ledger_replay`, INTERIOR recipe, 255 operations, support `["0,0"]`, seven parity offsets. Manifest/sidecar physical SHA-256 `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd` Codex-reported verified. The pinned Godot 4.7.2 console executable's SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` was likewise reported verified.

## Independently verified canonical digest

From reviewed `Contract.build_commands`, `_command` and sorted-key `canonical_json`, independently rebuilt the 255 commands: index/sequence 0–254, alternating CARVE/FILL, radius 580 mm, centers `[8000+(i%4)*100, 3200, 6000+(floor(i/4)%4)*100]` mm. SHA-256 of the resulting canonical JSON equals:

`b68066c669dd56126fc1fe39f802bc87e2c9e20e29d57e9842b110eb62e03156`.

It exactly matches the reported N255 terminal digest. Source defines zero-based sequences, 255 accepted edits, `revision=255`, `last_sequence=254`; 255×7 expected parity probes = **1,785**. This source-level confirmation is independent of the local Codex execution. Ledger capacity `MAX_EDITS=256` remains unchanged.

## Reported four-stage Windows execution

| Stage | Codex report |
| --- | --- |
| A — cold editor import | PASS, exit 0, 11.17 s |
| B — harness `--check-only` | PASS, exit 0, 4.50 s |
| C — R7 contract suite | PASS, exit 0, 4.86 s, 2,586 assertions/0 failures/11 groups |
| D — exactly one N255 UNSCORED | PASS, exit 0, 6.14 s, terminal PASS/0 failures |

Reported **259 JSONL events**: 1 start, 255 accepted, 1 ledger replay result PASS, 1 scenario complete PASS, 1 logger-overhead record. All 255 accepted commands and cumulative prefix digests reportedly matched; revision/count 255, last_sequence 254, support/rebuild region `["0,0"]`, dependency regions `[]`, full-vs-filtered SDF parity **1785/1785 PASS**. All four stderr logs empty and no parser warnings/errors. Launcher PID `30772` was reportedly observed as parent of Godot PID `60104` through live process polling and captured command lines. This process attribution is **Codex-reported, not independently replayed**.

Two setup/evidence corrections were reportedly made without touching repo files or rerunning the scenario: wrong local preflight lookup `freeze_status` rather than manifest `status`, and post-run inventory threshold. No additional scenario or protected operation. Disposable checkout had no tracked changes; development worktree, three pre-existing untracked `.gd.uid` hashes and `stash@{0}` were preserved.

Raw Windows evidence (not independently accessible by this remote GitHub reviewer): `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_n255_ceb8a017a4544e5d8661086237dbe01c_evidence`. Reported artifacts include raw `d_n255.jsonl`, `d_n255.integrity_summary.json`, `n255.prefix_digest_validation.json` and `artifact_hashes.json`. [Independent review comment](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6341102855).

## Limitations and next gate

**UNSCORED only.** Do not infer benchmark success, target budgets, GPU completion, actual presented FPS, RSS/VRAM, visual GUI acceptance, P1.1C implementation or production terrain readiness. No merge. Five F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

Next candidate: one **separate frozen N256 UNSCORED** run at exact unchanged R7 SHA, with cold import, parser and R7 contracts before starting the one scenario. Source-reviewed `MAX_EDITS=256`, so 256 admissions should succeed; require sequences 0–255, count/revision=256, last_sequence=255, 1792 parity probes and independently computed full command list SHA-256 `33bae9714720dd343e2bcf464f73750fec6fad50a7e1c07dacbcc3b2848e840c`. No automatic 257th admission: that would be a separate negative-capacity boundary test, not part of frozen N256. Bounded host-side pre-scenario repairs are allowed under standing authorization; tracked source, manifest and acceptance criteria are not to be changed. Maintain existing PR drafts, all historical evidence and protected holds.

No new owner decision, code integration or changelog merge record was made by this review.
