# 2026-11-11 — P5 streaming E1.1 experiment

**Event:** owner explicitly authorized "execute e1.1" after E1 performance A/B showed mixed results.

**Authoritative checked-at-state:** `main` = `2dca19d125309f3b70c858df1acdf22324c31c17` (unchanged by this experiment). Experimental base = `f6fbfa844ebf283ad9ff83684e4018f0c3faf1bd` on `exp/p5-0f-adaptive-stream-budget`. Implementation branch = `exp/p5-stream-visibility-lab`; PR [#282](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/282) draft, **DO NOT MERGE**. Implementation candidate pinned at `1264d711449ef15626775b0f77787acb233fd00c`; immediate parent `be4acc966cbf8b0a8a7037a167957e75491755d1`.

## Grounding before E1.1

Owner A/B at `fa58f289a82eb3a306fc7cbe167ba3448fb5a75c`, F10 18m/s, seed 424242: `adaptive-skip` p50 region-first-visual 2626.39ms, p95 4877.25ms, missing 5.05 regions per moving frame, >20ms frames 1.86%, process mean 4.19ms. `adaptive-skip-dependency` p50 2312.17ms, p95 4659.35ms, missing 4.73, >20ms frames 3.20%, process mean 5.40ms. Paths/frames differed. E1 breached +1 percentage point >20ms frame budget; keep `adaptive-skip` control and **do not promote E1**.

## Source change summary

E1.1 maintains the opt-in `adaptive-skip-dependency` profile; it is not a new default. Presentation scheduling now only reconstructs stage priority on stage/focus changes; it rechecks dependency readiness on a monotonic effect-source publication, invalidation, reconciliation, eviction or release event. A stable frame reuses cached readiness and avoids repeated source-halo walks and prefetch sorting. A changed demand still reorders already-queued sources while preserving urgent FIFO and existing bounds.

New headless checks validate cache hits without scope reads, wakeups after scope changes, readiness invalidation and target/focus changes. The one-second performance aggregation reports scheduler CPU microseconds, recomputes and stable-frame hit count; PowerShell A/B metrics report scheduler average CPU ms/frame and stable-frame percentage. Other profiles, canonical snapshot gates, edit transactions, simulation, water, persistence, and mod-first authority remain unchanged in intended behavior.

## Evidence and status at checkpoint

- GitHub source and PR: [PR #282](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/282), pinned candidate `1264d711449ef15626775b0f77787acb233fd00c`.
- Previous E0/E1 CI at `fa58f289`: Windows Godot 4.7.2 [PASS](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43079607052); **does not qualify E1.1**.
- Latest candidate Windows CI [run 43095074532](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43095074532), [run 43095083428](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43095083428): queued at last inspection, not PASS.
- No owner GUI A/B, 54m/s Ctrl-boost test, or new benchmark for E1.1 yet. No merged code, no production behavior claims.
- Evidence class: L0 remote source presence and static Git ref verification. Prior A/B logs owner-supplied; CI candidate L2–L3 **pending**, owner GUI L4–L5 **pending**.

## Next authorized step

Qualify exact candidate HEAD with pinned Godot 4.7.2 full inherited P4/P5 gate. If green, owner tests reproducible F10 18m/s and 54m/s ABBA with same seed/route and compares `adaptive-skip` versus `adaptive-skip-dependency` for queue-to-visual p50/p95, missing regions, >20/33ms frame fractions and scheduler CPU. Reject if it exceeds +1 percentage point frames >20ms, breaks revisions/seams/authority, or worsens visual gaps. Re-review exact source and await explicit owner acceptance before any merge. Update checkpoint via a new dated record rather than rewriting this frozen observation.
