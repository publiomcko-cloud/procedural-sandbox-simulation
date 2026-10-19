# P1.0C long-history and stream-supersession correction — Issue #94

**Date:** 2026-10-19. **Scope:** correction on existing P1.0C draft PR #92; no new branch or PR.  
**Starting candidate:** `6d128e3d231aa0456c42cf06e9e60f5a861d59df`.  
**Implementation commit:** `3ee811b8a814ed52229bae21db0b21e703e2413a` (direct parent `6d128e3d231aa0456c42cf06e9e60f5a861d59df`).  
**Validation engine:** Godot `4.7.2.stable.official.ed1daf0bf`, `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.  
**Disposition:** implementation and pinned local source validation complete; independent SHA-specific review and owner GUI retest remain required. PR #92 must remain draft/open/unmerged.

## Root causes and correction

Issue #94 identified two independent defects. The old `SdfBrushEditState.MAX_EDITS=32` rejected operation index 32 (the 33rd accepted-intent brush) globally, even after moving to another region. A staged load whose ledger revision changed was also sent through genuine stage-failure handling, consuming retry budget and leaving a persistent stream error for normal supersession.

The ledger is now explicitly bounded at 256 accepted operations. Admission validates mode, finite values, coordinate/radius bounds and maximum region fanout before checking capacity; rejection exposes distinct reason codes and does not consume a sequence or revision. `X` removes the commands whose canonical sphere support intersects the focused region, preserves the remaining global order and monotonic sequence, and frees bounded capacity. No operation is silently evicted; the ledger remains in-memory only and is not durable across process exit.

The general-purpose SDF evaluator retains complete ordered carve/fill replay. For meshing only, a chunk snapshot may omit a command if it is mathematically dominated throughout that chunk's complete sample and central-difference-normal query domain. The domain includes the chunk AABB expanded by 0.25 (half the 0.5 sample step). With radius at most 2, command threshold is a no-op when the center is at least 9 units away. The v1 base density is bounded to `[-6.68, 4]`; every ordered `min`/`max` brush operation stays in that interval because carve thresholds are no lower than -2 and fill thresholds no higher than 2. At distance >=9, carve threshold is >=7 and fill threshold <=-7, so either operation is dominated for every intermediate density, regardless of command order. This is a proven no-op filter, not geometric-support culling. In-domain operations are kept in original sequence. Tests compare complete and filtered density samples plus generated vertices and normals.

Expected stage supersession now discards the stale stage without treating it as a task failure. Current revision work is requeued or the full target transaction is restarted; stale results still cannot publish. A per-region error map preserves unrelated genuine failures, and a successful current-revision completion clears only its resolved error. Existing retry limits are retained for actual failures.

Resource invariants remain: at most 4 CPU jobs in flight, at most 2 `ArrayMesh` constructions per frame, at most 25 resident regions / 400 chunks. Publication remains revision checked and transactional. SDF v1, global sequence semantics, negative ownership, shared borders/normals, C/R/X, and unload/reentry replay are retained.

## Reproduction and validation

- Before the correction, a disposable temporary Godot script against the exact starting code accepted indices 0–31 and rejected index 32; count remained 32. The temporary script was removed.
- After correction, `terrain_history_tests.gd` accepted 256 sequential commands spread across 16 signed regions, rejected command 257 with `ledger_capacity_exceeded` without changing sequence/revision, then verified reset capacity, X behavior, unload/reentry, supersession during loading, rapid focus changes, and worker/residency bounds.
- Focused suites: history **554/554**, performance kernel **11/11**.
- Full `scripts/validate.ps1` after implementation commit: Godot import and main-scene startup passed; smoke **52**, SDF **44**, brush **606**, chunk **179**, multiregion **7,634**, performance kernel **11**, history **554**, end-to-end performance **251**, concurrency **11**, bootstrap structure **18**. Total **9,360 assertions, zero failures**. Bootstrap test does not assess rendered pixels. Visual owner acceptance is not claimed.
- Whole-history test: 256 operations over 16 regions; edit visible latency p50/p95 **48.284/62.057 ms**; process static-memory monitor **38,669,914 bytes**; estimated resident mesh bytes **9,795,456**; peak queue **144**, peak workers **4**; maximum measured mesh-queue p95 across edits **2.673 ms**, worker-pool wait p95 **0.716 ms**, publication p95 **2.509 ms**; retries **0**; test frame p95/p99 **6.944/6.944 ms**.

## Replay benchmark — same five-repeat workload

The full-replay column is the unfiltered ordered kernel reference. The filtered column uses the bounded chunk-specific snapshot on the same chunk and ledger inputs; exact density/mesh comparisons are asserted. Timings are local headless CPU microbenchmarks, not end-to-end GPU or guaranteed GUI latency.

| Ops | Candidates | Payload | Full replay p50/p95 ms | Filtered meshing p50/p95 ms | Worker CPU p50/p95 ms | Worker wait p50/p95 ms | SDF / triangulation / normals / ArrayMesh p50 ms | Static-memory before/ledger/delta bytes |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 0 B | 21.784 / 24.800 | 21.899 / 21.987 | 21.727 / 23.976 | 0.064 / 0.080 | 3.071 / 11.039 / 1.847 / 0.248 | 25,681,759 / 25,683,315 / 1,556 |
| 32 | 2 | 74 B | 70.833 / 72.293 | 25.044 / 26.611 | 24.821 / 25.836 | 0.070 / 0.103 | 4.485 / 11.326 / 2.935 / 0.271 | 25,980,851 / 26,040,915 / 60,064 |
| 64 | 5 | 185 B | 113.378 / 127.615 | 26.567 / 37.277 | 25.643 / 32.570 | 0.062 / 0.067 | 4.920 / 11.373 / 3.225 / 0.270 | 26,041,349 / 26,097,917 / 56,568 |
| 128 | 10 | 370 B | 211.809 / 216.654 | 27.760 / 28.802 | 29.277 / 34.561 | 0.061 / 0.114 | 6.024 / 11.415 / 3.834 / 0.274 | 26,098,248 / 26,210,080 / 111,832 |
| 256 | 20 | 740 B | 425.977 / 436.359 | 29.945 / 30.057 | 29.985 / 40.142 | 0.064 / 0.077 | 7.212 / 11.296 / 4.918 / 0.278 | 26,210,511 / 26,437,815 / 227,304 |

At 256 operations, filtered snapshot construction reduced the candidate commands for the measured chunk from 256 to 20; measured p95 meshing time was about 93% lower than full replay for that workload. The 0-op path is within measurement variation, not a claimed improvement. Godot's static-memory monitor includes process/test allocations; per-ledger deltas are indicative, not an isolated heap attribution.

Additional same-run end-to-end observations: cold 3×3 window **1,128 ms**; region crossing p50/p95 **393.274/393.317 ms**; single-region click-to-visible p50/p95 **47.967/61.703 ms**; two-region seam **48.229/75.355 ms**; 32nd command's two-region seam commit **144.812 ms**; unload/travel plus return to edited 3×3 window after 256 operations **1,140/1,727 ms**. These movement/reentry timings have no matched old-code baseline and are not claimed as a speedup. A separate multiregion fixture measured transient frame p99 of **122 ms** during global-edit/reference work; it does not establish normal gameplay frame time, but demonstrates that bulk publication and scene work can still hitch.

Final full-history stress sample: visible latency p50/p95 **48.283/62.075 ms**, static-memory monitor **38,670,186 bytes**, estimated mesh attributes **9,795,456 bytes**, peak queue **144**, peak workers **4**, mesh-queue p95 max **2.802 ms**, worker-pool wait p95 max **0.528 ms**, publication p95 max **3.027 ms**, retries **0**, test frame p95/p99 **6.926/6.944 ms**. These figures come from the synthetic headless harness and exclude guaranteed display/GPU completion.

## Documentation and parallel PR reconciliation

This checkpoint, the index update and the current status update are recorded on the existing feature PR #92 branch so the implementation and its evidence share one exact candidate. Docs-only PR #87 was independently checked live on 2026-10-19: it remains open/draft/unmerged, head `6fad428a22a149624da245e88a5e608d09ed7dd3`, base `main`, and retains overlapping historical status/index documentation. Its branch was not changed. Reconcile its documentation deliberately at a separately authorized integration point; neither branch's overlapping snapshot should be treated as newer without checking merge ancestry.

## Residual risks and gates

- The ledger is bounded at 256 and transient; accepted edits are not persisted across application restart. More than 256 outstanding commands are rejected explicitly until X clears applicable support; no promise of unlimited history is made.
- Returning to a previously edited 3×3 area after 256 edits took about 1.68 s in this headless test. The local chunk kernel improves substantially over full replay, but streaming/reentry latency remains material.
- Headless timing does not measure GPU completion or physical display scanout. Bulk multi-mesh publication can still create frame spikes. Only the owner can validate actual visual continuity, responsiveness and lighting in the GUI.
- Independent source review of the final pushed SHA, owner GUI retest (including 256 edits across positive/negative regions, rapid movement, X/C/R, unload/reentry, seams/corners and no stale stream error), and a separate merge authorization are outstanding.
- No persistence, networking, multiplayer, V3 work or protected F2-G1 execution was performed. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
