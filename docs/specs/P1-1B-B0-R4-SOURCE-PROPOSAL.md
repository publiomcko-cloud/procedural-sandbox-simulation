> **Repository registration (2026-10-21).** This is the unmodified content of the owner-provided R4 proposal, preserved as source evidence. Its direct diagonal streaming scenario, edited revisit status, and tunnel connectivity oracle are **superseded by** [R4a](P1-1B-B0-R4A-ACCEPTED-ADDENDUM.md). The binding scope/approval restrictions are in [owner's B0 decision](P1-1B-B0-OWNER-APPROVED-CONTRACT.md). This file alone is not executable approval.

---

# P1.1B-B0 R4 — Final Contract Consistency Correction

**Terminal status:** `P1_1B_B0_R4_READY_FOR_FINAL_INDEPENDENT_REVIEW`

This is a planning-only contract. I made no repository changes and ran no Godot, benchmark, or native Voxel Tools code. The five F2-G1 holds remain unchanged.

## Identity and review evidence

GitHub identifies `665c5c883ae88b949f4030f7affc786064999f61` as the PR #97 merge commit. I reviewed the independent [R3 review #6313944424](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/97#issuecomment-6313944424) and the source at that exact revision, including the streaming lifecycle, edit ledger, SDF, region mapping, and LOD fixture.

The local checkout is on branch `feat/p1-1a-lod01-transition-fixture` at `cfdc0d3f48636c3567ac38a45de2a2935345d833`, so it was not used as evidence for the reviewed main source.

This report corrects R3’s active-versus-requested accounting, fully defines the synthetic tunnel field, enumerates individual geometry cases, freezes exact edit recipes, and marks viewport histories that still need a frozen outcome baseline as `NOT_FROZEN`.

## 1. Fixed contracts and identity encoding

Use the approved P1.1 R2 architecture and the source at the reviewed SHA:

- SDF generator version `1`, demo seed `424242`.
- World-space region sizes: X `16`, Z `12`; ownership uses mathematical floor for signed coordinates.
- Canonical global ledger: ordered `CARVE`/`FILL`, up to 256 accepted commands. Radius bounds are `[0.45, 2.0]`.
- Current viewport brush radius is `1.25`; this differs from the proposed canonical replay radius `0.58`.
- LOD fixture cell spacing is `0.5` for LOD0 and `1.0` for LOD1. LOD1 origins must be globally aligned.
- Region request radius is 1 (3×3); retention radius is 2 (5×5); active residency maximum is 25 regions / 400 chunks.
- CPU worker limit is 4; ArrayMesh construction/upload limit is 2 per frame.
- Current project renderer is GL Compatibility.

These are architecture/source constraints. They do not constitute owner-approved performance thresholds.

### Command and manifest hashes

Coordinates and radii in manifests use integer millimeters. The future harness converts them to world units once at the boundary by dividing by 1000. It must not use decimal floating-point formatting as command identity.

For command identity, serialize the ordered command array as UTF-8 JSON using RFC 8785/JCS canonicalization, without a BOM or trailing newline. The schema contains only integer values, strings, arrays, and fixed keys:

`sequence`, `mode`, `center_mm`, `radius_mm`.

SHA-256 that byte sequence and record lowercase hexadecimal. The manifest records the command digest, scenario ID/version, source SHA, generator/seed, setup, and expected checks. Hash the canonical manifest bytes with its own `manifest_sha256` field omitted; store the resulting digest outside the manifest. Never sort commands.

No SHA-256 is claimed here: final manifest bytes do not yet exist.

## 2. Streaming residence and readiness contract

The source distinguishes `active_regions` from `loading_regions`. A region enters `active_regions` only when `_publish_region` publishes its meshes. Requested `D(k)` is therefore not evidence of active residency.

For focus region key `k` define:

- `D(k)`: requested 3×3 key set.
- `R2(k)`: 5×5 retention key set.
- `A_prev`: keys actually present in `active_regions` before reconciliation.
- `A_ret = A_prev ∩ R2(k)`: previously published regions retained for the new focus.
- `L_pending`: current region stages in `loading_regions`; these are not active.
- `P_success(t)`: requested stages that completed and were published by time `t`.
- `A_observed(t) = A_ret ∪ P_success(t)`: actual active set at time `t`.
- `A_settled = A_ret ∪ D(k)`: a valid final expected set **only if** every requested key is published for the intended seed/generator/revision, no relevant stage remains pending, and no relevant failed stage remains unresolved.

Failures, cancellations, retries, and successful publications are separate event counts. A canceled job or failed load is not a published region. A retry is not a second resident region. Record the final `active_regions` keys, not merely the requested keys. Enforce the 25-region cap against actual active residency.

**Cold-start counterexample:** at process start, `A_prev = ∅`; reconciliation requests 9 keys, which may put up to 9 keys in `L_pending`. Before any publication, `A_observed = ∅`, not 9. After `m` successful publications and no other event, `|A_observed| = m`. Only after all nine are published can the settled count be 9.

**Source lifecycle:** `_reconcile_region_window` removes active keys outside retention and cancels obsolete loading stages; `_begin_region_stage` puts new work in `loading_regions`; completion publishes through `_publish_region`; `_unload_region` removes an active publication; revision supersession and stage failures may cancel/requeue work; failed loads may retry and then remain absent with an error. The benchmark must record all these transitions.

### Frozen route definitions and settled-set arithmetic

All focus positions below are exact world millimeters; `y=3200`. The route moves between waypoints at the listed velocity. Camera orbit offset is `(12000,8000,15000)` mm; actual camera position is `focus + offset` and looks at the focus. At route boundaries, wait for the event-based readiness predicate before continuing where stated. Any fixed observation dwell is separately recorded and cannot stand in for readiness.

| Scenario ID                    | Ordered focus waypoints                                                                                                                                            | Expected settled counts                                                                                       |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `B0S.COLD.ORIGIN.v1`           | Start `(8000,3200,6000)`; no movement. Fresh engine process, with OS/GPU cache state recorded as unknown unless separately controlled.                             | First request: 9; initial actual active count may be 0 and rises only on publication.                         |
| `B0S.FACE.POS_X.v1`            | `(8000,3200,6000)` → `(24000,3200,6000)` at `+8000 mm/s` X.                                                                                                        | After origin settles: 9 → 12.                                                                                 |
| `B0S.FACE.NEG_X.v1`            | `(8000,3200,6000)` → `(-8000,3200,6000)` at `-8000 mm/s` X.                                                                                                        | 9 → 12.                                                                                                       |
| `B0S.FACE.POS_Z.v1`            | `(8000,3200,6000)` → `(8000,3200,18000)` at `+8000 mm/s` Z.                                                                                                        | 9 → 12.                                                                                                       |
| `B0S.FACE.NEG_Z.v1`            | `(8000,3200,6000)` → `(8000,3200,-6000)` at `-8000 mm/s` Z.                                                                                                        | 9 → 12.                                                                                                       |
| `B0S.CORNER.DIRECT_POS_POS.v1` | `(8000,3200,6000)` → `(24000,3200,18000)` at `(+8000,+8000) mm/s`, no intermediate focus-key dwell.                                                                | 9 → 14 after settling.                                                                                        |
| `B0S.CORNER.LOOP_POS.v1`       | `(8000,3200,6000)` → `(24000,3200,6000)` → `(24000,3200,18000)` → `(8000,3200,18000)`; each leg 8000 mm/s on its axis; settle after each leg.                      | 9 → 12 → 15 → 16.                                                                                             |
| `B0S.CORNER.LOOP_NEG.v1`       | `(8000,3200,6000)` → `(-8000,3200,6000)` → `(-8000,3200,-6000)` → `(8000,3200,-6000)`; settle after each leg.                                                      | 9 → 12 → 15 → 16.                                                                                             |
| `B0S.CORNER.LOOP_MIXED.v1`     | `(8000,3200,6000)` → `(24000,3200,6000)` → `(24000,3200,-6000)` → `(8000,3200,-6000)`; settle after each leg.                                                      | 9 → 12 → 15 → 16.                                                                                             |
| `B0S.REVERSE.POS_X.v1`         | `(8000,3200,6000)` → `(24000,3200,6000)` → `(8000,3200,6000)`, 8000 mm/s each way.                                                                                 | Record actual set at every focus crossing and final readiness; do not assume intermediate requests completed. |
| `B0S.WARM.REVISIT.EDITED.v1`   | Settle at origin; apply the frozen viewport edit described below; travel to `(72000,3200,6000)` at `+8000 mm/s`, settle, return to origin at `-8000 mm/s`, settle. | Record each key crossing, actual publications/cancellations, unload, reload, and final edit revision.         |

For any movement, calculate expectations using actual state:

`A_ret = A_prev ∩ R2(k_new)`

`A_observed(t) = A_ret ∪ P_success(t)`

`A_settled = A_ret ∪ D(k_new)` only under the settled conditions above.

A direct one-step diagonal has 14 regions from a settled 3×3 initial set. The route that reaches 16 is explicitly the three-leg loop, whose settled counts are 9, 12, 15, and 16. This resolves the earlier ambiguity without counting `D(k)` as already active.

### Readiness events

For every route, record separately:

1. Motion start and end.
2. Fixed dwell interval, if any.
3. First desired region actually published and usable.
4. Full requested-window readiness (`D(k) ⊆ A_observed`, with matching revision).
5. Final settled active set.
6. Failed, canceled, retried, timed-out, and successful publication counts.

The proposed 120-second readiness guard is a protective timeout, not a performance target.

## 3. Canonical replay scenarios

For all cases below, seed `424242`, generator v1, sequence starts at 0, modes alternate `CARVE`, `FILL`, starting with `CARVE`; radius is exactly `580 mm`. `N=0` means no commands and revision 0. For `N>0`, expected command count and revision are `N`. Expected SDF results are checked by comparing complete-ledger sampling with the optimized meshing-query path at the pinned deterministic sample set; no uncomputed golden values are asserted here.

| Scenario ID                                                    | Exact command centers in mm                                                                                                                                                                                      | Expected support/rebuild contract                                                                       |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `B0A.INTERIOR.N000.v1`, `N001`, `N032`, `N128`, `N255`, `N256` | For command `i`: `(8000+(i mod 4)*100, 3200, 6000+(floor(i/4) mod 4)*100)`.                                                                                                                                      | All commands’ support and rebuild regions are `(0,0)`.                                                  |
| `B0A.EDGE.POS_X.N032.v1`, `N128`, `N256`                       | `(15700+(i mod 3)*20, 3200, 6000+(floor(i/3) mod 3)*20)`.                                                                                                                                                        | Support and rebuild keys are `(0,0)` and `(1,0)` for each command.                                      |
| `B0A.CORNER.POS_XZ.N032.v1`, `N256`                            | `(15800+(i mod 2)*10, 3200, 11800+(floor(i/2) mod 2)*10)`.                                                                                                                                                       | Per command: `(0,0),(1,0),(0,1),(1,1)`.                                                                 |
| `B0A.CORNER.NEG_XZ.N032.v1`, `N256`                            | `(-200+(i mod 2)*10, 3200, -200+(floor(i/2) mod 2)*10)`.                                                                                                                                                         | Per command: `(-1,-1),(-1,0),(0,-1),(0,0)`.                                                             |
| `B0A.DISTRIBUTED.N032.v1`, `N128`, `N256`                      | Cycle region keys `(-2,-2),(-1,-2),(0,-2),(1,-2),(1,-1),(0,-1),(-1,-1),(-2,-1),(-2,0),(-1,0),(0,0),(1,0),(1,1),(0,1),(-1,1),(-2,1)`. For command `i`, use the selected region origin plus `(8000,3200,6000)` mm. | Each command supports exactly its listed region; the union must equal the selected command region keys. |

The output record also includes each command’s sequence, revision, support, dependency and rebuild keys, acceptance result, and command-list hash.

## 4. Real viewport events and remote histories

### Frozen clean-scene click recipe

Use seed `424242`, generator v1; viewport `1280×720`; focus `(8000,3200,6000)` mm; orbit offset `(12000,8000,15000)` mm; camera position `(20000,11200,21000)` mm; look-at point is focus; click position `(640,360)`. Generate the ray using the production `project_ray_origin`/`project_ray_normal` path. Do not change the recipe after observing results.

The preflight checks that the focus region is published, no coherent transaction is pending, the independent ray oracle and production picker both hit the same first surface under the frozen input, and the scene is otherwise ready. A failed preflight makes the scenario fail; do not move the camera or click elsewhere to make it pass.

Every accepted operation records actual hit position, mode, production radius `1.25`, sequence, revision, support regions, and the resulting observed-command hash. This is not equivalent to the 0.58-radius canonical replay.

### Repeated real-click histories

These IDs and recipes are defined, but their exact observed command-list hashes are not yet established. They are therefore **`NOT_FROZEN` and excluded from the executable benchmark contract** until an authorized preflight produces and freezes the expected results:

- `B0B.VIEWPORT.HISTORY.N001.v1`
- `B0B.VIEWPORT.HISTORY.N032.v1`
- `B0B.VIEWPORT.HISTORY.N128.v1`
- `B0B.VIEWPORT.HISTORY.N255.v1`
- `B0B.VIEWPORT.HISTORY.N256.v1`

Preparation recipe: start from the clean-scene pose above. Send left-click events at `(640,360)`, alternate Shift state beginning with carve, and after each click wait for that exact accepted revision’s coherent publication before sending the next. After each event, assert an actual picker hit, ledger acceptance, expected sequence, and published revision. Any no-hit, busy state, missing acceptance, cancellation, or timeout invalidates setup; do not substitute direct ledger injection or alter the ray recipe. The frozen expected list must include all actual hit centers and their hash.

For the N256 capacity check, first establish and publish exactly 256 accepted setup commands. Then send one extra click only after confirming a valid hit and an otherwise-ready scene. `ledger_capacity_exceeded` is the expected rejection only if the picker hit occurred and no earlier readiness/pending rejection applied. Otherwise classify the capacity test as invalid, not passed.

### Remote history for picker candidate filtering

These cases use direct setup into a disposable scene’s canonical ledger; they are picker-filtering experiments, not simulated real-click histories.

- IDs: `B0B.VIEWPORT.REMOTE.N032.v1` and `B0B.VIEWPORT.REMOTE.N256.v1`.
- Seed/version: `424242/1`. For sequence `i`, alternate carve/fill; center is region `(64,64)` origin plus `(8000,3200,6000)` mm, i.e. `(1032000,3200,774000)` mm; radius `1250 mm`.
- Expected: count and revision N; every operation support region is `(64,64)`; all commands are beyond the 120-unit picker ray range from the local frozen click recipe; expected local ray candidate count is zero.
- After setup, rebuild and wait for the actual local requested window to publish the current revision. Then run the frozen click preflight. At N<256, expect one accepted radius-1.25 command. At N=256, use the qualified capacity check above.

These cases are frozen only after the independent-hit preflight described above succeeds. Until then they remain `NOT_FROZEN`.

## 5. LOD geometry cases

The fixture domain is one world-space unit. For LOD0 lattice origin `L`, `base = 0.5 * Vector3(L)` and the cell AABB is `[base, base+(1,1,1)]`. The accepted signed origin is `L=(-4,-2,-6)`, giving `base=(-2,-1,-3)`. Fine neighbor origin offsets by `-2` LOD0 indices along the selected negative face or `+2` along the selected positive face; this makes the reference cell touch the requested external plane. LOD1 origins use the same globally aligned unit-domain origin.

For each single-face case, build the transition with the listed face mask, an independently constructed LOD0 reference adjacent to that fine face, and an independently constructed LOD1 reference adjacent to its opposite coarse face:

| Scenario ID               | Face mask        |
| ------------------------- | ---------------- |
| `B0G.LOD01.FACE.X_NEG.v1` | `[FACE_X_NEG=0]` |
| `B0G.LOD01.FACE.X_POS.v1` | `[FACE_X_POS=1]` |
| `B0G.LOD01.FACE.Y_NEG.v1` | `[FACE_Y_NEG=2]` |
| `B0G.LOD01.FACE.Y_POS.v1` | `[FACE_Y_POS=3]` |
| `B0G.LOD01.FACE.Z_NEG.v1` | `[FACE_Z_NEG=4]` |
| `B0G.LOD01.FACE.Z_POS.v1` | `[FACE_Z_POS=5]` |

For every case, expected checks are: valid transition; non-empty, non-degenerate reference contours; exact AABB contact and disjoint interiors; equal interface contour segments; no T-junction; consistent endpoint normals. Require shared-position normals to match under the existing fixture tolerance `1e-6`.

Edge and corner masks are individually enumerated:

| Scenario ID                             | Exact mask |
| --------------------------------------- | ---------- |
| `B0G.LOD01.EDGE.X_NEG_Y_NEG.v1`         | `[0,2]`    |
| `B0G.LOD01.EDGE.X_POS_Y_NEG.v1`         | `[1,2]`    |
| `B0G.LOD01.CORNER.X_NEG_Y_POS_Z_NEG.v1` | `[0,3,4]`  |
| `B0G.LOD01.CORNER.ALL_POS.v1`           | `[1,3,5]`  |

The density override for these transition-topology cases is exactly:

`f(p) = 0.38*dx + 0.31*dy + 0.27*dz + 0.18*dx*dy - 0.45`

where `d = p - base`, in world units. It is intentionally nonlinear and is **not** claimed to equal canonical SDF v1. Existing fixture tests use this signed domain and require `f(base)<0` and `f(base+(1,1,1))>0`.

### Fully specified tunnel field

Tunnel geometry is world-space, with `x,y,z` in world units over the bounded test domain `x∈[-16,16]`, `y∈[-2,8]`, `z∈[-12,12]`; cave-section cut is off. Positive density denotes solid; negative density denotes empty.

For seed `s`, set `phase = posmod(s,100003)*0.000173`. Define:

`surface_y(x,z) = 3.8 + 1.25 sin(0.22x+phase) + 0.70 cos(0.31z-0.7phase) + 0.28 sin(0.11(x+z)+0.3phase)`

`surface_density(x,y,z) = min(surface_y(x,z)-y, y-(-1))`

`center_y(x) = 1.15 + 0.24 sin(0.25x+phase)`

`center_z(x) = 6.0 + 1.05 sin(0.17x+0.6phase)`

At each fixed `x`, tunnel distance is the Euclidean 2D cross-section distance in the YZ plane, not the shortest 3D curve distance:

`d_tunnel(x,y,z;r) = sqrt((y-center_y(x))² + (z-center_z(x))²) - r`

`density(x,y,z;r) = min(surface_density(x,y,z), d_tunnel(x,y,z;r))`

The negative inside-tunnel sign and `min` CSG match the production convention. The synthetic family changes only tunnel radius; it is not by itself evidence of production mesh equivalence.

| Scenario ID                             | Tunnel width | Radius                                     |
| --------------------------------------- | ------------ | ------------------------------------------ |
| `B0G.TUNNEL.SYNTH.W500.v1`              | 500 mm       | 0.25                                       |
| `B0G.TUNNEL.SYNTH.W1000.v1`             | 1000 mm      | 0.50                                       |
| `B0G.TUNNEL.CANONICAL_CONTROL.W1840.v1` | 1840 mm      | 0.92, matching the canonical source radius |
| `B0G.TUNNEL.SYNTH.W2000.v1`             | 2000 mm      | 1.00                                       |

The canonical control uses the production centerline/surface functions at seed `424242`; it is distinct from claiming the width-500/1000/2000 synthetic fields are canonical.

**Sampling/connectivity oracle:** evaluate on a deterministic 125-mm world lattice over the declared domain. Use density `<0` as empty and `>=0` as solid. Use 6-neighbor connectivity for empty voxels. Expected topology is one continuous empty tunnel component connecting the negative-X and positive-X boundaries, with no unexplained branching. Record sampled occupancy, component count, and cross-sections along the declared centerline. The 125-mm oracle is a proposed numerical method, not an accepted feature-width threshold. Whether any width must remain open/preserved is `OWNER_TO_DEFINE`.

**Status:** the formula, domain, widths, and discrete oracle are frozen as definitions. Numerical reference outputs and feature-preservation acceptance remain unscored and require future authorized execution and owner thresholds.

## 6. Canonical edit seam and unload/reload scenarios

### Frozen command lists

Each scenario begins with a new isolated ledger, seed `424242`, generator v1. Commands below use radius `580 mm`, mode and sequence as listed. Expected revision equals list length.

| Scenario ID                     | Ordered commands                                             | Expected support and readiness                                        |
| ------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------- |
| `B0E.SEAM.POS_X.CARVE_FILL.v1`  | 0: CARVE `(15800,3200,6000)`; 1: FILL `(15800,3400,6200)`.   | Both commands support/rebuild `(0,0),(1,0)`; count/revision 2.        |
| `B0E.SEAM.POS_XZ.CARVE_FILL.v1` | 0: CARVE `(15800,3200,11800)`; 1: FILL `(16200,3400,12200)`. | Both support/rebuild `(0,0),(1,0),(0,1),(1,1)`; count/revision 2.     |
| `B0E.SEAM.NEG_XZ.CARVE_FILL.v1` | 0: CARVE `(-200,3200,-200)`; 1: FILL `(200,3400,200)`.       | Both support/rebuild `(-1,-1),(-1,0),(0,-1),(0,0)`; count/revision 2. |

For each command, verify the actual support and rebuild keys against ledger output. Compare complete-ledger and meshing-query canonical densities at the frozen sample points before comparing mesh contours. If a contour is empty, the seam geometry case fails its non-empty-contour precondition; it does not pass because both sides are empty.

These edit/LOD combinations are `NOT_FROZEN` for geometric scoring until a future preflight shows non-empty contours on both references under the exact SDF-plus-ledger input and the owner freezes that result. The ledger replay scenarios themselves remain frozen and executable once authorized.

### Edited unload/reload

`B0S.EDITED.RELOAD.REGION_2_NEG1.v1`:

- Seed/version: `424242/1`.
- Initial focus `(40000,3200,-6000)` mm, region key `(2,-1)`; wait until its requested window is published.
- Disposable ledger commands: sequence 0 `CARVE`, center `(40000,3200,-6000)` mm, radius `580`; sequence 1 `FILL`, center `(40500,3200,-6000)` mm, radius `580`.
- Expected count/revision 2. Both commands’ support and rebuild region is `(2,-1)`.
- Probe world positions in mm: `(40000,3200,-6000)`, `(40500,3200,-6000)`, `(39400,3200,-6000)`, `(40600,3200,-6000)`, `(40000,2600,-6000)`, `(40000,3800,-6000)`, `(40000,3200,-5400)`, `(40000,3200,-6600)`.
- After publication, move focus to `(88000,3200,-6000)` mm, region key `(5,-1)`, and wait until region `(2,-1)` is absent from `active_regions`; then return to `(40000,3200,-6000)` mm and wait for its actual publication.
- Expected: one unload and one successful reload event for the target; loaded revision 2; canonical SDF probe values after reload equal the values before unload; no pending/failed target stage at final readiness.

Any failed command admission, missing initial publication, absent unload, failed reload, or probe mismatch fails the scenario.

## 7. Picker histories: explicit frozen and not-frozen boundary

### Remote histories

These preseed a disposable canonical ledger directly, then measure the viewport picker. They are not a history of mouse-generated edits.

- IDs `B0B.VIEWPORT.REMOTE.N032.v1`, `B0B.VIEWPORT.REMOTE.N256.v1`.
- For `i=0..N-1`, alternate carve/fill and use center `(1032000,3200,774000)` mm, radius `1250 mm`, seed/version `424242/1`.
- Expected command count/revision N; every support/rebuild region is `(64,64)`. The local frozen ray is at least 120 world units from the remote center, so expected local operation-candidate count is zero.
- After preseed, build the current local requested window and wait for matching publication before running the fixed viewport recipe.
- N=32 expects a hit and one accepted command; N=256 is the conditional capacity test defined below.

These cases are `NOT_FROZEN` until authorized preflight verifies the local ray hit and the independently computed expected first hit under the frozen camera recipe.

### Real viewport histories

`B0B.VIEWPORT.HISTORY.N001/N032/N128/N255/N256.v1` use the exact clean-scene camera and input recipe from Section 4. Send one left click at `(640,360)` per desired operation; alternate Shift state starting with carve. After each event:

1. Verify the picker reports a hit.
2. Verify the ledger accepted the intended command and incremented sequence/revision exactly once.
3. Record actual center, mode, radius `1.25`, support/rebuild keys, and command hash.
4. Wait until that revision is coherently published before sending the next input.

Any miss, busy rejection, timeout, cancellation, unexpected acceptance, or publication mismatch invalidates setup. Do not change camera, input position, timing recipe, or substitute direct seeding after seeing a failure.

All five repeated-history cases are **`NOT_FROZEN` and excluded from executable benchmarks** until a separately authorized preflight completes all requested events, freezes the observed command list/hash and confirms that the same fixed recipe meets its hit/acceptance contract. A no-hit or busy event is a failed preflight, not permission to retune the pose.

For the N256 capacity event, first complete and publish exactly 256 valid operations. Then issue one further click. Interpret `ledger_capacity_exceeded` as the expected result only if the ray independently hits and the focus scene is otherwise ready with no transaction pending. Otherwise the capacity scenario is invalid.

## 8. Clock, measurement, statistics, and timeout rules

Retain the R3 definitions:

- Use one process-local monotonic `Time.get_ticks_usec()` clock. Record process-local origin `T0`; store integer microseconds. Never subtract across processes.
- Correlate `run_id`, process ID, scenario ID, sample/event IDs, parent event ID, seed, generator version, revision, command hash, region and chunk.
- Input dispatch is timed around `Viewport.push_input()` return; separately time callback entry-to-exit.
- Picker is `_apply_brush_at` entry to result, with snapshot and picker-loop subintervals.
- Ledger acceptance is immediately before `add_sphere` through its return.
- Queue, worker, mesher stages, ArrayMesh construction, scene publication, GPU submission/completion, and actual presented frame each have separate start/end events.
- Scene publication is a CPU proxy. It is not evidence of GPU completion or a presented frame. GPU/present metrics are optional and valid only with demonstrated correlation; otherwise report `NOT_AVAILABLE`/`UNSCORED`, without invalidating valid CPU records.
- Preserve separate process distributions: proposed 5 launches; 2 unscored warmups; 10,000 consecutive eligible frames and 30 latency events per process where applicable. Report n, p50, p95, p99, max, completion fraction, and failures per process. Use nearest-rank `ceil(p*n)`. Summarize between-run variation from per-process statistics; never pool different scenarios, machines, renderers, or cache states into one p99.
- Preserve failures and timeouts. Incomplete work is right-censored at its observed lower-bound time; never enter timeout thresholds as completed latency samples. Proposed 120 s readiness/transaction guard and 30 min process guard are protective limits only. Slow successful events remain completed samples.

## 9. Geometry oracle and comparability

- Use a separately configured higher-resolution mesh from the exact canonical field and ordered command list as a numerical reference. Pin its build/configuration in the eventual manifest; it is not analytic ground truth.
- Sample both surfaces deterministically over triangles, edges, seams, caves, and bounds. Compute nearest point-to-triangle distances in both directions; report directed distributions and symmetric percentiles/max in world millimeters.
- With identical camera, projection, clipping, viewport, renderer, and frame capture, compare projected silhouette/contour samples bidirectionally in pixels. Headless publication is not screen evidence.
- Match surface points and report normal angle `acos(clamp(dot,-1,1))`, winding, orientation, and degenerate-triangle results.
- For seams, compare contour segments, endpoints and normals; detect cracks, unmatched/duplicate segments, T-junctions and edge crossings.
- For cave topology, use the declared 125-mm sampling/connectivity oracle and cross-sections. Numeric tolerances and required minimum cave widths are `OWNER_TO_DEFINE`.
- Report resolution-matched and quality-matched comparisons separately. Equal nominal cell spacing is not equal quality.
- Do not assume Voxel Tools accepts the custom immutable density buffers or the canonical ordered ledger. If seed, SDF, command order, unloaded-region replay, and oracle inputs cannot be made equivalent, report `NOT_COMPARABLE`. Public documentation cannot establish performance or integration compatibility.

## 10. Owner decision matrix

| Item                                                                              | Status                             | Current contract                                                  |
| --------------------------------------------------------------------------------- | ---------------------------------- | ----------------------------------------------------------------- |
| SDF v1, demo seed/version, ordered global ledger                                  | `OWNER_APPROVED`                   | Preserve canonical authority; no LOD/cache may alter it.          |
| Signed floor ownership, region/chunk layout and sample spacing                    | `EXISTING_HARD_CONSTRAINT`         | Fixed by current source and approved R2 plan.                     |
| Worker cap 4, upload/construction cap 2/frame, residency 25/400                   | `EXISTING_HARD_CONSTRAINT`         | Fixed resource ceilings, not goals.                               |
| Godot 4.7.2 build and current GL Compatibility baseline                           | `EXISTING_HARD_CONSTRAINT`         | Other platform/renderers require separate selection.              |
| Scenario IDs, command recipes, viewport pose, statistics, synthetic oracle        | `PROPOSED`                         | Freeze only after final independent review and owner decision.    |
| Target OS/hardware, minimum and reference GPU/CPU/RAM, driver, display/resolution | `OWNER_TO_DEFINE`                  | Required for product comparison.                                  |
| FPS, frame p95/p99/max and allowable stalls                                       | `OWNER_TO_DEFINE`                  | No approved thresholds exist.                                     |
| Edit/picker/scene publication/first-present latency limits                        | `OWNER_TO_DEFINE`                  | These are distinct metrics.                                       |
| RAM/VRAM ceilings and measurement tools                                           | `OWNER_TO_DEFINE`                  | Existing `MEMORY_STATIC` and payload estimates are not RSS/VRAM.  |
| World/screen geometric error, normal, seam and T-junction tolerances              | `OWNER_TO_DEFINE`                  | No numeric limits approved.                                       |
| Required cave width/connectivity and acceptable feature loss                      | `OWNER_TO_DEFINE`                  | Synthetic test widths are not requirements.                       |
| GPU/presentation/RSS/VRAM tooling and event correlation                           | `OWNER_TO_DEFINE`                  | Optional until separately approved and validated.                 |
| Raw artifact location, contents, retention, redaction                             | `OWNER_TO_DEFINE`                  | Do not store private machine identity unnecessarily.              |
| Exploratory baseline                                                              | `UNSCORED`, optional future choice | Requires separate authorization for implementation and execution. |
| Voxel Tools acquisition/execution, backend adoption, ADR-0002                     | `OWNER_TO_DEFINE`                  | Not authorized by B0.                                             |

## 11. Proposed B1-1 implementation ticket

**Ticket:** `P1.1B-B1-1 — Opt-in test-only custom benchmark harness`.

**Scope:** Add a standalone, opt-in `SceneTree` test harness for the frozen custom-only B0 cases. Do not alter the playable scene’s production behavior, SDF, ledger, streamer, mesher, resource caps, or project dependencies. Do not implement native backend support.

**Proposed files:**

- `game/tests/p1_1b_benchmark_harness.gd`: scenario runner and event records.
- `game/tests/fixtures/p1_1b_b0_manifest.json`: canonical inputs and generated digest.
- `game/tests/p1_1b_benchmark_contract_tests.gd`: command hashes, coordinate conversion, ordering, lifecycle/readiness, and censoring semantics.
- `docs/specs/P1-1B-B0-BENCHMARK-CONTRACT.md`: frozen schema, results, limits, and unavailable metrics.

**Available source telemetry:** seed/version/revision; operation list and fan-out; picker snapshot, loop, candidates and sample counts; queue enqueue/submission and worker timestamps; mesher CPU-stage times; ArrayMesh creation; scene publication; active/requested/loading region keys; frame diagnostics; `MEMORY_STATIC` and packed payload estimates.

**Unavailable from the current harness:** process RSS, VRAM, GPU completion fences, and actual presentation correlated with a specific revision. Keep those fields unavailable unless separately authorized instrumentation proves correlation.

**Validation and gates:** deterministic canonical hashes; exact repeated ledger revisions and support keys; real viewport preflight; fail-closed handling of incomplete click histories; assertion that requested regions are not counted active before publication; explicit canceled/retry/failure records; unchanged caps; test-only opt-in; full `scripts/validate.ps1`; independent exact-SHA review. Harness implementation and benchmark execution require separate owner authorizations. No merge, scoring, backend selection, or P1.1C authorization follows automatically.

**Rollback:** revert only the test-only harness and its manifest/spec if correctness, overhead, or scope checks fail. Production files remain unchanged.

## 12. Source-to-contract consistency table

| Source evidence at `665c5c…`                                                                                                                             | R4 contract consequence                                                                                             |
| -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `terrain_demo.gd:_reconcile_region_window` builds desired keys, removes active keys outside retention, and starts stages for keys not active or loading. | `D(k)` is a request set; it is never counted active merely because requested.                                       |
| `terrain_demo.gd:_begin_region_stage` inserts a region into `loading_regions`; `world_states` indexes both active and loading states.                    | Do not use `world_states` size as published residency. Track `active_regions` and `loading_regions` separately.     |
| `_complete_region_stage` calls `_publish_region`; `_publish_region` inserts the region into `active_regions`.                                            | Count successful publications only at the publication event.                                                        |
| `_unload_region` removes the active entry; `_supersede_region_stage` cancels stale work and may requeue; load failure has bounded retry behavior.        | Record unload, cancellation, retry, failure and success separately. Settled state requires resolved requested work. |
| `REQUEST_RADIUS=1`, `UNLOAD_RADIUS=2`, max active 25; key generation is square.                                                                          | 3×3 requests, 5×5 retention and maximum actual residency 25 are preserved.                                          |
| `BRUSH_RADIUS=1.25`; `_accept_brush_at_world` passes that radius to the ledger.                                                                          | Viewport tests use actual 1.25 radius; 0.58 applies only to isolated canonical replay.                              |
| Ledger bounds are 256 operations and radii `[0.45,2.0]`; fan-out and revision update are atomic.                                                         | Replay recipes are legal and expected count/revision is explicit; verify support from returned ledger data.         |
| SDF surface/cave formula and `MIN_Y=-1`; cave distance is a YZ cross-section at fixed X.                                                                 | Tunnel formula above matches production conventions; width variants remain synthetic.                               |
| Transition fixture face IDs 0–5, valid global alignment, and reference origin changes by ±2 LOD0 indices.                                                | Six signed face scenarios and explicit reference transforms are frozen.                                             |
| Existing seam tests use masks `[0,2]`, `[1,2]`, `[0,3,4]`, `[1,3,5]` and the stated nonlinear field.                                                     | Edge/corner cases use concrete tested inputs and expected independent contour checks.                               |
| Source timestamps worker start/end, mesh stages, publication, and input-picker durations.                                                                | CPU event intervals are measurable; scene publication is not GPU completion/present.                                |
| `MEMORY_STATIC` and payload estimates exist; no correlated present or VRAM mechanism exists in the reviewed harness.                                     | RSS/VRAM/GPU/present are unavailable absent separately approved tools.                                              |

## 13. Readiness and remaining blockers

| Classification                                           | Disposition                                                                                                                                                                                                                                                         |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Verified existing contracts                              | Source-backed and fixed as listed above.                                                                                                                                                                                                                            |
| Proposed and fully specified                             | Canonical replay cases, streaming routes and readiness accounting, LOD face/edge/corner cases, tunnel equations, seam command lists, and unload/reload probes.                                                                                                      |
| `NOT_FROZEN`, excluded from executable benchmark         | Repeated real-click histories and remote-history click cases until a separately authorized preflight establishes valid hits and freezes observed outcomes. Edited LOD seam scoring also remains excluded until non-empty canonical edited contours are established. |
| Ready for future test-only implementation after approval | Frozen ledger replay, streaming state/event accounting, synthetic LOD topology, and tunnel formula/oracle.                                                                                                                                                          |
| Not measured by existing harness                         | RSS, VRAM, GPU completion, and actual presented-frame latency.                                                                                                                                                                                                      |
| Owner decisions outstanding                              | B0 freeze, target rig, product budgets, feature-retention policy, tools/artifacts, and B1-1 implementation authorization.                                                                                                                                           |

## Owner decisions requested

1. Approve or revise the frozen scenario registry and input/hash scheme.
2. Select target hardware, renderer, viewport/display configuration, and cache-control method.
3. Set performance and geometry budgets, including required cave features, or separately authorize an `UNSCORED` baseline.
4. Approve external measurement tools and raw-artifact handling.
5. Separately authorize the B1-1 test-only harness; runtime benchmark execution remains a later independent gate.

**Terminal status:** `P1_1B_B0_R4_READY_FOR_FINAL_INDEPENDENT_REVIEW`.