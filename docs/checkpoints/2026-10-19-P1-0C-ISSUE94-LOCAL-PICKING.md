# P1.0C Issue #94 — concentrated local-history picker coverage

**Date:** 2026-10-19. **Event:** implementation correction and full local validation after independent review #5571259552.
**Repository/workspace:** `publiomcko-cloud/procedural-sandbox-simulation`, `C:\Dev\sandbox-sim-dev`.
**Branch/PR:** `feat/p1-0c-global-cross-region-brushes`, existing draft PR [#92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92).
**Reviewed starting HEAD:** `dd1b2d75569444a49200c996873a86e81479767f`.
**Source commit:** `f632f7cc06066b690ad7574fe7b92bb306851893` (direct parent `dd1b2d75569444a49200c996873a86e81479767f`).
**Engine/validation:** Godot `4.7.2.stable.official.ed1daf0bf`, `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.
**Disposition:** source implementation and full L0–L2 validation passed. Independent review of the final documentation descendant and owner GUI retest remain pending. No visual acceptance, merge or release is implied.

## Review correction and implementation

The earlier picker profile primarily placed commands in remote regions and therefore did not measure the 256-command history concentrated near the mouse ray. This checkpoint adds four same-region layouts: interior `(8, 6)`, positive edge `(14.55, 6)`, positive corner `(14.55, 10.55)`, and negative corner `(-1.45, -1.45)`. For each layout it measures histories of 0, 32, 128, 255 and 256 commands, with five repeats and real `Viewport.push_input(InputEventMouseButton)` events. The operation centers are clustered close to the ray; fixtures verify each command's canonical geometric support remains exactly the anchor region. The earlier remote-history scenario remains as a control.

Instrumentation now reports ray-snapshot construction, picker loop, combined snapshot-plus-picker time, synchronous `push_input`, event-to-ledger acceptance, mesh transaction, accepted-to-visible time, candidate counts, sampled points, frame p95/p99/peak, mesh/worker queue waits, ArrayMesh upload and publication. Near/far hits, no-intersection rays, edge/corner cases, capacity rejection at 256 and the actual 255-to-256 accepted click are included.

The measured bottleneck was repeated fixed-step sampling through empty space, multiplying the cost of replaying a concentrated edit history. The production entrypoint now uses a bounded adaptive empty-space approach only for the documented SdfWorld v1 field: its terrain gradient bound is below 1.076, its cave field below 1.02, and min/max composition with unit sphere SDFs preserves the maximum Lipschitz bound. A conservative 1.1 bound and 0.8 safety factor prevent an adaptive jump from reaching the zero set. Once the safe step is no larger than the historical 0.1 spacing, the picker resumes the original fixed grid. This retains the original first grid crossing and bisection bracket. If an adaptive sample unexpectedly arrives on or beyond the zero set, the implementation falls back to scanning the original grid. The generic callable API keeps its original fixed-step behavior.

SDF v1, brush radii, global carve/fill order, ledger semantics, streaming, chunks and publication were not changed. The tests compare every ray-march and bisection density sample from full ordered replay with the ray snapshot, compare hit classification and returned position, and compare the adaptive V1 picker with the legacy fixed picker at 0 and 255 operations in all four layouts. A synthetic higher-gradient field verifies fallback behavior. Remote histories remain separately profiled. No speculative squared-distance SDF shortcut was retained.

## Godot validation

The final source commit passed `scripts/validate.ps1` in the pinned Godot 4.7.2 environment:

| Suite | Assertions | Result |
| --- | ---: | --- |
| Bootstrap smoke | 52 | PASS |
| SDF | 44 | PASS |
| Brush and picker contracts | 611 | PASS |
| Chunk/seam | 179 | PASS |
| Multiregion/ownership/viewport | 7,634 | PASS |
| Mesh performance/equivalence | 11 | PASS |
| History, 256 commands, replay/reset/supersession | 842 | PASS |
| Real Viewport mouse-event picking and local-history profiles | 713 | PASS |
| End-to-end streaming/edit performance | 251 | PASS |
| Worker concurrency/cancellation/publication | 11 | PASS |
| Bootstrap scene structure | 18 | PASS; rendered pixels are not assessed |
| **Total** | **10,366** | **0 failures** |

The prior accepted 9,752 assertions remain enabled; the final suite adds 614 assertions. Godot import and configured main-scene startup passed. `git diff --check` passed. The established limits remain four CPU workers, at most two ArrayMesh builds per frame, and 25 resident regions / 400 resident chunks.

## Concentrated local-history comparison

The before values are from the fixed-grid picker behavior at the reviewed starting code using the same local-history benchmark and instrumentation. The after values are from five repetitions per level and layout during final full validation. Each cell is the maximum across the four layouts of the per-layout p50 / p95, in milliseconds; the reported maximum p50 and maximum p95 can come from different layouts. These are local headless CPU measurements, not GUI/GPU completion timings.

| Operations before click | Picker end-to-end p50 / p95 before | Picker end-to-end p50 / p95 after | p95 reduction |
| ---: | ---: | ---: | ---: |
| 0 | 5.999 / 11.870 | 0.203 / 0.382 | 96.8% |
| 32 | 8.533 / 15.278 | 0.454 / 0.682 | 95.5% |
| 128 | 17.730 / 22.391 | 1.046 / 1.186 | 94.7% |
| 255 | 28.989 / 51.618 | 1.598 / 3.034 | 94.1% |
| 256 | 33.610 / 57.855 | 1.707 / 4.026 | 93.0% |

At 255 operations, local candidate counts were exactly 255 and the maximum sampled-count p95 across layouts was 34 (the fixed-grid baseline reached 1,201). The maximum p95 by stage was 0.915 ms to construct the ray snapshot, 1.771 ms inside the picker loop, and 3.034 ms for combined snapshot-plus-picker time. The maximum event-to-acceptance p95 was 3.929 ms. Capacity is tested separately at 256; the ledger remains unchanged and no publication is expected.

For accepted 255-operation clicks, the worst per-layout p95 across the four local layouts was 244.319 ms for the mesh transaction and 248.249 ms from input to visible publication. Mesh queue-wait p95 reached 141.931 ms in the negative-corner case; worker wait p95 was at most 0.714 ms and publication p95 at most 2.334 ms. This residual cost is streaming/remesh scheduling and publication, not picker replay. The worst local frame p95/p99/peak at 255 was 73.859 / 95.864 / 95.864 ms. Across the whole local matrix, one frame peak reached 110.336 ms. No frame-time guarantee is claimed.

The dedicated real-click acceptance of operation 256 from a 255-command history measured picker p50/p95 `0.165/0.252 ms`, click-to-visible p50/p95 `45.242/67.158 ms`, frame p95/p99/peak `75.528/88.229/88.229 ms`, queue peak 224 and four peak workers. The full 256-command distributed-history replay measured acceptance-to-visible `55.120/68.964 ms` p50/p95, with retries 0, queue peak 144, four peak workers, mesh-queue p95 max 3.109 ms, worker-wait p95 max 0.690 ms and publication p95 max 3.398 ms.

Separate headless streaming measurements remained: cold window 1,266 ms, region crossing p50/p95 `420.952/455.371 ms`, and unload/reentry to the edited 3×3 area `1,304/1,796 ms`. They are not improved or concealed by this picker correction. Frame spikes and corner mesh-queue latency remain follow-up profiling concerns.

## State, limitations and next gates

- Exact final source SHA is `f632f7cc06066b690ad7574fe7b92bb306851893`; the checkpoint/index/status documentation is its descendant commit on the same PR #92 branch.
- The change is local to the existing P1.0C PR #92. PR #87 remains a separate open draft and was not changed.
- Owner GUI validation has not occurred. Verify interior/edge/corner picking, visible geometry, carve/fill, 256-command capacity, X/C/R, streaming, seams and frame hitches in Godot GUI after independent exact-SHA source review.
- Adaptive stepping is enabled only for the documented SdfWorld v1 path. Any generator change requires recalculating and testing the gradient bound. Generic field callables retain fixed-step sampling.
- The 256-command ledger remains transient and bounded. Persistence, networking, cross-platform bit-identical replay and sustained GUI acceptance are not established.
- No protected-host/F2-G1 operation was performed. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
- PR #92 remains draft/open/unmerged; no merge or release is authorized.
