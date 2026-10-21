# P1.1B-B1-1 — Test-only benchmark harness contract

**Implementation baseline:** ea4422d90726d3f2fe6d5cef097126268f93685a (owner-approved B0 R4/R4a contract).
**Harness schema:** P1.1B-B1-1.v1.
**Disposition:** opt-in synthetic/fixture measurement infrastructure only. This file records no benchmark execution, no Godot runtime validation, no performance acceptance, and no target-hardware result.

## Scope and invocation boundary

The harness is an isolated SceneTree script under game/tests. It is not referenced by the project main scene, production scripts, or scripts/validate.ps1. It accepts exactly one --scenario-id <id> argument, verifies the checked-in canonical manifest and sidecar SHA-256 before dispatch, requires Godot 4.7.2.stable.official.ed1daf0bf, and rejects IDs outside the FROZEN registry. It has no default scenario, “all” option, caller-selected path, backend switch, or native dependency.

From the repository root, the future separately authorized invocation form is:

    godot --headless --path ./game --script res://tests/p1_1b_benchmark_harness.gd -- --scenario-id B0A.INTERIOR.N032.v1

This command is documentation for a later authorized run; it was not executed here. Use one fresh process per scenario run when following the approved per-process sampling proposal. Do not treat this harness as authorization to run it.

The runner emits one JSON object per line to stdout with prefix P1B1_JSONL; it does not select or write an artifact directory. Raw-result retention/storage remains OWNER_TO_DEFINE. Before a future run, independently verify git rev-parse HEAD, the physical source hashes and the expected review SHA. The runner deliberately does not claim a self-reported Git commit identity.

## Manifest identity and command identity

game/tests/fixtures/p1_1b_b0_manifest.json contains the 44 executable scenario definitions and their recipe parameters; its canonical UTF-8 byte SHA-256 is `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd` (11123 bytes, no BOM or trailing newline), pinned by the adjacent `.sha256` file. At startup, the contract helper:

1. parses JSON and rejects floating-point values;
2. regenerates the restricted canonical representation by ordinally sorting object keys while preserving array order;
3. requires byte-for-byte equality with the source file; and
4. compares the companion pin to both the reviewed source constant and the physical file SHA-256; and
5. verifies the B0 contract identifier, schema, source SHA, seed and generator version.

Ordered command lists use the approved JCS-compatible subset schema: fixed string/integer fields sequence, mode, center_mm, radius_mm, UTF-8, no BOM or final newline, and SHA-256 lowercase hex. All values are integers or ASCII strings. Commands are never sorted. World-unit conversion occurs once at the ledger boundary by dividing integer millimeters by 1000.

For ledger parity samples, the manifest pins a deterministic implementation oracle: every command center plus the six cardinal offsets of exactly the approved 580-mm replay radius; N=0 uses the frozen empty_parity_center_mm plus those same offsets. This is a sampling recipe, not a new geometry tolerance or product acceptance threshold. The raw record contains each probe coordinate, its ordered probe-list hash, per-probe elapsed microseconds, and exact complete-ledger versus chunk-filtered SDF equality outcome.

## Frozen executable registry

The manifest includes:

- 16 canonical replay instances: interior N=0/1/32/128/255/256; positive-X edge N=32/128/256; positive-XZ and negative-XZ corners N=32/256 each; distributed N=32/128/256.
- 10 streaming instances: cold origin, four signed face routes, R4a atomic positive diagonal, three settled three-leg corner loops, and reverse positive-X route.
- 10 detached LOD0/LOD1 instances: six signed faces, the two accepted edge masks, and the two accepted corner masks. They use origin (-4,-2,-6), the frozen nonlinear density function, independent adjacent reference builders, physical AABB checks, interface contour comparison, and the existing shared-normal tolerance.
- Three synthetic tunnel instances at widths 500/1000/2000 mm and one separate canonical SDF v1 control at width/radius 1840/920 mm. The control calls production `SdfWorld.sample_density` on mapped world points; synthetic cases use the complete R4 equation. Neither family has an owner-approved feature-retention threshold.
- Three frozen canonical carve/fill seam replay instances and one edited unload/reload instance at region (2,-1).

R4a's B0S.CORNER.DIRECT_ATOMIC_POS_POS.v1 is one synchronous _move_focus call from focus key (0,0) to (1,1). The harness checks the observed focus sequence and then compares exact requested, retained, pending, published and final active key sets; it does not count requested/loading regions as residents. It checks settled loop counts 9→12→15→16 only after actual publication.

Synthetic tunnel cases use the exact B0 surface and fixed-X YZ tunnel equations; the 1840-mm control samples canonical SDF v1 directly. Both use seed 424242, the inclusive 125-mm grid (257×81×193), negative density as empty, and six-neighbor connectivity. Global empty components are labeled for diagnostics, including top/bottom exterior components; all negative space is not required to be one component. For each synthetic tunnel only, the oracle additionally builds an empty-sample mask constrained to the seeded centerline's YZ radius at each X slice, floods that corridor with six-neighbor connectivity, and requires every nearest centerline lattice sample—including both X boundary openings—to be in the same corridor component. This prevents an exterior-air route outside the tunnel corridor from satisfying cave continuity. The canonical SDF v1 control does not claim this synthetic centerline corridor oracle. The reported nearest-centerline lattice clearance is descriptive only.

## Explicit exclusion list

The manifest carries these identifiers as excluded_not_frozen, and none appears in the executable registry:

- B0B.VIEWPORT.HISTORY.N001/N032/N128/N255/N256.v1;
- B0B.VIEWPORT.REMOTE.N032/N256.v1;
- B0S.WARM.REVISIT.EDITED.v1; and
- B0E.EDITED_LOD_GEOMETRIC_SCORING.v1.

No real picker event, viewport history, remote-picker preflight, edited revisit, or edited LOD contour result is implemented or inferred. Fixed canonical seam edits are ledger replay only; their edited LOD geometry score remains explicitly excluded until the independent non-empty-contour preflight is authorized and frozen.

## Record schema and measurement semantics

Every record includes schema version, run_id, process ID, scenario ID, process-local Time.get_ticks_usec() origin and timestamp, event ID and parent event ID, engine version, and previous JSON encode/print overhead. scenario_started distinguishes the owner-approved B0 contract SHA from exact executing source identity, which must be captured externally.

Records include:

- one ledger_command_accepted event per accepted command with sequence, revision, mode, integer-mm center/radius, support/dependency/rebuild keys, admission duration and incremental command-list hash; edited-reload operations additionally have a separate mesh-transaction-completed event, so an accepted edit remains recorded even if publication later times out;
- ledger_replay_result with count/revision/hash, per-command acceptance p50/p95/p99/max, full sample count, SDF parity probes and per-probe latency distribution;
- lod_fixture_result with transition/reference CPU timings, counts and per-face independent adjacency/contour/normal evidence; CPU triangle-array fixture time is not ArrayMesh or GPU publication time;
- streaming initial, crossing, readiness, settled and final records with actual active, requested and pending key sets; successful publication/unload, retry and supersession counts are reported as per-invocation deltas against a captured start, while sanitized scalar diagnostics and unresolved error region IDs remain separate. Human-readable stream error messages are never copied to the raw log;
- tunnel_connectivity_result with sample count, global connected-component IDs/sizes, the synthetic-only corridor-constrained centerline component and visited count, X openings, separate exterior components, explicit `PRODUCTION_SDF_V1` versus `B0_R4_SYNTHETIC_FIELD` source identity, and sampling/labeling durations;
- edited_reload_result with command hash, actual unload/reload observation, revision and before/after canonical SDF probes. This result is emitted only after the harness observes a successful sequence-matched edit-transaction commit, a cleared transaction, matching active world-state revision, all expected resident chunk meshes, and a successful region-load publication with the same revision after reload. The production lifecycle pins each stage to edit_revision, rejects completed jobs after revision drift, validates the complete staged mesh set before coherent commit, and publishes a load stage only after its requested chunks complete. Ledger/SDF equality alone is insufficient evidence of mesh publication; and
- scenario_failure or right-censored timeout_censored records. A timeout is never a completed latency sample.

Times are integer microseconds from one process-local monotonic clock; no cross-process subtraction occurs. The runner records command admission, snapshot/query parity, LOD geometry/reference builds, movement-call time, readiness wait, and engine process-frame intervals as separate quantities. p50/p95/p99/max use nearest rank ceil(p*n) within the invocation, with n and raw samples retained. Multiple runs/scenarios/machines must not be pooled into one p99. The current one-process harness does not establish population tails; report insufficient sample count and failures.

GPU completion, presented-frame correlation, process RSS and VRAM are explicitly NOT_AVAILABLE. Performance.MEMORY_STATIC is included only as an engine process-static estimate, not as RSS or an acceptance result. Headless engine frame intervals are not presented frames. No numeric performance or geometry threshold is invented.

The 120-second readiness/transaction and 30-minute process guards are protective censoring limits from the approved R4 methodology, not product targets. Tunnel sampling yields between fixed slices to check the process guard. Synchronous bounded single-cell fixture work is recorded as one operation; a hard process timeout still belongs to the future external runner.

## Verification and evidence boundary

The separate game/tests/p1_1b_benchmark_contract_tests.gd covers manifest pin/canonical bytes, unique scenario IDs, freeze exclusions, exact replay recipe expansion and ordering, signed support keys, atomic/settled streaming arithmetic, LOD case masks, tunnel dimensions/width mapping, and seam/reload inputs. Invoke it only after separate Godot runtime authorization:

    godot --headless --path ./game --script res://tests/p1_1b_benchmark_contract_tests.gd

This task did not execute Godot, scripts/validate.ps1, the contract suite, or any benchmark scenario. The contract suite and all pre-existing runtime suites therefore remain NOT_RUN for this HEAD. The repository's usual scripts/validate.ps1 launches Godot and historical benchmark/performance tests; it is intentionally not changed or invoked. The only expected hosted workflow for this change is the existing Starter static project-structure check, which does not run Godot.

Harness scenario PASS means only that this individual synthetic or source fixture produced internally consistent recorded checks in a future authorized run. It is not product performance acceptance, visual acceptance, native backend comparison, protected-host attestation, or release approval. Target hardware, FPS/frame-time budgets, RAM/VRAM limits, geometry tolerances, cave-feature preservation, profiler permissions and artifact retention remain owner decisions.

All F2-G1 holds remain: CURRENT_PROTECTED_STATE_UNKNOWN, V3_NOT_ATTESTED, ACL_REVIEW_REQUIRED, G1_BLOCKED_ENVIRONMENT, F2_G1_RELEASE_HOLD.

\n
