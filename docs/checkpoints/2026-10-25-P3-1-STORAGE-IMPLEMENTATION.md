# P3.1 Storage implementation candidate — 2026-10-25

## Identity and state

- Repository: publiomcko-cloud/procedural-sandbox-simulation; origin was verified as the expected GitHub repository.
- Verified main/base: 5997a76d345f45bf86edfe83f690336391e8be27.
- Implementation branch: feat/p3-1-scalable-terrain-storage.
- Candidate HEAD: 1438784d40567a787156afc12778cc30e27365e0.
- Direct parent: ad53055f0a63da2d8d79ff3efaea2358c27acdba.
- Implementation PR #129: open, draft, unmerged. Architecture PR #128: open, draft, unchanged.
- Worktree after commit/push: only the three pre-existing untracked P1.1B .gd.uid files remained; stash@{0} and stash@{1} were preserved.

## Decision and scope

Owner authorized P3.1 on 2026-10-25 and explicitly allowed starting a clean schema-2 terrain store without legacy schema-1 read/migration. Legacy files must not be automatically deleted or overwritten. This event records a source candidate, not independent review, owner GUI acceptance, merge or release.

Implemented a new v2 namespace, immutable globally ordered segments, checked manifest and spatial reference index. SDF generator v1 and CARVE/FILL operation order remain authoritative. No lossy compaction, Issue #108, entity schema change or F2-G1 operation was performed.

## Source changes

Fifteen implementation/test files changed:

- game/scripts/experiments/lod01_transition_fixture.gd
- game/scripts/terrain/sdf_brush_edit_state.gd
- game/scripts/terrain/terrain_demo.gd
- game/scripts/terrain/terrain_mesh_job.gd
- game/scripts/terrain/terrain_world_save_store_v2.gd
- game/scripts/terrain/terrain_world_save_store_v2.gd.uid
- game/tests/lod01_transition_tests.gd
- game/tests/p3_0d_entity_placement_tests.gd
- game/tests/terrain_brush_tests.gd
- game/tests/terrain_end_to_end_perf.gd
- game/tests/terrain_history_tests.gd
- game/tests/terrain_multiregion_tests.gd
- game/tests/terrain_picker_history_perf.gd
- game/tests/terrain_world_persistence_process_probe.gd
- game/tests/terrain_world_persistence_tests.gd

The three untracked P1.1B benchmark UID files were not added or changed.

## Validation and evidence class

Godot 4.7.2.stable.official.ed1daf0bf, executable SHA-256 c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643. Full scripts/validate.ps1 was run with a unique temporary APPDATA/LOCALAPPDATA profile and exited 0. Actual assertion markers total 20,660 across 21 suites; all failure counts were zero, with no parser/script/validation error markers. Main-scene startup passed. Three non-fatal colinear target/up-vector warnings occurred in procedural-object scene tests, outside the changed files.

Focused terrain V2 storage suite: 2,778 assertions, 0 failures.

Scenarios included 640 distributed and 2,048 concentrated alternating CARVE/FILL operations, operation order parity against the full v1 evaluator, negative and positive boundaries, save/load/restart, lazy source attachment, LOD0/LOD1 reconstruction, reset, corruption, quotas, interrupted manifest recovery and unchanged schema-1 fixture bytes.

Recovery correction after source inspection: a corrupt newer committed JSON generation previously could be ignored while an older generation loaded. The loader now returns newest_committed_v2_generation_corrupt instead of silently rolling back. Incomplete temporary manifests still fall back to the prior valid commit; a complete valid temporary generation remains promotable.

Raw full validation log: C:/Users/PUBLI/AppData/Local/Temp/p3-1-final-validation-1433ea3971a94553b92406be4f8dac14/validate.log. Exit code: 0. Focused storage run passed in an isolated disposable fixture root.

Exploratory performance observations from the full run:

| Workload | Generation | Save | Verify/load | Replay | LOD0 chunk | LOD1 chunk | Segments |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 distributed | 20.975 ms | 202.067 ms | 69.153 ms | — | 20.881 ms | 110.889 ms | 5 |
| 2,048 concentrated | 73.698 ms | 638.134 ms | 180.677 ms | 374.712 ms (4 probes) | 560.192 ms | 1,959.425 ms | 16 |

Concentrated generation reported a 4,260,068-byte process static-memory delta; this is not RSS or peak memory. All timings are one local exploratory run, not product budgets or performance acceptance.

## Limits and pending gates

- Finite quotas: 65,536 active operations, 128 ops/2 MiB per segment, 256 MiB total v2 directory and 2,000,000 spatial refs. No silent eviction.
- Segments/indexes are retained; no garbage collection/compaction exists. Eventually a full disk quota blocks further save.
- Single writer process assumed; no cross-process writer lock.
- Explicit P save only. File flush/readback does not prove physical power-loss durability or directory fsync.
- Owner GUI retest has not occurred. Schema-1 user files were not read or accessed by tests; only isolated schema-1 fixture bytes were checked for preservation.
- Independent source review is pending. Starter checks passed at exact source SHA; they are static only.
- Issue #108 remains excluded.

Owner GUI retest: run terrain_demo.tscn with a disposable/test Windows profile; verify it reports any legacy schema-1 save as preserved and starts a separate v2 world. Add alternating carve/fill edits across positive/negative region boundaries, press P, restart, press O and compare visible boundaries/LOD with pre-save state. Confirm the old schema-1 file bytes and path remain unchanged. This visual procedure is not automated acceptance.

All five F2-G1 holds remain unchanged: CURRENT_PROTECTED_STATE_UNKNOWN; V3_NOT_ATTESTED; ACL_REVIEW_REQUIRED; G1_BLOCKED_ENVIRONMENT; F2_G1_RELEASE_HOLD.