# CHK-2026-10-17-P1-0C-PREPARED-ISSUE91 — next core milestone plan

**Date:** 2026-10-17 UTC−03. **Type:** owner-requested significant planning handoff, **not implementation authorization**. Prepared in open docs-only PR #87.

- Verified repo [publiomcko-cloud/procedural-sandbox-simulation](https://github.com/publiomcko-cloud/procedural-sandbox-simulation), `main` `2f86c42503cfa3a334215b1ff5b9bf9658263440` (PR #90 actual merge).
- [Parent P1.0 plan #83](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/83) specifies P1.0C globally ordered commands across regions. New [Issue #91](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/91) prepared to implement **global world-space SDF carve/fill**, including effects across positive/negative region borders/corners, updates of loaded or unloaded neighbors, deterministic replay during unload/reload within the same process, and atomic multi-region mesh publication.
- Remote feature branch `feat/p1-0c-global-cross-region-brushes` created at `2f86c42503cfa3a334215b1ff5b9bf9658263440`. No implementation or feature PR created in this action.
- Critical inherited constraints: P1.0B currently uses local operation sequence/32 brush cap per region and caches only 16 edited-region states. Do not silently evict previously accepted edits. Decide bounded global ledger/admission, exact X clear semantics, revisions for in-flight stages and failure/cancellation rollback *before* coding. Evaluate seam normals/mesh parity under edited boundary/corners, and unload/reload replays; keep meshes derived.
- Existing Windows workspace `C:\Dev\sandbox-sim-dev` only after inspecting dirty/untracked state and ensuring previous Codex has stopped. The prior lighting handoff noted CRLF-only modification in `game/project.godot` and untracked experimental capture directories; do not clean/reset without permission.
- No networking, multiplayer server, persistence to disk, native addon, LOD/collision or F2-G1 protected execution is part of this preparation. Future multiplayer compatibility remains data-contract intent only.
- All five F2-G1 protected holds preserved. Local Godot baseline from Codex: 7,947 assertions; GitHub CI static only.

**Next authorized gate:** owner explicitly authorizes P1.0C implementation of [Issue #91](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/91), then Codex prepares a single draft PR for independent SHA-specific review and owner GUI check. No automatic start or merge.
