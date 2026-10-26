# P3.1 Storage — R2 Query and Append Corrections

**Checkpoint date:** 2026-10-25 (America/Sao_Paulo)  
**Event:** Issue #127 R2 implementation corrections and full validation  
**Publication:** Existing draft PR #129; open and unmerged at checkpoint creation  
**Immutable:** yes; subsequent review, GUI, or merge outcomes require a separate checkpoint.

## Repository identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Baseline/main: `5997a76d345f45bf86edfe83f690336391e8be27`
- Starting PR #129 head: `db1c72fadd24e69f87f0eb2c5091cee1ac1b39da`
- Source correction commit: `ea18432c6f9cfc1912e1d4aeb5363bb8f5bc9731` (parent `db1c72fadd24e69f87f0eb2c5091cee1ac1b39da`)
- Branch: `feat/p3-1-scalable-terrain-storage`
- PR: [#129](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/129), draft, not merged
- Design PR #128 and parallel PR #130 were not changed.

## Corrections

The R2 query path no longer scans and decodes every saved segment for each density sample. Schema-v2 maintains a conservative query-region index based on the 9-unit proven min/max SDF influence bound, separate from geometric support. Queries deduplicate and resolve only referenced immutable segments, read each selected segment once per request, and return operations in global sequence order. A bounded 8 MiB segment LRU avoids repeated decoding. The in-memory ledger uses the same conservative spatial candidate selection; outside the bounded field domain it deliberately falls back to full ordered replay.

Chunk and ray snapshots propagate conservative minimum/maximum density intervals through the ordered CARVE/FILL min/max operations. An operation is omitted only when its threshold is dominated for every point in the query domain, including the chunk's normal-sampling margin. Consecutive identical operations are removed only when adjacent and mathematically idempotent. No operation is omitted solely because the query lies outside its geometric brush radius. Exact parity is checked against the full replay, including persisted and negative-coordinate cases.

Subsequent append-only saves reuse already committed segment and index identities when the loaded source identity is current and the ledger delta is a contiguous append with no exclusions/reset. Reused bytes are rehashed before publishing a new manifest; only newly appended records are serialized into new immutable segments. The manifest remains the commit point and the in-memory source reference is rebound only after successful readback. Historical files are never garbage-collected. The 256 MiB world quota rejects a write rather than deleting a recovery generation. Schema-1 data remains in its separate namespace and is neither migrated, overwritten, nor deleted.

## Changed paths

- `game/scripts/terrain/sdf_brush_edit_state.gd`
- `game/scripts/terrain/terrain_world_save_store_v2.gd`
- `game/tests/terrain_history_tests.gd`
- `game/tests/terrain_world_persistence_tests.gd`
- `docs/checkpoints/2026-10-25-P3-1-STORAGE-R2-CORRECTIONS.md`
- `docs/checkpoints/INDEX.md`
- `docs/status/CURRENT_STATUS.md`

## Validation evidence

- Godot: `4.7.2.stable.official.ed1daf0bf`; executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`; SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.
- Focused persistence suite: `TERRAIN_WORLD_V2_STORAGE_PASS`, 3,516 assertions, zero failures. It covers distributed/concentrated 640, 2,048 and 8,192 operation ledgers, full-replay parity, repeated saves and restart verification, read/candidate accounting, LOD0/LOD1 reconstruction, corruption, interrupted writes, quota behavior, and legacy namespace preservation.
- Full `scripts/validate.ps1`: exit code 0; `VALIDATION_PASS: L0-L2`; 21 assertion-marker suites, 21,464 assertions, zero failures. Main-scene startup and project import completed. Three non-fatal camera target/up colinearity warnings were emitted. The host could not create the optional Issue #118 junction fixture (`DirAccess.create_link returned Failed`); that specific reparse fixture was unavailable, while the suite completed successfully.
- Final complete log: `C:\Users\PUBLI\AppData\Local\Temp\p31-storage-r2-validation-isolated-85b349988b7746be96ae85a938cfa79d\validate.console.txt`; SHA-256 `934F236E4F5BB03A625DB18D7BFB9F412F1DD7CFC1FC0E2F7E01B4B91B79FDA3`; `exit-code.txt` contains `0`; PowerShell stderr was empty. The validation used an isolated temporary `APPDATA` Godot profile so installed user mods did not contaminate declarative-mod tests.
- Earlier attempts remain preserved: a Windows PowerShell native-stderr promotion and default-profile test contamination, then a PowerShell 7 default-profile run with five cascading mod-contamination failures. They are not counted as passing runs. No user save was deleted or rewritten.
- `git diff --check` passed before source commit and after documentation edits. The three pre-existing untracked P1.1B `.gd.uid` files and both stashes remained present.

## Exploratory performance observations

These are developer-run headless measurements from the final full validation, not acceptance budgets. Times are milliseconds; each profile reports its own run. `process_memory_delta_bytes` is the harness's measured process-static delta, not peak resident memory. LOD timings represent isolated chunk reconstruction, not presented-frame performance.

| Operations | Distribution | Point SDF p50/p95/p99 | Ray snapshot p50/p95/p99 | Picker p50/p95/p99 | Ray end-to-end p50/p95/p99 | Repeat-save p50/p95/p99 | LOD0 / LOD1 | Disk bytes | Static memory delta | Query candidates / segment reads |
|---:|---|---|---|---|---|---|---:|---:|---:|---|
| 640 | distributed | 0.013 / 0.014 / 0.019 | 0.055 / 0.061 / 0.095 | 0.085 / 0.088 / 0.108 | 0.142 / 0.155 / 0.194 | 32.889 / 34.615 / 34.615 | 21.177 / 109.918 | 107,547 | 714,220 | 0 / 0 |
| 640 | concentrated | 1.723 / 1.789 / 2.112 | 2.433 / 5.120 / 5.694 | 0.095 / 0.153 / 0.203 | 2.529 / 5.279 / 5.851 | 29.105 / 29.698 / 29.698 | 161.494 / 672.016 | 112,645 | 821,938 | 640 / 5 |
| 2,048 | distributed | 0.013 / 0.014 / 0.018 | 0.055 / 0.076 / 0.106 | 0.086 / 0.105 / 0.145 | 0.143 / 0.216 / 0.232 | 49.797 / 50.523 / 50.523 | 18.076 / 97.559 | 343,132 | 1,889,232 | 0 / 0 |
| 2,048 | concentrated | 5.618 / 8.236 / 8.616 | 7.839 / 9.051 / 11.437 | 0.100 / 0.114 / 0.156 | 7.947 / 9.212 / 11.608 | 40.874 / 41.384 / 41.384 | 466.621 / 1,958.178 | 368,235 | 2,686,617 | 2,048 / 16 |
| 8,192 | distributed | 0.126 / 0.139 / 0.189 | 0.629 / 0.688 / 1.402 | 0.092 / 0.097 / 0.115 | 0.725 / 0.785 / 1.513 | 125.178 / 126.879 / 126.879 | 17.819 / 99.925 | 1,364,055 | 9,500,220 | 5 / 3 |
| 8,192 | concentrated | 33.882 / 42.209 / 49.133 | 41.978 / 49.599 / 63.039 | 0.124 / 0.175 / 0.188 | 42.113 / 49.786 / 63.183 | 102.955 / 105.158 / 105.158 | 1,792.553 / 6,454.740 | 1,499,302 | 8,448,473 | 8,192 / 64 |

The concentrated 8,192-command query still visits 64 local segment candidates, so the spatial index does not reduce work for a history wholly concentrated in the queried region. The 8 MiB decoded-cache bound is a conservative estimate based on serialized segment bytes and a per-operation weight, not a measured peak heap cap. Each append save rehashes reused segments to detect post-load corruption; it avoids rewriting history but still performs I/O proportional to reused bytes. Full restart verification likewise reads the complete referenced generation. No host/GPU-presented frame, peak VRAM/RAM, GUI acceptance, or approved performance threshold is established.

## Disposition and remaining gates

This is a P3.1 R2 implementation candidate, not independent source approval, owner GUI acceptance, merge authorization, or release approval. PR #129 remains draft/unmerged. Review the exact pushed SHA and run owner GUI save/restart checks separately. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`. No F2-G1/protected-host operation was performed.
