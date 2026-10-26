# P3.1 R3B — benchmark preregistration (experimental)

Date: 2026-10-26. Production source is pinned to `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`; no production path, save schema or user save is in scope. Workloads are the byte-identical Issue #131 R3A fixture set, whose scenario-manifest SHA-256 is `2dff9ccd5b98e1ea722051b25f961ff8f64c3ae698f3bc12102826e04ec3088d` and SHA256SUMS SHA-256 is `ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1`.

## Frozen inputs and run plan

Seed `131102026`, SDF generator v1, radius `0.580` world units (`580` mm), operation order from frozen files, CARVE/FILL modes as serialized. Counts 256, 640, 2048, 8192 in both CONCENTRATED and DISTRIBUTED layouts. Region/chunk is `(0,0)/(0,0)` for concentrated and `(-31,-64)/(2,2)` for distributed. Each case is run in five independent Godot processes (`R01`–`R05`) on the same machine and executable, with paired canonical/optimized measurements in each process; query order is alternated per probe and mesh order is counterbalanced by repetition, iteration and LOD. Cold mesh build, warm memory hit, fresh-instance disk hit, post-remote-edit lookup and post-local-edit rebuild are separately measured. Corrupt-entry fallback is a separate functional test in the exactness/cache contract suite. No workload input or threshold changes after first final run.

Commands and per-run outputs are recorded by the external serial launcher. It records process ID, launcher ID, sampled Windows working/private bytes every 100 ms, and the OS-reported peak working set when available; these observations are not a precise allocator census. Godot results use monotonic process-local microseconds and report p50/p95/p99 only within a scenario and process; the five process medians and range are reported separately. A failed assertion, nonzero exit, timeout, missing result row, or incomplete cache outcome invalidates that process sample. It is retained and never silently replaced. No headless timing is presented as rendered FPS, GPU completion, or user-perceived frame time.

## Exactness contract

The canonical oracle is the pinned production SDF v1 plus the pinned production ordered CARVE/FILL evaluator, including arbitrary off-grid coordinates. Exact replay must have zero bitwise density mismatches at frozen and seeded adversarial probes, including cave points, signed region boundaries, overlaps, and points near brush surfaces; finite-difference normals and picker ray outcomes must match exactly. LOD0/LOD1 CPU mesh positions, normals, topology counts and sample counts must match the canonical builder exactly for both layouts/counts. Cache hits must decode to exact canonical arrays. Any exactness mismatch rejects the relevant optimization, regardless of speed.

## Proposed experimental gates (not owner-approved product budgets)

These bounds are frozen for evaluating the prototype, not for product acceptance:

* Exact replay: zero exactness mismatches; for concentrated N8192 LOD1, median CPU build at least 2x faster than paired canonical in each repetition; at every other size/layout, optimized median may not regress by more than 10% in at least four of five repetitions. If an exact repetition reduction is not present in a frozen history, use the canonical evaluator and report fallback.
* Cache: 100% hit for a proven remote edit whose exact chunk snapshot is unchanged; local dependency change must miss and reproduce exact canonical output; corrupt entries must rebuild exactly. Fresh-process disk hit median should be below 50% of cold build median; first cold build/cache-write overhead should be no more than 10% over canonical build plus serialization. Cache prototype caps are 64 MiB of `.bin` files, 128 files, 16 MiB of serialized resident mesh payload accounting and 32 entries. The in-memory cap measures each cached mesh using `var_to_bytes` size; it is a deterministic cache-payload budget, not a bound on Godot allocator overhead or total process RSS. Those are measured separately where the host observation supports them. Quota exhaustion declines cache publication while returning the canonical build; no world operation is rejected.
* No acceptance budget exists for hardware FPS, frame stalls, shipped RAM/VRAM, world-scale disk, user latency, or visual quality. These remain `OWNER_TO_DEFINE`.

## Reporting

Publish raw JSONL/CSV and command/environment records; all artifacts receive SHA-256 inventory after final campaign. Report all five repetitions, failures and outliers, not only pooled percentiles. CPU builder timings exclude GPU upload/render/presentation. Any comparison the harness cannot measure is `NOT_MEASURED`.
