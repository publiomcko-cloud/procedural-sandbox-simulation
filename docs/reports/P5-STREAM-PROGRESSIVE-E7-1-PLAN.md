# P5 E7.1 — event-driven provisional chunk publication

**Experimental branch:** `exp/p5-stream-progressive-chunks-e7-1`, derived from immutable E7 benchmark source `12a9385e583cc00dc80d041a76f97c31ccb5558e`. No `main` changes.

## Why

E7 proved canonical chunks could be displayed 1–1.5 s before their parent region completed, and produced 330 focused definitive chunks at 18 m/s and 152 at out-back 54 m/s across two trials. At 54 m/s straight, only 38 chunks appeared off-focus. However E7 increased CPU 0.6–1.8ms/frame. Its `mesh_dispatch_and_upload` stage rose from ~1.97 to 3.84ms/frame at 18m/s and from ~1.57 to 2.84ms/frame at 54m/s, mostly from repeatedly scanning and sorting all loading regions and validating 16 chunk LODs in every frame with no completed mesh.

## Revised scheduling

- On the only path that already validated/created the actual canonical ArrayMesh (`_process_completed_mesh_jobs`), enqueue a compact record of ID + current stage token + ready chunk coordinate for any incomplete pristine LOAD stage. Cap the queue at 400. Prioritize records from the focused region at insertion time.
- Per frame, drain up to 2 ready records within a 2.2ms budget; do not scan all staged regions. Reject stale stage tokens or revisions, partial/full/edit stages and non-ready coordinates. Check only the chosen chunk's target LOD. Existing worker capacity and source halo unchanged.
- On region unload/edit/fail/rebuild/revision replacement, delete pending records and revoke provisional nodes. On normal 16-chunk completion, adopt visible nodes and erase pending records.
- Preserve original E7 16-patch preview masks, no Z overlap, no early simulation/object/placement authority and unchanged authoritative region completion.

## Qualification and acceptance

1. Godot 4.7.2 parser and prior policy/coarse/stream-budget/effect contracts. Run real-scene smoke requiring stage-tokened progressive chunks and complete canonical regions, fail on any ERROR.
2. 16 identical cold-world ABBA 720-frame runs comparing E2 coarse-first to E7.1 on same SHA and Windows GPU-labeled runner. Analyze focused chunk count, first-to-full lead, latency and frame pacing.
3. Reject if >20ms frame frequency rises at least 1pp, mean `_process` rises >0.5ms, perceived focus gap rises at least 1pp, or whole LOAD completion drops >1. Candidate requires real focused chunks during high-speed travel, and full inherited P4/P5 + GUI verification before merge.

No automatic merge; keep E7 baseline and E7.1 separate.
