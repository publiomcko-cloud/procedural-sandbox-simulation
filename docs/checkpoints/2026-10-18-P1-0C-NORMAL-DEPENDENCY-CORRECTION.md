# P1.0C normal-sampling dependency correction — Issue #91

**State:** the LT-4 correction is implemented and locally validated. PR #92 remains draft/open; independent source rereview and owner GUI retest are pending. This checkpoint does not authorize merge, release, persistence, networking, protected-host access, or any F2-G1 operation.

## Identity

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Workspace: `C:\Dev\sandbox-sim-dev`; existing functional-development worktree only
- Branch: `feat/p1-0c-global-cross-region-brushes`
- Source commit: `ad9997b2deaf285d01e360bb7f7adb9d0f03ba41`
- Direct parent: reviewed candidate `608b7d6d621d0b340454f84c00a9ad7bb0379317`
- Draft PR: [#92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92)
- Scope: Issue #91 correction requested from independent review [5562602003](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92#pullrequestreview-5562602003)

## Correction

Each accepted global SDF command now explicitly separates:

- `support_regions`: regions whose spatial bounds intersect the actual brush sphere; this remains the index/reset ownership basis.
- `dependency_regions`: regions outside the sphere support that may sample changed SDF values while calculating shared-seam normals.
- `rebuild_regions`: the union staged for coherent publication.

Region fanout uses the chunk grid's `SAMPLE_STEP` as a conservative normal dependency halo. The chunk selector also includes its sample halo and schedules affected boundary chunks in each resident rebuild region. Existing transaction staging still validates the complete target set and ledger revision before publishing. Unloaded dependencies are not retained; loading them later rebuilds from the canonical ordered ledger. `X` removes commands only when the focused region is in `support_regions`, then rebuilds their dependent regions. Sequence assignment, ledger capacity, reset monotonicity, streaming, SDF v1, controls and transient-only scope remain unchanged.

## Changed source and test paths

- `game/scripts/terrain/sdf_brush_edit_state.gd`
- `game/scripts/terrain/terrain_demo.gd`
- `game/tests/terrain_brush_tests.gd`
- `game/tests/terrain_multiregion_tests.gd`

New deterministic tests use generated terrain surface heights and near-boundary brushes that stay within their geometric support regions. Positive/negative X and corner ledger cases distinguish support from dependencies. Shared-seam normal maps match when both sides rebuild and differ in the deliberate stale-neighbor comparison. The streaming integration unloads and reloads a dependency-only region, checks the edited dependent chunk against a freshly generated reference and checks all X-seam chunk normals. Focused-reset coverage confirms a dependency-only region does not delete the command.

## Validation

Command: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate.ps1`

Godot: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, version `4.7.2.stable.official.ed1daf0bf`.

| Suite | Assertions | Result |
| --- | ---: | --- |
| Smoke | 52 | PASS |
| SDF generator and mesh | 44 | PASS |
| Brush and viewport | 156 | PASS |
| Chunk partition and local rebuild | 179 | PASS |
| Multi-region streaming, editing, failure injection | 7,634 | PASS |
| Bootstrap structure | 18 | PASS |
| **Total** | **8,083** | **0 failures** |

Godot import and main-scene startup passed. The local run reported a two-region, four-chunk, 40-slice global brush stage at about 3,315 ms elapsed. Final streaming diagnostics measured peak mesh-slice/process work around 30.3/67.5 ms. The seven-run full-mesh medians were about 411–430 ms; localized interior/border/corner medians were about 35.3/73.9/152.7 ms. These single-host measurements are variable and are not frame-time or cross-machine guarantees. No F2 ACL suite was run.

## Remaining gates and visual retest

1. Independent source rereview the exact PR #92 HEAD and this change.
2. In Godot 4.7.2, orbit to a region seam and apply a brush crossing the seam and one just inside it; the HUD should distinguish support from dependent rebuild counts. Inspect for matching surface normals/no cracks.
3. Stream the dependent region out and back in; verify the sculpt and seam continuity return.
4. Verify negative coordinates, a near-corner brush, `C`, `R`, and `X`; specifically confirm X is based on the focused support region and preserves global sequence monotonicity.
5. Record owner GUI acceptance separately. The source/test result does not establish visual acceptance.

F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
