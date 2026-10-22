# CHK-2026-10-22-P1-1B-B1-1-STREAMING-RELOAD-BATCH-11-EVIDENCE-CUSTODY-INCIDENT

**Recorded:** 2026-10-22 (America/Sao_Paulo). Exact host-event timestamps have not been independently checked.
**Status:** `STREAMING_RELOAD_BATCH_11_PARTIAL_OR_BLOCKED_WITH_EVIDENCE / CUSTODY_COMPROMISED / 0_QUALIFIED_PASS / 2_BLOCKED / 9_NOT_RUN / OWNER_DECISION_REQUIRED`.
**Publication:** a new historical checkpoint in existing separate docs-only draft PR #101; unmerged. All existing prior checkpoints remain intact.

## Remote source identity and campaign scope

Repository `publiomcko-cloud/procedural-sandbox-simulation`; independently verified main `ea4422d90726d3f2fe6d5cef097126268f93685a`. [Feature PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) remains open/draft/unmerged at exact reviewed R7 HEAD `2b4355363a43b73476715cf4002e31575bf9828d`, direct parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`. Pinned manifest Git blob `fde2ff84e2754cfef48052b32998903f45276aa1`, physical SHA-256 `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd` reportedly matched; Godot 4.7.2 console binary physical SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` reportedly matched. The exact frozen campaign contains ten `B0S` streaming and one edited-reload case. No source edits reported.

## Codex-reported shared gates and failure

Initial isolated checkout used redirected Windows `USERPROFILE`, causing four `get_system_dir` diagnostics on import. These outputs were reportedly retained. A fresh second checkout, retaining original `USERPROFILE` and isolating `APPDATA`/`LOCALAPPDATA`, then passed cold editor import, harness `--check-only`, and full R7 contract suite (11 groups, 2,586 assertions, zero failures), with actual exit 0 and no parser errors.

The first two streaming scenarios individually reached functional `scenario_complete=PASS`, but due to failures in the host-only postprocessor they were **accidentally launched twice, overwriting first-execution raw files**. Specifically, the postprocessor wrongly assumed the FACE scenario contained `expected_settled_counts`; a faulty scenario-ID list replacement while repairing it reran both scenarios. A later bad crossing-vector construction produced a false external negative and was corrected by offline validation on surviving logs.

| Frozen ID | Formal campaign verdict | Surviving functional evidence |
| --- | --- | --- |
| `B0S.COLD.ORIGIN.v1` | **BLOCKED — original raw evidence overwritten** | second run reported exit 0, terminal PASS, 7 JSONL, 9 active regions |
| `B0S.FACE.POS_X.v1` | **BLOCKED — original raw evidence overwritten** | second run reported exit 0, terminal PASS, 14 JSONL, focus (1,0), 1 crossing, 12 active regions |
| `B0S.FACE.NEG_X.v1` | NOT_RUN | no process/log evidence |
| `B0S.FACE.POS_Z.v1` | NOT_RUN | no process/log evidence |
| `B0S.FACE.NEG_Z.v1` | NOT_RUN | no process/log evidence |
| `B0S.CORNER.DIRECT_ATOMIC_POS_POS.v1` | NOT_RUN | no process/log evidence |
| `B0S.CORNER.LOOP_POS.v1` | NOT_RUN | no process/log evidence |
| `B0S.CORNER.LOOP_NEG.v1` | NOT_RUN | no process/log evidence |
| `B0S.CORNER.LOOP_MIXED.v1` | NOT_RUN | no process/log evidence |
| `B0S.REVERSE.POS_X.v1` | NOT_RUN | no process/log evidence |
| `B0S.EDITED.RELOAD.REGION_2_NEG1.v1` | NOT_RUN | no process/log evidence |

**Qualification tally: PASS 0, FAIL 0, BLOCKED 2, NOT_RUN 9.** The two surviving second-run PASS events demonstrate limited functional behavior but **do not satisfy once-only campaign custody requirements**; do not count them as qualified and do not relabel them as a functional source FAIL. The other nine scenarios were never executed.

## Evidence classification and custody

Codex-reported evidence root: `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_stream_reload_e35b71f298d64b7d8b2dcf31432eed0b\campaign`; reported `campaign_summary.json`, `incident_report.md`, `artifact_sha256_index.csv` (515 entries, reported SHA-256 `e9eae561e6e4472c62b71023eb9ebfa4bd5ae7c6fe55a10a4162ed1c0b5e00f0`). The presence of an index does not establish custody of superseded first raw files. Host files and full incident logs were not independently mounted or replayed by GitHub reviewer, so original execution details and overwrite analysis remain Codex-reported. Development worktree, three pre-existing untracked `.gd.uid` files, `stash@{0}` and preexisting unrelated Godot process reportedly remained intact. No new PR or protected action reported.

## Recovery design and execution hold

No new scenario run should take place until the owner authorizes a corrected, fresh qualification campaign. Historical incident evidence should be preserved read-only and never silently overwritten or promoted to PASS.

A corrected **host-only** runner must physically separate Godot process-spawning from the postprocessor, disallow any run/resume action in validators, atomically reserve each scenario once per campaign, and fail closed on any duplicate. New unique campaign/run/attempt directories and raw stdout/stderr files must use create-if-absent/exclusive creation semantics, with immediate SHA indexing and append-only event/launch ledger. Exercise launcher dry-run, fail-closed duplicate-run injection, offline postprocessor validation for FACE without `expected_settled_counts`, malformed crossing-vector rejection, and failure recovery using the retained incident data **without launching Godot**. Preserve original Windows `USERPROFILE` and isolate supported APPDATA/LOCALAPPDATA paths.

Recommended **owner-decision option**: approve one entirely **new** eleven-scenario batch, under a new campaign ID/evidence root, after no-Godot dry-run acceptance of runner safeguards. The first incident remains `0 PASS / 2 BLOCKED / 9 NOT_RUN` forever as historical evidence. No automatic retry of a started scenario. Stop on any global evidence-integrity failure. Once all eleven complete, one consolidated independent evidence review. Alternatively owner can decline any new execution and hold the campaign blocked.

Previous **19/19 reported B0A/B0E ledger/seam UNSCORED PASS** remains historical and unaffected. The remaining 14 LOD/tunnel scenarios are not authorized within this paused streaming/reload campaign. All five F2-G1 holds remain `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`. No scored performance, production changes or PR merge. [Independent incident review in PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6345091176).
