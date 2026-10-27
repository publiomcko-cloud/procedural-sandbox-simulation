# P3.1 R4 campaign closeout

**Checkpoint ID/date:** `CHK-2026-10-26-P3-1-R4-CAMPAIGN-CLOSEOUT`; 2026-10-26

**Event type:** experimental campaign and evidence/report closeout

**Publication state:** separate evidence PR #141 is open, draft and unmerged; base is the P3.1 storage candidate branch

## Identity and scope

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Production baseline: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Worktree/branch: `C:\Dev\sandbox-sim-p3-1-r4-subledger-snapshots`, `bench/p3-1-r4-subledger-snapshots`.
- Evidence PR: [#141](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/141), based on `feat/p3-1-scalable-terrain-storage` at `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`; PR #129 remains open/draft/unmerged and unchanged.
- Campaign source: `83c7c091bcec0d10534d8638225d3d24d94b6334`, parent `8b76e778b0f282a37aa11a229b795c423f581467`. Documentation/report corrections are being committed after the campaign; the benchmark data remain attributed to the campaign source SHA.
- Evidence/report commit: `4c71f2b0b8e5e8c30a047626dd3a5e588aafe71e`, direct parent `83c7c091bcec0d10534d8638225d3d24d94b6334`.
- Frozen manifest SHA-256: `c6fd895685304795101968ed1104385d31c3f4b1cf303fb26582b16a22666c31`.
- Godot: `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Only test/benchmark prototypes and evidence/documentation were changed. Production terrain, ledger, schemas, saves, PR #129 and Issue #108 were not modified.

## Validation and evidence

- Focused R4 architecture suite: 201 assertions, zero failures. R4 benchmark script `--check-only` and editor import passed.
- Full `scripts/validate.ps1`, using isolated `APPDATA`, `LOCALAPPDATA`, `TEMP` and `TMP`: exit 0; 21 groups; 21,464 assertions; zero failures. The host could not create the existing junction/reparse fixture (`DirAccess.create_link` returned `Failed`), so that subtest is unavailable in this run. This is explicitly recorded as a limitation.
- A first validation attempt using the normal profile hit two `duplicate_mod_id` assertions and was stopped. No user mods or saves were removed or modified. Both that log and the isolated successful run are retained.
- The final experimental campaign executed 90 fresh Godot processes (18 frozen scenario instances × five repeats); 90 PASS records, exit 0, no campaign timeout or unrun row. It yielded 1,230 corrected metric rows and 246 groups. The R5 exporter independently checked source/manifest identity, 90 result files, and 560 artifact hashes.
- Raw campaign bundle SHA-256: `06398da449df934a286312cd05ba90e0303327fb3ab475c20f2820e785d83d83`.
- R5 derived metric CSV SHA-256: `b9dd771dc3aececf406fd81b8f4f5681ab2b5e8f552022baee342588122e706c`; summary CSV `aaeafc530b949d52955c68a83c79b5a521604af01b0edd29db5b4af574fd2ad2`; artifact inventory `bdfe4f3bf5bee5263454a02703f990e17f6f1f53ca4a266d4baf52d04e2f06fc`; R5 integrity manifest `049d0c9109072dfe66937ade6d6846733fea386d8417abc0f1965a189c4037ae`.
- Evidence files and per-file hashes are indexed in `docs/reports/P3-1-R4/evidence/final-r4/evidence-index.csv`. Original raw outputs and earlier derived-report versions remain preserved.

## Results and limits

Architecture A's chunk subledger matched canonical density probes and LOD0/LOD1 mesh arrays in all recorded campaign runs (5,760 density probes plus bitwise mesh-array comparisons). However, the preregistered LOD0 p95 regression screen was exceeded in multiple rows. A is exact but has not cleared the complete exploratory adoption screen; focused LOD0 performance work is still required before any production proposal.

Architectures B/C use sampled/interpolated float32 fields and are approximate. At concentrated 8,192 edits, selected median surface-distance p95 values at spacing 0.5 were 0.0674/0.0540 world units for LOD0/LOD1; nonperiodic concentrated values rose to 0.517/0.638, with large normal-angle differences. No owner-approved geometric tolerance exists. These lower-fidelity CPU results are not comparable production speedups.

All timing evidence is headless. No rendered FPS, presented frame, GPU completion, VRAM or engine OS RSS was measured. The runner's peak working set is the launcher process and is labeled accordingly; allocator delta is separately reported. An unrelated long-running Godot process was present on the host and may have affected timings. Results are UNSCORED and exploratory; no art, owner GUI, production, merge or release approval is claimed.

The isolated validation log reports 21,464 assertions with zero failures, but the junction/reparse fixture was unavailable. The normal-profile duplicate-mod failure is retained as an environmental observation, not resolved by modifying user data.

## Recommendation and gates

Keep the global schema-v2 ledger as the sole authority. Continue A only as an exact derived projection candidate and investigate the LOD0 p95 regression. Do not adopt B/C as production geometry absent owner-approved fidelity limits and cave/tunnel/picker behavior criteria. Independent exact-source/evidence review and owner GUI review remain outstanding. PR #141 is a separate draft evidence PR; no merge is authorized.

All protected-state holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
