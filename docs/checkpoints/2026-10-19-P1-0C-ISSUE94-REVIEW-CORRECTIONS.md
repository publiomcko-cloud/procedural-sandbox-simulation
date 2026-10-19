# P1.0C Issue #94 review corrections — vertical meshing bounds and real picking profile

**Date:** 2026-10-19. **Scope:** bounded correction on the existing P1.0C draft PR #92; no new branch or PR.
**Reviewed starting HEAD:** `8d4057698ced5fe24cd12d90d27807a01f8d887f`.
**Source commit:** `946b16b6ef37015e0a408e4ec59c3cb94ff7d995` (direct parent `8d4057698ced5fe24cd12d90d27807a01f8d887f`).
**Validation:** Godot `4.7.2.stable.official.ed1daf0bf`, `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.
**Disposition:** implementation and full local headless validation passed; exact-SHA independent source rereview and owner GUI retest are still required. PR #92 remains draft, open and unmerged. No merge or visual acceptance is implied.

## Review findings and changes

The independent Issue #94 review identified an incomplete vertical query AABB in `get_meshing_snapshot_for_chunk()`: the prior range started at y=0, while the SDF lattice spans `GRID.MIN_BOUND.y=-2` through `GRID.MAX_BOUND.y=8`; normal probes extend half a sample beyond both endpoints. The query now uses the explicit vertical bounds plus `GRID.SAMPLE_STEP * 0.5`, while x/z remain the chunk bounds expanded by the same margin.

The review also found that the old performance experiment mostly invoked brush APIs directly and did not profile the real viewport-input path at the requested history sizes. The new headless scene-tree benchmark sends actual `InputEventMouseButton` events through the Viewport and measures picking, accepted-event/visible-publication latency, sample counts, frame p95/p99/peak, mesh/worker queue waits, publication, queue depth, and worker count. It covers near and far hits, near positive and negative corners, and a no-intersection ray at 0, 32, 128 and 256 existing operations. A separate five-repeat case admits the 256th command through a real click and waits for coherent publication.

Profiling on the reviewed code showed a history-dependent picker bottleneck, so the picking path now captures one conservative ordered SDF command subset for the finite ray segment and reuses it for each ray sample. The subset propagates conservative density intervals through carve/fill commands in global sequence order and omits a command only when it is dominated for every point on the ray. SDF v1, carve/fill order and values remain unchanged. Existing full ordered evaluation remains available for general world queries. Equivalence tests compare filtered and full SDF samples along bounded ray segments for distributed and concentrated histories.

The corrected meshing AABB tests compare full and filtered density at vertical endpoints, half-step normal probes, horizontal borders and negative coordinates. A concentrated 256-command history around the negative-coordinate region corner compares exact generated vertices/normals in four adjacent chunks. Distributed histories and existing unload/reload, reset, cancellation, worker and publication tests remain enabled. The stale benchmark label now prints the measured ledger size rather than the former literal `31`.

## Godot validation

`scripts/validate.ps1` completed on the pinned Godot executable:

| Suite | Assertions | Result |
| --- | ---: | --- |
| Bootstrap smoke | 52 | PASS |
| SDF | 44 | PASS |
| Brush | 606 | PASS |
| Chunk/seam | 179 | PASS |
| Multiregion/ownership/viewport | 7,634 | PASS |
| Mesh performance/equivalence | 11 | PASS |
| History, 256 commands, density/mesh/normal parity, reset and supersession | 842 | PASS |
| Real Viewport mouse-event picking and publication profile | 104 | PASS |
| End-to-end streaming/edit performance | 251 | PASS |
| Worker concurrency/cancellation/publication | 11 | PASS |
| Bootstrap scene structure | 18 | PASS; rendered pixels not assessed |
| **Total** | **9,752** | **0 failures** |

Godot import and configured main-scene startup also passed. `git diff --check` passed. The history suite verifies the 256-command ledger and exact full-vs-filtered SDF and mesh equivalence; the input benchmark verifies that a real viewport click commits operation 256 and that `X` can remove that added focused operation. The existing bounds remain 4 CPU workers, at most 2 ArrayMesh builds per frame, and 25 regions / 400 chunks resident.

## Input-to-publication profile

The before column was recorded against the exact reviewed starting HEAD using the same five real viewport scenarios per level. The after column is from the full validation run at this source commit. Values are headless, local CPU/event-to-publication measurements; p95 over five samples is coarse and sensitive to scene loading and frame scheduling. It is not a GUI, GPU-completion or display-scanout guarantee.

| Existing history | Picker p50/p95 before → after (ms) | Visible commit p50/p95 after (ms) | Frame p95/p99/peak after (ms) | Mesh queue wait p95 / worker wait p95 / publish p95 after (ms) | Peak queue / workers |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 2.295 / 12.462 → 1.286 / 9.979 | 48.252 / 61.736 | 16.667 / 41.378 / 41.378 | 1.419 / 0.110 / 2.136 | 144 / 4 |
| 32 | 6.499 / 36.162 → 1.172 / 6.164 | 47.317 / 54.272 | 10.000 / 83.368 / 83.368 | 1.554 / 0.118 / 2.189 | 224 / 4 |
| 128 | 50.544 / 123.010 → 1.214 / 5.836 | 45.195 / 58.612 | 8.508 / 75.894 / 75.894 | 1.685 / 0.252 / 2.252 | 224 / 4 |
| 256 | 42.308 / 246.400 → 1.207 / 6.227 | Capacity rejection, no publication | 73.988 / 73.988 / 73.988 | 0 / 0 / 0 | 224 / 4 |

At 128 commands, measured picker p95 fell about 95%; at 256, about 97%. The 256th actual mouse edit from a 255-command ledger measured picker p50/p95 `1.193/2.243 ms`, click-to-visible p50/p95 `47.232/59.250 ms`, and frame p95/p99/peak `75.856/85.904/85.904 ms`, with queue peak 224 and four workers. Capacity rejection at 256 leaves the ledger unchanged. Queue peaks reflect the existing bounded streaming scheduler; they are not an unbounded worker increase.

The full validation's 256-operation distributed-history rebuild measured visible publication p50/p95 `48.287/62.068 ms`, static-memory monitor `38,764,354 bytes`, estimated mesh bytes `9,795,456`, queue peak 144, four peak workers, mesh queue p95 max `2.895 ms`, worker wait p95 max `0.661 ms`, publish p95 max `2.441 ms`, retries 0, and test frame p95/p99 `6.896/6.896 ms`. Static-memory monitor values are process-wide, and do not isolate the ledger heap.

For context, the same complete validation measured region crossing p50/p95 `400.209/413.997 ms`, cold initial window `1,162.631 ms`, and return to an edited 3×3 window after unload/travel `1,801.575 ms`. The picker correction addresses the measured event-path regression; it does not optimize or conceal those separate streaming costs. The 256th-edit seam end-to-end scenario was `117.218 ms` in its distinct fixture. Headless frame maxima up to `85.904 ms` demonstrate remaining spikes; no frame-time guarantee is claimed.

## Remaining gates and limits

- Independent reviewer must inspect exact pushed HEAD `946b16b6ef37015e0a408e4ec59c3cb94ff7d995` and its final documentation descendant. No source review result is inferred from this developer validation.
- Owner GUI retest remains required for visible geometry, corners/seams, mouse interaction, sustained edits, `X/C/R`, unload/reentry, lighting and frame hitches. Headless benchmarks and structural tests do not establish visual acceptance.
- Edits remain transient and bounded to 256; persistence, networking, cross-platform bit-identical replay and arbitrary-history behavior are not implemented.
- SDF ray filtering is validated against dense 0.05-unit samples on distributed and concentrated histories and uses a fixed 120-unit picker range. It is not a proof of arbitrary precision equivalence for every floating-point input outside the defined picker path.
- The existing staging/revision/cancellation model remains bounded, but load/movement latency and occasional frame spikes remain measurable concerns for later profiling.
- No F2-G1 or protected-host operation was performed. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
- PR #87 was not changed. Its overlapping status/index snapshot still requires deliberate reconciliation at a separately authorized integration point.
