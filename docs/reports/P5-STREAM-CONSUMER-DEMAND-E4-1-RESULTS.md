# P5 E4.1 — final verdict: PERFORMANCE_REJECTED

- **Pure policy qualification PASSED**: nine source-rank templates reproduce every source rank of original E4; Godot 4.7.2 scene and preview contracts passed on self-hosted Windows.
- **Benchmark source**: `b5353efc159b5e2414ab77a44693d291a40fd409`, A/B/B/A on one GPU-interactive Windows runner in Godot **headless** mode, same seed 424242 and 720 fixed movement frames per trial.
- **Evidence**: [Actions run #43195799967](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43195799967), artifact `13933431531` (16 stdout, stderr, per-trial metrics, `consumer-demand-abba-verdict.json`).
- **Control**: `adaptive-skip-coarse` versus `adaptive-skip-coarse-demand` (relative rank templates). No changed worker/projection budgets, region residency, effect authority, edits, mods, SDF or source membership.

| Route | Definitive regions: control → E4.1 | Mean _process ms/frame | Frames >20ms | Mesh dispatch count |
|---|---:|---:|---:|---:|
| Idle | 9 → 9 | 3.356 → 3.476 | 1.040% → 1.179% | 144 → 144 |
| 18m/s straight | 12.5 → 16 | 5.769 → 6.316 | 3.259% → 4.438% | 324 → 349.5 |
| 54m/s straight | 0 → 0 | 5.650 → 6.132 | 0.486% → 0.902% | 1.5 → 19 |
| 54m/s out-and-back | 0 → 0 | 5.962 → 6.441 | 1.179% → 1.248% | 147.5 → 165.5 |

All rows are two-trial means. The runtime `consumer_demand_scheduler` averaged approximately 0.286ms/frame at 18 and 0.281ms/frame for outback; original E4 was 0.324ms/frame at 18 and 0.317ms/frame for outback (separate same-run controls, not mixed-SHA ABBA). The template optimization saves only ~0.03–0.04ms/frame. More mesh dispatches do not result in any fully authoritative region at 54m/s. At 18, increased definitive LOAD count from 12.5 to 16 is outweighed by process +0.547ms and >20ms frame rate +1.179pp, exceeding both predeclared gates.

**Decision: PERFORMANCE_REJECTED; do not merge.** P4/P5 inherited long regression and GUI qualification not run for a rejected performance candidate. The correct next hypothesis is the *critical source-generation / projection latency* and the all-16-chunk region publication barrier, not another full-queue re-sort or readiness cache. Investigate exact source generation/finalization and projection worker timing, task cancellation/revisit reuse, and possibly revision-gated incremental LOAD chunk publication with edits staying atomic; plan separately before any change.