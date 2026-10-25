# P3.1 Storage — implementation candidate

**Status: IMPLEMENTATION CANDIDATE; independent source review and owner GUI retest pending.** Source HEAD 1438784d40567a787156afc12778cc30e27365e0 on draft PR #129, based on main 5997a76d345f45bf86edfe83f690336391e8be27. The architecture proposal remains separate in draft PR #128; neither PR is merged.

## Scope

Replace the global 256-edit prototype admission limit with finite schema-2 terrain storage. Preserve canonical SDF generator v1, world identity/seed, globally ordered CARVE/FILL min/max operations, regional ownership, streaming, LOD and existing explicit P-save behavior. Entity schema 3 is untouched. Issue #108 terrain/object imprint is excluded.

Schema-1 saves stay under user://worlds/<world-id>. Schema 2 uses a separate user://worlds-v2/<world-id> namespace. The runtime detects and reports a legacy save but does not read, import, overwrite or delete it. The owner starts a separate v2 world.

## Schema-2 storage model

- The globally sequenced command records remain authoritative: sequence, revision, mode, world-space center and radius, plus manifest world ID, seed, generator version, revision and next sequence.
- A generation is represented by bounded immutable content-addressed operation segments, a spatial reference index, and a hash-checked manifest. Segment boundaries do not change global order.
- Region support and conservative mesh-query indexes store sequence references only. Load recomputes their meaning from the canonical commands and rejects mismatches. Chunk queries filter the conservative candidate set by exact chunk/normal-probe bounds; general sampling streams the complete ordered log when required by min/max semantics.
- Startup verifies the generation and index, then attaches a lazy source reference to the ledger rather than materializing every operation dictionary. Operations are loaded a segment at a time for source-backed reads.
- No mesh/voxel approximation or lossy compaction is authoritative. The v1 evaluator remains the semantic reference.

## Commit and recovery behavior

New immutable segments/index bytes are written to unique temporary files, read back and hashed, then renamed. The manifest is written and verified as temporary data and committed last by rename. A partial invalid temporary manifest is ignored and the prior valid committed generation can be recovered; a valid complete temporary manifest can be verified and promoted.

A corrupt newer committed .json generation must not silently roll back accepted edits: load now fails with newest_committed_v2_generation_corrupt, with diagnostics. If the latest generation is corrupt, owner recovery is manual; the implementation does not pretend an older generation represents the latest saved state.

Committed files are retained; no compaction or garbage collection is implemented. Saves are explicit, not per-edit durable. The storage contract assumes one writer process. Readback/hash checks and process-interruption fixtures do not establish physical power-loss durability or cross-process locking.

## Finite limits

- 65,536 active operations per world.
- 128 operations and 2 MiB maximum per operation segment.
- 256 MiB aggregate v2 directory quota, including retained generations and temporary/orphan files.
- 2,000,000 aggregate spatial index references.
- Region/query indexes and file sizes are bounded. Quota exhaustion blocks saving; it never discards commands.

These are implementation limits, not infinite capacity or product performance acceptance. Retained generations can eventually exhaust disk quota; cleanup policy needs a separate safe design.

## Verification evidence

Godot 4.7.2.stable.official.ed1daf0bf, isolated APPDATA/LOCALAPPDATA: scripts/validate.ps1 exited 0 with 20,660 assertions across 21 assertion-marker suites; no failed assertions, parser errors or script errors. Three non-fatal existing procedural-object test warnings concern colinear camera target/up vectors. Headless startup passed; visual acceptance is not claimed.

The V2 storage suite passed 2,778 assertions. It tested 640 distributed alternating operations and 2,048 concentrated alternating operations, exact full-order evaluator parity, negative/positive boundaries, lazy reload, LOD0/LOD1 reconstruction, resets, interrupted manifests, corruption, quotas and preservation of schema-1 fixture bytes.

Exploratory single-run timings from the isolated local test process (not thresholds): 640 distributed operations: generation 20.975 ms, save 202.067 ms, verify/load 69.153 ms, LOD0 chunk 20.881 ms, LOD1 chunk 110.889 ms. 2,048 concentrated operations: generation 73.698 ms, static process-memory delta during generation 4,260,068 bytes (not RSS/peak), save 638.134 ms, verify/load 180.677 ms, four-probe replay 374.712 ms, LOD0 chunk 560.192 ms, LOD1 chunk 1,959.425 ms. These are machine-specific exploratory measurements, not scored acceptance.

Full raw validation log: C:/Users/PUBLI/AppData/Local/Temp/p3-1-final-validation-1433ea3971a94553b92406be4f8dac14/validate.log. Focused V2 test evidence was produced in isolated disposable fixtures; no actual schema-1 user save was opened.

## Next gates and limitations

1. Independent exact-SHA source review of PR #129.
2. Owner GUI retest on the separate v2 namespace and confirm the schema-1 save remains intact.
3. Review the finite quotas, recovery behavior and retained-generation disk policy before merge.
4. Do not start Issue #108 work until its separate architectural blockers are addressed.

All five F2-G1 holds remain: CURRENT_PROTECTED_STATE_UNKNOWN, V3_NOT_ATTESTED, ACL_REVIEW_REQUIRED, G1_BLOCKED_ENVIRONMENT, F2_G1_RELEASE_HOLD.