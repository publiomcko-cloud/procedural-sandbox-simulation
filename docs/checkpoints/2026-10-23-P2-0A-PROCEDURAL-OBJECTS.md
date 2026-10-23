# P2.0A — Mod-First Procedural Objects Checkpoint

Date: 2026-10-23  
Feature branch: `feat/p2-0a-mod-first-procedural-objects`  
Implementation commit: `5dd3ddf40b955c373868797c1b79c47a1f0755dc`  
Implementation parent: `0ea2ad834db5dc2de1110cf0388ea06604cc7715`  
Verified base: `main` at `0ea2ad834db5dc2de1110cf0388ea06604cc7715`

## Delivered

- Added a node-independent deterministic placement-record builder for two required namespaced rock definitions. It uses the P0.3 `ContentDefinitionRegistry` recipe/pin APIs and canonical SDF v1 surface samples, and supports signed region coordinates and discovery-order-independent identities.
- Added a shared bounded low-poly mesh adapter for `stacked_spheres_v1`. First-party and external definitions use the same recipe and rendering path.
- Added a transient object stream that discovers bundled first-party content and the authorized `user://mods` root, with the repository example as a source-checkout fallback. It rejects missing/incompatible required content, publishes once per actually published terrain region, and releases representations on region unload.
- Integrated the stream with terrain region publication/unload, added `V` visibility toggle and concise HUD status. Existing terrain input paths, including `L`, remain in place.
- Added deterministic and playable-scene tests, wired into `scripts/validate.ps1`, and documented the scope and limitations in `docs/specs/P2-0A-MOD-FIRST-PROCEDURAL-OBJECTS.md`.

## Validation evidence

Pinned executable: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`  
Version: `4.7.2.stable.official.ed1daf0bf`  
Executable SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`

Focused import and object suite passed: `PROCEDURAL_OBJECT_PASS: assertions=117 failures=0`.

Full validation ran once after implementation stabilization using an isolated temporary `APPDATA` profile. `scripts/validate.ps1` exited 0 and ended with `VALIDATION_PASS: L0-L2; GUI visual test remains an owner task`. Sixteen assertion groups completed with 17,375 assertions and zero reported failures. No parser, script, runtime error or warning diagnostics were present. The bootstrap structural check explicitly does not assess rendered pixels.

Raw validation log and run metadata:

`C:\Users\PUBLI\AppData\Local\Temp\p2_0a_full_validation_b0d8e6626740431695b0ef5f11539461\validate.log`  
`C:\Users\PUBLI\AppData\Local\Temp\p2_0a_full_validation_b0d8e6626740431695b0ef5f11539461\run-metadata.txt`

Observed exploratory tests report workload measurements only; this slice has no approved performance target and headless timing does not establish GUI/GPU acceptance.

## Boundaries and limitations

- Object records and meshes are derived and transient. They are not written to the schema-1 world save, edit ledger, or production terrain state.
- Placement checks the base canonical SDF v1 surface, not accumulated terrain edits. Subsequent carve/fill edits can leave a rock floating, buried, or intersecting the changed surface; unload/reload recreates its deterministic original placement.
- No physics bodies, collision, object editing, entity persistence, migration, networking, or generalized ECS were added.
- Owner GUI verification is still required for rock silhouette, scale, grounding/readability, streaming at positive and negative regions, and the `V`, `L`, `P`, and `O` controls. No visual acceptance is claimed.
- `docs/status/CURRENT_STATUS.md` was not changed because its local snapshot did not match the verified live main and draft PRs #100/#101 are open against overlapping documentation. This checkpoint records the verified refs directly. PRs #100/#101 were not modified.
- No protected F2-G1 operation was performed. The five holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

## Review and integration state

This checkpoint records implementation and local Godot validation only. Independent source review, owner GUI acceptance, and PR integration remain pending. The feature branch is based on the verified main commit above; no merge or release was performed.
