# P5 E6 — bounded projection concurrency: PERFORMANCE_REJECTED

## Controlled experiment

- Source commit: `579726daeca08a518c7555226d772adb41983dbc`.
- 16 deterministic ABBA cold-world headless Godot 4.7.2 runs, seed 424242, 720 movement frames per trial, same Windows runner, exact code and hardware for both profiles; 2 samples per profile/route.
- Control `adaptive-skip-coarse`: 2 source-generation workers, 2 projection workers, 1 projection publication/frame.
- E6 `adaptive-skip-coarse-pipeline`: **2 source-generation workers unchanged**, 4 projection workers, 2 projection publications/frame. No geometry, mods, edits, object authority, SDF, source halo, world revisions or mesh pipeline changes.
- Qualification (Godot/issue108/P5) passed. [GitHub Actions run #43204424738](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43204424738); original trace artifact `13938061291` with 16 per-trial logs/JSON plus `projection-e6-abba-verdict.json`; qualification artifact `13937196366`.
- Automated verdict: **PERFORMANCE_REJECTED**. Headless workflow success confirms complete evidence, not performance acceptance. P4/P5 extended regression and GUI acceptance deliberately not run for a rejected candidate.

## Results (each cell average of two independent cold starts per profile/route)

| Route | Definitive LOAD completions control→E6 | Mean _process ms/frame control→E6 | >20ms frames % control→E6 | Projection worker p50 ms control→E6 |
|---|---:|---:|---:|---:|
| Idle | 9→9 | 3.110→2.897 | 1.110→1.040 | 60.666→63.735 |
| Straight 18m/s | 15→18.5 | 5.887→6.484 | 3.675→5.894 | 62.980→68.536 |
| Straight 54m/s | 0→0 | 5.597→6.783 | 0.416→1.318 | 59.860→64.319 |
| Out-back 54m/s | 0→1.5 | 6.028→6.669 | 0.624→1.248 | 59.587→65.646 |

- Exact worker in-flight peaks: 2 control, 4 variant.
- Published projection scopes at straight 54m/s: 302/306 control vs 411/412 E6, ~35% more scope publications, **but zero whole definitive regions in both variants**.
- Straight 18m/s produced 19 and 18 definitive LOAD completions under E6 versus 15/15 control, but process main thread +0.597ms/frame and frames >20ms +2.219pp — violates both predeclared +0.5ms and +1pp rejection gates.
- Straight 54m/s process +1.186ms/frame, and zero definitive progress; outback +0.641ms/frame.
- Projection worker p50 *increases* 5–10% with higher concurrency, consistent with contention, despite more jobs completing in a fixed simulation window.

## Technical verdict

Four projection workers and two projection publications improve throughput and modestly increase full LOAD completions at 18m/s and 54m/s out-and-back, but worsen gameplay frame pacing and cannot finish regions at straight 54m/s. **Do not merge**. Maintain E2 coarse-first as reference and `main` unchanged.

The next isolated investigation should model the **region-finalization barrier**: a region requires all 16 chunk results and their effect sources before replacing previews. Explore revision-gated incremental chunk publication for unedited LOAD regions, with atomic edit/full rebuild transactions and safe cancellation/unload, *only after documenting exact publication ownership and seam constraints*. This is an architectural experiment, not an E6 parameter tweak. Verify visible chunk geometry and latency independently of whole-region completion; preserve original authoritative effect snapshots and all mod/brush semantics.
