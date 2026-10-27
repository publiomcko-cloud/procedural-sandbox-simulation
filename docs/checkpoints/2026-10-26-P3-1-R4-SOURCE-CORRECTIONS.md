# P3.1 R4 source correction checkpoint

**Checkpoint ID/date:** `CHK-2026-10-26-P3-1-R4-SOURCE-CORRECTIONS`; 2026-10-26

**Event type:** material defect diagnosis and bounded experimental correction

**Publication state:** local R4 experiment branch; draft evidence PR not yet created

## Verified identity

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Production baseline: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Worktree: `C:\Dev\sandbox-sim-p3-1-r4-subledger-snapshots`; branch `bench/p3-1-r4-subledger-snapshots`.
- At diagnosis, HEAD was `8b76e778b0f282a37aa11a229b795c423f581467`, descended directly from the baseline through the R4-only commits. No production source paths were changed.
- Issue #140 authorizes only isolated A/B/C experiments; PRs #129/#134/#136/#137/#138/#139 remain out of scope for modification.

## Finding and correction

The first diagnostic campaign exposed a real C-arm error. `r4_chunk_subledger.gd::as_snapshot()` returned its internal `PackedVector3Array`, `PackedFloat64Array`, `PackedByteArray`, and `PackedInt32Array` values directly. A caller retained that dictionary as a previous-revision checkpoint. Subsequent `append_snapshot()` appended into the shared packed-array storage, so the supposed base checkpoint advanced too. C materialized the advanced checkpoint then replayed its tail operation a second time.

The prototype now returns duplicated packed arrays from `as_snapshot()`. The benchmark captures C's pre-append snapshot before advancing the projection. A new regression reproduces the prior aliasing sequence and requires unchanged base revision/cardinality and exact equality between incremental C densities and a complete C materialization. After correction the focused R4 architecture suite passed **199 assertions, zero failures** on Godot `4.7.2.stable.official.ed1daf0bf`; import passed, PowerShell 5.1 parsing passed, and `git diff --check` passed.

The same diagnostic campaign exposed two harness/evidence issues: frozen R3C nonperiodic radii were incorrectly forced to 580 mm, and the runner treated a valid functional failure as global invalid evidence because PASS-only metrics were mandatory for FAIL. R3B remains fixed at 580 mm; R3C replays its pinned radii after canonical bounds validation. The runner now separates common identity checks, PASS-specific geometry checks, substantive scenario failures, and frozen-input integrity failures.

## Evidence ledger and recovery

- The initial campaign root is preserved at `C:\Users\PUBLI\AppData\Local\Temp\p31-r4-campaign-312def8287844d5c90e563bca4fd4e9f`; its full raw evidence will be archived byte-for-byte within the final report package. It stopped after row 11: 6 PASS, 4 functional failures, 1 invalid-evidence classification, 79 globally not run. It is diagnostic only.
- The 90-row manifest remains unchanged at SHA-256 `c6fd895685304795101968ed1104385d31c3f4b1cf303fb26582b16a22666c31`; R3B and R3C fixture hashes and original acceptance criteria remain unchanged.
- Full `scripts/validate.ps1` and the corrected final 90-row campaign are still pending. No performance, geometry acceptance, owner approval, production integration, or release is claimed.
- F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

## Next authorized action

Finish exact-source parser/import and canonical validation, run the frozen R4 campaign once at the committed candidate SHA with the 600-second scenario stop-loss, preserve every result, publish a separate draft evidence PR, and await independent source/evidence review. Do not modify production, PR #129 or other evidence PRs, and do not merge.
