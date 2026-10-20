# P1.0C — owner GUI PASS and integration-readiness handoff

**Date:** 2026-10-19 (America/Sao_Paulo). **Event:** owner GUI acceptance after independent source review; **publication:** new checkpoint on draft PR #92, not yet integrated into `main`.

## Pinned evidence
- Repository: `publiomcko-cloud/procedural-sandbox-simulation`; verified `main` at `2f86c42503cfa3a334215b1ff5b9bf9658263440` during this handoff.
- Existing feature branch: `feat/p1-0c-global-cross-region-brushes`; exact owner-tested and independently source-reviewed feature HEAD `531bae3d5d5770b67e4b7fa4c5c44a8c13249284` (source commit `f632f7cc06066b690ad7574fe7b92bb306851893`).
- [Independent source review #5578386601](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5578386601): `PASS_SOURCE_REVIEW_WITH_GUI_PERFORMANCE_CAVEATS / OWNER_GUI_PENDING / NO_MERGE`, later completed by the owner's GUI report.
- [PR #92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92) is still open, draft, unmerged; [PR #87](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/87) remains separate, open, draft, unmerged.
- Codex reports Godot `4.7.2.stable.official.ed1daf0bf` full `scripts/validate.ps1`: **10,366 assertions, zero failures**, import and main-scene startup PASS. These Windows runs were developer-reported and were NOT independently rerun by the source reviewer; GitHub Starter checks cover static structure only.

## Owner-observed GUI gate — PASS within stated scope
On 2026-10-19 the owner said terrain editing is satisfactory in quantity and works concurrently with movement across the map. The owner then explicitly confirmed that the additional previously enumerated GUI checks **also passed**: positive/negative borders and corners, `X/C/R`, returning to edited areas after unload/reentry, and no persistent `STREAM ERROR` message. This is an owner GUI/interaction acceptance statement on the reviewed candidate, not independent pixel-capture evidence. The owner did not certify an exact number of manually clicked edits or a measured FPS threshold; do not invent either.

**Gate:** `P1_0C_OWNER_GUI_PASS_REPORTED / SOURCE_REVIEW_PASS / MERGE_AUTHORIZATION_PENDING`.

## Known non-blocking limitations and boundaries
- Bounded in-memory global ordered brush ledger: up to 256 accepted commands; operation 257 rejects with `ledger_capacity_exceeded` until a focused X/reset frees capacity. No disk persistence or crash recovery.
- Source-reviewed v1 adaptive ray picking, exact ordered carve/fill semantics, stage cancellation and resource caps remain unchanged by this *documentation-only* handoff.
- Developer-measured, local headless *worst-layout* at 255 nearby operations: mesh transaction p95 ~244.319 ms, click-to-scene-visible p95 ~248.249 ms; transient frame peak ~110.336 ms. These do not establish GPU presentation latency or universal smooth FPS.
- Fixed worker/render/resident upper bounds: four CPU jobs in flight, two `ArrayMesh` constructions/frame, 25 regions/400 chunks resident.
- Phase P1 as a whole is NOT complete. Backend comparison/ADR-0002, durable saving, production LOD/materials and other P1 gates remain separate.
- F2-G1 still on HOLD: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

## Next authorized step
The owner authorized **documentation reconciliation and readiness preparation only**, online. No explicit approval to merge #92 or #87, close issues or run protected operations was provided. The next step is a deliberate owner decision on PR #92 integration, after reconfirming live HEAD, docs-only ancestry and mergeability. On an explicitly authorized merge, verify the actual `main` merge SHA before adding the *post-merge* checkpoint and `CHANGELOG` entry. P1.1 discussion/planning may proceed, but no P1.1 implementation has been authorized.
