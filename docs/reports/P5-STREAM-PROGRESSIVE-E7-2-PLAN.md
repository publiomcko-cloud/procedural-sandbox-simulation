# P5 E7.2 — frame-budgeted progressive chunk visibility

Branch `exp/p5-stream-progressive-chunks-e7-2`; builds on qualified E7.1 event-driven queue, keeping exactly the same original E2 coarse-first control. No change to `main`.

E7.1 source `7ff7edaf4764d7a8dbcb9e5aaee85b5756a4fe4a`: 16 valid ABBA receipts, authoritative regions at 18 m/s 14→15.5, 598 progressive chunks in 18m/s (326 focused), 311 progressive chunks in outback54 (154 focused), but **zero focused** at straight54. Rejected because >20ms frames +1.733pp at 18m/s and +1.248pp at outback54. Mean process +0.431ms at 18m/s, +0.073ms at outback54. CPU frame spikes, not average cost, now dominate.

Changes for E7.2:
- Publish at most **one** provisional chunk node/frame (formerly 2), with a **1.1ms budget** (formerly 2.2ms).
- Defer provisional publication when the same frame already uploaded any authoritative mesh, when last frame >=16ms or prior main process >=8ms. Retain queued ready records, still capped at 400.
- Process completed mesh jobs first; publish provisional node only if there was no mesh upload that frame. No change to work queue, stage token/revision checks, coarse preview patch clipping, source worker counts, geometry, actual LOD or complete 16-chunk publication.
- These are conservative frame pacing settings, not a claim of improved 54m/s source readiness.

Acceptance: Godot 4.7.2 import and E7 existing policy/revision/coarse split tests and real scene. Then 16 720-frame ABBA trials (idle, 18, 54 and outback54) on one Windows runner, same SHA, seed 424242. Reject if >20ms frame frequency grows >=1pp, process mean >0.5ms, perceived focus gap >=1pp, whole LOAD completions drop >1, or no focused high-speed chunk progress. If promising, run full P4/P5 and GUI qualification before any merge.
