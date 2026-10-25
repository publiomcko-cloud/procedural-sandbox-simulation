# P3.1 storage lazy-reference identity correction — 2026-10-25

## Exact source state

- Repository: publiomcko-cloud/procedural-sandbox-simulation.
- Verified main/base: 5997a76d345f45bf86edfe83f690336391e8be27.
- Branch: feat/p3-1-scalable-terrain-storage.
- Corrected candidate HEAD: db1c72fadd24e69f87f0eb2c5091cee1ac1b39da.
- Direct parent: 1438784d40567a787156afc12778cc30e27365e0.
- Existing PR #129 is open, draft, unmerged. Separate architecture PR #128 remains untouched.

## Finding and correction

Source inspection found that a lazy storage reference was matched against world ID, generation, count and revisions, but its world seed and generator version were not compared. A mismatched reference could therefore attach a source whose commands would not correspond to the ledger's identity. The v2 store now checks both identity fields. New negative tests alter each field independently and verify that restoration rejects the reference while leaving the target ledger pristine.

The prior checkpoint [P3.1 implementation candidate](2026-10-25-P3-1-STORAGE-IMPLEMENTATION.md) remains unchanged and records source HEAD 1438784d. This checkpoint records its subsequent identity correction.

## Validation

Godot 4.7.2.stable.official.ed1daf0bf; executable SHA-256 c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643. Full scripts/validate.ps1 used an isolated temporary APPDATA/LOCALAPPDATA profile and exited 0. It reported 20,664 assertions across 21 assertion-marker suites, zero failed assertions, and no parser/script errors. The V2 storage suite passed 2,782 assertions. Three non-fatal colinear camera target/up-vector warnings were emitted by unchanged procedural-object tests; pixel appearance is not assessed by the headless bootstrap check.

Focused storage evidence also passed 2,782 assertions. The full result's raw log is C:/Users/PUBLI/AppData/Local/Temp/p3-1-final-validation-r2-e6af7864106c4da486ff73bb2f436638/validate.log; exit code 0 is in exit-code.txt.

Latest exploratory measurements (one local run; not acceptance budgets):

| Workload | Generation | Save | Verify/load | Replay | LOD0 | LOD1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 640 distributed | 39.212 ms | 181.252 ms | 58.731 ms | — | 19.144 ms | 107.248 ms |
| 2,048 concentrated | 77.724 ms | 625.303 ms | 177.044 ms | 379.799 ms / four probes | 576.161 ms | 2,002.461 ms |

Generation memory delta was 4,260,068 bytes from Godot static-memory accounting; it is not process RSS or peak memory. These figures are exploratory, machine-specific and not product acceptance.

## Pending gates and limits

Independent exact-SHA source review and owner GUI retest remain pending. Schema 1 was not opened from user data; only disposable fixture bytes were checked for non-modification. V2 remains an explicit separate world path. No automatic migration/deletion, lossy compaction, garbage collection, cross-process writer lock, per-edit save durability or physical power-loss guarantee is claimed. Issue #108 remains excluded. Preserve all five F2-G1 holds.